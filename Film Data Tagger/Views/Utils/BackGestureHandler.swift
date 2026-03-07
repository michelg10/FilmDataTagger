//
//  BackGestureHandler.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 1/31/26.
//

import UIKit

/// Re-enables the interactive pop gesture when .navigationBarBackButtonHidden() is used.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}
