// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import BetterBCoolCore

final class BaconMQTTTests: XCTestCase {
    func testJWTSubjectParsing() throws {
        let payload = Data("{\"sub\":\"account-subject\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(BaconMQTTClient.jwtSubject(from: "header.\(payload).signature"), "account-subject")
    }

    func testConnectPacketUsesMQTTFiveAndCredentials() throws {
        let packet = try BaconMQTTCodec.decodePacket(
            BaconMQTTCodec.connect(clientID: String(repeating: "a", count: 64), username: "subject", password: "token")
        )
        XCTAssertEqual(packet.body[6], 5)
        XCTAssertEqual(packet.body[7], 0xC2)
    }

    func testPublishPacketRoundTrip() throws {
        let encoded = BaconMQTTCodec.publish(topic: "users/sub/devices/unit/shadows/state/get", payload: Data("{}".utf8))
        let packet = try BaconMQTTCodec.decodePacket(encoded)
        let publish = try XCTUnwrap(BaconMQTTCodec.decodePublish(packet))
        XCTAssertEqual(publish.topic, "users/sub/devices/unit/shadows/state/get")
        XCTAssertEqual(publish.payload, Data("{}".utf8))
    }
}
