// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import FeverFridaKit

final class AdvertisementFilterTests: XCTestCase {
    func testRecognizesAppleCompanyIdentifier() {
        XCTAssertTrue(advertisement(manufacturerDataHex: "4C 00 10 05 01").isAppleDevice)
        XCTAssertTrue(advertisement(manufacturerDataHex: "4c 00").isAppleDevice)
    }

    func testRecognizesAppleProductNameWithoutManufacturerData() {
        XCTAssertTrue(advertisement(localName: "Mario’s AirPods Pro").isAppleDevice)
        XCTAssertTrue(advertisement(localName: "Apple Watch").isAppleDevice)
    }

    func testDoesNotHideFeverFridaOrUnknownPeripheral() {
        XCTAssertFalse(advertisement(localName: "FeverFrida", manufacturerDataHex: "34 12 4C 00").isAppleDevice)
        XCTAssertFalse(advertisement(localName: nil, manufacturerDataHex: nil).isAppleDevice)
    }

    private func advertisement(
        localName: String? = nil,
        manufacturerDataHex: String? = nil
    ) -> BLEAdvertisement {
        BLEAdvertisement(
            id: UUID(),
            capturedAt: Date(),
            localName: localName,
            rssi: -50,
            isConnectable: true,
            serviceUUIDs: [],
            overflowServiceUUIDs: [],
            solicitedServiceUUIDs: [],
            manufacturerDataHex: manufacturerDataHex,
            serviceDataHex: [:],
            transmitPower: nil
        )
    }
}
