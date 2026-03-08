//
//  LogItemView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/2/26.
//

import SwiftUI

struct LogItemView: View {
    /// Exposure number to display, must be <100
    let exposureNumber: Int?
    var isPreFrame: Bool = false
    var onFrameNumberTapped: (() -> Void)?
    let previewImage: Image?
    let timeText: Text
    let timeSecondaryText: Text?
    var onTimeTapped: (() -> Void)?
    let locationText: Text

    var body: some View {
        HStack(spacing: 12) {
            if isPreFrame {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 10, height: 10)
                    .frame(width: 38, alignment: .center)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .transaction { $0.animation = nil }
                    .onTapGesture { onFrameNumberTapped?() }
            } else if let exposureNumber = exposureNumber {
                Text(String(format: "%02d", exposureNumber % 100))
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, alignment: .center)
                    .frame(maxHeight: .infinity)
                    .opacity(0.85)
                    .transaction { $0.animation = nil }
                    .contentShape(Rectangle())
                    .onTapGesture {
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
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 20, weight: .bold, design: .default))
                            .foregroundStyle(Color.white)
                            .opacity(0.45)
                    }
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
    private func infoRow(icon: String, main: Text, secondary: Text? = nil) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 17, height: 14, alignment: .center)
                .opacity(0.6)
                .padding(.trailing, 5)
            Group {
                main
                    .opacity(0.9)
                if let secondary {
                    Text(" ")
                    secondary
                        .opacity(0.5)
                }
            }.font(.system(size: 12, weight: .bold))
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
                previewImage: .init("test-image"),
                timeText: Text("3:45 P.M."),
                timeSecondaryText: Text("1/5/2023"),
                locationText: Text("The University of Hong Kong")
            )
            LogItemView(
                exposureNumber: 2,
                previewImage: .init("test-image"),
                timeText: Text("9:15 A.M."),
                timeSecondaryText: Text("1/12/2023"),
                locationText: Text("Central Park, New York")
            )
            LogItemView(
                exposureNumber: 3,
                previewImage: .init("test-image"),
                timeText: Text("11:30 P.M."),
                timeSecondaryText: Text("2/14/2023"),
                locationText: Text("Shibuya Crossing, Tokyo")
            )
        }.padding(.horizontal, 16)
    }
}
