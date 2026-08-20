// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import Foundation
import SwiftUI

@MainActor
final class ScheduleController: ObservableObject {
    @Published private(set) var schedules: [ClimateSchedule]
    @Published private(set) var nextEvent: ClimateScheduleEvent?
    @Published private(set) var errorMessage: String?

    private let service: any ClimateService
    private let remoteService: (any ClimateScheduleRemoteService)?
    private let defaults: UserDefaults
    private let storageKey = "betterBCool.climateSchedules.v1"
    private var runner: Task<Void, Never>?
    private var lastAppliedEventID: String?
    private var scheduleChangeObserver: NSObjectProtocol?

    init(
        service: any ClimateService,
        remoteService: (any ClimateScheduleRemoteService)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.remoteService = remoteService
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ClimateSchedule].self, from: data) {
            schedules = decoded
        } else {
            schedules = []
        }
        scheduleChangeObserver = NotificationCenter.default.addObserver(
            forName: .betterBCoolSchedulesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromStorage()
            }
        }
        refreshNextEvent()
    }

    deinit {
        if let scheduleChangeObserver {
            NotificationCenter.default.removeObserver(scheduleChangeObserver)
        }
    }

    var enabledCount: Int { schedules.filter(\.isEnabled).count }
    var usesCloud: Bool { remoteService != nil }

    func activate() {
        if remoteService == nil { restartRunner() }
        else { syncAllWithCloud() }
    }

    func deactivate() {
        runner?.cancel()
        runner = nil
    }

    func save(_ schedule: ClimateSchedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        schedules.sort { $0.startMinutes < $1.startMinutes }
        persistAndRestart()
        syncWithCloud(schedule)
    }

    func setEnabled(_ enabled: Bool, for scheduleID: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == scheduleID }) else { return }
        schedules[index].isEnabled = enabled
        let schedule = schedules[index]
        persistAndRestart()
        syncWithCloud(schedule)
    }

    func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { schedules[$0].id }
        schedules.remove(atOffsets: offsets)
        persistAndRestart()
        guard let remoteService else { return }
        Task {
            do {
                for id in deletedIDs { try await remoteService.delete(scheduleID: id) }
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "The routine was removed locally, but cloud deletion will need to be retried.")
            }
        }
    }

    private func persistAndRestart() {
        if let data = try? JSONEncoder().encode(schedules) {
            defaults.set(data, forKey: storageKey)
        }
        NotificationCenter.default.post(name: .betterBCoolSchedulesDidChange, object: nil)
        lastAppliedEventID = nil
        refreshNextEvent()
        if remoteService == nil { restartRunner() }
    }

    private func reloadFromStorage() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClimateSchedule].self, from: data),
              decoded != schedules else { return }
        schedules = decoded.sorted { $0.startMinutes < $1.startMinutes }
        lastAppliedEventID = nil
        refreshNextEvent()
        if remoteService == nil { restartRunner() }
    }

    private func restartRunner() {
        runner?.cancel()
        runner = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        while !Task.isCancelled {
            do {
                let now = Date()
                refreshNextEvent(after: now)
                guard let event = nextEvent else {
                    try await Task.sleep(for: .seconds(60 * 60))
                    continue
                }

                let delay = max(0, event.date.timeIntervalSinceNow)
                try await Task.sleep(for: .seconds(delay))

                // Only execute transitions that this runner actually observed. Replaying the
                // current step on launch can unexpectedly power on a unit hours after it began.
                let lateness = Date().timeIntervalSince(event.date)
                if lateness <= 60, event.id != lastAppliedEventID {
                    guard let device = try await service.devices().first else { return }
                    let capabilities = try await service.capabilities(for: device.id)
                    guard capabilities.canWrite else { continue }
                    try capabilities.validate(event.patch)
                    _ = try await service.apply(event.patch, to: device.id)
                    lastAppliedEventID = event.id
                    errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = String(localized: "A scheduled change could not be applied. Retrying shortly.")
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refreshNextEvent(after date: Date = Date()) {
        nextEvent = ClimateScheduleTimeline.nextEvent(in: schedules, after: date)
    }

    private func syncAllWithCloud() {
        let schedules = schedules
        Task {
            do {
                guard let remoteService else { return }
                try await remoteService.reconcile(
                    schedules: schedules,
                    timezone: TimeZone.current.identifier
                )
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "Cloud schedules could not be synchronized. The app will retry when reopened.")
            }
        }
    }

    private func syncWithCloud(_ schedule: ClimateSchedule) {
        guard let remoteService else { return }
        Task {
            do {
                try await remoteService.sync(schedule: schedule, timezone: TimeZone.current.identifier)
                errorMessage = nil
            } catch {
                errorMessage = String(localized: "This routine is saved locally but has not reached the cloud yet.")
            }
        }
    }
}

struct ScheduleListView: View {
    @ObservedObject var controller: ScheduleController
    @State private var draft: ClimateSchedule?

    var body: some View {
        List {
            if controller.schedules.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No routines yet",
                        systemImage: "calendar.badge.plus",
                        description: Text("Build a timeline once and your climate will follow it automatically.")
                    )
                }
            } else {
                Section("Your routines") {
                    ForEach(controller.schedules) { schedule in
                        Button { draft = schedule } label: {
                            ScheduleRow(
                                schedule: schedule,
                                onToggle: { controller.setEnabled($0, for: schedule.id) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: controller.delete)
                }
            }

            Section {
                Button {
                    draft = .nightComfortTemplate()
                } label: {
                    Label("Start with Night comfort", systemImage: "moon.stars.fill")
                }
            } header: {
                Text("Quick start")
            } footer: {
                Text("Cool with the fan for 2 hours, stay quiet until 4:00 AM, pause for 30 minutes, then resume silently. Every detail can be changed before saving.")
            }

            if let message = controller.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Label(
                    controller.usesCloud
                        ? String(localized: "Vercel cloud scheduling")
                        : String(localized: "On-device scheduling"),
                    systemImage: controller.usesCloud ? "cloud.fill" : "iphone"
                )
            } footer: {
                Text(controller.usesCloud
                     ? String(localized: "Routines run in the cloud with durable waits and automatic retries, even while this iPhone is offline.")
                     : String(localized: "Routines are private to this device and run while betterBCool is active. Missed changes are not replayed when the app opens."))
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { draft = newSchedule() } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add routine")
            }
        }
        .sheet(item: $draft) { schedule in
            NavigationStack {
                ScheduleEditor(
                    schedule: schedule,
                    onSave: { controller.save($0) },
                    onCancel: { draft = nil }
                )
            }
        }
    }

    private func newSchedule() -> ClimateSchedule {
        .init(
            name: String(localized: "My routine"),
            startMinutes: 22 * 60,
            weekdays: Set(ScheduleWeekday.allCases),
            steps: [
                .init(
                    name: String(localized: "Start cooling"),
                    patch: .init(powerEnabled: true, operatingMode: .cool, fanSpeed: .auto, temperatureSetpoint: 24),
                    durationMinutes: nil
                )
            ]
        )
    }
}

private struct ScheduleRow: View {
    let schedule: ClimateSchedule
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(schedule.name).font(.headline)
                Text(
                    schedule.steps.count == 1
                        ? String(
                            format: String(localized: "%@ · 1 step"),
                            locale: .current,
                            schedule.startMinutes.clockText
                        )
                        : String(
                            format: String(localized: "%1$@ · %2$lld steps"),
                            locale: .current,
                            schedule.startMinutes.clockText,
                            Int64(schedule.steps.count)
                        )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(schedule.weekdays.repeatSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { schedule.isEnabled }, set: onToggle))
                .labelsHidden()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

private struct ScheduleEditor: View {
    @State var schedule: ClimateSchedule
    let onSave: (ClimateSchedule) -> Void
    let onCancel: () -> Void
    @State private var editingStep: ClimateScheduleStep?

    var body: some View {
        Form {
            Section("Routine") {
                TextField("Name", text: $schedule.name)
                DatePicker("Starts", selection: startTime, displayedComponents: .hourAndMinute)
                Toggle("Enabled", isOn: $schedule.isEnabled)
            }

            Section("Repeats") {
                weekdayPicker
            }

            Section {
                ForEach(Array(schedule.steps.enumerated()), id: \.element.id) { index, step in
                    Button { editingStep = step } label: {
                        TimelineStepRow(step: step, time: time(for: index), isLast: index == schedule.steps.count - 1)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete {
                    schedule.steps.remove(atOffsets: $0)
                    if let last = schedule.steps.indices.last {
                        schedule.steps[last].durationMinutes = nil
                    }
                }

                Button {
                    editingStep = .init(
                        name: String(localized: "Next step"),
                        patch: .init(powerEnabled: true, operatingMode: .cool, fanSpeed: .quiet, temperatureSetpoint: 25)
                    )
                } label: {
                    Label("Add a step", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Timeline")
            } footer: {
                Text("Each step starts when the previous one finishes. The final step stays in effect until you make a manual change or another routine changes it.")
            }
        }
        .navigationTitle(schedule.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var savedSchedule = schedule
                    if let last = savedSchedule.steps.indices.last {
                        savedSchedule.steps[last].durationMinutes = nil
                    }
                    onSave(savedSchedule)
                    onCancel()
                }
                .accessibilityIdentifier("schedule.saveButton")
                .disabled(schedule.name.trimmingCharacters(in: .whitespaces).isEmpty || schedule.weekdays.isEmpty || schedule.steps.isEmpty)
            }
        }
        .sheet(item: $editingStep) { step in
            NavigationStack {
                ScheduleStepEditor(
                    step: step,
                    isFinalStep: schedule.steps.last?.id == step.id || !schedule.steps.contains(where: { $0.id == step.id }),
                    onSave: { updated in
                        if let index = schedule.steps.firstIndex(where: { $0.id == updated.id }) {
                            schedule.steps[index] = updated
                        } else {
                            if let last = schedule.steps.indices.last, schedule.steps[last].durationMinutes == nil {
                                schedule.steps[last].durationMinutes = 60
                            }
                            schedule.steps.append(updated)
                        }
                    },
                    onCancel: { editingStep = nil }
                )
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(ScheduleWeekday.allCases, id: \.self) { day in
                Button {
                    if schedule.weekdays.contains(day) { schedule.weekdays.remove(day) }
                    else { schedule.weekdays.insert(day) }
                } label: {
                    Text(String(day.shortName.prefix(1)))
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(schedule.weekdays.contains(day) ? .white : .secondary)
                        .background(schedule.weekdays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.shortName)
                .accessibilityAddTraits(schedule.weekdays.contains(day) ? .isSelected : [])
            }
        }
    }

    private var startTime: Binding<Date> {
        Binding {
            Calendar.current.date(byAdding: .minute, value: schedule.startMinutes, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        } set: { value in
            let components = Calendar.current.dateComponents([.hour, .minute], from: value)
            schedule.startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        }
    }

    private func time(for index: Int) -> String {
        let priorMinutes = schedule.steps.prefix(index).compactMap(\.durationMinutes).reduce(0, +)
        return (schedule.startMinutes + priorMinutes).clockText
    }
}

private struct TimelineStepRow: View {
    let step: ClimateScheduleStep
    let time: String
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(time).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
            Image(systemName: step.patch.powerEnabled == false ? "power" : (step.patch.fanSpeed == .quiet ? "moon.fill" : "snowflake"))
                .foregroundStyle(step.patch.powerEnabled == false ? .secondary : Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.name).font(.body.weight(.semibold))
                Text(step.summary).font(.caption).foregroundStyle(.secondary)
                Text(
                    step.durationMinutes.map {
                        String(
                            format: String(localized: "For %@"),
                            locale: .current,
                            $0.durationText
                        )
                    } ?? finalStepDescription
                )
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private var finalStepDescription: String {
        guard isLast else { return String(localized: "Until changed") }
        return step.patch.powerEnabled == false
            ? String(localized: "Stay off until changed")
            : String(localized: "Keep this setting until changed")
    }
}

private struct ScheduleStepEditor: View {
    @State var step: ClimateScheduleStep
    let isFinalStep: Bool
    let onSave: (ClimateScheduleStep) -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            Section("Step") {
                TextField("Name", text: $step.name)
                Picker("Power", selection: powerEnabled) {
                    Text("On").tag(true)
                    Text("Off").tag(false)
                }
#if os(iOS)
                .pickerStyle(.segmented)
#endif
            }

            if step.patch.powerEnabled != false {
                Section("Comfort") {
                    Picker("Mode", selection: operatingMode) {
                        ForEach(OperatingMode.allCases, id: \.self) { Text($0.scheduleTitle).tag($0) }
                    }
                    Picker("Fan", selection: fanSpeed) {
                        ForEach(FanSpeed.allCases, id: \.self) { Text($0.scheduleTitle).tag($0) }
                    }
                    Stepper(value: temperature, in: 15...32.5, step: 0.5) {
                        LabeledContent("Temperature", value: String(format: "%.1f°", step.patch.temperatureSetpoint ?? 24))
                    }
                }
            }

            Section {
                if isFinalStep {
                    Label(
                        step.patch.powerEnabled == false
                            ? String(localized: "Stay off until changed")
                            : String(localized: "Keep this setting until changed"),
                        systemImage: "infinity"
                    )
                } else {
                    Stepper(value: durationMinutes, in: 15...(12 * 60), step: 15) {
                        LabeledContent("Duration", value: (step.durationMinutes ?? 60).durationText)
                    }
                }
            } header: {
                Text("After this step")
            } footer: {
                Text(afterStepExplanation)
            }
        }
        .navigationTitle(step.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if isFinalStep { step.durationMinutes = nil }
                    onSave(step)
                    onCancel()
                }
                .accessibilityIdentifier("schedule.stepDoneButton")
                .disabled(step.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var powerEnabled: Binding<Bool> {
        Binding(get: { step.patch.powerEnabled ?? true }, set: { step.patch.powerEnabled = $0 })
    }
    private var operatingMode: Binding<OperatingMode> {
        Binding(get: { step.patch.operatingMode ?? .cool }, set: { step.patch.operatingMode = $0 })
    }
    private var fanSpeed: Binding<FanSpeed> {
        Binding(get: { step.patch.fanSpeed ?? .auto }, set: { step.patch.fanSpeed = $0 })
    }
    private var temperature: Binding<Double> {
        Binding(get: { step.patch.temperatureSetpoint ?? 24 }, set: { step.patch.temperatureSetpoint = $0 })
    }
    private var durationMinutes: Binding<Int> {
        Binding(get: { step.durationMinutes ?? 60 }, set: { step.durationMinutes = $0 })
    }

    private var afterStepExplanation: String {
        if isFinalStep {
            return step.patch.powerEnabled == false
                ? String(localized: "The unit stays off until you turn it on manually or another routine changes it.")
                : String(localized: "This setting stays active until you change it manually or another routine changes it.")
        }
        if step.patch.powerEnabled == false {
            return String(localized: "The unit stays off for this duration, then the next step begins. To keep it off, make this the final step.")
        }
        return String(localized: "The next step begins automatically when this duration ends.")
    }
}

extension ClimateScheduleStep {
    fileprivate var summary: String {
        guard patch.powerEnabled != false else { return String(localized: "Turn off") }
        var values = [
            patch.operatingMode?.scheduleTitle,
            patch.fanSpeed.map {
                String(format: String(localized: "%@ fan"), locale: .current, $0.scheduleTitle)
            }
        ].compactMap { $0 }
        if let temperature = patch.temperatureSetpoint { values.append(String(format: "%.1f°", temperature)) }
        return values.joined(separator: " · ")
    }
}

extension Int {
    fileprivate var clockText: String {
        let minutes = self % (24 * 60)
        var components = DateComponents()
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? ""
    }

    fileprivate var durationText: String {
        if self < 60 {
            return String(format: String(localized: "%lld min"), locale: .current, Int64(self))
        }
        if self % 60 == 0 {
            return String(format: String(localized: "%lld hr"), locale: .current, Int64(self / 60))
        }
        return String(
            format: String(localized: "%1$lld hr %2$lld min"),
            locale: .current,
            Int64(self / 60),
            Int64(self % 60)
        )
    }
}

extension Set where Element == ScheduleWeekday {
    fileprivate var repeatSummary: String {
        if count == 7 { return String(localized: "Every day") }
        if self == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            return String(localized: "Weekdays")
        }
        if self == Set([.saturday, .sunday]) { return String(localized: "Weekends") }
        return ScheduleWeekday.allCases.filter(contains).map(\.shortName).joined(separator: ", ")
    }
}

extension OperatingMode {
    fileprivate var scheduleTitle: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .cool: String(localized: "Cool")
        case .dry: String(localized: "Dry")
        case .fan: String(localized: "Fan")
        case .heat: String(localized: "Heat")
        }
    }
}

extension FanSpeed {
    fileprivate var scheduleTitle: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .quiet: String(localized: "Quiet")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .turbo: String(localized: "Turbo")
        }
    }
}
