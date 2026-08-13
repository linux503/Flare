import AppKit

/// 截图相关的文本导出（OCR → TXT）。空白「新建 TXT」请用 `DocumentService`。
enum TextFileService {
    @discardableResult
    static func createTXT(
        content: String? = nil,
        suggestedName: String? = nil,
        directory: URL? = nil,
        askWhere: Bool = false
    ) throws -> URL {
        do {
            return try DocumentService.create(
                .txt,
                content: content,
                suggestedName: suggestedName,
                directory: directory ?? AppSettings.shared.documentDirectory,
                askWhere: askWhere
            )
        } catch DocumentService.DocumentError.cancelled {
            throw TextFileError.cancelled
        }
    }

    /// OCR 图片后保存为 txt（属于截图工作流）
    static func createTXTFromOCR(image: NSImage, askWhere: Bool = true) async throws -> URL {
        let text = await OCRService.recognize(image: image)
        let body: String
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            body = """
            # OCR 结果
            创建于 \(f.string(from: Date())) · \(FlareBrand.name)

            （未识别到文字）
            """
        } else {
            body = text + "\n"
        }
        return try await MainActor.run {
            do {
                return try DocumentService.create(
                    .txt,
                    content: body,
                    suggestedName: "\(FlareBrand.name) OCR",
                    directory: AppSettings.shared.saveDirectory,
                    askWhere: askWhere
                )
            } catch DocumentService.DocumentError.cancelled {
                throw TextFileError.cancelled
            }
        }
    }

    static func reveal(_ url: URL) {
        DocumentService.reveal(url)
    }

    static func open(_ url: URL) {
        DocumentService.open(url)
    }

    enum TextFileError: LocalizedError, Equatable {
        case cancelled
        var errorDescription: String? {
            switch self {
            case .cancelled: return "已取消"
            }
        }
    }
}
