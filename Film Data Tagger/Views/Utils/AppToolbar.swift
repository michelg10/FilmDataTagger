//
//  AppToolbar.swift
//  Film Data Tagger
//

import SwiftUI

/// Reusable toolbar layout: leading | center content | trailing action.
/// Applied via `.appToolbar(leading:center:trailing:)`. Defaults to `BackButton()` for leading.
struct AppToolbar<Leading: View, Center: View, Trailing: View>: ViewModifier {
    var leading: Leading
    var center: Center
    var trailing: Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        leading
                            .padding(.trailing, 12)
                        center
                            .padding(.trailing, 12)
                        Spacer(minLength: 0)
                        trailing
                    }
                    .frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
                }
            }
    }
}

extension View {
    func appToolbar<Leading: View, Center: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(AppToolbar(leading: leading(), center: center(), trailing: trailing()))
    }

    func appToolbar<Center: View, Trailing: View>(
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        modifier(AppToolbar(leading: ToolbarBackButton(), center: center(), trailing: trailing()))
    }

    func appToolbar<Center: View>(
        @ViewBuilder center: () -> Center
    ) -> some View {
        modifier(AppToolbar(leading: ToolbarBackButton(), center: center(), trailing: EmptyView()))
    }
}

/// Back button that wraps ToolbarIconButton with dismiss.
struct ToolbarBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ToolbarIconButton(icon: "chevron.left") { dismiss() }
            .accessibilityLabel("Back")
    }
}

/// Two-line title for the toolbar center slot: primary text on top, secondary below.
struct ToolbarTitle<Secondary: View>: View {
    let primary: String
    @ViewBuilder var secondary: Secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(primary)
                .font(.system(size: 18, weight: .bold, design: .default))
                .fontWidth(.expanded)
                .foregroundStyle(Color.white)
            secondary
                .font(.system(size: 15, weight: .medium, design: .default))
                .fontWidth(.expanded)
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }
}

extension ToolbarTitle where Secondary == Text {
    init(primary: String, secondary: String) {
        self.primary = primary
        self.secondary = Text(secondary)
    }
}

/// Single icon button in a glass circle, for toolbar trailing actions.
struct ToolbarIconButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .frame(width: 44, height: 44)
        .glassEffectCompat(in: Circle())
    }
}
