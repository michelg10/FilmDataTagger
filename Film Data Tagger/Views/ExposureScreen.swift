//
//  ExposureScreen.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI

struct FinishRollButton: View {
    let icon: String = "checkmark.arrow.trianglehead.counterclockwise"
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
    let viewModel: any ExposuresViewModel
    let menuContext: any ExposureMenuContext
    var onCameraSwitched: ((UUID) -> Void)? = nil

    @State private var newRollCameraID: UUID?
    @State private var scrollState = ExposureScrollState()

    private var logItems: [LogItemSnapshot] { viewModel.openRollItems }

    var body: some View {
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel.openCameraSnapshot?.name ?? "No camera selected",
                cameraID: viewModel.openCameraSnapshot?.id,
                filmStock: viewModel.openRollSnapshot?.filmStock
                    ?? (viewModel.openCameraSnapshot != nil ? "No roll selected" : ""),
                hasRoll: viewModel.openRollSnapshot != nil,
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
                onCapture: { await viewModel.logExposure() },
                onAddPlaceholder: { viewModel.logPlaceholder() }
            )
            .clipShape(captureSheetRectangle)
            .glassEffectCompat(in: captureSheetRectangle)
            .overlay(alignment: .top) {
                FinishRollOverlay(
                    scrollState: scrollState,
                    hasRoll: viewModel.openRollSnapshot != nil,
                    hasItems: !logItems.isEmpty,
                    onFinishRoll: {
                        if let id = viewModel.openCameraSnapshot?.id {
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
        .onAppear { viewModel.camera.ensureRunning() }
        .onDisappear { viewModel.camera.scheduleStop() }
        .sheet(item: $newRollCameraID) { cameraID in
            RollFormSheet(
                cameraID: cameraID,
                defaultFilmStock: viewModel.openRollSnapshot?.filmStock,
                defaultCapacity: viewModel.openRollSnapshot?.capacity,
                allowSubmitWithPlaceholder: true,
                onCreateRoll: { menuContext.createRoll(cameraID: $0, filmStock: $1, capacity: $2) },
                onEditRoll: { menuContext.editRoll(id: $0, filmStock: $1, capacity: $2) },
                formIsAboveAnotherSheet: true
            )
        }
    }
}
