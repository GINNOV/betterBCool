// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Live adapter for newer HomeCom/Matter RAC units backed by Bosch Bacon MQTT shadows.
public actor BaconClimateService: ClimateService {
    private let tokenProvider: any AccessTokenProviding
    private let deviceID: String
    private let region: BaconRegion
    private let deviceName: String

    public init(
        tokenProvider: any AccessTokenProviding,
        deviceID: String,
        region: BaconRegion,
        deviceName: String = "Bosch Climate"
    ) {
        self.tokenProvider = tokenProvider
        self.deviceID = deviceID
        self.region = region
        self.deviceName = deviceName
    }

    public func devices() async throws -> [ClimateDevice] {
        [ClimateDevice(id: deviceID, name: deviceName)]
    }

    public func capabilities(for requestedID: String) async throws -> ClimateCapabilities {
        try verify(requestedID)
        return ClimateCapabilities(
            canWrite: true,
            operatingModes: Set(OperatingMode.allCases),
            fanSpeeds: Set(FanSpeed.allCases),
            minimumSetpoint: 16,
            maximumSetpoint: 30,
            setpointStep: 0.5
        )
    }

    public func state(for requestedID: String) async throws -> ClimateState {
        try verify(requestedID)
        let shadow = try await client().readShadow(deviceID: deviceID)
        return try Self.climateState(from: shadow)
    }

    public func apply(_ patch: ClimatePatch, to requestedID: String) async throws -> ClimateState {
        try verify(requestedID)
        try await capabilities(for: requestedID).validate(patch)
        var desired: [String: JSONValue] = [:]
        if let value = patch.powerEnabled { desired["powerEnabled"] = .bool(value) }
        if let value = patch.operatingMode { desired["opMode"] = .string(value.rawValue) }
        if let value = patch.fanSpeed { desired["fanSpeed"] = .string(value.rawValue) }
        if let value = patch.temperatureSetpoint { desired["tempSetpoint"] = .number(value) }
        if let value = patch.ecoEnabled { desired["ecoEnabled"] = .bool(value) }
        if let value = patch.sleepEnabled { desired["sleepEnabled"] = .bool(value) }
        if let value = patch.horizontalSwingEnabled { desired["hSwingEnabled"] = .bool(value) }
        if let value = patch.verticalSwingEnabled { desired["vSwingEnabled"] = .bool(value) }
        guard !desired.isEmpty else { return try await state(for: requestedID) }

        let shadow = try await client().updateDesired(deviceID: deviceID, desired: desired)
        return try Self.climateState(from: shadow)
    }

    private func client() async throws -> BaconMQTTClient {
        try BaconMQTTClient(accessToken: try await tokenProvider.accessToken(), region: region)
    }

    private func verify(_ requestedID: String) throws {
        guard requestedID == deviceID else { throw ClimateServiceError.deviceNotFound }
    }

    static func climateState(from shadow: BaconShadow) throws -> ClimateState {
        guard case .object(let values) = shadow.reported,
              let power = values["powerEnabled"]?.boolValue,
              let modeValue = values["opMode"]?.stringValue,
              let mode = OperatingMode(rawValue: modeValue) else {
            throw BaconMQTTError.invalidShadow
        }
        return ClimateState(
            timestamp: Date(),
            powerEnabled: power,
            operatingMode: mode,
            fanSpeed: values["fanSpeed"]?.stringValue.flatMap(FanSpeed.init(rawValue:)),
            roomTemperature: nil,
            temperatureSetpoint: values["tempSetpoint"]?.numberValue,
            breezeAwayEnabled: values["breezeAwayEnabled"]?.boolValue ?? false,
            ecoEnabled: values["ecoEnabled"]?.boolValue ?? false,
            fullPowerEnabled: values["fullPowerEnabled"]?.boolValue ?? false,
            horizontalSwingEnabled: values["hSwingEnabled"]?.boolValue ?? false,
            ionizerEnabled: values["ionizerEnabled"]?.boolValue ?? false,
            setbackEnabled: values["setbackEnabled"]?.boolValue ?? false,
            sleepEnabled: values["sleepEnabled"]?.boolValue ?? false,
            verticalSwingEnabled: values["vSwingEnabled"]?.boolValue ?? false
        )
    }
}

private extension JSONValue {
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
}
