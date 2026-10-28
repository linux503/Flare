import AppKit
import SwiftUI

final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private init() {}

    func show() {
        HomeWindowController.shared.showHistory()
    }
}

struct HistoryPane: View {
    @ObservedObject private var store = HistoryStore.shared
    @Environment(\.flareTheme) private var theme
    @State private var confirmClear = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlarePageHeader(
                title: L("历史记录"),
                subtitle: store.items.isEmpty
                    ? L("截图会出现在这里 · 保留 %@", AppSettings.shared.historyRetention.displayName)
                    : L("共 %@ 张 · 保留 %@", store.items.count, AppSettings.shared.historyRetention.displayName)
            ) {
                FlareSecondaryButton(title: L("清空"), glyph: .trash) {
                    confirmClear = true
                }
                .disabled(store.items.isEmpty)
                .opacity(store.items.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 6)

            if store.items.isEmpty {
                VStack(spacing: 14) {
                    SnapIcon(.history, size: .display, opacity: 0.45)
                    Text(L("还没有截图"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(L("使用快捷键或侧栏「截图」开始"))
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                    FlarePrimaryButton(title: L("去截图"), glyph: .area) {
                        HomeWindowController.shared.show(tab: .home)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(store.items) { item in
                            HistoryCard(item: item)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)
                }
            }
        }
        .confirmationDialog(L("清空全部历史？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("清空全部"), role: .destructive) {
                store.clear()
                StatusBarController.shared?.reloadMenu()
                ToastController.shared.show(L("已清空历史"))
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(L("将删除 %@ 条记录，此操作不可撤销。", store.items.count))
        }
    }
}

struct HistoryCard: View {
    let item: HistoryItem
    @ObservedObject private var store = HistoryStore.shared
    @Environment(\.flareTheme) private var theme

    var body: some View {
        FlareHoverCard(cornerRadius: 12) {
            VStack(alignment: .leading, spacing: 0) {
                HistoryThumbnailView(item: item, aspectRatio: 16 / 10)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
                    .padding(.bottom, 2)
                    .contentShape(Rectangle())
                    .onTapGesture { openEditor() }

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.fileName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(item.createdAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        iconButton(.edit, theme.textSecondary, openEditor)
                        iconButton(.copy, theme.textSecondary) {
                            guard let image = store.image(for: item) else { return }
                            Task { await PrivacyGuard.copyIfAllowed(image) }
                        }
                        iconButton(.trash, Color.red.opacity(0.75)) {
                            store.delete(item)
                            StatusBarController.shared?.reloadMenu()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .frame(height: 48, alignment: .top)
            }
        }
        .contextMenu {
            Button(L("编辑"), action: openEditor)
            Button(L("OCR 保存 TXT…")) {
                guard let image = store.image(for: item) else { return }
                Task {
                    if let url = try? await TextFileService.createTXTFromOCR(image: image, askWhere: true) {
                        await MainActor.run {
                            ToastController.shared.show(L("已保存 %@", url.lastPathComponent))
                            TextFileService.reveal(url)
                        }
                    }
                }
            }
            Button(L("截图翻译")) {
                guard let image = store.image(for: item) else { return }
                Task { @MainActor in
                    await PrivacyGuard.presentTranslate(from: image)
                }
            }
            Button(L("删除"), role: .destructive) {
                store.delete(item)
                StatusBarController.shared?.reloadMenu()
            }
        }
    }

    private func openEditor() {
        if let image = store.image(for: item) {
            EditorWindowController.shared.present(image: image)
        }
    }

    private func iconButton(_ glyph: SnapGlyph, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SnapIcon(glyph, size: .caption, opacity: 1, tint: tint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(FlareChipButtonStyle())
        .help(glyph == .edit ? L("编辑") : glyph == .copy ? L("复制") : L("删除"))
    }
}
