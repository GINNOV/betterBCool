// SPDX-License-Identifier: Apache-2.0

import Foundation
import OSLog
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

public struct PointTGatewayDiscovery: Equatable, Sendable {
    public let returnedEntryCount: Int
    public let gateways: [PointTGateway]

    public init(returnedEntryCount: Int, gateways: [PointTGateway]) {
        self.returnedEntryCount = returnedEntryCount
        self.gateways = gateways
    }
}

public extension JSONValue {
    var pointTGatewayDiscovery: PointTGatewayDiscovery {
        let entries: [JSONValue]
        switch self {
        case .array(let values):
            entries = values
        case .object(let object):
            let wrapped = object["gateways"] ?? object["items"] ?? object["data"]
            guard case .array(let values) = wrapped else {
                return .init(returnedEntryCount: 0, gateways: [])
            }
            entries = values
        default:
            return .init(returnedEntryCount: 0, gateways: [])
        }

        let gateways: [PointTGateway] = entries.compactMap { entry in
            guard case .object(let object) = entry else { return nil }
            let rawID = object["deviceId"] ?? object["gatewayId"] ?? object["id"]
            guard case .string(let id) = rawID, !id.isEmpty else { return nil }
            let rawType = object["deviceType"] ?? object["type"]
            let type: String
            if case .string(let value) = rawType { type = value }
            else { type = "unknown" }
            return PointTGateway(id: id, type: type)
        }
        return .init(returnedEntryCount: entries.count, gateways: gateways)
    }

    var pointTGateways: [PointTGateway] { pointTGatewayDiscovery.gateways }
}

public protocol AccessTokenProviding: Sendable {
    func accessToken() async throws -> String
}

public struct StaticAccessToken: AccessTokenProviding {
    private let value: String

    public init(_ value: String) { self.value = value }
    public func accessToken() async throws -> String { value }
}

public struct PointTAPI: Sendable {
    public static let productionBaseURL = URL(string: "https://pointt-api.bosch-thermotechnology.com")!
    private static let logger = Logger(subsystem: "dev.betterbcool.app", category: "BoschDiscovery")

    private let baseURL: URL
    private let tokenProvider: (any AccessTokenProviding)?
    private let directAccessToken: String?
    private let session: URLSession

    public init(
        baseURL: URL = PointTAPI.productionBaseURL,
        tokenProvider: any AccessTokenProviding,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.directAccessToken = nil
        self.session = session
    }

    public init(
        baseURL: URL = PointTAPI.productionBaseURL,
        accessToken: String,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = nil
        self.directAccessToken = accessToken
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

    /// Selects a gateway by verifying that it exposes the read-only RAC resource tree.
    /// Reported types are only a preference because Bosch has used multiple type labels.
    public func airConditioningGateway(from gateways: [PointTGateway]) async throws -> PointTGateway? {
        let candidates = gateways.sorted { left, right in
            let leftIsRAC = left.type.caseInsensitiveCompare("rac") == .orderedSame
            let rightIsRAC = right.type.caseInsensitiveCompare("rac") == .orderedSame
            return leftIsRAC && !rightIsRAC
        }

        for gateway in candidates {
            do {
                _ = try await resource(
                    deviceID: gateway.id,
                    path: ["airConditioning", "standardFunctions"]
                )
                return gateway
            } catch PointTError.httpStatus(404) {
                continue
            }
        }
        return nil
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
        let accessToken: String
        if let directAccessToken {
            accessToken = directAccessToken
        } else if let tokenProvider {
            accessToken = try await tokenProvider.accessToken()
        } else {
            throw PointTError.unauthorized
        }
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        Self.logger.info("PointT HTTP request started: \(method, privacy: .public) \(url.path, privacy: .public)")
        let (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { try await self.session.data(for: request) }
            group.addTask {
                try await Task.sleep(nanoseconds: 25_000_000_000)
                throw PointTError.timedOut
            }
            guard let first = try await group.next() else { throw PointTError.invalidResponse }
            group.cancelAll()
            return first
        }
        guard let http = response as? HTTPURLResponse else { throw PointTError.invalidResponse }
        Self.logger.info(
            "PointT HTTP response: \(http.statusCode, privacy: .public), \(data.count, privacy: .public) bytes"
        )
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
    case timedOut
    case httpStatus(Int)
}
