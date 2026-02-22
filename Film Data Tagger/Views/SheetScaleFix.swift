//
//  SheetScaleFix.swift
//  Film Data Tagger
//
//  Counters the ~0.96x scale iOS applies to a sheet's content
//  when a non-full-screen sheet is presented on top of it.
//

import SwiftUI
import UIKit

extension View {
    /// Counters the scale-down iOS applies when another sheet is presented on top.
    func sheetScaleFix() -> some View {
        background(SheetScaleFixBridge())
    }
}

private struct SheetScaleFixBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.anchorView = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.ensureDisplayLink()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var anchorView: UIView?
        var displayLink: CADisplayLink?
        weak var discoveredPresentedView: UIView?

        deinit { displayLink?.invalidate() }

        func ensureDisplayLink() {
            guard displayLink == nil else { return }
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        }

        private func findPresentedView() -> UIView? {
            if let pv = discoveredPresentedView, pv.window != nil {
                return pv
            }
            // Walk up from our anchor to find the presentation controller
            var responder: UIResponder? = anchorView
            while let r = responder {
                if let vc = r as? UIViewController,
                   let pv = vc.presentationController?.presentedView {
                    discoveredPresentedView = pv
                    return pv
                }
                responder = r.next
            }
            return nil
        }

        @objc private func tick() {
            guard let presentedView = findPresentedView() else { return }
            guard presentedView.subviews.count > 1 else { return }

            let sheetTransform = presentedView.transform
            let contentView = presentedView.subviews[1]

            if !sheetTransform.isIdentity {
                let inverseScale = 1.0 / sheetTransform.a
//                print(sheetTransform.a, sheetTransform.d)
                // hack: iOS does this weird y-transform thing that doesn't make any sense. empirically, this measures good. and we're clipping the effect, so i don't think this should shoot us in the foot too hard.
                let inverse = CGAffineTransform(scaleX: inverseScale, y: inverseScale)
                    .translatedBy(x: 0, y: 2.096692111959287 + max(min((sheetTransform.ty + 2.096692111959287) * -0.1, 1), -1))
                contentView.transform = inverse
                contentView.clipsToBounds = false
                print("[INV] scale=\(sheetTransform.a) ty=\(sheetTransform.ty) -> inverseScale=\(inverseScale)")
            } else if !contentView.transform.isIdentity {
                contentView.transform = .identity
                print("[INV] reset to identity")
            }
        }
    }
}
