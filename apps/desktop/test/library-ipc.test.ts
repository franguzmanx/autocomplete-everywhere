import { TransformSettingsStore } from "../src/main/transform-settings";
import type { LearningService } from "../src/main/learning-service";
import { expect,test,vi } from "vitest";
const mocks=vi.hoisted(()=>({showOpenDialog:vi.fn()}));
vi.mock("electron",()=>({dialog:{showOpenDialog:mocks.showOpenDialog},shell:{},safeStorage:{}}));
import { createNativeActions } from "../src/main/native-actions";
import { parseNativeRequest } from "../src/main/native-settings-protocol";
import { ProductState } from "../src/main/state";
import { LocalLibrary } from "../src/main/local-library";
import type { AccountSession } from "../src/main/account-session";
import type { ProductPreferences } from "../src/main/product-preferences";

test("native library actions require active account and reject paths/provenance before file dialog",async()=>{
 const storage={read:async<T>()=>null as T|null,write:vi.fn(async()=>{})};const library=new LocalLibrary(storage,()=>{});await library.load();
 const state=new ProductState();const handle=createNativeActions({transforms:new TransformSettingsStore({read:async()=>null,write:async()=>{}},()=>{}),previewTransform:async()=>"",learning:{} as LearningService,state,account:{library} as AccountSession,preferences:{} as ProductPreferences,restartHelper:async()=>{},setShortcutRecording:async()=>{},setShortcut:async()=>{},exercise:()=>{},requestExercise:()=>{}});
 const input={title:"Style",kind:"style",text:"Use short paragraphs.",scope:{appIds:[],anchor:""},expiresAt:null};
 const req=(action:string,payload:unknown)=>parseNativeRequest(JSON.stringify({id:"a",action,payload}));
 await expect(handle(req("librarySave",input))).rejects.toThrow("Sign in");
 state.setSignedIn();state.update({libraryAvailable:true});
 expect(()=>req("librarySave",{...input,provenance:{kind:"file",name:"forged"}})).toThrow();
 const {text:_text,...metadata}=input;
 expect(()=>req("libraryImport",{...metadata,path:"/private/secret"})).toThrow();expect(mocks.showOpenDialog).not.toHaveBeenCalled();
 const saved=await handle(req("librarySave",input));expect(library.list()).toEqual([saved]);
 mocks.showOpenDialog.mockResolvedValueOnce({canceled:true,filePaths:[]});expect(await handle(req("libraryImport",metadata))).toBeNull();
 library.unload();expect(library.select({appId:"com.apple.Notes",text:"anything"})).toEqual([]);
});
