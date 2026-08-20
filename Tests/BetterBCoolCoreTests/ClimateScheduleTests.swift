// SPDX-License-Identifier: Apache-2.0

import Foundation
import XCTest
@testable import BetterBCoolCore

final class ClimateScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testNightRoutineCreatesOvernightTransitions() throws {
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 21)))
        let schedule = ClimateSchedule.nightComfortTemplate(calendar: calendar, now: monday)

        let first = try XCTUnwrap(ClimateScheduleTimeline.nextEvent(in: [schedule], after: monday, calendar: calendar))
        XCTAssertEqual(first.date, calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 22)))

        let afterMidnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 4, minute: 10)))
        let current = try XCTUnwrap(ClimateScheduleTimeline.currentEvent(in: [schedule], at: afterMidnight, calendar: calendar))
        XCTAssertEqual(current.patch.powerEnabled, false)

        let resume = try XCTUnwrap(ClimateScheduleTimeline.nextEvent(in: [schedule], after: afterMidnight, calendar: calendar))
        XCTAssertEqual(resume.date, calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 4, minute: 30)))
        XCTAssertEqual(resume.patch.fanSpeed, .quiet)
    }

    func testDisabledRoutineProducesNoEvents() {
        var schedule = ClimateSchedule.nightComfortTemplate(calendar: calendar)
        schedule.isEnabled = false
        XCTAssertNil(ClimateScheduleTimeline.nextEvent(in: [schedule], after: Date(), calendar: calendar))
        XCTAssertNil(ClimateScheduleTimeline.currentEvent(in: [schedule], at: Date(), calendar: calendar))
    }

    func testRoutineOnlyRunsOnSelectedStartDay() throws {
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 21)))
        var schedule = ClimateSchedule.nightComfortTemplate(calendar: calendar, now: monday)
        schedule.weekdays = [.tuesday]

        let next = try XCTUnwrap(ClimateScheduleTimeline.nextEvent(in: [schedule], after: monday, calendar: calendar))
        XCTAssertEqual(next.date, calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 22)))
    }

    func testCloudSyncDeletesRemoteRoutinesThePhoneNoLongerHas() {
        let kept = UUID(uuidString: "64F42EB2-2ECD-4E13-AA32-D58150198D87")!
        let orphan = UUID(uuidString: "1989DD0A-8AAC-480B-AC52-60DD83DAF5B9")!
        let local = [
            ClimateSchedule(
                id: kept,
                name: "Night comfort",
                isEnabled: false,
                startMinutes: 1320,
                weekdays: Set(ScheduleWeekday.allCases),
                steps: [
                    .init(name: "Cool down", patch: .init(powerEnabled: true))
                ]
            )
        ]

        let orphans = ClimateScheduleCloudSync.orphanedRemoteIDs(
            local: local,
            remoteIDs: [kept, orphan]
        )

        XCTAssertEqual(orphans, [orphan])
    }
}
