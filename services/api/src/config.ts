export type ApiEnvironment = {
  databaseUrl?: string;
  aiDiagnostics: "off" | "full";
  clerkSecretKey: string;
  clerkPublishableKey: string;
};

export function parseApiEnvironment(
  environment: Readonly<Record<string, string | undefined>>,
): ApiEnvironment {
  const aiDiagnostics = environment.AI_DIAGNOSTICS?.trim();
  const clerkSecretKey = environment.CLERK_SECRET_KEY;
  const clerkPublishableKey = environment.CLERK_PUBLISHABLE_KEY;

  if (
    (aiDiagnostics !== "off" && aiDiagnostics !== "full") ||
    !clerkSecretKey ||
    !clerkPublishableKey
  ) {
    throw new Error("API environment is incomplete");
  }

  const databaseUrl = environment.DATABASE_URL?.trim();
  return {
    ...(databaseUrl ? { databaseUrl } : {}),
    aiDiagnostics,
    clerkSecretKey,
    clerkPublishableKey,
  };
}
