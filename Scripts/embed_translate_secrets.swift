import Foundation

@main
enum EmbedTranslateVault {
    static func main() {
        guard CommandLine.arguments.count >= 3 else {
            fputs("usage: embed-translate-vault <translate.json> <FlareVault.dat>\n", stderr)
            exit(1)
        }
        do {
            let src = URL(fileURLWithPath: CommandLine.arguments[1])
            let dst = URL(fileURLWithPath: CommandLine.arguments[2])
            let plain = try Data(contentsOf: src)
            _ = try JSONDecoder().decode(TranslateVault.Payload.self, from: plain)
            let sealed = try TranslateVault.seal(plain)
            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sealed.write(to: dst, options: .atomic)
            fputs("embedded translate vault\n", stderr)
        } catch {
            fputs("embed failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
