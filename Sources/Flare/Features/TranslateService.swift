import Foundation

enum TranslateService {
    struct TranslateError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 45
        return URLSession(configuration: config)
    }()

    static func translate(
        text: String,
        sourceName: String,
        target: TranslateTargetLanguage
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslateError(message: "没有可翻译的文字")
        }

        guard let secret = TranslateSecrets.payload() else {
            throw TranslateError(message: "未配置翻译接口")
        }
        let key = secret.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw TranslateError(message: "未配置翻译接口")
        }
        guard let url = endpoint(from: secret.apiBaseURL) else {
            throw TranslateError(message: "翻译接口地址无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body = ChatRequest(
            model: secret.model,
            temperature: 0.1,
            messages: [
                ChatMessage(role: "system", content: systemPrompt(sourceName: sourceName, target: target)),
                ChatMessage(role: "user", content: trimmed)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 {
            throw TranslateError(message: "翻译接口鉴权失败")
        }
        if status == 429 {
            throw TranslateError(message: "翻译接口繁忙，请稍后再试")
        }
        if !(200...299).contains(status) {
            throw TranslateError(message: apiErrorMessage(from: data, status: status))
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            throw TranslateError(message: "翻译接口没有返回译文")
        }
        return stripWrapping(content)
    }

    private static func endpoint(from baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/chat/completions")
    }

    private static func systemPrompt(sourceName: String, target: TranslateTargetLanguage) -> String {
        """
        你是截图 OCR 文本的专业翻译。
        原文语言：\(sourceName)。
        请翻译成\(target.displayName)（\(target.rawValue)）。
        保留换行、编号、链接、代码和专有名词。
        只输出译文，不要解释，不要加引号。
        """
    }

    private static func apiErrorMessage(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = obj["error"] as? [String: Any],
               let message = err["message"] as? String,
               !message.isEmpty {
                return "翻译失败：\(message)"
            }
            if let message = obj["message"] as? String, !message.isEmpty {
                return "翻译失败：\(message)"
            }
        }
        return "翻译失败（HTTP \(status)）"
    }

    private static func stripWrapping(_ text: String) -> String {
        var out = text
        if out.hasPrefix("```") {
            let lines = out.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count >= 3, lines.last?.hasPrefix("```") == true {
                out = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        if out.hasPrefix("\"") && out.hasSuffix("\"") && out.count > 1 {
            out = String(out.dropFirst().dropLast())
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let temperature: Double
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String?
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}
