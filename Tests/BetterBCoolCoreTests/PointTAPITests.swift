import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BetterBCoolCore

final class PointTAPITests: XCTestCase {
    override func setUp() {
        URLProtocolStub.handler = nil
    }

    func testGatewayDiscoveryUsesBearerTokenAndExpectedPath() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/pointt-api/api/v1/gateways")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[{\"deviceId\":\"redacted\"}]".utf8))
        }
        let api = PointTAPI(
            baseURL: URL(string: "https://example.invalid")!,
            tokenProvider: StaticAccessToken("test-token"),
            session: stubbedSession()
        )

        let result = try await api.gateways()
        XCTAssertEqual(result, .array([.object(["deviceId": .string("redacted")])]))
    }

    func testSetpointWriteUsesIsolatedResourceAndJSONValueEnvelope() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/pointt-api/api/v1/gateways/device/resource/airConditioning/temperatureSetpoint")
            let body = try request.bodyData()
            XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: body), .object(["value": .number(24.5)]))
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let api = PointTAPI(
            baseURL: URL(string: "https://example.invalid")!,
            tokenProvider: StaticAccessToken("test-token"),
            session: stubbedSession()
        )

        try await api.setResource(
            deviceID: "device",
            path: ["airConditioning", "temperatureSetpoint"],
            value: .number(24.5)
        )
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }
}

private extension URLRequest {
    func bodyData() throws -> Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { throw PointTError.invalidPayload }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? PointTError.invalidPayload }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class URLProtocolStub: URLProtocol {
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
