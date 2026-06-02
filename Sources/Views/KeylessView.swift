import SwiftUI

// MARK: - Keyless View (Tab 2)
struct KeylessView: View {
    @State private var unlockEnabled = true
    @State private var unlockThreshold: Double = -48
    @State private var unlockPopup = true
    @State private var unlockVibrate = true
    @State private var unlockVibPattern = "短促单震"
    @State private var unlockVibStrength: Double = 60

    @State private var lockEnabled = true
    @State private var lockThreshold: Double = -72
    @State private var lockDelay: Double = 15
    @State private var lockPopup = true
    @State private var lockVibrate = true
    @State private var lockVibPattern = "短促单震"
    @State private var lockVibStrength: Double = 60

    @State private var keylessEnabled = true
    @State private var pluginTakeover = true
    @State private var smartSwitch = false
    @State private var drBlock = false
    @State private var cmdInterval: Double = 5

    private let vibPatterns = ["短促单震", "长短双震", "连续轻震", "厚重强震", "间歇节奏"]

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    unlockSection
                    lockSection
                    keylessSection
                    Spacer(minLength: 20)
                }
                .padding(.vertical, 16)
            }
            .background(AppTheme.pageBg.ignoresSafeArea())
            .navigationTitle("无感车控")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: Unlock Section
    private var unlockSection: some View {
        CardView(title: "解锁设置", icon: "lock.open.fill", iconColor: AppTheme.green) {
            ToggleRow(icon: "power", label: "解锁开关", isOn: $unlockEnabled)

            SliderRow(icon: "wifi", label: "dBm 阈值",
                      value: $unlockThreshold, range: -110...(-30), step: 1,
                      format: "\(Int(unlockThreshold)) dBm", tint: AppTheme.green)

            ToggleRow(icon: "bell.fill", label: "解锁弹窗", isOn: $unlockPopup)
            ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $unlockVibrate)

            if unlockVibrate {
                VibrationDetailView(
                    pattern: $unlockVibPattern,
                    strength: $unlockVibStrength,
                    patterns: vibPatterns,
                    testLabel: "模拟解锁震动",
                    tint: AppTheme.green
                )
            }
        }
    }

    // MARK: Lock Section
    private var lockSection: some View {
        CardView(title: "上锁设置", icon: "lock.fill", iconColor: AppTheme.red) {
            ToggleRow(icon: "power", label: "上锁开关", isOn: $lockEnabled)

            SliderRow(icon: "wifi", label: "dBm 阈值",
                      value: $lockThreshold, range: -110...(-30), step: 1,
                      format: "\(Int(lockThreshold)) dBm", tint: AppTheme.red)

            SliderRow(icon: "gauge.medium", label: "上锁延迟",
                      value: $lockDelay, range: 0...60, step: 1,
                      format: "\(Int(lockDelay))s", tint: AppTheme.red)

            ToggleRow(icon: "bell.fill", label: "上锁弹窗", isOn: $lockPopup)
            ToggleRow(icon: "flame.fill", label: "震动反馈", isOn: $lockVibrate)

            if lockVibrate {
                VibrationDetailView(
                    pattern: $lockVibPattern,
                    strength: $lockVibStrength,
                    patterns: vibPatterns,
                    testLabel: "模拟上锁震动",
                    tint: AppTheme.red
                )
            }
        }
    }

    // MARK: Keyless Section
    private var keylessSection: some View {
        CardView(title: "无感功能", icon: "dot.radiowaves.left.and.right", iconColor: AppTheme.purple) {
            ToggleRow(icon: "power", label: "无感开关", isOn: $keylessEnabled)
            ToggleRow(icon: "shield.fill", label: "插件托管", isOn: $pluginTakeover)
            ToggleRow(icon: "arrow.triangle.2.circlepath", label: "智能切换", isOn: $smartSwitch)
            ToggleRow(icon: "exclamationmark.triangle.fill", label: "D/R 挡禁止", isOn: $drBlock)

            SliderRow(icon: "gauge.medium", label: "重复指令间隔",
                      value: $cmdInterval, range: 1...15, step: 1,
                      format: "\(Int(cmdInterval))s", tint: AppTheme.purple)
        }
    }
}

// MARK: - Slider Row
struct SliderRow: View {
    let icon: String
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Text(label)
                    .font(.system(size: 14)).foregroundColor(.secondary)
                Spacer()
                Text(format)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            Slider(value: $value, in: range, step: step)
                .tint(tint)
        }
    }
}

// MARK: - Vibration Detail View
struct VibrationDetailView: View {
    @Binding var pattern: String
    @Binding var strength: Double
    let patterns: [String]
    let testLabel: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("震动模式")
                .font(.system(size: 12)).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(patterns, id: \.self) { p in
                        ChipButton(text: p, isSelected: pattern == p) { pattern = p }
                    }
                }
            }

            SliderRow(icon: "gauge.medium", label: "震动强度",
                      value: $strength, range: 20...100, step: 1,
                      format: "\(Int(strength))%", tint: tint)

            Button(action: {}) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 13))
                    Text(testLabel)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(AppTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
