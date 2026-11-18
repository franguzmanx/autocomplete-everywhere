import SwiftUI

struct WritingView: View {
    let status: ProductStatus

    @Environment(SettingsStore.self) private var store
    @Environment(\.l10n) private var l10n

    private var automatic: Binding<Bool> {
        Binding(get: { store.writing.automaticSuggestions }, set: { store.setAutomatic($0) })
    }

    private var timing: Binding<SuggestionTiming> {
        Binding(get: { store.writing.timing }, set: { store.setTiming($0) })
    }

    private var visibility: Binding<SuggestionVisibility> {
        Binding(get: { store.writing.visibility }, set: { store.setVisibility($0) })
    }

    var body: some View {
        Form {
            Section(l10n[.suggestionsSection]) {
                SettingsRow(title: l10n[.modeLabel], detail:
                    store.writing.automaticSuggestions ? l10n[.modeAutomaticFooter] : l10n[.modeOnRequestFooter]) {
                    Picker(l10n[.modeLabel], selection: automatic) {
                        Text(l10n[.modeAutomatic]).tag(true)
                        Text(l10n[.modeOnRequest]).tag(false)
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsRow(title: l10n[.timingLabel], detail: l10n.footer(for: store.writing.timing)) {
                    Picker(l10n[.timingLabel], selection: timing) {
                        ForEach(SuggestionTiming.allCases) { option in
                            Text(l10n.name(for: option)).tag(option)
                        }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(!store.writing.automaticSuggestions)
                }

            }

            Section {
                SettingsRow(title: l10n[.visibilityLabel], detail: l10n.footer(for: store.writing.visibility)) {
                    Picker(l10n[.visibilityLabel], selection: visibility) {
                        ForEach(SuggestionVisibility.allCases) { option in
                            Text(l10n.name(for: option)).tag(option)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                HStack(spacing: 16) {
                    GhostPreview(scheme: .light, visibility: store.writing.visibility)
                    GhostPreview(scheme: .dark, visibility: store.writing.visibility)
                }
                .padding(.vertical, 4)
            } header: {
                Text(l10n[.appearanceSection])
            }

            Section(l10n[.personalization]) {
                SettingsRow(title: l10n[.enableLearning], detail: l10n[.learningHelp]) {
                    Toggle(l10n[.enableLearning], isOn: Binding(
                        get: { store.writing.personalization.enabled }, set: { store.setLearningEnabled($0) }))
                        .labelsHidden()
                        .disabled(!status.isSignedIn)
                }
                if !status.isSignedIn {
                    Text(l10n[.learningSignedOut]).foregroundStyle(.secondary)
                } else {
                    ForEach(store.displayedPreferences) { preference in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(preferenceTitle(preference.dimension))
                                Spacer()
                                Picker(preferenceTitle(preference.dimension), selection: Binding(
                                    get: { preference.value }, set: { store.editPreference(id: preference.id, value: $0) })) {
                                    ForEach(preference.dimension.values, id: \.self) { value in
                                        Text(preferenceValue(value)).tag(value)
                                    }
                                }.labelsHidden().fixedSize()
                                Button(l10n[.forgetPreference]) { store.forgetPreference(preference.id) }
                            }
                            Picker(l10n[.preferenceScope], selection: Binding(
                                get: { preference.appId == nil }, set: { store.editPreference(id: preference.id, global: $0) })) {
                                Text(preferenceApplication(preference)).tag(false)
                                Text(l10n[.allApplications]).tag(true)
                            }
                            .fixedSize()
                        }.padding(.vertical, 4)
                    }
                    if store.displayedPreferences.isEmpty {
                        Text(l10n[.learningEmpty]).foregroundStyle(.secondary)
                    }
                    Button(l10n[.resetLearning], role: .destructive) { store.resetLearning() }
                        .disabled(store.writing.personalization.reset)
                }
            }

        }
        .disabled(store.writingSaving)
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                if store.writingSaving {
                    ProgressView().controlSize(.small)
                    Text(l10n[.writingSaving]).foregroundStyle(.secondary)
                } else if store.writingSaved {
                    Label(l10n[.writingSaved], systemImage: "checkmark")
                        .foregroundStyle(.secondary)
                } else if store.hasUnsavedWritingChanges {
                    Text(l10n[.writingUnsaved]).foregroundStyle(.secondary)
                }
                Spacer()
                Button(l10n[.writingRevert]) { store.discardWritingChanges() }
                    .disabled(!store.hasUnsavedWritingChanges || store.writingSaving)
                Button(l10n[.save]) { store.saveWriting() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!store.hasUnsavedWritingChanges || store.writingSaving)
            }
            .controlSize(.regular)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .navigationTitle(l10n[.sectionWriting])
    }

    private func preferenceApplication(_ preference: StylePreference) -> String {
        guard let id = preference.appId else { return l10n[.thisApplication] }
        return status.applications.first(where: { $0.id == id })?.name ?? id
    }

    private func preferenceTitle(_ dimension: PreferenceDimension) -> String {
        switch dimension {
        case .concision: l10n[.concision]
        case .formality: l10n[.formality]
        case .structure: l10n[.structure]
        }
    }

    private func preferenceValue(_ value: String) -> String {
        value == "balanced" ? l10n[.timingBalanced] : l10n[L10nKey(rawValue: value) ?? .neutral]
    }


}

/// Local, explicit light/dark rendering of suggested text. This never reflects the host app.
private struct GhostPreview: View {
    let scheme: ColorScheme
    let visibility: SuggestionVisibility

    @Environment(\.l10n) private var l10n

    private var background: Color {
        scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : .white
    }

    private var foreground: Color {
        scheme == .dark ? Color(white: 0.92) : Color(white: 0.1)
    }

    private var ghost: Color {
        foreground.opacity(visibility == .subtle ? 0.30 : 0.45)
    }

    private var border: Color {
        scheme == .dark ? Color(white: 1, opacity: 0.12) : Color(white: 0, opacity: 0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scheme == .dark ? l10n[.previewDark] : l10n[.previewLight])
                .font(.caption)
                .foregroundStyle(.secondary)
            (Text(l10n[.previewDraft]).foregroundStyle(foreground)
                + Text(l10n[.previewGhost]).foregroundStyle(ghost))
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(border)
                )
        }
        .accessibilityElement(children: .combine)
    }
}
