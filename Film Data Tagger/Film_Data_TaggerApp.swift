//
//  Film_Data_TaggerApp.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

@main
struct Film_Data_TaggerApp: App {
    @State private var viewModel: FilmLogViewModel

    init() {
        _viewModel = State(initialValue: FilmLogViewModel())
    }

    var body: some Scene {
        // Note: scenePhase observation is on ContentView, not here. Reading
        // @Environment(\.scenePhase) at the App level causes App.body to
        // re-evaluate on every scene phase transition during launch
        // (.background → .inactive → .active), which reconstructs
        // ContentView and triggers extra view hierarchy churn. ContentView
        // can observe scenePhase the same way without the extra cost,
        // because re-evaluating ContentView's body doesn't re-init it.
        WindowGroup {
            ContentView(viewModel: viewModel)
                .environment(viewModel)
        }
    }
}
