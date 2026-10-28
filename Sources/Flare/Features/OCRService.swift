import AppKit
import CoreImage
import NaturalLanguage
import Vision

struct OCRResult {
    let text: String
    let language: NLLanguage?
    let languageConfidence: Double

    var languageName: String {
        TranslateTargetLanguage.displayName(for: language)
    }
}

enum OCRService {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func recognize(image: NSImage) async -> String {
        await recognizeDetailed(image: image).text
    }

    static func recognizeDetailed(image: NSImage) async -> OCRResult {
        guard let source = cgImage(from: image) else {
            return OCRResult(text: "", language: nil, languageConfidence: 0)
        }
        let prepared = prepare(source)

        async let auto = pieces(prepared, languages: nil, autoDetect: true)
        async let chinese = pieces(prepared, languages: ["zh-Hans", "en-US"], autoDetect: false)
        var merged = merge(primary: await auto, han: await chinese)

        if text(of: merged).count < 2 {
            let contrast = boostContrast(prepared) ?? prepared
            async let boosted = pieces(contrast, languages: nil, autoDetect: true)
            async let eastern = pieces(prepared, languages: ["ja-JP", "ko-KR", "en-US"], autoDetect: false)
            let candidates = [await boosted, await eastern]
            if let longer = candidates.max(by: { text(of: $0).count < text(of: $1).count }),
               text(of: longer).count > text(of: merged).count {
                merged = longer
            }
        }

        let cleaned = tidy(text(of: merged))
        let detected = detectLanguageDetailed(in: cleaned)
        return OCRResult(text: cleaned, language: detected.language, languageConfidence: detected.confidence)
    }

    static func detectLanguage(in text: String) -> NLLanguage? {
        detectLanguageDetailed(in: text).language
    }

    static func detectLanguageDetailed(in text: String) -> (language: NLLanguage?, confidence: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, 0) }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
        guard let best = hypotheses.max(by: { $0.value < $1.value }), best.key != .undetermined else {
            let dominant = recognizer.dominantLanguage
            return (dominant == .undetermined ? nil : dominant, 0)
        }
        return (best.key, best.value)
    }

    // MARK: - Pipeline

    private struct Piece: Sendable {
        let box: CGRect
        let text: String
    }

    private static func pieces(_ image: CGImage, languages: [String]?, autoDetect: Bool) async -> [Piece] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let found = observations.compactMap { observation -> Piece? in
                    guard let best = observation.topCandidates(1).first,
                          !best.string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    return Piece(box: observation.boundingBox, text: best.string)
                }
                continuation.resume(returning: found)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.004
            if let languages, !languages.isEmpty {
                let allowed = filterSupported(languages, level: .accurate)
                if !allowed.isEmpty {
                    request.recognitionLanguages = allowed
                }
            }
            if #available(macOS 13.0, *), autoDetect {
                request.automaticallyDetectsLanguage = true
            }
            do {
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    /// 自动识别对英文更准，但认不出夹在英文里的汉字（会给出「11F28 E」这类乱码）。
    /// 同一位置中文模型认出了汉字时换成中文那一段；自动识别认出的是假名或韩文时保留原样。
    private static func merge(primary: [Piece], han: [Piece]) -> [Piece] {
        guard !han.isEmpty else { return primary }
        guard !primary.isEmpty else { return han }
        var result = primary
        for candidate in han where containsHan(candidate.text) {
            let overlapping = result.indices.filter { overlap(result[$0].box, candidate.box) > 0.5 }
            if overlapping.isEmpty {
                result.append(candidate)
                continue
            }
            let keepsAuto = overlapping.contains { containsKanaOrHangul(result[$0].text) }
            guard !keepsAuto else { continue }
            for index in overlapping.sorted(by: >) { result.remove(at: index) }
            result.append(candidate)
        }
        return result
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? (inter.width * inter.height) / smaller : 0
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
    }

    private static func containsKanaOrHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }
    }

    private static func text(of pieces: [Piece]) -> String {
        struct Row {
            var midY: CGFloat
            var height: CGFloat
            var parts: [(minX: CGFloat, text: String)]
        }

        var rows: [Row] = []
        for piece in pieces {
            let box = piece.box
            let midY = box.midY
            let height = max(box.height, 0.008)
            if let index = rows.firstIndex(where: { abs($0.midY - midY) < max(0.014, $0.height * 0.7) }) {
                rows[index].parts.append((box.minX, piece.text))
                rows[index].midY = (rows[index].midY + midY) / 2
                rows[index].height = max(rows[index].height, height)
            } else {
                rows.append(Row(midY: midY, height: height, parts: [(box.minX, piece.text)]))
            }
        }
        rows.sort { $0.midY > $1.midY }
        return rows.map { joinLine($0.parts.sorted { $0.minX < $1.minX }.map(\.text)) }.joined(separator: "\n")
    }

    private static func joinLine(_ parts: [String]) -> String {
        guard let first = parts.first else { return "" }
        return parts.dropFirst().reduce(into: first) { result, next in
            if needsSpace(between: result, and: next) {
                result += " " + next
            } else {
                result += next
            }
        }
    }

    private static func needsSpace(between left: String, and right: String) -> Bool {
        guard let last = left.unicodeScalars.last, let first = right.unicodeScalars.first else { return true }
        return !(isCJK(last) && isCJK(first))
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value)
            || (0x3040...0x30FF).contains(scalar.value)
            || (0xAC00...0xD7AF).contains(scalar.value)
    }

    private static func tidy(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty {
                if collapsed.last?.isEmpty == false { collapsed.append("") }
            } else {
                collapsed.append(line)
            }
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func filterSupported(_ languages: [String], level: VNRequestTextRecognitionLevel) -> [String] {
        let supported = (try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: level,
            revision: VNRecognizeTextRequest.currentRevision
        )) ?? []
        guard !supported.isEmpty else { return languages }
        let lower = supported.map { $0.lowercased() }
        return languages.filter { lang in
            let key = lang.lowercased()
            return lower.contains(key) || lower.contains(where: { $0.hasPrefix(String(key.prefix(2))) })
        }
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var best: CGImage?
        var bestPixels = 0
        for rep in image.representations {
            if let bitmap = rep as? NSBitmapImageRep, let cg = bitmap.cgImage {
                let pixels = cg.width * cg.height
                if pixels > bestPixels {
                    best = cg
                    bestPixels = pixels
                }
            }
        }
        if let best { return best }
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high]) {
            return cg
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }

    private static func prepare(_ image: CGImage) -> CGImage {
        let minSide = min(image.width, image.height)
        let scale: CGFloat
        if minSide < 32 || minSide >= 600 {
            return image
        }
        scale = min(2.0, 600 / CGFloat(minSide))
        return redraw(image, scale: scale) ?? image
    }

    private static func boostContrast(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(1.18, forKey: kCIInputContrastKey)
        filter?.setValue(0.04, forKey: kCIInputBrightnessKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let out = filter?.outputImage else { return nil }
        return ciContext.createCGImage(out, from: out.extent)
    }

    private static func redraw(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
