//
//  FilmLogViewModel.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftUI
import Combine

@Observable
@MainActor
final class FilmLogViewModel {
    let store: DataStore
    let settings = AppSettings.shared
    let camera = CameraController()
    let locationService = LocationService()

    // MARK: - View-facing published snapshots (value types only)

    /// Camera list screen data.
    private(set) var cameraList: [CameraSnapshot] = []
    /// Open camera header data (roll list / exposure screen).
    private(set) var openCameraSnapshot: CameraSnapshot?
    /// Roll list body data.
    private(set) var openCameraRolls: OpenCameraRolls?
    /// Camera entries for menus (camera switcher / move-to-roll).
    /// Writable from +MenuContext extension — views see read-only via protocol.
    var menuCameras: [MenuCameraEntry] = []
    /// Roll entries for the move-to-roll menu (current camera's rolls).
    var menuRolls: [MenuRollEntry] = []
    /// Current camera ID for menu highlighting.
    var currentCameraID: UUID?
    /// Current roll ID for menu filtering.
    var currentRollID: UUID?
    /// Open roll header data (exposure screen).
    private(set) var openRollSnapshot: RollSnapshot?
    /// Open roll items (exposure screen body).
    private(set) var openRollItems: [LogItemSnapshot] = []

    // MARK: - Internal tree (internal for extension access, views see only protocols)

    var _cameras: [CameraState] = []
    var _openCamera: CameraState?
    var _openRoll: RollState?

    private var cancellables = Set<AnyCancellable>()
    private var persistTask: Task<Void, Never>?

    /// Bumped every time applyFullTree replaces the in-memory tree.
    /// Lets code spanning an await detect whether the tree was swapped underneath it.
    private(set) var treeGeneration = UUID()

    /// Version of the last applied tree from the DataStore. Used to discard stale trees
    /// when multiple loadAll calls complete out of order.
    private var lastAppliedTreeVersion = 0

    // MARK: - Optimistic State
    //
    // Bounded-TTL optimistic entries that survive tree replacements from the DataStore.
    // When applyFullTree receives a new tree, it merges these entries in so that
    // in-flight mutations (adds, edits, moves, deletes) aren't clobbered by stale data.

    private struct OptimisticEntry {
        let item: LogItemSnapshot
        // Non-nil for moves — the roll the item was moved FROM. Only tracks the most recent
        // source, not the full chain. A double-move (A→B→C) before the first persist completes
        // could theoretically leave a stale copy in A, but this can't happen through the UI
        // (user must navigate to B, find the item, and move it again before the first persist
        // finishes) and self-corrects within the 8s TTL window.
        let sourceRollID: UUID?
        let modifiedAt: Date
    }

    private var optimisticItems: [UUID: OptimisticEntry] = [:]
    private var optimisticDeletes: [UUID: (rollID: UUID, date: Date)] = [:]
    private var sweepTask: Task<Void, Never>?

    private static let optimisticTTL: TimeInterval = 8
    private static let sweepInterval: TimeInterval = 4

    func recordOptimistic(_ item: LogItemSnapshot, sourceRollID: UUID? = nil) {
        optimisticItems[item.id] = OptimisticEntry(item: item, sourceRollID: sourceRollID, modifiedAt: Date())
        ensureSweepRunning()
    }

    func recordOptimisticDelete(_ id: UUID, rollID: UUID) {
        optimisticDeletes[id] = (rollID: rollID, date: Date())
        optimisticItems.removeValue(forKey: id)
        ensureSweepRunning()
    }

    private func ensureSweepRunning() {
        guard sweepTask == nil else { return }
        sweepTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.sweepInterval))
                guard !Task.isCancelled, let self else { break }
                let cutoff = Date().addingTimeInterval(-Self.optimisticTTL)
                self.optimisticItems = self.optimisticItems.filter { $0.value.modifiedAt > cutoff }
                self.optimisticDeletes = self.optimisticDeletes.filter { $0.value.date > cutoff }
                if self.optimisticItems.isEmpty && self.optimisticDeletes.isEmpty {
                    self.sweepTask = nil
                    break
                }
            }
        }
    }

    /// Merge optimistic entries into an incoming tree from the DataStore.
    /// O(optimistic entries) — only touches rolls that have pending inserts or deletes.
    private func mergeOptimisticState(into tree: [CameraState]) {
        guard !optimisticItems.isEmpty || !optimisticDeletes.isEmpty else { return }

        // Group optimistic items by rollID
        var insertsByRoll: [UUID: [LogItemSnapshot]] = [:]
        for (_, entry) in optimisticItems {
            guard let rollID = entry.item.rollID else { continue }
            insertsByRoll[rollID, default: []].append(entry.item)
        }

        // Group deletes by rollID
        var deletesByRoll: [UUID: Set<UUID>] = [:]
        for (itemID, entry) in optimisticDeletes {
            deletesByRoll[entry.rollID, default: []].insert(itemID)
        }

        // IDs to remove from any roll (optimistic items replace DataStore versions)
        let optimisticIDs = Set(optimisticItems.keys)

        // Source rolls for moves — the DataStore still has the old copy there
        let sourceRollIDs = Set(optimisticItems.values.compactMap(\.sourceRollID))

        // Only touch affected rolls
        let affectedRollIDs = Set(insertsByRoll.keys).union(deletesByRoll.keys).union(sourceRollIDs)
        guard !affectedRollIDs.isEmpty else { return }

        // Build roll lookup — O(rolls), not O(items)
        var rollLookup: [UUID: (roll: RollState, camera: CameraState)] = [:]
        for camera in tree {
            for roll in camera.rolls where affectedRollIDs.contains(roll.id) {
                rollLookup[roll.id] = (roll, camera)
            }
        }

        // Track which cameras need snapshot updates
        var cameraDelta: [UUID: Int] = [:]

        for rollID in affectedRollIDs {
            guard let (roll, camera) = rollLookup[rollID] else { continue }
            let countBefore = roll.items.count

            // 1. Remove DataStore versions of optimistic items + deleted items
            let deleteIDs = deletesByRoll[rollID] ?? []
            if !optimisticIDs.isEmpty || !deleteIDs.isEmpty {
                roll.items.removeAll { optimisticIDs.contains($0.id) || deleteIDs.contains($0.id) }
            }
            let removed = countBefore - roll.items.count

            // 2. Re-insert optimistic items
            var added = 0
            if let inserts = insertsByRoll[rollID] {
                roll.items.append(contentsOf: inserts)
                roll.items.sort { $0.createdAt < $1.createdAt }
                added = inserts.count
            }

            // 3. Update roll snapshot if count changed
            let delta = added - removed
            if delta != 0 {
                roll.snapshot.exposureCount = roll.items.count
                roll.snapshot.lastExposureDate = roll.items.last(where: { $0.hasRealCreatedAt })?.createdAt
                cameraDelta[camera.id, default: 0] += delta

                if camera.activeRoll?.id == rollID {
                    camera.snapshot.activeRoll = roll.snapshot
                }
            }
        }

        // 4. Update affected camera snapshots
        for (cameraID, delta) in cameraDelta {
            guard let camera = tree.first(where: { $0.id == cameraID }) else { continue }
            camera.snapshot.totalExposureCount += delta
            camera.snapshot.lastUsedDate = camera.rolls.compactMap {
                $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil)
            }.max()
        }
    }

    // MARK: - Tree lookups

    func camera(_ id: UUID) -> CameraState? {
        _cameras.first(where: { $0.id == id })
    }

    func roll(_ id: UUID) -> RollState? {
        _cameras.flatMap(\.rolls).first(where: { $0.id == id })
    }

    // MARK: - Snapshot publishing

    /// Tracking state for O(1) items fast-path in publishSnapshots()
    private weak var _lastPublishedRoll: RollState?
    private var _lastPublishedItemsVersion: Int = -1

    /// Project the internal tree into view-facing snapshot properties.
    /// Diffs before assigning to avoid triggering unnecessary SwiftUI re-renders.
    func publishSnapshots() {
        // Camera list — diff ~9 structs, cheap
        let newCameraList = _cameras.map(\.snapshot)
        if cameraList != newCameraList { cameraList = newCameraList }

        // Open camera snapshot
        let newCameraSnap = _openCamera?.snapshot
        if openCameraSnapshot != newCameraSnap { openCameraSnapshot = newCameraSnap }

        // Open camera rolls — computed inline, no cache to go stale
        let newRolls: OpenCameraRolls? = if let openCamera = _openCamera {
            OpenCameraRolls(
                activeRoll: openCamera.activeRoll?.snapshot,
                pastRolls: openCamera.rolls
                    .filter { $0.id != openCamera.activeRoll?.id }
                    .map(\.snapshot)
                    .sorted { ($0.lastExposureDate ?? $0.createdAt) > ($1.lastExposureDate ?? $1.createdAt) },
                maxRollCapacity: openCamera.rolls.map(\.snapshot.totalCapacity).max() ?? 36,
                hasRolls: !openCamera.rolls.isEmpty
            )
        } else {
            nil
        }
        if openCameraRolls != newRolls { openCameraRolls = newRolls }

        // Menu entries — minimal structs for camera switcher / move-to-roll menus
        publishMenuEntries()

        // Open roll — O(1) fast-path via version counter + object identity
        let roll = _openRoll
        let version = roll?.itemsVersion ?? -1
        if roll !== _lastPublishedRoll || version != _lastPublishedItemsVersion {
            let newSnap = roll?.snapshot
            if openRollSnapshot != newSnap { openRollSnapshot = newSnap }
            openRollItems = roll?.items ?? []
            _lastPublishedRoll = roll
            _lastPublishedItemsVersion = version
        } else {
            // Same roll, items unchanged — but snapshot may have changed (e.g. extraExposures)
            let newSnap = roll?.snapshot
            if openRollSnapshot != newSnap { openRollSnapshot = newSnap }
        }
    }

    init(store: DataStore) {
        self.store = store

        // Sync restore from disk — sets openCamera/openRoll before ContentView.init reads them
        restoreOpenStateFromDisk()

        store.remoteDataChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleRemoteDataChanged() }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    func setup() {
        camera.setup()
        locationService.setup()

        // Capture previous launch date before overwriting — the detached task needs it for geocoding cutoff
        let previousLaunchDate = settings.lastAppLaunchDate
        recordAppLaunch()

        // Full async load — replaces the minimal persisted state with the real tree
        Task.detached(priority: .userInitiated) { [store, weak self] in
            let (tree, version) = await store.loadAll()
            guard let self else { return }

            await self.applyFullTree(tree, version: version)
            await store.observeRemoteChanges()

            // Background work — lower priority, not blocking UI
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                
                await store.startTimezoneChangeDetection()
                await store.warmThumbnailCache()

                // Warm thumbnails for the open roll (if any)
                if let rollID = await MainActor.run(body: { self._openRoll?.id }) {
                    await store.warmRollThumbnails(rollID)
                }

                // Background maintenance
                let cutoffDate = min(
                    Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
                    previousLaunchDate ?? Date.distantPast
                )
                await store.geocodeItemsIfNeeded(since: cutoffDate)
                await store.runPeriodicCleanupIfNeeded()
            }
        }
    }

    /// Called when the app returns to the foreground.
    /// Geocodes items logged via Shortcuts while backgrounded, and checks for TZ changes.
    func onForeground() {
        camera.recheckPermission()
        let cutoff = settings.lastForegroundDate ?? Date()
        settings.lastForegroundDate = Date()
        Task.detached(priority: .medium) { [store] in
            await store.checkTimezoneChange()
        }
        Task.detached(priority: .utility) { [store] in
            await store.geocodeItemsIfNeeded(since: cutoff)
        }
    }

    /// Called when the app enters background. Flushes any pending debounced saves.
    func onBackground() {
        flushOpenState()
        Task.detached(priority: .userInitiated) { [store] in
            await store.flushSave()
        }
    }

    /// Snapshot the current open state on MainActor. Returns nil if no roll is open.
    private func snapshotOpenState() -> PersistedOpenState? {
        guard let roll = _openRoll else { return nil }
        return PersistedOpenState(cameraName: _openCamera?.snapshot.name, roll: roll.snapshot, items: roll.items)
    }

    /// Write the open state plist immediately and synchronously.
    /// Call from onBackground where the process may be killed right after.
    private func flushOpenState() {
        persistTask?.cancel()
        persistTask = nil
        guard let state = snapshotOpenState() else {
            try? FileManager.default.removeItem(at: Self.openStateURL)
            return
        }
        guard let data = try? PropertyListEncoder().encode(state) else {
            errorLog("flushOpenState: failed to encode")
            return
        }
        do {
            try data.write(to: Self.openStateURL, options: .atomic)
        } catch {
            errorLog("flushOpenState: failed to write: \(error)")
        }
    }

    /// Write the open state plist off the main actor. Snapshot is captured on MainActor,
    /// encoding and I/O happen on a utility thread.
    private func writeOpenStateAsync() {
        persistTask?.cancel()
        let state = snapshotOpenState()
        persistTask = Task.detached(priority: .utility) {
            if let state {
                guard let data = try? PropertyListEncoder().encode(state) else {
                    errorLog("writeOpenStateAsync: failed to encode")
                    return
                }
                do {
                    try data.write(to: Self.openStateURL, options: .atomic)
                } catch {
                    errorLog("writeOpenStateAsync: failed to write: \(error)")
                }
            } else {
                try? FileManager.default.removeItem(at: Self.openStateURL)
            }
        }
    }

    private func recordAppLaunch() {
        settings.lastAppLaunchDate = Date()
        settings.lastForegroundDate = Date()
    }

    // MARK: - Open State Persistence

    private struct PersistedOpenState: Codable {
        let cameraName: String?
        let roll: RollSnapshot
        let items: [LogItemSnapshot]
    }

    private static let openStateURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("openState.plist")
    }()

    /// Sync restore from disk. Called in init before ContentView reads openCamera/openRoll.
    private func restoreOpenStateFromDisk() {
        let data: Data
        do {
            data = try Data(contentsOf: Self.openStateURL)
        } catch {
            errorLog("restoreOpenStateFromDisk: could not read plist: \(error)")
            return
        }
        let state: PersistedOpenState
        do {
            state = try PropertyListDecoder().decode(PersistedOpenState.self, from: data)
        } catch {
            errorLog("restoreOpenStateFromDisk: decode failed: \(error)")
            return
        }
        guard let cameraID = state.roll.cameraID else {
            debugLog("restoreOpenStateFromDisk: no cameraID in persisted roll")
            return
        }

        // Build minimal tree nodes for immediate display
        let rollState = RollState(snapshot: state.roll, items: state.items)
        let minimalCameraSnapshot = CameraSnapshot(
            id: cameraID,
            name: state.cameraName ?? "",
            createdAt: .distantPast,
            listOrder: 0,
            rollCount: 0,
            totalExposureCount: 0
        )
        let cameraState = CameraState(snapshot: minimalCameraSnapshot, rolls: [rollState])
        _cameras = [cameraState]
        _openCamera = cameraState
        _openRoll = rollState
        publishSnapshots()
    }

    /// Debounced write of the current open state to disk.
    /// Snapshots state on MainActor, encodes and writes off-main.
    func persistOpenState() {
        persistTask?.cancel()
        let state = snapshotOpenState()
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if let state {
                guard let data = try? PropertyListEncoder().encode(state) else {
                    errorLog("persistOpenState: failed to encode")
                    return
                }
                do {
                    try data.write(to: Self.openStateURL, options: .atomic)
                } catch {
                    errorLog("persistOpenState: failed to write: \(error)")
                }
            } else {
                try? FileManager.default.removeItem(at: Self.openStateURL)
            }
        }
    }

    /// Replace the tree with fresh data from the DataStore.
    /// Always installs the new tree — publishSnapshots() handles diffing for views.
    @MainActor
    private func applyFullTree(_ tree: sending [CameraState], version: Int) {
        guard version > lastAppliedTreeVersion else {
            debugLog("applyFullTree: skipping stale tree (version \(version), current \(lastAppliedTreeVersion))")
            return
        }
        lastAppliedTreeVersion = version
        treeGeneration = UUID()
        let oldCameraID = _openCamera?.id
        let oldRollID = _openRoll?.id
        // Preserve in-memory extraExposures — can be rapidly cycled by the user,
        // and the persist may not have completed before this tree replacement.
        let preservedExtra = _openRoll?.snapshot.extraExposures

        mergeOptimisticState(into: tree)
        _cameras = tree
        _openCamera = oldCameraID.flatMap { id in tree.first { $0.id == id } }
        _openRoll = oldRollID.flatMap { id in
            _openCamera?.rolls.first { $0.id == id }
                ?? tree.flatMap(\.rolls).first { $0.id == id }
        }

        // Restore extraExposures if the new tree has a stale value
        if let extra = preservedExtra, let roll = _openRoll,
           roll.snapshot.extraExposures != extra {
            roll.snapshot.extraExposures = extra
            roll.snapshot.totalCapacity = roll.snapshot.capacity + extra
            if let openCamera = _openCamera, openCamera.activeRoll?.id == roll.id {
                openCamera.snapshot.activeRoll = roll.snapshot
            }
        }

        publishSnapshots()
        persistOpenState()
    }

    /// Handle remote data changes — reload the tree from the DataStore.
    private func handleRemoteDataChanged() {
        Task.detached(priority: .userInitiated) { [store, weak self] in
            let (tree, version) = await store.loadAll()
            guard let self else { return }
            await self.applyFullTree(tree, version: version)
        }
    }

    // MARK: - Capture state (stored properties for logExposure, accessed from +Exposures extension)

    var pendingCaptures = 0
    var isCapturing = false

    // MARK: - Export

    func exportJSON() async -> URL? {
        await store.exportJSON()
    }

    func exportCSV() async -> URL? {
        await store.exportCSV()
    }
}
