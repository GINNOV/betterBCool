// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BetterBCoolCore

final class CloudClimateServiceTests: XCTestCase {
    override func tearDown() {
        CloudURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testMissingInstallationCredentialsAreRestoredAndRequestIsRetried() async throws {
        let lock = NSLock()
        var pathsAndMethods: [String] = []
        let expectedState = ClimateState(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            powerEnabled: true,
            operatingMode: .cool,
            fanSpeed: .auto,
            roomTemperature: 24,
            temperatureSetpoint: 22,
            breezeAwayEnabled: false,
            ecoEnabled: false,
            fullPowerEnabled: false,
            horizontalSwingEnabled: false,
            ionizerEnabled: false,
            setbackEnabled: false,
            sleepEnabled: false,
            verticalSwingEnabled: false
        )
        let stateEncoder = JSONEncoder()
        stateEncoder.dateEncodingStrategy = .iso8601

        CloudURLProtocolStub.handler = { request in
            lock.lock()
            pathsAndMethods.append("\(request.httpMethod ?? "GET") \(request.url!.path)")
            let requestNumber = pathsAndMethods.count
            lock.unlock()

            if requestNumber == 1 {
                return Self.response(
                    for: request,
                    status: 502,
                    body: #"{"error":"Installation credentials are missing"}"#
                )
            }
            if request.url?.path == "/api/credentials" {
                XCTAssertEqual(request.httpMethod, "PUT")
                return Self.response(for: request, status: 200, body: #"{"ok":true}"#)
            }
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                try stateEncoder.encode(expectedState)
            )
        }

        let tokens = OAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let service = CloudClimateService(
            configuration: configuration,
            session: stubbedSession(),
            credentialRecovery: { tokens }
        )

        let state = try await service.state(for: "device")

        XCTAssertEqual(state, expectedState)
        XCTAssertEqual(pathsAndMethods, [
            "GET /api/climate/state",
            "PUT /api/credentials",
            "GET /api/climate/state"
        ])
    }

    func testRejectedBoschRefreshRequiresReauthentication() {
        XCTAssertTrue(
            CloudClimateError
                .httpStatus(502, "Bosch token refresh failed (400)")
                .requiresBoschReauthentication
        )
        XCTAssertFalse(
            CloudClimateError
                .httpStatus(502, "Installation credentials are missing")
                .requiresBoschReauthentication
        )
    }

    private var configuration: CloudClimateConfiguration {
        CloudClimateConfiguration(
            baseURL: URL(string: "https://example.invalid")!,
            apiKey: "api-key",
            installationID: "installation-1234",
            deviceID: "device",
            transport: "bacon",
            region: "euc1"
        )
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }
}

private final class CloudURLProtocolStub: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
