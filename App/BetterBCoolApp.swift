// SPDX-License-Identifier: Apache-2.0

import AuthenticationServices
import BetterBCoolCore
import BetterBCoolUI
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
    @State private var showingSettings = false

    var body: some View {
        ClimateDashboard(service: configuration.service) { showingSettings = true }
            .id(configuration.revision)
            .sheet(isPresented: $showingSettings) {
                SettingsView(configuration: configuration)
            }
    }
}

@MainActor
private final class AppConfiguration: ObservableObject {
    @Published var liveAccessEnabled: Bool
    @Published private(set) var gatewayID: String
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var revision = UUID()

    let oauthClient = SingleKeyOAuthClient()
    let tokenStore = KeychainOAuthTokenStore()

    private enum Key {
        static let liveAccess = "liveAccessEnabled"
        static let gatewayID = "gatewayID"
    }

    init() {
        liveAccessEnabled = UserDefaults.standard.bool(forKey: Key.liveAccess)
        gatewayID = UserDefaults.standard.string(forKey: Key.gatewayID) ?? ""
        isSignedIn = (try? tokenStore.loadTokens()) != nil
        if !isSignedIn { liveAccessEnabled = false }
    }

    var service: any ClimateService {
        guard liveAccessEnabled, isSignedIn, !gatewayID.isEmpty else {
            return DemoClimateService()
        }
        let provider = RefreshingAccessTokenProvider(client: oauthClient, store: tokenStore)
        return PointTClimateService(api: PointTAPI(tokenProvider: provider), deviceID: gatewayID)
    }

    func completeSignIn(tokens: OAuthTokens) async throws {
        try tokenStore.saveTokens(tokens)
        let provider = RefreshingAccessTokenProvider(client: oauthClient, store: tokenStore)
        let gateways = try await PointTAPI(tokenProvider: provider).gateways().pointTGateways
        guard let gateway = gateways.first(where: { $0.type.lowercased() == "rac" }) else {
            try? tokenStore.deleteTokens()
            throw SignInError.noCompatibleGateway
        }
        gatewayID = gateway.id
        isSignedIn = true
        liveAccessEnabled = true
        persistAndReload()
    }

    func saveAccessMode() {
        if !isSignedIn { liveAccessEnabled = false }
        persistAndReload()
    }

    func signOut() {
        try? tokenStore.deleteTokens()
        isSignedIn = false
        liveAccessEnabled = false
        gatewayID = ""
        persistAndReload()
    }

    private func persistAndReload() {
        UserDefaults.standard.set(liveAccessEnabled, forKey: Key.liveAccess)
        UserDefaults.standard.set(gatewayID, forKey: Key.gatewayID)
        revision = UUID()
    }
}

private struct SettingsView: View {
    @ObservedObject var configuration: AppConfiguration
    @Environment(\.dismiss) private var dismiss
    @StateObject private var signInCoordinator = SingleKeySignInCoordinator()
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if configuration.isSignedIn {
                        Label("Signed in with Bosch", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        LabeledContent("Gateway", value: configuration.gatewayID)
                            .textSelection(.enabled)
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
                    LabeledContent("Dashboard data", value: configuration.liveAccessEnabled ? "Live" : "Demo")
                    LabeledContent("Controls", value: configuration.liveAccessEnabled ? "Read & write" : "Disabled")
                }

                Section("Privacy & safety") {
                    Text("Tokens are stored in the iOS Keychain and refreshed automatically. Commands are limited to power, mode, fan, temperature, and swing, then verified with a fresh state read.")
                    Text("This is an independent integration and is not endorsed by Bosch.")
                }

                if configuration.isSignedIn {
                    Section {
                        Button("Sign out", role: .destructive) { showingSignOutConfirmation = true }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        configuration.saveAccessMode()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Sign out of Bosch?", isPresented: $showingSignOutConfirmation) {
                Button("Sign out", role: .destructive) { configuration.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stored Bosch tokens and the discovered gateway will be removed from this device.")
            }
        }
    }
}

@MainActor
private final class SingleKeySignInCoordinator: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    private var session: ASWebAuthenticationSession?

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
        } catch SignInError.noCompatibleGateway {
            errorMessage = "No compatible PointT air conditioner was found on this Bosch account."
        } catch {
            errorMessage = "Bosch sign-in could not be completed. Please try again."
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
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}

private struct KeychainOAuthTokenStore: OAuthTokenStoring, @unchecked Sendable {
    private let service = "dev.betterbcool.app"
    private let account = "bosch-singlekey-oauth-tokens"

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
        try? deleteTokens()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
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

private enum SignInError: Error { case couldNotStartBrowser, noCompatibleGateway }
private enum KeychainError: Error { case status(OSStatus) }
