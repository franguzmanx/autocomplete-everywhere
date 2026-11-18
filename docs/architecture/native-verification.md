# Native verification boundary

## Return-to-source correction — 2026-09-04, 18:27 Argentina

Returning to a source field used to drop the known authored range. A reproduced
test changed a date from 17 to 18 after visiting a destination and retained only
`8`, losing its surrounding fact. Another reproduced failure kept an obsolete
fact after the source changed while unobserved. Both are fixed by validating the
retained bounded fragment at its original document range when focus returns.
No whole-document cache, per-application route or model change was added.

Fresh verification: 40 tests passed across RecentWritingContext, KeyboardMonitor
and SuggestionController, including four new return/expiry/bounded-Unicode cases.
`package:mac:qa` passed with Apple Development signing and integrity verification
(not notarized). The new package was restarted at 18:27 (main PID 17078, embedded
helper 17083). No backend deployment, commit or push was needed for this change.

The earlier automation limitation was reproduced: background Notes edits were
not captured. After the user activated Notes, the helper recorded a native field
and HTTP 200 in 1487 ms (`1B8A7AE4-DAFC-4244-A426-167D7720DAD0`, prior package).
After restart, the new package captured fresh source writing and returned final
text in 1143 ms (`37C45886-DE2F-450F-A650-074390087070`). These are transport and
capture observations, not yet proof of cross-app semantic quality or insertion.

## Recent-writing layer — 2026-09-04, subsequent work

The current layer adds RAM-only recent observed edits and verified acceptances,
and lets the model choose a block in already-started multiline fields. It keeps
`qwen-3.8-27b` on Cerebras, final-only output and no provider fallback.
Multiline requests now use the existing structured block path with low reasoning;
single-line artifact-free requests retain plain final text with no reasoning.
This is a change in output scope, not evidence of a latency improvement.

Fresh focused verification for this layer:

- API app/generator: 59 tests passed; protocol messages: 36 tests passed.
- Native recent-writing, keyboard and controller suites: 36 tests passed,
  including transient AX read recovery, five-minute expiry, corrections,
  exclusion of preexisting text, secure-field attribution and verified insertion.
- Desktop coordinator/trace: 9 tests passed, including content-free context counts.
- Workspace TypeScript checks passed; desktop check repeated after trace changes.
- Final `package:mac:qa` succeeded with Apple Development signing and package
  integrity verification; not notarized. The packaged app was restarted at
  18:14 Argentina time (main PID 97895, embedded helper PID 97913). Runtime status
  confirmed enabled with Accessibility and Input Monitoring granted.
- `git diff --check` passed after the implementation and documentation changes.

These results do not extend the older full-suite counts below to this layer.

The backend was deployed and promoted with subsequent user authorization:
`<deployment-id>`, deployment URL
`https://your-preview.example.com`. The production alias
`https://your-api.example.com` resolves to that Ready deployment.
`AI_DIAGNOSTICS=off` is configured in Production. No commit or push was made.

Authenticated packaged-app traffic returned HTTP 200 with final text:
`6105F80E-3532-46A5-9E23-E29D1A957732` took 2609 ms HTTP and
`F76A5636-E3DD-4B00-A9A4-2D1DE69B4927` took 1005 ms HTTP. Helper traces
reported presentation, but these traces are not visual confirmation of quality,
cross-application context use, or native acceptance.

The cross-app acceptance matrix remains open. Tool-driven Notes/TextEdit edits
did not establish corresponding destination capture and context use by the helper.
Do not call that semantic silence or a verified context failure without matching
request evidence. Computer Use denied Codex access and the local Surface Lab file
URL; neither restriction was bypassed. Gmail's existing draft was left unchanged.
No new CJK/RTL quality or native Tab/click acceptance is claimed for this layer.

## Earlier worktree verification — 2026-09-04

> Historical source-only audit below: its protocol/provider/configuration description was superseded by the current final-only protocol v4 and native settings. Its unperformed production checks remain unperformed.

## Protocol v3 release candidate — 2026-09-03 (Linux source verification only)

This revision advances desktop, protocol, helper, backend, and database
together:

- `configure` carries one boolean `enabled`; the per-application list, the
  desktop per-app state, and every `AUTOCOMPLETION_ENGINE_LAB` runtime path are gone.
- The desktop correlates helper requests, API responses, and helper
  `interaction` reports into content-free outcomes with request-to-final and
  request-to-visible latency, shows them in Settings, persists them in
  `runtime-status.json`, and records them through
  `POST /v1/suggestions/outcomes`.
- The desktop re-sends `configure` only when the effective switch changes,
  because the helper invalidates in-flight work on every configuration.
- Migration `20260903120000_suggestion_outcomes.sql` adds
  `record_suggestion_outcome`, the `generated` and `cancelled` outcomes, and
  `request_to_final_ms`, and drops the client `language_code` column.

Verified on Linux (Bun 1.3.14, Node 22) from a frozen install:

```sh
bun install --frozen-lockfile
bun run check
bun run test
bun run build
git diff --check
```

Proof level: **source-verified** for every TypeScript workspace: 200 tests
passed and 6 macOS-only package checks skipped. The Swift changes to
`HelperCommand.swift`, `FixtureDiagnostics.swift`, and their tests are written
in lockstep but **not compiled or run** here; there is no Swift toolchain on
Linux. The package-integrity tests skip off macOS instead of failing so a
Linux run can never be mistaken for package verification. No package,
signature, notarization, real-surface, or production measurement was produced
by this revision.

### Founder validation path for this revision (macOS)

Steps 4 and 9 touch production state. They require the founder's explicit
production authorization and are the founder's actions alone; no agent
applies hosted migrations or deploys the API. This revision did neither.

Run in this order and stop at the first failure:

1. `bun install --frozen-lockfile && bun run check && bun run test`
2. `swift test --package-path native/macos` — must pass, including the three
   rewritten `HelperConfigurationTests` cases.
3. `bun run --cwd apps/desktop package:mac:qa` — packages, verifies the
   helper, and validates signatures.
4. **Production step, founder authorization required.** Run the pgTAP suites
   locally first (`bunx supabase@latest db reset && bunx supabase@latest test
   db`). Only with explicit authorization, apply
   `supabase/migrations/20260903120000_suggestion_outcomes.sql` to the hosted
   project, rerun `suggestion_outcomes_test.sql` and `access_control_test.sql`
   there, and deploy the API afterwards, never before. Until both are live the
   desktop drops rejected outcome batches; nothing breaks and nothing is
   recorded.
5. Launch the packaged app normally (no fixture variables), sign in, enable
   autocomplete, and confirm `runtime-status.json` reports
   `configuration.enabled: true` and `helper_running`.
6. In Notes, type one synthetic sentence, pause, and confirm: one ghost
   appears inline; `runtime-status.json` shows `interaction: shown` and an
   `activity` block with `requested`, `generated`, `shown` at 1 and a
   `requestToVisibleMs` sample; the Settings window shows the same counts.
7. Press Tab once; confirm the text is inserted exactly once and `activity`
   shows `accepted: 1` with the accepted character count.
8. Type through a second suggestion, Escape a third, and switch focus during
   a fourth; confirm `typed_through`, `dismissed`, and `cancelled` appear in
   `recentPipeline` or `activity` and that no draft or suggestion text
   appears anywhere in `runtime-status.json`.
9. **Only if step 4 was authorized and completed.** After about fifteen
   seconds, confirm in the hosted database that `suggestion_events` holds
   rows for those requests with `model_id` set and no content columns. Events
   still in flight when the app quits are lost by design; use
   `runtime-status.json` for the complete session record.
10. Quit and relaunch; confirm one Electron parent and one helper, and that
    pausing from the menu bar sends exactly one `configure` (the helper log
    shows no repeated configuration during typing).

Then continue with the per-surface acceptance matrix below using this exact
package.

### Post-release manual acceptance: multilingual and empty-field intelligence

This is the checklist for the next objective. It has **not** been run. Every
row is labeled `blocked` until a person performs it with the packaged app and
the real engine; the only acceptable labels afterwards are `real-engine
manual`, `fixture-manual`, or `blocked` with the exact failing step. There
are no application-specific exceptions: if a surface needs its own code path
to pass, the surface stays unsupported and the row stays `blocked`.

Preconditions: the packaged app from this revision, normal execution (no
fixture variables), signed in, a short synthetic personal profile in one
language and company profile in another, Accessibility and Input Monitoring
granted. Use synthetic text only; never a real draft.

Run the same nine scenarios in each surface. Record per cell: label,
`requestToVisibleMs` from `runtime-status.json`, and shown/accepted counts.

| # | Scenario | Expected | Silence expected? |
|---|---|---|---|
| 1 | Type a Spanish sentence opener, pause | One inline Spanish continuation, no translation | No |
| 2 | Type an English sentence opener, pause | One inline English continuation | No |
| 3 | Two English paragraphs, then start a Spanish paragraph, pause | Continuation in Spanish; earlier text untouched | No |
| 4 | Mixed-language sentence (e.g. Spanish with an English product term), pause | Continuation keeps the mix; no forced single language | No |
| 5 | Focus an empty field whose nearby field already has text (Subject next to a written Body; Title above a written note) | One short line derived from the nearby text; nothing typed by the product | No |
| 6 | Focus an empty field with no nearby text | Nothing shown; `runtime-status.json` shows no request | Yes |
| 7 | Focus a password or one-time-code field | Nothing shown; no request; no capture | Yes |
| 8 | CJK or RTL sentence opener, pause | Continuation in the same script, aligned inline, Tab inserts once | No |
| 9 | Accept one suggestion with Tab, type through a second, Escape a third | Counts in Settings match: accepted 1, typed through 1, dismissed 1; no text in diagnostics | — |

| Surface | Field family | Status |
|---|---|---|
| Notes | native multiline body, title line | blocked |
| Slack | Electron message composer, thread reply | blocked |
| Gmail in Chrome | web Subject (single line), Body (contenteditable), To excluded from suggestions | blocked |
| Chrome | plain textarea and contenteditable on a synthetic page; address bar must stay silent | blocked |
| Safari | textarea, input, contenteditable on the same synthetic page; address bar must stay silent | blocked |
| Codex | Electron prompt composer, empty and non-empty | blocked |

Exit criteria for the objective: every non-silence cell shows exactly one
inline ghost or exact silence with a named reason, every silence cell stays
silent, no cell needed a surface-specific change, and `runtime-status.json`
contains no draft or suggestion text after the run.

## Worktree verification — 2026-09-02

The capability-based cross-surface implementation was verified locally with:

```sh
bun run --filter '*' test
bun run check
swift test --package-path native/macos
bun run --cwd apps/desktop package:mac:qa
git diff --check
```

The fresh results were 287 Bun tests and 367 native tests with zero failures,
successful workspace checks, and a strictly valid Apple Development-signed
package at `apps/desktop/dist/mac-arm64/AutocompleteEverywhere.app`. Static inspection
also confirmed that the suggestion path is final-only end to end: no
`streamText`, partial protocol message, incremental presenter state, AI Gateway
route, Electron clipboard enrichment, or application-specific model route.

The same packaged app was then exercised against the configured remote service
in Apple Notes and the controlled Chromium Surface Lab:

- Notes captured `Hola, te escribo porque`, received one final response in
  511 ms, and visibly rendered a Spanish inline continuation. The helper
  presented it 10 ms after the final response arrived.
- Chromium rendered final-only inline continuations for a Spanish/English
  code-switching line and an RTL multiline case. The RTL request completed in
  601 ms and the helper presented it 22 ms later.
- A CJK multiline request completed in 554 ms with semantic silence. This
  verifies capture, transport, and final-only handling, but not CJK suggestion
  quality.
- A secure field emitted repeated `secure_field` capture skips and no request
  while text was entered.
- An empty field with authoritative nearby context prepared a request but did
  not render while caret geometry was unavailable. This is the required safe
  behavior; no heuristic anchor or host-specific fallback was added.

This is not a completed cross-application release matrix. The public backend
used during the manual run predates the current Cerebras generation fixes, and
the current backend cannot be validated locally with production credentials.
Safari, Slack, Gmail, Codex, CJK visible quality, and native Tab/click acceptance
therefore remain unverified for the current candidate. Browser automation
events also bypass the native event tap and cannot establish Tab acceptance.

The web empty-field contract is structural rather than metadata-dependent:
when marker-native text before, selection, and text after are all empty, the
ghost receives an opaque host-background layer. This masks placeholders in
Chromium/Electron hosts that omit `AXPlaceholderValue`, without inserting or
changing any host text.

Web content and web geometry have separate Accessibility authorities. Only the
focused editable's `AXValue` and `AXSelectedTextRange` define request text;
text markers provide caret geometry and typography. A document-scoped marker
range therefore cannot leak surrounding browser or Electron UI into the field
request, and this remains one capability-based path rather than an app adapter.

Electron editors may expose text-marker APIs directly on the focused text area
without an `AXWebArea` ancestor. Such a control is classified by its actual
marker capabilities and uses itself as the marker provider. When its synthetic
placeholder is published as marker text, an empty current line plus impossible
full-field character geometry identifies that value as presentation rather
than authored content.

Related editables are discovered through an incremental neighborhood walk, not
a fixed descendant depth or an application adapter. The walk expands only new
sibling branches exposed by the focused field's ancestor chain, prunes a branch
at an editable root, and resumes its frontier after exhausting a time or node
slice. It caches topology only; related text is read fresh for each snapshot.

Content stability and inline geometry are separate. An empty semantic field may
prepare a request from an authoritative neighboring field while its caret is
unavailable, but it cannot render or consume Tab/click until current geometry is
corroborated. A matching first character can reveal the prepared remainder as
soon as the host publishes a real caret.

This proves the source/package/lifecycle boundary only. It does not prove that
the ghost is visibly aligned in each real host. Notes and browser acceptance
still requires the manual matrix below using this exact package.

## Verified source and package boundary on macOS

At source commit `84a88fe`, a clean archive was verified on Apple Silicon macOS
with Bun 1.3.14, Node 22.23.2, and Xcode 26.6:

```sh
env TMPDIR=/private/tmp bun install --frozen-lockfile
bun run check
bun run test
swift test --package-path native/macos
bun run --filter @autocompletion/desktop package:mac
```

The checks passed across all JavaScript workspaces, the native suite passed
167 tests, and packaging produced:

```text
apps/desktop/dist/mac-arm64/AutocompleteEverywhere.app
```

The package has bundle identifier `com.autocompleteeverywhere.desktop`. It contains an
arm64 executable helper at
`Contents/Resources/native/AutocompleteHelper`; both app and helper validate on
disk and satisfy their designated code-signing requirements. The local build is
signed with an Apple Development identity and is not notarized, so Gatekeeper
distribution assessment rejects it. This does not establish a distributable
release artifact.

The packaged main bundle includes the development-only fixture gate. It creates
a fixture suggestion coordinator only when
`AUTOCOMPLETION_VISUAL_FIXTURE=1`; normal execution remains disabled without a
verified suggestion source and completed onboarding.

### Accessibility display-coordinate contract

macOS Accessibility screen rectangles and `NSScreen.frame` are both expressed
in logical screen points. Retina `backingScaleFactor` describes backing pixels
per logical point and must not be applied to Accessibility rectangles. The
converter only flips and offsets the logical rectangle within the concrete
display that fully contains it; it never guesses a display or scales by Retina.

## Still requires live macOS verification

Source tests and a valid package do not prove Apple Notes visual behavior or
the permission/lifecycle boundary. Before calling the layer complete, launch
the packaged app with the explicit fixture, verify Accessibility and Input
Monitoring through normal macOS consent, and test rapid typing, wrapping,
multiline text, native suggestion pills, window movement, resize, scrolling,
focus changes, Tab, Escape, Return, emoji, accents, CJK, RTL, and unavailable
geometry. Then quit and relaunch normally while confirming there is only one
helper and that it exits with the Electron parent.

Captured text, suggestions, clipboard contents, screenshots, and OCR must not
appear in logs or verification artifacts.

## Option + Tab and integration — 2026-09-08

Option + Tab accepts the next whitespace-delimited word and adjacent separators
from the current ready suggestion. Plain Tab accepts the remaining text; Escape
discards it. Repeated key-down events while Tab is held do not accept extra words.
The remaining ghost is reanchored from verified host geometry without another
model request. Cancellation is checked again before asynchronous insertion.

The local session/policy probe passed 39 tests using production logic with host
boundary doubles on Linux; disabling prefix slicing made the new regression
checks fail. This does not establish AppKit, native Settings, undo or packaged
behavior, and predates final integration with the newer remote source-evidence
pipeline. Run the native Swift suite and manually check Notes/Gmail, Option+Tab
with no suggestion, pending preparation, IME, focus changes, and Cmd+Z.

The integration preserves the remote final-only protocol v4, native settings,
Cerebras model route and source-evidence validation, while adding selection
transforms and content-free outcome measurement. DATABASE_URL enables outcome
persistence; the endpoint returns outcomes_unavailable when it is not configured.
No hosted migration or manual production deployment was performed here.
