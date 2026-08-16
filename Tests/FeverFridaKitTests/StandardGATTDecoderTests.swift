// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import FeverFridaKit

final class StandardGATTDecoderTests: XCTestCase {
    func testDecodesStandardCelsiusTemperature() throws {
        let packet = BLEPacket(
            capturedAt: Date(timeIntervalSince1970: 123),
            direction: .indication,
            peripheralID: UUID(),
            characteristicUUID: "2A1C",
            payloadHex: "00 77 0E 00 FE"
        )

        let sample = try XCTUnwrap(FeverFridaStandardGATTDecoder.temperature(from: packet))
        XCTAssertEqual(sample.celsius, 37.03, accuracy: 0.0001)
        XCTAssertEqual(sample.transmittedUnit, .celsius)
        XCTAssertNil(sample.sensorTime)
    }

    func testDecodesStandardFahrenheitTimestampAndType() throws {
        let packet = BLEPacket(
            direction: .notification,
            peripheralID: UUID(),
            characteristicUUID: "00002A1E-0000-1000-8000-00805F9B34FB",
            payloadHex: "07 DC 00 00 00 E9 07 08 03 14 15 16 01"
        )

        let sample = try XCTUnwrap(FeverFridaStandardGATTDecoder.temperature(from: packet))
        XCTAssertEqual(sample.transmittedValue, 220)
        XCTAssertEqual(sample.celsius, 104.444444, accuracy: 0.0001)
        XCTAssertEqual(sample.sensorTime, FeverFridaDateTime(year: 2025, month: 8, day: 3, hour: 20, minute: 21, second: 22))
        XCTAssertEqual(sample.temperatureType, 1)
    }

    func testDecodesStandardBatteryLevel() throws {
        let packet = BLEPacket(
            direction: .read,
            peripheralID: UUID(),
            characteristicUUID: "2A19",
            payloadHex: "4B"
        )
        XCTAssertEqual(FeverFridaStandardGATTDecoder.battery(from: packet)?.percent, 75)
    }

    func testRejectsProprietaryAndMalformedPackets() {
        let proprietary = BLEPacket(
            direction: .notification,
            peripheralID: UUID(),
            characteristicUUID: "FFF1",
            payloadHex: "00 77 0E 00 FF"
        )
        let invalidBattery = BLEPacket(
            direction: .read,
            peripheralID: UUID(),
            characteristicUUID: "2A19",
            payloadHex: "FF"
        )
        XCTAssertNil(FeverFridaStandardGATTDecoder.temperature(from: proprietary))
        XCTAssertNil(FeverFridaStandardGATTDecoder.battery(from: invalidBattery))
    }
}
