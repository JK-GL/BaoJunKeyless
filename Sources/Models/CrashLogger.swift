import Foundation
import UIKit

// MARK: - 崩溃/底层诊断日志
// 界面：短时间 + 中文可读摘要
// 复制/导出：DEBUG 完整时间戳 + 设备头，方便发给开发排查
class CrashLogger {
    static let shared = CrashLogger()
    private let logFile: URL?
    private let loggingKey = AppDefaultsKey.CrashLogger.enabled
    var isLoggingEnabled: Bool {
        get { UserDefaults.standard.object(forKey: loggingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: loggingKey) }
    }

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        logFile = dir?.appendingPathComponent("crash_log.txt")

        // 异常 + 信号
        NSSetUncaughtExceptionHandler { exception in
            CrashLogger.shared.logCrash("EXCEPTION: \(exception.name.rawValue)\nReason: \(exception.reason ?? "Unknown")")
        }
        signal(SIGABRT) { _ in CrashLogger.shared.logCrash("SIGNAL: SIGABRT"); signal(SIGABRT, SIG_DFL); raise(SIGABRT) }
        signal(SIGSEGV) { _ in CrashLogger.shared.logCrash("SIGNAL: SIGSEGV"); signal(SIGSEGV, SIG_DFL); raise(SIGSEGV) }
        signal(SIGBUS)  { _ in CrashLogger.shared.logCrash("SIGNAL: SIGBUS");  signal(SIGBUS, SIG_DFL);  raise(SIGBUS) }
        signal(SIGFPE)  { _ in CrashLogger.shared.logCrash("SIGNAL: SIGFPE");  signal(SIGFPE, SIG_DFL);  raise(SIGFPE) }
        signal(SIGILL)  { _ in CrashLogger.shared.logCrash("SIGNAL: SIGILL");  signal(SIGILL, SIG_DFL);  raise(SIGILL) }
        signal(SIGPIPE) { _ in CrashLogger.shared.logCrash("SIGNAL: SIGPIPE"); signal(SIGPIPE, SIG_DFL); raise(SIGPIPE) }

        // ⭐ 系统生命周期监听
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            CrashLogger.shared.logCrash("⚠️ APP WILL TERMINATE (系统杀死)")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            let mem = Self.formatBytes(Self.memoryUsageBytes())
            CrashLogger.shared.logCrash("⚠️ MEMORY WARNING — 当前内存: \(mem)")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            CrashLogger.shared.mark("Lifecycle", "background")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            CrashLogger.shared.mark("Lifecycle", "foreground")
        }
    }

    // MARK: - 记录（磁盘统一 DEBUG 时间戳）
    func logCrash(_ message: String) {
        guard isLoggingEnabled else { return }
        let timestamp = AppDateFormatters.timestampMillis.string(from: Date())
        let entry = "[\(timestamp)] \(message)\n"
        guard let data = entry.data(using: .utf8), let url = logFile else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: url, options: .atomic)
        }
        trimLogIfNeeded()
    }

    private func trimLogIfNeeded(maxLines: Int = 1000) {
        guard let url = logFile,
              let raw = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = raw.components(separatedBy: "\n")
        guard lines.count > maxLines + 100 else { return }
        let trimmed = lines.suffix(maxLines).joined(separator: "\n")
        try? trimmed.write(to: url, atomically: true, encoding: .utf8)
    }

    func readLog() -> String? {
        guard let url = logFile, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func readReversedRecentLog(limit: Int = 400) -> String {
        guard let raw = readLog(), !raw.isEmpty else { return "" }
        let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return lines.suffix(limit).reversed().joined(separator: "\n")
    }

    func readRecentLog(limit: Int = 100) -> String {
        guard let raw = readLog(), !raw.isEmpty else { return "" }
        let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return lines.suffix(limit).joined(separator: "\n")
    }

    /// 设置页界面用：短时间 + 中文可读摘要（新→旧）
    func readDisplayText(limit: Int = 200) -> String {
        let raw = readReversedRecentLog(limit: limit)
        guard !raw.isEmpty else { return "" }
        return raw
            .components(separatedBy: "\n")
            .map { Self.friendlyDisplayLine(from: $0) }
            .joined(separator: "\n")
    }

    /// 复制/导出用：DEBUG 包（完整时间 + 设备头）
    func exportDebugText(
        limit: Int = 500,
        newestFirst: Bool = true,
        tag: String = "export"
    ) -> String {
        logCurrentStatus(tag: tag)

        let rawLines: [String]
        if newestFirst {
            let text = readReversedRecentLog(limit: limit)
            rawLines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        } else {
            let text = readRecentLog(limit: limit)
            rawLines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        }

        let now = Date()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "--"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "--"
        let model = UIDevice.current.model
        let system = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let mem = Self.formatBytes(Self.memoryUsageBytes())

        var lines: [String] = []
        lines.append("=== SGMW Key Diagnostics Log (DEBUG) ===")
        lines.append("exportedAt=\(AppDateFormatters.timestampMillis.string(from: now))")
        lines.append("tag=\(tag)")
        lines.append("count=\(rawLines.count)")
        lines.append("app=SGMW Key \(version)(\(build))")
        lines.append("device=\(model) · \(system)")
        lines.append("memory=\(mem)")
        lines.append("order=\(newestFirst ? "newest-first" : "oldest-first")")
        lines.append("note=UI shows Chinese short time; this export is full debug for bug report.")
        lines.append("--- diagnostics (\(newestFirst ? "newest first" : "oldest first")) ---")
        if rawLines.isEmpty {
            lines.append("(empty)")
        } else {
            lines.append(contentsOf: rawLines)
        }
        lines.append("=== end ===")
        return lines.joined(separator: "\n")
    }

    func exportLogFile(tag: String = "export") -> URL? {
        let text = exportDebugText(limit: 800, newestFirst: true, tag: tag)
        guard text.contains("--- diagnostics") else { return nil }
        // 空日志也允许导出头信息，方便确认环境
        let filename = "SGMWKey_diagnostics_\(tag)_\(AppDateFormatters.fileTimestamp.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            logCrash("⚠️ EXPORT LOG FAILED: \(error.localizedDescription)")
            return nil
        }
    }

    func clearLog() {
        guard let url = logFile else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 界面友好行转换

    /// 把磁盘行转成设置页可读行：
    /// `14:32:05  后台  进入后台 | 详情`
    static func friendlyDisplayLine(from raw: String) -> String {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return line }

        // 1) 剥时间戳
        var rest = line
        var shortTime = "--:--:--"
        if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
            let ts = String(line[line.index(after: line.startIndex)..<close])
            shortTime = shortenTimestamp(ts)
            rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }

        // 2) 去掉 emoji 前缀噪音
        rest = rest
            .replacingOccurrences(of: "🧭 ", with: "")
            .replacingOccurrences(of: "⚠️ ", with: "")
            .replacingOccurrences(of: "ℹ️ ", with: "")

        // 3) 解析 [Component] message — MEM: ... — File:line
        var component = "系统"
        var message = rest
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            component = mapComponent(String(rest[rest.index(after: rest.startIndex)..<close]))
            message = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }

        // 去掉尾部 MEM / 源文件定位（界面不需要）
        if let memRange = message.range(of: " — MEM:") {
            message = String(message[..<memRange.lowerBound])
        } else if let memRange = message.range(of: " — mem=") {
            message = String(message[..<memRange.lowerBound])
        }
        // 中文润色常见英文词
        message = polishMessage(message)

        return "\(shortTime)  \(component)  \(message)"
    }

    private static func shortenTimestamp(_ ts: String) -> String {
        // yyyy-MM-dd HH:mm:ss.SSS → HH:mm:ss
        if ts.count >= 19, ts.contains("-"), ts.contains(":") {
            let parts = ts.split(separator: " ")
            if parts.count >= 2 {
                let time = String(parts[1])
                if time.count >= 8 {
                    return String(time.prefix(8))
                }
                return time
            }
        }
        // 本地化 medium 时间兜底：尽量取末尾时间段
        if let range = ts.range(of: #"\d{1,2}:\d{2}:\d{2}"#, options: .regularExpression) {
            return String(ts[range])
        }
        return String(ts.suffix(8))
    }

    private static func mapComponent(_ raw: String) -> String {
        switch raw.lowercased() {
        case "bg", "background": return "后台"
        case "lifecycle": return "生命周期"
        case "ble": return "蓝牙"
        case "mqtt": return "MQTT"
        case "http": return "网络"
        case "location": return "定位"
        case "cache": return "缓存"
        case "status": return "状态"
        case "sgmw": return "账号"
        case "motion": return "运动"
        case "haptics": return "震动"
        case "radar": return "雷达"
        case "addressservice": return "地址"
        default:
            if raw.isEmpty { return "系统" }
            return raw
        }
    }

    private static func polishMessage(_ message: String) -> String {
        var m = message
        let pairs: [(String, String)] = [
            ("background", "进入后台"),
            ("foreground", "回到前台"),
            ("location keep-alive start", "定位保活开启"),
            ("location keep-alive stop", "定位保活停止"),
            ("beginBackgroundTask", "开始后台任务"),
            ("endBackgroundTask", "结束后台任务"),
            ("geofence updated", "电子围栏已更新"),
            ("geofence removed", "电子围栏已移除"),
            ("status updated", "车况已更新"),
            ("status refresh failed", "车况刷新失败"),
            ("connecting", "连接中"),
            ("connected", "已连接"),
            ("disconnected", "已断开"),
            ("MEMORY WARNING", "内存警告"),
            ("MEMORY NOTICE", "内存提示"),
            ("MEMORY BASELINE", "内存基线"),
            ("APP WILL TERMINATE", "应用即将被系统结束"),
            ("no local token found", "未找到本地 Token"),
            ("queryDefaultCar failed", "查询默认车辆失败"),
            ("mqtt token fetch failed", "获取 MQTT Token 失败"),
            ("update failed", "更新失败"),
            ("pause", "已暂停"),
            ("resume", "已恢复"),
        ]
        for (en, zh) in pairs {
            if m.localizedCaseInsensitiveContains(en) {
                // 只替换整词片段，保留后续 detail
                m = m.replacingOccurrences(of: en, with: zh, options: .caseInsensitive)
            }
        }
        return m
    }

    private var memoryTimer: Timer?
    private var lastMemoryBytes: UInt64 = 0
    private var lastMemoryWarningSnapshotBytes: UInt64 = 0

    func startMemoryMonitor() {
        memoryTimer?.invalidate()

        memoryTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = Self.memoryUsageBytes()
            defer { self.lastMemoryBytes = current }

            guard self.lastMemoryBytes > 0 else { return }

            let delta = Int64(current) - Int64(self.lastMemoryBytes)
            let largeIncrease = delta >= Int64(80 * 1024 * 1024)
            let highMemory = current >= 500 * 1024 * 1024
            let highMemoryChanged = highMemory && abs(Int64(current) - Int64(self.lastMemoryWarningSnapshotBytes)) >= Int64(80 * 1024 * 1024)

            if largeIncrease || highMemoryChanged {
                let sign = delta >= 0 ? "+" : ""
                self.logCrash("⚠️ MEMORY NOTICE: \(Self.formatBytes(current)) (Δ\(sign)\(Self.formatBytes(UInt64(abs(delta)))))")
                self.lastMemoryWarningSnapshotBytes = current
            }
        }
    }

    func stopMemoryMonitor() {
        memoryTimer?.invalidate()
        memoryTimer = nil
    }

    func setLoggingEnabled(_ enabled: Bool) {
        isLoggingEnabled = enabled
        if enabled {
            startMemoryMonitor()
        } else {
            stopMemoryMonitor()
        }
    }

    static func memoryUsageBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }

    static func formatBytes(_ bytes: UInt64) -> String {
        if bytes > 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
    }

    func logMemoryBaseline() {
        let mem = Self.formatBytes(Self.memoryUsageBytes())
        logCrash("ℹ️ MEMORY BASELINE: \(mem)")
    }

    func logImageDiagnostics(_ component: String,
                             width: CGFloat,
                             height: CGFloat,
                             bytes: Int? = nil,
                             note: String? = nil,
                             file: String = #file,
                             line: Int = #line) {
        let decodedBytes = Int(width * height * 4)
        var details: [String] = ["size=\(Int(width))x\(Int(height))", "decoded≈\(Self.formatBytes(UInt64(max(decodedBytes, 0))))"]
        if let bytes {
            details.append("data=\(Self.formatBytes(UInt64(max(bytes, 0))))")
        }
        if let note {
            details.append(note)
        }
        mark(component, "image", details: details.joined(separator: " | "), file: file, line: line)
    }

    func logCurrentStatus(tag: String,
                          file: String = #file,
                          line: Int = #line) {
        let defaults = UserDefaults.standard
        let details = [
            "tag=\(tag)",
            "mem=\(Self.formatBytes(Self.memoryUsageBytes()))",
            "bgOff=\(defaults.bool(forKey: AppDiagnosticsSettings.disableBackgroundImageKey))",
            "blurOff=\(defaults.bool(forKey: AppDiagnosticsSettings.disableBackgroundBlurKey))",
            "previewOff=\(defaults.bool(forKey: AppDiagnosticsSettings.disableThemePreviewKey))",
            "radarOff=\(defaults.bool(forKey: AppDiagnosticsSettings.disableRadarKey))",
            "sfCar=\(defaults.bool(forKey: AppDiagnosticsSettings.useSFRadarCarIconKey))"
        ].joined(separator: " | ")
        mark("Status", "snapshot", details: details, file: file, line: line)
    }

    func logEvent(_ component: String, _ message: String, file: String = #file, line: Int = #line) {
        let current = Self.formatBytes(Self.memoryUsageBytes())
        let src = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        logCrash("🧭 [\(component)] \(message) — MEM: \(current) — \(src):\(line)")
    }

    func mark(_ component: String, _ message: String, details: String? = nil, file: String = #file, line: Int = #line) {
        let body = [message, details].compactMap { $0 }.joined(separator: " | ")
        logEvent(component, body, file: file, line: line)
    }
}
