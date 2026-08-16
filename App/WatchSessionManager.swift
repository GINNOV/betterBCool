// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import Foundation
import WatchConnectivity

@MainActor
final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    private let configuration: AppConfiguration
    private var scheduleChangeObserver: NSObjectProtocol?
    private var climateStateObserver: NSObjectProtocol?

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
        climateStateObserver = NotificationCenter.default.addObserver(
            forName: .betterBCoolClimateStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let state = notification.object as? ClimateState else { return }
            Task { @MainActor [weak self] in
                self?.pushSnapshot(overriding: state)
            }
        }
        activate()
    }

    deinit {
        if let scheduleChangeObserver {
            NotificationCenter.default.removeObserver(scheduleChangeObserver)
        }
        if let climateStateObserver {
            NotificationCenter.default.removeObserver(climateStateObserver)
        }
    }

    private func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushSnapshot(overriding state: ClimateState? = nil) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if let state,
           let data = WCSession.default.applicationContext[Self.payloadKey] as? Data,
           let existing = try? JSONDecoder().decode(WatchSnapshot.self, from: data),
           let updated = try? JSONEncoder().encode(existing.replacingState(state)) {
            try? WCSession.default.updateApplicationContext([Self.payloadKey: updated])
            return
        }
        Task {
            let snapshot = await configuration.watchSnapshot(overriding: state)
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
            if snapshot.errorMessage == nil {
                configuration.reloadDashboard()
            }
            guard let response = try? JSONEncoder().encode(snapshot) else {
                replyHandler([Self.payloadKey: Self.errorData("The iPhone could not prepare a response.")])
                return
            }
            replyHandler([Self.payloadKey: response])
        }
    }

    nonisolated private static let payloadKey = "betterBCool.watchPayload"

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
            let snapshot = await self.configuration.handleWatchRequest(request)
            if snapshot.errorMessage == nil {
                self.configuration.reloadDashboard()
            }
            self.pushSnapshot()
        }
    }
}

private extension WatchSnapshot {
    func replacingState(_ state: ClimateState) -> WatchSnapshot {
        WatchSnapshot(
            deviceName: deviceName,
            state: state,
            canWrite: canWrite,
            minimumSetpoint: minimumSetpoint,
            maximumSetpoint: maximumSetpoint,
            setpointStep: setpointStep,
            schedules: schedules,
            nextScheduleDate: nextScheduleDate,
            errorMessage: errorMessage
        )
    }
}
