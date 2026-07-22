// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ScheduleWeekday: Int, Codable, CaseIterable, Hashable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public var shortName: String {
        switch self {
        case .sunday: "Sun"
        case .monday: "Mon"
        case .tuesday: "Tue"
        case .wednesday: "Wed"
        case .thursday: "Thu"
        case .friday: "Fri"
        case .saturday: "Sat"
        }
    }
}

public struct ClimateScheduleStep: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var patch: ClimatePatch
    /// How long this state lasts before the next step. `nil` keeps it active.
    public var durationMinutes: Int?

    public init(
        id: UUID = UUID(),
        name: String,
        patch: ClimatePatch,
        durationMinutes: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.patch = patch
        self.durationMinutes = durationMinutes
    }
}

public struct ClimateSchedule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Minutes after local midnight.
    public var startMinutes: Int
    public var weekdays: Set<ScheduleWeekday>
    public var steps: [ClimateScheduleStep]

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        startMinutes: Int,
        weekdays: Set<ScheduleWeekday>,
        steps: [ClimateScheduleStep]
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.startMinutes = min(max(startMinutes, 0), 1_439)
        self.weekdays = weekdays
        self.steps = steps
    }
}

public struct ClimateScheduleEvent: Identifiable, Equatable, Sendable {
    public var id: String { "\(scheduleID.uuidString)-\(stepID.uuidString)-\(date.timeIntervalSince1970)" }
    public let scheduleID: UUID
    public let stepID: UUID
    public let date: Date
    public let patch: ClimatePatch

    public init(scheduleID: UUID, stepID: UUID, date: Date, patch: ClimatePatch) {
        self.scheduleID = scheduleID
        self.stepID = stepID
        self.date = date
        self.patch = patch
    }
}

public enum ClimateScheduleTimeline {
    /// The last transition that should have taken effect by `date`.
    public static func currentEvent(
        in schedules: [ClimateSchedule],
        at date: Date,
        calendar: Calendar = .current
    ) -> ClimateScheduleEvent? {
        events(in: schedules, around: date, calendar: calendar)
            .filter { $0.date <= date }
            .max { $0.date < $1.date }
    }

    /// The next transition, including the beginning of a routine or one of its later steps.
    public static func nextEvent(
        in schedules: [ClimateSchedule],
        after date: Date,
        calendar: Calendar = .current
    ) -> ClimateScheduleEvent? {
        events(in: schedules, around: date, calendar: calendar)
            .filter { $0.date > date }
            .min { $0.date < $1.date }
    }

    private static func events(
        in schedules: [ClimateSchedule],
        around date: Date,
        calendar: Calendar
    ) -> [ClimateScheduleEvent] {
        guard let firstDay = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: date)) else {
            return []
        }

        return schedules.filter(\.isEnabled).flatMap { schedule in
            (0...15).flatMap { dayOffset -> [ClimateScheduleEvent] in
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay),
                      let weekdayValue = calendar.dateComponents([.weekday], from: day).weekday,
                      let weekday = ScheduleWeekday(rawValue: weekdayValue),
                      schedule.weekdays.contains(weekday),
                      let start = calendar.date(byAdding: .minute, value: schedule.startMinutes, to: day) else {
                    return []
                }

                var offset = 0
                var result: [ClimateScheduleEvent] = []
                for step in schedule.steps {
                    guard let eventDate = calendar.date(byAdding: .minute, value: offset, to: start) else { break }
                    result.append(.init(scheduleID: schedule.id, stepID: step.id, date: eventDate, patch: step.patch))
                    guard let duration = step.durationMinutes, duration > 0 else { break }
                    offset += duration
                }
                return result
            }
        }
    }
}

public extension ClimateSchedule {
    static func nightComfortTemplate(calendar: Calendar = .current, now: Date = Date()) -> ClimateSchedule {
        let start = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now) ?? now
        let components = calendar.dateComponents([.hour, .minute], from: start)
        return ClimateSchedule(
            name: "Night comfort",
            startMinutes: (components.hour ?? 22) * 60 + (components.minute ?? 0),
            weekdays: Set(ScheduleWeekday.allCases),
            steps: [
                .init(
                    name: "Cool down",
                    patch: .init(powerEnabled: true, operatingMode: .cool, fanSpeed: .medium, temperatureSetpoint: 24),
                    durationMinutes: 120
                ),
                .init(
                    name: "Silent sleep",
                    patch: .init(powerEnabled: true, operatingMode: .cool, fanSpeed: .quiet, temperatureSetpoint: 25),
                    durationMinutes: 240
                ),
                .init(name: "Pause", patch: .init(powerEnabled: false), durationMinutes: 30),
                .init(
                    name: "Resume silent",
                    patch: .init(powerEnabled: true, operatingMode: .cool, fanSpeed: .quiet, temperatureSetpoint: 25)
                )
            ]
        )
    }
}
