import { describe, expect, test } from "vitest";

import { createHelperConfiguration } from "../src/main/helper-configuration";
import { ProductState } from "../src/main/state";

describe("native helper configuration", () => {
  test("fails closed until the product and both permissions are enabled", () => {
    const state = new ProductState();
    state.setEnabled(true);

    expect(createHelperConfiguration(state.snapshot())).toEqual({
      protocolVersion: 5,
      type: "configure",
      payload: {
        enabled: false,
        excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
        clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
      },
    });
  });

  test("stays disabled without a signed-in account", () => {
    const state = new ProductState();
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });
    state.setEnabled(true);

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
      }).payload.enabled,
    ).toBe(false);
  });

  test("normal remote mode requires sign-in without a profile step", () => {
    const state = new ProductState();
    state.restore({
      signedIn: true,
      enabled: true,
      apps: {},
    });
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
      }).payload.enabled,
    ).toBe(true);
  });

  test("allows the explicit visual fixture without restored product enablement", () => {
    const state = new ProductState();
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
        fixtureModeActive: true,
      }).payload,
    ).toEqual({
      enabled: true,
      excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
    });
    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: false,
        fixtureModeActive: true,
      }).payload,
    ).toEqual({
      enabled: false,
      excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
    });
  });

  test("fixture mode never bypasses macOS permissions", () => {
    const state = new ProductState();

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
        fixtureModeActive: true,
      }).payload.enabled,
    ).toBe(false);

    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });
    state.setAppEnabled("com.apple.Notes", false);
    state.setAppEnabled("com.apple.TextEdit", false);
    state.setAppEnabled("com.apple.Safari", false);
    state.setAppEnabled("com.google.Chrome", false);

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
        fixtureModeActive: true,
      }).payload.enabled,
    ).toBe(true);
  });

  test("allows the explicit Autocomplete Everywhere engine lab without auth or context", () => {
    const state = new ProductState();
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
        engineLabModeActive: true,
      }).payload,
    ).toEqual({
      enabled: true,
      excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
    });
  });

  test("reports only content-free reasons for the effective configuration", () => {
    const state = new ProductState();
    const decisions: unknown[] = [];
    const options = {
      suggestionsAvailable: true,
      fixtureModeActive: true,
      onDecision: (decision: unknown) => decisions.push(decision),
    };

    createHelperConfiguration(state.snapshot(), options);

    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });
    createHelperConfiguration(state.snapshot(), options);

    expect(decisions).toEqual([
      {
        enabled: false,
        reasons: ["accessibility_required", "input_monitoring_required"],
      },
      { enabled: true, reasons: [] },
    ]);
  });

  test("enables every accessible writing surface after product, account, and OS consent", () => {
    const state = new ProductState();
    state.restore({
      signedIn: true,
      enabled: true,
      apps: {},
    });
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
      }),
    ).toEqual({
      protocolVersion: 5,
      type: "configure",
      payload: {
        enabled: true,
        excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
        clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
      },
    });
  });

  test("passes the explicit clipboard-context opt-in to the native helper", () => {
    const state = new ProductState();
    state.restore({
      signedIn: true,
      enabled: true,
      apps: {},
    });
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
        clipboardContextEnabled: true, contextEnabled:false,contextImagesEnabled:false,
      }).payload,
    ).toEqual({
      enabled: true,
      excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: true, contextEnabled:false,contextImagesEnabled:false,
    });
  });

  test("passes user exclusions without changing global field interpretation", () => {
    const state = new ProductState();
    state.restore({
      signedIn: true,
      enabled: true,
      apps: { "com.apple.Notes": false },
    });
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: true,
      }).payload,
    ).toEqual({
      enabled: true,
      excludedApplications: ["com.apple.Notes", "com.autocompletion.settings"],
      quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
    });
  });

  test("fails closed when no verified suggestion backend is configured", () => {
    const state = new ProductState();
    state.restore({
      signedIn: true,
      enabled: true,
      apps: {},
    });
    state.setPermissions({
      accessibility: "granted",
      inputMonitoring: "granted",
    });

    expect(createHelperConfiguration(state.snapshot()).payload).toEqual({
      enabled: false,
      excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
    });
    expect(
      createHelperConfiguration(state.snapshot(), {
        suggestionsAvailable: false,
      }).payload,
    ).toEqual({
      enabled: false,
      excludedApplications: ["com.autocompletion.settings"],
        quietPeriodMs: 300, ghostAlpha: 0.30,
        acceptShortcut:{keyCode:48,modifiers:0},
        dismissShortcut:{keyCode:53,modifiers:0},
      automaticSuggestions: true, learningEnabled: false,
      clipboardContextEnabled: false, contextEnabled:false,contextImagesEnabled:false,
    });
  });
});

test("learning capture requires both persisted consent and a currently available account learning service",()=>{
  const state=new ProductState(); state.restore({signedIn:true,enabled:true,apps:{}});
  state.setPermissions({accessibility:"granted",inputMonitoring:"granted"});
  state.update({personalization:{enabled:true,revision:1,preferences:[]}});
  expect(createHelperConfiguration(state.snapshot(),{suggestionsAvailable:true}).payload.learningEnabled).toBe(false);
  expect(createHelperConfiguration(state.snapshot(),{suggestionsAvailable:true,learningAvailable:true}).payload.learningEnabled).toBe(true);
  state.setEnabled(false);
  expect(createHelperConfiguration(state.snapshot(),{suggestionsAvailable:true,learningAvailable:true}).payload.learningEnabled).toBe(false);
});
