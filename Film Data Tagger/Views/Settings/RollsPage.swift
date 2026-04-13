//
//  RollsPage.swift
//  Film Data Tagger
//

import SwiftUI

struct RollsPage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        SettingsDetailPage(title: "Rolls") {
            SettingsSection(header: "Finish roll") {
                SettingsRow(text: "Create roll upon finish") {
                    Toggle("Create roll upon finish", isOn: $settings.createRollUponFinish)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsSeparator()
                SettingsRow(text: "Hide 'Finish roll' until last shot") {
                    Toggle("Hide finish roll until last shot", isOn: $settings.hideFinishUntilLastShot)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            SettingsSection(header: "Pre-frames", caption: "Tap the first frame number to mark it as a pre-frame shot and match your camera's counter.\nFor when you've loaded film carefully enough to shoot before the counter hits 1.") {
                SettingsRow(text: "Log shots before frame 1") {
                    Toggle("Log shots before frame 1", isOn: $settings.preFramesEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RollsPage()
    }
    .preferredColorScheme(.dark)
}
