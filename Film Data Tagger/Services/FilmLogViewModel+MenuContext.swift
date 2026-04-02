//
//  FilmLogViewModel+MenuContext.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 4/1/26.
//

import Foundation

extension FilmLogViewModel: ExposureMenuContext {
    /// Project the internal tree into minimal menu entries.
    /// Called from publishSnapshots(). Diffs before assigning.
    func publishMenuEntries() {
        let newCameraID = _openCamera?.id
        if currentCameraID != newCameraID {
            currentCameraID = newCameraID
        }

        let newRollID = _openRoll?.id
        if currentRollID != newRollID {
            currentRollID = newRollID
        }

        let newMenuCameras = _cameras.map { cameraState -> MenuCameraEntry in
            let activeRoll = cameraState.activeRoll?.snapshot
            return MenuCameraEntry(
                id: cameraState.id,
                name: cameraState.snapshot.name,
                lastUsedDate: cameraState.snapshot.lastUsedDate,
                activeRollID: activeRoll?.id,
                activeRollName: activeRoll?.filmStock,
                activeRollExposureCount: activeRoll?.exposureCount ?? 0,
                activeRollExtraExposures: activeRoll?.extraExposures ?? 0
            )
        }
        if menuCameras != newMenuCameras {
            menuCameras = newMenuCameras
        }

        let newMenuRolls: [MenuRollEntry] = (_openCamera?.rolls ?? []).map { roll in
            MenuRollEntry(
                id: roll.id,
                name: roll.snapshot.filmStock,
                lastExposureDate: roll.snapshot.lastExposureDate,
                exposureCount: roll.snapshot.exposureCount,
                totalCapacity: roll.snapshot.totalCapacity
            )
        }
        if menuRolls != newMenuRolls {
            menuRolls = newMenuRolls
        }
    }
}
