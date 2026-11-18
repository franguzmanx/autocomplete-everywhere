import { createHash, randomUUID } from "node:crypto";
import { join } from "node:path";
import { z } from "zod";
import { beginDesktopSignIn, type OAuthTokens } from "./auth";
import { OAuthTokenProvider, hasCurrentOAuthSession, type StoredProductData } from "./oauth-token-provider";
import type { DesktopRuntimeConfig } from "./runtime-config";
import type { ProductState } from "./state";
import { SecureStore } from "./secure-store";
import { LocalLibrary } from "./local-library";
import type { AccountIdentity } from "../shared/contracts";

export function libraryFileForAccount(root:string, subject:string, originalOwner:string|undefined):string {
  return join(root, originalOwner===subject?"library.bin":`library-${createHash("sha256").update(subject).digest("hex")}.bin`);
}
const identitySchema=z.object({sub:z.string().min(1).max(256),name:z.string().max(256).optional(),email:z.string().max(320).optional()});
type Options={store:SecureStore;root:string;state:ProductState;config:DesktopRuntimeConfig;openExternal(url:string):Promise<void>;invalidate():void;changed():void;request?:typeof fetch};

/** What the product needs from an account, hosted or local. */
export interface Account {
  readonly tokenProvider:{getAccessToken(forceRefresh?:boolean):Promise<string>};
  readonly library:LocalLibrary|null;
  initialize():Promise<void>;
  restoreIdentity():Promise<void>;
  beginSignIn():Promise<void>;
  setApiKey(value:string):Promise<void>;
  expire():void;
  signOut():Promise<void>;
  openManageAccount():Promise<void>;
  dispose():void;
}

/** Owns credential transitions and account-scoped library lifetime in one place. */
export class AccountSession implements Account {
  readonly tokenProvider:OAuthTokenProvider;
  library:LocalLibrary|null=null;
  private epoch=0;
  private queue:Promise<unknown>=Promise.resolve();
  private signingIn:Promise<void>|null=null;
  private readonly request:typeof fetch;
  constructor(private readonly options:Options){
    this.request=options.request??fetch;
    this.tokenProvider=new OAuthTokenProvider({
      store:{read:()=>options.store.read<StoredProductData>(),write:value=>this.update(current=>{
        if(!value.tokens || !current.oauthSessionId || current.oauthSessionId!==value.oauthSessionId)throw new Error("unauthorized");
        return {...current,tokens:value.tokens};
      })}, tokenEndpoint:options.config.tokenEndpoint,clientId:options.config.clientId,
      ...(options.request?{request:options.request}:{}),
    });
  }
  private update(change:(current:StoredProductData)=>StoredProductData):Promise<void>{
    const next=this.queue.then(async()=>{const current=await this.options.store.read<StoredProductData>()??{};await this.options.store.write(change(current));});
    this.queue=next.catch(()=>{});return next;
  }
  private unload():void{
    this.options.invalidate();this.library?.unload();this.library=null;
    this.options.state.update({libraryAvailable:false,exercise:"idle"});this.options.changed();
  }
  async initialize():Promise<void>{
    const stored=await this.options.store.read<StoredProductData>();
    if(!hasCurrentOAuthSession(stored,this.options.config.clientId))return;
    if(!stored?.oauthSessionId)await this.update(c=>({...c,oauthSessionId:randomUUID()}));
    this.options.state.update({account:{state:"signed_in",identity:stored?.identity??null}});
    await this.restoreIdentity(true);
  }
  async restoreIdentity(claimOriginal=false):Promise<void>{
    const generation=this.epoch;
    try {
      const token=await this.tokenProvider.getAccessToken();
      const response=await this.request(this.options.config.userinfoEndpoint,{headers:{authorization:`Bearer ${token}`},signal:AbortSignal.timeout(10_000)});
      if(!response.ok){if(response.status===401||response.status===403){if(generation===this.epoch)this.expire();return;}throw new Error("Identity unavailable");}
      const info=identitySchema.parse(await response.json());
      if(generation!==this.epoch)return;
      const identity:AccountIdentity={subject:info.sub,name:info.name??"",email:info.email??""};
      await this.update(c=>{
        if(generation!==this.epoch)throw new Error("Session changed");
        return {...c,identity,...(claimOriginal&&!c.libraryOwnerSubject?{libraryOwnerSubject:identity.subject}:{})};
      });
      if(generation!==this.epoch)return;
      // Library is deferred from this MVP. Do not open or retrieve its saved data.
      this.library?.unload();this.library=null;
      this.options.state.update({account:{state:"signed_in",identity},libraryAvailable:false,connection:"ready"});
      this.options.changed();
    }catch(error){
      if(generation!==this.epoch)return;
      if(error instanceof Error && (error.message==="unauthorized" || /OAuth token refresh failed with status (400|401|403)/.test(error.message)))this.expire();
      else this.options.state.update({connection:"offline"});
    }
  }
  beginSignIn():Promise<void>{
    if(this.signingIn)return this.signingIn;
    const generation=++this.epoch;
    this.unload();this.tokenProvider.invalidate();
    this.options.state.update({account:{state:"signed_out",identity:null}});
    this.signingIn=beginDesktopSignIn({...this.options.config,scopes:["openid","profile","email","offline_access"]},{
      openExternal:this.options.openExternal,
      storeTokens:async(tokens:OAuthTokens)=>{
        if(generation!==this.epoch)throw new Error("Sign-in cancelled");
        await this.update(c=>{if(generation!==this.epoch)throw new Error("Sign-in cancelled");return {...c,oauthClientId:this.options.config.clientId,oauthSessionId:randomUUID(),tokens,identity:undefined};});
        this.tokenProvider.invalidate();
      },
    }).then(async()=>{
      if(generation!==this.epoch)return;
      this.options.state.update({account:{state:"signed_in",identity:null}});
      await this.restoreIdentity();
    }).finally(()=>{this.signingIn=null;});
    return this.signingIn;
  }
  expire():void{
    this.epoch++;this.tokenProvider.invalidate();
    this.options.state.update({account:{...this.options.state.snapshot().account,state:"expired"}});
    this.unload();
  }
  async signOut():Promise<void>{
    this.epoch++;this.tokenProvider.invalidate();
    this.options.state.update({account:{state:"signed_out",identity:null},connection:"ready"});
    this.unload();
    const previous=await this.options.store.read<StoredProductData>();
    await this.update(c=>{
      const {tokens:_tokens,identity:_identity,oauthClientId:_client,oauthSessionId:_session,...remaining}=c;
      return remaining;
    });
    // Local sign-out is immediate. Revocation is best effort; no network failure restores credentials.
    if(previous?.tokens?.refreshToken)void this.request(this.options.config.revocationEndpoint,{
      method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},
      body:new URLSearchParams({token:previous.tokens.refreshToken,token_type_hint:"refresh_token",client_id:this.options.config.clientId}),signal:AbortSignal.timeout(5_000),
    }).then(r=>r.body?.cancel()).catch(()=>{});
  }
  async openManageAccount():Promise<void>{await this.options.openExternal(this.options.config.manageAccountUrl);}
  async setApiKey():Promise<void>{throw new Error("This build signs in with an account.");}
  dispose():void{this.epoch++;this.tokenProvider.invalidate();this.library?.unload();this.library=null;}
}
