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

// MARK: - 自定义震动播放（UIImpactFeedbackGenerator — 体感更强）
extension CustomVibrationPattern {
    func play() {
        for (index, evt) in events.enumerated() {
            guard evt.duration > 0.01 else { continue }

            if evt.intensity > 0 {
                let delay = computedDelay(for: index)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let g = UIImpactFeedbackGenerator(style: .rigid)
                    g.impactOccurred(intensity: evt.intensity)
                }
            }
        }
    }

    // 计算每个事件的延迟（累加前面的时长）
    private func computedDelay(for index: Int) -> TimeInterval {
        var delay: TimeInterval = 0
        for i in 0..<index {
            delay += events[i].duration
        }
        return delay
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
