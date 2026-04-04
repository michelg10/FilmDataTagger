//
//  AppInstallTracker.swift
//  Film Data Tagger
//

import Foundation

/// Tracks the first-ever app open across all of the user's devices via iCloud KVS.
/// Each device gets a stable UUID and records its own first-open date into a shared map.
actor AppInstallTracker {
    static let shared = AppInstallTracker()

    private static let deviceIDKey = "deviceUUID"
    private static let firstOpenMapKey = "firstOpenDates"

    /// This device's stable identifier.
    nonisolated let deviceID: String

    /// This device's first-open date.
    nonisolated let thisDeviceFirstOpened: Date

    /// The earliest first-open date across all of the user's devices.
    nonisolated let firstEverOpened: Date

    private init() {
        let local = UserDefaults.standard
        let cloud = NSUbiquitousKeyValueStore.default
        cloud.synchronize()

        // Get or create this device's UUID
        if let existing = local.string(forKey: Self.deviceIDKey) {
            deviceID = existing
        } else {
            let id = UUID().uuidString
            local.set(id, forKey: Self.deviceIDKey)
            deviceID = id
        }

        // Get the existing map from iCloud KVS
        var map = cloud.dictionary(forKey: Self.firstOpenMapKey) as? [String: Double] ?? [:]

        // Record this device if not already present
        if let existing = map[deviceID] {
            thisDeviceFirstOpened = Date(timeIntervalSince1970: existing)
        } else {
            let now = Date()
            map[deviceID] = now.timeIntervalSince1970
            thisDeviceFirstOpened = now
            cloud.set(map, forKey: Self.firstOpenMapKey)
        }

        // Earliest across all devices
        if let earliest = map.values.min() {
            firstEverOpened = Date(timeIntervalSince1970: earliest)
        } else {
            firstEverOpened = thisDeviceFirstOpened
        }
    }
}
