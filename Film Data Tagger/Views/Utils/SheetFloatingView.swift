//
//  SheetFloatingView.swift
//  Film Data Tagger
//
//  Adds a floating view that hovers above a permanently-presented sheet.
//  The floating view is inserted into the sheet's containerView so it sits
//  above the sheet but below any sheets presented from within it.
//

import SwiftUI
import UIKit

// MARK: - Public API

extension View {
    /// Adds a floating view that stays `offset` points above the presented sheet.
    func sheetFloatingView<F: View>(
        offset: CGFloat = 20,
        @ViewBuilder content: @escaping () -> F
    ) -> some View {
        background(SheetFloatingBridge(offset: offset, floatingContent: content))
    }
}

// MARK: - Bridge

private struct SheetFloatingBridge<F: View>: UIViewRepresentable {
    let offset: CGFloat
    let floatingContent: () -> F

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.anchorView = view
        context.coordinator.offset = offset
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.offset = offset
        if let child = context.coordinator.floatingChild {
            child.rootView = floatingContent()
        } else {
            context.coordinator.pendingContent = floatingContent()
        }
        context.coordinator.ensureDisplayLink()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var anchorView: UIView?
        var offset: CGFloat = 20
        var pendingContent: F?

        var floatingChild: UIHostingController<F>?
        var displayLink: CADisplayLink?
        var isSetUp = false

        var lastModelY: CGFloat = 0
        var cachedSize: CGSize = .zero
        var springAnimator: UIViewPropertyAnimator?

        weak var discoveredPresentedView: UIView?
        weak var discoveredContainerView: UIView?
        deinit { displayLink?.invalidate() }

        func ensureDisplayLink() {
            guard displayLink == nil else { return }
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        }

        /// Finds the first presented sheet's views.
        private func findSheetViews() -> (presentedView: UIView, containerView: UIView)? {
            if let pv = discoveredPresentedView, pv.window != nil,
               let cv = discoveredContainerView, cv.window != nil {
                return (pv, cv)
            }
            guard let window = anchorView?.window,
                  let presented = window.rootViewController?.presentedViewController,
                  let pv = presented.presentationController?.presentedView,
                  let cv = presented.presentationController?.containerView
            else { return nil }
            discoveredPresentedView = pv
            discoveredContainerView = cv
            return (pv, cv)
        }

        /// Adds the floating hosting controller's view into the sheet's containerView.
        private func setUp(content: F, containerView: UIView) {
            let child = UIHostingController(rootView: content)
            child.view.backgroundColor = .clear
            child.view.isUserInteractionEnabled = true

            // Give an initial frame so the hosting controller can lay out
            child.view.frame = CGRect(
                x: 0, y: -200,
                width: UIScreen.main.bounds.width, height: 100
            )

            containerView.addSubview(child.view)
            floatingChild = child
            isSetUp = true
        }

        @objc private func tick() {
            guard let views = findSheetViews() else { return }
            let (presentedView, containerView) = views

            // Bootstrap: create and insert the floating view
            if !isSetUp {
                guard let content = pendingContent else { return }
                pendingContent = nil
                setUp(content: content, containerView: containerView)
            }

            guard let child = floatingChild else { return }
            let childView = child.view!

            // Ensure floating view stays on top within the containerView
            // (above the sheet, but the containerView itself is below any inner sheets)
            containerView.bringSubviewToFront(childView)

            let modelY = presentedView.convert(presentedView.bounds, to: nil).minY

            // Measure size once
            if cachedSize == .zero {
                let measured = childView.sizeThatFits(
                    CGSize(width: UIScreen.main.bounds.width,
                           height: CGFloat.greatestFiniteMagnitude)
                )
                guard measured.width > 0, measured.height > 0 else { return }
                cachedSize = measured
            }

            let size = cachedSize
            let screenWidth = containerView.bounds.width
            let x = (screenWidth - size.width) / 2
            // Position in containerView coordinates (containerView is full-screen)
            let targetY = modelY - offset - size.height
            let targetFrame = CGRect(x: x, y: targetY, width: size.width, height: size.height)

            let jump = abs(modelY - lastModelY)
            let isFirstPosition = lastModelY == 0
            lastModelY = modelY

            if isFirstPosition {
                childView.frame = targetFrame
            } else if jump > 50 {
                springAnimator?.stopAnimation(true)
                let anim = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.78)
                anim.addAnimations { childView.frame = targetFrame }
                anim.startAnimation()
                springAnimator = anim
            } else if springAnimator?.isRunning == true && jump > 2 {
                springAnimator?.stopAnimation(true)
                springAnimator = nil
                childView.frame = targetFrame
            } else if springAnimator?.isRunning != true {
                childView.frame = targetFrame
            }
        }

    }
}

