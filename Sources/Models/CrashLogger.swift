import Foundation
import UIKit

// MARK: - 崩溃日志记录器
class CrashLogger {
    static let shared = CrashLogger()
    private let logFile: URL?
    private let loggingKey = "CrashLoggerEnabled"
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
            CrashLogger.shared.logCrash("ℹ️ ENTERED BACKGROUND")
            CrashLogger.shared.mark("Lifecycle", "background")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            CrashLogger.shared.logCrash("ℹ️ WILL ENTER FOREGROUND")
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
    }

    func readLog() -> String? {
        guard let url = logFile, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func readReversedRecentLog(limit: Int = 400) -> String {
        guard let raw = readLog(), !raw.isEmpty else { return "" }
        let lines = raw.components(separatedBy: "\n")
        let tail = lines.suffix(limit)
        return tail.reversed().joined(separator: "\n")
    }

    func clearLog() {
        guard let url = logFile else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private var memoryTimer: Timer?
    private var lastMemoryBytes: UInt64 = 0

    func startMemoryMonitor() {
        memoryTimer?.invalidate()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let current = Self.memoryUsageBytes()
            if self.lastMemoryBytes == 0 || current != self.lastMemoryBytes {
                let delta = Int64(current) - Int64(self.lastMemoryBytes)
                let sign = delta >= 0 ? "+" : ""
                self.logCrash("📊 MEMORY: \(Self.formatBytes(current)) (Δ\(sign)\(Self.formatBytes(UInt64(abs(delta)))))")
                self.lastMemoryBytes = current
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
