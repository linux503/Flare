import AppKit
import NaturalLanguage
import Vision

struct OCRResult {
    let text: String
    let language: NLLanguage?

    var languageName: String {
        TranslateTargetLanguage.displayName(for: language)
    }
}

enum OCRService {
    static func recognize(image: NSImage) async -> String {
        await recognizeDetailed(image: image).text
    }

    static func recognizeDetailed(image: NSImage) async -> OCRResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return OCRResult(text: "", language: nil)
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: OCRResult(text: text, language: detectLanguage(in: text)))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = [
                "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR",
                "fr-FR", "de-DE", "es-ES", "ru-RU", "pt-BR", "it-IT",
                "vi-VT", "th-TH", "ar-SA"
            ]
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: OCRResult(text: "", language: nil))
            }
        }
    }

    static func detectLanguage(in text: String) -> NLLanguage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        return language
    }
}
