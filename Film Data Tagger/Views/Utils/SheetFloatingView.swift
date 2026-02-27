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
    /// Pass `height` to skip automatic measurement.
    /// `compensationPoints` maps sheet heights to offset adjustments, linearly interpolated and clamped.
    func sheetFloatingView<F: View>(
        offset: CGFloat = 20,
        height: CGFloat? = nil,
        compensationPoints: [(sheetHeight: CGFloat, compensation: CGFloat)] = [],
        @ViewBuilder content: @escaping () -> F
    ) -> some View {
        background(SheetFloatingBridge(offset: offset, fixedHeight: height, compensationPoints: compensationPoints, floatingContent: content))
    }
}

// MARK: - Bridge

private struct SheetFloatingBridge<F: View>: UIViewRepresentable {
    let offset: CGFloat
    let fixedHeight: CGFloat?
    let compensationPoints: [(sheetHeight: CGFloat, compensation: CGFloat)]
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
        context.coordinator.anchorView = uiView
        context.coordinator.offset = offset
        context.coordinator.fixedHeight = fixedHeight
        context.coordinator.compensationPoints = compensationPoints
        if let child = context.coordinator.floatingChild {
            child.rootView = floatingContent()
            context.coordinator.invalidateSize()
        } else {
            context.coordinator.pendingContent = floatingContent()
        }
        context.coordinator.installOrUpdateFloatingViewIfPossible()
        DispatchQueue.main.async {
            context.coordinator.installOrUpdateFloatingViewIfPossible()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        weak var anchorView: UIView?
        var offset: CGFloat = 20
        var fixedHeight: CGFloat?
        var pendingContent: F?

        var floatingChild: UIHostingController<F>?
        var isSetUp = false

        var cachedSize: CGSize = .zero
        var measuredWidth: CGFloat = .zero

        weak var discoveredPresentedView: UIView?
        weak var discoveredContainerView: UIView?
        var activeConstraints: [NSLayoutConstraint] = []
        var bottomConstraint: NSLayoutConstraint?
        var heightConstraint: NSLayoutConstraint?
        var usesFixedHeightLayout: Bool?

        var compensationPoints: [(sheetHeight: CGFloat, compensation: CGFloat)] = [] {
            didSet {
                sortedCompensationPoints = compensationPoints.sorted { $0.sheetHeight < $1.sheetHeight }
            }
        }
        private var sortedCompensationPoints: [(sheetHeight: CGFloat, compensation: CGFloat)] = []
        private var positionObservation: NSKeyValueObservation?
        private var lastCompensation: CGFloat = 0

        func invalidateSize() {
            cachedSize = .zero
            measuredWidth = .zero
        }

        func startObservingPosition(of presentedView: UIView) {
            guard positionObservation == nil else { return }
            applyCompensation(for: presentedView.layer)
            positionObservation = presentedView.layer.observe(\.position, options: [.new]) { [weak self] layer, _ in
                self?.applyCompensation(for: layer)
            }
        }

        private func applyCompensation(for layer: CALayer) {
            guard !sortedCompensationPoints.isEmpty else { return }
            let sheetHeight = layer.frame.height
            guard sheetHeight > 0 else { return }
            let compensation = interpolateCompensation(for: sheetHeight)
            guard compensation != lastCompensation else { return }
            lastCompensation = compensation
            bottomConstraint?.constant = -offset + compensation
        }

        private func interpolateCompensation(for sheetHeight: CGFloat) -> CGFloat {
            let sorted = sortedCompensationPoints
            guard sorted.count >= 2 else {
                return sorted.first?.compensation ?? 0
            }
            // Clamp below first point
            if sheetHeight <= sorted.first!.sheetHeight {
                return sorted.first!.compensation
            }
            // Clamp above last point
            if sheetHeight >= sorted.last!.sheetHeight {
                return sorted.last!.compensation
            }
            // Find the two surrounding points and lerp
            for i in 0..<(sorted.count - 1) {
                let lo = sorted[i]
                let hi = sorted[i + 1]
                if sheetHeight >= lo.sheetHeight && sheetHeight <= hi.sheetHeight {
                    let t = (sheetHeight - lo.sheetHeight) / (hi.sheetHeight - lo.sheetHeight)
                    return lo.compensation + t * (hi.compensation - lo.compensation)
                }
            }
            return 0
        }

        /// Finds the first presented sheet's views.
        private func findSheetViews() -> (presentedView: UIView, containerView: UIView)? {
            guard let window = anchorView?.window,
                  let presented = window.rootViewController?.presentedViewController,
                  let pv = presented.presentationController?.presentedView,
                  let cv = presented.presentationController?.containerView
            else { return nil }
            return (pv, cv)
        }

        /// Adds the floating hosting controller's view into the sheet's containerView.
        private func setUp(content: F, containerView: UIView) {
            let child = UIHostingController(rootView: content)
            child.view.backgroundColor = .clear
            child.view.isUserInteractionEnabled = true
            child.view.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(child.view)
            floatingChild = child
            isSetUp = true
        }

        private func ensureZOrder(childView: UIView, above presentedView: UIView, in containerView: UIView) {
            guard childView.superview === containerView else { return }
            let childIndex = containerView.subviews.firstIndex(of: childView)
            let presentedIndex = containerView.subviews.firstIndex(of: presentedView)
            guard let childIndex, let presentedIndex, childIndex <= presentedIndex else { return }
            containerView.insertSubview(childView, aboveSubview: presentedView)
        }

        private func measureSizeIfNeeded(childView: UIView, maxWidth: CGFloat) -> CGSize {
            guard fixedHeight == nil else {
                return CGSize(width: maxWidth, height: fixedHeight ?? 0)
            }
            if cachedSize == .zero || measuredWidth != maxWidth {
                let measured = childView.sizeThatFits(
                    CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
                )
                guard measured.width > 0, measured.height > 0 else { return .zero }
                cachedSize = measured
                measuredWidth = maxWidth
            }
            return cachedSize
        }

        private func rebuildConstraintsIfNeeded(
            childView: UIView,
            presentedView: UIView,
            containerView: UIView
        ) -> Bool {
            guard containerView.bounds.width > 0 else { return false }
            NSLayoutConstraint.deactivate(activeConstraints)
            activeConstraints.removeAll()
            bottomConstraint = nil
            heightConstraint = nil

            let bottom = childView.bottomAnchor.constraint(equalTo: presentedView.topAnchor, constant: -offset)
            var constraints: [NSLayoutConstraint] = [bottom]

            if let fixedHeight {
                constraints.append(childView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor))
                constraints.append(childView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor))
                let height = childView.heightAnchor.constraint(equalToConstant: fixedHeight)
                constraints.append(height)
                heightConstraint = height
            } else {
                let size = measureSizeIfNeeded(childView: childView, maxWidth: containerView.bounds.width)
                guard size != .zero else { return false }
                constraints.append(childView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor))
                constraints.append(childView.widthAnchor.constraint(equalToConstant: size.width))
                let height = childView.heightAnchor.constraint(equalToConstant: size.height)
                constraints.append(height)
                heightConstraint = height
            }

            NSLayoutConstraint.activate(constraints)
            activeConstraints = constraints
            bottomConstraint = bottom
            usesFixedHeightLayout = fixedHeight != nil
            return true
        }

        func installOrUpdateFloatingViewIfPossible() {
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
            let containerChanged = childView.superview !== containerView
                || discoveredPresentedView !== presentedView
                || discoveredContainerView !== containerView

            if containerChanged {
                if childView.superview !== containerView {
                    childView.removeFromSuperview()
                    containerView.addSubview(childView)
                }
                let didBuildConstraints = rebuildConstraintsIfNeeded(
                    childView: childView,
                    presentedView: presentedView,
                    containerView: containerView
                )
                if didBuildConstraints {
                    discoveredPresentedView = presentedView
                    discoveredContainerView = containerView
                }
            } else {
                let wantsFixedHeightLayout = fixedHeight != nil
                if usesFixedHeightLayout != wantsFixedHeightLayout {
                    _ = rebuildConstraintsIfNeeded(
                        childView: childView,
                        presentedView: presentedView,
                        containerView: containerView
                    )
                }
                bottomConstraint?.constant = -offset + lastCompensation
                if let fixedHeight {
                    heightConstraint?.constant = fixedHeight
                } else if measuredWidth != containerView.bounds.width {
                    _ = rebuildConstraintsIfNeeded(
                        childView: childView,
                        presentedView: presentedView,
                        containerView: containerView
                    )
                }
            }

            ensureZOrder(childView: childView, above: presentedView, in: containerView)
            startObservingPosition(of: presentedView)
        }
    }
}
