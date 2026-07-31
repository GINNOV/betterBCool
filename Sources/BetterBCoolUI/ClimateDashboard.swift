// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import SwiftUI

@MainActor
public struct ClimateDashboard: View {
    @StateObject private var model: ClimateViewModel
    @StateObject private var scheduleController: ScheduleController
    @ObservedObject private var sensorTag: SensorTagManager
    private let settingsContent: () -> AnyView
    private let onSettingsTapped: (() -> Void)?
    private let onReconnectTapped: (() -> Void)?

    public init(
        service: any ClimateService,
        remoteScheduler: (any ClimateScheduleRemoteService)? = nil,
        sensorTag: SensorTagManager? = nil
    ) {
        _model = StateObject(wrappedValue: ClimateViewModel(service: service))
        _scheduleController = StateObject(
            wrappedValue: ScheduleController(service: service, remoteService: remoteScheduler)
        )
        self.sensorTag = sensorTag ?? .shared
        settingsContent = { AnyView(EmptyView()) }
        onSettingsTapped = nil
        onReconnectTapped = nil
    }

    public init<SettingsContent: View>(
        service: any ClimateService,
        remoteScheduler: (any ClimateScheduleRemoteService)? = nil,
        sensorTag: SensorTagManager? = nil,
        @ViewBuilder settingsContent: @escaping () -> SettingsContent
    ) {
        _model = StateObject(wrappedValue: ClimateViewModel(service: service))
        _scheduleController = StateObject(
            wrappedValue: ScheduleController(service: service, remoteService: remoteScheduler)
        )
        self.sensorTag = sensorTag ?? .shared
        self.settingsContent = { AnyView(settingsContent()) }
        onSettingsTapped = nil
        onReconnectTapped = nil
    }

    public init(
        service: any ClimateService,
        remoteScheduler: (any ClimateScheduleRemoteService)? = nil,
        sensorTag: SensorTagManager? = nil,
        onSettingsTapped: @escaping () -> Void,
        onReconnectTapped: (() -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: ClimateViewModel(service: service))
        _scheduleController = StateObject(
            wrappedValue: ScheduleController(service: service, remoteService: remoteScheduler)
        )
        self.sensorTag = sensorTag ?? .shared
        settingsContent = { AnyView(EmptyView()) }
        self.onSettingsTapped = onSettingsTapped
        self.onReconnectTapped = onReconnectTapped
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if let state = model.state {
                    dashboard(state)
                } else if model.isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .accessibilityLabel("Loading climate data")
                } else {
                    VStack(spacing: 18) {
                        HStack {
                            Spacer()
                            settingsButton
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                        Spacer()

                        ContentUnavailableView(
                            "No climate data",
                            systemImage: "air.conditioner.horizontal",
                            description: Text(model.errorMessage ?? String(localized: "Check your connection settings."))
                        )
                        if model.requiresReauthentication, let onReconnectTapped {
                            Button("Reconnect Bosch", systemImage: "person.crop.circle.badge.checkmark") {
                                onReconnectTapped()
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("dashboard.reconnectButton")
                        }

                        Spacer()
                    }
                    .foregroundStyle(.white)
                }
            }
            .task {
                scheduleController.activate()
                await model.load()
            }
            .onDisappear { scheduleController.deactivate() }
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#endif
        }
        .preferredColorScheme(.dark)
    }

    private func dashboard(_ state: ClimateState) -> some View {
        VStack(spacing: 14) {
            header(state)
                .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(spacing: 18) {
                    temperatureCard(state)
                    if sensorTag.connectionState == .connected {
                        sensorTagCard
                    }
                    modeCard(state)
                    fanCard(state)
                    scheduleCard
                    quickActions(state)
                    activityLogCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.load() }
        }
        .padding(.top, 14)
    }

    private func header(_ state: ClimateState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR CLIMATE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 7) {
                    Text(model.selectedDevice?.name ?? "betterBCool")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    if model.controlsEnabled {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.mint)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            Spacer()

            settingsButton

            Button {
                Task { await model.togglePower() }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(state.powerEnabled ? Color.accentBlue : Color.white.opacity(0.1))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!model.controlsEnabled)
            .opacity(model.controlsEnabled ? 1 : 0.75)
            .accessibilityLabel(
                state.powerEnabled
                    ? String(localized: "Turn air conditioner off")
                    : String(localized: "Turn air conditioner on")
            )
            .accessibilityIdentifier("dashboard.powerButton")
        }
    }

    private var settingsButton: some View {
        Group {
            if let onSettingsTapped {
                Button(action: onSettingsTapped) {
                    settingsIcon
                }
            } else {
                NavigationLink {
                    settingsContent()
                } label: {
                    settingsIcon
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("dashboard.settingsButton")
    }

    private var settingsIcon: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 48, height: 48)
            .background(.white.opacity(0.08), in: Circle())
            .contentShape(Circle())
    }

    private func temperatureCard(_ state: ClimateState) -> some View {
        VStack(spacing: 22) {
            HStack {
                StatusPill(isOn: state.powerEnabled)
                Spacer()
                if let sensorTemperature = sensorTagRoomTemperature {
                    Label(
                        String(
                            format: String(localized: "SensorTag %@°"),
                            locale: .current,
                            sensorTemperature.formatted(.number.precision(.fractionLength(1)))
                        ),
                        systemImage: "sensor.tag.radiowaves.forward.fill"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.mint)
                        .accessibilityLabel("SensorTag temperature")
                        .accessibilityValue(
                            String(
                                format: String(localized: "%@ degrees Celsius"),
                                locale: .current,
                                sensorTemperature.formatted(.number.precision(.fractionLength(1)))
                            )
                        )
                        .accessibilityIdentifier("dashboard.sensorTagTemperature")
                } else if let roomTemperature = state.roomTemperature {
                    Label(
                        String(
                            format: String(localized: "Room %@°"),
                            locale: .current,
                            roomTemperature.formatted(.number.precision(.fractionLength(1)))
                        ),
                        systemImage: "house.fill"
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        Label("Room —°", systemImage: "house.fill")
                            .font(.caption.weight(.semibold))
                        Text("Not reported by device")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.62))
                }
            }

            VStack(spacing: 2) {
                Text("SET TO")
                    .font(.caption2.weight(.bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.46))

                HStack(alignment: .top, spacing: 2) {
                    Text(state.temperatureSetpoint.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 76, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("°")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.top, 9)
                }
                .foregroundStyle(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Set temperature")
                .accessibilityValue(
                    state.temperatureSetpoint.map {
                        String(
                            format: String(localized: "%@ degrees Celsius"),
                            locale: .current,
                            $0.formatted(.number.precision(.fractionLength(1)))
                        )
                    } ?? String(localized: "Unavailable")
                )
            }

            HStack(spacing: 22) {
                TemperatureButton(systemName: "minus") {
                    adjustTemperature(state, by: -temperatureStep)
                }
                .disabled(!canAdjust(state, by: -temperatureStep))

                modeSummary(state.operatingMode)

                TemperatureButton(systemName: "plus") {
                    adjustTemperature(state, by: temperatureStep)
                }
                .disabled(!canAdjust(state, by: temperatureStep))
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentBlue.opacity(0.82), Color.deepBlue.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 210)
                        .blur(radius: 2)
                        .offset(x: 75, y: -95)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: Color.accentBlue.opacity(0.24), radius: 28, y: 16)
    }

    private func modeSummary(_ mode: OperatingMode) -> some View {
        Label(mode.title, systemImage: mode.symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(minWidth: 96)
            .padding(.vertical, 12)
            .background(.white.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.13), lineWidth: 1))
    }

    private func modeCard(_ state: ClimateState) -> some View {
        DashboardCard(
            title: String(localized: "Mode"),
            subtitle: String(localized: "Choose how the room feels")
        ) {
            HStack(spacing: 8) {
                ForEach(OperatingMode.allCases, id: \.self) { mode in
                    SelectableIcon(
                        title: mode.title,
                        symbol: mode.symbol,
                        selected: state.operatingMode == mode
                    ) {
                        Task { await model.apply(.init(operatingMode: mode)) }
                    }
                    .disabled(!model.controlsEnabled || model.capabilities?.operatingModes.contains(mode) != true)
                }
            }
        }
    }

    private var sensorTagCard: some View {
        DashboardCard(
            title: String(localized: "SensorTag"),
            subtitle: sensorTag.connectedDevice?.name ?? String(localized: "Live room sensors")
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SensorMetric(
                    title: String(localized: "Ambient"),
                    value: formatted(sensorTag.readings.ambientTemperature, unit: "°C", precision: 1),
                    symbol: "thermometer.medium"
                )
                SensorMetric(
                    title: String(localized: "Humidity"),
                    value: formatted(sensorTag.readings.relativeHumidity, unit: "%", precision: 1),
                    symbol: "humidity.fill"
                )
                SensorMetric(
                    title: String(localized: "Object"),
                    value: formatted(sensorTag.readings.objectTemperature, unit: "°C", precision: 1),
                    symbol: "viewfinder"
                )
                SensorMetric(
                    title: String(localized: "Pressure"),
                    value: formatted(sensorTag.readings.pressure, unit: " hPa", precision: 0),
                    symbol: "gauge.with.dots.needle.33percent"
                )
            }

            if let acceleration = sensorTag.readings.acceleration {
                VectorMetric(title: String(localized: "Acceleration"), vector: acceleration, unit: "g")
            }
            if let angularVelocity = sensorTag.readings.angularVelocity {
                VectorMetric(title: String(localized: "Gyroscope"), vector: angularVelocity, unit: "°/s")
            }
            if let magneticField = sensorTag.readings.magneticField {
                VectorMetric(title: String(localized: "Magnetic field"), vector: magneticField, unit: "µT")
            }
        }
        .accessibilityIdentifier("dashboard.sensorTagCard")
    }

    private var sensorTagRoomTemperature: Double? {
        sensorTag.connectionState == .connected ? sensorTag.readings.ambientTemperature : nil
    }

    private func formatted(_ value: Double?, unit: String, precision: Int) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(precision))) + unit
    }

    private func fanCard(_ state: ClimateState) -> some View {
        DashboardCard(
            title: String(localized: "Fan"),
            subtitle: String(localized: "Airflow intensity")
        ) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "fan.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                        .frame(width: 38, height: 38)
                        .background(Color.accentBlue.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("CURRENT SPEED")
                            .font(.caption2.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.42))
                        Text(state.fanSpeed?.title ?? String(localized: "Unavailable"))
                            .font(.subheadline.weight(.semibold))
                    }

                    Spacer(minLength: 8)
                    FanBars(speed: state.fanSpeed)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(FanSpeed.allCases, id: \.self) { speed in
                        SelectableText(
                            title: speed.title,
                            selected: state.fanSpeed == speed
                        ) {
                            Task { await model.apply(.init(fanSpeed: speed)) }
                        }
                        .disabled(!model.controlsEnabled || model.capabilities?.fanSpeeds.contains(speed) != true)
                    }
                }
            }
        }
    }

    private func quickActions(_ state: ClimateState) -> some View {
        DashboardCard(
            title: String(localized: "Comfort"),
            subtitle: String(localized: "Status and swing controls")
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                FeatureTile(title: String(localized: "Eco"), symbol: "leaf.fill", enabled: state.ecoEnabled)
                FeatureTile(title: String(localized: "Sleep"), symbol: "moon.stars.fill", enabled: state.sleepEnabled)
                FeatureTile(
                    title: String(localized: "Vertical swing"),
                    symbol: "arrow.up.and.down",
                    enabled: state.verticalSwingEnabled,
                    action: {
                        Task {
                            await model.apply(.init(verticalSwingEnabled: !state.verticalSwingEnabled))
                        }
                    }
                )
                .disabled(!model.controlsEnabled)
                .accessibilityIdentifier("dashboard.verticalSwingButton")

                FeatureTile(
                    title: String(localized: "Horizontal"),
                    symbol: "arrow.left.and.right",
                    enabled: state.horizontalSwingEnabled,
                    action: {
                        Task {
                            await model.apply(.init(horizontalSwingEnabled: !state.horizontalSwingEnabled))
                        }
                    }
                )
                .disabled(!model.controlsEnabled)
                .accessibilityIdentifier("dashboard.horizontalSwingButton")
            }
        }
    }

    private var activityLogCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity").font(.headline)
                    Text("Recent unit changes").font(.caption).foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Button("Clear") {
                    model.clearActivities()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.activities.isEmpty ? .white.opacity(0.3) : Color.accentBlue)
                .disabled(model.activities.isEmpty)
                .accessibilityIdentifier("dashboard.clearActivityButton")
            }

            if model.activities.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.045), in: Circle())
                    Text("Unit changes will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.activities.enumerated()), id: \.element.id) { index, activity in
                        ActivityRow(activity: activity)
                        if index < model.activities.count - 1 {
                            Divider().overlay(.white.opacity(0.08)).padding(.leading, 50)
                        }
                    }
                }
                .accessibilityIdentifier("dashboard.activityLog")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.075)))
    }

    private var scheduleCard: some View {
        NavigationLink {
            ScheduleListView(controller: scheduleController)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .frame(width: 44, height: 44)
                    .background(Color.accentBlue.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Schedules").font(.headline)
                    if scheduleController.enabledCount == 0 {
                        Text("Create a routine for your day")
                    } else if let event = scheduleController.nextEvent {
                        Text(
                            String(
                                format: String(localized: "Next change %@"),
                                locale: .current,
                                event.date.formatted(date: .omitted, time: .shortened)
                            )
                        )
                    } else {
                        Text(
                            String(
                                format: String(localized: "%lld active"),
                                locale: .current,
                                Int64(scheduleController.enabledCount)
                            )
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.white)

                Spacer()

                if scheduleController.enabledCount > 0 {
                    Text("\(scheduleController.enabledCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(Color.accentBlue, in: Circle())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(17)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.075)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.schedulesButton")
    }

    private func canAdjust(_ state: ClimateState, by delta: Double) -> Bool {
        guard model.controlsEnabled,
              let value = state.temperatureSetpoint,
              let capabilities = model.capabilities else { return false }
        return value + delta >= capabilities.minimumSetpoint && value + delta <= capabilities.maximumSetpoint
    }

    private var temperatureStep: Double {
        model.capabilities?.setpointStep ?? 0.5
    }

    private func adjustTemperature(_ state: ClimateState, by delta: Double) {
        guard let value = state.temperatureSetpoint else { return }
        Task { await model.apply(.init(temperatureSetpoint: value + delta)) }
    }
}

private struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.appTop, Color.appBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentBlue.opacity(0.13))
                .frame(width: 330)
                .blur(radius: 70)
                .offset(x: 120, y: -130)
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.45))
            }
            content
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.075)))
    }
}

private struct SensorMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentBlue)
                .frame(width: 30, height: 30)
                .background(Color.accentBlue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.48))
                Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct VectorMetric: View {
    let title: String
    let vector: SensorVector
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.58))
            HStack {
                axis("X", vector.x)
                axis("Y", vector.y)
                axis("Z", vector.z)
            }
        }
        .padding(.top, 2)
    }

    private func axis(_ name: String, _ value: Double) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(Color.accentBlue)
            Text(value.formatted(.number.precision(.fractionLength(2))))
            Text(unit).foregroundStyle(.white.opacity(0.42))
        }
        .font(.caption2.monospacedDigit())
        .frame(maxWidth: .infinity)
    }
}

private struct StatusPill: View {
    let isOn: Bool
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(isOn ? Color.mint : .white.opacity(0.45)).frame(width: 7, height: 7)
            Text(isOn ? String(localized: "COOLING") : String(localized: "OFF"))
                .font(.caption2.weight(.bold))
                .tracking(1.1)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.black.opacity(0.16), in: Capsule())
    }
}

private struct TemperatureButton: View {
    let systemName: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 46, height: 46)
                .background(.white.opacity(isEnabled ? 0.16 : 0.07), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.13)))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(
            systemName == "plus"
                ? String(localized: "Increase temperature")
                : String(localized: "Decrease temperature")
        )
    }
}

private struct SelectableIcon: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                if !isEnabled {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(.white.opacity(0.035), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isEnabled ? "" : String(localized: "Unavailable"))
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .white.opacity(0.20) }
        return selected ? .white : .white.opacity(0.46)
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .white.opacity(0.015) }
        return selected ? Color.accentBlue : .white.opacity(0.045)
    }
}

private struct SelectableText: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(foregroundColor)
                .background(backgroundColor, in: Capsule())
                .overlay {
                    if !isEnabled {
                        Capsule().stroke(.white.opacity(0.035), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isEnabled ? "" : String(localized: "Unavailable"))
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .white.opacity(0.20) }
        return selected ? .white : .white.opacity(0.5)
    }

    private var backgroundColor: Color {
        guard isEnabled else { return .white.opacity(0.015) }
        return selected ? Color.accentBlue : .white.opacity(0.045)
    }
}

private struct FanBars: View {
    let speed: FanSpeed?

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(1...5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(level <= (speed?.barLevel ?? 0) ? Color.accentBlue : .white.opacity(0.12))
                    .frame(width: 6, height: CGFloat(5 + level * 4))
            }
        }
        .frame(height: 25, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fan speed")
        .accessibilityValue(speed?.title ?? String(localized: "Unavailable"))
    }
}

private struct FeatureTile: View {
    let title: String
    let symbol: String
    let enabled: Bool
    var action: (() -> Void)? = nil
    @Environment(\.isEnabled) private var isAvailable

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
                    .accessibilityElement(children: .combine)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(enabled ? String(localized: "On") : String(localized: "Off"))
    }

    private var content: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.mint : .white.opacity(0.38))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.06), in: Circle())
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Text(enabled ? String(localized: "On") : String(localized: "Off"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(enabled ? Color.mint : .white.opacity(0.34))
        }
        .padding(10)
        .foregroundStyle(enabled ? .white : .white.opacity(0.43))
        .background(.white.opacity(enabled ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 15))
        .opacity(isAvailable ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 15))
    }
}

private struct ActivityRow: View {
    let activity: ClimateActivity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 38, height: 38)
                .background(Color.accentBlue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline.weight(.semibold))
                Text(activity.detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer(minLength: 8)

            Text(activity.timestamp, format: .dateTime.hour().minute())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.title), \(activity.detail)")
    }
}

private extension OperatingMode {
    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .cool: String(localized: "Cool")
        case .dry: String(localized: "Dry")
        case .fan: String(localized: "Fan")
        case .heat: String(localized: "Heat")
        }
    }
    var symbol: String {
        switch self { case .auto: "sparkles"; case .cool: "snowflake"; case .dry: "drop.fill"; case .fan: "fan.fill"; case .heat: "sun.max.fill" }
    }
}

private extension FanSpeed {
    var title: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .quiet: String(localized: "Quiet")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .turbo: String(localized: "Turbo")
        }
    }

    var barLevel: Int {
        switch self {
        case .quiet: 1
        case .low: 2
        case .medium: 3
        case .high: 4
        case .auto, .turbo: 5
        }
    }
}

private extension Color {
    static let appTop = Color(red: 0.045, green: 0.065, blue: 0.12)
    static let appBottom = Color(red: 0.025, green: 0.035, blue: 0.07)
    static let accentBlue = Color(red: 0.20, green: 0.46, blue: 0.98)
    static let deepBlue = Color(red: 0.12, green: 0.23, blue: 0.62)
}
