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
            CrashLogger.shared.logCrash("⚠️ MEMORY WARNING (内存警告)")
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
}
