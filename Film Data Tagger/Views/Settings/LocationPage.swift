//
//  LocationPage.swift
//  Film Data Tagger
//

import SwiftUI

struct LocationPage: View {
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

#Preview {
    NavigationStack {
        LocationPage()
    }
    .preferredColorScheme(.dark)
}
