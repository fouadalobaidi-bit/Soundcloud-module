import UIKit

/// Settings live in the keyboard's own storage on the phone.
@MainActor
final class KeyboardSettings {
    static let shared = KeyboardSettings()
    private let defaults = UserDefaults.standard

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    var haptics: Bool {
        get { bool("haptics", true) }
        set { defaults.set(newValue, forKey: "haptics") }
    }

    var sound: Bool {
        get { bool("sound", true) }
        set { defaults.set(newValue, forKey: "sound") }
    }

    var autocorrectEnglish: Bool {
        get { bool("autocorrectEnglish", true) }
        set { defaults.set(newValue, forKey: "autocorrectEnglish") }
    }

    var autocorrectArabic: Bool {
        get { bool("autocorrectArabic", false) }
        set { defaults.set(newValue, forKey: "autocorrectArabic") }
    }

    var arabicDigits: Bool {
        get { bool("arabicDigits", false) }
        set { defaults.set(newValue, forKey: "arabicDigits") }
    }

    var language: KeyboardLanguage {
        get { KeyboardLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .arabic }
        set { defaults.set(newValue.rawValue, forKey: "language") }
    }
}
