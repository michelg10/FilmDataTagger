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

    private var showEyeSlash: Bool {
        !referencePhotosEnabled || cameraUnavailable || permissionDenied
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: showEyeSlash ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(Color.white)
                .frame(width: 25, height: 19)
                .opacity(0.8)
                .padding(.trailing, 15)
            if lastCaptureDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    CompactInfoRow(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 16, weight: .semibold, design: .default)),
                        text: formatElapsed(from: lastCaptureDate, now: context.date) ?? ""
                    )
                }.padding(.trailing, 13)
            }
            CompactInfoRow(
                icon: Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold, design: .default)),
                text: currentPlaceName ?? "Locating..."
            )
        }.padding(.horizontal, 27)
        .padding(.bottom, 15)
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
                Text("\(frameCount) / \(rollCapacity) •")
                    .opacity(0.46)
                Text(" Capture")
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
        .padding(.bottom, 34)
    }
}

// MARK: - CaptureSheet

struct CaptureSheet: View {
    private static let referencePhotoSize = (143.0 / 347.0) * (UIScreen.main.bounds.width - 2 * (15 + 8))
    static let compactScaledHeight: CGFloat = 147 * sheetScaleCompensationFactor
    static let fullScaledHeight: CGFloat = (110 + 25 + referencePhotoSize) * sheetScaleCompensationFactor
    
    static let compactDetent: PresentationDetent = .height(CGFloat(compactScaledHeight - bottomSafeAreaInset))
    static let fullDetent: PresentationDetent = .height(fullScaledHeight - bottomSafeAreaInset)

    var viewModel: FilmLogViewModel
    var frameCount: Int = 0
    var rollCapacity: Int
    var lastCaptureDate: Date?

    @State private var selectedDetent: PresentationDetent = fullDetent

    var body: some View {
        let isCompact = selectedDetent == CaptureSheet.compactDetent
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            CaptureSheetFullContent(
                viewModel: viewModel,
                lastCaptureDate: lastCaptureDate,
                referencePhotoSize: Self.referencePhotoSize
            )
            .frame(maxHeight: isCompact ? 0 : nil)
            .opacity(isCompact ? 0 : 1)

            CaptureSheetCompactContent(
                referencePhotosEnabled: viewModel.referencePhotosEnabled,
                cameraUnavailable: viewModel.cameraManager.cameraUnavailable,
                permissionDenied: viewModel.cameraManager.permissionDenied,
                currentPlaceName: viewModel.currentPlaceName,
                lastCaptureDate: lastCaptureDate
            )
            .frame(maxHeight: isCompact ? nil : 0)
            .opacity(isCompact ? 1 : 0)

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

        }.animation(.easeOut(duration: 0.15), value: selectedDetent)
        .onChange(of: selectedDetent) {
            playHaptic(.sheetDetentChange)
        }
        .background(SheetDragDisabler())
        .padding(.horizontal, 8)
        .ignoresSafeArea()
        .sheetContentClip(cornerRadius: 35)
        .presentationDetents([CaptureSheet.compactDetent, CaptureSheet.fullDetent], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .presentationBackgroundInteraction(.enabled)
        .sheetScaleFix()
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
                , rollCapacity: 36
            )
        }
}
