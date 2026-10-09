// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import BetterBCoolCore

final class AppLanguageTests: XCTestCase {
    func testItalianRegionalVariantsUseItalian() {
        for language in ["it", "it-IT", "it-CH"] {
            XCTAssertEqual(AppLanguage.identifier(for: [language]), "it")
        }
    }

    func testUnsupportedPrimaryLanguageUsesEnglishEvenWithItalianSecondary() {
        for language in ["en-GB", "fr-FR", "de-DE", "es-ES", "ja-JP", "en-IT"] {
            XCTAssertEqual(AppLanguage.identifier(for: [language, "it"]), "en")
        }
        XCTAssertEqual(AppLanguage.identifier(for: []), "en")
    }
}
