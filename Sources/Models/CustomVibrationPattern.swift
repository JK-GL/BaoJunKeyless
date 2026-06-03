import Foundation
import SwiftUI
import CoreHaptics

// MARK: - 自定义震动模式数据
struct CustomVibrationPattern: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var events: [VibrationEvent]  // 震动事件序列（时长+强度）

    struct VibrationEvent: Codable, Hashable {
        let duration: Double   // 秒
        let intensity: Double  // 0.0~1.0
    }

    init(name: String, events: [VibrationEvent]) {
        self.id = UUID()
        self.name = name
        self.events = events
    }

    // 总时长
    var totalDuration: Double {
        events.reduce(0) { $0 + $1.duration }
    }

    // 格式化时长
    var durationText: String {
        String(format: "%.1f 秒", totalDuration)
    }
}

// MARK: - 自定义震动播放（Core Haptics — 支持强度调节）
extension CustomVibrationPattern {
    func play(intensity: Double = 1.0) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        var hapticEvents: [CHHapticEvent] = []
        var time: TimeInterval = 0

        for evt in events {
            guard evt.duration > 0.01 else { continue }

            if evt.intensity > 0 {
                let i = Float(evt.intensity * intensity)
                // 叠加多层 transient 脉冲增强体感
                let layers: [(Float, Float)] = [
                    (i, 1.0),
                    (i * 0.8, 0.6),
                    (i * 0.5, 0.3),
                ]
                for (intensityVal, sharpness) in layers {
                    let params = [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensityVal),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                    ]
                    hapticEvents.append(CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: params,
                        relativeTime: time
                    ))
                }
                time += evt.duration
            } else {
                time += evt.duration
            }
        }

        guard !hapticEvents.isEmpty else { return }

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
            print("Core Haptics playback failed: \(error)")
        }
    }
}

// MARK: - 自定义震动存储
class CustomVibrationStore: ObservableObject {
    @Published var patterns: [CustomVibrationPattern] = []

    private let key = "CustomVibrationPatterns"

    init() {
        load()
    }

    func add(_ pattern: CustomVibrationPattern) {
        patterns.append(pattern)
        save()
    }

    func delete(at offsets: IndexSet) {
        patterns.remove(atOffsets: offsets)
        save()
    }

    func delete(_ pattern: CustomVibrationPattern) {
        patterns.removeAll { $0.id == pattern.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomVibrationPattern].self, from: data) else { return }
        patterns = decoded
    }
}
