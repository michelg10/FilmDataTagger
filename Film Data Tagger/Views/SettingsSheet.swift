//
//  SettingsSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 3/7/26.
//

import SwiftUI
import SwiftData
import CloudKit

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

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
    let text: String
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
    let text: String
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

private struct SettingsActionRow: View {
    let text: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(text)
                    .padding(.leading, 20)
                    .foregroundStyle(color)
                    .font(.system(size: 17, weight: .medium, design: .default))
                Spacer(minLength: 16)
            }.frame(height: 54)
            .contentShape(Rectangle())
        }.buttonStyle(SettingsButtonStyle())
    }
}

private struct SettingsTaskRow: View {
    let text: String
    let color: Color
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(text)
                    .padding(.leading, 20)
                    .foregroundStyle(isActive ? color.opacity(0.4) : color)
                    .font(.system(size: 17, weight: .medium, design: .default))
                Spacer(minLength: 16)
                if isActive {
                    ProgressView()
                        .tint(color.opacity(0.6))
                        .padding(.trailing, 16)
                }
            }.frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsButtonStyle())
        .disabled(isActive || isDisabled)
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(hex: 0x656565) : .clear)
    }
}

private struct SettingsOptionRow<T: Equatable>: View {
    let text: String
    let value: T
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
                let lines = caption.split(separator: "\n")
                let styledText = { (text: String) in
                    Text(text)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineHeight(.exact(points: 16))
                        .multilineTextAlignment(.leading)
                }

                Group {
                    if lines.count > 1 {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(lines, id: \.self) { line in
                                styledText(String(line))
                            }
                        }
                    } else {
                        styledText(caption)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
            }
        }.padding(.bottom, 36)
    }
}

private struct SettingsHeroSection<Icon: View>: View {
    @ViewBuilder var icon: Icon
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            icon
                .frame(width: 64, height: 64)
                .padding(.bottom, 20)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .default))
                .fontWidth(.expanded)
                .padding(.bottom, 8)
            Text(subtitle)
                .font(.system(size: 17, weight: .regular, design: .default))
                .lineHeight(.exact(points: 23))
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.leading)
        }.padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).foregroundStyle(Color(hex: 0x222222)))
        .padding(.bottom, 36)
    }
}

private struct SettingsDetailPage<Content: View>: View {
    let title: String
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
                }.frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
            }
        }
    }
}

private struct SettingsFullScreenDetailPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .offset(y: -32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    }.frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
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
        .accessibilityLabel("Close")
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
        .accessibilityLabel("Back")
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
    let viewModel: FilmLogViewModel
    @State private var activeExport: ExportType?
    @State private var shareURL: URL?

    private enum ExportType { case json, csv }

    var body: some View {
        SettingsDetailPage(title: "Export") {
            SettingsHeroSection(
                icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.init(hex: 0x303030))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .inset(by: 2)
                                    .stroke(Color.init(hex: 0x787878), lineWidth: 2)
                            }
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 21, weight: .bold, design: .default))
                            .foregroundStyle(Color.white)
                    }
                },
                title: "Data export",
                subtitle: "Export your data for backup, external programs, or spreadsheet analysis."
            )
            SettingsSection(caption: "JSON is best for backup and external programs. CSV is best for spreadsheets.\nSome data, like reference photos, is not included in exports.") {
                SettingsTaskRow(text: "Export as JSON", color: .accentColor, isActive: activeExport == .json, isDisabled: activeExport != nil) {
                    guard activeExport == nil else { return }
                    activeExport = .json
                    Task {
                        shareURL = await viewModel.exportJSON()
                        activeExport = nil
                    }
                }
                SettingsSeparator()
                SettingsTaskRow(text: "Export as CSV", color: .accentColor, isActive: activeExport == .csv, isDisabled: activeExport != nil) {
                    guard activeExport == nil else { return }
                    activeExport = .csv
                    Task {
                        shareURL = await viewModel.exportCSV()
                        activeExport = nil
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL {
                ShareSheet(url: shareURL)
            }
        }
    }
}

private struct AboutPage: View {
    @State private var showBuildNumber = false
    @Query private var cameras: [Camera]
    @Query private var rolls: [Roll]
    @Query private var exposures: [LogItem]
    // TODO: count InstantFilmGroups once instant film is wired up

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    var body: some View {
        SettingsFullScreenDetailPage(title: "About") {
            VStack(alignment: .center, spacing: 0) {
                Image("app-icon-image")
                    .resizable()
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .padding(.bottom, 32)

                let versionText = Text(Self.version).foregroundStyle(Color.white.opacity(0.5))
                let buildText = Text("b.\(Self.build)").foregroundStyle(Color.white.opacity(0.5)).fontDesign(.monospaced)
                Text("Sprokbook \(showBuildNumber ? buildText : versionText)")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showBuildNumber.toggle()
                    }
                    .padding(.bottom, 32)
                VStack(spacing: 14) {
                    Text("\(cameras.count)\(Text(" camera\(cameras.count == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5)))")
                    Text("\(rolls.count)\(Text(" roll\(rolls.count == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5)))")
                    Text("\(exposures.count)\(Text(" exposure\(exposures.count == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5)))")
                }.foregroundStyle(Color.white)
                .font(.system(size: 20, weight: .semibold, design: .default))
                .fontWidth(.expanded)
                .opacity(0.8)
                Spacer(minLength: 0)
                Text("Made with \(Image(systemName: "heart.fill")) by Michel")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    let viewModel: FilmLogViewModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @State private var showResetAlert = false
    @State private var iCloudStatus: CKAccountStatus?

    private var iCloudStatusLabel: String {
        switch iCloudStatus {
        case .available: "Active"
        case .noAccount: "Signed out"
        case .restricted, .temporarilyUnavailable: "Unavailable"
        case .couldNotDetermine, .none: "…"
        @unknown default: "Unknown"
        }
    }

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
                            Text(iCloudStatusLabel)
                                .foregroundStyle(Color.white.opacity(0.7))
                                .fontWidth(.expanded)
                                .font(.system(size: 17, weight: .medium, design: .default))
                        }
                        SettingsSeparator()
                        SettingsNavRow(text: "Export...") { ExportPage(viewModel: viewModel) }
                        SettingsSeparator()
                        SettingsNavRow(text: "About") { AboutPage() }
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
                    }.frame(width: UIScreen.currentWidth - 32, height: 44)
                }
            }
        }
        .environment(\.dismissSheet, { dismiss() })
        .background(Color(hex: 0x121212))
        .navigationBarBackButtonHidden()
        .onChange(of: settings.preferredCamera) { viewModel.cameraManager.reconfigure() }
        .onChange(of: settings.photoQuality) { viewModel.cameraManager.reconfigure() }
        .onChange(of: settings.locationEnabled) { viewModel.locationService.setEnabled(settings.locationEnabled) }
        .onChange(of: settings.locationAccuracy) { viewModel.locationService.updateAccuracy(settings.locationAccuracy.clAccuracy) }
        .task {
            iCloudStatus = try? await CKContainer.default().accountStatus()
        }
    }

}
