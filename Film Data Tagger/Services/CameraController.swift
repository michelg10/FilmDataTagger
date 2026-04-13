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
    private static let doubleTapThreshold: TimeInterval = 0.3

    private let manager = CameraManager()
    private let settings = AppSettings.shared

    private(set) var isRunning = false
    private(set) var permissionDenied = false
    private(set) var unavailable = false
    /// True when reference photos are enabled but camera permission hasn't been requested yet.
    private(set) var needsPermission = false

    /// Incremented on each camera flip. Views observe this to show a temporary indicator.
    private(set) var flipCount = 0

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
        guard referencePhotosEnabled else { return } // toggled off during start
        needsPermission = false
        isRunning = status == .running
        unavailable = status == .unavailable
    }

    /// Start the camera session if reference photos are enabled and permission is already granted.
    /// Call on exposure screen appear. Does NOT prompt for permission — use `requestPermissionIfNeeded()` for that.
    func ensureRunning() {
        stopTimer?.cancel()
        stopTimer = nil
        guard referencePhotosEnabled else { return }
        Task(priority: .userInitiated) {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                needsPermission = false
                await startCamera()
            case .notDetermined:
                needsPermission = true
            case .denied, .restricted:
                needsPermission = false
                permissionDenied = true
            @unknown default:
                break
            }
        }
    }

    /// Request camera permission. Call when the user taps the reference photo preview to set up.
    func requestPermissionIfNeeded() {
        guard referencePhotosEnabled else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        needsPermission = false
        Task(priority: .userInitiated) {
            let granted = await CameraManager.requestPermission()
            guard referencePhotosEnabled else { return } // may have been disabled during await
            permissionDenied = !granted
            if granted {
                await startCamera()
            } else {
                referencePhotosEnabled = false
            }
        }
    }

    /// Re-check camera authorization after returning from Settings or foreground.
    /// Recovers from a previous denial if the user granted access in Settings.
    func recheckPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            if permissionDenied {
                permissionDenied = false
                needsPermission = false
                // Re-enable reference photos — the user went to Settings to fix this
                referencePhotosEnabled = true
                Task(priority: .userInitiated) { await startCamera() }
            }
        case .notDetermined:
            if referencePhotosEnabled {
                needsPermission = true
            }
        case .denied, .restricted:
            permissionDenied = true
            needsPermission = false
        @unknown default:
            break
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

    /// Timestamp of the last time reference photos were toggled off, for double-tap detection.
    private var lastToggleOffDate: Date?

    func toggle() {
        if !referencePhotosEnabled {
            // Double-tap detection: if toggled back on within 300ms and the
            // device has both front + back cameras, flip the camera side.
            var didFlip = false
            if let lastOff = lastToggleOffDate {
                let ms = Date().timeIntervalSince(lastOff) * 1000
                let canFlip = settings.deviceCanFlipCamera && settings.doubleTapToFlipCamera
                if ms < Self.doubleTapThreshold * 1000, canFlip {
                    settings.preferredCameraSide = settings.preferredCameraSide.toggled
                    reconfigure()
                    didFlip = true
                }
            }
            lastToggleOffDate = nil
            playHaptic(didFlip ? .cameraFlip : .viewfinderToggle)
            if didFlip { flipCount += 1 }
            // Turning on — check permission first
            needsPermission = false
            referencePhotosEnabled = true // set eagerly so ensureRunning() doesn't bail
            Task(priority: .userInitiated) {
                let granted = await CameraManager.requestPermission()
                guard referencePhotosEnabled else { return } // toggled off during await
                permissionDenied = !granted
                if granted {
                    await startCamera()
                } else {
                    referencePhotosEnabled = false
                }
                // If denied, iOS won't re-prompt — user must go to Settings.
            }
        } else {
            playHaptic(.viewfinderToggle)
            lastToggleOffDate = Date()
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
