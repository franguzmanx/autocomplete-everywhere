import { expect, it, vi } from "vitest";
import { LearningTransport } from "../src/main/learning-transport";
const id = "00000000-0000-4000-8000-000000000001";
const input = { observations: [{ id, sessionId: id, appId: "com.example.Editor", before: "Rather long", after: "Short" }] };
it("uses the canonical authenticated endpoint once and validates observation attribution", async () => {
  const request = vi.fn(async (_url: URL | RequestInfo, _init?: RequestInit) => Response.json({ evidence: [{ observationId: id, dimension: "structure", value: "lists" }] }));
  const transport = new LearningTransport({ apiUrl: "https://api.example.com", tokenProvider: { getAccessToken: async () => "test-token" }, request });
  await expect(transport.extract(input, new AbortController().signal)).resolves.toMatchObject({ evidence: [{ observationId: id }] });
  expect(request).toHaveBeenCalledTimes(1);
  expect(String(request.mock.calls[0]![0])).toBe("https://api.example.com/v1/preferences/extract");
  expect(request.mock.calls[0]![1]).toMatchObject({ method: "POST", headers: { authorization: "Bearer test-token" } });
  const bad = new LearningTransport({ apiUrl: "https://api.example.com", tokenProvider: { getAccessToken: async () => "test-token" }, request: async () => Response.json({ evidence: [{ observationId: "00000000-0000-4000-8000-000000000002", dimension: "structure", value: "lists" }] }) });
  await expect(bad.extract(input, new AbortController().signal)).rejects.toThrow("invalid");
});
it("does not retry unauthorized extraction or send after cancellation during token lookup", async () => {
  const request = vi.fn(async () => new Response("unauthorized", { status: 401 }));
  const transport = new LearningTransport({ apiUrl: "https://api.example.com", tokenProvider: { getAccessToken: async () => "test-token" }, request });
  await expect(transport.extract(input, new AbortController().signal)).rejects.toThrow("unavailable"); expect(request).toHaveBeenCalledTimes(1);
  const controller = new AbortController(); let resolve!: (token: string) => void;
  const delayed = new LearningTransport({ apiUrl: "https://api.example.com", tokenProvider: { getAccessToken: () => new Promise(r => { resolve = r; }) }, request });
  const promise = delayed.extract(input, controller.signal); controller.abort(); resolve("test-token");
  await expect(promise).rejects.toThrow(); expect(request).toHaveBeenCalledTimes(1);
});
it("bounds response bytes and rejects non-JSON or malformed traits", async () => {
  for (const response of [new Response("x".repeat(16_385), { headers: { "content-type": "application/json" } }), Response.json({ evidence: [{ observationId: id, dimension: "name", value: "Someone" }] }), new Response("nothing")]) {
    const transport = new LearningTransport({ apiUrl: "https://api.example.com", tokenProvider: { getAccessToken: async () => "test-token" }, request: async () => response });
    await expect(transport.extract(input, new AbortController().signal)).rejects.toThrow();
  }
});
it("settles cancellation and timeout while shared token refresh never resolves", async () => {
  for (const timeout of [false,true]) {
    const cancellation = new AbortController(), deadline = new AbortController();
    const timeoutSpy = vi.spyOn(AbortSignal,"timeout").mockReturnValue(deadline.signal);
    try {
      const request=vi.fn();
      const transport=new LearningTransport({apiUrl:"https://api.example.com",tokenProvider:{getAccessToken:()=>new Promise<string>(()=>{})},request});
      const promise=transport.extract(input,cancellation.signal);
      (timeout?deadline:cancellation).abort(new Error(timeout?"deadline":"cancelled"));
      await expect(promise).rejects.toThrow(timeout?"deadline":"cancelled");
      expect(request).not.toHaveBeenCalled();
    }finally{timeoutSpy.mockRestore();}
  }
});
