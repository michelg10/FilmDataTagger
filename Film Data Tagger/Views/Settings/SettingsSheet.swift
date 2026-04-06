//
//  SettingsSheet.swift
//  Film Data Tagger
//

import SwiftUI
import CloudKit

struct SettingsSheet: View {
    let viewModel: FilmLogViewModel
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
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
                        SettingsNavRow(text: "About") { AboutPage(cameras: viewModel.cameraList) }
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
        .onChange(of: settings.preferredCamera) { viewModel.camera.reconfigure() }
        .onChange(of: settings.photoQuality) { viewModel.camera.reconfigure() }
        .onChange(of: settings.locationEnabled) { viewModel.locationService.setEnabled(settings.locationEnabled) }
        .onChange(of: settings.locationAccuracy) { viewModel.locationService.updateAccuracy(settings.locationAccuracy.clAccuracy) }
        .task {
            iCloudStatus = try? await CKContainer.default().accountStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .CKAccountChanged)) { _ in
            Task(priority: .medium) {
                iCloudStatus = try? await CKContainer.default().accountStatus()
            }
        }
    }
}

#Preview {
    let container = PreviewSampleData.makeContainer()
    let viewModel = FilmLogViewModel(store: PreviewSampleData.makeStore(container: container))
    SettingsSheet(viewModel: viewModel)
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
