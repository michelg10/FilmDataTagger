//
//  ViewExtensions.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import SwiftUI

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
