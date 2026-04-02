//
//  FilmLogViewModel+Cameras.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 4/1/26.
//

import Foundation

extension FilmLogViewModel: CamerasViewModel {
    func createCamera(name: String) -> UUID {
        let id = UUID()
        let listOrder = (_cameras.map(\.snapshot.listOrder).max() ?? -1) + 1
        let createdAt = Date()
        let snapshot = CameraSnapshot(
            id: id,
            name: name,
            createdAt: createdAt,
            listOrder: listOrder,
            rollCount: 0,
            totalExposureCount: 0
        )
        _cameras.append(CameraState(snapshot: snapshot))
        publishSnapshots()
        Task.detached(priority: .medium) { [store] in
            await store.createCamera(id: id, name: name, listOrder: listOrder, createdAt: createdAt)
        }
        return id
    }

    func renameCamera(id: UUID, name: String) {
        if let target = camera(id) {
            target.snapshot.name = name
        }
        publishSnapshots()
        Task.detached(priority: .medium) { [store] in
            await store.renameCamera(id: id, name: name)
        }
    }

    func deleteCamera(id: UUID) {
        if _openCamera?.id == id {
            _openRoll = nil
            _openCamera = nil
        }
        _cameras.removeAll { $0.id == id }
        publishSnapshots()
        persistOpenState()
        Task.detached(priority: .medium) { [store] in
            await store.deleteCamera(id: id)
        }
    }

    func reorderCameras(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: _cameras.map { ($0.id, $0) })
        let movedSet = Set(orderedIDs)
        let remaining = _cameras.filter { !movedSet.contains($0.id) }
        let reordered = orderedIDs.compactMap { byID[$0] } + remaining
        for (i, camera) in reordered.enumerated() {
            camera.snapshot.listOrder = Double(i)
        }
        _cameras = reordered
        publishSnapshots()
        Task.detached(priority: .medium) { [store] in
            await store.reorderCameras(orderedIDs: orderedIDs)
        }
    }
}
