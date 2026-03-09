//
//  PrimaryButton.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/24/26.
//

import SwiftUI

struct PrimaryButton<Label: View>: View {
    var enabled: Bool = true
    let action: () -> Void
    var isAboveAnotherSheet: Bool = false
    var showShadow: Bool = true
    @ViewBuilder var label: Label

    private var shadowOpacity: Double {
        guard showShadow && enabled else { return 0 }
        return isAboveAnotherSheet ? aboveSheetShadowOpacity : sheetShadowOpacity
    }

    var body: some View {
        Button {
            action()
        } label: {
            label
                .frame(maxWidth: .infinity)
                .foregroundStyle(enabled ? Color.black : Color.white.opacity(0.3))
                .font(.system(size: 22, weight: .bold, design: .default))
                .fontWidth(.expanded)
        }.frame(height: 63)
        .disabled(!enabled)
        .glassEffectCompat(
            tint: .white.opacity(enabled ? 0.91 : (isAboveAnotherSheet ? 0.07 : 0.055)),
            in: Capsule(style: .continuous),
            interactive: enabled,
            fallbackColor: enabled ? Color(hex: 0xE0E0E0) : Color(hex: isAboveAnotherSheet ? 0x333333 : 0x2C2C2C)
        )
        .shadow(color: .black.opacity(shadowOpacity), radius: isAboveAnotherSheet ? aboveSheetShadowRadius : sheetShadowRadius)
        .contentShape(Capsule())
        .animation(.easeInOut(duration: 0.12), value: enabled)
    }
}
