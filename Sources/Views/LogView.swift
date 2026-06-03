import SwiftUI

// MARK: - Log View (Tab 3)
struct LogView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @State private var logs: [LogEntry] = [
        LogEntry(time: "14:52", icon: "lock.open.fill", color: .green,
                 title: "无感解锁", detail: "信号强度: -48 dBm → 阈值: -48 dBm"),
        LogEntry(time: "14:30", icon: "bolt.fill", color: .orange,
                 title: "远程启动", detail: "发动机预热 5 分钟"),
        LogEntry(time: "13:15", icon: "lock.fill", color: .red,
                 title: "无感上锁", detail: "延迟 15s 后执行, RSSI: -72 dBm"),
        LogEntry(time: "12:00", icon: "location.fill", color: .purple,
                 title: "寻车闪灯", detail: "双闪+喇叭鸣响"),
        LogEntry(time: "10:30", icon: "bolt.fill", color: .blue,
                 title: "BLE 钥匙加载", detail: "从五菱 APP 读取钥匙数据成功"),
        LogEntry(time: "10:28", icon: "antenna.radiowaves.left.and.right", color: .blue,
                 title: "BLE 连接", detail: "连接到 E260-BLE (CC:45:A5:DA:B5:C3)"),
        LogEntry(time: "10:25", icon: "power", color: .secondary,
                 title: "插件启动", detail: "BaojunBLEHUD v1.0.0 初始化")
    ]

    @State private var showingClearAlert = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "日志")
                    .padding(.leading, 20)
                    .padding(.top, 8)

                CardView(title: "今日日志", icon: "list.bullet.rectangle", iconColor: theme.accent) {
                    HStack {
                        Spacer()
                        Text(DateFormatter.localizedString(from: Date(),
                                                           dateStyle: .medium, timeStyle: .none))
                            .font(.caption).foregroundStyle(theme.textSecondary)
                    }
                    .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                            LogRow(log: log, isLast: index == logs.count - 1)
                        }
                    }
                }

                Button(action: { showingClearAlert = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13))
                        Text("清除今日日志")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .padding(.horizontal, 16)
                .alert("清除日志", isPresented: $showingClearAlert) {
                    Button("取消", role: .cancel) { }
                    Button("确认清除", role: .destructive) {
                        withAnimation { logs.removeAll() }
                    }
                } message: {
                    Text("确定要清除今日所有日志吗？此操作不可撤销。")
                }

                Spacer(minLength: 100)
            }
        }
        .modifier(ChromeScrollTrackingModifier(scrollState: scrollState))
        .onDisappear {
            scrollState.reset()
        }
    }
}

// MARK: - Log Row
struct LogRow: View {
    let log: LogEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(log.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: log.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(log.color)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1.5, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(log.title)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(log.time)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(log.detail)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }
}
