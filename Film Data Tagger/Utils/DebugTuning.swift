//
//  DebugTuning.swift
//  Film Data Tagger
//
//  Persistent scaffold for live UI tuning sliders. To experiment:
//    1. Add a property below (default = current best guess for the value)
//    2. Add a Slider somewhere visible bound to it
//    3. Read site uses `DebugTuning.shared.foo`
//  When dialed in:
//    1. Hardcode the value at the read site
//    2. Remove the property here
//    3. Remove the slider
//  The class itself persists with an empty body, ready for the next experiment.
//

#if DEBUG
import Foundation

@MainActor
@Observable
final class DebugTuning {
    static let shared = DebugTuning()
}
#endif
