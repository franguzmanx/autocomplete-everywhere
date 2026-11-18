import { describe, expect, test } from "vitest";
import { readFile } from "node:fs/promises";

import {
  createContentSignature,
  parseProtocolMessage,
} from "../src/index";

const identity = {
  requestId: "da2f74ce-c1da-4e2e-85c7-b6d3c4069b63",
  focusSequence: 7,
  contentSignature: "0123456789abcdef0123456789abcdef",
  timestampMs: 1_788_000_000_000,
};

describe("protocol messages", () => {
  test("rejects fixed Autocomplete Everywhere shortcuts in helper configuration but allows extra modifiers", () => {
    const message = {protocolVersion:5,type:"configure",payload:{enabled:true,excludedApplications:[],
      automaticSuggestions:true,clipboardContextEnabled:false, contextEnabled:false,contextImagesEnabled:false,learningEnabled:false,quietPeriodMs:300,ghostAlpha:0.30,
      acceptShortcut:{keyCode:48,modifiers:0},dismissShortcut:{keyCode:53,modifiers:0}}};
    for (const keyCode of [48,125,126,18,19,20,21,23,22,26,28,25]) {
      for (const kind of ["acceptShortcut", "dismissShortcut"]) {
        const reserved = {...message,payload:{...message.payload,[kind]:{keyCode,modifiers:2048}}};
        expect(parseProtocolMessage(reserved)).toEqual({ok:false,code:"invalid_message"});
        const available = {...message,payload:{...message.payload,[kind]:{keyCode,modifiers:2304}}};
        expect(parseProtocolMessage(available)).toEqual(available);
      }
    }
  });

  test("carries alternatives separately from authored evidence only on explicit requests", () => {
    const message = {
      protocolVersion: 5, type: "suggestion_request", identity,
      payload: {
        appId: "test.destination", surface: "text_editor", textBefore: "Hello", textAfter: "",
        selectedText: "", explicit: true, alternativeTo: [" there.", " again. 🚀"], artifacts: [],
        fieldContext: { shape: "multiline", sources: [], relatedFields: [] },
      },
    };
    expect(parseProtocolMessage(message)).toEqual(message);
    for (const alternativeTo of [[], [" "], ["x".repeat(12_001)], Array(6).fill(" version")]) {
      expect(parseProtocolMessage({ ...message, payload: { ...message.payload, alternativeTo } }))
        .toEqual({ ok: false, code: "invalid_message" });
    }
    expect(parseProtocolMessage({ ...message, payload: { ...message.payload, explicit: false } }))
      .toEqual({ ok: false, code: "invalid_message" });
  });

  test("carries recent writing provenance while bounding combined context", () => {
    const message = {
      protocolVersion: 5, type: "suggestion_request", identity,
      payload: {
        appId: "test.destination", surface: "text_editor", textBefore: "", textAfter: "",
        selectedText: "", explicit: false,
        fieldContext: { shape: "multiline", sources: [], relatedFields: [] },
        artifacts: [
          { id: "writing-1", kind: "recent_writing", text: "Entrega el viernes.", capturedAtMs: identity.timestampMs, sourceSurface: "text_editor" },
          { id: "writing-2", kind: "accepted_completion", text: "\n明日の計画", capturedAtMs: identity.timestampMs, sourceSurface: "web_textarea" },
        ],
      },
    };
    expect(parseProtocolMessage(message)).toEqual(message);
    const oversized = { ...message, payload: { ...message.payload, artifacts: Array.from({length: 5}, (_, i) => ({
      id: `writing-${i}`, kind: "recent_writing", text: "x".repeat(4_000), capturedAtMs: identity.timestampMs,
    })) }};
    expect(parseProtocolMessage(oversized)).toEqual({ ok: false, code: "invalid_message" });
  });

  test("accepts bounded authored artifacts with provenance without altering their bytes", () => {
    const artifactText = "Hola Dana,\r\n\r\nTabla:\t€ 1.250 🚀";
    const message = {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.apple.Notes",
        surface: "text_editor",
        textBefore: "",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [
          {
            id: "clipboard-current",
            kind: "clipboard",
            text: artifactText,
            capturedAtMs: 1_788_000_000_000,
          },
        ],
        fieldContext: { shape: "multiline", sources: [], relatedFields: [] },
      },
    };

    expect(parseProtocolMessage(message)).toEqual(message);
  });

  test("rejects duplicate artifact ids because exact references must be unambiguous", () => {
    const artifact = {
      id: "same-source",
      kind: "saved",
      text: "First exact source",
      capturedAtMs: 1_788_000_000_000,
    } as const;
    const result = parseProtocolMessage({
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.apple.Notes",
        surface: "text_editor",
        textBefore: "",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [artifact, { ...artifact, text: "Second exact source" }],
        fieldContext: { shape: "multiline", sources: [], relatedFields: [] },
      },
    });

    expect(result).toEqual({ ok: false, code: "invalid_message" });
  });

  test("accepts bounded raw field context in protocol v3", () => {
    const message = {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.google.Chrome",
        surface: "web_textarea",
        textBefore: "",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "single_line",
          placeholder: "Subject",
          sources: [], relatedFields: [
            {
              shape: "multiline",
              label: "Message Body",
              text: "Hola Dana, te comparto la propuesta actualizada.",
            },
          ],
        },
      },
    };

    expect(parseProtocolMessage(message)).toEqual(message);
  });

  test("parses the canonical cross-language request fixture", async () => {
    const fixture = JSON.parse(
      await readFile(
        new URL("../fixtures/suggestion-request.json", import.meta.url),
        "utf8",
      ),
    );

    expect(parseProtocolMessage(fixture)).toEqual(fixture);
  });

  test("rejects the canonical protocol-mismatch fixture", async () => {
    const fixture = JSON.parse(
      await readFile(
        new URL("../fixtures/protocol-mismatch.json", import.meta.url),
        "utf8",
      ),
    );

    expect(parseProtocolMessage(fixture)).toEqual({
      ok: false,
      code: "protocol_version_mismatch",
    });
  });

  test.each([
    {
      protocolVersion: 5,
      type: "hello",
      payload: {
        platform: "macos",
        helperVersion: "0.1.0",
        capabilities: ["focus", "ghost_text"],
      },
    },
    {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.apple.Notes",
        surface: "text_editor",
        textBefore: "Hola Axel,",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
      },
    },
    {
      protocolVersion: 5,
      type: "permission_state",
      payload: {
        accessibility: "granted",
        inputMonitoring: "required",
      },
    },
    {
      protocolVersion: 5,
      type: "configure",
      payload: {
        enabled: true,
        excludedApplications: ["com.apple.Notes"],
        automaticSuggestions: false,
        clipboardContextEnabled: true, contextEnabled:false,contextImagesEnabled:false,
        learningEnabled: false,
        quietPeriodMs: 300,
        ghostAlpha: 0.30,
        acceptShortcut: {keyCode:48, modifiers:0},
        dismissShortcut: {keyCode:53, modifiers:0},
      },
    },
    {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.apple.TextEdit",
        surface: "text_editor",
        textBefore: "Draft",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
      },
    },
    {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.google.Chrome",
        surface: "web_textarea",
        textBefore: "Draft",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
      },
    },
    {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.apple.Safari",
        surface: "web_textarea",
        textBefore: "Draft",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
      },
    },
    {
      protocolVersion: 5,
      type: "cancel_request",
      identity,
      payload: { reason: "content_changed" },
    },
    {
      protocolVersion: 5,
      type: "suggestion_final",
      identity,
      payload: { text: " te mando el resumen hoy." },
    },
    {
      protocolVersion: 5,
      type: "request_failed",
      identity,
      payload: { code: "network", retryable: true },
    },
    {
      protocolVersion: 5,
      type: "interaction",
      identity,
      payload: { outcome: "accepted_full", acceptedCharacters: 26 },
    },
  ])("accepts a valid $type message", (message) => {
    expect(parseProtocolMessage(message)).toEqual(message);
  });

  test("rejects an unknown protocol version", () => {
    const result = parseProtocolMessage({
      protocolVersion: 1,
      type: "hello",
      payload: {
        platform: "macos",
        helperVersion: "0.1.0",
        capabilities: [],
      },
    });

    expect(result).toEqual({
      ok: false,
      code: "protocol_version_mismatch",
    });
  });

  test("rejects malformed input instead of returning a partial message", () => {
    expect(
      parseProtocolMessage({ protocolVersion: 5, type: "suggestion_request" }),
    ).toEqual({ ok: false, code: "invalid_message" });
  });

  test.each([
    { enabledApplications: ["*"] },
    { enabledApplications: [] },
    { enabledApplications: ["com.apple.TextEdit"] },
  ])(
    "rejects the retired per-application capture list (%j)",
    ({ enabledApplications }) => {
      expect(
        parseProtocolMessage({
          protocolVersion: 5,
          type: "configure",
          payload: { enabled: true, enabledApplications },
        }),
      ).toEqual({ ok: false, code: "invalid_message" });
    },
  );



  test("rejects the retired chromium_prompt surface class", () => {
    expect(
      parseProtocolMessage({
        protocolVersion: 5,
        type: "suggestion_request",
        identity,
        payload: {
          appId: "com.google.Chrome",
          surface: "chromium_prompt",
          textBefore: "Draft",
          textAfter: "",
          selectedText: "",
          explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
        },
      }),
    ).toEqual({ ok: false, code: "invalid_message" });
  });

  test.each(["unauthorized", "network", "timeout", "server"])(
    "accepts the content-free request failure code %s",
    (code) => {
      const message = {
        protocolVersion: 5,
        type: "request_failed",
        identity,
        payload: { code, retryable: code !== "unauthorized" },
      };

      expect(parseProtocolMessage(message)).toEqual(message);
    },
  );

  test("rejects request failure details that could expose content", () => {
    expect(
      parseProtocolMessage({
        protocolVersion: 5,
        type: "request_failed",
        identity,
        payload: {
          code: "network",
          retryable: true,
          detail: "failed while sending Hola Axel",
        },
      }),
    ).toEqual({ ok: false, code: "invalid_message" });
  });

  test("rejects the removed post-acceptance visual effect", () => {
    expect(
      parseProtocolMessage({
        protocolVersion: 5,
        type: "acceptance_effect",
        identity,
        payload: {
          frame: { x: 10, y: 20, width: 300, height: 40 },
          font: { name: ".AppleSystemUIFont", size: 17 },
          direction: "left_to_right",
          lines: [
            {
              text: " completion",
              frame: { x: 10, y: 20, width: 300, height: 40 },
              baselineFromTop: 20,
            },
          ],
        },
      }),
    ).toEqual({ ok: false, code: "invalid_message" });
  });

  test("rejects the obsolete pre-insertion acceptance commit command", () => {
    expect(
      parseProtocolMessage({
        protocolVersion: 5,
        type: "acceptance_commit",
        identity,
        payload: {},
      }),
    ).toEqual({ ok: false, code: "invalid_message" });
  });

  test.each([
    ["textBefore", 8_001],
    ["textAfter", 2_001],
    ["selectedText", 2_001],
  ] as const)("rejects an oversized %s field", (field, length) => {
    const message = {
      protocolVersion: 5,
      type: "suggestion_request",
      identity,
      payload: {
        appId: "com.apple.Notes",
        surface: "text_editor",
        textBefore: "",
        textAfter: "",
        selectedText: "",
        explicit: false,
        artifacts: [],
        fieldContext: {
          shape: "multiline",
          sources: [], relatedFields: [],
        },
        [field]: "x".repeat(length),
      },
    };

    expect(parseProtocolMessage(message)).toEqual({
      ok: false,
      code: "invalid_message",
    });
  });
});

test("rejects the removed suggestion_partial command", () => {
  expect(
    parseProtocolMessage({
      protocolVersion: 5,
      type: "suggestion_partial",
      identity,
      payload: { sequence: 1, text: " hello" },
    }),
  ).toEqual({ ok: false, code: "invalid_message" });
});

describe("content signature", () => {
  const snapshot = {
    appId: "com.apple.Notes",
    elementIdentity: "window-1/editor-1",
    selectionLocation: 11,
    selectionLength: 0,
    textBefore: "Hola Axel,",
    textAfter: "",
  };

  test("is deterministic and does not expose its input", () => {
    const signature = createContentSignature(snapshot);

    expect(signature).toBe(createContentSignature(snapshot));
    expect(signature).toMatch(/^[a-f0-9]{64}$/);
    expect(signature).not.toContain("Axel");
  });

  test("changes when focus or content changes", () => {
    const signature = createContentSignature(snapshot);

    expect(
      createContentSignature({ ...snapshot, elementIdentity: "window-1/editor-2" }),
    ).not.toBe(signature);
    expect(
      createContentSignature({ ...snapshot, textBefore: "Hola Ana," }),
    ).not.toBe(signature);
  });
});

test("manual invocation leaves current-field authority with the helper", () => {
  const message = {protocolVersion: 5, type: "request_suggestion", payload: null};
  expect(parseProtocolMessage(message)).toEqual(message);
  expect(parseProtocolMessage({...message, payload:{appId:"stale.application"}})).toEqual({ok:false,code:"invalid_message"});
});

test("learning messages are request-correlated and strictly bounded", () => {
  const identity = { requestId: "11111111-1111-4111-8111-111111111111", focusSequence: 1, contentSignature: "a".repeat(64), timestampMs: 1 };
  const message = { protocolVersion: 5, type: "correction_observed", identity, payload: {
    appId: "com.apple.mail", sessionId: "22222222-2222-4222-8222-222222222222", before: "Thanks very much", after: "Thanks", observedAtMs: 1,
  } };
  expect(parseProtocolMessage(message)).toEqual(message);
  for (const payload of [ {...message.payload, after: message.payload.before}, {...message.payload, before: "x".repeat(2001)}, {...message.payload, rawDocument: "must not travel"} ]) {
    expect(parseProtocolMessage({...message, payload})).toEqual({ok: false, code: "invalid_message"});
  }
  expect(parseProtocolMessage({...message, protocolVersion: 3})).toEqual({ok: false, code: "protocol_version_mismatch"});
  expect(parseProtocolMessage({protocolVersion: 5, type: "user_activity", payload: null})).toEqual({protocolVersion: 5, type: "user_activity", payload: null});
  expect(parseProtocolMessage({protocolVersion: 5, type: "user_activity", payload: {text:"private"}})).toEqual({ok: false, code: "invalid_message"});
});

test("Instant configuration transports a zero typing delay", () => {
  const message = {protocolVersion:5, type:"configure", payload:{enabled:true,
    excludedApplications:[], automaticSuggestions:true, clipboardContextEnabled:false, contextEnabled:false,contextImagesEnabled:false,
    learningEnabled:false, quietPeriodMs:0, ghostAlpha:0.3,
    acceptShortcut:{keyCode:48,modifiers:0}, dismissShortcut:{keyCode:53,modifiers:0}}};
  expect(parseProtocolMessage(message)).toEqual(message);
});
