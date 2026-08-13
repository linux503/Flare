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
    private let columns = [GridItem(.adaptive(minimum: 196), spacing: 16)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                FlarePageHeader(
                    title: "历史记录",
                    subtitle: store.items.isEmpty ? "截图会出现在这里" : "共 \(store.items.count) 张 · 双击打开编辑"
                ) {
                    FlareSecondaryButton(title: "清空", glyph: .trash) {
                        confirmClear = true
                    }
                    .disabled(store.items.isEmpty)
                    .opacity(store.items.isEmpty ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 12)

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
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.items) { item in
                            HistoryCard(item: item)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
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
        FlareHoverCard(cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HistoryThumbnailView(item: item, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onTapGesture(count: 2) { openEditor() }

                Text(item.fileName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)

                HStack(spacing: 8) {
                    miniButton("编辑", .edit, openEditor)
                    miniButton("复制", .copy) {
                        if let image = store.image(for: item) {
                            ImageExporter.copyToClipboard(image)
                            ToastController.shared.show("已复制")
                        }
                    }
                    Spacer()
                    Button {
                        store.delete(item)
                        StatusBarController.shared?.reloadMenu()
                    } label: {
                        SnapIcon(.trash, size: .caption, opacity: 1, tint: Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
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

    private func miniButton(_ title: String, _ glyph: SnapGlyph, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                SnapIcon(glyph, size: .caption, opacity: 0.85)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(theme.fillStrong)
            .foregroundStyle(theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(FlareChipButtonStyle())
    }
}
