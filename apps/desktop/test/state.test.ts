import { describe, expect, test } from "vitest";

import { ProductState } from "../src/main/state";
import { emptySuggestionActivity } from "../src/shared/contracts";

describe("product state", () => {
  test("starts with unknown permissions until the native helper reports", () => {
    expect(new ProductState().snapshot().permissions).toEqual({
      accessibility: "unknown",
      inputMonitoring: "unknown",
    });
  });

  test("restores non-secret status from encrypted persisted data", () => {
    const state = new ProductState();
    state.restore({
      apps: {},
      signedIn: true,
      enabled: true,
    });

    expect(state.snapshot()).toMatchObject({
      account: { state: "signed_in" },
      enabled: true,
    });
  });

  test("returns a copy that cannot mutate the main-process state", () => {
    const state = new ProductState();
    const snapshot = state.snapshot();
    snapshot.enabled = true;

    expect(state.snapshot().enabled).toBe(false);
  });

  test("starts the activity baseline at the session start, not the epoch", () => {
    const explicit = new ProductState({ startedAt: "2026-09-03T08:15:00.000Z" });
    expect(explicit.snapshot().activity.since).toBe("2026-09-03T08:15:00.000Z");

    const before = Date.now();
    const live = new ProductState();
    const since = Date.parse(live.snapshot().activity.since);
    expect(since).toBeGreaterThanOrEqual(before - 1_000);
    expect(since).toBeLessThanOrEqual(Date.now() + 1_000);
  });

  test("publishes content-free suggestion activity to the product status", () => {
    const state = new ProductState({ startedAt: "2026-09-03T00:00:00.000Z" });

    expect(state.snapshot().activity).toMatchObject({ requested: 0, shown: 0 });

    state.setActivity({
      ...emptySuggestionActivity("2026-09-03T00:00:00.000Z"),
      requested: 2,
      shown: 1,
      lastOutcome: "shown",
    });

    expect(state.snapshot().activity).toMatchObject({
      requested: 2,
      shown: 1,
      lastOutcome: "shown",
    });
  });

  test("uses the native helper permission state", () => {
    const state = new ProductState();

    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "required",
    });

    expect(state.snapshot().permissions).toEqual({
      accessibility: "granted",
      inputMonitoring: "required",
    });
  });

  test("notifies subscribers after changes and supports unsubscribe", () => {
    const state = new ProductState();
    const snapshots: boolean[] = [];
    const unsubscribe = state.subscribe((snapshot) => {
      snapshots.push(snapshot.enabled);
    });

    state.setEnabled(true);
    unsubscribe();
    state.setEnabled(false);

    expect(snapshots).toEqual([true]);
  });
});
