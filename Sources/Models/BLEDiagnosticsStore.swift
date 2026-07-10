import Foundation
import Combine

final class BLEDiagnosticsStore: ObservableObject {
    @Published var debugRawRSSI: Int?
    @Published var debugSmoothedRSSI: Int?
    @Published var debugLastSeenText: String = "--"
    @Published var debugLastTransitionText: String = "--"
    @Published var phaseText: String = "待机"
    @Published var detailText: String = "等待开始"
    @Published var lastConclusionText: String = "--"
    @Published var lastConclusionAtText: String = "--"
    @Published var lastReasonText: String = "--"
    @Published var noDeviceCount: Int = 0
    @Published var foundButNotConnectedCount: Int = 0
    @Published var authFailedCount: Int = 0

    var didSeeDeviceThisCycle = false
    var didReachConnectedThisCycle = false
    var currentCandidateName: String = "--"
    var currentCandidateRSSI: Int?

    var countsSummaryText: String {
        "未发现 \(noDeviceCount) · 未连上 \(foundButNotConnectedCount) · 鉴权失败 \(authFailedCount)"
    }

    func currentCandidateText(fallbackName: String) -> String {
        let name = currentCandidateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = name.isEmpty || name == "--" ? fallbackName : name
        if let rssi = currentCandidateRSSI {
            return "\(label) · RSSI \(rssi)"
        }
        return label
    }

    func resetCycle() {
        didSeeDeviceThisCycle = false
        didReachConnectedThisCycle = false
        currentCandidateName = "--"
        currentCandidateRSSI = nil
    }

    func setPhase(_ phase: String, detail: String) {
        phaseText = phase
        detailText = detail
    }

    func setConclusion(_ conclusion: String, reason: String = "--") {
        lastConclusionText = conclusion
        lastConclusionAtText = formatTime(Date())
        lastReasonText = reason
    }

    func noteDeviceSeen(name: String, rssi: Int?, fallbackName: String) {
        didSeeDeviceThisCycle = true
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty, normalized != "--" {
            currentCandidateName = normalized
        }
        if let rssi {
            currentCandidateRSSI = rssi
        }
        setPhase("发现设备", detail: currentCandidateText(fallbackName: fallbackName))
    }

    func noteConnectedCandidate(name: String, fallbackName: String) {
        didReachConnectedThisCycle = true
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty, normalized != "--" {
            currentCandidateName = normalized
        }
        setPhase("已连上", detail: currentCandidateText(fallbackName: fallbackName))
    }

    func noteNoDeviceFound(displayName: String, duration: String) {
        noDeviceCount += 1
        let detail = "\(displayName) · 已扫描 \(duration)"
        setPhase("未发现设备", detail: detail)
        setConclusion("完全没发现设备", reason: "扫描超时，未看到目标设备")
    }

    func noteFoundButNotConnected(_ detail: String, reason: String = "已发现目标，但连接未完成") {
        foundButNotConnectedCount += 1
        setPhase("发现未连上", detail: detail)
        setConclusion("发现过设备但没连上", reason: reason)
    }

    func noteAuthFailed(_ reason: String) {
        authFailedCount += 1
        setPhase("鉴权失败", detail: reason)
        setConclusion("连上了但鉴权失败", reason: reason)
    }
}
