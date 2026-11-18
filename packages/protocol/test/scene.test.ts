import { describe, expect, test } from "vitest";
import { readFileSync } from "node:fs";
import { parseProtocolMessage } from "../src/index";

const fixture = JSON.parse(readFileSync(new URL("../fixtures/suggestion-request.json", import.meta.url), "utf8"));
const source = { id: "source-1", containerId: "container-1", relation: "shared_container", text: "¿Cuándo llega Jacaranda?" };
const request = (sources: unknown[]) => ({ ...fixture, payload: { ...fixture.payload, fieldContext: { ...fixture.payload.fieldContext, sources } } });

describe("scene provenance", () => {
  test("retains structural evidence without promoting it to a reply target", () => {
    const message = request([source]);
    expect(parseProtocolMessage(message)).toEqual(message);
    expect(parseProtocolMessage(request([{ ...source, relation: "reply_target" }]))).toEqual({ ok: false, code: "invalid_message" });
  });
  test("accepts fragmented conversation evidence with a shared text budget", () => {
    const fragments = Array.from({length: 24}, (_, i) => ({...source, id: `source-${i}`}));
    expect(parseProtocolMessage(request(fragments))).toEqual(request(fragments));
    expect(parseProtocolMessage(request(fragments.map(s => ({...s, text: "x".repeat(501)}))))).toEqual({ ok: false, code: "invalid_message" });
  });
  test("rejects oversized, ambiguous or duplicate source references", () => {
    for (const sources of [[{ ...source, text: "x".repeat(2001) }], [source, source], Array.from({length: 25}, (_,i) => ({ ...source, id: `source-${i}` }))]) {
      expect(parseProtocolMessage(request(sources))).toEqual({ ok: false, code: "invalid_message" });
    }
  });
  test("requires explicit source absence rather than silently accepting a missing field", () => {
    const message = request([]);
    delete message.payload.fieldContext.sources;
    expect(parseProtocolMessage(message)).toEqual({ ok: false, code: "invalid_message" });
  });
  test("can deliver a complete bounded transported artifact", () => {
    const message = { protocolVersion: 5, type: "suggestion_final", identity: fixture.identity, payload: { text: "a".repeat(4000) } };
    expect(parseProtocolMessage(message)).toEqual(message);
    expect(parseProtocolMessage({ ...message, payload: { text: "a".repeat(12001) } })).toEqual({ ok: false, code: "invalid_message" });
  });
});
