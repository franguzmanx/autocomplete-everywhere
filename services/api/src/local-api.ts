import { createGateway, GatewayAuthenticationError } from "@ai-sdk/gateway";

import { createApi, createMemoryLeasePool } from "./compose.js";

/** The single user of an API that runs inside the desktop app. */
export const LOCAL_USER_ID = "local";

export type LocalApi = {
  /** Dispatches a request to the routes in process. No port is opened. */
  fetch(request: Request): Promise<Response>;
};

/**
 * The same routes as the hosted API, for one person using their own AI
 * Gateway key. There is no identity provider and no database: outcome events
 * are discarded and background work is bounded in memory.
 */
export function createLocalApi(options: { apiKey: string }): LocalApi {
  const app = createApi({
    authenticate: async request =>
      request.headers.get("authorization") ? { userId: LOCAL_USER_ID } : null,
    modelProvider: createGateway({ apiKey: options.apiKey }),
    aiDiagnostics: "off",
    environment: {},
    backgroundLeases: createMemoryLeasePool(),
    outcomes: { record: async () => {} },
  });
  return { fetch: async request => app.fetch(request) };
}

export type GatewayKeyVerdict = "accepted" | "rejected" | "unverified";

/**
 * Asks the gateway whether it accepts the key. A network or service failure is
 * "unverified", so a key can still be saved while offline.
 */
export async function verifyGatewayKey(apiKey: string): Promise<GatewayKeyVerdict> {
  try {
    await createGateway({ apiKey }).getCredits();
    return "accepted";
  } catch (error) {
    return GatewayAuthenticationError.isInstance(error) ? "rejected" : "unverified";
  }
}
