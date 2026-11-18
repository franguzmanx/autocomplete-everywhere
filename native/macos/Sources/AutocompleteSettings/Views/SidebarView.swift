import SwiftUI

/// Navigation only. The sidebar lists destinations on the flush window material; product state
/// lives in General, where it can carry a recovery action.
struct SidebarView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    private var selection: Binding<SidebarSection?> {
        Binding(
            get: { store.selection },
            set: { section in
                if let section { store.navigate(.section(section)) }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            ForEach(SidebarSection.primary) { section in
                row(section)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The same list style keeps the anchored row's inset, height and selection shape identical
            // to the rows above it.
            List(selection: selection) {
                row(.account)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 44)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ section: SidebarSection) -> some View {
        Label(l10n[section.titleKey], systemImage: section.symbolName)
            .tag(section)
    }
}
