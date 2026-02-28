//
//  LogItemView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/2/26.
//

import SwiftUI

struct LogItemView: View {
    struct LogItemInfoItem: Identifiable {
        var id: String
        var icon: Image
        var mainText: Text
        let secondaryText: Text?
        var onTap: (() -> Void)? = nil
    }
    
    /// Exposure number to display, must be <100
    var exposureNumber: Int?
    var isPreFrame: Bool = false
    var onFrameNumberTapped: (() -> Void)?
    var previewImage: Image?
    var infoItems: [LogItemInfoItem]

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
                ForEach(infoItems) { infoItem in
                    HStack(spacing: 0) {
                        infoItem.icon
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 17, height: 14, alignment: .center)
                            .opacity(0.6)
                            .padding(.trailing, 5)
                        Group {
                            infoItem.mainText
                                .opacity(0.9)
                            if let secondaryText = infoItem.secondaryText {
                                Text(" ")
                                secondaryText
                                    .opacity(0.5)
                            }
                        }.font(.system(size: 12, weight: .bold))
                    }.contentShape(Rectangle())
                    .onTapGesture {
                        infoItem.onTap?()
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(Color.white)
        .frame(height: 60, alignment: .leading)
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
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("3:45 P.M."), secondaryText: Text("1/5/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("The University of Hong Kong"), secondaryText: nil),
                ]
            )
            LogItemView(
                exposureNumber: 2,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("9:15 A.M."), secondaryText: Text("1/12/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Central Park, New York"), secondaryText: nil),
                ]
            )
            LogItemView(
                exposureNumber: 3,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("11:30 P.M."), secondaryText: Text("2/14/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Shibuya Crossing, Tokyo"), secondaryText: nil),
                ]
            )
        }.padding(.horizontal, 16)
    }
}
