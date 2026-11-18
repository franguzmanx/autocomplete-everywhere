# Autocomplete Everywhere — Build-Ready Architecture v2

**Status:** Approved build specification
**Date:** 2026-08-29
**Scope:** Historical specification for this repository. The user confirmed on September 4 that this product is Autocomplete Everywhere; Autocomplete Everywhere was its working name. Earlier product-separation wording is superseded by that identity decision.

**September 4 product review:** the [complete product proposal](../product-intelligence/invisible-intelligence-product-design.md) defines the newer connector-free experience and distinguishes it from implemented capability. Technology choices and future subsystems below are historical design decisions unless current code and the product-intelligence contracts establish them. In particular, their presence here does not prove implemented durable storage, retrieval, ingestion or onboarding behavior.

## 1. Decision

Autocomplete Everywhere will use a shared Electron product shell with one native autocomplete helper per desktop operating system:

- **macOS:** Swift and AppKit, built first.
- **Windows:** C#/.NET and Windows APIs, built after the Mac loop meets its product and reliability gates.
- **Shared product layer:** Electron main process and a sandboxed React renderer.
- **Shared backend:** TypeScript on Vercel, Clerk, a new Supabase Postgres project, Supabase Storage and Queues when required, and AI Gateway inference for text generation.
- **Device hot context:** encrypted SQLite through SQLCipher. The native helper prepares a small authorized context capsule before the user pauses.
- **Context retrieval:** hybrid lexical and semantic search over canonical, permissioned records. `google/gemini-embedding-2` at 1,024 dimensions is the first embedding implementation.
- **Context-engine experiment:** Supermemory hosted is evaluated against owned hybrid retrieval. It is never the source of truth or the final authorization authority.

All text generation is remote. The production path uses one server-owned `google/gemini-3.5-flash-lite` model through Vercel AI Gateway. Offline bakeoffs may compare other models and providers, but they do not add production routes, fallbacks, or desktop configuration. Model selection remains invisible to the user.

This is intentionally hybrid. Electron shares the parts that are genuinely cross-platform: account, settings, integrations, backend communication, experiments, updates, and diagnostics. The native helpers own the parts that cannot be made reliably cross-platform: focus, text ranges, keyboard interception, caret geometry, ghost text, insertion, and secure-field enforcement.

Electron-only is rejected because its global-shortcut and window APIs do not provide the full conditional keyboard, accessibility, and insertion behaviour this product requires. Fully native clients are also rejected because they would duplicate the entire product interface while still requiring separate OS implementations of the critical loop.

## 2. Product contract

Autocomplete Everywhere supplies missing intelligence at the moment a person begins expressing intent. It serves two audiences through the same interaction:

1. People writing messages, email, posts, documents, sales copy, product text, names, and other human-facing work.
2. People writing instructions and context for AI agents.

The user experiences one product, not a model selector or a collection of modes.

The core interaction contract is:

- The user begins writing.
- The product stays silent unless it has a useful, sufficiently grounded continuation.
- A suggestion appears beside the cursor without taking focus.
- Tab accepts; Escape dismisses; continued typing reconciles with or dismisses the suggestion.
- Nothing sends, submits, commits, or publishes automatically.
- A stale suggestion never appears.
- Secure fields never enter the generation pipeline.

## 3. Goals

The architecture must:

- Deliver automatic ghost-text autocomplete with low perceived latency.
- Work across different application families, starting with one native Mac app and one Chromium/Electron app.
- Carry bounded, relevant context across applications without storing raw keystroke history.
- Support partial and full acceptance, type-through, dismissal, and stale-work cancellation.
- Fail closed for password, secure, financial, and otherwise excluded fields.
- Let models and providers change without changing the desktop interaction.
- Share the product layer across macOS and Windows.
- Keep OS-specific behaviour isolated behind one versioned helper protocol.
- Provide enough telemetry to improve suggestion quality without collecting draft contents by default.
- Continue in the language and script of the active field, with baseline coverage across more than 100 languages and a measured certified-language set.
- Keep remote databases and remote retrieval out of the synchronous per-keystroke path.
- Preserve provenance, validity, and permissions for every durable piece of context.

## 4. Non-goals

The first implementation will not include:

- A Windows helper before the Mac experience meets its gates.
- iOS; Electron does not solve iOS, which will require a separate native client or keyboard extension.
- Local or on-device generation.
- Mercury models.
- A user-facing model chooser.
- Screenshot OCR by default.
- Universal support for every application.
- Autonomous sending or publishing.
- A custom-trained autocomplete model before real acceptance data exists.
- Persistent raw keystroke, prompt, or completion logging.
- Dependency on the existing Autocomplete Everywhere application, database, auth instance, or deployment.
- Voice dictation or transcription. It is a separate product path from written autocomplete.
- A production dependency on Supermemory before the owned-versus-managed retrieval bakeoff is complete.

## 5. System boundary

```text
┌──────────────────── Shared desktop product ────────────────────┐
│                                                                │
│  Electron renderer                 Electron main process       │
│  - onboarding                      - helper lifecycle           │
│  - account and settings            - authenticated API client  │
│  - integrations                    - request cancellation       │
│  - diagnostics                     - experiment assignment      │
│  - no hot-path access              - privacy-safe telemetry     │
│                                             │                  │
└─────────────────────────────────────────────┼──────────────────┘
                                              │ versioned stdio IPC
                    ┌─────────────────────────┴────────────────────────┐
                    │                                                  │
          macOS native helper                               Windows native helper
          Swift + AppKit                                    C#/.NET + Windows APIs
          - AX focus and text                               - UI Automation
          - CGEvent taps                                    - Win32 keyboard hooks
          - caret geometry                                  - caret/text ranges
          - NSPanel ghost text                              - native overlay
          - insertion                                      - insertion
          - secure-field gate                               - secure-field gate
          - SQLCipher capsule                               - SQLCipher capsule
                    │                                                  │
                    └─────────────────────────┬────────────────────────┘
                                              │
                                  ┌───────────▼───────────┐
                                  │ TypeScript backend    │
                                  │ - Clerk verification  │
                                  │ - capsule and retrieval│
                                  │ - prompt assembly      │
                                  │ - show/suppress policy │
                                  │ - AI Gateway generation  │
                                  │ - evaluation events    │
                                  └──────┬─────────┬──────┘
                                         │         │
                         Supabase Postgres│         │AI Gateway
                         - canonical truth│         │- Gemini 3.5 Flash-Lite
                         - RLS permissions│         │- direct inference
                         - hybrid search  │         │- no fallback route
                                         │
                              Supermemory bakeoff
                              - derived index only
                              - never permission authority
```

The Electron renderer is never part of the keystroke-to-suggestion path. It receives only settings, permission state, aggregate diagnostics, and explicit user actions.

## 6. Repository structure

The product will start in a new repository with these top-level boundaries:

```text
apps/
  desktop/              Electron main process and React renderer
services/
  api/                  TypeScript backend deployed to Vercel
native/
  macos/                Swift/AppKit helper and platform tests
  windows/              C#/.NET helper and platform tests; added later
packages/
  protocol/             Message schemas, fixtures, and contract tests
  database/             Authenticated Postgres access and repository tests
  evaluation/           Frozen multilingual and retrieval bakeoff corpus; not yet created
supabase/
  migrations/           Reproducible schema, indexes, grants, and RLS
  tests/                pgTAP allow-and-deny access tests
docs/
  architecture/         Product architecture and platform contracts
```

JavaScript packages use one workspace. Swift and .NET remain normal native projects inside the repository; they are not forced into the JavaScript build system.

## 7. Shared Electron product layer

### 7.1 Electron main process

The main process owns:

- Starting the correct signed helper for the current operating system.
- Verifying the helper protocol version during startup.
- Passing non-secret settings and short-lived auth state to the helper when required.
- Sending suggestion requests to the backend and forwarding one final result to the helper.
- Cancelling remote work when the helper reports a newer focus or content signature.
- Recording content-free latency and interaction events.
- App updates and helper-version coordination.
- Opening account, integration, and settings windows.

The main process does not decide whether Tab may be consumed. The native helper is the final authority because it owns current focus and suggestion state.

### 7.2 Renderer

The renderer owns ordinary product UI only:

- Permission onboarding.
- Clerk sign-in and account status.
- Personal and company context connections.
- Global pause and resume; there are no per-application switches.
- Privacy controls.
- Model-independent diagnostics.
- Update and connection status.

The renderer runs with context isolation, sandboxing, and no Node integration. A narrow preload API exposes only named product actions. Arbitrary IPC and raw helper messages are not exposed to renderer code.

## 8. Native helper contract

Electron launches one helper as a signed child process. Communication uses newline-delimited JSON over stdin and stdout:

- **stdin:** commands from Electron main to the helper.
- **stdout:** versioned protocol messages only.
- **stderr:** structured native logs with no draft contents by default.

This avoids local ports, discovery, and another authentication mechanism. The helper exits when its parent exits.

Every message includes:

- `protocol_version`
- `request_id`
- `focus_sequence`
- `content_signature`
- `timestamp_ms`
- a typed payload

Initial message types are:

| Direction | Message | Purpose |
|---|---|---|
| Helper → main | `hello` | Platform, helper version, protocol version, capabilities |
| Main → helper | `configure` | One boolean capability switch; the helper decides field eligibility |
| Helper → main | `permission_state` | Current OS permission status |
| Helper → main | `suggestion_request` | Bounded raw field context (shape, label, placeholder, text around the cursor, nearby fields) and current signatures |
| Helper → main | `cancel_request` | Current work became stale |
| Main → helper | `suggestion_final` | Final normalized continuation or explicit silence |
| Main → helper | `request_failed` | Retryable or terminal request outcome |
| Helper → main | `interaction` | Shown, accepted, partially accepted, dismissed, or typed through |
| Main → helper | `shutdown` | Ordered termination |

There is no backward-compatibility layer. Desktop and helper ship as one version. A protocol mismatch disables autocomplete and asks the user to update the application.

## 9. macOS helper

The first production helper uses Swift and AppKit.

It owns:

- Accessibility and Input Monitoring permission state.
- Focus tracking through Accessibility APIs.
- Editable-field capability and secure-field detection.
- Text before the cursor, selection, text after the cursor, and bounded field content.
- App identity and best-effort surface identity.
- Caret or field geometry with an explicit quality level.
- Listen-only keyboard observation.
- Conditional event consumption only while a valid suggestion is visible.
- A borderless, non-activating AppKit panel for ghost text.
- Type-through reconciliation.
- Word/phrase and full-tail acceptance.
- Text insertion and post-insertion verification.
- Cancellation and rejection of stale results.

The helper treats Accessibility as synchronous cross-process communication. It bounds work, avoids deep unbounded tree walks, and revalidates focus and content after every asynchronous boundary.

Insertion preference is:

1. A verified settable Accessibility value or text operation when the target supports it reliably.
2. Synthetic Unicode input for normal short text.
3. Clipboard paste for IME, long, or multiline text, with clipboard restoration that does not overwrite newer user activity.
4. A fresh Accessibility snapshot to verify the observed result.

There is one Accessibility-capability route for native and web text controls. Notes, Slack, Gmail, Chrome, Safari, and Codex are acceptance surfaces that earn support through packaged manual proof, never application-specific implementation branches.

## 10. Windows helper

The Windows helper is implemented after the Mac product proves the interaction and protocol. It uses C#/.NET rather than forcing Swift concepts or a cross-platform systems abstraction onto Windows.

It owns the same behavioural contract through Windows-native APIs:

- Microsoft UI Automation for focused elements, values, text ranges, selections, and caret state.
- `SetWindowsHookEx` with low-level keyboard hooks for observation and conditional consumption.
- A native non-activating, always-on-top overlay.
- ValuePattern, supported text patterns, `SendInput`, or paste according to target capability.
- Secure-field detection and application-specific exclusions.
- Stale-result checks, type-through, acceptance, insertion verification, and failure recovery.

UI Automation TextPattern is not treated as a universal editing API. It is primarily a text-reading interface; insertion falls back according to the target control's capabilities.

The initial Windows compatibility matrix will cover one native editor, one Microsoft productivity surface, and one Chromium/Electron surface. The shared Electron shell requires no product-UI rewrite; only permission guidance and platform-specific diagnostics differ.

## 11. Hot path and state machine

The automatic suggestion path is:

1. The native helper observes a meaningful text or focus change.
2. Deterministic local gates reject unsupported, secure, noisy, or ineligible states.
3. A short debounce waits for a natural pause.
4. The helper captures an immutable, bounded focus snapshot.
5. It sends `suggestion_request` to Electron main.
6. Electron main adds experiment assignment and authenticated request metadata, then calls the backend.
7. The backend retrieves only relevant, permissioned context and calls Gemini 3.5 Flash-Lite through Vercel AI Gateway.
8. Electron main waits for the validated completion and forwards one final result to the helper.
9. Before presenting anything, the helper compares focus sequence and content signature with current state.
10. A valid final result becomes ghost text. A stale result is discarded.
11. Continued typing reconciles with the suggestion or dismisses it. Focus change, navigation, Escape, or incompatible typing cancels it.
12. Tab is consumed only when the helper has a valid, visible, accept-ready suggestion.
13. The helper inserts the accepted portion, verifies the host result, and requests another continuation only when appropriate.

The native helper owns this state machine:

```text
idle
  → observing
  → debounce
  → requesting
  → visible
      → partial_accept → visible
      → full_accept → verifying → idle
      → type_through → visible or idle
      → dismiss → idle
      → stale → idle
```

Cancellation is normal lifecycle, not an error.

## 12. Context architecture

Context is split into three planes so intelligence does not force database latency into every suggestion.

### 12.1 Canonical context plane

Supabase Postgres is the source of truth for:

- Personal and organization spaces.
- Source identity, freshness, content hashes, and provenance.
- Documents, facts, preferences, instructions, episodes, policies, and proof.
- Temporal relationships: `updates`, `extends`, `derives`, and `evidence`.
- Clerk user and organization membership.
- Model-independent experiment assignments and content-free suggestion outcomes.

Every durable item belongs to exactly one personal or organization space. RLS checks that space on every client-visible record. A retrieved item is authorized again before prompt assembly. A vector index or managed memory result never becomes permission authority.

### 12.2 Derived context plane

The first owned retrieval implementation combines:

- `simple` Postgres full-text search for language-neutral token matching.
- Trigram search for names, codenames, brands, and incomplete words.
- HNSW vector search using `google/gemini-embedding-2` at 1,024 dimensions.
- Reciprocal rank fusion over lexical and semantic candidates.
- Provenance, validity, language, recipient, and freshness checks after retrieval.

Embeddings and extracted facts are rebuildable derivatives. Source records remain canonical. Changing an embedding model requires re-embedding; it does not rewrite source or permission data.

Supermemory hosted is tested as an alternative derived engine using the same frozen corpus. Its container is scoped per personal or organization space, and every returned source identifier is re-authorized against Postgres. We keep it only if it creates a material quality advantage after latency, deletion, isolation, and cost are measured.

### 12.3 Device hot-context plane

The helper maintains an encrypted SQLCipher store containing only context already authorized for the signed-in user and needed for current work. It never mirrors the full company repository.

Context preparation begins on app, field, conversation, document, selection, or recipient change. The device builds a small context capsule before a typing pause. A passive request therefore uses local live-field state plus a prepared capsule; it does not start with a remote database search after every keypress.

A capsule contains:

- App and surface identity.
- Language and script.
- Recipient or audience when known.
- Bounded text around the caret.
- Relevant source identifiers and short grounded facts.
- Permission and freshness timestamps.
- A content signature and expiry.

The first MVP uses live field context plus manual personal and company profiles. Connectors, meetings, repositories, and broader activity streams come after the loop works. Meetings are one source, never the center.

Raw keystrokes are never stored as history. Live drafts are not logged by default. Screenshot OCR remains a separate opt-in data path.

### 12.4 Multilingual contract

The generation model infers language directly from the visible text and bounded context. The native client does not classify language or pass a language override. Retrieval may cross languages; generation must continue the field's current language, script, locale, formality, and natural code-switching unless the user explicitly asks to translate.

Baseline coverage targets more than 100 languages through the multilingual embedding and generation stack. Certification begins with English, Spanish, Portuguese, French, German, Italian, Dutch, Japanese, Simplified and Traditional Chinese, Korean, Arabic, and Hindi. Each certified language must pass the same usefulness, latency, exact-name, and leakage tests. RTL layout, IME composition, CJK segmentation, accents, and mixed-language text are explicit native test cases.

## 13. Backend

The backend is a new TypeScript service on Vercel. It owns:

- Clerk access-token verification.
- User, organization, and permission resolution.
- Context retrieval and bounded prompt assembly.
- Passive versus explicit request policy.
- Show-or-suppress decisions.
- The fixed AI Gateway generation boundary.
- Request budgets, timeouts, and cancellation.
- Privacy-safe evaluation events.
- Admin-only experiment configuration.

The desktop never receives provider credentials. Model and provider changes happen server-side.

The database is a new Supabase Postgres project. The initial reproducible schema lives in `docs/autocompletion/build-ready/supabase/` until the new product repository is created, then moves unchanged to that repository's `supabase/` directory. Large source bodies will use a private Supabase Storage bucket when file ingestion enters scope; they never enter telemetry tables.

### 13.1 Why this data stack

**Supabase is the canonical store** because this product needs relational integrity, native Postgres RLS, pgvector, full-text and trigram search, current first-party Clerk token support, reproducible SQL migrations, local development, and database-level allow-and-deny tests in one system. The permission boundary must survive a bug in an API handler.

**Neon is a credible Postgres alternative**, not a rejected technology. It supports pgvector, Clerk-compatible JWT RLS, and strong scaling options. It is not the first choice because Supabase gives this particular MVP the database, Data API, third-party Clerk integration, Storage path, and local pgTAP workflow with fewer separate pieces. The schema uses ordinary Postgres primitives so a future move remains possible if measured performance, reliability, or economics justify it.

**Convex is attractive for reactive product state**, but it would move the main authorization boundary into application functions and model the canonical context as documents. Its vector search also runs through actions and offers a narrower filtering model than the relational permission and temporal joins required here. We prefer database-enforced RLS and foreign keys for personal-versus-company intelligence. Electron UI state does not require Convex's reactive database enough to offset that trade.

**Supermemory is a context engine, not the account ledger or permission authority.** It can ingest, organize, and retrieve memories well, so it remains in the controlled retrieval bakeoff. Postgres still owns users, organizations, provenance, deletion, freshness, consent, and the final authorization check.

**Google, Cohere, and Voyage provide embedding models, not the database.** Their vectors are rebuildable derivatives stored beside a model ID. Changing the embedding winner must not change ownership or source truth.

**OpenClaw and Hermes provide design lessons, not a stack to copy.** We keep their useful pattern of durable canonical memory plus a small local searchable layer and background consolidation. We do not copy their agent-centric trust assumptions into a multi-tenant product that can place company facts into human messages.

## 14. Authentication and secrets

The product uses a new Clerk application configured as a public desktop client with Authorization Code and PKCE.

- Sign-in opens the system browser.
- The Electron main process completes the callback.
- Refreshable credentials are stored in the macOS Keychain or Windows Credential Manager.
- The renderer receives account state, not raw refresh tokens.
- The native helper receives no long-lived Clerk or provider secret.
- Backend calls use short-lived access tokens.
- Supabase is configured with its current Clerk third-party auth integration, not the deprecated shared-JWT-template integration.
- RLS reads Clerk's `sub` claim as the user identifier. Organization membership is also persisted in Postgres so revoked access can be enforced without trusting user-editable metadata.
- Administrative sync and ingestion may use a server-only Supabase secret; it never reaches Electron or the native helper.

## 15. Model and serving design

There is no model choice in the desktop application. The backend has one production model/provider pair: `google/gemini-3.5-flash-lite` through Vercel AI Gateway. AI Gateway uses Vercel OIDC in deployments or `AI_GATEWAY_API_KEY` outside Vercel; `AI_DIAGNOSTICS=full` remains content-free: it records only timing, token counts, finish reason, and error kind. There is no production route selector.

Each suggestion uses exactly one model call and is shown only after the final result is available and validated. The deterministic product gate selects `line` or `block` from field capability and safe insertion shape; it does not infer language or semantic intent. Line continuation uses final plain text with low thinking and a 2.5-second server deadline. Block or artifact composition uses one final structured object with low reasoning and an 8-second deadline. The desktop cancels the whole request after 10 seconds, while native cancellation invalidates work immediately when the field changes. Gemini interprets field intent, language, code-switching, tone, and continuation. There is no partial ghost, client-side intent classifier, language classifier, model catalog, second model call, application-specific route, or model/provider fallback.

Protocol v3 may carry up to three bounded user-authored artifacts with provenance. The native helper owns this evidence on the same Accessibility path as field capture: it may retain the current selection for 60 seconds and, only with explicit clipboard opt-in, the current clipboard version for 10 minutes. It keeps no history, clears retained evidence when capture is disabled, and never lets Electron reread or enrich the request. The model composes its answer from generated text parts and artifact references. The server expands references to the original bytes, snaps near-verbatim reproductions back to their unique source, and silently discards unknown or malformed compositions. An empty multiline field with an artifact receives a block budget on every supported surface; that budget grows to the exact artifact length, within the protocol's 4,000-UTF-16-unit artifact limit, so authored multiline material is not truncated.

The first owned retrieval bakeoff compares:

- `google/gemini-embedding-2` at 1,024 dimensions.
- `cohere/embed-v4.0` at 1,024 dimensions.
- `voyage/voyage-4` and `voyage/voyage-4-lite` at 1,024 dimensions.
- Supermemory hosted hybrid search as an end-to-end managed baseline.

The MVP implements Gemini Embedding 2 first because it provides one multilingual, multimodal space. Embedding calls are cached by content hash and model ID. Reranking is excluded from the passive synchronous path; it may run during prefetch or explicit summon after measurement.

The explicit summon path may later use a stronger or slower remote model, but this remains invisible to the user. There is one interaction surface.

No model wins from a public benchmark alone. The product bakeoff measures:

- Pause-to-first-visible-ghost p50 and p95.
- Provider and regional variance.
- Stale cancellation rate.
- Shown-suggestion rate.
- Full and partial acceptance rate.
- Accepted characters per active day.
- Semantic usefulness in English and Spanish.
- Human-writing and agent-prompt completion quality.
- Cost per accepted character.
- Distraction rate.

The corpus combines frozen, consented scenarios with shadow traffic and blinded human preference. Draft contents are excluded from routine production telemetry unless the user explicitly contributes a sample to improve the product.

## 16. Confidence and suppression

Silence is a product decision. A model's self-reported confidence never decides whether a suggestion appears.

Suppression has three layers:

1. **Native eligibility:** secure-field block, supported surface, valid geometry, sufficient context, no incompatible composition, typing-pause boundary, cooldowns, and current permission state.
2. **Backend policy:** app and field priors, context relevance, suggestion shape, output safety, recent interaction outcomes, and experiment thresholds.
3. **Learned acceptance policy:** introduced only after enough opt-in accept/reject data exists. It predicts whether showing a suggestion is worth its interruption cost.

The product optimizes accepted useful work, not the number of generated words.

## 17. Privacy and security

### Native boundary

- Secure and excluded fields are blocked before request construction.
- The helper accepts commands only from its parent stdio channel.
- Helper and desktop binaries are signed and shipped together.
- Protocol mismatch fails closed.
- Generated input events are tagged or suppressed from re-entering the observation loop.

### Electron boundary

- Renderer sandboxing and context isolation are mandatory.
- Node integration is disabled in the renderer.
- Preload exposes a narrow allowlist.
- External navigation and new-window creation are denied unless explicitly allowed.
- Auth tokens and helper IPC remain in the main process.

### Backend boundary

- Provider credentials remain server-side.
- Logs exclude live text and retrieved source bodies by default.
- Context sources retain ownership, permission, recipient, and freshness metadata.
- Sensitive topics and cross-recipient context fail closed.
- Zero-data-retention provider policy is enforced before production release.

### Telemetry boundary

Default events may contain:

- Request and experiment identifiers.
- Coarse application category.
- Latency and token counts.
- Suggestion length.
- Shown, accepted, partially accepted, typed through, dismissed, or stale outcome.
- Error class without content.

They do not contain field text, suggestion text, clipboard contents, screenshots, or retrieved documents.

## 18. Failure behaviour

| Failure | User-visible behaviour | System behaviour |
|---|---|---|
| Helper unavailable | Autocomplete off; settings explain why | One controlled restart, then remain disabled |
| Permission missing | Guided permission state | No capture or generation |
| Unsupported or secure field | No suggestion | Fail closed before context construction |
| IPC mismatch | Update required | No compatibility fallback |
| Network or model timeout | Silence | Cancel, record content-free error class, apply short backoff |
| Provider failure | Silence | Record the content-free error class; never route to another provider or show late output |
| Focus/content changed | Nothing stale appears | Discard by signature before presentation |
| Insertion not verified | Do not repeat automatically | Dismiss session and record insertion failure |
| Electron renderer crash | Existing ghost session is dismissed | Main process remains authority; renderer can reload |
| Main process exits | Product exits | Native helper exits with parent |

## 19. Performance targets

These are proposed product gates, not current measurements:

- Pause-to-visible-ghost p50: **700 ms or less**.
- Pause-to-visible-ghost p95: **1,400 ms or less**.
- Native capture plus local IPC p95: **25 ms or less** on supported fields.
- Local capsule lookup p95: **30 ms or less**.
- Remote retrieval on the passive critical path: **zero after a valid capsule is prepared**.
- Context prefetch p95: measured separately and never allowed to delay focus or typing.
- Stale suggestions displayed: **zero**.
- Tab without a valid visible suggestion: **100% pass-through**.
- Secure fields entering request construction: **zero**.
- Verified insertion success in the initial app matrix: **99.5% or better**.
- Accepted shown suggestions after initial calibration: **25% or better**, with a separate distraction guardrail.

If remote models cannot meet the latency gate, the product suggests at stronger boundaries—such as sentence endings and longer pauses—rather than reintroducing local generation.

## 20. First-week Mac vertical slice

The first week must produce a complete, impressive loop rather than isolated infrastructure.

It includes:

- New repository and JavaScript workspace.
- Electron main process and minimal settings/onboarding window.
- Signed Swift helper launched through the versioned stdio protocol.
- Accessibility and Input Monitoring onboarding.
- Focus, text, selection, and caret capture in Notes and Slack.
- Focus, text, selection, and caret capture in one Chromium browser prompt surface.
- Secure-field and unsupported-field gates.
- A new Clerk app and local Supabase project using the checked-in migration and RLS tests.
- Manual personal and company profile fields that create grounded context items.
- One embedding route for `google/gemini-embedding-2` and hybrid retrieval over those profiles.
- One `google/gemini-3.5-flash-lite` generation route through Vercel AI Gateway.
- Offline model comparison tooling that cannot change production routing.
- Streamed native ghost text.
- Tab acceptance, Escape dismissal, type-through, and stale cancellation.
- Post-insertion verification.
- Content-free latency and interaction telemetry.
- A repeatable frozen bakeoff corpus in English and Spanish plus structural smoke cases for the twelve initially certified languages.
- A local development `.dmg` or zipped `.app` artifact. A publicly downloadable notarized build requires the Apple signing credentials supplied later.

It does not include Windows implementation, external connectors, meetings, document ingestion, OCR, billing, or automated long-term memory extraction.

The week is successful only if the full user journey works in Notes, Slack, and the selected browser prompt surface and produces measured latency and correctness results. A source build, simulated overlay, or backend response alone does not satisfy the gate.

## 21. Windows expansion gate

Windows implementation begins after the Mac slice demonstrates:

- The interaction is useful enough to keep.
- The helper protocol survived at least one real product iteration.
- The model bakeoff produced an acceptable remote serving path.
- Stale cancellation, Tab ownership, secure-field blocking, and insertion verification meet their gates.

The Windows helper then implements the same behavioural contract against the existing protocol. Contract fixtures and state-machine tests are shared; OS integration tests remain native.

The first Windows app matrix should include:

- Notepad or another native Windows editor.
- Outlook or another Microsoft productivity surface.
- Slack or a Chromium browser field.

## 22. Testing strategy

### Shared contract tests

- Protocol schema fixtures accepted by Electron, Swift, and C#.
- Request identity and cancellation sequences.
- Final-response identity and bounded-payload validation.
- Protocol mismatch and malformed-message failure.

### Native state-machine tests

- Eligibility and secure-field gates.
- Focus/content signature changes.
- Type-through and partial acceptance.
- Tab pass-through and consumption.
- IME and composition boundaries.
- Insertion verification.

### Application integration matrix

- Real typing, navigation, focus change, selection, partial accept, full accept, and dismissal.
- Native and Chromium/Electron surfaces.
- Password and excluded fields.
- Large text, multiline text, and non-Latin input.

### Backend and model tests

- Retrieval permissions and recipient boundaries.
- Timeouts, cancellations, and provider failures.
- Frozen-corpus latency and quality bakeoff.
- Content-free telemetry enforcement.
- ZDR routing policy.

### Release tests

- Signed helper identity and parent lifecycle.
- macOS notarization and permissions after update.
- Windows code signing and installer behaviour when that client exists.
- Auto-update keeps desktop and helper on one protocol version.

## 23. Build sequence

The product grows in working layers:

1. **Mac loop:** Electron shell, Swift helper, backend, one remote model, Notes, Slack, and one browser prompt surface.
2. **Grounded context loop:** manual personal and company profiles, Supabase RLS, Gemini embeddings, hybrid retrieval, and the device capsule.
3. **Quality loop:** generation and retrieval bakeoffs, suppression, multilingual evaluation, acceptance telemetry, app adapters, and reliability gates.
4. **Windows loop:** C# helper implementing the proven protocol.
5. **Surface depth:** browser, email, AI prompts, Figma, sales, support, and other high-value editable moments.

Each layer ships on top of a working product. Windows preparation is the stable protocol boundary, not an unfinished Windows implementation inside the first Mac release.

## 24. Decisions deliberately left to experiments

These are not architectural gaps:

- Which remote model wins passive autocomplete.
- Which provider and region meet latency and privacy requirements.
- Whether owned hybrid retrieval or Supermemory produces the better context engine.
- Whether Gemini, Cohere, or Voyage embeddings win the frozen retrieval corpus.
- The optimal debounce and suppression thresholds.
- The exact context budget by surface.
- Whether a specialized FIM model adds value for non-code writing.
- When acceptance data justifies a learned show-or-suppress policy.

Each decision has a named bakeoff or production metric. None requires changing the native-helper boundary or the product interaction.

## 25. References

- [Electron overview and supported platforms](https://www.electronjs.org/docs/latest/)
- [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)
- [Electron global shortcuts](https://www.electronjs.org/docs/latest/api/global-shortcut)
- [Electron native modules](https://www.electronjs.org/docs/latest/tutorial/using-native-node-modules)
- [Electron security guidance](https://www.electronjs.org/docs/latest/tutorial/security)
- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Cotabby architecture](https://raw.githubusercontent.com/FuJacob/cotabby/main/ARCHITECTURE.md)
- [Windows UI Automation overview](https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-uiautomationoverview)
- [Windows TextPattern overview](https://learn.microsoft.com/en-us/dotnet/framework/ui-automation/ui-automation-textpattern-overview)
- [Windows low-level hooks](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw)
- [Gemini Embedding 2](https://ai.google.dev/gemini-api/docs/embeddings)
- [Supabase Clerk integration](https://supabase.com/docs/guides/auth/third-party/clerk)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase hybrid search](https://supabase.com/docs/guides/ai/hybrid-search)
- [Neon AI and pgvector](https://neon.com/docs/ai/ai-concepts)
- [Neon RLS and external auth](https://neon.com/docs/manage/projects#neon-rls)
- [Convex vector search](https://docs.convex.dev/search/vector-search)
- [Convex authorization patterns](https://stack.convex.dev/authorization)
- [Supermemory architecture](https://supermemory.ai/docs/concepts/how-it-works)
- [Supermemory multi-tenancy](https://supermemory.ai/docs/concepts/multi-tenancy)
- [OpenClaw memory architecture](https://github.com/openclaw/openclaw/blob/main/docs/concepts/memory-architecture.md)
- [Hermes Agent](https://github.com/NousResearch/hermes-agent)
- [Clerk public clients and PKCE](https://clerk.com/docs/guides/configure/auth-strategies/oauth/how-clerk-implements-oauth)
- [Artificial Analysis performance methodology](https://artificialanalysis.ai/methodology/performance-benchmarking)
- [Cursor's Fusion autocomplete model](https://cursor.com/blog/tab-update)
- [Cursor's online autocomplete reinforcement learning](https://cursor.com/blog/tab-rl)
