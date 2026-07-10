import Foundation
import Combine

final class VehicleTokenSourceStore: ObservableObject {
    static let shared = VehicleTokenSourceStore()

    @Published var label: String = ""
    @Published var path: String = ""

    var displayText: String {
        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLabel.isEmpty && normalizedPath.isEmpty {
            return "未配置 / 未读取"
        }
        if normalizedPath.isEmpty { return normalizedLabel }
        if normalizedLabel.isEmpty { return normalizedPath }
        return "\(normalizedLabel)\n\(normalizedPath)"
    }

    func update(label: String, path: String = "") {
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.path = path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clear() {
        label = ""
        path = ""
    }
}
