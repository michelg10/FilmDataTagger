//
//  SheetContentClip.swift
//  Film Data Tagger
//
//  Forces the sheet's presentedView to clip content to its rounded corners.
//

import SwiftUI
import UIKit

extension View {
    /// Clips sheet content to match the sheet's rounded top corners.
    func sheetContentClip(cornerRadius: CGFloat = 35) -> some View {
        background(SheetContentClipBridge(cornerRadius: cornerRadius))
    }
}

private struct SheetContentClipBridge: UIViewRepresentable {
    let cornerRadius: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        context.coordinator.cornerRadius = cornerRadius
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.cornerRadius = cornerRadius
        context.coordinator.anchorView = uiView
        context.coordinator.ensureDisplayLink()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var anchorView: UIView?
        var cornerRadius: CGFloat = 35
        var displayLink: CADisplayLink?
        weak var presentedView: UIView?

        deinit { displayLink?.invalidate() }

        func ensureDisplayLink() {
            guard displayLink == nil else { return }
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        }

        @objc private func tick() {
            if presentedView == nil || presentedView?.window == nil {
                guard let anchor = anchorView,
                      let window = anchor.window,
                      let presented = window.rootViewController?.presentedViewController,
                      let pv = presented.presentationController?.presentedView else { return }
                presentedView = pv
            }

            guard let pv = presentedView else { return }
            pv.clipsToBounds = true
            pv.layer.cornerRadius = cornerRadius
            pv.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
    }
}
