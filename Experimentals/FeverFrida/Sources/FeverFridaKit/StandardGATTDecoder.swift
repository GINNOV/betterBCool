// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum FeverFridaTemperatureUnit: String, Codable, Equatable, Sendable {
    case celsius
    case fahrenheit
}

public struct FeverFridaDateTime: Codable, Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int

    public init(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

public struct FeverFridaTemperatureSample: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let receivedAt: Date
    public let celsius: Double
    public let transmittedValue: Double
    public let transmittedUnit: FeverFridaTemperatureUnit
    public let sensorTime: FeverFridaDateTime?
    public let temperatureType: UInt8?
    public let characteristicUUID: String

    public init(
        id: UUID = UUID(),
        receivedAt: Date,
        celsius: Double,
        transmittedValue: Double,
        transmittedUnit: FeverFridaTemperatureUnit,
        sensorTime: FeverFridaDateTime?,
        temperatureType: UInt8?,
        characteristicUUID: String
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.celsius = celsius
        self.transmittedValue = transmittedValue
        self.transmittedUnit = transmittedUnit
        self.sensorTime = sensorTime
        self.temperatureType = temperatureType
        self.characteristicUUID = characteristicUUID
    }
}

public struct FeverFridaBatteryLevel: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let receivedAt: Date
    public let percent: UInt8
    public let characteristicUUID: String

    public init(id: UUID = UUID(), receivedAt: Date, percent: UInt8, characteristicUUID: String) {
        self.id = id
        self.receivedAt = receivedAt
        self.percent = percent
        self.characteristicUUID = characteristicUUID
    }
}

/// Decodes Bluetooth SIG standard characteristics only. Proprietary FeverFrida
/// packets are intentionally left raw until confirmed by a physical capture.
public enum FeverFridaStandardGATTDecoder {
    public static func temperature(from packet: BLEPacket) -> FeverFridaTemperatureSample? {
        guard let uuid = packet.characteristicUUID,
              matches(uuid, shortUUIDs: ["2A1C", "2A1E"]),
              let bytes = bytes(from: packet.payloadHex),
              bytes.count >= 5 else { return nil }

        let flags = bytes[0]
        guard flags & 0b1111_1000 == 0 else { return nil }
        guard let value = ieee11073Float(Array(bytes[1...4])) else { return nil }

        var offset = 5
        var sensorTime: FeverFridaDateTime?
        if flags & 0b0000_0010 != 0 {
            guard bytes.count >= offset + 7 else { return nil }
            sensorTime = FeverFridaDateTime(
                year: Int(bytes[offset]) | Int(bytes[offset + 1]) << 8,
                month: Int(bytes[offset + 2]),
                day: Int(bytes[offset + 3]),
                hour: Int(bytes[offset + 4]),
                minute: Int(bytes[offset + 5]),
                second: Int(bytes[offset + 6])
            )
            offset += 7
        }

        var temperatureType: UInt8?
        if flags & 0b0000_0100 != 0 {
            guard bytes.count > offset else { return nil }
            temperatureType = bytes[offset]
            offset += 1
        }
        guard bytes.count == offset else { return nil }

        let unit: FeverFridaTemperatureUnit = flags & 1 == 0 ? .celsius : .fahrenheit
        let celsius = unit == .celsius ? value : (value - 32) * 5 / 9
        return FeverFridaTemperatureSample(
            receivedAt: packet.capturedAt,
            celsius: celsius,
            transmittedValue: value,
            transmittedUnit: unit,
            sensorTime: sensorTime,
            temperatureType: temperatureType,
            characteristicUUID: uuid
        )
    }

    public static func battery(from packet: BLEPacket) -> FeverFridaBatteryLevel? {
        guard let uuid = packet.characteristicUUID,
              matches(uuid, shortUUIDs: ["2A19"]),
              let bytes = bytes(from: packet.payloadHex),
              bytes.count == 1,
              bytes[0] <= 100 else { return nil }
        return FeverFridaBatteryLevel(
            receivedAt: packet.capturedAt,
            percent: bytes[0],
            characteristicUUID: uuid
        )
    }

    private static func matches(_ uuid: String, shortUUIDs: Set<String>) -> Bool {
        let normalized = uuid.uppercased()
        return shortUUIDs.contains(normalized) || shortUUIDs.contains { normalized == "0000\($0)-0000-1000-8000-00805F9B34FB" }
    }

    private static func bytes(from hex: String) -> [UInt8]? {
        let parts = hex.split(whereSeparator: { $0.isWhitespace })
        guard !parts.isEmpty else { return [] }
        var result: [UInt8] = []
        result.reserveCapacity(parts.count)
        for part in parts {
            guard part.count == 2, let byte = UInt8(part, radix: 16) else { return nil }
            result.append(byte)
        }
        return result
    }

    private static func ieee11073Float(_ bytes: [UInt8]) -> Double? {
        guard bytes.count == 4 else { return nil }
        let rawMantissa = Int32(bytes[0]) | Int32(bytes[1]) << 8 | Int32(bytes[2]) << 16
        let mantissa = rawMantissa & 0x0080_0000 == 0 ? rawMantissa : rawMantissa | ~0x00FF_FFFF
        let exponent = Int(Int8(bitPattern: bytes[3]))

        // IEEE 11073 reserves the top mantissas for NaN and infinities.
        guard ![0x007F_FFFE, 0x007F_FFFF, 0x0080_0000, 0x0080_0001, 0x0080_0002]
            .contains(rawMantissa) else { return nil }
        return Double(mantissa) * pow(10, Double(exponent))
    }
}
