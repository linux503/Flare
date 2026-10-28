import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L("跟随系统")
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// 源码里的中文即键；英文词典在 Resources/en.json，`%@` 按顺序替换参数。
enum L10n {
    static let defaultsKey = "appLanguage"

    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    /// 启动时确定；切换语言后重启生效
    static let isEnglish: Bool = {
        switch language {
        case .zh: return false
        case .en: return true
        case .system:
            let first = Locale.preferredLanguages.first?.lowercased() ?? "zh"
            return !first.hasPrefix("zh")
        }
    }()

    private static let english: [String: String] = {
        guard isEnglish,
              let url = Bundle.main.url(forResource: "en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }()

    static func lookup(_ key: String) -> String {
        guard isEnglish, let value = english[key], !value.isEmpty else { return key }
        return value
    }
}

func L(_ key: String, _ args: Any...) -> String {
    let template = L10n.lookup(key)
    guard !args.isEmpty else { return template }
    var out = ""
    var rest = Substring(template)
    var index = 0
    while let range = rest.range(of: "%@") {
        out += rest[..<range.lowerBound]
        out += index < args.count ? String(describing: args[index]) : ""
        index += 1
        rest = rest[range.upperBound...]
    }
    out += rest
    return out
}
