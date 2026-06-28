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
                                    ? (hapticManager.isPressing ? AppTheme.accent : Color.white.opacity(0.15))
                                    : Color.white.opacity(0.1),
                                lineWidth: 2
                            )
                            .frame(width: 200, height: 200)

                        // 内圈 — 按住时扩大变亮
                        Circle()
                            .fill(
                                hapticManager.isPressing
                                    ? AppTheme.accent.opacity(0.5)
                                    : (hapticManager.isRecording ? AppTheme.accent.opacity(0.2) : Color.white.opacity(0.06))
                            )
                            .frame(width: hapticManager.isPressing ? 180 : 120,
                                   height: hapticManager.isPressing ? 180 : 120)

                        // 中心图标
                        Image(systemName: hapticManager.isRecording ? "hand.tap" : "record.circle")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(hapticManager.isPressing ? .white : (hapticManager.isRecording ? AppTheme.accent : Color.white.opacity(0.62)))
                    }
                    .animation(.spring(response: 0.2), value: hapticManager.isPressing)
                    .animation(.spring(response: 0.2), value: hapticManager.isRecording)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if hapticManager.isRecording && !hapticManager.isPressing {
                                    hapticManager.pressStart()
                                }
                            }
                            .onEnded { _ in
                                if hapticManager.isPressing {
                                    hapticManager.pressEnd()
                                }
                            }
                    )
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded {
                                if hapticManager.isRecording && !hapticManager.isPressing {
                                    hapticManager.tap()
                                }
                            }
                    )

                    // 提示文字
                    if hapticManager.isRecording {
                        if hapticManager.isPressing {
                            Text("松开停止，继续点击或按住录制")
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.accent)
                        } else {
                            Text("点击录制脉冲，按住录制持续震动")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                    } else if hapticManager.hasRecording {
                        Text("点击「开始录制」重新录制")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.62))
                    } else {
                        Text("点击「开始录制」，点击或按住屏幕录制")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.white.opacity(0.62))
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
                Color.clear
                    .ignoresSafeArea()
                    .onTapGesture { showSaveDialog = false }

                FloatingPopupCard(
                    icon: "waveform",
                    iconColor: AppTheme.accent,
                    title: "保存震动模式",
                    subtitle: "为你的自定义震动模式命名",
                    maxWidth: 320
                ) {
                    TextField("输入名称", text: $patternName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                } actions: {
                    VStack(spacing: 8) {
                        FloatingPopupPrimaryButton(
                            title: "保存",
                            color: AppTheme.accent,
                            isDisabled: patternName.isEmpty
                        ) {
                            guard !patternName.isEmpty else { return }
                            let pattern = CustomVibrationPattern(
                                name: patternName,
                                events: hapticManager.recordedEvents
                            )
                            onSave(pattern)
                            dismiss()
                        }

                        FloatingPopupSecondaryButton(
                            title: "取消",
                            textColor: Color.white.opacity(0.62)
                        ) {
                            showSaveDialog = false
                        }
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSaveDialog)
            }
        }
    }
}

// MARK: - Core Haptics 录制管理器（点击 + 按住混合）
class HapticRecorderManager: ObservableObject {
    @Published var isRecording = false
    @Published var isPressing = false
    @Published var hasRecording = false
    @Published var totalDuration: Double = 0

    var recordedEvents: [CustomVibrationPattern.VibrationEvent] = []

    private var engine: CHHapticEngine?
    private var recordingStartTime: TimeInterval = 0
    private var lastEventEndTime: TimeInterval = 0
    private var pressStartTime: TimeInterval = 0
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    // 记录每个事件的原始时长（用于按住模式）
    private var eventTimestamps: [(start: TimeInterval, end: TimeInterval, isContinuous: Bool)] = []

    init() {
        setupEngine()
    }

    private func setupEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            CrashLogger.shared.mark("Haptics", "record engine failed", details: error.localizedDescription)
        }
    }

    func startRecording() {
        isRecording = true
        hasRecording = false
        recordedEvents = []
        eventTimestamps = []
        totalDuration = 0
        recordingStartTime = CACurrentMediaTime()
        lastEventEndTime = 0
    }

    func stopRecording() {
        isRecording = false
        isPressing = false
        try? continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil
        buildEventsFromTimestamps()
        hasRecording = !recordedEvents.isEmpty
    }

    // 按下 — 开始持续震动
    func pressStart() {
        guard isRecording else { return }
        let now = CACurrentMediaTime() - recordingStartTime

        // 如果距上次事件有间隔，先记录静音
        if now - lastEventEndTime > 0.01 {
            let gap = now - lastEventEndTime
            eventTimestamps.append((start: lastEventEndTime, end: now, isContinuous: false))
            recordedEvents.append(.init(duration: gap, intensity: 0))
        }

        pressStartTime = now
        isPressing = true

        // 开始持续震动反馈
        guard let engine = engine else { return }
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensity, sharpness], relativeTime: 0, duration: 60)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: 0)
        } catch {
            CrashLogger.shared.mark("Haptics", "start continuous failed", details: error.localizedDescription)
        }
    }

    // 松开 — 停止持续震动，记录时长
    func pressEnd() {
        guard isRecording, isPressing else { return }
        let now = CACurrentMediaTime() - recordingStartTime

        // 停止持续震动
        try? continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil
        isPressing = false

        // 记录持续震动事件
        let duration = max(now - pressStartTime, 0.05)
        eventTimestamps.append((start: pressStartTime, end: now, isContinuous: true))
        recordedEvents.append(.init(duration: duration, intensity: 1.0))
        lastEventEndTime = now
    }

    // 点击 — 短脉冲
    func tap() {
        guard isRecording else { return }
        let now = CACurrentMediaTime() - recordingStartTime

        // 如果距上次事件有间隔，先记录静音
        if now - lastEventEndTime > 0.01 {
            let gap = now - lastEventEndTime
            eventTimestamps.append((start: lastEventEndTime, end: now, isContinuous: false))
            recordedEvents.append(.init(duration: gap, intensity: 0))
        }

        // 记录点击脉冲
        let duration = 0.05
        eventTimestamps.append((start: now, end: now + duration, isContinuous: false))
        recordedEvents.append(.init(duration: duration, intensity: 1.0))
        lastEventEndTime = now + duration

        // 实时震动反馈
        let g = UIImpactFeedbackGenerator(style: .rigid)
        g.impactOccurred(intensity: 1.0)
    }

    private func buildEventsFromTimestamps() {
        totalDuration = recordedEvents.reduce(0) { $0 + $1.duration }
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


