import {
  createHash,
  createHmac,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";
import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import { z } from "zod";
import type { AuthenticateRequest } from "../app.js";
type Provider = "github" | "figma";
const providerSchema = z.enum(["github", "figma"]);
const token = z
  .string()
  .min(1)
  .max(8192)
  .regex(/^[\x21-\x7e]+$/);
export function connectorResourceUrl(
  provider: Provider,
  resource: string,
): string {
  if (provider === "figma") {
    const match = /^([A-Za-z0-9]{1,128})(?:\/nodes\/([0-9]+:[0-9]+))?$/.exec(
      resource,
    );
    if (match)
      return match[2]
        ? `https://api.figma.com/v1/files/${match[1]}/nodes?ids=${encodeURIComponent(match[2])}&depth=4`
        : `https://api.figma.com/v1/files/${match[1]}?depth=2`;
  }
  if (provider === "github") {
    if (
      /^[A-Za-z0-9_-]{1,100}\/[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99}\/(?:issues|pulls)\/[1-9][0-9]{0,9}$/.test(
        resource,
      )
    )
      return `https://api.github.com/repos/${resource}`;
    const match =
      /^([A-Za-z0-9_-]{1,100}\/[A-Za-z0-9_-][A-Za-z0-9_.-]{0,99})\/contents\/([^?]+)(?:\?ref=([A-Za-z0-9_.-]{1,128}))?$/.exec(
        resource,
      );
    if (
      match &&
      match[2]!
        .split("/")
        .every(
          (part) =>
            /^[A-Za-z0-9_. -]{1,128}$/.test(part) &&
            part !== "." &&
            part !== "..",
        )
    )
      return `https://api.github.com/repos/${match[1]}/contents/${match[2]!.split("/").map(encodeURIComponent).join("/")}?ref=${encodeURIComponent(match[3] ?? "HEAD")}`;
  }
  throw new Error("invalid_resource");
}
class ConnectorResponseError extends Error {
  constructor(
    readonly status: number,
    readonly retryAfter: string | null,
  ) {
    super("connector_response");
  }
}
const StateSchema = z.object({
  provider: providerSchema,
  userId: z.string(),
  challenge: z.string(),
  expires: z.number(),
  nonce: z.string(),
});
export function createConnectorApp(deps: {
  authenticate: AuthenticateRequest;
  environment: Readonly<Record<string, string | undefined>>;
  fetch?: typeof fetch;
}) {
  const app = new Hono(),
    request = deps.fetch ?? fetch;
  const configuration = (provider: Provider) => {
    const prefix = provider.toUpperCase(),
      clientId = deps.environment[`${prefix}_CONTEXT_CLIENT_ID`],
      secret = deps.environment[`${prefix}_CONTEXT_CLIENT_SECRET`],
      redirectUri = deps.environment[`${prefix}_CONTEXT_REDIRECT_URI`],
      stateSecret = deps.environment.CONTEXT_OAUTH_STATE_SECRET;
    if (
      !clientId ||
      !secret ||
      !redirectUri ||
      !stateSecret ||
      stateSecret.length < 32 ||
      !(
        redirectUri.startsWith("https://") ||
        redirectUri === "http://127.0.0.1:43120/context/callback"
      )
    )
      return undefined;
    return { clientId, secret, redirectUri, stateSecret };
  };
  const sign = (payload: string, secret: string) =>
    createHmac("sha256", secret).update(payload).digest("base64url");
  const stateData = (state: string, secret: string) => {
    const [payload, signature] = state.split(".");
    if (!payload || !signature) throw new Error("invalid_state");
    const expected = Buffer.from(sign(payload, secret)),
      actual = Buffer.from(signature);
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual))
      throw new Error("invalid_state");
    const data = StateSchema.parse(
      JSON.parse(Buffer.from(payload, "base64url").toString()),
    );
    if (data.expires < Date.now()) throw new Error("expired_state");
    return data;
  };
  async function boundedJson(response: Response) {
    if (Number(response.headers.get("content-length") ?? 0) > 1_000_000)
      throw new Error("too_large");
    const reader = response.body?.getReader();
    if (!reader) throw new Error("empty_response");
    let length = 0;
    const chunks: Uint8Array[] = [];
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.length;
        if (length > 1_000_000) throw new Error("too_large");
        chunks.push(value);
      }
    } finally {
      await reader.cancel();
    }
    return JSON.parse(Buffer.concat(chunks).toString()) as Record<
      string,
      unknown
    >;
  }
  app.use("*", async (c, next) => {
    c.header("cache-control", "no-store");
    c.header("referrer-policy", "no-referrer");
    await next();
  });
  app.use(
    "*",
    bodyLimit({
      maxSize: 20000,
      onError: (c) => c.json({ error: "invalid_request" }, 413),
    }),
  );
  app.post("/v1/context/connectors/:provider/:operation", async (c) => {
    let user;
    try {
      user = await deps.authenticate(c.req.raw);
    } catch {
      return c.json({ error: "auth_unavailable" }, 503);
    }
    if (!user) return c.json({ error: "unauthorized" }, 401);
    const parsedProvider = providerSchema.safeParse(c.req.param("provider"));
    if (!parsedProvider.success)
      return c.json({ error: "invalid_provider" }, 400);
    const provider = parsedProvider.data,
      operation = c.req.param("operation"),
      config = configuration(provider);
    const body = await c.req.json().catch(() => null);
    const signal = AbortSignal.any([
      c.req.raw.signal,
      AbortSignal.timeout(15000),
    ]);
    try {
      if (operation === "start") {
        if (!config) return c.json({ error: "connector_unavailable" }, 503);
        const parsed = z
          .object({ codeChallenge: z.string().regex(/^[A-Za-z0-9_-]{43}$/) })
          .strict()
          .safeParse(body);
        if (!parsed.success) return c.json({ error: "invalid_request" }, 400);
        const payload = Buffer.from(
          JSON.stringify({
            provider,
            userId: user.userId,
            challenge: parsed.data.codeChallenge,
            expires: Date.now() + 600000,
            nonce: randomBytes(24).toString("base64url"),
          }),
        ).toString("base64url");
        const state = `${payload}.${sign(payload, config.stateSecret)}`;
        const url = new URL(
          provider === "github"
            ? "https://github.com/login/oauth/authorize"
            : "https://www.figma.com/oauth",
        );
        url.search = new URLSearchParams({
          client_id: config.clientId,
          redirect_uri: config.redirectUri,
          state,
          response_type: "code",
          code_challenge: parsed.data.codeChallenge,
          code_challenge_method: "S256",
          ...(provider === "figma"
            ? { scope: "file_content:read file_comments:read" }
            : {}),
        }).toString();
        return c.json({ authorizationUrl: url.toString(), state });
      }
      if (operation === "exchange" || operation === "refresh") {
        if (!config) return c.json({ error: "connector_unavailable" }, 503);
        const parsed = (
          operation === "exchange"
            ? z
                .object({
                  code: token,
                  state: z.string().max(4096),
                  codeVerifier: z.string().regex(/^[A-Za-z0-9._~-]{43,128}$/),
                })
                .strict()
            : z.object({ refreshToken: token }).strict()
        ).safeParse(body);
        if (!parsed.success) return c.json({ error: "invalid_request" }, 400);
        const form = new URLSearchParams({
          client_id: config.clientId,
          client_secret: config.secret,
        });
        if ("code" in parsed.data) {
          const state = stateData(parsed.data.state, config.stateSecret);
          if (
            state.provider !== provider ||
            state.userId !== user.userId ||
            state.challenge !==
              createHash("sha256")
                .update(parsed.data.codeVerifier)
                .digest("base64url")
          )
            return c.json({ error: "invalid_state" }, 400);
          form.set("code", parsed.data.code);
          form.set("code_verifier", parsed.data.codeVerifier);
          form.set("redirect_uri", config.redirectUri);
          form.set("grant_type", "authorization_code");
        } else {
          form.set("refresh_token", parsed.data.refreshToken);
          form.set("grant_type", "refresh_token");
        }
        const response = await request(
          provider === "github"
            ? "https://github.com/login/oauth/access_token"
            : `https://api.figma.com/v1/oauth/${operation === "refresh" ? "refresh" : "token"}`,
          {
            method: "POST",
            headers: {
              accept: "application/json",
              "content-type": "application/x-www-form-urlencoded",
              ...(provider === "figma"
                ? {
                    authorization: `Basic ${Buffer.from(`${config.clientId}:${config.secret}`).toString("base64")}`,
                  }
                : {}),
            },
            body: form,
            redirect: "error",
            signal,
          },
        );
        if (!response.ok) return c.json({ error: "authorization_failed" }, 502);
        const data = await boundedJson(response);
        const tokens = z
          .object({
            access_token: token,
            refresh_token: token.optional(),
            expires_in: z.number().positive().optional(),
          })
          .safeParse(data);
        if (!tokens.success)
          return c.json({ error: "authorization_failed" }, 502);
        return c.json({
          accessToken: tokens.data.access_token,
          ...(tokens.data.refresh_token
            ? { refreshToken: tokens.data.refresh_token }
            : {}),
          ...(tokens.data.expires_in
            ? { expiresAtMs: Date.now() + tokens.data.expires_in * 1000 }
            : {}),
        });
      }
      if (operation === "read") {
        const parsed = z
          .object({
            accessToken: token,
            resourceId: z.string().min(1).max(300),
          })
          .strict()
          .safeParse(body);
        if (!parsed.success) return c.json({ error: "invalid_request" }, 400);
        let url;
        try {
          url = connectorResourceUrl(provider, parsed.data.resourceId);
        } catch {
          return c.json({ error: "invalid_resource" }, 400);
        }
        const get = async (
          target: string,
        ): Promise<Record<string, unknown>> => {
          const response = await request(target, {
            headers: {
              authorization: `Bearer ${parsed.data.accessToken}`,
              accept: "application/json",
              "user-agent": "AutocompleteEverywhere-context",
            },
            redirect: "error",
            signal,
          });
          if (!response.ok)
            throw new ConnectorResponseError(
              response.status,
              response.headers.get("retry-after"),
            );
          return boundedJson(response);
        };
        const data = await get(url);
        const pick = (
          value: unknown,
          keys: string[],
        ): Record<string, unknown> => {
          if (!value || typeof value !== "object") return {};
          const record = value as Record<string, unknown>;
          return Object.fromEntries(
            keys
              .filter((key) => key in record)
              .map((key) => [key, record[key]]),
          );
        };
        const boundedList = (value: unknown, keys: string[]) =>
          Array.isArray(value)
            ? value.slice(0, 20).map((item) => pick(item, keys))
            : [];
        let content: Record<string, unknown>;
        if (provider === "github") {
          if (parsed.data.resourceId.includes("/contents/")) {
            if (
              data.type !== "file" ||
              data.encoding !== "base64" ||
              typeof data.content !== "string" ||
              typeof data.size !== "number" ||
              data.size > 48000
            )
              return c.json(
                { error: "resource_too_large_or_unsupported" },
                422,
              );
            content = {
              ...pick(data, ["name", "path", "sha", "html_url"]),
              text: Buffer.from(data.content, "base64")
                .toString("utf8")
                .slice(0, 12000),
            };
          } else {
            content = pick(data, [
              "title",
              "body",
              "state",
              "user",
              "updated_at",
              "html_url",
            ]);
            if (parsed.data.resourceId.includes("/pulls/")) {
              const [files, reviews] = await Promise.all([
                get(`${url}/files?per_page=20`),
                get(`${url}/reviews?per_page=20`),
              ]);
              content.files = boundedList(files, [
                "filename",
                "status",
                "additions",
                "deletions",
                "patch",
              ]);
              content.reviews = boundedList(reviews, [
                "state",
                "body",
                "submitted_at",
                "user",
              ]);
              const head = data.head as { sha?: unknown } | undefined;
              if (
                typeof head?.sha === "string" &&
                /^[a-f0-9]{40}$/.test(head.sha)
              ) {
                const repo = parsed.data.resourceId
                  .split("/")
                  .slice(0, 2)
                  .join("/");
                const checks = await get(
                  `https://api.github.com/repos/${repo}/commits/${head.sha}/check-runs?per_page=20`,
                );
                content.checks = boundedList(checks.check_runs, [
                  "name",
                  "status",
                  "conclusion",
                  "completed_at",
                  "details_url",
                ]);
              }
            }
          }
        } else {
          const key = parsed.data.resourceId.split("/")[0]!;
          const comments = await get(
            `https://api.figma.com/v1/files/${key}/comments`,
          );
          content = {
            ...pick(data, ["name", "lastModified", "document", "nodes"]),
            comments: boundedList(comments.comments, [
              "message",
              "created_at",
              "resolved_at",
              "user",
              "client_meta",
            ]),
          };
        }
        // Bound individual large fields before serialization so evidence stays complete JSON.
        const text = JSON.stringify(content, (_key, value: unknown) =>
          typeof value === "string" ? value.slice(0, 4000) : value,
        );
        const boundedText =
          text.length <= 16000
            ? text
            : text.slice(0, 15950) + " [source excerpt truncated]";
        return c.json({
          resourceId: parsed.data.resourceId,
          text: boundedText,
          revision: createHash("sha256").update(boundedText).digest("hex"),
          capturedAtMs: Date.now(),
        });
      }
      if (operation === "revoke") {
        const parsed = z
          .object({ accessToken: token })
          .strict()
          .safeParse(body);
        if (!parsed.success) return c.json({ error: "invalid_request" }, 400);
        if (provider === "figma")
          return c.json({
            revoked: false,
            requiresProviderAction: true,
            settingsUrl: "https://www.figma.com/settings",
          });
        if (!config) return c.json({ error: "connector_unavailable" }, 503);
        const response = await request(
          `https://api.github.com/applications/${encodeURIComponent(config.clientId)}/token`,
          {
            method: "DELETE",
            headers: {
              authorization: `Basic ${Buffer.from(`${config.clientId}:${config.secret}`).toString("base64")}`,
              "content-type": "application/json",
              "user-agent": "AutocompleteEverywhere-context",
            },
            body: JSON.stringify({ access_token: parsed.data.accessToken }),
            redirect: "error",
            signal,
          },
        );
        if (response.status !== 204 && response.status !== 404)
          return c.json({ error: "revocation_failed" }, 502);
        return c.json({ revoked: true });
      }
      return c.json({ error: "invalid_operation" }, 404);
    } catch (error) {
      if (error instanceof ConnectorResponseError) {
        if (
          error.status === 429 ||
          (error.status === 403 && error.retryAfter)
        ) {
          if (error.retryAfter) c.header("retry-after", error.retryAfter);
          return c.json({ error: "rate_limited" }, 429);
        }
        if (error.status === 401)
          return c.json({ error: "authorization_revoked" }, 401);
        if (error.status === 403)
          return c.json({ error: "permission_denied" }, 403);
        if (error.status === 404)
          return c.json({ error: "resource_unavailable" }, 404);
      }
      return c.json(
        {
          error: signal.aborted
            ? "connector_cancelled"
            : "connector_unavailable",
        },
        502,
      );
    }
  });
  return app;
}
