import { expect, test, vi } from "vitest";
vi.mock("electron",()=>({dialog:{},shell:{},safeStorage:{}}));
import { defaultTransformSettings } from "@autocompletion/protocol";
import { createNativeActions } from "../src/main/native-actions";
import { parseNativeRequest } from "../src/main/native-settings-protocol";
import { TransformSettingsStore } from "../src/main/transform-settings";
import { ProductState } from "../src/main/state";
import type { LearningService } from "../src/main/learning-service";
import type { ProductPreferences } from "../src/main/product-preferences";
import type { AccountSession } from "../src/main/account-session";

test("native transform changes acknowledge persistence and previews require sign-in",async()=>{
  let reject=false;
  const write=vi.fn(async()=>{if(reject)throw Error("disk");});
  const transforms=new TransformSettingsStore({read:async()=>null,write},()=>{});
  const state=new ProductState();const previewTransform=vi.fn(async()=>"Edited text");
  const handle=createNativeActions({transforms,state,previewTransform,learning:{} as LearningService,preferences:{} as ProductPreferences,account:{} as AccountSession,restartHelper:async()=>{},setShortcutRecording:async()=>{},setShortcut:async()=>{},exercise:()=>{},requestExercise:()=>{}});
  const req=(action:string,payload:unknown)=>parseNativeRequest(JSON.stringify({id:"t",action,payload}));
  expect(await handle(req("getDefaultTransforms",null))).toEqual(defaultTransformSettings());expect(write).not.toHaveBeenCalled();
  const value={...defaultTransformSettings(),enabled:false};
  expect(await handle(req("saveTransforms",value))).toEqual(value);
  reject=true;await expect(handle(req("saveTransforms",{...value,enabled:true}))).rejects.toThrow("disk");expect(transforms.get()).toEqual(value);
  const preview=req("previewTransform",{text:"Example",singleLine:false,transform:value.transforms[0]});
  await expect(handle(preview)).rejects.toThrow("Sign in");expect(previewTransform).not.toHaveBeenCalled();
  state.setSignedIn();expect(await handle(preview)).toBe("Edited text");
});
