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

struct MoveItemResult: Sendable {
    let targetCameraID: UUID
}

// MARK: - DataStore

@ModelActor
actor DataStore {

    // MARK: - Publishers

    let rollItemsSubject = CurrentValueSubject<[LogItemSnapshot], Never>([])

    // MARK: - Observed state

    private var observedRollID: UUID?

    // MARK: - Startup

    /// Provide relationship metadata to the ImageCache bookkeeper so it can decide
    /// which rolls to warm, then fetch item IDs only for those rolls.
    func warmThumbnailCache() async {
        let allCameras = (try? modelContext.fetch(FetchDescriptor<Camera>())) ?? []
        let cameraInfo: [(cameraID: UUID, activeRollID: UUID?, rollIDs: [UUID])] = allCameras.map { camera in
            let rolls = camera.rolls ?? []
            let activeRollID = rolls.first(where: \.isActive)?.id
            return (camera.id, activeRollID, rolls.map(\.id))
        }

        // Phase 1: bookkeeper decides which rolls matter
        let bookkeeper = ImageCache.shared.bookkeeper
        await bookkeeper.load()
        let rollsToWarm = await bookkeeper.rollsToWarm(cameraInfo: cameraInfo)

        // Phase 2: fetch item IDs only for those rolls
        var priorityIDs = Set<UUID>()
        for rollID in rollsToWarm {
            let ids = fetchLogItemIDs(forRoll: rollID)
            priorityIDs.formUnion(ids)
        }

        // Phase 3: warm from disk
        await ImageCache.shared.warmOnLaunch(priorityIDs: priorityIDs)
    }

    // MARK: - Read API

    /// Set the actively observed roll. Returns the initial snapshot list
    /// and begins publishing updates for this roll via `rollItemsSubject`.
    func observeRoll(_ rollID: UUID) async -> [LogItemSnapshot] {
        observedRollID = rollID
        // Fire-and-forget roll access tracking
        Task { await ImageCache.shared.bookkeeper.recordAccess(rollID) }
        let items = await fetchLogItems(forRoll: rollID)
        // Guard against a newer observeRoll call that started during our await
        guard observedRollID == rollID else { return items }
        rollItemsSubject.send(items)
        return items
    }

    /// Stop observing any roll.
    func stopObservingRoll() {
        observedRollID = nil
        rollItemsSubject.send([])
    }

    // MARK: - Write API

    /// Persist a new exposure. The VM has already updated its local state optimistically.
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
            return
        }
        let item = LogItem(roll: roll)
        item.id = id
        item.createdAt = createdAt
        item.exposureSource = source
        item.photoData = photoData
        item.thumbnailData = thumbnailData
        if let location {
            item.setLocation(location)
            item.placeName = placeName
            item.cityName = cityName
        }
        modelContext.insert(item)
        roll.lastExposureDate = createdAt
        roll.exposureCount += 1
        save()
        if let thumbnailData {
            await ImageCache.shared.preload(for: id, data: thumbnailData)
        }
    }

    /// Persist a new placeholder. The VM has already updated its local state optimistically.
    func logPlaceholder(id: UUID, rollID: UUID, createdAt: Date) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("logPlaceholder: roll \(rollID) not found")
            return
        }
        let item = LogItem.placeholder(roll: roll)
        item.id = id
        item.createdAt = createdAt
        modelContext.insert(item)
        roll.exposureCount += 1
        save()
    }

    /// Delete an item. The VM has already removed it from its local state optimistically.
    /// If the item doesn't exist (e.g., already deleted via CloudKit), re-publish
    /// the current roll items so the VM can reconcile.
    func deleteItem(id: UUID) async {
        guard let item = fetchLogItem(id) else {
            debugLog("deleteItem: item \(id) not found — triggering reconciliation")
            if let rollID = observedRollID {
                rollItemsSubject.send(await fetchLogItems(forRoll: rollID))
            }
            return
        }
        let roll = item.roll
        modelContext.delete(item)
        if let roll {
            roll.exposureCount = max(0, roll.exposureCount - 1)
            recomputeLastExposureDate(for: roll)
        }
        save()
        ImageCache.shared.evict(id: id)
    }

    /// Persist the new extra exposures count. The VM computes the cycling logic
    /// and updates its local state optimistically.
    func setExtraExposures(rollID: UUID, count: Int) {
        guard let roll = fetchRoll(rollID) else {
            debugLog("setExtraExposures: roll \(rollID) not found")
            return
        }
        roll.extraExposures = count
        save()
    }

    /// Persist a placeholder's new timestamp. The VM has already resorted its local state.
    func movePlaceholder(id: UUID, newTimestamp: Date) {
        guard let item = fetchLogItem(id) else {
            debugLog("movePlaceholder: item \(id) not found")
            return
        }
        item.createdAt = newTimestamp
        save()
    }

    /// Move an item to a different roll. NOT optimistic — the VM awaits the result
    /// and then calls `observeRoll` on the target roll.
    func moveItem(id: UUID, toRollID: UUID) -> MoveItemResult? {
        guard let item = fetchLogItem(id),
              let targetRoll = fetchRoll(toRollID),
              let targetCamera = targetRoll.camera else {
            debugLog("moveItem: item \(id) or roll \(toRollID) not found")
            return nil
        }
        let oldRoll = item.roll

        // Re-parent (SwiftData inverse handles the rest)
        item.roll = targetRoll

        // Recompute counts and dates
        if let oldRoll {
            oldRoll.exposureCount = max(0, oldRoll.exposureCount - 1)
            recomputeLastExposureDate(for: oldRoll)
        }
        targetRoll.exposureCount += 1
        if let date = item.hasRealCreatedAt ? item.createdAt : nil {
            if targetRoll.lastExposureDate == nil || date > targetRoll.lastExposureDate! {
                targetRoll.lastExposureDate = date
            }
        }

        save()
        return MoveItemResult(targetCameraID: targetCamera.id)
    }

    // MARK: - Internal

    private func save() {
        do {
            try modelContext.save()
        } catch {
            debugLog("DataStore save failed: \(error)")
        }
    }

    private func fetchRoll(_ id: UUID) -> Roll? {
        let descriptor = FetchDescriptor<Roll>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchLogItem(_ id: UUID) -> LogItem? {
        let descriptor = FetchDescriptor<LogItem>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    private func recomputeLastExposureDate(for roll: Roll) {
        roll.lastExposureDate = (roll.logItems ?? [])
            .filter { $0.hasRealCreatedAt }
            .map(\.createdAt)
            .max()
    }

    private func fetchLogItems(forRoll rollID: UUID) async -> [LogItemSnapshot] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let items = (try? modelContext.fetch(descriptor)) ?? []
        // Decode + cache thumbnails on the actor thread (off main)
        for item in items {
            if let data = item.thumbnailData {
                await ImageCache.shared.preload(for: item.id, data: data)
            }
        }
        return items.map { $0.snapshot }
    }

    private func fetchLogItemIDs(forRoll rollID: UUID) -> [UUID] {
        let descriptor = FetchDescriptor<LogItem>(
            predicate: #Predicate<LogItem> { $0.roll?.id == rollID }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.id)
    }
}
