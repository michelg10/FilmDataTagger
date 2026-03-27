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

    /// Minimum distance (meters) before re-geocoding the user's location
    var geocodeDistanceThreshold: CLLocationDistance {
        switch self {
        case .low: 500
        case .medium: 100
        case .high: 20
        case .maximum: 5
        }
    }

    /// How long a cached location remains valid for shortcut use
    nonisolated var locationCacheTTL: TimeInterval {
        switch self {
        case .low: 600      // 10 minutes
        case .medium: 60    // 1 minute
        case .high: 30      // 30 seconds
        case .maximum: 10   // 10 seconds
        }
    }
}

@Observable @MainActor
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Active state

    var openRollId: UUID? {
        didSet { defaults.set(openRollId?.uuidString, forKey: AppSettingsKeys.openRollId) }
    }

    var openCameraId: UUID? {
        didSet { defaults.set(openCameraId?.uuidString, forKey: AppSettingsKeys.openCameraId) }
    }

    var activeInstantFilmGroupId: UUID? {
        didSet { defaults.set(activeInstantFilmGroupId?.uuidString, forKey: AppSettingsKeys.activeInstantFilmGroupId) }
    }

    var activeInstantFilmCameraId: UUID? {
        didSet { defaults.set(activeInstantFilmCameraId?.uuidString, forKey: AppSettingsKeys.activeInstantFilmCameraId) }
    }

    // MARK: - Preferences

    var referencePhotosEnabled: Bool {
        didSet { defaults.set(referencePhotosEnabled, forKey: AppSettingsKeys.referencePhotosEnabled) }
    }

    var referencePhotoStartup: ReferencePhotoStartup {
        didSet { defaults.set(referencePhotoStartup.rawValue, forKey: AppSettingsKeys.referencePhotoStartup) }
    }

    var photoQuality: PhotoQuality {
        didSet { defaults.set(photoQuality.rawValue, forKey: AppSettingsKeys.photoQuality) }
    }

    var preferredCamera: PreferredCamera {
        didSet { defaults.set(preferredCamera.rawValue, forKey: AppSettingsKeys.preferredCamera) }
    }

    var locationEnabled: Bool {
        didSet { defaults.set(locationEnabled, forKey: AppSettingsKeys.locationEnabled) }
    }

    var locationAccuracy: LocationAccuracy {
        didSet { defaults.set(locationAccuracy.rawValue, forKey: AppSettingsKeys.locationAccuracy) }
    }

    var reduceHaptics: Bool {
        didSet { defaults.set(reduceHaptics, forKey: AppSettingsKeys.reduceHaptics) }
    }

    var lastAppLaunchDate: Date? {
        didSet { defaults.set(lastAppLaunchDate, forKey: AppSettingsKeys.lastAppLaunchDate) }
    }

    var lastForegroundDate: Date? {
        didSet { defaults.set(lastForegroundDate, forKey: AppSettingsKeys.lastForegroundDate) }
    }

    var lastDataCleanDate: Date? {
        didSet { defaults.set(lastDataCleanDate, forKey: AppSettingsKeys.lastDataCleanDate) }
    }

    // MARK: - Location cache (for accelerating consecutive Shortcut triggers)

    /// Returns a cached location if one exists within the TTL for the current accuracy setting, otherwise nil.
    nonisolated func shortcutCachedLocation() -> CLLocation? {
        let d = UserDefaults.standard
        guard let lat = d.object(forKey: AppSettingsKeys.shortcutCachedLocationLat) as? Double,
              let lon = d.object(forKey: AppSettingsKeys.shortcutCachedLocationLon) as? Double,
              let timestamp = d.object(forKey: AppSettingsKeys.shortcutCachedLocationTimestamp) as? Date else { return nil }
        let accuracy = d.string(forKey: AppSettingsKeys.locationAccuracy)
            .flatMap(LocationAccuracy.init) ?? .high
        guard Date().timeIntervalSince(timestamp) <= accuracy.locationCacheTTL else { return nil }
        let alt = d.object(forKey: AppSettingsKeys.shortcutCachedLocationAlt) as? Double ?? 0
        let hAcc = d.object(forKey: AppSettingsKeys.shortcutCachedLocationHAcc) as? Double ?? -1
        let vAcc = d.object(forKey: AppSettingsKeys.shortcutCachedLocationVAcc) as? Double ?? -1
        let course = d.object(forKey: AppSettingsKeys.shortcutCachedLocationCourse) as? Double ?? -1
        let speed = d.object(forKey: AppSettingsKeys.shortcutCachedLocationSpeed) as? Double ?? -1
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: alt,
            horizontalAccuracy: hAcc,
            verticalAccuracy: vAcc,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }

    /// Persist a location for use by subsequent Shortcut invocations.
    nonisolated func cacheShortcutLocation(_ location: CLLocation) {
        let d = UserDefaults.standard
        d.set(location.coordinate.latitude, forKey: AppSettingsKeys.shortcutCachedLocationLat)
        d.set(location.coordinate.longitude, forKey: AppSettingsKeys.shortcutCachedLocationLon)
        d.set(location.altitude, forKey: AppSettingsKeys.shortcutCachedLocationAlt)
        d.set(location.horizontalAccuracy, forKey: AppSettingsKeys.shortcutCachedLocationHAcc)
        d.set(location.verticalAccuracy, forKey: AppSettingsKeys.shortcutCachedLocationVAcc)
        d.set(location.course, forKey: AppSettingsKeys.shortcutCachedLocationCourse)
        d.set(location.speed, forKey: AppSettingsKeys.shortcutCachedLocationSpeed)
        d.set(location.timestamp, forKey: AppSettingsKeys.shortcutCachedLocationTimestamp)
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private init() {
        let d = UserDefaults.standard

        openRollId = d.string(forKey: AppSettingsKeys.openRollId).flatMap(UUID.init)
        openCameraId = d.string(forKey: AppSettingsKeys.openCameraId).flatMap(UUID.init)
        activeInstantFilmGroupId = d.string(forKey: AppSettingsKeys.activeInstantFilmGroupId).flatMap(UUID.init)
        activeInstantFilmCameraId = d.string(forKey: AppSettingsKeys.activeInstantFilmCameraId).flatMap(UUID.init)

        referencePhotosEnabled = d.object(forKey: AppSettingsKeys.referencePhotosEnabled) == nil
            ? true : d.bool(forKey: AppSettingsKeys.referencePhotosEnabled)
        referencePhotoStartup = d.string(forKey: AppSettingsKeys.referencePhotoStartup)
            .flatMap(ReferencePhotoStartup.init) ?? .preserveLast
        photoQuality = d.string(forKey: AppSettingsKeys.photoQuality)
            .flatMap(PhotoQuality.init) ?? .high
        let savedCamera = d.string(forKey: AppSettingsKeys.preferredCamera).flatMap(PreferredCamera.init)
        let available = PreferredCamera.available
        preferredCamera = if let savedCamera, available.contains(savedCamera) {
            savedCamera
        } else if available.contains(.ultraWide) {
            .ultraWide
        } else {
            available.first ?? .wide
        }
        locationEnabled = d.object(forKey: AppSettingsKeys.locationEnabled) == nil
            ? true : d.bool(forKey: AppSettingsKeys.locationEnabled)
        locationAccuracy = d.string(forKey: AppSettingsKeys.locationAccuracy)
            .flatMap(LocationAccuracy.init) ?? .high
        reduceHaptics = d.bool(forKey: AppSettingsKeys.reduceHaptics)
        lastAppLaunchDate = d.object(forKey: AppSettingsKeys.lastAppLaunchDate) as? Date
        lastForegroundDate = d.object(forKey: AppSettingsKeys.lastForegroundDate) as? Date
        lastDataCleanDate = d.object(forKey: AppSettingsKeys.lastDataCleanDate) as? Date
    }

}

nonisolated enum AppSettingsKeys {
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
    static let lastDataCleanDate = "lastDataCleanDate"
    static let shortcutCachedLocationLat = "shortcutCachedLocationLat"
    static let shortcutCachedLocationLon = "shortcutCachedLocationLon"
    static let shortcutCachedLocationAlt = "shortcutCachedLocationAlt"
    static let shortcutCachedLocationHAcc = "shortcutCachedLocationHAcc"
    static let shortcutCachedLocationVAcc = "shortcutCachedLocationVAcc"
    static let shortcutCachedLocationCourse = "shortcutCachedLocationCourse"
    static let shortcutCachedLocationSpeed = "shortcutCachedLocationSpeed"
    static let shortcutCachedLocationTimestamp = "shortcutCachedLocationTimestamp"
    static let pendingOrphanRollIDs = "pendingOrphanRollIDs"
    static let pendingOrphanItemIDs = "pendingOrphanItemIDs"
}
