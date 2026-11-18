# Autocomplete Everywhere MVP implementation record

Approved scope: reliable inline assistance, lower generation waste, and opt-in bounded preference learning. This record tracks implementation, not a release claim.

## Order and gates

1. **Implemented and package-verified:** 90-case acceptance ledger and truthful generation outcomes.
2. **Implemented and package-verified; real-surface gates open:** shared measurement, visible-text/insertion consistency and editor-family evidence.
3. **Library foreground work removed; generation baseline retained:** compact prompts and removal of inactive Library work; controlled production-generator comparison before adopting output-mode changes.
4. **Implemented, reviewed and packaged; live learning quality unproven:** verified correction observation, encrypted account-scoped learning and authenticated background extraction.
5. **Personalization packaged and Save/Revert verified; release gates open:** native Writing Save/Revert with strict saved snapshot acknowledgement.

Each implementation layer must build and package before the next. A successful package does not close real-application acceptance gates. The model remains Qwen 3.8 27B on Cerebras, one final foreground generation without fallback. Library stays disabled. The initial checkpoints below are historical; subsequent authorized changes were committed and pushed. The matching API and local development package were rolled out together after validation; distribution approval remains gated by notarization and real-surface evidence.

## Evidence

The machine-readable [acceptance ledger](../qa/autocompletion-acceptance-ledger.json) preserves all 90 atlas cases. Entries start untested; previous demonstrations do not prove the current package. Cases requiring unavailable authoritative sources remain explicit.

Known release blockers retained separately from semantic atlas cases:

| Gate | Status | Evidence needed |
|---|---|---|
| Codex second line, soft wrap and font size | Failed: user report | Real visible preview, caret and accepted text on current package |
| LinkedIn Tab acceptance | Failed: user report | Verified exactly-once insertion and host-key pass-through |
| Notes wrapping and container width | Failed: reported discrepancy | Real multiline and soft-wrap geometry |
| Native plain/rich text, browser inputs/contenteditable, Electron, WebKit, custom/code/terminal | Not tested as a matrix | Empty, mid-paragraph, newline, zoom, scroll, resize, mixed-script and IME cases |
| Oldest supported macOS (14) | Requires unavailable evidence | Device/VM running the signed candidate |
| Current macOS | Not tested for this candidate | Packaged end-to-end verification |
| Clean install and notarization | Not tested | Installer, signing/notary validation and fresh profile |

## Learning contract

Learning starts off. Only verified corrections to accepted text contribute style evidence. Raw snippets remain in bounded RAM for at most five minutes; observation ends after 30 seconds or lost field/range authority. Loss of visibility is unknown. No inference that text was sent.

Extraction waits for 30 seconds without typing, cancels on typing, and is bounded to one request per 15 minutes and 12 per day. The same model is used through a separate authenticated endpoint. Only concision, formality and paragraph/list preferences may be extracted. Three supporting corrections in two writing sessions activate an app-scoped preference. Explicit user edits are authoritative; current draft intent and language remain strongest. Encrypted state is account-scoped. Disable stops activity and deactivates preferences; reset deletes candidate and active learned preferences.

## Execution decisions

- Continue in the existing authorized shared checkout to preserve the running prototype and accumulated changes. Restrict each implementation task to owned files; do not reset or commit others' work.
- Preserve restricted or unavailable UI evidence as open gates; do not circumvent tool access restrictions.
- No provider cost or latency savings are claimed until measured with fixed-model, fixed-case comparisons including failures and cancellations.

## Layer 1 checkpoint — 2026-09-05

Created all 90 atlas entries plus 91 editor-family checks. No new real-surface pass is claimed. Generator/app regressions now distinguish malformed output, timeout, cancellation and provider failure from deliberate silence, while preserving final `text/plain` success and exact artifacts. Focused API tests: 110 passed; API typecheck and build passed. Signed desktop package integrity passed (`/tmp/autocompletion-mvp-layer1-package.log`); notarization was skipped and remains open. API changes are local, not deployed. Independent code review passed, including the raw-control follow-up.

## Benchmark preparation

Added `--mvp` to the existing workload runner. This executes the actual production generator and HTTP finalizer with current deadlines/settings, one call and no sample retry. Its first candidate changes JSON whitespace only; ordering alternates. Four focused regressions passed. No runtime prompt or model/output setting changed.

Live preflight is blocked: `CEREBRAS_API_KEY` is unavailable in this process/local environment (`/tmp/autocompletion-mvp-benchmark-preflight.log`). Nonempty responses are not automatically marked useful. Useful-response latency, retained-acceptance ratios and costs remain unmeasured. Pricing pages were consulted but the model's rates were not available in their retrieved primary-source content; no secondary-source estimate was substituted.

## Layer 2 implementation — 2026-09-05

Shared web font calibration now requires a contained single-line sample attached to independently measured line/caret evidence. Full suggestion text must fit the preview, including the bottom edge; clipped paragraphs and overflowing single lines no longer remain acceptable as full text. No font is enlarged to fill available space. Fitting geometry refreshes retain the same final text and identity.

Insertion preparation now runs off-main before Tab/click eligibility, tied to the current presentation and revoked on changes. Insertion prepares again before writing. Known unavailable insertion methods pass host keys through. A focus change after a valid key was consumed can still cancel the write; no unsafe delayed key replay was added.

Fresh focused checks: 198 geometry/presenter/layout tests and 157 controller/keyboard/insertion/session/monitor tests passed (overlapping suites; do not add counts). Swift build passed. Independent review passed. These repairs can suppress formerly clipped suggestions; no invisible suffix is accepted. Codex/LinkedIn/Notes visual gates remain open.

## Further checkpoints

Layer2 signed package integrity passed (`/tmp/autocompletion-mvp-layer2-package.log`). Layer3 removed inactive Library acquisition and its request data; two focused tests and desktop typecheck passed. Its signed package integrity passed (`/tmp/autocompletion-mvp-layer3-package.log`); independent review passed. No runtime prompt/model/output optimization was adopted. The 24 workload-runner tests passed.

Existing Vercel access subsequently permitted a credential export. Both benchmark arms then failed all 30 attempted calls; each also had two no-call eligibility suppressions. A single bounded diagnostic showed upstream HTTP401 for the CLI-exported value. The deployed backend credential is not thereby verified or disproven. These measurements are authentication rejection, not generation latency; no token savings or useful-response quality can be inferred. See `/tmp/autocompletion-benchmark-diagnostic.md`.

## Cooldown checkpoint

Explicit dismissal now requires an authored edit and a five-second cooldown; repeated dismissal within a minute uses fifteen seconds. Manual generation bypasses the cooldown without causing a duplicate request at expiry. A subsequent new draft still resumes at the original deadline. 88 focused native tests and build passed, followed by independent review and signed package integrity (`/tmp/autocompletion-mvp-cooldown-final-package.log`).

## Learning integration in progress

Protocol4 adds content-free activity/outcomes and a private bounded verified-correction message. Backend extraction and shared schemas are implemented:143 focused API tests and8 schema tests pass, with API build/check. Foreground instructions are unchanged when preferences are absent. Native Writing controls pass60 tests, including malformed acknowledgements, automatic additions during unsaved edits, explicit null scope, reset/revert and account changes during save. Desktop service and native range observation are still being integrated; these counts are implementation evidence, not real-app learning outcomes.

## Final implementation checkpoint — 2026-09-05

All five implementation layers are present. Independent review closed account ABA save races, malformed native acknowledgement scope, unreadable-encryption quota reset, cancellation while OAuth refresh stalls, and in-flight raw-observation memory bounds. Final desktop tests:165 passed; API:196 passed (46 app tests rerun after the Vercel type-narrowing fix); protocol:51 passed; database:3 passed. All workspace TypeScript checks passed. Native helper:506 total,503 passed and3 opt-in live tests skipped; native Settings:62 passed. Signed package integrity passed after the production-source freeze (`/tmp/autocompletion-mvp-final-package.log`).

Production API `<deployment-id>` was built cleanly, staged, then promoted. Canonical `/health` returns200 and the new extraction route returns401 without authentication. Local Autocomplete Everywhere was restarted with the matching protocol4 package (desktop27644, Settings27659, helper27660 at verification). No commit or push occurred. This is a development rollout, not a claim of release readiness.

The packaged native Writing screen was visually inspected. A learning opt-in draft was reverted without enabling learning. Timing was changed from Quick to Balanced, saved with a real persisted acknowledgement, then restored to Quick and saved. Library remains absent; learning remains off.

The deployed generator also returned real text in the owned practice field: request `F06D1D72-AA97-460E-BF62-F9F27EE15D50`, final HTTP200 in711.9ms, native final accepted then presented/shown reported. This single observation is neither a p50/p95 benchmark nor a visual acceptance pass. The app-window screenshot did not show the helper overlay; the tool's Tab inserted a literal tab, so physical acceptance remains unverified. The practice sheet was closed. Notes background editing succeeded, but real foreground confirmation remained unavailable. Codex, LinkedIn, Notes wrapping, full family coverage, live preference extraction/benefit, macOS14, clean install, and notarization remain open.

Only an Apple Development signing identity is available on this Mac. No Developer ID distribution signing/notarization result is claimed. Local model benchmark credentials failed401 while the deployed production model later responded successfully; the failure applies to the exported local credential, not the deployed provider. No prompt/output optimization was adopted and no cost saving is claimed. The production generator baseline was retained as required when an equivalent controlled comparison could not be completed.

Final artifact SHA256:
- app.asar: `dcabb00a292e2392af4d32fbd4f5dba8cb8173d62ce3ea5b66e2ca7888e21220`
- helper: `e4009bee9e456400aa3ac93a0f5c4987ea0ef86056c5fcefca396809db9544d2`
- Settings: `f7924d55664845d4ed4a7e594a26c9df3793f699757f69b757e618010bcfbae3`

See the acceptance ledger's productChecks for narrowly verified product actions. The90 semantic cases and91 editor checks have not been converted into passes based on unit tests or this practice request.

## Codex continuation follow-up — 2026-09-05

The user reported missing continuations and incomplete last-message context again after the MVP push. Recent content-free traces contain successful final text responses followed by `anchor_unavailable`, plus requests with zero read-only sources. These traces do not themselves identify the application or prove the semantic contents of its last message.

A regression reproduces a shared measurement bug: an off-editor glyph with height37 calibrates a valid height22 line, causing that line to fail height validation. Height calibration now uses only valid, contained, display-backed samples. This does not relax caret containment or guess editor padding. The test failed before the fix and passed afterward.

Source traversal also stopped after four ancestors even when they were only layout wrappers. A failing nested-composer test now passes with bounded deeper ancestry; the original128-node total budget,50ms read deadline, document/window boundaries, six-source limit, and visibility checks remain. New categorical diagnostics distinguish source-read deadline exhaustion from no visible sources; no source text is logged. This change does not assert that a nearby sibling is the intended reply target.

Focused validation:147 native tests passed, including geometry, source visibility, traversal limits, and diagnostic opt-in/deduplication (`/tmp/autocompletion-codex-final-tests.log`). Real Codex continuation, last-message relevance, and the existing editor-family release gates remain unverified; do not promote ledger cases to Passed from these regressions.

The full native suite subsequently passed570 tests with3 live opt-in tests skipped (`/tmp/autocompletion-codex-native-suite.log`). The signed development package passed integrity verification (`/tmp/autocompletion-codex-context-package.log`), and the matching desktop/helper restarted with capture enabled and both required permissions granted. Helper SHA256: `3f444ae53958ec70e7b0aac561d01c645bf602ea4e48d560596c0ba544c1c2ea`. Notarization remains unavailable. A manual Codex continuation check was requested; no real-surface success is asserted without its result.

## Repeated manual invocation — 2026-09-06

The user confirmed that Codex showed a continuation, but reported intermittent failure, including explicit invocation. Subsequent traces include source counts5–6 and successful presentation, alongside four final-text responses rejected as `presenter_paragraph_outside_visible_field`. This is limited evidence of improvement, not general Codex coverage or proof of last-message relevance. The older `session_unavailable` presentation event also occurs for deliberate silence and must not be counted automatically as a rendering failure.

A regression with queued main-thread callbacks reproduced a separate manual-invocation bug. Resetting capture advances its generation, so a queued invalidation of the old ready result can be superseded. The ready-result reuse guard then swallowed the explicit request. Automatic geometry refresh still reuses the final result; explicit invocation now requests a replacement. The test covers visible and hidden previous results, stale-response rejection, presentation of the replacement after fresh geometry, and no dismissal feedback from retrying.

Desktop traces now retain the request's content-free `explicit` boolean, separating at-keyboard invocations from automatic requests. Validation:571 native tests passed with3 live tests skipped,12 desktop tracing/coordinator tests passed, and desktop typecheck passed. Signed development package integrity passed (`/tmp/autocompletion-manual-package.log`) and Autocomplete Everywhere restarted. No API/model/prompt change was made. The user was asked to verify two successive manual invocations. Oversized inline replies and real-surface manual verification remain open; no text is cropped or accepted invisibly to claim a pass.

## September 6 current capture checkpoint

Commits `9a6028b` and `e369c14` are pushed. The latest development package includes viewport-priority source traversal, per-capture structural attribute reuse, and display initialization before observation. Long-history, middle-scroll, same-reader source replacement/hiding and 20 first-attempt source acquisitions were verified against the owned native fixture. See [full evidence and remaining gates](../qa/2026-09-06-viewport-reply-source.md). This does not close Codex, semantic continuation quality, learning benefit, or distribution gates. The 90-case semantic atlas and 91 editor checks must not become Passed from these isolated source-reader tests.
