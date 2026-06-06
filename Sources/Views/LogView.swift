import SwiftUI

// MARK: - Log View (Tab 3)
struct LogView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var vehicleLog: VehicleEventLogStore
    @State private var showingClearAlert = false

    private var todayLogs: [VehicleEventLogEntry] {
        vehicleLog.todayEntries
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeaderView(title: "日志")
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                CardView(title: "今日日志", icon: "list.bullet.rectangle", iconColor: theme.accent) {
                    HStack {
                        Text("真实事件记录")
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))
                            .font(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.bottom, 4)

                    if todayLogs.isEmpty {
                        EmptyLogStateView()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(todayLogs.enumerated()), id: \.element.id) { index, log in
                                VehicleLogRow(log: log, isLast: index == todayLogs.count - 1)
                            }
                        }
                    }
                }

                Button(action: { showingClearAlert = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
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
                .darkAlert(
                    isPresented: $showingClearAlert,
                    title: "清除日志",
                    message: "确定要清除今日所有车辆事件日志吗？错误日志不会清空。",
                    confirmTitle: "确认清除",
                    confirmColor: .red
                ) {
                    withAnimation { vehicleLog.clearToday() }
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

private struct EmptyLogStateView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.green)
            Text("今天暂无车辆事件")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

// MARK: - Log Row
struct VehicleLogRow: View {
    let log: VehicleEventLogEntry
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(log.category.color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: log.category.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(log.category.color)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1.5, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(log.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(log.timeText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                if !log.detail.isEmpty {
                    Text(log.detail)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }
}
