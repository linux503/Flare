import AppKit
import UniformTypeIdentifiers

enum ImageExporter {
    static func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        if let png = pngData(from: image) {
            pb.setData(png, forType: .png)
        }
    }

    static func save(_ image: NSImage, to directory: URL? = nil, format: ImageFormat? = nil) throws -> URL {
        let settings = AppSettings.shared
        let dir = directory ?? settings.saveDirectory
        let fmt = format ?? settings.imageFormat
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "\(FlareBrand.name) \(formatter.string(from: Date())).\(fmt.fileExtension)"
        let url = dir.appendingPathComponent(name)
        try write(image, to: url, format: fmt)
        return url
    }

    static func write(_ image: NSImage, to url: URL, format: ImageFormat) throws {
        if format == .png, let data = pngData(from: image) {
            try data.write(to: url, options: .atomic)
            return
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw ExportError.encodingFailed
        }

        let type: NSBitmapImageRep.FileType
        let props: [NSBitmapImageRep.PropertyKey: Any]
        switch format {
        case .png:
            type = .png
            props = [:]
        case .jpeg:
            type = .jpeg
            props = [.compressionFactor: 0.92]
        case .tiff:
            type = .tiff
            props = [:]
        }

        guard let data = rep.representation(using: type, properties: props) else {
            throw ExportError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let cg = cgImagePreservingAlpha(image) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func cgImagePreservingAlpha(_ image: NSImage) -> CGImage? {
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cg
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.cgImage
    }

    static func nsImage(from cgImage: CGImage, scale: CGFloat = 2.0) -> NSImage {
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        let image = NSImage(cgImage: cgImage, size: size)
        return image
    }

    enum ExportError: Error {
        case encodingFailed
    }
}

enum SoundPlayer {
    static func playShutter() {
        guard AppSettings.shared.playSound else { return }
        NSSound(named: "Tink")?.play()
    }
}
