//
//  ReferencePhotoPage.swift
//  Film Data Tagger
//

import SwiftUI
import AVFoundation

struct ReferencePhotoPage: View {
    @Bindable private var settings = AppSettings.shared
    @State private var authStatus: AVAuthorizationStatus = .notDetermined

    private var cameraState: CameraState {
        switch authStatus {
        case .authorized: .allowed
        case .notDetermined: .notSetUp
        default: .notAllowed
        }
    }

    enum CameraState {
        case notSetUp
        case notAllowed
        case allowed
    }

    var body: some View {
        SettingsDetailPage(title: "Reference photo") {
            SettingsSection(header: nil, caption: { cameraCaptionView }) {
                SettingsHeroRow(
                    icon: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: 0xFF6565))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .inset(by: 1)
                                        .stroke(Color(hex: 0xFFA8A8), lineWidth: 2)
                                }
                            Image(systemName: "photo")
                                .font(.system(size: 21, weight: .bold, design: .default))
                                .foregroundStyle(Color.white)
                        }
                    },
                    title: "Reference photos",
                    subtitle: "Take a reference photo with each Capture to match scans to logged exposures.",
                    isStandaloneSection: cameraState == .allowed
                )
                if cameraState != .allowed {
                    SettingsSeparator()
                    SettingsRow(text: "Reference photos") {
                        Text(cameraState == .notSetUp ? "Set up..." : "Not allowed")
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                }
            }
            if cameraState == .allowed {
                SettingsSection(header: "Start with reference photo") {
                    ForEach(ReferencePhotoStartup.allCases, id: \.self) { option in
                        if option != .preserveLast { SettingsSeparator() }
                        SettingsOptionRow(text: option.label, value: option, selection: $settings.referencePhotoStartup)
                    }
                }
                SettingsSection(header: "Quality", caption: settings.photoQuality.caption) {
                    ForEach(PhotoQuality.allCases, id: \.self) { option in
                        if option != .low { SettingsSeparator() }
                        SettingsOptionRow(text: option.label, value: option, selection: $settings.photoQuality)
                    }
                }
                SettingsSection(header: "Preferred camera") {
                    ForEach(settings.availableCameras, id: \.self) { option in
                        if option != settings.availableCameras.first { SettingsSeparator() }
                        SettingsOptionRow(text: option.label, value: option, selection: $settings.preferredCamera)
                    }
                }
            }
        }
        .onAppear { authStatus = AVCaptureDevice.authorizationStatus(for: .video) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    @ViewBuilder
    private var cameraCaptionView: some View {
        switch cameraState {
        case .notSetUp:
            SettingsCaptionText(text: "Reference photos are set up from the Capture controls. Open a roll to get started.")
        case .notAllowed:
            (
                Text("To take reference photos, ")
                + Text("allow Sprokbook to access the camera in your iPhone’s Settings")
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.medium)
                + Text(".")
            ).foregroundStyle(Color.white.opacity(0.4))
            .font(.system(size: 13, weight: .regular, design: .default))
            .lineHeightCompat(points: 16, fallbackSpacing: 0.5)
            .multilineTextAlignment(.leading)
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .onTapGesture { openSettings() }
        case .allowed:
            EmptyView()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        ReferencePhotoPage()
    }
    .preferredColorScheme(.dark)
}
