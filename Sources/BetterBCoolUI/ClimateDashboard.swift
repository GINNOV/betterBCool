// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import SwiftUI

public struct ClimateDashboard: View {
    @StateObject private var model: ClimateViewModel
    @StateObject private var scheduleController: ScheduleController
    private let settingsContent: () -> AnyView

    public init(
        service: any ClimateService,
        remoteScheduler: (any ClimateScheduleRemoteService)? = nil
    ) {
        _model = StateObject(wrappedValue: ClimateViewModel(service: service))
        _scheduleController = StateObject(
            wrappedValue: ScheduleController(service: service, remoteService: remoteScheduler)
        )
        settingsContent = { AnyView(EmptyView()) }
    }

    public init<SettingsContent: View>(
        service: any ClimateService,
        remoteScheduler: (any ClimateScheduleRemoteService)? = nil,
        @ViewBuilder settingsContent: @escaping () -> SettingsContent
    ) {
        _model = StateObject(wrappedValue: ClimateViewModel(service: service))
        _scheduleController = StateObject(
            wrappedValue: ScheduleController(service: service, remoteService: remoteScheduler)
        )
        self.settingsContent = { AnyView(settingsContent()) }
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
                    ContentUnavailableView(
                        "No climate data",
                        systemImage: "air.conditioner.horizontal",
                        description: Text(model.errorMessage ?? "Check your connection settings.")
                    )
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
        ScrollView {
            LazyVStack(spacing: 18) {
                header(state)
                temperatureCard(state)
                modeCard(state)
                fanCard(state)
                scheduleCard
                quickActions(state)
                connectionCard(state)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.load() }
    }

    private func header(_ state: ClimateState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR CLIMATE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.55))
                Text(model.selectedDevice?.name ?? "betterBCool")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }

            Spacer()

            settingsLink

            Button {
                Task { await model.apply(.init(powerEnabled: !state.powerEnabled)) }
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
            .accessibilityLabel(state.powerEnabled ? "Turn air conditioner off" : "Turn air conditioner on")
        }
    }

    private var settingsLink: some View {
        NavigationLink {
            settingsContent()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("dashboard.settingsButton")
    }

    private func temperatureCard(_ state: ClimateState) -> some View {
        VStack(spacing: 22) {
            HStack {
                StatusPill(isOn: state.powerEnabled)
                Spacer()
                if let roomTemperature = state.roomTemperature {
                    Label("Room \(roomTemperature, specifier: "%.1f")°", systemImage: "house.fill")
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
                .accessibilityValue(state.temperatureSetpoint.map { "\($0) degrees Celsius" } ?? "Unavailable")
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
        DashboardCard(title: "Mode", subtitle: "Choose how the room feels") {
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

    private func fanCard(_ state: ClimateState) -> some View {
        DashboardCard(title: "Fan", subtitle: "Airflow intensity") {
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
                        Text(state.fanSpeed?.title ?? "Unavailable")
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
        DashboardCard(title: "Comfort", subtitle: "Active features") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                FeatureTile(title: "Eco", symbol: "leaf.fill", enabled: state.ecoEnabled)
                FeatureTile(title: "Sleep", symbol: "moon.stars.fill", enabled: state.sleepEnabled)
                FeatureTile(title: "Vertical swing", symbol: "arrow.up.and.down", enabled: state.verticalSwingEnabled)
                FeatureTile(title: "Horizontal", symbol: "arrow.left.and.right", enabled: state.horizontalSwingEnabled)
            }
        }
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
                        Text("Next change \(event.date.formatted(date: .omitted, time: .shortened))")
                    } else {
                        Text("\(scheduleController.enabledCount) active")
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

    private func connectionCard(_ state: ClimateState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.controlsEnabled ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(model.controlsEnabled ? Color.mint : .white.opacity(0.5))

            VStack(alignment: .leading, spacing: 3) {
                Text(model.controlsEnabled ? "Connected" : "Read-only connection")
                    .font(.subheadline.weight(.semibold))
                Text("Updated \(state.timestamp.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))
            }

            Spacer()

            Circle()
                .fill(model.controlsEnabled ? Color.mint : Color.white.opacity(0.28))
                .frame(width: 8, height: 8)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.07)))
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

private struct StatusPill: View {
    let isOn: Bool
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(isOn ? Color.mint : .white.opacity(0.45)).frame(width: 7, height: 7)
            Text(isOn ? "COOLING" : "OFF")
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
        .accessibilityLabel(systemName == "plus" ? "Increase temperature" : "Decrease temperature")
    }
}

private struct SelectableIcon: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? .white : .white.opacity(0.46))
            .background(selected ? Color.accentBlue : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

private struct SelectableText: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(selected ? .white : .white.opacity(0.5))
                .background(selected ? Color.accentBlue : .white.opacity(0.045), in: Capsule())
        }
        .buttonStyle(.plain)
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
        .accessibilityValue(speed?.title ?? "Unavailable")
    }
}

private struct FeatureTile: View {
    let title: String
    let symbol: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? Color.mint : .white.opacity(0.38))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.06), in: Circle())
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .foregroundStyle(enabled ? .white : .white.opacity(0.43))
        .background(.white.opacity(enabled ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 15))
    }
}

private extension OperatingMode {
    var title: String {
        switch self { case .auto: "Auto"; case .cool: "Cool"; case .dry: "Dry"; case .fan: "Fan"; case .heat: "Heat" }
    }
    var symbol: String {
        switch self { case .auto: "sparkles"; case .cool: "snowflake"; case .dry: "drop.fill"; case .fan: "fan.fill"; case .heat: "sun.max.fill" }
    }
}

private extension FanSpeed {
    var title: String {
        switch self {
        case .auto: "Auto"
        case .quiet: "Quiet"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .turbo: "Turbo"
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
