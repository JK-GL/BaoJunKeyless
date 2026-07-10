import Foundation
import Combine

final class FuelBarModeStore: ObservableObject {
    static let shared = FuelBarModeStore()

    @Published var mode: FuelBarMode = .auto

    func setMode(_ mode: FuelBarMode) {
        self.mode = mode
    }
}
