import SwiftUI

struct GeneralView: View {
    let status: ProductStatus

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    private var condition: ProductCondition { ProductCondition(status: status) }

    private var languageSelection: Binding<AppLanguage> {
        Binding(
            get: { store.language },
            set: { store.setLanguage($0) }
        )
    }

    /// A status row only when the user can or must do something about it. A healthy product
    /// shows its controls, not a headline.
    private var needsAttention: Bool { condition.tone != .positive }

    var body: some View {
        Form {
            Section(l10n[.suggestionsSection]) {
                if needsAttention {
                    StatusRow(condition: condition) { recovery }
                }
                // The only pause/resume control in the window, whatever else needs attention.
                SettingsRow(title: condition.tone == .positive ? l10n[.suggestionsActive] : l10n[.suggestionsSection], detail: l10n[.pauseSuggestionsHelp]) {
                    if store.isBusy(.resume) || store.isBusy(.pause(.oneHour)) {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if status.enabled {
                        Menu {
                            ForEach(PauseDuration.allCases) { duration in
                                Button(l10n.name(for: duration)) {
                                    store.perform(.pause(duration))
                                }
                            }
                        } label: {
                            Text(l10n[.pauseMenu])
                        }
                        .fixedSize()
                    } else {
                        Button(l10n[.resume]) { store.perform(.resume) }
                            .disabled(store.isBusy(.resume))
                    }
                }
            }

            Section(l10n[.shortcutSection]) {
                SettingsRow(title: l10n[.askForSuggestion], detail: l10n[.shortcutFooter]) {
                    SuggestionShortcutRecorder()
                }
                SettingsRow(title: l10n[.acceptSuggestion], detail: l10n[.acceptShortcutHelp]) {
                    SuggestionShortcutRecorder(kind: .accept)
                }
                SettingsRow(title: l10n[.dismissSuggestion], detail: l10n[.dismissShortcutHelp]) {
                    SuggestionShortcutRecorder(kind: .dismiss)
                }
                if !status.shortcutRegistered {
                    InlineError(message: l10n[.shortcutConflict])
                }
                ActionRow(title: l10n[.trySuggestion], detail: l10n[.trySuggestionDetail],
                          systemImage: "chevron.right", action: { store.openExercise() })
            }

            Section(l10n[.systemGroup]) {
                SettingsRow(title: l10n[.appLanguage], detail: l10n[.languageFooter]) {
                    Picker(l10n[.appLanguage], selection: languageSelection) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(l10n.name(for: language)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if status.permissions.allGranted {
                    SettingsRow(title: l10n[.permissionsSection], detail:
                        l10n[.accessibility] + ": " + l10n[.accessibilityDetail] + "\n\n" +
                        l10n[.inputMonitoring] + ": " + l10n[.inputMonitoringDetail]) {
                        Label(l10n[.permissionGranted], systemImage: "checkmark")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    PermissionRow(kind: .accessibility, state: status.permissions.accessibility,
                                  title: l10n[.accessibility], detail: l10n[.accessibilityDetail])
                    PermissionRow(kind: .inputMonitoring, state: status.permissions.inputMonitoring,
                                  title: l10n[.inputMonitoring], detail: l10n[.inputMonitoringDetail])
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(l10n[.sectionGeneral])
    }

    /// The one action that resolves the current condition. A pause is resumed from the row below,
    /// missing permissions are granted from the System rows, and offline or service errors clear
    /// on their own.
    @ViewBuilder
    private var recovery: some View {
        switch condition {
        case .apiKeyMissing:
            Button(l10n[.apiKeyAdd]) { store.signIn() }
        case .signedOut, .sessionExpired:
            Button(l10n[.signIn]) { store.signIn() }
                .disabled(store.isBusy(.beginSignIn))
        case .helperUnavailable:
            Button(l10n[.restartHelper]) { store.perform(.restartHelper) }
                .disabled(store.isBusy(.restartHelper))
        case .helperStarting:
            ProgressView()
                .controlSize(.small)
        case .paused, .permissionsRequired, .offline, .serviceError, .readyAutomatic, .readyOnRequest:
            EmptyView()
        }
    }
}

private struct PermissionRow: View {
    let kind: MacPermissionKind
    let state: PermissionState
    let title: String
    let detail: String

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(l10n.name(for: state))
                    .foregroundStyle(state == .granted ? .secondary : .primary)
                if state != .granted {
                    Button(l10n[.openSystemSettings]) {
                        store.perform(.openMacPermissionSettings(kind))
                    }
                }
            }
        } label: {
            TitleDetail(title, detail: detail)
        }
    }
}
