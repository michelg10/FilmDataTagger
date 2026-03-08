//
//  Film_Data_TaggerApp.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

enum SharedModelContainer {
    @MainActor
    static let shared: ModelContainer = {
        let schema = Schema([
            Camera.self,
            Roll.self,
            LogItem.self,
            InstantFilmGroup.self,
            InstantFilmCamera.self,
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

@main
struct Film_Data_TaggerApp: App {
    var sharedModelContainer: ModelContainer { SharedModelContainer.shared }

    @State private var viewModel: FilmLogViewModel

    init() {
        let vm = FilmLogViewModel(modelContext: SharedModelContainer.shared.mainContext)
        vm.setup()
        _viewModel = State(initialValue: vm)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.geocodeUngeocodedItems()
            }
        }
    }
}
