//
//  AppSettings.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation
import CoreLocation
import AVFoundation

// MARK: - Settings Enums

enum ReferencePhotoStartup: String, CaseIterable {
    case preserveLast
    case on
    case off

    var label: String {
        switch self {
        case .preserveLast: "Preserve last setting"
        case .on: "On"
        case .off: "Off"
        }
    }
}

enum PhotoQuality: String, CaseIterable {
    case low
    case medium
    case high
    case maximum

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High (Recommended)"
        case .maximum: "Maximum"
        }
    }

    var caption: String {
        switch self {
        case .low: "Capture reference photos up to 360p. Lower quality may improve performance and reduce storage use."
        case .medium: "Capture reference photos up to 720p. Lower quality may improve performance and reduce storage use."
        case .high: "Capture reference photos up to 1440p. Higher quality may reduce performance and increase storage use."
        case .maximum: "Capture reference photos at the highest available quality. This may reduce performance and significantly increase storage use."
        }
    }

    /// Maximum dimension (width or height) for the resized photo.
    var maxDimension: CGFloat? {
        switch self {
        case .low: 360
        case .medium: 720
        case .high: 1440
        case .maximum: nil
        }
    }

    var compressionQuality: CGFloat {
        switch self {
        case .low: 0.6
        case .medium: 0.7
        case .high: 0.85
        case .maximum: 0.95 // Not used; native HEIF output is stored as-is
        }
    }

    /// Session preset matching the quality level.
    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .low: .vga640x480
        case .medium: .hd1280x720
        case .high, .maximum: .photo
        }
    }
}

enum PreferredCamera: String, CaseIterable {
    case ultraWide
    case wide
    case telephoto
    case front

    var label: String {
        switch self {
        case .ultraWide: "Ultra-wide"
        case .wide: "Wide"
        case .telephoto: "Telephoto"
        case .front: "Front"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: .builtInUltraWideCamera
        case .wide: .builtInWideAngleCamera
        case .telephoto: .builtInTelephotoCamera
        case .front: .builtInWideAngleCamera
        }
    }

    var position: AVCaptureDevice.Position {
        self == .front ? .front : .back
    }

    static var available: [PreferredCamera] {
        allCases.filter {
            AVCaptureDevice.default($0.deviceType, for: .video, position: $0.position) != nil
        }
    }
}

enum LocationAccuracy: String, CaseIterable {
    case low
    case medium
    case high
    case maximum

    var label: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High (recommended)"
        case .maximum: "Maximum"
        }
    }

    var caption: String {
        switch self {
        case .low: "Record location at up to 1000 meter accuracy. Lower accuracy may improve battery life."
        case .medium: "Record location at up to 100 meter accuracy. Lower accuracy may improve battery life."
        case .high: "Record location at up to 10 meter accuracy. Higher accuracy may reduce battery life."
        case .maximum: "Record location at the highest possible accuracy. This may significantly reduce battery life."
        }
    }

    var clAccuracy: CLLocationAccuracy {
        switch self {
        case .low: kCLLocationAccuracyKilometer
        case .medium: kCLLocationAccuracyHundredMeters
        case .high: kCLLocationAccuracyNearestTenMeters
        case .maximum: kCLLocationAccuracyBest
        }
    }
}

@Observable @MainActor
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Active state

    var openRollId: UUID? {
        didSet { defaults.set(openRollId?.uuidString, forKey: Keys.openRollId) }
    }

    var openCameraId: UUID? {
        didSet { defaults.set(openCameraId?.uuidString, forKey: Keys.openCameraId) }
    }

    var activeInstantFilmGroupId: UUID? {
        didSet { defaults.set(activeInstantFilmGroupId?.uuidString, forKey: Keys.activeInstantFilmGroupId) }
    }

    var activeInstantFilmCameraId: UUID? {
        didSet { defaults.set(activeInstantFilmCameraId?.uuidString, forKey: Keys.activeInstantFilmCameraId) }
    }

    // MARK: - Preferences

    var referencePhotosEnabled: Bool {
        didSet { defaults.set(referencePhotosEnabled, forKey: Keys.referencePhotosEnabled) }
    }

    var referencePhotoStartup: ReferencePhotoStartup {
        didSet { defaults.set(referencePhotoStartup.rawValue, forKey: Keys.referencePhotoStartup) }
    }

    var photoQuality: PhotoQuality {
        didSet { defaults.set(photoQuality.rawValue, forKey: Keys.photoQuality) }
    }

    var preferredCamera: PreferredCamera {
        didSet { defaults.set(preferredCamera.rawValue, forKey: Keys.preferredCamera) }
    }

    var locationEnabled: Bool {
        didSet { defaults.set(locationEnabled, forKey: Keys.locationEnabled) }
    }

    var locationAccuracy: LocationAccuracy {
        didSet { defaults.set(locationAccuracy.rawValue, forKey: Keys.locationAccuracy) }
    }

    var reduceHaptics: Bool {
        didSet { defaults.set(reduceHaptics, forKey: Keys.reduceHaptics) }
    }

    var lastAppLaunchDate: Date? {
        didSet { defaults.set(lastAppLaunchDate, forKey: Keys.lastAppLaunchDate) }
    }

    var lastForegroundDate: Date? {
        didSet { defaults.set(lastForegroundDate, forKey: Keys.lastForegroundDate) }
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard

        openRollId = d.string(forKey: Keys.openRollId).flatMap(UUID.init)
        openCameraId = d.string(forKey: Keys.openCameraId).flatMap(UUID.init)
        activeInstantFilmGroupId = d.string(forKey: Keys.activeInstantFilmGroupId).flatMap(UUID.init)
        activeInstantFilmCameraId = d.string(forKey: Keys.activeInstantFilmCameraId).flatMap(UUID.init)

        referencePhotosEnabled = d.object(forKey: Keys.referencePhotosEnabled) == nil
            ? true : d.bool(forKey: Keys.referencePhotosEnabled)
        referencePhotoStartup = d.string(forKey: Keys.referencePhotoStartup)
            .flatMap(ReferencePhotoStartup.init) ?? .preserveLast
        photoQuality = d.string(forKey: Keys.photoQuality)
            .flatMap(PhotoQuality.init) ?? .high
        let savedCamera = d.string(forKey: Keys.preferredCamera).flatMap(PreferredCamera.init)
        let available = PreferredCamera.available
        preferredCamera = if let savedCamera, available.contains(savedCamera) {
            savedCamera
        } else if available.contains(.ultraWide) {
            .ultraWide
        } else {
            available.first ?? .wide
        }
        locationEnabled = d.object(forKey: Keys.locationEnabled) == nil
            ? true : d.bool(forKey: Keys.locationEnabled)
        locationAccuracy = d.string(forKey: Keys.locationAccuracy)
            .flatMap(LocationAccuracy.init) ?? .high
        reduceHaptics = d.bool(forKey: Keys.reduceHaptics)
        lastAppLaunchDate = d.object(forKey: Keys.lastAppLaunchDate) as? Date
        lastForegroundDate = d.object(forKey: Keys.lastForegroundDate) as? Date
    }

    private enum Keys {
        static let openRollId = "openRollId"
        static let openCameraId = "openCameraId"
        static let activeInstantFilmGroupId = "activeInstantFilmGroupId"
        static let activeInstantFilmCameraId = "activeInstantFilmCameraId"
        static let referencePhotosEnabled = "referencePhotosEnabled"
        static let referencePhotoStartup = "referencePhotoStartup"
        static let photoQuality = "photoQuality"
        static let preferredCamera = "preferredCamera"
        static let locationEnabled = "locationEnabled"
        static let locationAccuracy = "locationAccuracy"
        static let reduceHaptics = "reduceHaptics"
        static let lastAppLaunchDate = "lastAppLaunchDate"
        static let lastForegroundDate = "lastForegroundDate"
    }
}
