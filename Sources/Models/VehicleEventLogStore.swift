import SwiftUI

enum VehicleEventLogCategory: String, Codable, CaseIterable, Equatable {
    case system
    case ble
    case keyless
    case plugin
    case action
    case warning
    case error

    var icon: String {
        switch self {
        case .system: return "power"
        case .ble: return "antenna.radiowaves.left.and.right"
        case .keyless: return "key.fill"
        case .plugin: return "shield.fill"
        case .action: return "bolt.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .system: return .secondary
        case .ble: return .blue
        case .keyless: return AppTheme.green
        case .plugin: return AppTheme.purple
        case .action: return AppTheme.orange
        case .warning: return AppTheme.orange
        case .error: return AppTheme.red
        }
    }
}

struct VehicleEventLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let category: VehicleEventLogCategory
    let title: String
    let detail: String

    init(id: UUID = UUID(), date: Date = Date(), category: VehicleEventLogCategory, title: String, detail: String = "") {
        self.id = id
        self.date = date
        self.category = category
        self.title = title
        self.detail = detail
    }

    var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

final class VehicleEventLogStore: ObservableObject {
    @Published private(set) var entries: [VehicleEventLogEntry] = []

    private let key = "VehicleEventLogs"
    private let maxEntries = 500

    init() {
        load()
        if entries.isEmpty {
            add(.system, "日志系统就绪", detail: "等待 BLE / 无感车控事件")
        }
    }

    func add(_ category: VehicleEventLogCategory, _ title: String, detail: String = "") {
        entries.insert(VehicleEventLogEntry(category: category, title: title, detail: detail), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clearToday() {
        let calendar = Calendar.current
        entries.removeAll { calendar.isDateInToday($0.date) }
        save()
    }

    func clearAll() {
        entries.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }

    var todayEntries: [VehicleEventLogEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.date) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([VehicleEventLogEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.date > $1.date }
    }
}
