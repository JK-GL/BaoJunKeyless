import Foundation
import SwiftUI

// MARK: - 车辆配置视图模型
final class VehicleConfigViewModel: ObservableObject {
    @Published var accessTokenDraft: String = ""
    @Published var vinDraft: String = ""
    @Published var phoneDraft: String = ""
    @Published var isFetching = false
    @Published var showingImportGuide = false
    @Published var showingFilePicker = false
    @Published var showingVehicleInfoConfirm = false
    @Published var queriedVehicleName = ""
    @Published var isEditingToken = false

    private let credentials: VehicleCredentialsStore
    private let apiClient: SGMWApiClient

    init(
        credentials: VehicleCredentialsStore,
        apiClient: SGMWApiClient = .shared
    ) {
        self.credentials = credentials
        self.apiClient = apiClient
        syncFromStore()
    }

    var tokenSourceSummary: String {
        let label = credentials.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = credentials.tokenSourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty && path.isEmpty {
            return credentials.autoReadWulingToken ? "自动读取" : "手动输入"
        }
        if !label.isEmpty {
            if label.contains("自动读取") { return "自动读取" }
            if label.contains("导入") { return "文件导入" }
            if label.contains("手动") { return "手动输入" }
            return label
        }
        return path.isEmpty ? "--" : "文件导入"
    }

    var tokenFieldDisplayText: String {
        let source = isEditingToken ? accessTokenDraft : (accessTokenDraft.isEmpty ? credentials.accessToken : accessTokenDraft)
        return isEditingToken ? source : maskToken(source)
    }

    var currentVINText: String {
        let value = vinDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        let stored = credentials.vin.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? "未配置" : stored
    }

    var currentUserText: String {
        let value = phoneDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        let stored = credentials.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty ? "未配置" : stored
    }

    var statusBadgeText: String {
        credentials.isConfigured ? "已配置" : "未配置"
    }

    var isConfigured: Bool {
        credentials.isConfigured
    }

    var autoReadWulingToken: Bool {
        get { credentials.autoReadWulingToken }
        set { credentials.autoReadWulingToken = newValue }
    }

    var hasTokenAndVin: Bool {
        !accessTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !vinDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func syncFromStore() {
        accessTokenDraft = credentials.accessToken
        vinDraft = credentials.vin
        phoneDraft = credentials.phone
        isEditingToken = false
    }

    func beginTokenEditing() {
        isEditingToken = true
        if !credentials.accessToken.isEmpty {
            accessTokenDraft = credentials.accessToken
        }
    }

    func endTokenEditing() {
        isEditingToken = false
    }

    func autoImportFromWulingApp(onComplete: @escaping (_ toast: String, _ shouldConnect: Bool) -> Void) {
        if let tokenInfo = apiClient.readLocalTokenInfo() {
            accessTokenDraft = tokenInfo.token
            credentials.accessToken = tokenInfo.token
            credentials.tokenSourceLabel = "五菱 App 自动读取"
            credentials.tokenSourcePath = tokenInfo.sourcePath
            isEditingToken = false
            fetchVehicleInfo(onComplete: onComplete, successToast: "车辆信息已获取并保存")
        } else {
            onComplete("自动读取失败，可切换为手动选择文件", false)
            showingImportGuide = true
        }
    }

    func fetchVehicleInfo(onComplete: @escaping (_ toast: String, _ shouldConnect: Bool) -> Void, successToast: String = "车辆信息已获取并保存") {
        let token = accessTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isFetching = true
        apiClient.queryDefaultCar(accessToken: token) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isFetching = false
                guard let result else {
                    onComplete("查询失败，请检查 Token", false)
                    return
                }
                self.vinDraft = result.vin
                self.phoneDraft = result.phone
                self.credentials.accessToken = token
                self.credentials.vin = result.vin
                self.credentials.phone = result.phone
                self.isEditingToken = false
                if self.credentials.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.credentials.tokenSourceLabel = self.credentials.autoReadWulingToken ? "五菱 App 自动读取" : "手动输入 Token"
                }
                self.queriedVehicleName = "车辆信息确认"
                self.showingVehicleInfoConfirm = true
                onComplete(successToast, true)
            }
        }
    }

    func importTokenFromSelectedFile(url: URL, onComplete: @escaping (_ toast: String, _ shouldConnect: Bool) -> Void) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            onComplete("读取文件失败", false)
            return
        }
        let token = (json["access_token"] as? String)
            ?? ((json["data"] as? [String: Any])?["access_token"] as? String)
        guard let token, !token.isEmpty else {
            onComplete("文件中未找到 access_token", false)
            return
        }
        accessTokenDraft = token
        credentials.accessToken = token
        credentials.tokenSourceLabel = "手动导入 SavedOAuthModel"
        credentials.tokenSourcePath = url.path
        isEditingToken = false
        fetchVehicleInfo(onComplete: onComplete, successToast: "车辆信息已获取并保存")
    }

    func saveManualConfig(onComplete: @escaping (_ toast: String, _ shouldConnect: Bool) -> Void) {
        let token = accessTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !vinDraft.isEmpty else {
            onComplete("请先查询车辆信息", false)
            return
        }
        credentials.accessToken = token
        credentials.vin = vinDraft
        credentials.phone = phoneDraft
        isEditingToken = false
        if credentials.tokenSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            credentials.tokenSourceLabel = "手动输入 Token"
        }
        onComplete("配置已保存 · \(vinDraft)", true)
    }

    func clear(onComplete: @escaping (_ toast: String, _ shouldConnect: Bool) -> Void) {
        credentials.reset()
        accessTokenDraft = ""
        vinDraft = ""
        phoneDraft = ""
        queriedVehicleName = ""
        isEditingToken = false
        onComplete("配置已清除", false)
    }

    private func maskToken(_ raw: String) -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "未读取" }
        guard token.count > 12 else { return token }
        let prefix = token.prefix(6)
        let suffix = token.suffix(6)
        return "\(prefix)******\(suffix)"
    }
}
