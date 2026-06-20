//
//  FilmLogViewModel+Rolls.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 4/1/26.
//

import Foundation

extension FilmLogViewModel: RollsViewModel {
    // MARK: - Navigation

    /// Navigate to a camera's roll list.
    func navigateToCamera(_ cameraID: UUID) {
        _openCamera = camera(cameraID)
        publishSnapshots()
        // Pre-warm active roll thumbnails
        if let activeRollID = _openCamera?.activeRoll?.id {
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let store = await self.store
                await store.warmRollThumbnails(activeRollID)
            }
        }
    }

    /// Switch to a roll within the current camera.
    func switchToRoll(id rollID: UUID) {
        clearUndoState()
        _openRoll = roll(rollID)
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.warmRollThumbnails(rollID)
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.geocodeItemsInRoll(rollID)
            await store.repairPlaceholderTimestamps(rollID: rollID)
        }
    }

    /// Switch to a different camera's active roll (camera switcher in ExposureListView header).
    func switchToCameraActiveRoll(_ cameraID: UUID) {
        clearUndoState()
        guard let camera = camera(cameraID),
              let activeRoll = camera.activeRoll else {
                debugLog("switchToCameraActiveRoll: camera \(cameraID) has no active roll");
                return
            }
        _openCamera = camera
        _openRoll = activeRoll
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.warmRollThumbnails(activeRoll.id)
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.geocodeItemsInRoll(activeRoll.id)
            await store.repairPlaceholderTimestamps(rollID: activeRoll.id)
        }
    }

    // MARK: - Roll CRUD

    @discardableResult
    // MARK: - Active-roll transitions (optimistic snapshot)

    /// Single point for deactivating a roll's optimistic snapshot — mirrors
    /// DataStore.deactivate so the in-memory snapshot carries unload context
    /// immediately, before the next loadAll reconciles from the store.
    func deactivateSnapshot(_ rollState: RollState, at date: Date, timeZoneIdentifier: String?, cityName: String?) {
        rollState.snapshot.isActive = false
        rollState.snapshot.unloadedAt = date
        rollState.snapshot.unloadedTimeZoneIdentifier = timeZoneIdentifier
        rollState.snapshot.unloadedCityName = cityName
    }

    /// Single point for reactivating a roll's optimistic snapshot — mirrors
    /// DataStore.reactivate. Clears unload context, since the roll is loaded again.
    func reactivateSnapshot(_ rollState: RollState) {
        rollState.snapshot.isActive = true
        rollState.snapshot.unloadedAt = nil
        rollState.snapshot.unloadedTimeZoneIdentifier = nil
        rollState.snapshot.unloadedCityName = nil
    }

    func createRoll(cameraID: UUID, filmStock: String, capacity: Int = 36) -> UUID? {
        guard let camera = camera(cameraID) else {
            debugLog("createRoll: camera \(cameraID) not found")
            return nil
        }
        let id = UUID()
        let createdAt = Date()
        let timeZoneIdentifier = TimeZone.current.identifier
        let cityName = locationService.geocodingState.persistableCityName
        // Deactivate previous active roll — unloaded now, where the new roll is loaded.
        if let prior = camera.activeRoll {
            deactivateSnapshot(prior, at: createdAt, timeZoneIdentifier: timeZoneIdentifier, cityName: cityName)
        }
        let snapshot = RollSnapshot(
            id: id,
            cameraID: cameraID,
            filmStock: filmStock,
            capacity: capacity,
            extraExposures: 0,
            isActive: true,
            loadedAt: createdAt,
            loadedTimeZoneIdentifier: timeZoneIdentifier,
            loadedCityName: cityName,
            notes: nil,
            lastExposureDate: nil,
            exposureCount: 0,
            totalCapacity: capacity
        )
        let newRoll = RollState(snapshot: snapshot)
        camera.rolls.insert(newRoll, at: 0)
        camera.activeRoll = newRoll
        // Switch to the new roll
        _openCamera = camera
        _openRoll = newRoll
        // Update camera snapshot caches
        camera.snapshot.rollCount += 1
        camera.snapshot.activeRoll = newRoll.snapshot
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.createRoll(id: id, cameraID: cameraID, filmStock: filmStock, capacity: capacity, createdAt: createdAt, timeZoneIdentifier: timeZoneIdentifier, cityName: cityName)
        }
        return id
    }

    func editRoll(id: UUID, filmStock: String, capacity: Int) {
        if let roll = roll(id) {
            roll.snapshot.filmStock = filmStock
            roll.snapshot.capacity = capacity
            roll.snapshot.totalCapacity = capacity + roll.snapshot.extraExposures
            // Update camera snapshot if this is the active roll
            if _openCamera?.activeRoll?.id == id {
                _openCamera?.snapshot.activeRoll = roll.snapshot
            }
        }
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.editRoll(id: id, filmStock: filmStock, capacity: capacity)
        }
    }

    /// Activate the currently open roll. If another roll is currently active on this camera, it will be deactivated.
    func loadRoll() {
        guard let camera = _openCamera,
              let roll = _openRoll else { return }
        // Deactivate the previously active roll — unloaded now, because the user
        // is loading a different roll.
        if let previousActive = camera.activeRoll, previousActive.id != roll.id {
            deactivateSnapshot(previousActive, at: Date(), timeZoneIdentifier: TimeZone.current.identifier, cityName: nil)
        }
        reactivateSnapshot(roll)
        camera.activeRoll = roll
        camera.snapshot.activeRoll = roll.snapshot
        publishSnapshots()
        persistOpenState()
        let rollID = roll.id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.loadRoll(id: rollID)
        }
    }

    /// Deactivate the current active roll without creating a new one.
    func unloadRoll() {
        guard let camera = _openCamera,
              let roll = camera.activeRoll else { return }
        let unloadedAt = Date()
        let timeZoneIdentifier = TimeZone.current.identifier
        let cityName = locationService.geocodingState.persistableCityName
        deactivateSnapshot(roll, at: unloadedAt, timeZoneIdentifier: timeZoneIdentifier, cityName: cityName)
        camera.activeRoll = nil
        camera.snapshot.activeRoll = nil
        publishSnapshots()
        persistOpenState()
        let rollID = roll.id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.unloadRoll(id: rollID, unloadedAt: unloadedAt, timeZoneIdentifier: timeZoneIdentifier, cityName: cityName)
        }
    }

    func deleteRoll(id: UUID) {
        clearUndoState()
        guard let camera = _openCamera else {
            debugLog("deleteRoll: no open camera, cannot delete roll \(id)")
            return
        }
        if _openRoll?.id == id {
            _openRoll = nil
        }
        let wasActive = camera.activeRoll?.id == id
        let deletedExposureCount = roll(id)?.items.count ?? 0
        camera.rolls.removeAll { $0.id == id }
        camera.snapshot.rollCount = max(0, camera.snapshot.rollCount - 1)
        camera.snapshot.totalExposureCount = max(0, camera.snapshot.totalExposureCount - deletedExposureCount)
        camera.snapshot.lastUsedDate = camera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.loadedAt : nil) }.max()
        if wasActive {
            camera.activeRoll = nil
            camera.snapshot.activeRoll = nil
        }
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.deleteRoll(id: id)
        }
    }

    // MARK: - Roll Detail Edits

    /// Update roll notes in-memory and optionally persist to the store.
    /// Called with `persist: false` on every keystroke (cheap snapshot update so
    /// other views like RollListView see the draft immediately), and with
    /// `persist: true` on debounce flush (hits Core Data + CloudKit).
    func updateRollNotes(id: UUID, notes: String?, persist: Bool) {
        guard let roll = roll(id) else {
            debugLog("updateRollNotes: roll \(id) not found")
            return
        }
        roll.snapshot.notes = notes
        if let camera = _openCamera, camera.activeRoll?.id == id {
            camera.snapshot.activeRoll = roll.snapshot
        }
        publishSnapshots()
        guard persist else { return }
        persistOpenState()
        let rollID = id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.updateRollNotes(rollID: rollID, notes: notes)
        }
    }

    func updateRollCreatedAt(id: UUID, createdAt: Date, timeZoneIdentifier: String, cityName: String?) {
        guard let roll = roll(id) else {
            debugLog("updateRollCreatedAt: roll \(id) not found")
            return
        }
        roll.snapshot.loadedAt = createdAt
        roll.snapshot.loadedTimeZoneIdentifier = timeZoneIdentifier
        roll.snapshot.loadedCityName = cityName
        // Update camera snapshot if this is the active roll
        if let camera = _openCamera, camera.activeRoll?.id == id {
            camera.snapshot.activeRoll = roll.snapshot
        }
        publishSnapshots()
        persistOpenState()
        let rollID = id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.updateRollCreatedAt(rollID: rollID, createdAt: createdAt, timeZoneIdentifier: timeZoneIdentifier, cityName: cityName)
        }
    }
}
