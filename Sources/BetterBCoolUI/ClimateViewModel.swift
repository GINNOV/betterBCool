// SPDX-License-Identifier: Apache-2.0

import BetterBCoolCore
import Foundation

@MainActor
public final class ClimateViewModel: ObservableObject {
    @Published public private(set) var devices: [ClimateDevice] = []
    @Published public private(set) var selectedDevice: ClimateDevice?
    @Published public private(set) var state: ClimateState?
    @Published public private(set) var capabilities: ClimateCapabilities?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isApplying = false
    @Published public private(set) var errorMessage: String?

    private let service: any ClimateService
    private var applyGeneration = 0
    private var pendingApplyCount = 0

    public init(service: any ClimateService) {
        self.service = service
    }

    public var controlsEnabled: Bool { capabilities?.canWrite == true && state != nil }

    public func load() async {
        isLoading = true
        errorMessage = nil
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
        } catch {
            errorMessage = "Unable to load climate data."
        }
    }

    public func apply(_ patch: ClimatePatch) async {
        guard let device = selectedDevice, let capabilities, let previousState = state else { return }
        do {
            try capabilities.validate(patch)
        } catch ClimateServiceError.readOnly {
            errorMessage = "Controls are read-only until the Bosch API is verified."
            return
        } catch {
            errorMessage = "The requested setting is not supported."
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
            guard generation == applyGeneration else { return }
            // Some device shadows acknowledge a desired value before reporting it back.
            // Keep the acknowledged patch visible instead of flashing back to stale state.
            state = confirmedState.applying(patch)
        } catch ClimateServiceError.readOnly {
            guard generation == applyGeneration else { return }
            state = previousState
            errorMessage = "Controls are read-only until the Bosch API is verified."
        } catch {
            guard generation == applyGeneration else { return }
            state = previousState
            errorMessage = "The device did not accept that setting."
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
