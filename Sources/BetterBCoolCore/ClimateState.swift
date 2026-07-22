// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum OperatingMode: String, Codable, CaseIterable, Sendable {
    case auto, cool, dry, fan, heat
}

public enum FanSpeed: String, Codable, CaseIterable, Sendable {
    case auto, low, medium, quiet
}

public struct ClimateState: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var powerEnabled: Bool
    public var operatingMode: OperatingMode
    public var fanSpeed: FanSpeed?
    public var roomTemperature: Double
    public var temperatureSetpoint: Double?
    public var breezeAwayEnabled: Bool
    public var ecoEnabled: Bool
    public var fullPowerEnabled: Bool
    public var horizontalSwingEnabled: Bool
    public var ionizerEnabled: Bool
    public var setbackEnabled: Bool
    public var sleepEnabled: Bool
    public var verticalSwingEnabled: Bool
}

public struct ClimatePatch: Codable, Equatable, Sendable {
    public var powerEnabled: Bool?
    public var operatingMode: OperatingMode?
    public var fanSpeed: FanSpeed?
    public var temperatureSetpoint: Double?
    public var horizontalSwingEnabled: Bool?
    public var verticalSwingEnabled: Bool?

    public init(
        powerEnabled: Bool? = nil,
        operatingMode: OperatingMode? = nil,
        fanSpeed: FanSpeed? = nil,
        temperatureSetpoint: Double? = nil,
        horizontalSwingEnabled: Bool? = nil,
        verticalSwingEnabled: Bool? = nil
    ) {
        self.powerEnabled = powerEnabled
        self.operatingMode = operatingMode
        self.fanSpeed = fanSpeed
        self.temperatureSetpoint = temperatureSetpoint
        self.horizontalSwingEnabled = horizontalSwingEnabled
        self.verticalSwingEnabled = verticalSwingEnabled
    }
}
