//
//  CaptureSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation

// MARK: - Helpers

private func formatElapsed(from date: Date?, now: Date) -> String? {
    guard let date else { return nil }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    if seconds < 60 { return "\(seconds)s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = Double(minutes) / 60.0
    if hours < 24 { return String(format: "%.1fh", hours) }
    let days = hours / 24.0
    return String(format: "%.1fd", days)
}

private struct CompactInfoRow<Icon: View>: View {
    var icon: Icon
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            icon
                .frame(width: 21, height: 25, alignment: .center)
                .opacity(0.8)
            Text(text)
                .lineLimit(1)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .opacity(0.95)
        }
    }
}

private struct FullInfoRow<Icon: View>: View {
    var icon: Icon
    var text: String
    var subtext: String
    var textSubtextPadding: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 21, height: 25, alignment: .center)
                .opacity(0.8)
            VStack(alignment: .leading, spacing: textSubtextPadding) {
                Text(text)
                    .lineLimit(2)
                    .font(.system(size: 17, weight: .semibold, design: .default))
                    .opacity(0.95)
                Text(subtext)
                    .lineLimit(1)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .opacity(0.65)
            }
        }
    }
}

// MARK: - Subviews

/// Isolated so that GPS updates only re-render the text, not the camera preview.
private struct LocationInfoRow: View {
    var viewModel: FilmLogViewModel

    var body: some View {
        FullInfoRow(
            icon: Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold, design: .default)),
            text: viewModel.currentPlaceName ?? "Locating...",
            subtext: viewModel.currentLocation.map {
                String(format: "%.4f / %.4f", $0.coordinate.latitude, $0.coordinate.longitude)
            } ?? (viewModel.currentPlaceName == "Unknown" ? "Location unavailable" : "Locating..."),
            textSubtextPadding: 3.0
        )
    }
}

private struct CaptureSheetFullContent: View {
    var viewModel: FilmLogViewModel
    var lastCaptureDate: Date?
    var referencePhotoSize: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            // reference photo
            ZStack {
                if viewModel.cameraManager.permissionDenied || viewModel.cameraManager.cameraUnavailable {
                    ZStack {
                        Rectangle()
                            .foregroundStyle(Color(hex: 0x454545))
                        VStack(spacing: 6) {
                            Image(systemName: viewModel.cameraManager.cameraUnavailable
                                  ? "camera.fill" : "hand.raised.slash.fill")
                            Text(viewModel.cameraManager.cameraUnavailable
                                 ? "no camera\navailable" : "no camera\naccess")
                                .multilineTextAlignment(.center)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .opacity(0.62)
                        .frame(width: 120)
                    }
                    .transition(.opacity)
                } else if viewModel.referencePhotosEnabled, viewModel.cameraManager.isRunning {
                    CameraPreview(previewView: viewModel.cameraManager.previewView)
                        .transition(.opacity)
                } else if viewModel.referencePhotosEnabled {
                    ZStack {
                        Color(hex: 0x454545)
                        ProgressView()
                            .tint(.white)
                    }
                    .transition(.opacity)
                } else {
                    ZStack {
                        Rectangle()
                            .foregroundStyle(Color(hex: 0x454545))
                        VStack(spacing: 6) {
                            Image(systemName: "eye.slash")
                            Text("reference photo\noff")
                                .multilineTextAlignment(.center)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .opacity(0.62)
                        .frame(width: 120)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: referencePhotoSize, height: referencePhotoSize)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: viewModel.referencePhotosEnabled)
            .animation(.easeInOut(duration: 0.25), value: viewModel.cameraManager.isRunning)
            .animation(.easeInOut(duration: 0.25), value: viewModel.cameraManager.permissionDenied)
            .onTapGesture {
                playHaptic(.viewfinderToggle)
                if viewModel.cameraManager.cameraUnavailable {
                    // No camera hardware — nothing to do
                } else if viewModel.cameraManager.permissionDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    viewModel.toggleReferencePhotos()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FullInfoRow(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 17, weight: .semibold, design: .default)),
                        text: formatElapsed(from: lastCaptureDate, now: context.date) ?? "n/a",
                        subtext: lastCaptureDate != nil ? "since last capture" : "no captures yet"
                    )
                }
                LocationInfoRow(viewModel: viewModel)
            }
        }
        .padding(.bottom, 21)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CaptureSheetCompactContent: View {
    var referencePhotosEnabled: Bool
    var cameraUnavailable: Bool
    var permissionDenied: Bool
    var currentPlaceName: String?
    var lastCaptureDate: Date?
    var onEyeTapped: (() -> Void)?

    private var showEyeSlash: Bool {
        !referencePhotosEnabled || cameraUnavailable || permissionDenied
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: showEyeSlash ? "eye.slash.fill" : "eye.fill")
                .contentTransition(.symbolEffect(.replace, options: .speed(1.5)))
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(Color.white)
                .frame(width: 25, height: 19)
                .opacity(0.8)
                .padding(.horizontal, 15)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    playHaptic(.viewfinderToggle)
                    onEyeTapped?()
                }
            if lastCaptureDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CompactInfoRow(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 16, weight: .semibold, design: .default)),
                        text: formatElapsed(from: lastCaptureDate, now: context.date) ?? ""
                    )
                }.padding(.trailing, 13)
                .padding(.vertical, 4)
            }
            CompactInfoRow(
                icon: Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold, design: .default)),
                text: currentPlaceName ?? "Locating..."
            ).padding(.trailing, 15)
            .padding(.vertical, 4)
        }.padding(.horizontal, 27 - 15)
        .padding(.bottom, 11)
    }
}

private struct CaptureButton: View {
    var hasRoll: Bool
    var frameCount: Int
    var rollCapacity: Int
    var onCapture: () -> Void
    var onAddPlaceholder: () -> Void

    var body: some View {
        PrimaryButton(enabled: hasRoll, action: {
            playHaptic(.capture)
            onCapture()
        }) {
            if hasRoll {
                HStack(spacing: 0) {
                    Text("\(frameCount) / \(rollCapacity) •")
                        .opacity(0.46)   
                    Text(" Capture")
                }
            } else {
                Text("Capture")
            }
        }
        .contextMenu {
            Button {
                onAddPlaceholder()
            } label: {
                Label("Add placeholder", systemImage: "questionmark.square.dashed")
            }
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 26)
    }
}

// MARK: - CaptureSheet

struct CaptureSheet: View {
    private static let referencePhotoSize = (143.0 / 347.0) * (UIScreen.main.bounds.width - 2 * (15 + 8))
    private static let handleAreaHeight: CGFloat = 15
    static let compactHeight: CGFloat = 147
    static let fullHeight: CGFloat = 110 + 25 + referencePhotoSize
    private static let detentAnimation = Animation.interpolatingSpring(stiffness: 360, damping: 36)

    private enum Detent {
        case compact
        case full

        var height: CGFloat {
            switch self {
            case .compact: CaptureSheet.compactHeight
            case .full: CaptureSheet.fullHeight
            }
        }
    }

    var viewModel: FilmLogViewModel

    private var frameCount: Int { viewModel.logItems.count }
    private var rollCapacity: Int { viewModel.openRoll?.totalCapacity ?? 0 }
    private var lastCaptureDate: Date? { viewModel.logItems.last?.createdAt }

    private static let captureButtonHeight: CGFloat = 63 + 26

    @State private var selectedDetent: Detent = .full
    @State private var dragStartHeight: CGFloat?
    @State private var dragHeight: CGFloat?

    private static var detentMidpoint: CGFloat {
        (compactHeight + fullHeight) / 2
    }

    private var currentHeight: CGFloat {
        dragHeight ?? selectedDetent.height
    }

    private var dragRegionHeight: CGFloat {
        max(Self.handleAreaHeight, currentHeight - Self.captureButtonHeight)
    }

    private var showsFullContent: Bool {
        currentHeight >= Self.detentMidpoint
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                let startHeight = dragStartHeight ?? currentHeight
                if dragStartHeight == nil {
                    dragStartHeight = startHeight
                }

                let proposedHeight = startHeight - value.translation.height
                dragHeight = rubberBandedHeight(for: proposedHeight)
            }
            .onEnded { value in
                let startHeight = dragStartHeight ?? currentHeight
                let projectedHeight = clampedHeight(startHeight - value.predictedEndTranslation.height)
                let targetDetent = nearestDetent(for: projectedHeight)
                settle(on: targetDetent)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 34, height: 5)
                    .padding(.top, 5)
                    .padding(.bottom, 5)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settle(on: selectedDetent == .compact ? .full : .compact)
                    }

                ZStack(alignment: .top) {
                    CaptureSheetFullContent(
                        viewModel: viewModel,
                        lastCaptureDate: lastCaptureDate,
                        referencePhotoSize: Self.referencePhotoSize
                    ).padding(.top, 10)
                    .opacity(showsFullContent ? 1 : 0)
                    .offset(y: showsFullContent ? 0 : -10)
                    .allowsHitTesting(showsFullContent)

                    CaptureSheetCompactContent(
                        referencePhotosEnabled: viewModel.referencePhotosEnabled,
                        cameraUnavailable: viewModel.cameraManager.cameraUnavailable,
                        permissionDenied: viewModel.cameraManager.permissionDenied,
                        currentPlaceName: viewModel.currentPlaceName,
                        lastCaptureDate: lastCaptureDate,
                        onEyeTapped: {
                            if viewModel.cameraManager.cameraUnavailable {
                                // No camera hardware
                            } else if viewModel.cameraManager.permissionDenied {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } else {
                                viewModel.toggleReferencePhotos()
                            }
                        }
                    )
                    .opacity(showsFullContent ? 0 : 1)
                    .offset(y: showsFullContent ? 10 : 0)
                    .allowsHitTesting(!showsFullContent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
                .animation(.easeInOut(duration: 0.18), value: showsFullContent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dragRegionHeight, alignment: .top)
            .contentShape(Rectangle())
            .simultaneousGesture(sheetDragGesture)

            CaptureButton(
                hasRoll: viewModel.openRoll != nil,
                frameCount: frameCount,
                rollCapacity: rollCapacity,
                onCapture: { Task { await viewModel.logExposure() } },
                onAddPlaceholder: {
                    playHaptic(.addPlaceholder)
                    viewModel.logPlaceholder()
                }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: currentHeight, alignment: .top)
        .clipped()
    }

    private func settle(on detent: Detent) {
        let detentDidChange = detent != selectedDetent
        dragStartHeight = nil

        withAnimation(Self.detentAnimation) {
            selectedDetent = detent
            dragHeight = nil
        }

        if detentDidChange {
            playHaptic(.sheetDetentChange)
        }
    }

    private func nearestDetent(for height: CGFloat) -> Detent {
        abs(height - Self.compactHeight) < abs(height - Self.fullHeight) ? .compact : .full
    }

    private func clampedHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, Self.compactHeight), Self.fullHeight)
    }

    private func rubberBandedHeight(for proposedHeight: CGFloat) -> CGFloat {
        if proposedHeight < Self.compactHeight {
            return Self.compactHeight - rubberBandDistance(Self.compactHeight - proposedHeight)
        }

        if proposedHeight > Self.fullHeight {
            return Self.fullHeight + rubberBandDistance(proposedHeight - Self.fullHeight)
        }

        return proposedHeight
    }

    private func rubberBandDistance(_ offset: CGFloat) -> CGFloat {
        let detentRange = max(Self.fullHeight - Self.compactHeight, 1)
        let coefficient: CGFloat = 0.55
        let progress = (offset * coefficient / detentRange) + 1

        return (1 - (1 / progress)) * detentRange
    }
}

#Preview {
    let vm = FilmLogViewModel(
        modelContext: try! ModelContainer(for: LogItem.self, Roll.self, Camera.self).mainContext
    )
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        CaptureSheet(viewModel: vm)
            .padding([.bottom, .leading, .trailing], 8)
    }
}
