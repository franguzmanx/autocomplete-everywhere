import {
  GENERATION_MODEL_ID,
  LOCAL_USER_ID,
  createLocalApi,
  verifyGatewayKey,
  type GatewayKeyVerdict,
  type LocalApi,
} from "../../../../services/api/src/local-api";
import type { AccountIdentity } from "../shared/contracts";
import type { Account } from "./account-session";
import type { ProductState } from "./state";

/** Placeholder origin for requests that never leave the process. */
export const LOCAL_API_ORIGIN = "https://local.invalid";
export const GATEWAY_KEYS_URL = "https://vercel.com/ai-gateway";

const IDENTITY: AccountIdentity = { subject: LOCAL_USER_ID, name: "", email: "" };
const KEY_PATTERN = /^[\x21-\x7e]{8,512}$/;

type StoredLocalBackend = { gatewayApiKey?: string };
type Options = {
  store: { read<T>(): Promise<T | null>; write(value: unknown): Promise<void> };
  state: ProductState;
  openExternal(url: string): Promise<void>;
  invalidate(): void;
  changed(): void;
  verify?: (apiKey: string) => Promise<GatewayKeyVerdict>;
  createApi?: (options: { apiKey: string }) => LocalApi;
};

/**
 * The account when no hosted backend is configured: one local user whose
 * credential is their own AI Gateway key. The API runs in process, so the key
 * goes only to the gateway.
 */
export class LocalAccount implements Account {
  readonly library = null;
  readonly tokenProvider = {
    getAccessToken: async (): Promise<string> => {
      if (!this.api) throw new Error("unauthorized");
      return LOCAL_USER_ID;
    },
  };
  private api: LocalApi | null = null;

  constructor(private readonly options: Options) {
    // Settings must offer the key field, not a sign-in, before the store is read.
    options.state.update({ account: { state: "signed_out", identity: null, kind: "api_key", model: GENERATION_MODEL_ID } });
  }

  /** Stands in for `fetch` in every API transport. */
  readonly request: typeof fetch = async (input, init) => {
    if (!this.api) return new Response(null, { status: 401 });
    return this.api.fetch(new Request(input, init));
  };

  private publish(state: "signed_in" | "signed_out" | "expired"): void {
    this.options.state.update({
      account: { state, identity: state === "signed_in" ? IDENTITY : null, kind: "api_key", model: GENERATION_MODEL_ID },
      ...(state === "signed_in" ? { connection: "ready" as const } : {}),
    });
    this.options.changed();
  }

  private open(apiKey: string): void {
    this.api = (this.options.createApi ?? createLocalApi)({ apiKey });
    this.publish("signed_in");
  }

  async initialize(): Promise<void> {
    const stored = await this.options.store.read<StoredLocalBackend>();
    if (stored?.gatewayApiKey) this.open(stored.gatewayApiKey);
    else this.publish("signed_out");
  }

  async setApiKey(value: string): Promise<void> {
    const apiKey = value.trim();
    if (!KEY_PATTERN.test(apiKey)) throw new Error("That does not look like an AI Gateway key.");
    if (await (this.options.verify ?? verifyGatewayKey)(apiKey) === "rejected") {
      throw new Error("AI Gateway rejected this key. Check it and try again.");
    }
    await this.options.store.write({ gatewayApiKey: apiKey } satisfies StoredLocalBackend);
    this.options.invalidate();
    this.open(apiKey);
  }

  async signOut(): Promise<void> {
    this.api = null;
    this.options.invalidate();
    this.publish("signed_out");
    await this.options.store.write({} satisfies StoredLocalBackend);
  }

  expire(): void {
    this.api = null;
    this.options.invalidate();
    this.publish("expired");
  }

  async beginSignIn(): Promise<void> {
    throw new Error("Add your AI Gateway key in Account.");
  }

  async restoreIdentity(): Promise<void> {}

  async openManageAccount(): Promise<void> {
    await this.options.openExternal(GATEWAY_KEYS_URL);
  }

  dispose(): void {
    this.api = null;
  }
}
