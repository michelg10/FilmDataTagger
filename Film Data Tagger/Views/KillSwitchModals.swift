//
//  KillSwitchModals.swift
//  Film Data Tagger
//
//  Skeleton modal views for the kill switch. Intentionally unstyled — all
//  layout is bare VStacks/HStacks. Style passes happen here.
//

import SwiftUI

// MARK: - Soft kill

struct KillModal<HamburgerMenuContents: View>: View {
    @ViewBuilder let hamburgerMenu: () -> HamburgerMenuContents
    let onDismiss: (() -> Void)?
    let titleMessage: String
    let bodyMessage: String
    let onUpdateTapped: () -> Void
    let onNotNow: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Menu {
                    hamburgerMenu()
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .glassEffectCompat(in: Circle(), interactive: true)
                }
                Spacer(minLength: 0)
                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffectCompat(in: Circle(), interactive: true)
                    }
                }
            }.font(.system(size: 20, weight: .semibold, design: .default))
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 70)
            ZStack(alignment: .topLeading) {
                Image("app-icon-image")
                    .resizable()
                    .frame(width: 111, height: 111)
                    .clipShape(RoundedRectangle(cornerRadius: 31, style: .continuous))
                Image("killswitch-app-icon-error-overlay")
                    .frame(width: 138, height: 112)
            }.frame(width: 138, height: 112)
            .padding(.bottom, 32)
            .padding(.leading, 26)
            Text(titleMessage)
                .foregroundStyle(Color.white)
                .font(.system(size: 22, weight: .bold, design: .default))
                .fontWidth(.expanded)
                .padding(.bottom, 12)
                .padding(.leading, 26)
            Text(bodyMessage)
                .foregroundStyle(Color.white.opacity(0.5))
                .font(.system(size: 17, weight: .regular, design: .default))
                .multilineTextAlignment(.leading)
                .lineHeightCompat(points: 25)
                .padding(.horizontal, 26)
            Spacer()
            Button {
                onUpdateTapped()
            } label: {
                Text("Update")
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .frame(height: 61)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
            }
            .glassEffectCompat(tint: .accentColor, in: Capsule(), interactive: true, fallbackColor: Color(hex: 0x005dcb))
            .buttonStyle(.plain)
            .padding(.horizontal, 26)
            .padding(.bottom, onNotNow == nil ? 30 : 0)
            if let onNotNow = onNotNow {
                Button {
                    onNotNow()
                } label: {
                    Text("Not now")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

        }.background(Color(hex: 0x121212))
    }
}

struct SoftKillModal: View {
    let appStoreURL: URL?
    let onDontShowAgain: () -> Void
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        KillModal(
            hamburgerMenu: {
                Button(role: .destructive, action: onDontShowAgain) {
                    Label("Don't show again", systemImage: "bell.slash")
                }
            },
            onDismiss: onDismiss,
            titleMessage: "Update Sprokbook",
            bodyMessage: "This version of Sprokbook is out of date. Update to make sure new data stays compatible across your devices.",
            onUpdateTapped: {
                if let appStoreURL {
                    openURL(appStoreURL)
                }
            },
            onNotNow: onDismiss
        )
    }
}

// MARK: - Hard kill

struct HardKillModal: View {
    let appStoreURL: URL?
    let onContinueAnyway: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showContinueWarning = false

    var body: some View {
        KillModal(
            hamburgerMenu: {
                Button(role: .destructive) {
                    showContinueWarning = true
                } label: {
                    Label("Continue anyway", systemImage: "arrow.forward.circle")
                }
            },
            onDismiss: nil,
            titleMessage: "Update required",
            bodyMessage: "Sprokbook needs to update before you can keep logging.",
            onUpdateTapped: {
                if let appStoreURL {
                    openURL(appStoreURL)
                }
            },
            onNotNow: nil
        )
        .alert("Continue anyway?", isPresented: $showContinueWarning) {
            Button("Continue", role: .destructive, action: onContinueAnyway)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This version has bugs that can cause data loss. We strongly recommend updating from the App Store. If you'd rather continue for now, please back up your data regularly from Settings → Export.")
        }
    }
}

// MARK: - Previews

#Preview("Soft kill") {
    SoftKillModal(
        appStoreURL: URL(string: "itms-apps://apps.apple.com/us/app/sprokbook/id6760282935"),
        onDontShowAgain: {},
        onDismiss: {}
    )
}

#Preview("Soft kill — no URL") {
    SoftKillModal(
        appStoreURL: nil,
        onDontShowAgain: {},
        onDismiss: {}
    )
}

#Preview("Hard kill") {
    HardKillModal(
        appStoreURL: URL(string: "itms-apps://apps.apple.com/us/app/sprokbook/id6760282935"),
        onContinueAnyway: {}
    )
}

#Preview("Hard kill — no URL") {
    HardKillModal(
        appStoreURL: nil,
        onContinueAnyway: {}
    )
}
