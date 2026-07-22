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
    @Published public private(set) var errorMessage: String?

    private let service: any ClimateService

    public init(service: any ClimateService) {
        self.service = service
    }

    public var controlsEnabled: Bool { capabilities?.canWrite == true && !isLoading }

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
        guard let device = selectedDevice, let capabilities else { return }
        do {
            try capabilities.validate(patch)
            isLoading = true
            defer { isLoading = false }
            state = try await service.apply(patch, to: device.id)
        } catch ClimateServiceError.readOnly {
            errorMessage = "Controls are read-only until the Bosch API is verified."
        } catch {
            errorMessage = "The requested setting is not supported."
        }
    }
}
