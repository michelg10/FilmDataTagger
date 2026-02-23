//
//  AppSettings.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/20/26.
//

import Foundation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: - Setup

    /// Whether the app has been initialized with default data. When false on launch,
    /// the app creates a default camera and roll (or later, shows a setup screen).
    var isInitialized: Bool {
        get { defaults.bool(forKey: Keys.isInitialized) }
        set { defaults.set(newValue, forKey: Keys.isInitialized) }
    }

    // MARK: - Active state

    /// The currently open (viewed) roll ID (regular camera mode).
    var openRollId: UUID? {
        get { uuid(forKey: Keys.openRollId) }
        set { setUUID(newValue, forKey: Keys.openRollId) }
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
            // Default to true if never set
            defaults.object(forKey: Keys.referencePhotosEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.referencePhotosEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.referencePhotosEnabled) }
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
        static let isInitialized = "isInitialized"
        static let openRollId = "openRollId"
        static let activeInstantFilmGroupId = "activeInstantFilmGroupId"
        static let activeInstantFilmCameraId = "activeInstantFilmCameraId"
        static let referencePhotosEnabled = "referencePhotosEnabled"
        static let lastAppLaunchDate = "lastAppLaunchDate"
    }

    private func uuid(forKey key: String) -> UUID? {
        guard let str = defaults.string(forKey: key) else { return nil }
        return UUID(uuidString: str)
    }

    private func setUUID(_ value: UUID?, forKey key: String) {
        defaults.set(value?.uuidString, forKey: key)
    }
}
