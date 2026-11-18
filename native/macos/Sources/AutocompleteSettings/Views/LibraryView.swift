import SwiftUI

struct LibraryView: View {
    let status: ProductStatus

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var search = ""

    var body: some View {
        Group {
            if !status.isSignedIn {
                ContentUnavailableView {
                    Label(l10n[.librarySignedOut], systemImage: "lock")
                } description: {
                    Text(l10n[.librarySignedOutDetail])
                } actions: {
                    Button(l10n[.signIn]) { store.perform(.beginSignIn) }
                        .disabled(store.isBusy(.beginSignIn))
                }
            } else if !status.libraryAvailable {
                ContentUnavailableView(
                    l10n[.libraryUnavailable],
                    systemImage: "exclamationmark.triangle",
                    description: Text(l10n[.libraryUnavailableDetail])
                )
            } else {
                LibraryBrowser(search: $search)
            }
        }
        .navigationTitle(l10n[.sectionLibrary])

    }
}

private struct LibraryBrowser: View {
    @Binding var search: String

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    private var filteredEntries: [LibraryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries
            .filter { entry in
                if let kind = store.libraryKindFilter, entry.kind != kind { return false }
                guard !query.isEmpty else { return true }
                return entry.title.localizedCaseInsensitiveContains(query)
                    || entry.scope.anchor.localizedCaseInsensitiveContains(query)
                    || entry.text.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var entrySelection: Binding<String?> {
        Binding(
            get: { store.libraryDraft?.id },
            set: { id in
                if let id { store.navigate(.openEntry(id)) }
            }
        )
    }

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                NativeSearchField(prompt: l10n[.searchLibrary], text: $search)
                    .frame(height: 24)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                HStack(spacing: 8) {
                    Picker(l10n[.typeLabel], selection: $store.libraryKindFilter) {
                        Text(l10n[.filterAll]).tag(LibraryKind?.none)
                        ForEach(LibraryKind.allCases) { kind in
                            Text(l10n.name(for: kind)).tag(LibraryKind?.some(kind))
                        }
                    }
                    .labelsHidden()

                    Menu {
                        Button(l10n[.addReference]) { store.navigate(.newEntry(.knowledge)) }
                        Button(l10n[.addMemory]) { store.navigate(.newEntry(.memory)) }
                        Button(l10n[.addStyle]) { store.navigate(.newEntry(.style)) }
                    } label: {
                        Label(l10n[.add], systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .fixedSize()
                    .disabled(store.status?.canEditLibrary != true)
                    .help(l10n[.add])
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                let entries = filteredEntries
                List(selection: entrySelection) {
                    ForEach(entries) { entry in
                        LibraryEntryRow(entry: entry)
                            .tag(entry.id)
                    }
                }
                .listStyle(.inset)
                .overlay {
                    if entries.isEmpty {
                        Text(store.entries.isEmpty ? l10n[.libraryEmpty] : l10n[.noMatchingSources])
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .frame(width: 240)

            Divider()

            if let draft = store.libraryDraft {
                LibraryEditorView(
                    draft: Binding(
                        get: { store.libraryDraft ?? draft },
                        set: { store.libraryDraft = $0 }
                    )
                )
                .id(draft.id ?? "new")
            } else if store.entries.isEmpty {
                ContentUnavailableView {
                    Label(l10n[.libraryEmpty], systemImage: "books.vertical")
                } description: {
                    Text(l10n[.libraryEmptyDetail])
                } actions: {
                    Button(l10n[.addReference]) { store.navigate(.newEntry(.knowledge)) }
                }
            } else {
                Text(l10n[.selectSource])
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct LibraryEntryRow: View {
    let entry: LibraryEntry

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .lineLimit(1)
                Text(entry.scopeSummary(l10n: l10n, applicationName: applicationName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if entry.isExpired(at: Date()), let expiryDate = entry.expiryDate {
                    Text(l10n.format(.expiredOn, l10n.shortDate(expiryDate)))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func applicationName(_ identifier: String) -> String {
        store.status?.applications.first { $0.id == identifier }?.name
            ?? store.applicationCatalog.displayName(for: identifier)
            ?? identifier
    }
}
