import AppKit
import Combine

struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let fileName: String
    var fileURLPath: String?

    var thumbnailURL: URL {
        HistoryStore.thumbnailsDirectory.appendingPathComponent("\(id.uuidString).png")
    }
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []

    private let ioQueue = DispatchQueue(label: "app.flare.history.io", qos: .userInitiated)
    private let thumbCache = NSCache<NSString, NSImage>()
    /// 原图内存缓存：后台落盘完成前也能打开清晰图
    private let imageCache = NSCache<NSString, NSImage>()

    nonisolated static var rootDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Flare", isDirectory: true)
    }

    nonisolated static var thumbnailsDirectory: URL {
        rootDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// 未「另存为」时，原图落在此目录（历史打开/复制/OCR 用全分辨率）
    nonisolated static var capturesDirectory: URL {
        rootDirectory.appendingPathComponent("Captures", isDirectory: true)
    }

    nonisolated static var indexURL: URL {
        rootDirectory.appendingPathComponent("history.json")
    }

    private init() {
        thumbCache.countLimit = 80
        imageCache.countLimit = 24
        imageCache.totalCostLimit = 120 * 1024 * 1024
    }

    func load() {
        try? FileManager.default.createDirectory(at: Self.thumbnailsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.capturesDirectory, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded.sorted { $0.createdAt > $1.createdAt }
        pruneExpired(persistAfter: true)
    }

    /// 按设置的保留时长清理过期记录
    func pruneExpired(persistAfter: Bool = true) {
        let limit = AppSettings.shared.historyRetention.timeInterval
        let cutoff = Date().addingTimeInterval(-limit)
        let expired = items.filter { $0.createdAt < cutoff }
        guard !expired.isEmpty else { return }
        let ids = Set(expired.map(\.id))
        items.removeAll { ids.contains($0.id) }
        for item in expired {
            thumbCache.removeObject(forKey: item.id.uuidString as NSString)
            imageCache.removeObject(forKey: item.id.uuidString as NSString)
        }
        if persistAfter { persist() }
        ioQueue.async { [weak self] in
            for item in expired {
                self?.removeFiles(for: item)
            }
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }

    /// 立刻更新列表；无 fileURL 时后台写入 Captures 原图 + 缩略图
    func add(image: NSImage, fileURL: URL? = nil) {
        let id = UUID()
        let managedURL: URL? = fileURL == nil
            ? Self.capturesDirectory.appendingPathComponent("\(id.uuidString).png")
            : nil
        let storedURL = fileURL ?? managedURL
        let item = HistoryItem(
            id: id,
            createdAt: Date(),
            fileName: fileURL?.lastPathComponent ?? "\(FlareBrand.name) \(Self.stamp()).png",
            fileURLPath: storedURL?.path
        )
        // 先塞内存，避免落盘前打开历史只有糊图
        imageCache.setObject(image, forKey: id.uuidString as NSString, cost: Self.roughCost(image))

        items.insert(item, at: 0)
        // 先按时间清理，再按数量封顶
        let cutoff = Date().addingTimeInterval(-AppSettings.shared.historyRetention.timeInterval)
        var removed = items.filter { $0.createdAt < cutoff && $0.id != item.id }
        items.removeAll { removed.contains($0) }
        if items.count > 100 {
            removed.append(contentsOf: items.suffix(from: 100))
            items = Array(items.prefix(100))
        }
        persist()

        let thumbURL = item.thumbnailURL
        let writeManaged = managedURL
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: Self.thumbnailsDirectory, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: Self.capturesDirectory, withIntermediateDirectories: true)

            if let writeManaged {
                Self.writePNG(image, to: writeManaged)
            }

            if let thumb = Self.makeThumbnail(image, maxPixel: 360) {
                if let tiff = thumb.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let data = rep.representation(using: .png, properties: [.compressionFactor: 0.85]) {
                    try? data.write(to: thumbURL, options: .atomic)
                }
                self.thumbCache.setObject(thumb, forKey: item.id.uuidString as NSString)
            }
            for old in removed {
                self.removeFiles(for: old)
                self.thumbCache.removeObject(forKey: old.id.uuidString as NSString)
                self.imageCache.removeObject(forKey: old.id.uuidString as NSString)
            }
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        thumbCache.removeObject(forKey: item.id.uuidString as NSString)
        imageCache.removeObject(forKey: item.id.uuidString as NSString)
        persist()
        ioQueue.async { [weak self] in
            self?.removeFiles(for: item)
        }
    }

    func clear() {
        let snapshot = items
        items.removeAll()
        thumbCache.removeAllObjects()
        imageCache.removeAllObjects()
        persist()
        ioQueue.async { [weak self] in
            for item in snapshot {
                self?.removeFiles(for: item)
            }
        }
    }

    func image(for item: HistoryItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = imageCache.object(forKey: key) { return cached }
        if let path = item.fileURLPath, let img = NSImage(contentsOfFile: path) {
            imageCache.setObject(img, forKey: key, cost: Self.roughCost(img))
            return img
        }
        // 兼容旧历史：仅有缩略图
        return thumbnail(for: item) ?? NSImage(contentsOf: item.thumbnailURL)
    }

    func thumbnail(for item: HistoryItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let img = NSImage(contentsOf: item.thumbnailURL) else { return nil }
        thumbCache.setObject(img, forKey: key)
        return img
    }

    func thumbnailAsync(for item: HistoryItem) async -> NSImage? {
        if let cached = thumbnail(for: item) { return cached }
        return await withCheckedContinuation { cont in
            ioQueue.async {
                let img = NSImage(contentsOf: item.thumbnailURL)
                if let img {
                    self.thumbCache.setObject(img, forKey: item.id.uuidString as NSString)
                }
                cont.resume(returning: img)
            }
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: Self.rootDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: Self.indexURL, options: .atomic)
        }
    }

    /// 只删应用管理的 Captures 原图；用户「保存到文件」的路径不动
    private func removeFiles(for item: HistoryItem) {
        try? FileManager.default.removeItem(at: item.thumbnailURL)
        guard let path = item.fileURLPath else { return }
        let url = URL(fileURLWithPath: path)
        let captures = Self.capturesDirectory.standardizedFileURL.path
        if url.standardizedFileURL.path.hasPrefix(captures + "/") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func writePNG(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func roughCost(_ image: NSImage) -> Int {
        let px = max(image.size.width, 1) * max(image.size.height, 1) * 4
        return Int(min(px, 40_000_000))
    }

    nonisolated private static func makeThumbnail(_ image: NSImage, maxPixel: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let longest = max(size.width, size.height)
        let scale = min(1, maxPixel / longest)
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let thumb = NSImage(size: target)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .medium
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        return thumb
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
