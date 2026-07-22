// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import BetterBCoolCore

final class BaseTelemetryCSVTests: XCTestCase {
    func testDecodesObservedRow() throws {
        let csv = """
        timestamp,breezeAwayEnabled,ecoEnabled,fanSpeed,fullPowerEnabled,hSwingEnabled,ionizerEnabled,offTimestamp [sec],onTimestamp [sec],opMode,powerEnabled,roomTemperature [degC],setbackEnabled,sleepEnabled,tempSetpoint [degC],vSwingEnabled
        2026-07-22T13:05:40.000Z,false,false,auto,false,false,false,0,0,cool,true,28.5,false,false,25,false
        """

        let states = try BaseTelemetryCSV.decode(csv)

        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].operatingMode, .cool)
        XCTAssertEqual(states[0].fanSpeed, .auto)
        XCTAssertEqual(states[0].roomTemperature, 28.5)
        XCTAssertEqual(states[0].temperatureSetpoint, 25)
        XCTAssertTrue(states[0].powerEnabled)
    }

    func testRejectsUnknownMode() {
        let csv = """
        timestamp,breezeAwayEnabled,ecoEnabled,fanSpeed,fullPowerEnabled,hSwingEnabled,ionizerEnabled,offTimestamp [sec],onTimestamp [sec],opMode,powerEnabled,roomTemperature [degC],setbackEnabled,sleepEnabled,tempSetpoint [degC],vSwingEnabled
        2026-07-22T13:05:40.000Z,false,false,auto,false,false,false,0,0,unsupported,true,28.5,false,false,25,false
        """

        XCTAssertThrowsError(try BaseTelemetryCSV.decode(csv)) {
            XCTAssertEqual($0 as? TelemetryImportError, .invalidRow(2))
        }
    }

    func testCapabilitiesRejectUnsafeSetpoint() throws {
        let capabilities = ClimateCapabilities(
            canWrite: true,
            operatingModes: [.cool],
            fanSpeeds: [.auto],
            minimumSetpoint: 16,
            maximumSetpoint: 30,
            setpointStep: 0.5
        )

        XCTAssertThrowsError(try capabilities.validate(.init(temperatureSetpoint: 30.25)))
        XCTAssertNoThrow(try capabilities.validate(.init(temperatureSetpoint: 24.5)))
    }

    func testBaconRangeAcceptsHalfDegreeSetpoint() throws {
        let capabilities = ClimateCapabilities(
            canWrite: true,
            operatingModes: Set(OperatingMode.allCases),
            fanSpeeds: Set(FanSpeed.allCases),
            minimumSetpoint: 16,
            maximumSetpoint: 30,
            setpointStep: 0.5
        )

        XCTAssertNoThrow(try capabilities.validate(.init(temperatureSetpoint: 24.5)))
    }
}

final class DemoClimateServiceTests: XCTestCase {
    func testDemoControlsUpdateState() async throws {
        let service = DemoClimateService()
        let device = try await service.devices().first!

        let updated = try await service.apply(
            .init(powerEnabled: false, operatingMode: .dry, temperatureSetpoint: 24.5),
            to: device.id
        )

        XCTAssertFalse(updated.powerEnabled)
        XCTAssertEqual(updated.operatingMode, .dry)
        XCTAssertEqual(updated.temperatureSetpoint, 24.5)
        XCTAssertEqual(updated.roomTemperature, 28.5)
    }
}
