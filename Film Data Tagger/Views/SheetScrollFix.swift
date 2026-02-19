//
//  SheetScrollFix.swift
//  Film Data Tagger
//

import UIKit
import SwiftUI

struct SheetDragDisabler: UIViewControllerRepresentable {
    var isScrolling: Bool

    func makeUIViewController(context: Context) -> SheetDragDisablerController {
        SheetDragDisablerController()
    }

    func updateUIViewController(_ vc: SheetDragDisablerController, context: Context) {
        vc.setSheetGesturesEnabled(!isScrolling)
    }
}

final class SheetDragDisablerController: UIViewController {
    private var sheetPanGestures: [UIGestureRecognizer] = []
    private var discovered = false
    private var retryCount = 0

    override func loadView() {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        self.view = v
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        discoverGestures()
    }

    func setSheetGesturesEnabled(_ enabled: Bool) {
        if !discovered { discoverGestures() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for gesture in sheetPanGestures {
            gesture.isEnabled = enabled
        }
        CATransaction.commit()
    }

    private func isSheetGesture(_ gr: UIGestureRecognizer) -> Bool {
        guard gr is UIPanGestureRecognizer, !(gr is UIScreenEdgePanGestureRecognizer) else {
            return false
        }
        // Skip pan gestures owned by scroll views — those are scroll gestures, not sheet gestures
        if gr.view is UIScrollView { return false }
        return true
    }

    private func discoverGestures() {
        guard !discovered, let window = view.window else { return }

        // Walk up from our view to the window, collecting sheet pan gestures
        var current: UIView? = view.superview
        while let v = current {
            for gr in v.gestureRecognizers ?? [] {
                if isSheetGesture(gr) {
                    sheetPanGestures.append(gr)
                }
            }
            current = v.superview
        }

        // Also search window's direct children and grandchildren
        for child in window.subviews {
            for gr in child.gestureRecognizers ?? [] {
                if isSheetGesture(gr), !sheetPanGestures.contains(where: { $0 === gr }) {
                    sheetPanGestures.append(gr)
                }
            }
            for grandchild in child.subviews {
                for gr in grandchild.gestureRecognizers ?? [] {
                    if isSheetGesture(gr), !sheetPanGestures.contains(where: { $0 === gr }) {
                        sheetPanGestures.append(gr)
                    }
                }
            }
        }

        if !sheetPanGestures.isEmpty {
            discovered = true
        } else {
            retryCount += 1
            if retryCount < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.discoverGestures()
                }
            }
        }
    }
}
