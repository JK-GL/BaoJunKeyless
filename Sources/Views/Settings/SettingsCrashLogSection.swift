import SwiftUI

/// 设置页「错误日志」：只展示 CrashLogger 异常/诊断，不是业务流水。
/// 业务 HTTP/围栏/后台状态请看「日志」页。
struct SettingsCrashLogSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var crashLogText: String
    @Binding var isCrashLogExpanded: Bool
    @Binding var toastText: String?
    let refreshCrashLog: () -> Void
    let copyRecentLog: () -> Void
    let exportCrashLog: () -> Void

    private var previewLines: [String] {
        crashLogText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var headerSummary: String {
        if crashLogText.isEmpty { return "暂无异常" }
        let n = previewLines.count
        return n > 0 ? "最近 \(n) 条" : "有记录"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 整行点按展开/折叠（与 CollapsibleCard 一致）
            Button {
                withAnimation(PopupMotion.contentEase) { isCrashLogExpanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(Color.red.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 20, height: 20, alignment: .center)
                    Text("错误日志")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if !isCrashLogExpanded {
                        Text(headerSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isCrashLogExpanded ? 90 : 0))
                        .frame(width: 14, height: 14)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCrashLogExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .background(theme.cardStroke)
                        .padding(.top, 10)

                    HStack(spacing: 8) {
                        Text(crashLogText.isEmpty ? "暂无异常记录" : "预览仅异常/诊断 · 业务流水在「日志」页")
                            .font(.caption2)
                            .foregroundStyle(crashLogText.isEmpty ? Color.white.opacity(0.45) : Color.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("记录")
                            .font(.caption2)
                            .foregroundStyle(Color.white.opacity(0.45))
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { CrashLogger.shared.isLoggingEnabled },
                                set: { CrashLogger.shared.setLoggingEnabled($0) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(theme.accent)
                        .scaleEffect(0.7)
                    }

                    Text("界面看摘要；复制/导出为详细 DEBUG。HTTP 轮询、围栏 reeval 等已改走控制台日志。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .fixedSize(horizontal: false, vertical: true)

                    if previewLines.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.green)
                                .font(.system(size: 14))
                            Text("暂无错误记录")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                    } else {
                        // 固定高度内滚 + 分行 Lazy，避免整页被超长 Text 拖卡
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(previewLines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Color.white.opacity(0.72))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(10)
                        }
                        .frame(height: 220)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], alignment: .leading, spacing: 10) {
                        Button {
                            refreshCrashLog()
                            withAnimation { toastText = "预览已刷新" }
                        } label: {
                            actionLabel(icon: "arrow.counterclockwise", title: "刷新", color: AppTheme.accent)
                        }

                        Button {
                            CrashLogger.shared.logCurrentStatus(tag: "manual")
                            refreshCrashLog()
                            withAnimation { toastText = "状态已记录" }
                        } label: {
                            actionLabel(icon: "waveform.path.ecg", title: "记录状态", color: AppTheme.accent)
                        }

                        Button {
                            copyRecentLog()
                        } label: {
                            actionLabel(icon: "doc.on.doc", title: "复制详细", color: AppTheme.accent)
                        }

                        Button {
                            exportCrashLog()
                        } label: {
                            actionLabel(icon: "square.and.arrow.up", title: "导出详细", color: AppTheme.accent)
                        }

                        Button {
                            CrashLogger.shared.clearLog()
                            refreshCrashLog()
                            withAnimation { toastText = "日志已清空" }
                        } label: {
                            actionLabel(icon: "trash", title: "清空", color: Color.red.opacity(0.8))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, isCrashLogExpanded ? 14 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, AppSpacing.screenHorizontal)
        .onAppear {
            if isCrashLogExpanded { refreshCrashLog() }
        }
        .onChange(of: isCrashLogExpanded) { expanded in
            if expanded { refreshCrashLog() }
        }
    }

    private func actionLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(color)
    }
}
