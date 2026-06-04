import SwiftUI

@main
struct BaoJunKeylessApp: App {
    @StateObject private var theme = ThemeManager()

    init() {
        _ = CrashLogger.shared  // 初始化崩溃日志记录器
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
