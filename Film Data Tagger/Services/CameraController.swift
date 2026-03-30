//
//  CameraController.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/29/26.
//

@preconcurrency import AVFoundation
import UIKit

/// Observable bridge between the camera service and the UI.
/// Owns all camera UI state, the preview view, and screen-lifecycle policy.
@Observable @MainActor
final class CameraController {
    private let manager = CameraManager()
    private let settings = AppSettings.shared

    private(set) var isRunning = false
    private(set) var permissionDenied = false
    private(set) var unavailable = false

    var referencePhotosEnabled: Bool {
        didSet { settings.referencePhotosEnabled = referencePhotosEnabled }
    }

    private var stopTimer: Task<Void, Never>?
    private var _previewView: CameraPreviewUIView?

    /// Persistent preview view. Created once, reused across navigation.
    var previewView: CameraPreviewUIView {
        if let existing = _previewView { return existing }
        let view = CameraPreviewUIView()
        view.previewLayer.session = manager.session
        view.previewLayer.videoGravity = .resizeAspectFill
        _previewView = view
        return view
    }

    init() {
        self.referencePhotosEnabled = AppSettings.shared.referencePhotosEnabled
    }

    /// Apply the startup setting for reference photos.
    func setup() {
        switch settings.referencePhotoStartup {
            case .preserveLast: break
            case .on: referencePhotosEnabled = true
            case .off: referencePhotosEnabled = false
        }
    }

    // MARK: - Session lifecycle

    private func config() -> (AVCaptureDevice.DeviceType, AVCaptureDevice.Position, AVCaptureSession.Preset) {
        let camera = settings.preferredCamera
        return (camera.deviceType, camera.position, settings.photoQuality.sessionPreset)
    }

    private func startCamera() async {
        let (deviceType, position, preset) = config()
        let status = await manager.start(deviceType: deviceType, position: position, preset: preset)
        isRunning = status == .running
        unavailable = status == .unavailable
    }

    /// Start the camera session if reference photos are enabled. Call on exposure screen appear.
    func ensureRunning() {
        stopTimer?.cancel()
        stopTimer = nil
        guard referencePhotosEnabled else { return }
        Task(priority: .userInitiated) {
            let granted = await CameraManager.requestPermission()
            permissionDenied = !granted
            if granted {
                await startCamera()
            } else {
                referencePhotosEnabled = false
            }
        }
    }

    /// Schedule camera stop after a delay. Call on exposure screen disappear.
    func scheduleStop(after seconds: TimeInterval = 30) {
        stopTimer?.cancel()
        stopTimer = Task(priority: .utility) {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            manager.stop()
            isRunning = false
        }
    }

    func toggle() {
        if !referencePhotosEnabled {
            // Turning on — check permission first
            Task(priority: .userInitiated) {
                let granted = await CameraManager.requestPermission()
                permissionDenied = !granted
                if granted {
                    referencePhotosEnabled = true
                    await startCamera()
                }
                // If denied, iOS won't re-prompt — user must go to Settings.
            }
        } else {
            referencePhotosEnabled = false
            manager.stop()
            isRunning = false
        }
    }

    func reconfigure() {
        let (deviceType, position, preset) = config()
        manager.reconfigure(deviceType: deviceType, position: position, preset: preset)
    }

    // MARK: - Frame capture

    /// Grab the latest pixel buffer if reference photos are enabled and the camera is running.
    func captureFrame() -> CVPixelBuffer? {
        guard referencePhotosEnabled, isRunning else { return nil }
        return manager.captureFrame()
    }
}
