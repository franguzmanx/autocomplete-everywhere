import SwiftUI

/// Rewrites: the Option + number shortcuts that rewrite selected text in place. The wire and
/// storage still call these transforms; only the words shown to the user changed.
///
/// Editing happens in a sheet. The sheet's Save, a delete, the enable switch and Restore defaults
/// each write through the store at once, so this page keeps no draft of its own. A store draft
/// survives only when a save failed or something else staged one; then the page shows it with
/// Save rewrites / Revert and never discards it silently.
struct RewritesView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var editing: WritingTransform?
    @State private var confirmRestore = false
    @State private var restoring = false
    @State private var restoreError: String?

    var body: some View {
        Form {
            if let settings = store.transforms {
                Section {
                    SettingsRow(title: l10n[.transformEnable],
                                detail: l10n[.transformHelp] + "\n\n" + l10n[.transformPriority]) {
                        Toggle(l10n[.transformEnable], isOn: Binding(
                            get: { settings.enabled },
                            set: { value in commit { $0.enabled = value } }
                        ))
                        .labelsHidden()
                    }
                }

                Section(l10n[.shortcutSection]) {
                    ForEach(settings.transforms.sorted { $0.shortcut < $1.shortcut }) { transform in
                        TransformRow(transform: transform) { editing = transform }
                    }
                    HStack(spacing: 12) {
                        Button(l10n[.transformCreate]) { editing = newTransform(in: settings) }
                            .disabled(settings.transforms.count >= 9)
                        Button(l10n[.transformDefaults]) { confirmRestore = true }
                        Spacer()
                        if store.transformsSaving || restoring {
                            ProgressView().controlSize(.small)
                        }
                    }
                    pendingChanges(settings)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(store.transformsSaving || restoring)
        .navigationTitle(l10n[.sectionRewrites])
        .sheet(item: $editing) { transform in
            TransformEditorSheet(
                transform: transform,
                original: store.transforms?.transforms.first { $0.id == transform.id }
            )
        }
        .confirmationDialog(l10n[.transformRestoreTitle], isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(l10n[.transformDefaults], role: .destructive) { restoreDefaults() }
            Button(l10n[.cancel], role: .cancel) {}
        } message: {
            Text(l10n[.transformRestoreDetail])
        }
    }

    /// Shown only while a store draft exists outside a save in flight: a failed save, or edits staged
    /// elsewhere. Save stays disabled while the draft is invalid; Revert returns to the saved settings.
    @ViewBuilder
    private func pendingChanges(_ settings: TransformSettings) -> some View {
        if let error = store.transformsError ?? restoreError {
            InlineError(message: error)
        } else if store.hasUnsavedTransformChanges, !settings.isValid {
            InlineError(message: l10n[.transformValidation])
        }
        if store.hasUnsavedTransformChanges, !store.transformsSaving {
            HStack(spacing: 12) {
                Text(l10n[.writingUnsaved]).foregroundStyle(.secondary)
                Spacer()
                Button(l10n[.writingRevert]) { store.discardTransformChanges() }
                Button(l10n[.transformSave]) { store.saveTransforms() }
                    .disabled(!settings.isValid)
            }
        }
    }

    private func commit(_ edit: (inout TransformSettings) -> Void) {
        restoreError = nil
        store.editTransforms(edit)
        store.saveTransforms()
    }

    private func newTransform(in settings: TransformSettings) -> WritingTransform? {
        guard let shortcut = (1...9).first(where: { number in !settings.transforms.contains { $0.shortcut == number } })
        else { return nil }
        return WritingTransform(id: UUID().uuidString.lowercased(), name: "", shortcut: shortcut,
                                rules: [.clarity, .tone], prompt: "", examples: [])
    }

    /// Replaces the rewrite list with the desktop's defaults and saves. The enable switch is kept.
    private func restoreDefaults() {
        restoring = true
        restoreError = nil
        Task { @MainActor in
            defer { restoring = false }
            do {
                let defaults = try await store.request(.getDefaultTransforms).decoded(as: TransformSettings.self)
                guard defaults.isValid else { throw RequestFailure(message: l10n[.transformValidation]) }
                commit { $0.transforms = defaults.transforms }
            } catch {
                restoreError = store.message(for: error)
            }
        }
    }
}

private struct TransformRow: View {
    let transform: WritingTransform
    let edit: () -> Void

    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(spacing: 12) {
            Text(transform.name)
                .lineLimit(1)
            Spacer(minLength: 8)
            KeyCap(symbol: "⌥\(transform.shortcut)",
                   accessibilityName: l10n.format(.transformOptionKey, String(transform.shortcut)))
            Button(l10n[.transformEdit], action: edit)
                .accessibilityLabel(l10n.format(.transformEditNamed, transform.name))
        }
        .accessibilityElement(children: .contain)
    }
}

/// Edits one rewrite in isolation. Nothing reaches the store until Save; Cancel or Escape discards.
private struct TransformEditorSheet: View {
    @State private var transform: WritingTransform
    private let original: WritingTransform?

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    init(transform: WritingTransform, original: WritingTransform?) {
        _transform = State(initialValue: transform)
        self.original = original
    }

    private var isNew: Bool { original == nil }

    /// The value that would be saved: trimmed like the desktop schema, with empty examples dropped.
    private var normalized: WritingTransform {
        var value = transform
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.prompt = value.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        value.examples = value.examples
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return value
    }

    private var isDirty: Bool { normalized != original }

    private var canSave: Bool {
        isDirty && normalized.isValid && !store.transformsSaving
    }

    /// Shortcuts not taken by another rewrite, plus the current one.
    private var availableShortcuts: [Int] {
        let others = store.transforms?.transforms.filter { $0.id != transform.id } ?? []
        return (1...9).filter { number in
            number == transform.shortcut || !others.contains { $0.shortcut == number }
        }
    }

    var body: some View {
        Form {
            Section {
                TextField(l10n[.transformName], text: $transform.name)
                Picker(l10n[.transformShortcut], selection: $transform.shortcut) {
                    ForEach(availableShortcuts, id: \.self) { number in
                        Text("⌥\(number)").tag(number)
                    }
                }
            } header: {
                Text(isNew ? l10n[.transformNew] : original?.name ?? "")
                    .font(.title3.weight(.semibold))
            }

            Section(l10n[.transformRules]) {
                ForEach(TransformRule.allCases) { rule in
                    Toggle(l10n[rule.titleKey], isOn: ruleBinding(rule))
                        .toggleStyle(.checkbox)
                }
            }

            Section(l10n[.transformInstructions]) {
                TextEditor(text: $transform.prompt)
                    .font(.body)
                    .frame(minHeight: 96)
                    .accessibilityLabel(l10n[.transformInstructions])
            }

            if !transform.examples.isEmpty {
                Section {
                    LabeledContent(l10n.format(.transformExamplesKept, l10n.integer(transform.examples.count))) {
                        Button(l10n[.transformRemoveExamples]) { transform.examples = [] }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) { editorBar }
        .frame(width: 460, height: 540)
        .confirmationDialog(
            l10n.format(.deleteConfirmTitle, original?.name ?? ""),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(l10n[.delete], role: .destructive) { delete() }
            Button(l10n[.cancel], role: .cancel) {}
        }
    }

    private var editorBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDirty, !normalized.isValid {
                Text(l10n[.transformEditorValidation])
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if !isNew {
                    Button(l10n[.transformDelete], role: .destructive) { confirmDelete = true }
                }
                Spacer(minLength: 8)
                Button(l10n[.cancel]) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(l10n[.save]) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!canSave)
            }
        }
        .padding(16)
        .background(.bar)
    }

    private func ruleBinding(_ rule: TransformRule) -> Binding<Bool> {
        Binding(
            get: { transform.rules.contains(rule) },
            set: { enabled in
                transform.rules = TransformRule.allCases.filter { $0 == rule ? enabled : transform.rules.contains($0) }
            }
        )
    }

    private func save() {
        let value = normalized
        guard value.isValid, !store.transformsSaving else { return }
        store.editTransforms { settings in
            if let index = settings.transforms.firstIndex(where: { $0.id == value.id }) {
                settings.transforms[index] = value
            } else {
                settings.transforms.append(value)
            }
        }
        store.saveTransforms()
        dismiss()
    }

    private func delete() {
        guard !store.transformsSaving else { return }
        store.editTransforms { $0.transforms.removeAll { $0.id == transform.id } }
        store.saveTransforms()
        dismiss()
    }
}

private extension TransformRule {
    var titleKey: L10nKey {
        switch self {
        case .concise: .transformConcise
        case .clarity: .transformClarity
        case .reorder: .transformReorder
        case .structure: .transformStructure
        case .tone: .transformTone
        }
    }
}
