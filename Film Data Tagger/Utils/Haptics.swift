//
//  Haptics.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import CoreHaptics

private let hapticEngine: CHHapticEngine? = {
    let engine = try? CHHapticEngine()
    engine?.isAutoShutdownEnabled = true
    engine?.playsHapticsOnly = true
    return engine
}()

func playHaptic(intensity: Float, sharpness: Float) {
    guard let engine = hapticEngine else { return }
    try? engine.start()
    let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ],
        relativeTime: 0
    )
    try? engine.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
}
