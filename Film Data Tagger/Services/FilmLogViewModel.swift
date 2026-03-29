//
//  FilmLogViewModel.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import Foundation
import SwiftUI
import SwiftData
import CoreData
import CoreLocation
import Combine
import os.log

@Observable
@MainActor
final class FilmLogViewModel {
    private let modelContext: ModelContext
    let store: DataStore
    private let settings = AppSettings.shared
    let cameraManager = CameraManager()
    let locationService = LocationService()

    var referencePhotosEnabled: Bool {
        didSet { settings.referencePhotosEnabled = referencePhotosEnabled }
    }

    /// The currently open (viewed) roll. May or may not be the active roll for its camera.
    var openRoll: RollSnapshot? {
        didSet {
            settings.openRollID = openRoll?.id
        }
    }

    /// The sorted items for the open roll/group. All mutations go through the view model.
    private(set) var logItems: [LogItemSnapshot] = []

    /// The currently selected camera. Derived from openRoll when a roll is set,
    /// or persisted independently when no roll is selected.
    var openCamera: CameraSnapshot? {
        didSet { settings.openCameraID = openCamera?.id }
    }

    /// Camera list — driven by DataStore via Combine, with optimistic local updates.
    private(set) var cameras: [CameraSnapshot] = []

    /// Rolls for the currently observed camera — driven by DataStore via Combine, with optimistic local updates.
    private(set) var rolls: [RollSnapshot] = []

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Location (proxied from LocationService)
    var geocodingState: GeocodingState { locationService.geocodingState }
    /// Display-friendly location text that avoids flashing "Locating..." during re-geocoding.
    var displayLocationText: String {
        locationService.displayPlaceName ?? geocodingState.displayText
    }

    init(modelContext: ModelContext, store: DataStore) {
        self.modelContext = modelContext
        self.store = store
        self.referencePhotosEnabled = AppSettings.shared.referencePhotosEnabled

        store.camerasSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.cameras = $0 }
            .store(in: &cancellables)

        store.cameraRollsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rolls = $0 }
            .store(in: &cancellables)

        store.observedCameraInvalidated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.openCamera = nil
                self.openRoll = nil
                self.logItems = []
                self.rolls = []
            }
            .store(in: &cancellables)

        store.observedRollInvalidated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.openRoll = nil
                self.logItems = []
            }
            .store(in: &cancellables)

        store.rollItemsSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.logItems = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    func setup() {
        switch settings.referencePhotoStartup {
        case .preserveLast: break
        case .on: referencePhotosEnabled = true
        case .off: referencePhotosEnabled = false
        }
        locationService.setup()

        // DataStore startup — load cameras, restore state, start background work
        Task.detached(priority: .userInitiated) { [store, weak self] in
            let cameras = await store.loadCameras()
            await store.observeRemoteChanges()
            await store.startTimezoneChangeDetection()
            await store.warmThumbnailCache()

            // Restore persisted open state
            await self?.restoreOpenState(cameras: cameras)

            // Background maintenance
            let defaults = UserDefaults.standard
            let cutoffDate = min(
                Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date(),
                defaults.object(forKey: AppSettingsKeys.lastAppLaunchDate) as? Date ?? Date.distantPast
            )
            await store.geocodeItemsIfNeeded(since: cutoffDate)
            await store.runPeriodicCleanupIfNeeded()
        }
        recordAppLaunch()
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

    /// Restore persisted open state from the loaded cameras + DataStore.
    private func restoreOpenState(cameras: [CameraSnapshot]) async {
        // 1. Try the persisted open roll ID
        if let storedRollID = settings.openRollID {
            let camera = cameras.first(where: { $0.activeRollID == storedRollID })
            // Observe both camera (for rolls) and roll (for items)
            var cameraRolls: [RollSnapshot] = []
            if let cameraID = camera?.id {
                cameraRolls = store.observeCamera(cameraID)
            }
            let items = await store.observeRoll(storedRollID)
            await MainActor.run {
                openCamera = camera
                rolls = cameraRolls
                openRoll = cameraRolls.first(where: { $0.id == storedRollID })
                logItems = items
            }
            return
        }

        // 2. Try the persisted open camera ID (no roll selected)
        if let storedCameraID = settings.openCameraID {
            let cameraRolls = store.observeCamera(storedCameraID)
            await MainActor.run {
                openCamera = cameras.first(where: { $0.id == storedCameraID })
                rolls = cameraRolls
            }
            return
        }

        // 3. No persisted state matched — drop user at the root CameraListView.
    }

    // MARK: - Logging (optimistic + DataStore)

    private var pendingCaptures = 0
    private var isCapturing = false

    func logExposure() async {
        pendingCaptures += 1
        guard !isCapturing else { return }
        isCapturing = true

        // Snapshot state before the await — roll/camera could change during capture
        let targetRoll = openRoll

        // Collect data once — shared across all pending taps
        let location = settings.locationEnabled ? locationService.currentLocation : nil
        let placeName = locationService.geocodingState.persistablePlaceName
        let cityName = locationService.geocodingState.persistableCityName
        // If the camera isn't ready yet, capturePhoto returns nil — that's fine,
        // the exposure still logs timestamp + location. Speed of capture matters more than blocking for a photo.
        let maxDimension = settings.photoQuality.maxDimension
        let compressionQuality = settings.photoQuality.compressionQuality
        let rawPhotoData: Data? = if referencePhotosEnabled {
            await cameraManager.capturePhoto()
        } else {
            nil
        }

        // Resize + generate thumbnail off-main so the main thread stays responsive.
        // We await the result so the row appears with its image — no flicker.
        let (photoData, thumbnailData): (Data?, Data?) = if let rawPhotoData {
            await Task.detached(priority: .userInitiated) {
                let resized: Data? = if let maxDimension {
                    CameraManager.resized(rawPhotoData, maxDimension: maxDimension, quality: compressionQuality)
                } else {
                    rawPhotoData
                }
                let thumb = resized.flatMap { CameraManager.generateThumbnail(from: $0) }
                return (resized, thumb)
            }.value
        } else {
            (nil, nil)
        }

        // Drain the counter — any taps during the await are included
        let count = pendingCaptures
        pendingCaptures = 0
        isCapturing = false

        for _ in 0..<count {
            guard let targetRoll else { continue }
            let id = UUID()
            let createdAt = Date()

            // Build snapshot optimistically
            let snapshot = LogItemSnapshot(
                id: id,
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
            logItems.append(snapshot)

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
    }

    func logPlaceholder() {
        guard let rollID = openRoll?.id else { return }
        let id = UUID()
        let createdAt = Date()
        let snapshot = LogItemSnapshot(
            id: id,
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
        logItems.append(snapshot)
        Task.detached(priority: .userInitiated) { [store] in
            await store.logPlaceholder(id: id, rollID: rollID, createdAt: createdAt)
        }
    }

    func deleteItem(_ item: LogItemSnapshot) {
        logItems.removeAll { $0.id == item.id }
        Task.detached(priority: .userInitiated) { [store] in
            await store.deleteItem(id: item.id)
        }
    }

    /// Move an exposure to a different roll. NOT optimistic — awaits store, then observes target roll.
    func moveItem(_ item: LogItemSnapshot, toRollID: UUID) {
        logItems.removeAll { $0.id == item.id }
        Task.detached(priority: .userInitiated) { [store, weak self] in
            guard let result = await store.moveItem(id: item.id, toRollID: toRollID) else { return }
            let targetRolls = store.observeCamera(result.targetCameraID)
            let items = await store.observeRoll(toRollID)
            await MainActor.run {
                guard let self else { return }
                self.rolls = targetRolls
                self.openRoll = targetRolls.first(where: { $0.id == toRollID })
                self.openCamera = self.cameras.first(where: { $0.id == result.targetCameraID })
                self.logItems = items
            }
        }
    }

    /// Move a placeholder to just before the target item.
    func movePlaceholder(_ item: LogItemSnapshot, before target: LogItemSnapshot) {
        guard item.isPlaceholder, item.id != target.id else { return }
        let others = logItems.filter { $0.id != item.id }
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
        guard item.isPlaceholder, item.id != target.id else { return }
        let others = logItems.filter { $0.id != item.id }
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
        guard item.isPlaceholder else { return }
        let others = logItems.filter { $0.id != item.id }
        let newTimestamp = (others.last?.createdAt ?? Date()).addingTimeInterval(1)
        applyPlaceholderMove(id: item.id, newTimestamp: newTimestamp)
    }

    /// Shared: update local state and persist a placeholder move.
    private func applyPlaceholderMove(id: UUID, newTimestamp: Date) {
        if let i = logItems.firstIndex(where: { $0.id == id }) {
            logItems[i].createdAt = newTimestamp
            logItems.sort { $0.createdAt < $1.createdAt }
        }
        Task.detached(priority: .userInitiated) { [store] in
            await store.movePlaceholder(id: id, newTimestamp: newTimestamp)
        }
    }

    func cycleExtraExposures() {
        guard var roll = openRoll else { return }
        let maxExtra = min(4, roll.exposureCount)
        let next = roll.extraExposures + 1
        roll.extraExposures = next > maxExtra ? 0 : next
        openRoll = roll
        playHaptic(.cycleExtraExposures)
        Task.detached(priority: .userInitiated) { [store] in
            await store.setExtraExposures(rollID: roll.id, count: roll.extraExposures)
        }
    }

    // MARK: - Export

    func exportJSON() async -> URL? {
        await store.exportJSON()
    }

    func exportCSV() async -> URL? {
        await store.exportCSV()
    }

    /// Start the camera session if reference photos are enabled. Call on exposure screen appear.
    func ensureCameraRunning() {
        guard referencePhotosEnabled else { return }
        Task(priority: .userInitiated) {
            let granted = await cameraManager.requestPermission()
            if granted {
                cameraManager.start()
            } else {
                referencePhotosEnabled = false
            }
        }
    }

    /// Schedule camera stop after a delay. Call on exposure screen disappear.
    func scheduleCameraStop() {
        cameraManager.scheduleStop()
    }

    func toggleReferencePhotos() {
        if !referencePhotosEnabled {
            // Turning on — check permission first
            Task(priority: .userInitiated) {
                let granted = await cameraManager.requestPermission()
                if granted {
                    referencePhotosEnabled = true
                    cameraManager.start()
                }
                // If denied, iOS won't re-prompt — user must go to Settings.
                // permissionDenied is set on CameraManager for the UI to react to.
            }
        } else {
            referencePhotosEnabled = false
            cameraManager.stop()
        }
    }

    // MARK: - Roll Management (optimistic + DataStore)

    /// Navigate to a camera's roll list. Sets openCamera and begins roll observation.
    func navigateToCamera(_ cameraID: UUID) {
        openCamera = cameras.first(where: { $0.id == cameraID })
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let snapshots = await self.store.observeCamera(cameraID)
            await MainActor.run { self.rolls = snapshots }
        }
    }

    func createRoll(cameraID: UUID, filmStock: String, capacity: Int = 36) -> UUID {
        let id = UUID()
        // Deactivate previous active roll optimistically
        for i in rolls.indices where rolls[i].isActive {
            rolls[i].isActive = false
        }
        let snapshot = RollSnapshot(
            id: id,
            filmStock: filmStock,
            capacity: capacity,
            extraExposures: 0,
            isActive: true,
            createdAt: Date(),
            lastExposureDate: nil,
            exposureCount: 0,
            totalCapacity: capacity
        )
        rolls.insert(snapshot, at: 0)
        Task.detached(priority: .userInitiated) { await self.store.createRoll(id: id, cameraID: cameraID, filmStock: filmStock, capacity: capacity) }
        return id
    }

    func editRoll(id: UUID, filmStock: String, capacity: Int) {
        if let i = rolls.firstIndex(where: { $0.id == id }) {
            rolls[i].filmStock = filmStock
            rolls[i].capacity = capacity
            rolls[i].totalCapacity = capacity + rolls[i].extraExposures
        }
        Task.detached(priority: .userInitiated) { await self.store.editRoll(id: id, filmStock: filmStock, capacity: capacity) }
    }

    func deleteRoll(id: UUID) {
        if openRoll?.id == id {
            openRoll = nil
            logItems = []
        }
        rolls.removeAll { $0.id == id }
        Task.detached(priority: .userInitiated) { await self.store.deleteRoll(id: id) }
    }

    /// Switch to a roll by ID. Sets openRoll/openCamera and begins observing.
    func switchToRoll(id rollID: UUID) {
        openRoll = rolls.first(where: { $0.id == rollID })
        Task.detached(priority: .userInitiated) { [store, weak self] in
            let items = await store.observeRoll(rollID)
            await MainActor.run { self?.logItems = items }
        }
    }

    // MARK: - Camera Management (optimistic + DataStore)

    func createCamera(name: String) -> UUID {
        let id = UUID()
        let listOrder = (cameras.map(\.listOrder).max() ?? -1) + 1
        let snapshot = CameraSnapshot(
            id: id,
            name: name,
            createdAt: Date(),
            listOrder: listOrder,
            rollCount: 0,
            totalExposureCount: 0
        )
        cameras.append(snapshot)
        Task.detached(priority: .userInitiated) { await self.store.createCamera(id: id, name: name, listOrder: listOrder) }
        return id
    }

    func renameCamera(id: UUID, name: String) {
        if let i = cameras.firstIndex(where: { $0.id == id }) {
            cameras[i].name = name
        }
        Task.detached(priority: .userInitiated) { await self.store.renameCamera(id: id, name: name) }
    }

    func deleteCamera(id: UUID) {
        if openCamera?.id == id {
            openRoll = nil
            openCamera = nil
            logItems = []
        }
        cameras.removeAll { $0.id == id }
        Task.detached(priority: .userInitiated) { await self.store.deleteCamera(id: id) }
    }

    func reorderCameras(_ orderedIDs: [UUID]) {
        // Reorder local state optimistically
        let byID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0) })
        let movedSet = Set(orderedIDs)
        let remaining = cameras.filter { !movedSet.contains($0.id) }
        var reordered = orderedIDs.compactMap { byID[$0] } + remaining
        for i in reordered.indices {
            reordered[i].listOrder = Double(i)
        }
        cameras = reordered
        Task.detached(priority: .userInitiated) { await self.store.reorderCameras(orderedIDs: orderedIDs) }
    }
}
