export function classifyDatabaseCode(value: unknown): string {
  return typeof value === "string" && /^[A-Z0-9_]{1,32}$/.test(value)
    ? value
    : "UNKNOWN";
}

/// Reduces a driver or Postgres error to a content-free reason class.
export function classifyDatabaseReason(value: unknown): string {
  if (typeof value !== "string") return "rejected";
  const message = value.toLowerCase();
  if (message.includes("expired")) return "expired";
  if (message.includes("role") && message.includes("claim")) {
    return "missing_role_claim";
  }
  if (message.includes("issuer")) return "issuer_rejected";
  if (message.includes("audience")) return "audience_rejected";
  if (message.includes("signature") || message.includes("suitable key")) {
    return "signature_rejected";
  }
  if (message.includes("jwt")) return "jwt_rejected";
  return "rejected";
}

export function requireSubject(subject: string): string | null {
  const normalized = subject.trim();
  return !normalized || normalized.length > 512 ? null : normalized;
}
