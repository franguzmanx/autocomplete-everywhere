# Autocomplete Everywhere intelligence implementation — 4 September 2026

Spec: `invisible-intelligence-product-design.md`, `scenario-atlas.md`, and the user's request to implement the whole product, beyond its controls.

## Requirements

One Qwen/Cerebras final generation, no streaming or provider fallback. Read the active writing situation through generic Accessibility capabilities. Keep read-only source evidence separate from the author's draft and reusable knowledge. Bind suggestions to source revisions as well as the field. Never capture secure/excluded applications, promote observed third-party text to user beliefs, or send anything automatically. Preserve existing work in this authorized checkout.

## Tasks

1. Native scene: bounded visible read-only AX sources, structural provenance, retained while typing, revised when the source changes. Include source context in cancellation, presentation and insertion identity. Explicit invocation reaches the request; unrelated incidental memory cannot authorize an empty-field suggestion. Tests cover source changes and privacy boundaries.
2. Local library: encrypted, bounded, user-editable memory/knowledge/style entries with revisions, dates and explicit app/topic scope. Plain text/Markdown import, replace and delete. Pre-index locally; source/draft matching only ranks candidates after scope checks. No automatic promotion of observed facts. Integrate settings and IPC with real storage and invalidation.
3. Generation: carry source and scoped library candidates to the existing provider; prioritize draft intention, source relationship and authority. Abstain when source/intent is insufficient. Stop injecting the old unscoped profile. One bounded complete output, stable prompt prefix and content-free timing.
4. Product integration: fix menu icon sizing, connect knowledge to transport, cancel work on edits/deletions and exclusions, preserve minimal onboarding and existing controls. Package and deploy the matching contracts.
5. Verification: focused regression tests, workspace/native checks, independent review, signed package, actual application source-to-ghost and persistence journeys. Record unavailable capabilities honestly. AX absence is not evidence of source understanding; visual-only understanding requires its own demonstrated implementation.

## Interface ownership

- Native task owns `native/macos/**`. New `fieldContext.sources` always encodes an array (maximum 6): `{id, containerId, relation: labelled_by | described_by | shared_container, text}`; IDs are content-free stable hashes, text maximum 2000 UTF-16 units each. A structural relation is evidence, not a claim that a post is definitely the reply target.
- Library task owns new library modules, `packages/protocol/src/knowledge.ts`, Settings/library UI, shared bridge contracts, preload, IPC and security allowlist. It exports a main-process store/service; root wires it into index and transport. Library candidates use a separately exported schema/type. No captured draft is sent to settings.
- Root owns protocol messages, backend, main index/coordinator/transport, tray, documentation and verification. Cross-task interfaces are agreed before consumers are changed.

## Evidence ledger

Implemented: native read-only source capture and revision binding; encrypted local library and real settings/IPC; synchronous scoped retrieval before the existing provider request; removal of the unscoped remote profile; exact-artifact output preservation; native menu images bounded to 16 points.

Independent implementation and integration reviews found and corrected exact-artifact mutation, incomplete context identity, duplicate source IDs, viewport clipping, and inadmissible candidates consuming the source budget. A subsequent runtime correction makes system Accessibility focus authoritative instead of asynchronous workspace/menu metadata; its scoped review found no remaining issue.

Verification on 4 September: workspace checks pass; desktop 134, API 132, protocol 41, database 3 and native 414 tests pass (724 total). The final native resume/edit correction also received a scoped independent review with no actionable finding. Signed Apple Development packages pass the package integrity check; they are not notarized releases.

The matching API is deployed and promoted as `<deployment-id>` at `https://your-api.example.com`; health returned 200. Model/provider remain Qwen 3.8 27B/Cerebras. Deployment health is not evidence of authenticated generation or contextual quality.

Actual packaged-app checks: a synthetic app-scoped reference was saved encrypted, restored after restart, and replaced through the native file dialog. Its UI displayed revision 2 and imported-file provenance. Fifteen-minute pause disabled the helper; resume cleared the deadline. The application switch persisted the SceneLab exclusion and was restored after the check.

The final package recognizes same-field draft edits delivered through Accessibility/dictation as an opportunity after resume. Initial content, caret/selection movement and source-only changes do not clear that gate or count as authored memory.

Live SceneLab evidence from the final package:

| Journey | Observed result |
| --- | --- |
| Draft plus current read-only message | Native request `AFB39F3E-0983-4C3B-AFCD-7D9898EAAA16` admitted 4 sources and 0 library references. Authenticated production HTTP returned 200/text; helper accepted the final response and emitted `presented`. Edit-to-presented was approximately 1.55 seconds, including 301 ms quiet time. |
| Source changes while draft stays the same | Changing the fixture message from Tuesday/plans to Thursday/budget cancelled ready request `F5323C37-8E8F-4BCB-8244-B89102C75FA5` with `content_changed`, then request `2B88A34F-14C8-4C46-B2FF-E61C9A2B53A6` used 4 refreshed sources and reached `presented`. No draft edit was needed. |
| Scoped library in a real request | Draft naming Orquidea QA admitted exactly 1 library candidate, unlike the Jacaranda drafts' 0. Request `CC780162-DFA5-4FC0-8CD4-0634A5E5EFFA` returned production 200/text and reached `presented`. This establishes selection and transport, not that the model chose the right identifier. |

The source-change and clean-draft requests took approximately 1.05–1.33 seconds to the helper's presentation event; the first reference query approximately 1.56 seconds. Context preparation observed 0–21 ms. These are a few controlled observations, not a latency benchmark or a quality-adjusted speed claim. Native capture has cooperative budgets and showed an 83 ms source-refresh sample, so 50 ms is not a guaranteed total capture ceiling.

**Acceptance remains unverified:** the computer-use screenshot contains only SceneLab's own window, not the helper's separate overlay. Its synthetic Tab reached the host as a literal tab instead of traversing the global keyboard hook. A physical visual/Tab check was requested from the user. There is no observed accepted insertion or verified final wording from this run, and no claim that the 90-case atlas or real Slack/email/social applications passed. The Settings icon size is fixed in code and the running package, but the actual tray menu has not been visually re-captured.

## Decisions and limits

### Follow-up — 5 September

Two native defects were reproduced and corrected with focused regressions. The custom-drawn suggestion had role `AXUnknown` and no accessible value; its active renderer now exposes only the visible completion as read-only static text, excluding the authored paragraph prefix. Dismissal, external hiding, renderer replacement and a rejected presentation remove that accessible value. The window remains nonactivating and mouse-transparent. This follows the AppKit custom-view mechanism documented by [Apple](https://developer.apple.com/documentation/appkit/accessibility-for-appkit); an actual VoiceOver journey has not been verified.

Repeated identical capture-skip diagnostics previously emitted every 100 ms. They now emit immediately for state/focus/new-episode changes and once every five seconds while unchanged, retaining the cumulative failure count. Capture scheduling and generation are unchanged. A deterministic 100-poll test emits 2 records instead of 100; the running signed package confirmed approximately 5.1-second gaps with counts 1, 52 and 103. The trace file was already size-bounded; the benefit is less repeated serialization/IPC/file work and slower eviction of useful evidence, not a proven battery or model-speed improvement.

All **420 native tests pass**; package integrity and signature checks pass. The app was quit through its native menu, process termination verified, and the rebuilt package relaunched. Production request `BA1196C3-B4F4-4158-BC1D-7B88E14EDC39` again admitted 4 sources and 1 library candidate, returned HTTP 200/text and reached `presented`. This sample took **2.24 seconds from request to presentation**, including 2.17 seconds HTTP time; context preparation took 5 ms. This is slower than the previous examples and must remain in the evidence set. Content quality, visual overlay and physical Tab acceptance remain unverified. Original on-request mode was restored after this regression check.

Evidence: `/tmp/autocompletion-a11y-red.log`, `/tmp/autocompletion-idle-trace-red.log`, `/tmp/autocompletion-sep5-native-all.log`, `/tmp/autocompletion-sep5-package.log`. Only native source/tests changed in this follow-up; the earlier workspace suites were not unnecessarily rerun and no backend redeployment was needed.

- Work stayed in the authorized, already-dirty checkout without commits. This preserves the user's full pending product; rollback requires file-level correction.
- Native focus and complete context identity govern destination validity. Menu application metadata is asynchronous and cannot reject an otherwise valid native request.
- Generic AX source perception uses bounded traversal and verified visibility. Missing AX evidence produces omission rather than invented screen understanding. OCR, image/diagram understanding and offscreen history are not implemented.
- Durable knowledge, memory and style are explicit user entries. App/topic/expiry scope precedes local ranking; ambiguous neighbouring feed text cannot unlock library facts. This avoids automatic fact contamination but limits recall and does not implement autonomous personality learning.
- Keep the established model and one final response. No streaming, speculative extra generation call, connector dependency or provider fallback was added. No new speed claim follows from passing tests.
- Stage and then promote the matching backend alongside the packaged contract. A temporary mismatch remains possible for older app builds; backward-compatible transport paths were not added.

## Native settings layer — 5 September 2026

Replaced the React renderer and preload/IPC presentation bridge with a SwiftUI/AppKit executable inside the signed desktop bundle. Electron owns the tray, OAuth session, encrypted account-scoped library, validated parent/child actions and runtime controls. The native helper still owns capture, stale-result rejection and insertion. Existing Qwen/Cerebras generation and final-output mode are unchanged.

Implemented English/Spanish UI, finite pauses (15/30/60 minutes or tomorrow 09:00), persistent application exclusions, automatic/on-request mode, timing (150/300/700 ms), and live suggestion opacity (0.48/0.72). The native preview now uses those same alpha values. Account identity comes from Clerk userinfo; sign-out invalidates pending credentials and unloads the library. Native editor state clears on sign-out/account switch.

The native titlebar uses automatic split-view layout and full-size content. General is reduced to three compact groups; successful permissions become one summary row. Secondary explanations use native hover tooltips with matching VoiceOver hints. Recovery actions and blocking states remain visible.

Verification: workspace typecheck passed; desktop 132 tests passed, followed by 11 focused preference/package tests including the new shortcut persistence case. API 132, database 3, and protocol 41 tests passed. Full native suite previously passed 468 tests; the updated native UI suite passes 49 tests. Signed package integrity includes the nested settings application and its shortcut resource bundle.

Native live inspection verified the corrected header, restored session and existing library, English/Spanish updates, finite pause persistence/resume, and custom shortcut recording. Recording Control+Alt+K changed the UI, contextual help and persisted preference; the default Command+Shift+Space was restored after QA. Application exclusions used during QA were also restored.

Practice request `61789E69-9650-47BA-920B-E4080BBEFB70` used 3 source blocks and completed HTTP 200 in 2.03s, then reached helper `presented` and UI `shown`. Grouping the conversation separately from changing feedback prevents the earlier self-cancellation. The automation tool sends application key events rather than a physical global key press, so global invocation and Tab acceptance were not established by this run. The target-window screenshot excludes the helper's overlay; these observations do not establish universal contextual quality or visual overlay acceptance.

## Manual invocation and insertion verification — September 5, 2026

Removed the UI-provided application ID from manual invocation. The helper resolves foreground application metadata locally when the command arrives; capture still enforces field safety, user exclusions, focus stability and insertion verification. Added content-free routing diagnostics so received, blocked and forwarded invocations can be distinguished.

Verification: the new null-payload protocol regression failed before the change and passed afterward. 37 protocol message tests, 16 native controller tests, and 18 desktop shortcut/configuration/diagnostic tests passed. Workspace typechecks and signed package integrity passed. No backend or model change was made.

Packaged live tests now cover actual system keyboard events, rather than only events delivered to an application window:

- Manual mode, practice request `5DF690D5-175A-4B99-B06C-76A31AF3532F`: Command+Shift+Space invoked generation, the helper presented the continuation, and Tab inserted “the deck by Friday.” into the real NSTextView. The UI reported Accepted and the field contents were checked.
- Automatic mode, TextEdit request `AD66FF8E-4237-454B-A06A-BF372F9993BD`: typing triggered generation without a request action. HTTP completed in 825.5 ms; presentation followed 874.5 ms after request. Tab produced `accepted_full`; the document visibly contained the inserted continuation “the revised version shortly.”

Automatic mode was restored, the default shortcut preserved, and the user's Clear visibility retained. These tests establish the two observed paths, not universal coverage of all web editors. Earlier absence of system-key verification above is superseded by this run.

## Web-field failure investigation — September 5, 2026

The user reported missing suggestions in Codex and other applications. Existing content-free traces showed a web request with no text before the caret, no admitted read-only sources, unresolved geometry and a successful HTTP response choosing silence. This does not establish an API outage, nor does the before-caret count alone establish that the whole field was empty. Direct computer-use inspection of Codex was denied by the tool; the investigation did not bypass that restriction. Codex remains unverified.

A regression reproduced a separate concrete capture defect: stale placeholder-shaped text markers could override a nonempty authoritative AXValue/AXSelectedTextRange and replace the draft with empty text. Placeholder classification now requires agreement with the focused field value and collapsed selection at its start. Three conflicting publication cases failed before the guard and pass afterward. This establishes the defect and correction, not that it caused the user's specific Codex failure.

Request tracing now includes a bounded after-caret text bucket and a selection flag, without capturing field text. The matching strict desktop trace decoder ships in the same package. Verification: 89 capture tests, 16 controller tests, 5 native trace tests, 21 desktop helper/trace tests, desktop typecheck and signed package integrity pass.

A separate controlled Electron 44 editor was used for actual packaged-app verification:

- Rich contenteditable reply: automatic request `C50E4E50-01B8-410C-9ABA-056CEA2745FB` admitted the nearby message asking for a revised proposal by Friday. The helper presented the final response about 1.94 seconds after request, and system Tab inserted the continuation into the real field. The resulting field value was verified through Accessibility.
- Textarea, final package: automatic request `C5D0A55B-6DAF-4873-B183-05CA4928BC19` had nonempty before-caret text, empty after-caret text, no selection and a resolved anchor. It admitted one read-only source and one related field, returned HTTP 200 in 908 ms, presented about 949 ms after request, and emitted `accepted_full` after system Tab. The textarea contained the inserted continuation about sending the revised proposal by Friday.
- An empty textarea in the same fixture exposed a zero-height range and no usable text-marker caret. That case still has no reliable inline anchor. No guessed cursor position, popup, OCR path or app-specific workaround was added.

Automatic mode, the default shortcut and Clear visibility remain unchanged. These samples establish two controlled web-editor paths, not universal coverage or a Codex fix. Evidence: `/tmp/autocompletion-placeholder-red.log`, `/tmp/autocompletion-placeholder-green.log`, `/tmp/autocompletion-field-trace-green.log`, `/tmp/autocompletion-field-trace-desktop-green.log`, `/tmp/autocompletion-web-field-package-final.log`; the standalone reproduction is `/tmp/autocompletion-electron-surface-qa/`.

## Nested source perception — September 5, 2026

The new local Context Lab reproduced a visible-message failure: adding ordinary DOM containers made the current message disappear from AX context while a nearby formatting hint remained. Three independent cutoffs contributed: visibility ancestry stopped at 12 nodes including Electron's native host containers; source descent stopped after three levels despite its existing node budget; and the first nonempty ancestor ring ended the search.

Visibility now follows at most 32 ancestors to a verified window. Source descent uses the existing 32-node budget and cycle detection instead of the shallow depth cutoff. The enclosing-container search retains its four-ring limit and six-source total budget but continues past a nearby hint. Secure/hidden/editable branches, clipping checks, source provenance and the cooperative capture deadline remain in force. No app-specific semantic logic or model change was introduced.

The original nested live check and focused regressions failed before correction. After correction, 102 focused native checks passed, including the live fixture, capture, visibility and source-traversal suites. The revised-deadline and conversation-switch fixture phases also passed independently. Signed package integrity passed (`/tmp/autocompletion-context-package.log`) and that package was relaunched before the following actual system-key tests:

| Fixture journey | Request | Observed accepted result | Request to presentation |
| --- | --- | --- | --- |
| Nested message, initial proposal | `CCCFE798-F7F6-4EB3-BF68-54920E66EA42` | Reply included the revised Jacaranda proposal and Thursday at 16:00 | 2091 ms |
| Same field after deadline revision | `3E73B881-B948-4586-A19C-DD485C662F60` | Reply used Monday at 10:00; Thursday was absent | 751 ms |
| Switch to dinner conversation | `C4B1AA9D-55B9-488F-9B6C-EA423B862E0A` | Reply offered a chocolate cake without nuts; proposal details were absent | 691 ms |

Each request admitted two read-only sources (message and editor hint), no library candidate, and emitted `accepted_full`. The actual host field value was inspected after Tab. These establish correct wording for these controlled cases, not universal social/email coverage or a latency improvement. One batched automation draft reset produced an incomplete test prefix; it was corrected and verified before the revised-deadline measurement. Cold live source scans took 75–91 ms and sometimes returned no source on the first read, followed by a successful bounded reread; the cooperative 50 ms deadline is not a hard total-time guarantee.

Reproduction files: `apps/desktop/dev/context-lab.cjs`, `apps/desktop/dev/context-lab.html`, and `native/macos/Tests/AutocompleteHelperTests/LiveContextLabTests.swift`. Content-free per-request evidence is in `/tmp/autocompletion-context-{proposal,revised,dinner}-live.jsonl`. Source-regression evidence is in `/tmp/autocompletion-nested-source-live-red.log`, `/tmp/autocompletion-source-rings-red.log`, `/tmp/autocompletion-source-depth-red.log`, and `/tmp/autocompletion-context-green.log`.

Open release gates are tracked in `release-readiness.md`. Codex's reported failure, empty web fields without caret geometry, the remaining real-app journeys, explicit-library quality cases, useful latency distribution and fresh-install/recovery checks remain open.
# Caret recovery follow-up — September 5, 2026

The user confirmed Notes works but Codex still has no ghost after typing and pausing. Direct computer use of Codex remains blocked by the tool; no alternate AX/screenshot route was used to inspect it. Existing content-free runtime diagnostics showed an unavailable caret, including following-glyph geometry outside the input frame and missing line-edge candidates. That is not proof that every Codex failure has the same cause.

Two generic capture defects were corrected:

- On an independently measured empty line, a preceding marker could point at generated placeholder content instead of the insertion point. The reader now uses an exact caret corroborated by the empty line range. Live LinkedIn geometry passes; its separate placeholder-as-authored-text gate still fails. No placeholder text is removed by this change.
- Reader and capture discarded line geometry merely because a glyph rectangle existed, before the resolver established whether that rectangle was usable. Both now retain measured candidates. The resolver gives glyphs priority only after field, display and line-height validation. Valid glyphs still outrank line edges; an out-of-bounds or invalid-height glyph no longer suppresses a valid line anchor. No app-specific branch, invented geometry, or suffix-overlap permission was added.

Tests reproduced the second failure before implementation (`/tmp/autocompletion-glyph-priority-red.log`). The final focused capture, resolver, monitor and presenter suites passed **209 tests** (`/tmp/autocompletion-glyph-priority-verified.log`). A prior intermediate run failed only the old diagnostic assertion that line evidence must be absent; the final assertion checks it is retained while the same valid glyph still wins.

The preceding signed package was physically checked in TextEdit: request `45E90682-9BFC-419C-AB3B-D86D7562A3CF` displayed and accepted with system Tab; host text was verified. A separate unaccepted ghost was visually inspected at `/tmp/autocompletion-native-ghost-visible.png`, request `CEE95672-467A-4F32-ADEF-078F4F6112D2`. These checks establish that path only, not Codex compatibility or the later candidate-priority fix's packaged result.
