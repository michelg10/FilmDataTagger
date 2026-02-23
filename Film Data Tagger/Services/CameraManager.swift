//
//  CameraManager.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

@preconcurrency import AVFoundation
import UIKit

@Observable @MainActor
final class CameraManager: NSObject {
    // nonisolated so the session and output can be used from sessionQueue
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<Data?, Never>?
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
        sessionQueue.async {
            if !self.isConfigured {
                self.isConfigured = true
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let running = self.session.isRunning
            Task { @MainActor in self.isRunning = running }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in self.isRunning = false }
        }
    }

    private nonisolated func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Prefer ultra-wide, fall back to wide, then default
        let device: AVCaptureDevice? =
            AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
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

    func capturePhoto() async -> Data? {
        guard session.isRunning, output.connection(with: .video)?.isActive == true else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed

            self.output.capturePhoto(with: settings, delegate: self)
        }
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
