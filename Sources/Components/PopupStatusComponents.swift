import SwiftUI

// MARK: - 弹窗内统一状态项
struct PopupStatusItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    let value: String
    let color: Color

    init(icon: String, label: String, value: String, color: Color) {
        self.id = "\(icon)|\(label)"
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
    }

    static func == (lhs: PopupStatusItem, rhs: PopupStatusItem) -> Bool {
        lhs.id == rhs.id && lhs.value == rhs.value
    }
}

// MARK: - 弹窗内状态摘要组件
struct PopupStatusSummaryView: View {
    let items: [PopupStatusItem]

    var body: some View {
        if !items.isEmpty {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(item.color)
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.45))
                        Text(item.value)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity)

                    if item.id != items.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1, height: 36)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }
}

// MARK: - 弹窗内统一信息行数据
struct PopupInfoRowItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let label: String
    let value: String
    /// 可选第二行（如围栏地址）；空则不显示，避免与主值挤成一坨
    let secondaryValue: String
    let mono: Bool
    let color: Color
    let secondaryColor: Color

    init(
        _ icon: String,
        _ label: String,
        _ value: String,
        secondaryValue: String = "",
        mono: Bool = false,
        color: Color = .primary,
        secondaryColor: Color = Color.white.opacity(0.48)
    ) {
        self.id = "\(icon)|\(label)"
        self.icon = icon
        self.label = label
        self.value = value
        self.secondaryValue = secondaryValue
        self.mono = mono
        self.color = color
        self.secondaryColor = secondaryColor
    }

    static func == (lhs: PopupInfoRowItem, rhs: PopupInfoRowItem) -> Bool {
        lhs.id == rhs.id
            && lhs.value == rhs.value
            && lhs.secondaryValue == rhs.secondaryValue
            && lhs.mono == rhs.mono
    }
}

// MARK: - 弹窗内统一分隔线
struct PopupInfoDivider: View {
    var leadingPadding: CGFloat = 30

    var body: some View {
        Divider()
            .padding(.leading, leadingPadding)
    }
}

// MARK: - 弹窗内统一信息行列表
struct PopupInfoRowsView: View {
    let rows: [PopupInfoRowItem]
    var labelWidth: CGFloat? = nil
    var valueLineLimit: Int? = 1
    var secondaryLineLimit: Int = 2
    var valueMinimumScaleFactor: CGFloat = 0.64
    var rowVerticalPadding: CGFloat = 7
    /// 标签/图标字号（默认 13；无感实时可略小）
    var labelFontSize: CGFloat = 13
    /// 主值字号（mono 会再减 1）
    var valueFontSize: CGFloat = 13
    /// 副行字号
    var secondaryFontSize: CGFloat = 10.5
    var iconSize: CGFloat = 13

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                infoRow(row)

                if idx < rows.count - 1 {
                    PopupInfoDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func infoRow(_ row: PopupInfoRowItem) -> some View {
        let hasSecondary = !row.secondaryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // 左标签固定、右值贴右；避免 maxWidth infinity 把值块撑到中间
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: row.icon)
                .font(.system(size: iconSize))
                .foregroundColor(.secondary)
                .frame(width: 20)

            labelText(row.label)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: hasSecondary ? 2 : 0) {
                Text(row.value.isEmpty ? "--" : row.value)
                    .font(.system(
                        size: row.mono ? max(10, valueFontSize - 1) : valueFontSize,
                        weight: .medium,
                        design: row.mono ? .monospaced : .default
                    ))
                    .foregroundColor(row.color)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(valueLineLimit)
                    .minimumScaleFactor(valueMinimumScaleFactor)

                if hasSecondary {
                    Text(row.secondaryValue)
                        .font(.system(size: secondaryFontSize, weight: .regular))
                        .foregroundColor(row.secondaryColor)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(secondaryLineLimit)
                        .minimumScaleFactor(0.85)
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, rowVerticalPadding)
    }

    @ViewBuilder
    private func labelText(_ label: String) -> some View {
        if let labelWidth = labelWidth {
            Text(label)
                .font(.system(size: labelFontSize))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
        } else {
            Text(label)
                .font(.system(size: labelFontSize))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 弹窗内统一长文本块
struct PopupInfoTextBlock: View {
    let icon: String
    let title: String
    let value: String
    var mono: Bool = false
    var valueColor: Color = Color.white.opacity(0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(value.isEmpty ? "--" : value)
                .font(.system(size: mono ? 11 : 12,
                              weight: .medium,
                              design: mono ? .monospaced : .default))
                .foregroundStyle(valueColor)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

// MARK: - 弹窗内统一列表块
struct PopupInfoListBlock: View {
    let icon: String
    let title: String
    let items: [String]
    var countText: String? = nil
    var mono: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let countText = countText {
                    Text(countText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    Text(item)
                        .font(.system(size: 10.5,
                                      weight: .medium,
                                      design: mono ? .monospaced : .default))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)

                    if idx < items.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
        }
    }
}

// MARK: - 弹窗内温度滑块组件
struct PopupTemperatureSlider: View {
    let title: String
    @Binding var temperature: Double
    let range: ClosedRange<Double>
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
                Spacer()
                Text("\(Int(temperature))°C")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(tint)
            }
            Slider(value: $temperature, in: range, step: 1)
                .tint(tint)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}
