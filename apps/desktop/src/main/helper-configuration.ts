import {
  PROTOCOL_VERSION,
  type ProtocolMessage,
} from "@autocompletion/protocol";

import { TIMING_MS, GHOST_ALPHA, type ProductStatus } from "../shared/contracts";

export type HelperConfigurationDisabledReason =
  | "product_disabled"
  | "onboarding_incomplete"
  | "accessibility_required"
  | "input_monitoring_required"
  | "suggestion_source_unavailable";

export type HelperConfigurationDecision = {
  enabled: boolean;
  reasons: HelperConfigurationDisabledReason[];
};

export function createHelperConfiguration(
  status: ProductStatus,
  options: {
    suggestionsAvailable?: boolean;
    fixtureModeActive?: boolean;
    engineLabModeActive?: boolean;
    clipboardContextEnabled?: boolean;
    contextEnabled?: boolean;
    contextImagesEnabled?: boolean;
    exerciseActive?: boolean;
    learningAvailable?: boolean;
    onDecision?: (decision: HelperConfigurationDecision) => void;
  } = {},
): Extract<ProtocolMessage, { type: "configure" }> {
  const onboardingComplete = status.account.state === "signed_in";
  const suggestionsAvailable = options.suggestionsAvailable === true;
  const fixtureModeActive = options.fixtureModeActive === true;
  const engineLabModeActive = options.engineLabModeActive === true;
  const developmentModeActive = fixtureModeActive || engineLabModeActive;
  const productEnabled = status.enabled || developmentModeActive;
  const onboardingAllowed = onboardingComplete || developmentModeActive;
  const reasons: HelperConfigurationDisabledReason[] = [];
  if (!productEnabled) reasons.push("product_disabled");
  if (!onboardingAllowed) reasons.push("onboarding_incomplete");
  if (status.permissions.accessibility !== "granted") {
    reasons.push("accessibility_required");
  }
  if (status.permissions.inputMonitoring !== "granted") {
    reasons.push("input_monitoring_required");
  }
  if (!suggestionsAvailable) reasons.push("suggestion_source_unavailable");
  const enabled = reasons.length === 0;
  options.onDecision?.({ enabled, reasons });

  return {
    protocolVersion: PROTOCOL_VERSION,
    type: "configure",
    payload: {
      enabled,
      contextEnabled: enabled && options.contextEnabled === true,
      contextImagesEnabled: enabled && options.contextImagesEnabled === true,
      excludedApplications: Array.from(new Set([...Object.entries(status.apps).filter(([, allowed]) => !allowed).map(([id]) => id), ...(options.exerciseActive ? [] : ["com.autocompletion.settings"])] )).sort(),
      automaticSuggestions: status.automaticSuggestions,
      learningEnabled: enabled && status.personalization.enabled && options.learningAvailable === true,
      quietPeriodMs: TIMING_MS[status.timing],
      ghostAlpha: GHOST_ALPHA[status.visibility],
      acceptShortcut: {keyCode:status.acceptShortcut.keyCode,modifiers:status.acceptShortcut.modifiers},
      dismissShortcut: {keyCode:status.dismissShortcut.keyCode,modifiers:status.dismissShortcut.modifiers},
      clipboardContextEnabled:
        enabled && options.clipboardContextEnabled === true,
    },
  };
}
