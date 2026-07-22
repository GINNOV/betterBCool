// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import BetterBCoolCore

final class SingleKeyOAuthTests: XCTestCase {
    func testAuthorizationRequestUsesPKCEAndExpectedCallback() async throws {
        let request = try await SingleKeyOAuthClient().authorizationRequest()
        let components = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: try XCTUnwrap(components.queryItems).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "singlekey-id.com")
        XCTAssertEqual(query["redirect_uri"], SingleKeyOAuthClient.redirectURI)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertNotNil(query["code_challenge"])
        XCTAssertEqual(query["state"], request.state)
        XCTAssertGreaterThanOrEqual(request.codeVerifier.count, 43)
    }

    func testCallbackValidatesStateAndReturnsCode() async throws {
        let client = SingleKeyOAuthClient()
        let callback = URL(string: "com.bosch.tt.dashtt.pointt://app/login?code=temporary-code&state=expected")!

        let code = try await client.authorizationCode(from: callback, expectedState: "expected")

        XCTAssertEqual(code, "temporary-code")
    }

    func testCallbackRejectsWrongState() async throws {
        let client = SingleKeyOAuthClient()
        let callback = URL(string: "com.bosch.tt.dashtt.pointt://app/login?code=temporary-code&state=wrong")!

        do {
            _ = try await client.authorizationCode(from: callback, expectedState: "expected")
            XCTFail("Expected state validation to fail")
        } catch {
            XCTAssertEqual(error as? OAuthError, .stateMismatch)
        }
    }

    func testGatewayDiscoveryParsing() {
        let payload: JSONValue = .array([
            .object(["deviceId": .string("gateway-1"), "deviceType": .string("rac")])
        ])

        XCTAssertEqual(payload.pointTGateways, [.init(id: "gateway-1", type: "rac")])
    }
}
