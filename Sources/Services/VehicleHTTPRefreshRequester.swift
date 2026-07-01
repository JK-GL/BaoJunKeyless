import Foundation

// MARK: - HTTP 刷新结果（只承载请求结果，不写状态）
struct VehicleHTTPRefreshResult {
    let payload: SGMWApiClient.VehicleHTTPPayload
    let fetchedAt: Date

    var carInfo: [String: String] { payload.carInfo }
    var carStatus: [String: String] { payload.carStatus }
}

// MARK: - HTTP 刷新请求器
// 只负责请求和封装结果，不修改 MQTTVehicleStateStore 内部状态
final class VehicleHTTPRefreshRequester {
    static let shared = VehicleHTTPRefreshRequester()
    private init() {}

    func fetch(accessToken: String, apiClient: SGMWApiClient = .shared, completion: @escaping (Result<VehicleHTTPRefreshResult, SGMWApiError>) -> Void) {
        apiClient.queryVehicleStatusResult(accessToken: accessToken) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let payload):
                completion(.success(VehicleHTTPRefreshResult(payload: payload, fetchedAt: Date())))
            }
        }
    }
}
