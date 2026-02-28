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
//    @Query private var cameras: [Camera]
//    @Query private var instantFilmGroups: [InstantFilmGroup]
//
//    @State private var path = NavigationPath()
//    @State private var showSheet = false
//    @State private var showNewRoll = false
//    @State private var isOnExposureList = false
//    @State private var isNearBottomVar = 0 // 0: initial state. 1: is not near bottom. 2: is near bottom
//    @State private var scrollToBottom: (() -> Void)?
//
//    private var isNearBottom: Bool {
//        isNearBottomVar != 1
//    }
//
//    private var logItems: [LogItem] {
//        viewModel.logItems
//    }

    var body: some View {
        NavigationStack {
            CameraListView(
                viewModel: viewModel,
                onNavigateToCamera: { id in

                }
            )
        }.preferredColorScheme(.dark)
        
        /*
        Group {
            NavigationStack(path: $path) {
                CameraListView(
                        viewModel: viewModel,
                        onNavigateToCamera: { id in
                            path.append(id)
                        }
                    )
                    .navigationDestination(for: UUID.self) { id in
                        if let camera = cameras.first(where: { $0.id == id }) {
                            RollListView(
                                camera: camera,
                                viewModel: viewModel,
                                onRollSelected: { _ in
                                    path.append(ExposureMarker())
                                }
                            )
                        } else if let group = instantFilmGroups.first(where: { $0.id == id }) {
                            exposureListScreen(viewModel: viewModel)
                                .onAppear {
                                    viewModel.switchToInstantFilmGroup(group)
                                    isOnExposureList = true
                                }
                                .onDisappear {
                                    isOnExposureList = false
                                    isNearBottomVar = 0
                                }
                        }
                    }
                    .navigationDestination(for: ExposureMarker.self) { _ in
                        exposureListScreen(viewModel: viewModel)
                            .onAppear {
                                isOnExposureList = true
                            }
                            .onDisappear {
                                isOnExposureList = false
                                isNearBottomVar = 0
                            }
                    }
                }
                .sheet(isPresented: $showSheet) {
                    CaptureSheet(
                        viewModel: viewModel,
                        frameCount: logItems.count + 1,
                        rollCapacity: viewModel.rollCapacity,
                        lastCaptureDate: logItems.last(where: { $0.hasRealCreatedAt })?.createdAt
                    )
                    .sheet(isPresented: $showNewRoll) {
                        if let camera = viewModel.openCamera {
                            RollFormSheet(viewModel: viewModel, camera: camera)
                        }
                    }
                }
                .sheetFloatingView(offset: 20, height: 48, compensationPoints: [
                    (sheetHeight: CaptureSheet.compactScaledHeight, compensation: -2),
                    (sheetHeight: CaptureSheet.fullScaledHeight, compensation: 4),
                ]) {
                    if showSheet {
                        if viewModel.openRoll != nil {
                            FinishRollButton(isNearBottom: isNearBottom, action: {
                                if isNearBottom {
                                    showNewRoll = true
                                    playHaptic(.newRollOrCamera)
                                } else {
                                    scrollToBottom?()
                                }
                            })
                            .animation(.easeInOut(duration: 0.25), value: isNearBottomVar)
                        } else if viewModel.openCamera != nil {
                            FinishRollButton(icon: "plus", text: "New roll", isNearBottom: false, action: {
                                showNewRoll = true
                                playHaptic(.newRollOrCamera)
                            })
                        } else {
                            EmptyView()
                        }
                    } else {
                        EmptyView()
                    }
                }
                .onChange(of: isOnExposureList) { _, showing in
                    if showing && !showSheet {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { showSheet = true }
                    } else if !showing && showSheet {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { showSheet = false }
                    }
                }
        }
        .onAppear {
            restoreNavigationPath(viewModel)
        }
        .preferredColorScheme(.dark)
         */
    }
    
    /*
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
}

#Preview {
    let container = PreviewSampleData.makeContainer()
    let viewModel = FilmLogViewModel(modelContext: container.mainContext)
    ContentView(viewModel: viewModel)
        .modelContainer(container)
}
