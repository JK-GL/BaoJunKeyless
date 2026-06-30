import SwiftUI

struct SettingsResetSection: View {
    @Binding var showingResetAlert: Bool
    let onReset: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: { showingResetAlert = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13))
                    Text("重置全部设置")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }
}
