# Research Evidence and Open Questions

**Status:** Historical research, reviewed 2026-08-31. Sources support mechanisms, not product-market proof. The current contracts linked in README supersede architectural recommendations here; cascades, streaming and per-app adapters are not current implementation requirements.

## TL;DR

Prior work supports goal inference from event streams, episode recovery, breakpoint-aware intervention, asynchronous writing assistance, and personalized pause timing. Apple exposes useful accessibility and pasteboard seams, but integrations and screen access remain incomplete and permission-sensitive. The evidence supports the architecture; it does not prove that the product will predict correctly without measured trials.

## Evidence informing the direction

### Goal inference from software events

Microsoft Research's Lumiere project modeled time-varying software-user goals from observed actions, queries, user background, and application event streams. It also separated probabilistic beliefs about goals from utility-directed intervention. This is direct precedent for `events -> goal distribution -> assistance`, although Autocomplete Everywhere must avoid the intrusive behavior associated with historical assistants.

- [The Lumiere Project](https://www.microsoft.com/en-us/research/publication/lumiere-project-bayesian-user-modeling-inferring-goals-needs-software-users/)
- [Principles of Mixed-Initiative User Interfaces](https://www.microsoft.com/en-us/research/publication/principles-mixed-initiative-user-interfaces/)

### Cross-task episode recovery

TaskTracer studied associating desktop interactions and resources with tasks so knowledge workers could recover from interruptions and reuse successful processes. This supports episode-oriented working memory, but its detailed monitoring model should not be copied wholesale.

- [TaskTracer paper](https://web.engr.oregonstate.edu/~tgd/publications/iui2005-tasktracer.pdf)

### Event segmentation and task boundaries

Event-segmentation research argues that people organize continuous activity into hierarchical events using both perceptual change and actors' goals. Interruption-management research finds that meaningful task breakpoints are lower-cost moments to intervene.

- [Event Segmentation](https://journals.sagepub.com/doi/10.1111/j.1467-8721.2007.00480.x)
- [Paying Attention to Interruption](https://www.microsoft.com/en-us/research/video/paying-attention-to-interruption-a-human-centered-approach-to-intelligent-interruption-management/)

### Real-time writing assistance

Google's Smart Compose work establishes that high-throughput, real-time language-model serving is an engineering discipline distinct from general text generation. Grammarly reports major input-lag reductions by moving suggestion processing off the synchronous typing path and updating after typing stops.

- [Gmail Smart Compose](https://research.google/pubs/gmail-smart-compose-real-time-assisted-writing/)
- [Reducing Text Input Lag](https://www.grammarly.com/blog/engineering/reducing-text-input-lag/)

### Personalized pause detection

Keystroke-process research warns that one fixed pause threshold does not represent every writer. Dynamic, writer-dependent pause assessment can better distinguish normal motor gaps from cognitive pauses.

- [Dynamic pause assessment](https://aclanthology.org/W16-4111/)
- [Methods for studying the writing time-course](https://link.springer.com/article/10.1007/s11145-023-10490-8)

### macOS field and clipboard seams

Apple accessibility protocols expose focused elements, roles, frames, identifiers, and placeholder values in supported controls. `NSPasteboard` exposes shared pasteboard items, types, and a change counter. Clipboard item lifetime follows ownership changes. These APIs provide mechanisms, not permission to construct an invisible clipboard history.

- [NSAccessibility](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol)
- [Accessibility placeholder value](https://developer.apple.com/documentation/appkit/nsaccessibility-c.protocol/accessibilityplaceholdervalue)
- [NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)
- [NSPasteboard changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount)

### Connector scope and minimization

Slack conversation history is constrained by token type, scopes, and conversation membership. Gmail body access uses sensitive or restricted scopes and can trigger verification and security-assessment obligations. Google Workspace also applies use-case eligibility rules beyond OAuth consent, so a Gmail connector needs policy review before it becomes a committed product path. NIST defines minimization as limiting collection, processing, retention, and disclosure to what is directly necessary.

- [Slack conversations.history](https://api.slack.com/methods/conversations.history)
- [Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Google Workspace API user data policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy)
- [NIST minimization](https://csrc.nist.gov/glossary/term/minimization)

## Open-source landscape

Snapshot reviewed on 2026-08-31. Repository maturity, licensing, and behavior must be reverified before reuse.

| Project | What it demonstrates | What we should learn | What we should not copy blindly |
|---|---|---|---|
| [KeyType](https://github.com/johnbean393/KeyType) | MIT-licensed modular macOS autocomplete with Accessibility capture, prompt budgets, local runtime, constrained generation, overlay, insertion, and app compatibility | Separation of pure domain contracts, app policy, bounded prompt sections, cancellation, KV reuse, and suppression taxonomy | It logs typed context tails and generated suggestions for debugging; that conflicts with our default content-free telemetry contract |
| [Pretype](https://github.com/nikiomori/Pretype) | MIT-licensed system-wide local autocomplete, selection handling, OCR context, per-app statistics, personal n-grams, and explicit reply composition | Count only offers the user could perceive; go quiet reversibly in consistently unproductive apps; use a deterministic personal fast path before an LLM | Its optional local journal stores raw context, suggestions, and divergent text, with a large on-disk allowance; silent raw-text learning is not our default |
| [Inkling](https://github.com/dafuct/Inkling-macOS) | Work-in-progress MIT project with deterministic memory suggestions, LLM upgrades, a pure confidence gate, and offline threshold sweeps | Tiered `instant deterministic -> later model upgrade`, pure gates, no-flicker arbitration, and benchmarkable thresholds | Token probability is not product confidence, and personal vocabulary storage requires explicit consent and deletion controls |
| [Cotabby](https://github.com/FuJacob/cotabby) | AGPL system-wide autocomplete with a detailed state machine, multiple engines, bounded context, request-time clipboard relevance, OCR, and app-specific reliability policies | Revalidate focus/content signatures after every asynchronous boundary; separate availability, request construction, generation, normalization, presentation, and insertion | AGPL affects reuse decisions; its architecture documents secure-field acquisition privacy debt and full prompt/completion debug logs |
| [SwiftType](https://github.com/mgxv/SwiftType) | System-wide next-word prediction using spell checking and a 5-gram KenLM model without generative AI or network calls | A cheap deterministic/statistical tier can own spelling, word completion, and common next-word cases | N-grams cannot provide cross-application goal inference, audience adaptation, or canonical retrieval |
| [ActivityWatch](https://github.com/ActivityWatch/activitywatch) | Local collection of active app/window, browser tab, and AFK activity through modular watchers | Event schemas, app-transition timing, local ownership, and modular observation | Its goal of retaining high-resolution raw activity is the opposite of our episode-minimization default |
| [Screenpipe](https://github.com/screenpipe/screenpipe) | Searchable OCR, audio, input actions, app switches, and accessibility context with compact query surfaces | Broad desktop context is technically possible; accessibility outlines can be far cheaper than raw visual payloads | Continuous capture and searchable historical content are too broad for default inline autocomplete and create a much larger privacy product |
| [OpenAdapt](https://github.com/OpenAdaptAI/OpenAdapt) | Recording user demonstrations and compiling repeatable desktop workflows | Repeated behavior can eventually become a deterministic pattern rather than repeated model calls | Raw screen, keyboard, and action recording plus autonomous replay are outside the current product boundary |

### What exists and what remains open

The last-mile mechanics are well represented: focused-field capture, caret geometry, ghost overlays, Tab handling, cancellation, local inference, bounded prompts, and compatibility policies. We should study or reuse established implementations only after license, security, and real-app verification.

The targeted search did not find one open-source system that combines all of the following:

- Sparse cross-application episode inference rather than lifetime recording.
- Selected/copy artifact transport with source authority and audience boundaries.
- Destination field-role understanding across supported applications.
- An explicit economic policy for `no call / cheap call / strong call`.
- A separate decision for whether a ready result should become visible.
- Content-free learning of usefulness, interruption, regret, and wasted calls.

This is not proof that no such project exists. It does clarify the likely product boundary: the differentiator is the **context router plus invocation and intervention policy**, not the local LLM or ghost-text overlay alone.

### Concrete design corrections from prior art

1. **Do not count every rendered frame as a rejected offer.** Pretype's code found that fast typing can replace a ghost before it was humanly readable, badly corrupting acceptance statistics. Our readability threshold must be measured per user and shape.
2. **A reversible per-surface quiet mode can start simple.** Counts with a minimum sample, decay, visible explanation, and manual reset may beat an early learned policy.
3. **Tiered results are viable.** Inkling demonstrates instant deterministic memory followed by a model upgrade, with a pure arbiter preventing flicker or replacement during acceptance.
4. **Every asynchronous artifact is stale by default.** Cotabby and KeyType repeatedly revalidate field, focus, and content signatures before display or insertion.
5. **Budget context by decision value.** KeyType's sectioned prompt budgets and Cotabby's bounded providers support cursor-local and destination-critical evidence before OCR or broad history.
6. **Continuous capture is a different product.** ActivityWatch, Screenpipe, and OpenAdapt prove collection feasibility, but their raw-history orientation should not redefine Autocomplete Everywhere's default privacy model.
7. **Local does not automatically mean acceptable.** A 50 MB local journal of drafts is still a hidden history. Retention requires product consent, inspection, deletion, and demonstrated incremental value.

## Important corrections to the intuitive vision

1. **The screen is not a reliable universal database.** Accessibility varies by application. Tested adapters and connectors are necessary for world-class precision.
2. **Clipboard availability is not blanket consent.** Copying is strong selection evidence, but the product still needs explicit clipboard-product consent and strict ephemeral handling.
3. **Copied AI output is selected, not verified.** Preserve it as an artifact, but do not promote its factual claims over canonical sources.
4. **A connector is not merely engineering.** Gmail and Slack access introduce scope, review, retention, tenant-isolation, and user-explanation obligations.
5. **More context can reduce quality.** Every extra source increases ambiguity, latency, leakage risk, and prompt noise.
6. **Perfect prediction is unnecessary.** The product can be world-class by preparing broadly, revealing narrowly, and failing silently.

## Open founder decisions

These should be resolved before the product-intelligence architecture becomes an implementation specification:

1. May automatic multiline suggestions appear at very strong block boundaries, or must they always be explicitly summoned?
2. How much invisible, discarded speculative inference cost is acceptable for a materially faster experience?
3. Is clipboard intelligence a default-on permission explained during onboarding, or a separate opt-in capability?
4. Should nearby read-only accessibility text be eligible by default inside supported apps, or require per-application permission?
5. Which first cross-application proof matters most: AI-to-email, Slack-to-email, bug-to-AI-prompt, or interrupted-task resumption?
6. What explicit dismissal or regret rate disables goal-conditioned suggestions automatically?

## Recommended first research proof

Test one narrow, favorable journey before generalizing:

```text
copy a prepared email in an AI surface
  -> focus Gmail subject
  -> derive subject
  -> focus Gmail body
  -> offer exact copied body
  -> accept or continue typing
```

This journey tests clipboard change detection, artifact classification, field-role understanding, exact transport versus derivation, timing, stale cancellation, provenance, and privacy without requiring a universal task ontology. If it cannot feel correct and trustworthy here, broader cross-application prediction is premature.
