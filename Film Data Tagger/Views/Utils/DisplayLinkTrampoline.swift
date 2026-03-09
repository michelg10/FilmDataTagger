//
//  DisplayLinkTrampoline.swift
//  Film Data Tagger
//
//  Weak-target wrapper for CADisplayLink to avoid retain cycles.
//  The display link retains the trampoline, but the trampoline only
//  weakly references the real target via its closure.
//

import Foundation

final class DisplayLinkTrampoline: NSObject {
    private let callback: () -> Void

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    @objc func fire() {
        callback()
    }
}
