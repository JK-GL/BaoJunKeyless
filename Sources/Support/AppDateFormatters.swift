import Foundation

final class ThreadSafeDateFormatter {
    private let formatter: DateFormatter
    private let lock = NSLock()

    init(configure: (DateFormatter) -> Void) {
        let formatter = DateFormatter()
        configure(formatter)
        self.formatter = formatter
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }

    func date(from string: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: string)
    }
}

enum AppDateFormatters {
    static let vehicleTime = ThreadSafeDateFormatter {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "HH:mm:ss"
    }

    static let fullDateTime = ThreadSafeDateFormatter {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    static let timestampMillis = ThreadSafeDateFormatter {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    static let logTime = ThreadSafeDateFormatter {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "HH:mm"
    }

    static let fileTimestamp = ThreadSafeDateFormatter {
        $0.locale = Locale(identifier: "en_US_POSIX")
        $0.dateFormat = "yyyyMMdd_HHmmss"
    }
}
