import Foundation

/// Settings and learned words, shared by the app and the keyboard and kept across reinstalls.
///
/// Each program works from its own UserDefaults, which is fast. A copy in the keychain (see KeychainBox)
/// carries changes between the two, and brings everything back after the app is installed again.
/// Every copy has a time stamp; the newer one wins.
@MainActor
final class SharedStore {
    enum Section: String, CaseIterable {
        case settings, words
    }

    static let shared: SharedStore = {
        #if canImport(Security)
        return SharedStore(defaults: .standard, box: KeychainBox())
        #else
        return SharedStore(defaults: .standard, box: MemoryBox())
        #endif
    }()

    static let wordKeys = ["pm.unigrams", "pm.bigrams"]
    /// Learned words are copied at most this often while typing (and always when the keyboard closes).
    static let wordsInterval: TimeInterval = 20

    let defaults: UserDefaults
    let box: BlobStore

    /// Settings changed here that the keychain doesn't have yet. A newer copy from the other side
    /// never overwrites them.
    private var dirtySettings: Set<String> = []
    private var settingsGeneration = 0
    private var wordsPending = false
    private var wordsScheduled = false
    private var lastWordsPush = Date.distantPast

    init(defaults: UserDefaults, box: BlobStore) {
        self.defaults = defaults
        self.box = box
    }

    /// The app and the keyboard read and write the same copy.
    var isShared: Bool { box.isShared }
    /// Settings and words come back after reinstalling.
    var survivesReinstall: Bool { box.isAvailable }

    // MARK: Pull

    /// Takes in what the other side (or an earlier install) saved. Returns the sections that changed here.
    @discardableResult
    func pull() -> Set<Section> {
        var changed: Set<Section> = []
        for section in Section.allCases where pull(section) {
            changed.insert(section)
        }
        return changed
    }

    @discardableResult
    func pull(_ section: Section) -> Bool {
        guard box.isAvailable else { return false }
        let local = localStamp(section)
        guard let remote = box.stamp(section.rawValue) else {
            // Nothing in the keychain yet (first run of this version): keep a copy of what is here.
            if hasData(section) { push(section) }
            return false
        }
        if remote > local {
            guard let item = box.read(section.rawValue), apply(section, item.data) else { return false }
            setLocalStamp(section, item.stamp)
            return true
        }
        if local > remote { push(section) }
        return false
    }

    // MARK: Push

    /// Copies this section to the keychain. Empty learned words are only copied when `force`
    /// (the user reset them), so a failed restore can never wipe the saved copy.
    func push(_ section: Section, force: Bool = false) {
        guard box.isAvailable else { return }
        if section == .words {
            lastWordsPush = Date()
            wordsPending = false
            if !force && !hasData(.words) { return }
        }
        guard let data = snapshot(section) else { return }
        let stamp = max(Date().timeIntervalSince1970, localStamp(section) + 0.001)
        if box.write(section.rawValue, data: data, stamp: stamp) {
            setLocalStamp(section, stamp)
        }
    }

    func settingChanged(_ key: String) {
        dirtySettings.insert(key)
        settingsGeneration += 1
        let generation = settingsGeneration
        // Sliders change many times a second: copy once they settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.settingsGeneration == generation else { return }
            self.flushSettings()
        }
    }

    func wordsChanged() {
        wordsPending = true
        let wait = Self.wordsInterval - Date().timeIntervalSince(lastWordsPush)
        if wait <= 0 {
            flushWords()
            return
        }
        guard !wordsScheduled else { return }
        wordsScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.wordsScheduled = false
            self.flushWords()
        }
    }

    /// Copies everything waiting to the keychain now (the keyboard is closing, the app is leaving).
    func flush() {
        flushSettings()
        flushWords()
    }

    func flushSettings() {
        guard !dirtySettings.isEmpty else { return }
        settingsGeneration += 1
        pull(.settings)  // take in newer changes from the other side, keeping ours
        push(.settings)
        dirtySettings.removeAll()
    }

    func flushWords() {
        guard wordsPending else { return }
        push(.words)
    }

    // MARK: Contents

    private func localStamp(_ section: Section) -> Double {
        defaults.double(forKey: "sync." + section.rawValue)
    }

    private func setLocalStamp(_ section: Section, _ stamp: Double) {
        defaults.set(stamp, forKey: "sync." + section.rawValue)
    }

    func hasData(_ section: Section) -> Bool {
        switch section {
        case .settings:
            return KeyboardSettings.syncedKeys.contains { defaults.object(forKey: $0) != nil }
        case .words:
            return !(defaults.dictionary(forKey: "pm.unigrams")?.isEmpty ?? true)
        }
    }

    private func snapshot(_ section: Section) -> Data? {
        switch section {
        case .settings:
            var values: [String: Any] = [:]
            for key in KeyboardSettings.syncedKeys {
                if let value = defaults.object(forKey: key) { values[key] = value }
            }
            return try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        case .words:
            let values: [String: Any] = [
                "u": defaults.dictionary(forKey: "pm.unigrams") ?? [:],
                "b": defaults.dictionary(forKey: "pm.bigrams") ?? [:]
            ]
            guard let raw = try? PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0) else {
                return nil
            }
            return Self.pack(raw)
        }
    }

    private func apply(_ section: Section, _ data: Data) -> Bool {
        switch section {
        case .settings:
            guard let values = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
                return false
            }
            // Merge: keys the other side never set keep their value here.
            for (key, value) in values where KeyboardSettings.syncedKeys.contains(key) && !dirtySettings.contains(key) {
                defaults.set(value, forKey: key)
            }
            return true
        case .words:
            guard let raw = Self.unpack(data),
                  let values = (try? PropertyListSerialization.propertyList(from: raw, format: nil)) as? [String: Any] else {
                return false
            }
            defaults.set(values["u"] as? [String: Int] ?? [:], forKey: "pm.unigrams")
            defaults.set(values["b"] as? [String: [String: Int]] ?? [:], forKey: "pm.bigrams")
            return true
        }
    }

    /// First byte says how the rest is stored: 1 = zlib, 0 = as is.
    static func pack(_ data: Data) -> Data {
        #if canImport(Darwin)
        if let compressed = try? (data as NSData).compressed(using: .zlib) as Data {
            return Data([1]) + compressed
        }
        #endif
        return Data([0]) + data
    }

    static func unpack(_ data: Data) -> Data? {
        guard let kind = data.first else { return nil }
        let body = Data(data.dropFirst())
        switch kind {
        case 0:
            return body
        case 1:
            #if canImport(Darwin)
            return try? (body as NSData).decompressed(using: .zlib) as Data
            #else
            return nil
            #endif
        default:
            return nil
        }
    }
}
