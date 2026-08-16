// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct BLEAdvertisement: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let capturedAt: Date
    public let localName: String?
    public let rssi: Int
    public let isConnectable: Bool?
    public let serviceUUIDs: [String]
    public let overflowServiceUUIDs: [String]
    public let solicitedServiceUUIDs: [String]
    public let manufacturerDataHex: String?
    public let serviceDataHex: [String: String]
    public let transmitPower: Int?

    public init(
        id: UUID,
        capturedAt: Date,
        localName: String?,
        rssi: Int,
        isConnectable: Bool?,
        serviceUUIDs: [String],
        overflowServiceUUIDs: [String],
        solicitedServiceUUIDs: [String],
        manufacturerDataHex: String?,
        serviceDataHex: [String: String],
        transmitPower: Int?
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.localName = localName
        self.rssi = rssi
        self.isConnectable = isConnectable
        self.serviceUUIDs = serviceUUIDs
        self.overflowServiceUUIDs = overflowServiceUUIDs
        self.solicitedServiceUUIDs = solicitedServiceUUIDs
        self.manufacturerDataHex = manufacturerDataHex
        self.serviceDataHex = serviceDataHex
        self.transmitPower = transmitPower
    }
}

public extension BLEAdvertisement {
    /// True when the advertisement identifies itself as Apple hardware.
    /// Apple owns Bluetooth SIG company identifier 0x004C, transmitted in
    /// little-endian order as the first two manufacturer-data bytes (`4C 00`).
    var isAppleDevice: Bool {
        let compactManufacturerData = manufacturerDataHex?
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        if compactManufacturerData?.hasPrefix("4C00") == true { return true }

        let name = (localName ?? "").lowercased()
        let appleProductNames = [
            "iphone", "ipad", "ipod", "macbook", "imac", "mac mini", "mac studio",
            "apple watch", "apple tv", "airpods", "homepod", "apple pencil", "beats"
        ]
        return appleProductNames.contains(where: name.contains)
    }
}

public struct GATTDescriptor: Codable, Equatable, Sendable {
    public let uuid: String
    public let valueHex: String?
    public let valueDescription: String?

    public init(uuid: String, valueHex: String? = nil, valueDescription: String? = nil) {
        self.uuid = uuid
        self.valueHex = valueHex
        self.valueDescription = valueDescription
    }
}

public struct GATTCharacteristic: Codable, Equatable, Sendable {
    public let uuid: String
    public let properties: [String]
    public let valueHex: String?
    public let descriptors: [GATTDescriptor]

    public init(uuid: String, properties: [String], valueHex: String? = nil, descriptors: [GATTDescriptor] = []) {
        self.uuid = uuid
        self.properties = properties
        self.valueHex = valueHex
        self.descriptors = descriptors
    }
}

public struct GATTService: Codable, Equatable, Sendable {
    public let uuid: String
    public let isPrimary: Bool
    public let includedServiceUUIDs: [String]
    public let characteristics: [GATTCharacteristic]

    public init(
        uuid: String,
        isPrimary: Bool,
        includedServiceUUIDs: [String] = [],
        characteristics: [GATTCharacteristic]
    ) {
        self.uuid = uuid
        self.isPrimary = isPrimary
        self.includedServiceUUIDs = includedServiceUUIDs
        self.characteristics = characteristics
    }
}

public struct GATTMap: Codable, Equatable, Sendable {
    public let peripheralID: UUID
    public let capturedAt: Date
    public let isComplete: Bool
    public let discoveryErrors: [String]
    public let services: [GATTService]

    public init(
        peripheralID: UUID,
        capturedAt: Date,
        isComplete: Bool = false,
        discoveryErrors: [String] = [],
        services: [GATTService]
    ) {
        self.peripheralID = peripheralID
        self.capturedAt = capturedAt
        self.isComplete = isComplete
        self.discoveryErrors = discoveryErrors
        self.services = services
    }
}

public enum BLEPacketDirection: String, Codable, Equatable, Sendable {
    case advertisement
    case read
    case notification
    case indication
    case write
}

public struct BLEPacket: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let capturedAt: Date
    public let direction: BLEPacketDirection
    public let peripheralID: UUID
    public let serviceUUID: String?
    public let characteristicUUID: String?
    public let payloadHex: String

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        direction: BLEPacketDirection,
        peripheralID: UUID,
        serviceUUID: String? = nil,
        characteristicUUID: String? = nil,
        payloadHex: String
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.direction = direction
        self.peripheralID = peripheralID
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.payloadHex = payloadHex
    }
}

public extension Data {
    var feverFridaHex: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
