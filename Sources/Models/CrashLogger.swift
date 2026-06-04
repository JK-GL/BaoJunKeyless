import Foundation

// MARK: - 崩溃日志记录器
class CrashLogger {
    static let shared = CrashLogger()
    private let logFile: URL?

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        logFile = dir?.appendingPathComponent("crash_log.txt")

        // 注册崩溃处理器
        NSSetUncaughtExceptionHandler(exceptionHandler)
        signal(SIGABRT, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGBUS, signalHandler)
        signal(SIGFPE, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGPIPE, signalHandler)
    }

    // MARK: - 记录崩溃信息
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

    // MARK: - 读取崩溃日志
    func readLog() -> String? {
        guard let url = logFile, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 清空日志
    func clearLog() {
        guard let url = logFile else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 异常处理器
    private let exceptionHandler: NSUncaughtExceptionHandler? = { exception in
        let reason = exception.reason ?? "Unknown"
        let name = exception.name.rawValue
        CrashLogger.shared.logCrash("EXCEPTION: \(name)\nReason: \(reason)\nStack: \(exception.callStackSymbols.joined(separator: "\n"))")
    }

    // MARK: - 信号处理器
    private let signalHandler: @convention(c) (Int32) -> Void = { signal in
        let name: String
        switch signal {
        case SIGABRT: name = "SIGABRT"
        case SIGSEGV: name = "SIGSEGV"
        case SIGBUS:  name = "SIGBUS"
        case SIGFPE:  name = "SIGFPE"
        case SIGILL:  name = "SIGILL"
        case SIGPIPE: name = "SIGPIPE"
        default:      name = "SIGNAL(\(signal))"
        }
        CrashLogger.shared.logCrash("SIGNAL: \(name)")
        // 重新触发信号让系统处理
        signal(signal, SIG_DFL)
        raise(signal)
    }
}
