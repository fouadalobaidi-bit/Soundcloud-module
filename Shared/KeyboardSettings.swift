import Foundation

enum AIProvider: String {
    case gemini, claude
}

/// Settings, used by both the keyboard and the app. Stored through SharedStore, so a change made in
/// the app reaches the keyboard, and everything comes back after installing a new version.
@MainActor
final class KeyboardSettings {
    static let shared = KeyboardSettings()
    static let aiDailyLimit = 1000

    /// What SharedStore copies between the app and the keyboard. The language and the model that last
    /// answered stay local, so typing never waits on the keychain.
    static let syncedKeys: Set<String> = [
        "numberRow", "longPressDigits", "haptics", "hapticStrength", "sound", "soundVolume", "systemSound",
        "autocorrectEnglish", "autocorrectArabic", "arabicDigits",
        "claudeEnabled", "aiProvider", "claudeUseSonnet", "claudeKey", "geminiKey", "presetKeyImported"
    ]

    private var store: SharedStore { SharedStore.shared }
    private var defaults: UserDefaults { store.defaults }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    /// Saves a value and, for shared settings, tells SharedStore. Unchanged values are ignored.
    private func write(_ value: Any, _ key: String) {
        if let old = defaults.object(forKey: key) as? NSObject, let new = value as? NSObject, old.isEqual(new) {
            return
        }
        defaults.set(value, forKey: key)
        if Self.syncedKeys.contains(key) {
            store.settingChanged(key)
        }
    }

    private func float(_ key: String, _ fallback: Float) -> Float {
        (defaults.object(forKey: key) as? NSNumber)?.floatValue ?? fallback
    }

    // MARK: Look

    var numberRow: Bool {
        get { bool("numberRow", false) }
        set { write(newValue, "numberRow") }
    }

    var longPressDigits: Bool {
        get { bool("longPressDigits", true) }
        set { write(newValue, "longPressDigits") }
    }

    // MARK: Feedback

    var haptics: Bool {
        get { bool("haptics", true) }
        set { write(newValue, "haptics") }
    }

    var hapticStrength: Float {
        get { float("hapticStrength", 0.7) }
        set { write(newValue, "hapticStrength") }
    }

    var sound: Bool {
        get { bool("sound", true) }
        set { write(newValue, "sound") }
    }

    var soundVolume: Float {
        get { float("soundVolume", 1.0) }
        set { write(newValue, "soundVolume") }
    }

    /// Play Apple's system click instead of our adjustable one.
    var systemSound: Bool {
        get { bool("systemSound", false) }
        set { write(newValue, "systemSound") }
    }

    // MARK: Typing

    var autocorrectEnglish: Bool {
        get { bool("autocorrectEnglish", true) }
        set { write(newValue, "autocorrectEnglish") }
    }

    var autocorrectArabic: Bool {
        get { bool("autocorrectArabic", false) }
        set { write(newValue, "autocorrectArabic") }
    }

    var arabicDigits: Bool {
        get { bool("arabicDigits", false) }
        set { write(newValue, "arabicDigits") }
    }

    var language: KeyboardLanguage {
        get { KeyboardLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .arabic }
        set { write(newValue.rawValue, "language") }
    }

    // MARK: AI suggestions

    var aiEnabled: Bool {
        get { bool("claudeEnabled", false) }
        set { write(newValue, "claudeEnabled") }
    }

    var aiProvider: AIProvider {
        get { AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .gemini }
        set { write(newValue.rawValue, "aiProvider") }
    }

    /// The key for whichever provider is selected.
    var activeKey: String {
        aiProvider == .claude ? claudeKey : geminiKey
    }

    var claudeUseSonnet: Bool {
        get { bool("claudeUseSonnet", false) }
        set { write(newValue, "claudeUseSonnet") }
    }

    var claudeModel: String {
        claudeUseSonnet ? "claude-sonnet-5-5" : "claude-haiku-5-5"
    }

    var claudeKey: String {
        get { defaults.string(forKey: "claudeKey") ?? "" }
        set { write(newValue, "claudeKey") }
    }

    var geminiKey: String {
        get { defaults.string(forKey: "geminiKey") ?? "" }
        set { write(newValue, "geminiKey") }
    }

    var geminiModel: String {
        get { defaults.string(forKey: "geminiModel") ?? GeminiClient.defaultModel }
        set { write(newValue, "geminiModel") }
    }

    var geminiMinimalThinking: Bool {
        get { bool("geminiMinimalThinking", true) }
        set { write(newValue, "geminiMinimalThinking") }
    }

    var aiLastError: String? {
        get { defaults.string(forKey: "claudeLastError") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "claudeLastError")
            } else {
                defaults.removeObject(forKey: "claudeLastError")
            }
        }
    }

    // MARK: Built-in key

    /// A private copy of the keyboard can carry a Gemini key in Preset.plist (it is never in the public code).
    /// It is copied into the settings once. "مسح المفتاح" removes it for good: the same key is not imported again.
    func importPresetKeyIfNeeded(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "Preset", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let raw = plist["geminiKey"] as? String else { return }
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let stamp = Self.fingerprint(key)
        guard defaults.string(forKey: "presetKeyImported") != stamp else { return }
        write(stamp, "presetKeyImported")
        geminiKey = key
        aiProvider = .gemini
        aiEnabled = true
        aiLastError = nil
    }

    /// The Gemini key in use is the one that came with the app.
    var usesPresetKey: Bool {
        !geminiKey.isEmpty && defaults.string(forKey: "presetKeyImported") == Self.fingerprint(geminiKey)
    }

    /// Enough to recognise the key again without keeping a second copy of it.
    private static func fingerprint(_ key: String) -> String {
        "\(key.count):" + String(key.suffix(6))
    }

    private var today: String {
        String(Int(Date().timeIntervalSince1970 / 86_400))
    }

    var aiUsageToday: Int {
        defaults.string(forKey: "claudeUsageDay") == today ? defaults.integer(forKey: "claudeUsageCount") : 0
    }

    func recordAIRequest() {
        let count = aiUsageToday + 1
        defaults.set(today, forKey: "claudeUsageDay")
        defaults.set(count, forKey: "claudeUsageCount")
    }
}
