import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()

    init() {
        _ = CrashLogger.shared
        CrashLogger.shared.logMemoryBaseline()
        CrashLogger.shared.startMemoryMonitor()  // 每 30 秒记录内存
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .preferredColorScheme(.dark)
                .onAppear {
                    // 显示上次崩溃日志
                    if let log = CrashLogger.shared.readLog() {
                        print("=== 上次崩溃日志 ===\n\(log)")
                    }
                }
        }
    }
}
