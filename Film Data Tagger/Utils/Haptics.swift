//
//  Haptics.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

import CoreHaptics

enum Haptic {
    case capture
    case addPlaceholder
    case viewfinderToggle
    case sheetDetentChange
    case finishRoll

    var intensity: Float {
        switch self {
        case .capture:           return 0.36
        case .addPlaceholder:    return 0.53
        case .viewfinderToggle:  return 0.53
        case .sheetDetentChange: return 0.44
        case .finishRoll:        return 0.77
        }
    }

    var sharpness: Float {
        switch self {
        case .capture:           return 0.36
        case .addPlaceholder:    return 0.15
        case .viewfinderToggle:  return 0.21
        case .sheetDetentChange: return 0.18
        case .finishRoll:        return 0.31
        }
    }
}

private let hapticEngine: CHHapticEngine? = {
    let engine = try? CHHapticEngine()
    engine?.isAutoShutdownEnabled = true
    engine?.playsHapticsOnly = true
    return engine
}()

func playHaptic(_ haptic: Haptic) {
    guard let engine = hapticEngine else { return }
    try? engine.start()
    let event = CHHapticEvent(
        eventType: .hapticTransient,
        parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: haptic.intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: haptic.sharpness),
        ],
        relativeTime: 0
    )
    try? engine.makePlayer(with: CHHapticPattern(events: [event], parameters: [])).start(atTime: 0)
}
