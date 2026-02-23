//
//  ViewExtensions.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import SwiftUI

let sheetScaleCompensationFactor = UIScreen.main.bounds.width / (UIScreen.main.bounds.width - 16)
let bottomSafeAreaInset = UIApplication.shared.connectedScenes
    .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
    .first ?? 0

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
