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
    let viewModel: FilmLogViewModel
    var onCameraSwitched: ((UUID) -> Void)? = nil

    @State private var newRollCameraID: UUID?
    @State private var scrollState = ExposureScrollState()

    private var logItems: [LogItemSnapshot] { viewModel.openRoll?.items ?? [] }

    var body: some View {
        ZStack(alignment: .bottom) {
            ExposureListView(
                logItems: logItems,
                cameraName: viewModel.openCamera?.name ?? "No camera selected",
                cameraID: viewModel.openCamera?.id,
                filmStock: viewModel.openRoll?.snapshot.filmStock
                    ?? (viewModel.openCamera != nil ? "No roll selected" : ""),
                hasRoll: viewModel.openRoll != nil,
                extraExposures: viewModel.openRoll?.snapshot.extraExposures ?? 0,
                scrollContextID: viewModel.openRoll?.id ?? viewModel.openCamera?.id,
                onDelete: { viewModel.deleteItem($0) },
                onMoveToRoll: { item, rollID in
                    let previousCameraID = viewModel.openCamera?.id
                    viewModel.moveItem(item, toRollID: rollID)
                    // If moveItem switched to a different camera, rebuild the nav path
                    if let newCameraID = viewModel.openCamera?.id, newCameraID != previousCameraID {
                        onCameraSwitched?(newCameraID)
                    }
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
                cameras: viewModel.cameras.map(\.snapshot),
                currentCameraID: viewModel.openCamera?.id,
                currentRollID: viewModel.openRoll?.id,
                currentRolls: viewModel.openCamera?.rolls.map(\.snapshot) ?? [],
                onCameraSelected: { cameraID in
                    viewModel.switchToCameraActiveRoll(cameraID)
                    onCameraSwitched?(cameraID)
                }
            )
            let captureSheetRectangle = UnevenRoundedRectangle(
                topLeadingRadius: 35, bottomLeadingRadius: screenCornerRadius - 8, bottomTrailingRadius: screenCornerRadius - 8, topTrailingRadius: 35, style: .continuous)

            CaptureSheet(
                camera: viewModel.camera,
                locationService: viewModel.locationService,
                roll: viewModel.openRoll,
                onCapture: { await viewModel.logExposure() },
                onAddPlaceholder: { viewModel.logPlaceholder() }
            )
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
        .onAppear { viewModel.camera.ensureRunning() }
        .onDisappear { viewModel.camera.scheduleStop() }
        .sheet(item: $newRollCameraID) { cameraID in
            RollFormSheet(
                cameraID: cameraID,
                defaultFilmStock: viewModel.openRoll?.snapshot.filmStock,
                defaultCapacity: viewModel.openRoll?.snapshot.capacity,
                allowSubmitWithPlaceholder: true,
                onCreateRoll: { viewModel.createRoll(cameraID: $0, filmStock: $1, capacity: $2) },
                onEditRoll: { viewModel.editRoll(id: $0, filmStock: $1, capacity: $2) },
                formIsAboveAnotherSheet: true
            )
        }
    }
}
