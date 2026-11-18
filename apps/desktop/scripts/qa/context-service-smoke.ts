/** Real native RPC + Keychain smoke, synthetic owned content only. */
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { createHash, randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { ContextServiceClient } from "../../src/main/context-service";
const root = await mkdtemp(join(tmpdir(), "autocompletion-context-smoke-"));
const executable =
  process.env.AUTOCOMPLETION_CONTEXT_SERVICE_PATH ??
  resolve("../../native/macos/.build/release/AutocompleteContextService");
const accounts = [`autocompletion-qa-${randomUUID()}`, `autocompletion-qa-${randomUUID()}`];
let client = new ContextServiceClient({ root, executable });
const require = (condition: unknown, label: string) => {
  if (!condition) throw new Error(label);
};
try {
  const now = Date.now();
  const text = "SYNTHETIC_CROSS_APP_CANARY_" + randomUUID();
  const evidence = {
    id: "qa-source",
    sourceId: "qa-source",
    revision: "1",
    appId: "qa.browser",
    provenance: "observed",
    capturedAtMs: now,
    expiresAtMs: now + 86400000,
    text,
    dependencies: [],
  };
  await client.call("open", { accountId: accounts[0] });
  await client.call("put", { evidence });
  const found = await client.call<any>("retrieve", { query: text });
  require(found.evidence.some(
    (e: any) => e.text === text,
  ), "cross_app_retrieval");
  await client.call("save", { evidenceId: evidence.id, saved: true });
  await client.call("clear");
  require((await client.call<any>("history", { savedOnly: true })).evidence
    .length === 1, "saved_survives_clear");
  await client.call("open", { accountId: accounts[1] });
  require((await client.call<any>("history")).evidence.length ===
    0, "account_isolation");
  client.stop();
  client = new ContextServiceClient({ root, executable });
  await client.call("open", { accountId: accounts[0] });
  require((await client.call<any>("history")).evidence.length ===
    1, "restart_persistence");
  await client.call("delete", { evidenceId: evidence.id });
  await client.call("put", { evidence });
  require((await client.call<any>("history")).evidence.length ===
    0, "deleted_revision_not_replayed");
  client.stop();
  for (const directory of await readdir(root))
    for (const name of await readdir(join(root, directory))) {
      const bytes = await readFile(join(root, directory, name));
      require(!bytes.includes(Buffer.from(text)), "ciphertext_contains_canary");
    }
  console.info(
    JSON.stringify({
      verified: true,
      checks: [
        "real_keychain",
        "real_native_rpc",
        "cross_app_retrieval",
        "account_isolation",
        "restart_persistence",
        "saved_reference",
        "deletion_tombstone",
        "encrypted_files",
      ],
    }),
  );
} finally {
  client.stop();
  await rm(root, { recursive: true, force: true });
  for (const account of accounts) {
    try {
      execFileSync(
        "/usr/bin/security",
        [
          "delete-generic-password",
          "-s",
          "com.autocompletion.context.database",
          "-a",
          createHash("sha256").update(account).digest("hex"),
        ],
        { stdio: "ignore" },
      );
    } catch {}
  }
}
