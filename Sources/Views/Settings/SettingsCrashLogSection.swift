import SwiftUI

struct SettingsCrashLogSection: View {
    @EnvironmentObject var theme: ThemeManager
    @Binding var crashLogText: String
    @Binding var isCrashLogExpanded: Bool
    @Binding var toastText: String?
    let refreshCrashLog: () -> Void
    let copyRecentLog: () -> Void
    let exportCrashLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PopupMotion.contentEase) { isCrashLogExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "ladybug.fill")
                        .foregroundStyle(Color.red.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold))
                    Text("错误日志")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .rotationEffect(.degrees(isCrashLogExpanded ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isCrashLogExpanded {
                Divider().background(theme.cardStroke)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if crashLogText.isEmpty {
                            Text("暂无记录")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.45))
                        } else {
                            Text("有记录")
                                .font(.caption2)
                                .foregroundStyle(Color.orange.opacity(0.9))
                        }

                        Spacer()

                        Text("记录开关")
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

                    if crashLogText.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.green)
                                .font(.system(size: 14))
                            Text("暂无错误记录")
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(crashLogText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.62))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
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
                            withAnimation { toastText = "日志已刷新" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("刷新")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            CrashLogger.shared.logCurrentStatus(tag: "manual")
                            refreshCrashLog()
                            withAnimation { toastText = "状态已记录" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 12))
                                Text("记录状态")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            copyRecentLog()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 12))
                                Text("复制最近")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            exportCrashLog()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12))
                                Text("导出")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(AppTheme.accent)
                        }

                        Button {
                            CrashLogger.shared.clearLog()
                            refreshCrashLog()
                            withAnimation { toastText = "日志已清空" }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                Text("清空")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(Color.red.opacity(0.8))
                        }
                    }
                }
                .padding(16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.cardStroke, lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .onAppear {
            if isCrashLogExpanded {
                refreshCrashLog()
            }
        }
        .onChange(of: isCrashLogExpanded) { expanded in
            if expanded {
                refreshCrashLog()
            }
        }
    }
}
