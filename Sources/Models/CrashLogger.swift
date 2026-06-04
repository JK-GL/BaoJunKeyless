import Foundation
import UIKit

// MARK: - 崩溃日志记录器
class CrashLogger {
    static let shared = CrashLogger()
    private let logFile: URL?

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
            let mem = Self.memoryUsage()
            CrashLogger.shared.logCrash("⚠️ MEMORY WARNING — 当前内存: \(mem)")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            CrashLogger.shared.logCrash("ℹ️ ENTERED BACKGROUND")
        }
    }

    // MARK: - 记录
    func logCrash(_ message: String) {
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

    func clearLog() {
        guard let url = logFile else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 内存使用量
    static func memoryUsage() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "未知" }
        let bytes = info.resident_size
        if bytes > 1024 * 1024 * 1024 {
            return String(format: "%.1f GB", Double(bytes) / 1024 / 1024 / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        }
    }

    // ⭐ 启动时记录内存基线
    func logMemoryBaseline() {
        let mem = Self.memoryUsage()
        logCrash("ℹ️ MEMORY BASELINE: \(mem)")
    }
}
