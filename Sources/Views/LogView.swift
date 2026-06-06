import SwiftUI
import UIKit

private enum VehicleLogFilter: Hashable, CaseIterable {
    case all
    case category(VehicleEventLogCategory)

    static var allCases: [VehicleLogFilter] {
        [.all] + VehicleEventLogCategory.allCases.map { .category($0) }
    }

    var title: String {
        switch self {
        case .all: return "全部"
        case .category(let category): return category.title
        }
    }

    var fileTag: String {
        switch self {
        case .all: return "all"
        case .category(let category): return category.fileTag
        }
    }
}

// MARK: - Log View (Tab 3)
struct LogView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var vehicleLog: VehicleEventLogStore
    @State private var showingClearAlert = false
    @State private var selectedFilter: VehicleLogFilter = .all
    @State private var exportedLogURL: URL?
    @State private var isShareSheetPresented = false
    @State private var toastText: String?

    private var todayLogs: [VehicleEventLogEntry] {
        vehicleLog.todayEntries
    }

    private var filteredLogs: [VehicleEventLogEntry] {
        switch selectedFilter {
        case .all:
            return todayLogs
        case .category(let category):
            return todayLogs.filter { $0.category == category }
        }
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

                    VehicleLogFilterBar(selectedFilter: $selectedFilter)
                        .padding(.bottom, 8)

                    if filteredLogs.isEmpty {
                        EmptyLogStateView(filterTitle: selectedFilter.title)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredLogs.enumerated()), id: \.element.id) { index, log in
                                VehicleLogRow(log: log, isLast: index == filteredLogs.count - 1)
                            }
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 12)], alignment: .leading, spacing: 10) {
                    LogActionButton(icon: "doc.on.doc", title: "复制今日", action: copyFilteredLogs)
                    LogActionButton(icon: "square.and.arrow.up", title: "导出今日", action: exportFilteredLogs)
                    LogActionButton(icon: "trash", title: "清除今日") {
                        showingClearAlert = true
                    }
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
        .sheet(isPresented: $isShareSheetPresented) {
            if let exportedLogURL {
                ShareSheet(activityItems: [exportedLogURL])
            }
        }
        .overlay(alignment: .bottom) {
            if let text = toastText {
                ToastView(text: text)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { toastText = nil }
                        }
                    }
            }
        }
        .onDisappear {
            scrollState.reset()
        }
    }

    private func copyFilteredLogs() {
        let text = vehicleLog.exportText(entries: filteredLogs)
        guard !text.isEmpty else {
            withAnimation { toastText = "暂无可复制日志" }
            return
        }
        UIPasteboard.general.string = text
        withAnimation { toastText = "已复制今日日志" }
    }

    private func exportFilteredLogs() {
        guard let url = vehicleLog.exportFile(entries: filteredLogs, filterTitle: selectedFilter.fileTag) else {
            withAnimation { toastText = "暂无日志可导出" }
            return
        }
        exportedLogURL = url
        isShareSheetPresented = true
    }
}

private struct VehicleLogFilterBar: View {
    @Binding var selectedFilter: VehicleLogFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VehicleLogFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedFilter == filter ? .black : Color.white.opacity(0.68))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedFilter == filter ? AppTheme.accent : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct LogActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyLogStateView: View {
    let filterTitle: String

    private var message: String {
        filterTitle == "全部" ? "今天暂无车辆事件" : "今天暂无\(filterTitle)事件"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.green)
            Text(message)
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
