# Autocomplete Everywhere native settings implementation contract

The user authorized implementation on September 5, 2026. The initial delegated UI work is complete; the primary agent owns the integrated SwiftUI, Electron, packaging and helper changes. Preserve the dirty checkout. No commits, pushes, migrations or destructive cleanup.

## Ownership and process

- Keep native presentation, Electron services and helper capture responsibilities separate.
- Native presentation is a separate process, with a real AppKit window hosting SwiftUI. Electron owns authentication, persisted preferences, library, tray, generation and process lifetime. Native UI never stores these itself or receives credentials.
- Parent packages the executable in `Autocomplete Everywhere Settings.app` (bundle id `com.autocompletion.settings`), spawned with stdin/stdout pipes. UI exits on stdin EOF and last-window close. JSON only on stdout; never log messages, entries or account data. Normal app menus, copy/paste/undo and keyboard navigation must work.
- All outgoing requests: `{ "id": "UUID", "action": "name", "payload": value }`, one JSON line. No shell commands, file paths, URLs or dynamic IPC channel names accepted from UI.
- Incoming state: `{ "type": "state", "status": ProductStatus, "entries": LibraryEntry[] }`. Incoming result: `{ "type": "result", "id": "UUID", "ok": true, "value": valueOrNull }` or `{ "type": "result", "id": "UUID", "ok": false, "error": "safe human-readable message" }`. Incoming activation: `{ "type": "show" }`. All state/results handled on main actor. Result errors visible and busy state cleared.

## ProductStatus (JSON, timestamps milliseconds)

```
permissions: { accessibility: "unknown"|"required"|"granted", inputMonitoring: same }
account: { state: "signed_out"|"signed_in"|"expired", identity: { subject:string, name:string, email:string } | null }
enabled: boolean
pausedUntil: number|null
automaticSuggestions: boolean
uiLanguage: "en"|"es"
timing: "quick"|"balanced"|"deliberate"
visibility: "subtle"|"clear"
apps: { [bundleId]:boolean }
applications: [{id:string,name:string}]
currentApplication: string|null
helperState: "starting"|"running"|"unavailable"
shortcut: { accelerator:string, keyCode:number, modifiers:number } | null
acceptShortcut: { accelerator:string, keyCode:number, modifiers:number }
dismissShortcut: { accelerator:string, keyCode:number, modifiers:number }
shortcutRegistered: boolean
libraryAvailable: boolean
connection: "ready"|"offline"|"error"
exercise: "idle"|"waiting"|"shown"|"accepted"|"dismissed"|"unavailable"
personalization: {enabled:boolean,revision:number,preferences:StylePreference[]}
```

Read existing desktop `shared/contracts.ts` for LibraryEntry/Input: retain every field, scope, expiry, revisions, import/replace behavior. No stub source data.

## Requests

- `ready` / `resume` / `beginSignIn` / `signOut` / `openManageAccount` / `restartHelper`: null payload.
- `pause`: `"15m"|"30m"|"1h"|"tomorrow"`. Main computes next local 09:00 for tomorrow and persists absolute deadline.
- `saveWriting`: `{automaticSuggestions:boolean,timing:"quick"|"balanced"|"deliberate",visibility:"subtle"|"clear",personalization:{accountSubject:string,enabled:boolean,edits:StylePreference[],forgetIds:string[],reset:boolean}}`. Success returns `{personalization:PersonalizationSnapshot}` after persistence. Native UI strictly validates the acknowledgement; null is an error. Patches preserve automatically added entries not mentioned by the user. Account changes invalidate drafts and stale acknowledgements. Subtle uses 0.30 alpha and Clear uses 0.45 in both the local preview and helper. Validate controls as one group and preferences through the encrypted account store. A partial persistence failure is reported explicitly and never acknowledged as Saved. `setUiLanguage`: `"en"|"es"` remains immediate.
- `setInteractionShortcut`: `{action:"accept"|"dismiss", shortcut:{accelerator,keyCode,modifiers}}`. Saved locally and sent to the native event policy; never registered as a global Electron shortcut. Defaults are Tab and Escape. A visible Reset button restores the corresponding default. Exact matching and non-repeating input are required, and keys pass through when no eligible ghost is visible. All three Autocomplete Everywhere shortcuts must be distinct. Practice and permission help reflect the selected bindings.
- `setShortcutRecording`: boolean. While recording, release the global request binding and acknowledge before prompting for keys. Restore the saved binding on completion, cancellation, focus loss, or Settings exit.
- `setShortcut`: a shortcut object as above, or null to remove the shortcut. The native recorder validates chords; main registers the candidate before persisting and unregistering the previous chord. Conflict or persistence failure preserves the working shortcut. Menu and help reflect the confirmed binding.
- `setAppEnabled`: `{appId:string,enabled:boolean}`.
- `openMacPermissionSettings`: `"accessibility"|"input_monitoring"`.
- `librarySave`: existing LibraryInput. `libraryDelete`: `{id:string,revision:number}`. `libraryImport`: LibraryInput without text (main shows native file picker; result entry or null).
- `setExerciseActive`: boolean. Native UI sends true only while an explicit isolated practice sheet is open, and false on dismissal. The sheet contains only a real AppKit NSTextView with accessibility identifier `autocompletion-exercise`, and a read-only source "Can you send the deck by Friday?". Other settings editors inaccessible during exercise. Request/results go through real helper, never simulate success. Parent feeds exercise states from actual events; waiting can be dismissed/skipped, and missing permission/on-request state is explained. Include a manual `requestExerciseSuggestion` null-payload action for on-request mode.

## Design and behavior

- Native AppKit split shell (`NSSplitViewController`) with a flush `NSVisualEffectView` sidebar material, SwiftUI sidebar `List` and grouped forms, SF Symbols, native pickers/toggles/menu, and automatic appearance. Navigation stays visible; there is no sidebar collapse button or collapse behavior. Applications and Library use native NSSearchField controls beside their content, keeping the titlebar free of cross-pane search controls. The semantic window title follows selection but stays visually hidden, avoiding title overlap across the split; opaque window backing fills divider gaps while sidebar material remains translucent. Prefer system default sizing and legible labels; no giant cards or repeated subtitles. Content size 920 × 680 pt, minimum 760 × 560 pt, owned only by NSWindow. Sidebar 184–240 pt, initially 208 pt. Sections General, Writing, Rewrites, Applications; Account anchored at bottom. The sidebar contains navigation only, with no repeated readiness footer. English default; English/Español popup available even while signed out, before permissions and sign-in. No mandatory language step.
- General has three titled groups: Suggestions (status only when attention is needed, finite pause), Keyboard shortcuts (practice and native recorders for request, acceptance, and dismissal), and System (interface language and permissions). Granted permissions collapse to one row; missing permissions retain recovery actions. Secondary explanations use native hover help and VoiceOver hints, never click popovers.
- Writing groups Suggestions (Automatic/On request and timing), Appearance (Subtle/Clear with a local light/dark preview), and Personalization (opt-in learning, active preferences, Forget and Reset learning). Edits remain a local draft until Save or Command-S. A fixed native footer provides Save, Revert, and unsaved/saving/saved feedback. Save sends one validated `saveWriting` payload including the personalization patch; main acknowledges the saved snapshot. Preferences remain inspectable while learning is off, but are inactive. Only an explicit edit can change an app-scoped preference to global. Failed saves preserve edits. Drafts survive section navigation; closing or quitting asks before discarding, and cannot interrupt an in-progress save.
- Applications: searchable observed and saved apps, use NSWorkspace icons where locally available without launching apps. Switches are persistent exclusions; explain browser-wide scope. Never offer global indefinite disable.
- Library is deferred from the current MVP: hidden from navigation and Writing, no saved Library data is opened or retrieved. Existing encrypted files are preserved. The dormant implementation supports list and editor for explicit knowledge/memory/style. The native Add menu sits beside the list type filter; search stays in the toolbar. Preserve scopes, title, text, expiry, revisions and import/replace/delete. Display provenance compactly in detail. Show save errors; preserve draft until successful save, ask about unsaved edits on navigation. No editing or content shown while signed out/unavailable.
- Account: real identity only; manage account and signout. Local encryption does not mean data never leaves device: relevant excerpts are sent for generation. Do not claim sync, subscription, teams or billing. Automatic preference learning remains opt-in; implementation tests do not prove reduced real-world correction rates. Empty/recovery states real.
- All visible UI strings English and Spanish, including error labels and accessibility. Writing uses explicit Save; other controls persist via main immediately. Reflect confirmed runtime state outside the Writing preview. Preferences in UI are projections of main, not competing persistence.

## Validation

Compile the native target and test decoding/action serialization/localization where useful. Verify packaged native appearance, account and pause boundaries, real native controls and existing engine. Signing/build evidence is separate from user-visible and contextual-quality evidence.

Native settings release builds use the Xcode build system through SwiftPM so dependency resource accessors resolve Contents/Resources in a signed macOS application. KeyboardShortcuts resources ship inside that directory. The capture helper continues to use the native SwiftPM build.

Manual invocation sends `request_suggestion` with a null payload. The helper resolves the foreground application at receipt, then binds the explicit request to that application while obtaining a fresh stable field snapshot. Electron's mirrored application state is only for presentation and per-app controls, never manual capture authority. A focus change before capture cannot retarget the explicit request.

September 5 refinement: recording uses native AppKit buttons with a visible Reset label, modifier feedback, and explicit validation; plain Tab/Escape/Return/Right Arrow are supported for accept/dismiss. Request Reset restores Command-Shift-Space. Info help remains NSView.toolTip, with app-local NSInitialToolTipDelay registered at 350 ms; its precise behavior is OS-controlled. Practice keeps instruction text and request controls stable while a ghost appears so presentation feedback cannot become new context.

## Personalization wire

`StylePreference`: `{id:UUID,dimension:"concision"|"formality"|"structure",value:string,appId:string|null,origin:"learned"|"explicit"}`. Values are bounded to concise/balanced/detailed, casual/neutral/formal, or paragraphs/lists for the corresponding dimension. Learned scope always names an app. Empty global scope is encoded as explicit null. No free-text facts or language preferences are inferred. Desktop/helper protocol is4; both binaries and API ship together without a compatibility path.

Rewrites has its own grouped native destination. Editing a rewrite opens its existing native sheet; enable, save and restore use the existing encrypted transform storage. Recent activity is not displayed. The menu bar has one Open Autocomplete Everywhere command, finite pause/resume, current-app enablement and Suggest text; it does not duplicate a Settings command or a healthy Ready label.
