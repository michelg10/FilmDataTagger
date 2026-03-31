//
//  FilmLogViewModel.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftUI
import CoreLocation
import Combine

@Observable
@MainActor
final class FilmLogViewModel {
    let store: DataStore
    private let settings = AppSettings.shared
    let camera = CameraController()
    let locationService = LocationService()

    // MARK: - In-memory data tree

    /// The full camera hierarchy. Source of truth for the UI.
    @ObservationIgnored private var _cameras: [CameraState] = []
    private(set) var cameras: [CameraState] {
        get { access(keyPath: \.cameras); return _cameras }
        set { withMutation(keyPath: \.cameras) { _cameras = newValue } }
    }

    /// The currently viewed camera (reference into the tree).
    @ObservationIgnored private var _openCamera: CameraState?
    var openCamera: CameraState? {
        get { access(keyPath: \.openCamera); return _openCamera }
        set { withMutation(keyPath: \.openCamera) { _openCamera = newValue } }
    }

    /// The currently viewed roll (reference into the tree).
    @ObservationIgnored private var _openRoll: RollState?
    var openRoll: RollState? {
        get { access(keyPath: \.openRoll); return _openRoll }
        set { withMutation(keyPath: \.openRoll) { _openRoll = newValue }; persistOpenState() }
    }

    private var cancellables = Set<AnyCancellable>()
    private var persistTask: Task<Void, Never>?

    /// Bumped every time applyFullTree replaces the in-memory tree.
    /// Lets code spanning an await detect whether the tree was swapped underneath it.
    private(set) var treeGeneration = UUID()

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

    private func recordOptimistic(_ item: LogItemSnapshot, sourceRollID: UUID? = nil) {
        optimisticItems[item.id] = OptimisticEntry(item: item, sourceRollID: sourceRollID, modifiedAt: Date())
        ensureSweepRunning()
    }

    private func recordOptimisticDelete(_ id: UUID, rollID: UUID) {
        optimisticDeletes[id] = (rollID: rollID, date: Date())
        optimisticItems.removeValue(forKey: id)
        ensureSweepRunning()
    }

    private func ensureSweepRunning() {
        guard sweepTask == nil else { return }
        sweepTask = Task { [weak self] in
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

    private func camera(_ id: UUID) -> CameraState? {
        cameras.first(where: { $0.id == id })
    }

    private func roll(_ id: UUID) -> RollState? {
        cameras.flatMap(\.rolls).first(where: { $0.id == id })
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
            let tree = await store.loadAll()
            guard let self else { return }

            await self.applyFullTree(tree)
            await store.observeRemoteChanges()

            // Background work — lower priority, not blocking UI
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                
                await store.startTimezoneChangeDetection()
                await store.warmThumbnailCache()

                // Warm thumbnails for the open roll (if any)
                if let rollID = await MainActor.run(body: { self.openRoll?.id }) {
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
        let cutoff = settings.lastForegroundDate ?? Date()
        settings.lastForegroundDate = Date()
        Task.detached(priority: .medium) { [store] in
            await store.checkTimezoneChange()
        }
        Task.detached(priority: .utility) { [store] in
            await store.geocodeItemsIfNeeded(since: cutoff)
        }
    }

    private func recordAppLaunch() {
        settings.lastAppLaunchDate = Date()
        settings.lastForegroundDate = Date()
    }

    // MARK: - Open State Persistence

    private struct PersistedOpenState: Codable {
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
            debugLog("restoreOpenStateFromDisk: could not read plist: \(error)")
            return
        }
        let state: PersistedOpenState
        do {
            state = try PropertyListDecoder().decode(PersistedOpenState.self, from: data)
        } catch {
            debugLog("restoreOpenStateFromDisk: decode failed: \(error)")
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
            name: "",
            createdAt: .distantPast,
            listOrder: 0,
            rollCount: 0,
            totalExposureCount: 0
        )
        let cameraState = CameraState(snapshot: minimalCameraSnapshot, rolls: [rollState])
        cameras = [cameraState]
        openCamera = cameraState
        openRoll = rollState
    }

    /// Debounced write of the current open state to disk.
    private func persistOpenState() {
        persistTask?.cancel()
        persistTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let state = await MainActor.run { () -> PersistedOpenState? in
                guard let roll = self.openRoll else { return nil }
                return PersistedOpenState(roll: roll.snapshot, items: roll.items)
            }
            if let state {
                guard let data = try? PropertyListEncoder().encode(state) else {
                    debugLog("persistOpenState: failed to encode")
                    return
                }
                do {
                    try await data.write(to: Self.openStateURL, options: .atomic)
                } catch {
                    debugLog("persistOpenState: failed to write: \(error)")
                }
            } else {
                // No open roll — remove persisted state
                try? await FileManager.default.removeItem(at: Self.openStateURL)
            }
        }
    }

    /// Replace the tree with fresh data from the DataStore. Re-link openCamera/openRoll.
    /// Uses relink methods to diff content and only trigger observation when data actually changed.
    /// Always looks up from the new tree (not _cameras) so item-level changes are detected
    /// even when camera snapshots are unchanged.
    @MainActor
    private func applyFullTree(_ tree: [CameraState]) {
        treeGeneration = UUID()
        let oldCameraID = openCamera?.id
        let oldRollID = openRoll?.id

        mergeOptimisticState(into: tree)
        relinkCameras(tree)

        // Look up from the new tree, not _cameras — relinkCameras may have skipped assignment
        let newCamera = oldCameraID.flatMap { id in tree.first(where: { $0.id == id }) }
        let newRoll = oldRollID.flatMap { id in newCamera?.rolls.first(where: { $0.id == id })
            ?? tree.flatMap(\.rolls).first(where: { $0.id == id }) }

        if oldCameraID != nil {
            relinkOpenCamera(newCamera)
        } else {
            openCamera = nil
        }
        if oldRollID != nil {
            relinkOpenRoll(newRoll)
        } else {
            openRoll = nil
        }
    }

    // MARK: - Observation-aware relinking (applyFullTree only)

    /// Relink cameras to a new tree. Only triggers observation if camera snapshots changed.
    /// When unchanged, keeps old references so existing observations stay valid.
    private func relinkCameras(_ tree: [CameraState]) {
        if _cameras.map(\.snapshot) != tree.map(\.snapshot) {
            withMutation(keyPath: \.cameras) { _cameras = tree }
        }
    }

    /// Relink openCamera. Only triggers observation if the camera snapshot changed.
    /// When unchanged, keeps old reference so observations on CameraState stay valid.
    private func relinkOpenCamera(_ newCamera: CameraState?) {
        if _openCamera?.snapshot != newCamera?.snapshot {
            withMutation(keyPath: \.openCamera) { _openCamera = newCamera }
        }
    }

    /// Relink openRoll. Only triggers observation if snapshot or items changed.
    /// When unchanged, keeps old reference so observations on RollState.items stay valid.
    private func relinkOpenRoll(_ newRoll: RollState?) {
        if _openRoll?.snapshot != newRoll?.snapshot || _openRoll?.items != newRoll?.items {
            withMutation(keyPath: \.openRoll) { _openRoll = newRoll }
            persistOpenState()
        }
    }

    /// Handle remote data changes — reload the tree from the DataStore.
    private func handleRemoteDataChanged() {
        Task.detached(priority: .userInitiated) { [store, weak self] in
            let tree = await store.loadAll()
            guard let self else { return }
            await MainActor.run {
                self.applyFullTree(tree)
            }
        }
    }

    // MARK: - Navigation (instant, in-memory)

    /// Navigate to a camera's roll list.
    func navigateToCamera(_ cameraID: UUID) {
        openCamera = camera(cameraID)
        // Pre-warm active roll thumbnails
        if let activeRollID = openCamera?.activeRoll?.id {
            Task.detached(priority: .utility) { [store] in
                await store.warmRollThumbnails(activeRollID)
            }
        }
    }

    /// Switch to a roll within the current camera.
    func switchToRoll(id rollID: UUID) {
        openRoll = roll(rollID)
        Task.detached(priority: .userInitiated) { [store] in
            await store.warmRollThumbnails(rollID)
        }
        Task.detached(priority: .utility) { [store] in
            await store.geocodeItemsInRoll(rollID)
            await store.repairPlaceholderTimestamps(rollID: rollID)
        }
    }

    /// Switch to a different camera's active roll (camera switcher in ExposureListView header).
    func switchToCameraActiveRoll(_ cameraID: UUID) {
        guard let camera = camera(cameraID),
              let activeRoll = camera.activeRoll else {
                debugLog("switchToCameraActiveRoll: camera \(cameraID) has no active roll");
                return
            }
        openCamera = camera
        openRoll = activeRoll
        Task.detached(priority: .medium) { [store] in
            await store.warmRollThumbnails(activeRoll.id)
        }
        Task.detached(priority: .utility) { [store] in
            await store.geocodeItemsInRoll(activeRoll.id)
            await store.repairPlaceholderTimestamps(rollID: activeRoll.id)
        }
    }

    // MARK: - Logging (optimistic + DataStore)

    private var pendingCaptures = 0
    private var isCapturing = false

    func logExposure() async {
        pendingCaptures += 1
        guard !isCapturing else { return }
        isCapturing = true

        // Capture references + generation before the await — applyFullTree may replace the tree during capture
        let gen = treeGeneration
        var targetRoll = openRoll
        var targetCamera = openCamera

        // Collect data once — shared across all pending taps
        let location = settings.locationEnabled ? locationService.currentLocation : nil
        let placeName = locationService.geocodingState.persistablePlaceName
        let cityName = locationService.geocodingState.persistableCityName
        // Grab the latest video frame instantly — no async wait.
        // If the camera isn't ready yet, captureFrame returns nil — that's fine,
        // the exposure still logs timestamp + location.
        let maxDimension = settings.photoQuality.maxDimension
        let compressionQuality = settings.photoQuality.compressionQuality
        let pixelBuffer = camera.captureFrame()

        // Phase 1 — Fast capture: pixel buffer → CGImage → thumbnail CGImage.
        // No encoding — just a VT call and a small scale+crop.
        let rawData: CaptureRawData? = if let pixelBuffer {
            await Task.detached(priority: .userInitiated) {
                guard let frame = CameraManager.createImage(from: pixelBuffer) else { return nil as CaptureRawData? }
                guard let thumb = CameraManager.generateThumbnail(from: frame) else { return nil as CaptureRawData? }
                return CaptureRawData(fullImage: frame, thumbnailImage: thumb)
            }.value
        } else {
            nil
        }

        // Drain the counter — any taps during the await are included
        let count = pendingCaptures
        pendingCaptures = 0
        isCapturing = false

        // Re-resolve by ID only if the tree was replaced during the await
        if gen != treeGeneration {
            debugLog("logExposure: tree replaced during capture, re-resolving references")
            targetRoll = targetRoll.flatMap { roll($0.id) }
            targetCamera = targetCamera.flatMap { camera($0.id) }
        }

        // Phase 2 — Hot loop: cache thumbnails in memory, build snapshots, append to roll.
        var capturedIDs: [UUID] = []
        var capturedDates: [Date] = []

        for _ in 0..<count {
            guard let targetRoll else {
                debugLog("logExposure: no target roll (deleted during capture?)");
                continue
            }

            // Activate the roll if it isn't already (mirrors DataStore behavior)
            if !targetRoll.snapshot.isActive, let camera = targetCamera {
                camera.activeRoll?.snapshot.isActive = false
                targetRoll.snapshot.isActive = true
                camera.activeRoll = targetRoll
                camera.snapshot.activeRoll = targetRoll.snapshot
                camera.recomputeRollDisplayData()
            }

            let id = UUID()
            let createdAt = Date()

            // Cache thumbnail in memory BEFORE appending snapshot
            // so the view's .task(id:) hits L1 immediately when the row appears
            if let thumb = rawData?.thumbnailImage {
                ImageCache.shared.cacheInMemory(for: id, image: thumb, rollID: targetRoll.id)
            }

            // Build snapshot optimistically
            let snapshot = LogItemSnapshot(
                id: id,
                rollID: targetRoll.id,
                createdAt: createdAt,
                hasRealCreatedAt: true,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                placeName: placeName,
                cityName: cityName,
                timeZoneIdentifier: TimeZone.current.identifier,
                isPlaceholder: false,
                source: ExposureSource.app.rawValue,
                hasThumbnail: rawData?.thumbnailImage != nil,
                hasPhoto: rawData != nil,
                formattedTime: createdAt.formatted(.dateTime.hour().minute()),
                formattedDate: createdAt.formatted(.dateTime.month().day().year()),
                localFormattedTime: createdAt.formatted(.dateTime.hour().minute()),
                localFormattedDate: createdAt.formatted(.dateTime.month().day().year()),
                hasDifferentTimeZone: false,
                capturedTZLabel: nil
            )
            targetRoll.items.append(snapshot)
            recordOptimistic(snapshot)

            // Update roll snapshot caches
            targetRoll.snapshot.exposureCount = targetRoll.items.count
            targetRoll.snapshot.lastExposureDate = createdAt

            // Update camera snapshot caches (use pre-await snapshot, not current openCamera)
            if let camera = targetCamera {
                camera.snapshot.totalExposureCount += 1
                if camera.activeRoll?.id == targetRoll.id {
                    camera.snapshot.activeRoll = targetRoll.snapshot
                }
                camera.snapshot.lastUsedDate = createdAt
            }

            // Cache location for Shortcuts
            if let location {
                AppSettings.shared.cacheShortcutLocation(location)
            }

            capturedIDs.append(id)
            capturedDates.append(createdAt)
        }
        persistOpenState()

        // Phase 3 — Deferred: HEIC encode, persist, disk-cache thumbnails.
        // All encoding and I/O happens here, off the critical path.
        guard !capturedIDs.isEmpty, let targetRoll else { return }
        let rollID = targetRoll.id
        Task.detached(priority: .medium) { [store] in
            // Encode once — shared across all items
            var photoData: Data? = nil
            var thumbnailData: Data? = nil
            if let rawData {
                let scaled: CGImage = if let maxDimension {
                    CameraManager.scaled(rawData.fullImage, maxDimension: maxDimension)
                } else {
                    rawData.fullImage
                }
                photoData = CameraManager.encode(scaled, quality: compressionQuality)
                thumbnailData = CameraManager.formatThumbnailForPersist(rawData.thumbnailImage)
            }

            // Persist each item
            for (id, createdAt) in zip(capturedIDs, capturedDates) {
                await store.logExposure(
                    id: id, rollID: rollID, createdAt: createdAt,
                    source: .app, photoData: photoData, thumbnailData: thumbnailData,
                    location: location, placeName: placeName, cityName: cityName
                )
            }

            // After persistence, apply geocoding
            // This guarantees the rows exist in the DB before we try to update them.
            if let location, placeName == nil {
                let result = await Geocoder.geocode(location)
                if let name = result.placeName {
                    await store.applyGeocoding(itemIDs: capturedIDs, placeName: name, cityName: result.cityName)
                }
            }

            // Disk-cache thumbnails (BGRA, encoding once, saving per-UUID)
            if let rawData {
                await ImageCache.shared.persistThumbnails(for: capturedIDs, image: rawData.thumbnailImage)
            }
        }

        // Geocode if we captured with coordinates but no place name.
        // Fires independently — geocodes the location, updates snapshots in-memory,
        // and tells the DataStore to persist without a full tree reload.
        if let location, placeName == nil {
            let ids = capturedIDs
            let capturedRoll = targetRoll
            Task.detached(priority: .medium) { [store, weak self] in
                let result = await Geocoder.geocode(location)
                guard let name = result.placeName else { return }
                guard let self else { return }
                await MainActor.run {
                    // Use captured roll reference, not self.openRoll —
                    // the user may have switched rolls while geocoding was in-flight.
                    for i in capturedRoll.items.indices where ids.contains(capturedRoll.items[i].id) {
                        capturedRoll.items[i].placeName = name
                        capturedRoll.items[i].cityName = result.cityName
                        self.recordOptimistic(capturedRoll.items[i])
                    }
                    self.persistOpenState()
                }
                await store.applyGeocoding(itemIDs: ids, placeName: name, cityName: result.cityName)
            }
        }
    }

    func logPlaceholder() {
        guard let roll = openRoll else {
            debugLog("logPlaceholder: no open roll");
            return
        }
        let id = UUID()
        let createdAt = Date()
        let snapshot = LogItemSnapshot(
            id: id,
            rollID: roll.id,
            createdAt: createdAt,
            hasRealCreatedAt: false,
            isPlaceholder: true,
            hasThumbnail: false,
            hasPhoto: false,
            formattedTime: "",
            formattedDate: "",
            localFormattedTime: "",
            localFormattedDate: "",
            hasDifferentTimeZone: false,
            capturedTZLabel: nil
        )
        roll.items.append(snapshot)
        recordOptimistic(snapshot)
        // Update roll snapshot caches
        roll.snapshot.exposureCount = roll.items.count
        // Update camera snapshot caches
        if let camera = openCamera {
            camera.snapshot.totalExposureCount += 1
            if camera.activeRoll?.id == roll.id {
                camera.snapshot.activeRoll = roll.snapshot
            }
        }
        persistOpenState()
        Task.detached(priority: .medium) { [store] in
            await store.logPlaceholder(id: id, rollID: roll.id, createdAt: createdAt)
        }
    }

    func deleteItem(_ item: LogItemSnapshot) {
        guard let rollID = item.rollID else {
            debugLog("deleteItem: item \(item.id) has no rollID");
            return
        }
        openRoll?.items.removeAll { $0.id == item.id }
        recordOptimisticDelete(item.id, rollID: rollID)
        // Update roll snapshot caches
        if let roll = openRoll {
            roll.snapshot.exposureCount = roll.items.count
            roll.snapshot.lastExposureDate = roll.items.last(where: { $0.hasRealCreatedAt })?.createdAt
        }
        // Update camera snapshot caches
        if let camera = openCamera {
            camera.snapshot.totalExposureCount = max(0, camera.snapshot.totalExposureCount - 1)
            if let roll = openRoll, camera.activeRoll?.id == roll.id {
                camera.snapshot.activeRoll = roll.snapshot
            }
            camera.snapshot.lastUsedDate = camera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil) }.max()
        }
        persistOpenState()
        Task.detached(priority: .medium) { [store] in
            await store.deleteItem(id: item.id)
        }
    }

    /// Move an exposure to a different roll.
    func moveItem(_ item: LogItemSnapshot, toRollID: UUID) {
        let sourceCamera = openCamera
        let sourceRoll = openRoll

        // Remove from current roll
        sourceRoll?.items.removeAll { $0.id == item.id }

        // Update source roll snapshot caches
        if let sourceRoll {
            sourceRoll.snapshot.exposureCount = sourceRoll.items.count
            sourceRoll.snapshot.lastExposureDate = sourceRoll.items.last(where: { $0.hasRealCreatedAt })?.createdAt
        }

        // Update source camera caches
        if let sourceCamera {
            sourceCamera.snapshot.totalExposureCount = max(0, sourceCamera.snapshot.totalExposureCount - 1)
            if let sourceRoll, sourceCamera.activeRoll?.id == sourceRoll.id {
                sourceCamera.snapshot.activeRoll = sourceRoll.snapshot
            }
            sourceCamera.snapshot.lastUsedDate = sourceCamera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil) }.max()
        }

        // Find target roll in the tree and add the item
        if let targetRoll = roll(toRollID) {
            var movedItem = item
            movedItem.rollID = toRollID
            targetRoll.items.append(movedItem)
            targetRoll.items.sort { $0.createdAt < $1.createdAt }
            recordOptimistic(movedItem, sourceRollID: sourceRoll?.id)

            // Update target roll snapshot caches
            targetRoll.snapshot.exposureCount = targetRoll.items.count
            if item.hasRealCreatedAt {
                if targetRoll.snapshot.lastExposureDate == nil || item.createdAt > targetRoll.snapshot.lastExposureDate! {
                    targetRoll.snapshot.lastExposureDate = item.createdAt
                }
            }

            // Update target camera caches
            if let targetCamera = targetRoll.snapshot.cameraID.flatMap({ camera($0) }) {
                targetCamera.snapshot.totalExposureCount += 1
                if targetCamera.activeRoll?.id == toRollID {
                    targetCamera.snapshot.activeRoll = targetRoll.snapshot
                }
                targetCamera.snapshot.lastUsedDate = targetCamera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil) }.max()
                openCamera = targetCamera
            }
            openRoll = targetRoll
        }

        Task.detached(priority: .medium) { [store] in
            await store.moveItem(id: item.id, toRollID: toRollID)
        }
    }

    /// Move a placeholder to just before the target item.
    func movePlaceholder(_ item: LogItemSnapshot, before target: LogItemSnapshot) {
        guard let roll = openRoll, item.isPlaceholder, item.id != target.id else { return }
        let others = roll.items.filter { $0.id != item.id }
        guard let targetIndex = others.firstIndex(where: { $0.id == target.id }) else { return }

        let newTimestamp: Date
        if targetIndex == 0 {
            newTimestamp = others[0].createdAt.addingTimeInterval(-1)
        } else {
            let a = others[targetIndex - 1].createdAt
            let b = others[targetIndex].createdAt
            newTimestamp = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2.0)
        }
        applyPlaceholderMove(id: item.id, newTimestamp: newTimestamp)
    }

    /// Move a placeholder to just after the target item.
    func movePlaceholder(_ item: LogItemSnapshot, after target: LogItemSnapshot) {
        guard let roll = openRoll, item.isPlaceholder, item.id != target.id else { return }
        let others = roll.items.filter { $0.id != item.id }
        guard let targetIndex = others.firstIndex(where: { $0.id == target.id }) else { return }

        let newTimestamp: Date
        if targetIndex == others.count - 1 {
            newTimestamp = others[targetIndex].createdAt.addingTimeInterval(1)
        } else {
            let a = others[targetIndex].createdAt
            let b = others[targetIndex + 1].createdAt
            newTimestamp = Date(timeIntervalSince1970: (a.timeIntervalSince1970 + b.timeIntervalSince1970) / 2.0)
        }
        applyPlaceholderMove(id: item.id, newTimestamp: newTimestamp)
    }

    func movePlaceholderToEnd(_ item: LogItemSnapshot) {
        guard let roll = openRoll, item.isPlaceholder else { return }
        let others = roll.items.filter { $0.id != item.id }
        let newTimestamp = (others.last?.createdAt ?? Date()).addingTimeInterval(1)
        applyPlaceholderMove(id: item.id, newTimestamp: newTimestamp)
    }

    /// Shared: update local state and persist a placeholder move.
    private func applyPlaceholderMove(id: UUID, newTimestamp: Date) {
        guard let roll = openRoll else {
            debugLog("applyPlaceholderMove: no open roll");
            return
        }
        if let i = roll.items.firstIndex(where: { $0.id == id }) {
            roll.items[i].createdAt = newTimestamp
            recordOptimistic(roll.items[i])
            roll.items.sort { $0.createdAt < $1.createdAt }
        }
        persistOpenState()
        Task.detached(priority: .medium) { [store] in
            await store.movePlaceholder(id: id, newTimestamp: newTimestamp)
        }
    }

    func cycleExtraExposures() {
        playHaptic(.cycleExtraExposures)
        guard let roll = openRoll else {
            debugLog("cycleExtraExposures: no open roll");
            return
        }
        let maxExtra = min(4, roll.items.count)
        let next = roll.snapshot.extraExposures + 1
        roll.snapshot.extraExposures = next > maxExtra ? 0 : next
        roll.snapshot.totalCapacity = roll.snapshot.capacity + roll.snapshot.extraExposures
        // Update camera snapshot if this is the active roll
        if let camera = openCamera, camera.activeRoll?.id == roll.id {
            camera.snapshot.activeRoll = roll.snapshot
        }
        openCamera?.recomputeRollDisplayData()
        persistOpenState()
        let count = roll.snapshot.extraExposures
        Task.detached(priority: .medium) { [store] in
            await store.setExtraExposures(rollID: roll.id, count: count)
        }
    }

    // MARK: - Export

    func exportJSON() async -> URL? {
        await store.exportJSON()
    }

    func exportCSV() async -> URL? {
        await store.exportCSV()
    }

    // MARK: - Roll Management (optimistic + DataStore)

    @discardableResult
    func createRoll(cameraID: UUID, filmStock: String, capacity: Int = 36) -> UUID {
        guard let camera = camera(cameraID) else {
            debugLog("createRoll: camera \(cameraID) not found");
            return UUID()
        }
        let id = UUID()
        // Deactivate previous active roll
        camera.activeRoll?.snapshot.isActive = false
        let snapshot = RollSnapshot(
            id: id,
            cameraID: cameraID,
            filmStock: filmStock,
            capacity: capacity,
            extraExposures: 0,
            isActive: true,
            createdAt: Date(),
            lastExposureDate: nil,
            exposureCount: 0,
            totalCapacity: capacity
        )
        let newRoll = RollState(snapshot: snapshot)
        camera.rolls.insert(newRoll, at: 0)
        camera.activeRoll = newRoll
        // Switch to the new roll
        openCamera = camera
        openRoll = newRoll
        // Update camera snapshot caches
        camera.snapshot.rollCount += 1
        camera.snapshot.activeRoll = newRoll.snapshot
        camera.recomputeRollDisplayData()
        Task.detached(priority: .medium) { [store] in
            await store.createRoll(id: id, cameraID: cameraID, filmStock: filmStock, capacity: capacity)
        }
        return id
    }

    func editRoll(id: UUID, filmStock: String, capacity: Int) {
        if let roll = roll(id) {
            roll.snapshot.filmStock = filmStock
            roll.snapshot.capacity = capacity
            roll.snapshot.totalCapacity = capacity + roll.snapshot.extraExposures
            // Update camera snapshot if this is the active roll
            if openCamera?.activeRoll?.id == id {
                openCamera?.snapshot.activeRoll = roll.snapshot
            }
            openCamera?.recomputeRollDisplayData()
        }
        persistOpenState()
        Task.detached(priority: .medium) { [store] in
            await store.editRoll(id: id, filmStock: filmStock, capacity: capacity)
        }
    }

    func deleteRoll(id: UUID) {
        guard let camera = openCamera else {
            debugLog("deleteRoll: no open camera, cannot delete roll \(id)")
            return
        }
        if openRoll?.id == id {
            openRoll = nil
        }
        let wasActive = camera.activeRoll?.id == id
        let deletedExposureCount = roll(id)?.items.count ?? 0
        camera.rolls.removeAll { $0.id == id }
        camera.snapshot.rollCount = max(0, camera.snapshot.rollCount - 1)
        camera.snapshot.totalExposureCount = max(0, camera.snapshot.totalExposureCount - deletedExposureCount)
        camera.snapshot.lastUsedDate = camera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil) }.max()
        if wasActive {
            camera.activeRoll = nil
            camera.snapshot.activeRoll = nil
        }
        camera.recomputeRollDisplayData()
        Task.detached(priority: .medium) { [store] in
            await store.deleteRoll(id: id)
        }
    }

    // MARK: - Camera Management (optimistic + DataStore)

    func createCamera(name: String) -> UUID {
        let id = UUID()
        let listOrder = (cameras.map(\.snapshot.listOrder).max() ?? -1) + 1
        let snapshot = CameraSnapshot(
            id: id,
            name: name,
            createdAt: Date(),
            listOrder: listOrder,
            rollCount: 0,
            totalExposureCount: 0
        )
        cameras.append(CameraState(snapshot: snapshot))
        Task.detached(priority: .medium) { [store] in
            await store.createCamera(id: id, name: name, listOrder: listOrder)
        }
        return id
    }

    func renameCamera(id: UUID, name: String) {
        if let cam = camera(id) {
            cam.snapshot.name = name
        }
        Task.detached(priority: .medium) { [store] in
            await store.renameCamera(id: id, name: name)
        }
    }

    func deleteCamera(id: UUID) {
        if openCamera?.id == id {
            openRoll = nil
            openCamera = nil
        }
        cameras.removeAll { $0.id == id }
        Task.detached(priority: .medium) { [store] in
            await store.deleteCamera(id: id)
        }
    }

    func reorderCameras(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        let movedSet = Set(orderedIDs)
        let remaining = cameras.filter { !movedSet.contains($0.id) }
        let reordered = orderedIDs.compactMap { byID[$0] } + remaining
        for (i, camera) in reordered.enumerated() {
            camera.snapshot.listOrder = Double(i)
        }
        cameras = reordered
        Task.detached(priority: .medium) { [store] in
            await store.reorderCameras(orderedIDs: orderedIDs)
        }
    }
}
