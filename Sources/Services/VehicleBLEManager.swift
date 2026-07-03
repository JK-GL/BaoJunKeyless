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
        case sessionStopped

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "BLE 未鉴权成功"
            case .writeCharacteristicMissing: return "BLE 控制写特征不存在"
            case .invalidConfig: return "BLE 控制配置无效"
            case .frameBuildFailed: return "BLE 控制帧构造失败"
            case .writeFailed(let detail): return "BLE 控制写入失败：\(detail)"
            case .receiptTimeout: return "BLE 控制回包超时"
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
        let sentStatus: UInt8?
        let sentBtParam: UInt8?
        let responseServiceId: UInt16?
        let responseStatus: UInt8?
        let responseBtParam: UInt8?
        let resultCode: UInt8?
        let elapsedMillis: Int?
        let rawHex: String
        let decryptedHex: String?
        let receivedAt: Date

        var displayDetail: String {
            var parts: [String] = []
            parts.append("sent=\(sentStatus.map(String.init) ?? "--")/\(sentBtParam.map(String.init) ?? "--")")
            if let responseServiceId { parts.append("serviceId=\(responseServiceId)") }
            if let responseStatus { parts.append("respStatus=\(responseStatus)") }
            if let responseBtParam { parts.append("respBtParam=\(responseBtParam)") }
            if let resultCode { parts.append("code=\(resultCode)") }
            if let elapsedMillis { parts.append("2A7E→2A7F=\(elapsedMillis)ms") }
            parts.append("rawLen=\(rawHex.count / 2)")
            if let decryptedHex { parts.append("decrypted=\(decryptedHex.prefix(32))") }
            return parts.joined(separator: ", ")
        }
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
    private var pendingDoorLockStatus: UInt8?
    private var pendingDoorLockBtParam: UInt8?
    private var pendingDoorLockSentAt: Date?
    private var pendingDoorLockCompletion: ((Result<Void, BLEControlError>) -> Void)?
    private var pendingControlTimeoutWorkItem: DispatchWorkItem?
    private var rssiReadWorkItem: DispatchWorkItem?
    private var candidatePeripheral: CBPeripheral?
    private var candidateName: String = "--"
    private var candidateRSSI: Int = -127
    private var candidateScore: Int = Int.min
    private var candidateSelectionWorkItem: DispatchWorkItem?
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

    var canSendDoorLockControl: Bool {
        if case .authenticated = state {
            return controlWriteCharacteristic != nil
        }
        return false
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
            completePendingDoorLock(.failure(.sessionStopped))
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
        if let discoveredPeripheral {
            central.cancelPeripheralConnection(discoveredPeripheral)
        }
        completePendingDoorLock(.failure(.sessionStopped))
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
        if cancelPendingControl {
            pendingControlTimeoutWorkItem?.cancel()
            pendingControlTimeoutWorkItem = nil
            pendingDoorLockStatus = nil
            pendingDoorLockBtParam = nil
            pendingDoorLockSentAt = nil
            pendingDoorLockCompletion = nil
        }
    }

    private func handleCentralState() {
        switch central.state {
        case .poweredOn:
            startScanning()
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
        onLog?("BLE", "scanning services 181A/182A target=\(config?.bleMac ?? "--")")
        central.scanForPeripherals(withServices: [authService, controlService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func finishIfReady() {
        guard notify181AReady, notify182AReady else { return }
        state = .connected
        onLog?("BLE", "notify ready 2A6F + 2A7F")
        sendAuthFrameIfPossible()
    }

    func sendDoorLockCommand(lock: Bool, completion: @escaping (Result<Void, BLEControlError>) -> Void) {
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
        guard let frame = makeDoorLockControlFrame(config: config, lock: lock) else {
            lastControlError = .frameBuildFailed
            completion(.failure(.frameBuildFailed))
            return
        }
        lastControlError = nil
        let statusValue: UInt8 = lock ? 1 : 0
        let btParam: UInt8 = lock ? 0 : 1
        pendingControlTimeoutWorkItem?.cancel()
        pendingDoorLockCompletion = completion
        pendingDoorLockStatus = statusValue
        pendingDoorLockBtParam = btParam
        pendingDoorLockSentAt = Date()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pendingDoorLockCompletion != nil else { return }
            self.onLog?("BLE", "doorLock control receipt timeout status=\(statusValue) btParam=\(btParam)")
            self.completePendingDoorLock(.failure(.receiptTimeout))
        }
        pendingControlTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: timeout)
        onLog?("BLE", "send doorLock control status=\(statusValue) btParam=\(btParam) len=\(frame.count) bleType=\(config.bleType ?? "--") bleKey=\(config.bleKey ?? "--")")
        peripheral.writeValue(frame, for: controlWriteCharacteristic, type: .withResponse)
    }

    private func completePendingDoorLock(_ result: Result<Void, BLEControlError>) {
        pendingControlTimeoutWorkItem?.cancel()
        pendingControlTimeoutWorkItem = nil
        let completion = pendingDoorLockCompletion
        pendingDoorLockCompletion = nil
        pendingDoorLockStatus = nil
        pendingDoorLockBtParam = nil
        pendingDoorLockSentAt = nil
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

    private func makeDoorLockControlFrame(config: SessionConfig, lock: Bool) -> Data? {
        let controlKeyHex = config.controlAes128Key?.isEmpty == false ? config.controlAes128Key! : config.masterKey
        guard let controlKey = Data(hex: controlKeyHex), controlKey.count == 16 else {
            onLog?("BLE", "control key invalid")
            return nil
        }
        let serviceId: UInt16 = 1
        let statusValue: UInt8 = lock ? 1 : 0
        let btParam: UInt8 = lock ? 0 : 1
        var controlData = Data()
        controlData.append(contentsOf: serviceId.bigEndianBytes)
        controlData.append(statusValue)
        controlData.append(btParam)
        onLog?("BLE", "doorLock payload serviceId=1 status=\(statusValue) btParam=\(btParam) keySource=\(config.controlAes128Key?.isEmpty == false ? "controlAes128Key" : "masterKey")")
        guard let encrypted = aesECBEncrypt(controlData, key: controlKey) else {
            onLog?("BLE", "control aes encrypt failed")
            return nil
        }
        return wrapBLEFrame(encrypted)
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
        cryptECB(input: plain, key: key, operation: CCOperation(kCCEncrypt), outputLength: ((plain.count / kCCBlockSizeAES128) + 1) * kCCBlockSizeAES128)
    }

    private func aesECBDecrypt(_ encrypted: Data, key: Data) -> Data? {
        cryptECB(input: encrypted, key: key, operation: CCOperation(kCCDecrypt), outputLength: encrypted.count)
    }

    private func cryptECB(input: Data, key: Data, operation: CCOperation, outputLength: Int) -> Data? {
        var out = Data(count: outputLength)
        let outCount = out.count
        var outLength: size_t = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
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
        guard let config,
              let aesKey = Data(hex: config.masterKey), aesKey.count == 16,
              let nonce = Data(hex: config.keyMasterRandom), nonce.count == 16,
              let expectedKeyId = parseUInt32(config.keyId) else {
            state = .authFailed("鉴权配置无效")
            onLog?("BLE", "auth response skipped: invalid config")
            return
        }
        guard let encrypted = extractEncryptedPayload(from: data),
              let plain = aesECBDecrypt(encrypted, key: aesKey),
              plain.count >= 28 else {
            state = .authFailed("鉴权响应解密失败")
            onLog?("BLE", "auth response decrypt failed")
            return
        }
        let keyId = plain.readUInt32BE(at: 0)
        let echoedNonce = plain.subdata(in: 8..<24)
        let crc = plain.readUInt32BE(at: 24)
        let payload = Data(plain.prefix(24))
        let calculatedCRC = crc32(payload)
        guard keyId == expectedKeyId else {
            state = .authFailed("keyId 不匹配")
            onLog?("BLE", "auth failed keyId expected=\(expectedKeyId) got=\(keyId)")
            return
        }
        guard echoedNonce == nonce else {
            state = .authFailed("nonce 不匹配")
            onLog?("BLE", "auth failed nonce mismatch")
            return
        }
        guard crc == calculatedCRC else {
            state = .authFailed("CRC32 不匹配")
            onLog?("BLE", "auth failed crc expected=\(String(format: "%08X", calculatedCRC)) got=\(String(format: "%08X", crc))")
            return
        }
        state = .authenticated
        onLog?("BLE", "auth success keyId=\(keyId)")
        startRSSILoop()
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
        let parsed = parseControlResponse(plain)
        let receipt = BLEControlReceipt(
            sentStatus: pendingDoorLockStatus,
            sentBtParam: pendingDoorLockBtParam,
            responseServiceId: parsed.serviceId,
            responseStatus: parsed.status,
            responseBtParam: parsed.btParam,
            resultCode: parsed.resultCode,
            elapsedMillis: pendingDoorLockSentAt.map { Int(Date().timeIntervalSince($0) * 1000) },
            rawHex: rawHex,
            decryptedHex: plain?.hexString,
            receivedAt: Date()
        )
        let context: String
        if let status = pendingDoorLockStatus, let btParam = pendingDoorLockBtParam {
            context = "pendingDoorLock status=\(status) btParam=\(btParam)"
        } else {
            context = "no pending control context"
        }
        onLog?("BLE", "control notify received | \(context) | \(receipt.displayDetail)")
        onControlReceipt?(receipt)
        completePendingDoorLock(.success(()))
    }

    private func decryptControlNotificationData(_ data: Data) -> Data? {
        guard let config else { return nil }
        let controlKeyHex = config.controlAes128Key?.isEmpty == false ? config.controlAes128Key! : config.masterKey
        guard let key = Data(hex: controlKeyHex), key.count == 16,
              let encrypted = extractEncryptedPayload(from: data),
              let plain = aesECBDecrypt(encrypted, key: key),
              !plain.isEmpty else { return nil }
        return plain.removingPKCS7PaddingIfPresent()
    }

    private func parseControlResponse(_ data: Data?) -> (serviceId: UInt16?, status: UInt8?, btParam: UInt8?, resultCode: UInt8?) {
        guard let data, !data.isEmpty else { return (nil, nil, nil, nil) }
        let serviceId = data.count >= 2 ? data.readUInt16BE(at: 0) : nil
        let status = data.count >= 3 ? data[2] : nil
        let btParam = data.count >= 4 ? data[3] : nil
        let resultCode = data.count >= 5 ? data[4] : nil
        return (serviceId, status, btParam, resultCode)
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
        guard let peripheral = candidatePeripheral else {
            if config != nil {
                startScanning()
            }
            return
        }
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        state = .connecting
        onLog?("BLE", "connecting \(candidateName) rssi=\(candidateRSSI) score=\(candidateScore)")
        central.connect(peripheral, options: nil)
    }

    private func discoveryScore(localName: String, advertisementData: [String: Any], rssi: Int) -> Int {
        var score = 0
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(authService) { score += 6 }
            if serviceUUIDs.contains(controlService) { score += 6 }
        }
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           manufacturerData.count >= 2,
           manufacturerData[0] == 0x55,
           manufacturerData[1] == 0x2B {
            score += 8
        }
        let normalizedName = localName.lowercased().filter { $0.isLetter || $0.isNumber }
        let normalizedMac = (config?.bleMac ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
        if normalizedMac.count >= 4 {
            let suffix4 = String(normalizedMac.suffix(4))
            if normalizedName.contains(suffix4) { score += 12 }
        }
        if normalizedMac.count >= 6 {
            let suffix6 = String(normalizedMac.suffix(6))
            if normalizedName.contains(suffix6) { score += 18 }
        }
        score += max(-10, min(10, (rssi + 90) / 4))
        return score
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
        let score = discoveryScore(localName: localName, advertisementData: advertisementData, rssi: RSSI.intValue)
        let manufacturerHex = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexString ?? "--"
        onLog?("BLE", "discovered name=\(localName) rssi=\(RSSI) score=\(score) mfg=\(manufacturerHex.prefix(20))")
        guard discoveredPeripheral == nil else { return }
        if candidatePeripheral == nil || score > candidateScore || (score == candidateScore && RSSI.intValue > candidateRSSI) {
            candidatePeripheral = peripheral
            candidateName = localName
            candidateRSSI = RSSI.intValue
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
        state = .error(error?.localizedDescription ?? "connect failed")
        onLog?("BLE", "connect failed | \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        notify181AReady = false
        notify182AReady = false
        completePendingDoorLock(.failure(.sessionStopped))
        onLog?("BLE", "disconnected | \(error?.localizedDescription ?? "no error")")
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
        peripheral.services?.forEach { service in
            if service.uuid == authService {
                peripheral.discoverCharacteristics([authWrite, authNotify], for: service)
            } else if service.uuid == controlService {
                peripheral.discoverCharacteristics([controlWrite, controlNotify], for: service)
            }
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
                completePendingDoorLock(.failure(controlError))
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
