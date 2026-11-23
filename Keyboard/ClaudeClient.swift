import Foundation

struct ClaudeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Asks Claude (through the user's own API key) for the next words or the word being typed.
/// Only the text before the cursor in the current field is sent (at most 300 characters),
/// plus the user's most frequent words so suggestions match how they write.
final class ClaudeClient {
    private let session: URLSession
    private var task: URLSessionDataTask?
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        session = URLSession(configuration: config)
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as NSError).code == NSURLErrorCancelled
    }

    func suggest(context: String, partialWord: String, vocabulary: [String], model: String, apiKey: String,
                 completion: @escaping (Result<[String], Error>) -> Void) {
        task?.cancel()
        let prompt = Self.prompt(context: context, partialWord: partialWord, vocabulary: vocabulary)
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 60,
            "system": prompt.system,
            "messages": [["role": "user", "content": prompt.user]]
        ]
        task = send(body: body, apiKey: apiKey) { result in
            completion(result.map { Self.extractList(from: $0) })
        }
    }

    func test(apiKey: String, model: String, completion: @escaping (Result<String, Error>) -> Void) {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 10,
            "messages": [["role": "user", "content": "Reply with the single word OK."]]
        ]
        _ = send(body: body, apiKey: apiKey, completion: completion)
    }

    private func send(body: [String: Any], apiKey: String,
                      completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = session.dataTask(with: request) { data, response, error in
            let result = Self.parse(data: data, response: response, error: error)
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }

    static func prompt(context: String, partialWord: String, vocabulary: [String]) -> (system: String, user: String) {
        let system = """
        You are the predictive-text engine of an iPhone keyboard. The user writes in Iraqi Arabic \
        (informal dialect spelling, for example شلونك، هسه، شكو، اكو) and in English, sometimes mixed in one message. \
        Reply with ONLY a JSON array of exactly 3 strings and nothing else.
        """
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
        return (system, user)
    }

    static func parse(data: Data?, response: URLResponse?, error: Error?) -> Result<String, Error> {
        if let error { return .failure(error) }
        guard let data, let http = response as? HTTPURLResponse else {
            return .failure(ClaudeError(message: "ما وصل رد"))
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard http.statusCode == 200 else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            return .failure(ClaudeError(message: message))
        }
        let blocks = json?["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["text"] as? String }.joined()
        return .success(text)
    }

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
