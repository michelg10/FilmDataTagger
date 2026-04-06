//
//  GeneralPage.swift
//  Film Data Tagger
//

import SwiftUI

struct GeneralPage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        SettingsDetailPage(title: "General") {
            SettingsSection(header: "Prefer Capture controls") {
                ForEach(CaptureControlsPreference.allCases, id: \.self) { option in
                    if option != .expanded { SettingsSeparator() }
                    SettingsOptionRow(text: option.label, value: option, selection: $settings.captureControlsPreference)
                }
            }
            SettingsSection(header: "Rolls") {
                SettingsRow(text: "Create roll upon finish") {
                    Toggle("", isOn: $settings.createRollUponFinish)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsSeparator()
                SettingsRow(text: "Hide 'Finish roll' until last shot") {
                    Toggle("", isOn: $settings.hideFinishUntilLastShot)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsSection(header: "Pre-frames", caption: "Tap the first frame number to mark it as a pre-frame shot and match your camera's counter.\nFor when you've loaded film carefully enough to shoot before the counter hits 1.") {
                SettingsRow(text: "Log shots before frame 1") {
                    Toggle("", isOn: $settings.preFramesEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsSection(header: "Hold capture for", caption: "Hold the Capture button to log a frame without time or location data.") {
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
        GeneralPage()
    }
    .preferredColorScheme(.dark)
}
