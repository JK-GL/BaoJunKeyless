import SwiftUI
import CoreHaptics

// MARK: - 震动录制器
struct VibrationRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hapticManager = HapticRecorderManager()
    @State private var showSaveDialog = false
    @State private var patternName = ""
    @State private var hasRecorded = false

    let onSave: (CustomVibrationPattern) -> Void

    var body: some View {
        ZStack {
            // 背景
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.07, blue: 0.10),
                    Color(red: 0.04, green: 0.04, blue: 0.06),
                    .black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                // 顶部
                HStack {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.white.opacity(0.62))
                    Spacer()
                    Text("录制震动")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()

                // 波形可视化
                VStack(spacing: 16) {
                    ZStack {
                        // 外圈
                        Circle()
                            .stroke(
                                hapticManager.isRecording
                                    ? AppTheme.accent.opacity(0.4)
                                    : Color.white.opacity(0.1),
                                lineWidth: 2
                            )
                            .frame(width: 200, height: 200)

                        // 内圈 — 点击时脉冲
                        Circle()
                            .fill(
                                hapticManager.isRecording
                                    ? AppTheme.accent.opacity(0.3)
                                    : Color.white.opacity(0.06)
                            )
                            .frame(width: 140, height: 140)

                        // 中心图标
                        Image(systemName: hapticManager.isRecording ? "hand.tap" : "record.circle")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(hapticManager.isRecording ? AppTheme.accent : Color.white.opacity(0.62))
                    }

                    // 提示文字
                    if hapticManager.isRecording {
                        Text("点击屏幕录制震动节奏")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.62))
                    } else if hapticManager.hasRecording {
                        Text("点击「开始录制」重新录制")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.62))
                    } else {
                        Text("点击「开始录制」，然后点击屏幕录制节奏")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                }
                .onTapGesture {
                    if hapticManager.isRecording {
                        hapticManager.tap()
                    }
                }

                // 录制时间
                if hapticManager.hasRecording {
                    Text(String(format: "%.1f 秒", hapticManager.totalDuration))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Spacer()

                // 底部按钮
                VStack(spacing: 12) {
                    // 开始/停止录制
                    Button(action: {
                        if hapticManager.isRecording {
                            hapticManager.stopRecording()
                        } else {
                            hapticManager.startRecording()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: hapticManager.isRecording ? "stop.fill" : "record.circle")
                            Text(hapticManager.isRecording ? "停止录制" : "开始录制")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(hapticManager.isRecording ? .white : AppTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(hapticManager.isRecording ? AppTheme.accent : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(hapticManager.isRecording ? AppTheme.accent : AppTheme.accent.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    // 播放预览
                    if hapticManager.hasRecording {
                        Button(action: { hapticManager.playRecording() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("播放预览")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // 保存
                    if hapticManager.hasRecording {
                        Button(action: { showSaveDialog = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.down")
                                Text("保存模式")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .interactiveDismissDisabled()
        .overlay {
            if showSaveDialog {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { showSaveDialog = false }

                VStack(spacing: 0) {
                    // 标题
                    Text("保存震动模式")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 24)

                    // 输入框
                    TextField("输入名称", text: $patternName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // 提示
                    Text("为你的自定义震动模式命名")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(.top, 8)

                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.top, 16)

                    // 按钮
                    HStack(spacing: 0) {
                        Button(action: { showSaveDialog = false }) {
                            Text("取消")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }

                        Divider()
                            .background(Color.white.opacity(0.08))
                            .frame(height: 28)

                        Button(action: {
                            guard !patternName.isEmpty else { return }
                            let pattern = CustomVibrationPattern(
                                name: patternName,
                                events: hapticManager.recordedEvents
                            )
                            onSave(pattern)
                            dismiss()
                        }) {
                            Text("保存")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(patternName.isEmpty ? Color.white.opacity(0.3) : AppTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .disabled(patternName.isEmpty)
                    }
                }
                .frame(width: 280)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 40, x: 0, y: 20)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.2), value: showSaveDialog)
            }
        }
    }
}

// MARK: - Core Haptics 录制管理器
class HapticRecorderManager: ObservableObject {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var totalDuration: Double = 0

    var recordedEvents: [CustomVibrationPattern.VibrationEvent] = []

    private var engine: CHHapticEngine?
    private var tapCount = 0

    init() {
        setupEngine()
    }

    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Haptic engine failed: \(error)")
        }
    }

    func startRecording() {
        isRecording = true
        hasRecording = false
        recordedEvents = []
        tapCount = 0
        totalDuration = 0
    }

    func stopRecording() {
        isRecording = false
        hasRecording = !recordedEvents.isEmpty
    }

    func tap() {
        guard isRecording else { return }
        tapCount += 1

        // 每次点击记录一个震动事件（短震 + 间隔）
        recordedEvents.append(.init(duration: 0.12, intensity: 1.0))
        // 间隔：根据点击节奏动态调整
        let interval = tapCount > 1 ? 0.08 : 0.0
        if interval > 0 {
            recordedEvents.append(.init(duration: interval, intensity: 0))
        }

        totalDuration = recordedEvents.reduce(0) { $0 + $1.duration }

        // 每次点击时实际震动反馈
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.impactOccurred(intensity: 1.0)
    }

    func playRecording() {
        guard !recordedEvents.isEmpty else { return }
        let pattern = CustomVibrationPattern(name: "preview", events: recordedEvents)
        pattern.play()
    }

    deinit {
        engine?.stop(completionHandler: nil)
    }
}


