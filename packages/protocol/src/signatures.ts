import { createHash } from "node:crypto";

export type SignatureInput = {
  appId: string;
  elementIdentity: string;
  selectionLocation: number;
  selectionLength: number;
  textBefore: string;
  textAfter: string;
};

export function createContentSignature(input: SignatureInput): string {
  const canonicalSnapshot = JSON.stringify([
    input.appId,
    input.elementIdentity,
    input.selectionLocation,
    input.selectionLength,
    input.textBefore,
    input.textAfter,
  ]);

  return createHash("sha256").update(canonicalSnapshot, "utf8").digest("hex");
}
