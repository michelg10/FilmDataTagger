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
        stopTimer = Task {
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
            Task { @MainActor in self.cameraUnavailable = true }
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(output) {
            session.addOutput(output)
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
            }

            self.session.commitConfiguration()
        }
    }

    func capturePhoto(maxDimension: CGFloat? = nil, compressionQuality: CGFloat = 0.8) async -> Data? {
        guard session.isRunning, output.connection(with: .video)?.isActive == true else {
            return nil
        }

        let data: Data? = await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let photoSettings: AVCapturePhotoSettings
            if self.output.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                photoSettings = AVCapturePhotoSettings()
            }
            photoSettings.photoQualityPrioritization = .speed

            self.output.capturePhoto(with: photoSettings, delegate: self)
        }

        guard let data, let maxDimension else { return data }
        return Self.resized(data, maxDimension: maxDimension, quality: compressionQuality)
    }

    private static func resized(_ data: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        guard scale < 1.0 else { return data }
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        guard let cgImage = resizedImage.cgImage else { return data }
        let heifData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(heifData, "public.heic" as CFString, 1, nil) else { return data }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return heifData as Data
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.photoContinuation?.resume(returning: data)
            self.photoContinuation = nil
        }
    }
}
