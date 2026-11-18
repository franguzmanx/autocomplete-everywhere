import SwiftUI

struct ApplicationsView: View {
    let status: ProductStatus

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var search = ""

    private var rows: [ApplicationRow] {
        let all = store.applicationRows().filter { !["com.autocompleteeverywhere.desktop", "com.autocompletion.settings"].contains($0.id) }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        let visible = rows
        Form {
            if visible.isEmpty {
                Section {
                    if search.isEmpty {
                        ContentUnavailableView(
                            l10n[.applicationsEmpty],
                            systemImage: "app.dashed",
                            description: Text(l10n[.applicationsEmptyDetail])
                        )
                    } else {
                        Text(l10n[.applicationsNoResults])
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ForEach(visible) { row in
                        ApplicationToggleRow(row: row)
                    }
                } header: {
                    InfoLabel(title: l10n[.sectionApplications], detail: l10n[.applicationsFooter])
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            NativeSearchField(prompt: l10n[.applicationsSearch], text: $search)
                .frame(height: 24)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .navigationTitle(l10n[.sectionApplications])
    }
}

private struct ApplicationToggleRow: View {
    let row: ApplicationRow

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    private var enabled: Binding<Bool> {
        Binding(
            get: { store.isApplicationEnabled(row.id) },
            set: { store.setApplication(row.id, enabled: $0) }
        )
    }

    var body: some View {
        Toggle(isOn: enabled) {
            HStack(spacing: 8) {
                ApplicationIcon(bundleIdentifier: row.id, size: 24)
                TitleDetail(row.name, detail: row.isCurrent ? l10n[.activeNow] : nil)
            }
        }
        .toggleStyle(.switch)
        .accessibilityLabel(l10n.format(.applicationToggleLabel, row.name))
    }
}
