import Foundation
import CoreBluetooth
import CommonCrypto

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
            if let crcCheckPassed, crcCheckPassed == false { return false }
            if let responseErrorCodeHex { return responseErrorCodeHex == "00000000" }
            return responseType == 1
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
        case scan
    }

    var onStateChange: ((State) -> Void)?
    var onLog: ((String, String?) -> Void)?
    var onControlReceipt: ((BLEControlReceipt) -> Void)?
    var onRSSIUpdate: ((Int) -> Void)?

    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private var config: SessionConfig?
    private var discoveredPeripheral: CBPeripheral?
    private var authWriteCharacteristic: CBCharacteristic?
    private var controlWriteCharacteristic: CBCharacteristic?
    private var notify181AReady = false
    private var notify182AReady = false
    private var hasStartedCentral = false
    private var didSendAuthFrame = false
    private var pendingControl: E300PendingControl?
    private var pendingControlCompletion: ((Result<Void, BLEControlError>) -> Void)?
    private var pendingControlTimeoutWorkItem: DispatchWorkItem?
    private var rssiReadWorkItem: DispatchWorkItem?
    private var candidatePeripheral: CBPeripheral?
    private var candidateName: String = "--"
    private var candidateRSSI: Int = -127
    private var candidateScore: Int = Int.min
    private var candidateSelectionWorkItem: DispatchWorkItem?
    private var scanWatchdogWorkItem: DispatchWorkItem?
    private var currentConnectionSource: ConnectionSource?
    private var hasTriedBoundPeripheral = false
    private let candidateMinimumScore = 8
    private(set) var state: State = .idle {
        didSet {
            guard oldValue != state else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onStateChange?(self.state)
            }
        }
    }
    private(set) var lastControlError: BLEControlError?

    var canSendVehicleControl: Bool {
        if case .authenticated = state {
            return controlWriteCharacteristic != nil
        }
        return false
    }

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
        if self.config == config {
            switch state {
            case .scanning, .connecting, .connected, .authenticating, .authenticated:
                return
            case .idle, .unsupported, .bluetoothOff, .authFailed, .error:
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
        self.config = config
        lastControlError = nil
        clearSessionRuntime(cancelPendingControl: configChanged)
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
        rssiReadWorkItem?.cancel()
        rssiReadWorkItem = nil
        candidatePeripheral = nil
        candidateName = "--"
        candidateRSSI = -127
        candidateScore = Int.min
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
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
        if !hasTriedBoundPeripheral, connectBoundPeripheralIfAvailable() {
            return
        }
        startScanning()
    }

    private func connectBoundPeripheralIfAvailable() -> Bool {
        hasTriedBoundPeripheral = true
        guard let binding = VehicleBLEBindingStore.load(),
              let uuid = UUID(uuidString: binding.peripheralIdentifier) else {
            onLog?("BLE", "bound peripheral miss, fallback wide scan")
            return false
        }
        let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = peripherals.first else {
            onLog?("BLE", "bound peripheral not found id=\(binding.shortIdentifier), fallback wide scan")
            return false
        }
        discoveredPeripheral = peripheral
        currentConnectionSource = .bound
        peripheral.delegate = self
        central.stopScan()
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        state = .connecting
        onLog?("BLE", "connecting bound peripheral name=\(binding.peripheralName) id=\(binding.shortIdentifier) keyId=\(binding.keyId) macSuffix=\(binding.bleMacSuffix)")
        central.connect(peripheral, options: nil)
        return true
    }

    private func startScanning() {
        guard config != nil else {
            state = .idle
            return
        }
        guard discoveredPeripheral == nil else { return }
        candidateSelectionWorkItem?.cancel()
        candidateSelectionWorkItem = nil
        candidatePeripheral = nil
        candidateName = "--"
        candidateRSSI = -127
        candidateScore = Int.min
        central.stopScan()
        state = .scanning
        let targetSuffix = normalizedMacSuffixText(config?.bleMac ?? "")
        onLog?("BLE", "wide scanning target=\(targetSuffix) minScore=\(candidateMinimumScore)")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scheduleScanWatchdog()
    }

    private func scheduleScanWatchdog() {
        scanWatchdogWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard case .scanning = self.state else { return }
            self.onLog?("BLE", "wide scan still running no candidate target=\(self.normalizedMacSuffixText(self.config?.bleMac ?? "")) minScore=\(self.candidateMinimumScore)")
            self.scheduleScanWatchdog()
        }
        scanWatchdogWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)

    private func finishIfReady() {
        guard notify181AReady, notify182AReady else { return }
        state = .connected
        onLog?("BLE", "notify ready 2A6F + 2A7F")
        sendAuthFrameIfPossible()
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
        state = .authenticating
        onLog?("BLE", "send auth frame len=\(frame.count) keyId=\(config.keyId)")
        peripheral.writeValue(frame, for: authWriteCharacteristic, type: .withResponse)
    }

    private func makeAuthFrame(config: SessionConfig) -> Data? {
        guard let keyId = parseUInt32(config.keyId),
              let nonce = Data(hex: config.keyMasterRandom), nonce.count == 16,
              let aesKey = Data(hex: config.masterKey), aesKey.count == 16 else {
            onLog?("BLE", "auth config invalid")
            return nil
        }

        let timestamp = UInt32(Date().timeIntervalSince1970)
        var plain = Data()
        plain.append(contentsOf: keyId.bigEndianBytes)
        plain.append(contentsOf: timestamp.bigEndianBytes)
        plain.append(nonce)
        let crc = crc32(plain).bigEndian
        plain.append(contentsOf: crc.bigEndianBytes)

        guard let encrypted = aesECBEncrypt(plain, key: aesKey) else {
            onLog?("BLE", "auth aes encrypt failed")
            return nil
        }
        return wrapBLEFrame(encrypted)
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
        let now = UInt32(Date().timeIntervalSince1970)
        let randomDataHex = String(format: "%08X", now)
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
        if let controlKeyHex = config.controlAes128Key?.trimmingCharacters(in: .whitespacesAndNewlines),
           !controlKeyHex.isEmpty,
           let key = Data(hex: controlKeyHex), key.count == 16 {
            return (key, "controlAes128Key")
        }
        guard let masterKey = Data(hex: config.masterKey), masterKey.count == 16,
              let random = Data(hex: config.keyMasterRandom), random.count == 16 else {
            return nil
        }
        return (masterKey.xor(with: random), "masterKey XOR keyMasterRandom")
    }

    private func e300BleKeyHex(config: SessionConfig) -> String? {
        if let bleKey = config.bleKey?.trimmingCharacters(in: .whitespacesAndNewlines), !bleKey.isEmpty {
            let raw = bleKey
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: "-", with: "")
                .uppercased()
            guard raw.allSatisfy({ UInt8(String($0), radix: 16) != nil }) else { return nil }
            return String(raw.suffix(8)).leftPadded(to: 8, with: "0")
        }
        guard let value = parseUInt32(config.keyId) else { return nil }
        return String(format: "%08X", value)
    }

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
            onLog?("BLE", detail)
            if currentConnectionSource == .bound {
                onLog?("BLE", "bound auth failed, fallback wide scan | \(reason)")
                fallbackToWideScanAfterBoundFailure()
            }
        }

        guard let config,
              let aesKey = Data(hex: config.masterKey), aesKey.count == 16,
              let nonce = Data(hex: config.keyMasterRandom), nonce.count == 16,
              let expectedKeyId = parseUInt32(config.keyId) else {
            failAuth("鉴权配置无效", detail: "auth response skipped: invalid config")
            return
        }
        guard let encrypted = extractEncryptedPayload(from: data),
              let plain = aesECBDecrypt(encrypted, key: aesKey),
              plain.count >= 28 else {
            failAuth("鉴权响应解密失败", detail: "auth response decrypt failed")
            return
        }
        let keyId = plain.readUInt32BE(at: 0)
        let echoedNonce = plain.subdata(in: 8..<24)
        let crc = plain.readUInt32BE(at: 24)
        let payload = Data(plain.prefix(24))
        let calculatedCRC = crc32(payload)
        guard keyId == expectedKeyId else {
            failAuth("keyId 不匹配", detail: "auth failed keyId expected=\(expectedKeyId) got=\(keyId)")
            return
        }
        guard echoedNonce == nonce else {
            failAuth("nonce 不匹配", detail: "auth failed nonce mismatch")
            return
        }
        guard crc == calculatedCRC else {
            failAuth("CRC32 不匹配", detail: "auth failed crc expected=\(String(format: "%08X", calculatedCRC)) got=\(String(format: "%08X", crc))")
            return
        }
        state = .authenticated
        onLog?("BLE", "auth success keyId=\(keyId) source=\(currentConnectionSource == .bound ? "bound" : "scan")")
        persistBindingAfterAuthSuccess(config: config, keyId: keyId)
        startRSSILoop()
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

    private func extractEncryptedPayload(from frame: Data) -> Data? {
        guard frame.count >= 38 else { return nil }
        if frame.first == 0xAA {
            let length = Int(UInt16(frame[1]) << 8 | UInt16(frame[2]))
            let start = 3
            let end = start + length
            guard end <= frame.count else { return nil }
            return frame.subdata(in: start..<end)
        }
        return frame
    }

    private func handleControlNotification(_ data: Data) {
        let rawHex = data.hexString
        let plain = decryptControlNotificationData(data)
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
            decryptedHex: plain?.hexString,
            receivedAt: Date()
        )
        let context = pending.map { "pending=\($0.command.title) serviceId=\(String(format: "%04X", $0.serviceId)) sub=\(String(format: "%04X", $0.subfunction))" } ?? "no pending control context"
        onLog?("BLE", "E300 control notify received | \(context) | \(receipt.displayDetail)")
        onControlReceipt?(receipt)
        if receipt.isSuccess {
            completePendingControl(.success(()))
        } else {
            completePendingControl(.failure(.controlRejected(receipt.displayDetail)))
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
            return E300ControlResponse(serviceId: nil, subfunction: nil, randomDataHex: nil, payloadLength: nil, errorCodeHex: nil, responseType: nil, crcCheckPassed: nil)
        }
        let serviceId = data.count >= 2 ? data.readUInt16BE(at: 0) : nil
        let subfunction = data.count >= 4 ? data.readUInt16BE(at: 2) : nil
        let randomDataHex = data.count >= 8 ? data.subdata(in: 4..<8).hexString : nil
        let payloadLength = data.count >= 9 ? data[8] : nil
        let errorCodeHex = data.count >= 13 ? data.subdata(in: 9..<13).hexString : nil
        let responseType: UInt8? = errorCodeHex == "00000000" ? 1 : 0
        let crcCheckPassed = data.count >= 2 ? (crc16CcittFalse(data) == 0) : nil
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
        guard candidateSelectionWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.connectBestCandidate()
        }
        candidateSelectionWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func connectBestCandidate() {
        candidateSelectionWorkItem = nil
        guard discoveredPeripheral == nil else { return }
        guard let peripheral = candidatePeripheral, candidateScore >= candidateMinimumScore else {
            onLog?("BLE", "no connectable candidate score=\(candidateScore), keep wide scanning")
            candidatePeripheral = nil
            candidateName = "--"
            candidateRSSI = -127
            candidateScore = Int.min
            return
        }
        discoveredPeripheral = peripheral
        currentConnectionSource = .scan
        peripheral.delegate = self
        central.stopScan()
        scanWatchdogWorkItem?.cancel()
        scanWatchdogWorkItem = nil
        state = .connecting
        onLog?("BLE", "connecting scanned candidate \(candidateName) rssi=\(candidateRSSI) score=\(candidateScore)")
        central.connect(peripheral, options: nil)
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

private func parseUInt32(_ string: String) -> UInt32? {
    let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "--"
        let rssi = RSSI.intValue
        let score = discoveryScore(localName: localName, advertisementData: advertisementData, rssi: rssi)
        let manufacturerHex = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexString ?? "--"
        let serviceText = ((advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []).map { $0.uuidString }.joined(separator: ",")
        if score >= 4 {
            onLog?("BLE", "candidate name=\(localName) rssi=\(rssi) score=\(score) services=\(serviceText.isEmpty ? "--" : serviceText) mfg=\(manufacturerHex.prefix(20))")
        }
        guard discoveredPeripheral == nil, score >= candidateMinimumScore else { return }
        if candidatePeripheral == nil || score > candidateScore || (score == candidateScore && rssi > candidateRSSI) {
            candidatePeripheral = peripheral
            candidateName = localName
            candidateRSSI = rssi
            candidateScore = score
        }
        scheduleBestCandidateConnectionIfNeeded()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onLog?("BLE", "connected \(peripheral.name ?? "--")")
        peripheral.discoverServices([authService, controlService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        let sourceText = currentConnectionSource == .bound ? "bound" : "scan"
        currentConnectionSource = nil
        state = .error(error?.localizedDescription ?? "connect failed")
        onLog?("BLE", "connect failed source=\(sourceText) | \(error?.localizedDescription ?? "unknown")")
        if config != nil, central.state == .poweredOn {
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        let sourceText = currentConnectionSource == .bound ? "bound" : "scan"
        currentConnectionSource = nil
        notify181AReady = false
        notify182AReady = false
        completePendingControl(.failure(.sessionStopped))
        onLog?("BLE", "disconnected source=\(sourceText) | \(error?.localizedDescription ?? "no error")")
        if config != nil, central.state == .poweredOn {
            startScanning()
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
                peripheral.discoverCharacteristics([authWrite, authNotify], for: service)
            } else if service.uuid == controlService {
                hasControlService = true
                peripheral.discoverCharacteristics([controlWrite, controlNotify], for: service)
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
            }
            if characteristic.uuid == controlWrite {
                controlWriteCharacteristic = characteristic
            }
            if characteristic.uuid == authNotify || characteristic.uuid == controlNotify {
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
        onLog?("BLE", "notify uuid=\(characteristic.uuid.uuidString) len=\(data.count) hex=\(hex)")
        if characteristic.uuid == authNotify {
            handleAuthNotification(data)
        } else if characteristic.uuid == controlNotify {
            handleControlNotification(data)
        }
    }
}
