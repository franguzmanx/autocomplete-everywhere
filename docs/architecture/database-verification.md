# Database verification boundary

**Updated:** 2026-09-03

## Runtime identity boundary

The desktop authenticates to the Autocomplete Everywhere API with a Clerk OAuth access
token. The API verifies that token with Clerk and retains only the verified
`userId` for database authorization.

Clerk's native Supabase integration augments Clerk session tokens, but a public
desktop OAuth access token is a different token class and does not inherit the
Supabase `role` claim. The API therefore does not forward the desktop token to
PostgREST and does not use a Supabase service role.

Instead, the API connects through Supabase's transaction pooler with a
server-only `DATABASE_URL`. One shared runner
(`createAuthenticatedPostgresRunner`) serves manual context and suggestion
outcomes. Every user operation runs in one transaction that:

1. sets the local database role to `authenticated`;
2. sets `request.jwt.claims` to the verified Clerk `sub` and
   `role: authenticated`;
3. invokes the existing `security invoker` context functions; and
4. lets the checked-in RLS policies authorize every affected row.

Both role and claims are transaction-local and disappear when the transaction
ends. The database URL never reaches Electron, the renderer, the native helper,
logs, tests, or git.

## Suggestion outcomes — 2026-09-03 (source-verified, hosted apply pending)

Migration `20260903120000_suggestion_outcomes.sql`:

- adds the `generated` and `cancelled` values to `public.suggestion_outcome`;
- drops `suggestion_events.language_code` (the client no longer classifies
  language) and adds `request_to_final_ms`;
- adds `public.record_suggestion_outcome(...)`, a `security invoker` function
  that creates the caller's `users` row on first use, validates surface class
  and detail lengths, inserts one row per outcome, and ignores a repeated
  outcome for the same request through `on conflict do nothing`.

`supabase/tests/suggestion_outcomes_test.sql` asserts the schema, first-use
user creation, repeated `shown` idempotence, surface validation, and
cross-user isolation. `access_control_test.sql` no longer inserts
`language_code` into events.

This migration and its tests have **not** been applied or run against the
hosted project in this revision, and no local Supabase stack was available
on the Linux build host. Applying it to the hosted project and deploying the
API are production changes that require the founder's explicit
authorization; the order is migration first, API second.

## Current verified evidence

- Both checked-in migrations are applied to the separate hosted Supabase
  project.
- `access_control_test.sql` passes 14 pgTAP assertions.
- `manual_context_test.sql` passes 8 pgTAP assertions.
- A direct repository integration saved and read a synthetic profile while a
  different synthetic Clerk subject read an empty profile.
- The authenticated packaged desktop flow saved a real account profile through
  the production API.
- A content-free database check observed one profile owner and two separately
  scoped canonical items. No profile body was printed or logged.
- The obsolete client-side PostgREST path and its publishable-key dependency
  were removed.

## Repeatable local verification

With Docker and the Supabase CLI available:

```bash
bunx supabase@latest start
bunx supabase@latest db reset
bunx supabase@latest test db
bunx supabase@latest db lint --level warning
bunx supabase@latest gen types typescript --local > packages/database/src/types.ts
```

`packages/database/src/types.ts` is currently a placeholder; regenerate it
after the outcome migration is applied locally.

The hosted-project proof remains separate from local parser, type, and unit
tests. Do not claim production authorization from a green source suite alone.
