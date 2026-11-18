import AppKit
import Foundation
import Observation

enum SidebarSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case writing
    case rewrites
    case context
    case applications
    case library
    case account

    /// Destinations listed in the sidebar, top to bottom. Account is anchored separately at the
    /// bottom and Library stays hidden while it is deferred.
    static let primary: [SidebarSection] = [.general, .writing, .rewrites, .applications, .context]

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .writing: "pencil"
        case .rewrites: "wand.and.stars"
        case .context: "rectangle.stack"
        case .applications: "square.grid.2x2"
        case .library: "book"
        case .account: "person.circle"
        }
    }

    var titleKey: L10nKey {
        switch self {
        case .general: .sectionGeneral
        case .writing: .sectionWriting
        case .rewrites: .sectionRewrites
        case .context: .sectionContext
        case .applications: .sectionApplications
        case .library: .sectionLibrary
        case .account: .sectionAccount
        }
    }
}

enum NavigationIntent: Equatable, Sendable {
    case section(SidebarSection)
    case openEntry(String)
    case newEntry(LibraryKind)
    case closeEditor
}

struct PresentedAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

struct ApplicationRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isObserved: Bool
    let isCurrent: Bool
}

enum TransportClosed: Error {
    case closed
}

struct WritingPreferences: Codable, Equatable, Sendable {
    var automaticSuggestions: Bool
    var timing: SuggestionTiming
    var visibility: SuggestionVisibility
    var personalization: PersonalizationEdit
}

/// Single source of truth for the window. Every value shown is a projection of the parent's state;
/// Writing is staged locally until Save; other preferences apply immediately after confirmation.
@MainActor
@Observable
final class SettingsStore {
    // MARK: Connection

    private(set) var status: ProductStatus?
    private(set) var context: ContextState = .empty
    private(set) var entries: [LibraryEntry] = []
    private(set) var transformSettings: TransformSettings?
    private(set) var transformDraft: TransformSettings?
    private(set) var transformsSaving = false
    private(set) var transformsSaved = false
    private(set) var transformsError: String?
    private(set) var initialLoadFailure: String?
    private(set) var connectionClosed = false

    // MARK: Requests

    private(set) var inFlight: [String: String] = [:]
    private var continuations: [String: CheckedContinuation<JSONValue, any Error>] = [:]

    // MARK: Pending preference overlays (cleared when the parent answers)

    private(set) var pendingLanguage: AppLanguage?
    private(set) var pendingInteractionShortcuts: [SuggestionShortcutKind: SuggestionKeyBinding] = [:]
    private(set) var pendingShortcut: SuggestionKeyBinding??
    private(set) var writingDraft: WritingPreferences?
    private(set) var writingSaving = false
    private(set) var writingSaved = false
    private var accountEpoch = 0
    private(set) var pendingApplications: [String: Bool] = [:]

    // MARK: Navigation

    private(set) var selection: SidebarSection = .general
    private(set) var pendingNavigation: NavigationIntent?

    // MARK: Library editor

    var libraryDraft: LibraryDraft?
    private(set) var libraryOriginal: LibraryDraft?
    private(set) var libraryError: String?
    private(set) var libraryBusy = false
    var libraryKindFilter: LibraryKind?

    // MARK: Exercise

    private(set) var exercisePresented = false
    private(set) var exerciseStarting = false
    private(set) var exerciseError: String?

    // MARK: Presentation

    var alert: PresentedAlert?
    private var reportedMalformedMessage = false

    var onShowRequested: (@MainActor () -> Void)?
    var onConnectionClosed: (@MainActor () -> Void)?

    let applicationCatalog = ApplicationCatalog()

    private let transport: any SettingsTransport
    private let makeIdentifier: @Sendable () -> String
    private let diagnostics: @Sendable (String) -> Void

    init(
        transport: any SettingsTransport,
        makeIdentifier: @escaping @Sendable () -> String = { UUID().uuidString },
        diagnostics: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.transport = transport
        self.makeIdentifier = makeIdentifier
        self.diagnostics = diagnostics
    }

    // MARK: - Derived

    var language: AppLanguage {
        pendingLanguage ?? status?.uiLanguage ?? .en
    }

    var l10n: L10n {
        L10n(language: language, shortcut: effectiveShortcut?.display, acceptShortcut: shortcut(for: .accept)?.display ?? "Tab", dismissShortcut: shortcut(for: .dismiss)?.display ?? "Esc")
    }

    var condition: ProductCondition? {
        status.map(ProductCondition.init(status:))
    }

    var effectiveAutomatic: Bool {
        status?.automaticSuggestions ?? true
    }

    var effectiveShortcut: SuggestionKeyBinding? {
        if let pendingShortcut { return pendingShortcut }
        return status?.shortcut
    }

    func shortcut(for kind: SuggestionShortcutKind) -> SuggestionKeyBinding? {
        switch kind {
        case .request: effectiveShortcut
        case .accept: pendingInteractionShortcuts[kind] ?? status?.acceptShortcut ?? kind.defaultBinding
        case .dismiss: pendingInteractionShortcuts[kind] ?? status?.dismissShortcut ?? kind.defaultBinding
        }
    }

    func setShortcut(_ value: SuggestionKeyBinding?, for kind: SuggestionShortcutKind) {
        guard kind != .request else { setShortcut(value); return }
        guard let value = value ?? kind.defaultBinding else { return }
        pendingInteractionShortcuts[kind] = value
        Task {
            defer { pendingInteractionShortcuts[kind] = nil }
            await run(.setInteractionShortcut(kind: kind, shortcut: value))
        }
    }

    func setShortcut(_ value: SuggestionKeyBinding?) {
        pendingShortcut = .some(value)
        Task {
            defer { pendingShortcut = nil }
            await run(.setShortcut(value))
        }
    }

    var effectiveTiming: SuggestionTiming {
        status?.timing ?? .balanced
    }

    var effectiveVisibility: SuggestionVisibility {
        status?.visibility ?? .subtle
    }

    func isApplicationEnabled(_ id: String) -> Bool {
        pendingApplications[id] ?? status?.isApplicationEnabled(id) ?? true
    }

    func isBusy(_ action: SettingsAction) -> Bool {
        inFlight.values.contains(action.name)
    }

    var hasUnsavedLibraryChanges: Bool {
        guard status?.canEditLibrary == true, let libraryDraft else { return false }
        return libraryDraft != libraryOriginal
    }

    var styleEntries: [LibraryEntry] {
        entries.filter { $0.kind == .style }
    }

    /// Observed applications merged with saved preferences and the draft's scope, sorted by name.
    func applicationRows(includingDraftScope: Bool = false) -> [ApplicationRow] {
        guard let status else { return [] }
        var rows: [String: ApplicationRow] = [:]
        for application in status.applications {
            rows[application.id] = ApplicationRow(
                id: application.id,
                name: application.name,
                isObserved: true,
                isCurrent: status.currentApplication == application.id
            )
        }
        var extraIdentifiers = Array(status.apps.keys)
        if includingDraftScope, let libraryDraft {
            extraIdentifiers.append(contentsOf: libraryDraft.appIds)
        }
        for identifier in extraIdentifiers where rows[identifier] == nil {
            rows[identifier] = ApplicationRow(
                id: identifier,
                name: applicationCatalog.displayName(for: identifier) ?? identifier,
                isObserved: false,
                isCurrent: status.currentApplication == identifier
            )
        }
        return rows.values.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    // MARK: - Lifecycle

    func start() {
        transport.startReading(
            onLine: { line in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.receive(line: line) }
                }
            },
            onEnd: {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.connectionDidClose() }
                }
            }
        )
        requestInitialState()
    }

    func requestInitialState() {
        initialLoadFailure = nil
        Task {
            do {
                _ = try await request(.ready)
            } catch {
                if status == nil {
                    initialLoadFailure = message(for: error)
                }
            }
        }
    }

    func receive(line: String) {
        do {
            apply(try IncomingMessage.decode(line: line))
        } catch {
            diagnostics("decode_failed")
            if !reportedMalformedMessage {
                reportedMalformedMessage = true
                alert = PresentedAlert(title: l10n[.windowTitle], message: l10n[.malformedUpdate])
            }
        }
    }

    func apply(_ message: IncomingMessage) {
        switch message {
        case .state(let status, let entries, let transforms, let context):
            let previousAccount = self.status?.isSignedIn == true ? self.status?.account.identity?.subject : nil
            let nextAccount = status.isSignedIn ? status.account.identity?.subject : nil
            if previousAccount != nextAccount {
                accountEpoch += 1
                writingDraft = nil
                writingSaved = false
            }
            if self.status?.account.identity?.subject != status.account.identity?.subject
                || status.account.state != .signedIn {
                closeEditor()
                pendingNavigation = nil
            }
            self.context = status.isSignedIn ? context : .empty
            self.status = status
            self.transformSettings = transforms
            self.entries = status.account.state == .signedIn ? entries : []
            reconcileLibraryDraft()
        case .result(let id, let outcome):
            guard let continuation = continuations.removeValue(forKey: id) else {
                diagnostics("unknown_result")
                return
            }
            switch outcome {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let failure):
                continuation.resume(throwing: failure)
            }
        case .show:
            onShowRequested?()
        }
    }

    private func connectionDidClose() {
        connectionClosed = true
        let pending = continuations
        continuations.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: TransportClosed.closed)
        }
        onConnectionClosed?()
    }

    // MARK: - Requests

    func request(_ action: SettingsAction) async throws -> JSONValue {
        guard !connectionClosed else { throw TransportClosed.closed }
        let id = makeIdentifier()
        inFlight[id] = action.name
        defer { inFlight[id] = nil }
        do {
            try transport.send(RequestEnvelope(id: id, action: action))
        } catch {
            diagnostics("send_failed")
            throw TransportClosed.closed
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
        }
    }

    /// Fire-and-forget request whose failure is surfaced in the window alert.
    func perform(_ action: SettingsAction) {
        Task {
            await run(action)
        }
    }

    @discardableResult
    private func run(_ action: SettingsAction) async -> Bool {
        do {
            _ = try await request(action)
            return true
        } catch {
            presentError(error)
            return false
        }
    }

    func message(for error: any Error) -> String {
        if let failure = error as? RequestFailure {
            let message = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? l10n[.requestFailedGeneric] : message
        }
        return l10n[.transportError]
    }

    private func presentError(_ error: any Error) {
        guard !connectionClosed else { return }
        alert = PresentedAlert(title: l10n[.errorTitle], message: message(for: error))
    }

    // MARK: - Transforms

    var transforms: TransformSettings? { transformDraft ?? transformSettings }
    var hasUnsavedTransformChanges: Bool {
        transformDraft.map { $0 != transformSettings } ?? false
    }

    func editTransforms(_ edit: (inout TransformSettings) -> Void) {
        guard !transformsSaving, var draft = transforms else { return }
        edit(&draft)
        transformDraft = draft == transformSettings ? nil : draft
        transformsSaved = false
        transformsError = nil
    }

    func discardTransformChanges() {
        guard !transformsSaving else { return }
        transformDraft = nil
        transformsSaved = false
        transformsError = nil
    }

    func restoreTransformDefaults() {
        guard !transformsSaving else { return }
        transformsSaving = true
        transformsError = nil
        Task {
            defer { transformsSaving = false }
            do {
                let defaults = try await request(.getDefaultTransforms).decoded(as: TransformSettings.self)
                guard defaults.isValid else { throw RequestFailure(message: l10n[.transformValidation]) }
                transformDraft = defaults == transformSettings ? nil : defaults
                transformsSaved = false
            } catch { transformsError = message(for: error) }
        }
    }

    func saveTransforms() {
        guard let submitted = transforms, submitted.isValid,
              hasUnsavedTransformChanges, !transformsSaving else { return }
        transformsSaving = true
        transformsSaved = false
        transformsError = nil
        Task {
            defer { transformsSaving = false }
            do {
                let saved = try await request(.saveTransforms(submitted)).decoded(as: TransformSettings.self)
                guard saved.isValid else { throw RequestFailure(message: l10n[.transformValidation]) }
                transformSettings = saved
                transformDraft = nil
                transformsSaved = true
            } catch { transformsError = message(for: error) }
        }
    }

    // MARK: - Preferences

    var writing: WritingPreferences {
        writingDraft ?? confirmedWriting
    }

    private var confirmedWriting: WritingPreferences {
        WritingPreferences(automaticSuggestions: effectiveAutomatic, timing: effectiveTiming, visibility: effectiveVisibility,
            personalization: PersonalizationEdit(accountSubject: status?.isSignedIn == true ? status?.account.identity?.subject ?? "" : "",
                enabled: status?.personalization.enabled ?? false))
    }

    var hasUnsavedWritingChanges: Bool {
        writingDraft.map { $0 != confirmedWriting } ?? false
    }

    var hasUnsavedChanges: Bool { hasUnsavedWritingChanges || hasUnsavedLibraryChanges || hasUnsavedTransformChanges }

    private func editWriting(_ edit: (inout WritingPreferences) -> Void) {
        guard !writingSaving else { return }
        var draft = writing
        edit(&draft)
        writingDraft = draft == confirmedWriting ? nil : draft
        writingSaved = false
    }

    func setAutomatic(_ value: Bool) { editWriting { $0.automaticSuggestions = value } }
    func setTiming(_ value: SuggestionTiming) { editWriting { $0.timing = value } }
    func setVisibility(_ value: SuggestionVisibility) { editWriting { $0.visibility = value } }

    var displayedPreferences: [StylePreference] {
        let patch = writing.personalization
        guard !patch.reset else { return [] }
        return (status?.personalization.preferences ?? []).filter { !patch.forgetIds.contains($0.id) }
            .map { item in patch.edits.first(where: { $0.id == item.id }) ?? item }
    }

    func setLearningEnabled(_ enabled: Bool) {
        guard status?.isSignedIn == true else { return }
        editWriting { $0.personalization.enabled = enabled }
    }

    func editPreference(id: String, value: String? = nil, global: Bool? = nil) {
        guard var preference = displayedPreferences.first(where: { $0.id == id }), status?.isSignedIn == true else { return }
        if let value, preference.dimension.values.contains(value) { preference.value = value }
        if let global {
            preference.appId = global ? nil : (status?.personalization.preferences.first(where: { $0.id == id })?.appId
                ?? status?.currentApplication)
            guard global || preference.appId != nil else { return }
        }
        preference.origin = .explicit
        editWriting { draft in
            draft.personalization.edits.removeAll { $0.id == id }
            draft.personalization.edits.append(preference)
        }
    }

    func forgetPreference(_ id: String) {
        guard status?.isSignedIn == true, displayedPreferences.contains(where: { $0.id == id }) else { return }
        editWriting { draft in
            draft.personalization.edits.removeAll { $0.id == id }
            draft.personalization.forgetIds.append(id)
        }
    }

    func resetLearning() {
        guard status?.isSignedIn == true else { return }
        editWriting { draft in
            draft.personalization.reset = true
            draft.personalization.edits = []
            draft.personalization.forgetIds = []
        }
    }

    func discardWritingChanges() {
        guard !writingSaving else { return }
        writingDraft = nil
        writingSaved = false
    }

    func saveWriting() {
        guard status != nil, hasUnsavedWritingChanges, !writingSaving else { return }
        let submitted = writing
        let submittedAccountEpoch = accountEpoch
        writingSaving = true
        writingSaved = false
        Task {
            defer { writingSaving = false }
            do {
                let result = try await request(.saveWriting(submitted)).decoded(as: WritingSaveResult.self)
                guard result.personalization.isValid else { throw RequestFailure(message: l10n[.requestFailedGeneric]) }
                guard accountEpoch == submittedAccountEpoch,
                    confirmedWriting.personalization.accountSubject == submitted.personalization.accountSubject else { return }
            // The acknowledgement follows durable persistence. Adopt it even if the
            // accompanying state publication has not reached this process yet.
            status?.automaticSuggestions = submitted.automaticSuggestions
            status?.timing = submitted.timing
            status?.visibility = submitted.visibility
            if result.personalization.revision >= (status?.personalization.revision ?? 0) {
                status?.personalization = result.personalization
            }
            writingDraft = nil
            writingSaved = true
            } catch { presentError(error) }
        }
    }

    func setLanguage(_ value: AppLanguage) {
        pendingLanguage = value
        Task {
            defer { pendingLanguage = nil }
            await run(.setUiLanguage(value))
        }
    }

    func setApplication(_ id: String, enabled: Bool) {
        pendingApplications[id] = enabled
        Task {
            defer { pendingApplications[id] = nil }
            await run(.setAppEnabled(appId: id, enabled: enabled))
        }
    }

    func signOut() {
        closeEditor()
        perform(.signOut)
    }

    /// Hosted accounts sign in through the browser; a local build asks for the key in Account.
    func signIn() {
        if status?.account.usesApiKey == true {
            navigate(.section(.account))
        } else {
            perform(.beginSignIn)
        }
    }

    func signInTitle(for status: ProductStatus) -> String {
        l10n[status.account.usesApiKey ? .apiKeyAdd : .signIn]
    }

    // MARK: - Navigation

    func navigate(_ intent: NavigationIntent) {
        if case .section(let section) = intent, section == selection {
            return
        }
        if case .openEntry(let id) = intent, libraryDraft?.id == id, selection == .library {
            return
        }
        if hasUnsavedLibraryChanges {
            pendingNavigation = intent
            return
        }
        applyNavigation(intent)
    }

    func confirmPendingNavigation() {
        guard let intent = pendingNavigation else { return }
        pendingNavigation = nil
        closeEditor()
        applyNavigation(intent)
    }

    func cancelPendingNavigation() {
        pendingNavigation = nil
    }

    private func applyNavigation(_ intent: NavigationIntent) {
        switch intent {
        case .section(let section):
            selection = section
        case .openEntry(let id):
            selection = .library
            guard let entry = entries.first(where: { $0.id == id }) else { return }
            let draft = LibraryDraft(entry: entry)
            libraryDraft = draft
            libraryOriginal = draft
            libraryError = nil
        case .newEntry(let kind):
            selection = .library
            let draft = LibraryDraft(kind: kind)
            libraryDraft = draft
            libraryOriginal = draft
            libraryError = nil
        case .closeEditor:
            closeEditor()
        }
    }

    func closeEditor() {
        libraryDraft = nil
        libraryOriginal = nil
        libraryError = nil
    }

    // MARK: - Library

    private func reconcileLibraryDraft() {
        guard let draft = libraryDraft, let id = draft.id else { return }
        guard let entry = entries.first(where: { $0.id == id }) else {
            if draft == libraryOriginal {
                closeEditor()
            }
            return
        }
        if draft == libraryOriginal, entry.revision != draft.expectedRevision {
            let refreshed = LibraryDraft(entry: entry)
            libraryDraft = refreshed
            libraryOriginal = refreshed
        }
    }

    func saveLibraryDraft() {
        guard let draft = libraryDraft, draft.canSave, !libraryBusy else { return }
        libraryBusy = true
        libraryError = nil
        Task {
            defer { libraryBusy = false }
            do {
                let value = try await request(.librarySave(draft.input()))
                try adopt(value)
            } catch {
                libraryError = message(for: error)
            }
        }
    }

    func importLibraryDraft() {
        guard let draft = libraryDraft, draft.canImport, !libraryBusy else { return }
        libraryBusy = true
        libraryError = nil
        Task {
            defer { libraryBusy = false }
            do {
                let value = try await request(.libraryImport(draft.input(includeText: false)))
                if !value.isNull {
                    try adopt(value)
                }
            } catch {
                libraryError = message(for: error)
            }
        }
    }

    func deleteLibraryDraft() {
        guard let draft = libraryDraft, let id = draft.id, let revision = draft.expectedRevision,
              !libraryBusy else { return }
        libraryBusy = true
        libraryError = nil
        Task {
            defer { libraryBusy = false }
            do {
                _ = try await request(.libraryDelete(id: id, revision: revision))
                entries.removeAll { $0.id == id }
                closeEditor()
            } catch {
                libraryError = message(for: error)
            }
        }
    }

    private func adopt(_ value: JSONValue) throws {
        let entry: LibraryEntry
        do {
            entry = try value.decoded()
        } catch {
            diagnostics("result_decode_failed")
            throw RequestFailure(message: l10n[.malformedUpdate])
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        let draft = LibraryDraft(entry: entry)
        libraryDraft = draft
        libraryOriginal = draft
    }

    // MARK: - Exercise

    func openExercise() {
        guard !exercisePresented else { return }
        exercisePresented = true
        exerciseError = nil
        exerciseStarting = true
        Task {
            defer { exerciseStarting = false }
            do {
                _ = try await request(.setExerciseActive(true))
            } catch {
                exerciseError = message(for: error)
            }
        }
    }

    func closeExercise() {
        guard exercisePresented else { return }
        exercisePresented = false
        exerciseError = nil
        perform(.setExerciseActive(false))
    }

    func requestExerciseSuggestion() {
        perform(.requestExerciseSuggestion)
    }
}

/// Icons and names for bundle identifiers, resolved from local application bundles without
/// launching anything. Missing lookups are remembered so they aren't repeated on every render.
@MainActor
final class ApplicationCatalog {
    private var icons: [String: NSImage] = [:]
    private var names: [String: String] = [:]
    private var unresolved: Set<String> = []

    func icon(for bundleIdentifier: String) -> NSImage? {
        if let icon = icons[bundleIdentifier] { return icon }
        guard let url = applicationURL(for: bundleIdentifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleIdentifier] = icon
        return icon
    }

    func displayName(for bundleIdentifier: String) -> String? {
        if let name = names[bundleIdentifier] { return name }
        guard let url = applicationURL(for: bundleIdentifier) else { return nil }
        let bundle = Bundle(url: url)
        let candidates = [
            bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
            bundle?.infoDictionary?["CFBundleDisplayName"] as? String,
            bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
            bundle?.infoDictionary?["CFBundleName"] as? String,
            url.deletingPathExtension().lastPathComponent,
        ]
        guard let name = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) else { return nil }
        names[bundleIdentifier] = name
        return name
    }

    private func applicationURL(for bundleIdentifier: String) -> URL? {
        guard !unresolved.contains(bundleIdentifier) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            unresolved.insert(bundleIdentifier)
            return nil
        }
        return url
    }
}
