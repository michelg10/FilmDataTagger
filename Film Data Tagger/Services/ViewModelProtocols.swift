//
//  ViewModelProtocols.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 4/1/26.
//

import Foundation

/// Roll list display data, projected from CameraState by the VM.
struct OpenCameraRolls: Equatable {
    let activeRoll: RollSnapshot?
    let pastRolls: [RollSnapshot]
    let maxRollCapacity: Int
    let hasRolls: Bool
}

// MARK: - Camera List

@MainActor
protocol CamerasViewModel: AnyObject, Observable {
    var cameraList: [CameraSnapshot] { get }
    @discardableResult func createCamera(name: String) -> UUID
    func renameCamera(id: UUID, name: String)
    func deleteCamera(id: UUID)
    func reorderCameras(_ orderedIDs: [UUID])
}

// MARK: - Roll List

@MainActor
protocol RollsViewModel: AnyObject, Observable {
    var openCameraSnapshot: CameraSnapshot? { get }
    var openCameraRolls: OpenCameraRolls? { get }
    func switchToRoll(id: UUID)
    @discardableResult func createRoll(cameraID: UUID, filmStock: String, capacity: Int) -> UUID
    func editRoll(id: UUID, filmStock: String, capacity: Int)
    func deleteRoll(id: UUID)
}

// MARK: - Exposure Screen (slim — no cross-cutting data)

@MainActor
protocol ExposuresViewModel: AnyObject, Observable {
    var openCameraSnapshot: CameraSnapshot? { get }
    var openRollSnapshot: RollSnapshot? { get }
    var openRollItems: [LogItemSnapshot] { get }
    var camera: CameraController { get }
    var locationService: LocationService { get }
    func logExposure() async
    func logPlaceholder()
    func deleteItem(_ item: LogItemSnapshot)
    func movePlaceholder(_ item: LogItemSnapshot, before target: LogItemSnapshot)
    func movePlaceholder(_ item: LogItemSnapshot, after target: LogItemSnapshot)
    func movePlaceholderToEnd(_ item: LogItemSnapshot)
    func cycleExtraExposures()
}

// MARK: - Exposure Menus (camera switcher + move-to-roll)

@MainActor
protocol ExposureMenuContext: AnyObject, Observable {
    var cameraList: [CameraSnapshot] { get }
    var currentRollSnapshots: [RollSnapshot] { get }
    var openCameraSnapshot: CameraSnapshot? { get }
    var openRollSnapshot: RollSnapshot? { get }
    func moveItem(_ item: LogItemSnapshot, toRollID: UUID)
    func switchToCameraActiveRoll(_ cameraID: UUID)
    @discardableResult func createRoll(cameraID: UUID, filmStock: String, capacity: Int) -> UUID
    func editRoll(id: UUID, filmStock: String, capacity: Int)
}
