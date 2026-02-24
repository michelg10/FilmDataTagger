//
//  RingView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/24/26.
//

import SwiftUI

struct RingView: View {
    var diameter: CGFloat
    var strokeWidth: CGFloat
    var progress: Double
    var fillColor: Color
    var trackColor: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(fillColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            RingView(diameter: 53, strokeWidth: 6, progress: 0.75,
                     fillColor: .white, trackColor: .white.opacity(0.2))
        }
    }
}
