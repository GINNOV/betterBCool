// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum AppLanguage {
    public static func identifier(for preferredLanguages: [String]) -> String {
        guard let first = preferredLanguages.first else { return "en" }
        return Locale(identifier: first).language.languageCode?.identifier == "it" ? "it" : "en"
    }

    private static var preferredLanguages: [String] {
        // Locale.preferredLanguages may already be filtered to the app's supported languages.
        UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? Locale.preferredLanguages
    }

    public static var locale: Locale {
        Locale(identifier: identifier(for: preferredLanguages))
    }

    public static var bundle: Bundle {
#if os(iOS)
        let language = identifier(for: preferredLanguages)
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
#endif
        return .main
    }
}
