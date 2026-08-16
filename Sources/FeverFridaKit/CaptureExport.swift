// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum FeverFridaCaptureExport {
    public static func jsonLines<T: Encodable>(_ values: [T]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var output = Data()
        for value in values {
            output.append(try encoder.encode(value))
            output.append(0x0A)
        }
        return output
    }

    public static func prettyJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
