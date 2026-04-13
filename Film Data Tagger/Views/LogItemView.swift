//
//  LogItemView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/2/26.
//

import SwiftUI

struct LogItemView: View {
    /// Exposure number to display (1–99 as two digits, 100–999 as three digits, 1000+ wraps mod 1000)
    let exposureNumber: Int?
    var isPreFrame: Bool = false
    var frameNumberTapCount: Int
    var onFrameNumberTapped: (() -> Void)?
    let previewImage: Image?
    var isFromShortcut: Bool = false
    var exposureType: ExposureType = .regular
    let timeText: Text
    let timeSecondaryText: Text?
    var onTimeTapped: (() -> Void)?
    let locationText: Text

    var body: some View {
        HStack(spacing: 0) {
            if isPreFrame {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .frame(width: 38 + 12 + 12, alignment: .center)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .transaction { $0.animation = nil }
                    .onTapGesture(count: frameNumberTapCount) { onFrameNumberTapped?() }
            } else if let exposureNumber = exposureNumber {
                Text(exposureNumber < 100
                    ? String(format: "%02d", exposureNumber)
                    : String(format: "%03d", exposureNumber % 1000))
                    .font(.system(size: exposureNumber < 100 ? 17 : 15, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .frame(width: 38 + 12 + 12, alignment: .center)
                    .frame(maxHeight: .infinity)
                    .opacity(0.85)
                    .transaction { $0.animation = nil }
                    .contentShape(Rectangle())
                    .onTapGesture(count: frameNumberTapCount) {
                        onFrameNumberTapped?()
                    }
            }
            Group {
                if let previewImage = previewImage {
                    previewImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle()
                            .foregroundStyle(Color(hex: 0x313131))
                        switch exposureType {
                        case .regular:
                            if isFromShortcut {
                                Image("shortcuts-symbol")
                                    .frame(width: 60, height: 60)
                            } else {
                                placeholderIcon("eye.slash.fill", size: 20, weight: .bold)
                            }
                        case .placeholder:
                            placeholderIcon("questionmark", size: 23, weight: .bold)
                        case .lostFrame:
                            placeholderIcon("xmark", size: 22, weight: .bold)
                        case .unknown:
                            placeholderIcon("exclamationmark.triangle.fill", size: 25, weight: .bold)
                        }
                    }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 5) {
                infoRow(icon: "clock.fill", main: timeText, secondary: timeSecondaryText)
                    .contentShape(Rectangle())
                    .onTapGesture { onTimeTapped?() }

                infoRow(icon: "location.fill", main: locationText)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(Color.white)
        .frame(height: 60, alignment: .leading)
    }

    @ViewBuilder
    private func placeholderIcon(_ name: String, size: CGFloat, weight: Font.Weight) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: weight, design: .default))
            .foregroundStyle(Color.white)
            .opacity(0.45)
    }

    @ViewBuilder
    private func infoRow(icon: String, main: Text, secondary: Text? = nil) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 17, height: 14, alignment: .center)
                .opacity(0.6)
                .padding(.trailing, 5)
            Text("\(main.foregroundStyle(Color.white.opacity(0.9))) \(secondary == nil ? Text("") : secondary!.foregroundStyle(Color.white.opacity(0.5)))")
                .lineLimit(1)
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

#Preview {
    ZStack {
        Rectangle()
            .background(Color.black)
        VStack(spacing: 16) {
            LogItemView(
                exposureNumber: 1,
                frameNumberTapCount: 1,
                previewImage: .init("test-image"),
                timeText: Text("3:45 P.M."),
                timeSecondaryText: Text("1/5/2023"),
                locationText: Text("The University of Hong Kong")
            )
            LogItemView(
                exposureNumber: 2,
                frameNumberTapCount: 1,
                previewImage: .init("test-image"),
                timeText: Text("9:15 A.M."),
                timeSecondaryText: Text("1/12/2023"),
                locationText: Text("Central Park, New York")
            )
            LogItemView(
                exposureNumber: 3,
                frameNumberTapCount: 1,
                previewImage: .init("test-image"),
                timeText: Text("11:30 P.M."),
                timeSecondaryText: Text("2/14/2023"),
                locationText: Text("Shibuya Crossing, Tokyo")
            )
        }.padding(.horizontal, 16)
    }
}
