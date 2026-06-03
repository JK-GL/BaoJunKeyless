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

// MARK: - 自定义震动播放（Core Haptics）
extension CustomVibrationPattern {
    func play() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        var hapticEvents: [CHHapticEvent] = []
        var time: TimeInterval = 0

        for evt in events {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(evt.intensity))
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
            let hapticEvent = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: time,
                duration: evt.duration
            )
            hapticEvents.append(hapticEvent)
            time += evt.duration
        }

        guard !hapticEvents.isEmpty else { return }

        do {
            let engine = try CHHapticEngine()
            try engine.start()
            let pattern = try CHHapticPattern(events: hapticEvents, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.5) {
                engine.stop(completionHandler: nil)
            }
        } catch {
            print("Core Haptics playback failed: \(error.localizedDescription)")
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
