// SPDX-License-Identifier: Apache-2.0

import Foundation

/// UUIDs observed on a physical FeverFrida-branded Raiing WT701.
public enum FeverFridaWT701UUID {
    public static let realtimeService = "A72435C3-D797-44ED-A625-CF29D84AA64C"
    public static let realtimeMeasurement = "5869CF77-A8EA-47D8-A239-CD2100FA30A1"
    public static let batteryLevel = "29A59C78-CCC0-11E2-B493-14CF921AE45D"
}

/// One integrity-checked WT701 realtime frame. Both temperatures are raw
/// thermistor channels; neither is claimed to be the app's processed body
/// temperature.
public struct FeverFridaWT701Frame: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let receivedAt: Date
    public let deviceCounter: UInt32
    public let batteryPercent: UInt8
    public let primaryMilliCelsius: UInt16
    public let secondaryMilliCelsius: UInt16
    public let reserved: UInt16
    public let checksum: UInt16

    public var primaryCelsius: Double { Double(primaryMilliCelsius) / 1_000 }
    public var secondaryCelsius: Double { Double(secondaryMilliCelsius) / 1_000 }

    public init(
        id: UUID = UUID(),
        receivedAt: Date,
        deviceCounter: UInt32,
        batteryPercent: UInt8,
        primaryMilliCelsius: UInt16,
        secondaryMilliCelsius: UInt16,
        reserved: UInt16,
        checksum: UInt16
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.deviceCounter = deviceCounter
        self.batteryPercent = batteryPercent
        self.primaryMilliCelsius = primaryMilliCelsius
        self.secondaryMilliCelsius = secondaryMilliCelsius
        self.reserved = reserved
        self.checksum = checksum
    }
}

public enum FeverFridaWT701Decoder {
    /// Decodes the 13-byte direct realtime indication observed on the WT701.
    public static func realtimeFrame(from packet: BLEPacket) -> FeverFridaWT701Frame? {
        guard packet.characteristicUUID?.caseInsensitiveCompare(FeverFridaWT701UUID.realtimeMeasurement) == .orderedSame,
              let bytes = bytes(from: packet.payloadHex), bytes.count == 13 else { return nil }

        let expectedChecksum = littleEndianUInt16(bytes, at: 11)
        guard crc16CCITTFalse(Array(bytes[0..<11])) == expectedChecksum else { return nil }

        let battery = bytes[4]
        guard battery <= 100 else { return nil }
        return FeverFridaWT701Frame(
            receivedAt: packet.capturedAt,
            deviceCounter: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24,
            batteryPercent: battery,
            primaryMilliCelsius: littleEndianUInt16(bytes, at: 5),
            secondaryMilliCelsius: littleEndianUInt16(bytes, at: 7),
            reserved: littleEndianUInt16(bytes, at: 9),
            checksum: expectedChecksum
        )
    }

    /// Decodes either the dedicated one-byte battery characteristic or the
    /// battery byte embedded in an integrity-checked realtime frame.
    public static func battery(from packet: BLEPacket) -> FeverFridaBatteryLevel? {
        if let frame = realtimeFrame(from: packet) {
            return FeverFridaBatteryLevel(
                receivedAt: frame.receivedAt,
                percent: frame.batteryPercent,
                characteristicUUID: FeverFridaWT701UUID.realtimeMeasurement
            )
        }
        guard packet.characteristicUUID?.caseInsensitiveCompare(FeverFridaWT701UUID.batteryLevel) == .orderedSame,
              let payload = bytes(from: packet.payloadHex), payload.count == 1, payload[0] <= 100 else { return nil }
        return FeverFridaBatteryLevel(
            receivedAt: packet.capturedAt,
            percent: payload[0],
            characteristicUUID: FeverFridaWT701UUID.batteryLevel
        )
    }

    public static func temperature(from packet: BLEPacket) -> FeverFridaTemperatureSample? {
        guard let frame = realtimeFrame(from: packet) else { return nil }
        return FeverFridaTemperatureSample(
            receivedAt: frame.receivedAt,
            celsius: frame.primaryCelsius,
            transmittedValue: frame.primaryCelsius,
            transmittedUnit: .celsius,
            sensorTime: nil,
            temperatureType: nil,
            characteristicUUID: FeverFridaWT701UUID.realtimeMeasurement
        )
    }

    public static func crc16CCITTFalse(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = crc & 0x8000 == 0 ? crc << 1 : (crc << 1) ^ 0x1021
            }
        }
        return crc
    }

    private static func littleEndianUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func bytes(from hex: String) -> [UInt8]? {
        let parts = hex.split(whereSeparator: { $0.isWhitespace })
        var result: [UInt8] = []
        result.reserveCapacity(parts.count)
        for part in parts {
            guard part.count == 2, let byte = UInt8(part, radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }
}
