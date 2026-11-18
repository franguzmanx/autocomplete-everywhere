export type DesktopRuntimeConfig = {
  apiUrl: string;
  authorizationEndpoint: string;
  tokenEndpoint: string;
  clientId: string;
  redirectUri: string;
  userinfoEndpoint: string;
  revocationEndpoint: string;
  manageAccountUrl: string;
};

type Environment = Readonly<Record<string, string | undefined>>;

const DEFAULT_REDIRECT_URI = "http://127.0.0.1:43119/callback";

// The project ships without a hosted backend. Every deployment supplies its
// own API and identity provider through these variables.
const REQUIRED_VARIABLES = {
  apiUrl: "AUTOCOMPLETION_API_URL",
  authorizationEndpoint: "AUTOCOMPLETION_CLERK_AUTHORIZATION_URL",
  tokenEndpoint: "AUTOCOMPLETION_CLERK_TOKEN_URL",
  clientId: "AUTOCOMPLETION_CLERK_CLIENT_ID",
  userinfoEndpoint: "AUTOCOMPLETION_CLERK_USERINFO_URL",
  revocationEndpoint: "AUTOCOMPLETION_CLERK_REVOCATION_URL",
  manageAccountUrl: "AUTOCOMPLETION_ACCOUNT_URL",
} as const satisfies Partial<Record<keyof DesktopRuntimeConfig, string>>;

export const RUNTIME_CONFIG_VARIABLES: readonly string[] = [
  ...Object.values(REQUIRED_VARIABLES),
  "AUTOCOMPLETION_CLERK_REDIRECT_URI",
];

export class MissingRuntimeConfigError extends Error {
  constructor(readonly missing: readonly string[]) {
    super(`Backend is not configured. Set ${missing.join(", ")}.`);
    this.name = "MissingRuntimeConfigError";
  }
}

/**
 * Runtime environment wins over values baked in at build time, so a packaged
 * app keeps the backend it was built for and a shell can still override it.
 */
export function resolveDesktopRuntimeConfig(
  environment: Environment,
  buildDefaults: Environment = {},
): DesktopRuntimeConfig {
  const read = (name: string): string | undefined =>
    environment[name] || buildDefaults[name] || undefined;
  const missing = Object.values(REQUIRED_VARIABLES).filter(name => !read(name));
  if (missing.length > 0) throw new MissingRuntimeConfigError(missing);
  const required = (key: keyof typeof REQUIRED_VARIABLES): string =>
    read(REQUIRED_VARIABLES[key]) as string;
  return {
    apiUrl: required("apiUrl"),
    authorizationEndpoint: required("authorizationEndpoint"),
    tokenEndpoint: required("tokenEndpoint"),
    clientId: required("clientId"),
    redirectUri: read("AUTOCOMPLETION_CLERK_REDIRECT_URI") ?? DEFAULT_REDIRECT_URI,
    userinfoEndpoint: required("userinfoEndpoint"),
    revocationEndpoint: required("revocationEndpoint"),
    manageAccountUrl: required("manageAccountUrl"),
  };
}
