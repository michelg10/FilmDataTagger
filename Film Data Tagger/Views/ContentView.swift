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
    let shadow1Opacity: Double = 0.36
    let shadow1Radius: Double = 24.8
    let shadow2Opacity: Double = 0.5
    let shadow2Radius: Double = 6.9

    var body: some View {
        Button {
            action()
        } label: {
            if isNearBottom {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .padding(.leading, 14)
                    Text(text)
                        .padding(.trailing, 21)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .transition(.identity)
                }.foregroundStyle(Color.white.opacity(0.95))
                .fontWidth(.expanded)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 48)
            }
        }.frame(height: 48)
        .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        .shadow(color: .black.opacity(shadow1Opacity), radius: shadow1Radius)
        .shadow(color: .black.opacity(shadow2Opacity), radius: shadow2Radius)
    }
}

/// Navigation marker for pushing to the exposure list screen.
private struct ExposureMarker: Hashable {}

struct ContentView: View {
    var viewModel: FilmLogViewModel
    @Query private var cameras: [Camera]
    @Query private var instantFilmGroups: [InstantFilmGroup]

    @State private var path = NavigationPath()
    @State private var showNewCamera = false
    @State private var showNewRoll = false
    @State private var pendingCameraNavigation: UUID?
    @State private var selectedCamera: Camera?

    private var isOnRollList: Bool { !path.isEmpty }

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
    }

    private var floatingButtons: some View {
        HStack(spacing: 0) {
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

            Spacer(minLength: 0)

            // Settings button
            Button {
                // TODO: settings
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 60, height: 60)
            }
            .glassEffect(.regular.interactive(), in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 16.4)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .offset(y: 6)
        .animation(.easeInOut(duration: 0.25), value: isOnRollList)
    }
}

/*
// MARK: - Exposure screen (to be re-enabled)

private func restoreNavigationPath(_ vm: FilmLogViewModel) {
    guard path.isEmpty else { return }
    if let group = vm.activeInstantFilmGroup {
        path.append(group.id)
    } else if let roll = vm.openRoll, let camera = roll.camera {
        path.append(camera.id)
        path.append(ExposureMarker())
    } else if let camera = vm.openCamera {
        path.append(camera.id)
    }
}

// Navigation destination for ExposureMarker:
//
//    .navigationDestination(for: ExposureMarker.self) { _ in
//        exposureListScreen(viewModel: viewModel)
//            .onAppear {
//                isOnExposureList = true
//            }
//            .onDisappear {
//                isOnExposureList = false
//                isNearBottomVar = 0
//            }
//    }

// State needed:
//    @State private var showSheet = false
//    @State private var isOnExposureList = false
//    @State private var isNearBottomVar = 0
//    @State private var scrollToBottom: (() -> Void)?
//    private var isNearBottom: Bool { isNearBottomVar != 1 }
//    private var logItems: [LogItem] { viewModel.logItems }

// CaptureSheet + FinishRollButton (on NavigationStack):
//
//    .sheet(isPresented: $showSheet) {
//        CaptureSheet(
//            viewModel: viewModel,
//            frameCount: logItems.count + 1,
//            rollCapacity: viewModel.rollCapacity,
//            lastCaptureDate: logItems.last(where: { $0.hasRealCreatedAt })?.createdAt
//        )
//        .sheet(isPresented: $showNewRoll) {
//            if let camera = viewModel.openCamera {
//                RollFormSheet(viewModel: viewModel, camera: camera)
//            }
//        }
//    }
//    .sheetFloatingView(offset: 20, height: 48, compensationPoints: [
//        (sheetHeight: CaptureSheet.compactScaledHeight, compensation: -2),
//        (sheetHeight: CaptureSheet.fullScaledHeight, compensation: 4),
//    ]) {
//        if showSheet {
//            if viewModel.openRoll != nil {
//                FinishRollButton(isNearBottom: isNearBottom, action: {
//                    if isNearBottom {
//                        showNewRoll = true
//                        playHaptic(.newRollOrCamera)
//                    } else {
//                        scrollToBottom?()
//                    }
//                })
//                .animation(.easeInOut(duration: 0.25), value: isNearBottomVar)
//            } else if viewModel.openCamera != nil {
//                FinishRollButton(icon: "plus", text: "New roll", isNearBottom: false, action: {
//                    showNewRoll = true
//                    playHaptic(.newRollOrCamera)
//                })
//            } else {
//                EmptyView()
//            }
//        } else {
//            EmptyView()
//        }
//    }
//    .onChange(of: isOnExposureList) { _, showing in
//        if showing && !showSheet {
//            var t = Transaction(); t.disablesAnimations = true
//            withTransaction(t) { showSheet = true }
//        } else if !showing && showSheet {
//            var t = Transaction(); t.disablesAnimations = true
//            withTransaction(t) { showSheet = false }
//        }
//    }

@ViewBuilder
private func exposureListScreen(viewModel: FilmLogViewModel) -> some View {
    ExposureListView(
        logItems: logItems,
        cameraName: viewModel.openCamera?.name ?? "No camera selected",
        filmStock: viewModel.openRoll?.filmStock
            ?? (viewModel.openCamera != nil ? "No roll selected" : ""),
        hasRoll: viewModel.openRoll != nil,
        scrollContextID: viewModel.openRoll?.id ?? viewModel.openCamera?.id,
        onDelete: { item in
            viewModel.deleteItem(item)
        },
        onMovePlaceholderBefore: { item, target in
            viewModel.movePlaceholder(item, before: target)
        },
        onMovePlaceholderAfter: { item, target in
            viewModel.movePlaceholder(item, after: target)
        },
        onMovePlaceholderToEnd: { item in
            viewModel.movePlaceholderToEnd(item)
        },
        onCycleExtraExposures: {
            viewModel.cycleExtraExposures()
        },
        onNearBottomChanged: {
            if $0 {
                isNearBottomVar = 2
            } else {
                guard isNearBottomVar != 0 else { return }
                isNearBottomVar = 1
            }
        },
        onScrollToBottomRegistered: { scrollToBottom = $0 }
    )
}
*/

#Preview {
    let container = PreviewSampleData.makeContainer()
    let viewModel = FilmLogViewModel(modelContext: container.mainContext)
    ContentView(viewModel: viewModel)
        .modelContainer(container)
}
