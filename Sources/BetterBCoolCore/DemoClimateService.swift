// SPDX-License-Identifier: Apache-2.0

import Foundation

public actor DemoClimateService: ClimateService {
    private let device = ClimateDevice(id: "demo", name: "Living Room")
    private var currentState = ClimateState(
        timestamp: Date(), powerEnabled: true, operatingMode: .cool, fanSpeed: .auto,
        roomTemperature: 28.5, temperatureSetpoint: 25,
        breezeAwayEnabled: false, ecoEnabled: false, fullPowerEnabled: false,
        horizontalSwingEnabled: false, ionizerEnabled: false, setbackEnabled: false,
        sleepEnabled: false, verticalSwingEnabled: false
    )

    public init() {}
    public func devices() async throws -> [ClimateDevice] { [device] }
    public func capabilities(for deviceID: String) async throws -> ClimateCapabilities {
        guard deviceID == device.id else { throw ClimateServiceError.deviceNotFound }
        return .init(
            canWrite: false, operatingModes: Set(OperatingMode.allCases),
            fanSpeeds: Set(FanSpeed.allCases), minimumSetpoint: 15,
            maximumSetpoint: 32.5, setpointStep: 0.5
        )
    }
    public func state(for deviceID: String) async throws -> ClimateState {
        guard deviceID == device.id else { throw ClimateServiceError.deviceNotFound }
        return currentState
    }
    public func apply(_ patch: ClimatePatch, to deviceID: String) async throws -> ClimateState {
        throw ClimateServiceError.readOnly
    }
}
