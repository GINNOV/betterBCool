// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import FeverFridaKit

final class WT701DecoderTests: XCTestCase {
    private let capturedAt = Date(timeIntervalSince1970: 1_785_779_000)

    func testDecodesCapturedRealtimeFrame() throws {
        let packet = BLEPacket(
            capturedAt: capturedAt,
            direction: .indication,
            peripheralID: UUID(),
            serviceUUID: FeverFridaWT701UUID.realtimeService,
            characteristicUUID: FeverFridaWT701UUID.realtimeMeasurement,
            payloadHex: "A1 03 00 00 64 46 75 C9 7A 00 00 BF 6A"
        )
        let frame = try XCTUnwrap(FeverFridaWT701Decoder.realtimeFrame(from: packet))
        XCTAssertEqual(frame.deviceCounter, 929)
        XCTAssertEqual(frame.batteryPercent, 100)
        XCTAssertEqual(frame.primaryMilliCelsius, 30_022)
        XCTAssertEqual(frame.secondaryMilliCelsius, 31_433)
        XCTAssertEqual(frame.primaryCelsius, 30.022, accuracy: 0.000_001)
        XCTAssertEqual(frame.secondaryCelsius, 31.433, accuracy: 0.000_001)
        XCTAssertEqual(frame.reserved, 0)
        XCTAssertEqual(frame.checksum, 0x6ABF)
        XCTAssertEqual(FeverFridaWT701Decoder.temperature(from: packet)?.celsius, 30.022)
        XCTAssertEqual(FeverFridaWT701Decoder.battery(from: packet)?.percent, 100)
    }

    func testRejectsBadChecksumWrongUUIDAndInvalidBattery() {
        func packet(_ payload: String, uuid: String = FeverFridaWT701UUID.realtimeMeasurement) -> BLEPacket {
            BLEPacket(direction: .indication, peripheralID: UUID(), characteristicUUID: uuid, payloadHex: payload)
        }
        XCTAssertNil(FeverFridaWT701Decoder.realtimeFrame(from: packet("A1 03 00 00 64 46 75 C9 7A 00 00 BE 6A")))
        XCTAssertNil(FeverFridaWT701Decoder.realtimeFrame(from: packet("A1 03 00 00 64 46 75 C9 7A 00 00 BF 6A", uuid: "2A1C")))

        let invalidBattery = BLEPacket(
            direction: .read,
            peripheralID: UUID(),
            characteristicUUID: FeverFridaWT701UUID.batteryLevel,
            payloadHex: "65"
        )
        XCTAssertNil(FeverFridaWT701Decoder.battery(from: invalidBattery))
    }

    func testChecksumMatchesCapturedFrame() {
        XCTAssertEqual(
            FeverFridaWT701Decoder.crc16CCITTFalse([0xA1, 0x03, 0, 0, 0x64, 0x46, 0x75, 0xC9, 0x7A, 0, 0]),
            0x6ABF
        )
    }

    func testDedicatedBatteryCharacteristic() {
        let packet = BLEPacket(
            direction: .read,
            peripheralID: UUID(),
            characteristicUUID: FeverFridaWT701UUID.batteryLevel.lowercased(),
            payloadHex: "64"
        )
        XCTAssertEqual(FeverFridaWT701Decoder.battery(from: packet)?.percent, 100)
    }

    func testDecodesEveryFrameInControlledSequence() throws {
        let payloads = [
            "7E 08 00 00 64 55 74 40 75 00 00 01 FE",
            "82 08 00 00 64 58 74 40 75 00 00 B3 71",
            "84 08 00 00 64 58 74 4B 75 00 00 58 9E",
            "88 08 00 00 64 57 74 58 75 00 00 E9 28",
            "8C 08 00 00 64 5A 74 69 75 00 00 B0 6D",
            "91 08 00 00 64 56 74 78 75 00 00 FD 75",
            "95 08 00 00 64 54 74 85 75 00 00 31 09",
            "99 08 00 00 64 50 74 8C 75 00 00 2E 0F",
            "9D 08 00 00 64 51 74 97 75 00 00 71 1E",
            "A1 08 00 00 64 53 74 A5 75 00 00 3E 58"
        ]
        let frames = payloads.compactMap {
            FeverFridaWT701Decoder.realtimeFrame(from: BLEPacket(
                direction: .read,
                peripheralID: UUID(),
                characteristicUUID: FeverFridaWT701UUID.realtimeMeasurement,
                payloadHex: $0
            ))
        }
        XCTAssertEqual(frames.count, payloads.count)
        XCTAssertEqual(frames.first?.deviceCounter, 2_174)
        XCTAssertEqual(frames.last?.deviceCounter, 2_209)
        XCTAssertEqual(frames.first?.secondaryCelsius, 30.016)
        XCTAssertEqual(frames.last?.secondaryCelsius, 30.117)
        XCTAssertTrue(frames.allSatisfy { $0.batteryPercent == 100 && $0.reserved == 0 })
    }
}
