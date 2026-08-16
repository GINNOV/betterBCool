// SPDX-License-Identifier: Apache-2.0

import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionClient: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var errorMessage: String?

    private let session = WCSession.default
    private var didStart = false
    private static let payloadKey = "betterBCool.watchPayload"

    override init() {
        if let data = WCSession.default.applicationContext[Self.payloadKey] as? Data {
            snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data)
        }
        super.init()
    }

    func start() {
        guard !didStart, WCSession.isSupported() else { return }
        didStart = true
        session.delegate = self
        session.activate()
    }

    func refresh() {
        send(.refresh)
    }

    func togglePower() {
        send(.togglePower)
    }

    func setTemperature(_ temperature: Double) {
        send(.setTemperature(temperature))
    }

    func setSchedulesEnabled(_ enabled: Bool) {
        send(.setSchedulesEnabled(enabled))
    }

    private func send(_ request: WatchRequest) {
        start()
        guard WCSession.isSupported() else {
            errorMessage = "Watch connectivity is unavailable."
            return
        }

        guard session.isReachable else {
            if let data = try? JSONEncoder().encode(request) {
                session.transferUserInfo([Self.payloadKey: data])
            }
            errorMessage = "Open betterBCool on your iPhone to apply this change."
            return
        }

        guard let data = try? JSONEncoder().encode(request) else {
            errorMessage = "The request could not be prepared."
            return
        }

        errorMessage = nil
        session.sendMessage(
            [Self.payloadKey: data],
            replyHandler: { [weak self] response in
                guard let data = response[Self.payloadKey] as? Data else { return }
                Task { @MainActor [weak self] in
                    self?.receive(data)
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.errorMessage = error.localizedDescription
                }
            }
        )
    }

    private func receive(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else {
            errorMessage = "The iPhone sent an invalid climate response."
            return
        }
        self.snapshot = snapshot
        errorMessage = snapshot.errorMessage
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                errorMessage = error.localizedDescription
            } else if activationState == .activated, snapshot == nil {
                refresh()
            }
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[Self.payloadKey] as? Data else { return }
        Task { @MainActor [weak self] in
            self?.receive(data)
        }
    }
}
