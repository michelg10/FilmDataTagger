//
//  LogItemVeiw.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/2/26.
//

import SwiftUI

struct LogItemView: View {
    struct LogItemInfoItem: Identifiable {
        let id = UUID()
        var icon: Image
        var mainText: Text
        let secondaryText: Text?
    }
    
    /// Exposure number to display, must be <100
    var exposureNumber: Int?
    var previewImage: Image?
    var infoItems: [LogItemInfoItem]
    
    var body: some View {
        HStack(spacing: 12) {
            if let exposureNumber = exposureNumber {
                Text(String(format: "%02d", exposureNumber))
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .fontWidth(.expanded)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, alignment: .center)
                    .opacity(0.85)
            }
            
            if let previewImage = previewImage {
                previewImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            
            VStack(alignment: .leading, spacing: 5) {
                ForEach(infoItems) { infoItem in
                    HStack(spacing: 0) {
                        infoItem.icon
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 17, height: 14, alignment: .center)
                            .opacity(0.85)
                            .padding(.trailing, 5)
                        Group {
                            infoItem.mainText
                            if let secondaryText = infoItem.secondaryText {
                                Text(" ")
                                secondaryText
                                    .opacity(0.5)
                            }
                        }.font(.system(size: 12, weight: .bold))
                    }
                }
            }
            Spacer(minLength: 0)
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
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("3:45 P.M."), secondaryText: Text("1/5/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("The University of Hong Kong"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/4.5, 1/125s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 2,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("9:15 A.M."), secondaryText: Text("1/12/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("Central Park, New York"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/2.8, 1/250s"), secondaryText: Text("\(Image(systemName: "bolt.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 3,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("11:30 P.M."), secondaryText: Text("2/14/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("Shibuya Crossing, Tokyo"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/1.4, 1/60s"), secondaryText: Text("\(Image(systemName: "bolt.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 4,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("6:20 A.M."), secondaryText: Text("3/8/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("Golden Gate Bridge"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/8, 1/500s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 5,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("1:05 P.M."), secondaryText: Text("4/20/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("Louvre Museum, Paris"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/5.6, 1/125s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 6,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("8:45 P.M."), secondaryText: Text("5/2/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("Times Square"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/2, 1/30s"), secondaryText: Text("\(Image(systemName: "bolt.fill"))"))
                ]
            )
            
            LogItemView(
                exposureNumber: 7,
                previewImage: .init("test-image"),
                infoItems: [
                    .init(icon: .init(systemName: "clock.fill"), mainText: Text("4:10 P.M."), secondaryText: Text("6/15/2023")),
                    .init(icon: .init(systemName: "location.fill"), mainText: Text("Santa Monica Pier"), secondaryText: nil),
                    .init(icon: .init(systemName: "camera.fill"), mainText: Text("\(Image(systemName: "f.cursive"))/11, 1/1000s"), secondaryText: Text("\(Image(systemName: "bolt.slash.fill"))"))
                ]
            )
            
        }.padding(.horizontal, 16)
    }
}
