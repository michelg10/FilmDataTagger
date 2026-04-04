//
//  AppVersionTracker.swift
//  Film Data Tagger
//

import Foundation

/// Tracks app build number across launches. Logs when the app has been updated.
/// Synchronous on init — UserDefaults reads are cached memory lookups, sub-microsecond.
@MainActor
final class AppVersionTracker {
    static let shared = AppVersionTracker()

    private static let lastBuildKey = "lastLaunchedBuildNumber"

    /// The build number from the previous launch, or nil on first launch.
    let previousBuild: Int?

    /// The current build number.
    let currentBuild: Int

    /// Whether this launch is the first after an app update (or fresh install).
    let didUpdate: Bool

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.lastBuildKey) as? Int
        let current = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0

        previousBuild = stored
        currentBuild = current
        didUpdate = stored != current

        if didUpdate {
            if let prev = stored {
                errorLog("App updated: build \(prev) → \(current)")
            } else {
                errorLog("App first launch: build \(current)")
            }
            UserDefaults.standard.set(current, forKey: Self.lastBuildKey)
        }
    }
}
