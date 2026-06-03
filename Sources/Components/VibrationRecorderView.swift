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

                        // 内圈 — 按住时扩大
                        Circle()
                            .fill(
                                hapticManager.isRecording
                                    ? AppTheme.accent.opacity(0.3)
                                    : Color.white.opacity(0.06)
                            )
                            .frame(width: hapticManager.isRecording ? 180 : 120,
                                   height: hapticManager.isRecording ? 180 : 120)

                        // 中心图标
                        Image(systemName: hapticManager.isRecording ? "stop.fill" : "hand.tap")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(hapticManager.isRecording ? .white : Color.white.opacity(0.62))
                    }
                    .animation(.spring(response: 0.3), value: hapticManager.isRecording)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !hapticManager.isRecording {
                                    hapticManager.startRecording()
                                }
                            }
                            .onEnded { _ in
                                if hapticManager.isRecording {
                                    hapticManager.stopRecording()
                                }
                            }
                    )

                    // 提示文字
                    Text(hapticManager.isRecording ? "松开手指停止录制" : "按住屏幕开始录制")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.62))
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
        .alert("保存震动模式", isPresented: $showSaveDialog) {
            TextField("输入名称", text: $patternName)
            Button("保存") {
                guard !patternName.isEmpty else { return }
                let pattern = CustomVibrationPattern(
                    name: patternName,
                    events: hapticManager.recordedEvents
                )
                onSave(pattern)
                dismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("为你的自定义震动模式命名")
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
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var recordingStartTime: TimeInterval = 0
    private var segments: [(start: TimeInterval, end: TimeInterval)] = []
    private var currentSegmentStart: TimeInterval = 0

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
        segments = []
        totalDuration = 0
        recordingStartTime = CACurrentMediaTime()
        currentSegmentStart = 0

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
            print("Start recording haptic failed: \(error)")
        }
    }

    func stopRecording() {
        isRecording = false
        let now = CACurrentMediaTime() - recordingStartTime

        // 停止持续震动
        try? continuousPlayer?.stop(atTime: 0)
        continuousPlayer = nil

        // 记录最后一段
        let segEnd = now
        segments.append((start: currentSegmentStart, end: segEnd))

        // 合并连续段，生成事件
        buildEvents()
        totalDuration = now
        hasRecording = !recordedEvents.isEmpty
    }

    func tapStart() {
        currentSegmentStart = CACurrentMediaTime() - recordingStartTime
    }

    func tapEnd() {
        let now = CACurrentMediaTime() - recordingStartTime
        segments.append((start: currentSegmentStart, end: now))
    }

    private func buildEvents() {
        recordedEvents = []
        for seg in segments {
            let duration = seg.end - seg.start
            guard duration > 0.02 else { continue }
            // 在同一段内添加静音间隙
            if !recordedEvents.isEmpty {
                recordedEvents.append(.init(duration: 0.05, intensity: 0))
            }
            recordedEvents.append(.init(duration: duration, intensity: 1.0))
        }
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

// MARK: - 按住手势
struct PressGestureView: View {
    @Binding var isPressed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            onPress()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        onRelease()
                    }
            )
    }
}
