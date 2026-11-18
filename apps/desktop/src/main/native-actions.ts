import { defaultTransformSettings, type TransformInput } from "@autocompletion/protocol";
import type { TransformSettingsStore } from "./transform-settings";
import type { LearningService } from "./learning-service";
import type { SuggestionKeyBinding } from "../shared/contracts";
import { dialog, shell } from "electron";
import type { NativeRequest } from "./native-settings-protocol";
import type { ProductState } from "./state";
import type { ProductPreferences } from "./product-preferences";
import type { AccountSession } from "./account-session";
import { readLibraryImport } from "./library-import";

type Options={transforms:TransformSettingsStore;previewTransform(input:TransformInput):Promise<string>;learning:LearningService;state:ProductState;preferences:ProductPreferences;account:AccountSession;restartHelper():Promise<void>;setShortcutRecording(active:boolean):Promise<void>;setShortcut(value:SuggestionKeyBinding | null):Promise<void>;exercise(active:boolean):void;requestExercise():void};
export function createNativeActions(options:Options):(request:NativeRequest)=>Promise<unknown>{
  return async request=>{
    const {preferences,account}=options;
    switch(request.action){
      case "ready":return null;
      case "getDefaultTransforms":return defaultTransformSettings();
      case "saveTransforms":await options.transforms.save(request.payload);return options.transforms.get();
      case "previewTransform":{
        if(options.state.snapshot().account.state!=="signed_in")throw new Error("Sign in first");
        return options.previewTransform(request.payload);
      }
      case "resume":return preferences.resume();
      case "pause":return preferences.pause(request.payload);
      case "saveWriting":{
        const {personalization,...writing}=request.payload;
        return {personalization:await options.learning.save(personalization,()=>preferences.saveWriting(writing))};
      }
      case "setUiLanguage":return preferences.setUiLanguage(request.payload);
      case "setInteractionShortcut":return options.preferences.setInteractionShortcut(request.payload.action, request.payload.shortcut);
      case "setShortcutRecording":return options.setShortcutRecording(request.payload);
      case "setShortcut":return options.setShortcut(request.payload);
      case "setAppEnabled":return preferences.setAppEnabled(request.payload.appId,request.payload.enabled);
      case "beginSignIn":return account.beginSignIn();
      case "signOut":return account.signOut();
      case "openManageAccount":{
        if(options.state.snapshot().account.state!=="signed_in")throw new Error("Sign in first");
        return account.openManageAccount();
      }
      case "restartHelper":await options.restartHelper();if(options.state.snapshot().account.state==="signed_in")await account.restoreIdentity();return;
      case "setExerciseActive":return options.exercise(request.payload);
      case "requestExerciseSuggestion":return options.requestExercise();
      case "openMacPermissionSettings":return shell.openExternal(`x-apple.systempreferences:com.apple.preference.security?${request.payload==="accessibility"?"Privacy_Accessibility":"Privacy_ListenEvent"}`);
      case "librarySave":case "libraryDelete":case "libraryImport":{
        const state=options.state.snapshot();const library=account.library;
        if(state.account.state!=="signed_in"||!state.libraryAvailable||!library)throw new Error("Sign in to open your library");
        if(request.action==="librarySave")return library.upsert(request.payload);
        if(request.action==="libraryDelete")return library.delete(request.payload.id,request.payload.revision);
        const picker=await dialog.showOpenDialog({title:state.uiLanguage==="es"?"Añadir a la biblioteca":"Add to Library",properties:["openFile"],filters:[{name:"Text / Markdown",extensions:["txt","md"]}]});
        if(picker.canceled||picker.filePaths.length!==1)return null;
        if(account.library!==library)throw new Error("Account changed");
        const source=await readLibraryImport(picker.filePaths[0]!);
        if(account.library!==library)throw new Error("Account changed");
        return library.upsert({...request.payload,text:source.text},{kind:"file",name:source.name});
      }
    }
  };
}
