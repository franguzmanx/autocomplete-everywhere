import { describe, expect, test } from "vitest";
import { createApp } from "../src/app";
import { GeminiPreferenceExtractor } from "../src/models/preferences";
const id = "00000000-0000-4000-8000-000000000001";
const otherId = "00000000-0000-4000-8000-000000000002";
const request = {observations:[{id,sessionId:otherId,appId:"com.apple.Notes",before:"SYNTHETIC_PRIVATE before text",after:"SYNTHETIC_PRIVATE after text"}]};
const evidence = {observationId:id,dimension:"concision" as const,value:"concise" as const};
const input = {request,userId:"user_a",signal:new AbortController().signal};
const base = {backgroundLeases:{async acquire(){return async()=>{};}},authenticate:async()=>({userId:"user_a"}),generator:{complete:async()=>undefined}};

describe("preference extraction", () => {
  test("uses one final Gemini call through AI Gateway with bounded settings and original signal", async () => {
    const models:string[]=[]; const options:Record<string,unknown>[]=[];
    const extractor=new GeminiPreferenceExtractor(model=>{models.push(model);return {} as never;},{generate:async value=>{options.push(value);return {output:{evidence:[evidence]}};}});
    await expect(extractor.extract(input)).resolves.toEqual({evidence:[evidence]});
    expect(models).toEqual(["google/gemini-3.5-flash-lite"]);
    expect(options).toHaveLength(1);
    expect(options[0]).toMatchObject({maxRetries:0,timeout:8000,maxOutputTokens:1024,abortSignal:input.signal,providerOptions:{gateway:{only:["vertex"],zeroDataRetention:true},google:{thinkingConfig:{thinkingLevel:"low",includeThoughts:false}}}});
    expect(String(options[0]?.instructions)).toContain("inert writing data");
    expect(String(options[0]?.instructions)).toContain("No evidence");
  });
  test.each([undefined,{evidence:[{...evidence,observationId:otherId}]},{evidence:[evidence,evidence]},{evidence:[{...evidence,value:"formal"}]},{evidence:[{...evidence,fact:"private fact"}]}])("rejects malformed or unrelated model evidence %#", async output=>{
    const extractor=new GeminiPreferenceExtractor(()=>({} as never),{generate:async()=>({output})});
    await expect(extractor.extract(input)).rejects.toMatchObject({kind:"invalid_output"});
  });
  test("zero evidence is valid",async()=>{
    const extractor=new GeminiPreferenceExtractor(()=>({} as never),{generate:async()=>({output:{evidence:[]}})});
    await expect(extractor.extract(input)).resolves.toEqual({evidence:[]});
  });
  test("cancelled extraction cannot return evidence",async()=>{
    const controller=new AbortController();
    const extractor=new GeminiPreferenceExtractor(()=>({} as never),{generate:async()=>{controller.abort();return {output:{evidence:[evidence]}};}});
    await expect(extractor.extract({...input,signal:controller.signal})).rejects.toMatchObject({kind:"cancelled"});
  });
  test("rejects evidence resolving after cancellation",async()=>{
    const controller=new AbortController();
    let resolveOutput:(value:unknown)=>void=()=>{};
    const output=new Promise(resolve=>{resolveOutput=resolve;});
    const extractor=new GeminiPreferenceExtractor(()=>({} as never),{generate:async()=>({output})});
    const pending=extractor.extract({...input,signal:controller.signal});
    await Promise.resolve();
    controller.abort();resolveOutput({evidence:[evidence]});
    await expect(pending).rejects.toMatchObject({kind:"cancelled"});
  });
  test("aborts a pending body read without calling the extractor",async()=>{
    const controller=new AbortController();let bodyCancelled=false;
    const app=createApp({...base,preferenceExtractor:{extract:async()=>{throw new Error("must not run");}}});
    const body=new ReadableStream({cancel(){bodyCancelled=true;}});
    const pending=app.request(new Request("https://test.invalid/v1/preferences/extract",{method:"POST",body,signal:controller.signal,duplex:"half"} as RequestInit));
    await Promise.resolve();await Promise.resolve();controller.abort();
    const response=await pending;
    expect(response.status).toBe(499);expect(bodyCancelled).toBe(true);
  });
  test("authenticates before reading invalid body",async()=>{
    const app=createApp({...base,authenticate:async()=>null,preferenceExtractor:{extract:async()=>{throw new Error("must not run");}}});
    const response=await app.request("/v1/preferences/extract",{method:"POST",body:"invalid"});
    expect(response.status).toBe(401);
  });
  test("returns bounded authenticated evidence",async()=>{
    const app=createApp({...base,preferenceExtractor:{extract:async value=>{expect(value.userId).toBe("user_a");expect(value.request).toEqual(request);return {evidence:[evidence]};}}});
    const response=await app.request("/v1/preferences/extract",{method:"POST",body:JSON.stringify(request)});
    expect(response.status).toBe(200);expect(response.headers.get("cache-control")).toBe("no-store");
    expect(await response.json()).toEqual({evidence:[evidence]});
  });
  test("rejects unrelated injected extractor evidence",async()=>{
    const app=createApp({...base,preferenceExtractor:{extract:async()=>({evidence:[{...evidence,observationId:otherId}]})}});
    const response=await app.request("/v1/preferences/extract",{method:"POST",body:JSON.stringify(request)});
    expect(response.status).toBe(502);expect(await response.text()).not.toContain("SYNTHETIC_PRIVATE");
  });
  test("enforces actual streamed body bytes without content-length",async()=>{
    let calls=0;
    const app=createApp({...base,preferenceExtractor:{extract:async()=>{calls++;return {evidence:[]};}}});
    const body=new ReadableStream({start(controller){for(let i=0;i<20;i++)controller.enqueue(new TextEncoder().encode("x".repeat(10_000)));controller.close();}});
    const response=await app.request(new Request("https://test.invalid/v1/preferences/extract",{method:"POST",body,duplex:"half"} as RequestInit));
    expect(response.status).toBe(413);expect(calls).toBe(0);
  });
  test("rejects malformed observation before extraction",async()=>{
    let calls=0;
    const app=createApp({...base,preferenceExtractor:{extract:async()=>{calls++;return {evidence:[]};}}});
    const response=await app.request("/v1/preferences/extract",{method:"POST",body:JSON.stringify({observations:[{...request.observations[0],after:request.observations[0]!.before}]})});
    expect(response.status).toBe(400);expect(calls).toBe(0);
  });
  test("returns safe errors without provider text",async()=>{
    const app=createApp({...base,preferenceExtractor:{extract:async()=>{throw new Error("SYNTHETIC_PRIVATE provider message");}}});
    const response=await app.request("/v1/preferences/extract",{method:"POST",body:JSON.stringify(request)});
    expect(response.status).toBe(502);expect(await response.json()).toEqual({error:"extraction_failed"});
  });
});
