//
//  AppSettings.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation
import CoreLocation

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
        case .low: "Low (360p)"
        case .medium: "Medium (720p)"
        case .high: "High (1440p)"
        case .maximum: "Maximum"
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

    var clAccuracy: CLLocationAccuracy {
        switch self {
        case .low: kCLLocationAccuracyKilometer
        case .medium: kCLLocationAccuracyHundredMeters
        case .high: kCLLocationAccuracyNearestTenMeters
        case .maximum: kCLLocationAccuracyBest
        }
    }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Active state

    /// The currently open (viewed) roll ID (regular camera mode).
    var openRollId: UUID? {
        get { uuid(forKey: Keys.openRollId) }
        set { setUUID(newValue, forKey: Keys.openRollId) }
    }

    /// The currently selected camera ID (used when no roll is open).
    var openCameraId: UUID? {
        get { uuid(forKey: Keys.openCameraId) }
        set { setUUID(newValue, forKey: Keys.openCameraId) }
    }

    /// The currently active instant film group ID.
    var activeInstantFilmGroupId: UUID? {
        get { uuid(forKey: Keys.activeInstantFilmGroupId) }
        set { setUUID(newValue, forKey: Keys.activeInstantFilmGroupId) }
    }

    /// The currently active instant film camera ID.
    var activeInstantFilmCameraId: UUID? {
        get { uuid(forKey: Keys.activeInstantFilmCameraId) }
        set { setUUID(newValue, forKey: Keys.activeInstantFilmCameraId) }
    }

    // MARK: - Preferences

    /// Whether reference photos are captured with each exposure.
    var referencePhotosEnabled: Bool {
        get {
            defaults.object(forKey: Keys.referencePhotosEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.referencePhotosEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.referencePhotosEnabled) }
    }

    var referencePhotoStartup: ReferencePhotoStartup {
        get { enumValue(forKey: Keys.referencePhotoStartup) ?? .preserveLast }
        set { defaults.set(newValue.rawValue, forKey: Keys.referencePhotoStartup) }
    }

    var photoQuality: PhotoQuality {
        get { enumValue(forKey: Keys.photoQuality) ?? .high }
        set { defaults.set(newValue.rawValue, forKey: Keys.photoQuality) }
    }

    var preferredCamera: PreferredCamera {
        get { enumValue(forKey: Keys.preferredCamera) ?? .ultraWide }
        set { defaults.set(newValue.rawValue, forKey: Keys.preferredCamera) }
    }

    var locationEnabled: Bool {
        get {
            defaults.object(forKey: Keys.locationEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.locationEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.locationEnabled) }
    }

    var locationAccuracy: LocationAccuracy {
        get { enumValue(forKey: Keys.locationAccuracy) ?? .high }
        set { defaults.set(newValue.rawValue, forKey: Keys.locationAccuracy) }
    }

    var reduceHaptics: Bool {
        get { defaults.bool(forKey: Keys.reduceHaptics) }
        set { defaults.set(newValue, forKey: Keys.reduceHaptics) }
    }

    /// The last time the app was launched (used for geocoding cutoff).
    var lastAppLaunchDate: Date? {
        get { defaults.object(forKey: Keys.lastAppLaunchDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastAppLaunchDate) }
    }

    // MARK: - Private

    private let defaults = UserDefaults.standard

    private init() {}

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
    }

    private func uuid(forKey key: String) -> UUID? {
        guard let str = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: str)
    }

    private func setUUID(_ value: UUID?, forKey key: String) {
        defaults.set(value?.uuidString, forKey: key)
    }

    private func enumValue<T: RawRepresentable>(forKey key: String) -> T? where T.RawValue == String {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}
