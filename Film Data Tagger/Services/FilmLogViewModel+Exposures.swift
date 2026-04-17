//
//  FilmLogViewModel+Exposures.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 4/1/26.
//

import Foundation
import CoreLocation
import CoreGraphics

// MARK: - ExposuresViewModel + ExposureMenuContext

extension FilmLogViewModel: ExposuresViewModel {
    // MARK: - Capture state

    // pendingCaptures and isCapturing live on the main class since they're stored properties.
    // Extension methods access them via self.

    func logExposure() async {
        pendingCaptures += 1
        guard !isCapturing else { return }
        isCapturing = true

        // Capture references + generation before the await — applyFullTree may replace the tree during capture
        let gen = treeGeneration
        var targetRoll = _openRoll
        var targetCamera = _openCamera

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
        // Intentionally fail-fast: if either step fails (memory pressure, corrupt data),
        // drop both rather than persisting a partial result that could cause issues downstream.
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
                exposureType: .regular,
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

        // Backfill roll city name if it was missing at creation (e.g., first install —
        // location permission hadn't been granted yet when the roll was created).
        if let targetRoll, targetRoll.snapshot.cityName == nil,
           let cityName, !cityName.isEmpty,
           targetRoll.snapshot.createdAt.timeIntervalSinceNow > -900 {
            targetRoll.snapshot.cityName = cityName
            if let camera = targetCamera, camera.activeRoll?.id == targetRoll.id {
                camera.snapshot.activeRoll = targetRoll.snapshot
            }
            let rollID = targetRoll.id
            Task.detached(priority: .utility) { [weak self] in
                guard let self else { return }
                let store = await self.store
                await store.updateRollCityName(rollID: rollID, cityName: cityName)
            }
        }

        publishSnapshots()
        persistOpenState()

        // Phase 3 — Deferred: HEIC encode, persist, disk-cache thumbnails.
        // All encoding and I/O happens here, off the critical path.
        guard !capturedIDs.isEmpty, let targetRoll else { return }
        let rollID = targetRoll.id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
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
        // Fires independently — patches in-memory snapshots for fast UI update.
        // DB write is handled by Phase 3 above (which geocodes after persistence guarantees rows exist).
        if let location, placeName == nil {
            let ids = capturedIDs
            let capturedRoll = targetRoll
            Task.detached(priority: .medium) { [weak self] in
                let result = await Geocoder.geocode(location)
                guard let name = result.placeName else { return }
                guard let self else { return }
                await MainActor.run {
                    // If the tree was replaced, capturedRoll is orphaned — grab the live one
                    guard let roll = self.roll(capturedRoll.id) else {
                        debugLog("Geocoding update: roll \(capturedRoll.id) not found, skipping in-memory update")
                        return
                    }
                    for i in roll.items.indices where ids.contains(roll.items[i].id) {
                        roll.items[i].placeName = name
                        roll.items[i].cityName = result.cityName
                        self.recordOptimistic(roll.items[i])
                    }
                    self.publishSnapshots()
                    self.persistOpenState()
                }
            }
        }
    }

    func logPlaceholderLike(_ type: ExposureType) {
        guard type == .placeholder || type == .lostFrame else {
            debugLog("logPlaceholderLike: invalid type \(type), ignoring")
            return
        }
        guard let roll = _openRoll else {
            debugLog("logPlaceholderLike: no open roll");
            return
        }
        let id = UUID()
        let createdAt = Date()

        // Lost frames record real time/location (the exposure happened, just no photo).
        // Placeholders have no metadata — they're just positional markers.
        let recordMetadata = type == .lostFrame
        let location = recordMetadata && settings.locationEnabled ? locationService.currentLocation : nil
        let placeName = recordMetadata ? locationService.geocodingState.persistablePlaceName : nil
        let cityName = recordMetadata ? locationService.geocodingState.persistableCityName : nil
        let timeZoneIdentifier = recordMetadata ? TimeZone.current.identifier : nil

        let snapshot = LogItemSnapshot(
            id: id,
            rollID: roll.id,
            createdAt: createdAt,
            hasRealCreatedAt: recordMetadata,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            placeName: placeName,
            cityName: cityName,
            timeZoneIdentifier: timeZoneIdentifier,
            exposureType: type,
            hasThumbnail: false,
            hasPhoto: false,
            formattedTime: recordMetadata ? createdAt.formatted(.dateTime.hour().minute()) : "",
            formattedDate: recordMetadata ? createdAt.formatted(.dateTime.month().day().year()) : "",
            localFormattedTime: recordMetadata ? createdAt.formatted(.dateTime.hour().minute()) : "",
            localFormattedDate: recordMetadata ? createdAt.formatted(.dateTime.month().day().year()) : "",
            hasDifferentTimeZone: false,
            capturedTZLabel: nil
        )
        roll.items.append(snapshot)
        recordOptimistic(snapshot)
        // Update roll snapshot caches
        roll.snapshot.exposureCount = roll.items.count
        if recordMetadata {
            roll.snapshot.lastExposureDate = createdAt
        }
        // Update camera snapshot caches
        if let camera = _openCamera {
            camera.snapshot.totalExposureCount += 1
            if recordMetadata {
                camera.snapshot.lastUsedDate = createdAt
            }
            if camera.activeRoll?.id == roll.id {
                camera.snapshot.activeRoll = roll.snapshot
            }
        }
        publishSnapshots()
        persistOpenState()
        let rollID = roll.id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.logPlaceholderLike(
                id: id, rollID: rollID, createdAt: createdAt, type: type,
                location: location, placeName: placeName, cityName: cityName,
                timeZoneIdentifier: timeZoneIdentifier
            )
        }
    }

    func deleteItem(_ item: LogItemSnapshot) {
        guard let rollID = item.rollID else {
            debugLog("deleteItem: item \(item.id) has no rollID");
            return
        }
        // Commit the previous pending deletion before saving the new one
        let previousID = lastDeletedItem?.id
        let deletedAt = Date()
        lastDeletedItem = item
        lastDeletedAt = deletedAt
        undoExpirationTask?.cancel()
        undoExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undoDeleteCutoff))
            guard !Task.isCancelled else { return }
            self?.clearUndoState()
        }
        _openRoll?.items.removeAll { $0.id == item.id }
        recordOptimisticDelete(item.id, rollID: rollID)
        // Update roll snapshot caches
        if let roll = _openRoll {
            roll.snapshot.exposureCount = roll.items.count
            roll.snapshot.lastExposureDate = roll.items.last(where: { $0.hasRealCreatedAt })?.createdAt
        }
        // Update camera snapshot caches
        if let camera = _openCamera {
            camera.snapshot.totalExposureCount = max(0, camera.snapshot.totalExposureCount - 1)
            if let roll = _openRoll, camera.activeRoll?.id == roll.id {
                camera.snapshot.activeRoll = roll.snapshot
            }
            camera.snapshot.lastUsedDate = camera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil) }.max()
        }
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            // Hard-delete the previous item, soft-delete the new one
            if let previousID { await store.commitItemDeletion(id: previousID) }
            await store.markItemPendingDeletion(id: item.id, deletedAt: deletedAt)
        }
    }

    /// Commits the pending deletion and clears undo state.
    func clearUndoState() {
        guard let item = lastDeletedItem else { return }
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        lastDeletedItem = nil
        lastDeletedAt = nil
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.commitItemDeletion(id: item.id)
        }
    }

    /// Undo the last deletion: re-insert the item into the roll at its correct position.
    func undoDelete() {
        guard let item = lastDeletedItem else {
            debugLog("undoDelete: no item to undo")
            return
        }
        guard let roll = _openRoll, roll.id == item.rollID else {
            debugLog("undoDelete: open roll (\(_openRoll?.id.uuidString ?? "nil")) doesn't match item's roll (\(item.rollID?.uuidString ?? "nil")), clearing")
            clearUndoState()
            return
        }

        // Clear undo state without committing the deletion
        undoExpirationTask?.cancel()
        undoExpirationTask = nil
        lastDeletedItem = nil
        lastDeletedAt = nil

        // Undo optimistic tracking: remove from deletes, add back as optimistic item
        removeOptimisticDelete(item.id)
        recordOptimistic(item)

        // Re-insert at the correct position by createdAt
        let insertIndex = roll.items.firstIndex { $0.createdAt > item.createdAt } ?? roll.items.endIndex
        roll.items.insert(item, at: insertIndex)

        // Update roll snapshot caches
        roll.snapshot.exposureCount = roll.items.count
        roll.snapshot.lastExposureDate = roll.items.last(where: { $0.hasRealCreatedAt })?.createdAt

        // Update camera snapshot caches
        if let camera = _openCamera {
            camera.snapshot.totalExposureCount += 1
            if camera.activeRoll?.id == roll.id {
                camera.snapshot.activeRoll = roll.snapshot
            }
            camera.snapshot.lastUsedDate = camera.rolls.compactMap { $0.snapshot.lastExposureDate ?? ($0.snapshot.exposureCount > 0 ? $0.snapshot.createdAt : nil) }.max()
        }

        publishSnapshots()
        persistOpenState()

        // Unmark in the store
        let itemID = item.id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.unmarkItemPendingDeletion(id: itemID)
        }
    }

    /// Move an exposure to a different roll.
    func moveItem(_ item: LogItemSnapshot, toRollID: UUID) {
        clearUndoState()
        guard let targetRoll = roll(toRollID) else {
            debugLog("moveItem: target roll \(toRollID) not found")
            return
        }
        let sourceCamera = _openCamera
        let sourceRoll = _openRoll

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

        // Add to target roll
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
            _openCamera = targetCamera
        }
        _openRoll = targetRoll

        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.moveItem(id: item.id, toRollID: toRollID)
        }
    }

    /// Move a placeholder to just before the target item.
    func movePlaceholder(_ item: LogItemSnapshot, before target: LogItemSnapshot) {
        guard let roll = _openRoll, item.exposureType.isReorderable, item.id != target.id else { return }
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
        guard let roll = _openRoll, item.exposureType.isReorderable, item.id != target.id else { return }
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
        guard let roll = _openRoll, item.exposureType.isReorderable else { return }
        let others = roll.items.filter { $0.id != item.id }
        let newTimestamp = (others.last?.createdAt ?? Date()).addingTimeInterval(1)
        applyPlaceholderMove(id: item.id, newTimestamp: newTimestamp)
    }

    /// Shared: update local state and persist a placeholder move.
    private func applyPlaceholderMove(id: UUID, newTimestamp: Date) {
        guard let roll = _openRoll else {
            debugLog("applyPlaceholderMove: no open roll");
            return
        }
        if let i = roll.items.firstIndex(where: { $0.id == id }) {
            roll.items[i].createdAt = newTimestamp
            recordOptimistic(roll.items[i])
            roll.items.sort { $0.createdAt < $1.createdAt }
        }
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.movePlaceholder(id: id, newTimestamp: newTimestamp)
        }
    }

    func cycleExtraExposures() {
        playHaptic(.cycleExtraExposures)
        guard let roll = _openRoll else {
            debugLog("cycleExtraExposures: no open roll");
            return
        }
        let maxExtra = min(4, roll.items.count)
        let next = roll.snapshot.extraExposures + 1
        roll.snapshot.extraExposures = next > maxExtra ? 0 : next
        roll.snapshot.totalCapacity = roll.snapshot.capacity + roll.snapshot.extraExposures
        // Update camera snapshot if this is the active roll
        if let camera = _openCamera, camera.activeRoll?.id == roll.id {
            camera.snapshot.activeRoll = roll.snapshot
        }
        publishSnapshots()
        persistOpenState()
        let count = roll.snapshot.extraExposures
        let rollID = roll.id
        Task.detached(priority: .medium) { [weak self] in
            guard let self else { return }
            let store = await self.store
            await store.setExtraExposures(rollID: rollID, count: count)
        }
    }
}
