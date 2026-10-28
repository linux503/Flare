import AppKit
import SwiftUI

struct DocumentsPane: View {
    @Environment(\.flareTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FlarePageHeader(
                    title: L("新建文档"),
                    subtitle: L("一键创建空白文件并打开")
                )

                VStack(spacing: 0) {
                    ForEach(Array(DocumentKind.allCases.enumerated()), id: \.element.id) { index, kind in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.stroke)
                                .frame(height: 0.5)
                                .padding(.leading, 46)
                        }
                        documentRow(kind)
                    }
                }
                .flareGlass(cornerRadius: 10)

                HStack(spacing: 12) {
                    FlareSecondaryButton(title: L("打开文档文件夹"), glyph: .folder) {
                        try? FileManager.default.createDirectory(
                            at: AppSettings.shared.documentDirectory,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(AppSettings.shared.documentDirectory)
                    }
                    Text(AppSettings.shared.documentDirectory.path)
                        .font(.caption2)
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
    }

    private func documentRow(_ kind: DocumentKind) -> some View {
        Button {
            DocumentService.createAndReveal(kind, askWhere: true)
        } label: {
            HStack(spacing: 10) {
                SnapIconWell(kind.glyph, side: 24, iconSize: .caption, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textPrimary)
                    Text(kind.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(L("创建"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(theme.accent)
                FlareChevron()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(FlareCardButtonStyle())
    }
}
