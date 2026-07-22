import Foundation

public struct ClimateDevice: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Transport-neutral boundary. Implement only from an authorized, observed contract.
public protocol ClimateService: Sendable {
    func devices() async throws -> [ClimateDevice]
    func capabilities(for deviceID: String) async throws -> ClimateCapabilities
    func state(for deviceID: String) async throws -> ClimateState
    func apply(_ patch: ClimatePatch, to deviceID: String) async throws -> ClimateState
}

public struct ClimateCapabilities: Codable, Equatable, Sendable {
    public let canWrite: Bool
    public let operatingModes: Set<OperatingMode>
    public let fanSpeeds: Set<FanSpeed>
    public let minimumSetpoint: Double
    public let maximumSetpoint: Double
    public let setpointStep: Double

    public init(
        canWrite: Bool,
        operatingModes: Set<OperatingMode>,
        fanSpeeds: Set<FanSpeed>,
        minimumSetpoint: Double,
        maximumSetpoint: Double,
        setpointStep: Double
    ) {
        self.canWrite = canWrite
        self.operatingModes = operatingModes
        self.fanSpeeds = fanSpeeds
        self.minimumSetpoint = minimumSetpoint
        self.maximumSetpoint = maximumSetpoint
        self.setpointStep = setpointStep
    }

    public func validate(_ patch: ClimatePatch) throws {
        guard canWrite else { throw ClimateServiceError.readOnly }
        if let mode = patch.operatingMode, !operatingModes.contains(mode) {
            throw ClimateServiceError.unsupportedValue
        }
        if let fan = patch.fanSpeed, !fanSpeeds.contains(fan) {
            throw ClimateServiceError.unsupportedValue
        }
        if let value = patch.temperatureSetpoint {
            guard value.isFinite,
                  value >= minimumSetpoint,
                  value <= maximumSetpoint,
                  setpointStep > 0 else {
                throw ClimateServiceError.unsupportedValue
            }
            let steps = (value - minimumSetpoint) / setpointStep
            guard abs(steps.rounded() - steps) < 0.000_001 else {
                throw ClimateServiceError.unsupportedValue
            }
        }
    }
}

public actor ReadOnlyHistoricalService: ClimateService {
    private let device: ClimateDevice
    private let states: [ClimateState]

    public init(device: ClimateDevice, states: [ClimateState]) {
        self.device = device
        self.states = states.sorted { $0.timestamp > $1.timestamp }
    }

    public func devices() async throws -> [ClimateDevice] { [device] }

    public func capabilities(for deviceID: String) async throws -> ClimateCapabilities {
        guard deviceID == device.id else { throw ClimateServiceError.deviceNotFound }
        return ClimateCapabilities(
            canWrite: false,
            operatingModes: Set(OperatingMode.allCases),
            fanSpeeds: Set(FanSpeed.allCases),
            minimumSetpoint: 15,
            maximumSetpoint: 32.5,
            setpointStep: 0.5
        )
    }

    public func state(for deviceID: String) async throws -> ClimateState {
        guard deviceID == device.id, let latest = states.first else {
            throw ClimateServiceError.deviceNotFound
        }
        return latest
    }

    public func apply(_ patch: ClimatePatch, to deviceID: String) async throws -> ClimateState {
        throw ClimateServiceError.readOnly
    }
}

public enum ClimateServiceError: Error, Equatable {
    case deviceNotFound
    case readOnly
    case unsupportedValue
}
