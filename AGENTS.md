# Autocomplete Everywhere engineering rules

- This repository implements Autocomplete Everywhere, a Mac utility that offers inline completions in any accessible text field. Internal package, bundle and environment identifiers keep the `autocompletion` prefix.
- Build one complete working layer before adding the next.
- Use tests first for behavior changes.
- Never capture secure fields or log draft, suggestion, clipboard, screenshot, or retrieved-context contents.
- Nothing sends, submits, publishes, clicks, or commits automatically.
- The native helper owns focus, staleness, Tab consumption, and insertion decisions.
- Do not add backward-compatibility layers. Desktop and helper ship as one protocol version.
- Do not expose provider, Supabase admin, or Clerk server credentials to Electron renderer code.
- Distinguish Linux/static verification from macOS/AppKit, packaged-app, signed, notarized, and real-device proof.

## Current intelligence contract

- Follow `docs/product-intelligence/README.md` and its current contracts. Historical research alternatives are not implementation requirements.
- Use one global Accessibility capability path and Gemini through AI Gateway for semantics; no per-app semantic allowlists, local intent/language classifiers, streaming, or model/provider fallback.
- User-controlled app exclusions are supported privacy boundaries: block capture and generation, purge retained context and cancel pending work. They do not select app-specific semantic logic.
- Physical field shape limits formatting; the model chooses useful length, including blocks in already-started multiline fields.
- Recent context comes from bounded observed edits and verified acceptance, never from merely shown ghosts or whole preexisting application histories.
- Run focused behavioral tests for changed boundaries and package before visual claims. Repeat broader suites only for a new failure, material change or unresolved concern.
