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
                title: "历史记录",
                subtitle: store.items.isEmpty
                    ? "截图会出现在这里 · 保留 \(AppSettings.shared.historyRetention.displayName)"
                    : "共 \(store.items.count) 张 · 保留 \(AppSettings.shared.historyRetention.displayName)"
            ) {
                FlareSecondaryButton(title: "清空", glyph: .trash) {
                    confirmClear = true
                }
                .disabled(store.items.isEmpty)
                .opacity(store.items.isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 8)

            if store.items.isEmpty {
                VStack(spacing: 14) {
                    SnapIcon(.history, size: .display, opacity: 0.45)
                    Text("还没有截图")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textSecondary)
                    Text("使用快捷键或侧栏「截图」开始")
                        .font(.caption)
                        .foregroundStyle(theme.textMuted)
                    FlarePrimaryButton(title: "去截图", glyph: .area) {
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
                    .padding(.bottom, 28)
                }
            }
        }
        .confirmationDialog("清空全部历史？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) {
                store.clear()
                StatusBarController.shared?.reloadMenu()
                ToastController.shared.show("已清空历史")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(store.items.count) 条记录，此操作不可撤销。")
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
                            if let image = store.image(for: item) {
                                ImageExporter.copyToClipboard(image)
                                ToastController.shared.show("已复制")
                            }
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
            Button("编辑", action: openEditor)
            Button("OCR 保存 TXT…") {
                guard let image = store.image(for: item) else { return }
                Task {
                    if let url = try? await TextFileService.createTXTFromOCR(image: image, askWhere: true) {
                        await MainActor.run {
                            ToastController.shared.show("已保存 \(url.lastPathComponent)")
                            TextFileService.reveal(url)
                        }
                    }
                }
            }
            Button("删除", role: .destructive) {
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
        .help(glyph == .edit ? "编辑" : glyph == .copy ? "复制" : "删除")
    }
}
