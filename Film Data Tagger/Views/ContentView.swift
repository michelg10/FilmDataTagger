//
//  ContentView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

struct FinishRollButton: View {
    var icon: String = "checkmark.arrow.trianglehead.counterclockwise"
    var text: String = "Finish roll"
    var isNearBottom: Bool
    var action: () -> Void

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
            }.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
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
    var scrollState: ExposureScrollState
    var hasRoll: Bool
    var hasItems: Bool
    @Binding var showNewRoll: Bool

    var body: some View {
        if hasRoll && hasItems {
            FinishRollButton(
                isNearBottom: scrollState.isNearBottom,
                action: {
                    if scrollState.isNearBottom {
                        playHaptic(.newRollOrCamera)
                        showNewRoll = true
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
    var viewModel: FilmLogViewModel
    @Query private var cameras: [Camera]

    @State private var showNewRoll = false
    @State private var scrollState = ExposureScrollState()

    private var logItems: [LogItem] { viewModel.logItems }

    var body: some View {
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel.openCamera?.name ?? "No camera selected",
                filmStock: viewModel.openRoll?.filmStock
                ?? (viewModel.openCamera != nil ? "No roll selected" : ""),
                hasRoll: viewModel.openRoll != nil,
                scrollContextID: viewModel.openRoll?.id ?? viewModel.openCamera?.id,
                onDelete: { viewModel.deleteItem($0) },
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
                camerasWithActiveRolls: cameras.filter { $0.activeRoll != nil },
                onCameraSelected: { camera in
                    if let roll = camera.activeRoll {
                        viewModel.switchToRoll(roll)
                    }
                }
            )
            let screenRadius = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat ?? 50
            let captureSheetRectangle = UnevenRoundedRectangle(
                topLeadingRadius: 35, bottomLeadingRadius: screenRadius - 8, bottomTrailingRadius: screenRadius - 8, topTrailingRadius: 35, style: .continuous)

            CaptureSheet(
                viewModel: viewModel,
                frameCount: logItems.count,
                rollCapacity: viewModel.openRoll?.totalCapacity ?? 0,
                lastCaptureDate: logItems.last?.createdAt
            )
            .clipShape(captureSheetRectangle)
            .glassEffect(.regular.interactive(), in: captureSheetRectangle)
            .overlay(alignment: .top) {
                FinishRollOverlay(
                    scrollState: scrollState,
                    hasRoll: viewModel.openRoll != nil,
                    hasItems: !logItems.isEmpty,
                    showNewRoll: $showNewRoll
                )
                .frame(maxWidth: .infinity)
                .offset(y: -48 - 20) // button height + spacing
            }
            .padding([.bottom, .leading, .trailing], 8)
            .animation(.easeInOut(duration: 0.25), value: logItems.isEmpty)
        }.ignoresSafeArea()
        .sheet(isPresented: $showNewRoll) {
            if let camera = viewModel.openCamera {
                RollFormSheet(viewModel: viewModel, camera: camera)
            }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    var viewModel: FilmLogViewModel
    @Query private var cameras: [Camera]
    @Query private var instantFilmGroups: [InstantFilmGroup]

    @State private var path = NavigationPath()
    @State private var showNewCamera = false
    @State private var showNewRoll = false
    @State private var pendingCameraNavigation: UUID?
    @State private var selectedCamera: Camera?

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
                    if let camera = cameras.first(where: { $0.id == id }) {
                        RollListView(
                            camera: camera,
                            viewModel: viewModel,
                            onRollSelected: { _ in
                                path.append(ExposureMarker())
                            }
                        )
                        .onAppear { selectedCamera = camera }
                    } else if let group = instantFilmGroups.first(where: { $0.id == id }) {
                        // TODO: instant film
                        EmptyView()
                    }
                }
                .navigationDestination(for: ExposureMarker.self) { _ in
                    ExposureScreen(viewModel: viewModel)
                }
        }
        .overlay(alignment: .bottom) { floatingButtons }
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
        .sheet(isPresented: $showNewRoll) {
            if let camera = selectedCamera ?? viewModel.openCamera {
                RollFormSheet(viewModel: viewModel, camera: camera, onRollCreated: {
                    // TODO: route to the new roll
                })
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { restoreNavigationPath(viewModel) }
    }

    private var floatingButtons: some View {
        HStack(spacing: 0) {
            if !isOnExposureList {
                // Add button
                Button {
                    playHaptic(.newRollOrCamera)
                    if isOnRollList {
                        showNewRoll = true
                    } else {
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
                .glassEffect(.regular.interactive(), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 16.4)
                .buttonStyle(.plain)
                .transition(.blurReplace.combined(with: .scale(0.9)))
            }

            Spacer(minLength: 0)

            if !isOnExposureList {
                // Settings button
                Button {
                    // TODO: settings
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundStyle(Color.white.opacity(0.95))
                        .frame(width: 60, height: 60)
                        .contentShape(Rectangle())
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 16.4)
                .buttonStyle(.plain)
                .transition(.blurReplace.combined(with: .scale(0.9)))
            }
        }
        .padding(.horizontal, 28)
        .offset(y: 6)
        .animation(.easeInOut(duration: 0.25), value: isOnExposureList)
        .animation(.easeInOut(duration: 0.25), value: isOnRollList)
    }

    // MARK: - Deep link restoration (TODO: call on appear)

    private func restoreNavigationPath(_ vm: FilmLogViewModel) {
        guard path.isEmpty else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if let group = vm.activeInstantFilmGroup {
                path.append(group.id)
            } else if let roll = vm.openRoll, let camera = roll.camera {
                path.append(camera.id)
                path.append(ExposureMarker())
            } else if let camera = vm.openCamera {
                path.append(camera.id)
            }
        }
    }

}

#Preview {
    let container = PreviewSampleData.makeContainer()
    let viewModel = FilmLogViewModel(modelContext: container.mainContext)
    ContentView(viewModel: viewModel)
        .modelContainer(container)
}
