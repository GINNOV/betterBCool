// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import BetterBCoolCore

final class SensorTagReadingsTests: XCTestCase {
    func testEnvironmentalAndMotionConversions() throws {
        let temperature = try XCTUnwrap(CC2541SensorDecoder.infraredTemperature(Data([0, 0, 0x80, 0x0C])))
        XCTAssertEqual(temperature.ambient, 25, accuracy: 0.001)

        let humidity = try XCTUnwrap(CC2541SensorDecoder.humidity(Data([0, 0, 0, 0x80])))
        XCTAssertEqual(humidity, 56.5, accuracy: 0.1)

        let acceleration = try XCTUnwrap(CC2541SensorDecoder.acceleration(Data([0x10, 0xF0, 0x08])))
        XCTAssertEqual(acceleration, SensorVector(x: 1, y: -1, z: 0.5))

        let magnetic = try XCTUnwrap(CC2541SensorDecoder.magneticField(Data([0, 4, 0, 0xFC, 0, 0])))
        XCTAssertEqual(magnetic.x, 31.25, accuracy: 0.001)
        XCTAssertEqual(magnetic.y, -31.25, accuracy: 0.001)

        let angular = try XCTUnwrap(CC2541SensorDecoder.angularVelocity(Data([0, 0x20, 0, 0, 0, 0])))
        XCTAssertEqual(angular.x, 62.5, accuracy: 0.001)
    }

    func testBarometerCalibrationSignedness() throws {
        let bytes: [UInt8] = [1, 0, 2, 0, 3, 0, 4, 0, 0xFF, 0xFF, 6, 0, 7, 0, 8, 0]
        XCTAssertEqual(CC2541SensorDecoder.barometerCalibration(Data(bytes)), [1, 2, 3, 4, -1, 6, 7, 8])
    }

    func testMalformedPayloadsAreRejected() {
        XCTAssertNil(CC2541SensorDecoder.infraredTemperature(Data([0])))
        XCTAssertNil(CC2541SensorDecoder.humidity(Data([0, 1])))
        XCTAssertNil(CC2541SensorDecoder.pressure(Data([0, 1, 2, 3]), calibration: []))
    }
}
