import { DEFAULT_SHORTCUT, DEFAULT_ACCEPT_SHORTCUT, DEFAULT_DISMISS_SHORTCUT } from "./suggestion-shortcut";
import { emptySuggestionActivity, type SuggestionActivitySummary, type ProductStatus } from "../shared/contracts";

export type RestoredProductState = {
  apps: Record<string, boolean>;
  signedIn: boolean;
  enabled: boolean;
};

export class ProductState {
  readonly #listeners = new Set<(status: ProductStatus) => void>();
  readonly #status: ProductStatus = {
    permissions: {
      accessibility: "unknown",
      inputMonitoring: "unknown",
    },
    account: { state: "signed_out", identity: null },
    uiLanguage: "en", timing: "balanced", visibility: "subtle",
    shortcut: DEFAULT_SHORTCUT, acceptShortcut: DEFAULT_ACCEPT_SHORTCUT, dismissShortcut: DEFAULT_DISMISS_SHORTCUT, helperState: "starting", shortcutRegistered: true, libraryAvailable: false, connection: "ready", exercise: "idle",
    personalization: { enabled: false, revision: 0, preferences: [] },
    enabled: false,
    activity: emptySuggestionActivity(new Date().toISOString()),
    pausedUntil: null,
    automaticSuggestions: true,
    apps: {},
    applications: [],
    currentApplication: null,
  };

  constructor(options: { startedAt?: string } = {}) {
    this.#status.activity = emptySuggestionActivity(options.startedAt ?? new Date().toISOString());
  }

  setActivity(activity: SuggestionActivitySummary): void { this.update({ activity: structuredClone(activity) }); }

  snapshot(): ProductStatus {
    return structuredClone(this.#status);
  }

  restore(restored: RestoredProductState): void {
    this.#status.account.state = restored.signedIn ? "signed_in" : "signed_out";
    this.#status.enabled = restored.enabled;
    this.#status.apps = structuredClone(restored.apps);
    this.#notify();
  }

  update(values: Partial<ProductStatus>): void {
    if(Object.entries(values).every(([key,value])=>JSON.stringify(this.#status[key as keyof ProductStatus])===JSON.stringify(value)))return;
    Object.assign(this.#status, values); this.#notify();
  }

  setSignedIn(): void {
    this.#status.account.state = "signed_in";
    this.#notify();
  }

  setEnabled(enabled: boolean): void {
    this.#status.enabled = enabled;
    this.#notify();
  }

  setPreferences(preferences: Pick<ProductStatus, "enabled" | "pausedUntil" | "automaticSuggestions" | "apps" | "uiLanguage" | "timing" | "visibility" | "shortcut" | "acceptShortcut" | "dismissShortcut">): void {
    Object.assign(this.#status, structuredClone(preferences));
    this.#notify();
  }

  setApplications(applications: ProductStatus["applications"], currentApplication: string | null): void {
    this.update({applications:structuredClone(applications),currentApplication});
  }

  setAppEnabled(appId: string, enabled: boolean): void {
    this.#status.apps[appId] = enabled;
    this.#notify();
  }

  setPermissions(permissions: ProductStatus["permissions"]): void {
    this.update({permissions:structuredClone(permissions)});
  }

  subscribe(listener: (status: ProductStatus) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  #notify(): void {
    for (const listener of this.#listeners) listener(this.snapshot());
  }
}
