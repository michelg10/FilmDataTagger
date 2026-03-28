//
//  DataStore.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/27/26.
//

import Foundation
import SwiftData
import Combine

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

    // MARK: - Internal

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
