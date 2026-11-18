import type { ProtocolMessage } from "@autocompletion/protocol";

import { ProductState } from "./state";

export function applyHelperMessage(
  state: ProductState,
  message: ProtocolMessage,
): void {
  if (message.type === "permission_state") {
    state.setPermissions(message.payload);
  } else if (message.type === "application_state") {
    state.setApplications(message.payload.applications, message.payload.currentApplication);
  }
}
