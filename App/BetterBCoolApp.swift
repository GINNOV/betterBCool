import BetterBCoolCore
import BetterBCoolUI
import Security
import SwiftUI

@main
struct BetterBCoolApp: App {
    @StateObject private var configuration = AppConfiguration()

    var body: some Scene {
        WindowGroup {
            AppRootView(configuration: configuration)
        }
    }
}

private struct AppRootView: View {
    @ObservedObject var configuration: AppConfiguration
    @State private var showingSettings = false

    var body: some View {
        ClimateDashboard(service: configuration.service) {
            showingSettings = true
        }
        .id(configuration.revision)
        .sheet(isPresented: $showingSettings) {
            SettingsView(configuration: configuration)
        }
    }
}

@MainActor
private final class AppConfiguration: ObservableObject {
    @Published var liveAccessEnabled: Bool
    @Published var gatewayID: String
    @Published var accessToken: String
    @Published private(set) var revision = UUID()

    private enum Key {
        static let liveAccess = "liveAccessEnabled"
        static let gatewayID = "gatewayID"
        static let tokenAccount = "bosch-pointt-access-token"
    }

    init() {
        liveAccessEnabled = UserDefaults.standard.bool(forKey: Key.liveAccess)
        gatewayID = UserDefaults.standard.string(forKey: Key.gatewayID) ?? ""
        accessToken = Keychain.read(account: Key.tokenAccount) ?? ""
    }

    var service: any ClimateService {
        guard liveAccessEnabled,
              !gatewayID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !accessToken.isEmpty else {
            return DemoClimateService()
        }
        let api = PointTAPI(tokenProvider: StaticAccessToken(accessToken))
        return PointTClimateService(
            api: api,
            deviceID: gatewayID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var isLiveConfigurationValid: Bool {
        !gatewayID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !accessToken.isEmpty
    }

    func save() throws {
        if !accessToken.isEmpty {
            try Keychain.write(accessToken, account: Key.tokenAccount)
        } else {
            Keychain.delete(account: Key.tokenAccount)
        }
        UserDefaults.standard.set(gatewayID, forKey: Key.gatewayID)
        UserDefaults.standard.set(liveAccessEnabled, forKey: Key.liveAccess)
        revision = UUID()
    }
}

private struct SettingsView: View {
    @ObservedObject var configuration: AppConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Live read/write access", isOn: $configuration.liveAccessEnabled)
                    TextField("Gateway ID", text: $configuration.gatewayID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("SingleKey access token", text: $configuration.accessToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Connection")
                } footer: {
                    Text("The access token is stored in the iOS Keychain. The gateway ID is stored in app preferences.")
                }

                Section("Access mode") {
                    LabeledContent("Current selection") {
                        Text(configuration.liveAccessEnabled ? "Live" : "Demo")
                            .foregroundStyle(configuration.liveAccessEnabled ? .green : .secondary)
                    }
                    if configuration.liveAccessEnabled && !configuration.isLiveConfigurationValid {
                        Label("Gateway ID and access token are required.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Safety") {
                    Text("Live mode reads the AC state when the dashboard opens. Power, mode, fan, temperature, and swing changes are sent immediately and followed by a fresh state read.")
                    Text("Use only with an account and device you own. Disable live access here to return to the offline demo.")
                }

                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try configuration.save()
                            dismiss()
                        } catch {
                            saveError = "The access token could not be stored securely."
                        }
                    }
                    .disabled(configuration.liveAccessEnabled && !configuration.isLiveConfigurationValid)
                }
            }
        }
    }
}

private enum Keychain {
    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.betterbcool.app",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) throws {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.betterbcool.app",
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.betterbcool.app",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum KeychainError: Error { case status(OSStatus) }
