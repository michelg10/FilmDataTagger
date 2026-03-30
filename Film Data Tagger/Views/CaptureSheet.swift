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
    let icon: Icon
    let text: String

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
    let icon: Icon
    let text: String
    let subtext: String
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
    let text: String
    let subtext: String

    var body: some View {
        FullInfoRow(
            icon: Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold, design: .default)),
            text: text,
            subtext: subtext,
            textSubtextPadding: 3.0
        )
    }
}

private struct CaptureSheetFullContent: View {
    let camera: CameraController
    let lastCaptureDate: Date?
    let referencePhotoSize: CGFloat
    let locationText: String
    let locationSubtext: String

    var body: some View {
        HStack(spacing: 18) {
            // reference photo
            ZStack {
                if camera.permissionDenied || camera.unavailable {
                    ZStack {
                        Rectangle()
                            .foregroundStyle(Color(hex: 0x454545))
                        VStack(spacing: 6) {
                            Image(systemName: camera.unavailable
                                  ? "camera.fill" : "hand.raised.slash.fill")
                            Text(camera.unavailable
                                 ? "no camera\navailable" : "no camera\naccess")
                                .multilineTextAlignment(.center)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .opacity(0.62)
                        .frame(width: 120)
                    }
                    .transition(.opacity)
                } else if camera.referencePhotosEnabled, camera.isRunning {
                    CameraPreview(previewView: camera.previewView)
                        .transition(.opacity)
                } else if camera.referencePhotosEnabled {
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
            .animation(.easeInOut(duration: 0.25), value: camera.referencePhotosEnabled)
            .animation(.easeInOut(duration: 0.25), value: camera.isRunning)
            .animation(.easeInOut(duration: 0.25), value: camera.permissionDenied)
            .onTapGesture {
                playHaptic(.viewfinderToggle)
                if camera.unavailable {
                    // No camera hardware — nothing to do
                } else if camera.permissionDenied {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    camera.toggle()
                }
            }
            .accessibilityLabel(camera.referencePhotosEnabled ? "Hide camera preview" : "Show camera preview")

            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FullInfoRow(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 17, weight: .semibold, design: .default)),
                        text: formatElapsed(from: lastCaptureDate, now: context.date) ?? "n/a",
                        subtext: lastCaptureDate != nil ? "since last capture" : "no captures yet"
                    )
                }
                LocationInfoRow(text: locationText, subtext: locationSubtext)
            }
        }
        .padding(.bottom, 21)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// TODO: audit
private struct CaptureSheetCompactContent: View {
    let referencePhotosEnabled: Bool
    let cameraUnavailable: Bool
    let permissionDenied: Bool
    let locationText: String
    let lastCaptureDate: Date?
    let onEyeTapped: (() -> Void)?

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
                .accessibilityLabel("Toggle camera preview")
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
                text: locationText
            ).padding(.trailing, 15)
            .padding(.vertical, 4)
        }.padding(.horizontal, 27 - 15)
        .padding(.bottom, 11)
    }
}

// TODO: audit
private struct CaptureButton: View {
    let hasRoll: Bool
    let frameCount: Int
    let frameNumber: Int
    let onCapture: () -> Void
    let onAddPlaceholder: () -> Void

    var body: some View {
        PrimaryButton(enabled: hasRoll && frameCount < 999, action: {
            playHaptic(.capture)
            onCapture()
        }, showShadow: false) {
            if hasRoll {
                HStack(spacing: 0) {
                    Text("\(frameNumber) •")
                        .opacity(0.5)
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

// TODO: audit
struct CaptureSheet: View {
    private static let referencePhotoSize = (143.0 / 347.0) * (UIScreen.currentWidth - 2 * (15 + 8))
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

    let viewModel: FilmLogViewModel

    private var items: [LogItemSnapshot] { viewModel.openRoll?.items ?? [] }
    private var frameCount: Int { items.count }
    private var frameNumber: Int { items.count - (viewModel.openRoll?.snapshot.extraExposures ?? 0) + 1}
    private var lastCaptureDate: Date? { items.last(where: { $0.hasRealCreatedAt })?.createdAt }

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
                    .accessibilityLabel(selectedDetent == .compact ? "Expand capture details" : "Collapse capture details")

                ZStack(alignment: .top) {
                    CaptureSheetFullContent(
                        camera: viewModel.camera,
                        lastCaptureDate: lastCaptureDate,
                        referencePhotoSize: Self.referencePhotoSize,
                        locationText: viewModel.locationService.displayLocationText,
                        locationSubtext: viewModel.locationService.displayLocationSubtext
                    ).padding(.top, 10)
                    .opacity(showsFullContent ? 1 : 0)
                    .offset(y: showsFullContent ? 0 : -10)
                    .allowsHitTesting(showsFullContent)

                    CaptureSheetCompactContent(
                        referencePhotosEnabled: viewModel.camera.referencePhotosEnabled,
                        cameraUnavailable: viewModel.camera.unavailable,
                        permissionDenied: viewModel.camera.permissionDenied,
                        locationText: viewModel.locationService.displayLocationText,
                        lastCaptureDate: lastCaptureDate,
                        onEyeTapped: {
                            if viewModel.camera.unavailable {
                                // No camera hardware
                            } else if viewModel.camera.permissionDenied {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } else {
                                viewModel.camera.toggle()
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
                frameNumber: frameNumber,
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
    let container = try! ModelContainer(for: LogItem.self, Roll.self, Camera.self)
    let vm = FilmLogViewModel(store: PreviewSampleData.makeStore(container: container))
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        CaptureSheet(viewModel: vm)
            .padding([.bottom, .leading, .trailing], 8)
    }
}
