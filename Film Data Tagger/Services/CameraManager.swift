//
//  CameraManager.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

@preconcurrency import AVFoundation
import UIKit
import ImageIO
import VideoToolbox

enum CameraStatus: Sendable {
    case running
    case stopped
    case unavailable
}

final class CameraManager: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoOutputQueue = DispatchQueue(label: "camera.videoOutput", qos: .userInitiated)
    // Only accessed from sessionQueue — serial queue provides synchronization.
    private var isConfigured = false

    // Frame capture — skip interval computed dynamically from device frame rate
    private static let targetCapturesPerSecond = 5
    private var frameSkip = 6
    // frameCounter is only accessed from videoOutputQueue (serial) — no lock needed
    private var frameCounter = 0
    private var _latestPixelBuffer: CVPixelBuffer?
    private let frameLock = NSLock()

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start(
        deviceType: AVCaptureDevice.DeviceType,
        position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset
    ) async -> CameraStatus {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !self.isConfigured {
                    self.isConfigured = true
                    if !self.configureSession(deviceType: deviceType, position: position, preset: preset) {
                        continuation.resume(returning: .unavailable)
                        return
                    }
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                continuation.resume(returning: self.session.isRunning ? .running : .stopped)
            }
        }
    }

    func stop() {
        frameLock.lock()
        _latestPixelBuffer = nil
        frameLock.unlock()
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func reconfigure(
        deviceType: AVCaptureDevice.DeviceType,
        position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset
    ) {
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

                // Reapply frame rate and recalculate frame skip
                let maxSupported = newDevice.activeFormat.videoSupportedFrameRateRanges
                    .map(\.maxFrameRate).max() ?? 30
                let targetFPS = min(60, maxSupported)
                do {
                    try newDevice.lockForConfiguration()
                    newDevice.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                    newDevice.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
                    newDevice.unlockForConfiguration()
                } catch {
                    debugLog("CameraManager: lockForConfiguration failed in reconfigure: \(error)")
                }
                self.frameLock.lock()
                self.frameSkip = max(1, Int(targetFPS) / Self.targetCapturesPerSecond)
                self.frameLock.unlock()
            } else {
                debugLog("CameraManager: reconfigure failed for requested device")
            }

            self.session.commitConfiguration()

            // Reapply portrait orientation
            if let connection = self.videoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    /// Grab the latest pixel buffer (instant — lock + pointer read). Safe to call on any thread.
    func captureFrame() -> CVPixelBuffer? {
        frameLock.lock()
        let pb = _latestPixelBuffer
        frameLock.unlock()
        return pb
    }

    /// Convert a pixel buffer to a CGImage. Call off-main.
    static func createImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
        return cgImage
    }

    /// Scale a CGImage so its longest edge fits within maxDimension.
    static func scaled(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let w = image.width, h = image.height
        guard CGFloat(max(w, h)) > maxDimension else { return image }

        let scale = maxDimension / CGFloat(max(w, h))
        let newW = Int(CGFloat(w) * scale)
        let newH = Int(CGFloat(h) * scale)

        guard let ctx = CGContext(
            data: nil, width: newW, height: newH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }

    /// Encode a CGImage to HEIC data (JPEG fallback).
    static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        guard let opaque = stripAlpha(image) else {
            debugLog("CameraManager: encode — stripAlpha failed")
            return nil
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else {
            debugLog("CameraManager: encode — HEIC destination failed, falling back to JPEG")
            return UIImage(cgImage: opaque).jpegData(compressionQuality: quality)
        }
        CGImageDestinationAddImage(dest, opaque, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            debugLog("CameraManager: encode — HEIC finalize failed, falling back to JPEG")
            return UIImage(cgImage: opaque).jpegData(compressionQuality: quality)
        }
        return data as Data
    }

    /// Generate a 180×180 square JPEG thumbnail from a CGImage (scale-to-fill + center crop).
    static func generateThumbnail(from image: CGImage, size: Int = 180) -> Data? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }

        // Scale so the short edge == size
        let shortEdge = min(w, h)
        let scale = CGFloat(size) / CGFloat(shortEdge)
        let scaledW = Int(ceil(CGFloat(w) * scale))
        let scaledH = Int(ceil(CGFloat(h) * scale))

        guard let ctx = CGContext(
            data: nil, width: scaledW, height: scaledH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            debugLog("CameraManager: generateThumbnail — scale context failed")
            return nil
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: scaledW, height: scaledH))
        guard let scaled = ctx.makeImage() else {
            debugLog("CameraManager: generateThumbnail — makeImage failed")
            return nil
        }

        // Center crop to square
        let cropRect = if scaledW > scaledH {
            CGRect(x: (scaledW - scaledH) / 2, y: 0, width: scaledH, height: scaledH)
        } else {
            CGRect(x: 0, y: (scaledH - scaledW) / 2, width: scaledW, height: scaledW)
        }
        guard let cropped = scaled.cropping(to: cropRect) else {
            debugLog("CameraManager: generateThumbnail — crop failed")
            return nil
        }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.7)
    }

    // MARK: - Private

    /// Returns true on success, false if camera hardware is unavailable.
    private func configureSession(
        deviceType: AVCaptureDevice.DeviceType,
        position: AVCaptureDevice.Position,
        preset: AVCaptureSession.Preset
    ) -> Bool {
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
            return false
        }

        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            debugLog("CameraManager: could not add input to session")
        }

        // Lock frame rate — prefer 60fps, fall back to device max
        let maxSupported = device.activeFormat.videoSupportedFrameRateRanges
            .map(\.maxFrameRate).max() ?? 30
        let targetFPS = min(60, maxSupported)
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
            device.unlockForConfiguration()
        } catch {
            debugLog("CameraManager: lockForConfiguration failed in configureSession: \(error)")
        }

        // Compute frame skip to hit ~5 captures/sec
        frameLock.lock()
        self.frameSkip = max(1, Int(targetFPS) / Self.targetCapturesPerSecond)
        frameLock.unlock()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            debugLog("CameraManager: could not add video output to session")
        }

        session.commitConfiguration()

        // Set portrait orientation on the video connection
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return true
    }

    /// Re-draw a CGImage without alpha channel.
    private static func stripAlpha(_ image: CGImage) -> CGImage? {
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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCounter += 1
        frameLock.lock()
        let skip = frameSkip
        frameLock.unlock()
        guard frameCounter % skip == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        frameLock.lock()
        _latestPixelBuffer = pixelBuffer
        frameLock.unlock()
    }
}
