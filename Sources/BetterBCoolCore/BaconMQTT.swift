// SPDX-License-Identifier: Apache-2.0

import CryptoKit
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct BaconShadow: Equatable, Sendable {
    public let reported: JSONValue
    public let desired: JSONValue

    public init(reported: JSONValue, desired: JSONValue) {
        self.reported = reported
        self.desired = desired
    }
}

public actor BaconMQTTClient {
    private let accessToken: String
    private let subject: String
    private let region: BaconRegion
    private let clientID: String
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var packetIdentifier: UInt16 = 1

    public init(
        accessToken: String,
        region: BaconRegion,
        clientID: String? = nil,
        session: URLSession = .shared
    ) throws {
        guard let subject = Self.jwtSubject(from: accessToken) else {
            throw BaconMQTTError.invalidAccessToken
        }
        self.accessToken = accessToken
        self.subject = subject
        self.region = region
        self.clientID = clientID ?? Self.makeClientID()
        self.session = session
    }

    public func readShadow(deviceID: String) async throws -> BaconShadow {
        try await connect()
        defer { socket?.cancel(with: .normalClosure, reason: nil); socket = nil }

        try await subscribe(to: "users/\(subject)/#")
        let getTopic = "users/\(subject)/devices/\(deviceID)/shadows/state/get"
        try await send(BaconMQTTCodec.publish(topic: getTopic, payload: Data()))

        let accepted = "\(getTopic)/accepted"
        let rejected = "\(getTopic)/rejected"
        return try await withThrowingTaskGroup(of: BaconShadow.self) { group in
            group.addTask { try await self.receiveShadow(accepted: accepted, rejected: rejected) }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw BaconMQTTError.timedOut
            }
            guard let shadow = try await group.next() else { throw BaconMQTTError.timedOut }
            group.cancelAll()
            return shadow
        }
    }

    public func updateDesired(deviceID: String, desired: [String: JSONValue]) async throws -> BaconShadow {
        try await connect()
        try await subscribe(to: "users/\(subject)/#")
        let updateTopic = "users/\(subject)/devices/\(deviceID)/shadows/state/update"
        let payload = try JSONEncoder().encode(
            JSONValue.object(["state": .object(["desired": .object(desired)])])
        )
        try await send(BaconMQTTCodec.publish(topic: updateTopic, payload: payload))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.waitForAcknowledgement(
                    accepted: "\(updateTopic)/accepted",
                    rejected: "\(updateTopic)/rejected"
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000)
                throw BaconMQTTError.timedOut
            }
            _ = try await group.next()
            group.cancelAll()
        }
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        return try await readShadow(deviceID: deviceID)
    }

    private func connect() async throws {
        let host = "broker.\(region.rawValue).bacon.bosch-tt-cw.com"
        guard let url = URL(string: "wss://\(host):443/mqtt") else {
            throw BaconMQTTError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("DashApp/4.0.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("mqtt", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        let socket = session.webSocketTask(with: request)
        self.socket = socket
        socket.resume()
        try await send(BaconMQTTCodec.connect(clientID: clientID, username: subject, password: accessToken))

        let packet = try await receivePacket()
        guard packet.type == .connack else { throw BaconMQTTError.unexpectedPacket }
        guard packet.body.count >= 2 else { throw BaconMQTTError.malformedPacket }
        guard packet.body[1] == 0 else { throw BaconMQTTError.connectionRefused(packet.body[1]) }
    }

    private func subscribe(to topic: String) async throws {
        let identifier = nextPacketIdentifier()
        try await send(BaconMQTTCodec.subscribe(topic: topic, packetIdentifier: identifier))
        while true {
            let packet = try await receivePacket()
            if packet.type == .suback { return }
        }
    }

    private func receiveShadow(accepted: String, rejected: String) async throws -> BaconShadow {
        while !Task.isCancelled {
            let packet = try await receivePacket()
            guard packet.type == .publish,
                  let publish = try BaconMQTTCodec.decodePublish(packet) else { continue }
            if publish.topic == rejected { throw BaconMQTTError.shadowRejected }
            guard publish.topic == accepted else { continue }
            let payload = try JSONDecoder().decode(JSONValue.self, from: publish.payload)
            guard case .object(let root) = payload,
                  case .object(let state)? = root["state"] else {
                throw BaconMQTTError.invalidShadow
            }
            return BaconShadow(
                reported: state["reported"] ?? .object([:]),
                desired: state["desired"] ?? .object([:])
            )
        }
        throw CancellationError()
    }

    private func waitForAcknowledgement(accepted: String, rejected: String) async throws {
        while !Task.isCancelled {
            let packet = try await receivePacket()
            guard packet.type == .publish,
                  let publish = try BaconMQTTCodec.decodePublish(packet) else { continue }
            if publish.topic == rejected { throw BaconMQTTError.shadowRejected }
            if publish.topic == accepted { return }
        }
        throw CancellationError()
    }

    private func send(_ data: Data) async throws {
        guard let socket else { throw BaconMQTTError.notConnected }
        try await socket.send(.data(data))
    }

    private func receivePacket() async throws -> BaconMQTTCodec.Packet {
        guard let socket else { throw BaconMQTTError.notConnected }
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw BaconMQTTError.unexpectedPacket
        }
        return try BaconMQTTCodec.decodePacket(data)
    }

    private func nextPacketIdentifier() -> UInt16 {
        let current = packetIdentifier
        packetIdentifier = packetIdentifier == .max ? 1 : packetIdentifier + 1
        return current
    }

    private static func makeClientID() -> String {
        SHA256.hash(data: Data(UUID().uuidString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func jwtSubject(from token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }
        var value = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        guard let data = Data(base64Encoded: value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String,
              !subject.isEmpty else { return nil }
        return subject
    }
}

enum BaconMQTTCodec {
    enum PacketType: UInt8 {
        case connack = 2
        case publish = 3
        case suback = 9
        case other = 0
    }

    struct Packet {
        let type: PacketType
        let flags: UInt8
        let body: Data
    }

    struct Publish {
        let topic: String
        let payload: Data
    }

    static func connect(clientID: String, username: String, password: String) -> Data {
        var body = Data()
        body.appendUTF8("MQTT")
        body.append(5)
        body.append(0xC2) // username, password, clean start
        body.append(contentsOf: [0x00, 0x3C])
        body.append(0) // CONNECT properties length
        body.appendUTF8(clientID)
        body.appendUTF8(username)
        body.appendUTF8(password)
        return packet(header: 0x10, body: body)
    }

    static func subscribe(topic: String, packetIdentifier: UInt16) -> Data {
        var body = Data([UInt8(packetIdentifier >> 8), UInt8(packetIdentifier & 0xff), 0])
        body.appendUTF8(topic)
        body.append(0) // QoS 0 subscription
        return packet(header: 0x82, body: body)
    }

    static func publish(topic: String, payload: Data) -> Data {
        var body = Data()
        body.appendUTF8(topic)
        body.append(0) // PUBLISH properties length
        body.append(payload)
        return packet(header: 0x30, body: body)
    }

    static func decodePacket(_ data: Data) throws -> Packet {
        guard let header = data.first else { throw BaconMQTTError.malformedPacket }
        let (remaining, bodyIndex) = try decodeVariableInteger(data, startingAt: 1)
        guard remaining >= 0, bodyIndex + remaining <= data.count else {
            throw BaconMQTTError.malformedPacket
        }
        let rawType = header >> 4
        let type = PacketType(rawValue: rawType) ?? .other
        return Packet(type: type, flags: header & 0x0f, body: data.subdata(in: bodyIndex..<(bodyIndex + remaining)))
    }

    static func decodePublish(_ packet: Packet) throws -> Publish? {
        guard packet.type == .publish else { return nil }
        let body = packet.body
        guard body.count >= 2 else { throw BaconMQTTError.malformedPacket }
        let topicLength = Int(body[0]) << 8 | Int(body[1])
        guard body.count >= 2 + topicLength else { throw BaconMQTTError.malformedPacket }
        let topicData = body.subdata(in: 2..<(2 + topicLength))
        guard let topic = String(data: topicData, encoding: .utf8) else {
            throw BaconMQTTError.malformedPacket
        }
        var index = 2 + topicLength
        let qos = (packet.flags >> 1) & 0x03
        if qos > 0 { index += 2 }
        let (propertiesLength, propertiesIndex) = try decodeVariableInteger(body, startingAt: index)
        index = propertiesIndex + propertiesLength
        guard index <= body.count else { throw BaconMQTTError.malformedPacket }
        return Publish(topic: topic, payload: body.subdata(in: index..<body.count))
    }

    private static func packet(header: UInt8, body: Data) -> Data {
        var result = Data([header])
        result.append(contentsOf: encodeVariableInteger(body.count))
        result.append(body)
        return result
    }

    private static func encodeVariableInteger(_ value: Int) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(value % 128)
            value /= 128
            if value > 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value > 0
        return bytes
    }

    private static func decodeVariableInteger(_ data: Data, startingAt start: Int) throws -> (Int, Int) {
        var multiplier = 1
        var value = 0
        var index = start
        repeat {
            guard index < data.count, multiplier <= 128 * 128 * 128 else {
                throw BaconMQTTError.malformedPacket
            }
            let byte = data[index]
            index += 1
            value += Int(byte & 0x7f) * multiplier
            if byte & 0x80 == 0 { return (value, index) }
            multiplier *= 128
        } while true
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        let encoded = Data(value.utf8)
        append(UInt8((encoded.count >> 8) & 0xff))
        append(UInt8(encoded.count & 0xff))
        append(encoded)
    }
}

public enum BaconMQTTError: Error, Equatable {
    case invalidAccessToken
    case invalidURL
    case notConnected
    case malformedPacket
    case unexpectedPacket
    case connectionRefused(UInt8)
    case shadowRejected
    case invalidShadow
    case timedOut
}
