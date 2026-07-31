// SPDX-License-Identifier: Apache-2.0

import Combine
@preconcurrency import CoreBluetooth
import Foundation
import OSLog

public struct SensorTagDevice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let signalStrength: Int

    public init(id: UUID, name: String, signalStrength: Int) {
        self.id = id
        self.name = name
        self.signalStrength = signalStrength
    }
}

public enum SensorTagConnectionState: Equatable, Sendable {
    case unavailable
    case idle
    case scanning
    case connecting
    case connected
    case failed(String)
}

@MainActor
public final class SensorTagManager: NSObject, ObservableObject {
    public static let shared = SensorTagManager()
    private static let logger = Logger(subsystem: "dev.betterbcool.app", category: "SensorTag")

    @Published public private(set) var connectionState: SensorTagConnectionState = .idle
    @Published public private(set) var discoveredDevices: [SensorTagDevice] = []
    @Published public private(set) var connectedDevice: SensorTagDevice?
    @Published public private(set) var readings = SensorTagReadings()

    private static let savedDeviceKey = "betterBCool.sensorTag.identifier"
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var activePeripheral: CBPeripheral?
    private var barometerCalibration: [Int]?
    private var barometerConfiguration: CBCharacteristic?
    private var barometerCalibrationCharacteristic: CBCharacteristic?
    private var awaitingBarometerCalibration = false
    private var isPreviewing = false
    private var connectionTimeoutTask: Task<Void, Never>?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func scan() {
        guard central.state == .poweredOn else {
            connectionState = .unavailable
            return
        }
        connectionTimeoutTask?.cancel()
        discoveredDevices.removeAll()
        connectionState = .scanning
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    public func stopScanning() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .idle }
    }

    public func connect(to device: SensorTagDevice) {
        guard let peripheral = peripherals[device.id] else { return }
        connect(peripheral, device: device)
    }

    private func connect(_ peripheral: CBPeripheral, device: SensorTagDevice? = nil) {
        guard peripheral.state == .disconnected,
              connectionState != .connecting,
              connectionState != .connected else { return }
        central.stopScan()
        activePeripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        let identifier = device?.id ?? peripheral.identifier
        Self.logger.info("Connecting to SensorTag \(identifier.uuidString, privacy: .public), state \(peripheral.state.rawValue, privacy: .public)")
        record("connect requested id=\(identifier.uuidString) peripheralState=\(peripheral.state.rawValue)")
        central.connect(peripheral)
        startConnectionTimeout(for: peripheral)
    }

    public func cancelConnectionAttempt() {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        if let activePeripheral, activePeripheral.state != .disconnected {
            central.cancelPeripheralConnection(activePeripheral)
        }
        self.activePeripheral = nil
        connectedDevice = nil
        connectionState = central.state == .poweredOn ? .idle : .unavailable
    }

    public func disconnect() {
        if isPreviewing {
            isPreviewing = false
            connectedDevice = nil
            readings = SensorTagReadings()
            connectionState = central.state == .poweredOn ? .idle : .unavailable
            return
        }
        guard let activePeripheral else { return }
        UserDefaults.standard.removeObject(forKey: Self.savedDeviceKey)
        central.cancelPeripheralConnection(activePeripheral)
    }

    public func loadPreviewReadings() {
        central.stopScan()
        isPreviewing = true
        connectedDevice = SensorTagDevice(
            id: UUID(uuidString: "CC254100-0000-4000-8000-000000000001")!,
            name: "SensorTag preview",
            signalStrength: -48
        )
        readings = SensorTagReadings(
            timestamp: Date(),
            ambientTemperature: 23.4,
            objectTemperature: 25.1,
            relativeHumidity: 47.8,
            pressure: 1_014,
            acceleration: SensorVector(x: 0.02, y: -0.04, z: 0.99),
            angularVelocity: SensorVector(x: 0.14, y: -0.08, z: 0.03),
            magneticField: SensorVector(x: 21.7, y: -4.2, z: 42.8)
        )
        connectionState = .connected
    }

    private func restoreSavedDeviceIfPossible() {
        guard let rawID = UserDefaults.standard.string(forKey: Self.savedDeviceKey),
              let id = UUID(uuidString: rawID) else { return }

        if let connected = central.retrieveConnectedPeripherals(
            withServices: Array(SensorTagUUID.sensorServices)
        ).first(where: { $0.identifier == id }) {
            peripherals[id] = connected
            connect(connected)
            return
        }

        beginAutomaticScan()
    }

    private var savedDeviceID: UUID? {
        UserDefaults.standard.string(forKey: Self.savedDeviceKey).flatMap(UUID.init(uuidString:))
    }

    private func beginAutomaticScan() {
        guard central.state == .poweredOn, savedDeviceID != nil, !isPreviewing else { return }
        activePeripheral = nil
        connectionState = .scanning
        Self.logger.info("Scanning for remembered SensorTag")
        record("automatic scan started savedID=\(savedDeviceID?.uuidString ?? "none")")
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func startConnectionTimeout(for peripheral: CBPeripheral) {
        connectionTimeoutTask?.cancel()
        let identifier = peripheral.identifier
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled,
                  let self,
                  self.connectionState == .connecting,
                  self.activePeripheral?.identifier == identifier else { return }
            Self.logger.error("SensorTag connection timed out: \(identifier.uuidString, privacy: .public)")
            self.record("connection timed out id=\(identifier.uuidString)")
            self.central.cancelPeripheralConnection(peripheral)
            self.activePeripheral = nil
            if self.savedDeviceID == identifier {
                self.beginAutomaticScan()
            } else {
                self.connectionState = .failed(
                    "Connection timed out. Close other Bluetooth apps, press the SensorTag side button, then scan again."
                )
            }
        }
    }

    private func updateReadings(_ update: (inout SensorTagReadings) -> Void) {
        var next = readings
        update(&next)
        next.timestamp = Date()
        readings = next
    }

    private func record(_ message: String) {
        let fileManager = FileManager.default
        guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let file = directory.appending(path: "SensorTag.log")
        let line = "\(Date().ISO8601Format()) \(message)\n"
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: file.path),
               let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } else {
                try Data(line.utf8).write(to: file, options: .atomic)
            }
        } catch {
            Self.logger.error("Could not persist SensorTag trace: \(String(describing: error), privacy: .public)")
        }
    }
}

extension SensorTagManager: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !isPreviewing else { return }
        switch central.state {
        case .poweredOn:
            connectionState = .idle
            restoreSavedDeviceIfPossible()
        case .unknown, .resetting:
            connectionState = .idle
        case .unsupported, .unauthorized, .poweredOff:
            connectionState = .unavailable
        @unknown default:
            connectionState = .unavailable
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "SensorTag"
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.localizedCaseInsensitiveContains("SensorTag")
                || !Set(advertisedServices).isDisjoint(with: SensorTagUUID.sensorServices) else { return }
        peripherals[peripheral.identifier] = peripheral
        let device = SensorTagDevice(id: peripheral.identifier, name: name, signalStrength: RSSI.intValue)
        discoveredDevices.removeAll { $0.id == device.id }
        discoveredDevices.append(device)
        discoveredDevices.sort { $0.signalStrength > $1.signalStrength }

        if savedDeviceID == peripheral.identifier {
            Self.logger.info("Remembered SensorTag rediscovered; connecting automatically")
            record("remembered tag discovered id=\(peripheral.identifier.uuidString) rssi=\(RSSI.intValue)")
            connect(peripheral, device: device)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        Self.logger.info("Connected to SensorTag \(peripheral.identifier.uuidString, privacy: .public)")
        record("connected id=\(peripheral.identifier.uuidString)")
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.savedDeviceKey)
        connectionState = .connected
        connectedDevice = discoveredDevices.first { $0.id == peripheral.identifier }
            ?? SensorTagDevice(id: peripheral.identifier, name: peripheral.name ?? "SensorTag", signalStrength: 0)
        readings = SensorTagReadings()
        barometerCalibration = nil
        peripheral.discoverServices(Array(SensorTagUUID.sensorServices))
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        Self.logger.error("SensorTag connection failed: \(String(describing: error), privacy: .public)")
        record("connection failed id=\(peripheral.identifier.uuidString) error=\(String(describing: error))")
        activePeripheral = nil
        connectedDevice = nil
        readings = SensorTagReadings()
        if savedDeviceID == peripheral.identifier {
            beginAutomaticScan()
        } else {
            connectionState = .failed(error?.localizedDescription ?? "Could not connect")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        Self.logger.notice("SensorTag disconnected: \(String(describing: error), privacy: .public)")
        record("disconnected id=\(peripheral.identifier.uuidString) error=\(String(describing: error))")
        activePeripheral = nil
        connectedDevice = nil
        readings = SensorTagReadings()
        if savedDeviceID == peripheral.identifier {
            beginAutomaticScan()
        } else {
            connectionState = error.map { .failed($0.localizedDescription) } ?? .idle
        }
    }
}

extension SensorTagManager: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            connectionState = .failed(error?.localizedDescription ?? "Service discovery failed")
            return
        }
        record("services discovered count=\(peripheral.services?.count ?? 0)")
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        record("characteristics discovered service=\(service.uuid.uuidString) count=\(service.characteristics?.count ?? 0)")
        service.characteristics?.forEach { characteristic in
            switch characteristic.uuid {
            case SensorTagUUID.barometerConfiguration:
                barometerConfiguration = characteristic
            case SensorTagUUID.barometerCalibration:
                barometerCalibrationCharacteristic = characteristic
            case SensorTagUUID.infraredData, SensorTagUUID.humidityData,
                 SensorTagUUID.accelerometerData, SensorTagUUID.magnetometerData,
                 SensorTagUUID.barometerData, SensorTagUUID.gyroscopeData:
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            default:
                if let enableValue = SensorTagUUID.enableValue(for: characteristic.uuid) {
                    peripheral.writeValue(Data([enableValue]), for: characteristic, type: .withResponse)
                } else if SensorTagUUID.periodCharacteristics.contains(characteristic.uuid) {
                    peripheral.writeValue(Data([100]), for: characteristic, type: .withResponse)
                }
            }
        }

        if service.uuid == SensorTagUUID.barometerService,
           let barometerConfiguration,
           barometerCalibrationCharacteristic != nil {
            awaitingBarometerCalibration = true
            peripheral.writeValue(Data([2]), for: barometerConfiguration, type: .withResponse)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == SensorTagUUID.barometerConfiguration,
              awaitingBarometerCalibration,
              let barometerCalibrationCharacteristic else { return }
        awaitingBarometerCalibration = false
        peripheral.readValue(for: barometerCalibrationCharacteristic)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        switch characteristic.uuid {
        case SensorTagUUID.infraredData:
            guard let value = CC2541SensorDecoder.infraredTemperature(data) else { return }
            updateReadings {
                $0.ambientTemperature = value.ambient
                $0.objectTemperature = value.object
            }
            record("temperature ambient=\(value.ambient) object=\(value.object)")
        case SensorTagUUID.humidityData:
            guard let value = CC2541SensorDecoder.humidity(data) else { return }
            updateReadings { $0.relativeHumidity = value }
        case SensorTagUUID.accelerometerData:
            guard let value = CC2541SensorDecoder.acceleration(data) else { return }
            updateReadings { $0.acceleration = value }
        case SensorTagUUID.magnetometerData:
            guard let value = CC2541SensorDecoder.magneticField(data) else { return }
            updateReadings { $0.magneticField = value }
        case SensorTagUUID.gyroscopeData:
            guard let value = CC2541SensorDecoder.angularVelocity(data) else { return }
            updateReadings { $0.angularVelocity = value }
        case SensorTagUUID.barometerCalibration:
            guard let calibration = CC2541SensorDecoder.barometerCalibration(data),
                  let barometerConfiguration else { return }
            barometerCalibration = calibration
            peripheral.writeValue(Data([1]), for: barometerConfiguration, type: .withResponse)
        case SensorTagUUID.barometerData:
            guard let barometerCalibration,
                  let value = CC2541SensorDecoder.pressure(data, calibration: barometerCalibration) else { return }
            updateReadings { $0.pressure = value }
        default:
            break
        }
    }
}

private enum SensorTagUUID {
    static let infraredService = uuid(0xAA00)
    static let infraredData = uuid(0xAA01)
    static let infraredConfiguration = uuid(0xAA02)
    static let infraredPeriod = uuid(0xAA03)
    static let accelerometerService = uuid(0xAA10)
    static let accelerometerData = uuid(0xAA11)
    static let accelerometerConfiguration = uuid(0xAA12)
    static let accelerometerPeriod = uuid(0xAA13)
    static let humidityService = uuid(0xAA20)
    static let humidityData = uuid(0xAA21)
    static let humidityConfiguration = uuid(0xAA22)
    static let humidityPeriod = uuid(0xAA23)
    static let magnetometerService = uuid(0xAA30)
    static let magnetometerData = uuid(0xAA31)
    static let magnetometerConfiguration = uuid(0xAA32)
    static let magnetometerPeriod = uuid(0xAA33)
    static let barometerService = uuid(0xAA40)
    static let barometerData = uuid(0xAA41)
    static let barometerConfiguration = uuid(0xAA42)
    static let barometerCalibration = uuid(0xAA43)
    static let barometerPeriod = uuid(0xAA44)
    static let gyroscopeService = uuid(0xAA50)
    static let gyroscopeData = uuid(0xAA51)
    static let gyroscopeConfiguration = uuid(0xAA52)
    static let gyroscopePeriod = uuid(0xAA53)

    static let sensorServices: Set<CBUUID> = [
        infraredService, accelerometerService, humidityService,
        magnetometerService, barometerService, gyroscopeService
    ]

    static let periodCharacteristics: Set<CBUUID> = [
        infraredPeriod, accelerometerPeriod, humidityPeriod,
        magnetometerPeriod, barometerPeriod, gyroscopePeriod
    ]

    static func enableValue(for uuid: CBUUID) -> UInt8? {
        switch uuid {
        case infraredConfiguration, accelerometerConfiguration,
             humidityConfiguration, magnetometerConfiguration:
            return 1
        case gyroscopeConfiguration:
            return 7
        default:
            return nil
        }
    }

    private static func uuid(_ short: UInt16) -> CBUUID {
        CBUUID(string: String(format: "F000%04X-0451-4000-B000-000000000000", short))
    }
}
