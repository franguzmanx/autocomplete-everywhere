import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";

export type PkcePair = {
  verifier: string;
  challenge: string;
};

type AuthorizationUrlInput = {
  authorizationEndpoint: string;
  clientId: string;
  redirectUri: string;
  state: string;
  challenge: string;
  scopes: string[];
};

type TokenExchangeInput = {
  tokenEndpoint: string;
  clientId: string;
  redirectUri: string;
  code: string;
  verifier: string;
};

type RefreshTokenExchangeInput = {
  tokenEndpoint: string;
  clientId: string;
  refreshToken: string;
  now?: () => number;
};

export type OAuthTokens = {
  accessToken: string;
  refreshToken: string;
  expiresAt: number;
  tokenType: string;
};

export type DesktopOAuthConfig = {
  authorizationEndpoint: string;
  tokenEndpoint: string;
  clientId: string;
  redirectUri: string;
  scopes: string[];
};

type DesktopOAuthDependencies = {
  openExternal(url: string): Promise<void>;
  storeTokens(tokens: OAuthTokens): Promise<void>;
};

function toBase64Url(value: Uint8Array): string {
  return Buffer.from(value).toString("base64url");
}

export function createPkcePair(entropy = randomBytes(32)): PkcePair {
  const verifier = toBase64Url(entropy);
  const challenge = toBase64Url(
    createHash("sha256").update(verifier, "ascii").digest(),
  );

  return { verifier, challenge };
}

export function buildAuthorizationUrl(input: AuthorizationUrlInput): URL {
  const url = new URL(input.authorizationEndpoint);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", input.clientId);
  url.searchParams.set("redirect_uri", input.redirectUri);
  url.searchParams.set("scope", input.scopes.join(" "));
  url.searchParams.set("state", input.state);
  url.searchParams.set("code_challenge", input.challenge);
  url.searchParams.set("code_challenge_method", "S256");
  return url;
}

export function parseAuthorizationCallback(
  callbackUrl: string,
  expectedRedirectUri: string,
  expectedState: string,
): { code: string } {
  const callback = new URL(callbackUrl);
  const expected = new URL(expectedRedirectUri);
  if (
    callback.protocol !== expected.protocol ||
    callback.hostname !== expected.hostname ||
    callback.port !== expected.port ||
    callback.pathname !== expected.pathname
  ) {
    throw new Error("OAuth callback URL mismatch");
  }

  const error = callback.searchParams.get("error");
  if (error) {
    throw new Error(`OAuth authorization failed: ${error}`);
  }

  if (callback.searchParams.get("state") !== expectedState) {
    throw new Error("OAuth state mismatch");
  }

  const code = callback.searchParams.get("code");
  if (!code) {
    throw new Error("OAuth callback did not include a code");
  }

  return { code };
}

export async function exchangeAuthorizationCode(
  input: TokenExchangeInput,
  request: typeof fetch = fetch,
): Promise<OAuthTokens> {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: input.clientId,
    redirect_uri: input.redirectUri,
    code: input.code,
    code_verifier: input.verifier,
  });
  const response = await request(input.tokenEndpoint, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/x-www-form-urlencoded",
    },
    body,
    signal: AbortSignal.timeout(10_000),
  });

  if (!response.ok) {
    throw new Error(`OAuth token exchange failed with status ${response.status}`);
  }

  const payload = (await response.json()) as Record<string, unknown>;
  if (
    typeof payload.access_token !== "string" ||
    typeof payload.refresh_token !== "string" ||
    typeof payload.expires_in !== "number" ||
    typeof payload.token_type !== "string"
  ) {
    throw new Error("OAuth token response is incomplete");
  }

  return {
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token,
    expiresAt: Date.now() + payload.expires_in * 1_000,
    tokenType: payload.token_type,
  };
}

export async function exchangeRefreshToken(
  input: RefreshTokenExchangeInput,
  request: typeof fetch = fetch,
): Promise<OAuthTokens> {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    client_id: input.clientId,
    refresh_token: input.refreshToken,
  });
  const response = await request(input.tokenEndpoint, {
    method: "POST",
    headers: {
      accept: "application/json",
      "content-type": "application/x-www-form-urlencoded",
    },
    body,
    signal: AbortSignal.timeout(10_000),
  });

  if (!response.ok) {
    throw new Error(`OAuth token refresh failed with status ${response.status}`);
  }

  const payload = (await response.json()) as Record<string, unknown>;
  if (
    typeof payload.access_token !== "string" ||
    typeof payload.expires_in !== "number" ||
    typeof payload.token_type !== "string"
  ) {
    throw new Error("OAuth refresh response is incomplete");
  }

  return {
    accessToken: payload.access_token,
    refreshToken:
      typeof payload.refresh_token === "string"
        ? payload.refresh_token
        : input.refreshToken,
    expiresAt: (input.now ?? Date.now)() + payload.expires_in * 1_000,
    tokenType: payload.token_type,
  };
}

function validateDesktopOAuthConfig(config: DesktopOAuthConfig): URL {
  const authorizationEndpoint = new URL(config.authorizationEndpoint);
  const tokenEndpoint = new URL(config.tokenEndpoint);
  const redirect = new URL(config.redirectUri);

  if (
    authorizationEndpoint.protocol !== "https:" ||
    tokenEndpoint.protocol !== "https:"
  ) {
    throw new Error("OAuth provider endpoints must use HTTPS");
  }
  if (
    redirect.protocol !== "http:" ||
    redirect.hostname !== "127.0.0.1" ||
    !redirect.port
  ) {
    throw new Error("OAuth redirect must use a fixed 127.0.0.1 loopback port");
  }
  return redirect;
}

async function waitForAuthorizationCode(
  redirect: URL,
  state: string,
  openAuthorizationPage: () => Promise<void>,
): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const timeout = setTimeout(() => {
      server.close();
      reject(new Error("OAuth sign-in timed out"));
    }, 120_000);
    timeout.unref();

    const finish = (result: { code: string } | Error): void => {
      clearTimeout(timeout);
      server.close();
      if (result instanceof Error) reject(result);
      else resolve(result.code);
    };

    const server = createServer((request, response) => {
      const candidate = new URL(request.url ?? "/", redirect.origin);
      if (candidate.pathname !== redirect.pathname) {
        response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
        response.end("Not found");
        return;
      }

      try {
        const result = parseAuthorizationCallback(
          candidate.toString(),
          redirect.toString(),
          state,
        );
        response.writeHead(200, {
          "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'",
          "content-type": "text/plain; charset=utf-8",
          "x-content-type-options": "nosniff",
        });
        response.end("You are signed in. You can close this tab and return to Autocomplete Everywhere.");
        finish(result);
      } catch (error) {
        response.writeHead(400, { "content-type": "text/plain; charset=utf-8" });
        response.end("Sign-in could not be completed.");
        finish(error as Error);
      }
    });

    server.on("error", (error) => finish(error));
    server.listen(Number(redirect.port), "127.0.0.1", () => {
      void openAuthorizationPage().catch((error: unknown) =>
        finish(error as Error),
      );
    });
  });
}

export async function beginDesktopSignIn(
  config: DesktopOAuthConfig,
  dependencies: DesktopOAuthDependencies,
): Promise<void> {
  const redirect = validateDesktopOAuthConfig(config);
  const state = toBase64Url(randomBytes(32));
  const pkce = createPkcePair();
  const authorizationUrl = buildAuthorizationUrl({
    authorizationEndpoint: config.authorizationEndpoint,
    clientId: config.clientId,
    redirectUri: redirect.toString(),
    state,
    challenge: pkce.challenge,
    scopes: config.scopes,
  });

  const code = await waitForAuthorizationCode(redirect, state, () =>
    dependencies.openExternal(authorizationUrl.toString()),
  );
  const tokens = await exchangeAuthorizationCode({
    tokenEndpoint: config.tokenEndpoint,
    clientId: config.clientId,
    redirectUri: redirect.toString(),
    code,
    verifier: pkce.verifier,
  });
  await dependencies.storeTokens(tokens);
}
