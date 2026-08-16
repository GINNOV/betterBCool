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
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var session: WatchSessionClient
    @State private var crownTemperature = 24.0
    @State private var isUpdatingCrown = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let snapshot = session.snapshot, let state = snapshot.state {
                    if state.powerEnabled {
                        HStack(spacing: 8) {
                            deviceHeader(snapshot, state: state)
                            Spacer(minLength: 4)
                            powerButton(snapshot: snapshot, state: state)
                        }
                        temperatureControl(snapshot: snapshot, state: state)
                        if !snapshot.schedules.isEmpty {
                            schedulesControl(snapshot)
                        }
                    } else {
                        poweredOffView(snapshot: snapshot, state: state)
                    }
                } else {
                    unavailableView
                }

                if let message = session.errorMessage ?? session.snapshot?.errorMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            session.start()
            session.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refresh() }
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
            guard !isUpdatingCrown,
                  session.snapshot?.canWrite == true,
                  session.snapshot?.state?.powerEnabled == true else { return }
            session.setTemperature(value)
        }
    }

    private func deviceHeader(_ snapshot: WatchSnapshot, state: ClimateState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.deviceName ?? "Climate")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Circle()
                    .fill(snapshot.canWrite ? (state.powerEnabled ? .green : .secondary) : .orange)
                    .frame(width: 5, height: 5)
                Text(snapshot.canWrite ? (state.powerEnabled ? "On" : "Off") : "Read only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func powerButton(snapshot: WatchSnapshot, state: ClimateState) -> some View {
        Button {
            session.setPower(!state.powerEnabled)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 38, height: 38)
                .background(state.powerEnabled ? Color.green : Color.secondary.opacity(0.25), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!snapshot.canWrite)
        .opacity(snapshot.canWrite ? 1 : 0.45)
        .accessibilityLabel(state.powerEnabled ? "Turn off" : "Turn on")
        .accessibilityIdentifier("watch.powerButton")
    }

    private func poweredOffView(snapshot: WatchSnapshot, state: ClimateState) -> some View {
        powerButton(snapshot: snapshot, state: state)
            .scaleEffect(1.35)
            .frame(maxWidth: .infinity, minHeight: 130)
    }

    private func temperatureControl(snapshot: WatchSnapshot, state: ClimateState) -> some View {
        let canAdjust = snapshot.canWrite && state.powerEnabled
        return Text(crownTemperature.formatted(.number.precision(.fractionLength(1))) + "°")
            .font(.system(size: 42, weight: .medium, design: .rounded))
            .minimumScaleFactor(0.75)
            .contentTransition(.numericText(value: crownTemperature))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
#if os(watchOS)
        .focusable(canAdjust)
        .digitalCrownRotation(
            crownBinding(enabled: canAdjust),
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
        .opacity(canAdjust ? 1 : 0.38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set temperature")
        .accessibilityValue(
            canAdjust
                ? crownTemperature.formatted(.number.precision(.fractionLength(1))) + " degrees"
                : "Unavailable while off"
        )
        .accessibilityIdentifier("watch.temperatureControl")
    }

    private func crownBinding(enabled: Bool) -> Binding<Double> {
        Binding(
            get: { crownTemperature },
            set: { value in
                guard enabled else { return }
                crownTemperature = value
            }
        )
    }

    private func schedulesControl(_ snapshot: WatchSnapshot) -> some View {
        Button {
            session.setSchedulesEnabled(!snapshot.allSchedulesEnabled)
        } label: {
            Image(systemName: snapshot.allSchedulesEnabled ? "calendar.badge.checkmark" : "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(snapshot.allSchedulesEnabled ? .green : .primary)
                .frame(width: 38, height: 38)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!snapshot.canWrite)
        .opacity(snapshot.canWrite ? 1 : 0.45)
        .accessibilityLabel(snapshot.allSchedulesEnabled ? "Turn schedules off" : "Turn schedules on")
        .accessibilityIdentifier("watch.schedulesButton")
    }

    private var unavailableView: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("Open iPhone app")
                .font(.caption.weight(.semibold))
            Button { session.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
