// SPDX-License-Identifier: Apache-2.0

import Combine
import FeverFridaKit
import Foundation
import SwiftUI

private final class CaptureFileStore {
    let directoryURL: URL
    private let encoder: JSONEncoder

    init() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let runName = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        directoryURL = documents
            .appendingPathComponent("FeverFridaCaptures", isDirectory: true)
            .appendingPathComponent(runName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func append<T: Encodable>(_ value: T, to filename: String) {
        do {
            var line = try encoder.encode(value)
            line.append(0x0A)
            let url = directoryURL.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                try line.write(to: url, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } catch {
            // Capture remains available in memory and through the share buttons.
        }
    }

    func replace<T: Encodable>(_ value: T, at filename: String) {
        do {
            let prettyEncoder = JSONEncoder()
            prettyEncoder.dateEncodingStrategy = .iso8601
            prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try prettyEncoder.encode(value).write(
                to: directoryURL.appendingPathComponent(filename),
                options: .atomic
            )
        } catch {
            // Capture remains available in memory and through the share buttons.
        }
    }
}

@MainActor
final class ExplorerModel: ObservableObject {
    @Published private(set) var devices: [BLEAdvertisement] = []
    @Published private(set) var packets: [BLEPacket] = []
    @Published private(set) var gattMap: GATTMap?
    @Published private(set) var latestTemperature: FeverFridaTemperatureSample?
    @Published private(set) var latestBattery: FeverFridaBatteryLevel?
    @Published private(set) var latestWT701Frame: FeverFridaWT701Frame?
    @Published private(set) var status = "Bluetooth starting…"
    @Published private(set) var isScanning = false
    @Published private(set) var captureDirectory = "Capture storage unavailable"

    private let central = FeverFridaCentral()
    private var scanTask: Task<Void, Never>?
    private var packetTask: Task<Void, Never>?
    private var gattTask: Task<Void, Never>?
    private var temperatureTask: Task<Void, Never>?
    private var batteryTask: Task<Void, Never>?
    private var wt701Task: Task<Void, Never>?
    private let captureStore: CaptureFileStore?
    private var didAutoConnectWT701 = false

    init() {
        captureStore = try? CaptureFileStore()
        if let captureStore {
            captureDirectory = captureStore.directoryURL.lastPathComponent
        }
        packetTask = Task { [central] in
            for await packet in central.packetStream() {
                packets.append(packet)
                captureStore?.append(packet, to: "packets.jsonl")
            }
        }
        gattTask = Task { [central] in
            for await map in central.gattMapStream() {
                gattMap = map
                captureStore?.replace(map, at: "gatt.json")
                status = map.isComplete
                    ? "Connected · complete GATT map · \(map.services.count) services"
                    : "Connected · discovering GATT · \(map.services.count) services"
            }
        }
        temperatureTask = Task { [central] in
            for await sample in central.temperatureStream() {
                latestTemperature = sample
            }
        }
        batteryTask = Task { [central] in
            for await level in central.batteryStream() {
                latestBattery = level
            }
        }
        wt701Task = Task { [central] in
            for await frame in central.wt701FrameStream() {
                latestWT701Frame = frame
            }
        }
    }

    deinit {
        scanTask?.cancel()
        packetTask?.cancel()
        gattTask?.cancel()
        temperatureTask?.cancel()
        batteryTask?.cancel()
        wt701Task?.cancel()
    }

    func startScanning() {
        guard scanTask == nil else { return }
        isScanning = true
        status = "Waiting for Bluetooth…"
        scanTask = Task { [weak self, central] in
            guard let self else { return }
            do {
                try await central.waitUntilReady()
                self.status = "Scanning nearby BLE devices"
                let stream = try central.scan()
                for await advertisement in stream {
                    guard !Task.isCancelled else { break }
                    self.captureStore?.append(advertisement, to: "advertisements.jsonl")
                    if advertisement.isAppleDevice {
                        self.devices.removeAll { $0.id == advertisement.id }
                        continue
                    }
                    if let index = self.devices.firstIndex(where: { $0.id == advertisement.id }) {
                        self.devices[index] = advertisement
                    } else {
                        self.devices.append(advertisement)
                    }
                    self.devices.sort {
                        if Self.isLikelyFeverFrida($0) != Self.isLikelyFeverFrida($1) {
                            return Self.isLikelyFeverFrida($0)
                        }
                        return $0.rssi > $1.rssi
                    }
                    if !self.didAutoConnectWT701,
                       advertisement.isConnectable != false,
                       advertisement.serviceUUIDs.contains(where: { $0.caseInsensitiveCompare("FEE7") == .orderedSame }) {
                        self.didAutoConnectWT701 = true
                        self.connect(to: advertisement)
                    }
                }
            } catch {
                self.status = error.localizedDescription
            }
            self.isScanning = false
            self.scanTask = nil
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
        central.stopScanning()
        isScanning = false
        status = "Scan stopped"
    }

    func connect(to device: BLEAdvertisement) {
        status = "Connecting to \(device.localName ?? device.id.uuidString)…"
        Task { [central] in
            do {
                try await central.connect(to: device.id)
                status = "Connected · discovering GATT"
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func advertisementExport() -> Data { (try? central.exportAdvertisements()) ?? Data() }
    func packetExport() -> Data { (try? central.exportPackets()) ?? Data() }
    func gattExport() -> Data { (try? central.exportGATTMap()) ?? Data() }

    static func isLikelyFeverFrida(_ device: BLEAdvertisement) -> Bool {
        let name = (device.localName ?? "").lowercased()
        let nameHints = ["feverfrida", "fever frida", "itherm", "wt701", "raiing"]
        if nameHints.contains(where: name.contains) { return true }

        let normalizedServices = Set(device.serviceUUIDs.map { $0.uppercased() })
        let candidateServices: Set<String> = [
            "FEE7", "0000FEE7-0000-1000-8000-00805F9B34FB",
            "FFF0", "0000FFF0-0000-1000-8000-00805F9B34FB",
            "F000CCC0-0451-4000-B000-000000000000"
        ]
        let candidatePrefixes = ["5FC41000", "5FC43000", "5FC44000", "5FC45000"]
        return !normalizedServices.isDisjoint(with: candidateServices) ||
            normalizedServices.contains { uuid in candidatePrefixes.contains(where: uuid.hasPrefix) }
    }
}

struct ExplorerView: View {
    @StateObject private var model = ExplorerModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Text(model.status)
                    LabeledContent("Saved run", value: model.captureDirectory)
                        .font(.caption)
                    if let frame = model.latestWT701Frame {
                        LabeledContent("WT701 primary sensor", value: frame.primaryCelsius.formatted(.number.precision(.fractionLength(3))) + " °C")
                        LabeledContent("WT701 secondary sensor", value: frame.secondaryCelsius.formatted(.number.precision(.fractionLength(3))) + " °C")
                        LabeledContent("Device counter", value: "\(frame.deviceCounter)")
                    } else if let temperature = model.latestTemperature {
                        LabeledContent("Temperature", value: temperature.celsius.formatted(.number.precision(.fractionLength(2))) + " °C")
                    }
                    if let battery = model.latestBattery {
                        LabeledContent("Battery", value: "\(battery.percent)%")
                    }
                    Button(model.isScanning ? "Stop scan" : "Start scan") {
                        model.isScanning ? model.stopScanning() : model.startScanning()
                    }
                }

                Section("Nearby devices") {
                    if model.devices.isEmpty {
                        Text("Power on the FeverFrida after starting the scan.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.devices) { device in
                        Button { model.connect(to: device) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(device.localName ?? "Unnamed BLE device")
                                    if ExplorerModel.isLikelyFeverFrida(device) {
                                        Text("candidate")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.2), in: Capsule())
                                    }
                                }
                                Text("RSSI \(device.rssi) · \(device.id.uuidString)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if !device.serviceUUIDs.isEmpty {
                                    Text("Services: \(device.serviceUUIDs.joined(separator: ", "))")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let map = model.gattMap {
                    Section("GATT map") {
                        LabeledContent("Discovery", value: map.isComplete ? "Complete" : "In progress")
                        if !map.discoveryErrors.isEmpty {
                            ForEach(map.discoveryErrors, id: \.self) { error in
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                        ForEach(map.services, id: \.uuid) { service in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(service.uuid).font(.caption.monospaced().bold())
                                ForEach(service.characteristics, id: \.uuid) { characteristic in
                                    Text("\(characteristic.uuid) · \(characteristic.properties.joined(separator: ", "))")
                                        .font(.caption2.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                Section("Captured packets") {
                    Text("\(model.packets.count) reads, notifications, or indications")
                    ForEach(model.packets.suffix(30)) { packet in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(packet.direction.rawValue) · \(packet.characteristicUUID ?? "unknown")")
                                .font(.caption)
                            Text(packet.payloadHex)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Export") {
                    ShareLink(item: model.advertisementExport(), preview: SharePreview("advertisements.jsonl")) {
                        Label("Share advertisements", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: model.gattExport(), preview: SharePreview("gatt.json")) {
                        Label("Share GATT map", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(item: model.packetExport(), preview: SharePreview("packets.jsonl")) {
                        Label("Share packets", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("FeverFrida Explorer")
            .task { model.startScanning() }
        }
    }
}
