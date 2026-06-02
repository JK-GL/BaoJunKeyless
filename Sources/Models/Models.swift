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
