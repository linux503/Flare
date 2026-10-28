import Foundation

/// 翻译凭证：优先解密 App 内保险箱，开发时才读本地明文文件。明文不进 UserDefaults。
enum TranslateSecrets {
    typealias Payload = TranslateVault.Payload

    private static var cached: Payload?
    private static let lock = NSLock()

    static func bootstrap() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "translateAPIKey")
        defaults.removeObject(forKey: "translateAPIBaseURL")
        defaults.removeObject(forKey: "translateAPIModel")
        _ = payload()
    }

    static func payload() -> Payload? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        if let bundled = readBundledVault() {
            cached = bundled
            return bundled
        }
        if let local = readDevPlaintext() {
            cached = local
            return local
        }
        return nil
    }

    private static func readBundledVault() -> Payload? {
        let candidates = [
            Bundle.main.url(forResource: "FlareVault", withExtension: "dat"),
            Bundle.main.resourceURL?.appendingPathComponent("FlareVault.dat")
        ]
        for url in candidates.compactMap({ $0 }) {
            guard
                let blob = try? Data(contentsOf: url),
                let plain = try? TranslateVault.open(blob),
                let payload = try? JSONDecoder().decode(Payload.self, from: plain),
                !payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            return payload
        }
        return nil
    }

    private static func readDevPlaintext() -> Payload? {
        for url in devPlaintextURLs() {
            guard
                let data = try? Data(contentsOf: url),
                let payload = try? JSONDecoder().decode(Payload.self, from: data),
                !payload.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            return payload
        }
        return nil
    }

    private static func devPlaintextURLs() -> [URL] {
        var urls: [URL] = []
        let fm = FileManager.default
        urls.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Secrets/translate.json"))
        urls.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".flare/translate-secrets.json"))
        return urls
    }
}
