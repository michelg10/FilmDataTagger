//
//  LocationPage.swift
//  Film Data Tagger
//

import SwiftUI
import CoreLocation

struct LocationPage: View {
    @Bindable private var settings = AppSettings.shared
    @State private var authStatus: CLAuthorizationStatus = .notDetermined
    @State private var accuracyAuth: CLAccuracyAuthorization = .fullAccuracy

    private var locationState: LocationState {
        switch authStatus {
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .notDetermined: .notSetUp
        default: .notAllowed
        }
    }

    enum LocationState {
        case notSetUp
        case notAllowed
        case allowed
    }

    var body: some View {
        SettingsDetailPage(title: "Location") {
            SettingsSection(header: nil, caption: { locationCaptionView }) {
                SettingsHeroRow(
                    icon: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: 0x566AFF))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 15)
                                        .inset(by: 1)
                                        .stroke(Color(hex: 0x93A0FF), lineWidth: 2)
                                }
                            Image(systemName: "location.fill")
                                .font(.system(size: 21, weight: .bold, design: .default))
                                .foregroundStyle(Color.white)
                        }
                    },
                    title: "Location capture",
                    subtitle: "Remember where you shot. Location is recorded automatically with each Capture.",
                    isStandaloneSection: false
                )
                SettingsSeparator()
                SettingsRow(text: "Record location") {
                    switch locationState {
                    case .notSetUp:
                        Text("Set up...")
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.6))
                    case .notAllowed:
                        Text("Not allowed")
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .foregroundStyle(Color.white.opacity(0.6))
                    case .allowed:
                        Toggle("Enable location logging", isOn: $settings.locationEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
            if locationState == .allowed {
                SettingsSection(header: "Accuracy", caption: settings.locationAccuracy.caption) {
                    ForEach(LocationAccuracy.allCases, id: \.self) { option in
                        if option != .low { SettingsSeparator() }
                        SettingsOptionRow(text: option.label, value: option, selection: $settings.locationAccuracy)
                    }
                }
            }
        }
        .onAppear { refreshAuthStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshAuthStatus()
        }
    }

    @ViewBuilder
    private var locationCaptionView: some View {
        switch locationState {
        case .notSetUp:
            SettingsCaptionText(text: "Location recording is set up from the Capture controls. Open a roll to get started.")
        case .notAllowed:
            (
                Text("To record your location, ")
                + Text("allow Sprokbook to access your location in your iPhone's Settings")
                    .foregroundStyle(Color.accentColor)
                + Text(".")
            ).foregroundStyle(Color.white.opacity(0.4))
            .font(.system(size: 13, weight: .regular, design: .default))
            .lineHeightCompat(points: 16, fallbackSpacing: 0.5)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture { openSettings() }
            .padding(.top, 12)
        case .allowed where accuracyAuth == .reducedAccuracy:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Precise location disabled")
                }.fontWeight(.bold)
                Text("Sprokbook uses precise location to tag your exposures with street-level accuracy. Your location data stays private on your iCloud account.")
                (
                    Text("Enable Precise Location in your iPhone's Settings")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.medium)
                    + Text(".")
                )
            }
            .font(.system(size: 13, weight: .regular, design: .default))
            .foregroundStyle(Color.white.opacity(0.40))
            .lineHeightCompat(points: 16, fallbackSpacing: 0.5)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture { openSettings() }
            .padding(.top, 12)
        case .allowed:
            EmptyView()
        }
    }

    private func refreshAuthStatus() {
        let manager = CLLocationManager()
        authStatus = manager.authorizationStatus
        accuracyAuth = manager.accuracyAuthorization
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        LocationPage()
    }
    .preferredColorScheme(.dark)
}
