import Foundation
import UIKit

// MARK: - 崩溃日志记录器
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

    // MARK: - 记录
    func logCrash(_ message: String) {
        guard isLoggingEnabled else { return }
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .medium)
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
        let lines = raw.components(separatedBy: "\n")
        return lines.suffix(limit).reversed().joined(separator: "\n")
    }

    func readRecentLog(limit: Int = 100) -> String {
        guard let raw = readLog(), !raw.isEmpty else { return "" }
        let lines = raw.components(separatedBy: "\n")
        return lines.suffix(limit).joined(separator: "\n")
    }

    func exportLogFile(tag: String = "export") -> URL? {
        logCurrentStatus(tag: tag)
        guard let raw = readLog(), !raw.isEmpty else { return nil }

        let filename = "BaoJunKeyless_error_log_\(AppDateFormatters.fileTimestamp.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try raw.write(to: url, atomically: true, encoding: .utf8)
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
