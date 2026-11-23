import Foundation

struct GeminiSuggestion {
    let items: [String]
    /// The model and thinking setting that actually worked, so the next request starts there.
    let model: String
    let minimalThinking: Bool
}

/// Asks Gemini (with the user's free Google AI Studio key) for the next words or the word being typed.
/// Free keys allow a limited number of requests per minute, so requests are spaced out and back off on 429.
final class GeminiClient {
    static let defaultModel = "gemini-3.5-flash-lite"
    static let aliasModel = "gemini-flash-lite-latest"
    static var baseURL = "https://generativelanguage.googleapis.com/v1beta"

    private let session: URLSession
    private var task: URLSessionDataTask?
    private var lastRequest = Date.distantPast
    private var backoffUntil = Date.distantPast
    private var minInterval: TimeInterval = 1.0

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

    /// Seconds to wait before the next request is allowed (0 = send now).
    func waitTime(now: Date = Date()) -> TimeInterval {
        max(0, backoffUntil.timeIntervalSince(now), lastRequest.addingTimeInterval(minInterval).timeIntervalSince(now))
    }

    func suggest(context: String, partialWord: String, vocabulary: [String], model: String, minimalThinking: Bool,
                 apiKey: String, completion: @escaping (Result<GeminiSuggestion, Error>) -> Void) {
        task?.cancel()
        lastRequest = Date()
        let user = PredictionPrompt.user(context: context, partialWord: partialWord, vocabulary: vocabulary)
        generate(system: PredictionPrompt.system, user: user, json: true, maxTokens: 300, model: model,
                 minimalThinking: minimalThinking, apiKey: apiKey, retries: 2) { result in
            completion(result.map { reply in
                GeminiSuggestion(items: PredictionPrompt.extractList(from: reply.text),
                                 model: reply.model, minimalThinking: reply.minimalThinking)
            })
        }
    }

    func test(apiKey: String, model: String, minimalThinking: Bool,
              completion: @escaping (Result<GeminiSuggestion, Error>) -> Void) {
        generate(system: nil, user: "Reply with the single word OK.", json: false, maxTokens: 50, model: model,
                 minimalThinking: minimalThinking, apiKey: apiKey, retries: 2) { result in
            completion(result.map { reply in
                GeminiSuggestion(items: [reply.text], model: reply.model, minimalThinking: reply.minimalThinking)
            })
        }
    }

    private struct Reply {
        let text: String
        let model: String
        let minimalThinking: Bool
    }

    /// One request, plus a retry when the model name is unknown (use the -latest alias)
    /// or when the model doesn't accept the thinking setting (drop it).
    private func generate(system: String?, user: String, json: Bool, maxTokens: Int, model: String,
                          minimalThinking: Bool, apiKey: String, retries: Int,
                          completion: @escaping (Result<Reply, Error>) -> Void) {
        let body = Self.body(system: system, user: user, json: json, maxTokens: maxTokens, minimalThinking: minimalThinking)
        task = send(model: model, body: body, apiKey: apiKey) { [weak self] status, payload, error in
            guard let self else { return }
            if let error {
                completion(.failure(error))
                return
            }
            let message = ((payload?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            switch status {
            case 200:
                completion(.success(Reply(text: Self.text(from: payload), model: model, minimalThinking: minimalThinking)))
            case 404 where retries > 0 && model != Self.aliasModel:
                self.generate(system: system, user: user, json: json, maxTokens: maxTokens, model: Self.aliasModel,
                              minimalThinking: minimalThinking, apiKey: apiKey, retries: retries - 1,
                              completion: completion)
            case 400 where retries > 0 && minimalThinking && message.lowercased().contains("think"):
                self.generate(system: system, user: user, json: json, maxTokens: maxTokens, model: model,
                              minimalThinking: false, apiKey: apiKey, retries: retries - 1, completion: completion)
            case 429:
                self.backoffUntil = Date().addingTimeInterval(60)
                self.minInterval = min(self.minInterval * 2, 8)
                completion(.failure(ClaudeError(message: "Gemini: وصلت حد الطلبات المجانية، يرجع يشتغل بعد شوية")))
            default:
                completion(.failure(ClaudeError(message: "Gemini: " + message)))
            }
        }
    }

    private func send(model: String, body: [String: Any], apiKey: String,
                      completion: @escaping (Int, [String: Any]?, Error?) -> Void) -> URLSessionDataTask? {
        guard let url = URL(string: Self.baseURL + "/models/\(model):generateContent") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let task = session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            DispatchQueue.main.async { completion(status, json, error) }
        }
        task.resume()
        return task
    }

    static func body(system: String?, user: String, json: Bool, maxTokens: Int, minimalThinking: Bool) -> [String: Any] {
        var generation: [String: Any] = ["maxOutputTokens": maxTokens]
        if json { generation["responseMimeType"] = "application/json" }
        if minimalThinking { generation["thinkingConfig"] = ["thinkingLevel": "minimal"] }
        var body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": generation
        ]
        if let system {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        return body
    }

    /// Joins the answer's text parts, skipping any "thought" parts.
    static func text(from json: [String: Any]?) -> String {
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { return "" }
        return parts
            .filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
    }
}
