// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreBluetooth)
@preconcurrency import CoreBluetooth
import Foundation

public enum FeverFridaBLEError: LocalizedError, Equatable {
    case bluetoothUnavailable(String)
    case peripheralNotFound(UUID)
    case connectionFailed(String)
    case disconnected(String?)

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let state):
            return "Bluetooth is unavailable (\(state))."
        case .peripheralNotFound(let id):
            return "No discovered or system-known peripheral has identifier \(id)."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .disconnected(let message):
            return message.map { "The sensor disconnected: \($0)" } ?? "The sensor disconnected."
        }
    }
}

@MainActor
public final class FeverFridaCentral: NSObject {
    public private(set) var advertisements: [BLEAdvertisement] = []
    public private(set) var packets: [BLEPacket] = []
    public private(set) var latestGATTMap: GATTMap?

    private lazy var central = CBCentralManager(delegate: self, queue: nil)
    private var discovered: [UUID: CBPeripheral] = [:]
    private var advertisementContinuations: [UUID: AsyncStream<BLEAdvertisement>.Continuation] = [:]
    private var packetContinuations: [UUID: AsyncStream<BLEPacket>.Continuation] = [:]
    private var gattContinuations: [UUID: AsyncStream<GATTMap>.Continuation] = [:]
    private var temperatureContinuations: [UUID: AsyncStream<FeverFridaTemperatureSample>.Continuation] = [:]
    private var batteryContinuations: [UUID: AsyncStream<FeverFridaBatteryLevel>.Continuation] = [:]
    private var wt701Continuations: [UUID: AsyncStream<FeverFridaWT701Frame>.Continuation] = [:]
    private var readinessContinuations: [CheckedContinuation<Void, Error>] = []
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var connectedPeripheral: CBPeripheral?
    private var includedServicesCompleted: Set<ObjectIdentifier> = []
    private var characteristicsCompleted: Set<ObjectIdentifier> = []
    private var descriptorsCompleted: Set<ObjectIdentifier> = []
    private var gattDiscoveryErrors: [String] = []
    private var wt701PollingTask: Task<Void, Never>?
    private var pendingReads: Set<ObjectIdentifier> = []

    public override init() {
        super.init()
        _ = central
    }

    public func scan(allowDuplicates: Bool = true) throws -> AsyncStream<BLEAdvertisement> {
        guard central.state == .poweredOn else {
            throw FeverFridaBLEError.bluetoothUnavailable(Self.name(for: central.state))
        }

        let token = UUID()
        let pair = AsyncStream<BLEAdvertisement>.makeStream()
        advertisementContinuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                self?.advertisementContinuations[token] = nil
                if self?.advertisementContinuations.isEmpty == true {
                    self?.central.stopScan()
                }
            }
        }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
        )
        return pair.stream
    }

    public func waitUntilReady() async throws {
        if central.state == .poweredOn { return }
        if ![.unknown, .resetting].contains(central.state) {
            throw FeverFridaBLEError.bluetoothUnavailable(Self.name(for: central.state))
        }
        try await withCheckedThrowingContinuation { readinessContinuations.append($0) }
    }

    public func stopScanning() {
        central.stopScan()
        advertisementContinuations.values.forEach { $0.finish() }
        advertisementContinuations.removeAll()
    }

    public func packetStream() -> AsyncStream<BLEPacket> {
        let token = UUID()
        let pair = AsyncStream<BLEPacket>.makeStream()
        packetContinuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.packetContinuations[token] = nil }
        }
        return pair.stream
    }

    public func gattMapStream() -> AsyncStream<GATTMap> {
        let token = UUID()
        let pair = AsyncStream<GATTMap>.makeStream()
        gattContinuations[token] = pair.continuation
        if let latestGATTMap { pair.continuation.yield(latestGATTMap) }
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.gattContinuations[token] = nil }
        }
        return pair.stream
    }

    /// Temperature samples from either Bluetooth SIG thermometer
    /// characteristics or the observed WT701 realtime characteristic.
    public func temperatureStream() -> AsyncStream<FeverFridaTemperatureSample> {
        let token = UUID()
        let pair = AsyncStream<FeverFridaTemperatureSample>.makeStream()
        temperatureContinuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.temperatureContinuations[token] = nil }
        }
        return pair.stream
    }

    /// Battery samples from standard GATT or observed WT701 characteristics.
    public func batteryStream() -> AsyncStream<FeverFridaBatteryLevel> {
        let token = UUID()
        let pair = AsyncStream<FeverFridaBatteryLevel>.makeStream()
        batteryContinuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.batteryContinuations[token] = nil }
        }
        return pair.stream
    }

    /// Complete, checksum-validated proprietary WT701 realtime frames.
    public func wt701FrameStream() -> AsyncStream<FeverFridaWT701Frame> {
        let token = UUID()
        let pair = AsyncStream<FeverFridaWT701Frame>.makeStream()
        wt701Continuations[token] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.wt701Continuations[token] = nil }
        }
        return pair.stream
    }

    public func connect(to id: UUID) async throws {
        guard central.state == .poweredOn else {
            throw FeverFridaBLEError.bluetoothUnavailable(Self.name(for: central.state))
        }
        let peripheral = discovered[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let peripheral else { throw FeverFridaBLEError.peripheralNotFound(id) }

        if connectedPeripheral?.identifier == id, peripheral.state == .connected { return }
        includedServicesCompleted.removeAll()
        characteristicsCompleted.removeAll()
        descriptorsCompleted.removeAll()
        gattDiscoveryErrors.removeAll()
        wt701PollingTask?.cancel()
        wt701PollingTask = nil
        pendingReads.removeAll()
        latestGATTMap = nil
        connectedPeripheral = peripheral
        peripheral.delegate = self
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            central.connect(peripheral)
        }
    }

    public func disconnect() {
        wt701PollingTask?.cancel()
        wt701PollingTask = nil
        guard let connectedPeripheral else { return }
        central.cancelPeripheralConnection(connectedPeripheral)
    }

    public func exportAdvertisements() throws -> Data {
        try FeverFridaCaptureExport.jsonLines(advertisements)
    }

    public func exportPackets() throws -> Data {
        try FeverFridaCaptureExport.jsonLines(packets)
    }

    public func exportGATTMap() throws -> Data? {
        try latestGATTMap.map(FeverFridaCaptureExport.prettyJSON)
    }

    private func rebuildGATTMap(for peripheral: CBPeripheral) {
        guard let services = peripheral.services else { return }
        let mapped = services.map { service in
            GATTService(
                uuid: service.uuid.uuidString,
                isPrimary: service.isPrimary,
                includedServiceUUIDs: (service.includedServices ?? []).map { $0.uuid.uuidString },
                characteristics: (service.characteristics ?? []).map { characteristic in
                    GATTCharacteristic(
                        uuid: characteristic.uuid.uuidString,
                        properties: Self.names(for: characteristic.properties),
                        valueHex: characteristic.value?.feverFridaHex,
                        descriptors: (characteristic.descriptors ?? []).map {
                            GATTDescriptor(
                                uuid: $0.uuid.uuidString,
                                valueHex: ($0.value as? Data)?.feverFridaHex,
                                valueDescription: $0.value.map(String.init(describing:))
                            )
                        }
                    )
                }
            )
        }
        let isComplete = services.allSatisfy {
            includedServicesCompleted.contains(ObjectIdentifier($0)) &&
                characteristicsCompleted.contains(ObjectIdentifier($0)) &&
                ($0.characteristics ?? []).allSatisfy { descriptorsCompleted.contains(ObjectIdentifier($0)) }
        }
        latestGATTMap = GATTMap(
            peripheralID: peripheral.identifier,
            capturedAt: Date(),
            isComplete: isComplete,
            discoveryErrors: gattDiscoveryErrors,
            services: mapped
        )
        if let latestGATTMap { gattContinuations.values.forEach { $0.yield(latestGATTMap) } }
    }

    private func recordDiscoveryError(_ error: Error?, context: String, peripheral: CBPeripheral) {
        if let error { gattDiscoveryErrors.append("\(context): \(error.localizedDescription)") }
        rebuildGATTMap(for: peripheral)
    }

    private func record(_ packet: BLEPacket) {
        packets.append(packet)
        packetContinuations.values.forEach { $0.yield(packet) }
        if let frame = FeverFridaWT701Decoder.realtimeFrame(from: packet) {
            wt701Continuations.values.forEach { $0.yield(frame) }
        }
        if let temperature = FeverFridaWT701Decoder.temperature(from: packet) ?? FeverFridaStandardGATTDecoder.temperature(from: packet) {
            temperatureContinuations.values.forEach { $0.yield(temperature) }
        }
        if let battery = FeverFridaWT701Decoder.battery(from: packet) ?? FeverFridaStandardGATTDecoder.battery(from: packet) {
            batteryContinuations.values.forEach { $0.yield(battery) }
        }
    }

    private func startWT701Polling(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        wt701PollingTask?.cancel()
        wt701PollingTask = Task { [weak self, weak peripheral, weak characteristic] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled,
                      let self,
                      let peripheral,
                      let characteristic,
                      self.connectedPeripheral === peripheral,
                      peripheral.state == .connected else { return }
                self.requestRead(characteristic, on: peripheral)
            }
        }
    }

    private func requestRead(_ characteristic: CBCharacteristic, on peripheral: CBPeripheral) {
        pendingReads.insert(ObjectIdentifier(characteristic))
        peripheral.readValue(for: characteristic)
    }

    private static func name(for state: CBManagerState) -> String {
        switch state {
        case .unknown: "unknown"
        case .resetting: "resetting"
        case .unsupported: "unsupported"
        case .unauthorized: "unauthorized"
        case .poweredOff: "powered off"
        case .poweredOn: "powered on"
        @unknown default: "unrecognized"
        }
    }

    private static func names(for properties: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        let known: [(CBCharacteristicProperties, String)] = [
            (.broadcast, "broadcast"), (.read, "read"), (.writeWithoutResponse, "writeWithoutResponse"),
            (.write, "write"), (.notify, "notify"), (.indicate, "indicate"),
            (.authenticatedSignedWrites, "authenticatedSignedWrites"),
            (.extendedProperties, "extendedProperties"), (.notifyEncryptionRequired, "notifyEncryptionRequired"),
            (.indicateEncryptionRequired, "indicateEncryptionRequired")
        ]
        for (property, name) in known where properties.contains(property) { names.append(name) }
        return names
    }
}

extension FeverFridaCentral: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !readinessContinuations.isEmpty else { return }
        let continuations = readinessContinuations
        readinessContinuations.removeAll()
        if central.state == .poweredOn {
            continuations.forEach { $0.resume() }
        } else if ![.unknown, .resetting].contains(central.state) {
            let error = FeverFridaBLEError.bluetoothUnavailable(Self.name(for: central.state))
            continuations.forEach { $0.resume(throwing: error) }
        } else {
            readinessContinuations = continuations
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discovered[peripheral.identifier] = peripheral
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:])
            .reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value.feverFridaHex }
        let advertisement = BLEAdvertisement(
            id: peripheral.identifier,
            capturedAt: Date(),
            localName: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: RSSI.intValue,
            isConnectable: (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue,
            serviceUUIDs: (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
            overflowServiceUUIDs: (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
            solicitedServiceUUIDs: (advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString),
            manufacturerDataHex: (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.feverFridaHex,
            serviceDataHex: serviceData,
            transmitPower: (advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber)?.intValue
        )
        advertisements.append(advertisement)
        advertisementContinuations.values.forEach { $0.yield(advertisement) }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectContinuation?.resume()
        connectContinuation = nil
        peripheral.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectContinuation?.resume(throwing: FeverFridaBLEError.connectionFailed(error?.localizedDescription ?? "unknown error"))
        connectContinuation = nil
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if connectContinuation != nil {
            connectContinuation?.resume(throwing: FeverFridaBLEError.disconnected(error?.localizedDescription))
            connectContinuation = nil
        }
        if connectedPeripheral?.identifier == peripheral.identifier { connectedPeripheral = nil }
        wt701PollingTask?.cancel()
        wt701PollingTask = nil
    }
}

extension FeverFridaCentral: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            recordDiscoveryError(error, context: "services", peripheral: peripheral)
            return
        }
        peripheral.services?.forEach {
            peripheral.discoverIncludedServices(nil, for: $0)
            peripheral.discoverCharacteristics(nil, for: $0)
        }
        rebuildGATTMap(for: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?) {
        includedServicesCompleted.insert(ObjectIdentifier(service))
        recordDiscoveryError(error, context: "included services for \(service.uuid.uuidString)", peripheral: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        characteristicsCompleted.insert(ObjectIdentifier(service))
        guard error == nil else {
            recordDiscoveryError(error, context: "characteristics for \(service.uuid.uuidString)", peripheral: peripheral)
            return
        }
        for characteristic in service.characteristics ?? [] {
            peripheral.discoverDescriptors(for: characteristic)
            if characteristic.properties.contains(.read) { requestRead(characteristic, on: peripheral) }
            if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.uuid.uuidString.caseInsensitiveCompare(FeverFridaWT701UUID.realtimeMeasurement) == .orderedSame {
                startWT701Polling(characteristic, on: peripheral)
            }
        }
        rebuildGATTMap(for: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        descriptorsCompleted.insert(ObjectIdentifier(characteristic))
        guard error == nil else {
            recordDiscoveryError(error, context: "descriptors for \(characteristic.uuid.uuidString)", peripheral: peripheral)
            return
        }
        characteristic.descriptors?.forEach { peripheral.readValue(for: $0) }
        rebuildGATTMap(for: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        recordDiscoveryError(error, context: "descriptor value for \(descriptor.uuid.uuidString)", peripheral: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let wasRequestedRead = pendingReads.remove(ObjectIdentifier(characteristic)) != nil
        guard error == nil, let value = characteristic.value else {
            recordDiscoveryError(error, context: "characteristic value for \(characteristic.uuid.uuidString)", peripheral: peripheral)
            return
        }
        let direction: BLEPacketDirection
        if wasRequestedRead {
            direction = .read
        } else if characteristic.isNotifying {
            direction = characteristic.properties.contains(.indicate) && !characteristic.properties.contains(.notify)
                ? .indication : .notification
        } else {
            direction = .read
        }
        record(BLEPacket(
            direction: direction,
            peripheralID: peripheral.identifier,
            serviceUUID: characteristic.service?.uuid.uuidString,
            characteristicUUID: characteristic.uuid.uuidString,
            payloadHex: value.feverFridaHex
        ))
        rebuildGATTMap(for: peripheral)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        recordDiscoveryError(error, context: "notification state for \(characteristic.uuid.uuidString)", peripheral: peripheral)
    }
}
#endif
