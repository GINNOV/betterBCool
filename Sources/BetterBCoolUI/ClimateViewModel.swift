// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import Foundation

public struct ClimateActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let title: String
    public let detail: String
    public let symbol: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        detail: String,
        symbol: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }
}

@MainActor
public final class ClimateViewModel: ObservableObject {
    @Published public private(set) var devices: [ClimateDevice] = []
    @Published public private(set) var selectedDevice: ClimateDevice?
    @Published public private(set) var state: ClimateState?
    @Published public private(set) var capabilities: ClimateCapabilities?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isApplying = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var requiresReauthentication = false
    @Published public private(set) var activities: [ClimateActivity] = []

    private let service: any ClimateService
    private var applyGeneration = 0
    private var pendingApplyCount = 0

    public init(service: any ClimateService) {
        self.service = service
    }

    public var controlsEnabled: Bool { capabilities?.canWrite == true && state != nil }

    public func clearActivities() {
        activities.removeAll()
    }

    public func togglePower() async {
        guard let powerEnabled = state?.powerEnabled else { return }
        await apply(.init(powerEnabled: !powerEnabled))
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        requiresReauthentication = false
        defer { isLoading = false }

        do {
            devices = try await service.devices()
            guard let device = devices.first else {
                selectedDevice = nil
                state = nil
                return
            }
            selectedDevice = device
            async let fetchedCapabilities = service.capabilities(for: device.id)
            async let fetchedState = service.state(for: device.id)
            capabilities = try await fetchedCapabilities
            state = try await fetchedState
        } catch let error as CloudClimateError where error.requiresBoschReauthentication {
            requiresReauthentication = true
            errorMessage = String(
                localized: "Your Bosch session has expired. Reconnect to continue."
            )
        } catch OAuthError.tokenHTTPStatus(_) {
            requiresReauthentication = true
            errorMessage = String(
                localized: "Your Bosch session has expired. Reconnect to continue."
            )
        } catch {
            errorMessage = String(localized: "Unable to load climate data.")
        }
    }

    public func apply(_ patch: ClimatePatch) async {
        guard let device = selectedDevice, let capabilities, let previousState = state else { return }
        do {
            try capabilities.validate(patch)
        } catch ClimateServiceError.readOnly {
            errorMessage = String(localized: "Controls are read-only until the Bosch API is verified.")
            return
        } catch {
            errorMessage = String(localized: "The requested setting is not supported.")
            return
        }

        applyGeneration += 1
        let generation = applyGeneration
        pendingApplyCount += 1
        isApplying = true
        errorMessage = nil

        // Reflect the tap immediately. The service response reconciles the remaining fields.
        state = previousState.applying(patch)
        defer {
            pendingApplyCount -= 1
            isApplying = pendingApplyCount > 0
        }

        do {
            let confirmedState = try await service.apply(patch, to: device.id)
            recordActivities(for: patch)
            guard generation == applyGeneration else { return }
            // Some device shadows acknowledge a desired value before reporting it back.
            // Keep the acknowledged patch visible instead of flashing back to stale state.
            state = confirmedState.applying(patch)
        } catch ClimateServiceError.readOnly {
            guard generation == applyGeneration else { return }
            state = previousState
            errorMessage = String(localized: "Controls are read-only until the Bosch API is verified.")
        } catch {
            guard generation == applyGeneration else { return }
            state = previousState
            errorMessage = String(localized: "The device did not accept that setting.")
        }
    }

    private func recordActivities(for patch: ClimatePatch) {
        let timestamp = Date()
        var newActivities: [ClimateActivity] = []

        if let enabled = patch.powerEnabled {
            newActivities.append(.init(
                timestamp: timestamp,
                title: String(localized: "Power"),
                detail: enabled ? String(localized: "Unit turned on") : String(localized: "Unit turned off"),
                symbol: "power"
            ))
        }
        if let mode = patch.operatingMode {
            newActivities.append(.init(
                timestamp: timestamp,
                title: String(localized: "Mode"),
                detail: String(
                    format: String(localized: "Set to %@"),
                    locale: .current,
                    mode.activityTitle
                ),
                symbol: mode.activitySymbol
            ))
        }
        if let speed = patch.fanSpeed {
            newActivities.append(.init(
                timestamp: timestamp,
                title: String(localized: "Fan speed"),
                detail: String(
                    format: String(localized: "Set to %@"),
                    locale: .current,
                    speed.activityTitle
                ),
                symbol: "fan.fill"
            ))
        }
        if let temperature = patch.temperatureSetpoint {
            newActivities.append(.init(
                timestamp: timestamp,
                title: String(localized: "Temperature"),
                detail: String(
                    format: String(localized: "Set to %@"),
                    locale: .current,
                    "\(temperature.formatted(.number.precision(.fractionLength(1))))°"
                ),
                symbol: "thermometer.medium"
            ))
        }
        if let enabled = patch.horizontalSwingEnabled {
            newActivities.append(.init(
                timestamp: timestamp,
                title: String(localized: "Horizontal swing"),
                detail: enabled ? String(localized: "Enabled") : String(localized: "Disabled"),
                symbol: "arrow.left.and.right"
            ))
        }
        if let enabled = patch.verticalSwingEnabled {
            newActivities.append(.init(
                timestamp: timestamp,
                title: String(localized: "Vertical swing"),
                detail: enabled ? String(localized: "Enabled") : String(localized: "Disabled"),
                symbol: "arrow.up.and.down"
            ))
        }

        activities.insert(contentsOf: newActivities, at: 0)
        if activities.count > 50 {
            activities.removeLast(activities.count - 50)
        }
    }
}

private extension OperatingMode {
    var activityTitle: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .cool: String(localized: "Cool")
        case .dry: String(localized: "Dry")
        case .fan: String(localized: "Fan")
        case .heat: String(localized: "Heat")
        }
    }

    var activitySymbol: String {
        switch self {
        case .auto: "sparkles"
        case .cool: "snowflake"
        case .dry: "drop.fill"
        case .fan: "fan.fill"
        case .heat: "sun.max.fill"
        }
    }
}

private extension FanSpeed {
    var activityTitle: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .quiet: String(localized: "Quiet")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .turbo: String(localized: "Turbo")
        }
    }
}

private extension ClimateState {
    func applying(_ patch: ClimatePatch) -> ClimateState {
        var updated = self
        if let value = patch.powerEnabled { updated.powerEnabled = value }
        if let value = patch.operatingMode { updated.operatingMode = value }
        if let value = patch.fanSpeed { updated.fanSpeed = value }
        if let value = patch.temperatureSetpoint { updated.temperatureSetpoint = value }
        if let value = patch.horizontalSwingEnabled { updated.horizontalSwingEnabled = value }
        if let value = patch.verticalSwingEnabled { updated.verticalSwingEnabled = value }
        return updated
    }
}
