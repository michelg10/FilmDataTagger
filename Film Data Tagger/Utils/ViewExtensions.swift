//
//  ViewExtensions.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import SwiftUI

extension UIScreen {
    static var currentWidth: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .bounds
            .width) ?? 0
    }
}

let sheetScaleCompensationFactor = UIScreen.currentWidth / (UIScreen.currentWidth - 16)
// Private API, but widely used across the App Store with no known rejections. Falls back to 50 if unavailable.
let screenCornerRadius: CGFloat = UIScreen.main.value(forKey: "_displayCornerRadius") as? CGFloat ?? 50

let aboveSheetShadowOpacity: Double = 0.2
let aboveSheetShadowRadius: CGFloat = 16
let sheetShadowOpacity: Double = 0.12
let sheetShadowRadius: CGFloat = 16

var bottomSafeAreaInset: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
        .first ?? 0
}

var topSafeAreaInset: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
        .first ?? 0
}

extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    #if DEBUG
    // Set to true to preview pre-iOS 26 fallback appearance
    private var forceLegacy: Bool { false }
    #endif

    @ViewBuilder
    func lineHeightCompat(points: CGFloat, fallbackSpacing: CGFloat = 0) -> some View {
        #if DEBUG
        if #available(iOS 26, *), !forceLegacy {
            self.lineHeight(.exact(points: points))
        } else {
            self.lineSpacing(fallbackSpacing)
        }
        #else
        if #available(iOS 26, *) {
            self.lineHeight(.exact(points: points))
        } else {
            self.lineSpacing(fallbackSpacing)
        }
        #endif
    }

    @ViewBuilder
    func glassEffectCompat(in shape: some InsettableShape, interactive: Bool = true) -> some View {
        #if DEBUG
        if #available(iOS 26, *), !forceLegacy {
            self.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 1))
        }
        #else
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.16), lineWidth: 1))
        }
        #endif
    }

    @ViewBuilder
    func glassEffectCompat(tint: Color, in shape: some InsettableShape, interactive: Bool = true, fallbackColor: Color) -> some View {
        #if DEBUG
        if #available(iOS 26, *), !forceLegacy {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(fallbackColor, in: shape)
        }
        #else
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(fallbackColor, in: shape)
        }
        #endif
    }
}
