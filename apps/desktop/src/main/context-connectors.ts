import { createHash, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { z } from "zod";
import { ContextRequestError } from "./context-transport";
import type { ContextRow } from "./context-engine";
export type ContextProvider = "github" | "figma";
export type ConnectorRevocation = {
  revoked: boolean;
  requiresProviderAction?: boolean;
  settingsUrl?: string;
};
const tokenSchema = z.object({
  accessToken: z.string().min(1).max(8192),
  refreshToken: z.string().max(8192).optional(),
  expiresAtMs: z.number().int().nonnegative().optional(),
});
type Token = z.infer<typeof tokenSchema>;
const savedSchema = z.object({
  github: tokenSchema.optional(),
  figma: tokenSchema.optional(),
});
/** Identify only explicit provider URLs; never infer repositories from ordinary words. */
export function observedResources(
  text: string,
): Array<{ provider: ContextProvider; resourceId: string }> {
  const found = new Map<
    string,
    { provider: ContextProvider; resourceId: string }
  >();
  for (const match of text.matchAll(/https:\/\/[^\s<>"']+/g)) {
    try {
      const url = new URL(match[0]);
      let provider: ContextProvider, resourceId: string;
      if (url.username || url.password || url.port) continue;
      if (url.hostname === "github.com") {
        const m = url.pathname.match(
          /^\/([^/]+)\/([^/]+)\/(pull|issues)\/([1-9]\d*)\/?$/,
        );
        const file = url.pathname.match(
          /^\/([A-Za-z0-9_-]+)\/([A-Za-z0-9_.-]+)\/blob\/([A-Za-z0-9_.-]+)\/(.+)$/,
        );
        provider = "github";
        if (m)
          resourceId = `${m[1]}/${m[2]}/${m[3] === "pull" ? "pulls" : "issues"}/${m[4]}`;
        else if (
          file &&
          file[4]!
            .split("/")
            .every(
              (part) =>
                /^[A-Za-z0-9_.-]+$/.test(part) && part !== "." && part !== "..",
            )
        )
          resourceId = `${file[1]}/${file[2]}/contents/${file[4]}?ref=${file[3]}`;
        else continue;
      } else if (
        url.hostname === "www.figma.com" ||
        url.hostname === "figma.com"
      ) {
        const m = url.pathname.match(
          /^\/(?:design|file)\/([A-Za-z0-9]+)(?:\/|$)/,
        );
        if (!m) continue;
        provider = "figma";
        const node = url.searchParams.get("node-id")?.replace("-", ":");
        resourceId =
          m[1]! + (node && /^\d+:\d+$/.test(node) ? "/nodes/" + node : "");
      } else continue;
      found.set(provider + ":" + resourceId, { provider, resourceId });
    } catch {}
    if (found.size >= 5) break;
  }
  return [...found.values()];
}
export class ContextConnectors {
  private subject: string | null = null;
  private epoch = 0;
  private tokens: z.infer<typeof savedSchema> = {};
  private controller = new AbortController();
  private cancelLogin: (() => void) | null = null;
  private persistence: Promise<void> = Promise.resolve();
  private retryAt = new Map<ContextProvider, number>();
  private persist(
    subject: string,
    epoch: number,
    signal: AbortSignal,
  ): Promise<void> {
    const task = this.persistence
      .catch(() => {})
      .then(async () => {
        signal.throwIfAborted();
        if (epoch !== this.epoch || subject !== this.subject) return;
        await this.options.store(subject).write({ ...this.tokens }, signal);
      });
    this.persistence = task;
    return task;
  }
  constructor(
    private options: {
      revoked?(provider: ContextProvider): Promise<void>;
      remote: {
        call<T>(
          path: string,
          payload: unknown,
          signal: AbortSignal,
        ): Promise<T>;
      };
      store(subject: string): {
        read<T>(): Promise<T | null>;
        write(value: unknown, signal?: AbortSignal): Promise<void>;
      };
      open(url: string): Promise<void>;
      changed(): void;
    },
  ) {}
  async setAccount(subject: string | null): Promise<void> {
    if (subject === this.subject) return;
    this.epoch++;
    this.cancelLogin?.();
    this.cancelLogin = null;
    this.controller.abort();
    this.controller = new AbortController();
    this.subject = subject;
    this.tokens = {};
    this.retryAt.clear();
    this.options.changed();
    const epoch = this.epoch;
    if (subject) {
      const result = savedSchema.safeParse(
        await this.options.store(subject).read(),
      );
      if (epoch === this.epoch && result.success) {
        this.tokens = result.data;
        this.options.changed();
      }
    }
  }
  snapshot(): ContextRow[] {
    return (["github", "figma"] as const)
      .filter((p) => this.tokens[p])
      .map((id) => ({
        id,
        title: id === "github" ? "GitHub" : "Figma",
        detail: "Connected · Read only",
        excerpt: "",
      }));
  }
  async connect(provider: ContextProvider): Promise<void> {
    const subject = this.subject;
    if (!subject) throw new Error("Sign in first");
    if (this.cancelLogin) throw new Error("Connection already pending");
    const epoch = this.epoch;
    const verifier = randomBytes(32).toString("base64url"),
      challenge = createHash("sha256").update(verifier).digest("base64url");
    const controller = new AbortController(),
      signal = AbortSignal.any([controller.signal, this.controller.signal]);
    this.cancelLogin = () => controller.abort();
    try {
      const start = await this.options.remote.call<{
        authorizationUrl: string;
        state: string;
      }>(`connectors/${provider}/start`, { codeChallenge: challenge }, signal);
      if (epoch !== this.epoch) throw new Error("Account changed");
      const authUrl = new URL(start.authorizationUrl);
      if (
        authUrl.protocol !== "https:" ||
        authUrl.username ||
        authUrl.password ||
        authUrl.port ||
        !(provider === "github"
          ? authUrl.hostname === "github.com" &&
            authUrl.pathname === "/login/oauth/authorize"
          : authUrl.hostname === "www.figma.com" &&
            authUrl.pathname === "/oauth")
      )
        throw new Error("Invalid authorization URL");
      signal.throwIfAborted();
      const code = await new Promise<string>((resolve, reject) => {
        let settled = false;
        const server = createServer((request, response) => {
          const url = new URL(request.url ?? "/", "http://127.0.0.1:43120");
          if (
            url.pathname !== "/context/callback" ||
            url.searchParams.get("state") !== start.state
          ) {
            response.writeHead(400).end("Invalid callback");
            return;
          }
          if (request.method !== "GET") {
            response.writeHead(405).end();
            return;
          }
          const code = url.searchParams.get("code");
          if (code && code.length > 2048) {
            response.writeHead(400).end();
            return;
          }
          response.setHeader("Content-Type", "text/plain");
          response.setHeader("Cache-Control", "no-store");
          response.end(code ? "Return to Autocomplete Everywhere." : "Connection cancelled.");
          done(
            code ? undefined : new Error("Connection cancelled"),
            code ?? undefined,
          );
        });
        const abort = () => done(new Error("Connection cancelled"));
        const timeout = setTimeout(abort, 600000);
        const done = (error?: Error, value?: string) => {
          if (settled) return;
          settled = true;
          clearTimeout(timeout);
          signal.removeEventListener("abort", abort);
          this.cancelLogin = null;
          server.close();
          controller.abort();
          if (error) reject(error);
          else resolve(value!);
        };
        this.cancelLogin = abort;
        signal.addEventListener("abort", abort, { once: true });
        server.on("error", () =>
          done(new Error("Connection listener unavailable")),
        );
        server.listen(43120, "127.0.0.1", () => {
          if (signal.aborted) {
            abort();
            return;
          }
          void this.options
            .open(authUrl.toString())
            .catch(() => done(new Error("Could not open authorization")));
        });
      });
      if (epoch !== this.epoch) throw new Error("Account changed");
      const token = tokenSchema.parse(
        await this.options.remote.call(
          `connectors/${provider}/exchange`,
          { code, state: start.state, codeVerifier: verifier },
          this.controller.signal,
        ),
      );
      if (epoch !== this.epoch) return;
      this.tokens = { ...this.tokens, [provider]: token };
      await this.persist(subject, epoch, this.controller.signal);
      if (epoch === this.epoch) this.options.changed();
    } finally {
      if (epoch === this.epoch) this.cancelLogin = null;
      controller.abort();
    }
  }
  async disconnect(provider: ContextProvider): Promise<ConnectorRevocation> {
    const subject = this.subject;
    if (!subject) return { revoked: true };
    this.epoch++;
    this.cancelLogin?.();
    this.cancelLogin = null;
    this.controller.abort();
    this.controller = new AbortController();
    const epoch = this.epoch,
      signal = this.controller.signal;
    const token = this.tokens[provider];
    const next = { ...this.tokens };
    delete next[provider];
    this.tokens = next;
    this.options.changed();
    await this.persist(subject, epoch, signal);
    if (token && epoch === this.epoch) {
      try {
        const result = await this.options.remote.call<ConnectorRevocation>(
          `connectors/${provider}/revoke`,
          { accessToken: token.accessToken },
          signal,
        );
        if (result.revoked === true) return { revoked: true };
      } catch {}
      return {
        revoked: false,
        requiresProviderAction: true,
        settingsUrl:
          provider === "figma"
            ? "https://www.figma.com/settings"
            : "https://github.com/settings/apps/authorizations",
      };
    }
    return { revoked: true };
  }
  async read(
    provider: ContextProvider,
    resourceId: string,
    cancellation: AbortSignal,
  ): Promise<
    | {
        resourceId: string;
        text: string;
        revision: string;
        capturedAtMs: number;
      }
    | undefined
  > {
    if ((this.retryAt.get(provider) ?? 0) > Date.now()) return;
    let token = this.tokens[provider];
    const subject = this.subject;
    if (!token || !subject) return;
    const epoch = this.epoch;
    const signal = AbortSignal.any([cancellation, this.controller.signal]);
    try {
      if (token.expiresAtMs && token.expiresAtMs <= Date.now() + 60000) {
        if (!token.refreshToken) throw new Error("Reconnect source");
        const oldRefreshToken = token.refreshToken;
        token = {
          ...tokenSchema.parse(
            await this.options.remote.call(
              `connectors/${provider}/refresh`,
              { refreshToken: oldRefreshToken },
              signal,
            ),
          ),
        };
        token.refreshToken ??= oldRefreshToken;
        if (epoch !== this.epoch) return;
        this.tokens = { ...this.tokens, [provider]: token };
        await this.persist(subject, epoch, signal);
        if (epoch !== this.epoch || signal.aborted) return;
      }
      const result = await this.options.remote.call<{
        resourceId: string;
        text: string;
        revision: string;
        capturedAtMs: number;
      }>(
        `connectors/${provider}/read`,
        { accessToken: token.accessToken, resourceId },
        signal,
      );
      if (epoch !== this.epoch || signal.aborted) return;
      const parsed = z
        .object({
          resourceId: z.string().min(1).max(300),
          text: z.string().min(1).max(16000),
          revision: z.string().min(1).max(512),
          capturedAtMs: z.number().int().nonnegative(),
        })
        .parse(result);
      if (
        parsed.resourceId !== resourceId ||
        parsed.capturedAtMs > Date.now() + 1000 ||
        Date.now() - parsed.capturedAtMs > 300000
      )
        throw new Error("Invalid source");
      return parsed;
    } catch (error) {
      if (epoch !== this.epoch || signal.aborted) return;
      if (
        error instanceof ContextRequestError &&
        error.code === "rate_limited"
      ) {
        this.retryAt.set(
          provider,
          Date.now() +
            Math.min(86400000, Math.max(1000, error.retryAfterMs ?? 60000)),
        );
        return;
      }
      if (
        error instanceof ContextRequestError &&
        error.code === "authorization_revoked"
      ) {
        this.epoch++;
        this.controller.abort();
        this.controller = new AbortController();
        const currentEpoch = this.epoch;
        delete this.tokens[provider];
        this.options.changed();
        try {
          await this.persist(subject, currentEpoch, this.controller.signal);
        } finally {
          await this.options.revoked?.(provider);
        }
        return;
      }
      throw error;
    }
  }
  dispose(): void {
    this.cancelLogin?.();
    this.cancelLogin = null;
    this.controller.abort();
    this.tokens = {};
    this.subject = null;
    this.epoch++;
  }
}
