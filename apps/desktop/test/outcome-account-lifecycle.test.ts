import { afterEach, expect, test, vi } from "vitest";
vi.mock("electron", () => ({ safeStorage: {} }));
vi.mock("../src/main/auth", async importOriginal => ({
  ...await importOriginal<typeof import("../src/main/auth")>(),
  beginDesktopSignIn: async (_config: unknown, options: {storeTokens(tokens: unknown): Promise<void>}) => {
    await options.storeTokens(tokens("B"));
  },
}));
import { AccountSession } from "../src/main/account-session";
import { ProductState } from "../src/main/state";
import { HttpSuggestionTransport } from "../src/main/suggestion-transport";
import { SuggestionOutcomeUploader } from "../src/main/suggestion-outcome-uploader";
import type { StoredProductData } from "../src/main/oauth-token-provider";

function tokens(account: string) { return { accessToken: account, refreshToken: account, expiresAt: Date.now() + 3600000, tokenType: "Bearer" }; }
const event = (id: string) => ({requestId: id, appId: "private.app.id", surface: "text_editor" as const, outcome: "requested" as const});
function deferred<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(r => {resolve = r;}); return {promise, resolve}; }
afterEach(() => vi.useRealTimers());

for (const stall of ["token", "http", "refresh"] as const) {
  test(`account A ${stall} wait and pending events never send under B`, async () => {
    let stored: StoredProductData = {oauthClientId: "client", oauthSessionId: "A", tokens: tokens("A")};
    const gate = deferred<Response>();
    const tokenGate = deferred<StoredProductData>();
    let stallRead = false;
    let readStarted = false;
    let uploadStarted = false;
    let refreshStarted = false;
    const recorded: { token: string; ids: string[] }[] = [];
    let uploader: SuggestionOutcomeUploader | null = null;
    const state = new ProductState();
    const session = new AccountSession({state, root: "/unused", store: {
      read: async () => { if (stallRead) { readStarted = true; return tokenGate.promise; } return stored; },
      write: async (value: StoredProductData) => {stored = value;},
    } as never, config: {clientId: "client", tokenEndpoint: "https://auth.test/token", userinfoEndpoint: "https://auth.test/user", revocationEndpoint: "https://auth.test/revoke"} as never,
    invalidate: () => uploader?.reset(), changed: () => {}, openExternal: async () => {},
    request: async (url, init) => {
      if (String(url).endsWith("/user")) return Response.json({sub: new Headers(init?.headers).get("authorization")});
      if (String(url).endsWith("/token")) { refreshStarted = true; return gate.promise; }
      return new Response(null, {status: 204});
    }});
    await session.initialize();
    const transport = new HttpSuggestionTransport({apiUrl: "https://api.test", tokenProvider: session.tokenProvider,
      request: async (_url, init) => {
        const token = new Headers(init?.headers).get("authorization")!;
        if (token === "Bearer A") {
          uploadStarted = true;
          if (stall === "http") return gate.promise;
          if (stall === "refresh") return new Response(null, {status: 401});
        }
        recorded.push({token, ids: JSON.parse(String(init?.body)).events.map((e: {requestId: string}) => e.requestId)});
        return new Response(null, {status: 204});
      },
    });
    uploader = new SuggestionOutcomeUploader({batchSize: 1, send: (events, signal) => transport.recordSuggestionOutcomes(events, signal)});
    if (stall === "token") {session.tokenProvider.invalidate(); stallRead = true;}
    uploader.enqueue(event("A-active"));
    await vi.waitFor(() => expect(stall === "token" ? readStarted : uploadStarted).toBe(true));
    // Let 401 reach its refresh before switching accounts.
    if (stall === "refresh") await vi.waitFor(() => expect(refreshStarted).toBe(true));
    uploader.enqueue(event("A-pending"));
    stallRead = false;
    await session.signOut();
    await session.beginSignIn();
    uploader.enqueue(event("B-new"));
    tokenGate.resolve(stored);
    gate.resolve(stall === "refresh" ? Response.json({access_token: "A-renewed", refresh_token: "A", expires_in: 3600, token_type: "Bearer"}) : new Response(null, {status: 401}));
    await uploader.flush();
    expect(recorded).toEqual([{token: "Bearer B", ids: ["B-new"]}]);
    uploader.dispose(); session.dispose();
  });
}

for (const stall of ["token", "http", "body"] as const) {
test(`deadline releases stalled ${stall}, drops batch, and progresses with content-free diagnostics`, async () => {
  vi.useFakeTimers();
  const gate = deferred<string>();
  let calls = 0;
  const httpGate = deferred<Response>();
  const bodyGate = deferred<void>();
  const request = vi.fn(async (_url: string | URL | Request, _init?: RequestInit) => {
    if (request.mock.calls.length === 1 && stall === "http") return httpGate.promise;
    if (request.mock.calls.length === 1 && stall === "body") return new Response(new ReadableStream({cancel: () => bodyGate.promise}));
    return new Response(null, {status: 204});
  });
  const diagnostic = vi.fn();
  const transport = new HttpSuggestionTransport({apiUrl: "https://api.test", tokenProvider: {getAccessToken: () => ++calls === 1 && stall === "token" ? gate.promise : Promise.resolve("B")}, request});
  const uploader = new SuggestionOutcomeUploader({batchSize: 1, send: (events, signal) => transport.recordSuggestionOutcomes(events, signal), onDiagnostic: diagnostic});
  uploader.enqueue(event("sensitive-id"));
  await vi.advanceTimersByTimeAsync(0);
  uploader.enqueue(event("next"));
  await vi.advanceTimersByTimeAsync(10001);
  await uploader.flush();
  const expectedCalls = stall === "token" ? 1 : 2;
  expect(request).toHaveBeenCalledTimes(expectedCalls);
  expect(JSON.parse(String(request.mock.calls.at(-1)?.[1]?.body)).events[0].requestId).toBe("next");
  expect(diagnostic.mock.calls).toEqual([["outcome_upload_failed"]]);
  gate.resolve("old");
  httpGate.resolve(new Response(null, {status: 401}));
  bodyGate.resolve();
  await vi.advanceTimersByTimeAsync(0);
  expect(request).toHaveBeenCalledTimes(expectedCalls);
  uploader.dispose();
});

}
