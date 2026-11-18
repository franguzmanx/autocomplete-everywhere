import { defaultTransformSettings, TransformSettingsSchema, type TransformSettings } from '@autocompletion/protocol';

export class TransformSettingsStore {
  private settings = defaultTransformSettings();
  private writes: Promise<void> = Promise.resolve();
  constructor(private readonly store: { read<T>(): Promise<T | null>; write(value: unknown): Promise<void> }, private readonly onChange: () => void) {}
  async restore(): Promise<void> {
    const stored = await this.store.read<unknown>();
    if (stored !== null) this.settings = TransformSettingsSchema.parse(stored);
  }
  get(): TransformSettings { return structuredClone(this.settings); }
  async save(input: unknown): Promise<void> {
    const parsed = TransformSettingsSchema.safeParse(input);
    if (!parsed.success) throw new Error('Use unique shortcuts, a name, and at least one rule or instruction. Check text limits.');
    const pending = this.writes.then(async () => {
      await this.store.write(parsed.data);
      this.settings = parsed.data;
      this.onChange();
    });
    this.writes = pending.catch(() => {});
    return pending;
  }
}
