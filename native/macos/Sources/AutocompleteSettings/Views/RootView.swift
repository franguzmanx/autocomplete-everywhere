import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        let l10n = store.l10n
        SettingsSplitView(store: store)
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.l10n, l10n)
        .alert(
            store.alert?.title ?? "",
            isPresented: Binding(
                get: { store.alert != nil },
                set: { if !$0 { store.alert = nil } }
            ),
            presenting: store.alert
        ) { _ in
            Button(l10n[.ok]) { store.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
        .confirmationDialog(
            l10n[.unsavedTitle],
            isPresented: Binding(
                get: { store.pendingNavigation != nil },
                set: { if !$0 { store.cancelPendingNavigation() } }
            ),
            titleVisibility: .visible
        ) {
            Button(l10n[.discard], role: .destructive) { store.confirmPendingNavigation() }
            Button(l10n[.keepEditing], role: .cancel) { store.cancelPendingNavigation() }
        } message: {
            Text(l10n[.unsavedDetail])
        }
        .sheet(
            isPresented: Binding(
                get: { store.exercisePresented },
                set: { if !$0 { store.closeExercise() } }
            )
        ) {
            ExerciseSheet()
                .environment(\.l10n, l10n)
        }
    }
}

struct DetailView: View {
    @Environment(SettingsStore.self) private var store

    var body: some View {
        if let status = store.status {
            switch store.selection {
            case .context: ContextView()
            case .general: GeneralView(status: status)
            case .writing: WritingView(status: status)
            case .rewrites: RewritesView()
            case .applications: ApplicationsView(status: status)
            case .library: LibraryView(status: status)
            case .account: AccountView(status: status)
            }
        } else {
            ConnectingView()
        }
    }
}

private struct ConnectingView: View {
    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    var body: some View {
        if let failure = store.initialLoadFailure {
            ContentUnavailableView {
                Label(l10n[.connectionFailedTitle], systemImage: "bolt.slash")
            } description: {
                Text(failure)
            } actions: {
                Button(l10n[.retry]) { store.requestInitialState() }
            }
        } else {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.regular)
                Text(l10n[.connecting])
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }
}
