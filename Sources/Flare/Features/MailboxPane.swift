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
    @Published var status = L("无需注册，只收不发 · 来信 24 小时后删除")
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
        await apply(addr: "\(local)@\(domain)", note: L("地址已就绪，复制后贴到注册页"))
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
                    errorText = box.error ?? L("恢复码无效")
                    return
                }
                recover = box.recover ?? rk
                await apply(addr: next, note: L("已打开这个邮箱"))
                openInput = ""
            } catch {
                errorText = error.localizedDescription
            }
            return
        }
        if let full = OtpixClient.validAddr(raw) {
            await apply(addr: full, note: L("已打开这个邮箱"))
            openInput = ""
            return
        }
        if let local = OtpixClient.validLocal(raw) {
            await apply(addr: "\(local)@\(domain)", note: L("已打开这个邮箱"))
            openInput = ""
            return
        }
        errorText = L("填写完整地址、前缀，或恢复码 RK-xxxx")
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
                    status = L("等待来信 · 每 4 秒检查")
                } else {
                    status = L("已收到 %@ 封 · 每 4 秒检查", next.count)
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
                        ToastController.shared.show(L("收到验证码 %@", code))
                    } else {
                        ToastController.shared.show(L("收到新邮件"))
                    }
                } else {
                    knownIds.formUnion(nextIds)
                    if selected == nil, let first = next.first {
                        await openMail(first)
                    }
                }
            } else {
                errorText = inbox.error ?? L("收件箱暂时读不到")
            }
        } catch {
            errorText = L("网络中断，正在重试")
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
            status = L("收件箱已清空")
            ToastController.shared.show(L("收件箱已清空"))
        } catch {
            errorText = L("清空失败")
        }
    }

    func copyAddr() {
        guard !addr.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(addr, forType: .string)
        ToastController.shared.show(L("已复制 %@", addr))
    }

    func copyRecover() {
        guard !recover.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recover, forType: .string)
        ToastController.shared.show(L("已复制恢复码"))
    }

    func copyShare() {
        guard let share = OtpixClient.shareURL(for: addr) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(share.absoluteString, forType: .string)
        ToastController.shared.show(L("已复制分享链接"))
    }

    func copyCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        ToastController.shared.show(L("已复制验证码 %@", code))
    }

    func copyMailText() {
        guard let text = mail?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastController.shared.show(L("已复制正文"))
    }

    func openMailPage() {
        let id = mail?.id ?? selected?.id
        guard let id else { return }
        NSWorkspace.shared.open(OtpixClient.mailPageURL(addr: addr, id: id))
    }

    func remainLabel(for item: OtpixClient.Message) -> String {
        if let exp = item.expires_at {
            let left = exp - Date().timeIntervalSince1970
            if left <= 0 { return L("即将删除") }
            let hours = Int(left) / 3600
            let minutes = (Int(left) % 3600) / 60
            if hours >= 1 { return L("还剩 %@ 小时", hours) }
            return L("还剩 %@ 分钟", max(1, minutes))
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
        status = L("无需注册，只收不发")
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
                errorText = box.error ?? L("地址无效")
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
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 12)

            if !store.errorText.isEmpty {
                errorBanner
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            if store.isInside {
                addressBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                if !store.codes.isEmpty {
                    otpStrip
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                }
                HStack(alignment: .top, spacing: 10) {
                    inboxColumn
                    readerColumn
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    welcomeStage
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
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
            title: L("临邮"),
            subtitle: store.isInside
                ? store.status
                : L("临时邮箱 · 无需注册，只收不发")
        ) {
            if store.isInside {
                HStack(spacing: 8) {
                    Button(action: store.copyAddr) {
                        HStack(spacing: 6) {
                            SnapIcon(.copy, size: .caption, opacity: 1, tint: theme.inverseText)
                            Text(L("复制地址"))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.inverseFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(theme.inverseText)
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        SnapIcon(.refresh, size: .body, opacity: 0.9, tint: theme.textPrimary)
                            .frame(width: 32, height: 28)
                            .background(theme.fillStrong, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(L("刷新收件箱"))
                    moreMenu
                }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button(L("复制恢复码"), action: store.copyRecover)
                .disabled(store.recover.isEmpty)
            Button(L("复制分享链接"), action: store.copyShare)
            Divider()
            Button(L("换一个地址")) {
                Task { await store.recreate() }
            }
            .disabled(store.busy)
            Button(L("清空收件箱")) {
                Task { await store.clear() }
            }
            .disabled(store.addr.isEmpty || store.busy)
            Divider()
            Button(L("退出此邮箱")) {
                store.leaveBox()
            }
        } label: {
            SnapIcon(.more, size: .body, opacity: 0.9, tint: theme.textPrimary)
                .frame(width: 32, height: 28)
                .background(theme.fillStrong, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.fillStrong)
                SnapIcon(.mail, size: .title, opacity: 0.95, tint: theme.textPrimary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Button(action: store.copyAddr) {
                    HStack(spacing: 6) {
                        Text(store.localPart)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !store.domainPart.isEmpty {
                            Text("@\(store.domainPart)")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(theme.accentSoft, in: Capsule())
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(L("轻点复制完整地址"))

                HStack(spacing: 8) {
                    liveDot
                    Text(store.messages.isEmpty ? L("等待来信") : L("%@ 封来信", store.messages.count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                    if !store.recover.isEmpty {
                        Button(action: store.copyRecover) {
                            Text(store.recover)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.fill, in: Capsule())
                                .foregroundStyle(theme.textMuted)
                        }
                        .buttonStyle(.plain)
                        .help(L("轻点复制恢复码"))
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
        .flareGlass(cornerRadius: 14)
    }

    private var liveDot: some View {
        Circle()
            .fill(store.messages.isEmpty ? theme.success : theme.accent)
            .frame(width: 7, height: 7)
            .opacity(livePulse ? 1 : 0.35)
    }

    private var otpStrip: some View {
        HStack(spacing: 8) {
            ForEach(store.codes, id: \.self) { code in
                Button {
                    store.copyCode(code)
                } label: {
                    HStack(spacing: 10) {
                        Text(L("验证码"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accent)
                        if isDigitCode(code) {
                            HStack(spacing: 4) {
                                ForEach(Array(code.enumerated()), id: \.offset) { _, ch in
                                    Text(String(ch))
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .frame(width: 26, height: 32)
                                        .background(theme.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .foregroundStyle(theme.textPrimary)
                                }
                            }
                        } else {
                            Text(code)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .tracking(1.5)
                                .foregroundStyle(theme.textPrimary)
                        }
                        Spacer(minLength: 0)
                        Text(L("复制"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.accent.opacity(0.22), lineWidth: 1)
                    )
                }
                .buttonStyle(FlareCardButtonStyle())
                .help(L("轻点复制验证码"))
            }
        }
    }

    private func isDigitCode(_ code: String) -> Bool {
        (4...8).contains(code.count) && code.allSatisfy(\.isNumber)
    }

    private var inboxColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("收件箱"))
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
                    Text(L("还没有来信"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(L("复制地址，贴到注册页。验证码会自动出现。"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    FlareSecondaryButton(title: L("复制地址"), glyph: .copy, action: store.copyAddr)
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
        .frame(width: 280)
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
                    Text(L("正在打开邮件…"))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .flareGlass(cornerRadius: 12)
            } else {
                VStack(spacing: 8) {
                    SnapIconWell(.ocr, side: 36, iconSize: .title, cornerRadius: 9)
                    Text(L("等待验证码"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(L("来信后会自动打开，数字验证码会出现在上方。"))
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
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(selected ? theme.accent : Color.clear)
                    .frame(width: 3, height: 28)
                    .padding(.top, 2)
                senderBadge(item.sender ?? "", selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(senderName(item.sender))
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.ago ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                    }
                    Text(item.subject?.isEmpty == false ? (item.subject ?? "") : L("无主题"))
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
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(selected ? theme.fillStrong : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func senderName(_ sender: String?) -> String {
        let raw = sender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return L("未知发件人") }
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(mail.subject ?? L("无主题"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(senderName(mail.sender))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                    if let selected = store.selected {
                        Text(store.remainLabel(for: selected))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textMuted)
                    }
                    Spacer(minLength: 0)
                    if let text = mail.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(L("复制正文"), action: store.copyMailText)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                    if mail.html?.isEmpty == false || mail.id != nil {
                        Button(L("网页版"), action: store.openMailPage)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.accent)
                    }
                }
                if let codes = mail.codes, !codes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(codes, id: \.self) { code in
                            Button {
                                store.copyCode(code)
                            } label: {
                                Text(code)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(theme.accentSoft, in: Capsule())
                                    .foregroundStyle(theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(theme.stroke)
                .frame(height: 1)

            ScrollView {
                Group {
                    if let text = mail.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textPrimary)
                            .textSelection(.enabled)
                            .lineSpacing(4)
                    } else {
                        Text(L("这封信没有纯文本，可用网页版查看。"))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.textMuted)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .flareGlass(cornerRadius: 12)
    }

    private var welcomeStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("取一个地址"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(L("复制后贴到注册页，验证码会自动出现。"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                domainChips
                HStack(spacing: 8) {
                    field($store.prefix, placeholder: L("前缀，可空"))
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
                            Text(L("创建"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(theme.inverseFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(theme.inverseText)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.busy)
                }
                Text(L("只收不发 · 来信 24 小时后删除"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .flareGlass(cornerRadius: 14)

            VStack(alignment: .leading, spacing: 10) {
                Text(L("打开已有邮箱"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Text(store.recover.isEmpty ? L("填写地址或恢复码 RK-xxxx") : L("已填入上一只邮箱的恢复码"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                HStack(spacing: 8) {
                    field($store.openInput, placeholder: L("地址 / 前缀 / RK-xxxx"))
                        .onSubmit {
                            Task { await store.openKnown() }
                        }
                    Button(L("打开")) {
                        Task { await store.openKnown() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(theme.fillStrong, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(theme.textPrimary)
                    .disabled(store.busy)
                }
            }
            .padding(14)
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
