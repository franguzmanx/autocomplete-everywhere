import SwiftUI

struct AccountView: View {
    let status: ProductStatus

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var confirmSignOut = false

    var body: some View {
        Form {
            if status.account.usesApiKey {
                ApiKeySection(isSaved: status.isSignedIn, confirmRemove: $confirmSignOut)
            } else {
                switch status.account.state {
                case .signedIn:
                    Section {
                        IdentityRow(identity: status.account.identity)
                    }
                    Section {
                        ActionRow(
                            title: l10n[.manageAccount],
                            detail: nil,
                            systemImage: "arrow.up.forward.square",
                            action: { store.perform(.openManageAccount) }
                        )
                        ActionRow(
                            title: l10n[.signOut],
                            detail: nil,
                            systemImage: "rectangle.portrait.and.arrow.right",
                            action: { confirmSignOut = true }
                        )
                    }
                case .signedOut:
                    Section {
                        SignInPrompt(title: l10n[.notSignedIn], detail: l10n[.notSignedInDetail])
                    }
                case .expired:
                    Section {
                        SignInPrompt(title: l10n[.sessionExpired], detail: l10n[.sessionExpiredDetail])
                    }
                }
            }

            Section {
                InfoLabel(title: l10n[.privacySection],
                          detail: l10n[status.account.usesApiKey ? .privacyDetailLocal : .privacyDetail])
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n[.sectionAccount])
        .confirmationDialog(
            l10n[status.account.usesApiKey ? .apiKeyRemoveConfirmTitle : .signOutConfirmTitle],
            isPresented: $confirmSignOut,
            titleVisibility: .visible
        ) {
            Button(l10n[status.account.usesApiKey ? .apiKeyRemove : .signOut], role: .destructive) { store.signOut() }
            Button(l10n[.cancel], role: .cancel) {}
        } message: {
            Text(l10n[status.account.usesApiKey ? .apiKeyRemoveConfirmDetail : .signOutConfirmDetail])
        }
    }
}

private struct IdentityRow: View {
    let identity: AccountIdentity?

    @Environment(\.l10n) private var l10n

    private var initials: String? {
        guard let identity else { return nil }
        let words = identity.name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        if !letters.isEmpty { return letters.joined() }
        if let first = identity.email.first { return String(first).uppercased() }
        return nil
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.quaternary)
                if let initials {
                    Text(initials)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "person")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if let identity {
                    Text(identity.name.isEmpty ? identity.email : identity.name)
                        .font(.headline)
                    if !identity.name.isEmpty, !identity.email.isEmpty {
                        Text(identity.email)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                } else {
                    Text(l10n[.identityUnavailable])
                        .font(.headline)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text(l10n[.signedInLabel])
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SignInPrompt: View {
    let title: String
    let detail: String

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            TitleDetail(title, detail: detail)
            Spacer(minLength: 16)
            Button(l10n[.signIn]) { store.perform(.beginSignIn) }
                .buttonStyle(.borderedProminent)
                .disabled(store.isBusy(.beginSignIn))
        }
        .padding(.vertical, 4)
    }
}

/// Local builds have no account: the credential is the user's own AI Gateway key.
private struct ApiKeySection: View {
    let isSaved: Bool
    @Binding var confirmRemove: Bool

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n
    @State private var key = ""

    private static let keysURL = URL(string: "https://vercel.com/ai-gateway")!

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedKey.isEmpty else { return }
        store.perform(.setApiKey(trimmedKey))
        // The field never holds a key longer than the request that saves it.
        key = ""
    }

    @ViewBuilder private var modelRow: some View {
        if let model = store.status?.account.model {
            HStack(spacing: 16) {
                TitleDetail(l10n[.apiKeyModel], detail: l10n[.apiKeyModelDetail])
                Spacer(minLength: 8)
                Text(model)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        if isSaved {
            Section {
                HStack(spacing: 16) {
                    TitleDetail(l10n[.apiKeyTitle], detail: l10n[.apiKeySavedDetail])
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(l10n[.apiKeySaved])
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                modelRow
            }
            Section {
                ActionRow(
                    title: l10n[.apiKeyRemove],
                    detail: nil,
                    systemImage: "key.slash",
                    action: { confirmRemove = true }
                )
            }
        } else {
            Section {
                TitleDetail(l10n[.apiKeyTitle], detail: l10n[.apiKeyDetail])
                    .padding(.vertical, 4)
                HStack(spacing: 8) {
                    SecureField(l10n[.apiKeyTitle], text: $key, prompt: Text(l10n[.apiKeyPlaceholder]))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button(l10n[.save], action: save)
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedKey.isEmpty || store.isBusy(.setApiKey("")))
                }
                Link(l10n[.apiKeyGet], destination: Self.keysURL)
            }
            Section { modelRow }
        }
    }
}
