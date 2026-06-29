import SwiftUI

struct SettingsCredentialConfirmPopup: View {
    let payload: CredentialConfirmPayload
    let onConfirm: () -> Void

    var body: some View {
        FloatingPopupCard(
            icon: "person.text.rectangle.fill",
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
        VStack(alignment: .leading, spacing: 0) {
            row(icon: "info.circle", label: "VIN", value: payload.vin, mono: true)
            divider
            row(icon: "phone.fill", label: "手机号", value: payload.phone, mono: true)
            divider
            row(icon: "key.fill", label: "Token", value: payload.tokenMasked, mono: true)
        }
        .padding(.horizontal, 2)
    }

    private func row(icon: String, label: String, value: String, mono: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 68, alignment: .leading)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: mono ? 11 : 13, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Divider().padding(.leading, 30)
    }
}
