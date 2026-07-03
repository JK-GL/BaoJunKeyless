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

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "BLE 未鉴权成功"
            case .writeCharacteristicMissing: return "BLE 控制写特征不存在"
            case .invalidConfig: return "BLE 控制配置无效"
            case .frameBuildFailed: return "BLE 控制帧构造失败"
            case .writeFailed(let detail): return "BLE 控制写入失败：\(detail)"
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

    var onStateChange: ((State) -> Void)?
    var onLog: ((String, String?) -> Void)?

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
        self.config = config
        lastControlError = nil
        authWriteCharacteristic = nil
        controlWriteCharacteristic = nil
        notify181AReady = false
        notify182AReady = false
        didSendAuthFrame = false
        pendingDoorLockStatus = nil
        pendingDoorLockBtParam = nil
        if !hasStartedCentral {
            hasStartedCentral = true
            _ = central
        } else {
            handleCentralState()
        }
    }

    func stop() {
        central.stopScan()
        if let discoveredPeripheral {
            central.cancelPeripheralConnection(discoveredPeripheral)
        }
        discoveredPeripheral = nil
        authWriteCharacteristic = nil
        controlWriteCharacteristic = nil
        notify181AReady = false
        notify182AReady = false
        didSendAuthFrame = false
        pendingDoorLockStatus = nil
        pendingDoorLockBtParam = nil
        state = .idle
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
        central.stopScan()
        state = .scanning
        onLog?("BLE", "scanning services 181A/182A")
        central.scanForPeripherals(withServices: [authService, controlService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func finishIfReady() {
        guard notify181AReady, notify182AReady else { return }
        state = .connected
        onLog?("BLE", "notify ready 2A6F + 2A7F")
        sendAuthFrameIfPossible()
    }

    func sendDoorLockCommand(lock: Bool) -> Result<Void, BLEControlError> {
        guard case .authenticated = state else {
            lastControlError = .notAuthenticated
            return .failure(.notAuthenticated)
        }
        guard let config,
              let peripheral = discoveredPeripheral,
              let controlWriteCharacteristic else {
            lastControlError = .writeCharacteristicMissing
            return .failure(.writeCharacteristicMissing)
        }
        guard let frame = makeDoorLockControlFrame(config: config, lock: lock) else {
            lastControlError = .frameBuildFailed
            return .failure(.frameBuildFailed)
        }
        lastControlError = nil
        let statusValue: UInt8 = lock ? 1 : 0
        let btParam: UInt8 = lock ? 0 : 1
        pendingDoorLockStatus = statusValue
        pendingDoorLockBtParam = btParam
        onLog?("BLE", "send doorLock control status=\(statusValue) btParam=\(btParam) len=\(frame.count) bleType=\(config.bleType ?? "--") bleKey=\(config.bleKey ?? "--")")
        peripheral.writeValue(frame, for: controlWriteCharacteristic, type: .withResponse)
        return .success(())
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
        let context: String
        if let status = pendingDoorLockStatus, let btParam = pendingDoorLockBtParam {
            context = "pendingDoorLock status=\(status) btParam=\(btParam)"
        } else {
            context = "no pending control context"
        }
        onLog?("BLE", "control notify received | \(context) | rawLen=\(data.count)")
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
    func readUInt32BE(at offset: Int) -> UInt32 {
        let range = offset..<(offset + 4)
        return self.subdata(in: range).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
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
        onLog?("BLE", "discovered name=\(localName) rssi=\(RSSI)")
        guard discoveredPeripheral == nil else { return }
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        state = .connecting
        onLog?("BLE", "connecting \(localName)")
        central.connect(peripheral, options: nil)
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

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastControlError = .writeFailed(error.localizedDescription)
            state = .error(error.localizedDescription)
            onLog?("BLE", "write value failed | \(error.localizedDescription)")
            return
        }
        onLog?("BLE", "write ok uuid=\(characteristic.uuid.uuidString)")
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
