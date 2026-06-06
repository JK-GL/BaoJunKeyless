import SwiftUI
import CoreHaptics

// MARK: - Data Models

struct GaugeItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let maxValue: String
    let percent: Double
    let color: Color
}

struct TempItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color
}

struct StatusItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let color: Color
}

struct KeyInfoItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
}

// MARK: - Vibration Pattern
enum VibrationPattern: String, CaseIterable {
    case shortSingle    = "短促单震"
    case longShortDouble = "长短双震"
    case continuousLight = "连续轻震"
    case heavyStrong    = "厚重强震"
    case rhythmic       = "间歇节奏"

    func play(intensity: Double = 1.0) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            // Fallback for older devices
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.impactOccurred(intensity: intensity)
            return
        }

        var hapticEvents: [CHHapticEvent] = []
        var time: TimeInterval = 0
        let i = Float(max(min(intensity, 1.0), 0.0))

        func addEvent(_ type: CHHapticEvent.EventType, duration: Double, sharpness: Float = 1.0) {
            let params = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ]
            hapticEvents.append(CHHapticEvent(eventType: type, parameters: params, relativeTime: time, duration: duration))
            // 叠加第二层增强
            if type == .hapticTransient {
                let extra = [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: i * 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ]
                hapticEvents.append(CHHapticEvent(eventType: .hapticTransient, parameters: extra, relativeTime: time))
            }
            time += duration
        }

        func addPause(_ duration: Double) {
            time += duration
        }

        switch self {
        case .shortSingle:
            addEvent(.hapticTransient, duration: 0.15)
        case .longShortDouble:
            addEvent(.hapticTransient, duration: 0.12)
            addPause(0.25)
            addEvent(.hapticTransient, duration: 0.08)
            addEvent(.hapticTransient, duration: 0.12)
        case .continuousLight:
            for _ in 0..<6 {
                addEvent(.hapticTransient, duration: 0.05)
                addPause(0.06)
            }
        case .heavyStrong:
            addEvent(.hapticContinuous, duration: 0.4, sharpness: 1.0)
        case .rhythmic:
            [0.12, 0.08, 0.15, 0.08, 0.20].forEach { d in
                addEvent(.hapticTransient, duration: d)
                addPause(0.1)
            }
        }

        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + time + 0.5) {
                engine.stop(completionHandler: nil)
            }
        } catch {
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.impactOccurred(intensity: intensity)
        }
    }
}
