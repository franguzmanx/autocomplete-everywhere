import { describe, expect, test } from "vitest";
import { createApp, type SuggestionOutcomeStore } from "../src/app";
const authenticated = async () => ({userId:"user_a"});
describe("suggestion outcomes", () => {
  test("returns an explicit unavailable result when persistence is not configured", async () => {
    const app = createApp({ authenticate: authenticated, generator: { complete: async () => undefined } });
    const response = await app.request("/v1/suggestions/outcomes", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ events: [{
        requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63", appId: "com.apple.Notes",
        surface: "text_editor", outcome: "requested",
      }] }),
    });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "outcomes_unavailable" });
  });
  test("records content-free outcome batches only for the verified user", async () => {
    const recorded: unknown[] = [];
    const app = createApp({
      authenticate: authenticated,
      generator: { complete: async () => undefined },
      outcomes: {
        record: async (input) => {
          recorded.push(input);
        },
      },
    });

    const response = await app.request("/v1/suggestions/outcomes", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        events: [
          {
            requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
            appId: "com.apple.Notes",
            surface: "text_editor",
            outcome: "shown",
            requestToVisibleMs: 480,
            suggestionCharacterCount: 21,
          },
        ],
      }),
    });

    expect(response.status).toBe(204);
    expect(recorded).toEqual([
      {
        userId: "user_a",
        events: [
          {
            requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
            appId: "com.apple.Notes",
            surface: "text_editor",
            outcome: "shown",
            requestToVisibleMs: 480,
            suggestionCharacterCount: 21,
          },
        ],
      },
    ]);
  });

  test("rejects outcome events that carry content or arrive unauthenticated", async () => {
    let records = 0;
    const store: SuggestionOutcomeStore = {
      record: async () => {
        records += 1;
      },
    };
    const body = (event: Record<string, unknown>) =>
      JSON.stringify({
        events: [
          {
            requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
            appId: "com.apple.Notes",
            surface: "text_editor",
            outcome: "shown",
            ...event,
          },
        ],
      });

    const unauthenticated = createApp({
      authenticate: async () => null,
      generator: { complete: async () => undefined },
      outcomes: store,
    });
    expect(
      (
        await unauthenticated.request("/v1/suggestions/outcomes", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: body({}),
        })
      ).status,
    ).toBe(401);

    const app = createApp({
      authenticate: authenticated,
      generator: { complete: async () => undefined },
      outcomes: store,
    });
    const withContent = await app.request("/v1/suggestions/outcomes", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: body({ suggestionText: "private suggestion" }),
    });

    expect(withContent.status).toBe(400);
    expect(records).toBe(0);
  });

  test("fails closed when the outcome store is unavailable", async () => {
    const app = createApp({
      authenticate: authenticated,
      generator: { complete: async () => undefined },
      outcomes: {
        record: async () => {
          throw new Error("database unavailable");
        },
      },
    });

    const response = await app.request("/v1/suggestions/outcomes", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        events: [
          {
            requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
            appId: "com.apple.Notes",
            surface: "text_editor",
            outcome: "requested",
          },
        ],
      }),
    });

    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: "outcomes_unavailable" });
  });
});
