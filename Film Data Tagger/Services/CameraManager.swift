//
//  CameraManager.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

@preconcurrency import AVFoundation
import UIKit
import ImageIO

@Observable @MainActor
final class CameraManager: NSObject {
    // nonisolated so the session and output can be used from sessionQueue
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    // Only accessed from sessionQueue — serial queue provides synchronization.
    nonisolated(unsafe) private var isConfigured = false
    private var photoContinuation: CheckedContinuation<Data?, Never>?
    private var isCaptureInFlight = false
    private var captureGeneration = 0
    private var stopTimer: Task<Void, Never>?
    private var _previewView: CameraPreviewUIView?

    /// Persistent preview view. Created once, reused across navigation.
    var previewView: CameraPreviewUIView {
        if let existing = _previewView { return existing }
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        _previewView = view
        return view
    }

    var isRunning = false
    var permissionDenied = false
    var cameraUnavailable = false

    /// Request camera permission. Returns true if granted, false if denied.
    @discardableResult
    func requestPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        permissionDenied = !granted
        return granted
    }

    func start() {
        stopTimer?.cancel()
        stopTimer = nil
        let camera = AppSettings.shared.preferredCamera
        let deviceType = camera.deviceType
        let position = camera.position
        let preset = AppSettings.shared.photoQuality.sessionPreset
        sessionQueue.async {
            if !self.isConfigured {
                self.isConfigured = true
                self.configureSession(deviceType: deviceType, position: position, preset: preset)
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor in self.isRunning = running }
        }
    }

    func stop() {
        stopTimer?.cancel()
        stopTimer = nil
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in self.isRunning = false }
        }
    }

    /// Schedule a stop after a delay. Cancelled if `start()` or `stop()` is called first.
    func scheduleStop(after seconds: TimeInterval = 30) {
        stopTimer?.cancel()
        stopTimer = Task(priority: .utility) {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            stop()
        }
    }

    private nonisolated func configureSession(
        deviceType: AVCaptureDevice.DeviceType,
        position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset
    ) {
        session.beginConfiguration()
        session.sessionPreset = preset

        let device: AVCaptureDevice? =
            AVCaptureDevice.default(deviceType, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            self.isConfigured = false
            debugLog("CameraManager: configureSession failed — no camera device available")
            Task { @MainActor in self.cameraUnavailable = true }
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            debugLog("CameraManager: could not add input to session")
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            debugLog("CameraManager: could not add output to session")
        }

        session.commitConfiguration()
    }

    /// Re-read preferred camera and quality from AppSettings and reconfigure the session.
    func reconfigure() {
        let camera = AppSettings.shared.preferredCamera
        let deviceType = camera.deviceType
        let position = camera.position
        let preset = AppSettings.shared.photoQuality.sessionPreset
        sessionQueue.async {
            guard self.isConfigured else { return }

            self.session.beginConfiguration()

            // Update preset
            if self.session.canSetSessionPreset(preset) {
                self.session.sessionPreset = preset
            }

            // Swap camera input
            let newDevice =
                AVCaptureDevice.default(deviceType, for: .video, position: position)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)

            if let newDevice, let newInput = try? AVCaptureDeviceInput(device: newDevice) {
                // Remove existing input
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                }
            } else {
                debugLog("CameraManager: reconfigure failed for requested device")
            }

            self.session.commitConfiguration()
        }
    }

    /// Capture a photo and return the image data (or nil on failure/timeout).
    ///
    /// Three code paths can resume `photoContinuation`: `didFinishProcessingPhoto`,
    /// `didFinishCaptureFor` (Apple's terminal callback), and a 5-second safety timeout.
    /// This is safe because all three dispatch via `Task { @MainActor in }`, which
    /// serializes on the main actor — whichever runs first nils out the continuation,
    /// and the others no-op via optional chaining (`?.resume`).
    func capturePhoto() async -> Data? {
        guard isRunning else { return nil }
        // Only one capture at a time — flag set before the await so reentrancy can't sneak in
        guard !isCaptureInFlight else { return nil }
        isCaptureInFlight = true
        captureGeneration &+= 1
        let generation = captureGeneration

        let data: Data? = await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            // All AVCapturePhotoOutput access must happen on the session queue
            self.sessionQueue.async {
                let photoSettings: AVCapturePhotoSettings
                if self.output.availablePhotoCodecTypes.contains(.hevc) {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    photoSettings = AVCapturePhotoSettings()
                }
                photoSettings.photoQualityPrioritization = .speed
                self.output.capturePhoto(with: photoSettings, delegate: self)
            }

            // Safety timeout — if neither delegate callback resumes the continuation, unblock after 5s
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard self.captureGeneration == generation else { return }
                if self.photoContinuation != nil {
                    debugLog("CameraManager: photo capture timed out after 5s")
                }
                self.photoContinuation?.resume(returning: nil)
                self.photoContinuation = nil
            }
        }

        isCaptureInFlight = false
        return data
    }

    nonisolated static func resized(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else {
            debugLog("CameraManager: resize failed — could not create thumbnail, returning full-size data")
            return data
        }

        guard let opaqueImage = stripAlpha(thumbnail) else {
            debugLog("CameraManager: resize failed — could not strip alpha, returning full-size data")
            return data
        }

        let heifData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(heifData, "public.heic" as CFString, 1, nil) else {
            debugLog("CameraManager: resize failed — could not create HEIC destination, returning full-size data")
            return data
        }
        CGImageDestinationAddImage(dest, opaqueImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return heifData as Data
    }

    /// Generate a 180×180 square JPEG thumbnail (scale-to-fill + center crop).
    nonisolated static func generateThumbnail(from data: Data, size: Int = 180) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let fullW = properties[kCGImagePropertyPixelWidth] as? Int,
              let fullH = properties[kCGImagePropertyPixelHeight] as? Int,
              fullW > 0, fullH > 0 else {
            debugLog("CameraManager: generateThumbnail failed — could not read image source or properties")
            return nil
        }

        // Decode so the short edge == size (scale-to-fill)
        let shortEdge = min(fullW, fullH)
        let longEdge = max(fullW, fullH)
        let maxPixelSize = Int(ceil(Double(longEdge) * Double(size) / Double(shortEdge)))

        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else {
            debugLog("CameraManager: generateThumbnail failed — could not decode thumbnail at index")
            return nil
        }

        // Center crop to square
        let w = decoded.width, h = decoded.height
        let cropRect = if w > h {
            CGRect(x: (w - h) / 2, y: 0, width: h, height: h)
        } else {
            CGRect(x: 0, y: (h - w) / 2, width: w, height: w)
        }
        guard let cropped = decoded.cropping(to: cropRect),
              let opaque = stripAlpha(cropped) else {
            debugLog("CameraManager: generateThumbnail failed — crop or strip alpha failed")
            return nil
        }
        return UIImage(cgImage: opaque).jpegData(compressionQuality: 0.7)
    }

    /// Re-draw a CGImage without alpha channel.
    nonisolated private static func stripAlpha(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            debugLog("CameraManager: photoOutput error: \(error.localizedDescription)")
        }
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.photoContinuation?.resume(returning: data)
            self.photoContinuation = nil
        }
    }

    /// Terminal callback — guaranteed to fire for every capture request.
    /// Safety net: if didFinishProcessingPhoto never fired, resume with nil.
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        if let error {
            debugLog("CameraManager: didFinishCapture error: \(error.localizedDescription)")
        }
        Task { @MainActor in
            self.photoContinuation?.resume(returning: nil)
            self.photoContinuation = nil
        }
    }
}
