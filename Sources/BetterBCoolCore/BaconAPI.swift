// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum BaconRegion: String, CaseIterable, Sendable {
    case europe = "euc1"
    case unitedStates = "use1"
}

public struct BaconDevice: Equatable, Sendable {
    public let id: String
    public let region: BaconRegion

    public init(id: String, region: BaconRegion) {
        self.id = id
        self.region = region
    }
}

public struct BaconAPI: Sendable {
    private static let userAgent = "DashApp/4.0.0 (iOS)"

    private let accessToken: String
    private let session: URLSession

    public init(accessToken: String, session: URLSession = .shared) {
        self.accessToken = accessToken
        self.session = session
    }

    public func devices(in region: BaconRegion) async throws -> [BaconDevice] {
        let host = "claiming.\(region.rawValue).bacon.bosch-tt-cw.com"
        guard let url = URL(string: "https://\(host)/v1/users/self/devices") else {
            throw BaconError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BaconError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 { throw BaconError.unauthorized }
            throw BaconError.httpStatus(http.statusCode)
        }
        guard let serials = try? JSONDecoder().decode([String].self, from: data) else {
            throw BaconError.invalidPayload
        }
        return serials.filter { !$0.isEmpty }.map { BaconDevice(id: $0, region: region) }
    }
}

public enum BaconError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case invalidPayload
    case unauthorized
    case httpStatus(Int)
}
