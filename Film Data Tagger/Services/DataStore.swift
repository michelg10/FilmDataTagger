//
//  DataStore.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation
import SwiftData
import CoreLocation
import Combine
import CoreData

// MARK: - DataStore
actor DataStore: ModelActor {
    let modelExecutor: any ModelExecutor
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        #if DEBUG
        assert(!Thread.isMainThread, "DataStore must be initialized off the main thread")
        #endif
        let modelContext = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
        self.modelContainer = modelContainer
    }

    // MARK: - Publishers

    /// Single signal for remote changes. The VM re-reads `loadAll()` when this fires.
    nonisolated(unsafe) let remoteDataChanged = PassthroughSubject<Void, Never>()

    // MARK: - Startup / Read API

    /// Monotonic version counter — incremented on each loadAll.
    /// The VM uses this to discard stale trees from out-of-order completions.
    private var _treeVersion: Int = 0

    /// Load ALL metadata into memory as a ready-made tree.
    /// Called once on startup and on remote changes.
    /// Ownership is transferred to the caller — the actor holds no references afterward.
    func loadAll() -> sending (tree: [CameraState], version: Int) {
        #if DEBUG
        assertHighPriority()
        #endif
        _treeVersion += 1
        let version = _treeVersion
        let fetchStart = CFAbsoluteTimeGetCurrent()
        var cameras: [Camera] = []
        var allRolls: [Roll] = []
        var allItems: [LogItem] = []
        do {
            cameras = try modelContext.fetch(FetchDescriptor<Camera>(sortBy: [SortDescriptor(\.listOrder)]))
            allRolls = try modelContext.fetch(FetchDescriptor<Roll>())
            allItems = try modelContext.fetch(FetchDescriptor<LogItem>(sortBy: [SortDescriptor(\.createdAt)]))
        } catch {
            errorLog("loadAll fetch failed: \(error)")
        }

        // Build snapshots and seed the diff cache (minimal — own fields only)
        let cameraSnapshots = cameras.map { $0.snapshot }
        let rollSnapshots = allRolls.map { $0.snapshot }
        let itemSnapshots = allItems.map { $0.snapshot }
        let fetchMs = (CFAbsoluteTimeGetCurrent() - fetchStart) * 1000
        lastCameras = cameraSnapshots
        lastRolls = rollSnapshots
        lastItems = itemSnapshots

        // Group items by roll ID
        let itemsByRoll = Dictionary(grouping: itemSnapshots, by: { $0.rollID })

        // Enrich roll snapshots with computed counts from items
        let enrichedRolls = rollSnapshots.map { roll -> RollSnapshot in
            let items = itemsByRoll[roll.id] ?? []
            var s = roll
            s.exposureCount = items.count
            s.lastExposureDate = items.last(where: { $0.hasRealCreatedAt })?.createdAt
            return s
        }

        // Group enriched rolls by camera ID
        let rollsByCamera = Dictionary(grouping: enrichedRolls, by: { $0.cameraID })

        // Build the tree — derive camera summary fields from grouped data
        let tree = cameras.map { camera in
            let cameraRolls = (rollsByCamera[camera.id] ?? [])
                .sorted { ($0.lastExposureDate ?? $0.createdAt) > ($1.lastExposureDate ?? $1.createdAt) }
            let rollStates = cameraRolls.map { roll in
                RollState(snapshot: roll, items: itemsByRoll[roll.id] ?? [])
            }
            let snapshot = CameraSnapshot(
                id: camera.id,
                name: camera.name,
                createdAt: camera.createdAt,
                listOrder: camera.listOrder,
                rollCount: cameraRolls.count,
                totalExposureCount: cameraRolls.reduce(0) { $0 + (itemsByRoll[$1.id]?.count ?? 0) },
                lastUsedDate: cameraRolls.compactMap { $0.lastExposureDate ?? ($0.exposureCount > 0 ? $0.createdAt : nil) }.max()
            )
            return CameraState(snapshot: snapshot, rolls: rollStates)
        }

        let treeMs = (CFAbsoluteTimeGetCurrent() - fetchStart) * 1000 - fetchMs
        let totalMs = fetchMs + treeMs
        debugLog("loadAll: fetch \(String(format: "%.1f", fetchMs))ms + tree \(String(format: "%.1f", treeMs))ms (\(cameras.count) cameras, \(allRolls.count) rolls, \(allItems.count) items)")
        if totalMs > 2000 {
            errorLog("loadAll took \(String(format: "%.0f", totalMs))ms (fetch \(String(format: "%.0f", fetchMs))ms + tree \(String(format: "%.0f", treeMs))ms, \(cameras.count) cameras, \(allRolls.count) rolls, \(allItems.count) items)")
        }

        return (tree, version)
    }

    /// Warm thumbnails for a specific roll into ImageCache.
    /// Call when navigating to a camera (for its active roll) or switching to a roll.
    func warmRollThumbnails(_ rollID: UUID) async {
        let cache = ImageCache.shared
        await cache.bookkeeper.recordAccess(rollID)
        // Skip the SwiftData fault if NSCache still has everything for this roll
        guard cache.isRollDirty(rollID) || !cache.hasWarmedRoll(rollID) else {
            debugLog("warmRollThumbnails(\(rollID)): skipped, roll is clean")
            return
        }
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        for item in items {
            if let data = item.thumbnailData {
                await cache.preload(for: item.id, data: data, rollID: rollID)
            }
        }
        cache.clearRollDirty(rollID)
    }

    /// Provide relationship metadata to the ImageCache bookkeeper so it can decide
    /// which rolls to warm, then fetch item IDs only for those rolls.
    func warmThumbnailCache() async {
        let allCameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])] = allCameras.map { camera in
            let rolls = camera.rolls ?? []
            let activeRollID = rolls.first(where: \.isActive)?.id
            return (camera.id, activeRollID, rolls.map(\.id))
        }

        let bookkeeper = ImageCache.shared.bookkeeper
        await bookkeeper.load()
        let rollsToWarm = await bookkeeper.rollsToWarm(cameraInfo: cameraInfo)

        var priorityIDs = Set<UUID>()
        var itemToRoll: [UUID: UUID] = [:]
        for rollID in rollsToWarm {
            let ids = fetchLogItemIDs(forRoll: rollID, withThumbnailsOnly: true)
            priorityIDs.formUnion(ids)
            for id in ids { itemToRoll[id] = rollID }
        }

        await ImageCache.shared.warmOnLaunch(priorityIDs: priorityIDs, itemToRoll: itemToRoll)
    }

    // MARK: - Write API

    /// Persist a new exposure. The VM has already updated its local state optimistically.
    /// If the roll is not currently active, it will be activated (and the previous active roll
    /// on the same camera deactivated). This handles the case where the user navigates to
    /// an old roll and starts logging.
    ///
    /// Not high priority: do not await
    func logExposure(
        id: UUID,
        rollID: UUID,
        createdAt: Date,
        source: ExposureSource = .app,
        photoData: Data?,
        thumbnailData: Data?,
        location: CLLocation?,
        placeName: String?,
        cityName: String?
    ) async {
        guard let roll = fetchRoll(rollID) else {
            debugLog("logExposure: roll \(rollID) not found")
            remoteDataChanged.send()
            return
        }
        let item = LogItem(roll: roll)
        item.id = id
        item.createdAt = createdAt
        item.exposureSource = source
        item.photoData = photoData
        item.thumbnailData = thumbnailData
        item.cachedHasPhoto = photoData != nil
        item.cachedHasThumbnail = thumbnailData != nil
        if let location {
            item.setLocation(location)
            item.placeName = placeName
            item.cityName = cityName
        }
        modelContext.insert(item)

        // Activate the roll if it isn't already (deactivate the previous active roll)
        if !roll.isActive, let camera = roll.camera {
            for r in camera.rolls ?? [] where r.isActive {
                r.isActive = false
            }
            roll.isActive = true
        }

        save()
    }

    /// Persist a new placeholder. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func logPlaceholder(id: UUID, rollID: UUID, createdAt: Date) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("logPlaceholder: roll \(rollID) not found")
            remoteDataChanged.send()
            return
        }
        let item = LogItem.placeholder(roll: roll)
        item.id = id
        item.createdAt = createdAt
        modelContext.insert(item)
        save()
    }

    /// Delete an item. The VM has already removed it from its local state optimistically.
    /// If the item doesn't exist (e.g., already deleted via CloudKit), re-publish
    /// the current roll items so the VM can reconcile.
    ///
    /// Not high priority: do not await
    func deleteItem(id: UUID) {
        guard let item = fetchLogItem(id) else {
            debugLog("deleteItem: item \(id) not found — triggering reconciliation")
            remoteDataChanged.send()
            return
        }
        modelContext.delete(item)
        save()
        ImageCache.shared.evict(id: id)
    }

    /// Persist the new extra exposures count. The VM computes the cycling logic
    /// and updates its local state optimistically.
    ///
    /// Not high priority: do not await
    func setExtraExposures(rollID: UUID, count: Int) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("setExtraExposures: roll \(rollID) not found")
            remoteDataChanged.send()
            return
        }
        roll.extraExposures = count
        save()
    }

    /// Persist a placeholder's new timestamp. The VM has already resorted its local state.
    ///
    /// Not high priority: do not await
    func movePlaceholder(id: UUID, newTimestamp: Date) {
        guard let item = fetchLogItem(id) else {
            debugLog("movePlaceholder: item \(id) not found — triggering reconciliation")
            remoteDataChanged.send()
            return
        }
        item.createdAt = newTimestamp
        save()
    }

    /// Move an item to a different roll. The VM handles this optimistically and fire-and-forgets.
    func moveItem(id: UUID, toRollID: UUID) {
        guard let item = fetchLogItem(id),
              let targetRoll = fetchRoll(toRollID) else {
            debugLog("moveItem: item \(id) or roll \(toRollID) not found")
            remoteDataChanged.send()
            return
        }

        // Re-parent (SwiftData inverse handles the rest)
        item.roll = targetRoll
        save()
    }

    // MARK: - Roll API

    /// Persist a new roll. The VM has already added the snapshot optimistically.
    ///
    /// Not high priority: do not await
    func createRoll(id: UUID, cameraID: UUID, filmStock: String, capacity: Int, createdAt: Date) {
        guard let camera = fetchCamera(cameraID) else {
            debugLog("createRoll: camera \(cameraID) not found — triggering reload to reconcile")
            remoteDataChanged.send()
            return
        }
        // Deactivate any currently active roll on this camera
        for roll in camera.rolls ?? [] where roll.isActive {
            roll.isActive = false
        }
        let roll = Roll(filmStock: filmStock, camera: camera, capacity: capacity, createdAt: createdAt)
        roll.id = id
        modelContext.insert(roll)
        save()
    }

    /// Persist a roll edit. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func editRoll(id: UUID, filmStock: String, capacity: Int) {
        guard let roll = fetchRoll(id) else {
            debugLog("editRoll: roll \(id) not found")
            remoteDataChanged.send()
            return
        }
        roll.filmStock = filmStock
        roll.capacity = capacity
        save()
    }

    /// Activate a roll. Deactivates any other active roll on the same camera. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func loadRoll(id: UUID) {
        guard let roll = fetchRoll(id) else {
            debugLog("loadRoll: roll \(id) not found")
            remoteDataChanged.send()
            return
        }
        // Deactivate any other active roll on the same camera
        if let camera = roll.camera {
            for r in camera.rolls ?? [] where r.isActive && r.id != id {
                r.isActive = false
            }
        }
        roll.isActive = true
        save()
    }

    /// Deactivate a roll without deleting it. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func unloadRoll(id: UUID) {
        guard let roll = fetchRoll(id) else {
            debugLog("unloadRoll: roll \(id) not found")
            remoteDataChanged.send()
            return
        }
        roll.isActive = false
        save()
    }

    /// Delete a roll and all its exposures (cascade).
    /// The VM has already removed it from its local state optimistically.
    ///
    /// Not high priority: do not await
    func deleteRoll(id: UUID) {
        guard let roll = fetchRoll(id) else {
            debugLog("deleteRoll: roll \(id) not found")
            remoteDataChanged.send()
            return
        }
        for item in roll.logItems ?? [] {
            ImageCache.shared.evict(id: item.id)
        }
        modelContext.delete(roll)
        save()
    }

    // MARK: - Camera API

    /// Persist a new camera. The VM has already added the snapshot optimistically.
    ///
    /// Not high priority: do not await
    func createCamera(id: UUID, name: String, listOrder: Double, createdAt: Date) {
        let camera = Camera(name: name, listOrder: listOrder, createdAt: createdAt)
        camera.id = id
        modelContext.insert(camera)
        save()
    }

    /// Persist a camera rename. The VM has already updated its local state optimistically.
    ///
    /// Not high priority: do not await
    func renameCamera(id: UUID, name: String) {
        guard let camera = fetchCamera(id) else {
            debugLog("renameCamera: camera \(id) not found")
            remoteDataChanged.send()
            return
        }
        camera.name = name
        save()
    }

    /// Delete a camera and all its rolls/exposures (cascade).
    /// The VM has already removed it from its local state optimistically.
    ///
    /// Not high priority: do not await
    func deleteCamera(id: UUID) {
        guard let camera = fetchCamera(id) else {
            debugLog("deleteCamera: camera \(id) not found")
            remoteDataChanged.send()
            return
        }
        // Evict thumbnails for all items in all rolls
        for roll in camera.rolls ?? [] {
            for item in roll.logItems ?? [] {
                ImageCache.shared.evict(id: item.id)
            }
        }
        modelContext.delete(camera)
        save()
    }

    /// Persist a new camera ordering. The VM has already reordered its local state optimistically.
    ///
    /// Not high priority: do not await
    func reorderCameras(orderedIDs: [UUID]) {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>(
            sortBy: [SortDescriptor(\.listOrder)]
        ))) ?? []
        let byID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        // Safety net: append any cameras not in orderedIDs (e.g., arrived via CloudKit during drag)
        let movedSet = Set(orderedIDs)
        let finalOrder = orderedIDs + cameras.map(\.id).filter { !movedSet.contains($0) }
        for (index, id) in finalOrder.enumerated() {
            byID[id]?.listOrder = Double(index)
        }
        save()
    }

    // MARK: - Timezone Change Detection

    private var lastKnownUTCOffset = TimeZone.current.secondsFromGMT()
    private var tzCheckTask: Task<Void, Never>?

    /// Start a 30-second timer that checks for device timezone changes.
    /// If the offset changed, re-publish all observed snapshots with updated formatting.
    func startTimezoneChangeDetection() {
        tzCheckTask?.cancel()
        tzCheckTask = Task(priority: .utility) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                let currentOffset = TimeZone.current.secondsFromGMT()
                if currentOffset != lastKnownUTCOffset {
                    debugLog("Device timezone changed: offset \(lastKnownUTCOffset) → \(currentOffset)")
                    lastKnownUTCOffset = currentOffset
                    // Spawn at high priority — this updates the UI
                    Task(priority: .userInitiated) {
                        self.refreshFormattedSnapshots()
                    }
                }
            }
        }
    }

    /// Called on foreground — check immediately rather than waiting for the timer.
    func checkTimezoneChange() async {
        let currentOffset = TimeZone.current.secondsFromGMT()
        if currentOffset != lastKnownUTCOffset {
            debugLog("Device timezone changed on foreground: offset \(lastKnownUTCOffset) → \(currentOffset)")
            lastKnownUTCOffset = currentOffset
            refreshFormattedSnapshots()
        }
    }

    /// Signal the VM to re-read all data (formatted strings recomputed by LogItem.snapshot).
    private func refreshFormattedSnapshots() {
        remoteDataChanged.send()
    }

    // MARK: - Remote Changes

    private var remoteChangeObserver: (any NSObjectProtocol)?
    private var maintenanceTask: Task<Void, Never>?

    /// Begin observing CloudKit remote changes. Call once on startup.
    func observeRemoteChanges() {
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task(priority: .userInitiated) { await self.handleRemoteChange() }
        }
    }

    private var lastHistoryToken: DefaultHistoryToken?

    /// Check persistent history for real changes since our last token.
    /// Returns true if there are new transactions, false if the notification was a ghost.
    private func hasNewHistoryTransactions() -> Bool {
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>()
        if let lastHistoryToken {
            descriptor.predicate = #Predicate { $0.token > lastHistoryToken }
        }
        let context = ModelContext(modelContainer)
        guard let transactions = try? context.fetchHistory(descriptor), !transactions.isEmpty else {
            debugLog("Remote change: no new history transactions, skipping")
            return false
        }
        #if DEBUG
        // We're disabling this code for now as we've fixed the CloudKit issues, but leave this here for future debugging.
        if false {
            for transaction in transactions {
                let author = transaction.author ?? "nil"
                let changes = transaction.changes
                debugLog("Remote change (author: \(author)): \(changes.count) change(s)")
                for change in changes {
                    let entity = change.changedPersistentIdentifier.entityName
                    switch change {
                    case .insert(_):
                        debugLog("  INSERT \(entity)")
                    case .update(_):
                        debugLog("  UPDATE \(entity)")
                    case .delete(_):
                        debugLog("  DELETE \(entity)")
                    @unknown default:
                        debugLog("  UNKNOWN SWIFTDATA OPERATION")
                    }
                }
            }
        }
        #endif
        lastHistoryToken = transactions.last?.token
        return true
    }

    // Cached flat snapshots for diffing remote changes
    private var lastCameras: [CameraSnapshot] = []
    private var lastRolls: [RollSnapshot] = []
    private var lastItems: [LogItemSnapshot] = []

    /// Called on every NSPersistentStoreRemoteChange.
    /// Re-fetches flat snapshots, diffs against cached copies.
    /// Only rebuilds tree and signals the VM if something actually changed.
    private func handleRemoteChange() {
        // Skip ghost notifications — CloudKit fires many per save, most have no real changes
        guard hasNewHistoryTransactions() else { return }

        // Re-fetch flat snapshots — bail if any fetch fails to avoid diffing against empty data
        let freshCameras: [CameraSnapshot]
        let freshRolls: [RollSnapshot]
        let freshItems: [LogItemSnapshot]
        do {
            freshCameras = try modelContext.fetch(FetchDescriptor<Camera>(sortBy: [SortDescriptor(\.listOrder)])).map { $0.snapshot }
            freshRolls = try modelContext.fetch(FetchDescriptor<Roll>()).map { $0.snapshot }
            freshItems = try modelContext.fetch(FetchDescriptor<LogItem>(sortBy: [SortDescriptor(\.createdAt)])).map { $0.snapshot }
        } catch {
            errorLog("handleRemoteChange: fetch failed, skipping: \(error)")
            return
        }

        // Diff against cached copies
        let changed = freshCameras != lastCameras || freshRolls != lastRolls || freshItems != lastItems
        guard changed else {
            debugLog("Remote change: no diff, skipping")
            return
        }

        // Update cache
        lastCameras = freshCameras
        lastRolls = freshRolls
        lastItems = freshItems

        // Signal the VM to call loadAll()
        remoteDataChanged.send()

        // --- Debounced: maintenance ---

        maintenanceTask?.cancel()
        maintenanceTask = Task(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            repairDuplicateActiveRolls()
            let cutoff = Date().addingTimeInterval(-5 * 60)
            await geocodeItemsIfNeeded(since: cutoff)
        }
    }

    /// Ensure each camera has at most one active roll.
    /// Keeps the most recently used one, deactivates the rest.
    private func repairDuplicateActiveRolls() {
        let cameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        var didRepair = false
        for camera in cameras {
            let activeRolls = (camera.rolls ?? []).filter(\.isActive)
            guard activeRolls.count > 1 else { continue }
            debugLog("repairDuplicateActiveRolls: camera \(camera.name) has \(activeRolls.count) active rolls")
            let keeper = activeRolls
                .sorted {
                    let d0 = ($0.logItems ?? []).filter(\.hasRealCreatedAt).map(\.createdAt).max() ?? .distantPast
                    let d1 = ($1.logItems ?? []).filter(\.hasRealCreatedAt).map(\.createdAt).max() ?? .distantPast
                    return d0 > d1
                }
                .first!
            for roll in activeRolls where roll.id != keeper.id {
                roll.isActive = false
            }
            didRepair = true
        }
        if didRepair {
            save()
            remoteDataChanged.send()
        }
    }

    // MARK: - Export

    /// Export all data as JSON. The @concurrent ExportService runs off the actor's executor.
    func exportJSON() async -> URL? {
        flushSave()
        let context = ModelContext(modelContainer)
        do {
            return try await ExportService.exportJSON(context: context)
        } catch {
            errorLog("exportJSON failed: \(error)")
            return nil
        }
    }

    /// Export all data as CSV. The @concurrent ExportService runs off the actor's executor.
    func exportCSV() async -> URL? {
        flushSave()
        let context = ModelContext(modelContainer)
        do {
            return try await ExportService.exportCSV(context: context)
        } catch {
            errorLog("exportCSV failed: \(error)")
            return nil
        }
    }

    // MARK: - Geocoding

    /// Geocode items missing place names since a cutoff date.
    /// Call on startup (with lastAppLaunchDate cutoff) and foreground (with lastForegroundDate cutoff).
    ///
    /// Not high priority: do not await
    func geocodeItemsIfNeeded(since cutoffDate: Date) async {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> {
                $0.placeName == nil &&
                $0.latitude != nil &&
                $0.longitude != nil &&
                $0.createdAt >= cutoffDate
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let pending = items.compactMap { item -> (UUID, CLLocation)? in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return (item.id, CLLocation(latitude: lat, longitude: lon))
        }
        let results = await Geocoder.geocodeBatch(pending)
        applyGeocodingResults(results)
    }

    /// Geocode items missing place names in a specific roll.
    /// Call on roll switch and after remote changes.
    ///
    /// Not high priority: do not await
    func geocodeItemsInRoll(_ rollID: UUID) async {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> {
                $0.roll?.id == rollID &&
                $0.placeName == nil &&
                $0.latitude != nil &&
                $0.longitude != nil
            }
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let pending = items.compactMap { item -> (UUID, CLLocation)? in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return (item.id, CLLocation(latitude: lat, longitude: lon))
        }
        let results = await Geocoder.geocodeBatch(pending)
        applyGeocodingResults(results)
    }

    /// Persist geocoded place/city names for specific items. No tree reload — caller
    /// updates in-memory snapshots directly.
    func applyGeocoding(itemIDs: [UUID], placeName: String, cityName: String?) {
        for id in itemIDs {
            if let item = fetchLogItem(id) {
                item.placeName = placeName
                if let cityName { item.cityName = cityName }
            }
        }
        save()
    }

    /// Core: write geocoding results and signal remote data changed if any items were updated.
    private func applyGeocodingResults(_ results: [(UUID, GeocodingResult)]) {
        guard !results.isEmpty else { return }
        for (id, result) in results {
            if let item = fetchLogItem(id) {
                if let placeName = result.placeName { item.placeName = placeName }
                if let cityName = result.cityName { item.cityName = cityName }
            }
        }
        save()
        debugLog("applyGeocodingResults: updated \(results.count) item(s), sending remoteDataChanged")
        remoteDataChanged.send()
    }

    /// Re-interpolate placeholder timestamps between real exposures.
    /// Repairs precision exhaustion from repeated drag reordering.
    func repairPlaceholderTimestamps(rollID: UUID) {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        guard items.count >= 2, items.contains(where: \.hasRealCreatedAt) else { return }

        var didRepair = false
        var i = 0
        while i < items.count {
            guard !items[i].hasRealCreatedAt else { i += 1; continue }
            let runStart = i
            while i < items.count && !items[i].hasRealCreatedAt { i += 1 }
            let runEnd = i

            let before = runStart > 0
                ? items[runStart - 1].createdAt
                : items[runEnd < items.count ? runEnd : runStart].createdAt.addingTimeInterval(-Double(runEnd - runStart + 1))
            let after = runEnd < items.count
                ? items[runEnd].createdAt
                : before.addingTimeInterval(Double(runEnd - runStart + 1))

            let count = runEnd - runStart
            for j in 0..<count {
                let fraction = Double(j + 1) / Double(count + 1)
                let newTime = before.addingTimeInterval(after.timeIntervalSince(before) * fraction)
                if items[runStart + j].createdAt != newTime {
                    items[runStart + j].createdAt = newTime
                    didRepair = true
                }
            }
        }

        if didRepair {
            save()
            debugLog("repairPlaceholderTimestamps: repaired roll \(rollID), sending remoteDataChanged")
            remoteDataChanged.send()
        }
    }

    // MARK: - Maintenance

    /// Periodic cleanup: orphan data, stale cache entries.
    /// Runs every 72h. Fires a detached background task to avoid blocking the actor.
    ///
    /// Not high priority: do not await
    private var cleanupInProgress = false
    private func markCleanupDone() { cleanupInProgress = false }
    func runPeriodicCleanupIfNeeded(force: Bool = false) {
        guard !cleanupInProgress else {
            debugLog("Periodic cleanup: already in progress, skipping")
            return
        }
        let defaults = UserDefaults.standard
        if !force, let lastClean = defaults.object(forKey: AppSettingsKeys.lastDataCleanDate) as? Date,
           Date().timeIntervalSince(lastClean) < 72 * 60 * 60 { return }

        cleanupInProgress = true
        debugLog("Periodic cleanup: starting\(force ? " (forced)" : "")")
        let previousRollIDs = Set(defaults.stringArray(forKey: AppSettingsKeys.pendingOrphanRollIDs) ?? [])
        let previousItemIDs = Set(defaults.stringArray(forKey: AppSettingsKeys.pendingOrphanItemIDs) ?? [])

        let container = modelContainer
        Task.detached(priority: .background) { [weak self] in
            defer {
                defaults.set(Date(), forKey: AppSettingsKeys.lastDataCleanDate)
                Task { await self?.markCleanupDone() }
            }
            let context = ModelContext(container)

            // --- 1. Orphan cleanup (two-strike) ---

            let orphanedRolls = (try? context.fetch(FetchDescriptor<Roll>(
                predicate: #Predicate<Roll> { $0.camera == nil }
            ))) ?? []
            let candidateRollIDs = orphanedRolls.map { $0.id.uuidString }

            let orphanedItems = (try? context.fetch(FetchDescriptor<LogItem>(
                predicate: #Predicate<LogItem> { $0.roll == nil }
            ))) ?? []
            let candidateItemIDs = orphanedItems.map { $0.id.uuidString }

            // Persist current candidates for the next run's comparison
            defaults.set(candidateRollIDs, forKey: AppSettingsKeys.pendingOrphanRollIDs)
            defaults.set(candidateItemIDs, forKey: AppSettingsKeys.pendingOrphanItemIDs)

            // Only delete IDs that were also flagged on the previous run
            let confirmedRollIDs = Set(candidateRollIDs).intersection(previousRollIDs)
            let confirmedItemIDs = Set(candidateItemIDs).intersection(previousItemIDs)

            var deletedRolls = 0
            for roll in orphanedRolls where confirmedRollIDs.contains(roll.id.uuidString) {
                for item in roll.logItems ?? [] {
                    ImageCache.shared.evict(id: item.id)
                }
                context.delete(roll)
                deletedRolls += 1
            }
            var deletedItems = 0
            for item in orphanedItems where confirmedItemIDs.contains(item.id.uuidString) {
                ImageCache.shared.evict(id: item.id)
                context.delete(item)
                deletedItems += 1
            }

            if deletedRolls > 0 || deletedItems > 0 {
                do {
                    try context.save()
                    errorLog("Orphan cleanup: deleted \(deletedRolls) roll(s), \(deletedItems) item(s)")
                } catch {
                    errorLog("Orphan cleanup: save failed, \(deletedRolls) roll(s) and \(deletedItems) item(s) will be retried: \(error)")
                }
            }

            // --- 2. Purge stale cache bookkeeper entries ---

            let allRolls = (try? context.fetch(FetchDescriptor<Roll>())) ?? []
            let existingRollIDs = Set(allRolls.map(\.id))
            await ImageCache.shared.bookkeeper.purgeStaleEntries(existingRollIDs: existingRollIDs)

            // --- 3. Recompute media flags + 4. Purge orphaned thumbnails ---
            // Both steps need the full item list. If the fetch fails, bail — an empty
            // set would cause purgeOrphanedFiles to wipe the entire thumbnail cache.

            guard let allItems = try? context.fetch(FetchDescriptor<LogItem>()) else {
                errorLog("Periodic cleanup: LogItem fetch failed, skipping media flags + thumbnail purge")
                return
            }
            var mediaFlagsChanged = false
            for item in allItems {
                let hasPhoto = item.photoData != nil
                let hasThumbnail = item.thumbnailData != nil
                if item.cachedHasPhoto != hasPhoto {
                    item.cachedHasPhoto = hasPhoto
                    mediaFlagsChanged = true
                }
                if item.cachedHasThumbnail != hasThumbnail {
                    item.cachedHasThumbnail = hasThumbnail
                    mediaFlagsChanged = true
                }
            }
            if mediaFlagsChanged {
                do {
                    try context.save()
                    debugLog("Media flags recompute: corrected flags")
                } catch {
                    errorLog("Media flags recompute: save failed: \(error)")
                }
            }

            // --- 4. Purge orphaned thumbnail files ---

            let liveItemIDs = Set(allItems.map(\.id))
            await ImageCache.shared.purgeOrphanedFiles(liveItemIDs: liveItemIDs)
        }
    }

    // MARK: - Internal


    private func fetchCamera(_ id: UUID) -> Camera? {
        let descriptor = FetchDescriptor<Camera>(predicate: #Predicate { $0.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            errorLog("fetchCamera(\(id)) failed: \(error)")
            return nil
        }
    }


    /// Fetch thumbnail data from SwiftData for a single item.
    /// Used as a cache-miss recovery path when the disk cache has been purged.
    func fetchThumbnailData(for id: UUID) -> Data? {
        fetchLogItem(id)?.thumbnailData
    }

    #if DEBUG
    private func assertOffMain(caller: String = #function) {
        if Thread.isMainThread {
            debugLog("WARNING: DataStore.\(caller) running on main thread")
        }
    }
    private func assertHighPriority(caller: String = #function) {
        assertOffMain(caller: caller)
        let qos = Thread.current.qualityOfService
        if qos != .userInitiated && qos != .userInteractive {
            debugLog("WARNING: DataStore.\(caller) expected high-priority QoS, got \(qos.rawValue)")
        }
    }
    #endif

    // MARK: - Debounced save

    private var lastSaveDate: Date = .distantPast
    private var debouncedSaveTask: Task<Void, Never>?
    private static let debounceInterval: TimeInterval = 0.5
    private static let maxSaveDelay: TimeInterval = 2

    private func save() {
        #if DEBUG
        assertOffMain()
        #endif
        // If it's been too long since last save, flush immediately
        if Date().timeIntervalSince(lastSaveDate) > Self.maxSaveDelay {
            flushSave()
            return
        }
        // Otherwise debounce — wait for more writes to batch
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task {
            try? await Task.sleep(for: .seconds(Self.debounceInterval))
            guard !Task.isCancelled else { return }
            self.flushSave()
        }
    }

    /// Flush any pending debounced save immediately. Call on app background/termination.
    func flushSave() {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        lastSaveDate = Date()
        do {
            try modelContext.save()
        } catch {
            errorLog("DataStore save failed: \(error)")
        }
    }

    private func fetchRoll(_ id: UUID) -> Roll? {
        let descriptor = FetchDescriptor<Roll>(predicate: #Predicate { $0.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            errorLog("fetchRoll(\(id)) failed: \(error)")
            return nil
        }
    }

    private func fetchLogItem(_ id: UUID) -> LogItem? {
        let descriptor = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            errorLog("fetchLogItem(\(id)) failed: \(error)")
            return nil
        }
    }

    private func fetchLogItemIDs(forRoll rollID: UUID, withThumbnailsOnly: Bool = false) -> [UUID] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> {
                $0.roll?.id == rollID && (!withThumbnailsOnly || $0.cachedHasThumbnail)
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }
}
