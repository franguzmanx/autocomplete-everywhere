import SwiftUI

struct ContextView: View {
    @Environment(SettingsStore.self) private var store
    @State private var reference = ""
    @State private var query = ""
    @State private var referenceError: String?
    private func text(_ en: String, _ es: String) -> String { store.language == .es ? es : en }
    var body: some View {
        Form {
            Section {
                Toggle(text("Remember context", "Recordar contexto"), isOn: Binding(get: { store.context.enabled }, set: { store.perform(.contextSetEnabled($0)) }))
                Text(text("Autocomplete Everywhere reads visible content in your active app to connect related work. History is encrypted locally and kept for 30 days. Relevant text is sent to AI providers for suggestions and embeddings. Provider retention policies apply; this is not a zero-retention service.", "Autocomplete Everywhere lee el contenido visible de la app activa para relacionar tu trabajo. El historial se cifra localmente y se conserva 30 días. El texto relevante se envía a proveedores de IA para sugerencias y representaciones semánticas. Se aplican las políticas de retención del proveedor; no es un servicio sin retención."))
                    .font(.callout).foregroundStyle(.secondary)
                Text(text("Screen images require separate consent and macOS permission. They may be sent to the AI provider and are never saved locally. Pausing Autocomplete Everywhere or signing out stops observation. Secure fields and excluded apps are skipped.", "Las imágenes de pantalla requieren consentimiento separado y permiso de macOS. Pueden enviarse al proveedor de IA y nunca se guardan localmente. Pausar Autocomplete Everywhere o cerrar sesión detiene la observación. Se omiten los campos seguros y las apps excluidas."))
                    .font(.callout).foregroundStyle(.secondary)
                if store.context.semanticStatus == .unavailable {
                    Text(text("Semantic context is unavailable. Current text and text search still work.", "El contexto semántico no está disponible. El texto actual y la búsqueda de texto siguen funcionando."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                Button(text("Manage excluded apps", "Administrar apps excluidas")) { store.navigate(.section(.applications)) }
            }
            Section(text("Screen context", "Contexto de pantalla")) {
                Toggle(text("Allow screen images", "Permitir imágenes de pantalla"), isOn: Binding(get: { store.context.visualEnabled }, set: { store.perform(.contextSetVisualEnabled($0)) }))
                    .disabled(!store.context.enabled)
                switch store.context.visualStatus {
                case .disabled:
                    Text(text("Screen images are off.", "Las imágenes de pantalla están desactivadas."))
                case .permission_required:
                    Text(text("Allow Screen Recording so Autocomplete Everywhere can understand visual content in your active window.", "Permite la grabación de pantalla para que Autocomplete Everywhere pueda interpretar el contenido visual de la ventana activa."))
                    Button(text("Allow Screen Recording", "Permitir grabación de pantalla")) { store.perform(.contextRequestScreenPermission) }
                case .ready:
                    Label(text("Screen context is available", "El contexto de pantalla está disponible"), systemImage: "checkmark.circle")
                case .unverified:
                    Text(text("Visual context is not available yet. Text context continues to work.", "El contexto visual todavía no está disponible. El contexto de texto sigue funcionando."))
                }
            }
            Section {
                DisclosureGroup(text("Context used", "Contexto utilizado")) { entries(store.context.used, mode: .used) }
            }
            Section(text("History", "Historial")) {
                TextField(text("Search history", "Buscar en el historial"), text: $query)
                    .onSubmit { store.perform(.contextSearch(query)) }
                entries(store.context.history, mode: .history)
                HStack {
                    if store.context.historyPage > 0 {
                        Button(text("Previous page", "Página anterior")) { store.perform(.contextHistoryPrevious) }
                    }
                    if store.context.history.count >= 100 {
                        Button(text("Next page", "Página siguiente")) { store.perform(.contextHistoryMore) }
                    }
                    Button(text("Refresh", "Actualizar")) { query = ""; store.perform(.contextRefresh) }
                    Spacer()
                    Button(text("Delete history", "Eliminar historial"), role: .destructive) { store.perform(.contextClear) }
                }
            }
            Section(text("References", "Referencias")) {
                entries(store.context.references, mode: .reference)
                TextField(text("Add a reference", "Añadir una referencia"), text: $reference, axis: .vertical)
                Button(text("Add", "Añadir")) {
                    let submitted = reference
                    referenceError = nil
                    Task {
                        do {
                            _ = try await store.request(.contextAddReference(submitted))
                            if reference == submitted { reference = "" }
                        } catch {
                            referenceError = (error as? RequestFailure)?.message ?? text("Could not save the reference. Try again.", "No se pudo guardar la referencia. Inténtalo de nuevo.")
                        }
                    }
                }.disabled(reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy(.contextAddReference(reference)))
                if let referenceError { Text(referenceError).font(.callout).foregroundStyle(.red) }
            }
            Section(text("Connections", "Conexiones")) {
                ForEach(["github", "figma"], id: \.self) { provider in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(provider == "github" ? "GitHub" : "Figma")
                            if let entry = store.context.connections.first(where: { $0.id == provider }) {
                                Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if store.context.connections.contains(where: { $0.id == provider }) {
                            Button(text("Disconnect", "Desconectar")) { store.perform(.contextDisconnect(provider)) }
                        } else {
                            Button(text("Connect", "Conectar")) { store.perform(.contextConnect(provider)) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(store.status?.isSignedIn != true || store.connectionClosed)
    }
    private enum EntryMode { case history, reference, used }
    @ViewBuilder private func entries(_ items: [ContextState.Entry], mode: EntryMode) -> some View {
        if items.isEmpty { Text(text("Nothing yet", "Todavía no hay contenido")).foregroundStyle(.secondary) }
        ForEach(items) { entry in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.excerpt).textSelection(.enabled)
                    HStack {
                        if mode == .reference {
                            Button(text("Unpin", "Desfijar")) { store.perform(.contextUnpin(entry.id)) }
                        } else if mode == .history {
                            Button(text("Pin", "Fijar")) { store.perform(.contextPin(entry.id)) }
                        }
                        Spacer()
                        Button(text("Delete source", "Eliminar fuente"), role: .destructive) { store.perform(.contextDelete(entry.id)) }
                    }
                }
            } label: {
                VStack(alignment: .leading) {
                    Text(entry.title).lineLimit(2)
                    Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
    }
}
