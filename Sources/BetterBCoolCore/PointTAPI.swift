// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public struct PointTGateway: Equatable, Sendable {
    public let id: String
    public let type: String

    public init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}

public extension JSONValue {
    var pointTGateways: [PointTGateway] {
        guard case .array(let entries) = self else { return [] }
        return entries.compactMap { entry in
            guard case .object(let object) = entry,
                  case .string(let id) = object["deviceId"],
                  case .string(let type) = object["deviceType"] else { return nil }
            return PointTGateway(id: id, type: type)
        }
    }
}

public protocol AccessTokenProviding: Sendable {
    func accessToken() async throws -> String
}

public struct StaticAccessToken: AccessTokenProviding {
    private let value: String

    public init(_ value: String) { self.value = value }
    public func accessToken() async throws -> String { value }
}

public actor PointTAPI {
    public static let productionBaseURL = URL(string: "https://pointt-api.bosch-thermotechnology.com")!

    private let baseURL: URL
    private let tokenProvider: any AccessTokenProviding
    private let session: URLSession

    public init(
        baseURL: URL = PointTAPI.productionBaseURL,
        tokenProvider: any AccessTokenProviding,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Returns the untouched discovery representation while its schema is being verified.
    public func gateways() async throws -> JSONValue {
        try await request(path: ["pointt-api", "api", "v1", "gateways"])
    }

    public func resource(deviceID: String, path: [String]) async throws -> JSONValue {
        try await request(path: ["pointt-api", "api", "v1", "gateways", deviceID, "resource"] + path)
    }

    public func setResource(deviceID: String, path: [String], value: JSONValue) async throws {
        _ = try await request(
            path: ["pointt-api", "api", "v1", "gateways", deviceID, "resource"] + path,
            method: "PUT",
            body: .object(["value": value]),
            allowsEmptyResponse: true
        )
    }

    private func request(
        path: [String],
        method: String = "GET",
        body: JSONValue? = nil,
        allowsEmptyResponse: Bool = false
    ) async throws -> JSONValue {
        guard baseURL.scheme == "https", baseURL.host != nil else {
            throw PointTError.invalidBaseURL
        }
        var url = baseURL
        for component in path { url.appendPathComponent(component) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(try await tokenProvider.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PointTError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw PointTError.unauthorized
            case 429: throw PointTError.rateLimited
            default: throw PointTError.httpStatus(http.statusCode)
            }
        }
        if data.isEmpty && allowsEmptyResponse { return .null }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw PointTError.invalidPayload }
    }
}

public enum PointTError: Error, Equatable {
    case invalidBaseURL
    case invalidResponse
    case invalidPayload
    case unauthorized
    case rateLimited
    case httpStatus(Int)
}
