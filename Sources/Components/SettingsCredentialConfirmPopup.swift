import SwiftUI

struct SettingsCredentialConfirmPopup: View {
    let payload: CredentialConfirmPayload
    let onConfirm: () -> Void

    var body: some View {
        FloatingPopupCard(
            icon: "person.fill",
            iconColor: AppTheme.green,
            title: "用户凭证",
            maxWidth: 332,
            maxContentHeight: 220,
            contentScrollEnabled: false
        ) {
            rowsContent
        } actions: {
            FloatingPopupPrimaryButton(title: "确认", color: AppTheme.green, action: onConfirm)
        }
    }

    @ViewBuilder
    private var rowsContent: some View {
        PopupInfoRowsView(
            rows: [
                PopupInfoRowItem("info.circle", "VIN", payload.vin, mono: true, color: .white),
                PopupInfoRowItem("phone.fill", "手机号", payload.phone, mono: true, color: .white),
                PopupInfoRowItem("key.fill", "Token", payload.tokenMasked, mono: true, color: .white)
            ],
            labelWidth: 68,
            rowVerticalPadding: 8
        )
        .padding(.horizontal, 2)
    }
}
