import Foundation
import CoreBluetooth
import CommonCrypto
import Security
import UIKit

final class VehicleBLEManager: NSObject {
    enum BLEControlError: LocalizedError {
        case notAuthenticated
        case writeCharacteristicMissing
        case invalidConfig
        case frameBuildFailed
        case writeFailed(String)
        case receiptTimeout
        case controlRejected(String)
        case sessionStopped

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "蓝牙尚未就绪"
            case .writeCharacteristicMissing: return "蓝牙控制通道不可用"
            case .invalidConfig: return "蓝牙配置无效"
            case .frameBuildFailed: return "蓝牙指令发送失败"
            case .writeFailed(_): return "蓝牙指令发送失败"
            case .receiptTimeout: return "蓝牙控制超时"
            case .controlRejected(_): return "车辆未接受该指令"
            case .sessionStopped: return "蓝牙连接已断开"
            }
        }
    }

    enum State: Equatable {
        case idle
        case unsupported
        case bluetoothOff
        case scanning
        case connecting
        case connected
        case authenticating
        case authenticated
        case authFailed(String)
        case error(String)
    }

    struct SessionConfig: Equatable {
        let bleMac: String
        let keyId: String
        let masterKey: String
        let keyMasterRandom: String
        let controlAes128Key: String?
        let bleType: String?
        let bleKey: String?
    }

    struct BLEControlReceipt: Equatable {
        let commandTitle: String
        let requestServiceId: UInt16
        let requestSubfunction: UInt16
        let requestControlDataHex: String
        let requestRandomDataHex: String
        let requestCRC16Hex: String
        let responseServiceId: UInt16?
        let responseSubfunction: UInt16?
        let responseRandomDataHex: String?
        let responsePayloadLength: UInt8?
        let responseErrorCodeHex: String?
        let responseType: UInt8?
        let crcCheckPassed: Bool?
        let elapsedMillis: Int?
        let rawHex: String
        let decryptedHex: String?
        let receivedAt: Date

        var isSuccess: Bool {
            if crcCheckPassed == false { return false }
            guard responseServiceId == 0xA956,
                  responseSubfunction == 0x0001,
                  responseErrorCodeHex == "00000000" else {
                return false
            }
            return true
        }

        var displayDetail: String {
            var parts: [String] = []
            parts.append("command=\(commandTitle)")
            parts.append("req=\(String(format: "%04X", requestServiceId))/\(String(format: "%04X", requestSubfunction))")
            parts.append("controlData=\(requestControlDataHex)")
            parts.append("random=\(requestRandomDataHex)")
            parts.append("crc=\(requestCRC16Hex)")
            if let responseServiceId { parts.append("respService=\(String(format: "%04X", responseServiceId))") }
            if let responseSubfunction { parts.append("respSub=\(String(format: "%04X", responseSubfunction))") }
            if let responseErrorCodeHex { parts.append("errorCode=\(responseErrorCodeHex)") }
            if let responseType { parts.append("responseType=\(responseType)") }
            if let crcCheckPassed { parts.append("crcOK=\(crcCheckPassed ? "1" : "0")") }
            if let elapsedMillis { parts.append("2A7E→2A7F=\(elapsedMillis)ms") }
            parts.append("rawLen=\(rawHex.count / 2)")
            if let decryptedHex { parts.append("decrypted=\(decryptedHex.prefix(32))") }
            return parts.joined(separator: ", ")
        }
    }

    struct NearbyDevice: Equatable, Identifiable {
        let id: String
        let peripheralIdentifier: String
        let name: String
        let rssi: Int
        /// true 表示 rssi 是广告或 readRSSI 返回的真实值；false 表示系统已连、尚未读到信号。
        let hasLiveRSSI: Bool
        let manufacturerMac: String?
        let serviceText: String
        let score: Int?
        let exactMatched: Bool
        /// 只对已验证属于当前车的 system-connected 外设为 true。
        let isSystemConnected: Bool
        let lastSeenAt: Date

        var displayName: String {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "--" : normalized
        }
    }

    private enum E300ControlCommand: Equatable {
        case unlock
        case lock
        case powerOff
        case powerOnReady

        var title: String {
            switch self {
            case .unlock: return "解锁"
            case .lock: return "锁车"
            case .powerOff: return "远程熄火"
            case .powerOnReady: return "启动电源"
            }
        }

        var serviceId: UInt16 {
            switch self {
            case .unlock, .lock: return 0x39D6
            case .powerOff, .powerOnReady: return 0x40E5
            }
        }

        var subfunction: UInt16 {
            switch self {
            case .unlock, .lock, .powerOnReady: return 0x0001
            case .powerOff: return 0x0003
            }
        }

        var controlDataHex: String {
            switch self {
            case .unlock: return "0101F2000000"
            case .lock: return "0102F2000000"
            case .powerOff: return "030900000000"
            case .powerOnReady: return "031200000000"
            }
        }
    }

    private struct E300PendingControl: Equatable {
        let command: E300ControlCommand
        let serviceId: UInt16
        let subfunction: UInt16
        let controlDataHex: String
        let randomDataHex: String
        let crc16Hex: String
        let sentAt: Date
    }

    private struct E300ControlFrameBuildResult {
        let command: E300ControlCommand
        let encryptedData: Data
        let plainData: Data
        let randomDataHex: String
        let bleKeyHex: String
        let crc16Hex: String
        let keySource: String
    }

    private struct E300ControlResponse {
        let serviceId: UInt16?
        let subfunction: UInt16?
        let randomDataHex: String?
        let payloadLength: UInt8?
        let errorCodeHex: String?
        let responseType: UInt8?
        let crcCheckPassed: Bool?
    }

    private enum ConnectionSource: Equatable {
        case bound
        case manufacturer
        case debugScore
    }

    private enum E300AuthStage: Equatable {
        case idle
        case waitingChallengeResponse
        case waitingAuthorizeConfirm(localRandom2Hex: String, remoteRandom1Hex: String)
    }

    private struct E300AuthResponse {
        let serviceId: UInt16
        let subfunction: UInt16
        let randomDataHex: String?
        let bleKeyHex: String?
        let payloadLength: UInt8?
        let rawHex: String
        let plainHex: String?
    }

    var onStateChange: ((State) -> Void)?
    var onLog: ((String, String?) -> Void)?
    var onNearbyDeviceDiscovered: ((NearbyDevice) -> Void)?
    var onControlReceipt: ((BLEControlReceipt) -> Void)?
    var onRSSIUpdate: ((Int) -> Void)?
    var onControlCompletion: (() -> Void)?

    private static let centralRestoreIdentifier = "com.baojun.keyless.ble.central"
    private lazy var central = CBCentralManager(
        delegate: self,
        queue: nil,
        options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.centralRestoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
    )
    private var config: SessionConfig?
    private var discoveredPeripheral: CBPeripheral?
    private var authWriteCharacteristic: CBCharacteristic?
    private var controlWriteCharacteristic: CBCharacteristic?
    private var notify181AReady = false
    private var notify182AReady = false
    private var hasStartedCentral = false
    private var didSendAuthFrame = false
    private var authStage: E300AuthStage = .idle
    private var runtimeAuthRandom1RemoteHex: String?
    private var runtimeAuthRandom2LocalHex: String?
    private var runtimeControlAes128KeyHex: String?
    private var pendingControl: E300PendingControl?
    private var pendingControlCompletion: ((Result<Void, BLEControlError>) -> Void)?
    private var pendingControlTimeoutWorkItem: DispatchWorkItem?
    private var rssiReadWorkItem: DispatchWorkItem?
    private var candidatePeripheral: CBPeripheral?
    private var candidateName: String = "--"
    private var candidateRSSI: Int = -127
    private var candidateScore: Int = Int.min
    /// 本轮广播已用 manufacturer MAC 精确证明属于当前车的 peripheral UUID。
    /// 仅在内存中保存，扫描新周期会清空；旁车 UUID 不会跨周期变成当前车凭据。
    private var currentVehicleBroadcastIDs: Set<UUID> = []
    private var nearbyDeviceLastReportAt: [String: Date] = [:]
    private var candidateSelectionWorkItem: DispatchWorkItem?
    private var scanWatchdogWorkItem: DispatchWorkItem?
    private var scanSelfHealWorkItem: DispatchWorkItem?
    private var didRunScanSelfHealThisCycle = false
    private var scanTotalTimeoutWorkItem: DispatchWorkItem?
    private var scanRetryWorkItem: DispatchWorkItem?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var foregroundObserver: NSObjectProtocol?
    private var currentConnectionSource: ConnectionSource?
    private let candidateMinimumScore = 8
    private(set) var state: State = .idle {
        didSet {
            guard oldValue != state else { return }
            let newState = state
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(newState)
            }
        }
    }
    private(set) var lastControlError: BLEControlError?

    var canSendVehicleControl: Bool {
        if case .authenticated = state {
            return controlWriteCharacteristic != nil && notify182AReady
        }
        return false
    }

    var scanTimeoutDuration: TimeInterval = 20
    var scanRetryInterval: TimeInterval = 0
    /// 为 false 时：扫描超时后不再自动重试（用于「仅围栏内扫描」圈外立即停扫）
    var allowsAutomaticScanRetry: Bool = true

    var canSendDoorLockControl: Bool {
        canSendVehicleControl
    }

    private let authService = CBUUID(string: "181A")
    private let authWrite = CBUUID(string: "2A6E")
    private let authNotify = CBUUID(string: "2A6F")
    private let controlService = CBUUID(string: "182A")
    private let controlWrite = CBUUID(string: "2A7E")
    private let controlNotify = CBUUID(string: "2A7F")

    func start(config: SessionConfig) {
        // 同 config 且会话活跃：只更新超时/间隔参数，不打断
        if self.config == config {
            switch state {
            case .scanning, .connecting, .connected, .authenticating, .authenticated:
                // 扫描中也允许再试一次系统已连接接管（后台常卡在扫）
                if case .scanning = state {
                    _ = adoptSystemConnectedIfAvailable(reason: "same-config-scanning")
                }
                return
            case .idle, .unsupported, .bluetoothOff, .authFailed, .error:
                // 允许从 idle/error 重启
                break
            }
        }

        let configChanged = self.config == nil ? false : (self.config != config)
        if configChanged {
            central.stopScan()
            if let discoveredPeripheral {
                central.cancelPeripheralConnection(discoveredPeripheral)
            }
            completePendingControl(.failure(.sessionStopped))
        }

        // 从 stop() 后重启：config 从 nil 变成非 nil，必须清运行时
        let restartingFromStopped = self.config == nil
        self.config = config
        lastControlError = nil
        if configChanged || restartingFromStopped {
            // 清运行时但不要无故 cancel 系统层已连外设；下面会优先接管
            clearSessionRuntime(cancelPendingControl: true)
        }

        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.config != nil else { return }
                self.handleCentralState()
            }
        }

        if !hasStartedCentral {
            hasStartedCentral = true
            _ = central
        } else {
            handleCentralState()
        }
    }

    /// 公开：优先接管系统已连接的钥匙 BLE（181A/182A），避免后台仍显示「扫描中」。
    @discardableResult
    func adoptSystemConnectedIfAvailable(reason: String = "adopt") -> Bool {
        guard config != nil, central.state == .poweredOn else { return false }
        switch state {
        case .connecting, .connected, .authenticating, .authenticated:
            return true
        default:
            break
        }
        return connectSystemConnectedPeripheralIfAvailable(reason: reason)
    }

    func stop() {
        config = nil
        central.stopScan()
        candidateSelectionWorkItem?.cancel()
        candidateSelectionWorkItem = nil
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        scanSelfHealWorkItem?.cancel()
        scanSelfHealWorkItem = nil
        scanTotalTimeoutWorkItem?.cancel()
        scanTotalTimeoutWorkItem = nil
        scanRetryWorkItem?.cancel()
        scanRetryWorkItem = nil
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        currentConnectionSource = nil
        isSystemConnectedSession = false
        if let discoveredPeripheral {
            central.cancelPeripheralConnection(discoveredPeripheral)
        }
        completePendingControl(.failure(.sessionStopped))
        clearSessionRuntime(cancelPendingControl: true)
        state = .idle
    }

    private func clearSessionRuntime(cancelPendingControl: Bool) {
        discoveredPeripheral = nil
        isSystemConnectedSession = false
        authWriteCharacteristic = nil
        controlWriteCharacteristic = nil
        notify181AReady = false
        notify182AReady = false
        didSendAuthFrame = false
        authStage = .idle
        runtimeAuthRandom1RemoteHex = nil
        runtimeAuthRandom2LocalHex = nil
        runtimeControlAes128KeyHex = nil
        rssiReadWorkItem?.cancel()
        rssiReadWorkItem = nil
        candidatePeripheral = nil
        candidateName = "--"
        candidateRSSI = -127
        candidateScore = Int.min
        currentVehicleBroadcastIDs.removeAll()
        didRunScanSelfHealThisCycle = false
        nearbyDeviceLastReportAt.removeAll()
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        scanSelfHealWorkItem?.cancel()
        scanSelfHealWorkItem = nil
        scanTotalTimeoutWorkItem?.cancel()
        scanTotalTimeoutWorkItem = nil
        scanRetryWorkItem?.cancel()
        scanRetryWorkItem = nil
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        currentConnectionSource = nil
        if cancelPendingControl {
            pendingControlTimeoutWorkItem?.cancel()
            pendingControlTimeoutWorkItem = nil
            pendingControl = nil
            pendingControlCompletion = nil
        }
    }

    /// 会话假活检测：UI/无感以为已鉴权，但系统 peripheral 已断或丢失时强制 idle。
    /// 由 RSSI 丢失超时等上层调用，避免「无 dBm 仍显示已连接」。
    func revalidateConnectionOrForceIdle(reason: String) -> Bool {
        switch state {
        case .connected, .authenticating, .authenticated:
            break
        default:
            return false
        }
        let peripheral = discoveredPeripheral
        let systemAlive: Bool = {
            guard let peripheral else { return false }
            if peripheral.state == .connected { return true }
            // 再问系统：上次 UUID 是否仍 connected
            let still = central.retrievePeripherals(withIdentifiers: [peripheral.identifier]).first
            return still?.state == .connected
        }()
        if systemAlive { return false }
        onLog?("BLE", "force idle stale session reason=\(reason) state=\(state) peripheral=\(peripheral?.identifier.uuidString.prefix(8) ?? "nil")")
        completePendingControl(.failure(.sessionStopped))
        clearSessionRuntime(cancelPendingControl: true)
        state = .idle
        if config != nil, central.state == .poweredOn {
            startConnectionFlow()
        }
        return true
    }

    private func handleCentralState() {
        switch central.state {
        case .poweredOn:
            startConnectionFlow()
        case .poweredOff:
            state = .bluetoothOff
        case .unsupported, .unauthorized:
            state = .unsupported
        case .resetting, .unknown:
            state = .idle
        @unknown default:
            state = .idle
        }
    }

    private func startConnectionFlow() {
        guard config != nil else {
            state = .idle
            return
        }
        // 已在连/已鉴权：不要回扫
        switch state {
        case .connecting, .connected, .authenticating, .authenticated:
            return
        default:
            break
        }
        guard discoveredPeripheral == nil else { return }
        // 0) 系统已连接且带 181A/182A 的外设：接管（最快）
        if connectSystemConnectedPeripheralIfAvailable(reason: "start-flow") {
            return
        }
        // 1) 软直连上次鉴权成功的 peripheral（无 UI 绑定；4s 超时失败立刻宽扫）
        //    恢复「以前绑定很快」的体感，但不卡死在假连接中
        if connectLastSuccessfulPeripheralIfAvailable() {
            return
        }
        // 2) 宽扫匹配钥匙 MAC
        startScanning()
    }

    /// 当前配置下可自动接管/标为当前车的 UUID 集合；服务、名称或车型绝不参与身份判断。
    private func verifiedCurrentVehicleIDs() -> Set<UUID> {
        var ids = currentVehicleBroadcastIDs
        if let lastID = loadLastSuccessfulPeripheralUUID() {
            ids.insert(lastID)
        }
        return ids
    }

    private func isVerifiedCurrentVehicle(_ peripheral: CBPeripheral) -> Bool {
        verifiedCurrentVehicleIDs().contains(peripheral.identifier)
    }

    /// 仅接管已证明属于当前车的系统连接：
    /// 1) 当前 bleMac + keyId 作用域下、此前鉴权成功的 SoftLast UUID；或
    /// 2) 本扫描周期通过 manufacturer MAC == 当前接口 bleMac 精确确认过的 UUID。
    /// 名称、车型、181A/182A 服务本身均不是车辆身份，不能据此接管旁车。
    private func connectSystemConnectedPeripheralIfAvailable(reason: String = "retrieve") -> Bool {
        guard config != nil else { return false }
        // 本轮 MAC 精确广播证据优先于历史 SoftLast；Set 无序不能决定身份优先级。
        var trustedIDs = currentVehicleBroadcastIDs
        if let lastID = loadLastSuccessfulPeripheralUUID() {
            trustedIDs.insert(lastID)
        }
        guard !trustedIDs.isEmpty else {
            onLog?("BLE", "system adopt skipped: no verified current-vehicle UUID reason=\(reason)")
            return false
        }
        let orderedIDs = Array(currentVehicleBroadcastIDs) + Array(trustedIDs.subtracting(currentVehicleBroadcastIDs))

        for identifier in orderedIDs {
            guard let peripheral = central.retrievePeripherals(withIdentifiers: [identifier]).first,
                  peripheral.state == .connected else { continue }
            isSystemConnectedSession = true
            publishCurrentVehicleNearbyDevice(peripheral, rssi: nil)
            connectScannedPeripheral(
                peripheral,
                localName: peripheral.name ?? "system-connected",
                rssi: 0,
                source: .manufacturer,
                detail: "systemConnected verifiedCurrentVehicle id=\(peripheral.identifier.uuidString.prefix(8)) reason=\(reason)"
            )
            onLog?("BLE", "adopt verified current-vehicle system connection id=\(peripheral.identifier.uuidString.prefix(8)) name=\(peripheral.name ?? "--") reason=\(reason)")
            return true
        }
        onLog?("BLE", "system adopt found no connected verified current-vehicle UUID reason=\(reason) candidates=\(trustedIDs.count)")
        return false
    }

    /// 将已验证属于当前车的连接发布到「附近设备」。没有 readRSSI 时显式标成系统已连，绝不伪造 dBm。
    private func publishCurrentVehicleNearbyDevice(_ peripheral: CBPeripheral, rssi: Int?) {
        guard let config else { return }
        let targetMac = normalizedBleMacHex(config.bleMac)
        onNearbyDeviceDiscovered?(
            NearbyDevice(
                id: peripheral.identifier.uuidString,
                peripheralIdentifier: peripheral.identifier.uuidString,
                name: peripheral.name ?? "system-connected",
                rssi: rssi ?? 0,
                hasLiveRSSI: rssi != nil,
                manufacturerMac: targetMac,
                serviceText: "181A,182A",
                score: nil,
                exactMatched: true,
                isSystemConnected: true,
                lastSeenAt: Date()
            )
        )
    }

    // MARK: - Soft last-vehicle (no user binding UI; only speed up reconnect + display)

    /// 上次鉴权成功的车：UUID 用于软直连，name/mac 用于无感页展示
    struct SoftLastVehicle: Codable, Equatable {
        var peripheralIdentifier: String
        var peripheralName: String
        var keyId: String
        var bleMac: String
        var lastAuthAt: Date

        var shortIdentifier: String { String(peripheralIdentifier.prefix(8)) }

        var displaySummary: String {
            let name = peripheralName.trimmingCharacters(in: .whitespacesAndNewlines)
            let mac = bleMac.trimmingCharacters(in: .whitespacesAndNewlines)
            let namePart = name.isEmpty || name == "--" ? "钥匙模块" : name
            let macPart = mac.isEmpty ? "--" : mac
            return "\(namePart) · \(macPart) · id=\(shortIdentifier)"
        }
    }

    private static let lastVehicleKeyPrefix = "BLE.SoftLastVehicle.v1."

    private static func softLastCacheKey(bleMac: String, keyId: String) -> String? {
        let mac = bleMac.uppercased().filter { $0.isLetter || $0.isNumber }
        let kid = keyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mac.isEmpty || !kid.isEmpty else { return nil }
        let macKey = mac.isEmpty ? "nomac" : String(mac.suffix(12))
        return lastVehicleKeyPrefix + macKey + "." + (kid.isEmpty ? "nokey" : kid)
    }

    /// 无感页展示：上次连接的 BLE（不是可取消的绑定）
    static func loadSoftLastVehicle(bleMac: String, keyId: String) -> SoftLastVehicle? {
        guard let key = softLastCacheKey(bleMac: bleMac, keyId: keyId),
              let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(SoftLastVehicle.self, from: data) else { return nil }
        // 30 天未再用则失效
        if Date().timeIntervalSince(value.lastAuthAt) > 30 * 24 * 60 * 60 {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return value
    }

    static func clearSoftLastVehicle(bleMac: String, keyId: String) {
        guard let key = softLastCacheKey(bleMac: bleMac, keyId: keyId) else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func lastVehicleCacheKey() -> String? {
        guard let config else { return nil }
        return Self.softLastCacheKey(bleMac: config.bleMac, keyId: config.keyId)
    }

    private func loadLastSuccessfulPeripheralUUID() -> UUID? {
        guard let key = lastVehicleCacheKey(),
              let data = UserDefaults.standard.data(forKey: key) else {
            // 兼容旧版只存 UUID 字符串
            if let key = lastVehicleCacheKey(),
               let raw = UserDefaults.standard.string(forKey: key),
               let uuid = UUID(uuidString: raw) {
                return uuid
            }
            return nil
        }
        if let value = try? JSONDecoder().decode(SoftLastVehicle.self, from: data),
           let uuid = UUID(uuidString: value.peripheralIdentifier) {
            return uuid
        }
        return nil
    }

    private func saveLastSuccessfulPeripheralUUID(_ uuid: UUID) {
        guard let config, let key = lastVehicleCacheKey() else { return }
        let previous = (UserDefaults.standard.data(forKey: key)).flatMap { try? JSONDecoder().decode(SoftLastVehicle.self, from: $0) }
        let name = discoveredPeripheral?.name
            ?? previous?.peripheralName
            ?? "--"
        let macDisplay: String = {
            if let hex = normalizedBleMacHex(config.bleMac), hex.count == 12 {
                var parts: [String] = []
                var idx = hex.startIndex
                for _ in 0..<6 {
                    let next = hex.index(idx, offsetBy: 2)
                    parts.append(String(hex[idx..<next]))
                    idx = next
                }
                return parts.joined(separator: ":")
            }
            return config.bleMac
        }()
        let value = SoftLastVehicle(
            peripheralIdentifier: uuid.uuidString,
            peripheralName: name,
            keyId: config.keyId,
            bleMac: macDisplay,
            lastAuthAt: Date()
        )
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
            onLog?("BLE", "soft last-vehicle saved \(value.displaySummary)")
        }
    }

    /// 软直连上次鉴权成功的车：无 UI 绑定；短超时失败立刻宽扫，不卡「连接中」。
    private func connectLastSuccessfulPeripheralIfAvailable() -> Bool {
        guard let config else { return false }
        guard let uuid = loadLastSuccessfulPeripheralUUID() else {
            onLog?("BLE", "no soft last-vehicle uuid")
            return false
        }
        let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else {
            onLog?("BLE", "soft last-vehicle uuid not in system cache id=\(uuid.uuidString.prefix(8)), wide scan")
            return false
        }
        // 已连接则走严格接管；系统没有广播 RSSI 时不伪造 dBm。
        if peripheral.state == .connected {
            isSystemConnectedSession = true
            publishCurrentVehicleNearbyDevice(peripheral, rssi: nil)
            connectScannedPeripheral(
                peripheral,
                localName: peripheral.name ?? "last-vehicle",
                rssi: 0,
                source: .manufacturer,
                detail: "softLast alreadyConnected id=\(uuid.uuidString.prefix(8))"
            )
            onLog?("BLE", "soft last-vehicle already connected id=\(uuid.uuidString.prefix(8))")
            return true
        }
        discoveredPeripheral = peripheral
        currentConnectionSource = .manufacturer
        peripheral.delegate = self
        central.stopScan()
        candidateSelectionWorkItem?.cancel()
        candidateSelectionWorkItem = nil
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        scanSelfHealWorkItem?.cancel()
        scanSelfHealWorkItem = nil
        scanTotalTimeoutWorkItem?.cancel()
        scanTotalTimeoutWorkItem = nil
        isSystemConnectedSession = false
        state = .connecting
        onLog?("BLE", "soft last-vehicle direct connect id=\(uuid.uuidString.prefix(8)) keyId=\(config.keyId) mac=\(config.bleMac)")
        // 短超时：4s 失败立刻宽扫（比旧绑定 10s 更不卡）
        scheduleConnectionTimeout(uuid: peripheral.identifier, source: "soft-last", seconds: 4)
        central.connect(peripheral, options: nil)
        return true
    }

    private var allowsDebugScoreFallback: Bool {
        AppDiagnosticsSettings.vehicleControlRouteMode == .forceBLE
    }

    /// 当前会话是否基于系统已连接外设（retrieveConnected / alreadyConnected）
    private(set) var isSystemConnectedSession = false

    private var connectionSourceText: String {
        switch currentConnectionSource {
        case .bound: return "bound"
        case .manufacturer: return "manufacturer"
        case .debugScore: return "debugScore"
        case nil: return "none"
        }
    }

    private func startScanning(forceRestartScanning: Bool = false, preservingCurrentVehicleEvidence: Bool = false) {
        guard config != nil else {
            state = .idle
            return
        }
        if case .scanning = state, !forceRestartScanning { return }
        guard discoveredPeripheral == nil else { return }
        if !preservingCurrentVehicleEvidence {
            currentVehicleBroadcastIDs.removeAll()
            didRunScanSelfHealThisCycle = false
        }
        candidateSelectionWorkItem?.cancel()
        candidateSelectionWorkItem = nil
        scanRetryWorkItem?.cancel()
        scanRetryWorkItem = nil
        candidatePeripheral = nil
        candidateName = "--"
        candidateRSSI = -127
        candidateScore = Int.min
        nearbyDeviceLastReportAt.removeAll()
        central.stopScan()
        state = .scanning
        let targetMac = normalizedBleMacHex(config?.bleMac ?? "") ?? "--"
        let scanMode = forceRestartScanning ? "self-heal restart" : "official scan"
        onLog?("BLE", "\(scanMode) manufacturerLast6 target=\(targetMac) debugFallback=\(allowsDebugScoreFallback ? 1 : 0) minScore=\(candidateMinimumScore)")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scheduleScanWatchdog()
        scheduleScanSelfHealIfNeeded()
        // 5 秒自愈仅重开发现广播，原扫描总超时仍按首轮绝对时间执行。
        if !forceRestartScanning {
            scheduleScanTotalTimeout()
        }
    }

    /// 扫描中的 2.5 秒复查：只接管 SoftLast / 本轮精确 MAC 广播已证明属于当前车的 UUID。
    private func scheduleScanWatchdog() {
        scanWatchdogWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard case .scanning = self.state else { return }
            if self.connectSystemConnectedPeripheralIfAvailable(reason: "scan-watchdog-2.5s") {
                return
            }
            let targetMac = self.normalizedBleMacHex(self.config?.bleMac ?? "") ?? "--"
            self.onLog?("BLE", "scan watchdog 2.5s no verified system connection target=\(targetMac) evidenceUUIDs=\(self.currentVehicleBroadcastIDs.count) bestScore=\(self.candidateScore)")
            self.scheduleScanWatchdog()
        }
        scanWatchdogWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    /// 同一逻辑扫描周期最多一次：5 秒未接管仅重启扫描器，不取消 peripheral connection，不清会话。
    private func scheduleScanSelfHealIfNeeded() {
        scanSelfHealWorkItem?.cancel()
        guard !didRunScanSelfHealThisCycle else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard case .scanning = self.state, !self.didRunScanSelfHealThisCycle else { return }
            if self.connectSystemConnectedPeripheralIfAvailable(reason: "scan-self-heal-5s-pre-stop") {
                return
            }
            self.didRunScanSelfHealThisCycle = true
            self.onLog?("BLE", "scan self-heal 5s: stopScan → verified-current-vehicle recheck → restart; no peripheral connection cancelled")
            self.central.stopScan()
            if self.connectSystemConnectedPeripheralIfAvailable(reason: "scan-self-heal-5s-after-stop") {
                return
            }
            self.startScanning(forceRestartScanning: true, preservingCurrentVehicleEvidence: true)
        }
        scanSelfHealWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    private func scheduleScanTotalTimeout() {
        scanTotalTimeoutWorkItem?.cancel()
        let timeout = scanTimeoutDuration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard case .scanning = self.state else { return }
            self.onLog?("BLE", "scan total timeout (\(Int(timeout))s), stopping scan")
            self.central.stopScan()
            self.scanWatchdogWorkItem?.cancel()
            self.scanWatchdogWorkItem = nil
            self.scanSelfHealWorkItem?.cancel()
            self.scanSelfHealWorkItem = nil
            self.candidateSelectionWorkItem?.cancel()
            self.candidateSelectionWorkItem = nil
            if self.discoveredPeripheral == nil {
                self.state = .idle
                self.scheduleScanRetryIfNeeded()
            }
        }
        scanTotalTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    private func scheduleScanRetryIfNeeded() {
        scanRetryWorkItem?.cancel()
        scanRetryWorkItem = nil
        guard config != nil else { return }
        guard allowsAutomaticScanRetry else {
            onLog?("BLE", "scan retry suppressed (outside fence / policy)")
            return
        }
        let interval = max(0, scanRetryInterval)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.config != nil else { return }
            guard self.allowsAutomaticScanRetry else { return }
            guard case .idle = self.state else { return }
            self.startConnectionFlow()
        }
        scanRetryWorkItem = work
        if interval <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        }
    }

    private func scheduleConnectionTimeout(uuid: UUID, source: String, seconds: TimeInterval = 10) {
        connectionTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let peripheral = self.discoveredPeripheral,
                  peripheral.identifier == uuid else { return }
            guard case .connecting = self.state else { return }
            self.onLog?("BLE", "connection timeout (\(Int(seconds))s) source=\(source), disconnecting")
            self.central.cancelPeripheralConnection(peripheral)
            self.discoveredPeripheral = nil
            self.currentConnectionSource = nil
            // 超时后必须回到可重试路径；软直连/普通连接都回宽扫
            self.state = .idle
            self.scheduleScanRetryIfNeeded()
            // 若当前是 idle 且允许扫，立即扫更快
            if self.config != nil, self.allowsAutomaticScanRetry {
                self.startScanning()
            }
        }
        connectionTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func finishIfReady() {
        if notify181AReady {
            if case .connecting = state {
                state = .connected
            }
            onLog?("BLE", "auth notify ready 2A6F, start auth when write characteristic exists")
            sendAuthFrameIfPossible()
        }
        if notify182AReady {
            onLog?("BLE", "control notify ready 2A7F")
        }
    }

    func sendDoorLockCommand(lock: Bool, completion: @escaping (Result<Void, BLEControlError>) -> Void) {
        sendE300ControlCommand(lock ? .lock : .unlock, completion: completion)
    }

    func sendPowerOnReadyCommand(completion: @escaping (Result<Void, BLEControlError>) -> Void) {
        sendE300ControlCommand(.powerOnReady, completion: completion)
    }

    func sendPowerOffCommand(completion: @escaping (Result<Void, BLEControlError>) -> Void) {
        sendE300ControlCommand(.powerOff, completion: completion)
    }

    private func sendE300ControlCommand(_ command: E300ControlCommand, completion: @escaping (Result<Void, BLEControlError>) -> Void) {
        guard case .authenticated = state else {
            lastControlError = .notAuthenticated
            completion(.failure(.notAuthenticated))
            return
        }
        guard let config,
              let peripheral = discoveredPeripheral,
              let controlWriteCharacteristic else {
            lastControlError = .writeCharacteristicMissing
            completion(.failure(.writeCharacteristicMissing))
            return
        }
        guard pendingControl == nil else {
            onLog?("BLE", "E300 control blocked: pending command already in flight")
            completion(.failure(BLEControlError.writeFailed("已有待处理 BLE 命令")))
            return
        }
        guard notify182AReady else {
            lastControlError = .writeCharacteristicMissing
            onLog?("BLE", "E300 control blocked: 2A7F notify not ready")
            completion(.failure(.writeCharacteristicMissing))
            return
        }
        let hasPresetControlKey = !(config.controlAes128Key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard runtimeControlAes128KeyHex != nil || hasPresetControlKey else {
            lastControlError = .notAuthenticated
            onLog?("BLE", "E300 control blocked: runtimeControlAes128Key missing")
            completion(.failure(.notAuthenticated))
            return
        }
        guard let build = makeE300ControlFrame(config: config, command: command) else {
            lastControlError = .frameBuildFailed
            completion(.failure(.frameBuildFailed))
            return
        }
        lastControlError = nil
        pendingControlTimeoutWorkItem?.cancel()
        pendingControlCompletion = completion
        pendingControl = E300PendingControl(
            command: command,
            serviceId: command.serviceId,
            subfunction: command.subfunction,
            controlDataHex: command.controlDataHex,
            randomDataHex: build.randomDataHex,
            crc16Hex: build.crc16Hex,
            sentAt: Date()
        )
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingControlCompletion != nil else { return }
            self.onLog?("BLE", "E300 control receipt timeout command=\(command.title) serviceId=\(String(format: "%04X", command.serviceId)) sub=\(String(format: "%04X", command.subfunction))")
            self.completePendingControl(.failure(.receiptTimeout))
        }
        pendingControlTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timeout)
        onLog?("BLE", "E300 control send command=\(command.title) serviceId=\(String(format: "%04X", command.serviceId)) sub=\(String(format: "%04X", command.subfunction)) controlData=\(command.controlDataHex) random=\(build.randomDataHex) crc=\(build.crc16Hex) keySource=\(build.keySource) plainLen=\(build.plainData.count) encryptedLen=\(build.encryptedData.count) bleKey=\(build.bleKeyHex.suffix(4))")
        peripheral.writeValue(build.encryptedData, for: controlWriteCharacteristic, type: .withResponse)
    }

    private func completePendingControl(_ result: Result<Void, BLEControlError>) {
        pendingControlTimeoutWorkItem?.cancel()
        pendingControlTimeoutWorkItem = nil
        let completion = pendingControlCompletion
        pendingControlCompletion = nil
        pendingControl = nil
        if case .failure(let error) = result {
            lastControlError = error
        }
        completion?(result)
    }

    private func sendAuthFrameIfPossible() {
        guard !didSendAuthFrame,
              let config,
              let peripheral = discoveredPeripheral,
              let authWriteCharacteristic,
              let frame = makeAuthFrame(config: config) else { return }
        didSendAuthFrame = true
        authStage = .waitingChallengeResponse
        state = .authenticating
        let bleKeySuffix = e300BleKeyHex(config: config).map { String($0.suffix(4)) } ?? "--"
        onLog?("BLE", "E300 auth step1 send 38C7/0001 len=\(frame.count) bleKey=\(bleKeySuffix)")
        peripheral.writeValue(frame, for: authWriteCharacteristic, type: .withResponse)
    }

    private func makeAuthFrame(config: SessionConfig) -> Data? {
        guard let bleKeyHex = e300BleKeyHex(config: config) else {
            onLog?("BLE", "E300 auth bleKey invalid")
            return nil
        }

        let currentTime = UInt32(Date().timeIntervalSince1970)
        let random1Hex = String(format: "%08X", currentTime)
        let crcPrefixHex = "38C7" + "0001" + "00000000" + random1Hex + bleKeyHex + "06" + "000000000000"

        guard let crcPrefixData = Data(hex: crcPrefixHex) else {
            onLog?("BLE", "E300 auth step1 crc prefix invalid")
            return nil
        }
        let crcHex = String(format: "%04X", crc16CcittFalse(crcPrefixData))
        let finalHex = crcPrefixHex + crcHex + "00000000000000"

        guard let frame = Data(hex: finalHex), frame.count == 32 else {
            onLog?("BLE", "E300 auth step1 frame invalid len=\(finalHex.count / 2)")
            return nil
        }
        return frame
    }

    private func e300AuthKeyData(config: SessionConfig) -> Data? {
        guard let masterKey = Data(hex: config.masterKey), masterKey.count == 16,
              let random = Data(hex: config.keyMasterRandom), random.count == 16 else {
            return nil
        }
        return masterKey.xor(with: random)
    }

    private func makeAuthChallengeReplyFrame(config: SessionConfig, remoteRandom1Hex: String) -> (data: Data, localRandom2Hex: String)? {
        guard let bleKeyHex = e300BleKeyHex(config: config) else {
            onLog?("BLE", "E300 auth step3 bleKey invalid")
            return nil
        }
        guard let authKey = e300AuthKeyData(config: config) else {
            onLog?("BLE", "E300 auth step3 aes128Key invalid")
            return nil
        }

        let localRandom2Hex = makeRandomUInt32Hex()
        let crcPrefixHex = "38C7" + "0002" + localRandom2Hex + remoteRandom1Hex + bleKeyHex + "06" + "000000000000"

        guard let crcPrefixData = Data(hex: crcPrefixHex) else {
            onLog?("BLE", "E300 auth step3 crc prefix invalid")
            return nil
        }
        let crcHex = String(format: "%04X", crc16CcittFalse(crcPrefixData))
        let finalHex = crcPrefixHex + crcHex + "00000000000000"

        guard let plain = Data(hex: finalHex), plain.count == 32 else {
            onLog?("BLE", "E300 auth step3 plain invalid len=\(finalHex.count / 2)")
            return nil
        }
        guard let encrypted = aesECBNoPaddingEncrypt(plain, key: authKey), encrypted.count == 32 else {
            onLog?("BLE", "E300 auth step3 aes encrypt failed")
            return nil
        }
        return (encrypted, localRandom2Hex)
    }

    private func makeE300ControlFrame(config: SessionConfig, command: E300ControlCommand) -> E300ControlFrameBuildResult? {
        guard let keyInfo = e300ControlKeyData(config: config) else {
            onLog?("BLE", "E300 control key invalid")
            return nil
        }
        guard let bleKeyHex = e300BleKeyHex(config: config) else {
            onLog?("BLE", "E300 bleKey invalid")
            return nil
        }
        let randomDataHex = makeRandomUInt32Hex()
        let serviceIdHex = String(format: "%04X", command.serviceId)
        let subfunctionHex = String(format: "%04X", command.subfunction)
        let crcPrefixHex = serviceIdHex + subfunctionHex + "00000000" + randomDataHex + bleKeyHex + "06" + command.controlDataHex
        guard let crcPrefixData = Data(hex: crcPrefixHex) else {
            onLog?("BLE", "E300 crc prefix invalid")
            return nil
        }
        let crc = crc16CcittFalse(crcPrefixData)
        let crcHex = String(format: "%04X", crc)
        let finalDataHex = crcPrefixHex + crcHex + "00000000000000"
        guard let plainData = Data(hex: finalDataHex), plainData.count == 32 else {
            onLog?("BLE", "E300 plain frame invalid len=\(finalDataHex.count / 2)")
            return nil
        }
        guard let encryptedData = aesECBNoPaddingEncrypt(plainData, key: keyInfo.key), encryptedData.count == 32 else {
            onLog?("BLE", "E300 control aes encrypt failed")
            return nil
        }
        return E300ControlFrameBuildResult(
            command: command,
            encryptedData: encryptedData,
            plainData: plainData,
            randomDataHex: randomDataHex,
            bleKeyHex: bleKeyHex,
            crc16Hex: crcHex,
            keySource: keyInfo.source
        )
    }

    private func e300ControlKeyData(config: SessionConfig) -> (key: Data, source: String)? {
        if let runtime = runtimeControlAes128KeyHex,
           let key = Data(hex: runtime), key.count == 16 {
            return (key, "runtimeControlAes128Key")
        }
        if let preset = config.controlAes128Key?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preset.isEmpty,
           let key = Data(hex: preset), key.count == 16 {
            return (key, "presetControlAes128Key")
        }
        return nil
    }

    private func e300BleKeyHex(config: SessionConfig) -> String? {
        if let value = parseUInt32(config.keyId) {
            return String(format: "%08X", value)
        }

        if let bleKey = config.bleKey?.trimmingCharacters(in: .whitespacesAndNewlines), !bleKey.isEmpty {
            let raw = bleKey
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .uppercased()
            guard raw.allSatisfy({ UInt8(String($0), radix: 16) != nil }) else { return nil }
            return String(raw.suffix(8)).leftPadded(to: 8, with: "0")
        }

        return nil
    }

    /// Legacy wrapped49 helper. Not used by current official E300 auth/control path.
    private func wrapBLEFrame(_ encrypted: Data) -> Data {
        var frame = Data([0xAA])
        let length = UInt16(encrypted.count).bigEndian
        frame.append(contentsOf: length.bigEndianBytes)
        frame.append(encrypted)
        let checksum = encrypted.reduce(UInt8(0)) { UInt8(($0 &+ $1) & 0xFF) }
        frame.append(checksum)
        frame.append(0x55)
        if frame.count < 49 {
            frame.append(Data(repeating: 0, count: 49 - frame.count))
        }
        return frame
    }

    private func aesECBEncrypt(_ plain: Data, key: Data) -> Data? {
        cryptECB(input: plain, key: key, operation: CCOperation(kCCEncrypt), options: CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode), outputLength: ((plain.count / kCCBlockSizeAES128) + 1) * kCCBlockSizeAES128)
    }

    private func aesECBDecrypt(_ encrypted: Data, key: Data) -> Data? {
        cryptECB(input: encrypted, key: key, operation: CCOperation(kCCDecrypt), options: CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode), outputLength: encrypted.count)
    }

    private func aesECBNoPaddingEncrypt(_ plain: Data, key: Data) -> Data? {
        guard plain.count % kCCBlockSizeAES128 == 0 else { return nil }
        return cryptECB(input: plain, key: key, operation: CCOperation(kCCEncrypt), options: CCOptions(kCCOptionECBMode), outputLength: plain.count)
    }

    private func aesECBNoPaddingDecrypt(_ encrypted: Data, key: Data) -> Data? {
        guard encrypted.count % kCCBlockSizeAES128 == 0 else { return nil }
        return cryptECB(input: encrypted, key: key, operation: CCOperation(kCCDecrypt), options: CCOptions(kCCOptionECBMode), outputLength: encrypted.count)
    }

    private func cryptECB(input: Data, key: Data, operation: CCOperation, options: CCOptions, outputLength: Int) -> Data? {
        var out = Data(count: outputLength)
        let outCount = out.count
        var outLength: size_t = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        options,
                        keyBytes.baseAddress, key.count,
                        nil,
                        inputBytes.baseAddress, input.count,
                        outBytes.baseAddress, outCount,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.removeSubrange(outLength..<out.count)
        return out
    }

    private func handleAuthNotification(_ data: Data) {
        func failAuth(_ reason: String, detail: String) {
            state = .authFailed(reason)
            authStage = .idle
            onLog?("BLE", detail)
            // 鉴权失败：断开后回宽扫（不再区分绑定）
            fallbackToWideScanAfterBoundFailure()
        }

        guard let config else {
            failAuth("鉴权配置无效", detail: "E300 auth response skipped: config missing")
            return
        }

        guard let response = parseE300AuthResponse(data, config: config) else {
            failAuth("鉴权响应解析失败", detail: "E300 auth response parse failed")
            return
        }

        if response.serviceId == 0xA857 && response.subfunction == 0x0001 {
            guard let remoteRandom1Hex = response.randomDataHex, remoteRandom1Hex.count == 8 else {
                failAuth("A857/0001 randomData1 无效", detail: "E300 auth failed invalid A857/0001 random1")
                return
            }
            runtimeAuthRandom1RemoteHex = remoteRandom1Hex

            guard let (frame, localRandom2Hex) = makeAuthChallengeReplyFrame(config: config, remoteRandom1Hex: remoteRandom1Hex),
                  let peripheral = discoveredPeripheral,
                  let authWriteCharacteristic else {
                failAuth("38C7/0002 构造失败", detail: "E300 auth failed build 38C7/0002")
                return
            }

            runtimeAuthRandom2LocalHex = localRandom2Hex
            authStage = .waitingAuthorizeConfirm(localRandom2Hex: localRandom2Hex, remoteRandom1Hex: remoteRandom1Hex)
            onLog?("BLE", "E300 auth step2 recv A857/0001 random1=\(remoteRandom1Hex)")
            onLog?("BLE", "E300 auth step3 send 38C7/0002 random2=\(localRandom2Hex)")
            peripheral.writeValue(frame, for: authWriteCharacteristic, type: .withResponse)
            return
        }

        if response.serviceId == 0xA857 && response.subfunction == 0x0002 {
            guard let localRandom2Hex = runtimeAuthRandom2LocalHex,
                  let remoteRandom1Hex = runtimeAuthRandom1RemoteHex,
                  let returnedRandom2Hex = response.randomDataHex else {
                failAuth("A857/0002 状态不完整", detail: "E300 auth failed incomplete A857/0002 state")
                return
            }
            guard returnedRandom2Hex == localRandom2Hex else {
                failAuth("random2 不匹配", detail: "E300 auth failed random2 local=\(localRandom2Hex) remote=\(returnedRandom2Hex)")
                return
            }

            runtimeControlAes128KeyHex = remoteRandom1Hex + localRandom2Hex + remoteRandom1Hex + localRandom2Hex
            authStage = .idle
            state = .authenticated
            onLog?("BLE", "E300 auth success random1=\(remoteRandom1Hex) random2=\(localRandom2Hex) source=\(connectionSourceText)")
            onLog?("BLE", "runtimeControlAes128Key ready len=\(runtimeControlAes128KeyHex?.count ?? 0)")
            // 软记录上次成功 UUID，供下次快速直连（无 UI 绑定）
            if let id = discoveredPeripheral?.identifier {
                saveLastSuccessfulPeripheralUUID(id)
            }
            startRSSILoop()
            return
        }

        let plainPreview = response.plainHex.map { String($0.prefix(32)) } ?? "--"
        onLog?("BLE", "ignore auth notify service=\(String(format: "%04X", response.serviceId)) sub=\(String(format: "%04X", response.subfunction)) rawLen=\(response.rawHex.count / 2) plain=\(plainPreview)")
    }

    private func fallbackToWideScanAfterBoundFailure() {
        guard let peripheral = discoveredPeripheral else {
            currentConnectionSource = nil
            startScanning()
            return
        }
        central.cancelPeripheralConnection(peripheral)
        discoveredPeripheral = nil
        currentConnectionSource = nil
        notify181AReady = false
        notify182AReady = false
        didSendAuthFrame = false
        authStage = .idle
        runtimeAuthRandom1RemoteHex = nil
        runtimeAuthRandom2LocalHex = nil
        runtimeControlAes128KeyHex = nil
        authWriteCharacteristic = nil
        controlWriteCharacteristic = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.startScanning()
        }
    }

    private func normalizedBleMacHex(_ mac: String) -> String? {
        let normalized = mac.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count >= 12 else { return nil }
        return String(normalized.suffix(12))
    }

    private func manufacturerLast6MacHex(from advertisementData: [String: Any]) -> String? {
        guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              manufacturerData.count >= 6 else { return nil }
        return Data(manufacturerData.suffix(6)).hexString
    }

    private func extractAuthPayload(from frame: Data) -> Data? {
        guard !frame.isEmpty else { return nil }
        if frame.first == 0xAA, frame.count >= 5 {
            let length = Int(UInt16(frame[1]) << 8 | UInt16(frame[2]))
            let start = 3
            let end = start + length
            guard end <= frame.count else { return nil }
            return frame.subdata(in: start..<end)
        }
        if frame.first == 0x00, frame.count > 1 {
            let stripped = frame.subdata(in: 1..<frame.count)
            if stripped.count % 16 == 0 || (stripped.count >= 2 && stripped.readUInt16BE(at: 0) == 0xA857) {
                return stripped
            }
        }
        return frame
    }

    private func parseE300AuthResponse(_ data: Data, config: SessionConfig) -> E300AuthResponse? {
        guard let payload = extractAuthPayload(from: data) else { return nil }
        let rawHex = data.hexString
        var source = payload
        var plainHex: String?

        if let authKey = e300AuthKeyData(config: config),
           payload.count % 16 == 0,
           let decrypted = aesECBNoPaddingDecrypt(payload, key: authKey),
           decrypted.count >= 17 {
            let sid = decrypted.readUInt16BE(at: 0)
            let sub = decrypted.readUInt16BE(at: 2)
            if sid == 0xA857 && (sub == 0x0001 || sub == 0x0002) {
                source = decrypted
                plainHex = decrypted.hexString
            }
        }

        guard source.count >= 17 else { return nil }
        let serviceId = source.readUInt16BE(at: 0)
        let subfunction = source.readUInt16BE(at: 2)
        let randomDataHex = source.count >= 12 ? source.subdata(in: 8..<12).hexString : nil
        let bleKeyHex = source.count >= 16 ? source.subdata(in: 12..<16).hexString : nil
        let payloadLength = source.count >= 17 ? source[16] : nil

        return E300AuthResponse(
            serviceId: serviceId,
            subfunction: subfunction,
            randomDataHex: randomDataHex,
            bleKeyHex: bleKeyHex,
            payloadLength: payloadLength,
            rawHex: rawHex,
            plainHex: plainHex
        )
    }

    private func handleControlNotification(_ data: Data) {
        let rawHex = data.hexString
        guard let plain = decryptControlNotificationData(data) else {
            onLog?("BLE", "E300 control notify decrypt failed raw=\(rawHex.prefix(32))")
            return
        }
        let parsed = parseE300ControlResponse(plain)
        let pending = pendingControl

        let receipt = BLEControlReceipt(
            commandTitle: pending?.command.title ?? "未知BLE控制",
            requestServiceId: pending?.serviceId ?? 0,
            requestSubfunction: pending?.subfunction ?? 0,
            requestControlDataHex: pending?.controlDataHex ?? "--",
            requestRandomDataHex: pending?.randomDataHex ?? "--",
            requestCRC16Hex: pending?.crc16Hex ?? "--",
            responseServiceId: parsed.serviceId,
            responseSubfunction: parsed.subfunction,
            responseRandomDataHex: parsed.randomDataHex,
            responsePayloadLength: parsed.payloadLength,
            responseErrorCodeHex: parsed.errorCodeHex,
            responseType: parsed.responseType,
            crcCheckPassed: parsed.crcCheckPassed,
            elapsedMillis: pending.map { Int(Date().timeIntervalSince($0.sentAt) * 1000) },
            rawHex: rawHex,
            decryptedHex: plain.hexString,
            receivedAt: Date()
        )

        let context = pending.map {
            "pending=\($0.command.title) serviceId=\(String(format: "%04X", $0.serviceId)) sub=\(String(format: "%04X", $0.subfunction)) random=\($0.randomDataHex)"
        } ?? "no pending control context"

        onLog?("BLE", "E300 control notify received | \(context) | \(receipt.displayDetail)")
        onControlReceipt?(receipt)

        guard let pending else {
            onLog?("BLE", "E300 control notify ignored: no pending | \(receipt.displayDetail)")
            return
        }

        let randomMatchesRequest = parsed.randomDataHex?.uppercased() == pending.randomDataHex.uppercased()
        let responseMatchesRequest =
            parsed.serviceId == 0xA956 &&
            parsed.subfunction == 0x0001 &&
            randomMatchesRequest
        // 实车负 ACK：FFFF / 原请求 serviceId（如 39D6）/ 同一 random。
        // 这已是车端明确答复，绝不能继续等到 receiptTimeout。
        let negativeResponseMatchesRequest =
            parsed.serviceId == 0xFFFF &&
            parsed.subfunction == pending.serviceId &&
            randomMatchesRequest

        let crcOK = parsed.crcCheckPassed != false
        let errorOK = parsed.errorCodeHex == "00000000"

        if negativeResponseMatchesRequest {
            let code = parsed.errorCodeHex ?? "--"
            onLog?("BLE", "E300 control rejected by vehicle random=\(parsed.randomDataHex ?? "--") errorCode=\(code) crc=\(parsed.crcCheckPassed.map { $0 ? "1" : "0" } ?? "--")")
            completePendingControl(.failure(.controlRejected("车辆拒绝控制（\(code)）")))
        } else if responseMatchesRequest && crcOK && errorOK {
            let serviceText = parsed.serviceId.map { String(format: "%04X", $0) } ?? "--"
            onLog?(
                "BLE",
                "E300 control success service=\(serviceText) random=\(parsed.randomDataHex ?? "--") errorCode=\(parsed.errorCodeHex ?? "--") crc=\(parsed.crcCheckPassed.map { $0 ? "1" : "0" } ?? "--")"
            )
            completePendingControl(.success(()))
            DispatchQueue.main.async { [weak self] in
                self?.onControlCompletion?()
            }
        } else if responseMatchesRequest {
            onLog?(
                "BLE",
                "E300 control rejected random=\(parsed.randomDataHex ?? "--") errorCode=\(parsed.errorCodeHex ?? "--") crc=\(parsed.crcCheckPassed.map { $0 ? "1" : "0" } ?? "--")"
            )
            completePendingControl(.failure(.controlRejected(receipt.displayDetail)))
        } else {
            onLog?(
                "BLE",
                "E300 control notify ignored: random mismatch | pendingRandom=\(pending.randomDataHex) responseRandom=\(parsed.randomDataHex ?? "--") service=\(parsed.serviceId.map { String(format: "%04X", $0) } ?? "--")"
            )
            // 不完成 pending，继续等待正确 ACK 或超时。
        }
    }

    private func decryptControlNotificationData(_ data: Data) -> Data? {
        guard let config, let keyInfo = e300ControlKeyData(config: config),
              let encrypted = extractE300ControlEncryptedPayload(from: data),
              let plain = aesECBNoPaddingDecrypt(encrypted, key: keyInfo.key),
              !plain.isEmpty else { return nil }
        return plain
    }

    private func extractE300ControlEncryptedPayload(from frame: Data) -> Data? {
        if frame.first == 0xAA, frame.count >= 5 {
            let length = Int(UInt16(frame[1]) << 8 | UInt16(frame[2]))
            let start = 3
            let end = start + length
            guard end <= frame.count else { return nil }
            return frame.subdata(in: start..<end)
        }
        if frame.first == 0x00, frame.count > 1 {
            return frame.subdata(in: 1..<frame.count)
        }
        return frame
    }

    private func parseE300ControlResponse(_ data: Data?) -> E300ControlResponse {
        guard let data, data.count >= 13 else {
            return E300ControlResponse(
                serviceId: nil,
                subfunction: nil,
                randomDataHex: nil,
                payloadLength: nil,
                errorCodeHex: nil,
                responseType: nil,
                crcCheckPassed: nil
            )
        }

        let serviceId = data.readUInt16BE(at: 0)
        let subfunction = data.readUInt16BE(at: 2)
        let randomDataHex = data.subdata(in: 4..<8).hexString
        let payloadLength = data[8]

        // A956/0001 实车帧规格：
        // byte[0..<2]  = serviceId
        // byte[2..<4]  = subfunction
        // byte[4..<8]  = randomData，必须回显本次控制帧 random
        // byte[8]      = payloadLength，实车控制 ACK 为 0x04
        // byte[9..<13] = errorCode，00000000 表示控制成功
        let errorCodeHex = data.subdata(in: 9..<13).hexString
        let responseType: UInt8 = errorCodeHex == "00000000" ? 1 : 0
        let crcCheckPassed = crc16CcittFalse(data) == 0

        return E300ControlResponse(
            serviceId: serviceId,
            subfunction: subfunction,
            randomDataHex: randomDataHex,
            payloadLength: payloadLength,
            errorCodeHex: errorCodeHex,
            responseType: responseType,
            crcCheckPassed: crcCheckPassed
        )
    }

    private func startRSSILoop() {
        rssiReadWorkItem?.cancel()
        rssiReadWorkItem = nil
        scheduleRSSIRead(after: 0.5)
    }

    private func scheduleRSSIRead(after delay: TimeInterval) {
        guard case .authenticated = state, let peripheral = discoveredPeripheral else { return }
        let work = DispatchWorkItem { [weak self, weak peripheral] in
            guard let self, let peripheral else { return }
            guard case .authenticated = self.state else { return }
            peripheral.readRSSI()
        }
        rssiReadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleBestCandidateConnectionIfNeeded() {
        guard allowsDebugScoreFallback else { return }
        guard candidateSelectionWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.connectBestCandidate()
        }
        candidateSelectionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    private func connectScannedPeripheral(_ peripheral: CBPeripheral, localName: String, rssi: Int, source: ConnectionSource, detail: String) {
        guard discoveredPeripheral == nil else { return }
        discoveredPeripheral = peripheral
        currentConnectionSource = source
        peripheral.delegate = self
        central.stopScan()
        candidateSelectionWorkItem?.cancel()
        candidateSelectionWorkItem = nil
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        scanSelfHealWorkItem?.cancel()
        scanSelfHealWorkItem = nil
        scanTotalTimeoutWorkItem?.cancel()
        scanTotalTimeoutWorkItem = nil

        if peripheral.state == .connected {
            isSystemConnectedSession = true
            state = .connecting
            onLog?("BLE", "scanned peripheral already connected (system), discover services: \(peripheral.name ?? localName)")
            peripheral.discoverServices(nil)
            return
        }

        // 系统未连接：仍发起 connect，但标记非系统连接；UI 侧显示扫描/寻找，不显示“已连接”
        isSystemConnectedSession = false
        state = .connecting
        onLog?("BLE", "connecting \(connectionSourceText) candidate name=\(localName) rssi=\(rssi) systemConnected=0 | \(detail)")
        scheduleConnectionTimeout(uuid: peripheral.identifier, source: connectionSourceText)
        central.connect(peripheral, options: nil)
    }

    private func connectBestCandidate() {
        candidateSelectionWorkItem = nil
        guard discoveredPeripheral == nil else { return }
        guard allowsDebugScoreFallback else { return }
        guard let peripheral = candidatePeripheral, candidateScore >= candidateMinimumScore else {
            onLog?("BLE", "debug score fallback has no connectable candidate score=\(candidateScore), keep official scan")
            candidatePeripheral = nil
            candidateName = "--"
            candidateRSSI = -127
            candidateScore = Int.min
            return
        }
        connectScannedPeripheral(
            peripheral,
            localName: candidateName,
            rssi: candidateRSSI,
            source: .debugScore,
            detail: "score=\(candidateScore) fallback=forceBLE manufacturerExact=0"
        )
    }

    private func discoveryScore(localName: String, advertisementData: [String: Any], rssi: Int) -> Int {
        var identityScore = 0
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(authService) { identityScore += 6 }
            if serviceUUIDs.contains(controlService) { identityScore += 6 }
        }
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 2,
           manufacturerData[0] == 0x55,
           manufacturerData[1] == 0x2B {
            identityScore += 8
        }
        let normalizedName = localName.lowercased().filter { $0.isLetter || $0.isNumber }
        let normalizedMac = (config?.bleMac ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        if normalizedMac.count >= 4 {
            let suffix4 = String(normalizedMac.suffix(4))
            if normalizedName.contains(suffix4) { identityScore += 12 }
        }
        if normalizedMac.count >= 6 {
            let suffix6 = String(normalizedMac.suffix(6))
            if normalizedName.contains(suffix6) { identityScore += 18 }
        }
        guard identityScore > 0 else { return Int.min / 2 }
        return identityScore + max(-10, min(10, (rssi + 90) / 4))
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private func crc16CcittFalse(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }
}

private extension FixedWidthInteger {
    var bigEndianBytes: [UInt8] {
        withUnsafeBytes(of: self.bigEndian) { Array($0) }
    }
}

private func makeRandomUInt32Hex() -> String {
    var value: UInt32 = 0
    let status = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &value)
    if status == errSecSuccess {
        return String(format: "%08X", UInt32(bigEndian: value))
    }
    return String(format: "%08X", UInt32.random(in: UInt32.min...UInt32.max))
}

private func parseUInt32(_ string: String) -> UInt32? {
    var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.lowercased().hasPrefix("0x") {
        cleaned.removeFirst(2)
    }
    if let value = UInt32(cleaned) {
        return value
    }
    return UInt32(cleaned, radix: 16)
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(character), count: length - count) + self
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    func readUInt16BE(at offset: Int) -> UInt16 {
        let range = offset..<(offset + 2)
        return self.subdata(in: range).reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        let range = offset..<(offset + 4)
        return self.subdata(in: range).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    func xor(with other: Data) -> Data {
        let count = Swift.min(self.count, other.count)
        var out = Data(capacity: count)
        for index in 0..<count {
            out.append(self[index] ^ other[index])
        }
        return out
    }

    func removingPKCS7PaddingIfPresent() -> Data {
        guard let last = self.last else { return self }
        let padding = Int(last)
        guard padding > 0, padding <= 16, padding <= count else { return self }
        let suffix = self.suffix(padding)
        guard suffix.allSatisfy({ $0 == last }) else { return self }
        return Data(self.dropLast(padding))
    }

    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

extension VehicleBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        let peripherals = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral]) ?? []
        onLog?("BLE", "central restore peripherals=\(peripherals.count) state=\(central.state.rawValue)")
        guard config != nil else { return }
        // 系统只恢复 peripheral 连接，不恢复可信鉴权会话。先清空随机数/控制密钥/特征/待处理命令，再重新发现服务并完整鉴权。
        clearSessionRuntime(cancelPendingControl: true)
        onLog?("BLE", "restore safety reset complete; full re-authentication required")
        // 恢复列表也可能含旁车：只接受当前 bleMac + keyId 作用域的 SoftLast UUID。
        let restoredCurrentVehicle = loadLastSuccessfulPeripheralUUID().flatMap { trustedID in
            peripherals.first(where: { $0.identifier == trustedID })
        }
        guard let peripheral = restoredCurrentVehicle else {
            onLog?("BLE", "restore has no verified current-vehicle UUID; resume strict MAC scan")
            if central.state == .poweredOn {
                startConnectionFlow()
            }
            return
        }
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        currentConnectionSource = .manufacturer
        switch peripheral.state {
        case .connected:
            isSystemConnectedSession = true
            publishCurrentVehicleNearbyDevice(peripheral, rssi: nil)
            state = .connecting
            onLog?("BLE", "restore verified current vehicle, discover services: \(peripheral.name ?? "--")")
            peripheral.discoverServices(nil)
        case .connecting:
            state = .connecting
            onLog?("BLE", "restore verified current vehicle connecting: \(peripheral.name ?? "--")")
        default:
            onLog?("BLE", "restore verified UUID not connected, resume strict MAC scan")
            discoveredPeripheral = nil
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "--"
        let rssi = RSSI.intValue
        let manufacturerHex = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexString ?? "--"
        let manufacturerMac = manufacturerLast6MacHex(from: advertisementData)
        let targetMac = normalizedBleMacHex(config?.bleMac ?? "")
        let serviceText = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []).map { $0.uuidString }.joined(separator: ",")
        let manufacturerExactMatched = manufacturerMac.flatMap { mac in targetMac.map { mac == $0 } } ?? false
        // 广播 manufacturer MAC 是本车身份的硬证据：仅本扫描周期记住 UUID，供稍后系统已连接管复查使用。
        if manufacturerExactMatched {
            currentVehicleBroadcastIDs.insert(peripheral.identifier)
        }

        if let manufacturerMac {
            onLog?("BLE", "manufacturer candidate name=\(localName) rssi=\(rssi) deviceMac=\(manufacturerMac) target=\(targetMac ?? "--") match=\(manufacturerExactMatched ? 1 : 0) mfg=\(manufacturerHex.prefix(24))")
        }

        let score = discoveryScore(localName: localName, advertisementData: advertisementData, rssi: rssi)
        if manufacturerMac != nil || score >= 4 {
            let key = peripheral.identifier.uuidString
            let now = Date()
            let minInterval: TimeInterval = manufacturerExactMatched ? 0.25 : 0.8
            let shouldReport = nearbyDeviceLastReportAt[key].map { now.timeIntervalSince($0) >= minInterval } ?? true
            if shouldReport {
                nearbyDeviceLastReportAt[key] = now
                onNearbyDeviceDiscovered?(
                    NearbyDevice(
                        id: key,
                        peripheralIdentifier: key,
                        name: localName,
                        rssi: rssi,
                        hasLiveRSSI: true,
                        manufacturerMac: manufacturerMac,
                        serviceText: serviceText.isEmpty ? "--" : serviceText,
                        score: score > (Int.min / 4) ? score : nil,
                        exactMatched: manufacturerExactMatched,
                        isSystemConnected: peripheral.state == .connected && manufacturerExactMatched,
                        lastSeenAt: now
                    )
                )
            }
        }

        guard discoveredPeripheral == nil else { return }
        if let manufacturerMac, let targetMac, manufacturerMac == targetMac {
            connectScannedPeripheral(
                peripheral,
                localName: localName,
                rssi: rssi,
                source: .manufacturer,
                detail: "manufacturerLast6=\(manufacturerMac) target=\(targetMac) services=\(serviceText.isEmpty ? "--" : serviceText)"
            )
            return
        }

        if score >= 4 {
            onLog?("BLE", "debug score candidate name=\(localName) rssi=\(rssi) score=\(score) services=\(serviceText.isEmpty ? "--" : serviceText) mfg=\(manufacturerHex.prefix(20)) exact=0")
        }
        guard allowsDebugScoreFallback, score >= candidateMinimumScore else { return }
        if candidatePeripheral == nil || score > candidateScore || (score == candidateScore && rssi > candidateRSSI) {
            candidatePeripheral = peripheral
            candidateName = localName
            candidateRSSI = rssi
            candidateScore = score
        }
        scheduleBestCandidateConnectionIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // 链路已建立（无论是否原先系统已连）
        isSystemConnectedSession = true
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        onLog?("BLE", "connected \(peripheral.name ?? "--") source=\(connectionSourceText), discover all services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let sourceText = connectionSourceText
        guard discoveredPeripheral?.identifier == peripheral.identifier else {
            onLog?("BLE", "stale connect failed ignored id=\(peripheral.identifier.uuidString.prefix(8)) | \(error?.localizedDescription ?? "unknown")")
            return
        }
        clearSessionRuntime(cancelPendingControl: true)
        onLog?("BLE", "connect failed source=\(sourceText) | \(error?.localizedDescription ?? "unknown")")
        guard config != nil, central.state == .poweredOn else {
            state = .error(error?.localizedDescription ?? "connect failed")
            return
        }
        // 连接失败：统一回宽扫（按钥匙 MAC 再找）
        state = .idle
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let sourceText = connectionSourceText
        guard discoveredPeripheral?.identifier == peripheral.identifier else {
            onLog?("BLE", "stale disconnect ignored id=\(peripheral.identifier.uuidString.prefix(8)) | \(error?.localizedDescription ?? "no error")")
            return
        }
        completePendingControl(.failure(.sessionStopped))
        clearSessionRuntime(cancelPendingControl: true)
        // 关键：先落 idle，清掉 authenticated。
        // 旧逻辑断连后不改 state 就 startConnectionFlow，authenticated 守卫直接 return，
        // UI 永久「已连接/已鉴权」且 RSSI 循环已停 → 无阈值、假已连接。
        state = .idle
        onLog?("BLE", "disconnected source=\(sourceText) | \(error?.localizedDescription ?? "no error")")
        if config != nil, central.state == .poweredOn {
            // 断连后重新走：系统已连接管 / 软直连 / 宽扫
            startConnectionFlow()
        }
    }
}

extension VehicleBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            onLog?("BLE", "discover services failed | \(error.localizedDescription)")
            return
        }
        var hasAuthService = false
        var hasControlService = false
        peripheral.services?.forEach { service in
            if service.uuid == authService {
                hasAuthService = true
                onLog?("BLE", "found service 181A Authorization")
                peripheral.discoverCharacteristics(nil, for: service)
            } else if service.uuid == controlService {
                hasControlService = true
                onLog?("BLE", "found service 182A Control")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        if !hasAuthService || !hasControlService {
            onLog?("BLE", "target services incomplete on \(peripheral.name ?? "--") auth=\(hasAuthService ? 1 : 0) control=\(hasControlService ? 1 : 0), disconnect and continue scanning")
            central.cancelPeripheralConnection(peripheral)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            onLog?("BLE", "discover characteristics failed | \(error.localizedDescription)")
            return
        }
        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == authWrite {
                authWriteCharacteristic = characteristic
                onLog?("BLE", "found 181A/2A6E ARequestCharacteristic")
                if notify181AReady { sendAuthFrameIfPossible() }
            }
            if characteristic.uuid == controlWrite {
                controlWriteCharacteristic = characteristic
                onLog?("BLE", "found 182A/2A7E CRequestCharacteristic")
            }
            if characteristic.uuid == authNotify || characteristic.uuid == controlNotify {
                if characteristic.uuid == authNotify {
                    onLog?("BLE", "found 181A/2A6F AResponseCharacteristic, enable notify")
                } else {
                    onLog?("BLE", "found 182A/2A7F CResponseCharacteristic, enable notify")
                }
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            onLog?("BLE", "set notify failed | \(error.localizedDescription)")
            return
        }
        if characteristic.uuid == authNotify, characteristic.isNotifying {
            notify181AReady = true
        }
        if characteristic.uuid == controlNotify, characteristic.isNotifying {
            notify182AReady = true
        }
        finishIfReady()
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error {
            onLog?("BLE", "read RSSI failed | \(error.localizedDescription)")
            scheduleRSSIRead(after: 1.0)
            return
        }
        let value = RSSI.intValue
        onLog?("BLE", "rssi=\(value)")
        // 鉴权后的 readRSSI 是当前车真实信号；只同步已验证当前车，避免旁车污染附近列表。
        if isVerifiedCurrentVehicle(peripheral) {
            publishCurrentVehicleNearbyDevice(peripheral, rssi: value)
        }
        onRSSIUpdate?(value)
        scheduleRSSIRead(after: 1.0)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            let controlError = BLEControlError.writeFailed(error.localizedDescription)
            lastControlError = controlError
            state = .error(error.localizedDescription)
            onLog?("BLE", "write value failed uuid=\(characteristic.uuid.uuidString) | \(error.localizedDescription)")
            if characteristic.uuid == controlWrite {
                completePendingControl(.failure(controlError))
            }
            return
        }
        if characteristic.uuid == controlWrite {
            onLog?("BLE", "control write ok uuid=\(characteristic.uuid.uuidString), waiting 2A7F")
        } else {
            onLog?("BLE", "write ok uuid=\(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            onLog?("BLE", "notify update failed | \(error.localizedDescription)")
            return
        }
        let data = characteristic.value ?? Data()
        let hex = data.map { String(format: "%02X", $0) }.joined()
        let hexPreview = String(hex.prefix(64))
        onLog?("BLE", "notify uuid=\(characteristic.uuid.uuidString) len=\(data.count) hex=\(hexPreview)")
        if characteristic.uuid == authNotify {
            handleAuthNotification(data)
        } else if characteristic.uuid == controlNotify {
            handleControlNotification(data)
        }
    }
}
