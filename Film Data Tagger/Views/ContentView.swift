//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// Navigation marker for pushing to the exposure list screen.
private struct ExposureMarker: Hashable {}

let bottomGradientOpacity: Double = 0.4

// MARK: - Content View

struct ContentView: View {
    let viewModel: FilmLogViewModel

    private var cameras: [CameraSnapshot] { viewModel.cameraList }

    @State private var path: NavigationPath
    @State private var showNewCamera = false
    @State private var newRollCameraID: UUID?
    @State private var pendingCameraNavigation: UUID?
    @State private var pendingRollNavigation = false
    @State private var selectedCameraID: UUID?
    @State private var showSettings = false

    init(viewModel: FilmLogViewModel) {
        self.viewModel = viewModel
        var initialPath = NavigationPath()
        var initialCameraID: UUID?
        if viewModel.openRollSnapshot != nil, let camera = viewModel.openCameraSnapshot {
            initialPath.append(camera.id)
            initialPath.append(ExposureMarker())
            initialCameraID = camera.id
        } else if let camera = viewModel.openCameraSnapshot {
            initialPath.append(camera.id)
            initialCameraID = camera.id
        }
        _path = State(initialValue: initialPath)
        _selectedCameraID = State(initialValue: initialCameraID)
    }

    // Path depth: 0 = camera list, 1 = roll list, 2 = exposure screen
    private var isOnExposureList: Bool { path.count >= 2 }
    private var isOnRollList: Bool { path.count == 1 }

    private var addButtonLabel: String {
        isOnRollList ? "Roll" : "Camera"
    }

    var body: some View {
        NavigationStack(path: $path) {
            CameraListView(viewModel: viewModel, onCameraSelected: { id in
                    guard path.isEmpty else { return }
                    selectedCameraID = id
                    viewModel.navigateToCamera(id)
                    path.append(id)
                })
                .navigationDestination(for: UUID.self) { id in
                    if cameras.contains(where: { $0.id == id }) {
                        RollListView(
                            viewModel: viewModel,
                            onRollSelected: { _ in
                                guard !isOnExposureList else { return }
                                path.append(ExposureMarker())
                            }
                        )
                    }
                }
                .navigationDestination(for: ExposureMarker.self) { _ in
                    ExposureScreen(
                        viewModel: viewModel,
                        menuContext: viewModel,
                        onCameraSwitched: { cameraID in
                            var newPath = NavigationPath()
                            newPath.append(cameraID)
                            newPath.append(ExposureMarker())
                            path = newPath
                            selectedCameraID = cameraID
                        },
                        onCreateRoll: { viewModel.createRoll(cameraID: $0, filmStock: $1, capacity: $2) },
                        onEditRoll: { viewModel.editRoll(id: $0, filmStock: $1, capacity: $2) }
                    )
                }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                if !isOnExposureList {
                    // Add button
                    Button {
                        playHaptic(.newRollOrCamera)
                        if isOnRollList, let cameraID = selectedCameraID ?? viewModel.openCameraSnapshot?.id {
                            newRollCameraID = cameraID
                        } else if !isOnRollList {
                            showNewCamera = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold, design: .default))
                                .padding(.leading, 18)
                            Text(addButtonLabel)
                                .font(.system(size: 20, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .padding(.trailing, 24)
                                .id("bottom-leading-button-\(addButtonLabel)")
                                .transition(.blurReplace)
                        }.foregroundStyle(Color.white.opacity(0.95))
                        .frame(height: 60)
                        .contentShape(Rectangle())
                    }
                    .glassEffectCompat(in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 16.4)
                    .buttonStyle(.plain)
                    .transition(.blurReplace.combined(with: .scale(0.9)))
                }

                Spacer(minLength: 0)

                if !isOnExposureList {
                    // Settings button
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundStyle(Color.white.opacity(0.95))
                            .frame(width: 60, height: 60)
                            .contentShape(Rectangle())
                    }
                    .glassEffectCompat(in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 16.4)
                    .buttonStyle(.plain)
                    .transition(.blurReplace.combined(with: .scale(0.9)))
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal, 28)
            .offset(y: 6)
            .animation(.easeInOut(duration: 0.25), value: isOnExposureList)
            .animation(.easeInOut(duration: 0.25), value: isOnRollList)
        }
        .sheet(isPresented: $showNewCamera, onDismiss: {
            if let id = pendingCameraNavigation {
                pendingCameraNavigation = nil
                selectedCameraID = id
                viewModel.navigateToCamera(id)
                path.append(id)
            }
        }) {
            NewCameraSheet(
                onCameraCreated: { id in pendingCameraNavigation = id },
                onCreateCamera: { viewModel.createCamera(name: $0) }
            )
        }
        .sheet(item: $newRollCameraID, onDismiss: {
            if pendingRollNavigation {
                pendingRollNavigation = false
                path.append(ExposureMarker())
            }
        }) { cameraID in
            let referenceRoll = viewModel.openCameraRolls?.activeRoll ?? viewModel.openCameraRolls?.pastRolls.first
            RollFormSheet(
                cameraID: cameraID,
                defaultFilmStock: referenceRoll?.filmStock,
                defaultCapacity: referenceRoll?.capacity,
                allowSubmitWithPlaceholder: referenceRoll != nil,
                onRollCreated: {
                    pendingRollNavigation = true
                },
                onCreateRoll: { viewModel.createRoll(cameraID: $0, filmStock: $1, capacity: $2) },
                onEditRoll: { viewModel.editRoll(id: $0, filmStock: $1, capacity: $2) }
            )
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(viewModel: viewModel)
        }
        .onChange(of: cameras.map(\.id)) {
            validateNavigationPath()
        }
        .onChange(of: viewModel.openRollSnapshot?.id) {
            validateNavigationPath()
        }
    }

    /// Pop the nav path if the selected camera or roll no longer exists (e.g. deleted via iCloud sync).
    private func validateNavigationPath() {
        guard isOnRollList || isOnExposureList else { return }
        // The first path element is a camera UUID
        guard let selectedCameraID, cameras.contains(where: { $0.id == selectedCameraID }) else {
            path = NavigationPath()
            return
        }
        // If on exposure screen, verify the open roll still exists
        if isOnExposureList, viewModel.openRollSnapshot == nil {
            var newPath = NavigationPath()
            newPath.append(selectedCameraID)
            path = newPath
        }
    }
}

#Preview {
    let container = PreviewSampleData.makeContainer()
    let viewModel = FilmLogViewModel(store: PreviewSampleData.makeStore(container: container))
    ContentView(viewModel: viewModel)
        .modelContainer(container)
}
