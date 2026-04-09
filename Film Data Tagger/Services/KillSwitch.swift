//
//  KillSwitch.swift
//  Film Data Tagger
//
//  Two-tier remote kill switch for builds with known issues. Fetches a JSON
//  manifest from the marketing site at launch and compares the current build
//  against `hardKill` / `softKill` lists.
//
//  Behavior:
//  - HARD kill: blocking modal. User can update or invoke "Continue anyway"
//    (one-time per build, behind a confirmation).
//  - SOFT kill: gentle nudge modal. Re-shown every 72h. User can dismiss it
//    forever for the current build.
//
//  Both opt-outs are scoped to the current build and cleared automatically
//  when the user installs a different build.
//
//  Fail-open: any network or parse error keeps whatever state was persisted
//  from the last successful fetch (or nothing on first launch). The kill
//  switch must never brick the app.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class KillSwitch {
    static let shared = KillSwitch()

    enum State: Equatable {
        case none
        case soft
        case hard
    }

    /// Current modal state. Always reflects the most recent truth — persisted
    /// flags on launch, then the fetched manifest once it returns. Showing the
    /// modal is optimistic on launch (so a known-killed build doesn't have to
    /// wait for the network), but the fetch can both *escalate* (none → soft,
    /// soft → hard, etc.) and *de-escalate* (anything → none) when the lists
    /// have changed since the last launch.
    private(set) var state: State = .none

    /// App Store URL fetched from the manifest. Cached in UserDefaults so the
    /// modal "Update" button works on the very first launch even before the
    /// network completes.
    private(set) var appStoreURL: URL?

    private static let manifestURL = URL(string: "https://sprokbook.com/kill-switch.json")!
    private static let softKillCadence: TimeInterval = 72 * 3600

    // MARK: - Persisted state

    private enum Keys {
        static let lastCheckedBuild = "killSwitch.lastCheckedBuild"
        static let hardKilled = "killSwitch.hardKilled"
        static let softKilled = "killSwitch.softKilled"
        static let hardKillContinuedAnyway = "killSwitch.hardKillContinuedAnyway"
        static let softKillDisabled = "killSwitch.softKillDisabled"
        static let softKillLastShownAt = "killSwitch.softKillLastShownAt"
        static let cachedAppStoreURL = "killSwitch.cachedAppStoreURL"
    }

    /// Trivial — no UserDefaults reads, no state computation, no work of any
    /// kind. The actual setup happens in `setup()`, called from `.task` after
    /// the first frame so it can never block startup.
    private init() {}

    private var didSetup = false

    /// Initial setup. Idempotent. Async so the caller (ContentView's `.task`)
    /// can `await` it without blocking the main thread on synchronous prefix
    /// work.
    func setup() async {
        guard !didSetup else { return }
        didSetup = true

        let currentBuild = AppVersionTracker.shared.currentBuild
        let lastCheckedBuild = UserDefaults.standard.integer(forKey: Keys.lastCheckedBuild)

        if lastCheckedBuild != currentBuild {
            // Build changed (or first launch with kill switch installed).
            // Wipe all per-build state so the new build starts clean.
            clearPerBuildState()
            UserDefaults.standard.set(currentBuild, forKey: Keys.lastCheckedBuild)
        }

        // Restore cached App Store URL so the Update button is wired up
        // before the first network fetch returns.
        if let urlString = UserDefaults.standard.string(forKey: Keys.cachedAppStoreURL),
           let url = URL(string: urlString) {
            appStoreURL = url
        }

        // Compute initial state from persisted flags.
        state = computeState()

        // Kick off the network fetch off-main. Result either escalates state
        // (none → soft/hard) or no-ops on fail.
        Task.detached(priority: .utility) {
            await KillSwitch.shared.fetch()
        }
    }

    // MARK: - State computation

    private func computeState() -> State {
        let defaults = UserDefaults.standard
        let hardKilled = defaults.bool(forKey: Keys.hardKilled)
        let continuedAnyway = defaults.bool(forKey: Keys.hardKillContinuedAnyway)
        let softKilled = defaults.bool(forKey: Keys.softKilled)
        let softDisabled = defaults.bool(forKey: Keys.softKillDisabled)

        if hardKilled && !continuedAnyway {
            debugLog("KillSwitch: present .hard (hardKilled=true, continuedAnyway=false)")
            return .hard
        }
        if softKilled && !softDisabled && softKillCadenceElapsed() {
            debugLog("KillSwitch: present .soft (softKilled=true, softDisabled=false, cadence elapsed)")
            return .soft
        }

        // state=.none — collect any skip reasons so we know *why* nothing is showing.
        var reasons: [String] = []
        if hardKilled && continuedAnyway { reasons.append("hard skipped: continuedAnyway=true") }
        if softKilled && softDisabled { reasons.append("soft skipped: dismissed forever") }
        if softKilled && !softDisabled && !softKillCadenceElapsed() {
            reasons.append("soft skipped: 72h cadence not elapsed")
        }
        if reasons.isEmpty {
            debugLog("KillSwitch: state=.none (build not killed)")
        } else {
            debugLog("KillSwitch: state=.none (\(reasons.joined(separator: "; ")))")
        }
        return .none
    }

    private func softKillCadenceElapsed() -> Bool {
        guard let lastShown = UserDefaults.standard.object(forKey: Keys.softKillLastShownAt) as? Date else {
            return true
        }
        return Date().timeIntervalSince(lastShown) >= Self.softKillCadence
    }

    private func clearPerBuildState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.hardKilled)
        defaults.removeObject(forKey: Keys.softKilled)
        defaults.removeObject(forKey: Keys.hardKillContinuedAnyway)
        defaults.removeObject(forKey: Keys.softKillDisabled)
        defaults.removeObject(forKey: Keys.softKillLastShownAt)
    }

    // MARK: - User actions

    /// User picked "Don't show again" on the soft kill modal. Permanent for
    /// the current build (cleared on upgrade).
    func dismissSoftKillForever() {
        UserDefaults.standard.set(true, forKey: Keys.softKillDisabled)
        if state == .soft { state = .none }
    }

    /// User confirmed "Continue anyway" on the hard kill warning. Permanent
    /// for the current build (cleared on upgrade). Note that escalating from
    /// soft to hard within a session, or a fresh hard kill being added to the
    /// list later, will NOT re-prompt — the opt-out is final per build.
    func continueAnyway() {
        UserDefaults.standard.set(true, forKey: Keys.hardKillContinuedAnyway)
        if state == .hard { state = .none }
    }

    /// User dismissed the soft kill modal without picking "Don't show again".
    /// Acts as a "remind me later" — the modal won't show again until the
    /// 72h cadence elapses. The cadence timer starts ticking now.
    ///
    /// Setting the timestamp here (rather than on `onAppear`) means an
    /// auto-dismiss from a fetch that says "no longer killed" doesn't burn
    /// the 72h window — only an explicit user dismiss does.
    func dismissSoftKillTemporary() {
        UserDefaults.standard.set(Date(), forKey: Keys.softKillLastShownAt)
        if state == .soft { state = .none }
    }

    // MARK: - Network

    private nonisolated func fetch() async {
        var request = await URLRequest(url: Self.manifestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Fail open — keep persisted state from last successful fetch.
            debugLog("KillSwitch fetch failed: \(error)")
            return
        }

        // Only trust 200 responses. A 404, 5xx, or any other status means
        // either the manifest was removed, the host is misconfigured, or
        // GitHub Pages is serving an error page that could decode as garbage.
        // Fail open in all those cases.
        guard let http = response as? HTTPURLResponse else {
            errorLog("KillSwitch fetch: response was not an HTTPURLResponse")
            return
        }
        guard http.statusCode == 200 else {
            errorLog("KillSwitch fetch: non-200 status \(http.statusCode), ignoring response")
            return
        }

        let manifest: KillSwitchManifest
        do {
            manifest = try JSONDecoder().decode(KillSwitchManifest.self, from: data)
        } catch {
            debugLog("KillSwitch manifest parse failed: \(error)")
            return
        }

        await MainActor.run {
            KillSwitch.shared.applyManifest(manifest)
        }
    }

    private func applyManifest(_ manifest: KillSwitchManifest) {
        let currentBuild = AppVersionTracker.shared.currentBuild

        let hardKilled = (manifest.hardKill ?? []).contains(currentBuild)
            || (manifest.hardKillMinimumBuild.map { currentBuild < $0 } ?? false)
        let softKilled = (manifest.softKill ?? []).contains(currentBuild)

        if hardKilled {
            let inList = (manifest.hardKill ?? []).contains(currentBuild)
            let belowMin = manifest.hardKillMinimumBuild.map { currentBuild < $0 } ?? false
            let why = [
                inList ? "in hardKill list" : nil,
                belowMin ? "below hardKillMinimumBuild=\(manifest.hardKillMinimumBuild ?? 0)" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            debugLog("KillSwitch: fetch reports build \(currentBuild) is HARD killed (\(why))")
        } else if softKilled {
            debugLog("KillSwitch: fetch reports build \(currentBuild) is SOFT killed (in softKill list)")
        } else {
            debugLog("KillSwitch: fetch reports build \(currentBuild) is not killed")
        }

        let defaults = UserDefaults.standard
        defaults.set(hardKilled, forKey: Keys.hardKilled)
        defaults.set(softKilled, forKey: Keys.softKilled)

        // Cache the App Store URL so the Update button works offline next launch.
        if let url = URL(string: manifest.appStoreURL) {
            appStoreURL = url
            defaults.set(manifest.appStoreURL, forKey: Keys.cachedAppStoreURL)
        }

        // Always reflect the freshly-computed state. The fetch is the source
        // of truth — it can both escalate (none → soft / soft → hard) and
        // de-escalate (anything → none) when the lists have changed since
        // the last successful fetch.
        state = computeState()
    }
}

private struct KillSwitchManifest: Decodable {
    let hardKill: [Int]?
    let hardKillMinimumBuild: Int?
    let softKill: [Int]?
    let appStoreURL: String
}
