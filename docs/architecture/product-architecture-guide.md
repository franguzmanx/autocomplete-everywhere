# Autocomplete Everywhere product architecture guide

**Status:** Living guide for product and engineering decisions  
**Updated:** 2026-09-08
**Authority:** The approved architecture and build contract remain the normative specifications. This guide explains how the pieces fit together and separates the intended product from what has actually been verified.

## TL;DR

Autocomplete Everywhere places a useful continuation at the cursor in another Mac application. The interaction is deliberately narrow: show trustworthy inline ghost text, let the user accept it, or show nothing. It never substitutes a popup, guesses a position, captures secure fields, or sends content on the user's behalf.

The shared Electron app owns account, settings, helper lifecycle, remote requests, and diagnostics. A Swift/AppKit helper owns the live writing loop: focus, field eligibility, bounded capture, caret geometry, ghost rendering, keyboard decisions, insertion, and stale-state rejection. A future backend owns authentication, permissioned context, model routing, and show-or-suppress policy. The native helper remains the final authority over whether anything may be shown or inserted.

Today, the repository has a tested and packaged native foundation plus a real
authenticated suggestion path: Clerk OAuth on the desktop, a Vercel API,
one Gemini 3.5 Flash-Lite route through Vercel AI Gateway, and user-authored
personal/company context in a separate Supabase project behind RLS.
Deterministic fixtures remain available
only for development interaction QA. The production path has returned a real,
context-backed continuation for the packaged account, but the full visible
Notes and cross-surface acceptance matrix, suppression calibration, notarized
distribution, and release-level observability remain unfinished.

### Where the product is now

Think of the product as four layers. A layer counts as finished only after it
works in the packaged app, not merely because its source tests pass.

1. **Inline writing loop — nearly complete.** The native helper can capture,
   render, reconcile typing, accept with Tab or click, and insert across native
   and browser editors. The remaining work is the current real-surface
   acceptance matrix and measured reliability.
2. **The field knows what it is for — in progress.** Protocol v3 now carries a
   bounded semantic field context. The model infers the destination task from bounded raw evidence, stays silent on unresolved empty fields, and can use a
   nearby field as an authoritative source. Gmail body to empty Subject is the
   first product proof; it is source-verified but not yet packaged-manual.
3. **Mac product shell — in progress.** The desktop has a menu bar state,
   pause/resume, Settings with grounding context, and a content-free activity
   readout (requests, shown, accepted, silent, time to appear). Timed pauses,
   deletion controls, and polished onboarding remain.
4. **Learning, distribution, and expansion — measurement started.** Every
   request now produces content-free outcome events on the desktop, persisted
   locally and recorded through the API into `suggestion_events` under RLS.
   Notarization, updates, richer context, connectors, and Windows begin only
   after the first three layers are reliable and the measurement has real
   data behind it.

The near-term product is therefore not a dashboard. It is a quiet Mac utility
that works inline, understands a small set of high-value fields, explains its
source when asked, and otherwise stays silent.

## 1. Product vision and the narrow wedge

The long-term product is grounded intelligence at the point where a person is already writing. It should help with both human-facing prose and instructions to AI agents without asking the user to move into a separate chat interface or choose a model.

The wedge is intentionally smaller than “AI everywhere”:

- macOS first;
- one invisible interaction: continuation at the active cursor;
- one acceptance primitive: Tab, with direct click supported only on the actual ghost glyphs;
- explicit dismissal through Escape, Return, incompatible typing, navigation, or focus change;
- a small, measured surface matrix before adding more applications;
- remote generation behind a stable native interaction contract;
- no autonomous sending, submitting, clicking, publishing, or committing.

The target MVP remains a real journey in Notes, Slack, and one Chromium
prompt surface. The implementation matrix now includes Notes, TextEdit,
Safari, and Google Chrome: TextEdit is a useful native-control validation
surface, while Safari and Chrome exercise web textarea, input, and
contenteditable behavior. Neither a local fixture nor support code in the
repository makes a surface production-supported; each browser still requires
its own packaged visual acceptance.

## 2. User experience contract: inline or silence

The product has only two acceptable visible states:

1. A continuation is laid out inline at a validated caret, without taking focus.
2. Nothing is shown.

“Inline” is a behavioral promise, not merely a gray overlay near the editor. The completion must begin at the real insertion boundary, shape and wrap like the host paragraph, remain within the visible field, and disappear as soon as its field, content, selection, or geometry is no longer current.

Silence is the correct response when:

- the field is secure, excluded, unsupported, or not explicitly enabled;
- Accessibility or Input Monitoring permission is missing;
- the selection is incompatible with safe completion;
- IME or native suggestion state is ambiguous;
- caret or paragraph geometry is missing, contradictory, stale, or outside a known display;
- the suggestion is late, unsafe, ungrounded, low-value, malformed, or belongs to an older request;
- insertion cannot be prepared and revalidated safely.

There is no card, pill, popup, mouse-position fallback, first-screen fallback, or guessed geometry fallback. A momentary gap while the host publishes coherent state is preferable to a jump.

## 3. System layers and ownership

```text
User types in a host application
             │
             ▼
Swift/AppKit helper
focus · eligibility · bounded capture · geometry · session · keys · insertion
             │ versioned newline-delimited JSON over parent stdio
             ▼
Electron main process
helper lifecycle · cancellation · authenticated transport · content-free events
             │ HTTPS, when the real engine is enabled
             ▼
TypeScript backend
auth · permissioned retrieval · prompt assembly · suppression · model routing
             │
             ├── Supabase: canonical context, provenance, RLS
             └── AI Gateway: Gemini 3.5 Flash-Lite generation, without fallback

Electron renderer (beside, not inside, the hot path)
onboarding · account · permissions · settings · integrations · diagnostics
```

| Layer | Owns | Must not own |
|---|---|---|
| Host application | The user's document, focus, and final text | Autocomplete Everywhere state |
| Native helper | Current truth about focus, field, content signature, geometry, visible session, Tab/click consumption, and verified insertion | Long-lived auth secrets, provider selection, account UI |
| Electron main | Helper process/version, configuration, request transport/cancellation, short-lived auth use, aggregate diagnostics | Final Tab decision, direct host editing rules |
| Electron renderer | User-controlled settings, onboarding, account and connection UI | Raw helper IPC, provider credentials, captured draft content, hot-path decisions |
| Backend | Identity verification, authorization, retrieval, prompt construction, suppression, model/provider routing | OS focus, caret truth, keyboard ownership |
| Canonical data plane | Context ownership, provenance, freshness, deletion, personal/org boundaries | Live keystroke history |
| Derived/device context | Rebuildable indexes and a small encrypted, already-authorized hot capsule | Permission authority or a full company mirror |

Desktop and helper ship as one protocol version. A mismatch disables autocomplete; it does not start a compatibility or migration path.

## 4. End-to-end data flow

1. Electron starts the matching helper as a child process and sends a valid `configure` command carrying one boolean capability switch. Capture is off until the global switch, account/source readiness, and required OS permissions all permit it. Electron re-sends `configure` only when that switch changes, because the helper invalidates in-flight work whenever it applies a configuration. Eligible fields are then classified locally by capability, not by application name.
2. The helper observes focus or meaningful input, rejects ineligible state locally, waits for a natural pause, and captures a bounded immutable snapshot.
3. The snapshot carries field identity, focus sequence, content signature, selection, capture sequence, surface identity, and geometry provenance. Secure fields are rejected before their value or bounds are read.
4. The helper emits a `suggestion_request`. Electron attaches request metadata and, in the real-engine path, calls the authenticated backend.
5. The backend re-authorizes relevant context, assembles a bounded prompt, chooses show or silence, and routes generation server-side. Provider and model identity are not desktop product concepts. Content may stabilize and request before inline geometry exists; visibility and acceptance still wait for a corroborated caret.
6. Electron sends only the validated final output for the matching request back to the helper. Provider chunks and partial output never become product-visible protocol messages.
7. The helper rechecks current field/content identity and accepts geometry only from a coherent current snapshot. Stale output is discarded before presentation.
8. A valid completion is rendered through a non-activating AppKit panel. For multiline fields, the host prefix and completion must be shaped as one paragraph; the prefix is transparent and only completion glyphs are visible and clickable. A structurally empty web editor receives an opaque background beneath the ghost so host placeholders cannot blend with it; this does not depend on optional placeholder metadata and never mutates host text.
9. Continued matching typing reconciles the Unicode prefix and advances the drawing from the same paragraph layout while two fast post-input reads corroborate the predicted caret. A disagreement, mismatch, or incompatible input hides and cancels it.
10. Tab or a direct click is consumed only after field, session, and geometry revalidation. The helper inserts exactly once, captures again, and verifies the host result. Failure ends the session without an automatic retry.
11. The helper reports each interaction outcome (shown, accepted, typed through, dismissed, stale, failed) with the request identity and an accepted-character count. Electron correlates those reports with the request and the API response into one content-free lifecycle per request, updates the Settings activity readout, and records the events through the API in small best-effort batches.

Cancellation is normal lifecycle. A newer focus, content signature, capture generation, or request makes older work incapable of presenting or inserting.

## 5. Suggestion engine boundary

The native loop must not know whether suggestion text came from a deterministic fixture, one remote model, or a future retrieval/generation stack. Both sources enter through the same typed final-result protocol and must obey the same identity, staleness, rendering, and acceptance rules.

### Development fixture

`AUTOCOMPLETION_VISUAL_FIXTURE=1` enables a deterministic local suggestion coordinator for visual and interaction QA. It is valuable for reproducing layout, Unicode, multiline, type-through, dismissal, click, Tab, and insertion behavior without network or model variance.

It is development-only:

- normal execution must not silently fall back to it;
- it does not prove authentication, retrieval, generation quality, latency, grounding, privacy policy, or backend cancellation;
- a fixed response appearing in Notes is not “real Notes autocomplete”;
- a fixture passing in one application says nothing about another application's adapter.

### Real engine

The intended engine is an authenticated TypeScript backend using permissioned context and remote models. It owns context retrieval, prompt assembly, server-side model experiments, safety/output normalization, and show-or-suppress policy. The desktop owns cancellation and transport; the helper still rejects stale or unsafe-to-render results.

The first real engine slice is now connected: the packaged desktop signs in
with Clerk, the API verifies the OAuth token, retrieves only that user's manual
context through transaction-local RLS claims, and calls Gemini 3.5 Flash-Lite directly
through Vercel AI Gateway. Single-line output without artifacts uses one final plain-text result; multiline or artifact-bearing output uses one structured composition. Thinking is `low` for both single-line and multiline fields; thoughts are not included in the response. Multiline fields allow a block even after writing has started. There is
no production model/provider selector or fallback. This verifies the serving
boundary, not universal product quality.
Visible inline placement, usefulness, suppression, latency, and insertion still
require per-surface packaged acceptance.

## 6. Surface-adapter strategy

A “surface” is a tested compatibility contract, not just a bundle identifier. Shared machinery should handle the state machine and invariants; adapters should contain only behavior that genuinely differs by host family.

| Surface | Current purpose | Important adapter behavior | Evidence boundary |
|---|---|---|---|
| Apple Notes | Primary native product wedge | Notes caret candidate resolution, paragraph metrics, multiline mirror layout, native suggestion/autocorrect ambiguity, safe AX insertion | Automated coverage and historical manual scenarios exist; current coherent paragraph/timing work still requires newly packaged real Notes acceptance |
| TextEdit | Native text-control control case | Standard native AX capture/geometry and insertion with minimal host-specific behavior | Useful per-surface validation; not proof for Notes or web controls |
| Safari | Web-control family spike using local fixtures | Require a web-content element, exclude password fields, account for WebKit font/field geometry, prefer synthetic Unicode insertion, test input/textarea/contenteditable separately | Adapter and tests exist; visible rendering, Tab, one-click acceptance, and right-edge wrap require independent packaged verification |
| Google Chrome | First Chromium web family | Require an editable web-content element, use marker-native strings and line boxes, exclude browser chrome and secure fields before value reads, map to the shared `web_textarea` protocol surface, and verify synthetic Unicode insertion | Automated capture/presenter/insertion coverage exists; packaged Gmail rendering, Tab, click, and wrap still require manual acceptance |
| Slack | MVP target, future matrix entry | Classify its actual Electron accessibility capabilities; do not assume every Chromium descendant is an editable web surface | Not current verified support |

`WritingSurface` describes two capability families—native and web—and maps
them to protocol surface classes. Bundle identifiers are metadata, never an
eligibility gate. If a host needs different capture, layout, or insertion
behavior, add the smallest capability-specific behavior and test it rather
than adding another application list or weakening global invariants.

## 7. Input and acceptance lifecycle

```text
disabled
  └─ configure + account/source readiness + permissions
       → observing → debounce → capture/request → final response
       → validate identity + corroborate geometry
       → visible
            ├─ matching text → predict + corroborate → visible or complete
            ├─ mismatch/navigation/focus/Escape/Return → dismiss → observing
            ├─ Tab/direct ghost click → revalidate → insert once → verify → observing
            └─ stale/unsafe/ambiguous → silence → observing
```

Key ownership rules:

- The helper, not Electron, decides whether a key can be consumed.
- Tab passes through unless a valid visible accept-ready suggestion survives current revalidation.
- Escape dismisses. Return dismisses and passes through.
- Direct-click acceptance is limited to current completion glyph hit regions; clicks elsewhere pass through to the host.
- Type-through compares Unicode prefixes. It advances from the same shaped paragraph and becomes accept-ready only after current Accessibility geometry corroborates the prediction.
- Nonempty selection, middle-of-text insertion, trailing host text, incompatible typing, composition ambiguity, or failed verification closes the session.
- Generated input is tagged or otherwise prevented from re-entering the observation loop.

## 8. Trust, privacy, and security boundaries

Trust is enforced at several independent layers because no single permission implies product consent or safe output.

### On the device

- Accessibility and Input Monitoring permission are necessary but not consent to run. The explicit product switch, signed-in account, and available suggestion source remain required.
- Secure/excluded fields fail closed before text, bounds, request, or diagnostic construction.
- Capture is bounded to what the active completion needs; raw keystrokes are not stored as history.
- The helper accepts commands only from its Electron parent over stdio and exits with that parent.
- Desktop and helper are signed and versioned together; mismatch disables the loop.
- Renderer sandboxing, context isolation, no Node integration, and a narrow preload API keep drafts, helper IPC, tokens, and provider secrets out of renderer code.
- Refresh credentials belong in the OS credential store. The native helper receives no long-lived Clerk or provider secret.

### In the backend and context system

- Provider and administrative credentials remain server-side.
- Canonical context belongs to exactly one personal or organization space and carries provenance, validity, freshness, and recipient information.
- Database RLS is a defense-in-depth authorization boundary. Retrieval results are re-authorized before prompt assembly; vectors or managed-memory results never grant permission.
- Derived embeddings and indexes are rebuildable. The canonical source and its deletion/ownership policy remain authoritative.
- A device hot-context store, when implemented, is encrypted and contains only a small, already-authorized working set—not a full repository mirror.
- Zero-data-retention provider policy and cross-recipient leakage tests are release gates, not assumptions.

## 9. Reliability invariants

These rules are stronger than any individual adapter or optimization:

1. **Inline or silence.** Unsafe layout never degrades into another UI.
2. **Current identity only.** Presentation and insertion match field identity, focus sequence, content signature, selection, and capture generation.
3. **Coherent geometry only.** Never combine coordinates from different caret candidates, guess a display, or rescale logical Accessibility points by Retina scale.
4. **Corroborate after input.** Event payloads trigger reads; authoritative Accessibility state must agree before reappearance.
5. **One owner for acceptance.** The native helper consumes Tab/click only for a current valid session.
6. **Insert once, then verify.** Failure is terminal for that session; no automatic duplicate attempt.
7. **Fail closed.** Missing permission, secure field, protocol mismatch, unsupported host, timeout, provider failure, or uncertain geometry produces silence.
8. **No content logs.** Draft, suggestion, clipboard, screenshot, OCR, and retrieved-source bodies never enter default logs or telemetry.
9. **One parent, one helper.** Helper lifecycle follows Electron; a direct helper smoke test is not packaged lifecycle proof.
10. **Per-surface proof.** Notes, TextEdit, Safari, Slack, and future apps each earn support through their own packaged manual matrix.
11. **No compatibility layers.** Desktop and helper advance as one product version; obsolete rendering and protocol paths are removed.

## 10. Observability without content logging

Useful diagnosis does not require retaining what the user wrote. The
implemented lifecycle per request is:

```text
requested -> generated | suppressed | failed | cancelled
generated -> shown -> accepted_full | accepted_partial | typed_through
                      | dismissed | stale | failed
```

`requested` is emitted when the helper's request is observed; `generated`
and `suppressed` when the API returns text or silence; `cancelled` when the
helper withdraws the request; the rest come from the helper's interaction
report. Two latencies are measured on the desktop clock from the helper's
request timestamp: request-to-final and request-to-visible. Both exclude the
native quiet interval that precedes a request, so pause-to-visible is the
quiet interval plus request-to-visible. Aggregates live in
`runtime-status.json` and the Settings activity card; individual events are
recorded through `POST /v1/suggestions/outcomes` into `suggestion_events`
with the server-side model identity attached. Recording is best-effort:
batches leave every fifteen seconds or at twenty events, a rejected batch is
dropped without retry, and on quit the desktop starts one last flush but does
not wait for it, so events still in flight at exit are lost. The local
aggregates in `runtime-status.json` are the complete record for a session;
the database is the cross-session sample.

Default events may include:

- random request/experiment identifiers and protocol/build version;
- coarse surface class, eligibility/skip reason, geometry source/quality, and lifecycle transition;
- capture, transport, first-visible, and insertion-verification latency;
- suggestion character count—not suggestion text;
- shown, partially accepted, accepted, typed-through, dismissed, stale, suppressed, or failed outcome;
- content-free error class such as permission, timeout, malformed response, stale identity, unavailable geometry, or verification failure.

They must exclude field text, suggestion text, selected text, clipboard data, screenshots, OCR, retrieved documents/facts, URLs containing content, and hashes that could be used as durable cross-session fingerprints. Debug fixture diagnostics should describe structure and state transitions, not private payloads.

User-contributed evaluation samples require a separate explicit opt-in path and retention policy. They are not an extension of routine telemetry.

## 11. Current verified boundary and unfinished work

This section is deliberately conservative. “Tests exist” and “code is present” are not the same as a user-observed product capability.

| Area | What is supported by current evidence | What is not yet established |
|---|---|---|
| Source and package | At commit `84a88fe`, frozen install, shared checks/tests, 167 native tests, Mac packaging, embedded arm64 helper, and strict on-disk signing validation passed. The artifact was Apple Development signed. | A notarized public artifact, update path, and unrestricted Gatekeeper distribution |
| Protocol and helper lifecycle | Protocol v3 with one boolean `configure` switch, raw bounded field context, packaged helper presence, parent-child design, and failure-containment tests exist. The 2026-09-03 worktree passes the shared TypeScript suites on Linux; the Swift decoder change is written in lockstep but not yet compiled or run on macOS. | `swift test` on macOS for the v3 `configure` change, notarized distribution, and clean lifecycle proof across an actual update |
| Safety gates | Automated tests cover ineligible capabilities, secure fields before value reads, invalid selections, stale identities, and Tab/insertion revalidation. | Production privacy audit, real secure-field matrix across host families, and ZDR backend verification |
| Semantic field context | Protocol v3 carries bounded raw field shape, labels, placeholders, related fields, and up to five bounded user-authored artifacts with provenance. The native helper keeps current selection for 60 seconds, the opt-in current clipboard for 10 minutes, and up to three recent-writing fragments for five minutes (4,000 UTF-16 units total). Recent writing comes from observed edits or verified acceptance, excludes the current field, updates on observed corrections and deletion, and clears on disable. Electron never rereads or enriches it. An incremental capability-based neighborhood traversal crosses deeply wrapped forms without app adapters or a fixed descendant depth; it caches traversal state and rereads related text for each snapshot. Empty unresolved fields stay silent; authoritative nearby content or an artifact can produce a line or block budget. The model resolves intention, language, tone, code-switching, and whether to reference exact source material; there is no local language or task classifier. Secure-adjacent containers fail closed. | Real Gmail proved generic Subject capture, deep Body discovery, and request emission. The current artifact-reference and adaptive-output candidate still needs packaged manual proof in Notes and browser surfaces. |
| Native visual loop | One `SuggestionController` owns capture/session/presentation/type-through/acceptance; geometry provenance, marker-native web context, predicted type-through, scroll reacquisition, click/Tab paths, and verified off-main insertion exist and pass automated tests. | User-observed packaged acceptance across the full Notes and browser matrix; automation alone is not visual proof |
| Notes | Historical QA exercised wrap, Unicode/multiline, Tab/Escape/Return, focus, and insertion scenarios. | Current acceptance after the paragraph-mirror/timing changes: rapid typing, partial words, pills/autocorrect, resize/scroll/movement, emoji/accents/CJK/RTL, exactly-once Tab/click, and secure-field silence |
| TextEdit | A native adapter and controlled fixture have shown useful stability in prior QA. | Release-level matrix and proof that a real engine behaves correctly there |
| Safari | Capture/insertion/presenter support and local fixtures cover input, textarea, contenteditable, and password exclusion in source/tests. | Independent packaged proof of visible ghost rendering, Tab, one direct click, and right-edge wrap; the address bar is not a supported fixture |
| Suggestion source | Normal packaged execution uses one authenticated HTTP request and one complete validated response from the production API; development fixtures remain explicitly gated and never become a silent fallback. The real account path has returned a nonempty continuation without logging its content. | Quality/silence calibration, latency gates, cancellation under real load, and release evidence across every supported surface |
| Auth, backend, context | Clerk OAuth sign-in, server-side Clerk verification, one `google/gemini-3.5-flash-lite` AI Gateway route, and manual personal/company context are connected. Supabase stores that context in a separate project; transaction-local `authenticated` role and verified Clerk `sub` claims keep the existing RLS policies active. Hosted pgTAP isolation and real account save/read paths have passed. | Rich retrieval, organization context, connectors, device capsules, deletion UI, production telemetry, model bakeoffs, and provider-policy audit |
| Outcome measurement | The desktop correlates requests, responses, and helper interaction reports into content-free events with request-to-final and request-to-visible latency; Settings shows the counts; the API validates a strict allowlist and records rows through `record_suggestion_outcome` under RLS. Source-verified with Bun tests and a checked-in pgTAP suite. | Applying migration `20260903120000` to the hosted project, running its pgTAP suite there, and the first production-measured latency and acceptance numbers |

The performance and quality numbers in the architecture—700 ms p50, 1,400 ms p95, 99.5% verified insertion, 25% acceptance, zero leakage—are product gates, not current measurements.

## 12. Staged roadmap to a real product

Each stage must leave a working, demonstrable product layer. Do not begin the next platform or broad connector work to hide an incomplete Mac loop.

1. **Prove the native truth loop.** The paragraph mirror, generation-scoped
   reacquisition, and shared controller are implemented. Complete the real Notes
   and Chromium matrix with the packaged app, including wrap, typing through,
   wrong keys, native suggestions, Tab, click, scroll, and focus changes.
2. **Prove one semantic field journey.** The source path can derive an empty
   Gmail Subject or Notes title from an authoritative body and can generate a
   one-line empty-body opener. Validate those paths manually, then tune explicit
   silence and quality without weakening stale or secure-field gates.
3. **Ground one useful scenario.** Manual personal/company context now has
   canonical ownership and RLS. Complete the product proof with one Spanish and
   one English human-writing scenario plus one agent-prompt scenario, including
   explicit cross-user and cross-scope leakage checks.
4. **Earn the Mac surface matrix.** Expand the shared capability engine across native and web accessibility shapes; never add app-specific adapters. Notes, Slack, Chromium, TextEdit, and Safari are acceptance surfaces, not implementation branches. Publish support only after real-package acceptance.
5. **Measure suppression and reliability.** Latency and interaction outcomes are now recorded without content; apply the outcome migration, collect real data, then calibrate when to remain silent and meet stale, secure-field, Tab pass-through, insertion, leakage, and distraction gates.
6. **Harden distribution.** Verify signed/notarized artifacts, consent after update, auto-update protocol coordination, credential storage, helper lifecycle, crash recovery, and privacy/provider policy.
7. **Expand context and surfaces.** Add connectors, richer prefetch, and support for additional Accessibility capabilities only when permission, freshness, deletion, latency, and user-value gates remain intact.
8. **Add Windows last.** Implement the proven behavioral protocol with Windows-native APIs only after the Mac loop and remote serving path have survived real product iteration.

## 13. Key decisions and rejected approaches

| Decision | Why | Rejected approach |
|---|---|---|
| Electron product shell plus native OS helper | Shares account/settings/network product work while keeping focus, keyboard, geometry, and insertion native | Electron-only cannot safely own the full conditional keyboard and Accessibility loop; fully native duplicates the whole product UI |
| Parent stdio protocol | Simple lifecycle, no local discovery/port/auth layer, version ships with app | Local HTTP/socket service and independent helper versioning |
| Native helper is the interaction authority | It has the freshest focus, content, geometry, and event state | Electron deciding Tab or insertion from delayed IPC state |
| Overlay transport with exact inline contract | Does not mutate the host until acceptance and can disappear safely | Pre-inserting selected text, popup/card fallback, or mouse/caret guesses |
| Full paragraph mirror | Preserves shaping, partial words, kerning, bidi, and host-like wrapping | Laying out suggestion alone or replacing prefix width with synthetic indentation |
| Corroborated Accessibility polling | Host notifications and event timing are not authoritative enough | Treating a key event or single finite AX rectangle as coherent state |
| Remote generation behind server routing | Providers/models can change without changing desktop behavior; secrets stay server-side | Local generation, Mercury dependency, desktop model picker, provider credentials in Electron |
| Supabase canonical truth plus derived retrieval | Keeps ownership/RLS/provenance independent of embeddings or vendors | Vector index/Supermemory as permission authority or storing raw keystroke history |
| Capability-based field classification | The product is global, while secure, search, browser-chrome, self-process, and unsupported controls still fail closed before text reads | Bundle allowlists that make identical editable controls behave differently by application name |
| Remove obsolete paths | One product contract is easier to test and fail closed | Backward-compatibility layers, duplicate renderers, silent fixture fallbacks, per-application switches, a clipboard lab beside the real engine |
| Measure before tuning | Suppression, latency, and acceptance gates need real content-free numbers; guessing thresholds hides regressions | Tuning prompts or debounce from anecdotes; logging drafts to learn |

## 14. How to add a new surface safely

Adding a host name is not the definition of support; qualifying its actual editable capability is.

1. **Write the surface contract.** Name the exact application/control family and initial fields. Document exclusions such as address bars, password fields, rich canvases, IME states, or unsupported selections.
2. **Prove safe classification before reading.** Ensure secure, search/combo, browser-chrome, self-process, and unsupported roles are rejected before value or geometry access. Add capability-specific behavior only for a measured Accessibility difference.
3. **Capture one immutable snapshot.** Reuse the shared identity/signature model. Add capability-specific capture only for a demonstrated Accessibility difference, with bounded reads and structural diagnostics.
4. **Resolve geometry with provenance.** Define acceptable caret candidates, display conversion, paragraph metrics, font behavior, visible-field bounds, and when geometry becomes unavailable. Never guess or weaken the one-point/alignment and containment rules globally.
5. **Choose the existing renderer mode.** Use validated single-line or paragraph mirror. If neither can reproduce the host safely, the surface remains silent; do not add a third fallback UI.
6. **Specify insertion and revalidation.** Prefer a reliable Accessibility edit where supported, otherwise use an explicitly tested synthetic Unicode path. Re-capture before acceptance and verify afterward. Clipboard insertion requires its own user-activity-safe restoration contract before use.
7. **Add red tests at every boundary.** Cover configuration/capability classification, secure fields, capture, geometry, font/layout, stale cancellation, Unicode/IME, type-through, Tab pass-through/consume, click hit-testing, insertion, verification failure, and content-free diagnostics.
8. **Build a minimal real fixture.** For web surfaces, exercise input, textarea, contenteditable, and password exclusion separately; never use an address bar as the fixture. Keep fixture text synthetic and non-sensitive.
9. **Package before manual claims.** Record commit/build identity, run focused and full native/contract checks, package the real app, verify its helper/signature, and confirm one Electron parent and one helper.
10. **Run the per-surface acceptance matrix.** Normal line, right-edge wrap, rapid typing, partial word, wrong character, deletion/navigation, native suggestions, resize/scroll/movement, focus change, Tab once, Escape/Return, one direct click, emoji, accents, CJK/RTL as applicable, and secure-field silence.
11. **Report the exact proof level.** Label the result automated-only, fixture-manual, packaged-manual, blocked, or production-measured. Do not infer support from another surface.

A new surface is supported only when it preserves every global invariant. If host APIs cannot provide reliable current geometry or verified insertion, the correct adapter is one that stays silent.

## 15. Verification vocabulary

Use these labels consistently:

- **Source-verified:** static/type/unit/contract tests passed for a named revision.
- **Package-verified:** the named packaged artifact contains the expected helper and passes signature/integrity checks.
- **Fixture-manual:** a person observed behavior with `AUTOCOMPLETION_VISUAL_FIXTURE=1`.
- **Real-engine manual:** a person observed a real authenticated suggestion in the packaged app.
- **Production-measured:** release behavior met named reliability/privacy/quality gates using content-free metrics.
- **Blocked/unresolved:** the remaining surface, interaction, or trust boundary is named precisely.

Never collapse these into “works.”

## References

- [Build-ready architecture](./architecture-v2.md)
- [Mac MVP build contract](./mvp-build-contract.md)
- [Native verification boundary](./native-verification.md)
- [Stable inline ghost-text specification](../superpowers/specs/2026-08-29-notes-stable-inline-ghost.md)
- [Coherent paragraph mirror implementation plan](../superpowers/plans/2026-08-30-coherent-paragraph-mirror.md)
