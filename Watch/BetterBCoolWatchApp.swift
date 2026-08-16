// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
struct BetterBCoolWatchApp: App {
    @StateObject private var session = WatchSessionClient()

    var body: some Scene {
        WindowGroup {
            WatchControlView(session: session)
        }
    }
}

private struct WatchControlView: View {
    @ObservedObject var session: WatchSessionClient
    @State private var crownTemperature = 24.0
    @State private var isUpdatingCrown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let snapshot = session.snapshot, let state = snapshot.state {
                        deviceHeader(snapshot)
                        powerButton(snapshot: snapshot, state: state)
                        temperatureControl(snapshot: snapshot, state: state)
                        if !snapshot.schedules.isEmpty {
                            schedulesControl(snapshot)
                        }
                    } else {
                        unavailableView
                    }

                    if let message = session.errorMessage ?? session.snapshot?.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .navigationTitle("betterBCool")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh climate")
                }
            }
        }
        .task {
            session.start()
            if session.snapshot == nil { session.refresh() }
        }
        .onChange(of: session.snapshot?.state?.temperatureSetpoint) { _, value in
            guard let value else { return }
            isUpdatingCrown = true
            crownTemperature = value
            Task { @MainActor in
                await Task.yield()
                isUpdatingCrown = false
            }
        }
        .onChange(of: crownTemperature) { _, value in
            guard !isUpdatingCrown else { return }
            session.setTemperature(value)
        }
    }

    private func deviceHeader(_ snapshot: WatchSnapshot) -> some View {
        VStack(spacing: 2) {
            Text(snapshot.deviceName ?? "Climate")
                .font(.headline)
                .lineLimit(1)
            Text(snapshot.canWrite ? "Connected" : "Read only")
                .font(.caption2)
                .foregroundStyle(snapshot.canWrite ? .green : .orange)
        }
        .frame(maxWidth: .infinity)
    }

    private func powerButton(snapshot: WatchSnapshot, state: ClimateState) -> some View {
        Button {
            session.togglePower()
        } label: {
            Label(
                state.powerEnabled ? "Turn Off" : "Turn On",
                systemImage: state.powerEnabled ? "power" : "power"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(state.powerEnabled ? .orange : .green)
        .disabled(!snapshot.canWrite)
        .accessibilityIdentifier("watch.powerButton")
    }

    private func temperatureControl(snapshot: WatchSnapshot, state: ClimateState) -> some View {
        VStack(spacing: 3) {
            Text("SETPOINT")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(crownTemperature.formatted(.number.precision(.fractionLength(1))) + "°")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
            Text("Turn crown to adjust")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
#if os(watchOS)
        .focusable(snapshot.canWrite)
        .digitalCrownRotation(
            $crownTemperature,
            from: snapshot.minimumSetpoint ?? state.temperatureSetpoint ?? 15,
            through: snapshot.maximumSetpoint ?? state.temperatureSetpoint ?? 32.5,
            by: snapshot.setpointStep ?? 0.5,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
#endif
        .onAppear {
            if let value = state.temperatureSetpoint { crownTemperature = value }
        }
        .opacity(snapshot.canWrite ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set temperature")
        .accessibilityValue(crownTemperature.formatted(.number.precision(.fractionLength(1))) + " degrees")
        .accessibilityIdentifier("watch.temperatureControl")
    }

    private func schedulesControl(_ snapshot: WatchSnapshot) -> some View {
        Button {
            session.setSchedulesEnabled(!snapshot.allSchedulesEnabled)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: snapshot.allSchedulesEnabled ? "calendar.badge.checkmark" : "calendar.badge.minus")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Schedules")
                        .font(.headline)
                    Text(
                        snapshot.allSchedulesEnabled
                            ? String(
                                format: String(localized: "All %lld on"),
                                locale: .current,
                                Int64(snapshot.schedules.count)
                            )
                            : String(
                                format: String(localized: "%1$lld of %2$lld on"),
                                locale: .current,
                                Int64(snapshot.enabledScheduleCount),
                                Int64(snapshot.schedules.count)
                            )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: snapshot.allSchedulesEnabled ? "power" : "power.slash")
                    .foregroundStyle(snapshot.allSchedulesEnabled ? .green : .secondary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(snapshot.allSchedulesEnabled ? "Turn schedules off" : "Turn schedules on")
        .accessibilityIdentifier("watch.schedulesButton")
    }

    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open betterBCool on iPhone")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Connect Bosch, then return here to control your climate.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { session.refresh() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
