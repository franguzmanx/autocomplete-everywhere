import { describe, it, expect } from "vitest";
import { ContextServiceClient } from "../src/main/context-service";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
function child() {
  const c = Object.assign(new EventEmitter(), {
    stdin: new PassThrough(),
    stdout: new PassThrough(),
    stderr: new PassThrough(),
    kill() {
      c.emit("exit", 1);
      return true;
    },
  });
  return c;
}
const tick = () => new Promise((resolve) => setTimeout(resolve, 0));
describe("private context service RPC", () => {
  it("correlates replies and never propagates service error contents", async () => {
    const c = child();
    const client = new ContextServiceClient({
      executable: "unused",
      root: "/tmp/test",
      spawn: () => c,
    });
    let request: any;
    c.stdin.on("data", (b) => {
      request = JSON.parse(b.toString());
    });
    const task = client.call("open", { accountId: "a" });
    await tick();
    c.stdout.write(
      JSON.stringify({ id: request.id, ok: false, error: "private text" }) +
        "\n",
    );
    await expect(task).rejects.toThrow("Context service unavailable");
    client.stop();
  });
  it("reopens the same account before reading after process death", async () => {
    let count = 0;
    let c = child();
    const calls: any[] = [];
    const reply = (process: ReturnType<typeof child>) =>
      process.stdin.on("data", (b) => {
        const request = JSON.parse(b.toString());
        calls.push(request);
        process.stdout.write(
          JSON.stringify({ id: request.id, ok: true, result: [] }) + "\n",
        );
      });
    reply(c);
    const client = new ContextServiceClient({
      executable: "unused",
      root: "/tmp/test",
      spawn: () => {
        count++;
        return c;
      },
    });
    await client.call("open", { accountId: "a" });
    c.emit("exit", 1);
    c = child();
    reply(c);
    await expect(client.call("history")).resolves.toEqual([]);
    expect(count).toBe(2);
    expect(calls.map((c) => c.op)).toEqual(["open", "open", "history"]);
    expect(calls[1].accountId).toBe("a");
    client.stop();
  });
  it("rejects writes queued for an old account before opening the next", async () => {
    const c = child(),
      calls: any[] = [];
    let finish: (() => void) | undefined;
    c.stdin.on("data", (b) => {
      const request = JSON.parse(b.toString());
      calls.push(request);
      const reply = () =>
        c.stdout.write(
          JSON.stringify({ id: request.id, ok: true, result: {} }) + "\n",
        );
      if (request.op === "history") finish = reply;
      else reply();
    });
    const client = new ContextServiceClient({
      executable: "unused",
      root: "/tmp/test",
      spawn: () => c,
    });
    await client.call("open", { accountId: "old" });
    const history = client.call("history");
    await tick();
    const staleWrite = client.call("put", {
      evidence: { text: "old private data" },
    });
    const switched = client.call("open", { accountId: "new" });
    finish!();
    await history;
    await expect(staleWrite).rejects.toThrow("Context account changed");
    await switched;
    expect(calls.some((c) => c.op === "put")).toBe(false);
    client.stop();
  });
  it("rejects cancellation without submitting queued operations", async () => {
    const c = child();
    const client = new ContextServiceClient({
      executable: "unused",
      root: "/tmp/test",
      spawn: () => c,
    });
    const controller = new AbortController();
    const p = client.call("open", { accountId: "a" }, controller.signal);
    controller.abort();
    await expect(p).rejects.toThrow();
    client.stop();
  });
});
