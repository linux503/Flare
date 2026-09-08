import AppKit
import CryptoKit
import PDFKit
import Security
import WebKit

/// 网页业务留档。只做本机核对，不构成司法鉴定或法定电子证据。
enum EvidenceSnapshot {
    static let disclaimer = "本快照仅用于报价、聊天、订单或链上页面的业务留档与核对，不具备司法鉴定效力，也不能单独作为法律意义上的电子证据。"

    struct Result {
        let folder: URL
        let pdf: URL
    }

    struct CertInfo {
        var host: String
        var subject: String
        var issuer: String
        var notBefore: String
        var notAfter: String
        var fingerprint: String
    }

    struct ChainInfo {
        var network: String
        var tx: String
        var status: String
        var block: String
    }

    @MainActor
    static func capture(urlString: String, note: String, progress: @escaping (String) -> Void) async throws -> Result {
        let pageURL = try normalize(urlString)
        var timeline: [(Date, String)] = [(Date(), "开始记录网址")]
        progress("正在打开网页…")

        let loader = PageLoader()
        let loaded = try await loader.load(pageURL) { progress($0) }
        timeline.append((Date(), "页面加载完成"))

        progress("正在截取完整页面…")
        let image = try await loader.fullPageImage()
        timeline.append((Date(), "完成页面长截图"))

        progress("正在计算哈希…")
        let htmlData = Data(loaded.html.utf8)
        let htmlHash = sha256(htmlData)
        guard let png = ImageExporter.pngData(from: image) else {
            throw Failure.encoding
        }
        let imageHash = sha256(png)
        timeline.append((Date(), "已计算 HTML 与图片哈希"))

        progress("正在读取证书…")
        let cert = await CertificateReader.read(host: pageURL.host ?? pageURL.absoluteString, url: pageURL)
        timeline.append((Date(), cert == nil ? "未能读取证书" : "已记录域名与证书"))

        progress("正在核对链上状态…")
        let chain = await ChainLookup.lookup(url: loaded.finalURL)
        if chain != nil {
            timeline.append((Date(), "已查询区块高度或交易状态"))
        }

        let capturedAt = Date()
        let zone = TimeZone.current
        let integrity = integrityHash(
            url: loaded.finalURL.absoluteString,
            at: capturedAt,
            html: htmlHash,
            image: imageHash
        )
        timeline.append((Date(), "已生成防篡改校验"))

        let folder = try makeFolder(at: capturedAt)
        try htmlData.write(to: folder.appendingPathComponent("page.html"))
        try png.write(to: folder.appendingPathComponent("page.png"))

        let record = Packet(
            url: loaded.finalURL.absoluteString,
            title: loaded.title,
            note: note,
            capturedAt: capturedAt,
            timeZone: zone.identifier,
            htmlSha256: htmlHash,
            imageSha256: imageHash,
            domain: pageURL.host ?? "",
            cert: cert,
            chain: chain,
            timeline: timeline,
            integrity: integrity
        )
        let manifest = folder.appendingPathComponent("manifest.json")
        try record.json.write(to: manifest)
        let pdfURL = folder.appendingPathComponent("evidence.pdf")
        try PDFWriter.write(record: record, image: image, to: pdfURL)
        timeline.append((Date(), "已导出带时间线的 PDF"))
        return Result(folder: folder, pdf: pdfURL)
    }

    private static func normalize(_ raw: String) throws -> URL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Failure.emptyURL }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw Failure.badURL
        }
        return url
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func integrityHash(url: String, at: Date, html: String, image: String) -> String {
        let stamp = ISO8601DateFormatter().string(from: at)
        let line = "\(url)\n\(stamp)\n\(html)\n\(image)"
        return sha256(Data(line.utf8))
    }

    private static func makeFolder(at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let root = AppSettings.shared.saveDirectory.appendingPathComponent("Evidence", isDirectory: true)
        let folder = root.appendingPathComponent("Flare Evidence \(formatter.string(from: date))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    enum Failure: LocalizedError {
        case emptyURL
        case badURL
        case load
        case encoding

        var errorDescription: String? {
            switch self {
            case .emptyURL: return "请先填写网页地址"
            case .badURL: return "网址无法打开"
            case .load: return "网页加载失败"
            case .encoding: return "无法生成快照图片"
            }
        }
    }
}

private struct Packet {
    let url: String
    let title: String
    let note: String
    let capturedAt: Date
    let timeZone: String
    let htmlSha256: String
    let imageSha256: String
    let domain: String
    let cert: EvidenceSnapshot.CertInfo?
    let chain: EvidenceSnapshot.ChainInfo?
    let timeline: [(Date, String)]
    let integrity: String

    var json: Data {
        let formatter = ISO8601DateFormatter()
        var object: [String: Any] = [
            "disclaimer": EvidenceSnapshot.disclaimer,
            "url": url,
            "title": title,
            "note": note,
            "capturedAt": formatter.string(from: capturedAt),
            "timeZone": timeZone,
            "domain": domain,
            "htmlSha256": htmlSha256,
            "imageSha256": imageSha256,
            "integrity": integrity,
            "timeline": timeline.map { ["at": formatter.string(from: $0.0), "event": $0.1] }
        ]
        if let cert {
            object["certificate"] = [
                "host": cert.host,
                "subject": cert.subject,
                "issuer": cert.issuer,
                "notBefore": cert.notBefore,
                "notAfter": cert.notAfter,
                "sha256": cert.fingerprint
            ]
        }
        if let chain {
            object["chain"] = [
                "network": chain.network,
                "tx": chain.tx,
                "status": chain.status,
                "block": chain.block
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var finish: ((Result<LoadedPage, Error>) -> Void)?
    private var loadedURL = URL(string: "about:blank")!
    private var pageTitle = ""

    func load(_ url: URL, progress: @escaping (String) -> Void) async throws -> LoadedPage {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        view.navigationDelegate = self
        webView = view
        progress("正在加载 \(url.host ?? url.absoluteString)")
        return try await withCheckedThrowingContinuation { cont in
            finish = { cont.resume(with: $0) }
            view.load(URLRequest(url: url))
        }
    }

    func fullPageImage() async throws -> NSImage {
        guard let webView else { throw EvidenceSnapshot.Failure.load }
        let height = await contentHeight(webView)
        webView.frame = NSRect(x: 0, y: 0, width: 1280, height: height)
        try await Task.sleep(nanoseconds: 350_000_000)
        let config = WKSnapshotConfiguration()
        config.rect = webView.bounds
        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            webView.takeSnapshot(with: config) { image, error in
                if let image {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: error ?? EvidenceSnapshot.Failure.encoding)
                }
            }
        }
        return image
    }

    private func contentHeight(_ webView: WKWebView) async -> CGFloat {
        let raw: Any? = await withCheckedContinuation { cont in
            webView.evaluateJavaScript("Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement.scrollHeight)") { value, _ in
                cont.resume(returning: value)
            }
        }
        let value = (raw as? NSNumber)?.doubleValue ?? 1200
        return CGFloat(min(max(value, 720), 14000))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadedURL = webView.url ?? loadedURL
        pageTitle = webView.title ?? ""
        webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''") { [weak self] value, _ in
            guard let self else { return }
            let html = value as? String ?? ""
            let page = LoadedPage(finalURL: self.loadedURL, title: self.pageTitle, html: html)
            self.finish?(.success(page))
            self.finish = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish?(.failure(error))
        finish = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish?(.failure(error))
        finish = nil
    }
}

private struct LoadedPage {
    let finalURL: URL
    let title: String
    let html: String
}

private enum CertificateReader {
    static func read(host: String, url: URL) async -> EvidenceSnapshot.CertInfo? {
        await withCheckedContinuation { cont in
            let delegate = TrustGrabber { trust in
                cont.resume(returning: info(host: host, trust: trust))
            }
            let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: url) { _, _, _ in
                if !delegate.didResume {
                    delegate.finish(nil)
                }
                session.finishTasksAndInvalidate()
            }
            delegate.task = task
            task.resume()
        }
    }

    private static func info(host: String, trust: SecTrust?) -> EvidenceSnapshot.CertInfo? {
        guard let trust, let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let cert = chain.first else {
            return nil
        }
        let subject = SecCertificateCopySubjectSummary(cert) as String? ?? host
        var issuer = ""
        if let values = SecCertificateCopyValues(cert, [kSecOIDX509V1IssuerName] as CFArray, nil) as? [CFString: Any],
           let issuerValue = values[kSecOIDX509V1IssuerName] as? [CFString: Any],
           let value = issuerValue[kSecPropertyKeyValue] {
            issuer = String(describing: value)
        }
        let data = SecCertificateCopyData(cert) as Data
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var notBefore = ""
        var notAfter = ""
        if let values = SecCertificateCopyValues(cert, nil, nil) as? [CFString: Any] {
            notBefore = dateString(values, key: kSecOIDX509V1ValidityNotBefore, formatter: formatter)
            notAfter = dateString(values, key: kSecOIDX509V1ValidityNotAfter, formatter: formatter)
        }
        return EvidenceSnapshot.CertInfo(
            host: host,
            subject: subject,
            issuer: issuer.isEmpty ? "未知" : issuer,
            notBefore: notBefore,
            notAfter: notAfter,
            fingerprint: fingerprint
        )
    }

    private static func dateString(_ values: [CFString: Any], key: CFString, formatter: DateFormatter) -> String {
        guard let box = values[key] as? [CFString: Any], let date = box[kSecPropertyKeyValue] as? Date else { return "" }
        return formatter.string(from: date)
    }
}

private final class TrustGrabber: NSObject, URLSessionDelegate {
    var task: URLSessionTask?
    var didResume = false
    private let done: (SecTrust?) -> Void

    init(_ done: @escaping (SecTrust?) -> Void) {
        self.done = done
    }

    func finish(_ trust: SecTrust?) {
        guard !didResume else { return }
        didResume = true
        done(trust)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let trust = challenge.protectionSpace.serverTrust
        finish(trust)
        if let trust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
        task?.cancel()
    }
}

private enum ChainLookup {
    static func lookup(url: URL) async -> EvidenceSnapshot.ChainInfo? {
        let host = (url.host ?? "").lowercased()
        let text = url.absoluteString
        if let tx = text.range(of: #"0x[a-fA-F0-9]{64}"#, options: .regularExpression).map({ String(text[$0]) }) {
            let network = ethNetwork(host)
            if let network, let info = await ethReceipt(tx: tx, rpc: network.rpc, name: network.name) {
                return info
            }
        }
        if host.contains("mempool.space") || host.contains("blockstream"),
           let tx = text.range(of: #"/tx/([a-fA-F0-9]{64})"#, options: .regularExpression).map({ String(text[$0]) }) {
            let id = tx.components(separatedBy: "/").last ?? tx
            return await btc(tx: id)
        }
        return nil
    }

    private static func ethNetwork(_ host: String) -> (name: String, rpc: String)? {
        if host.contains("bscscan") { return ("BNB Chain", "https://bsc.publicnode.com") }
        if host.contains("polygonscan") { return ("Polygon", "https://polygon-bor.publicnode.com") }
        if host.contains("arbiscan") { return ("Arbitrum", "https://arbitrum-one.publicnode.com") }
        if host.contains("basescan") { return ("Base", "https://base.publicnode.com") }
        if host.contains("optimistic.etherscan") || host.contains("optimism") { return ("Optimism", "https://optimism.publicnode.com") }
        if host.contains("etherscan") || host.contains("eth.") { return ("Ethereum", "https://ethereum.publicnode.com") }
        return nil
    }

    private static func ethReceipt(tx: String, rpc: String, name: String) async -> EvidenceSnapshot.ChainInfo? {
        guard let endpoint = URL(string: rpc) else { return nil }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_getTransactionReceipt", "params": [tx]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else { return nil }
        let statusHex = result["status"] as? String ?? ""
        let blockHex = result["blockNumber"] as? String ?? ""
        let status = statusHex == "0x1" ? "成功" : (statusHex == "0x0" ? "失败" : "未知")
        let block = hexToDecimal(blockHex)
        return EvidenceSnapshot.ChainInfo(network: name, tx: tx, status: status, block: block)
    }

    private static func btc(tx: String) async -> EvidenceSnapshot.ChainInfo? {
        guard let url = URL(string: "https://mempool.space/api/tx/\(tx)") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let status = json["status"] as? [String: Any]
        let confirmed = status?["confirmed"] as? Bool ?? false
        let height = status?["block_height"] as? Int
        return EvidenceSnapshot.ChainInfo(
            network: "Bitcoin",
            tx: tx,
            status: confirmed ? "已确认" : "未确认",
            block: height.map(String.init) ?? "未上块"
        )
    }

    private static func hexToDecimal(_ hex: String) -> String {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let value = UInt64(cleaned, radix: 16) else { return hex }
        return String(value)
    }
}

private enum PDFWriter {
    static func write(record: Packet, image: NSImage, to url: URL) throws {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        var media = page
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw EvidenceSnapshot.Failure.encoding
        }
        let font = NSFont.systemFont(ofSize: 11)
        let titleFont = NSFont.systemFont(ofSize: 18, weight: .semibold)
        let small = NSFont.systemFont(ofSize: 9)
        var cursor = drawCover(ctx: ctx, page: page, record: record, font: font, titleFont: titleFont, small: small)
        _ = cursor
        drawImage(ctx: ctx, page: page, image: image, font: small)
        ctx.closePDF()
    }

    private static func drawCover(ctx: CGContext, page: CGRect, record: Packet, font: NSFont, titleFont: NSFont, small: NSFont) -> CGFloat {
        ctx.beginPDFPage(nil)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        NSColor.white.setFill()
        page.fill()
        var y = page.height - 48
        ("Flare 网页证据快照" as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: [.font: titleFont, .foregroundColor: NSColor.black])
        y -= 28
        let box = NSRect(x: 40, y: y - 52, width: page.width - 80, height: 52)
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        drawWrapped(EvidenceSnapshot.disclaimer, in: box.insetBy(dx: 10, dy: 8), font: small, color: .darkGray)
        y = box.minY - 22
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        stamp.timeZone = TimeZone(identifier: record.timeZone) ?? .current
        let lines = [
            "网址：\(record.url)",
            "标题：\(record.title.isEmpty ? "—" : record.title)",
            "时间：\(stamp.string(from: record.capturedAt))  \(record.timeZone)",
            "域名：\(record.domain)",
            "备注：\(record.note.isEmpty ? "—" : record.note)",
            "HTML SHA-256：\(record.htmlSha256)",
            "图片 SHA-256：\(record.imageSha256)",
            "校验：\(record.integrity)"
        ]
        for line in lines {
            y = drawWrapped(line, in: NSRect(x: 40, y: y - 28, width: page.width - 80, height: 28), font: font, color: .black) - 4
        }
        if let cert = record.cert {
            y -= 8
            y = drawWrapped("证书：\(cert.subject) · \(cert.issuer)", in: NSRect(x: 40, y: y - 24, width: page.width - 80, height: 24), font: font, color: .black) - 2
            y = drawWrapped("有效期：\(cert.notBefore) — \(cert.notAfter) · \(cert.fingerprint)", in: NSRect(x: 40, y: y - 24, width: page.width - 80, height: 24), font: small, color: .darkGray) - 4
        }
        if let chain = record.chain {
            y = drawWrapped("链上：\(chain.network) · \(chain.status) · 区块 \(chain.block)", in: NSRect(x: 40, y: y - 24, width: page.width - 80, height: 24), font: font, color: .black) - 2
            y = drawWrapped("交易：\(chain.tx)", in: NSRect(x: 40, y: y - 24, width: page.width - 80, height: 24), font: small, color: .darkGray) - 4
        }
        y -= 10
        ("时间线" as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        y -= 20
        for item in record.timeline {
            let text = "\(stamp.string(from: item.0))  \(item.1)"
            (text as NSString).draw(at: NSPoint(x: 40, y: y), withAttributes: [.font: small, .foregroundColor: NSColor.darkGray])
            y -= 16
        }
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        return y
    }

    @discardableResult
    private static func drawWrapped(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        return rect.minY
    }

    private static func drawImage(ctx: CGContext, page: CGRect, image: NSImage, font: NSFont) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let margin: CGFloat = 36
        let maxW = page.width - margin * 2
        let scale = maxW / max(CGFloat(cg.width), 1)
        let drawH = CGFloat(cg.height) * scale
        var remain = drawH
        var sourceY: CGFloat = 0
        while remain > 8 {
            ctx.beginPDFPage(nil)
            let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            ("页面长截图" as NSString).draw(at: NSPoint(x: margin, y: 28), withAttributes: [.font: font, .foregroundColor: NSColor.darkGray])
            let avail = page.height - 56
            let slice = min(remain, avail)
            let srcH = slice / scale
            let dest = NSRect(x: margin, y: 44, width: maxW, height: slice)
            if let piece = cg.cropping(to: CGRect(x: 0, y: CGFloat(cg.height) - sourceY - srcH, width: CGFloat(cg.width), height: srcH)) {
                ctx.draw(piece, in: dest)
            }
            sourceY += srcH
            remain -= slice
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
    }
}
