// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import BetterBCoolCore

final class WatchModelsTests: XCTestCase {
    func testTemperatureRequestRoundTripsThroughCodable() throws {
        let request = WatchRequest.setTemperature(24.5)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(WatchRequest.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.action, .setTemperature)
        XCTAssertEqual(decoded.temperature, 24.5)
    }

    func testPowerRequestCarriesExplicitDesiredState() throws {
        let request = WatchRequest.setPower(false)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(WatchRequest.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.action, .setPower)
        XCTAssertEqual(decoded.powerEnabled, false)
    }

    func testSnapshotReportsScheduleGroupState() {
        let enabled = WatchScheduleSummary(
            id: UUID(),
            name: "Night",
            isEnabled: true,
            startMinutes: 22 * 60,
            stepCount: 2
        )
        let disabled = WatchScheduleSummary(
            id: UUID(),
            name: "Morning",
            isEnabled: false,
            startMinutes: 7 * 60,
            stepCount: 1
        )

        let snapshot = WatchSnapshot(schedules: [enabled, disabled])

        XCTAssertEqual(snapshot.enabledScheduleCount, 1)
        XCTAssertFalse(snapshot.allSchedulesEnabled)
    }
}
