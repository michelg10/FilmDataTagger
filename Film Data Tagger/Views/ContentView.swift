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

struct FinishRollButton: View {
    var icon: String = "checkmark.arrow.trianglehead.counterclockwise"
    var text: String = "Finish roll"
    let isNearBottom: Bool
    let action: () -> Void

    var body: some View {
        ZStack {
            Button(action: action) {
                Color.clear.frame(width: 48, height: 48)
                    .padding(.horizontal, isNearBottom ? ((158 - 48) / 2) : 0)
                    .animation(.easeInOut(duration: 0.25), value: isNearBottom)
                    .shadow(color: .black.opacity(0.36), radius: 24.8)
                    .shadow(color: .black.opacity(0.5), radius: 6.9)
                    .overlay {
                        if isNearBottom {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: icon)
                                    .font(.system(size: 17, weight: .semibold, design: .default))
                                Text(text)
                                    .lineLimit(1)
                                    .padding(.trailing, 7)
                                    .font(.system(size: 17, weight: .semibold, design: .default))
                            }.transition(.opacity)
                            .foregroundStyle(Color.white.opacity(0.95))
                            .fontWidth(.expanded)
                        } else {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 20, weight: .bold, design: .default))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .transition(.opacity)
                        }
                    }
            }.glassEffectCompat(in: Capsule(style: .continuous))
            .accessibilityLabel(isNearBottom ? text : "Scroll to bottom")
        }.frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: isNearBottom)
    }
}

/// Navigation marker for pushing to the exposure list screen.
private struct ExposureMarker: Hashable {}

// MARK: - Exposure Screen

@Observable
private class ExposureScrollState {
    var nearBottomRaw = 0 // 0: initial, 1: not near bottom, 2: near bottom
    var scrollToBottom: (() -> Void)?
    var isNearBottom: Bool { nearBottomRaw != 1 }
}

/// Isolated view so that scroll-state changes only re-render this, not ExposureListView.
private struct FinishRollOverlay: View {
    let scrollState: ExposureScrollState
    let hasRoll: Bool
    let hasItems: Bool
    let onFinishRoll: () -> Void

    var body: some View {
        if hasRoll && hasItems {
            FinishRollButton(
                isNearBottom: scrollState.isNearBottom,
                action: {
                    if scrollState.isNearBottom {
                        playHaptic(.newRollOrCamera)
                        onFinishRoll()
                    } else {
                        scrollState.scrollToBottom?()
                    }
                }
            )
            .transition(.blurReplace.combined(with: .scale(0.9)))
        }
    }
}

struct ExposureScreen: View {
    let viewModel: FilmLogViewModel
    var onCameraSwitched: ((UUID) -> Void)? = nil

    @State private var newRollCameraID: UUID?
    @State private var scrollState = ExposureScrollState()

    private var logItems: [LogItemSnapshot] { viewModel.logItems }

    var body: some View {
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel.openCamera?.name ?? "No camera selected",
                cameraID: viewModel.openCamera?.id,
                filmStock: viewModel.openRoll?.filmStock
                    ?? (viewModel.openCamera != nil ? "No roll selected" : ""),
                hasRoll: viewModel.openRoll != nil,
                extraExposures: viewModel.openRoll?.extraExposures ?? 0,
                scrollContextID: viewModel.openRoll?.id ?? viewModel.openCamera?.id,
                onDelete: { viewModel.deleteItem($0) },
                onMoveToRoll: { item, rollID in
                    viewModel.moveItem(item, toRollID: rollID)
                },
                onMovePlaceholderBefore: { viewModel.movePlaceholder($0, before: $1) },
                onMovePlaceholderAfter: { viewModel.movePlaceholder($0, after: $1) },
                onMovePlaceholderToEnd: { viewModel.movePlaceholderToEnd($0) },
                onCycleExtraExposures: { viewModel.cycleExtraExposures() },
                onNearBottomChanged: {
                    if $0 {
                        scrollState.nearBottomRaw = 2
                    } else {
                        guard scrollState.nearBottomRaw != 0 else { return }
                        scrollState.nearBottomRaw = 1
                    }
                },
                onScrollToBottomRegistered: { scrollState.scrollToBottom = $0 },
                cameras: viewModel.cameras,
                currentCameraID: viewModel.openCamera?.id,
                currentRollID: viewModel.openRoll?.id,
                currentRolls: viewModel.rolls,
                onCameraSelected: { cameraID in
                    if let camera = viewModel.cameras.first(where: { $0.id == cameraID }),
                       let rollID = camera.activeRollID {
                        viewModel.switchToRoll(id: rollID)
                        onCameraSwitched?(cameraID)
                    }
                }
            )
            let captureSheetRectangle = UnevenRoundedRectangle(
                topLeadingRadius: 35, bottomLeadingRadius: screenCornerRadius - 8, bottomTrailingRadius: screenCornerRadius - 8, topTrailingRadius: 35, style: .continuous)

            CaptureSheet(viewModel: viewModel)
            .clipShape(captureSheetRectangle)
            .glassEffectCompat(in: captureSheetRectangle)
            .overlay(alignment: .top) {
                FinishRollOverlay(
                    scrollState: scrollState,
                    hasRoll: viewModel.openRoll != nil,
                    hasItems: !logItems.isEmpty,
                    onFinishRoll: {
                        if let id = viewModel.openCamera?.id {
                            newRollCameraID = id
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                .offset(y: -48 - 20) // button height + spacing
            }
            .padding([.bottom, .leading, .trailing], 8)
            .animation(.easeInOut(duration: 0.25), value: logItems.isEmpty)
        }.ignoresSafeArea()
        .onAppear { viewModel.ensureCameraRunning() }
        .onDisappear { viewModel.scheduleCameraStop() }
        .sheet(item: $newRollCameraID) { cameraID in
            RollFormSheet(
                viewModel: viewModel,
                cameraID: cameraID,
                defaultFilmStock: viewModel.openRoll?.filmStock,
                defaultCapacity: viewModel.openRoll?.capacity,
                allowSubmitWithPlaceholder: true,
                formIsAboveAnotherSheet: true
            )
        }
    }
}

let bottomGradientOpacity: Double = 0.4

// MARK: - Content View

struct ContentView: View {
    let viewModel: FilmLogViewModel

    private var cameras: [CameraSnapshot] { viewModel.cameras }

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
        if viewModel.openRoll != nil, let camera = viewModel.openCamera {
            initialPath.append(camera.id)
            initialPath.append(ExposureMarker())
            initialCameraID = camera.id
        } else if let camera = viewModel.openCamera {
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
            CameraListView(viewModel: viewModel)
                .navigationDestination(for: UUID.self) { id in
                    if cameras.contains(where: { $0.id == id }) {
                        RollListView(
                            cameraID: id,
                            viewModel: viewModel,
                            onRollSelected: { _ in
                                path.append(ExposureMarker())
                            }
                        )
                        .onAppear {
                            selectedCameraID = id
                            viewModel.navigateToCamera(id)
                        }
                    }
                }
                .navigationDestination(for: ExposureMarker.self) { _ in
                    ExposureScreen(viewModel: viewModel) { cameraID in
                        var newPath = NavigationPath()
                        newPath.append(cameraID)
                        newPath.append(ExposureMarker())
                        path = newPath
                        selectedCameraID = cameraID
                    }
                }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 0) {
                if !isOnExposureList {
                    // Add button
                    Button {
                        playHaptic(.newRollOrCamera)
                        if isOnRollList, let cameraID = selectedCameraID ?? viewModel.openCamera?.id {
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
                path.append(id)
            }
        }) {
            NewCameraSheet(viewModel: viewModel, onCameraCreated: { id in
                pendingCameraNavigation = id
            })
        }
        .sheet(item: $newRollCameraID, onDismiss: {
            if pendingRollNavigation {
                pendingRollNavigation = false
                path.append(ExposureMarker())
            }
        }) { cameraID in
            let activeRoll = viewModel.rolls.first(where: \.isActive)
            RollFormSheet(
                viewModel: viewModel,
                cameraID: cameraID,
                defaultFilmStock: activeRoll?.filmStock,
                defaultCapacity: activeRoll?.capacity,
                allowSubmitWithPlaceholder: activeRoll != nil,
                onRollCreated: {
                    pendingRollNavigation = true
                }
            )
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(viewModel: viewModel)
        }
        .onChange(of: cameras.map(\.id)) {
            validateNavigationPath()
        }
        .onChange(of: viewModel.openRoll?.id) {
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
        if isOnExposureList, viewModel.openRoll == nil {
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
