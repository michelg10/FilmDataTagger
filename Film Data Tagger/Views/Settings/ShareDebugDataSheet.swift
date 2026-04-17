//
//  ShareDebugDataSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 4/5/26.
//

import SwiftUI
import MessageUI

private struct MailCompose: UIViewControllerRepresentable {
    let url: URL
    let onFinish: (MFMailComposeResult) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let mc = MFMailComposeViewController()
        mc.mailComposeDelegate = context.coordinator
        mc.setToRecipients(["support@sprokbook.com"])
        mc.setSubject("Sprokbook Debug Report")
        mc.setMessageBody("Debug report attached.", isHTML: false)
        if let data = try? Data(contentsOf: url) {
            mc.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
        }
        return mc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result)
        }
    }
}

struct ShareDebugDataSheet: View {
    let cameras: [CameraSnapshot]
    @Environment(\.dismiss) private var dismiss
    @State private var isGenerating = false
    @State private var reportURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }.glassEffectCompat(in: Circle())
            .accessibilityLabel("Close")
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 16)
            .padding(.bottom, 36)
            Group {
                Image("privacy-sharing-icon")
                    .opacity(0.6)
                    .frame(width: 72, height: 59)
                    .padding(.bottom, 32)
                Text("Share debug data?")
                    .foregroundStyle(Color.white)
                    .font(.system(size: 22, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .padding(.bottom, 16 + 2)
                VStack(alignment: .leading, spacing: 13) {
                    Text("This will help us figure out what went wrong.")
                    Text("""
Debug info may include:
• General information about your device
• Precise location data
• App logs
""")
                    Text("No photo data will be shared. Your data is shared once and only used to improve Sprokbook.")
                    Text("Only share debug information when asked to by a Sprokbook developer.")
                }.foregroundStyle(Color.white.opacity(0.7))
                .multilineTextAlignment(.leading)
                .lineLimit(100)
                .lineHeightCompat(points: 25, fallbackSpacing: 4.7)
                .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
                
                Button {
                    guard !isGenerating else { return }
                    isGenerating = true
                    Task {
                        reportURL = await DebugReport.generate(cameras: cameras)
                        isGenerating = false
                    }
                } label: {
                    Group {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Share debug data")
                                .font(.system(size: 17, weight: .bold, design: .default))
                                .fontWidth(.expanded)
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(height: 61)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
                }
                .glassEffectCompat(tint: .accentColor, in: Capsule(), interactive: true, fallbackColor: Color(hex: 0x005dcb))
                .buttonStyle(.plain)
                Button {
                    dismiss()
                } label: {
                    Text("Don't share")
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .fontWidth(.expanded)
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }.padding(.horizontal, 26)
        }.frame(maxWidth: .infinity)
        .background(Color(hex: 0x141414))
        .sheet(isPresented: Binding(get: { reportURL != nil }, set: { if !$0 { reportURL = nil } })) {
            if let reportURL {
                if MFMailComposeViewController.canSendMail() {
                    MailCompose(url: reportURL) { result in
                        // Always dismiss the inner mail sheet (it doesn't dismiss itself on delegate callback).
                        self.reportURL = nil
                        if result == .sent {
                            // Let the inner sheet's dismiss animation finish before collapsing the outer.
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.3))
                                dismiss()
                            }
                        }
                    }
                } else {
                    ShareSheet(url: reportURL) { completed in
                        self.reportURL = nil
                        if completed {
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.3))
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Text("Hi")
    }.sheet(isPresented: .constant(true)) {
        ShareDebugDataSheet(cameras: [])
    }.preferredColorScheme(.dark)
}
