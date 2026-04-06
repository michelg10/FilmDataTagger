//
//  ExposureScreen.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI

struct FinishRollButton: View {
    let createRollUponFinish: Bool
    private var icon: String {
        createRollUponFinish
            ? "plus.arrow.trianglehead.counterclockwise"
            : "checkmark.arrow.trianglehead.counterclockwise"
    }
    let text: String = "Finish roll"
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
    let isActiveRoll: Bool
    let hasItems: Bool
    let rollCapacity: Int
    let itemCount: Int
    let extraExposures: Int
    let onFinishRoll: () -> Void
    let onUnloadRoll: () -> Void
    private var settings: AppSettings { .shared }

    private var isNearEndOfRoll: Bool {
        rollCapacity - itemCount + extraExposures <= 4
    }

    private var shouldShow: Bool {
        guard hasRoll && hasItems else { return false }
        
        // if the scroll state is not near bottom, always show the button (it's a scroll to bottom button)
        guard scrollState.isNearBottom else {
            return true
        }
        
        // now the button is guaranteed to be a "finish roll" button
        if isActiveRoll {
            if settings.hideFinishUntilLastShot {
                return isNearEndOfRoll
            }
            return true
        }
        // Inactive rolls: don't show
        return false
    }

    var body: some View {
        Group {
            if shouldShow {
                FinishRollButton(
                    createRollUponFinish: settings.createRollUponFinish,
                    isNearBottom: isActiveRoll && scrollState.isNearBottom,
                    action: {
                        if isActiveRoll && scrollState.isNearBottom {
                            playHaptic(.newRollOrCamera)
                            if settings.createRollUponFinish {
                                onFinishRoll()
                            } else {
                                onUnloadRoll()
                            }
                        } else {
                            scrollState.scrollToBottom?()
                        }
                    }
                )
                .transition(.blurReplace.combined(with: .scale(0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: scrollState.isNearBottom)
        .animation(.easeInOut(duration: 0.2), value: shouldShow)
    }
}

struct ExposureScreen: View {
    let viewModel: any ExposuresViewModel
    let menuContext: any ExposureMenuContext
    var onCameraSwitched: ((UUID) -> Void)? = nil
    var onCreateRoll: ((UUID, String, Int) -> UUID?)? = nil
    var onEditRoll: ((UUID, String, Int) -> Void)? = nil

    @State private var newRollCameraID: UUID?
    @State private var scrollState = ExposureScrollState()
    @State private var showInactiveRollWarning = false

    private var logItems: [LogItemSnapshot] { viewModel.openRollItems }

    var body: some View {
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel.openCameraSnapshot?.name ?? "No camera selected",
                filmStock: viewModel.openRollSnapshot?.filmStock
                    ?? (viewModel.openCameraSnapshot != nil ? "No roll selected" : ""),
                extraExposures: viewModel.openRollSnapshot?.extraExposures ?? 0,
                scrollContextID: viewModel.openRollSnapshot?.id ?? viewModel.openCameraSnapshot?.id,
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
                menuContext: menuContext,
                onCameraSwitched: onCameraSwitched
            )
            let captureSheetRectangle = UnevenRoundedRectangle(
                topLeadingRadius: 35, bottomLeadingRadius: screenCornerRadius - 8, bottomTrailingRadius: screenCornerRadius - 8, topTrailingRadius: 35, style: .continuous)

            CaptureSheet(
                camera: viewModel.camera,
                locationService: viewModel.locationService,
                roll: viewModel.openRollSnapshot,
                onCapture: {
                    if viewModel.openRollSnapshot?.isActive == false {
                        showInactiveRollWarning = true
                    } else {
                        playHaptic(.capture)
                        await viewModel.logExposure()
                    }
                },
                onAddPlaceholder: { viewModel.logPlaceholder() }
            )
            .clipShape(captureSheetRectangle)
            .glassEffectCompat(in: captureSheetRectangle)
            .overlay(alignment: .top) {
                FinishRollOverlay(
                    scrollState: scrollState,
                    hasRoll: viewModel.openRollSnapshot != nil,
                    isActiveRoll: viewModel.openRollSnapshot?.isActive ?? false,
                    hasItems: !logItems.isEmpty,
                    rollCapacity: viewModel.openRollSnapshot?.totalCapacity ?? 0,
                    itemCount: logItems.count,
                    extraExposures: viewModel.openRollSnapshot?.extraExposures ?? 0,
                    onFinishRoll: {
                        if let id = viewModel.openCameraSnapshot?.id {
                            newRollCameraID = id
                        }
                    },
                    onUnloadRoll: {
                        viewModel.unloadRoll()
                    }
                )
                .frame(maxWidth: .infinity)
                .offset(y: -48 - 20) // button height + spacing
            }
            .padding([.bottom, .leading, .trailing], 8)
            .animation(.easeInOut(duration: 0.25), value: logItems.isEmpty)
        }.ignoresSafeArea()
        .onChange(of: viewModel.openRollSnapshot?.id) {
            scrollState.nearBottomRaw = 0
        }
        .onAppear { viewModel.camera.ensureRunning() }
        .onDisappear { viewModel.camera.scheduleStop() }
        .sheet(item: $newRollCameraID) { cameraID in
            RollFormSheet(
                cameraID: cameraID,
                defaultFilmStock: viewModel.openRollSnapshot?.filmStock,
                defaultCapacity: viewModel.openRollSnapshot?.capacity,
                allowSubmitWithPlaceholder: true,
                onCreateRoll: onCreateRoll,
                onEditRoll: onEditRoll,
                formIsAboveAnotherSheet: true
            )
        }
        .alert("Roll finished", isPresented: $showInactiveRollWarning) {
            Button("Log") {
                playHaptic(.capture)
                Task(priority: .userInitiated) {
                    await viewModel.logExposure()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let activeRollName = viewModel.openCameraSnapshot?.activeRoll?.filmStock {
                Text("Are you sure you want to log an exposure? This will replace \"\(activeRollName)\" as your loaded roll.")
            } else {
                Text("Are you sure you want to log an exposure? This will make \"\(viewModel.openRollSnapshot?.filmStock ?? "")\" your loaded roll.")
            }
        }
    }
}
