import SwiftUI

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

struct LogEntry: Identifiable {
    let id = UUID()
    let time: String
    let icon: String
    let color: Color
    let title: String
    let detail: String
}

// MARK: - Vibration Pattern
enum VibrationPattern: String, CaseIterable {
    case shortSingle    = "短促单震"
    case longShortDouble = "长短双震"
    case continuousLight = "连续轻震"
    case heavyStrong    = "厚重强震"
    case rhythmic       = "间歇节奏"

    func play() {
        switch self {
        case .shortSingle:
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.impactOccurred()
        case .longShortDouble:
            let g = UIImpactFeedbackGenerator(style: .heavy)
            g.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .continuousLight:
            let g = UIImpactFeedbackGenerator(style: .light)
            g.prepare()
            for i in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.07) {
                    g.impactOccurred()
                }
            }
        case .heavyStrong:
            let g = UIImpactFeedbackGenerator(style: .rigid)
            g.impactOccurred(intensity: 1.0)
        case .rhythmic:
            let g = UIImpactFeedbackGenerator(style: .medium)
            g.prepare()
            [0.0, 0.15, 0.4, 0.55, 0.8].forEach { delay in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    g.impactOccurred()
                }
            }
        }
    }
}
