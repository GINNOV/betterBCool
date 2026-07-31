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
    @StateObject private var sensorTag = SensorTagManager.shared
    @StateObject private var signInCoordinator = SingleKeySignInCoordinator()
    @State private var isShowingSettings = false

    var body: some View {
        ClimateDashboard(
            service: configuration.service,
            remoteScheduler: configuration.remoteScheduler,
            sensorTag: sensorTag,
            onSettingsTapped: { isShowingSettings = true },
            onReconnectTapped: {
                Task { await signInCoordinator.signIn(configuration: configuration) }
            }
        )
            .id(configuration.revision)
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView(configuration: configuration, sensorTag: sensorTag)
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
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-sensortag-preview") {
                    sensorTag.loadPreviewReadings()
                }
            }
    }
}

@MainActor
private final class AppConfiguration: ObservableObject {
    private static let logger = Logger(subsystem: "dev.betterbcool.app", category: "BoschDiscovery")

    @Published var liveAccessEnabled: Bool
    @Published private(set) var gatewayID: String
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var revision = UUID()
    @Published private(set) var backend: Backend
    @Published private(set) var baconRegion: BaconRegion
    @Published private(set) var cloudEnabled: Bool
    @Published private(set) var cloudURL: String

    let oauthClient = SingleKeyOAuthClient()
    let tokenStore = KeychainOAuthTokenStore()
    let cloudSecretStore = KeychainStringStore(account: "vercel-cloud-api-key")
    let installationID: String

    private enum Key {
        static let liveAccess = "liveAccessEnabled"
        static let gatewayID = "gatewayID"
        static let backend = "backend"
        static let baconRegion = "baconRegion"
        static let cloudEnabled = "cloudEnabled"
        static let cloudURL = "cloudURL"
        static let installationID = "cloudInstallationID"
    }

    enum Backend: String { case pointT, bacon }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            let defaults = UserDefaults.standard
            let scheduleStorageKey = "betterBCool.climateSchedules.v1"
            defaults.removeObject(forKey: scheduleStorageKey)
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
                    defaults.set(data, forKey: scheduleStorageKey)
                }
            }
            liveAccessEnabled = false
            gatewayID = ""
            isSignedIn = false
            backend = .pointT
            baconRegion = .europe
            cloudEnabled = false
            cloudURL = ""
            installationID = "ui-testing-installation"
        } else {
            liveAccessEnabled = UserDefaults.standard.bool(forKey: Key.liveAccess)
            let startupGatewayID = UserDefaults.standard.string(forKey: Key.gatewayID) ?? ""
            gatewayID = startupGatewayID
            let storedBackend = UserDefaults.standard.string(forKey: Key.backend)
                .flatMap(Backend.init(rawValue:))
            backend = storedBackend ?? .pointT
            baconRegion = BaconRegion(rawValue: UserDefaults.standard.string(forKey: Key.baconRegion) ?? "") ?? .europe
            cloudEnabled = UserDefaults.standard.bool(forKey: Key.cloudEnabled)
            cloudURL = UserDefaults.standard.string(forKey: Key.cloudURL)
                ?? "https://betterbcool-cloud.vercel.app"
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
                UserDefaults.standard.set(false, forKey: Key.liveAccess)
            }
        }
        if !isSignedIn { liveAccessEnabled = false }
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
        guard liveAccessEnabled, isSignedIn, !gatewayID.isEmpty else {
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

    func completeSignIn(tokens: OAuthTokens) async throws {
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
                liveAccessEnabled = true
                await restoreCloudCredentialsIfNeeded(tokens: tokens)
                persistAndReload()
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
        liveAccessEnabled = true
        await restoreCloudCredentialsIfNeeded(tokens: tokens)
        persistAndReload()
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

    func saveAccessMode(cloudEnabled: Bool, cloudURL: String, cloudAPIKey: String) async throws {
        if !isSignedIn { liveAccessEnabled = false }
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
            try? cloudSecretStore.delete()
        }
        self.cloudEnabled = cloudEnabled
        self.cloudURL = trimmedURL
        persistAndReload()
    }

    func signOut() {
        if let cloudConfiguration {
            Task { try? await CloudClimateService(configuration: cloudConfiguration).removeCredentials() }
        }
        try? tokenStore.deleteTokens()
        try? cloudSecretStore.delete()
        isSignedIn = false
        liveAccessEnabled = false
        gatewayID = ""
        backend = .pointT
        baconRegion = .europe
        cloudEnabled = false
        cloudURL = ""
        persistAndReload()
    }

    private func persistAndReload() {
        UserDefaults.standard.set(liveAccessEnabled, forKey: Key.liveAccess)
        UserDefaults.standard.set(gatewayID, forKey: Key.gatewayID)
        UserDefaults.standard.set(backend.rawValue, forKey: Key.backend)
        UserDefaults.standard.set(baconRegion.rawValue, forKey: Key.baconRegion)
        UserDefaults.standard.set(cloudEnabled, forKey: Key.cloudEnabled)
        UserDefaults.standard.set(cloudURL, forKey: Key.cloudURL)
        revision = UUID()
    }
}

private struct SettingsView: View {
    @ObservedObject var configuration: AppConfiguration
    @ObservedObject var sensorTag: SensorTagManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var signInCoordinator = SingleKeySignInCoordinator()
    @State private var showingSignOutConfirmation = false
    @State private var cloudEnabled: Bool
    @State private var cloudURL: String
    @State private var cloudAPIKey: String
    @State private var cloudErrorMessage: String?
    @State private var isSaving = false

    init(configuration: AppConfiguration, sensorTag: SensorTagManager) {
        self.configuration = configuration
        self.sensorTag = sensorTag
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
                        Toggle("Live read/write access", isOn: $configuration.liveAccessEnabled)
                    } else {
                        Button {
                            Task { await signInCoordinator.signIn(configuration: configuration) }
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
                    Text("Sign-in opens Bosch SingleKey ID. betterBCool never sees or stores your password.")
                }

                if let message = signInCoordinator.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Access") {
                    LabeledContent(
                        "Dashboard data",
                        value: configuration.liveAccessEnabled
                            ? String(localized: "Live")
                            : String(localized: "Demo")
                    )
                    LabeledContent(
                        "Controls",
                        value: configuration.liveAccessEnabled
                            ? String(localized: "Read & write")
                            : String(localized: "Disabled")
                    )
                }

                Section {
                    switch sensorTag.connectionState {
                    case .connected:
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let device = sensorTag.connectedDevice {
                            LabeledContent("Device", value: device.name)
                        }
                        if let temperature = sensorTag.readings.ambientTemperature {
                            LabeledContent(
                                "Temperature",
                                value: temperature.formatted(
                                    .number.precision(.fractionLength(1))
                                ) + " °C"
                            )
                            .accessibilityIdentifier("settings.sensorTagTemperature")
                        } else {
                            HStack {
                                Text("Waiting for temperature…")
                                Spacer()
                                ProgressView()
                            }
                        }
                        Button("Disconnect", role: .destructive) { sensorTag.disconnect() }
                            .accessibilityIdentifier("settings.sensorTagDisconnectButton")
                    case .scanning:
                        HStack {
                            Label("Looking for SensorTag…", systemImage: "sensor.tag.radiowaves.forward.fill")
                            Spacer()
                            ProgressView()
                        }
                        Button("Stop scanning") { sensorTag.stopScanning() }
                    case .connecting:
                        HStack {
                            Text("Connecting…")
                            Spacer()
                            ProgressView()
                        }
                        Button("Cancel") { sensorTag.cancelConnectionAttempt() }
                    case .unavailable:
                        Label(bluetoothUnavailableMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
#if targetEnvironment(simulator)
                        Button("Find SensorTag", systemImage: "dot.radiowaves.left.and.right") {}
                            .disabled(true)
                            .accessibilityIdentifier("settings.sensorTagScanButton")
                        Button("Preview SensorTag readings", systemImage: "play.circle") {
                            sensorTag.loadPreviewReadings()
                        }
                        .accessibilityIdentifier("settings.sensorTagPreviewButton")
#endif
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Button("Scan again") { sensorTag.scan() }
                    case .idle:
                        Button("Find SensorTag", systemImage: "dot.radiowaves.left.and.right") {
                            sensorTag.scan()
                        }
                        .accessibilityIdentifier("settings.sensorTagScanButton")
                    }

                    ForEach(sensorTag.discoveredDevices) { device in
                        Button {
                            sensorTag.connect(to: device)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.id.uuidString)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("\(device.signalStrength) dBm")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(sensorTag.connectionState == .connecting)
                    }
                } header: {
                    Text("TI CC2541 SensorTag")
                } footer: {
                    Text(sensorTagFooter)
                }

                if configuration.isSignedIn {
                    Section {
                        Toggle("Reliable cloud schedules", isOn: $cloudEnabled)
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

                Section("Privacy & safety") {
                    Text("Tokens are stored in the iOS Keychain and refreshed automatically.")
                    Text("This is an independent integration and is not endorsed by Bosch.")
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
                        isSaving = true
                        cloudErrorMessage = nil
                        Task {
                            do {
                                try await configuration.saveAccessMode(
                                    cloudEnabled: cloudEnabled,
                                    cloudURL: cloudURL,
                                    cloudAPIKey: cloudAPIKey
                                )
                                dismiss()
                            } catch {
                                cloudErrorMessage = String(localized: "Cloud setup could not be verified. Check the URL and API key.")
                                isSaving = false
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .confirmationDialog("Sign out of Bosch?", isPresented: $showingSignOutConfirmation) {
                Button("Sign out", role: .destructive) { configuration.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stored Bosch tokens and the discovered gateway will be removed from this device.")
            }
            .onDisappear { sensorTag.stopScanning() }
    }

    private var sensorTagFooter: String {
#if targetEnvironment(simulator)
        String(localized: "The iOS Simulator cannot access physical Bluetooth devices. Preview sample readings here, or run the app on an iPhone to find your SensorTag.")
#else
        String(localized: "Press the SensorTag side button before scanning. Live temperature, humidity, pressure and motion readings appear on the dashboard.")
#endif
    }

    private var bluetoothUnavailableMessage: String {
#if targetEnvironment(simulator)
        String(localized: "Bluetooth devices are unavailable in Simulator")
#else
        String(localized: "Bluetooth is unavailable")
#endif
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

    func signIn(configuration: AppConfiguration) async {
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
            try await configuration.completeSignIn(tokens: tokens)
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
private enum CloudSettingsError: Error { case invalidConfiguration }
