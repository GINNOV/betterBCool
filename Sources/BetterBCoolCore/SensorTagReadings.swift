// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct SensorVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SensorTagReadings: Equatable, Sendable {
    public var timestamp: Date?
    public var ambientTemperature: Double?
    public var objectTemperature: Double?
    public var relativeHumidity: Double?
    public var pressure: Double?
    public var acceleration: SensorVector?
    public var angularVelocity: SensorVector?
    public var magneticField: SensorVector?

    public init(
        timestamp: Date? = nil,
        ambientTemperature: Double? = nil,
        objectTemperature: Double? = nil,
        relativeHumidity: Double? = nil,
        pressure: Double? = nil,
        acceleration: SensorVector? = nil,
        angularVelocity: SensorVector? = nil,
        magneticField: SensorVector? = nil
    ) {
        self.timestamp = timestamp
        self.ambientTemperature = ambientTemperature
        self.objectTemperature = objectTemperature
        self.relativeHumidity = relativeHumidity
        self.pressure = pressure
        self.acceleration = acceleration
        self.angularVelocity = angularVelocity
        self.magneticField = magneticField
    }
}

public enum CC2541SensorDecoder {
    public static func infraredTemperature(_ data: Data) -> (ambient: Double, object: Double)? {
        guard data.count >= 4 else { return nil }
        let ambient = Double(unsigned16(data, at: 2)) / 128
        let rawObject = Double(signed16(data, at: 0)) * 0.00000015625
        let dieTemperature = ambient + 273.15
        let referenceTemperature = 298.15
        let delta = dieTemperature - referenceTemperature
        let sensitivity = 5.593e-14 * (1 + 1.75e-3 * delta - 1.678e-5 * delta * delta)
        let offset = -2.94e-5 - 5.7e-7 * delta + 4.63e-9 * delta * delta
        let adjustedObject = rawObject - offset
        let flux = adjustedObject + 13.4 * adjustedObject * adjustedObject
        let object = pow(pow(dieTemperature, 4) + flux / sensitivity, 0.25) - 273.15
        guard ambient.isFinite, object.isFinite else { return nil }
        return (ambient, object)
    }

    public static func humidity(_ data: Data) -> Double? {
        guard data.count >= 4 else { return nil }
        let raw = Double(unsigned16(data, at: 2) & ~0x0003)
        return -6 + 125 * raw / 65_535
    }

    public static func acceleration(_ data: Data) -> SensorVector? {
        guard data.count >= 3 else { return nil }
        return SensorVector(
            x: Double(Int8(bitPattern: data[0])) / 16,
            y: Double(Int8(bitPattern: data[1])) / 16,
            z: Double(Int8(bitPattern: data[2])) / 16
        )
    }

    public static func magneticField(_ data: Data) -> SensorVector? {
        guard data.count >= 6 else { return nil }
        let scale = 2_000.0 / 65_536.0
        return SensorVector(
            x: Double(signed16(data, at: 0)) * scale,
            y: Double(signed16(data, at: 2)) * scale,
            z: Double(signed16(data, at: 4)) * scale
        )
    }

    public static func angularVelocity(_ data: Data) -> SensorVector? {
        guard data.count >= 6 else { return nil }
        let scale = 500.0 / 65_536.0
        return SensorVector(
            x: Double(signed16(data, at: 0)) * scale,
            y: Double(signed16(data, at: 2)) * scale,
            z: Double(signed16(data, at: 4)) * scale
        )
    }

    public static func barometerCalibration(_ data: Data) -> [Int]? {
        guard data.count == 16 else { return nil }
        return stride(from: 0, to: 16, by: 2).map { offset in
            offset < 8 ? Int(unsigned16(data, at: offset)) : Int(signed16(data, at: offset))
        }
    }

    public static func pressure(_ data: Data, calibration: [Int]) -> Double? {
        guard data.count >= 4, calibration.count == 8 else { return nil }
        let rawTemperature = Double(signed16(data, at: 0))
        let rawPressure = Double(unsigned16(data, at: 2))
        let c = calibration.map(Double.init)
        let sensitivity = c[2]
            + c[3] * rawTemperature / pow(2, 17)
            + c[4] * rawTemperature * rawTemperature / pow(2, 34)
        let offset = c[5] * pow(2, 14)
            + c[6] * rawTemperature / pow(2, 3)
            + c[7] * rawTemperature * rawTemperature / pow(2, 19)
        let pascals = (sensitivity * rawPressure + offset) / pow(2, 14)
        let hectopascals = pascals / 100
        return hectopascals.isFinite ? hectopascals : nil
    }

    private static func unsigned16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func signed16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: unsigned16(data, at: offset))
    }
}
