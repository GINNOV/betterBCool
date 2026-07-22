// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var needsRefresh: Bool { expiresAt <= Date().addingTimeInterval(60) }
}

public struct OAuthAuthorizationRequest: Equatable, Sendable {
    public let url: URL
    public let codeVerifier: String
    public let state: String
}

public protocol OAuthTokenStoring: Sendable {
    func loadTokens() throws -> OAuthTokens?
    func saveTokens(_ tokens: OAuthTokens) throws
    func deleteTokens() throws
}

public actor SingleKeyOAuthClient {
    public static let callbackScheme = "com.bosch.tt.dashtt.pointt"
    public static let redirectURI = "com.bosch.tt.dashtt.pointt://app/login"

    private let clientID = "762162C0-FA2D-4540-AE66-6489F189FADC"
    private let authorizationEndpoint = URL(string: "https://singlekey-id.com/auth/connect/authorize")!
    private let tokenEndpoint = URL(string: "https://singlekey-id.com/auth/connect/token")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func authorizationRequest() throws -> OAuthAuthorizationRequest {
        let verifier = Self.randomURLSafeValue()
        let state = Self.randomURLSafeValue()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "prompt", value: "login"),
            .init(name: "scope", value: "openid email profile offline_access pointt.gateway.claiming pointt.gateway.removal pointt.gateway.list pointt.gateway.users pointt.gateway.resource.dashapp pointt.castt.flow.token-exchange bacon hcc.tariff.read"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "style_id", value: "tt_bsch")
        ]
        guard let url = components.url else { throw OAuthError.invalidAuthorizationURL }
        return OAuthAuthorizationRequest(url: url, codeVerifier: verifier, state: state)
    }

    public func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard callbackURL.scheme == Self.callbackScheme,
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallback
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else { continue }
            guard values[item.name] == nil else { throw OAuthError.invalidCallback }
            values[item.name] = value
        }
        guard values["state"] == expectedState else { throw OAuthError.stateMismatch }
        if let error = values["error"] { throw OAuthError.provider(error) }
        guard let code = values["code"], !code.isEmpty else { throw OAuthError.missingCode }
        return code
    }

    public func exchange(code: String, verifier: String) async throws -> OAuthTokens {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier
        ], previousRefreshToken: nil)
    }

    public func refresh(_ refreshToken: String) async throws -> OAuthTokens {
        try await tokenRequest([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken
        ], previousRefreshToken: refreshToken)
    }

    private func tokenRequest(_ fields: [String: String], previousRefreshToken: String?) async throws -> OAuthTokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = fields.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthError.invalidTokenResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenHTTPStatus(http.statusCode)
        }
        let payload: TokenPayload
        do { payload = try JSONDecoder().decode(TokenPayload.self, from: data) }
        catch { throw OAuthError.invalidTokenResponse }
        let refreshToken = payload.refreshToken ?? previousRefreshToken
        guard let refreshToken, !refreshToken.isEmpty else { throw OAuthError.missingRefreshToken }
        return OAuthTokens(
            accessToken: payload.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
    }

    private static func randomURLSafeValue() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public actor RefreshingAccessTokenProvider: AccessTokenProviding {
    private let client: SingleKeyOAuthClient
    private let store: any OAuthTokenStoring

    public init(client: SingleKeyOAuthClient, store: any OAuthTokenStoring) {
        self.client = client
        self.store = store
    }

    public func accessToken() async throws -> String {
        guard var tokens = try store.loadTokens() else { throw OAuthError.notSignedIn }
        if tokens.needsRefresh {
            tokens = try await client.refresh(tokens.refreshToken)
            try store.saveTokens(tokens)
        }
        return tokens.accessToken
    }
}

private struct TokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

public enum OAuthError: Error, Equatable {
    case invalidAuthorizationURL
    case invalidCallback
    case stateMismatch
    case missingCode
    case provider(String)
    case tokenHTTPStatus(Int)
    case invalidTokenResponse
    case missingRefreshToken
    case notSignedIn
}
