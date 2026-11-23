import UIKit

struct SuggestionResult {
    var typed: String
    var candidates: [String]
    var correction: String?
    var isMisspelled: Bool
}

/// Word suggestions and spelling correction on top of Apple's on-device UITextChecker.
/// Nothing leaves the phone.
@MainActor
final class SuggestionEngine {
    private let checker = UITextChecker()
    private let defaults = UserDefaults.standard
    private var learned: Set<String>
    private var languageCache: [KeyboardLanguage: String?] = [:]

    init() {
        learned = Set(defaults.stringArray(forKey: "learnedWords") ?? [])
    }

    func languageCode(for language: KeyboardLanguage) -> String? {
        if let cached = languageCache[language] { return cached }
        let available = UITextChecker.availableLanguages
        let code: String?
        switch language {
        case .english:
            code = available.first(where: { $0 == "en_US" }) ?? available.first(where: { $0.hasPrefix("en") })
        case .arabic:
            code = available.first(where: { $0.hasPrefix("ar") })
        }
        languageCache.updateValue(code, forKey: language)
        return code
    }

    func learn(_ word: String) {
        let w = word.lowercased()
        guard !w.isEmpty, !learned.contains(w) else { return }
        learned.insert(w)
        UITextChecker.learnWord(w)
        defaults.set(Array(learned), forKey: "learnedWords")
    }

    func isLearned(_ word: String) -> Bool {
        learned.contains(word.lowercased())
    }

    func suggest(for word: String, language: KeyboardLanguage, replacements: [String: String],
                 personal: PersonalModel) -> SuggestionResult {
        var result = SuggestionResult(typed: word, candidates: [], correction: nil, isMisspelled: false)
        let replacement = replacements[word.lowercased()]
        // The user's own words come first.
        let personalCompletions = personal.completions(for: word, limit: 3).map { Self.matchCase($0, to: word) }

        if let code = languageCode(for: language) {
            let range = NSRange(location: 0, length: (word as NSString).length)
            let miss = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: code)
            let misspelled = miss.location != NSNotFound && !isLearned(word) && !personal.knows(word)
            result.isMisspelled = misspelled

            var candidates: [String] = []
            if misspelled {
                let guesses = (checker.guesses(forWordRange: range, in: word, language: code) ?? [])
                    .map { Self.matchCase($0, to: word) }
                if let best = guesses.first, word.count >= 2,
                   Self.distance(best.lowercased(), word.lowercased()) <= max(1, word.count / 3) {
                    result.correction = best
                }
                candidates += guesses
            }
            let completions = (checker.completions(forPartialWordRange: range, in: word, language: code) ?? [])
                .map { Self.matchCase($0, to: word) }
            candidates += completions
            result.candidates = candidates
        }
        result.candidates = personalCompletions + result.candidates

        if let replacement {
            result.correction = replacement
            result.candidates.insert(replacement, at: 0)
        }

        var seen: Set<String> = [word]
        result.candidates = result.candidates.filter { seen.insert($0).inserted }
        if let c = result.correction {
            result.candidates.removeAll { $0 == c }
            result.candidates.insert(c, at: 0)
        }
        result.candidates = Array(result.candidates.prefix(2))
        return result
    }

    static func matchCase(_ candidate: String, to word: String) -> String {
        guard let first = word.first, first.isUppercase else { return candidate }
        if word.count > 1, word == word.uppercased() { return candidate.uppercased() }
        return candidate.prefix(1).uppercased() + String(candidate.dropFirst())
    }

    static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
