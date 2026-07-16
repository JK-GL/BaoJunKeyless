import Foundation
import Combine

/// 本 App 系统推送历史（日志页「推送收集」用）。
/// 只收 App 主动发出的本地通知，不读系统其它 App。
struct AppPushRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    let body: String
    /// keyless / powerOff / background / other
    let source: String
    /// 系统通知是否实际允许发出（权限拒绝时仍记录，delivered=false）
    let delivered: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        body: String,
        source: String,
        delivered: Bool
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.source = source
        self.delivered = delivered
    }

    var timeText: String {
        AppDateFormatters.logTime.string(from: date)
    }

    var sourceTitle: String {
        switch source {
        case "keyless": return "无感"
        case "powerOff": return "熄火"
        case "background": return "后台"
        default: return "其他"
        }
    }
}

final class NotificationHistoryStore: ObservableObject {
    static let shared = NotificationHistoryStore()

    static let maxEntries = 50
    private let storageKey = "NotificationHistoryStore.entries.v1"

    @Published private(set) var entries: [AppPushRecord] = []

    private init() {
        load()
    }

    var todayEntries: [AppPushRecord] {
        let cal = Calendar.current
        return entries.filter { cal.isDateInToday($0.date) }
    }

    var todayCount: Int { todayEntries.count }

    var latest: AppPushRecord? { entries.first }

    func add(title: String, body: String, source: String = "other", delivered: Bool) {
        let work = {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return }

            // 1 秒内同 title+body 合并，避免双发刷屏。
            if let first = self.entries.first,
               first.title == trimmedTitle,
               first.body == trimmedBody,
               Date().timeIntervalSince(first.date) < 1.0 {
                return
            }

            let record = AppPushRecord(
                title: trimmedTitle.isEmpty ? "(无标题)" : trimmedTitle,
                body: trimmedBody,
                source: source,
                delivered: delivered
            )
            self.entries.insert(record, at: 0)
            if self.entries.count > Self.maxEntries {
                self.entries = Array(self.entries.prefix(Self.maxEntries))
            }
            self.save()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func clear() {
        let work = {
            self.entries.removeAll()
            self.save()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    func exportText(limit: Int = 50) -> String {
        let list = Array(entries.prefix(limit))
        guard !list.isEmpty else { return "暂无推送记录" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return list.map { item in
            let flag = item.delivered ? "已发出" : "未授权/未发出"
            return "[\(formatter.string(from: item.date))] [\(item.sourceTitle)] [\(flag)] \(item.title)\n\(item.body)"
        }.joined(separator: "\n\n")
    }

    /// 根据标题粗分来源，调用方可覆盖。
    static func inferSource(title: String) -> String {
        if title.contains("熄火") { return "powerOff" }
        if title.contains("后台") || title.contains("限制") { return "background" }
        if title.contains("无感") || title.contains("上锁") || title.contains("解锁") {
            return "keyless"
        }
        return "other"
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AppPushRecord].self, from: data) else {
            entries = []
            return
        }
        entries = Array(decoded.prefix(Self.maxEntries))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
