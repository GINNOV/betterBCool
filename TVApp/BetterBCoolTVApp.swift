// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import Foundation
import SwiftUI

#if canImport(Security)
import Security
#endif

@main
struct BetterBCoolTVApp: App {
    @StateObject private var appModel = TVAppModel()

    var body: some Scene {
        WindowGroup {
            TVRootView(model: appModel)
        }
    }
}

@MainActor
private final class TVAppModel: ObservableObject {
    struct PairingDisplay: Equatable {
        let sessionID: String
        let code: String
        let pollingSecret: String
        let expiresAt: Date
    }

    @Published var service: (any ClimateService)?
    @Published private(set) var session: TVStoredSession?
    @Published private(set) var pairing: PairingDisplay?
    @Published private(set) var isPairing = false
    @Published var message: String?

    private let sessionStore = TVSessionStore()
    private let pairingClient = TVPairingClient(baseURL: TVAppConfiguration.cloudBaseURL)

    init() {
        if let stored = sessionStore.load() {
            session = stored
            service = TVCloudClimateService(session: stored)
        }
    }

    var connectionLabel: String {
        if let session { return "LIVE · \(session.name.uppercased())" }
        return "LOCAL DEMO"
    }

    func useDemo() {
        session = nil
        service = DemoClimateService()
        message = nil
    }

    func startPairing() async {
        guard !isPairing else { return }
        isPairing = true
        message = nil
        do {
            let response = try await pairingClient.start()
            pairing = PairingDisplay(
                sessionID: response.sessionID,
                code: response.code,
                pollingSecret: response.pollingSecret,
                expiresAt: response.expiresAt
            )
            while !Task.isCancelled, let current = pairing {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                let exchange = try await pairingClient.exchange(
                    sessionID: current.sessionID,
                    pollingSecret: current.pollingSecret
                )
                if let token = exchange.token, let device = exchange.device {
                    let stored = TVStoredSession(
                        baseURL: TVAppConfiguration.cloudBaseURL,
                        token: token,
                        deviceID: device.deviceID,
                        installationID: device.installationID,
                        name: device.name,
                        transport: TVAppConfiguration.defaultTransport,
                        region: TVAppConfiguration.defaultRegion
                    )
                    sessionStore.save(stored)
                    session = stored
                    service = TVCloudClimateService(session: stored)
                    pairing = nil
                    message = "TV connected"
                    break
                }
            }
        } catch {
            pairing = nil
            message = "Pairing is unavailable right now. Try the demo or try again later."
        }
        isPairing = false
    }

    func cancelPairing() {
        pairing = nil
        isPairing = false
    }

    func disconnect() {
        sessionStore.remove()
        session = nil
        service = nil
        message = "This TV is disconnected"
    }
}

private struct TVRootView: View {
    @ObservedObject var model: TVAppModel

    var body: some View {
        Group {
            if let service = model.service {
                if model.session == nil {
                    TVClimateDashboard(service: service, connectionLabel: model.connectionLabel, onDisconnect: nil)
                } else {
                    TVClimateDashboard(service: service, connectionLabel: model.connectionLabel, onDisconnect: model.disconnect)
                }
            } else {
                TVWelcomeView(model: model)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct TVWelcomeView: View {
    @ObservedObject var model: TVAppModel

    var body: some View {
        ZStack {
            TVBackground(isOn: true)
            VStack(spacing: 36) {
                Image(systemName: "snowflake.circle.fill")
                    .font(.system(size: 118, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, TVColors.accent)
                    .shadow(color: TVColors.accent.opacity(0.7), radius: 35)

                VStack(spacing: 10) {
                    Text("betterBCool")
                        .font(.system(size: 74, weight: .bold, design: .rounded))
                    Text("A calmer climate dashboard for the biggest screen")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }

                if let pairing = model.pairing {
                    pairingCard(pairing)
                } else {
                    HStack(spacing: 26) {
                        Button {
                            Task { await model.startPairing() }
                        } label: {
                            Label("Pair with iPhone", systemImage: "iphone.and.arrow.forward")
                                .frame(minWidth: 310, minHeight: 84)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TVColors.accent)

                        Button {
                            model.useDemo()
                        } label: {
                            Label("Explore Demo", systemImage: "sparkles.tv")
                                .frame(minWidth: 250, minHeight: 84)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if model.isPairing {
                    ProgressView("Starting secure pairing…")
                        .controlSize(.large)
                        .tint(.white)
                }
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.66))
                }
            }
            .padding(80)
        }
    }

    private func pairingCard(_ pairing: TVAppModel.PairingDisplay) -> some View {
        VStack(spacing: 18) {
            Text("On your iPhone")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))
            Text("Open betterBCool → Settings → TVs")
                .font(.system(size: 28, weight: .medium))
            Text(pairing.code)
                .font(.system(size: 86, weight: .bold, design: .rounded))
                .tracking(12)
                .foregroundStyle(TVColors.mint)
                .accessibilityLabel("Pairing code \(pairing.code)")
            Text("This code expires in five minutes")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Button("Cancel") { model.cancelPairing() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 70)
        .padding(.vertical, 36)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 2) }
    }
}

@MainActor
private final class TVClimateViewModel: ObservableObject {
    @Published private(set) var device: ClimateDevice?
    @Published private(set) var capabilities: ClimateCapabilities?
    @Published private(set) var state: ClimateState?
    @Published private(set) var isLoading = false
    @Published private(set) var isApplying = false
    @Published var message: String?

    private let service: any ClimateService

    init(service: any ClimateService) {
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let device = try await service.devices().first else {
                message = "No climate unit is available."
                return
            }
            self.device = device
            async let capabilities = service.capabilities(for: device.id)
            async let state = service.state(for: device.id)
            self.capabilities = try await capabilities
            self.state = try await state
            message = nil
        } catch {
            message = "Climate data could not be loaded."
        }
    }

    func apply(_ patch: ClimatePatch) async {
        guard !isApplying, let device, let capabilities, let currentState = state else { return }
        guard currentState.powerEnabled || patch.powerEnabled == true else { return }
        do {
            try capabilities.validate(patch)
            // Reflect the command immediately so the TV feels local. The cloud
            // confirmation arrives in the background and replaces this state.
            state = currentState.applying(patch)
            isApplying = true
            defer { isApplying = false }
            let confirmedState = try await service.apply(patch, to: device.id)
            // Some HVAC transports acknowledge a power command before their
            // readback catches up. Keep the requested value authoritative for
            // this render so controls do not flash back after turning off.
            state = confirmedState.applying(patch)
            message = "Change confirmed"
        } catch {
            state = currentState
            message = "That change could not be applied."
        }
    }

    func adjustTemperature(by delta: Double) async {
        guard let current = state?.temperatureSetpoint, let capabilities else { return }
        let next = min(max(current + delta, capabilities.minimumSetpoint), capabilities.maximumSetpoint)
        await apply(.init(temperatureSetpoint: next))
    }
}

private struct TVClimateDashboard: View {
    @StateObject private var model: TVClimateViewModel
    @FocusState private var focusedControl: TVControlID?
    let connectionLabel: String
    let onDisconnect: (() -> Void)?

    init(service: any ClimateService, connectionLabel: String, onDisconnect: (() -> Void)?) {
        _model = StateObject(wrappedValue: TVClimateViewModel(service: service))
        self.connectionLabel = connectionLabel
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        ZStack {
            TVBackground(isOn: model.state?.powerEnabled == true)
            Group {
                if let state = model.state {
                    dashboard(state)
                } else if model.isLoading {
                    ProgressView("Loading Living Room")
                        .controlSize(.extraLarge)
                } else {
                    ContentUnavailableView {
                        Label("Climate unavailable", systemImage: "snowflake")
                    } description: {
                        Text(model.message ?? "Try loading the dashboard again.")
                    } actions: {
                        Button("Try Again") { Task { await model.load() } }
                    }
                }
            }
            .padding(.horizontal, 76)
            .padding(.vertical, 54)
        }
        .task { await model.load() }
        .defaultFocus($focusedControl, .power)
        .onChange(of: model.state?.powerEnabled) { _, isOn in
            if isOn == false { focusedControl = .power }
        }
    }

    private func dashboard(_ state: ClimateState) -> some View {
        VStack(spacing: 34) {
            header(state)
            climateHero(state)
            controlShelf(state)
            if let message = model.message {
                Text(message)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .transition(.opacity)
            }
        }
    }

    private func header(_ state: ClimateState) -> some View {
        HStack(spacing: 20) {
            Image(systemName: "snowflake.circle.fill")
                .font(.system(size: 64, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, TVColors.accent)
                .shadow(color: TVColors.accent.opacity(0.65), radius: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("betterBCool")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                Text(connectionLabel)
                    .font(.system(size: 23, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(TVColors.mint)
            if let roomTemperature = state.roomTemperature {
                Text("Room \(roomTemperature, specifier: "%.1f")°")
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }
            if let onDisconnect {
                Button { onDisconnect() } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Disconnect this TV")
            }
        }
    }

    private func climateHero(_ state: ClimateState) -> some View {
        HStack(spacing: 48) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(state.powerEnabled ? TVColors.mint : TVColors.off)
                        .frame(width: 14, height: 14)
                    Text(state.powerEnabled ? "LIVING ROOM · ON" : "LIVING ROOM · OFF")
                        .font(.system(size: 25, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.72))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.temperatureSetpoint.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 124, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("°")
                        .font(.system(size: 58, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("Set temperature")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
            if state.powerEnabled {
                HStack(spacing: 22) {
                    Button {
                        Task { await model.adjustTemperature(by: -(model.capabilities?.setpointStep ?? 0.5)) }
                    } label: {
                        Label("Cooler", systemImage: "minus").frame(minWidth: 150, minHeight: 70)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Lowers the target temperature")
                    Button {
                        Task { await model.adjustTemperature(by: model.capabilities?.setpointStep ?? 0.5) }
                    } label: {
                        Label("Warmer", systemImage: "plus").frame(minWidth: 150, minHeight: 70)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TVColors.accent)
                    .accessibilityHint("Raises the target temperature")
                }
            } else {
                Text("Turn on the unit to adjust temperature")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(width: 330)
            }
            VStack(spacing: 14) {
                Image(systemName: state.operatingMode.symbol)
                    .font(.system(size: 78, weight: .medium))
                Text(state.operatingMode.title).font(.system(size: 32, weight: .bold))
                Text(state.fanSpeed.map { "\($0.title) fan" } ?? "Fan unavailable")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(width: 250)
        }
        .padding(.horizontal, 54)
        .padding(.vertical, 38)
        .background {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(LinearGradient(
                    colors: state.powerEnabled
                        ? [TVColors.accent.opacity(0.72), TVColors.deepBlue.opacity(0.92)]
                        : [TVColors.off.opacity(0.7), Color.black.opacity(0.84)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay { RoundedRectangle(cornerRadius: 42, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 2) }
        }
        .shadow(color: (state.powerEnabled ? TVColors.accent : TVColors.off).opacity(0.22), radius: 22, y: 10)
    }

    private func controlShelf(_ state: ClimateState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            controlRow(title: state.powerEnabled ? "Power & mode" : "Power", symbol: "slider.horizontal.3") {
                TVControlCard(title: state.powerEnabled ? "Turn Off" : "Turn On", detail: "Power", symbol: "power", tint: state.powerEnabled ? TVColors.off : TVColors.mint) {
                    Task { await model.apply(.init(powerEnabled: !state.powerEnabled)) }
                }
                .focused($focusedControl, equals: .power)
                if state.powerEnabled {
                    ForEach(OperatingMode.allCases, id: \.self) { mode in
                        if model.capabilities?.operatingModes.contains(mode) == true {
                            TVControlCard(title: mode.title, detail: "Mode", symbol: mode.symbol, tint: state.operatingMode == mode ? TVColors.accent : .white.opacity(0.8)) {
                                Task { await model.apply(.init(operatingMode: mode)) }
                            }
                            .focused($focusedControl, equals: .mode(mode))
                        }
                    }
                }
            }

            if state.powerEnabled {
                controlRow(title: "Fan speed", symbol: "wind") {
                    ForEach(FanSpeed.allCases, id: \.self) { fan in
                        if model.capabilities?.fanSpeeds.contains(fan) == true {
                            TVControlCard(title: fan.title, detail: "Fan", symbol: "wind", tint: state.fanSpeed == fan ? TVColors.mint : .white.opacity(0.8)) {
                                Task { await model.apply(.init(fanSpeed: fan)) }
                            }
                            .focused($focusedControl, equals: .fan(fan))
                        }
                    }
                }

                controlRow(title: "Comfort & airflow", symbol: "arrow.triangle.2.circlepath") {
                    TVControlCard(title: state.ecoEnabled ? "Eco On" : "Eco Off", detail: "Comfort", symbol: "leaf.fill", tint: state.ecoEnabled ? TVColors.mint : .white.opacity(0.8)) {
                        Task { await model.apply(.init(ecoEnabled: !state.ecoEnabled)) }
                    }
                    .focused($focusedControl, equals: .eco)
                    TVControlCard(title: state.sleepEnabled ? "Sleep On" : "Sleep Off", detail: "Comfort", symbol: "moon.stars.fill", tint: state.sleepEnabled ? .purple : .white.opacity(0.8)) {
                        Task { await model.apply(.init(sleepEnabled: !state.sleepEnabled)) }
                    }
                    .focused($focusedControl, equals: .sleep)
                    TVControlCard(title: state.horizontalSwingEnabled ? "Swing On" : "Swing Off", detail: "Horizontal", symbol: "arrow.left.and.right", tint: state.horizontalSwingEnabled ? TVColors.accent : .white.opacity(0.8)) {
                        Task { await model.apply(.init(horizontalSwingEnabled: !state.horizontalSwingEnabled)) }
                    }
                    .focused($focusedControl, equals: .horizontalSwing)
                    TVControlCard(title: state.verticalSwingEnabled ? "Swing On" : "Swing Off", detail: "Vertical", symbol: "arrow.up.and.down", tint: state.verticalSwingEnabled ? TVColors.accent : .white.opacity(0.8)) {
                        Task { await model.apply(.init(verticalSwingEnabled: !state.verticalSwingEnabled)) }
                    }
                    .focused($focusedControl, equals: .verticalSwing)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func controlRow<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 17, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.48))
                .frame(height: TVLayout.rowLabelHeight, alignment: .leading)

            HStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                minHeight: TVLayout.cardHeight,
                maxHeight: TVLayout.cardHeight,
                alignment: .leading
            )
            .focusSection()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(
            minHeight: TVLayout.rowHeight,
            maxHeight: TVLayout.rowHeight,
            alignment: .topLeading
        )
    }
}

private enum TVLayout {
    static let cardWidth: CGFloat = 210
    static let cardHeight: CGFloat = 104
    static let cardSpacing: CGFloat = 14
    static let rowLabelHeight: CGFloat = 22
    static let rowHeight: CGFloat = rowLabelHeight + 8 + cardHeight
}

private enum TVControlID: Hashable {
    case power
    case mode(OperatingMode)
    case fan(FanSpeed)
    case eco
    case sleep
    case horizontalSwing
    case verticalSwing
}

private extension ClimateState {
    func applying(_ patch: ClimatePatch) -> ClimateState {
        var updated = self
        if let powerEnabled = patch.powerEnabled { updated.powerEnabled = powerEnabled }
        if let operatingMode = patch.operatingMode { updated.operatingMode = operatingMode }
        if let fanSpeed = patch.fanSpeed { updated.fanSpeed = fanSpeed }
        if let temperatureSetpoint = patch.temperatureSetpoint { updated.temperatureSetpoint = temperatureSetpoint }
        if let ecoEnabled = patch.ecoEnabled { updated.ecoEnabled = ecoEnabled }
        if let sleepEnabled = patch.sleepEnabled { updated.sleepEnabled = sleepEnabled }
        if let horizontalSwingEnabled = patch.horizontalSwingEnabled { updated.horizontalSwingEnabled = horizontalSwingEnabled }
        if let verticalSwingEnabled = patch.verticalSwingEnabled { updated.verticalSwingEnabled = verticalSwingEnabled }
        updated.timestamp = Date()
        return updated
    }
}

private struct TVControlCard: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: isFocused
                        ? [tint.opacity(0.24), TVColors.deepBlue.opacity(0.78)]
                        : [.white.opacity(0.1), TVColors.deepBlue.opacity(0.52)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(height: 36, alignment: .top)

                    Spacer(minLength: 0)

                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(detail.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            .frame(width: TVLayout.cardWidth, height: TVLayout.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isFocused ? tint.opacity(0.95) : .white.opacity(0.1), lineWidth: isFocused ? 2 : 1)
                    .padding(isFocused ? 2 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: TVLayout.cardWidth, height: TVLayout.cardHeight)
        .fixedSize()
        .buttonStyle(.plain)
        .focusEffectDisabled(true)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel("\(detail), \(title)")
    }
}

private struct TVBackground: View {
    let isOn: Bool
    @State private var ambientPhase = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [TVColors.navy, TVColors.deepBlue, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(
                colors: [(isOn ? TVColors.accent : TVColors.off).opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 640
            )
            RadialGradient(
                colors: [TVColors.accent.opacity(0.08), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 720
            )

            if isOn {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [TVColors.accent.opacity(0.28), TVColors.accent.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 330
                        )
                    )
                    .frame(width: 660, height: 660)
                    .blur(radius: 34)
                    .scaleEffect(ambientPhase ? 1.1 : 0.88)
                    .offset(
                        x: ambientPhase ? 470 : 210,
                        y: ambientPhase ? -245 : -70
                    )
                    .animation(
                        .easeInOut(duration: 11).repeatForever(autoreverses: true),
                        value: ambientPhase
                    )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [TVColors.mint.opacity(0.13), TVColors.mint.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 260
                        )
                    )
                    .frame(width: 520, height: 520)
                    .blur(radius: 48)
                    .scaleEffect(ambientPhase ? 0.86 : 1.08)
                    .offset(
                        x: ambientPhase ? -500 : -250,
                        y: ambientPhase ? 290 : 420
                    )
                    .animation(
                        .easeInOut(duration: 14).repeatForever(autoreverses: true),
                        value: ambientPhase
                    )

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.clear, TVColors.accent.opacity(0.13), TVColors.mint.opacity(0.07), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 1_050, height: 170)
                    .blur(radius: 42)
                    .rotationEffect(.degrees(ambientPhase ? 12 : -9))
                    .offset(
                        x: ambientPhase ? -260 : 280,
                        y: ambientPhase ? 270 : 150
                    )
                    .animation(
                        .easeInOut(duration: 16).repeatForever(autoreverses: true),
                        value: ambientPhase
                    )
                    .allowsHitTesting(false)
                    .onAppear { ambientPhase = true }
                    .onDisappear { ambientPhase = false }
            }
        }
        .ignoresSafeArea()
    }
}

private enum TVColors {
    static let navy = Color(red: 0.015, green: 0.035, blue: 0.13)
    static let deepBlue = Color(red: 0.02, green: 0.12, blue: 0.33)
    static let accent = Color(red: 0.05, green: 0.55, blue: 1.0)
    static let mint = Color(red: 0.22, green: 0.93, blue: 0.74)
    static let off = Color(red: 0.92, green: 0.2, blue: 0.28)
}

private extension OperatingMode {
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .auto: "a.circle.fill"
        case .cool: "snowflake"
        case .dry: "drop.fill"
        case .fan: "fan.fill"
        case .heat: "sun.max.fill"
        }
    }
}

private extension FanSpeed {
    var title: String { rawValue.capitalized }
}

private enum TVAppConfiguration {
    static let cloudBaseURL = URL(string: "https://betterbcool-cloud.vercel.app")!
    static let defaultTransport = "bacon"
    static let defaultRegion = "euc1"
}

private struct TVPairingStartResponse: Decodable {
    let sessionID: String
    let code: String
    let pollingSecret: String
    let expiresAt: Date
}

private struct TVPairingExchangeResponse: Decodable {
    struct Device: Decodable {
        let deviceID: String
        let installationID: String
        let name: String
    }
    let status: String
    let token: String?
    let device: Device?
}

private struct TVPairingClient: Sendable {
    let baseURL: URL
    let session: URLSession
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func start() async throws -> TVPairingStartResponse {
        try await request(path: "api/tv/pair/start", method: "POST", body: Optional<String>.none, response: TVPairingStartResponse.self)
    }

    func exchange(sessionID: String, pollingSecret: String) async throws -> TVPairingExchangeResponse {
        try await request(path: "api/tv/pair/exchange", method: "POST", body: ["sessionID": sessionID, "pollingSecret": pollingSecret], response: TVPairingExchangeResponse.self, allowsPending: true)
    }

    private func request<Body: Encodable, Response: Decodable>(path: String, method: String, body: Body, response: Response.Type, allowsPending: Bool = false) async throws -> Response {
        guard baseURL.scheme == "https" || baseURL.host == "localhost" else { throw CloudClimateError.insecureURL }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData = try? encoder.encode(body) {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudClimateError.invalidResponse }
        if allowsPending && http.statusCode == 202 {
            return try decoder.decode(Response.self, from: data)
        }
        guard (200..<300).contains(http.statusCode) else { throw CloudClimateError.httpStatus(http.statusCode, nil) }
        return try decoder.decode(Response.self, from: data)
    }
}

private struct TVStoredSession: Codable, Sendable {
    let baseURL: URL
    let token: String
    let deviceID: String
    let installationID: String
    let name: String
    let transport: String
    let region: String
}

private final class TVSessionStore: Sendable {
    private let service = "dev.betterbcool.tv.session"
    private let account = "default"

    func load() -> TVStoredSession? {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TVStoredSession.self, from: data)
        #else
        return nil
        #endif
    }

    func save(_ session: TVStoredSession) {
        #if canImport(Security)
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var item = query
            item.merge(attributes) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
        #endif
    }

    func remove() {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}

private actor TVCloudClimateService: ClimateService {
    private let session: TVStoredSession
    private let urlSession: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(session: TVStoredSession, urlSession: URLSession = .shared) {
        self.session = session
        self.urlSession = urlSession
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func devices() async throws -> [ClimateDevice] {
        [ClimateDevice(id: session.deviceID, name: session.name)]
    }

    func capabilities(for deviceID: String) async throws -> ClimateCapabilities {
        try verify(deviceID)
        if session.transport == "bacon" {
            return .init(canWrite: true, operatingModes: Set(OperatingMode.allCases), fanSpeeds: Set(FanSpeed.allCases), minimumSetpoint: 16, maximumSetpoint: 30, setpointStep: 0.5)
        }
        return .init(canWrite: true, operatingModes: Set(OperatingMode.allCases), fanSpeeds: [.auto, .quiet, .low, .medium], minimumSetpoint: 15, maximumSetpoint: 32.5, setpointStep: 0.5)
    }

    func state(for deviceID: String) async throws -> ClimateState {
        try verify(deviceID)
        return try await request(path: "api/tv/climate/state", method: "GET", response: ClimateState.self)
    }

    func apply(_ patch: ClimatePatch, to deviceID: String) async throws -> ClimateState {
        try verify(deviceID)
        try await capabilities(for: deviceID).validate(patch)
        return try await request(path: "api/tv/climate/apply", method: "PUT", body: patch, response: ClimateState.self)
    }

    private func verify(_ deviceID: String) throws {
        guard deviceID == session.deviceID else { throw ClimateServiceError.deviceNotFound }
    }

    private func request<Response: Decodable>(path: String, method: String, response: Response.Type) async throws -> Response {
        try await request(path: path, method: method, encodedBody: nil, response: response)
    }

    private func request<Body: Encodable, Response: Decodable>(path: String, method: String, body: Body, response: Response.Type) async throws -> Response {
        try await request(path: path, method: method, encodedBody: try encoder.encode(body), response: response)
    }

    private func request<Response: Decodable>(path: String, method: String, encodedBody: Data?, response: Response.Type) async throws -> Response {
        guard session.baseURL.scheme == "https" || session.baseURL.host == "localhost" else { throw CloudClimateError.insecureURL }
        var request = URLRequest(url: session.baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("TVBearer \(session.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let encodedBody {
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudClimateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? decoder.decode(TVErrorResponse.self, from: data)
            throw CloudClimateError.httpStatus(http.statusCode, error?.error)
        }
        guard let decoded = try? decoder.decode(Response.self, from: data) else { throw CloudClimateError.invalidResponse }
        return decoded
    }
}

private struct TVErrorResponse: Decodable { let error: String }
