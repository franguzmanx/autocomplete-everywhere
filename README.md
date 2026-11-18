# Autocomplete Everywhere

Inline AI autocomplete for every text field on your Mac.

Write in any accessible text field, pause, and a continuation appears as ghost
text at the cursor. Press **Tab** to accept it or keep typing to ignore it. It
works in Notes, Slack, Gmail, Chrome, Safari and other apps through the macOS
Accessibility API, with no per-app integrations.

Nothing sends, submits, publishes, or clicks automatically.

> **Status:** early and experimental. There is no signed download yet. You
> build the app and add your own [Vercel AI Gateway](https://vercel.com/ai-gateway)
> key. No account and no server are required.

## What it does

| Action | Shortcut |
| --- | --- |
| Accept the suggestion | Tab, or click it |
| Accept the next word | Option + Tab |
| Dismiss | Escape, or keep typing |
| Next version / request another | Option + ↓ |
| Previous version | Option + ↑ |
| Rewrite selected text (Polish, Improve prompt, Improve text, custom) | Option + 1–9, then Tab to apply |

Suggestion history holds up to five versions in memory. It clears when you
edit, change the target, dismiss, or accept.

Privacy rules that the code enforces:

- Secure fields are never captured.
- Drafts, suggestions, clipboard and retrieved context are never logged.
- You can exclude any app. Exclusion blocks capture and generation, and purges
  retained context.

## How it works

```
 text field ──(1) Accessibility──▶ Swift helper ──(2) protocol──▶ Electron app
     ▲                                  │                             │
     └────(5) ghost text / insertion────┘                  (3) your AI Gateway key
                                        ▲                             ▼
                                        └────(4) suggestion──── Vercel AI Gateway ──▶ model
```

The helper owns focus, capture, ghost text, keys and insertion. The Electron
app owns settings, the key and the request to the model.

There are two modes:

- **Local (default).** The suggestion API runs inside the app. It opens no
  port. Your key is encrypted with the macOS Keychain and goes only to Vercel
  AI Gateway.
- **Hosted (optional).** The same API runs on a server with sign-in, so users
  do not need their own key. See [Hosted mode](#hosted-mode).

## Repository layout

- `apps/desktop`: Electron shell (account, settings, helper lifecycle, request transport).
- `native/macos`: Swift/AppKit helper, settings UI and local context service.
- `services/api`: suggestion, context and outcome API (Hono). Runs inside the app in local mode, or on Vercel in hosted mode.
- `packages/protocol`: helper protocol v4 schemas, fixtures and contract tests.
- `packages/database`: authenticated Postgres access for manual context and suggestion outcomes.
- `supabase`: schema, RLS policies and pgTAP tests.
- `docs`: architecture and product design notes.

## Requirements

- macOS 14 or later on Apple Silicon, with Xcode.
- [Bun](https://bun.sh) 1.3.14.
- SQLCipher and pkg-config: `brew install sqlcipher pkgconf`.
- A [Vercel AI Gateway](https://vercel.com/ai-gateway) API key.

## Quick start

```sh
bun install
bun run --filter @autocompletion/desktop package:mac
open apps/desktop/dist/mac-arm64/AutocompleteEverywhere.app
```

Then:

1. Open **Settings → Account**, paste your AI Gateway key and save. The app
   checks the key with the gateway before it stores it.
2. Grant **Accessibility** and **Input Monitoring** in System Settings →
   Privacy & Security.
3. Type in any text field and pause.

Screen Recording is optional. The app uses it only for visual context, after
separate consent.

The build signs the app with a local Apple Development identity when it finds
one. macOS ties the permissions to the signature, so an unsigned build can ask
for them again after each rebuild.

Suggestions use `google/gemini-3.5-flash-lite` through the gateway, with zero
data retention requested. You pay the gateway for your own usage.

## Hosted mode

Use this mode to run the product for other people: they sign in, and your
server pays for the model. The app selects it when any hosted variable below
is set, at run time or at build time. If the set is incomplete, the app stops
at launch and names the missing variables.

You need:

1. **Identity: [Clerk](https://clerk.com).** Create an application and an
   OAuth application for the desktop client. It is a public client: use PKCE
   and the redirect URI `http://127.0.0.1:43119/callback`.
2. **Model access: [Vercel AI Gateway](https://vercel.com/ai-gateway).** On
   Vercel the function authenticates with OIDC. Elsewhere, set
   `AI_GATEWAY_API_KEY`.
3. **Database (optional): Postgres, for example [Supabase](https://supabase.com).**
   It stores manual context and content-free suggestion outcomes. Apply the
   migrations in `supabase/migrations` and set `DATABASE_URL`.

Copy `.env.example` to `.env.local` and fill it in. Never commit that file.

### API variables (`services/api`)

| Variable | Required | Purpose |
| --- | --- | --- |
| `CLERK_SECRET_KEY` | yes | Verifies desktop tokens. |
| `CLERK_PUBLISHABLE_KEY` | yes | Identifies the Clerk application. |
| `AI_DIAGNOSTICS` | yes | `off` or `full`. Use `off` in production. |
| `AI_GATEWAY_API_KEY` | outside Vercel | Model access. |
| `DATABASE_URL` | no | Enables manual context and outcome storage. |

### Desktop variables (`apps/desktop`)

The app reads these at run time. The build also bakes in the values that are
set when you run it, so a packaged app keeps your backend. They are public
values; do not put a secret in them.

| Variable | Example |
| --- | --- |
| `AUTOCOMPLETION_API_URL` | `https://your-api.example.com` |
| `AUTOCOMPLETION_CLERK_AUTHORIZATION_URL` | `https://clerk.example.com/oauth/authorize` |
| `AUTOCOMPLETION_CLERK_TOKEN_URL` | `https://clerk.example.com/oauth/token` |
| `AUTOCOMPLETION_CLERK_USERINFO_URL` | `https://clerk.example.com/oauth/userinfo` |
| `AUTOCOMPLETION_CLERK_REVOCATION_URL` | `https://clerk.example.com/oauth/token/revoke` |
| `AUTOCOMPLETION_CLERK_CLIENT_ID` | your OAuth client id |
| `AUTOCOMPLETION_ACCOUNT_URL` | `https://accounts.example.com/user` |
| `AUTOCOMPLETION_CLERK_REDIRECT_URI` | optional, defaults to `http://127.0.0.1:43119/callback` |

```sh
set -a; source .env.local; set +a
bun run --filter @autocompletion/desktop package:mac
```

## Test

```sh
bun run check                                   # TypeScript
bun run test                                    # TypeScript tests
swift test --package-path native/macos          # Swift tests (macOS)
```

Package and environment identifiers keep the `autocompletion` prefix.

## Documentation

- [Product architecture guide](./docs/architecture/product-architecture-guide.md)
- [Build-ready architecture](./docs/architecture/architecture-v2.md)
- [Selected-text transforms](./docs/architecture/transforms.md)
- [Native verification boundary](./docs/architecture/native-verification.md)
- [Database verification boundary](./docs/architecture/database-verification.md)
- [Product design notes](./docs/product-intelligence/README.md)

The docs include dated engineering notes from the original private
deployment. Hostnames in them are placeholders.

## Contributing

Issues and pull requests are welcome. Run `bun run check`, `bun run test` and
the Swift tests before you open a pull request. See [AGENTS.md](./AGENTS.md)
for the engineering rules.

## License

[MIT](./LICENSE)
