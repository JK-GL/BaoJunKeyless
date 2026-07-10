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
            case .notAuthenticated: return "BLE 未鉴权成功"
            case .writeCharacteristicMissing: return "BLE 控制写特征不存在"
            case .invalidConfig: return "BLE 控制配置无效"
            case .frameBuildFailed: return "BLE 控制帧构造失败"
            case .writeFailed(let detail): return "BLE 控制写入失败：\(detail)"
            case .receiptTimeout: return "BLE 控制回包超时"
            case .controlRejected(let detail): return "BLE 控制失败：\(detail)"
            case .sessionStopped: return "BLE 会话已停止"
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
        let manufacturerMac: String?
        let serviceText: String
        let score: Int?
        let exactMatched: Bool
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
            case .powerOnReady: return "BLE上电/启动授权"
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
    private var nearbyDeviceLastReportAt: [String: Date] = [:]
    private var candidateSelectionWorkItem: DispatchWorkItem?
    private var scanWatchdogWorkItem: DispatchWorkItem?
    private var scanTotalTimeoutWorkItem: DispatchWorkItem?
    private var scanRetryWorkItem: DispatchWorkItem?
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private var foregroundObserver: NSObjectProtocol?
    private var currentConnectionSource: ConnectionSource?
    private var hasTriedBoundPeripheral = false
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
                return
            case .idle, .unsupported, .bluetoothOff, .authFailed, .error:
                // 允许从 idle/error 重启
                break
            }
        }

        let configChanged = self.config != config
        if configChanged {
            central.stopScan()
            if let discoveredPeripheral {
                central.cancelPeripheralConnection(discoveredPeripheral)
            }
            completePendingControl(.failure(.sessionStopped))
            hasTriedBoundPeripheral = false
        }

        // 从 stop() 后重启：config 从 nil 变成非 nil，必须清运行时
        let restartingFromStopped = self.config == nil
        self.config = config
        lastControlError = nil
        clearSessionRuntime(cancelPendingControl: configChanged || restartingFromStopped)

        // 重启时允许重新尝试 bound peripheral
        if restartingFromStopped {
            hasTriedBoundPeripheral = false
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

    func stop() {
        config = nil
        central.stopScan()
        candidateSelectionWorkItem?.cancel()
        candidateSelectionWorkItem = nil
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
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
        hasTriedBoundPeripheral = false
        if let discoveredPeripheral {
            central.cancelPeripheralConnection(discoveredPeripheral)
        }
        completePendingControl(.failure(.sessionStopped))
        clearSessionRuntime(cancelPendingControl: true)
        state = .idle
    }

    private func clearSessionRuntime(cancelPendingControl: Bool) {
        discoveredPeripheral = nil
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
        nearbyDeviceLastReportAt.removeAll()
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
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
        guard discoveredPeripheral == nil else { return }
        // 一账号一车：始终优先尝试绑定外设，失败后再宽扫认车
        if !hasTriedBoundPeripheral, connectBoundPeripheralIfAvailable() {
            return
        }
        startScanning()
    }

    private var allowsDebugScoreFallback: Bool {
        AppDiagnosticsSettings.vehicleControlRouteMode == .forceBLE
    }

    private var connectionSourceText: String {
        switch currentConnectionSource {
        case .bound: return "bound"
        case .manufacturer: return "manufacturer"
        case .debugScore: return "debugScore"
        case nil: return "none"
        }
    }

    private func connectBoundPeripheralIfAvailable() -> Bool {
        hasTriedBoundPeripheral = true
        guard let config else {
            onLog?("BLE", "bound peripheral miss, fallback wide scan")
            return false
        }
        guard let binding = VehicleBLEBindingStore.loadMatching(keyId: config.keyId, bleMac: config.bleMac),
              let uuid = UUID(uuidString: binding.peripheralIdentifier) else {
            onLog?("BLE", "bound peripheral miss/mismatch, fallback wide scan")
            return false
        }
        let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else {
            // 系统已找不到该 UUID：清脏缓存后宽扫，避免每轮空等
            VehicleBLEBindingStore.clear()
            onLog?("BLE", "bound peripheral not found id=\(binding.shortIdentifier), cleared binding, fallback wide scan")
            return false
        }
        discoveredPeripheral = peripheral
        currentConnectionSource = .bound
        peripheral.delegate = self
        central.stopScan()
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        scanTotalTimeoutWorkItem?.cancel()
        scanTotalTimeoutWorkItem = nil

        if peripheral.state == .connected {
            state = .connecting
            onLog?("BLE", "connecting bound peripheral name=\(binding.peripheralName) id=\(binding.shortIdentifier) keyId=\(binding.keyId) macSuffix=\(binding.bleMacSuffix) alreadyConnected=1")
            peripheral.discoverServices(nil)
            return true
        }

        state = .connecting
        onLog?("BLE", "connecting bound peripheral name=\(binding.peripheralName) id=\(binding.shortIdentifier) keyId=\(binding.keyId) macSuffix=\(binding.bleMacSuffix)")
        scheduleConnectionTimeout(uuid: peripheral.identifier, source: "bound")
        central.connect(peripheral, options: nil)
        return true
    }

    private func startScanning() {
        guard config != nil else {
            state = .idle
            return
        }
        if case .scanning = state { return }
        guard discoveredPeripheral == nil else { return }
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
        onLog?("BLE", "official scan manufacturerLast6 target=\(targetMac) debugFallback=\(allowsDebugScoreFallback ? 1 : 0) minScore=\(candidateMinimumScore)")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scheduleScanWatchdog()
        scheduleScanTotalTimeout()
    }

    private func scheduleScanWatchdog() {
        scanWatchdogWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard case .scanning = self.state else { return }
            let targetMac = self.normalizedBleMacHex(self.config?.bleMac ?? "") ?? "--"
            self.onLog?("BLE", "official manufacturer scan still running target=\(targetMac) debugFallback=\(self.allowsDebugScoreFallback ? 1 : 0) bestScore=\(self.candidateScore)")
            self.scheduleScanWatchdog()
        }
        scanWatchdogWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
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
        let interval = max(0, scanRetryInterval)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.config != nil else { return }
            guard case .idle = self.state else { return }
            // 每一轮重试都重新优先绑定车，失败后再宽扫
            self.hasTriedBoundPeripheral = false
            self.startConnectionFlow()
        }
        scanRetryWorkItem = work
        if interval <= 0 {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        }
    }

    private func scheduleConnectionTimeout(uuid: UUID, source: String) {
        connectionTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let peripheral = self.discoveredPeripheral,
                  peripheral.identifier == uuid else { return }
            guard case .connecting = self.state else { return }
            self.onLog?("BLE", "connection timeout (10s) source=\(source), disconnecting")
            self.central.cancelPeripheralConnection(peripheral)
            self.discoveredPeripheral = nil
            self.currentConnectionSource = nil
            if source == "bound" {
                self.onLog?("BLE", "bound connect timeout, fallback wide scan")
                self.fallbackToWideScanAfterBoundFailure()
            } else {
                self.state = .idle
            }
        }
        connectionTimeoutWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
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
            if currentConnectionSource == .bound {
                VehicleBLEBindingStore.clear()
                onLog?("BLE", "bound auth failed, clear binding, fallback wide scan | \(reason)")
                fallbackToWideScanAfterBoundFailure()
            }
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
            if let keyId = parseUInt32(config.keyId) {
                persistBindingAfterAuthSuccess(config: config, keyId: keyId)
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

    private func persistBindingAfterAuthSuccess(config: SessionConfig, keyId: UInt32) {
        guard let peripheral = discoveredPeripheral else { return }
        let binding = VehicleBLEBinding(
            peripheralIdentifier: peripheral.identifier.uuidString,
            peripheralName: peripheral.name ?? "--",
            keyId: String(format: "%08X", keyId),
            bleMacSuffix: normalizedMacSuffixText(config.bleMac),
            boundAt: VehicleBLEBindingStore.load()?.boundAt ?? Date(),
            lastAuthAt: Date()
        )
        VehicleBLEBindingStore.save(binding)
        onLog?("BLE", "bound peripheral saved \(binding.displaySummary)")
    }

    private func normalizedMacSuffixText(_ mac: String) -> String {
        let normalized = mac.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.isEmpty else { return "--" }
        return String(normalized.suffix(6))
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

        let responseMatchesRequest =
            parsed.serviceId == 0xA956 &&
            parsed.subfunction == 0x0001 &&
            parsed.randomDataHex?.uppercased() == pending.randomDataHex.uppercased()

        let crcOK = parsed.crcCheckPassed != false
        let errorOK = parsed.errorCodeHex == "00000000"

        if responseMatchesRequest && crcOK && errorOK {
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

        // A956/0001 官方实车规格：
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
        scanTotalTimeoutWorkItem?.cancel()
        scanTotalTimeoutWorkItem = nil

        if peripheral.state == .connected {
            state = .connecting
            onLog?("BLE", "scanned peripheral already connected, discover services: \(peripheral.name ?? localName)")
            peripheral.discoverServices(nil)
            return
        }

        state = .connecting
        onLog?("BLE", "connecting \(connectionSourceText) candidate name=\(localName) rssi=\(rssi) | \(detail)")
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
        if let peripheral = peripherals.first {
            discoveredPeripheral = peripheral
            peripheral.delegate = self
            currentConnectionSource = .bound
            switch peripheral.state {
            case .connected:
                state = .connecting
                onLog?("BLE", "restore connected peripheral, discover services: \(peripheral.name ?? "--")")
                peripheral.discoverServices(nil)
            case .connecting:
                state = .connecting
                onLog?("BLE", "restore connecting peripheral: \(peripheral.name ?? "--")")
            default:
                onLog?("BLE", "restore peripheral idle, resume scan")
                startScanning()
            }
        } else if central.state == .poweredOn {
            handleCentralState()
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
                        manufacturerMac: manufacturerMac,
                        serviceText: serviceText.isEmpty ? "--" : serviceText,
                        score: score > (Int.min / 4) ? score : nil,
                        exactMatched: manufacturerExactMatched,
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
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil
        onLog?("BLE", "connected \(peripheral.name ?? "--") source=\(connectionSourceText), discover all services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let sourceText = connectionSourceText
        let wasBound = currentConnectionSource == .bound
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
        if wasBound {
            // 绑定直连失败：保留绑定记录，本轮回退宽扫；下一轮重试仍会优先绑定
            onLog?("BLE", "bound connect failed, fallback wide scan")
            fallbackToWideScanAfterBoundFailure()
        } else {
            state = .error(error?.localizedDescription ?? "connect failed")
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let sourceText = connectionSourceText
        guard discoveredPeripheral?.identifier == peripheral.identifier else {
            onLog?("BLE", "stale disconnect ignored id=\(peripheral.identifier.uuidString.prefix(8)) | \(error?.localizedDescription ?? "no error")")
            return
        }
        completePendingControl(.failure(.sessionStopped))
        clearSessionRuntime(cancelPendingControl: true)
        onLog?("BLE", "disconnected source=\(sourceText) | \(error?.localizedDescription ?? "no error")")
        if config != nil, central.state == .poweredOn {
            // 断开后重新走：有绑定先连绑定设备，再鉴权；失败再宽扫
            hasTriedBoundPeripheral = false
            startConnectionFlow()
        } else {
            state = .idle
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
