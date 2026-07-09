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

// MARK: - Log View (控制台窗口，固定区域内滚动)
struct LogView: View {
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var scrollState: AppScrollState
    @EnvironmentObject var vehicleLog: VehicleEventLogStore
    @State private var showingClearAlert = false
    @State private var selectedFilter: VehicleLogFilter = .all
    @State private var sharePayload: SharePayload?
    @State private var toastText: String?
    @State private var expandedIDs: Set<UUID> = []
    @State private var autoFollow = true
    @AppStorage("LogView.ExpandedIDs") private var persistedExpandedIDs = ""
    @AppStorage("LogView.AutoExpandAllDetails") private var autoExpandAllDetails = false

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

    private var errorCount: Int {
        todayLogs.filter { $0.category == .error || $0.category == .warning }.count
    }

    private var expandableLogIDs: Set<UUID> {
        Set(filteredLogs.filter { !$0.detail.isEmpty }.map(\.id))
    }

    private var hasExpandableLogs: Bool {
        !expandableLogIDs.isEmpty
    }

    private var allDetailsExpanded: Bool {
        hasExpandableLogs && expandableLogIDs.isSubset(of: expandedIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeaderView(title: "日志")
                .padding(.horizontal, 20)
                .padding(.top, 8)

            // 顶部摘要 + 筛选，固定不随日志无限拉长
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    consoleBadge(text: "今日 \(todayLogs.count)", color: theme.accent)
                    consoleBadge(text: "告警 \(errorCount)", color: errorCount > 0 ? AppTheme.orange : theme.textSecondary)
                    consoleBadge(text: selectedFilter.title, color: theme.textSecondary)
                    Spacer(minLength: 0)
                }

                VehicleLogFilterBar(selectedFilter: $selectedFilter)
            }
            .padding(.horizontal, 20)

            // 核心：固定高度控制台窗口，内部滚动
            consoleWindow
                .padding(.horizontal, 16)

            // 底部动作条固定
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], alignment: .leading, spacing: 6) {
                LogActionButton(icon: "doc.on.doc", title: "复制", action: copyFilteredLogs)
                LogActionButton(icon: "square.and.arrow.up", title: "导出", action: exportFilteredLogs)
                LogActionButton(icon: "arrow.up.left.and.arrow.down.right", title: allDetailsExpanded ? "全收起" : "全展开") {
                    toggleExpandAllDetails()
                }
                LogActionButton(icon: "arrow.down.to.line", title: autoFollow ? "跟随开" : "跟随关") {
                    autoFollow.toggle()
                }
                LogActionButton(icon: "trash", title: "清除") {
                    showingClearAlert = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.activityItems)
        }
        .overlay {
            if showingClearAlert {
                CustomAlertView(
                    title: "清除日志",
                    message: "确定要清除今日所有车辆事件日志吗？",
                    confirmTitle: "确认清除",
                    confirmColor: .red,
                    onCancel: { withAnimation(PopupMotion.dismissEase) { showingClearAlert = false } },
                    onConfirm: {
                        withAnimation(PopupMotion.dismissEase) { showingClearAlert = false }
                        withAnimation {
                            vehicleLog.clearToday()
                            expandedIDs.removeAll()
                            autoExpandAllDetails = false
                            persistExpandedIDs()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(PopupMotion.transition)
            }
        }
        .overlay(alignment: .bottom) {
            if let text = toastText {
                ToastView(text: text)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { toastText = nil }
                        }
                    }
            }
        }
        .animation(PopupMotion.presentSpring, value: showingClearAlert)
        .onAppear {
            restoreExpandedIDs()
            applyExpansionMemoryForCurrentFilter()
            // 日志页本身不再整页滚动，避免外层 chrome 误判
            scrollState.reset()
        }
        .onDisappear {
            scrollState.reset()
        }
    }

    private var consoleWindow: some View {
        GeometryReader { geo in
            let windowHeight = max(geo.size.height, 280)
            VStack(spacing: 0) {
                if filteredLogs.isEmpty {
                    EmptyLogStateView(filterTitle: selectedFilter.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredLogs) { log in
                                    ConsoleLogRow(
                                        log: log,
                                        expanded: expandedIDs.contains(log.id),
                                        onToggle: {
                                            autoExpandAllDetails = false
                                            if expandedIDs.contains(log.id) {
                                                expandedIDs.remove(log.id)
                                            } else {
                                                expandedIDs.insert(log.id)
                                            }
                                            persistExpandedIDs()
                                        }
                                    )
                                    .id(log.id)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onAppear {
                            scrollToLatest(proxy: proxy, animated: false)
                        }
                        .onChange(of: filteredLogs.first?.id) { _ in
                            applyExpansionMemoryForCurrentFilter()
                            guard autoFollow else { return }
                            scrollToLatest(proxy: proxy, animated: true)
                        }
                        .onChange(of: selectedFilter) { _ in
                            applyExpansionMemoryForCurrentFilter()
                            scrollToLatest(proxy: proxy, animated: false)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: windowHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToLatest(proxy: ScrollViewProxy, animated: Bool) {
        guard let firstID = filteredLogs.first?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(firstID, anchor: .top)
            }
        } else {
            proxy.scrollTo(firstID, anchor: .top)
        }
    }

    private func toggleExpandAllDetails() {
        let ids = expandableLogIDs
        guard !ids.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            if allDetailsExpanded {
                expandedIDs.subtract(ids)
                autoExpandAllDetails = false
            } else {
                expandedIDs.formUnion(ids)
                autoExpandAllDetails = true
            }
            persistExpandedIDs()
        }
    }

    private func applyExpansionMemoryForCurrentFilter() {
        if autoExpandAllDetails {
            expandedIDs.formUnion(expandableLogIDs)
        } else {
            restoreExpandedIDs()
        }
        pruneExpandedIDsToVisibleLogs()
    }

    private func restoreExpandedIDs() {
        let ids = persistedExpandedIDs
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        expandedIDs = Set(ids)
    }

    private func persistExpandedIDs() {
        persistedExpandedIDs = expandedIDs.map { $0.uuidString }.sorted().joined(separator: ",")
    }

    private func pruneExpandedIDsToVisibleLogs() {
        let validIDs = Set(todayLogs.map(\.id))
        expandedIDs = expandedIDs.intersection(validIDs)
        persistExpandedIDs()
    }

    private func consoleBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.14))
            )
    }

    private func copyFilteredLogs() {
        guard !filteredLogs.isEmpty else {
            withAnimation { toastText = "暂无可复制日志" }
            return
        }
        let text = vehicleLog.exportText(entries: filteredLogs)
        UIPasteboard.general.string = text
        withAnimation { toastText = "已复制今日日志" }
    }

    private func exportFilteredLogs() {
        guard !filteredLogs.isEmpty else {
            withAnimation { toastText = "暂无日志可导出" }
            return
        }
        guard let url = vehicleLog.exportFile(entries: filteredLogs, filterTitle: selectedFilter.fileTag) else {
            withAnimation { toastText = "暂无日志可导出" }
            return
        }
        sharePayload = SharePayload(activityItems: [url])
    }
}

// MARK: - 控制台行（错误日志风格）
private struct ConsoleLogRow: View {
    let log: VehicleEventLogEntry
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(log.timeText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .frame(width: 66, alignment: .leading)

                Text(log.category.title)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(log.category.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(log.category.color.opacity(0.16))
                    )

                Text(log.displayTitle)
                    .font(.system(size: 12.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(rowTitleColor)
                    .lineLimit(expanded ? nil : 1)

                Spacer(minLength: 0)

                if !log.detail.isEmpty {
                    Button(action: onToggle) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if expanded && !log.detail.isEmpty {
                Text(log.detail)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 56)
                    .padding(.bottom, 4)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    private var rowTitleColor: Color {
        switch log.category {
        case .error: return AppTheme.red
        case .warning: return AppTheme.orange
        default: return Color.white.opacity(0.92)
        }
    }

    private var rowBackground: Color {
        switch log.category {
        case .error: return AppTheme.red.opacity(0.08)
        case .warning: return AppTheme.orange.opacity(0.06)
        default: return Color.clear
        }
    }
}

private struct VehicleLogFilterBar: View {
    @Binding var selectedFilter: VehicleLogFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(VehicleLogFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(selectedFilter == filter ? .black : Color.white.opacity(0.68))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
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
        VStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.28))
            Text(message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.45))
            Text("新事件会显示在此控制台窗口内")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.28))
        }
    }
}
