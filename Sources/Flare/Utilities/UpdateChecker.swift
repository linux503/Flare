import AppKit
import Foundation

/// 在线版本检查（拉取官网 / GitHub Pages 的 version.json）
enum UpdateChecker {
    struct RemoteVersion: Decodable {
        let version: String
        let build: Int?
        let notes: String?
        let downloadURL: String?
        let minOS: String?
    }

    enum CheckResult {
        case upToDate(current: String)
        case updateAvailable(remote: RemoteVersion)
        case failed(String)
    }

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? FlareBrand.version
    }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    static func check() async -> CheckResult {
        guard let url = URL(string: FlareBrand.updateFeedURL) else {
            return .failed("更新地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("FlarePro/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed("服务器返回 \(http.statusCode)")
            }
            let remote = try JSONDecoder().decode(RemoteVersion.self, from: data)
            if isNewer(remote.version, than: currentVersion) {
                return .updateAvailable(remote: remote)
            }
            if let build = remote.build, build > currentBuild {
                return .updateAvailable(remote: remote)
            }
            return .upToDate(current: currentVersion)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 语义化比较：1.2.10 > 1.2.9
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let n = max(r.count, l.count)
        for i in 0..<n {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    @MainActor
    static func checkAndPrompt(silentIfCurrent: Bool = false) async {
        ToastController.shared.show("正在检查更新…")
        let result = await check()
        switch result {
        case .upToDate(let current):
            if !silentIfCurrent {
                ToastController.shared.show("已是最新版 \(current)")
            }
        case .updateAvailable(let remote):
            let alert = NSAlert()
            alert.messageText = "发现新版本 \(remote.version)"
            alert.informativeText = remote.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? (remote.notes ?? "")
                : "当前版本 \(currentVersion)，建议前往官网下载更新。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "稍后再说")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let link = remote.downloadURL.flatMap(URL.init(string:))
                    ?? URL(string: FlareBrand.downloadURL)
                    ?? URL(string: FlareBrand.websiteURL)
                if let link {
                    NSWorkspace.shared.open(link)
                }
            }
        case .failed(let message):
            ToastController.shared.show("检查更新失败：\(message)")
        }
    }
}
