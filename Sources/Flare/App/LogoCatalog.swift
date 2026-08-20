import AppKit

enum AppLogoKind: String, CaseIterable, Identifiable {
    case spark
    case iris
    case bolt
    case dusk
    case coral
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spark: return "翠绿闪光"
        case .iris: return "日落镜头"
        case .bolt: return "电光蓝"
        case .dusk: return "暮紫轨道"
        case .coral: return "珊瑚取景"
        case .custom: return "自选"
        }
    }

    var resourceName: String? {
        switch self {
        case .spark: return "LogoSpark"
        case .iris: return "LogoIris"
        case .bolt: return "LogoBolt"
        case .dusk: return "LogoDusk"
        case .coral: return "LogoCoral"
        case .custom: return nil
        }
    }

    static var presets: [AppLogoKind] { [.spark, .iris, .bolt, .dusk, .coral] }
}

enum LogoCatalog {
    private static var cacheKey: String?
    private static var cache: NSImage?

    static var customFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("CustomLogo.png")
    }

    static func invalidate() {
        cacheKey = nil
        cache = nil
    }

    static func currentImage() -> NSImage? {
        let kind = AppSettings.shared.logoKind
        let key: String
        if kind == .custom {
            let values = try? customFileURL.resourceValues(forKeys: [.contentModificationDateKey])
            key = "custom-\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        } else {
            key = kind.rawValue
        }
        if key == cacheKey, let cache { return cache }
        let image = load(kind)
        cacheKey = key
        cache = image
        return image
    }

    static func presetImage(_ kind: AppLogoKind) -> NSImage? {
        load(kind == .custom ? .spark : kind)
    }

    static func installCustom(from url: URL) -> Bool {
        guard let source = NSImage(contentsOf: url) else { return false }
        let side: CGFloat = 512
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)).fill()
        let src = source.size.width > 0 ? source.size : NSSize(width: side, height: side)
        let scale = min(side / src.width, side / src.height)
        let draw = NSRect(
            x: (side - src.width * scale) / 2,
            y: (side - src.height * scale) / 2,
            width: src.width * scale,
            height: src.height * scale
        )
        source.draw(in: draw, from: NSRect(origin: .zero, size: src), operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: customFileURL)
            AppSettings.shared.logoKind = .custom
            return true
        } catch {
            return false
        }
    }

    private static func load(_ kind: AppLogoKind) -> NSImage? {
        if kind == .custom, FileManager.default.fileExists(atPath: customFileURL.path) {
            return NSImage(contentsOf: customFileURL)
        }
        if let name = kind.resourceName {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                return img
            }
            if let img = NSImage(named: name) { return img }
        }
        if let url = Bundle.main.url(forResource: "FlareIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }
}
