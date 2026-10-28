import AppKit
import SwiftUI

@MainActor
final class MailboxStore: ObservableObject {
    static let shared = MailboxStore()

    @Published var addr = ""
    @Published var recover = ""
    @Published var domain = OtpixClient.domains[0]
    @Published var prefix = ""
    @Published var openInput = ""
    @Published var messages: [OtpixClient.Message] = []
    @Published var selected: OtpixClient.Message?
    @Published var mail: OtpixClient.Mail?
    @Published var status = "无需注册，只收不发 · 来信 24 小时后删除"
    @Published var busy = false
    @Published var openingId: String?
    @Published var errorText = ""

    private let defaults = UserDefaults.standard
    private let addrKey = "otpixAddr"
    private let recoverKey = "otpixRecover"
    private let domainKey = "otpixDomain"
    private var knownIds: Set<String> = []
    private var didPrimeIds = false

    private init() {
        addr = defaults.string(forKey: addrKey) ?? ""
        recover = defaults.string(forKey: recoverKey) ?? ""
        domain = defaults.string(forKey: domainKey) ?? OtpixClient.domains[0]
        if !OtpixClient.domains.contains(domain) {
            domain = OtpixClient.domains[0]
        }
        if addr.isEmpty, !recover.isEmpty {
            openInput = recover
        }
    }

    var isInside: Bool { !addr.isEmpty }

    var localPart: String {
        addr.split(separator: "@").first.map(String.init) ?? addr
    }

    var domainPart: String {
        guard let at = addr.split(separator: "@").dropFirst().first else { return "" }
        return String(at)
    }

    var codes: [String] {
        let fromMail = mail?.codes ?? []
        if !fromMail.isEmpty { return fromMail }
        return messages.flatMap { $0.codes ?? [] }
    }

    var latestCode: String? { codes.first }

    func persist() {
        defaults.set(addr, forKey: addrKey)
        defaults.set(recover, forKey: recoverKey)
        defaults.set(domain, forKey: domainKey)
    }

    func create() async {
        let local = OtpixClient.validLocal(prefix) ?? OtpixClient.randomLocal()
        await apply(addr: "\(local)@\(domain)", note: "地址已就绪，复制后贴到注册页")
        prefix = ""
    }

    func recreate() async {
        prefix = ""
        await create()
    }

    func openKnown() async {
        let raw = openInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rk = OtpixClient.validRecover(raw) {
            busy = true
            errorText = ""
            defer { busy = false }
            do {
                let box = try await OtpixClient.restore(key: rk)
                guard box.ok, let next = box.addr else {
                    errorText = box.error ?? "恢复码无效"
                    return
                }
                recover = box.recover ?? rk
                await apply(addr: next, note: "已打开这个邮箱")
                openInput = ""
            } catch {
                errorText = error.localizedDescription
            }
            return
        }
        if let full = OtpixClient.validAddr(raw) {
            await apply(addr: full, note: "已打开这个邮箱")
            openInput = ""
            return
        }
        if let local = OtpixClient.validLocal(raw) {
            await apply(addr: "\(local)@\(domain)", note: "已打开这个邮箱")
            openInput = ""
            return
        }
        errorText = "填写完整地址、前缀，或恢复码 RK-xxxx"
    }

    func refresh() async {
        guard !addr.isEmpty else { return }
        do {
            let inbox = try await OtpixClient.inbox(addr: addr)
            if inbox.ok {
                let next = inbox.messages ?? []
                let nextIds = Set(next.map(\.id))
                let newcomers = next.filter { !knownIds.contains($0.id) }
                messages = next
                if next.isEmpty {
                    status = "等待来信 · 每 4 秒检查"
                } else {
                    status = "已收到 \(next.count) 封 · 每 4 秒检查"
                }
                errorText = ""

                if !didPrimeIds {
                    knownIds = nextIds
                    didPrimeIds = true
                    if selected == nil, let first = next.first {
                        await openMail(first)
                    }
                } else if let newest = newcomers.first {
                    knownIds.formUnion(nextIds)
                    await openMail(newest)
                    if let code = newest.codes?.first {
                        ToastController.shared.show("收到验证码 \(code)")
                    } else {
                        ToastController.shared.show("收到新邮件")
                    }
                } else {
                    knownIds.formUnion(nextIds)
                    if selected == nil, let first = next.first {
                        await openMail(first)
                    }
                }
            } else {
                errorText = inbox.error ?? "收件箱暂时读不到"
            }
        } catch {
            errorText = "网络中断，正在重试"
        }
    }

    func openMail(_ item: OtpixClient.Message) async {
        selected = item
        openingId = item.id
        defer { if openingId == item.id { openingId = nil } }
        do {
            let next = try await OtpixClient.mail(addr: addr, id: item.id)
            guard selected?.id == item.id else { return }
            mail = next
            errorText = ""
        } catch {
            guard selected?.id == item.id else { return }
            mail = nil
            errorText = error.localizedDescription
        }
    }

    func clear() async {
        guard !addr.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            try await OtpixClient.clearInbox(addr: addr)
            messages = []
            selected = nil
            mail = nil
            knownIds = []
            status = "收件箱已清空"
            ToastController.shared.show("收件箱已清空")
        } catch {
            errorText = "清空失败"
        }
    }

    func copyAddr() {
        guard !addr.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addr, forType: .string)
        ToastController.shared.show("已复制 \(addr)")
    }

    func copyRecover() {
        guard !recover.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recover, forType: .string)
        ToastController.shared.show("已复制恢复码")
    }

    func copyShare() {
        guard let share = OtpixClient.shareURL(for: addr) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(share.absoluteString, forType: .string)
        ToastController.shared.show("已复制分享链接")
    }

    func copyCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        ToastController.shared.show("已复制验证码 \(code)")
    }

    func copyMailText() {
        guard let text = mail?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastController.shared.show("已复制正文")
    }

    func openMailPage() {
        let id = mail?.id ?? selected?.id
        guard let id else { return }
        NSWorkspace.shared.open(OtpixClient.mailPageURL(addr: addr, id: id))
    }

    func remainLabel(for item: OtpixClient.Message) -> String {
        if let exp = item.expires_at {
            let left = exp - Date().timeIntervalSince1970
            if left <= 0 { return "即将删除" }
            let hours = Int(left) / 3600
            let minutes = (Int(left) % 3600) / 60
            if hours >= 1 { return "还剩 \(hours) 小时" }
            return "还剩 \(max(1, minutes)) 分钟"
        }
        return item.ago ?? ""
    }

    func leaveBox() {
        addr = ""
        selected = nil
        mail = nil
        messages = []
        prefix = ""
        openInput = recover
        knownIds = []
        didPrimeIds = false
        status = "无需注册，只收不发"
        errorText = ""
        persist()
    }

    private func apply(addr next: String, note: String) async {
        busy = true
        errorText = ""
        defer { busy = false }
        do {
            let box = try await OtpixClient.create(addr: next)
            guard box.ok, let created = box.addr else {
                errorText = box.error ?? "地址无效"
                return
            }
            addr = created
            if let rk = box.recover, !rk.isEmpty { recover = rk }
            persist()
            selected = nil
            mail = nil
            messages = []
            knownIds = []
            didPrimeIds = false
            status = note
            ToastController.shared.show(note)
            await refresh()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct MailboxPane: View {
    @ObservedObject private var store = MailboxStore.shared
    @Environment(\.flareTheme) private var theme
    @State private var livePulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 14)

            if !store.errorText.isEmpty {
                errorBanner
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
            }

            if store.isInside {
                addressBar
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                if !store.codes.isEmpty {
                    otpStrip
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)
                }
                HStack(alignment: .top, spacing: 12) {
                    inboxColumn
                    readerColumn
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    welcomeStage
                        .padding(.horizontal, 28)
                        .padding(.bottom, 28)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                livePulse = true
            }
        }
        .task {
            if store.isInside {
                await store.refresh()
            } else if store.recover.isEmpty, store.prefix.isEmpty, store.openInput.isEmpty {
                await store.create()
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if store.isInside {
                    await store.refresh()
                }
            }
        }
    }

    private var header: some View {
        FlarePageHeader(
            title: "临时邮箱",
            subtitle: store.isInside
                ? store.status
                : "无需注册，只收不发 · 来信 24 小时后自动删除"
        ) {
            if store.isInside {
                HStack(spacing: 8) {
                    FlarePrimaryButton(title: "复制地址", glyph: .copy, action: store.copyAddr)
                    FlareSecondaryButton(title: "刷新", glyph: .refresh) {
                        Task { await store.refresh() }
                    }
                    moreMenu
                }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("复制恢复码", action: store.copyRecover)
                .disabled(store.recover.isEmpty)
            Button("复制分享链接", action: store.copyShare)
            Divider()
            Button("换一个地址") {
                Task { await store.recreate() }
            }
            .disabled(store.busy)
            Button("清空收件箱") {
                Task { await store.clear() }
            }
            .disabled(store.addr.isEmpty || store.busy)
            Divider()
            Button("退出此邮箱") {
                store.leaveBox()
            }
        } label: {
            HStack(spacing: 4) {
                SnapIcon(.more, size: .caption, opacity: 1, tint: theme.accent)
                Text("更多")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .foregroundStyle(theme.accent)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var errorBanner: some View {
        HStack(spacing: 8) {
            SnapIcon(.warning, size: .caption, opacity: 1, tint: theme.warning)
            Text(store.errorText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.warning)
            Spacer(minLength: 0)
            Button {
                store.errorText = ""
            } label: {
                SnapIcon(.close, size: .caption, opacity: 0.8, tint: theme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var addressBar: some View {
        HStack(spacing: 12) {
            SnapIconWell(.mail, side: 36, iconSize: .title, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 3) {
                Button(action: store.copyAddr) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(store.localPart)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        if !store.domainPart.isEmpty {
                            Text("@\(store.domainPart)")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .buttonStyle(.plain)
                .help("轻点复制完整地址")

                HStack(spacing: 8) {
                    liveDot
                    Text(store.messages.isEmpty ? "等待来信" : "\(store.messages.count) 封来信")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                    if !store.recover.isEmpty {
                        Text("·")
                            .foregroundStyle(theme.textMuted)
                        Button(action: store.copyRecover) {
                            Text(store.recover)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .help("轻点复制恢复码")
                    }
                }
            }
            Spacer(minLength: 8)
            if store.busy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .flareGlass(cornerRadius: 12)
    }

    private var liveDot: some View {
        Circle()
            .fill(store.messages.isEmpty ? theme.success : theme.accent)
            .frame(width: 7, height: 7)
            .opacity(livePulse ? 1 : 0.35)
    }

    private var otpStrip: some View {
        HStack(spacing: 10) {
            ForEach(store.codes, id: \.self) { code in
                Button {
                    store.copyCode(code)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("验证码")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.accent)
                            Text(code)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .tracking(2)
                                .foregroundStyle(theme.textPrimary)
                        }
                        SnapIcon(.copy, size: .body, opacity: 1, tint: theme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(FlareCardButtonStyle())
                .help("轻点复制验证码")
            }
        }
    }

    private var inboxColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("收件箱")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                Spacer()
                Text("\(store.messages.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if store.messages.isEmpty {
                VStack(spacing: 10) {
                    SnapIconWell(.mail, side: 36, iconSize: .title, cornerRadius: 9)
                    Text("还没有来信")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("复制地址，贴到注册页。验证码会自动出现。")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    FlareSecondaryButton(title: "复制地址", glyph: .copy, action: store.copyAddr)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle()
                                    .fill(theme.stroke)
                                    .frame(height: 0.5)
                                    .padding(.leading, 54)
                            }
                            mailRow(item)
                        }
                    }
                }
            }
        }
        .frame(width: 268)
        .frame(maxHeight: .infinity, alignment: .top)
        .flareGlass(cornerRadius: 12)
    }

    private var readerColumn: some View {
        Group {
            if let mail = store.mail, mail.ok {
                mailReader(mail)
            } else if store.openingId != nil {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在打开邮件…")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .flareGlass(cornerRadius: 12)
            } else {
                VStack(spacing: 8) {
                    SnapIconWell(.ocr, side: 36, iconSize: .title, cornerRadius: 9)
                    Text("等待验证码")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("来信后会自动打开，数字验证码会出现在上方。")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .flareGlass(cornerRadius: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func mailRow(_ item: OtpixClient.Message) -> some View {
        let selected = store.selected?.id == item.id
        return Button {
            Task { await store.openMail(item) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                senderBadge(item.sender ?? "", selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(senderName(item.sender))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.ago ?? "")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                    Text(item.subject?.isEmpty == false ? (item.subject ?? "") : "无主题")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                    if let codes = item.codes, !codes.isEmpty {
                        Text(codes.joined(separator: "  "))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? theme.accentSoft : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func senderName(_ sender: String?) -> String {
        let raw = sender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return "未知发件人" }
        if let start = raw.firstIndex(of: "<") {
            let name = raw[..<start].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return raw
    }

    private func senderBadge(_ sender: String, selected: Bool) -> some View {
        let source = senderName(sender)
        let letter = source.first.map { String($0).uppercased() } ?? "M"
        return ZStack {
            Circle()
                .fill(selected ? theme.accent : theme.fillStrong)
            Text(letter)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? theme.inverseText : theme.textSecondary)
        }
        .frame(width: 32, height: 32)
    }

    private func mailReader(_ mail: OtpixClient.Mail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(mail.subject ?? "无主题")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(senderName(mail.sender))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if let selected = store.selected {
                        Text(store.remainLabel(for: selected))
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                if let codes = mail.codes, !codes.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            Button {
                                store.copyCode(code)
                            } label: {
                                Text(code)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(theme.accentSoft, in: Capsule())
                                    .foregroundStyle(theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 8) {
                    if let text = mail.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        FlareSecondaryButton(title: "复制正文", glyph: .copy, action: store.copyMailText)
                    }
                    if mail.html?.isEmpty == false || mail.id != nil {
                        FlareSecondaryButton(title: "网页版", glyph: .link, action: store.openMailPage)
                    }
                }
                Divider().overlay(theme.stroke)
                if let text = mail.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(5)
                } else {
                    Text("这封信没有纯文本，可用网页版查看。")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .flareGlass(cornerRadius: 12)
    }

    private var welcomeStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("获取一个地址")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("复制后贴到注册页。验证码会自动出现在收件箱。")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }

                domainChips

                HStack(spacing: 10) {
                    field($store.prefix, placeholder: "前缀，可空")
                        .onSubmit {
                            Task { await store.create() }
                        }
                    Button {
                        Task { await store.create() }
                    } label: {
                        HStack(spacing: 6) {
                            if store.busy {
                                ProgressView().controlSize(.small)
                            } else {
                                SnapIcon(.plus, size: .caption, opacity: 1, tint: theme.inverseText)
                            }
                            Text("立即创建")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(theme.inverseText)
                    }
                    .buttonStyle(FlareChipButtonStyle())
                    .disabled(store.busy)
                }

                Text("只收不发  ·  来信 24 小时后删除  ·  用恢复码换设备")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flareGlass(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("打开已有邮箱")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(store.recover.isEmpty ? "填写完整地址或恢复码 RK-xxxx" : "已填入上一只邮箱的恢复码")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                }
                HStack(spacing: 10) {
                    field($store.openInput, placeholder: "地址 / 前缀 / RK-xxxx")
                        .onSubmit {
                            Task { await store.openKnown() }
                        }
                    FlareSecondaryButton(title: "打开", glyph: .success) {
                        Task { await store.openKnown() }
                    }
                    .disabled(store.busy)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flareGlass(cornerRadius: 12)
        }
    }

    private var domainChips: some View {
        HStack(spacing: 8) {
            ForEach(OtpixClient.domains, id: \.self) { item in
                let on = store.domain == item
                Button {
                    store.domain = item
                    store.persist()
                } label: {
                    Text("@\(item)")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(on ? theme.accent : theme.fill)
                        )
                        .foregroundStyle(on ? theme.inverseText : theme.textPrimary)
                }
                .buttonStyle(FlareChipButtonStyle())
            }
        }
    }

    private func field(_ text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
