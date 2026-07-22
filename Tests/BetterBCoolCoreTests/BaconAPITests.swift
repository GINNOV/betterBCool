// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import BetterBCoolCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BaconAPITests: XCTestCase {
    override func tearDown() {
        BaconURLProtocol.handler = nil
        super.tearDown()
    }

    func testEuropeanDeviceDiscovery() async throws {
        BaconURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "claiming.euc1.bacon.bosch-tt-cw.com")
            XCTAssertEqual(request.url?.path, "/v1/users/self/devices")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[\"serial-redacted\"]".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BaconURLProtocol.self]
        let api = BaconAPI(accessToken: "token", session: URLSession(configuration: configuration))

        let devices = try await api.devices(in: .europe)

        XCTAssertEqual(devices, [.init(id: "serial-redacted", region: .europe)])
    }
}

private final class BaconURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw BaconError.invalidResponse }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
