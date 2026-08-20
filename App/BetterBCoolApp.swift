// SPDX-License-Identifier: Apache-2.0

import AuthenticationServices
import BetterBCoolCore
import BetterBCoolUI
import OSLog
import Security
import SwiftUI
import UIKit

@main
struct BetterBCoolApp: App {
    @StateObject private var configuration = AppConfiguration()

    var body: some Scene {
        WindowGroup { AppRootView(configuration: configuration) }
    }
}

private struct AppRootView: View {
    @ObservedObject var configuration: AppConfiguration
    @StateObject private var bodyTemperature = BodyTemperatureManager.shared
    @StateObject private var signInCoordinator = SingleKeySignInCoordinator()
    @StateObject private var watchSession: WatchSessionManager
    @State private var isShowingSettings = false

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        _watchSession = StateObject(wrappedValue: WatchSessionManager(configuration: configuration))
    }

    var body: some View {
        ZStack {
            ClimateDashboard(
                service: configuration.service,
                remoteScheduler: configuration.remoteScheduler,
                bodyTemperature: bodyTemperature,
                onSettingsTapped: { isShowingSettings = true },
                onReconnectTapped: {
                    Task { await signInCoordinator.signIn(configuration: configuration) }
                }
            )
                .id(configuration.revision)
        }
            .sheet(isPresented: $isShowingSettings, onDismiss: {
                Task { @MainActor in
                    await Task.yield()
                    configuration.reloadDashboard()
                }
            }) {
                NavigationStack {
                    SettingsView(
                        configuration: configuration,
                        bodyTemperature: bodyTemperature,
                        onFinished: { isShowingSettings = false }
                    )
                }
            }
            .alert(
                "Bosch sign-in failed",
                isPresented: Binding(
                    get: { signInCoordinator.errorMessage != nil },
                    set: { if !$0 { signInCoordinator.clearError() } }
                )
            ) {
                Button("OK") { signInCoordinator.clearError() }
            } message: {
                Text(signInCoordinator.errorMessage ?? "")
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-wrist-temperature-preview") {
                    bodyTemperature.loadPreviewSnapshot()
                } else {
                    bodyTemperature.startMonitoring()
                    await bodyTemperature.refresh()
                }
            }
            .onChange(of: bodyTemperature.snapshot?.sampleID, initial: true) { _, _ in
                evaluateCurrentBodyTemperature()
            }
            .onChange(of: configuration.bodyTemperatureAutomationEnabled) { _, _ in
                evaluateCurrentBodyTemperature()
            }
            .onChange(of: configuration.bodyTemperatureDeltaThreshold) { _, _ in
                evaluateCurrentBodyTemperature()
            }
    }

    private func evaluateCurrentBodyTemperature() {
        guard let snapshot = bodyTemperature.snapshot else { return }
        Task { await configuration.evaluateBodyTemperatureAutomation(snapshot) }
    }
}

@MainActor
final class AppConfiguration: ObservableObject {
    private static let logger = Logger(subsystem: "dev.betterbcool.app", category: "BoschDiscovery")

    @Published private(set) var gatewayID: String
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var revision = UUID()
    @Published private(set) var backend: Backend
    @Published private(set) var baconRegion: BaconRegion
    @Published private(set) var cloudEnabled: Bool
    @Published private(set) var cloudURL: String
    @Published var bodyTemperatureAutomationEnabled: Bool {
        didSet { UserDefaults.standard.set(bodyTemperatureAutomationEnabled, forKey: Key.bodyTemperatureAutomation) }
    }
    @Published var bodyTemperatureDeltaThreshold: Double {
        didSet { UserDefaults.standard.set(bodyTemperatureDeltaThreshold, forKey: Key.bodyTemperatureThreshold) }
    }
    @Published private(set) var bodyTemperatureAutomationMessage: String?

    fileprivate let oauthClient = SingleKeyOAuthClient()
    fileprivate let tokenStore = KeychainOAuthTokenStore()
    fileprivate let cloudSecretStore = KeychainStringStore(account: "vercel-cloud-api-key")
    let installationID: String

    private enum Key {
        static let gatewayID = "gatewayID"
        static let backend = "backend"
        static let baconRegion = "baconRegion"
        static let cloudEnabled = "cloudEnabled"
        static let cloudURL = "cloudURL"
        static let installationID = "cloudInstallationID"
        static let bodyTemperatureAutomation = "bodyTemperatureAutomationEnabled"
        static let bodyTemperatureThreshold = "bodyTemperatureDeltaThreshold"
        static let bodyTemperatureLastSample = "bodyTemperatureLastActivatedSample"
        static let scheduleStorage = "betterBCool.climateSchedules.v1"
    }

    enum Backend: String { case pointT, bacon }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Key.scheduleStorage)
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-with-active-power-on-schedule") {
                let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
                let currentMinute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                let schedule = ClimateSchedule(
                    name: "Startup regression",
                    startMinutes: max(0, currentMinute - 1),
                    weekdays: Set(ScheduleWeekday.allCases),
                    steps: [
                        ClimateScheduleStep(
                            name: "Turn on",
                            patch: ClimatePatch(powerEnabled: true)
                        )
                    ]
                )
                if let data = try? JSONEncoder().encode([schedule]) {
                    defaults.set(data, forKey: Key.scheduleStorage)
                }
            }
            gatewayID = ""
            isSignedIn = false
            backend = .pointT
            baconRegion = .europe
            cloudEnabled = false
            cloudURL = ""
            bodyTemperatureAutomationEnabled = false
            bodyTemperatureDeltaThreshold = 0.5
            bodyTemperatureAutomationMessage = nil
            installationID = "ui-testing-installation"
        } else {
            let startupGatewayID = UserDefaults.standard.string(forKey: Key.gatewayID) ?? ""
            gatewayID = startupGatewayID
            let storedBackend = UserDefaults.standard.string(forKey: Key.backend)
                .flatMap(Backend.init(rawValue:))
            backend = storedBackend ?? .pointT
            baconRegion = BaconRegion(rawValue: UserDefaults.standard.string(forKey: Key.baconRegion) ?? "") ?? .europe
            cloudEnabled = UserDefaults.standard.bool(forKey: Key.cloudEnabled)
            cloudURL = UserDefaults.standard.string(forKey: Key.cloudURL)
                ?? "https://betterbcool-cloud.vercel.app"
            bodyTemperatureAutomationEnabled = UserDefaults.standard.bool(forKey: Key.bodyTemperatureAutomation)
            let savedTemperatureThreshold = UserDefaults.standard.double(forKey: Key.bodyTemperatureThreshold)
            bodyTemperatureDeltaThreshold = savedTemperatureThreshold > 0 ? savedTemperatureThreshold : 0.5
            bodyTemperatureAutomationMessage = nil
            let storedInstallationID = UserDefaults.standard.string(forKey: Key.installationID)
            installationID = storedInstallationID ?? UUID().uuidString
            if storedInstallationID == nil {
                UserDefaults.standard.set(installationID, forKey: Key.installationID)
            }
            let startupTokenStore = KeychainOAuthTokenStore()
            let hasTokens = (try? startupTokenStore.loadTokens()) != nil
            let canResumeSession = storedBackend != nil && !startupGatewayID.isEmpty
            isSignedIn = hasTokens && canResumeSession
            if hasTokens && !canResumeSession {
                Self.logger.notice("Removing legacy or incomplete sign-in state so transport discovery can run")
                try? startupTokenStore.deleteTokens()
            }
            if storedBackend == nil && !startupGatewayID.isEmpty {
                gatewayID = ""
                UserDefaults.standard.removeObject(forKey: Key.gatewayID)
            }
        }
        if !isSignedIn || cloudConfiguration == nil { cloudEnabled = false }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-keychain-self-test") {
            let store = KeychainOAuthTokenStore(
                service: "dev.betterbcool.app.self-test",
                account: "temporary-oauth-tokens"
            )
            let logger = Self.logger
            Task.detached {
                do {
                    let expected = OAuthTokens(
                        accessToken: "self-test-access",
                        refreshToken: "self-test-refresh",
                        expiresAt: Date().addingTimeInterval(300)
                    )
                    try store.saveTokens(expected)
                    guard try store.loadTokens() == expected else { throw KeychainError.selfTestMismatch }
                    try store.deleteTokens()
                    logger.notice("Keychain self-test passed")
                } catch {
                    logger.error("Keychain self-test failed: \(String(reflecting: error), privacy: .public)")
                }
            }
        }
        #endif
    }

    var service: any ClimateService {
        guard isSignedIn, !gatewayID.isEmpty else {
            let startsPoweredOff = ProcessInfo.processInfo.arguments.contains("-ui-testing-power-off")
            return DemoClimateService(initialPowerEnabled: !startsPoweredOff)
        }
        if cloudEnabled, let cloudConfiguration {
            return recoveringCloudService(configuration: cloudConfiguration)
        }
        let provider = RefreshingAccessTokenProvider(client: oauthClient, store: tokenStore)
        switch backend {
        case .pointT:
            return PointTClimateService(api: PointTAPI(tokenProvider: provider), deviceID: gatewayID)
        case .bacon:
            return BaconClimateService(tokenProvider: provider, deviceID: gatewayID, region: baconRegion)
        }
    }

    var remoteScheduler: (any ClimateScheduleRemoteService)? {
        guard cloudEnabled, let cloudConfiguration else { return nil }
        return recoveringCloudService(configuration: cloudConfiguration)
    }

    func handleWatchRequest(_ request: WatchRequest) async -> WatchSnapshot {
        guard isSignedIn else {
            return watchSnapshot(errorMessage: String(localized: "Open betterBCool on your iPhone to connect Bosch."))
        }

        let climateService = service
        do {
            var changedState: ClimateState?
            switch request.action {
            case .refresh:
                break
            case .togglePower:
                guard let device = try await climateService.devices().first else {
                    throw ClimateServiceError.deviceNotFound
                }
                let state = try await climateService.state(for: device.id)
                var appliedState = try await climateService.apply(
                    ClimatePatch(powerEnabled: !state.powerEnabled),
                    to: device.id
                )
                appliedState.powerEnabled = !state.powerEnabled
                changedState = appliedState
            case .setPower:
                guard let enabled = request.powerEnabled,
                      let device = try await climateService.devices().first else {
                    throw ClimateServiceError.unsupportedValue
                }
                var appliedState = try await climateService.apply(
                    ClimatePatch(powerEnabled: enabled),
                    to: device.id
                )
                appliedState.powerEnabled = enabled
                changedState = appliedState
            case .setTemperature:
                guard let temperature = request.temperature, temperature.isFinite,
                      let device = try await climateService.devices().first else {
                    throw ClimateServiceError.unsupportedValue
                }
                let capabilities = try await climateService.capabilities(for: device.id)
                try capabilities.validate(ClimatePatch(temperatureSetpoint: temperature))
                var appliedState = try await climateService.apply(
                    ClimatePatch(temperatureSetpoint: temperature),
                    to: device.id
                )
                appliedState.temperatureSetpoint = temperature
                changedState = appliedState
            case .setSchedulesEnabled:
                guard let enabled = request.schedulesEnabled else {
                    throw ClimateServiceError.unsupportedValue
                }
                try await setAllSchedulesEnabled(enabled)
            }
            if let changedState {
                NotificationCenter.default.post(
                    name: .betterBCoolClimateStateDidChange,
                    object: changedState
                )
            }
            return await watchSnapshot(using: climateService, overriding: changedState)
        } catch let error as CloudClimateError where error.requiresBoschReauthentication {
            return watchSnapshot(errorMessage: String(localized: "Reconnect Bosch on your iPhone to continue."))
        } catch ClimateServiceError.unsupportedValue {
            return watchSnapshot(errorMessage: String(localized: "That setting is not supported by this air conditioner."))
        } catch {
            return watchSnapshot(errorMessage: String(localized: "The iPhone could not reach the air conditioner."))
        }
    }

    func watchSnapshot() async -> WatchSnapshot {
        await watchSnapshot(overriding: nil)
    }

    func watchSnapshot(overriding state: ClimateState?) async -> WatchSnapshot {
        guard isSignedIn else {
            return watchSnapshot(errorMessage: String(localized: "Open betterBCool on your iPhone to connect Bosch."))
        }
        return await watchSnapshot(using: service, overriding: state)
    }

    private func watchSnapshot(errorMessage: String) -> WatchSnapshot {
        let schedules = storedSchedules()
        return WatchSnapshot(
            schedules: schedules.map(WatchScheduleSummary.init),
            nextScheduleDate: ClimateScheduleTimeline.nextEvent(in: schedules, after: Date())?.date,
            errorMessage: errorMessage
        )
    }

    private func watchSnapshot(
        using climateService: any ClimateService,
        overriding stateOverride: ClimateState? = nil
    ) async -> WatchSnapshot {
        let schedules = storedSchedules()
        do {
            guard let device = try await climateService.devices().first else {
                return WatchSnapshot(
                    schedules: schedules.map(WatchScheduleSummary.init),
                    nextScheduleDate: ClimateScheduleTimeline.nextEvent(in: schedules, after: Date())?.date,
                    errorMessage: String(localized: "No air conditioner is available.")
                )
            }
            async let fetchedCapabilities = climateService.capabilities(for: device.id)
            let capabilities = try await fetchedCapabilities
            let state: ClimateState
            if let stateOverride {
                state = stateOverride
            } else {
                state = try await climateService.state(for: device.id)
            }
            return WatchSnapshot(
                deviceName: device.name,
                state: state,
                canWrite: capabilities.canWrite,
                minimumSetpoint: capabilities.minimumSetpoint,
                maximumSetpoint: capabilities.maximumSetpoint,
                setpointStep: capabilities.setpointStep,
                schedules: schedules.map(WatchScheduleSummary.init),
                nextScheduleDate: ClimateScheduleTimeline.nextEvent(in: schedules, after: Date())?.date
            )
        } catch let error as CloudClimateError where error.requiresBoschReauthentication {
            return watchSnapshot(errorMessage: String(localized: "Reconnect Bosch on your iPhone to continue."))
        } catch {
            return watchSnapshot(errorMessage: String(localized: "The iPhone could not reach the air conditioner."))
        }
    }

    private func storedSchedules() -> [ClimateSchedule] {
        guard let data = UserDefaults.standard.data(forKey: Key.scheduleStorage),
              let schedules = try? JSONDecoder().decode([ClimateSchedule].self, from: data) else {
            return []
        }
        return schedules.sorted { $0.startMinutes < $1.startMinutes }
    }

    private func setAllSchedulesEnabled(_ enabled: Bool) async throws {
        var schedules = storedSchedules()
        guard !schedules.isEmpty else { return }
        for index in schedules.indices {
            schedules[index].isEnabled = enabled
        }
        let data = try JSONEncoder().encode(schedules)
        UserDefaults.standard.set(data, forKey: Key.scheduleStorage)
        NotificationCenter.default.post(name: .betterBCoolSchedulesDidChange, object: nil)

        if let remoteScheduler {
            try await remoteScheduler.reconcile(
                schedules: schedules,
                timezone: TimeZone.current.identifier
            )
        }
    }

    private func recoveringCloudService(
        configuration: CloudClimateConfiguration
    ) -> CloudClimateService {
        let tokenStore = self.tokenStore
        return CloudClimateService(
            configuration: configuration,
            credentialRecovery: { try tokenStore.loadTokens() }
        )
    }

    var cloudAPIKey: String { (try? cloudSecretStore.load()) ?? "" }

    private var cloudConfiguration: CloudClimateConfiguration? {
        guard let url = URL(string: cloudURL), !cloudAPIKey.isEmpty, !gatewayID.isEmpty else { return nil }
        return CloudClimateConfiguration(
            baseURL: url,
            apiKey: cloudAPIKey,
            installationID: installationID,
            deviceID: gatewayID,
            transport: backend.rawValue,
            region: baconRegion.rawValue
        )
    }

    func completeSignIn(tokens: OAuthTokens, reloadDashboard: Bool = true) async throws {
        Self.logger.info("Bosch token exchange succeeded; starting PointT gateway discovery")
        // Discovery runs immediately after the token exchange, so use that fresh token
        // directly instead of making a redundant Keychain read through the refresh actor.
        let api = PointTAPI(accessToken: tokens.accessToken)
        let discovery: PointTGatewayDiscovery
        do {
            discovery = try await fetchGatewayDiscovery(accessToken: tokens.accessToken)
        } catch {
            Self.logger.error(
                "PointT gateway request failed: \(String(reflecting: error), privacy: .public)"
            )
            throw error
        }
        Self.logger.info(
            "PointT discovery returned \(discovery.returnedEntryCount, privacy: .public) entries; parsed \(discovery.gateways.count, privacy: .public) gateways"
        )
        guard discovery.returnedEntryCount > 0 else {
            let baconDevices = try await discoverBaconDevices(accessToken: tokens.accessToken)
            if !baconDevices.isEmpty {
                Self.logger.notice(
                    "Bacon discovery found \(baconDevices.count, privacy: .public) newer HomeCom devices"
                )
                let device = baconDevices[0]
                let mqtt = try BaconMQTTClient(accessToken: tokens.accessToken, region: device.region)
                let shadow = try await mqtt.readShadow(deviceID: device.id)
                let fields: [String]
                if case .object(let reported) = shadow.reported {
                    fields = reported.keys.sorted()
                } else {
                    fields = []
                }
                Self.logger.notice(
                    "Bacon shadow read succeeded with \(fields.count, privacy: .public) reported fields: \(fields.joined(separator: ","), privacy: .public)"
                )
                let tokenStore = self.tokenStore
                Self.logger.info("Bacon gateway verified; saving tokens to Keychain")
                try await Task.detached { try tokenStore.saveTokens(tokens) }.value
                Self.logger.info("Bacon tokens saved; enabling live HomeCom MQTT access")
                gatewayID = device.id
                backend = .bacon
                baconRegion = device.region
                isSignedIn = true
                await restoreCloudCredentialsIfNeeded(tokens: tokens)
                persistConfiguration(reloadDashboard: reloadDashboard)
                return
            }
            Self.logger.error("Discovery failed: PointT and Bacon returned zero device entries")
            throw SignInError.noGatewayEntries
        }
        guard !discovery.gateways.isEmpty else {
            Self.logger.error(
                "Discovery failed: none of \(discovery.returnedEntryCount, privacy: .public) gateway entries matched a known schema"
            )
            throw SignInError.unrecognizedGatewayEntries(discovery.returnedEntryCount)
        }
        guard let gateway = try await api.airConditioningGateway(from: discovery.gateways) else {
            Self.logger.error(
                "Discovery failed: \(discovery.gateways.count, privacy: .public) parsed gateways did not expose the classic AC resource"
            )
            throw SignInError.noCompatibleGateway(discovery.gateways.count)
        }
        Self.logger.info("Gateway verified; saving Bosch tokens to Keychain")
        let tokenStore = self.tokenStore
        try await Task.detached { try tokenStore.saveTokens(tokens) }.value
        Self.logger.info("Bosch tokens saved to Keychain")
        Self.logger.info("Compatible classic AC gateway discovered; enabling live access")
        gatewayID = gateway.id
        backend = .pointT
        isSignedIn = true
        await restoreCloudCredentialsIfNeeded(tokens: tokens)
        persistConfiguration(reloadDashboard: reloadDashboard)
    }

    private func restoreCloudCredentialsIfNeeded(tokens: OAuthTokens) async {
        guard cloudEnabled, let cloudConfiguration else { return }
        do {
            try await CloudClimateService(configuration: cloudConfiguration).syncCredentials(tokens: tokens)
        } catch {
            Self.logger.error(
                "Cloud credentials could not be restored after sign-in; using direct access: \(String(reflecting: error), privacy: .public)"
            )
            cloudEnabled = false
        }
    }

    private func fetchGatewayDiscovery(accessToken: String) async throws -> PointTGatewayDiscovery {
        let url = PointTAPI.productionBaseURL
            .appending(path: "pointt-api/api/v1/gateways")
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        Self.logger.info("Direct PointT gateway request started: \(url.path, privacy: .public)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PointTError.invalidResponse }
        Self.logger.info(
            "Direct PointT gateway response: \(http.statusCode, privacy: .public), \(data.count, privacy: .public) bytes"
        )
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw PointTError.unauthorized
            case 429: throw PointTError.rateLimited
            default: throw PointTError.httpStatus(http.statusCode)
            }
        }
        return try JSONDecoder().decode(JSONValue.self, from: data).pointTGatewayDiscovery
    }

    private func discoverBaconDevices(accessToken: String) async throws -> [BaconDevice] {
        let api = BaconAPI(accessToken: accessToken)
        for region in BaconRegion.allCases {
            do {
                let devices = try await api.devices(in: region)
                Self.logger.info(
                    "Bacon \(region.rawValue, privacy: .public) discovery returned \(devices.count, privacy: .public) devices"
                )
                if !devices.isEmpty { return devices }
            } catch BaconError.unauthorized {
                throw BaconError.unauthorized
            } catch {
                Self.logger.notice(
                    "Bacon \(region.rawValue, privacy: .public) discovery failed: \(String(reflecting: error), privacy: .public)"
                )
            }
        }
        return []
    }

    func saveAccessMode(
        cloudEnabled: Bool,
        cloudURL: String,
        cloudAPIKey: String,
        reloadDashboard: Bool = false
    ) async throws {
        let trimmedURL = cloudURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = cloudAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if cloudEnabled {
            guard let url = URL(string: trimmedURL), url.scheme == "https", !trimmedKey.isEmpty else {
                throw CloudSettingsError.invalidConfiguration
            }
            let configuration = CloudClimateConfiguration(
                baseURL: url,
                apiKey: trimmedKey,
                installationID: installationID,
                deviceID: gatewayID,
                transport: backend.rawValue,
                region: baconRegion.rawValue
            )
            guard let tokens = try tokenStore.loadTokens() else { throw OAuthError.notSignedIn }
            try await CloudClimateService(configuration: configuration).syncCredentials(tokens: tokens)
            try cloudSecretStore.save(trimmedKey)
        } else {
            if let cloudConfiguration {
                try await CloudClimateService(configuration: cloudConfiguration).deleteAllSchedules()
            }
            try? cloudSecretStore.delete()
        }
        self.cloudEnabled = cloudEnabled
        self.cloudURL = trimmedURL
        persistConfiguration(reloadDashboard: reloadDashboard)
    }

    func signOut(reloadDashboard: Bool = false) {
        if let cloudConfiguration {
            Task {
                let service = CloudClimateService(configuration: cloudConfiguration)
                try? await service.deleteAllSchedules()
                try? await service.removeCredentials()
            }
        }
        try? tokenStore.deleteTokens()
        try? cloudSecretStore.delete()
        isSignedIn = false
        gatewayID = ""
        backend = .pointT
        baconRegion = .europe
        cloudEnabled = false
        cloudURL = ""
        persistConfiguration(reloadDashboard: reloadDashboard)
    }

    func evaluateBodyTemperatureAutomation(_ snapshot: BodyTemperatureSnapshot) async {
        guard bodyTemperatureAutomationEnabled else {
            bodyTemperatureAutomationMessage = nil
            return
        }
        guard snapshot.shouldActivateCooling(threshold: bodyTemperatureDeltaThreshold) else {
            if !snapshot.isFresh() {
                bodyTemperatureAutomationMessage = String(localized: "Latest wrist temperature is too old for automation.")
            } else if snapshot.baselineSampleCount < 3 {
                bodyTemperatureAutomationMessage = String(localized: "At least three prior nights are needed for a personal baseline.")
            } else {
                bodyTemperatureAutomationMessage = String(localized: "Wrist temperature is below the cooling trigger.")
            }
            return
        }
        guard isSignedIn else {
            bodyTemperatureAutomationMessage = String(localized: "Live Bosch access is required for automatic cooling.")
            return
        }
        guard UserDefaults.standard.string(forKey: Key.bodyTemperatureLastSample) != snapshot.sampleID.uuidString else {
            return
        }

        do {
            let climateService = service
            guard let device = try await climateService.devices().first else {
                bodyTemperatureAutomationMessage = String(localized: "No air conditioner is available for temperature automation.")
                return
            }
            let capabilities = try await climateService.capabilities(for: device.id)
            guard capabilities.canWrite else {
                bodyTemperatureAutomationMessage = String(localized: "The air conditioner is read-only.")
                return
            }
            let state = try await climateService.state(for: device.id)
            if !state.powerEnabled {
                let patch = ClimatePatch(
                    powerEnabled: true,
                    operatingMode: capabilities.operatingModes.contains(.cool) ? .cool : nil
                )
                _ = try await climateService.apply(patch, to: device.id)
            }
            UserDefaults.standard.set(snapshot.sampleID.uuidString, forKey: Key.bodyTemperatureLastSample)
            bodyTemperatureAutomationMessage = state.powerEnabled
                ? String(localized: "Cooling was already active when the elevated temperature arrived.")
                : String(localized: "Cooling activated from elevated Apple Watch wrist temperature.")
        } catch {
            bodyTemperatureAutomationMessage = String(localized: "Automatic cooling could not reach the air conditioner.")
        }
    }

    func reloadDashboard() {
        revision = UUID()
    }

    private func persistConfiguration(reloadDashboard shouldReloadDashboard: Bool) {
        UserDefaults.standard.set(gatewayID, forKey: Key.gatewayID)
        UserDefaults.standard.set(backend.rawValue, forKey: Key.backend)
        UserDefaults.standard.set(baconRegion.rawValue, forKey: Key.baconRegion)
        UserDefaults.standard.set(cloudEnabled, forKey: Key.cloudEnabled)
        UserDefaults.standard.set(cloudURL, forKey: Key.cloudURL)
        if shouldReloadDashboard { reloadDashboard() }
    }

    func approveTVPairing(code: String, name: String) async throws {
        guard let configuration = cloudConfiguration else {
            throw CloudSettingsError.invalidConfiguration
        }
        let payload = PhoneTVPairingApproval(code: code, tvName: name)
        var request = URLRequest(url: configuration.baseURL.appending(path: "api/tv/pair/approve"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.installationID, forHTTPHeaderField: "X-Installation-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudSettingsError.invalidConfiguration }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(PhoneTVPairingErrorPayload.self, from: data)
            throw PhoneTVPairingError.server(error?.error ?? "TV pairing could not be approved")
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var configuration: AppConfiguration
    @ObservedObject var bodyTemperature: BodyTemperatureManager
    let onFinished: () -> Void
    @StateObject private var signInCoordinator = SingleKeySignInCoordinator()
    @State private var showingSignOutConfirmation = false
    @State private var cloudEnabled: Bool
    @State private var cloudURL: String
    @State private var cloudAPIKey: String
    @State private var cloudErrorMessage: String?
    @State private var isSaving = false
    @State private var tvName = "Living Room TV"
    @State private var tvPairingCode = ""
    @State private var tvPairingMessage: String?
    @State private var isPairingTV = false

    init(
        configuration: AppConfiguration,
        bodyTemperature: BodyTemperatureManager,
        onFinished: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.bodyTemperature = bodyTemperature
        self.onFinished = onFinished
        _cloudEnabled = State(initialValue: configuration.cloudEnabled)
        _cloudURL = State(initialValue: configuration.cloudURL)
        _cloudAPIKey = State(initialValue: configuration.cloudAPIKey)
    }

    var body: some View {
        Form {
                Section {
                    if configuration.isSignedIn {
                        Label("Signed in with Bosch", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("Gateway", value: configuration.gatewayID)
                            .textSelection(.enabled)
                        LabeledContent("Transport", value: configuration.backend == .bacon ? "HomeCom MQTT" : "PointT REST")
                    } else {
                        Button {
                            Task {
                                await signInCoordinator.signIn(configuration: configuration, reloadDashboard: false)
                            }
                        } label: {
                            HStack {
                                Label("Sign in with Bosch", systemImage: "person.crop.circle.badge.checkmark")
                                Spacer()
                                if signInCoordinator.isWorking { ProgressView() }
                            }
                        }
                        .disabled(signInCoordinator.isWorking)
                        .accessibilityIdentifier("settings.signInButton")
                    }
                } header: {
                    Text("Bosch account")
                } footer: {
                    if !configuration.isSignedIn {
                        Text("Sign-in opens Bosch SingleKey ID. betterBCool never sees or stores your password.")
                    }
                }

                if let message = signInCoordinator.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle(
                        "Cool based on Apple Watch",
                        isOn: bodyTemperatureAutomationBinding
                    )
                    Stepper(
                        value: $configuration.bodyTemperatureDeltaThreshold,
                        in: 0.2...2.0,
                        step: 0.1
                    ) {
                        LabeledContent(
                            "Trigger above baseline",
                            value: "+" + configuration.bodyTemperatureDeltaThreshold.formatted(
                                .number.precision(.fractionLength(1))
                            ) + " °C"
                        )
                    }
                } header: {
                    Text("Apple Watch cooling")
                }

                if configuration.isSignedIn {
                    Section {
                        Toggle("Cloud schedule", isOn: $cloudEnabled)
                        if cloudEnabled {
                            TextField("https://your-project.vercel.app", text: $cloudURL)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            SecureField("Cloud API key", text: $cloudAPIKey)
                                .textInputAutocapitalization(.never)
                        }
                        if let cloudErrorMessage {
                            Label(cloudErrorMessage, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Cloud scheduling")
                    } footer: {
                        Text("When enabled, Cloud service securely executes routines and manual commands even while this iPhone is offline.")
                    }
                }

                Section {
                    if !configuration.isSignedIn {
                        Label("Sign in with Bosch to approve a TV.", systemImage: "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(.secondary)
                    } else if configuration.cloudAPIKey.isEmpty {
                        Label("Enable Cloud scheduling above, then enter the TV code here.", systemImage: "cloud.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("TV name", text: $tvName)
                            .textInputAutocapitalization(.words)
                        TextField("6-digit code", text: $tvPairingCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button {
                            approveTV()
                        } label: {
                            HStack {
                                Label("Approve this TV", systemImage: "appletv")
                                Spacer()
                                if isPairingTV { ProgressView() }
                            }
                        }
                        .disabled(isPairingTV || tvPairingCode.filter(\.isNumber).count != 6)
                    }
                    if let tvPairingMessage {
                        Text(tvPairingMessage)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("TV devices")
                } footer: {
                    Text("Enter the code shown on your Apple TV. The TV receives a separate scoped token and Bosch credentials stay on the cloud service.")
                }

                Section {
                    NavigationLink("Understand your AC") {
                        UnderstandYourACView()
                    }
                    NavigationLink("Privacy & safety") {
                        PrivacyAndSafetyView()
                    }
                    HStack {
                        Spacer()
                        Text("Version \(appVersion) • Build \(buildNumber)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if configuration.isSignedIn {
                    Section {
                        Button("Sign out", role: .destructive) { showingSignOutConfirmation = true }
                    }
                }

            }
            .accessibilityIdentifier("settings.screen")
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndFinish()
                    }
                    .accessibilityIdentifier("settings.doneButton")
                    .disabled(isSaving)
                }
            }
            .confirmationDialog("Sign out of Bosch?", isPresented: $showingSignOutConfirmation) {
                Button("Sign out", role: .destructive) {
                    configuration.signOut(reloadDashboard: false)
                    cloudEnabled = false
                    cloudURL = ""
                    cloudAPIKey = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stored Bosch tokens and the discovered gateway will be removed from this device.")
            }
    }

    private func saveAndFinish() {
        guard !isSaving else { return }
        isSaving = true
        cloudErrorMessage = nil
        Task { @MainActor in
            do {
                try await configuration.saveAccessMode(
                    cloudEnabled: cloudEnabled,
                    cloudURL: cloudURL,
                    cloudAPIKey: cloudAPIKey,
                    reloadDashboard: false
                )
                onFinished()
            } catch is CancellationError {
                isSaving = false
            } catch {
                cloudErrorMessage = String(localized: "Cloud setup could not be verified. Check the URL and API key.")
                isSaving = false
            }
        }
    }

    private func approveTV() {
        guard !isPairingTV else { return }
        isPairingTV = true
        tvPairingMessage = nil
        let code = tvPairingCode.filter(\.isNumber)
        Task { @MainActor in
            do {
                try await configuration.approveTVPairing(code: code, name: tvName)
                tvPairingMessage = "TV approved. It will connect automatically."
                tvPairingCode = ""
            } catch let error as PhoneTVPairingError {
                tvPairingMessage = error.localizedDescription
            } catch {
                tvPairingMessage = "TV pairing could not be approved."
            }
            isPairingTV = false
        }
    }

    private var bodyTemperatureAutomationBinding: Binding<Bool> {
        Binding(
            get: { configuration.bodyTemperatureAutomationEnabled },
            set: { enabled in
                configuration.bodyTemperatureAutomationEnabled = enabled
                guard enabled, !bodyTemperature.hasRequestedAuthorization else { return }
                Task { await bodyTemperature.requestAuthorization() }
            }
        )
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

private struct UnderstandYourACView: View {
    var body: some View {
        Form {
            Section("Modes") {
                ACGuideItem(
                    title: "Auto",
                    symbol: "sparkles",
                    description: "Lets the AC choose how to reach and maintain the selected temperature."
                )
                ACGuideItem(
                    title: "Cool",
                    symbol: "snowflake",
                    description: "Lowers the room temperature toward your selected setpoint."
                )
                ACGuideItem(
                    title: "Dry",
                    symbol: "drop.fill",
                    description: "Reduces humidity with gentle, intermittent cooling. Fan speed is automatic, so Quiet, Low, Medium, High and Turbo should not work. Climate 3000i, 5000i and 6000i units normally still allow a temperature setpoint in Dry; some Climate Class models lock it. Eco, Sleep and swing availability depends on the AC model."
                )
                ACGuideItem(
                    title: "Fan",
                    symbol: "fan.fill",
                    description: "Circulates room air without actively heating or cooling it."
                )
                ACGuideItem(
                    title: "Heat",
                    symbol: "sun.max.fill",
                    description: "Warms the room toward your selected setpoint on supported AC models."
                )
            }

            Section("Fan speeds") {
                ACGuideItem(
                    title: "Auto",
                    symbol: "gauge.with.dots.needle.50percent",
                    description: "Adjusts airflow automatically according to the current mode and room conditions."
                )
                ACGuideItem(
                    title: "Quiet",
                    symbol: "speaker.slash.fill",
                    description: "Uses the gentlest airflow to reduce noise."
                )
                ACGuideItem(
                    title: "Low, medium and high",
                    symbol: "fan.fill",
                    description: "Provide progressively stronger airflow. Higher speeds change the room faster but create more noise."
                )
                ACGuideItem(
                    title: "Turbo",
                    symbol: "bolt.fill",
                    description: "Uses maximum output for a rapid temperature change, with greater noise and energy use."
                )
            }

            Section {
                ACGuideItem(
                    title: "Eco",
                    symbol: "leaf.fill",
                    description: "Reduces energy use by limiting output and, on some Bosch models, selecting at least 24 °C with Auto fan. Bosch does not publish one guaranteed saving versus Cool across all Climate models, and betterBCool does not receive power-use data from this AC, so it cannot show a trustworthy percentage."
                )
                ACGuideItem(
                    title: "Sleep",
                    symbol: "moon.stars.fill",
                    description: "Prioritizes quieter overnight operation and may adjust the temperature gradually."
                )
                ACGuideItem(
                    title: "Vertical swing",
                    symbol: "arrow.up.and.down",
                    description: "Moves the louvers up and down to distribute air through the room."
                )
                ACGuideItem(
                    title: "Horizontal swing",
                    symbol: "arrow.left.and.right",
                    description: "Moves the louvers left and right to spread airflow across the room."
                )
            } header: {
                Text("Comfort features")
            } footer: {
                Text("Available modes and features depend on your AC model. betterBCool disables options that your unit does not report as supported. Eco, Sleep and swing can be controlled from the dashboard when the unit accepts them.")
            }
        }
        .navigationTitle("Understand your AC")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ACGuideItem: View {
    let title: LocalizedStringKey
    let symbol: String
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct PrivacyAndSafetyView: View {
    var body: some View {
        Form {
            Section("Apple Watch cooling") {
                Text("Apple Watch provides one wrist-temperature aggregate after sleep—not a live body-temperature stream. Automation uses only samples under 18 hours old and requires at least three prior nights for a personal baseline. This is not a medical feature.")
            }

            Section("Privacy & safety") {
                Text("Tokens are stored in the iOS Keychain and refreshed automatically.")
                Text("This is an independent integration and is not endorsed by Bosch.")
            }
        }
        .navigationTitle("Privacy & safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private final class SingleKeySignInCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    private var session: ASWebAuthenticationSession?

    func clearError() {
        errorMessage = nil
    }

    func signIn(configuration: AppConfiguration, reloadDashboard: Bool = true) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let authorization = try await configuration.oauthClient.authorizationRequest()
            let callback = try await authenticate(at: authorization.url)
            let code = try await configuration.oauthClient.authorizationCode(
                from: callback,
                expectedState: authorization.state
            )
            let tokens = try await configuration.oauthClient.exchange(
                code: code,
                verifier: authorization.codeVerifier
            )
            try await configuration.completeSignIn(tokens: tokens, reloadDashboard: reloadDashboard)
        } catch ASWebAuthenticationSessionError.canceledLogin {
            errorMessage = nil
        } catch SignInError.noGatewayEntries {
            errorMessage = String(localized: "Bosch sign-in worked, but neither the classic nor newer HomeCom service returned an AC for this account.")
        } catch SignInError.newHomeComDevices(let count) {
            let format = count == 1
                ? String(localized: "Found %lld newer HomeCom air conditioner. MQTT device-shadow control is the next integration step.")
                : String(localized: "Found %lld newer HomeCom air conditioners. MQTT device-shadow control is the next integration step.")
            errorMessage = String(format: format, locale: .current, Int64(count))
        } catch SignInError.newHomeComShadowRead(let fieldCount) {
            errorMessage = String(
                format: String(localized: "Connected to the newer HomeCom AC and read its live state (%lld fields). Control mapping is the next step."),
                locale: .current,
                Int64(fieldCount)
            )
        } catch SignInError.unrecognizedGatewayEntries(let count) {
            let format = count == 1
                ? String(localized: "Bosch returned %lld gateway entry, but its format was not recognized.")
                : String(localized: "Bosch returned %lld gateway entries, but their format was not recognized.")
            errorMessage = String(format: format, locale: .current, Int64(count))
        } catch SignInError.noCompatibleGateway(let count) {
            let format = count == 1
                ? String(localized: "Bosch returned %lld gateway entry, but it did not expose the classic air-conditioning resource.")
                : String(localized: "Bosch returned %lld gateway entries, but none exposed the classic air-conditioning resource.")
            errorMessage = String(format: format, locale: .current, Int64(count))
        } catch {
            errorMessage = String(localized: "Bosch sign-in could not be completed. Please try again.")
        }
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: SingleKeyOAuthClient.callbackScheme
            ) { callback, error in
                if let error { continuation.resume(throwing: error) }
                else if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: OAuthError.invalidCallback) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else {
                continuation.resume(throwing: SignInError.couldNotStartBrowser)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        guard let windowScene = scenes.first else {
            preconditionFailure("Authentication requires a connected window scene")
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
}

private struct KeychainOAuthTokenStore: OAuthTokenStoring, @unchecked Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "dev.betterbcool.app",
        account: String = "bosch-singlekey-oauth-tokens"
    ) {
        self.service = service
        self.account = account
    }

    func loadTokens() throws -> OAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.status(status) }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func saveTokens(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError.status(updateStatus) }

        var insertion = identity
        insertion.merge([
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]) { _, new in new }
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func deleteTokens() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

private struct KeychainStringStore: @unchecked Sendable {
    private let service = "dev.betterbcool.app"
    let account: String

    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError.status(status) }
        return value
    }

    func save(_ value: String) throws {
        try? delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

private enum SignInError: Error {
    case couldNotStartBrowser
    case noGatewayEntries
    case newHomeComDevices(Int)
    case newHomeComShadowRead(Int)
    case unrecognizedGatewayEntries(Int)
    case noCompatibleGateway(Int)
}
private enum KeychainError: Error {
    case status(OSStatus)
    case selfTestMismatch
}
private struct PhoneTVPairingApproval: Encodable {
    let code: String
    let tvName: String
}

private struct PhoneTVPairingErrorPayload: Decodable {
    let error: String
}

private enum PhoneTVPairingError: Error, LocalizedError {
    case server(String)

    var errorDescription: String? {
        if case .server(let message) = self { return message }
        return "TV pairing could not be approved."
    }
}

private enum CloudSettingsError: Error { case invalidConfiguration }
