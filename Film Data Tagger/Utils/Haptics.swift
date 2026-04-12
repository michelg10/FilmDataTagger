//
//  Haptics.swift
//  Film Data Tagger
//
//  Created by Michel Guo on 2/19/26.
//

@preconcurrency import CoreHaptics

enum Haptic {
    case capture
    case addPlaceholder
    case viewfinderToggle
    case sheetDetentChange
    case newRollOrCamera
    case cycleExtraExposures
    case loadUnloadRoll
    case cameraFlip

    var intensity: Float {
        switch self {
        case .capture:           return 0.36
        case .addPlaceholder:    return 0.53
        case .viewfinderToggle:  return 0.53
        case .sheetDetentChange: return 0.44
        case .newRollOrCamera:        return 0.77
        case .cycleExtraExposures:    return 0.30
        case .loadUnloadRoll:    return 0.76
        case .cameraFlip:        return 0.56
        }
    }

    var sharpness: Float {
        switch self {
        case .capture:           return 0.36
        case .addPlaceholder:    return 0.15
        case .viewfinderToggle:  return 0.21
        case .sheetDetentChange: return 0.18
        case .newRollOrCamera:        return 0.31
        case .cycleExtraExposures:    return 0.75
        case .loadUnloadRoll:    return 0.71
        case .cameraFlip:        return 0.32
        }
    }
}

private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

private let hapticQueue = DispatchQueue(label: "haptics", qos: .userInteractive)

private let hapticEngine: CHHapticEngine? = {
    guard supportsHaptics else { return nil }
    let engine = try? CHHapticEngine()
    engine?.isAutoShutdownEnabled = true
    engine?.playsHapticsOnly = true
    try? engine?.start()
    return engine
}()

@MainActor func playHaptic(_ haptic: Haptic) {
    guard supportsHaptics, !AppSettings.shared.reduceHaptics, let engine = hapticEngine else { return }
    hapticQueue.async {
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
}
