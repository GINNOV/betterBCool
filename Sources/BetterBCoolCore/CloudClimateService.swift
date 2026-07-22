// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CloudClimateConfiguration: Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let installationID: String
    public let deviceID: String
    public let transport: String
    public let region: String

    public init(
        baseURL: URL,
        apiKey: String,
        installationID: String,
        deviceID: String,
        transport: String,
        region: String
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.installationID = installationID
        self.deviceID = deviceID
        self.transport = transport
        self.region = region
    }
}

public protocol ClimateScheduleRemoteService: Sendable {
    func sync(schedule: ClimateSchedule, timezone: String) async throws
    func delete(scheduleID: UUID) async throws
}

public actor CloudClimateService: ClimateService, ClimateScheduleRemoteService {
    private let configuration: CloudClimateConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(configuration: CloudClimateConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func devices() async throws -> [ClimateDevice] {
        [ClimateDevice(id: configuration.deviceID, name: "Bosch Climate")]
    }

    public func capabilities(for deviceID: String) async throws -> ClimateCapabilities {
        try verify(deviceID)
        if configuration.transport == "bacon" {
            return .init(
                canWrite: true,
                operatingModes: Set(OperatingMode.allCases),
                fanSpeeds: Set(FanSpeed.allCases),
                minimumSetpoint: 16,
                maximumSetpoint: 30,
                setpointStep: 1
            )
        }
        return .init(
            canWrite: true,
            operatingModes: Set(OperatingMode.allCases),
            fanSpeeds: [.auto, .quiet, .low, .medium],
            minimumSetpoint: 15,
            maximumSetpoint: 32.5,
            setpointStep: 0.5
        )
    }

    public func state(for deviceID: String) async throws -> ClimateState {
        try verify(deviceID)
        return try await request(path: "api/climate/state", method: "GET", response: ClimateState.self)
    }

    public func apply(_ patch: ClimatePatch, to deviceID: String) async throws -> ClimateState {
        try verify(deviceID)
        try await capabilities(for: deviceID).validate(patch)
        return try await request(path: "api/climate/apply", method: "PUT", body: patch, response: ClimateState.self)
    }

    public func syncCredentials(tokens: OAuthTokens) async throws {
        let payload = CredentialPayload(
            gatewayID: configuration.deviceID,
            transport: configuration.transport,
            region: configuration.region,
            tokens: tokens
        )
        _ = try await request(path: "api/credentials", method: "PUT", body: payload, response: OKResponse.self)
    }

    public func removeCredentials() async throws {
        _ = try await request(path: "api/credentials", method: "DELETE", response: OKResponse.self)
    }

    public func sync(schedule: ClimateSchedule, timezone: String) async throws {
        let payload = SchedulePayload(schedule: schedule, timezone: timezone)
        _ = try await request(
            path: "api/schedules/\(schedule.id.uuidString)",
            method: "PUT",
            body: payload,
            response: ScheduleResponse.self
        )
    }

    public func delete(scheduleID: UUID) async throws {
        _ = try await request(
            path: "api/schedules/\(scheduleID.uuidString)",
            method: "DELETE",
            response: OKResponse.self
        )
    }

    private func verify(_ deviceID: String) throws {
        guard deviceID == configuration.deviceID else { throw ClimateServiceError.deviceNotFound }
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        response: Response.Type
    ) async throws -> Response {
        try await request(path: path, method: method, encodedBody: nil, response: response)
    }

    private func request<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        response: Response.Type
    ) async throws -> Response {
        try await request(path: path, method: method, encodedBody: encoder.encode(body), response: response)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        encodedBody: Data?,
        response: Response.Type
    ) async throws -> Response {
        guard configuration.baseURL.scheme == "https" || configuration.baseURL.host == "localhost" else {
            throw CloudClimateError.insecureURL
        }
        let url = configuration.baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.installationID, forHTTPHeaderField: "X-Installation-ID")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let encodedBody {
            request.httpBody = encodedBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse else { throw CloudClimateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(ErrorResponse.self, from: data)
            throw CloudClimateError.httpStatus(http.statusCode, payload?.error)
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw CloudClimateError.invalidResponse }
    }
}

private struct CredentialPayload: Encodable {
    let gatewayID: String
    let transport: String
    let region: String
    let tokens: OAuthTokens
}

private struct SchedulePayload: Encodable {
    let schedule: ClimateSchedule
    let timezone: String
}

private struct OKResponse: Decodable { let ok: Bool }
private struct ScheduleResponse: Decodable { let ok: Bool }
private struct ErrorResponse: Decodable { let error: String }

public enum CloudClimateError: Error, Equatable {
    case insecureURL
    case invalidResponse
    case httpStatus(Int, String?)
}
