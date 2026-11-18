import type { ProtocolMessage } from "@autocompletion/protocol";
import { writeFile } from "node:fs/promises";

import type {
  SuggestionActivitySummary,
} from "../shared/contracts";
import type { HelperConfigurationDisabledReason } from "./helper-configuration";

type PermissionGrant = "granted" | "required";
type PipelineStage =
  | "manual_request_invoked"
  | "manual_request_sent"
  | "manual_request_blocked"
  | "starting"
  | "helper_running"
  | "capture_observed"
  | "response_final"
  | "request_failed"
  | "interaction"
  | "outcome_upload_failed"
  | "helper_diagnostic";
type RequestFailure = "unauthorized" | "network" | "timeout" | "server";
type RequestState = "observed" | "cancelled" | "final" | "failed";
type RequestDetail =
  | "content_changed"
  | "focus_changed"
  | "dismissed"
  | "shutdown"
  | RequestFailure;
type WriteSnapshot = (path: string, data: string) => Promise<unknown>;
type Now = () => number;
type PipelineSnapshot = {
  sequence: number;
  timestampMs: number;
  stage: PipelineStage;
  detail?: string;
};

type RuntimeSnapshot = {
  version: 2;
  updatedAt: string;
  configuration?: {
    enabled: boolean;
    reasons: readonly HelperConfigurationDisabledReason[];
  };
  permissions?: {
    accessibility: PermissionGrant;
    inputMonitoring: PermissionGrant;
  };
  request?: {
    state: RequestState;
    detail?: RequestDetail;
  };
  pipeline: PipelineSnapshot;
  recentPipeline: PipelineSnapshot[];
  lastManualRequest?: PipelineSnapshot;
  activity?: SuggestionActivitySummary;
};

export class RuntimeDiagnostics {
  readonly #snapshot: RuntimeSnapshot;
  #pending: Promise<unknown> = Promise.resolve();
  #sequence = 0;

  constructor(
    private readonly path: string,
    private readonly writeSnapshot: WriteSnapshot = writeFile,
    private readonly now: Now = Date.now,
  ) {
    const timestampMs = this.now();
    const starting = { sequence: 0, timestampMs, stage: "starting" } as const;
    this.#snapshot = {
      version: 2,
      updatedAt: new Date(timestampMs).toISOString(),
      pipeline: starting,
      recentPipeline: [starting],
    };
    this.#persist(timestampMs);
  }

  configuration(
    enabled: boolean,
    reasons: readonly HelperConfigurationDisabledReason[],
  ): void {
    this.#snapshot.configuration = { enabled, reasons: [...reasons] };
    this.#persist();
  }

  permission(
    accessibility: PermissionGrant,
    inputMonitoring: PermissionGrant,
  ): void {
    this.#snapshot.permissions = { accessibility, inputMonitoring };
    this.#persist();
  }

  request(state: RequestState, detail?: RequestDetail): void {
    this.#snapshot.request = detail ? { state, detail } : { state };
    this.#persist();
  }

  pipeline(stage: Exclude<PipelineStage, "helper_diagnostic">, detail?: RequestFailure | "disabled" | "helper_unavailable"): void {
    const timestampMs = this.now();
    this.#recordPipeline(detail ? { stage, detail } : { stage }, timestampMs);
    this.#persist(timestampMs);
  }

  interaction(outcome: Extract<ProtocolMessage, {type:"interaction"}>["payload"]["outcome"]): void {
    const timestampMs = this.now();
    this.#recordPipeline({ stage: "interaction", detail: outcome }, timestampMs);
    this.#persist(timestampMs);
  }

  activity(summary: SuggestionActivitySummary): void {
    this.#snapshot.activity = structuredClone(summary);
    this.#persist();
  }

  helperDiagnostic(code: string): void {
    const safeCode = /^[a-z0-9_]{1,100}$/.test(code) ? code : "unknown";
    const timestampMs = this.now();
    this.#recordPipeline({
      stage: "helper_diagnostic",
      detail: safeCode,
    }, timestampMs);
    this.#persist(timestampMs);
  }

  flush(): Promise<unknown> {
    return this.#pending;
  }

  #recordPipeline(
    event: Pick<PipelineSnapshot, "stage" | "detail">,
    timestampMs: number,
  ): void {
    const snapshot = {
      ...event,
      sequence: ++this.#sequence,
      timestampMs,
    };
    this.#snapshot.pipeline = snapshot;
    if (event.stage.startsWith("manual_request_")) this.#snapshot.lastManualRequest = snapshot;
    this.#snapshot.recentPipeline.push(snapshot);
    if (this.#snapshot.recentPipeline.length > 256) {
      this.#snapshot.recentPipeline.splice(
        0,
        this.#snapshot.recentPipeline.length - 256,
      );
    }
  }

  #persist(timestampMs: number = this.now()): void {
    this.#snapshot.updatedAt = new Date(timestampMs).toISOString();
    const serialized = `${JSON.stringify(this.#snapshot)}\n`;
    this.#pending = this.#pending
      .catch(() => undefined)
      .then(() => this.writeSnapshot(this.path, serialized))
      .catch(() => undefined);
  }
}
