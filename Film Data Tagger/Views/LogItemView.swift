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
                    .onTapGesture { onFrameNumberTapped?() }
            } else if let exposureNumber = exposureNumber {
                Text(String(format: "%02d", exposureNumber % 100))
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, alignment: .center)
                    .frame(maxHeight: .infinity)
                    .opacity(0.85)
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
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/4.5, 1/125s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 2,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("9:15 A.M."), secondaryText: Text("1/12/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Central Park, New York"), secondaryText: nil),
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/2.8, 1/250s"), secondaryText: Text("\(Image(systemName: "bolt.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 3,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("11:30 P.M."), secondaryText: Text("2/14/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Shibuya Crossing, Tokyo"), secondaryText: nil),
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/1.4, 1/60s"), secondaryText: Text("\(Image(systemName: "bolt.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 4,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("6:20 A.M."), secondaryText: Text("3/8/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Golden Gate Bridge"), secondaryText: nil),
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/8, 1/500s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 5,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("1:05 P.M."), secondaryText: Text("4/20/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Louvre Museum, Paris"), secondaryText: nil),
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/5.6, 1/125s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 6,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("8:45 P.M."), secondaryText: Text("5/2/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Times Square"), secondaryText: nil),
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/2, 1/30s"), secondaryText: Text("\(Image(systemName: "bolt.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 7,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(id: "time", icon: .init(systemName: "clock.fill"), mainText: Text("4:10 P.M."), secondaryText: Text("6/15/2023")),
                    .init(id: "location", icon: .init(systemName: "location.fill"), mainText: Text("Santa Monica Pier"), secondaryText: nil),
                    .init(id: "camera", icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/11, 1/1000s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
        }.padding(.horizontal, 16)
    }
}
