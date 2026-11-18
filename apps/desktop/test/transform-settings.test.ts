import { expect, it } from 'vitest';
import { defaultTransformSettings } from '@autocompletion/protocol';
import { TransformSettingsStore } from '../src/main/transform-settings';

it('serializes saves and restores settings without overwriting newer writes', async () => {
  let stored: unknown = null;
  const storage = { read: async <T>() => stored as T, write: async (value: unknown) => { await new Promise(r => setTimeout(r, 2)); stored = value; } };
  const store = new TransformSettingsStore(storage, () => {});
  const first = defaultTransformSettings(); first.enabled = true;
  const second = defaultTransformSettings(); second.transforms[0]!.name = 'My polish';
  await Promise.all([store.save(first), store.save(second)]);
  const restored = new TransformSettingsStore(storage, () => {}); await restored.restore();
  expect(restored.get()).toEqual(second);
  const copy = restored.get(); copy.transforms.length = 0;
  expect(restored.get().transforms).toHaveLength(3);
});
it('keeps current settings if encrypted storage fails and allows a subsequent save', async () => {
  let fails = true;
  const store = new TransformSettingsStore({ read: async () => null, write: async () => { if (fails) throw new Error('disk'); } }, () => {});
  const next = defaultTransformSettings(); next.enabled = true;
  await expect(store.save(next)).rejects.toThrow('disk');
  expect(store.get().enabled).toBe(false);
  fails = false; await store.save(next); expect(store.get().enabled).toBe(true);
});
