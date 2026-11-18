import { exchangeRefreshToken, type OAuthTokens } from "./auth";

import type { AccountIdentity } from "../shared/contracts";

export type StoredProductData = {
  oauthSessionId?: string | undefined;
  identity?: AccountIdentity | undefined;
  libraryOwnerSubject?: string | undefined;
  oauthClientId?: string;
  tokens?: OAuthTokens;
  enabled?: boolean;
};

export function hasCurrentOAuthSession(
  stored: StoredProductData | null,
  clientId: string,
): boolean {
  return (
    stored?.oauthClientId === clientId &&
    typeof stored.tokens?.refreshToken === "string"
  );
}

export type ProductDataStore = {
  read(): Promise<StoredProductData | null>;
  write(value: StoredProductData): Promise<void>;
};

type OAuthTokenProviderOptions = {
  store: ProductDataStore;
  tokenEndpoint: string;
  clientId: string;
  now?: () => number;
  refreshSkewMs?: number;
  request?: typeof fetch;
};

export class OAuthTokenProvider {
  private epoch = 0;
  invalidate(): void { this.epoch++; this.cachedTokens=null; this.loadInFlight=null; this.refreshInFlight=null; }
  private cachedTokens: OAuthTokens | null = null;
  private loadInFlight: Promise<OAuthTokens> | null = null;
  private refreshInFlight: Promise<string> | null = null;

  constructor(private readonly options: OAuthTokenProviderOptions) {}

  async getAccessToken(forceRefresh = false): Promise<string> {
    const tokens = await this.getTokens();

    const now = (this.options.now ?? Date.now)();
    const skew = this.options.refreshSkewMs ?? 30_000;
    if (!forceRefresh && tokens.expiresAt - now > skew) {
      return tokens.accessToken;
    }

    this.refreshInFlight ??= this.refresh(tokens).finally(() => {
      this.refreshInFlight = null;
    });
    return this.refreshInFlight;
  }

  private async getTokens(): Promise<OAuthTokens> {
    if (this.cachedTokens) return this.cachedTokens;

    this.loadInFlight ??= this.loadTokens().finally(() => {
      this.loadInFlight = null;
    });
    return this.loadInFlight;
  }

  private async loadTokens(): Promise<OAuthTokens> {
    const epoch=this.epoch;
    const stored = await this.options.store.read();
    if (!hasCurrentOAuthSession(stored, this.options.clientId)) {
      throw new Error("unauthorized");
    }
    const tokens = stored?.tokens;
    if (!tokens) throw new Error("unauthorized");

    if(epoch!==this.epoch)throw new Error("unauthorized");
    this.cachedTokens = tokens;
    return tokens;
  }

  private async refresh(tokens: OAuthTokens): Promise<string> {
    const epoch=this.epoch;
    const renewed = await exchangeRefreshToken(
      {
        tokenEndpoint: this.options.tokenEndpoint,
        clientId: this.options.clientId,
        refreshToken: tokens.refreshToken,
        ...(this.options.now ? { now: this.options.now } : {}),
      },
      this.options.request,
    );

    if(epoch!==this.epoch)throw new Error("unauthorized");
    const current = await this.options.store.read();
    if (
      !hasCurrentOAuthSession(current, this.options.clientId) ||
      current?.tokens?.refreshToken !== tokens.refreshToken
    ) {
      this.cachedTokens = null;
      throw new Error("unauthorized");
    }

    await this.options.store.write({ ...current, tokens: renewed });
    if(epoch!==this.epoch)throw new Error("unauthorized");
    this.cachedTokens = renewed;
    return renewed.accessToken;
  }
}
