import { expect, test } from "vitest";

import { applyHelperMessage } from "../src/main/helper-messages";
import { ProductState } from "../src/main/state";

test("applies native permission state without exposing helper messages to the renderer", () => {
  const state = new ProductState();

  applyHelperMessage(state, {
    protocolVersion: 5,
    type: "permission_state",
    payload: {
      accessibility: "granted",
      inputMonitoring: "granted",
    },
  });

  expect(state.snapshot().permissions).toEqual({
    accessibility: "granted",
    inputMonitoring: "granted",
  });
});
