// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Live RAC adapter for the PointT resource API.
///
/// It reads individual resources so each value can be validated independently. Writes are
/// limited to the controls represented by `ClimatePatch` and are followed by a fresh read.
public actor PointTClimateService: ClimateService {
    private let api: PointTAPI
    private let deviceID: String
    private let deviceName: String

    public init(api: PointTAPI, deviceID: String, deviceName: String = "Bosch Climate") {
        self.api = api
        self.deviceID = deviceID
        self.deviceName = deviceName
    }

    public func devices() async throws -> [ClimateDevice] {
        [ClimateDevice(id: deviceID, name: deviceName)]
    }

    public func capabilities(for requestedID: String) async throws -> ClimateCapabilities {
        try verify(requestedID)
        return .init(
            canWrite: true,
            operatingModes: Set(OperatingMode.allCases),
            fanSpeeds: Set(FanSpeed.allCases),
            minimumSetpoint: 15,
            maximumSetpoint: 32.5,
            setpointStep: 0.5
        )
    }

    public func state(for requestedID: String) async throws -> ClimateState {
        try verify(requestedID)
        async let control = value(["airConditioning", "acControl"])
        async let mode = value(["airConditioning", "operationMode"])
        async let fan = value(["airConditioning", "fanSpeed"])
        async let room = value(["airConditioning", "roomTemperature"])
        async let setpoint = value(["airConditioning", "temperatureSetpoint"])
        async let eco = optionalValue(["airConditioning", "ecoMode"])
        async let sleep = optionalValue(["airConditioning", "sleepMode"])
        async let vertical = optionalValue(["airConditioning", "airFlowVertical"])
        async let horizontal = optionalValue(["airConditioning", "airFlowHorizontal"])

        let rawMode = try await mode.stringValue
        guard let operatingMode = OperatingMode(pointTValue: rawMode),
              let roomTemperature = try await room.numberValue else {
            throw PointTError.invalidPayload
        }

        return ClimateState(
            timestamp: Date(),
            powerEnabled: try await control.isEnabled,
            operatingMode: operatingMode,
            fanSpeed: FanSpeed(rawValue: try await fan.stringValue ?? ""),
            roomTemperature: roomTemperature,
            temperatureSetpoint: try await setpoint.numberValue,
            breezeAwayEnabled: false,
            ecoEnabled: await eco.isEnabled,
            fullPowerEnabled: false,
            horizontalSwingEnabled: await horizontal.isEnabled,
            ionizerEnabled: false,
            setbackEnabled: false,
            sleepEnabled: await sleep.isEnabled,
            verticalSwingEnabled: await vertical.isEnabled
        )
    }

    public func apply(_ patch: ClimatePatch, to requestedID: String) async throws -> ClimateState {
        try verify(requestedID)
        let capabilities = try await capabilities(for: requestedID)
        try capabilities.validate(patch)

        if let power = patch.powerEnabled {
            try await set(["airConditioning", "acControl"], .string(power ? "on" : "off"))
        }
        if let mode = patch.operatingMode {
            try await set(["airConditioning", "operationMode"], .string(mode.pointTValue))
        }
        if let fan = patch.fanSpeed {
            try await set(["airConditioning", "fanSpeed"], .string(fan.rawValue))
        }
        if let temperature = patch.temperatureSetpoint {
            try await set(["airConditioning", "temperatureSetpoint"], .number(temperature))
        }
        if let enabled = patch.verticalSwingEnabled {
            try await set(["airConditioning", "airFlowVertical"], .string(enabled ? "on" : "off"))
        }
        if let enabled = patch.horizontalSwingEnabled {
            try await set(["airConditioning", "airFlowHorizontal"], .string(enabled ? "on" : "off"))
        }
        return try await state(for: requestedID)
    }

    private func value(_ path: [String]) async throws -> JSONValue {
        try await api.resource(deviceID: deviceID, path: path).resourceValue
    }

    private func optionalValue(_ path: [String]) async -> JSONValue {
        (try? await value(path)) ?? .null
    }

    private func set(_ path: [String], _ value: JSONValue) async throws {
        try await api.setResource(deviceID: deviceID, path: path, value: value)
    }

    private func verify(_ requestedID: String) throws {
        guard requestedID == deviceID else { throw ClimateServiceError.deviceNotFound }
    }
}

private extension JSONValue {
    var resourceValue: JSONValue {
        if case .object(let object) = self, let value = object["value"] { return value }
        return self
    }
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    var isEnabled: Bool {
        switch self {
        case .bool(let value): value
        case .string(let value): ["on", "enabled", "true"].contains(value.lowercased())
        default: false
        }
    }
}

private extension OperatingMode {
    init?(pointTValue: String?) {
        guard let pointTValue else { return nil }
        self.init(rawValue: pointTValue == "fanOnly" ? "fan" : pointTValue)
    }
    var pointTValue: String { self == .fan ? "fanOnly" : rawValue }
}
