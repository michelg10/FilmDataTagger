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
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: FilmDataTaggerMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

enum SharedDataStore {
    /// Created off-main to satisfy DataStore's init assertion.
    @MainActor
    static let shared: DataStore = {
        let container = SharedModelContainer.shared
        var store: DataStore!
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue(label: "DataStore.init", qos: .userInitiated).async {
            store = DataStore(modelContainer: container)
            semaphore.signal()
        }
        semaphore.wait()
        return store
    }()
}

@main
struct Film_Data_TaggerApp: App {
    var sharedModelContainer: ModelContainer { SharedModelContainer.shared }

    @State private var viewModel: FilmLogViewModel

    init() {
        let store = SharedDataStore.shared
        let vm = FilmLogViewModel(modelContext: SharedModelContainer.shared.mainContext, store: store)
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
                viewModel.onForeground()
            }
        }
    }
}
