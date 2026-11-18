# Context backend

`POST /v1/context/visual`: `{imageBase64,mimeType}` → `{text}`. Gemini 3.5 Flash-Lite, Gateway Vertex-only with ZDR requested. Image bounds: base64 2.8M chars, PNG/JPEG/WebP only. Output is derived evidence, never authored text.

`POST /v1/context/embeddings`: `{text}` → `{embedding}` (exactly 768 finite numbers). Google Text Multilingual Embedding 002, Gateway Vertex-only, `vertex.outputDimensionality:768`, mandatory `zeroDataRetention:true`. Metrics contain only operation, duration and token count.

Both require Clerk authentication, share two database leases per account, respect request cancellation and have 20-second deadlines. Apply `supabase/migrations/20260917120000_context_background_leases.sql` and configure `DATABASE_URL`. Missing database/function fails closed with 503; there is no local semaphore fallback. Leases expire after 30 seconds if an API instance dies. Mocked tests do not establish deployed SQL concurrency or hosted model availability.

## Read-only connectors

Configure `GITHUB_CONTEXT_CLIENT_ID`, `GITHUB_CONTEXT_CLIENT_SECRET`, `GITHUB_CONTEXT_REDIRECT_URI`, the corresponding `FIGMA_CONTEXT_*` values, and random `CONTEXT_OAUTH_STATE_SECRET` (32+ chars). Secrets remain backend-only. Redirect URIs must match registered provider URLs; desktop uses `http://127.0.0.1:43120/context/callback`. Registration/approval and actual provider acceptance of this loopback URL are deployment gates, especially Figma. No credentials means `connector_unavailable`, not a simulated connection.

GitHub registration must be a **GitHub App** with read-only repository Contents, Issues, Pull requests and Checks permissions. No broad OAuth `repo` scope is requested. Figma scopes are `file_content:read file_comments:read`.

`POST /v1/context/connectors/{github|figma}/{operation}`:

- `start {codeChallenge}` (S256, 43-char base64url): returns `{authorizationUrl,state}`. Desktop opens the system browser, holds a random PKCE verifier and validates loopback state.
- `exchange {code,state,codeVerifier}`: validates signed account/provider/challenge/expiry bindings before code redemption. Returns `{accessToken,refreshToken?,expiresAtMs?}` for secure storage on the Mac.
- `refresh {refreshToken}`: returns replacement tokens with the same shape.
- `read {accessToken,resourceId}`: returns `{resourceId,text,revision,capturedAtMs}`. Desktop wraps as observed evidence with scoped identity/expiry.
- `revoke {accessToken}`: GitHub remote revocation. Figma returns `{revoked:false,requiresProviderAction:true,settingsUrl}`; no undocumented revoke endpoint is invented. Desktop must always stop requests and purge local credentials/evidence, then expose required provider-side revocation.

Resource IDs:

- GitHub `owner/repo/issues/123`.
- GitHub `owner/repo/pulls/123`: includes up to 20 changed files, reviews and head check runs.
- GitHub `owner/repo/contents/docs/file.md?ref=main`: bounded file content, no traversal or arbitrary URLs.
- Figma `fileKey` or `fileKey/nodes/12:34`: file/node and up to 20 comments.

Only constructed fixed-host URLs are fetched. Redirects are errors. Responses are streamed with a 1MB cap before JSON parsing; final excerpts are bounded to 16k chars. Excerpts may be truncated and are not complete histories. 401 means authorization revoked, 403 permission denied, and 429 propagates Retry-After. Access tokens, provider responses and document text are never logged. Live authorization, permissions, token refresh and revocation remain external acceptance gates until tested with real configured apps.

## Shared learning budget and measured diagnostics

The existing `/v1/preferences/extract` route acquires the **same** account lease pool as visual and embedding requests; missing database deployment fails closed there too. Inline completion and explicit rewrite do not use background slots. Learning has a 10-second server deadline, visual/embedding 20 seconds, below the 30-second crash-expiry lease.

`background_usage` emits only operation, success/error/cancelled, duration, known token counts and optional `costUsd`. Cost is read from the actual response's `providerMetadata.gateway.cost`, as [documented by Vercel](https://examples.vercel.com/academy/ai-gateway/ai-gateway-pricing). No rates are hardcoded and no estimated bill is invented; absent billing/token metadata stays absent. Failed calls with no usage metadata are counted as failures with unknown cost, not free calls. No prompts, image bytes, evidence, tokens/credentials, account identities or arbitrary errors enter metrics.

## Synthetic capability probe

After deployment and authenticated test-account setup, run:

```sh
bun --env-file=/absolute/path/to/private-probe.env services/api/scripts/probe-context.ts
```

The explicit environment file must supply `CONTEXT_PROBE_API_URL` and `CONTEXT_PROBE_ACCESS_TOKEN` (a current Clerk bearer); optional `CONTEXT_PROBE_REPORT` names a private JSON output file. Do not commit this environment file. The script does not discover credentials or read user content. It sends one fixed public PNG and one synthetic sentence through the actual authenticated visual and embedding routes. Only a valid nonempty visual response and exactly 768 finite dimensions produce `verified:true`. Output contains status codes, durations and known model IDs only, never response text or secrets. A report proves that deployment/account at the recorded instant, not native screen-capture behavior or connector OAuth permissions. No credential-free run is marked verified. This script has not been run against hosted credentials in this implementation session.

## Read-only production readiness inspection — 2026-09-17


`probe-context-models.ts` uses existing Gateway authentication with public synthetic inputs and reports content-free model results. With available Vercel OIDC authentication, the actual visual route through `google/gemini-3.5-flash-lite`, Vertex and ZDR succeeded: 1694ms, 1159 tokens, provider-reported $0.0003587. This establishes model/image capability, not deployed API, database semaphore, desktop capture or app permission acceptance.

The actual pinned Google `gemini-embedding-2` call returned HTTP 400: no ZDR providers or ZDR-attested BYOK credentials available. The request did not claim embedding ZDR; the existing Gateway policy nevertheless required it. The implementation did not disable or bypass that policy. Embedding activation remains blocked until an explicitly approved retention-compatible configuration is available. See the [official provider listing](https://vercel.com/ai-gateway/models/gemini-embedding-2), which does not establish ZDR for this Google embedding route. A successful visual probe must not set the combined context verification flag while embeddings remain blocked.

## Selected embedding route update

The user approved `google/text-multilingual-embedding-002` on Vertex after a live comparison. It returned eight valid vectors with ZDR enforced (513 ms median, measured from the development Mac). Production code now pins that route and explicitly requires ZDR. This supersedes the earlier Embedding 2 route blocker; the authenticated deployed endpoint still needs its own verification. No fallback or change to team policy was added.

