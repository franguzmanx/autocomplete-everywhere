import type { KnowledgeCandidate, PersonalizationSnapshot } from "@autocompletion/protocol";

export type PermissionState = "unknown" | "required" | "granted";

/// Content-free lifecycle outcomes for one suggestion request. They mirror
/// the helper's interaction report plus the desktop's own response states.
export type SuggestionOutcome =
  | "requested"
  | "generated"
  | "suppressed"
  | "failed"
  | "cancelled"
  | "shown"
  | "accepted_full"
  | "accepted_partial"
  | "typed_through"
  | "dismissed"
  | "stale";

export type LatencySummary = {
  p50: number | null;
  p95: number | null;
  samples: number;
};

/// Aggregate activity since the app started. Counts and latency bands only;
/// never text, application identity, or anything derived from a draft.
export type SuggestionActivitySummary = {
  since: string;
  requested: number;
  generated: number;
  suppressed: number;
  failed: number;
  cancelled: number;
  shown: number;
  accepted: number;
  typedThrough: number;
  dismissed: number;
  stale: number;
  acceptedCharacters: number;
  requestToVisibleMs: LatencySummary;
  requestToFinalMs: LatencySummary;
  lastOutcome: SuggestionOutcome | null;
};

/// `since` is the moment measurement began (the app start for the live
/// product). Callers must pass it explicitly; there is no epoch default.
export function emptySuggestionActivity(since: string): SuggestionActivitySummary {
  return {
    since,
    requested: 0,
    generated: 0,
    suppressed: 0,
    failed: 0,
    cancelled: 0,
    shown: 0,
    accepted: 0,
    typedThrough: 0,
    dismissed: 0,
    stale: 0,
    acceptedCharacters: 0,
    requestToVisibleMs: { p50: null, p95: null, samples: 0 },
    requestToFinalMs: { p50: null, p95: null, samples: 0 },
    lastOutcome: null,
  };
}

export type ProductStatus = {
  permissions: {
    accessibility: PermissionState;
    inputMonitoring: PermissionState;
  };
  account: {
    state: "signed_out" | "signed_in" | "expired";
    identity: AccountIdentity | null;
    /** Present when the credential is the user's own AI Gateway key. */
    kind?: "api_key";
    /** Model that answers suggestions, shown in Settings. */
    model?: string;
  };
  enabled: boolean;
  activity: SuggestionActivitySummary;
  pausedUntil: number | null;
  automaticSuggestions: boolean;
  uiLanguage: UiLanguage;
  timing: SuggestionTiming;
  visibility: SuggestionVisibility;
  helperState: "starting" | "running" | "unavailable";
  shortcutRegistered: boolean;
  shortcut: SuggestionKeyBinding | null;
  acceptShortcut: SuggestionKeyBinding;
  dismissShortcut: SuggestionKeyBinding;
  libraryAvailable: boolean;
  personalization: PersonalizationSnapshot;
  connection: "ready" | "offline" | "error";
  exercise: "idle" | "waiting" | "shown" | "accepted" | "dismissed" | "unavailable";
  apps: Record<string, boolean>;
  applications: { id: string; name: string }[];
  currentApplication: string | null;
};

export type LibraryEntry = Omit<KnowledgeCandidate, "sourceId"> & {
  id: string;
  createdAt: number;
  provenance: { kind: "user" } | { kind: "file"; name: string };
};
export type LibraryInput = Pick<LibraryEntry, "title" | "kind" | "text" | "scope" | "expiresAt"> & { id?: string | undefined; expectedRevision?: number | undefined };
export type LibraryImportInput = Omit<LibraryInput, "text">;

export type UiLanguage = "en" | "es";
export type SuggestionTiming = "instant" | "quick" | "balanced" | "deliberate";
export type SuggestionVisibility = "subtle" | "clear";
export type PauseChoice = "15m" | "30m" | "1h" | "tomorrow";
export type AccountIdentity = { subject: string; name: string; email: string };
export const TIMING_MS = { instant:0, quick:150, balanced:300, deliberate:700 } as const;
export const GHOST_ALPHA = { subtle:0.30, clear:0.45 } as const;

export type SuggestionKeyBinding = { accelerator: string; keyCode: number; modifiers: number };
