// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import FeverFridaKit

final class CaptureExportTests: XCTestCase {
    func testHexEncodingPreservesLeadingZeros() {
        XCTAssertEqual(Data([0x00, 0x09, 0xA0, 0xFF]).feverFridaHex, "00 09 A0 FF")
    }

    func testPacketJSONLinesIsStableAndOneRecordPerLine() throws {
        let packet = BLEPacket(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            capturedAt: Date(timeIntervalSince1970: 0),
            direction: .notification,
            peripheralID: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            serviceUUID: "FFF0",
            characteristicUUID: "FFF1",
            payloadHex: "01 02"
        )

        let data = try FeverFridaCaptureExport.jsonLines([packet])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(text.split(separator: "\n").count, 1)
        XCTAssertTrue(text.contains("\"payloadHex\":\"01 02\""))
    }
}
