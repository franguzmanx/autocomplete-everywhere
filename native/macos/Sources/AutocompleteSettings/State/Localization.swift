import Foundation
import SwiftUI

/// Every user-visible string. English is the default; Spanish is complete. The active language is a
/// projection of `ProductStatus.uiLanguage` and never stored locally.
enum L10nKey: String, CaseIterable, Sendable {
    // Sidebar and window
    case windowTitle, informationAbout, preferencesGroup, systemGroup, shortcutValidation
    case sectionContext
    case sectionGeneral, sectionWriting, sectionRewrites, sectionApplications, sectionLibrary, sectionAccount

    // Connection
    case connecting, connectionFailedTitle, connectionFailedDetail, retry

    // Status conditions
    case statusReady
    case statusReadyAutomaticDetail, statusReadyOnRequestDetail
    case statusPaused, statusPausedUntilDetail, statusPausedDetail
    case statusSignedOut, statusSignedOutDetail
    case statusApiKeyMissing, statusApiKeyMissingDetail
    case statusExpired, statusExpiredDetail
    case statusPermissions, statusPermissionsDetail
    case statusHelperUnavailable, statusHelperUnavailableDetail
    case statusHelperStarting, statusHelperStartingDetail
    case statusOffline, statusOfflineDetail
    case statusServiceError, statusServiceErrorDetail

    // General actions
    case suggestionsActive, pauseSuggestionsHelp
    case pauseMenu, pause15, pause30, pause1h, pauseTomorrow, resume, signIn, restartHelper
    case statusSection

    // Permissions
    case permissionsSection, accessibility, accessibilityDetail, inputMonitoring, inputMonitoringDetail
    case permissionGranted, permissionRequired, permissionUnknown, openSystemSettings

    // Language
    case languageSection, appLanguage, languageEnglish, languageSpanish, languageFooter

    // Shortcut
    case resetShortcut, preparingShortcut, pressShortcut, recordNativeShortcutHelp, interactionShortcutValidation
    case acceptSuggestion, dismissSuggestion, acceptShortcutHelp, dismissShortcutHelp, shortcutActionConflict, shortcutReserved
    case shortcutSection, askForSuggestion, shortcutFooter, shortcutConflict, keyShift, keyCommand, keySpace

    // Practice
    case practiceSection, trySuggestion, trySuggestionDetail

    // Writing
    case suggestionsSection, modeLabel, modeAutomatic, modeOnRequest, modeAutomaticFooter, modeOnRequestFooter
    case timingLabel, timingInstant, timingQuick, timingBalanced, timingDeliberate
    case timingInstantFooter, timingQuickFooter, timingBalancedFooter, timingDeliberateFooter
    case appearanceSection, visibilityLabel, visibilitySubtle, visibilityClear, visibilitySubtleFooter, visibilityClearFooter
    case previewSection, previewLight, previewDark, previewDraft, previewGhost, previewFooter
    case stylesSection, stylesFooter, addStyle, noStyles, stylesSignedOut, stylesUnavailable, showInLibrary

    case personalization, enableLearning, learningHelp, learningEmpty, learningSignedOut
    case forgetPreference, resetLearning, preferenceScope, thisApplication
    case concision, formality, structure, concise, detailed, casual, neutral, formal, paragraphs, lists

    // Applications
    case applicationsFooter, applicationsEmpty, applicationsEmptyDetail, applicationsSearch, applicationsNoResults
    case activeNow, applicationToggleLabel, applicationOff

    // Library
    case add, addReference, addMemory, kindReference, kindMemory, kindStyle
    case libraryEmpty, libraryEmptyDetail, librarySignedOut, librarySignedOutDetail
    case libraryUnavailable, libraryUnavailableDetail, selectSource, filterAll, searchLibrary, allApplications
    case titleLabel, typeLabel, scopeSection, anchorLabel, anchorOptionalLabel, anchorPlaceholder, anchorFooter
    case applicationsLabel, styleApplicationsFooter, scopeApplicationsEmpty
    case expirySection, expiresToggle, expiryFooter, textSection, textFooter, characterCount
    case writingSaving, writingSaved, writingUnsaved, writingRevert
    case save, cancel, importFile, replaceFromFile, deleteSource, deleteConfirmTitle, deleteConfirmDetail, delete
    case provenanceUser, provenanceFile, provenanceFileNote, updatedOn, revisionNumber, expiresOn, expiredOn
    case styleGuidance, unsavedTitle, unsavedDetail, discard, keepEditing
    case validationTitle, validationAnchor, validationApplications, validationText, validationTooLong
    case newSourceTitle, noMatchingSources, sourceActions

    // Account
    case manageAccount, manageAccountDetail, signOut, signOutDetail, signOutConfirmTitle, signOutConfirmDetail
    case notSignedIn, notSignedInDetail, sessionExpired, sessionExpiredDetail, identityUnavailable
    case signedInLabel, privacySection, privacyDetail
    case apiKeyModel, apiKeyModelDetail
    case apiKeyAdd, apiKeyTitle, apiKeyDetail, apiKeyPlaceholder, apiKeyGet
    case apiKeySaved, apiKeySavedDetail, apiKeyRemove, apiKeyRemoveConfirmTitle, apiKeyRemoveConfirmDetail
    case privacyDetailLocal

    // Exercise
    case exerciseTitle, exerciseSourceLabel, exerciseReplyLabel
    case exerciseIdleAutomatic, exerciseIdleOnRequest, exerciseWaiting, exerciseShown, exerciseAccepted
    case exerciseDismissed, exerciseUnavailable
    case exerciseUnavailablePermissions, exerciseUnavailableSignedOut, exerciseUnavailablePaused
    case exerciseUnavailableHelper, exerciseUnavailableOffline, exerciseUnavailableAppOff
    case requestSuggestion, skipPractice, done, exerciseKeys, exerciseActivationFailed, exerciseStarting

    // Errors
    case errorTitle, transportError, malformedUpdate, ok, requestFailedGeneric

    // Rewrites (stored and sent as transforms; the user only ever sees "rewrite")
    case transformHelp, transformEnable, transformPriority, transformName, transformShortcut, transformCreate, transformNew
    case transformDelete, transformInstructions, transformConcise, transformClarity, transformReorder, transformStructure
    case transformTone, transformSave, transformDefaults, transformValidation
    case transformEdit, transformEditNamed, transformRules, transformOptionKey, transformRestoreTitle, transformRestoreDetail
    case transformExamplesKept, transformRemoveExamples, transformEditorValidation

    // Menus
    case menuHide, menuHideOthers, menuShowAll, menuQuit, menuEdit, undo, redo, cut, copy, paste, selectAll
    case menuWindow, minimize, close, quitUnsavedTitle, quitUnsavedDetail, quit
}

struct L10n: Sendable, Equatable {
    let language: AppLanguage
    let shortcut: String?
    let acceptShortcut: String
    let dismissShortcut: String

    init(language: AppLanguage, shortcut: String? = "⇧⌘Space", acceptShortcut: String = "Tab", dismissShortcut: String = "Esc") {
        self.language = language
        self.shortcut = shortcut
        self.acceptShortcut = acceptShortcut
        self.dismissShortcut = dismissShortcut
    }

    subscript(_ key: L10nKey) -> String {
        if shortcut == nil && (key == .statusReadyOnRequestDetail || key == .modeOnRequestFooter) {
            return language == .en ? "Use “Help me here” in the menu bar." : "Usa «Ayudarme aquí» en la barra de menús."
        }
        let strings = L10n.strings(for: key)
        switch language {
        case .en: return strings.en.replacingOccurrences(of: "⇧⌘Space", with: shortcut ?? "").replacingOccurrences(of: "{accept}", with: acceptShortcut).replacingOccurrences(of: "{dismiss}", with: dismissShortcut)
        case .es: return strings.es.replacingOccurrences(of: "⇧⌘Space", with: shortcut ?? "").replacingOccurrences(of: "{accept}", with: acceptShortcut).replacingOccurrences(of: "{dismiss}", with: dismissShortcut)
        }
    }

    func format(_ key: L10nKey, _ arguments: String...) -> String {
        var result = self[key]
        for (index, argument) in arguments.enumerated() {
            result = result.replacingOccurrences(of: "{\(index)}", with: argument)
        }
        return result
    }

    /// Locale for dates and numbers: the UI language combined with the user's region.
    var locale: Locale {
        var components = Locale.Components(locale: .current)
        components.languageComponents.languageCode = language == .es ? .spanish : .english
        return Locale(components: components)
    }

    func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
    }

    func shortTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
    }

    /// Time only when the date is today; otherwise date and time.
    func returnMoment(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return shortTime(date)
        }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale))
    }

    func integer(_ value: Int) -> String {
        value.formatted(IntegerFormatStyle<Int>(locale: locale))
    }

    struct Strings: Sendable, Equatable {
        let en: String
        let es: String
    }

    static func strings(for key: L10nKey) -> Strings {
        switch key {
        case .transformHelp: Strings(en: "Select text and press Option + its number to rewrite that selection in place. Typing or changing fields cancels the rewrite. Up to 2,000 characters.", es: "Selecciona texto y pulsa Opción + su número para reescribir esa selección directamente. Escribir o cambiar de campo cancela la reescritura. Hasta 2.000 caracteres.")
        case .transformEnable: Strings(en: "Enable rewrite shortcuts", es: "Activar atajos de reescritura")
        case .transformPriority: Strings(en: "Autocomplete Everywhere must also be on. These shortcuts take priority over the same Option + number shortcuts in other apps.", es: "Autocomplete Everywhere también debe estar activo. Estos atajos tienen prioridad sobre los mismos atajos Opción + número de otras apps.")
        case .transformName: Strings(en: "Name", es: "Nombre")
        case .transformShortcut: Strings(en: "Shortcut", es: "Atajo")
        case .transformCreate: Strings(en: "Create rewrite", es: "Crear reescritura")
        case .transformNew: Strings(en: "New rewrite", es: "Nueva reescritura")
        case .transformDelete: Strings(en: "Delete rewrite", es: "Eliminar reescritura")
        case .transformInstructions: Strings(en: "Custom instructions", es: "Instrucciones personalizadas")
        case .transformConcise: Strings(en: "Make more concise", es: "Hacer más conciso")
        case .transformClarity: Strings(en: "Reword for clarity", es: "Reescribir con claridad")
        case .transformReorder: Strings(en: "Reorder for readability", es: "Reordenar para facilitar la lectura")
        case .transformStructure: Strings(en: "Add structure for readability", es: "Añadir estructura para facilitar la lectura")
        case .transformTone: Strings(en: "Maintain my tone", es: "Mantener mi tono")
        case .transformSave: Strings(en: "Save rewrites", es: "Guardar reescrituras")
        case .transformDefaults: Strings(en: "Restore defaults", es: "Restaurar valores predeterminados")
        case .transformValidation: Strings(en: "Use unique shortcuts, a name, and at least one rule or instruction. Examples must contain 1–4,000 characters.", es: "Usa atajos únicos, un nombre y al menos una regla o instrucción. Los ejemplos deben tener entre 1 y 4.000 caracteres.")
        case .transformEdit: Strings(en: "Edit", es: "Editar")
        case .transformEditNamed: Strings(en: "Edit {0}", es: "Editar {0}")
        case .transformRules: Strings(en: "Rules", es: "Reglas")
        case .transformOptionKey: Strings(en: "Option {0}", es: "Opción {0}")
        case .transformRestoreTitle: Strings(en: "Restore the default rewrites?", es: "¿Restaurar las reescrituras predeterminadas?")
        case .transformRestoreDetail: Strings(en: "Your current rewrites are replaced by the defaults. The shortcuts switch stays as it is.", es: "Tus reescrituras actuales se reemplazan por las predeterminadas. El interruptor de atajos no cambia.")
        case .transformExamplesKept: Strings(en: "Saved writing examples: {0}", es: "Ejemplos de escritura guardados: {0}")
        case .transformRemoveExamples: Strings(en: "Remove examples", es: "Eliminar ejemplos")
        case .transformEditorValidation: Strings(en: "Add a name, then choose at least one rule or write instructions.", es: "Añade un nombre y elige al menos una regla o escribe instrucciones.")
        case .informationAbout: Strings(en: "About {0}", es: "Acerca de {0}")
        case .preferencesGroup: Strings(en: "Preferences", es: "Preferencias")
        case .systemGroup: Strings(en: "System", es: "Sistema")
        case .shortcutValidation: Strings(en: "Use Command, Control or Option with a letter, number, arrow or function key.", es: "Usa Comando, Control u Opción con una letra, número, flecha o tecla de función.")
        case .sourceActions: Strings(en: "Source actions", es: "Acciones de la fuente")
        case .windowTitle: Strings(en: "Autocomplete Everywhere", es: "Autocomplete Everywhere")
        case .sectionContext: Strings(en: "Context", es: "Contexto")
        case .sectionGeneral: Strings(en: "General", es: "General")
        case .sectionWriting: Strings(en: "Writing", es: "Escritura")
        case .sectionRewrites: Strings(en: "Rewrites", es: "Reescrituras")
        case .sectionApplications: Strings(en: "Applications", es: "Aplicaciones")
        case .sectionLibrary: Strings(en: "Library", es: "Biblioteca")
        case .sectionAccount: Strings(en: "Account", es: "Cuenta")

        case .connecting: Strings(en: "Connecting to Autocomplete Everywhere…", es: "Conectando con Autocomplete Everywhere…")
        case .connectionFailedTitle: Strings(en: "Autocomplete Everywhere didn't respond", es: "Autocomplete Everywhere no respondió")
        case .connectionFailedDetail: Strings(en: "Settings couldn't load the current state.", es: "Ajustes no pudo cargar el estado actual.")
        case .retry: Strings(en: "Try Again", es: "Reintentar")

        case .statusReady: Strings(en: "Ready", es: "Listo")
        case .statusReadyAutomaticDetail: Strings(en: "Automatic suggestions are on.", es: "Las sugerencias automáticas están activadas.")
        case .statusReadyOnRequestDetail: Strings(en: "Suggestions appear when you ask with ⇧⌘Space.", es: "Las sugerencias aparecen cuando las pides con ⇧⌘Espacio.")
        case .statusPaused: Strings(en: "Paused", es: "En pausa")
        case .statusPausedUntilDetail: Strings(en: "Suggestions return at {0}.", es: "Las sugerencias vuelven a las {0}.")
        case .statusPausedDetail: Strings(en: "Suggestions are off until you resume.", es: "Las sugerencias están desactivadas hasta que reanudes.")
        case .statusSignedOut: Strings(en: "Signed out", es: "Sesión cerrada")
        case .statusSignedOutDetail: Strings(en: "Sign in to read context and suggest.", es: "Inicia sesión para leer contexto y sugerir.")
        case .statusApiKeyMissing: Strings(en: "AI Gateway key needed", es: "Falta la clave de AI Gateway")
        case .statusApiKeyMissingDetail: Strings(en: "Add your own key in Account to start suggesting.", es: "Añade tu propia clave en Cuenta para empezar a sugerir.")
        case .statusExpired: Strings(en: "Session expired", es: "Sesión caducada")
        case .statusExpiredDetail: Strings(en: "Sign in again to continue.", es: "Vuelve a iniciar sesión para continuar.")
        case .statusPermissions: Strings(en: "Permission needed", es: "Falta un permiso")
        case .statusPermissionsDetail: Strings(en: "Grant Accessibility and Input Monitoring below.", es: "Concede Accesibilidad y Monitorización de entrada más abajo.")
        case .statusHelperUnavailable: Strings(en: "Capture helper isn't running", es: "El asistente de captura no está en ejecución")
        case .statusHelperUnavailableDetail: Strings(en: "Restart it to read fields and show suggestions.", es: "Reinícialo para leer campos y mostrar sugerencias.")
        case .statusHelperStarting: Strings(en: "Starting…", es: "Iniciando…")
        case .statusHelperStartingDetail: Strings(en: "The capture helper is starting.", es: "El asistente de captura se está iniciando.")
        case .statusOffline: Strings(en: "Offline", es: "Sin conexión")
        case .statusOfflineDetail: Strings(en: "Suggestions resume when the connection returns.", es: "Las sugerencias vuelven cuando se recupere la conexión.")
        case .statusServiceError: Strings(en: "Last suggestion failed", es: "Falló la última sugerencia")
        case .statusServiceErrorDetail: Strings(en: "Autocomplete Everywhere remains on. You can request another suggestion.", es: "Autocomplete Everywhere sigue activo. Podés pedir otra sugerencia.")

        case .suggestionsActive: Strings(en: "Active", es: "Activo")
        case .pauseSuggestionsHelp: Strings(en: "Pause suggestions temporarily. They resume automatically when the selected time ends.", es: "Pausa las sugerencias temporalmente. Se reanudan automáticamente al terminar el tiempo elegido.")
        case .pauseMenu: Strings(en: "Pause", es: "Pausar")
        case .pause15: Strings(en: "For 15 minutes", es: "Durante 15 minutos")
        case .pause30: Strings(en: "For 30 minutes", es: "Durante 30 minutos")
        case .pause1h: Strings(en: "For 1 hour", es: "Durante 1 hora")
        case .pauseTomorrow: Strings(en: "Until tomorrow at 9:00", es: "Hasta mañana a las 9:00")
        case .resume: Strings(en: "Resume", es: "Reanudar")
        case .signIn: Strings(en: "Sign In…", es: "Iniciar sesión…")
        case .restartHelper: Strings(en: "Restart Helper", es: "Reiniciar asistente")
        case .statusSection: Strings(en: "Status", es: "Estado")

        case .permissionsSection: Strings(en: "Permissions", es: "Permisos")
        case .accessibility: Strings(en: "Accessibility", es: "Accesibilidad")
        case .accessibilityDetail: Strings(en: "Reads the field you're writing in.", es: "Lee el campo en el que escribes.")
        case .inputMonitoring: Strings(en: "Input Monitoring", es: "Monitorización de entrada")
        case .inputMonitoringDetail: Strings(en: "Lets {accept} accept and {dismiss} dismiss.", es: "Permite aceptar con {accept} y descartar con {dismiss}.")
        case .permissionGranted: Strings(en: "Granted", es: "Concedido")
        case .permissionRequired: Strings(en: "Required", es: "Necesario")
        case .permissionUnknown: Strings(en: "Not checked yet", es: "Sin comprobar")
        case .openSystemSettings: Strings(en: "Open System Settings…", es: "Abrir Ajustes del Sistema…")

        case .languageSection: Strings(en: "Language", es: "Idioma")
        case .appLanguage: Strings(en: "App language", es: "Idioma de la app")
        case .languageEnglish: Strings(en: "English", es: "English")
        case .languageSpanish: Strings(en: "Español", es: "Español")
        case .languageFooter: Strings(en: "Menus and settings. Suggestions follow the language you're writing in.", es: "Menús y ajustes. Las sugerencias siguen el idioma en el que escribes.")

        case .shortcutSection: Strings(en: "Keyboard shortcuts", es: "Atajos de teclado")
        case .askForSuggestion: Strings(en: "Ask for a suggestion", es: "Pedir una sugerencia")
        case .pressShortcut: Strings(en: "Press shortcut…", es: "Pulsa el atajo…")
        case .resetShortcut: Strings(en: "Reset", es: "Restablecer")
        case .preparingShortcut: Strings(en: "Preparing…", es: "Preparando…")
        case .recordNativeShortcutHelp: Strings(en: "Click to record. Click outside to cancel. Reset restores the default.", es: "Haz clic para grabar. Haz clic fuera para cancelar. Restablecer recupera el valor predeterminado.")
        case .interactionShortcutValidation: Strings(en: "Use Tab, Escape, Return, Right Arrow, or a key combination with Command, Control, or Option.", es: "Usa Tab, Escape, Retorno, flecha derecha o una combinación con Comando, Control u Opción.")
        case .acceptSuggestion: Strings(en: "Accept suggestion", es: "Aceptar sugerencia")
        case .dismissSuggestion: Strings(en: "Dismiss suggestion", es: "Descartar sugerencia")
        case .acceptShortcutHelp: Strings(en: "Inserts the visible suggestion. Otherwise, the key works normally.", es: "Inserta la sugerencia visible. Si no hay una, la tecla funciona normalmente.")
        case .dismissShortcutHelp: Strings(en: "Hides the visible suggestion without changing your text.", es: "Oculta la sugerencia visible sin cambiar tu texto.")
        case .shortcutReserved: Strings(en: "Option+Tab, Option+Up/Down and Option+1–9 are reserved for Autocomplete Everywhere actions. Add another modifier or choose a different key.", es: "Opción+Tab, Opción+Arriba/Abajo y Opción+1–9 están reservados para acciones de Autocomplete Everywhere. Añade otro modificador o elige otra tecla.")
        case .shortcutActionConflict: Strings(en: "This shortcut is already used by another Autocomplete Everywhere action.", es: "Otra acción de Autocomplete Everywhere ya usa este atajo.")
        case .shortcutFooter: Strings(en: "Works in any enabled application. {accept} accepts, {dismiss} dismisses.", es: "Funciona en cualquier aplicación habilitada. {accept} acepta, {dismiss} descarta.")
        case .shortcutConflict: Strings(en: "Another app already uses ⇧⌘Space, so Autocomplete Everywhere can't register it. Use “Help me here” from the Autocomplete Everywhere menu instead.", es: "Otra app ya usa ⇧⌘Espacio, así que Autocomplete Everywhere no puede registrarlo. Usa «Ayúdame aquí» en el menú de Autocomplete Everywhere.")
        case .keyShift: Strings(en: "Shift", es: "Mayúsculas")
        case .keyCommand: Strings(en: "Command", es: "Comando")
        case .keySpace: Strings(en: "Space", es: "Espacio")

        case .practiceSection: Strings(en: "Practice", es: "Práctica")
        case .trySuggestion: Strings(en: "Try a suggestion", es: "Probar una sugerencia")
        case .trySuggestionDetail: Strings(en: "Practice accepting and dismissing in a private field.", es: "Practica aceptar y descartar en un campo privado.")

        case .suggestionsSection: Strings(en: "Suggestions", es: "Sugerencias")
        case .modeLabel: Strings(en: "Mode", es: "Modo")
        case .modeAutomatic: Strings(en: "Automatic", es: "Automático")
        case .modeOnRequest: Strings(en: "On request", es: "A petición")
        case .modeAutomaticFooter: Strings(en: "Autocomplete Everywhere offers a suggestion while you write. A pause or an excluded application always takes priority.", es: "Autocomplete Everywhere ofrece una sugerencia mientras escribes. Una pausa o una aplicación excluida siempre tienen prioridad.")
        case .modeOnRequestFooter: Strings(en: "Nothing appears until you press ⇧⌘Space or choose “Help me here”.", es: "No aparece nada hasta que pulses ⇧⌘Espacio o elijas «Ayúdame aquí».")
        case .timingLabel: Strings(en: "Timing", es: "Momento")
        case .timingInstant: Strings(en: "Instant", es: "Instantáneo")
        case .timingInstantFooter: Strings(en: "Starts as soon as your text is captured, without waiting for a pause.", es: "Empieza al capturar tu texto, sin esperar una pausa.")
        case .timingQuick: Strings(en: "Quick", es: "Rápido")
        case .timingBalanced: Strings(en: "Balanced", es: "Equilibrado")
        case .timingDeliberate: Strings(en: "Deliberate", es: "Pausado")
        case .timingQuickFooter: Strings(en: "Suggests soon after you stop typing.", es: "Sugiere poco después de que dejes de escribir.")
        case .timingBalancedFooter: Strings(en: "Waits for a natural pause before suggesting.", es: "Espera una pausa natural antes de sugerir.")
        case .timingDeliberateFooter: Strings(en: "Waits longer, so fewer suggestions interrupt you.", es: "Espera más, así te interrumpen menos sugerencias.")
        case .appearanceSection: Strings(en: "Appearance", es: "Apariencia")
        case .visibilityLabel: Strings(en: "Visibility", es: "Visibilidad")
        case .visibilitySubtle: Strings(en: "Subtle", es: "Discreta")
        case .visibilityClear: Strings(en: "Clear", es: "Clara")
        case .visibilitySubtleFooter: Strings(en: "Suggested text stays faint until you accept it.", es: "El texto sugerido se mantiene tenue hasta que lo aceptes.")
        case .visibilityClearFooter: Strings(en: "Suggested text is easier to read at a glance.", es: "El texto sugerido se lee mejor de un vistazo.")
        case .previewSection: Strings(en: "Preview", es: "Vista previa")
        case .previewLight: Strings(en: "Light", es: "Claro")
        case .previewDark: Strings(en: "Dark", es: "Oscuro")
        case .previewDraft: Strings(en: "Thanks for the update, I'll ", es: "Gracias por la actualización, te ")
        case .previewGhost: Strings(en: "send the deck by Friday.", es: "envío la presentación el viernes.")
        case .previewFooter: Strings(en: "Preview only, shown in this window. Suggestions take on the text style of the app you're writing in.", es: "Solo es una vista previa en esta ventana. Las sugerencias adoptan el estilo de texto de la app en la que escribes.")
        case .stylesSection: Strings(en: "Writing preferences", es: "Preferencias de escritura")
        case .stylesFooter: Strings(en: "Preferences are Writing style entries in your library. They apply when you write; Autocomplete Everywhere never learns them on its own.", es: "Las preferencias son entradas de tipo Estilo en tu biblioteca. Se aplican al escribir; Autocomplete Everywhere nunca las aprende por sí solo.")
        case .addStyle: Strings(en: "Add Writing Preference…", es: "Añadir preferencia de escritura…")
        case .noStyles: Strings(en: "No writing preferences yet.", es: "Aún no hay preferencias de escritura.")
        case .stylesSignedOut: Strings(en: "Sign in to add writing preferences.", es: "Inicia sesión para añadir preferencias de escritura.")
        case .stylesUnavailable: Strings(en: "The library isn't available right now.", es: "La biblioteca no está disponible ahora mismo.")
        case .showInLibrary: Strings(en: "Show in Library", es: "Mostrar en Biblioteca")

        case .applicationsFooter: Strings(en: "Turning an application off stops reading context and suggesting there, including on request. Turning a browser off applies to all of its websites. Pausing keeps these choices.", es: "Desactivar una aplicación detiene la lectura de contexto y las sugerencias en ella, también a petición. Desactivar un navegador afecta a todos sus sitios web. Pausar conserva estas elecciones.")
        case .applicationsEmpty: Strings(en: "No applications yet", es: "Aún no hay aplicaciones")
        case .applicationsEmptyDetail: Strings(en: "Open an application and write in it to add it here.", es: "Abre una aplicación y escribe en ella para que aparezca aquí.")
        case .applicationsSearch: Strings(en: "Search applications", es: "Buscar aplicaciones")
        case .applicationsNoResults: Strings(en: "No applications match.", es: "Ninguna aplicación coincide.")
        case .activeNow: Strings(en: "Active now", es: "Activa ahora")
        case .applicationToggleLabel: Strings(en: "Enable Autocomplete Everywhere in {0}", es: "Activar Autocomplete Everywhere en {0}")
        case .applicationOff: Strings(en: "Autocomplete Everywhere off", es: "Autocomplete Everywhere desactivado")

        case .add: Strings(en: "Add", es: "Añadir")
        case .addReference: Strings(en: "Reference…", es: "Referencia…")
        case .addMemory: Strings(en: "Memory…", es: "Recuerdo…")
        case .kindReference: Strings(en: "Reference", es: "Referencia")
        case .kindMemory: Strings(en: "Memory", es: "Recuerdo")
        case .kindStyle: Strings(en: "Writing style", es: "Estilo de escritura")
        case .libraryEmpty: Strings(en: "No sources yet", es: "Aún no hay fuentes")
        case .libraryEmptyDetail: Strings(en: "Add a reference when you need one. Autocomplete Everywhere also works without a library.", es: "Añade una referencia cuando la necesites. Autocomplete Everywhere también funciona sin biblioteca.")
        case .librarySignedOut: Strings(en: "Sign in to open your library", es: "Inicia sesión para abrir tu biblioteca")
        case .librarySignedOutDetail: Strings(en: "Sources stay encrypted on this Mac. Matching excerpts are sent only when a suggestion is generated.", es: "Las fuentes se guardan cifradas en este Mac. Solo se envían fragmentos relevantes al generar una sugerencia.")
        case .libraryUnavailable: Strings(en: "Library unavailable", es: "Biblioteca no disponible")
        case .libraryUnavailableDetail: Strings(en: "The local library couldn't be opened. Restart Autocomplete Everywhere to try again.", es: "No se pudo abrir la biblioteca local. Reinicia Autocomplete Everywhere para volver a intentarlo.")
        case .selectSource: Strings(en: "Select a source, or add one.", es: "Selecciona una fuente o añade una.")
        case .filterAll: Strings(en: "All", es: "Todas")
        case .searchLibrary: Strings(en: "Search sources", es: "Buscar fuentes")
        case .titleLabel: Strings(en: "Title", es: "Título")
        case .typeLabel: Strings(en: "Type", es: "Tipo")
        case .scopeSection: Strings(en: "Where it applies", es: "Dónde se aplica")
        case .anchorLabel: Strings(en: "Topic or recipient", es: "Tema o destinatario")
        case .anchorOptionalLabel: Strings(en: "Topic or recipient (optional)", es: "Tema o destinatario (opcional)")
        case .anchorPlaceholder: Strings(en: "For example: Acme project or alex@example.com", es: "Por ejemplo: proyecto Acme o alex@example.com")
        case .anchorFooter: Strings(en: "This exact phrase must appear in your draft or in a linked source. Choose a specific project or recipient; broad words match unrelated conversations.", es: "Esta frase exacta debe aparecer en tu borrador o en una fuente vinculada. Elige un proyecto o destinatario concreto; las palabras genéricas coinciden con conversaciones ajenas.")
        case .applicationsLabel: Strings(en: "Applications", es: "Aplicaciones")
        case .styleApplicationsFooter: Strings(en: "With none selected, the style applies in every enabled application.", es: "Sin ninguna seleccionada, el estilo se aplica en todas las aplicaciones habilitadas.")
        case .scopeApplicationsEmpty: Strings(en: "Open an application to make it available here.", es: "Abre una aplicación para que esté disponible aquí.")
        case .expirySection: Strings(en: "Expiry", es: "Vencimiento")
        case .expiresToggle: Strings(en: "Expires", es: "Vence")
        case .expiryFooter: Strings(en: "After this date the source is no longer used.", es: "Después de esta fecha la fuente deja de usarse.")
        case .textSection: Strings(en: "Text", es: "Texto")
        case .textFooter: Strings(en: "Up to 12,000 characters. Imports accept UTF-8 .txt and .md files up to 48 KB.", es: "Hasta 12.000 caracteres. La importación admite archivos .txt y .md en UTF-8 de hasta 48 KB.")
        case .characterCount: Strings(en: "{0} of {1} characters", es: "{0} de {1} caracteres")
        case .writingSaving: Strings(en: "Saving…", es: "Guardando…")
        case .writingSaved: Strings(en: "Saved", es: "Guardado")
        case .writingUnsaved: Strings(en: "Unsaved changes", es: "Cambios sin guardar")
        case .writingRevert: Strings(en: "Revert", es: "Revertir")
        case .personalization: Strings(en: "Personalization", es: "Personalización")
        case .enableLearning: Strings(en: "Enable learning", es: "Activar aprendizaje")
        case .learningHelp: Strings(en: "Learns writing preferences from your corrections. Turning this off keeps preferences saved but inactive.", es: "Aprende preferencias de escritura a partir de tus correcciones. Al desactivarlo, las preferencias se conservan sin aplicarse.")
        case .learningEmpty: Strings(en: "Preferences appear after repeated corrections.", es: "Las preferencias aparecen después de varias correcciones.")
        case .learningSignedOut: Strings(en: "Sign in to enable learning.", es: "Inicia sesión para activar el aprendizaje.")
        case .forgetPreference: Strings(en: "Forget", es: "Olvidar")
        case .resetLearning: Strings(en: "Reset learning", es: "Restablecer aprendizaje")
        case .preferenceScope: Strings(en: "Use in", es: "Usar en")
        case .allApplications: Strings(en: "All applications", es: "Todas las aplicaciones")
        case .thisApplication: Strings(en: "This application", es: "Esta aplicación")
        case .concision: Strings(en: "Length", es: "Extensión")
        case .formality: Strings(en: "Tone", es: "Tono")
        case .structure: Strings(en: "Structure", es: "Estructura")
        case .concise: Strings(en: "Concise", es: "Conciso")
        case .detailed: Strings(en: "Detailed", es: "Detallado")
        case .casual: Strings(en: "Casual", es: "Informal")
        case .neutral: Strings(en: "Neutral", es: "Neutral")
        case .formal: Strings(en: "Formal", es: "Formal")
        case .paragraphs: Strings(en: "Paragraphs", es: "Párrafos")
        case .lists: Strings(en: "Lists", es: "Listas")
        case .save: Strings(en: "Save", es: "Guardar")
        case .cancel: Strings(en: "Cancel", es: "Cancelar")
        case .importFile: Strings(en: "Import File…", es: "Importar archivo…")
        case .replaceFromFile: Strings(en: "Replace from File…", es: "Reemplazar desde archivo…")
        case .deleteSource: Strings(en: "Delete…", es: "Eliminar…")
        case .deleteConfirmTitle: Strings(en: "Delete “{0}”?", es: "¿Eliminar «{0}»?")
        case .deleteConfirmDetail: Strings(en: "Suggestions that depended on this source will stop using it. This can't be undone.", es: "Las sugerencias que dependían de esta fuente dejarán de usarla. No se puede deshacer.")
        case .delete: Strings(en: "Delete", es: "Eliminar")
        case .provenanceUser: Strings(en: "Added by you", es: "Añadida por ti")
        case .provenanceFile: Strings(en: "Imported copy of {0}", es: "Copia importada de {0}")
        case .provenanceFileNote: Strings(en: "doesn't update on its own", es: "no se actualiza sola")
        case .updatedOn: Strings(en: "Updated {0}", es: "Actualizada el {0}")
        case .revisionNumber: Strings(en: "Revision {0}", es: "Revisión {0}")
        case .expiresOn: Strings(en: "Expires {0}", es: "Vence el {0}")
        case .expiredOn: Strings(en: "Expired {0}", es: "Venció el {0}")
        case .styleGuidance: Strings(en: "Use a writing style for preferences such as brevity or tone. Keep prices, personal details and other facts in scoped references or memories.", es: "Usa un estilo de escritura para preferencias como brevedad o tono. Guarda precios, datos personales y otros hechos en referencias o recuerdos con ámbito.")
        case .unsavedTitle: Strings(en: "Discard unsaved changes?", es: "¿Descartar los cambios sin guardar?")
        case .unsavedDetail: Strings(en: "Your changes haven't been saved.", es: "Tus cambios no se han guardado.")
        case .discard: Strings(en: "Discard Changes", es: "Descartar cambios")
        case .keepEditing: Strings(en: "Keep Editing", es: "Seguir editando")
        case .validationTitle: Strings(en: "Add a title.", es: "Añade un título.")
        case .validationAnchor: Strings(en: "Add a topic or recipient with at least 3 letters or digits in a row.", es: "Añade un tema o destinatario con al menos 3 letras o cifras seguidas.")
        case .validationApplications: Strings(en: "Select at least one application.", es: "Selecciona al menos una aplicación.")
        case .validationText: Strings(en: "Add the source text, or import a file.", es: "Añade el texto de la fuente o importa un archivo.")
        case .validationTooLong: Strings(en: "The text is longer than 12,000 characters.", es: "El texto supera los 12.000 caracteres.")
        case .newSourceTitle: Strings(en: "New source", es: "Nueva fuente")
        case .noMatchingSources: Strings(en: "No sources match.", es: "Ninguna fuente coincide.")

        case .manageAccount: Strings(en: "Manage Account…", es: "Gestionar cuenta…")
        case .manageAccountDetail: Strings(en: "Email, security and account deletion open in your browser.", es: "Correo, seguridad y eliminación de la cuenta se abren en tu navegador.")
        case .signOut: Strings(en: "Sign Out…", es: "Cerrar sesión…")
        case .signOutDetail: Strings(en: "Stops reading context and suggesting on this Mac.", es: "Deja de leer contexto y de sugerir en este Mac.")
        case .signOutConfirmTitle: Strings(en: "Sign out of Autocomplete Everywhere?", es: "¿Cerrar la sesión de Autocomplete Everywhere?")
        case .signOutConfirmDetail: Strings(en: "Suggestions stop until you sign in again. Your library stays encrypted on this Mac.", es: "Las sugerencias se detienen hasta que vuelvas a iniciar sesión. Tu biblioteca sigue cifrada en este Mac.")
        case .notSignedIn: Strings(en: "Not signed in", es: "Sin sesión iniciada")
        case .notSignedInDetail: Strings(en: "Your browser handles sign-in. Credentials never enter this window.", es: "Tu navegador gestiona el inicio de sesión. Las credenciales nunca entran en esta ventana.")
        case .sessionExpired: Strings(en: "Session expired", es: "Sesión caducada")
        case .sessionExpiredDetail: Strings(en: "Sign in again to continue. Your settings and library are kept.", es: "Vuelve a iniciar sesión para continuar. Tus ajustes y biblioteca se conservan.")
        case .identityUnavailable: Strings(en: "Account details unavailable", es: "Datos de la cuenta no disponibles")
        case .signedInLabel: Strings(en: "Signed in", es: "Sesión iniciada")
        case .apiKeyAdd: Strings(en: "Add Key…", es: "Añadir clave…")
        case .apiKeyTitle: Strings(en: "Vercel AI Gateway key", es: "Clave de Vercel AI Gateway")
        case .apiKeyDetail: Strings(en: "Suggestions use your own key. It is stored encrypted on this Mac and sent only to AI Gateway.", es: "Las sugerencias usan tu propia clave. Se guarda cifrada en este Mac y solo se envía a AI Gateway.")
        case .apiKeyPlaceholder: Strings(en: "Paste your key", es: "Pega tu clave")
        case .apiKeyGet: Strings(en: "Get a key…", es: "Obtener una clave…")
        case .apiKeyModel: Strings(en: "Model", es: "Modelo")
        case .apiKeyModelDetail: Strings(en: "Through Vercel AI Gateway.", es: "A través de Vercel AI Gateway.")
        case .apiKeySaved: Strings(en: "Key saved", es: "Clave guardada")
        case .apiKeySavedDetail: Strings(en: "Suggestions run on this Mac with your AI Gateway key.", es: "Las sugerencias se ejecutan en este Mac con tu clave de AI Gateway.")
        case .apiKeyRemove: Strings(en: "Remove Key…", es: "Quitar clave…")
        case .apiKeyRemoveConfirmTitle: Strings(en: "Remove your AI Gateway key?", es: "¿Quitar tu clave de AI Gateway?")
        case .apiKeyRemoveConfirmDetail: Strings(en: "Suggestions stop until you add a key again. Your settings are kept.", es: "Las sugerencias se detienen hasta que añadas una clave. Tus ajustes se conservan.")
        case .privacyDetailLocal: Strings(en: "There is no account and no server of ours. When a suggestion is generated, your draft and the visible context go from this Mac to Vercel AI Gateway with your key. Nothing is learned automatically.", es: "No hay cuenta ni servidor nuestro. Al generar una sugerencia, tu borrador y el contexto visible van de este Mac a Vercel AI Gateway con tu clave. Nada se aprende automáticamente.")
        case .privacySection: Strings(en: "Your data", es: "Tus datos")
        case .privacyDetail: Strings(en: "Your library is encrypted on this Mac. When a suggestion is generated, your draft, the visible context and matching excerpts are sent to the generation service. Nothing is learned automatically; you add and edit sources yourself.", es: "Tu biblioteca está cifrada en este Mac. Al generar una sugerencia, tu borrador, el contexto visible y los fragmentos relevantes se envían al servicio de generación. Nada se aprende automáticamente; tú añades y editas las fuentes.")

        case .exerciseTitle: Strings(en: "Try a suggestion", es: "Probar una sugerencia")
        case .exerciseSourceLabel: Strings(en: "Message received", es: "Mensaje recibido")
        case .exerciseReplyLabel: Strings(en: "Your reply", es: "Tu respuesta")
        case .exerciseIdleAutomatic: Strings(en: "Start typing a reply. A suggestion appears as you write.", es: "Empieza a escribir una respuesta. Aparecerá una sugerencia mientras escribes.")
        case .exerciseIdleOnRequest: Strings(en: "Automatic suggestions are off. Type a few words, then request a suggestion.", es: "Las sugerencias automáticas están desactivadas. Escribe unas palabras y pide una sugerencia.")
        case .exerciseWaiting: Strings(en: "Looking for a suggestion…", es: "Buscando una sugerencia…")
        case .exerciseShown: Strings(en: "Suggestion shown. Press {accept} to accept or {dismiss} to dismiss.", es: "Sugerencia mostrada. Pulsa {accept} para aceptar o {dismiss} para descartar.")
        case .exerciseAccepted: Strings(en: "Accepted. That's exactly how it works where you write.", es: "Aceptada. Así funciona exactamente donde escribes.")
        case .exerciseDismissed: Strings(en: "Dismissed. Keep writing to try again.", es: "Descartada. Sigue escribiendo para probar de nuevo.")
        case .exerciseUnavailable: Strings(en: "Suggestions aren't available right now.", es: "Las sugerencias no están disponibles ahora mismo.")
        case .exerciseUnavailablePermissions: Strings(en: "Grant Accessibility and Input Monitoring in General first.", es: "Concede primero Accesibilidad y Monitorización de entrada en General.")
        case .exerciseUnavailableSignedOut: Strings(en: "Sign in first.", es: "Inicia sesión primero.")
        case .exerciseUnavailablePaused: Strings(en: "Autocomplete Everywhere is paused. Resume it in General.", es: "Autocomplete Everywhere está en pausa. Reanúdalo en General.")
        case .exerciseUnavailableHelper: Strings(en: "The capture helper isn't running.", es: "El asistente de captura no está en ejecución.")
        case .exerciseUnavailableOffline: Strings(en: "The connection is offline.", es: "No hay conexión.")
        case .exerciseUnavailableAppOff: Strings(en: "Autocomplete Everywhere is turned off for this window in Applications.", es: "Autocomplete Everywhere está desactivado para esta ventana en Aplicaciones.")
        case .requestSuggestion: Strings(en: "Request Suggestion", es: "Pedir sugerencia")
        case .skipPractice: Strings(en: "Skip", es: "Omitir")
        case .done: Strings(en: "Done", es: "Listo")
        case .exerciseKeys: Strings(en: "{accept} accepts · {dismiss} dismisses", es: "{accept} acepta · {dismiss} descarta")
        case .exerciseActivationFailed: Strings(en: "Practice couldn't start: {0}", es: "La práctica no pudo empezar: {0}")
        case .exerciseStarting: Strings(en: "Preparing practice…", es: "Preparando la práctica…")

        case .errorTitle: Strings(en: "Couldn't complete this change", es: "No se pudo completar el cambio")
        case .transportError: Strings(en: "Autocomplete Everywhere isn't responding. Restart Autocomplete Everywhere and try again.", es: "Autocomplete Everywhere no responde. Reinicia Autocomplete Everywhere y vuelve a intentarlo.")
        case .malformedUpdate: Strings(en: "An update from Autocomplete Everywhere couldn't be read, so some information may be out of date.", es: "No se pudo leer una actualización de Autocomplete Everywhere, así que parte de la información puede estar desactualizada.")
        case .ok: Strings(en: "OK", es: "Aceptar")
        case .requestFailedGeneric: Strings(en: "The request failed.", es: "La solicitud falló.")

        case .menuHide: Strings(en: "Hide {0}", es: "Ocultar {0}")
        case .menuHideOthers: Strings(en: "Hide Others", es: "Ocultar otros")
        case .menuShowAll: Strings(en: "Show All", es: "Mostrar todo")
        case .menuQuit: Strings(en: "Quit {0}", es: "Salir de {0}")
        case .menuEdit: Strings(en: "Edit", es: "Edición")
        case .undo: Strings(en: "Undo", es: "Deshacer")
        case .redo: Strings(en: "Redo", es: "Rehacer")
        case .cut: Strings(en: "Cut", es: "Cortar")
        case .copy: Strings(en: "Copy", es: "Copiar")
        case .paste: Strings(en: "Paste", es: "Pegar")
        case .selectAll: Strings(en: "Select All", es: "Seleccionar todo")
        case .menuWindow: Strings(en: "Window", es: "Ventana")
        case .minimize: Strings(en: "Minimize", es: "Minimizar")
        case .close: Strings(en: "Close", es: "Cerrar")
        case .quitUnsavedTitle: Strings(en: "Quit with unsaved changes?", es: "¿Salir con cambios sin guardar?")
        case .quitUnsavedDetail: Strings(en: "Your unsaved changes will be lost.", es: "Se perderán tus cambios sin guardar.")
        case .quit: Strings(en: "Quit", es: "Salir")
        }
    }
}

// MARK: - Convenience lookups

extension L10n {
    func name(for language: AppLanguage) -> String {
        switch language {
        case .en: self[.languageEnglish]
        case .es: self[.languageSpanish]
        }
    }

    func name(for kind: LibraryKind) -> String {
        switch kind {
        case .knowledge: self[.kindReference]
        case .memory: self[.kindMemory]
        case .style: self[.kindStyle]
        }
    }

    func name(for timing: SuggestionTiming) -> String {
        switch timing {
        case .instant: self[.timingInstant]
        case .quick: self[.timingQuick]
        case .balanced: self[.timingBalanced]
        case .deliberate: self[.timingDeliberate]
        }
    }

    func footer(for timing: SuggestionTiming) -> String {
        switch timing {
        case .instant: self[.timingInstantFooter]
        case .quick: self[.timingQuickFooter]
        case .balanced: self[.timingBalancedFooter]
        case .deliberate: self[.timingDeliberateFooter]
        }
    }

    func name(for visibility: SuggestionVisibility) -> String {
        switch visibility {
        case .subtle: self[.visibilitySubtle]
        case .clear: self[.visibilityClear]
        }
    }

    func footer(for visibility: SuggestionVisibility) -> String {
        switch visibility {
        case .subtle: self[.visibilitySubtleFooter]
        case .clear: self[.visibilityClearFooter]
        }
    }

    func name(for duration: PauseDuration) -> String {
        switch duration {
        case .fifteenMinutes: self[.pause15]
        case .thirtyMinutes: self[.pause30]
        case .oneHour: self[.pause1h]
        case .tomorrow: self[.pauseTomorrow]
        }
    }

    func name(for permission: PermissionState) -> String {
        switch permission {
        case .granted: self[.permissionGranted]
        case .required: self[.permissionRequired]
        case .unknown: self[.permissionUnknown]
        }
    }
}

// MARK: - Environment

private struct L10nEnvironmentKey: EnvironmentKey {
    static let defaultValue = L10n(language: .en)
}

extension EnvironmentValues {
    var l10n: L10n {
        get { self[L10nEnvironmentKey.self] }
        set { self[L10nEnvironmentKey.self] = newValue }
    }
}
