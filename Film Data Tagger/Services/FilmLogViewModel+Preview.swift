//
//  FilmLogViewModel+Preview.swift
//  Film Data Tagger
//
//  Preview-only convenience init. Lives in its own file so SwiftUI preview
//  scaffolding doesn't bloat the main FilmLogViewModel.swift.
//

import Foundation

extension FilmLogViewModel {
    /// Preview-only init. Wraps the supplied store in a completed Task so
    /// previews bypass the production CloudKit container build entirely.
    convenience init(previewStore: DataStore) {
        self.init(storeTask: Task { previewStore })
    }

    /// Populate the in-memory tree directly for previews that need
    /// `openCameraRolls` / `openCameraSnapshot` (e.g. RollListView).
    func previewSetCamera(_ camera: CameraState) {
        _cameras = [camera]
        _openCamera = camera
        _openRoll = camera.activeRoll
        publishSnapshots()
    }
}
