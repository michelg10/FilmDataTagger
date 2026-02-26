//
//  PrimaryButton.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/24/26.
//

import SwiftUI

struct PrimaryButton<Label: View>: View {
    var enabled: Bool = true
    var action: () -> Void
    var isAboveAnotherSheet: Bool = false
    @ViewBuilder var label: Label

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Spacer(minLength: 0)
                label
                Spacer(minLength: 0)
            }.foregroundStyle(enabled ? Color.black : Color.white.opacity(0.3))
            .font(.system(size: 22, weight: .bold, design: .default))
            .fontWidth(.expanded)
        }.frame(height: 63)
        .disabled(!enabled)
        .glassEffect(.regular.tint(.white.opacity(enabled ? 0.91 : (isAboveAnotherSheet ? 0.07 : 0.055))).interactive(enabled), in: Capsule(style: .continuous))
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.12), value: enabled)
    }
}
