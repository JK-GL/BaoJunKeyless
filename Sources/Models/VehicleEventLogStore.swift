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
    let firstDate: Date
    let category: VehicleEventLogCategory
    let title: String
    let detail: String
    let repeatCount: Int

    init(id: UUID = UUID(), date: Date = Date(), firstDate: Date? = nil, category: VehicleEventLogCategory, title: String, detail: String = "", repeatCount: Int = 1) {
        self.id = id
        self.date = date
        self.firstDate = firstDate ?? date
        self.category = category
        self.title = title
        self.detail = detail
        self.repeatCount = max(1, repeatCount)
    }

    enum CodingKeys: String, CodingKey {
        case id, date, firstDate, category, title, detail, repeatCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        firstDate = try c.decodeIfPresent(Date.self, forKey: .firstDate) ?? date
        category = try c.decode(VehicleEventLogCategory.self, forKey: .category)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        repeatCount = max(1, try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encode(firstDate, forKey: .firstDate)
        try c.encode(category, forKey: .category)
        try c.encode(title, forKey: .title)
        try c.encode(detail, forKey: .detail)
        try c.encode(repeatCount, forKey: .repeatCount)
    }

    var timeText: String {
        AppDateFormatters.logTime.string(from: date)
    }

    var displayTitle: String {
        repeatCount > 1 ? "\(title) ×\(repeatCount)" : title
    }

    var repeatSummaryText: String? {
        guard repeatCount > 1 else { return nil }
        let firstText = AppDateFormatters.logTime.string(from: firstDate)
        let lastText = AppDateFormatters.logTime.string(from: date)
        return "首次 \(firstText) · 最近 \(lastText) · 共 \(repeatCount) 次"
    }
}

final class VehicleEventLogStore: ObservableObject {
    static let shared = VehicleEventLogStore()

    @Published private(set) var entries: [VehicleEventLogEntry] = []

    private let key = AppDefaultsKey.VehicleEventLog.entries
    private let maxEntries = 500
    private var recentEventTimestamps: [String: Date] = [:]
    private var entryTokens: [UUID: String] = [:]

    init() {
        load()
        if entries.isEmpty {
            add(.system, "日志系统就绪", detail: "等待 BLE / 无感车控事件")
        }
    }

    func add(_ category: VehicleEventLogCategory, _ title: String, detail: String = "") {
        let token = eventToken(category: category, title: title, detail: detail, identity: nil)
        insertEntry(VehicleEventLogEntry(category: category, title: title, detail: detail), token: token)
    }

    func addThrottled(
        _ category: VehicleEventLogCategory,
        _ title: String,
        detail: String = "",
        identity: String? = nil,
        minimumInterval: TimeInterval = 2
    ) {
        let now = Date()
        let token = eventToken(category: category, title: title, detail: detail, identity: identity)
        if let last = recentEventTimestamps[token], now.timeIntervalSince(last) < minimumInterval {
            return
        }
        recentEventTimestamps[token] = now
        pruneRecentEventIndex(now: now)
        insertEntry(VehicleEventLogEntry(category: category, title: title, detail: detail), token: token)
    }

    func addCoalesced(
        _ category: VehicleEventLogCategory,
        _ title: String,
        detail: String = "",
        identity: String? = nil,
        mergeWindow: TimeInterval = 180
    ) {
        let now = Date()
        let token = eventToken(category: category, title: title, detail: detail, identity: identity)
        if let index = entries.firstIndex(where: {
            let existingToken = entryTokens[$0.id] ?? eventToken(category: $0.category, title: $0.title, detail: $0.detail, identity: nil)
            return existingToken == token && now.timeIntervalSince($0.date) <= mergeWindow
        }) {
            let existing = entries.remove(at: index)
            let updated = VehicleEventLogEntry(
                id: existing.id,
                date: now,
                firstDate: existing.firstDate,
                category: existing.category,
                title: existing.title,
                detail: existing.detail,
                repeatCount: existing.repeatCount + 1
            )
            insertEntry(updated, token: token)
            return
        }
        insertEntry(VehicleEventLogEntry(category: category, title: title, detail: detail), token: token)
    }

    func clearToday() {
        let calendar = Calendar.current
        let removedIDs = Set(entries.filter { calendar.isDateInToday($0.date) }.map(\.id))
        entries.removeAll { calendar.isDateInToday($0.date) }
        removedIDs.forEach { entryTokens.removeValue(forKey: $0) }
        recentEventTimestamps.removeAll()
        save()
    }

    func clearAll() {
        entries.removeAll()
        recentEventTimestamps.removeAll()
        entryTokens.removeAll()
        UserDefaults.standard.removeObject(forKey: key)
    }

    var todayEntries: [VehicleEventLogEntry] {
        let calendar = Calendar.current
        return entries.filter { calendar.isDateInToday($0.date) }
    }

    func exportText(entries: [VehicleEventLogEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return entries.map { entry in
            let detail = entry.detail.isEmpty ? "" : " | \(entry.detail)"
            return "[\(AppDateFormatters.fullDateTime.string(from: entry.date))] [\(entry.category.title)] \(entry.displayTitle)\(detail)"
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
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func insertEntry(_ entry: VehicleEventLogEntry, token: String) {
        entries.insert(entry, at: 0)
        entryTokens[entry.id] = token
        if entries.count > maxEntries {
            let removed = Array(entries.dropFirst(maxEntries))
            removed.forEach { entryTokens.removeValue(forKey: $0.id) }
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    private func eventToken(category: VehicleEventLogCategory, title: String, detail: String, identity: String?) -> String {
        [category.rawValue, title, identity ?? detail].joined(separator: "|")
    }

    private func pruneRecentEventIndex(now: Date) {
        if recentEventTimestamps.count <= 256 { return }
        recentEventTimestamps = recentEventTimestamps.filter {
            now.timeIntervalSince($0.value) < 600
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([VehicleEventLogEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.date > $1.date }
        entryTokens = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.id, eventToken(category: $0.category, title: $0.title, detail: $0.detail, identity: nil))
        })
    }
}
