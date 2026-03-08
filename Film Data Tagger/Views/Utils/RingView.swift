//
//  RingView.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/24/26.
//

import SwiftUI

struct RingView: View {
    let diameter: CGFloat
    let strokeWidth: CGFloat
    let progress: Double
    let fillColor: Color
    let trackColor: Color
    var overflowShadowColor: Color = .black.opacity(0.75)
    var overflowShadowRadius: CGFloat = 2.9

    private var clampedProgress: Double { min(max(progress, 0), 1) }
    private var overflow: Double { max(progress - 1, 0) }

    private var showShadow: Bool {
        if progress >= 1 { return true }
        let radius = diameter / 2
        let remainingAngle = ((1 - clampedProgress) * 360) * .pi / 180
        return radius * remainingAngle <= strokeWidth
    }

    private func endCircleOffset(for progress: Double, in size: CGFloat) -> (CGFloat, CGFloat) {
        let angle = (progress * 360 - 90) * .pi / 180
        let radius = size / 2
        return (radius * cos(angle), radius * sin(angle))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: strokeWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(fillColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if overflow > 0 {
                Circle()
                    .trim(from: 0, to: min(overflow, 1))
                    .stroke(fillColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            
            if showShadow {
                let tipProgress = overflow > 0 ? min(overflow, 1) : clampedProgress
                let endOffset = endCircleOffset(for: tipProgress, in: diameter)
                let tipAngle = tipProgress * 360

                // Shadow circle, masked to a 50% arc ending at the tip
                Circle()
                    .fill(fillColor)
                    .frame(width: strokeWidth, height: strokeWidth)
                    .shadow(color: overflowShadowColor, radius: overflowShadowRadius)
                    .frame(width: diameter, height: diameter)
                    .offset(x: endOffset.0, y: endOffset.1)
                    .mask {
                        Circle()
                            .trim(from: 0.501, to: 1.0)
                            .stroke(style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                            .rotationEffect(.degrees(tipAngle - 270))
                    }

                // Clean cap on top
                Circle()
                    .fill(fillColor)
                    .frame(width: strokeWidth, height: strokeWidth)
                    .offset(x: endOffset.0, y: endOffset.1)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            RingView(diameter: 53, strokeWidth: 6, progress: 0.97,
                     fillColor: .white, trackColor: .white.opacity(0.2))
            RingView(diameter: 53, strokeWidth: 6, progress: 1.25,
                     fillColor: .white, trackColor: .white.opacity(0.2))
        }.scaleEffect(5)
    }
}
