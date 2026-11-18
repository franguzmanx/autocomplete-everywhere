import { expect, test, vi } from "vitest";
import { SuggestionShortcut, interactionShortcutSchema, shortcutSchema, DEFAULT_SHORTCUT } from "../src/main/suggestion-shortcut";
const next = { accelerator: "Command+Alt+K", keyCode: 40, modifiers: 2304 };

test("a conflicting shortcut keeps the working registration and preference", async () => {
  const register = vi.fn().mockReturnValueOnce(true).mockReturnValueOnce(false);
  const unregister = vi.fn(); const save = vi.fn();
  const shortcut = new SuggestionShortcut({register, unregister}, () => {});
  expect(shortcut.start(DEFAULT_SHORTCUT)).toBe(true);
  await expect(shortcut.change(next, save)).rejects.toThrow("unavailable");
  expect(save).not.toHaveBeenCalled(); expect(unregister).not.toHaveBeenCalled();
});
test("a saved change replaces the old registration and a failed save rolls back", async () => {
  const register = vi.fn(() => true); const unregister = vi.fn();
  const shortcut = new SuggestionShortcut({register, unregister}, () => {});
  shortcut.start(DEFAULT_SHORTCUT);
  await expect(shortcut.change(next, async () => { throw new Error("disk"); })).rejects.toThrow("disk");
  expect(unregister).toHaveBeenCalledWith(next.accelerator);
  unregister.mockClear();
  await shortcut.change(next, async () => {});
  expect(unregister).toHaveBeenCalledWith(DEFAULT_SHORTCUT.accelerator);
});
test("rejects typing keys and malformed shortcut payloads", () => {
  expect(shortcutSchema.safeParse({...next, accelerator:"K"}).success).toBe(false);
  expect(shortcutSchema.safeParse({...next, accelerator:"Shift+K"}).success).toBe(false);
  expect(shortcutSchema.safeParse({...next, modifiers: -1}).success).toBe(false);
  expect(shortcutSchema.safeParse(next).success).toBe(true);
});

test("clearing the shortcut unregisters it after saving", async () => {
  const unregister = vi.fn();
  const shortcut = new SuggestionShortcut({register: () => true, unregister}, () => {});
  shortcut.start(DEFAULT_SHORTCUT);
  const save = vi.fn(async () => { expect(unregister).not.toHaveBeenCalled(); });
  await shortcut.change(null, save);
  expect(unregister).toHaveBeenCalledWith(DEFAULT_SHORTCUT.accelerator);
});

test("recording releases the global shortcut and restores the latest saved binding", async () => {
  const register = vi.fn(() => true); const unregister = vi.fn();
  const shortcut = new SuggestionShortcut({register, unregister}, () => {});
  shortcut.start(DEFAULT_SHORTCUT);
  await shortcut.setRecording(true);
  expect(unregister).toHaveBeenCalledWith(DEFAULT_SHORTCUT.accelerator);
  register.mockClear();
  await shortcut.change(next, async () => {});
  expect(unregister).toHaveBeenCalledWith(next.accelerator);
  await shortcut.setRecording(false);
  expect(register).toHaveBeenLastCalledWith(next.accelerator, expect.any(Function));
});

const reserved = [[48, "Tab"], [125, "Down"], [126, "Up"], [18, "1"], [19, "2"], [20, "3"], [21, "4"], [23, "5"], [22, "6"], [26, "7"], [28, "8"], [25, "9"]] as const;
test("fixed Option actions cannot be assigned to configurable actions; additional modifiers remain usable", () => {
  for (const [keyCode, key] of reserved) {
    const binding = { accelerator: `Alt+${key}`, keyCode, modifiers: 2048 };
    for (const schema of [shortcutSchema, interactionShortcutSchema]) {
      expect(schema.safeParse(binding).success).toBe(false);
      expect(schema.safeParse({...binding, accelerator:`Alt+Shift+${key}`, modifiers:2560}).success).toBe(true);
    }
  }
});
test("startup does not register an impossible saved shortcut", () => {
  const register = vi.fn(() => true);
  const shortcut = new SuggestionShortcut({register, unregister:vi.fn()}, () => {});
  expect(() => shortcut.start({accelerator:"Alt+Tab",keyCode:48,modifiers:2048})).toThrow();
  expect(register).not.toHaveBeenCalled();
});
