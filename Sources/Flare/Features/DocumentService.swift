import AppKit
import UniformTypeIdentifiers

/// 独立「新建文档」能力（与截图无关）
enum DocumentKind: String, CaseIterable, Identifiable {
    case txt
    case word
    case powerpoint
    case spreadsheet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .txt: return "文本 TXT"
        case .word: return "Word 文档"
        case .powerpoint: return "PPT 演示文稿"
        case .spreadsheet: return "表格 Excel"
        }
    }

    var shortTitle: String {
        switch self {
        case .txt: return "TXT"
        case .word: return "Word"
        case .powerpoint: return "PPT"
        case .spreadsheet: return "表格"
        }
    }

    var glyph: SnapGlyph {
        switch self {
        case .txt: return .txt
        case .word: return .word
        case .powerpoint: return .powerpoint
        case .spreadsheet: return .spreadsheet
        }
    }

    var subtitle: String {
        switch self {
        case .txt: return "空白纯文本 · .txt"
        case .word: return "空白文档 · .docx"
        case .powerpoint: return "空白幻灯片 · .pptx"
        case .spreadsheet: return "空白表格 · .xlsx"
        }
    }

    var isAvailable: Bool { true }

    var fileExtension: String {
        switch self {
        case .txt: return "txt"
        case .word: return "docx"
        case .powerpoint: return "pptx"
        case .spreadsheet: return "xlsx"
        }
    }

    var contentTypes: [UTType] {
        switch self {
        case .txt: return [.plainText]
        case .word:
            return [UTType(filenameExtension: "docx") ?? .data]
        case .powerpoint:
            return [UTType(filenameExtension: "pptx") ?? .data]
        case .spreadsheet:
            return [UTType(filenameExtension: "xlsx") ?? .data]
        }
    }
}

enum DocumentService {
    enum DocumentError: LocalizedError, Equatable {
        case cancelled
        case notAvailable(DocumentKind)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .cancelled: return "已取消"
            case .notAvailable(let kind): return "「\(kind.title)」暂不可用"
            case .writeFailed: return "创建失败"
            }
        }
    }

    @discardableResult
    static func create(
        _ kind: DocumentKind,
        content: String? = nil,
        suggestedName: String? = nil,
        directory: URL? = nil,
        askWhere: Bool = true
    ) throws -> URL {
        guard kind.isAvailable else { throw DocumentError.notAvailable(kind) }

        let dir = directory ?? AppSettings.shared.documentDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            return f.string(from: Date())
        }()

        let baseName = (suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(kind.shortTitle) \(stamp)"
        let ext = kind.fileExtension
        let fileName = baseName.lowercased().hasSuffix(".\(ext)") ? baseName : "\(baseName).\(ext)"

        if askWhere {
            let panel = NSSavePanel()
            panel.allowedContentTypes = kind.contentTypes
            panel.nameFieldStringValue = fileName
            panel.directoryURL = dir
            panel.title = "新建\(kind.title)"
            panel.prompt = "创建"
            guard panel.runModal() == .OK, let url = panel.url else {
                throw DocumentError.cancelled
            }
            try write(kind: kind, to: url, content: content)
            return url
        }

        var url = dir.appendingPathComponent(fileName)
        var idx = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let stem = (fileName as NSString).deletingPathExtension
            url = dir.appendingPathComponent("\(stem) \(idx).\(ext)")
            idx += 1
        }
        try write(kind: kind, to: url, content: content)
        return url
    }

    static func createTXT(
        content: String? = nil,
        suggestedName: String? = nil,
        askWhere: Bool = true
    ) throws -> URL {
        try create(.txt, content: content, suggestedName: suggestedName, askWhere: askWhere)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// 统一入口：创建后打开，并在 Finder 中显示
    static func createAndReveal(_ kind: DocumentKind, askWhere: Bool = true) {
        do {
            let url = try create(kind, askWhere: askWhere)
            ToastController.shared.show("已创建 \(url.lastPathComponent)")
            open(url)
            // 稍后再定位 Finder，避免抢焦点盖住打开的文档
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                reveal(url)
            }
        } catch DocumentError.cancelled {
            return
        } catch {
            ToastController.shared.show(error.localizedDescription)
        }
    }

    private static func write(kind: DocumentKind, to url: URL, content: String?) throws {
        // 覆盖已有文件时先删掉，保证 zip 写入干净
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let title = url.deletingPathExtension().lastPathComponent
        switch kind {
        case .txt:
            let body = content ?? defaultTXTBody(title: title)
            try body.write(to: url, atomically: true, encoding: .utf8)
        case .word:
            try OfficePackage.writeDOCX(to: url, title: title)
        case .powerpoint:
            try OfficePackage.writePPTX(to: url, title: title)
        case .spreadsheet:
            try OfficePackage.writeXLSX(to: url, title: title)
        }
    }

    private static func defaultTXTBody(title: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return """
        # \(title)
        创建于 \(f.string(from: Date())) · \(FlareBrand.name)

        """
    }
}
