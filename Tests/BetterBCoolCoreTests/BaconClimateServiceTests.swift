// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import BetterBCoolCore

final class BaconClimateServiceTests: XCTestCase {
    func testMapsVerifiedShadowFieldsWithoutInventingRoomTemperature() throws {
        let shadow = BaconShadow(
            reported: .object([
                "powerEnabled": .bool(true),
                "opMode": .string("cool"),
                "fanSpeed": .string("high"),
                "tempSetpoint": .number(24),
                "hSwingEnabled": .bool(true),
                "vSwingEnabled": .bool(false)
            ]),
            desired: .object([:])
        )

        let state = try BaconClimateService.climateState(from: shadow)

        XCTAssertTrue(state.powerEnabled)
        XCTAssertEqual(state.operatingMode, .cool)
        XCTAssertEqual(state.fanSpeed, .high)
        XCTAssertEqual(state.temperatureSetpoint, 24)
        XCTAssertNil(state.roomTemperature)
        XCTAssertTrue(state.horizontalSwingEnabled)
        XCTAssertFalse(state.verticalSwingEnabled)
    }
}
