//
//  SettingsSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import SwiftUI

// MARK: - Environment

private struct DismissSheetKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    fileprivate var dismissSheet: (() -> Void)? {
        get { self[DismissSheetKey.self] }
        set { self[DismissSheetKey.self] = newValue }
    }
}

// MARK: - Reusable Components

private struct SettingsRow<Trailing: View>: View {
    var text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .padding(.leading, 20)
                .foregroundStyle(Color.white)
                .font(.system(size: 17, weight: .regular, design: .default))
            Spacer(minLength: 16)
            trailing
                .padding(.trailing, 16)
        }.frame(height: 54)
        .contentShape(Rectangle())
    }
}

private struct SettingsNavRow<Destination: View>: View {
    var text: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(text: text) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }.buttonStyle(SettingsButtonStyle())
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(hex: 0x656565) : .clear)
    }
}

private struct SettingsOptionRow<T: Equatable>: View {
    var text: String
    var value: T
    @Binding var selection: T

    var body: some View {
        Button {
            selection = value
        } label: {
            SettingsRow(text: text) {
                if selection == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }.buttonStyle(SettingsButtonStyle())
    }
}

private struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(Color.white.opacity(0.12))
            .padding(.leading, 20)
            .padding(.trailing, 12)
    }
}

private struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var caption: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .padding(.leading, 20)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 12)
            }
            VStack(spacing: 0) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .background(RoundedRectangle(cornerRadius: 26).foregroundStyle(Color(hex: 0x222222)))
            if let caption {
                Text(caption)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineHeight(.exact(points: 16))
                    .multilineTextAlignment(.leading)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
            }
        }.padding(.bottom, 36)
    }
}

private struct SettingsDetailPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }.padding(.horizontal, 16)
            .offset(y: -32)
        }
        .background(Color(hex: 0x121212))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    BackButton()
                    Spacer()
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white)
                        .padding(.top, 3)
                    Spacer()
                    DismissButton()
                }.frame(width: UIScreen.main.bounds.width - 32, height: 44, alignment: .leading)
            }
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        Button { dismissSheet?() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: Circle())
    }
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 44, height: 44)
        }
        .frame(width: 44, height: 44)
        .glassEffect(.regular.interactive(), in: Circle())
    }
}

// MARK: - Sub-Pages

private struct ReferencePhotoPage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        SettingsDetailPage(title: "Reference photo") {
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
                let available = PreferredCamera.available
                ForEach(available, id: \.self) { option in
                    if option != available.first { SettingsSeparator() }
                    SettingsOptionRow(text: option.label, value: option, selection: $settings.preferredCamera)
                }
            }
        }
    }
}

private struct LocationPage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        SettingsDetailPage(title: "Location") {
            SettingsSection {
                SettingsRow(text: "Log location") {
                    Toggle("", isOn: $settings.locationEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsSection(header: "Accuracy", caption: settings.locationAccuracy.caption) {
                ForEach(LocationAccuracy.allCases, id: \.self) { option in
                    if option != .low { SettingsSeparator() }
                    SettingsOptionRow(text: option.label, value: option, selection: $settings.locationAccuracy)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: settings.locationEnabled)
    }
}

private struct ExportPage: View {
    var body: some View {
        SettingsDetailPage(title: "Export") {
            SettingsSection {
                SettingsNavRow(text: "Export as JSON") { Text("TODO") }
                SettingsSeparator()
                SettingsNavRow(text: "Export as CSV") { Text("TODO") }
            }
        }
    }
}

private struct AboutPage: View {
    var body: some View {
        SettingsDetailPage(title: "About") {
            SettingsSection {
                SettingsRow(text: "Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .foregroundStyle(Color.white.opacity(0.7))
                        .font(.system(size: 17, weight: .medium, design: .default))
                }
            }
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    var viewModel: FilmLogViewModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @State private var showResetAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsSection(header: "Capture") {
                        SettingsNavRow(text: "Reference photo") { ReferencePhotoPage() }
                        SettingsSeparator()
                        SettingsNavRow(text: "Location") { LocationPage() }
                    }
                    SettingsSection(header: "Accessibility") {
                        SettingsRow(text: "Reduce haptics") {
                            Toggle("", isOn: $settings.reduceHaptics)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                    SettingsSection {
                        SettingsRow(text: "iCloud sync") {
                            Text("Active") // Active, Signed out, Unavailable
                                .foregroundStyle(Color.white.opacity(0.7))
                                .fontWidth(.expanded)
                                .font(.system(size: 17, weight: .medium, design: .default))
                        }
                        SettingsSeparator()
                        SettingsNavRow(text: "Export...") { ExportPage() }
                        SettingsSeparator()
                        SettingsNavRow(text: "About") { AboutPage() }
                    }
                    SettingsSection {
                        Button {
                            showResetAlert = true
                        } label: {
                            HStack(spacing: 0) {
                                Text("Reset...")
                                    .padding(.leading, 20)
                                    .foregroundStyle(.red)
                                    .font(.system(size: 17, weight: .regular, design: .default))
                                Spacer()
                            }
                            .frame(height: 54)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
                .offset(y: -38)
            }.toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        Text("Settings")
                            .font(.system(size: 22, weight: .bold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white)
                            .padding(.leading, 20)
                        Spacer()
                        DismissButton()
                    }.frame(width: UIScreen.main.bounds.width - 32, height: 44)
                }
            }
        }
        .environment(\.dismissSheet, { dismiss() })
        .background(Color(hex: 0x121212))
        .navigationBarBackButtonHidden()
        .alert("Reset all settings?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                // TODO: implement reset
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore all settings to their defaults. Your cameras, rolls, and exposures will not be affected.")
        }
    }

}
