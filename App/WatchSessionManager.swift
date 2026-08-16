// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    private let configuration: AppConfiguration
    private var scheduleChangeObserver: NSObjectProtocol?

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init()

        scheduleChangeObserver = NotificationCenter.default.addObserver(
            forName: .betterBCoolSchedulesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pushSnapshot()
            }
        }
        activate()
    }

    deinit {
        if let scheduleChangeObserver {
            NotificationCenter.default.removeObserver(scheduleChangeObserver)
        }
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushSnapshot() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        Task {
            let snapshot = await configuration.watchSnapshot()
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? WCSession.default.updateApplicationContext([Self.payloadKey: data])
        }
    }

    private func handleMessage(
        _ message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let data = message[Self.payloadKey] as? Data,
              let request = try? JSONDecoder().decode(WatchRequest.self, from: data) else {
            replyHandler([Self.payloadKey: Self.errorData("The watch sent an invalid request.")])
            return
        }

        Task {
            let snapshot = await configuration.handleWatchRequest(request)
            guard let response = try? JSONEncoder().encode(snapshot) else {
                replyHandler([Self.payloadKey: Self.errorData("The iPhone could not prepare a response.")])
                return
            }
            replyHandler([Self.payloadKey: response])
        }
    }

    private static let payloadKey = "betterBCool.watchPayload"

    private static func errorData(_ message: String) -> Data {
        let snapshot = WatchSnapshot(errorMessage: message)
        return (try? JSONEncoder().encode(snapshot)) ?? Data()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self, error == nil, activationState == .activated else { return }
            self.pushSnapshot()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                replyHandler([Self.payloadKey: Self.errorData("betterBCool is unavailable on the iPhone.")])
                return
            }
            self.handleMessage(message, replyHandler: replyHandler)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[Self.payloadKey] as? Data,
              let request = try? JSONDecoder().decode(WatchRequest.self, from: data) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.configuration.handleWatchRequest(request)
            self.pushSnapshot()
        }
    }
}
