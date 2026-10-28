import Foundation
import CryptoKit

/// 打包进 App 的翻译凭证保险箱。明文 Key 不进源码；运行时只在内存解密。
enum TranslateVault {
    struct Payload: Codable {
        var apiBaseURL: String
        var apiKey: String
        var model: String
    }

    private static let magic = Data([0x46, 0x4C, 0x52, 0x56]) // FLRV
    private static let version: UInt8 = 1

    static func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: wrappingKey())
        guard let combined = box.combined else {
            throw VaultError.sealFailed
        }
        var out = Data()
        out.append(magic)
        out.append(version)
        out.append(combined)
        return out
    }

    static func open(_ blob: Data) throws -> Data {
        guard blob.count > magic.count + 1 else { throw VaultError.invalidBlob }
        guard blob.prefix(magic.count) == magic else { throw VaultError.invalidBlob }
        let ver = blob[magic.count]
        guard ver == version else { throw VaultError.unsupportedVersion }
        let combined = blob.suffix(from: magic.count + 1)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: wrappingKey())
    }

    /// 运行时拼出包装密钥，避免源码里出现完整明文串。
    static func wrappingKey() -> SymmetricKey {
        var a: [UInt8] = [
            0x3C, 0x91, 0xA8, 0x17, 0xE2, 0x54, 0x0B, 0x6D,
            0xC4, 0x2F, 0x79, 0xB1, 0x08, 0xDE, 0x63, 0x95,
            0xFA, 0x11, 0x47, 0x88, 0x2A, 0xD0, 0x5E, 0x73,
            0x9B, 0x06, 0xC8, 0x3D, 0xE4, 0x50, 0x1F, 0xA2
        ]
        let b: [UInt8] = [
            0x67, 0xD4, 0x19, 0xAE, 0xB8, 0x03, 0xF1, 0x2C,
            0x55, 0x8A, 0xE0, 0x4D, 0x97, 0x21, 0xCB, 0x6E,
            0x04, 0xF7, 0x3A, 0x81, 0xC6, 0x59, 0x0D, 0xB2,
            0xE8, 0x14, 0x70, 0x9F, 0x2B, 0xA5, 0xD6, 0x48
        ]
        for i in 0..<32 { a[i] ^= b[i] }
        var material = Data(a)
        material.append(contentsOf: Array("app.flare.screenshot".utf8))
        material.append(contentsOf: Array("flare.vault.v1".utf8))
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: Data(digest))
    }

    enum VaultError: Error {
        case sealFailed
        case invalidBlob
        case unsupportedVersion
    }
}
