//
//  SettingsComponents.swift
//  Film Data Tagger
//

import SwiftUI
// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Environment

struct DismissSheetKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var dismissSheet: (() -> Void)? {
        get { self[DismissSheetKey.self] }
        set { self[DismissSheetKey.self] = newValue }
    }
}

// MARK: - Reusable Components

struct SettingsRow<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .padding(.leading, 20)
                .foregroundStyle(Color.white)
                .font(.system(size: 17, weight: .regular, design: .default))
            Spacer(minLength: 16)
            trailing
                .padding(.trailing, 16)
        }.frame(height: 54)
        .contentShape(Rectangle())
    }
}

struct SettingsNavRow<Destination: View>: View {
    let text: String
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRow(text: text) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }.buttonStyle(SettingsButtonStyle())
    }
}

struct SettingsActionRow: View {
    let text: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(text)
                    .padding(.leading, 20)
                    .foregroundStyle(color)
                    .font(.system(size: 17, weight: .medium, design: .default))
                Spacer(minLength: 16)
            }.frame(height: 54)
            .contentShape(Rectangle())
        }.buttonStyle(SettingsButtonStyle())
    }
}

struct SettingsTaskRow: View {
    let text: String
    let color: Color
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(text)
                    .padding(.leading, 20)
                    .foregroundStyle(isActive ? color.opacity(0.4) : color)
                    .font(.system(size: 17, weight: .medium, design: .default))
                Spacer(minLength: 16)
                if isActive {
                    ProgressView()
                        .tint(color.opacity(0.6))
                        .padding(.trailing, 16)
                }
            }.frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsButtonStyle())
        .disabled(isActive || isDisabled)
    }
}

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(hex: 0x656565) : .clear)
    }
}

struct SettingsOptionRow<T: Equatable>: View {
    let text: String
    let value: T
    @Binding var selection: T

    var body: some View {
        Button {
            selection = value
        } label: {
            SettingsRow(text: text) {
                if selection == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }.buttonStyle(SettingsButtonStyle())
    }
}

struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(Color.white.opacity(0.12))
            .padding(.leading, 20)
            .padding(.trailing, 12)
    }
}

struct SettingsSection<Content: View>: View {
    var header: String? = nil
    var caption: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .fontWidth(.expanded)
                    .padding(.leading, 20)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.bottom, 12)
            }
            VStack(spacing: 0) {
                content
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .background(RoundedRectangle(cornerRadius: 26).foregroundStyle(Color(hex: 0x202020)))
            if let caption {
                let lines = caption.split(separator: "\n")
                let styledText = { (text: String) in
                    Text(text)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .lineHeightCompat(points: 16, fallbackSpacing: 0.5)
                        .multilineTextAlignment(.leading)
                }

                Group {
                    if lines.count > 1 {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(lines, id: \.self) { line in
                                styledText(String(line))
                            }
                        }
                    } else {
                        styledText(caption)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
            }
        }.padding(.bottom, 36)
    }
}

struct SettingsHeroSection<Icon: View>: View {
    @ViewBuilder var icon: Icon
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            icon
                .frame(width: 64, height: 64)
                .padding(.bottom, 20)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .default))
                .fontWidth(.expanded)
                .padding(.bottom, 8)
            Text(subtitle)
                .font(.system(size: 17, weight: .regular, design: .default))
                .lineHeightCompat(points: 23, fallbackSpacing: 2.7)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.leading)
        }.padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).foregroundStyle(Color(hex: 0x222222)))
        .padding(.bottom, 36)
    }
}

struct SettingsDetailPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }.padding(.horizontal, 16)
            .offset(y: -32)
        }
        .background(Color(hex: 0x121212))
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    BackButton()
                    Spacer()
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white)
                        .padding(.top, 3)
                    Spacer()
                    DismissButton()
                }.frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
            }
        }
    }
}

struct SettingsFullScreenDetailPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(hex: 0x121212))
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        BackButton()
                        Spacer()
                        Text(title)
                            .font(.system(size: 18, weight: .bold, design: .default))
                            .fontWidth(.expanded)
                            .foregroundStyle(Color.white)
                            .padding(.top, 3)
                        Spacer()
                        DismissButton()
                    }.frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
                }
            }
    }
}

struct DismissButton: View {
    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        Button { dismissSheet?() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .frame(width: 44, height: 44)
        .glassEffectCompat(in: Circle())
        .accessibilityLabel("Close")
    }
}

struct SettingsMenuButton: View {
    @Environment(\.dismissSheet) private var dismissSheet

    var body: some View {
        Menu {
            Button {
                UIApplication.shared.open(URL(string: "https://sprokbook.com/support.html")!)
            } label: {
                Label("Support", systemImage: "questionmark.circle")
            }
            Button {
                // TODO: Share debug data action
            } label: {
                Label("Share debug data…", systemImage: "stethoscope")
            }
            Divider()
            Button {
                dismissSheet?()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 44, height: 44)
                .glassEffectCompat(in: Circle())
        }
        .accessibilityLabel("Support options")
    }
}

struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 44, height: 44)
        }
        .frame(width: 44, height: 44)
        .glassEffectCompat(in: Circle())
        .accessibilityLabel("Back")
    }
}

#Preview("Section with rows") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(header: "Example", caption: "This is a caption.") {
                SettingsRow(text: "Toggle row") {
                    Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                SettingsSeparator()
                SettingsNavRow(text: "Nav row") { Text("Detail") }
                SettingsSeparator()
                SettingsActionRow(text: "Action", color: .accentColor) {}
            }
        }.padding(.horizontal, 16)
    }
    .background(Color(hex: 0x121212))
    .preferredColorScheme(.dark)
}

#Preview("Hero section") {
    ScrollView {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeroSection(
                icon: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x303030))
                        Image(systemName: "star.fill")
                            .foregroundStyle(.white)
                    }
                },
                title: "Hero Title",
                subtitle: "This is a subtitle explaining the feature."
            )
        }.padding(.horizontal, 16)
    }
    .background(Color(hex: 0x121212))
    .preferredColorScheme(.dark)
}

#Preview("Buttons") {
    VStack(spacing: 0) {
        DismissButton()
        SettingsMenuButton()
        BackButton()
    }
    .padding(20)
    .background(Color(hex: 0x121212))
    .preferredColorScheme(.dark)
}
