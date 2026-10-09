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

    func testDeletingTheFinalStepKeepsThePreviousDuration() {
        let cool = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let quiet = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let resume = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        var steps = [
            ClimateScheduleStep(id: cool, name: "Cool", patch: .init(powerEnabled: true), durationMinutes: 30),
            ClimateScheduleStep(id: quiet, name: "Quiet", patch: .init(powerEnabled: true), durationMinutes: 45),
            ClimateScheduleStep(id: resume, name: "Resume", patch: .init(powerEnabled: true))
        ]
        var memory: [UUID: Int] = [:]

        ScheduleStepDurations.remember(steps, into: &memory)
        steps.removeLast()
        ScheduleStepDurations.normalize(&steps, remembered: &memory)

        XCTAssertEqual(steps.map(\.durationMinutes), [30, nil])
        XCTAssertEqual(memory[quiet], 45)

        steps.append(ClimateScheduleStep(id: resume, name: "Resume", patch: .init(powerEnabled: true)))
        ScheduleStepDurations.remember(steps, into: &memory)
        ScheduleStepDurations.normalize(&steps, remembered: &memory)

        XCTAssertEqual(steps.map(\.durationMinutes), [30, 45, nil])
    }

    func testReorderingRestoresADurationWhenAStepLeavesTheFinalPosition() {
        let timed = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let open = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        var steps = [
            ClimateScheduleStep(id: timed, name: "Timed", patch: .init(powerEnabled: true), durationMinutes: 15),
            ClimateScheduleStep(id: open, name: "Open", patch: .init(powerEnabled: true))
        ]
        var memory: [UUID: Int] = [:]
        ScheduleStepDurations.remember(steps, into: &memory)
        steps.swapAt(0, 1)
        ScheduleStepDurations.normalize(&steps, remembered: &memory)

        XCTAssertEqual(steps.map(\.id), [open, timed])
        XCTAssertEqual(steps.map(\.durationMinutes), [60, nil])
        XCTAssertEqual(memory[timed], 15)
    }

    func testReorderingKeepsARememberedDurationOnAFormerFinalStep() {
        let first = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let second = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        var steps = [
            ClimateScheduleStep(id: first, name: "Cool", patch: .init(powerEnabled: true), durationMinutes: 30),
            ClimateScheduleStep(id: second, name: "Hold", patch: .init(powerEnabled: true))
        ]
        var memory: [UUID: Int] = [second: 90]
        ScheduleStepDurations.remember(steps, into: &memory)
        let moved = steps.removeFirst()
        steps.append(moved)
        ScheduleStepDurations.normalize(&steps, remembered: &memory)

        XCTAssertEqual(steps.map(\.id), [second, first])
        XCTAssertEqual(steps.map(\.durationMinutes), [90, nil])
        XCTAssertEqual(memory[first], 30)
    }
}
