//
//  AboutPage.swift
//  Film Data Tagger
//

import SwiftUI

struct AboutPage: View {
    let cameras: [CameraSnapshot]
    @Environment(\.dismissSheet) private var dismissSheet
    @State private var showBuildNumber = false
    @State private var showShareDebugData = false

    private var totalRolls: Int { cameras.reduce(0) { $0 + $1.rollCount } }
    private var totalExposures: Int { cameras.reduce(0) { $0 + $1.totalExposureCount } }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Spacer(minLength: 0)
            Image("app-icon-image")
                .resizable()
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 32))
                .shadow(color: .black.opacity(0.88), radius: 28, x: 0, y: 0)
                .padding(.bottom, 25)

            let versionText = Text(Self.version).foregroundStyle(Color.white.opacity(0.5))
            let buildText = Text("b.\(Self.build)").foregroundStyle(Color.white.opacity(0.5)).fontDesign(.monospaced)
            Text("Sprokbook \(showBuildNumber ? buildText : versionText)")
                .font(.system(size: 28, weight: .bold, design: .default))
                .fontWidth(.expanded)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    showBuildNumber.toggle()
                }
                .padding(.bottom, 44)
            VStack(spacing: 14) {
                Text("\(cameras.count)\(Text(" camera\(cameras.count == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5)))")
                Text("\(totalRolls)\(Text(" roll\(totalRolls == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5)))")
                Text("\(totalExposures)\(Text(" exposure\(totalExposures == 1 ? "" : "s")").foregroundStyle(Color.white.opacity(0.5)))")
            }.foregroundStyle(Color.white)
            .font(.system(size: 20, weight: .semibold, design: .default))
            .fontWidth(.expanded)
            .opacity(0.8)
            .padding(.bottom, 42 + 68)
            Spacer(minLength: 0)
            Text("Made with \(Image(systemName: "heart.fill")) by Michel")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.bottom, 21)
        }.toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    BackButton()
                    Spacer()
                    Text("About")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white)
                        .padding(.top, 3)
                    Spacer()
                    Menu {
                        Button {
                            UIApplication.shared.open(URL(string: "https://sprokbook.com/support.html")!)
                        } label: {
                            Label("Support", systemImage: "questionmark.circle")
                        }
                        Button {
                            showShareDebugData = true
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
                }.frame(width: UIScreen.currentWidth - 32, height: 44, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x121212))
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showShareDebugData) {
            ShareDebugDataSheet(cameras: cameras)
        }
    }
}

#Preview {
    NavigationStack {
        AboutPage(cameras: [])
    }
    .preferredColorScheme(.dark)
}
