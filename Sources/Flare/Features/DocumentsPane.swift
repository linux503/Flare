import AppKit
import SwiftUI

struct DocumentsPane: View {
    @Environment(\.flareTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                FlarePageHeader(
                    title: "新建文档",
                    subtitle: "一键创建空白文件并打开"
                )

                VStack(spacing: 8) {
                    ForEach(DocumentKind.allCases) { kind in
                        documentRow(kind)
                    }
                }

                HStack(spacing: 12) {
                    FlareSecondaryButton(title: "打开文档文件夹", glyph: .folder) {
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
            HStack(spacing: 16) {
                SnapIconWell(kind.glyph, side: 52, iconSize: .title, cornerRadius: 13)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(kind.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                Text("创建")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inverseText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(theme.inverseFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(FlareCardButtonStyle())
    }
}
