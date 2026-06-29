import Foundation

struct CredentialConfirmPayload: Identifiable, Equatable {
    let id = UUID()
    let vin: String
    let phone: String
    let tokenMasked: String
}
