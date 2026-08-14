import AppKit
import SwiftUI

/// 卡片悬停 / 按下反馈
struct FlareCardButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enabled ? 0.985 : 1)
            .opacity(enabled ? (configuration.isPressed ? 0.92 : 1) : 0.55)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct FlareChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 半透明表面（随主题）
struct FlareHoverCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    @Environment(\.flareTheme) private var theme
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(hovering ? theme.fillStrong : theme.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                hovering ? theme.strokeStrong : theme.stroke,
                                lineWidth: 1
                            )
                    )
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// 页面大标题区
struct FlarePageHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.flareTheme) private var theme
    var trailing: AnyView? = nil

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 2)
    }
}

struct FlarePrimaryButton: View {
    let title: String
    var glyph: SnapGlyph? = nil
    let action: () -> Void
    @Environment(\.flareTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let glyph {
                    SnapIcon(glyph, size: .caption, opacity: 1, tint: theme.inverseText)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(theme.inverseFill)
            .foregroundStyle(theme.inverseText)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(FlareChipButtonStyle())
    }
}

struct FlareSecondaryButton: View {
    let title: String
    var glyph: SnapGlyph? = nil
    let action: () -> Void
    @Environment(\.flareTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let glyph {
                    SnapIcon(glyph, size: .caption, opacity: 0.85, tint: theme.textPrimary)
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.fillStrong)
            .foregroundStyle(theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(FlareChipButtonStyle())
    }
}

struct ThemePickerGrid: View {
    @ObservedObject private var themeController = ThemeController.shared
    @Environment(\.flareTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppThemeKind.allCases) { kind in
                Button {
                    themeController.set(kind)
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [kind.palette.canvasTop, kind.palette.canvasBottom],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 56)
                                .overlay(
                                    HStack(spacing: 6) {
                                        Circle().fill(kind.palette.textPrimary).frame(width: 8, height: 8)
                                        Capsule().fill(kind.palette.fillStrong).frame(width: 36, height: 6)
                                    }
                                    .padding(12),
                                    alignment: .bottomLeading
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            themeController.kind == kind ? theme.accent : theme.stroke,
                                            lineWidth: themeController.kind == kind ? 2 : 1
                                        )
                                )

                            if themeController.kind == kind {
                                SnapIcon(.success, size: .caption, opacity: 1, tint: theme.success)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(kind.subtitle)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textMuted)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(themeController.kind == kind ? theme.fillStrong : theme.fill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(theme.stroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(FlareCardButtonStyle())
            }
        }
    }
}

struct WindowOpacitySlider: View {
    @ObservedObject private var themeController = ThemeController.shared
    @Environment(\.flareTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("窗口透明度")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(opacityLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
            Slider(
                value: Binding(
                    get: { themeController.windowOpacity },
                    set: { themeController.setOpacity($0) }
                ),
                in: 0.72...1.0,
                step: 0.02
            )
            .tint(theme.accent)
            Text("数值越低越通透；接近 100% 时为实色窗口。")
                .font(.system(size: 10))
                .foregroundStyle(theme.textMuted)
        }
    }

    private var opacityLabel: String {
        "\(Int((themeController.windowOpacity * 100).rounded()))%"
    }
}

struct HistoryThumbnailView: View {
    let item: HistoryItem
    var height: CGFloat? = 110
    var aspectRatio: CGFloat? = nil
    @Environment(\.flareTheme) private var theme

    @State private var image: NSImage?

    var body: some View {
        let thumb = Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                theme.fillStrong
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.textMuted)
                    }
            }
        }

        Group {
            if let aspectRatio {
                Color.clear
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay { thumb }
                    .clipped()
            } else {
                thumb
                    .frame(maxWidth: .infinity)
                    .frame(height: height ?? 110)
                    .clipped()
            }
        }
        .task(id: item.id) {
            image = await HistoryStore.shared.thumbnailAsync(for: item)
        }
    }
}

extension View {
    func flareTabTransition() -> some View {
        self
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)).combined(with: .offset(x: 8)),
                removal: .opacity.combined(with: .offset(x: -6))
            ))
    }
}
