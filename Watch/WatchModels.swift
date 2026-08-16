// SPDX-License-Identifier: Apache-2.0

import Foundation

// Keep these Codable shapes in lockstep with BetterBCoolCore.WatchModels.swift.
// The watch target deliberately has no Swift package dependency so the iPhone and
// watch products can be built independently in Xcode.
struct WatchRequest: Codable, Equatable {
    enum Action: String, Codable, Equatable {
        case refresh
        case togglePower
        case setTemperature
        case setSchedulesEnabled
    }

    let action: Action
    let temperature: Double?
    let schedulesEnabled: Bool?

    static let refresh = WatchRequest(action: .refresh, temperature: nil, schedulesEnabled: nil)
    static let togglePower = WatchRequest(action: .togglePower, temperature: nil, schedulesEnabled: nil)

    static func setTemperature(_ temperature: Double) -> WatchRequest {
        .init(action: .setTemperature, temperature: temperature, schedulesEnabled: nil)
    }

    static func setSchedulesEnabled(_ enabled: Bool) -> WatchRequest {
        .init(action: .setSchedulesEnabled, temperature: nil, schedulesEnabled: enabled)
    }
}

enum OperatingMode: String, Codable {
    case auto, cool, dry, fan, heat
}

enum FanSpeed: String, Codable {
    case auto, quiet, low, medium, high, turbo
}

struct ClimateState: Codable, Equatable {
    var timestamp: Date
    var powerEnabled: Bool
    var operatingMode: OperatingMode
    var fanSpeed: FanSpeed?
    var roomTemperature: Double?
    var temperatureSetpoint: Double?
    var breezeAwayEnabled: Bool
    var ecoEnabled: Bool
    var fullPowerEnabled: Bool
    var horizontalSwingEnabled: Bool
    var ionizerEnabled: Bool
    var setbackEnabled: Bool
    var sleepEnabled: Bool
    var verticalSwingEnabled: Bool
}

struct WatchScheduleSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let isEnabled: Bool
    let startMinutes: Int
    let stepCount: Int
}

struct WatchSnapshot: Codable, Equatable {
    let deviceName: String?
    let state: ClimateState?
    let canWrite: Bool
    let minimumSetpoint: Double?
    let maximumSetpoint: Double?
    let setpointStep: Double?
    let schedules: [WatchScheduleSummary]
    let nextScheduleDate: Date?
    let errorMessage: String?

    var enabledScheduleCount: Int { schedules.filter(\.isEnabled).count }
    var allSchedulesEnabled: Bool { !schedules.isEmpty && schedules.allSatisfy(\.isEnabled) }
}
