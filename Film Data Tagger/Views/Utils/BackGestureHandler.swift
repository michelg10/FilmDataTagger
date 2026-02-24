//
//  BackGestureHandler.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import UIKit

extension Notification.Name {
    static let backGestureBegan = Notification.Name("backGestureBegan")
    static let backGestureCancelled = Notification.Name("backGestureCancelled")
}

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        interactivePopGestureRecognizer?.addTarget(self, action: #selector(handlePopGesture(_:)))
    }

    @objc func handlePopGesture(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            NotificationCenter.default.post(name: .backGestureBegan, object: nil)
            let vcCount = viewControllers.count
            var coordinatorGoneLastTick = false
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                // Pop succeeded — VC was removed
                if self.viewControllers.count < vcCount {
                    timer.invalidate()
                    return
                }
                // Wait an extra tick after coordinator clears before deciding
                if self.transitionCoordinator == nil {
                    if coordinatorGoneLastTick {
                        timer.invalidate()
                        NotificationCenter.default.post(name: .backGestureCancelled, object: nil)
                    } else {
                        coordinatorGoneLastTick = true
                    }
                }
            }
        }
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}
