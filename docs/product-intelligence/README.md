# Autocomplete Everywhere product intelligence

**Vision and implementation — 2026-09-04**

The product is **Autocomplete Everywhere**. Technical paths, package names and environment variables keep the `autocompletion` prefix.

## Current scope and verification

[Autocomplete Everywhere current scope](./mvp.md) now includes the user's requested end-to-end intelligence layer: source-bound AX context, one final generation, and native insertion controls. Library was deferred by the user on September 5: its UI and retrieval are disabled; saved files are preserved. The [implementation record](./intelligence-implementation.md) tracks interfaces and verification. This is not a completed user study or a claim of universal app coverage.

## Product design

[Consumer app direction](./consumer-app-direction.md) records the September 15 product discussion: the two writing flows, purpose-based actions, retained timing controls, and proposed consumer messaging, organization, onboarding, and pricing. Confirmed preferences are distinguished from proposals; this working document does not replace the current implementation contract.

[Invisible intelligence: complete product design](./invisible-intelligence-product-design.md) remains the broader design reference. Its source-perception layer is implemented. The explicit Library implementation is currently disabled. Visual capture/OCR remains a future capability. Bounded opt-in preference learning is implemented and packaged; its real-use benefit remains unproven. See the [MVP execution record](./mvp-execution.md) for that distinction.

## Current implementation direction

Autocomplete Everywhere should understand what the user is writing and offer the amount of text that usefully advances it, from a fragment to an email or block. It brings a small amount of relevant recent context to the current cursor without sending or submitting anything.

The current contract is one global Accessibility route, one Gemini 3.5 Flash-Lite / AI Gateway engine, model-owned semantics, and one validated final ghost. Astra is the development agent. Local code owns secure fields, resource bounds, expiry, current focus, geometry and verified insertion. There are no per-application semantic paths, local intent/language classifiers, model cascades or streaming.

## Current contract

- [Inline decision matrix: capture, generation, rendering and insertion](../architecture/inline-decision-matrix.md)

- [Product thesis](./product-thesis.md)
- [First-principles operating model](./first-principles-operating-model.md)
- [Available context signals](./context-signal-inventory.md)
- [Timing, generation and privacy](./timing-generation-privacy.md)

## Research and acceptance scenarios

- [Scenario atlas](./scenario-atlas.md): use cases and negative cases; some require evidence or integrations beyond the current layer.
- [Research evidence](./research-evidence.md): historical sources and alternatives, not implementation mandates.

## Evidence boundary

A document describes intent; code and focused tests establish an implementation boundary; a signed package establishes packaging; observing the real package and identified backend establishes product behavior. None substitutes for the next. See [native verification](../architecture/native-verification.md) for dated evidence and remaining work.

## Model migration — 2026-09-15

The user selected `google/gemini-3.5-flash-lite` after the Everyday Writing benchmark. Completion, selected-text transforms and preference extraction now use Vercel AI Gateway pinned to `vertex` with `zeroDataRetention: true`, `thinkingLevel: low` and `includeThoughts: false`. Authentication uses Vercel OIDC or `AI_GATEWAY_API_KEY`; no direct Google key is required; there is no Cerebras production path or fallback. Earlier dated validation records describe the engine used at that time.

Activation requires deploying this backend revision with AI Gateway access. Local compilation and mocked-provider tests do not prove hosted generation or macOS behavior.
