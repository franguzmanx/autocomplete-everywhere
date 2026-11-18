import { mkdtemp, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, expect, test, vi } from "vitest";
import { ProductPreferences, ReservedShortcutPreferencesError } from "../src/main/product-preferences";
import { ProductState } from "../src/main/state";
import { createHelperConfiguration } from "../src/main/helper-configuration";

let directory: string;
test("interaction shortcuts persist, reach the helper, and reject conflicts without changing saved controls", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-keys-"));
  const state = new ProductState();
  const path = join(directory, "preferences.json");
  const prefs = new ProductPreferences(path, state);
  await prefs.load();
  const accept = { accelerator: "Command+Enter", keyCode: 36, modifiers: 256 };
  await prefs.setInteractionShortcut("accept", accept);
  await expect(prefs.setInteractionShortcut("dismiss", accept)).rejects.toThrow();
  await expect(prefs.setShortcut(accept)).rejects.toThrow();
  await expect(prefs.setInteractionShortcut("accept", { accelerator: "A", keyCode: 0, modifiers: 0 })).rejects.toThrow();
  prefs.dispose();
  const reopened = new ProductPreferences(path, state); await reopened.load();
  expect(state.snapshot().acceptShortcut).toEqual(accept);
  expect(createHelperConfiguration(state.snapshot()).payload).toMatchObject({ acceptShortcut: {keyCode:36,modifiers:256}, dismissShortcut: {keyCode:53,modifiers:0} });
  reopened.dispose();
});
afterEach(async () => { vi.useRealTimers(); if (directory) await rm(directory, { recursive: true, force: true }); });

test("a timed pause survives restart and expires without enabling excluded apps", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_788_530_000_000);
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const state = new ProductState();
  const prefs = new ProductPreferences(join(directory, "preferences.json"), state);
  await prefs.load();
  await prefs.setAppEnabled("com.apple.Notes", false);
  await prefs.pause("15m");
  expect(state.snapshot().enabled).toBe(false);
  const deadline = state.snapshot().pausedUntil;
  prefs.dispose();
  vi.setSystemTime(1_788_530_300_000);
  const restored = new ProductState();
  const reopened = new ProductPreferences(join(directory, "preferences.json"), restored);
  await reopened.load();
  expect(restored.snapshot()).toMatchObject({ enabled: false, pausedUntil: deadline, apps: { "com.apple.Notes": false } });
  await vi.advanceTimersByTimeAsync(600_000);
  await vi.waitFor(() => expect(restored.snapshot()).toMatchObject({ enabled: true, pausedUntil: null, apps: { "com.apple.Notes": false } }));
  reopened.dispose();
});

test("rapid controls persist together, manual mode reaches helper, and resume cancels old timer", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_788_530_000_000);
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const state = new ProductState();
  const prefs = new ProductPreferences(join(directory, "preferences.json"), state);
  await prefs.load(); state.setSignedIn(); state.setPermissions({ accessibility: "granted", inputMonitoring: "granted" });
  await Promise.all([prefs.setAppEnabled("com.apple.Notes", false), prefs.saveWriting({automaticSuggestions:false,timing:"balanced",visibility:"subtle"})]);
  expect(createHelperConfiguration(state.snapshot(), { suggestionsAvailable: true }).payload).toMatchObject({ enabled: true, excludedApplications: ["com.apple.Notes", "com.autocompletion.settings"], automaticSuggestions: false });
  await prefs.pause("15m"); await prefs.resume(); await prefs.pause("30m");
  await vi.advanceTimersByTimeAsync(3_600_000);
  await vi.waitFor(() => expect(state.snapshot().enabled).toBe(true));
  prefs.dispose();
  const reopened = new ProductPreferences(join(directory, "preferences.json"), state);
  await reopened.load();
  expect(state.snapshot()).toMatchObject({ enabled: true, pausedUntil: null, automaticSuggestions: false, apps: { "com.apple.Notes": false } });
  reopened.dispose();
});


test("tomorrow is next local 09:00, invalid indefinite pause is rejected, preferences reach helper", async () => {
  vi.useFakeTimers(); vi.setSystemTime(new Date(2026, 8, 5, 20, 15));
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const state = new ProductState(); const prefs = new ProductPreferences(join(directory, "prefs.json"), state);
  await prefs.load();
  await prefs.pause("tomorrow");
  expect(state.snapshot().pausedUntil).toBe(new Date(2026, 8, 6, 9).getTime());
  expect(() => prefs.pause(null as never)).toThrow();
  await prefs.resume(); await prefs.saveWriting({automaticSuggestions:true,timing:"quick",visibility:"clear"}); await prefs.setUiLanguage("es");
  expect(createHelperConfiguration(state.snapshot()).payload).toMatchObject({ quietPeriodMs:150, ghostAlpha:0.45 });
  expect(state.snapshot().uiLanguage).toBe("es"); prefs.dispose();
});

test("the chosen shortcut and explicit clearing survive reopening", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const state = new ProductState();
  const path = join(directory, "preferences.json");
  const prefs = new ProductPreferences(path, state);
  await prefs.load();
  const shortcut = {accelerator:"Control+Alt+K",keyCode:40,modifiers:6144};
  await prefs.setShortcut(shortcut); prefs.dispose();
  const reopened = new ProductPreferences(path, state); await reopened.load();
  expect(state.snapshot().shortcut).toEqual(shortcut);
  await reopened.setShortcut(null); reopened.dispose();
  const cleared = new ProductPreferences(path, state); await cleared.load();
  expect(state.snapshot().shortcut).toBeNull(); cleared.dispose();
});


test("Writing saves atomically, survives reopening, and publishes nothing on disk failure", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-writing-"));
  const path = join(directory, "preferences.json");
  const state = new ProductState();
  const prefs = new ProductPreferences(path, state);
  await prefs.load();
  const observed: unknown[] = [];
  const unsubscribe = state.subscribe(value => observed.push({automaticSuggestions:value.automaticSuggestions, timing:value.timing, visibility:value.visibility}));
  const writing = {automaticSuggestions:false, timing:"quick" as const, visibility:"clear" as const};
  await prefs.saveWriting(writing);
  expect(observed).toEqual([writing]);
  prefs.dispose(); unsubscribe();
  const restored = new ProductState();
  const reader = new ProductPreferences(path, restored); await reader.load();
  expect(restored.snapshot()).toMatchObject(writing); reader.dispose();
  // A file cannot contain a preferences directory: exercise a real failed write.
  const brokenState = new ProductState();
  const broken = new ProductPreferences(join(path, "blocked.json"), brokenState);
  await expect(broken.saveWriting(writing)).rejects.toThrow();
  expect(brokenState.snapshot()).toMatchObject({automaticSuggestions:true,timing:"balanced",visibility:"subtle"});
  broken.dispose();
});

test("reserved shortcuts reject updates and saved input without rewriting preferences", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const path = join(directory, "preferences.json");
  const state = new ProductState();
  const prefs = new ProductPreferences(path, state);
  await prefs.load();
  const before = state.snapshot();
  const reserved = {accelerator:"Alt+Tab",keyCode:48,modifiers:2048};
  await expect(prefs.setShortcut(reserved)).rejects.toThrow();
  await expect(prefs.setInteractionShortcut("accept", reserved)).rejects.toThrow();
  await expect(prefs.setInteractionShortcut("dismiss", reserved)).rejects.toThrow();
  expect(state.snapshot().dismissShortcut).toEqual(before.dismissShortcut);
  await writeFile(path, JSON.stringify({...before, dismissShortcut:reserved}));
  await expect(new ProductPreferences(path, new ProductState()).load()).rejects.toThrow();
  prefs.dispose();
});

test("explicit shortcut repair preserves validated privacy and writing settings", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const path = join(directory, "preferences.json");
  const saved = {pausedUntil:Date.now()+60_000, automaticSuggestions:false, apps:{"com.private.editor":false}, uiLanguage:"es", timing:"deliberate", visibility:"clear", shortcut:{accelerator:"Control+K",keyCode:40,modifiers:4096}, acceptShortcut:{accelerator:"Enter",keyCode:36,modifiers:0}, dismissShortcut:{accelerator:"Alt+Tab",keyCode:48,modifiers:2048}};
  const original = JSON.stringify(saved);
  await writeFile(path, original);
  const state = new ProductState();
  const prefs = new ProductPreferences(path, state);
  await expect(prefs.load()).rejects.toBeInstanceOf(ReservedShortcutPreferencesError);
  expect(await readFile(path, "utf8")).toBe(original);
  await prefs.resetReservedShortcuts();
  const repaired = JSON.parse(await readFile(path, "utf8"));
  expect(repaired).toEqual({...saved, shortcut:{accelerator:"Command+Shift+Space",keyCode:49,modifiers:768}, acceptShortcut:{accelerator:"Tab",keyCode:48,modifiers:0}, dismissShortcut:{accelerator:"Escape",keyCode:53,modifiers:0}});
  await prefs.load();
  expect(state.snapshot()).toMatchObject({apps:saved.apps,automaticSuggestions:false,uiLanguage:"es",timing:"deliberate",enabled:false});
  prefs.dispose();
});

test("shortcut repair refuses unrelated invalid preferences and never rewrites them", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-prefs-"));
  const path = join(directory, "preferences.json");
  for (const invalid of [{apps:{"invalid app":false}}, {dismissShortcut:{accelerator:"nonsense",keyCode:48,modifiers:2048}}, {timing:"invalid"}]) {
    const original = JSON.stringify({pausedUntil:null,automaticSuggestions:true,apps:{},dismissShortcut:{accelerator:"Alt+Tab",keyCode:48,modifiers:2048},...invalid});
    await writeFile(path, original);
    const prefs = new ProductPreferences(path, new ProductState());
    await expect(prefs.load()).rejects.not.toBeInstanceOf(ReservedShortcutPreferencesError);
    await expect(prefs.resetReservedShortcuts()).rejects.toThrow();
    expect(await readFile(path,"utf8")).toBe(original);
    prefs.dispose();
  }
});

test("Instant timing persists and reaches the helper as zero milliseconds", async () => {
  directory = await mkdtemp(join(tmpdir(), "autocompletion-instant-"));
  const path = join(directory, "preferences.json");
  const state = new ProductState();
  const prefs = new ProductPreferences(path, state);
  await prefs.load();
  await prefs.saveWriting({automaticSuggestions:true, timing:"instant", visibility:"subtle"});
  prefs.dispose();
  const reopened = new ProductPreferences(path, state);
  await reopened.load();
  expect(state.snapshot().timing).toBe("instant");
  expect(createHelperConfiguration(state.snapshot()).payload.quietPeriodMs).toBe(0);
  reopened.dispose();
});
