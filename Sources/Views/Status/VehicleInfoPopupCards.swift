import SwiftUI

struct VehicleInfoMergedCard: View {
    let dashboard: VehicleDashboardState
    var isEmbedded: Bool = true
    @State private var isExpanded = false
    @State private var showCopiedToast = false

    private var rows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("clock.fill",     "更新日期",   dashboard.vehicleInfoUpdatedAtText),
            PopupInfoRowItem("car.fill",       "车型",       dashboard.vehicleName),
            PopupInfoRowItem("info.circle",    "VIN",        dashboard.vinText, mono: true),
            PopupInfoRowItem("person.fill",    "用户ID",     dashboard.userIdText, mono: true),
            PopupInfoRowItem("key.fill",       "钥匙类型",   dashboard.keyTypeText, color: AppTheme.green),
            PopupInfoRowItem("antenna.radiowaves.left.and.right", "BLE MAC",    dashboard.bleMacText, mono: true, color: AppTheme.accent),
            PopupInfoRowItem("number",         "Key ID",     dashboard.keyIdText, mono: true, color: AppTheme.accent),
            PopupInfoRowItem("lock.fill",      "MasterKey",  dashboard.masterKeyMaskedText, mono: true),
            PopupInfoRowItem("dice.fill",      "Random",     dashboard.randomMaskedText, mono: true),
            PopupInfoRowItem("clock.arrow.circlepath", "有效期至",   dashboard.keyExpiryText, color: AppTheme.green),
        ]
    }

    private var fullText: String {
        """
        更新日期: \(dashboard.vehicleInfoUpdatedAtText)
        车型: \(dashboard.vehicleName)
        VIN: \(dashboard.vinText)
        用户ID: \(dashboard.userIdText)
        钥匙类型: \(dashboard.keyTypeText)
        BLE MAC: \(dashboard.bleMacText)
        Key ID: \(dashboard.keyIdText)
        MasterKey: \(dashboard.masterKeyMaskedText)
        Random: \(dashboard.randomMaskedText)
        有效期至: \(dashboard.keyExpiryText)
        """
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if isEmbedded {
                    AnyView(
                        CollapsibleCard(
                            title: "车辆信息",
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
                    .transition(.scale.combined(with: .opacity))
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

    private var rows: [PopupInfoRowItem] {
        [
            PopupInfoRowItem("antenna.radiowaves.left.and.right", "状态", status.text, color: status.color),
            PopupInfoRowItem("network", "Broker", broker, mono: true),
            PopupInfoRowItem("iphone.radiowaves.left.and.right", "ClientID", clientId, mono: true),
            PopupInfoRowItem("person.fill", "Username", username, mono: true),
            PopupInfoRowItem("key.fill", "Password", password, mono: true)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            rowsContent

            PopupInfoTextBlock(
                icon: "doc.text.fill",
                title: "来源",
                value: tokenSource
            )

            if !topics.isEmpty {
                PopupInfoListBlock(
                    icon: "dot.radiowaves.left.and.right",
                    title: "订阅 Topics",
                    items: topics,
                    countText: "\(topics.count) 项"
                )
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var rowsContent: some View {
        PopupInfoRowsView(
            rows: rows,
            labelWidth: 72
        )
    }
}
