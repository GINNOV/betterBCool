// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TelemetryImportError: Error, Equatable {
    case empty
    case invalidHeader
    case invalidRow(Int)
}

public enum BaseTelemetryCSV {
    private static let expectedHeader = [
        "timestamp", "breezeAwayEnabled", "ecoEnabled", "fanSpeed",
        "fullPowerEnabled", "hSwingEnabled", "ionizerEnabled",
        "offTimestamp [sec]", "onTimestamp [sec]", "opMode", "powerEnabled",
        "roomTemperature [degC]", "setbackEnabled", "sleepEnabled",
        "tempSetpoint [degC]", "vSwingEnabled"
    ]

    public static func decode(_ text: String) throws -> [ClimateState] {
        let lines = text.split(whereSeparator: \Character.isNewline).map(String.init)
        guard let header = lines.first else { throw TelemetryImportError.empty }
        guard fields(in: header) == expectedHeader else { throw TelemetryImportError.invalidHeader }

        return try lines.dropFirst().enumerated().map { offset, line in
            let columns = fields(in: line)
            let lineNumber = offset + 2
            guard columns.count == expectedHeader.count,
                  let timestamp = ISO8601DateFormatter.telemetry.date(from: columns[0]),
                  let breezeAway = Bool(columns[1]),
                  let eco = Bool(columns[2]),
                  let fullPower = Bool(columns[4]),
                  let horizontalSwing = Bool(columns[5]),
                  let ionizer = Bool(columns[6]),
                  let mode = OperatingMode(rawValue: columns[9]),
                  let power = Bool(columns[10]),
                  let roomTemperature = Double(columns[11]),
                  let setback = Bool(columns[12]),
                  let sleep = Bool(columns[13]),
                  let verticalSwing = Bool(columns[15]) else {
                throw TelemetryImportError.invalidRow(lineNumber)
            }
            let fanSpeed = columns[3].isEmpty ? nil : FanSpeed(rawValue: columns[3])
            guard columns[3].isEmpty || fanSpeed != nil else {
                throw TelemetryImportError.invalidRow(lineNumber)
            }

            return ClimateState(
                timestamp: timestamp,
                powerEnabled: power,
                operatingMode: mode,
                fanSpeed: fanSpeed,
                roomTemperature: roomTemperature,
                temperatureSetpoint: Double(columns[14]),
                breezeAwayEnabled: breezeAway,
                ecoEnabled: eco,
                fullPowerEnabled: fullPower,
                horizontalSwingEnabled: horizontalSwing,
                ionizerEnabled: ionizer,
                setbackEnabled: setback,
                sleepEnabled: sleep,
                verticalSwingEnabled: verticalSwing
            )
        }
    }

    private static func fields(in line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
}

private extension ISO8601DateFormatter {
    static let telemetry: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
