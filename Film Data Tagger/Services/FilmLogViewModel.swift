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
    private(set) var cameras: [CameraState] = []

    /// The currently viewed camera (reference into the tree).
    var openCamera: CameraState?

    /// The currently viewed roll (reference into the tree).
    var openRoll: RollState? {
        didSet { persistOpenState() }
    }

    private var cancellables = Set<AnyCancellable>()
    private var persistTask: Task<Void, Never>?

    /// Bumped every time applyFullTree replaces the in-memory tree.
    /// Lets code spanning an await detect whether the tree was swapped underneath it.
    private(set) var treeGeneration = UUID()

    // MARK: - Tree lookups

    private func camera(_ id: UUID) -> CameraState? {
        cameras.first(where: { $0.id == id })
    }

    private func roll(_ id: UUID) -> RollState? {
        cameras.flatMap(\.rolls).first(where: { $0.id == id })
    }

    // MARK: - Location (proxied from LocationService)

    var geocodingState: GeocodingState { locationService.geocodingState }
    /// Display-friendly location text that avoids flashing "Locating..." during re-geocoding.
    var displayLocationText: String {
        locationService.displayPlaceName ?? geocodingState.displayText
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
            await self?.applyFullTree(tree)

            // Background work — not blocking UI
            await store.observeRemoteChanges()
            await store.startTimezoneChangeDetection()
            await store.warmThumbnailCache()

            // Warm thumbnails for the open roll (if any)
            if let rollID = await MainActor.run(body: { self?.openRoll?.id }) {
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

    /// Called when the app returns to the foreground.
    /// Geocodes items logged via Shortcuts while backgrounded, and checks for TZ changes.
    func onForeground() {
        let cutoff = settings.lastForegroundDate ?? Date()
        settings.lastForegroundDate = Date()
        Task.detached(priority: .userInitiated) { [store] in
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
        guard let state = try? PropertyListDecoder().decode(PersistedOpenState.self, from: data) else {
            debugLog("restoreOpenStateFromDisk: could not decode plist")
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
                    try data.write(to: Self.openStateURL, options: .atomic)
                } catch {
                    debugLog("persistOpenState: failed to write: \(error)")
                }
            } else {
                // No open roll — remove persisted state
                try? FileManager.default.removeItem(at: Self.openStateURL)
            }
        }
    }

    /// Replace the tree with fresh data from the DataStore. Re-link openCamera/openRoll.
    @MainActor
    private func applyFullTree(_ tree: [CameraState]) {
        treeGeneration = UUID()
        let oldCameraID = openCamera?.id
        let oldRollID = openRoll?.id

        cameras = tree

        if let cameraID = oldCameraID {
            openCamera = camera(cameraID)
        } else {
            openCamera = nil
        }
        if let rollID = oldRollID {
            openRoll = roll(rollID)
        } else {
            openRoll = nil
        }
    }

    /// Handle remote data changes — reload the tree from the DataStore.
    private func handleRemoteDataChanged() {
        Task.detached(priority: .userInitiated) { [store, weak self] in
            let tree = await store.loadAll()
            await MainActor.run {
                self?.applyFullTree(tree)
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
        Task.detached(priority: .userInitiated) { [store] in
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

        // All image work off-main: pixel buffer → CGImage → scale → encode + thumbnail.
        let (photoData, thumbnailData): (Data?, Data?) = if let pixelBuffer {
            await Task.detached(priority: .userInitiated) {
                guard let frame = CameraManager.createImage(from: pixelBuffer) else { return (nil, nil) }
                let scaled: CGImage = if let maxDimension {
                    CameraManager.scaled(frame, maxDimension: maxDimension)
                } else {
                    frame
                }
                let photo = CameraManager.encode(scaled, quality: compressionQuality)
                let thumb = CameraManager.generateThumbnail(from: scaled)
                return (photo, thumb)
            }.value
        } else {
            (nil, nil)
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
                camera.snapshot.activeRollID = targetRoll.id
                camera.snapshot.activeFilmStock = targetRoll.snapshot.filmStock
                camera.snapshot.activeExposureCount = targetRoll.items.count
                camera.snapshot.activeCapacity = targetRoll.snapshot.totalCapacity
            }

            let id = UUID()
            let createdAt = Date()

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
                hasThumbnail: thumbnailData != nil,
                hasPhoto: photoData != nil,
                formattedTime: createdAt.formatted(.dateTime.hour().minute()),
                formattedDate: createdAt.formatted(.dateTime.month().day().year()),
                localFormattedTime: createdAt.formatted(.dateTime.hour().minute()),
                localFormattedDate: createdAt.formatted(.dateTime.month().day().year()),
                hasDifferentTimeZone: false,
                capturedTZLabel: nil
            )
            targetRoll.items.append(snapshot)

            // Update roll snapshot caches
            targetRoll.snapshot.exposureCount = targetRoll.items.count
            targetRoll.snapshot.lastExposureDate = createdAt

            // Update camera snapshot caches (use pre-await snapshot, not current openCamera)
            if let camera = targetCamera {
                camera.snapshot.totalExposureCount += 1
                if camera.activeRoll?.id == targetRoll.id {
                    camera.snapshot.activeExposureCount = targetRoll.items.count
                }
                camera.snapshot.lastUsedDate = createdAt
            }

            // Pre-cache thumbnail so the row displays without decoding
            if let thumbnailData {
                await ImageCache.shared.preload(for: id, data: thumbnailData)
            }

            // Cache location for Shortcuts
            if let location {
                AppSettings.shared.cacheShortcutLocation(location)
            }

            // Fire-and-forget persistence
            Task.detached(priority: .userInitiated) { [store] in
                await store.logExposure(
                    id: id, rollID: targetRoll.id, createdAt: createdAt,
                    source: .app, photoData: photoData, thumbnailData: thumbnailData,
                    location: location, placeName: placeName, cityName: cityName
                )
            }
        }
        persistOpenState()
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
        // Update roll snapshot caches
        roll.snapshot.exposureCount = roll.items.count
        // Update camera snapshot caches
        if let camera = openCamera {
            camera.snapshot.totalExposureCount += 1
            if camera.activeRoll?.id == roll.id {
                camera.snapshot.activeExposureCount = roll.items.count
            }
        }
        persistOpenState()
        Task.detached(priority: .userInitiated) { [store] in
            await store.logPlaceholder(id: id, rollID: roll.id, createdAt: createdAt)
        }
    }

    func deleteItem(_ item: LogItemSnapshot) {
        openRoll?.items.removeAll { $0.id == item.id }
        // Update roll snapshot caches
        if let roll = openRoll {
            roll.snapshot.exposureCount = roll.items.count
            roll.snapshot.lastExposureDate = roll.items.last(where: { $0.hasRealCreatedAt })?.createdAt
        }
        // Update camera snapshot caches
        if let camera = openCamera {
            camera.snapshot.totalExposureCount = max(0, camera.snapshot.totalExposureCount - 1)
            if let roll = openRoll, camera.activeRoll?.id == roll.id {
                camera.snapshot.activeExposureCount = roll.items.count
            }
            camera.snapshot.lastUsedDate = camera.rolls.compactMap(\.snapshot.lastExposureDate).max()
        }
        persistOpenState()
        Task.detached(priority: .userInitiated) { [store] in
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
            if sourceCamera.activeRoll?.id == sourceRoll?.id {
                sourceCamera.snapshot.activeExposureCount = sourceRoll?.items.count
            }
            sourceCamera.snapshot.lastUsedDate = sourceCamera.rolls.compactMap(\.snapshot.lastExposureDate).max()
        }

        // Find target roll in the tree and add the item
        if let targetRoll = roll(toRollID) {
            var movedItem = item
            movedItem.rollID = toRollID
            targetRoll.items.append(movedItem)
            targetRoll.items.sort { $0.createdAt < $1.createdAt }

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
                    targetCamera.snapshot.activeExposureCount = targetRoll.items.count
                }
                targetCamera.snapshot.lastUsedDate = targetCamera.rolls.compactMap(\.snapshot.lastExposureDate).max()
                openCamera = targetCamera
            }
            openRoll = targetRoll
        }

        Task.detached(priority: .userInitiated) { [store] in
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
            roll.items.sort { $0.createdAt < $1.createdAt }
        }
        persistOpenState()
        Task.detached(priority: .userInitiated) { [store] in
            await store.movePlaceholder(id: id, newTimestamp: newTimestamp)
        }
    }

    func cycleExtraExposures() {
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
            camera.snapshot.activeCapacity = roll.snapshot.totalCapacity
        }
        playHaptic(.cycleExtraExposures)
        persistOpenState()
        let count = roll.snapshot.extraExposures
        Task.detached(priority: .userInitiated) { [store] in
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
        camera.snapshot.activeRollID = id
        camera.snapshot.activeFilmStock = filmStock
        camera.snapshot.activeExposureCount = 0
        camera.snapshot.activeCapacity = capacity
        Task.detached(priority: .userInitiated) { [store] in
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
                openCamera?.snapshot.activeFilmStock = filmStock
                openCamera?.snapshot.activeCapacity = capacity + roll.snapshot.extraExposures
            }
        }
        persistOpenState()
        Task.detached(priority: .userInitiated) { [store] in
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
        camera.snapshot.lastUsedDate = camera.rolls.compactMap(\.snapshot.lastExposureDate).max()
        if wasActive {
            camera.activeRoll = nil
            camera.snapshot.activeRollID = nil
            camera.snapshot.activeFilmStock = nil
            camera.snapshot.activeExposureCount = nil
            camera.snapshot.activeCapacity = nil
        }
        Task.detached(priority: .userInitiated) { [store] in
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
        Task.detached(priority: .userInitiated) { [store] in
            await store.createCamera(id: id, name: name, listOrder: listOrder)
        }
        return id
    }

    func renameCamera(id: UUID, name: String) {
        if let cam = camera(id) {
            cam.snapshot.name = name
        }
        Task.detached(priority: .userInitiated) { [store] in
            await store.renameCamera(id: id, name: name)
        }
    }

    func deleteCamera(id: UUID) {
        if openCamera?.id == id {
            openRoll = nil
            openCamera = nil
        }
        cameras.removeAll { $0.id == id }
        Task.detached(priority: .userInitiated) { [store] in
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
        Task.detached(priority: .userInitiated) { [store] in
            await store.reorderCameras(orderedIDs: orderedIDs)
        }
    }
}
