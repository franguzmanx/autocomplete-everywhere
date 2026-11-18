import AppKit
import SwiftUI

/// Uses the system hover help. VoiceOver receives the same explanation as a hint.
struct InfoHint: View {
    let title: String
    let detail: String
    @Environment(\.l10n) private var l10n

    var body: some View {
        NativeInfoIcon(title: l10n.format(.informationAbout, title), detail: detail)
            .frame(width: 20, height: 20)
    }
}

private struct NativeInfoIcon: NSViewRepresentable {
    let title: String
    let detail: String
    func makeNSView(context: Context) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        image.imageScaling = .scaleNone
        image.contentTintColor = .secondaryLabelColor
        return image
    }
    func updateNSView(_ view: NSImageView, context: Context) {
        // Keep hover registration stable across frequent status updates.
        if view.toolTip != detail { view.toolTip = detail }
        view.setAccessibilityLabel(title)
        view.setAccessibilityHelp(detail)
    }
}

struct InfoLabel: View {
    let title: String
    let detail: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            InfoHint(title: title, detail: detail)
        }
    }
}

/// Keep the label and native control aligned in a compact form row.
struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            InfoLabel(title: title, detail: detail)
            Spacer(minLength: 16)
            control
        }
        .accessibilityElement(children: .contain)
    }
}

/// Title with a secondary detail line, used for descriptive rows in grouped forms.
struct TitleDetail: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A row that performs an action, drawn like a disclosure row rather than a button.
struct ActionRow: View {
    let title: String
    let detail: String?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                TitleDetail(title, detail: detail)
                Spacer(minLength: 8)
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Status dot with a title and detail, plus optional trailing controls.
struct StatusRow<Trailing: View>: View {
    let condition: ProductCondition
    @ViewBuilder let trailing: Trailing

    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Circle()
                .fill(condition.color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            if condition.tone == .positive {
                InfoLabel(title: condition.title(l10n), detail: condition.detail(l10n))
            } else {
                TitleDetail(condition.title(l10n), detail: condition.detail(l10n))
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.vertical, 4)
    }
}

/// Static, non-editable key cap. Rendered as text so it stays legible and accessible.
struct KeyCap: View {
    let symbol: String
    let accessibilityName: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
            .accessibilityLabel(accessibilityName)
    }
}

struct ShortcutKeys: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(symbol: "⇧", accessibilityName: l10n[.keyShift])
            KeyCap(symbol: "⌘", accessibilityName: l10n[.keyCommand])
            KeyCap(symbol: l10n[.keySpace], accessibilityName: l10n[.keySpace])
        }
        .accessibilityElement(children: .combine)
    }
}

struct ApplicationIcon: View {
    let bundleIdentifier: String
    var size: CGFloat = 20

    @Environment(SettingsStore.self) private var store

    var body: some View {
        if let icon = store.applicationCatalog.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .lineLimit(3)
            .accessibilityLabel(message)
    }
}

extension LibraryKind {
    var symbolName: String {
        switch self {
        case .knowledge: "doc.text"
        case .memory: "clock.arrow.circlepath"
        case .style: "textformat"
        }
    }
}

extension LibraryEntry {
    /// "Reference · Acme project · Mail, Slack" style summary for lists.
    func scopeSummary(l10n: L10n, applicationName: (String) -> String) -> String {
        var parts = [l10n.name(for: kind)]
        let anchor = scope.anchor.trimmingCharacters(in: .whitespacesAndNewlines)
        if !anchor.isEmpty {
            parts.append(anchor)
        }
        if scope.appIds.isEmpty {
            parts.append(l10n[.allApplications])
        } else {
            parts.append(scope.appIds.map(applicationName).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    func provenanceSummary(l10n: L10n, now: Date = Date()) -> String {
        var parts: [String] = []
        switch provenance {
        case .user:
            parts.append(l10n[.provenanceUser])
        case .file(let name):
            parts.append("\(l10n.format(.provenanceFile, name)) (\(l10n[.provenanceFileNote]))")
        }
        parts.append(l10n.format(.updatedOn, l10n.shortDate(updatedDate)))
        parts.append(l10n.format(.revisionNumber, l10n.integer(revision)))
        if let expiryDate {
            let key: L10nKey = isExpired(at: now) ? .expiredOn : .expiresOn
            parts.append(l10n.format(key, l10n.shortDate(expiryDate)))
        }
        return parts.joined(separator: " · ")
    }
}

/// A native search control kept with the list it filters.
struct NativeSearchField: NSViewRepresentable {
    let prompt: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor
    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func searchChanged(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }
    }
}
