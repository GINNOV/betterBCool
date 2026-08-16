// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension Notification.Name {
    static let betterBCoolSchedulesDidChange = Notification.Name("betterBCool.schedulesDidChange")
    static let betterBCoolClimateStateDidChange = Notification.Name("betterBCool.climateStateDidChange")
}

/// Commands exchanged between the Apple Watch companion and the iPhone app.
/// The iPhone remains the authenticated Bosch client; the watch only sends these
/// narrow, user-initiated requests.
public struct WatchRequest: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Equatable, Sendable {
        case refresh
        case togglePower
        case setPower
        case setTemperature
        case setSchedulesEnabled
    }

    public let action: Action
    public let powerEnabled: Bool?
    public let temperature: Double?
    public let schedulesEnabled: Bool?

    public init(
        action: Action,
        powerEnabled: Bool? = nil,
        temperature: Double? = nil,
        schedulesEnabled: Bool? = nil
    ) {
        self.action = action
        self.powerEnabled = powerEnabled
        self.temperature = temperature
        self.schedulesEnabled = schedulesEnabled
    }

    public static let refresh = WatchRequest(action: .refresh)
    public static let togglePower = WatchRequest(action: .togglePower)

    public static func setPower(_ enabled: Bool) -> WatchRequest {
        .init(action: .setPower, powerEnabled: enabled)
    }

    public static func setTemperature(_ temperature: Double) -> WatchRequest {
        .init(action: .setTemperature, temperature: temperature)
    }

    public static func setSchedulesEnabled(_ enabled: Bool) -> WatchRequest {
        .init(action: .setSchedulesEnabled, schedulesEnabled: enabled)
    }
}

public struct WatchScheduleSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let isEnabled: Bool
    public let startMinutes: Int
    public let stepCount: Int

    public init(schedule: ClimateSchedule) {
        id = schedule.id
        name = schedule.name
        isEnabled = schedule.isEnabled
        startMinutes = schedule.startMinutes
        stepCount = schedule.steps.count
    }

    public init(
        id: UUID,
        name: String,
        isEnabled: Bool,
        startMinutes: Int,
        stepCount: Int
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.startMinutes = startMinutes
        self.stepCount = stepCount
    }
}

public struct WatchSnapshot: Codable, Equatable, Sendable {
    public let deviceName: String?
    public let state: ClimateState?
    public let canWrite: Bool
    public let minimumSetpoint: Double?
    public let maximumSetpoint: Double?
    public let setpointStep: Double?
    public let schedules: [WatchScheduleSummary]
    public let nextScheduleDate: Date?
    public let errorMessage: String?

    public init(
        deviceName: String? = nil,
        state: ClimateState? = nil,
        canWrite: Bool = false,
        minimumSetpoint: Double? = nil,
        maximumSetpoint: Double? = nil,
        setpointStep: Double? = nil,
        schedules: [WatchScheduleSummary] = [],
        nextScheduleDate: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.deviceName = deviceName
        self.state = state
        self.canWrite = canWrite
        self.minimumSetpoint = minimumSetpoint
        self.maximumSetpoint = maximumSetpoint
        self.setpointStep = setpointStep
        self.schedules = schedules
        self.nextScheduleDate = nextScheduleDate
        self.errorMessage = errorMessage
    }

    public var enabledScheduleCount: Int {
        schedules.filter(\.isEnabled).count
    }

    public var allSchedulesEnabled: Bool {
        !schedules.isEmpty && schedules.allSatisfy(\.isEnabled)
    }
}
