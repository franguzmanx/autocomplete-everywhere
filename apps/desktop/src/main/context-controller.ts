import { BackgroundOperations } from "./background-operations";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { ContextEngine, type ContextSnapshot } from "./context-engine";
import { ContextServiceClient } from "./context-service";
import { ContextTransport } from "./context-transport";
import { ContextConnectors } from "./context-connectors";
import { SecureStore } from "./secure-store";
import {
  PROTOCOL_VERSION,
  type ProtocolMessage,
} from "@autocompletion/protocol";
import type { NativeRequest } from "./native-settings-protocol";
import type { ProductStatus } from "../shared/contracts";
export class ContextController {
  readonly engine: ContextEngine;
  readonly background = new BackgroundOperations();
  private service: ContextServiceClient;
  private connectors: ContextConnectors;
  private screenGranted = false;
  private locked = false;
  private visualRevision = 0;
  private subject: string | null = null;
  private visualEnabled = false;
  private consentSerial: Promise<unknown> = Promise.resolve();
  private consentStore!: (subject: string) => SecureStore;
  constructor(
    private options: {
      root: string;
      executable: string;
      apiUrl: string;
      tokenProvider: { getAccessToken(): Promise<string> };
      request?: typeof fetch;
      visionVerified: boolean;
      open(url: string): Promise<void>;
      changed(): void;
      send(message: ProtocolMessage): void;
      invalidate(ids: string[]): void;
    },
  ) {
    const transport = new ContextTransport(options);
    const remote = {
      call: <T>(path: string, payload: unknown, signal: AbortSignal) =>
        this.background.run(signal, () =>
          transport.call<T>(path, payload, signal),
        ),
    };
    this.service = new ContextServiceClient({
      executable: options.executable,
      root: join(options.root, "context"),
    });
    const filename = (subject: string, name: string) =>
      join(
        options.root,
        "secure",
        `${name}-${createHash("sha256").update(subject).digest("hex")}.bin`,
      );
    this.consentStore = (subject) =>
      new SecureStore(filename(subject, "context-consent"));
    this.connectors = new ContextConnectors({
      remote,
      store: (subject) => new SecureStore(filename(subject, "connections")),
      open: options.open,
      changed: options.changed,
      revoked: (provider) => this.engine.purgeApp("connector." + provider),
    });
    this.engine = new ContextEngine({
      store: this.service,
      remote,
      changed: options.changed,
      invalidate: (ids) => {
        options.invalidate(ids);
        options.send({
          protocolVersion: PROTOCOL_VERSION,
          type: "context_invalidate",
          payload: { requestIds: ids },
        });
      },
      readEnabled: async (subject) => {
        await this.consentSerial.catch(() => {});
        const value = await this.consentStore(subject).read<{
          enabled: boolean;
          visualEnabled?: boolean;
        }>();
        if (this.subject === subject)
          this.visualEnabled = value?.visualEnabled === true;
        return value?.enabled === true;
      },
      writeEnabled: (subject, enabled) =>
        this.writeConsent(subject, { enabled }),
      readResource: (provider, resourceId, signal) =>
        this.connectors.read(provider, resourceId, signal),
    });
  }
  private writeConsent(
    subject: string,
    change: { enabled?: boolean; visualEnabled?: boolean },
  ): Promise<void> {
    const work = this.consentSerial
      .catch(() => {})
      .then(async () => {
        const store = this.consentStore(subject);
        const current = await store.read<{
          enabled?: boolean;
          visualEnabled?: boolean;
        }>();
        await store.write({
          enabled: current?.enabled === true,
          visualEnabled: current?.visualEnabled === true,
          ...change,
        });
      });
    this.consentSerial = work;
    return work;
  }
  snapshot(): ContextSnapshot & {
    visualStatus: string;
    visualEnabled: boolean;
  } {
    return {
      ...this.engine.snapshot(),
      connections: this.connectors.snapshot(),
      visualEnabled: this.visualEnabled,
      visualStatus:
        !this.engine.snapshot().enabled || !this.visualEnabled
          ? "disabled"
          : !this.options.visionVerified
            ? "unverified"
            : this.screenGranted
              ? "ready"
              : "permission_required",
    };
  }
  get enabled(): boolean {
    return this.engine.captureEnabled && !this.locked;
  }
  get imagesEnabled(): boolean {
    return this.enabled && this.visualEnabled && this.options.visionVerified;
  }
  setEnvironment(status: ProductStatus): void {
    const subject =
      status.account.state === "signed_in"
        ? (status.account.identity?.subject ?? null)
        : null;
    if (subject !== this.subject) {
      this.subject = subject;
      this.visualRevision++;
      this.visualEnabled = false;
    }
    this.engine.setEnvironment(
      subject,
      status.enabled &&
        !this.locked &&
        status.permissions.accessibility === "granted",
      [
        ...Object.entries(status.apps)
          .filter(([, allowed]) => !allowed)
          .map(([id]) => id),
        "com.autocompletion.settings",
      ],
    );
    void this.connectors.setAccount(subject).catch(() => {});
  }
  setLocked(locked: boolean, status: ProductStatus): void {
    this.locked = locked;
    this.setEnvironment(status);
    this.options.changed();
  }
  observe(message: ProtocolMessage): boolean {
    if (message.type === "context_observation") {
      const { image, ...text } = message.payload;
      void this.engine
        .observe(this.imagesEnabled ? message.payload : text)
        .catch(() => {});
      return true;
    }
    if (message.type === "context_screen_permission") {
      this.screenGranted = message.payload.granted;
      this.options.changed();
      return true;
    }
    return false;
  }
  async action(request: NativeRequest): Promise<unknown> {
    switch (request.action) {
      case "context_set_enabled":
        await this.engine.setEnabled(request.payload.enabled);
        return this.engine.refresh();
      case "context_refresh":
        return this.engine.browse("");
      case "context_history_more":
        return this.engine.moreHistory();
      case "context_history_previous":
        return this.engine.previousHistory();
      case "context_search":
        return this.engine.browse(request.payload.query);
      case "context_unpin":
        return this.engine.action("unpin", request.payload.id);
      case "context_set_visual_enabled": {
        const revision = ++this.visualRevision;
        const subject = this.subject;
        if (!subject) throw new Error("Sign in first");
        if (!request.payload.enabled) {
          this.visualEnabled = false;
          this.engine.stopVisual();
          this.options.changed();
        }
        await this.writeConsent(subject, {
          visualEnabled: request.payload.enabled,
        });
        if (this.subject === subject && this.visualRevision === revision) {
          this.visualEnabled = request.payload.enabled;
          this.options.changed();
        }
        return;
      }
      case "context_delete":
        return this.engine.action("delete", request.payload.id);
      case "context_pin":
        return this.engine.action("save", request.payload.id);
      case "context_clear":
        return this.engine.action("clear");
      case "context_add_reference":
        return this.engine.addReference(request.payload.text);
      case "context_connect":
        return this.connectors.connect(request.payload.provider);
      case "context_disconnect":
        try {
          const result = await this.connectors.disconnect(
            request.payload.provider,
          );
          if (result.requiresProviderAction && result.settingsUrl)
            await this.options.open(result.settingsUrl);
          return result;
        } finally {
          await this.engine.purgeApp("connector." + request.payload.provider);
        }
      case "context_request_screen_permission":
        this.options.send({
          protocolVersion: PROTOCOL_VERSION,
          type: "context_request_screen_permission",
          payload: null,
        });
        return;
      default:
        throw new Error("Unknown context action");
    }
  }
  dispose(): void {
    this.engine.dispose();
    this.connectors.dispose();
    this.service.stop();
  }
}
