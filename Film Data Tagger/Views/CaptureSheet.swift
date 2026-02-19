//
//  CaptureSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI
import SwiftData
import AVFoundation
import CoreHaptics
import CoreLocation

let hapticEngine: CHHapticEngine? = {
    let engine = try? CHHapticEngine()
    engine?.isAutoShutdownEnabled = true
    engine?.playsHapticsOnly = true
    return engine
}()

func playHaptic(intensity: Float, sharpness: Float) {
    guard let engine = hapticEngine else { return }
    try? engine.start()
    let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ],
        relativeTime: 0
    )
    try? engine.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
}

// MARK: - Helpers

private func formatElapsed(from date: Date?, now: Date) -> String {
    guard let date else { return "No captures yet" }
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

private struct CaptureSheetFullContent: View {
    var viewModel: FilmLogViewModel
    var lastCaptureDate: Date?

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                if viewModel.referencePhotosEnabled, viewModel.cameraManager.isRunning {
                    CameraPreview(session: viewModel.cameraManager.session)
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
                            Text("reference photo off")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .opacity(0.62)
                        .frame(width: 99)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 143, height: 143)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: viewModel.referencePhotosEnabled)
            .animation(.easeInOut(duration: 0.25), value: viewModel.cameraManager.isRunning)
            .onTapGesture {
                playHaptic(intensity: 0.53, sharpness: 0.21)
                viewModel.toggleReferencePhotos()
            }
            VStack(alignment: .leading, spacing: 10) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    FullInfoRow(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 17, weight: .semibold, design: .default)),
                        text: formatElapsed(from: lastCaptureDate, now: context.date),
                        subtext: "since last capture"
                    )
                }
                FullInfoRow(
                    icon: Image(systemName: "location.fill")
                        .font(.system(size: 17, weight: .semibold, design: .default)),
                    text: viewModel.currentPlaceName ?? "Locating...",
                    subtext: viewModel.currentLocation.map {
                        String(format: "%.4f / %.4f", $0.coordinate.latitude, $0.coordinate.longitude)
                    } ?? "",
                    textSubtextPadding: 3.0
                )
            }
        }
        .padding(.bottom, 21)
        .padding(.horizontal, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CaptureSheetCompactContent: View {
    var viewModel: FilmLogViewModel
    var lastCaptureDate: Date?

    var body: some View {
        HStack(spacing: 15) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                CompactInfoRow(
                    icon: Image(systemName: "clock.fill")
                        .font(.system(size: 16, weight: .semibold, design: .default)),
                    text: formatElapsed(from: lastCaptureDate, now: context.date)
                )
            }
            CompactInfoRow(
                icon: Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold, design: .default)),
                text: viewModel.currentPlaceName ?? "Locating..."
            )
        }.padding(.horizontal, 30)
        .padding(.bottom, 15)
    }
}

private struct CaptureButton: View {
    var frameCount: Int
    var rollCapacity: Int
    var onCapture: () -> Void

    var body: some View {
        Button {
            playHaptic(intensity: 0.36, sharpness: 0.36)
            onCapture()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Spacer(minLength: 0)
                Text("\(frameCount) / \(rollCapacity) •")
                    .opacity(0.46)
                Text(" Capture")
                Spacer(minLength: 0)
            }.foregroundStyle(Color.black)
            .font(.system(size: 22, weight: .bold, design: .default))
            .fontWidth(.expanded)
        }.frame(height: 63)
        .glassEffect(.regular.tint(.white.opacity(0.87)).interactive(), in: Capsule(style: .continuous))
        .padding(.horizontal, 15)
        .padding(.bottom, 34)
    }
}

// MARK: - CaptureSheet

struct CaptureSheet: View {
    static let iOSSheetPadding = 27
    static let compactDetent: PresentationDetent = .height(CGFloat(147 - iOSSheetPadding))
    static let fullDetent: PresentationDetent = .height(CGFloat(283 - iOSSheetPadding))

    var viewModel: FilmLogViewModel
    var isScrolling: Bool = false
    var frameCount: Int = 0
    var rollCapacity: Int = 36
    var lastCaptureDate: Date?

    @State private var selectedDetent: PresentationDetent = fullDetent

    var body: some View {
        let isCompact = selectedDetent == CaptureSheet.compactDetent
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            CaptureSheetFullContent(
                viewModel: viewModel,
                lastCaptureDate: lastCaptureDate
            )
            .frame(maxHeight: isCompact ? 0 : nil)
            .opacity(isCompact ? 0 : 1)

            CaptureSheetCompactContent(
                viewModel: viewModel,
                lastCaptureDate: lastCaptureDate
            )
            .frame(maxHeight: isCompact ? nil : 0)
            .opacity(isCompact ? 1 : 0)

            CaptureButton(
                frameCount: frameCount,
                rollCapacity: rollCapacity,
                onCapture: { Task { await viewModel.logExposure() } }
            )

        }.animation(.easeOut(duration: 0.15), value: selectedDetent)
        .background(SheetDragDisabler(isScrolling: isScrolling))
        .padding(.horizontal, 8)
        .ignoresSafeArea()
        .sheetContentClip(cornerRadius: 35)
        .presentationDetents([CaptureSheet.compactDetent, CaptureSheet.fullDetent], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .presentationBackgroundInteraction(.enabled)
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            CaptureSheet(
                viewModel: FilmLogViewModel(
                    modelContext: try! ModelContainer(for: LogItem.self, Roll.self, Camera.self).mainContext
                )
            )
        }
}
