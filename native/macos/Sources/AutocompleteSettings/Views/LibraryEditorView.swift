import SwiftUI

struct LibraryEditorView: View {
    @Binding var draft: LibraryDraft

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var confirmDelete = false

    private var savedEntry: LibraryEntry? {
        guard let id = draft.id else { return nil }
        return store.entries.first { $0.id == id }
    }

    private var isDirty: Bool {
        draft != store.libraryOriginal
    }

    private var expiryEnabled: Binding<Bool> {
        Binding(
            get: { draft.expiryDate != nil },
            set: { enabled in
                if enabled {
                    if draft.expiryDate == nil {
                        draft.expiryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())
                    }
                } else {
                    draft.expiryDate = nil
                }
            }
        )
    }

    private var expiryDate: Binding<Date> {
        Binding(
            get: { draft.expiryDate ?? Date() },
            set: { draft.expiryDate = $0 }
        )
    }

    var body: some View {
        Form {
            if let savedEntry {
                Section {
                    InfoLabel(title: l10n.format(.updatedOn, l10n.shortDate(savedEntry.updatedDate)),
                              detail: savedEntry.provenanceSummary(l10n: l10n))
                    if savedEntry.isExpired(at: Date()), let expiry = savedEntry.expiryDate {
                        Text(l10n.format(.expiredOn, l10n.shortDate(expiry))).foregroundStyle(.orange)
                    }
                }
            }

            Section {
                TextField(l10n[.titleLabel], text: $draft.title)
                Picker(l10n[.typeLabel], selection: $draft.kind) {
                    ForEach(LibraryKind.allCases) { kind in
                        Text(l10n.name(for: kind)).tag(kind)
                    }
                }
            }
            if draft.kind == .style {
                InfoLabel(title: l10n[.stylesSection], detail: l10n[.styleGuidance])
            }

            Section {
                TextField(
                    draft.kind == .style ? l10n[.anchorOptionalLabel] : l10n[.anchorLabel],
                    text: $draft.anchor,
                    prompt: Text(l10n[.anchorPlaceholder])
                )
                applicationScope
            } header: {
                InfoLabel(title: l10n[.scopeSection], detail:
                    l10n[.anchorFooter] + (draft.kind == .style ? "\n\n" + l10n[.styleApplicationsFooter] : ""))
            }

            Section {
                Toggle(l10n[.expiresToggle], isOn: expiryEnabled)
                if draft.expiryDate != nil {
                    DatePicker(
                        l10n[.expiresToggle],
                        selection: expiryDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .environment(\.locale, l10n.locale)
                }
            } header: {
                InfoLabel(title: l10n[.expirySection], detail: l10n[.expiryFooter])
            }

            Section {
                TextEditor(text: $draft.text)
                    .font(.body)
                    .frame(minHeight: 160)
                    .accessibilityLabel(l10n[.textSection])
            } header: {
                InfoLabel(title: l10n[.textSection], detail: l10n[.textFooter])
            } footer: {
                HStack(alignment: .top) {
                    Spacer()
                    Text(
                        l10n.format(
                            .characterCount,
                            l10n.integer(draft.text.count),
                            l10n.integer(LibraryInput.textLimit)
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(draft.text.count > LibraryInput.textLimit ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            editorBar
        }
        .confirmationDialog(
            l10n.format(.deleteConfirmTitle, draft.trimmedTitle.isEmpty ? l10n[.newSourceTitle] : draft.trimmedTitle),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(l10n[.delete], role: .destructive) { store.deleteLibraryDraft() }
            Button(l10n[.cancel], role: .cancel) {}
        } message: {
            Text(l10n[.deleteConfirmDetail])
        }
    }

    @ViewBuilder
    private var applicationScope: some View {
        let rows = store.applicationRows(includingDraftScope: true)
        LabeledContent(l10n[.applicationsLabel]) {
            if rows.isEmpty {
                Text(l10n[.scopeApplicationsEmpty])
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        Toggle(isOn: Binding(
                            get: { draft.appIds.contains(row.id) },
                            set: { draft.setApplication(row.id, included: $0) }
                        )) {
                            HStack(spacing: 8) {
                                ApplicationIcon(bundleIdentifier: row.id, size: 16)
                                Text(row.name)
                                if store.status?.isApplicationEnabled(row.id) == false {
                                    Text(l10n[.applicationOff])
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(row.name)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var blockingIssue: String? {
        guard let issue = draft.issues.first else { return nil }
        switch issue {
        case .missingTitle: return l10n[.validationTitle]
        case .invalidAnchor: return l10n[.validationAnchor]
        case .missingApplications: return l10n[.validationApplications]
        case .missingText: return l10n[.validationText]
        case .textTooLong: return l10n[.validationTooLong]
        }
    }

    private var editorBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.libraryError {
                InlineError(message: error)
            } else if isDirty, let blockingIssue {
                Text(blockingIssue)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Menu {
                    Button(draft.isNew ? l10n[.importFile] : l10n[.replaceFromFile]) {
                        store.importLibraryDraft()
                    }
                    .disabled(!draft.canImport)
                    if !draft.isNew {
                        Divider()
                        Button(l10n[.deleteSource], role: .destructive) { confirmDelete = true }
                    }
                } label: {
                    Label(l10n[.sourceActions], systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(l10n[.sourceActions])
                .disabled(store.libraryBusy)

                Spacer(minLength: 8)
                if store.libraryBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(l10n[.cancel]) { store.navigate(.closeEditor) }
                    .disabled(store.libraryBusy)
                Button(l10n[.save]) { store.saveLibraryDraft() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!draft.canSave || store.libraryBusy || (!draft.isNew && !isDirty))
            }
        }
        .padding(16)
        .background(.bar)
    }
}
