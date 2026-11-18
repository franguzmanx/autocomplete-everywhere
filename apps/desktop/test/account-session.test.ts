import { expect,test,vi } from "vitest";
vi.mock("electron",()=>({safeStorage:{}}));
import { libraryFileForAccount } from "../src/main/account-session";
import { OAuthTokenProvider } from "../src/main/oauth-token-provider";

test("libraries belong to one account, with original data left in place",()=>{
 expect(libraryFileForAccount("/data","original","original")).toBe("/data/library.bin");
 const second=libraryFileForAccount("/data","second","original");
 expect(second).not.toBe("/data/library.bin");expect(second).not.toContain("second");
 expect(libraryFileForAccount("/data","../escape","original")).toMatch(/^\/data\/library-[a-f0-9]{64}\.bin$/);
});
test("sign-out invalidation rejects a refresh already in flight",async()=>{
 let release:(r:Response)=>void=()=>{};
 const fetchGate=new Promise<Response>(resolve=>{release=resolve;});
 const write=vi.fn(async()=>{});
 const stored={oauthClientId:"client",tokens:{accessToken:"old",refreshToken:"old-refresh",expiresAt:1,tokenType:"Bearer"}};
 const request=vi.fn(()=>fetchGate);
 const provider=new OAuthTokenProvider({clientId:"client",tokenEndpoint:"https://identity.test/token",store:{read:async()=>stored,write},request});
 const refresh=provider.getAccessToken();
 await vi.waitFor(()=>expect(request).toHaveBeenCalledOnce());
 provider.invalidate();
 release(Response.json({access_token:"new",refresh_token:"new-refresh",expires_in:60,token_type:"Bearer"}));
 await expect(refresh).rejects.toThrow("unauthorized");expect(write).not.toHaveBeenCalled();
});

test("identity restoration leaves the deferred Library disabled", async () => {
 const {AccountSession}=await import("../src/main/account-session");
 const {ProductState}=await import("../src/main/state");
 const state=new ProductState();
 let stored:Record<string,unknown>={oauthClientId:"client",oauthSessionId:"session",tokens:{accessToken:"test-token",refreshToken:"test-refresh",expiresAt:Date.now()+3600000,tokenType:"Bearer"}};
 const session=new AccountSession({state,root:"/unused-library",store:{read:async()=>stored,write:async(value:Record<string,unknown>)=>{stored=value;}} as never,
 config:{clientId:"client",userinfoEndpoint:"https://identity.test/user",tokenEndpoint:"https://identity.test/token"} as never,
 openExternal:async()=>{},invalidate:()=>{},changed:()=>{},request:vi.fn(async()=>Response.json({sub:"test-account"}))});
 await session.initialize();
 expect(state.snapshot().account.state).toBe("signed_in");
 expect(state.snapshot().account.identity?.subject).toBe("test-account");
 expect(state.snapshot().connection).toBe("ready");
 expect(state.snapshot().libraryAvailable).toBe(false);
 expect(session.library).toBeNull();
 session.dispose();
});
