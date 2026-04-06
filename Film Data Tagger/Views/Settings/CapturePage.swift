//
//  CapturePage.swift
//  Film Data Tagger
//

import SwiftUI

struct CapturePage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        SettingsDetailPage(title: "Capture") {
            SettingsSection(header: "Prefer Capture controls") {
                ForEach(CaptureControlsPreference.allCases, id: \.self) { option in
                    if option != .expanded { SettingsSeparator() }
                    SettingsOptionRow(text: option.label, value: option, selection: $settings.captureControlsPreference)
                }
            }
            SettingsSection(header: "Hold Capture for", caption: "Hold the Capture button to log a frame without time or location data.") {
                SettingsRow(text: "Placeholders") {
                    Toggle("", isOn: $settings.holdCapturePlaceholders)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsSeparator()
                SettingsRow(text: "Lost frames") {
                    Toggle("", isOn: $settings.holdCaptureLostFrames)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CapturePage()
    }
    .preferredColorScheme(.dark)
}
