import Foundation

/// Otpix 临时邮箱（https://otpx.top）REST 客户端。原生 URLSession 不受浏览器 CORS 限制。
enum OtpixClient {
    static let home = URL(string: "https://otpx.top/")!
    static let domains = ["otpx.top", "linshimail.top", "tempyx.top"]

    struct Box: Decodable {
        let ok: Bool
        let addr: String?
        let recover: String?
        let error: String?
    }

    struct Message: Decodable, Identifiable, Hashable {
        let id: String
        let sender: String?
        let subject: String?
        let codes: [String]?
        let created_at: Double?
        let expires_at: Double?
        let ago: String?
    }

    struct Inbox: Decodable {
        let ok: Bool
        let addr: String?
        let messages: [Message]?
        let error: String?
    }

    struct Mail: Decodable {
        let ok: Bool
        let id: String?
        let sender: String?
        let subject: String?
        let codes: [String]?
        let text: String?
        let html: String?
        let error: String?
    }

    static func create(addr: String) async throws -> Box {
        try await postJSON(path: "/api/box", body: ["addr": addr])
    }

    static func restore(key: String) async throws -> Box {
        try await getJSON(path: "/api/box", query: ["key": key])
    }

    static func inbox(addr: String) async throws -> Inbox {
        try await getJSON(path: "/api/inbox", query: ["addr": addr])
    }

    static func mail(addr: String, id: String) async throws -> Mail {
        try await getJSON(path: "/api/mail", query: ["addr": addr, "id": id])
    }

    static func clearInbox(addr: String) async throws {
        var request = URLRequest(url: url("/api/inbox", ["addr": addr]))
        request.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 400 else {
            throw OtpixError.network
        }
    }

    static func randomLocal() -> String {
        let names = [
            "alex", "amy", "anna", "ben", "carl", "cole", "dan", "eli", "emma", "eva",
            "finn", "grace", "hank", "ivy", "jack", "jake", "jane", "jess", "joe", "kai",
            "leo", "liam", "lisa", "lucy", "luke", "max", "mia", "mike", "nina", "noah",
            "owen", "paul", "ryan", "sam", "sara", "sean", "tom", "tony", "vera", "will"
        ]
        let tags = ["6", "7", "8", "11", "16", "21", "24", "27", "66", "68", "77", "86", "88", "123", "168"]
        return (names.randomElement() ?? "flare") + (tags.randomElement() ?? "88")
    }

    static func validLocal(_ raw: String) -> String? {
        let local = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard local.range(of: #"^[a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?$"#, options: .regularExpression) != nil else {
            return nil
        }
        if isReserved(local) { return nil }
        return local
    }

    static func validRecover(_ raw: String) -> String? {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let match = upper.range(of: #"^RK-[A-Z2-9]{8}$"#, options: .regularExpression) else { return nil }
        return String(upper[match])
    }

    static func validAddr(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = s.range(
            of: #"^([a-z0-9](?:[a-z0-9._-]{0,30}[a-z0-9])?)@(otpx\.top|linshimail\.top|tempyx\.top)$"#,
            options: .regularExpression
        ) else { return nil }
        let addr = String(s[match])
        let local = addr.split(separator: "@").first.map(String.init) ?? ""
        if isReserved(local) { return nil }
        return addr
    }

    static func shareURL(for addr: String) -> URL? {
        var c = URLComponents(url: home, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "inbox", value: addr)]
        return c?.url
    }

    static func mailPageURL(addr: String, id: String) -> URL {
        url("/api/mail-page", ["addr": addr, "id": id])
    }

    private static func isReserved(_ local: String) -> Bool {
        let core = local.replacingOccurrences(of: "[._-]", with: "", options: .regularExpression)
        if core.range(of: #"^\d{1,3}$"#, options: .regularExpression) != nil { return true }
        let reserved = [
            "admin", "administrator", "adm", "system", "sys", "info", "root",
            "postmaster", "abuse", "webmaster", "support", "noreply", "www"
        ]
        return reserved.contains { core == $0 || core.hasPrefix($0) }
    }

    private static func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var c = URLComponents(string: "https://otpx.top" + path)!
        if !query.isEmpty {
            c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return c.url!
    }

    private static func getJSON<T: Decodable>(path: String, query: [String: String]) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url(path, query))
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 500 else { throw OtpixError.network }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func postJSON<T: Decodable>(path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 500 else { throw OtpixError.network }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum OtpixError: LocalizedError {
    case network
    case message(String)

    var errorDescription: String? {
        switch self {
        case .network: return L("网络中断，请稍后重试")
        case .message(let text): return text
        }
    }
}
