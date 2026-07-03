import SwiftUI

enum VehicleEventLogCategory: String, Codable, CaseIterable, Hashable {
    case system
    case ble
    case keyless
    case plugin
    case action
    case warning
    case error

    var title: String {
        switch self {
        case .system: return "系统"
        case .ble: return "蓝牙"
        case .keyless: return "无感"
        case .plugin: return "插件"
        case .action: return "动作"
        case .warning: return "警告"
        case .error: return "错误"
        }
    }

    var fileTag: String {
        switch self {
        case .system: return "system"
        case .ble: return "ble"
        case .keyless: return "keyless"
        case .plugin: return "plugin"
        case .action: return "action"
        case .warning: return "warning"
        case .error: return "error"
        }
    }

    var icon: String {
        switch self {
        case .system: return "power"
        case .ble: return "antenna.radiowaves.left.and.right"
        case .keyless: return "key.fill"
        case .plugin: return "puzzlepiece"
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
        AppDateFormatters.logTime.string(from: date)
    }
}

final class VehicleEventLogStore: ObservableObject {
    @Published private(set) var entries: [VehicleEventLogEntry] = []

    private let key = AppDefaultsKey.VehicleEventLog.entries
    private let maxEntries = 500
    private let saveQueue = DispatchQueue(label: "BaoJunKeyless.VehicleEventLogStore.save", qos: .utility)

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
        let key = self.key
        saveQueue.async {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    var todayEntries: [VehicleEventLogEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.date) }
    }

    func exportText(entries: [VehicleEventLogEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.map { entry in
            let detail = entry.detail.isEmpty ? "" : " | \(entry.detail)"
            return "[\(AppDateFormatters.fullDateTime.string(from: entry.date))] [\(entry.category.title)] \(entry.title)\(detail)"
        }.joined(separator: "\n")
    }

    func exportFile(entries: [VehicleEventLogEntry], filterTitle: String) -> URL? {
        let text = exportText(entries: entries)
        guard !text.isEmpty else { return nil }
        let safeFilter = filterTitle.replacingOccurrences(of: " ", with: "_")
        let filename = "BaoJunKeyless_vehicle_events_\(safeFilter)_\(AppDateFormatters.fileTimestamp.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            CrashLogger.shared.logCrash("⚠️ EXPORT VEHICLE LOG FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    private func save() {
        let snapshot = entries
        let key = self.key
        saveQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([VehicleEventLogEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.date > $1.date }
    }
}
