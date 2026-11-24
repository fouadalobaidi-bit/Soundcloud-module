import Foundation

/// Learns from what the user actually types, on the phone only:
/// how often each word is used, and which word tends to follow which.
/// That drives completions, next-word predictions and the vocabulary hint sent to the AI.
/// Saved through SharedStore, so the words survive installing a new version.
@MainActor
final class PersonalModel {
    private var defaults: UserDefaults { SharedStore.shared.defaults }
    private var unigrams: [String: Int]
    private var bigrams: [String: [String: Int]]
    private var unsaved = 0

    private static let maxWords = 5_000
    private static let maxPairs = 3_000
    private static let maxFollowers = 24

    init() {
        let defaults = SharedStore.shared.defaults
        unigrams = defaults.dictionary(forKey: "pm.unigrams") as? [String: Int] ?? [:]
        bigrams = defaults.dictionary(forKey: "pm.bigrams") as? [String: [String: Int]] ?? [:]
    }

    /// Reads the words again after SharedStore brought in a newer copy (restored, or reset in the app).
    func reload() {
        unigrams = defaults.dictionary(forKey: "pm.unigrams") as? [String: Int] ?? [:]
        bigrams = defaults.dictionary(forKey: "pm.bigrams") as? [String: [String: Int]] ?? [:]
        unsaved = 0
    }

    static func normalize(_ word: String) -> String {
        word.lowercased()
    }

    var wordCount: Int { unigrams.count }

    func learn(word: String, previous: String?) {
        let w = Self.normalize(word)
        guard w.count >= 2, w.count <= 24, w.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) else { return }
        unigrams[w, default: 0] += 1
        if let previous {
            let p = Self.normalize(previous)
            if p.count >= 1 {
                bigrams[p, default: [:]][w, default: 0] += 1
            }
        }
        unsaved += 1
        if unsaved >= 5 { save() }
    }

    /// Writes what was learned since the last save. Nothing new, nothing written.
    func save() {
        guard unsaved > 0 else { return }
        prune()
        defaults.set(unigrams, forKey: "pm.unigrams")
        defaults.set(bigrams, forKey: "pm.bigrams")
        unsaved = 0
        SharedStore.shared.wordsChanged()
    }

    func reset() {
        unigrams = [:]
        bigrams = [:]
        unsaved = 0
        defaults.set(unigrams, forKey: "pm.unigrams")
        defaults.set(bigrams, forKey: "pm.bigrams")
        SharedStore.shared.push(.words, force: true)
    }

    /// The user knows this word (typed it at least twice), so it should not be "corrected".
    func knows(_ word: String) -> Bool {
        (unigrams[Self.normalize(word)] ?? 0) >= 2
    }

    func completions(for prefix: String, limit: Int) -> [String] {
        let p = Self.normalize(prefix)
        guard !p.isEmpty else { return [] }
        return unigrams
            .filter { $0.key.count > p.count && $0.key.hasPrefix(p) }
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    func nextWords(after previous: String, limit: Int) -> [String] {
        guard let followers = bigrams[Self.normalize(previous)] else { return [] }
        return followers
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    func topWords(_ limit: Int) -> [String] {
        unigrams
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }

    private func prune() {
        if unigrams.count > Self.maxWords {
            let keep = unigrams.sorted { $0.value > $1.value }.prefix(Self.maxWords * 4 / 5)
            unigrams = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if bigrams.count > Self.maxPairs {
            let keep = bigrams
                .map { (key: $0.key, total: $0.value.values.reduce(0, +), value: $0.value) }
                .sorted { $0.total > $1.total }
                .prefix(Self.maxPairs * 4 / 5)
            bigrams = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        for (key, followers) in bigrams where followers.count > Self.maxFollowers {
            let keep = followers.sorted { $0.value > $1.value }.prefix(Self.maxFollowers)
            bigrams[key] = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}
