import { createClerkClient } from "@clerk/backend";
import { createHash } from "node:crypto";

import type {
  AuthenticateRequest,
  AuthenticatedUser,
  DependencySource,
} from "./app.js";

type UncachedAuthenticateRequest = (
  request: Request,
) => Promise<Omit<AuthenticatedUser, "source"> | null>;

type AuthenticationCacheOptions = {
  ttlMs?: number;
  maxEntries?: number;
  now?: () => number;
};

type CachedAuthentication = {
  user: Omit<AuthenticatedUser, "source">;
  expiresAtMs: number;
};

export function readBearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization");
  const match = authorization?.match(/^Bearer ([^\s]+)$/);
  return match?.[1] ?? null;
}

function tokenKey(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function jwtExpiryMs(token: string): number | undefined {
  const payload = token.split(".")[1];
  if (!payload) return undefined;
  try {
    const value = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    return typeof value?.exp === "number" && Number.isFinite(value.exp)
      ? value.exp * 1_000
      : undefined;
  } catch {
    return undefined;
  }
}

function withSource(
  user: Omit<AuthenticatedUser, "source">,
  source: DependencySource,
): AuthenticatedUser {
  return { ...user, source };
}

export function createCachedAuthenticateRequest(
  authenticate: UncachedAuthenticateRequest,
  options: AuthenticationCacheOptions = {},
): AuthenticateRequest {
  const ttlMs = Math.min(Math.max(options.ttlMs ?? 60_000, 0), 60_000);
  const maxEntries = Math.max(1, options.maxEntries ?? 5_000);
  const now = options.now ?? Date.now;
  const cache = new Map<string, CachedAuthentication>();
  const pending = new Map<
    string,
    Promise<Omit<AuthenticatedUser, "source"> | null>
  >();

  return async (request) => {
    const bearer = readBearerToken(request);
    if (!bearer) return null;
    const key = tokenKey(bearer);
    const currentTime = now();
    const cached = cache.get(key);
    if (cached && currentTime < cached.expiresAtMs) {
      cache.delete(key);
      cache.set(key, cached);
      return withSource(cached.user, "cache");
    }
    cache.delete(key);

    const inflight = pending.get(key);
    if (inflight) {
      const user = await inflight;
      return user ? withSource(user, "inflight") : null;
    }

    const operation = authenticate(request);
    pending.set(key, operation);
    try {
      const user = await operation;
      if (!user) return null;

      const verifiedAt = now();
      const expiresAtMs = Math.min(
        verifiedAt + ttlMs,
        jwtExpiryMs(bearer) ?? Number.POSITIVE_INFINITY,
      );
      if (expiresAtMs > verifiedAt) {
        while (cache.size >= maxEntries) {
          const oldest = cache.keys().next().value;
          if (typeof oldest !== "string") break;
          cache.delete(oldest);
        }
        cache.set(key, { user, expiresAtMs });
      }
      return withSource(user, "origin");
    } finally {
      pending.delete(key);
    }
  };
}

export function createAuthenticateClerkRequest(credentials: {
  secretKey: string;
  publishableKey: string;
}): AuthenticateRequest {
  const clerkClient = createClerkClient(credentials);
  return createCachedAuthenticateRequest(async (request) => {
    const accessToken = readBearerToken(request);
    if (!accessToken) return null;
    const state = await clerkClient.authenticateRequest(request, {
      acceptsToken: ["session_token", "oauth_token"],
    });
    if (!state.isAuthenticated) return null;

    const auth = state.toAuth();
    return auth.userId ? { userId: auth.userId } : null;
  });
}
