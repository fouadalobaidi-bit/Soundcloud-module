import UIKit

/// Settings live in the keyboard's own storage on the phone.
@MainActor
final class KeyboardSettings {
    static let shared = KeyboardSettings()
    static let claudeDailyLimit = 1000
    private let defaults = UserDefaults.standard

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func float(_ key: String, _ fallback: Float) -> Float {
        (defaults.object(forKey: key) as? NSNumber)?.floatValue ?? fallback
    }

    // MARK: Look

    var numberRow: Bool {
        get { bool("numberRow", false) }
        set { defaults.set(newValue, forKey: "numberRow") }
    }

    var longPressDigits: Bool {
        get { bool("longPressDigits", true) }
        set { defaults.set(newValue, forKey: "longPressDigits") }
    }

    // MARK: Feedback

    var haptics: Bool {
        get { bool("haptics", true) }
        set { defaults.set(newValue, forKey: "haptics") }
    }

    var hapticStrength: Float {
        get { float("hapticStrength", 0.7) }
        set { defaults.set(newValue, forKey: "hapticStrength") }
    }

    var sound: Bool {
        get { bool("sound", true) }
        set { defaults.set(newValue, forKey: "sound") }
    }

    var soundVolume: Float {
        get { float("soundVolume", 1.0) }
        set { defaults.set(newValue, forKey: "soundVolume") }
    }

    /// Play Apple's system click instead of our adjustable one.
    var systemSound: Bool {
        get { bool("systemSound", false) }
        set { defaults.set(newValue, forKey: "systemSound") }
    }

    // MARK: Typing

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

    // MARK: Claude

    var claudeEnabled: Bool {
        get { bool("claudeEnabled", false) }
        set { defaults.set(newValue, forKey: "claudeEnabled") }
    }

    var claudeUseSonnet: Bool {
        get { bool("claudeUseSonnet", false) }
        set { defaults.set(newValue, forKey: "claudeUseSonnet") }
    }

    var claudeModel: String {
        claudeUseSonnet ? "claude-sonnet-5-5" : "claude-haiku-5-5"
    }

    var claudeKey: String {
        get { defaults.string(forKey: "claudeKey") ?? "" }
        set { defaults.set(newValue, forKey: "claudeKey") }
    }

    var claudeLastError: String? {
        get { defaults.string(forKey: "claudeLastError") }
        set { defaults.set(newValue, forKey: "claudeLastError") }
    }

    private var today: String {
        String(Int(Date().timeIntervalSince1970 / 86_400))
    }

    var claudeUsageToday: Int {
        defaults.string(forKey: "claudeUsageDay") == today ? defaults.integer(forKey: "claudeUsageCount") : 0
    }

    func recordClaudeRequest() {
        let count = claudeUsageToday + 1
        defaults.set(today, forKey: "claudeUsageDay")
        defaults.set(count, forKey: "claudeUsageCount")
    }
}
