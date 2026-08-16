// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import BetterBCoolCore

final class BodyTemperatureSnapshotTests: XCTestCase {
    func testActivatesForFreshElevatedTemperatureWithEstablishedBaseline() throws {
        let now = Date()
        let snapshot = BodyTemperatureSnapshot(
            sampleID: UUID(),
            wristTemperatureCelsius: 36.2,
            baselineCelsius: 35.5,
            baselineSampleCount: 7,
            measuredAt: now.addingTimeInterval(-3_600),
            sourceName: "Apple Watch"
        )

        XCTAssertTrue(snapshot.shouldActivateCooling(threshold: 0.5, at: now))
        let deviation = try XCTUnwrap(snapshot.deviationCelsius)
        XCTAssertEqual(deviation, 0.7, accuracy: 0.001)
    }

    func testRejectsStaleTemperature() {
        let now = Date()
        let snapshot = BodyTemperatureSnapshot(
            sampleID: UUID(),
            wristTemperatureCelsius: 36.5,
            baselineCelsius: 35.5,
            baselineSampleCount: 7,
            measuredAt: now.addingTimeInterval(-20 * 60 * 60),
            sourceName: "Apple Watch"
        )

        XCTAssertFalse(snapshot.shouldActivateCooling(threshold: 0.5, at: now))
    }

    func testRequiresPersonalBaseline() {
        let snapshot = BodyTemperatureSnapshot(
            sampleID: UUID(),
            wristTemperatureCelsius: 36.5,
            baselineCelsius: 35.5,
            baselineSampleCount: 2,
            measuredAt: Date(),
            sourceName: "Apple Watch"
        )

        XCTAssertFalse(snapshot.shouldActivateCooling(threshold: 0.5))
    }
}
