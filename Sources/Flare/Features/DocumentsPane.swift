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
            HStack(spacing: 12) {
                SnapIconWell(kind.glyph, side: 36, iconSize: .body, cornerRadius: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(kind.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                Text("创建")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.inverseText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.inverseFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(FlareCardButtonStyle())
    }
}
