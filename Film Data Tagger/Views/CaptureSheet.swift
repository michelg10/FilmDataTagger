//
//  CaptureSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData

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
    let textLineHeight: CGFloat = 20
    let subtextLineHeight: CGFloat = 17

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
                    .lineHeightCompat(points: textLineHeight, fallbackSpacing: 0)
                Text(subtext)
                    .lineLimit(2)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .opacity(0.65)
                    .lineHeightCompat(points: subtextLineHeight, fallbackSpacing: 0.3)
            }
        }
    }
}

// MARK: - Subviews

/// Isolated so that GPS updates only re-render the text, not the eye icon or camera preview.
private struct CompactLocationInfoRow: View {
    let locationService: LocationService

    var body: some View {
        CompactInfoRow(
            icon: Image(systemName: "location.fill")
                .font(.system(size: 15, weight: .semibold, design: .default)),
            text: locationService.needsPermission ? "Set up..." : locationService.displayLocationText
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if locationService.needsPermission {
                locationService.requestPermissionIfNeeded()
            } else if case .notAuthorized = locationService.geocodingState {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

/// Isolated so that GPS updates only re-render the text, not the camera preview.
private struct LocationInfoRow: View {
    let locationService: LocationService

    var body: some View {
        if locationService.needsPermission {
            FullInfoRow(
                icon: Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .semibold, design: .default)),
                text: "Tap to set up",
                subtext: "Allow Sprokbook to access your location",
                textSubtextPadding: 3
            )
            .contentShape(Rectangle())
            .onTapGesture {
                locationService.requestPermissionIfNeeded()
            }
        } else {
            FullInfoRow(
                icon: Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .semibold, design: .default)),
                text: locationService.displayLocationText,
                subtext: locationService.displayLocationSubtext,
                textSubtextPadding: 3
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if case .notAuthorized = locationService.geocodingState {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}

private struct PreviewPlaceholder: View {
    let icon: String
    let text: String

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(Color(hex: 0x454545))
            VStack(spacing: 6) {
                Image(systemName: icon)
                Text(text)
                    .multilineTextAlignment(.center)
                    .lineHeightCompat(points: 18, fallbackSpacing: 1.3)
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .opacity(0.62)
            .frame(width: 120)
        }
        .transition(.opacity)
    }
}

private struct ReferencePhotoPreview: View {
    let camera: CameraController
    let size: CGFloat

    private var isTappable: Bool {
        // The unavailable branch is a no-op, so don't glow for it.
        !camera.unavailable
    }

    var body: some View {
        Button {
            if camera.needsPermission {
                playHaptic(.viewfinderToggle)
                camera.requestPermissionIfNeeded()
            } else if camera.unavailable {
                // No camera hardware — nothing to do
            } else if camera.permissionDenied {
                playHaptic(.viewfinderToggle)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } else {
                camera.toggle()
            }
        } label: {
            ZStack {
                if camera.needsPermission {
                    PreviewPlaceholder(icon: "camera.fill", text: "Tap to set up")
                } else if camera.permissionDenied || camera.unavailable {
                    PreviewPlaceholder(
                        icon: camera.unavailable ? "camera.fill" : "hand.raised.slash.fill",
                        text: camera.unavailable ? "no camera\navailable" : "no camera\naccess"
                    )
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
                    PreviewPlaceholder(icon: "eye.slash", text: "reference photo\noff")
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: camera.needsPermission)
            .animation(.easeInOut(duration: 0.25), value: camera.referencePhotosEnabled)
            .animation(.easeInOut(duration: 0.25), value: camera.isRunning)
            .animation(.easeInOut(duration: 0.25), value: camera.permissionDenied)
        }
        .buttonStyle(TapGlowButtonStyle(isTappable: isTappable, cornerRadius: 20))
        .accessibilityLabel(camera.needsPermission ? "Set up reference photos" : camera.referencePhotosEnabled ? "Hide camera preview" : "Show camera preview")
    }
}

/// Custom button style that overlays a press-driven glow on top of the label.
/// Glow appears immediately on touch-down and fades out on release, matching
/// the responsiveness of standard system buttons.
private struct TapGlowButtonStyle: ButtonStyle {
    let isTappable: Bool
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if isTappable {
                    TapGlowOverlay(isPressed: configuration.isPressed, cornerRadius: cornerRadius)
                }
            }
    }
}

private struct TapGlowOverlay: View {
    let isPressed: Bool
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white)
            .opacity(isPressed ? 0.08 : 0)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            // Snap on press-down (nil animation = instant), ease back on release.
            .animation(isPressed ? nil : .easeOut(duration: 0.25), value: isPressed)
    }
}

private struct CaptureSheetFullContent: View {
    let camera: CameraController
    let locationService: LocationService
    let lastCaptureDate: Date?
    let referencePhotoSize: CGFloat

    var body: some View {
        HStack(spacing: 18) {
            ReferencePhotoPreview(camera: camera, size: referencePhotoSize)

            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FullInfoRow(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 17, weight: .semibold, design: .default)),
                        text: formatElapsed(from: lastCaptureDate, now: context.date) ?? "n/a",
                        subtext: lastCaptureDate != nil ? "since last capture" : "No captures yet",
                        textSubtextPadding: 1
                    )
                }
                LocationInfoRow(locationService: locationService)
            }
        }
        .padding(.bottom, 21)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CaptureSheetCompactContent: View {
    let camera: CameraController
    let locationService: LocationService
    let lastCaptureDate: Date?

    private let flipIndicatorHoldDuration: TimeInterval = 3.0
    private let flipIndicatorFadeDuration: TimeInterval = 0.3

    @State private var showingFlipIndicator = false
    @State private var flipIndicatorTask: Task<Void, Never>?

    private var iconName: String {
        if showingFlipIndicator {
            return AppSettings.shared.preferredCameraSide == .front
                ? "person.crop.rectangle" : "photo"
        }
        if camera.needsPermission { return "hand.raised.fill" }
        if !camera.referencePhotosEnabled || camera.unavailable || camera.permissionDenied { return "eye.slash.fill" }
        return "eye.fill"
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: iconName)
                .contentTransition(.symbolEffect(.replace, options: .speed(1.5)))
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(Color.white)
                .frame(width: 25, height: 19)
                .opacity(showingFlipIndicator ? 1.0 : 0.8)
                .onChange(of: camera.flipCount) {
                    flipIndicatorTask?.cancel()
                    showingFlipIndicator = true
                    let hold = flipIndicatorHoldDuration
                    let fade = flipIndicatorFadeDuration
                    flipIndicatorTask = Task {
                        try? await Task.sleep(for: .seconds(hold))
                        guard !Task.isCancelled else { return }
                        // .contentTransition(.symbolEffect) drives the icon swap speed,
                        // not this animation. The withAnimation is here to subtly
                        // animate the opacity value (1.0 → 0.8) on dismiss.
                        withAnimation(.easeOut(duration: fade)) {
                            showingFlipIndicator = false
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Dismiss flip indicator instantly on any tap
                    flipIndicatorTask?.cancel()
                    flipIndicatorTask = nil
                    showingFlipIndicator = false
                    if camera.needsPermission {
                        playHaptic(.viewfinderToggle)
                        camera.requestPermissionIfNeeded()
                    } else if camera.unavailable {
                        // No camera hardware
                    } else if camera.permissionDenied {
                        playHaptic(.viewfinderToggle)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        camera.toggle()
                    }
                }
                .accessibilityLabel(camera.needsPermission ? "Set up reference photos" : "Toggle camera preview")
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
            CompactLocationInfoRow(locationService: locationService)
                .padding(.trailing, 15)
                .padding(.vertical, 4)
        }.padding(.horizontal, 27 - 15)
        .padding(.bottom, 11)
    }
}

private struct CaptureButton: View, Equatable {
    let frameCount: Int
    let frameNumber: Int
    let onCapture: () -> Void
    let onCaptureAndNote: () -> Void
    let onAddPlaceholder: () -> Void
    let onAddLostFrame: () -> Void

    static func == (lhs: CaptureButton, rhs: CaptureButton) -> Bool {
        lhs.frameCount == rhs.frameCount && lhs.frameNumber == rhs.frameNumber
    }
    private var settings: AppSettings { .shared }

    var body: some View {
        PrimaryButton(enabled: frameCount < 999, action: {
            onCapture()
        }, showShadow: false) {
            HStack(spacing: 0) {
                Text("\(frameNumber) •")
                    .opacity(0.5)
                Text(" Capture")
            }
        }
        .contextMenu {
            Button {
                onCaptureAndNote()
            } label: {
                Label("Capture and note", systemImage: SFSymbol.textPadHeader)
            }
            Section {
                if settings.holdCapturePlaceholders {
                    Button {
                        playHaptic(.addPlaceholder)
                        onAddPlaceholder()
                    } label: {
                        Label("Add placeholder", systemImage: "questionmark.square.dashed")
                    }
                }
                if settings.holdCaptureLostFrames {
                    Button {
                        playHaptic(.addPlaceholder)
                        onAddLostFrame()
                    } label: {
                        Label("Add lost frame", systemImage: "xmark.square")
                    }
                }
            } 
        }
        .padding(.horizontal, 15)
        .padding(.bottom, 26)
    }
}

// MARK: - CaptureSheet

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

    let camera: CameraController
    let locationService: LocationService
    let roll: RollSnapshot?
    let onCapture: () async -> Void
    let onAddPlaceholder: () -> Void
    let onAddLostFrame: () -> Void
    @Binding var expanded: Bool

    private var frameCount: Int { roll?.exposureCount ?? 0 }
    private var frameNumber: Int { frameCount - (roll?.extraExposures ?? 0) + 1 }
    private var lastCaptureDate: Date? { roll?.lastExposureDate }

    private static let captureButtonHeight: CGFloat = 63 + 26

    private var selectedDetent: Detent { expanded ? .full : .compact }
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

    /// Continuous 0–1 progress for crossfading between compact and full content.
    private var crossfadeProgress: CGFloat {
        let lower = Self.compactHeight + 11
        let upper = Self.fullHeight - 11
        guard upper > lower else { return showsFullContent ? 1 : 0 }
        return min(max((currentHeight - lower) / (upper - lower), 0), 1)
    }

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let startHeight = dragStartHeight ?? currentHeight
                if dragStartHeight == nil {
                    dragStartHeight = startHeight
                }

                let proposedHeight = startHeight - value.translation.height
                // TODO: check for fractional rendering
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
                        camera: camera,
                        locationService: locationService,
                        lastCaptureDate: lastCaptureDate,
                        referencePhotoSize: Self.referencePhotoSize
                    ).padding(.top, 10)
                    .opacity(crossfadeProgress)
                    .offset(y: (1 - crossfadeProgress) * -25.0)
                    .allowsHitTesting(showsFullContent)

                    CaptureSheetCompactContent(
                        camera: camera,
                        locationService: locationService,
                        lastCaptureDate: lastCaptureDate
                    )
                    .opacity(1 - crossfadeProgress)
                    .offset(y: crossfadeProgress * 25.0)
                    .allowsHitTesting(!showsFullContent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .frame(height: dragRegionHeight, alignment: .top)
            .contentShape(Rectangle())
            .simultaneousGesture(sheetDragGesture)

            CaptureButton(
                frameCount: frameCount,
                frameNumber: frameNumber,
                onCapture: { Task(priority: .userInitiated) { await onCapture() } },
                onCaptureAndNote: { /* TODO: Capture and Note */ },
                onAddPlaceholder: onAddPlaceholder,
                onAddLostFrame: onAddLostFrame
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
            expanded = detent == .full
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
    let vm = FilmLogViewModel(previewStore: PreviewSampleData.makeStore(container: container))
    ZStack(alignment: .bottom) {
        Color.black.ignoresSafeArea()
        CaptureSheet(
            camera: vm.camera,
            locationService: vm.locationService,
            roll: nil,
            onCapture: {},
            onAddPlaceholder: {},
            onAddLostFrame: {},
            expanded: .constant(true)
        )
        .padding([.bottom, .leading, .trailing], 8)
    }
    .environment(vm)
}
