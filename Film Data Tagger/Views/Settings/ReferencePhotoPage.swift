//
//  ReferencePhotoPage.swift
//  Film Data Tagger
//

import SwiftUI

struct ReferencePhotoPage: View {
    @Bindable private var settings = AppSettings.shared
    @State private var availableCameras: [PreferredCamera] = []

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
                ForEach(availableCameras, id: \.self) { option in
                    if option != availableCameras.first { SettingsSeparator() }
                    SettingsOptionRow(text: option.label, value: option, selection: $settings.preferredCamera)
                }
            }
        }
        .onAppear { availableCameras = PreferredCamera.available }
    }
}
