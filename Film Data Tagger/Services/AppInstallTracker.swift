//
//  AppInstallTracker.swift
//  Film Data Tagger
//

import Foundation

/// Tracks the first-ever app open across all of the user's devices via iCloud KVS.
/// Each device gets a stable UUID and records its own first-open date into a shared map.
///
/// IMPORTANT: This singleton uses `NSUbiquitousKeyValueStore` from a detached
/// background task because the iCloud KVS read can take 20-30ms on launch and
/// blocks main if done synchronously. `NSUbiquitousKeyValueStore` is NOT
/// documented as thread-safe — this code assumes nothing else in the app
/// touches `NSUbiquitousKeyValueStore.default`. If that ever changes, the
/// background dispatch here needs to be revisited.
///
/// Because the load is async, the published properties are nil until the
/// background task completes. Callers (currently only `DebugReport`) must
/// handle the loading state.
@MainActor
final class AppInstallTracker {
    static let shared = AppInstallTracker()

    private nonisolated static let deviceIDKey = "deviceUUID"
    private nonisolated static let firstOpenMapKey = "firstOpenDates"

    /// This device's stable identifier. nil until the background load completes.
    private(set) var deviceID: String?

    /// This device's first-open date. nil until the background load completes.
    private(set) var thisDeviceFirstOpened: Date?

    /// The earliest first-open date across all of the user's devices.
    /// nil until the background load completes.
    private(set) var firstEverOpened: Date?

    private init() {
        // Strong self capture is fine — the Task is one-shot, so the closure
        // (and its strong reference to self) is released as soon as the work
        // completes. There's no retain cycle because self doesn't hold the
        // Task.
        Task.detached(priority: .background) { [self] in
            let local = UserDefaults.standard
            let cloud = NSUbiquitousKeyValueStore.default
            cloud.synchronize()

            // Get or create this device's UUID
            let deviceID: String
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
            let thisDeviceFirstOpened: Date
            if let existing = map[deviceID] {
                thisDeviceFirstOpened = Date(timeIntervalSince1970: existing)
            } else {
                let now = Date()
                map[deviceID] = now.timeIntervalSince1970
                thisDeviceFirstOpened = now
                cloud.set(map, forKey: Self.firstOpenMapKey)
            }

            // Earliest across all devices
            let firstEverOpened: Date
            if let earliest = map.values.min() {
                firstEverOpened = Date(timeIntervalSince1970: earliest)
            } else {
                firstEverOpened = thisDeviceFirstOpened
            }

            let iso = ISO8601DateFormatter()
            debugLog("AppInstallTracker: this device first opened \(iso.string(from: thisDeviceFirstOpened)), earliest across all devices \(iso.string(from: firstEverOpened))")

            await MainActor.run {
                self.deviceID = deviceID
                self.thisDeviceFirstOpened = thisDeviceFirstOpened
                self.firstEverOpened = firstEverOpened
            }
        }
    }
}
