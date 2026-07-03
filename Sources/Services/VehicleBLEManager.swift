import Foundation
import CoreBluetooth

final class VehicleBLEManager: NSObject {
    enum State: Equatable {
        case idle
        case unsupported
        case bluetoothOff
        case scanning
        case connecting
        case connected
        case error(String)
    }

    struct SessionConfig: Equatable {
        let bleMac: String
        let keyId: String
        let masterKey: String
    }

    var onStateChange: ((State) -> Void)?
    var onLog: ((String, String?) -> Void)?

    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private var config: SessionConfig?
    private var discoveredPeripheral: CBPeripheral?
    private var notify181AReady = false
    private var notify182AReady = false
    private var hasStartedCentral = false
    private(set) var state: State = .idle {
        didSet {
            guard oldValue != state else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onStateChange?(self.state)
            }
        }
    }

    private let authService = CBUUID(string: "181A")
    private let authNotify = CBUUID(string: "2A6F")
    private let controlService = CBUUID(string: "182A")
    private let controlNotify = CBUUID(string: "2A7F")

    func start(config: SessionConfig) {
        self.config = config
        notify181AReady = false
        notify182AReady = false
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
        notify181AReady = false
        notify182AReady = false
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
        onLog?("BLE", "connect failed", error?.localizedDescription)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        discoveredPeripheral = nil
        notify181AReady = false
        notify182AReady = false
        onLog?("BLE", "disconnected", error?.localizedDescription)
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
            onLog?("BLE", "discover services failed", error.localizedDescription)
            return
        }
        peripheral.services?.forEach { service in
            if service.uuid == authService {
                peripheral.discoverCharacteristics([authNotify], for: service)
            } else if service.uuid == controlService {
                peripheral.discoverCharacteristics([controlNotify], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            onLog?("BLE", "discover characteristics failed", error.localizedDescription)
            return
        }
        service.characteristics?.forEach { characteristic in
            if characteristic.uuid == authNotify || characteristic.uuid == controlNotify {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            state = .error(error.localizedDescription)
            onLog?("BLE", "set notify failed", error.localizedDescription)
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
}
