import SwiftUI

struct VehicleInfoMergedCard: View {
    let dashboard: VehicleDashboardState
    var bleStatusText: String = "--"
    var isEmbedded: Bool = true
    @State private var isExpanded = false
    @State private var showCopiedToast = false

    private var rows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("clock.fill",     "更新时间",   dashboard.vehicleInfoUpdatedAtText),
            PopupInfoRowItem("dot.radiowaves.left.and.right", "蓝牙状态",   bleStatusText, color: AppTheme.accent),
            PopupInfoRowItem("car.fill",       "车型",       dashboard.vehicleName),
            PopupInfoRowItem("info.circle",    "VIN",        dashboard.vinText, mono: true),
            PopupInfoRowItem("person.fill",    "用户ID",     dashboard.userIdText, mono: true),
            PopupInfoRowItem("key.fill",       "钥匙类型",   dashboard.keyTypeText, color: AppTheme.green),
            PopupInfoRowItem("antenna.radiowaves.left.and.right", "蓝牙地址",    dashboard.bleMacText, mono: true, color: AppTheme.accent),
            PopupInfoRowItem("number",         "钥匙编号",     dashboard.keyIdText, mono: true, color: AppTheme.accent),
            PopupInfoRowItem("lock.fill",      "主密钥",  dashboard.masterKeyMaskedText, mono: true),
            PopupInfoRowItem("dice.fill",      "随机数",     dashboard.randomMaskedText, mono: true),
            PopupInfoRowItem("clock.arrow.circlepath", "有效期至",   dashboard.keyExpiryText, color: AppTheme.green),
        ]
    }

    private var fullText: String {
        """
        更新时间: \(dashboard.vehicleInfoUpdatedAtText)
        蓝牙状态: \(bleStatusText)
        车型: \(dashboard.vehicleName)
        VIN: \(dashboard.vinText)
        用户ID: \(dashboard.userIdText)
        钥匙类型: \(dashboard.keyTypeText)
        蓝牙地址: \(dashboard.bleMacText)
        钥匙编号: \(dashboard.keyIdText)
        主密钥: \(dashboard.masterKeyMaskedText)
        随机数: \(dashboard.randomMaskedText)
        有效期至: \(dashboard.keyExpiryText)
        """
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if isEmbedded {
                    AnyView(
                        CollapsibleCard(
                            title: "车辆与钥匙",
                            icon: "car.fill",
                            iconColor: AppTheme.accent,
                            isExpanded: $isExpanded,
                            headerExtra: {
                                Text("\(rows.count) 项")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        ) {
                            rowsContent
                        }
                    )
                } else {
                    AnyView(
                        VStack(alignment: .leading, spacing: 0) {
                            rowsContent
                        }
                        .padding(.horizontal, 2)
                    )
                }
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                UIPasteboard.general.string = fullText
                withAnimation { showCopiedToast = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showCopiedToast = false }
                }
            }

            if showCopiedToast {
                ToastView(text: "已复制到剪贴板")
                    .transition(PopupMotion.transition)
                    .zIndex(1)
                    .offset(y: -40)
            }
        }
    }

    @ViewBuilder
    private var rowsContent: some View {
        PopupInfoRowsView(
            rows: rows,
            valueMinimumScaleFactor: 0.7
        )
    }
}

struct MQTTInfoMergedCard: View {
    let status: StatusMQTTState
    let broker: String
    let clientId: String
    let username: String
    let password: String
    let tokenSource: String
    let topics: [String]

    private var statusRows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("antenna.radiowaves.left.and.right", "状态", status.text, color: status.color)
        ]
    }

    private var authRows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("iphone.radiowaves.left.and.right", "客户端", clientId, mono: true),
            PopupInfoRowItem("person.fill", "用户名", username, mono: true),
            PopupInfoRowItem("key.fill", "密码", password, mono: true)
        ]
    }

    private var serverRows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("network", "服务器", broker, mono: true)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoGroup(title: "连接状态") {
                PopupInfoRowsView(rows: statusRows, labelWidth: 72)
            }

            infoGroup(title: "连接账号") {
                PopupInfoRowsView(rows: authRows, labelWidth: 72)
            }

            infoGroup(title: "服务器") {
                PopupInfoRowsView(rows: serverRows, labelWidth: 72)
            }

            PopupInfoTextBlock(
                icon: "doc.text.fill",
                title: "登录来源",
                value: tokenSource
            )

            if !topics.isEmpty {
                PopupInfoListBlock(
                    icon: "dot.radiowaves.left.and.right",
                    title: "订阅主题",
                    items: topics,
                    countText: "\(topics.count) 项"
                )
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func infoGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 2)
            content()
        }
    }
}
