import Foundation

/// The prompt shared by every AI provider, and the parser for its answer.
enum PredictionPrompt {
    static let system = """
    You are the predictive-text engine of an iPhone keyboard. The user writes in Iraqi Arabic \
    (informal dialect spelling, for example شلونك، هسه، شكو، اكو) and in English, sometimes mixed in one message. \
    Reply with ONLY a JSON array of exactly 3 strings and nothing else.
    """

    static func user(context: String, partialWord: String, vocabulary: [String]) -> String {
        var user = ""
        if !vocabulary.isEmpty {
            user += "Words this user types often: " + vocabulary.joined(separator: ", ") + "\n"
        }
        user += "Text before the cursor, between ⟦ and ⟧:\n⟦" + context + "⟧\n"
        if partialWord.isEmpty {
            user += "Give the 3 most likely next words. Each item is one word (two at most), "
            user += "in the same language, dialect and spelling style as the user."
        } else {
            user += "The text ends in the middle of the word \"" + partialWord + "\". "
            user += "Give the 3 most likely complete words the user means: complete it, or fix its spelling. "
            user += "Each item is the full word only."
        }
        return user
    }

    /// Pulls the JSON array out of the model's answer, even if it is wrapped in a code fence or prose.
    static func extractList(from text: String) -> [String] {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]"), start < end else { return [] }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        var seen = Set<String>()
        let words = array
            .compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 30 && seen.insert($0).inserted }
        return Array(words.prefix(3))
    }
}
