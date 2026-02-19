//
//  CaptureSheet.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import SwiftUI

struct CaptureSheet: View {
    static let iOSSheetPadding = 27
    static let compactDetent: PresentationDetent = .height(CGFloat(147 - iOSSheetPadding))
    static let fullDetent: PresentationDetent = .height(CGFloat(283 - iOSSheetPadding))

    var onCapture: () -> Void = {}
    var isScrolling: Bool = false
    var placeName: String?
    var coordinates: String?
    var frameCount: Int = 0
    var rollCapacity: Int = 36
    var lastCaptureDate: Date?

    @State private var selectedDetent: PresentationDetent = fullDetent

    private var locationDisplayText: String {
        placeName ?? coordinates ?? "Locating..."
    }

    private static func formatElapsed(from date: Date?, now: Date) -> String {
        guard let date else { return "No captures yet" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = Double(minutes) / 60.0
        if hours < 24 { return String(format: "%.1fh", hours) }
        let days = hours / 24.0
        return String(format: "%.1fd", days)
    }

    struct CaptureSheetCompactInfo<Icon: View>: View {
        var icon: Icon
        var text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                icon
                    .frame(width: 21, height: 25, alignment: .center)
                    .opacity(0.8)
                Text(text)
                    .lineLimit(1)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .opacity(0.95)
            }
        }
    }

    struct CaptureSheetFullInfo<Icon: View>: View {
        var icon: Icon
        var text: String
        var subtext: String
        var textSubtextPadding: CGFloat = 0

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                icon
                    .frame(width: 21, height: 25, alignment: .center)
                    .opacity(0.8)
                VStack(alignment: .leading, spacing: textSubtextPadding) {
                    Text(text)
                        .lineLimit(2)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .opacity(0.95)
                    Text(subtext)
                        .lineLimit(1)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .opacity(0.65)
                }
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switch selectedDetent {
            case CaptureSheet.compactDetent:
                HStack(spacing: 15) {
                    CaptureSheetCompactInfo(
                        icon: Image(systemName: "clock.fill")
                            .font(.system(size: 16, weight: .semibold, design: .default)),
                        text: Self.formatElapsed(from: lastCaptureDate, now: context.date)
                    )
                    CaptureSheetCompactInfo(
                        icon: Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .semibold, design: .default)),
                        text: placeName ?? "Locating..."
                    )
                }.padding(.horizontal, 30)
                .padding(.bottom, 15)
                .transition(.opacity.combined(with: .offset(y: 20)))
            case CaptureSheet.fullDetent:
                HStack(spacing: 18) {
                    Image("test-image")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 143, height: 143)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    VStack(alignment: .leading, spacing: 10) {
                        CaptureSheetFullInfo(
                            icon: Image(systemName: "clock.fill")
                                .font(.system(size: 17, weight: .semibold, design: .default)),
                            text: Self.formatElapsed(from: lastCaptureDate, now: context.date),
                            subtext: "since last capture"
                        )
                        CaptureSheetFullInfo(
                            icon: Image(systemName: "location.fill")
                                .font(.system(size: 17, weight: .semibold, design: .default)),
                            text: placeName ?? "Locating...",
                            subtext: coordinates ?? "",
                            textSubtextPadding: 3.0
                        )
                    }
                }
                .padding(.bottom, 21)
                .padding(.horizontal, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .offset(y: 30)))
            default:
                EmptyView()
            }
            Button {
                onCapture()
            } label: {
                HStack (alignment: .firstTextBaseline, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("\(frameCount) / \(rollCapacity) •")
                        .opacity(0.46)
                    Text(" Capture")
                    Spacer(minLength: 0)
                }.foregroundStyle(Color.black)
                .font(.system(size: 22, weight: .bold, design: .default))
                .fontWidth(.expanded)
            }.frame(height: 63)
            .glassEffect(.regular.tint(.white.opacity(0.87)).interactive(), in: Capsule(style: .continuous))
            .padding(.horizontal, 15)
            .padding(.bottom, 34)

        }.animation(.easeOut(duration: 0.15), value: selectedDetent)
        .background(SheetDragDisabler(isScrolling: isScrolling))
        .padding(.horizontal, 8)
        .ignoresSafeArea()
        .presentationDetents([CaptureSheet.compactDetent, CaptureSheet.fullDetent], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
        .presentationBackgroundInteraction(.enabled)
        } // TimelineView
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            CaptureSheet()
        }
}
