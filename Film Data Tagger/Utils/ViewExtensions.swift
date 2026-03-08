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
}
