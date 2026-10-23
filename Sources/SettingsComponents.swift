import AppKit
import SwiftUI

enum SettingsMetrics {
    static let sidebarWidth: CGFloat = 215
    static let detailMinimumWidth: CGFloat = 420
    static let sidebarGlyph: CGFloat = 14
    static let tilePadding: CGFloat = 4
    static let tileRadius: CGFloat = 6
    static let rowIcon: CGFloat = 24
}

/// A tinted glyph on a faint tile of the same tint: the sidebar and row icon.
struct SettingsTabIcon: View {
    let systemImage: String
    let tint: Color
    var size = SettingsMetrics.sidebarGlyph + SettingsMetrics.tilePadding * 2

    var body: some View {
        let scale = size / (SettingsMetrics.sidebarGlyph + SettingsMetrics.tilePadding * 2)
        Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .frame(
                width: SettingsMetrics.sidebarGlyph * scale,
                height: SettingsMetrics.sidebarGlyph * scale
            )
            .foregroundStyle(tint)
            .padding(SettingsMetrics.tilePadding * scale)
            .background(
                tint.opacity(0.1),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.tileRadius * scale, style: .continuous))
    }
}

struct SettingsRow<Icon: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var subtitleLineLimit = 2
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(subtitle)
                }
            }
            Spacer(minLength: 10)
            trailing
        }
    }
}

extension SettingsRow where Icon == EmptyView {
    init(
        title: String, subtitle: String? = nil, subtitleLineLimit: Int = 2,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title, subtitle: subtitle, subtitleLineLimit: subtitleLineLimit,
            icon: { EmptyView() }, trailing: trailing)
    }
}

/// A warning row: tinted triangle and title, a secondary explanation, trailing actions.
struct SettingsNotice<Actions: View>: View {
    let title: String
    let message: String
    var tint: Color = .orange
    var systemImage = "exclamationmark.triangle.fill"
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: SettingsMetrics.rowIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(tint)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            HStack(spacing: 6) { actions }
        }
    }
}

extension SettingsNotice where Actions == EmptyView {
    init(title: String, message: String, tint: Color = .orange, systemImage: String = "exclamationmark.triangle.fill") {
        self.init(title: title, message: message, tint: tint, systemImage: systemImage) { EmptyView() }
    }
}

/// A trailing status such as "Granted" or "Unavailable".
struct SettingsStatusBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .font(.callout)
    }
}

struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 22, minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppIconView: View {
    let path: String?

    var body: some View {
        Image(nsImage: AppIconCache.icon(forPath: path))
            .resizable()
            .interpolation(.high)
            .frame(width: SettingsMetrics.rowIcon, height: SettingsMetrics.rowIcon)
            .accessibilityHidden(true)
    }
}

@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forPath path: String?) -> NSImage {
        guard let path, !path.isEmpty else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}
