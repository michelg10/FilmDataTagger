//
//  Film_Data_TaggerApp.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

enum SharedDataStore {
    /// Created off-main to satisfy DataStore's init assertion. The container
    /// is built inline here too — the main app no longer exposes a shared
    /// container singleton, since no SwiftUI view consumes one (no @Query, no
    /// @Environment(\.modelContext)). The CaptureIntent process owns its own
    /// container in CaptureIntent.swift.
    @MainActor
    static let shared: DataStore = {
        var store: DataStore!
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue(label: "DataStore.init", qos: .userInitiated).async {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            let container: ModelContainer
            do {
                container = try ModelContainer(
                    for: schema,
                    migrationPlan: FilmDataTaggerMigrationPlan.self,
                    configurations: [config]
                )
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
            store = DataStore(modelContainer: container)
            semaphore.signal()
        }
        semaphore.wait()
        return store
    }()
}

@main
struct Film_Data_TaggerApp: App {
    @State private var viewModel: FilmLogViewModel

    init() {
        let store = SharedDataStore.shared
        let vm = FilmLogViewModel(store: store)
        vm.setup()
        _viewModel = State(initialValue: vm)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.onForeground()
            } else if phase == .background {
                viewModel.onBackground()
            }
        }
    }
}
