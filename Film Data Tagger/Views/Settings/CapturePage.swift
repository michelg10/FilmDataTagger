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
            SettingsSection(header: "Hold Capture for", caption: "Hold the Capture button to add a placeholder or lost frame.\nPlaceholders mark a frame with no metadata, whereas lost frames record time and location with no reference photo.") {
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
