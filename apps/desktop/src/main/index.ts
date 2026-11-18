import { ContextController } from "./context-controller";
import { TransformCoordinator } from "./transforms";
import { TransformSettingsStore } from "./transform-settings";
import { SuggestionActivity } from "./suggestion-activity";
import { SuggestionOutcomeUploader } from "./suggestion-outcome-uploader";
import { LearningService, learningFileForAccount } from "./learning-service";
import { LearningTransport } from "./learning-transport";
import { SuggestionShortcut } from "./suggestion-shortcut";
import { join } from "node:path";
import { app, globalShortcut, powerMonitor, dialog, shell } from "electron";
import { HelperProcessManager, resolvePackagedHelperPath } from "./helper-process";
import { createHelperConfiguration } from "./helper-configuration";
import { applyHelperMessage } from "./helper-messages";
import { createFixtureDiagnostics } from "./fixture-diagnostics";
import { PipelineTraceWriter } from "./pipeline-trace";
import { SecureStore } from "./secure-store";
import { MissingRuntimeConfigError, resolveBackend } from "./runtime-config";
import { RuntimeDiagnostics } from "./runtime-diagnostics";
import { claimSingleInstance } from "./single-instance";
import { ProductState } from "./state";
import { ReservedShortcutPreferencesError, ProductPreferences } from "./product-preferences";
import { PROTOCOL_VERSION } from "@autocompletion/protocol";
import { createSuggestionBootstrap } from "./suggestion-bootstrap";
import { HttpSuggestionTransport } from "./suggestion-transport";
import { createProductTray } from "./tray";
import { ContextualSuggestionSource } from "./contextual-suggestion-source";
import { AccountSession, type Account } from "./account-session";
import { LocalAccount, LOCAL_API_ORIGIN } from "./local-account";
import { NativeSettings } from "./native-settings";
import { createNativeActions } from "./native-actions";

let contextController:ContextController|null=null;
let transformCoordinator:TransformCoordinator|null=null;
let outcomeUploader:SuggestionOutcomeUploader|null=null;
let settings:NativeSettings|null=null;
let helperManager:HelperProcessManager|null=null;
let coordinator:ReturnType<typeof createSuggestionBootstrap>=null;
let preferences:ProductPreferences|null=null;
let account:Account|null=null;
let learning:LearningService|null=null;
let disposeTray:(()=>void)|undefined;
let unsubscribe:(()=>void)|undefined;
const state=new ProductState();
const fixtureDiagnostics=createFixtureDiagnostics(process.env);

// Electron's name selects the user data folder and the OS encryption identity.
// It is set before the single-instance lock, which lives in that folder.
// Changing this name disconnects saved credentials.
app.setName("Autocomplete Everywhere");

function startPrimaryInstance():void{
  app.enableSandbox();
  void app.whenReady().then(async()=>{
    app.dock?.hide();
    const root=app.getPath("userData");
    const secureStore=new SecureStore(join(root,"secure","product-state.bin"));
    const runtime=new RuntimeDiagnostics(join(root,"runtime-status.json"));
    const trace=new PipelineTraceWriter(join(root,"pipeline-trace.ndjson"));
    const backend=resolveBackend(process.env,__AUTOCOMPLETION_BUILD_CONFIG__);
    const controls=new ProductPreferences(join(root,"preferences.json"),state);preferences=controls;
    try { await controls.load(); }
    catch (error) {
      if (!(error instanceof ReservedShortcutPreferencesError)) throw error;
      const choice = await dialog.showMessageBox({
        type:"warning", title:"Autocomplete Everywhere", message:"Saved shortcuts overlap reserved Autocomplete Everywhere actions.",
        detail:"Reset request, accept and dismiss shortcuts to their defaults to continue. Your app exclusions and other preferences will be preserved.",
        buttons:["Reset shortcuts", "Quit"], defaultId:1, cancelId:1, noLink:true,
      });
      if (choice.response !== 0) { app.quit(); return; }
      await controls.resetReservedShortcuts();
      await controls.load();
    }
    let exerciseActive=false;
    const exerciseRequests=new Set<string>();
    let lastConfiguration="";
    let fixtureModeActive=false;
    let engineLabModeActive=false;
    const configuration=()=>createHelperConfiguration(state.snapshot(),{
      suggestionsAvailable:coordinator!==null,fixtureModeActive,engineLabModeActive,exerciseActive,learningAvailable:learning?.observationEnabled===true,
      clipboardContextEnabled:process.env.AUTOCOMPLETION_CLIPBOARD_CONTEXT==="1",
      contextEnabled:contextController?.enabled===true,
      contextImagesEnabled:contextController?.imagesEnabled===true,
      onDecision:decision=>{runtime.configuration(decision.enabled,decision.reasons);fixtureDiagnostics.configureEffective(decision.enabled,decision.reasons);},
    });
    const sync=():void=>{
      if(helperManager?.state!=="running")return;
      const next=configuration();const serialized=JSON.stringify(next);
      if(serialized===lastConfiguration)return;
      // Opacity updates repaint existing ghosts without cancelling generation.
      const previous=lastConfiguration?JSON.parse(lastConfiguration) as typeof next:null;
      if(!previous || JSON.stringify({...previous,payload:{...previous.payload,ghostAlpha:next.payload.ghostAlpha}})!==serialized)coordinator?.stop();
      transformCoordinator?.stop();
      lastConfiguration=serialized;helperManager.send(next);
    };
    let activity:SuggestionActivity|null=null;
    const invalidate=():void=>{
      outcomeUploader?.reset();
      activity?.clearRequests();
      transformCoordinator?.stop();
      coordinator?.stop();
      if(helperManager?.state!=="running")return;
      const next=configuration();helperManager.send({...next,payload:{...next.payload,enabled:false}});helperManager.send(next);
    };
    // Without a hosted backend the API runs in process with the user's own AI Gateway key.
    const accountOptions={state,openExternal:(url:string)=>shell.openExternal(url),invalidate,changed:()=>settings?.publish()};
    let session:Account;
    let api:{apiUrl:string;tokenProvider:Account["tokenProvider"];request?:typeof fetch};
    if(backend.mode==="hosted"){
      session=new AccountSession({...accountOptions,store:secureStore,root:join(root,"secure"),config:backend.config});
      api={apiUrl:backend.config.apiUrl,tokenProvider:session.tokenProvider};
    }else{
      const local=new LocalAccount({...accountOptions,store:new SecureStore(join(root,"secure","local-backend.bin"))});
      session=local;api={apiUrl:LOCAL_API_ORIGIN,tokenProvider:local.tokenProvider,request:local.request};
    }
    account=session;
    contextController=new ContextController({root,...api,
      executable:app.isPackaged?join(process.resourcesPath,"native","AutocompleteContextService"):join(__dirname,"../../../../native/macos/.build/release/AutocompleteContextService"),
      visionVerified:process.env.AUTOCOMPLETION_CONTEXT_VISION_VERIFIED==="1",open:url=>shell.openExternal(url),
      changed:()=>{sync();settings?.publish();},send:message=>{if(helperManager?.state==="running")helperManager.send(message);},
      invalidate:ids=>{coordinator?.invalidate(ids);transformCoordinator?.invalidate(ids);},
    });
    const learningTransport=new LearningTransport(api);
    const learner=new LearningService({
      storeForAccount:subject=>new SecureStore(learningFileForAccount(join(root,"secure"),subject)),
      extract:(input,signal)=>contextController!.background.run(signal,()=>learningTransport.extract(input,signal)),
      changed:personalization=>{state.update({personalization});sync();},
    });learning=learner;
    const syncLearning=():void=>{
      const s=state.snapshot();
      void learner.setEnvironment(s.account.state==="signed_in"?s.account.identity?.subject??null:null,
        s.enabled&&s.helperState==="running"&&s.permissions.accessibility==="granted"&&s.permissions.inputMonitoring==="granted",
        [...Object.entries(s.apps).filter(([,allowed])=>!allowed).map(([id])=>id),"com.autocompletion.settings"])
        .catch(()=>{ /* Encryption/load failure leaves learning off, with no snippets retained. */ });
    };
    const requestSuggestion=():void=>{
      runtime.pipeline("manual_request_invoked");
      trace.record({event:"manual_request",attrs:{stage:"invoked"}});
      if(!configuration().payload.enabled){runtime.pipeline("manual_request_blocked","disabled");trace.record({event:"manual_request",attrs:{stage:"blocked",reason:"disabled"}});return;}
      if(helperManager?.state!=="running"){runtime.pipeline("manual_request_blocked","helper_unavailable");trace.record({event:"manual_request",attrs:{stage:"blocked",reason:"helper_unavailable"}});return;}
      // The helper resolves current focus and exclusions at invocation time.
      learner.userActivity();
      runtime.pipeline("manual_request_sent");
      trace.record({event:"manual_request",attrs:{stage:"sent"}});
      helperManager.send({protocolVersion:PROTOCOL_VERSION,type:"request_suggestion",payload:null});
    };
    const shortcut = new SuggestionShortcut(globalShortcut, requestSuggestion);
    state.update({shortcutRegistered:shortcut.start(state.snapshot().shortcut)});
    const exercise=(active:boolean):void=>{
      const current=state.snapshot();
      if(active&&(!current.enabled||current.account.state!=="signed_in"||current.apps["com.autocompletion.settings"]===false||current.permissions.accessibility!=="granted"||current.permissions.inputMonitoring!=="granted")){
        state.update({exercise:"unavailable"});throw new Error("Autocomplete Everywhere is not available for practice");
      }
      exerciseActive=active;exerciseRequests.clear();state.update({exercise:"idle"});sync();
    };
    const transport=new HttpSuggestionTransport({...api,trace});
    const transforms=new TransformSettingsStore(new SecureStore(join(root,"secure","transforms.bin")),()=>{transformCoordinator?.stop();syncTransforms();settings?.publish();});
    await transforms.restore();
    function syncTransforms():void {
      if(helperManager?.state!=="running")return;
      const value=transforms.get();
      helperManager.send({protocolVersion:PROTOCOL_VERSION,type:"transform_configure",payload:{shortcuts:value.enabled?value.transforms.map(t=>({id:t.id,name:t.name,key:t.shortcut})):[]}});
    }
    transformCoordinator=new TransformCoordinator({context:contextController.engine,getSettings:()=>transforms.get(),transform:(input,signal)=>transport.transform(input,signal),send:message=>{if(helperManager?.state==="running")helperManager.send(message);}});
    if(process.env.AUTOCOMPLETION_VISUAL_FIXTURE!=="1")outcomeUploader=new SuggestionOutcomeUploader({send:(events,signal)=>transport.recordSuggestionOutcomes(events,signal),onDiagnostic:code=>runtime.pipeline(code)});
    activity=new SuggestionActivity({onEvent:event=>{if(state.snapshot().account.state==="signed_in")outcomeUploader?.enqueue(event);},onChange:summary=>{state.setActivity(summary);runtime.activity(summary);}});
    const nativeActions=createNativeActions({transforms,previewTransform:input=>transport.transform(input,AbortSignal.timeout(16_000)),learning:learner,state,preferences:controls,account:session,
      setShortcutRecording:active=>shortcut.setRecording(active),
      setShortcut:async value=>{await shortcut.change(value,()=>controls.setShortcut(value));state.update({shortcutRegistered:true});},
      restartHelper:async()=>{await helperManager?.restart();},exercise,
      requestExercise:()=>{if(exerciseActive)requestSuggestion();},
    });
    settings=new NativeSettings({
      executable:app.isPackaged?join(process.resourcesPath,"native","AutocompleteEverywhere.app","Contents","MacOS","AutocompleteEverywhere"):join(__dirname,"../../native-ui/AutocompleteEverywhere.app/Contents/MacOS/AutocompleteEverywhere"),
      snapshot:()=>({context:contextController!.snapshot(),status:state.snapshot(),transforms:transforms.get(),entries:session.library&&state.snapshot().account.state==="signed_in"?session.library.list():[]}),
      handle:request=>request.action.startsWith("context_")?contextController!.action(request):nativeActions(request),closed:()=>{exercise(false);void shortcut.setRecording(false).catch(()=>state.update({shortcutRegistered:false}));},
      unavailable:()=>dialog.showErrorBox("Autocomplete Everywhere",state.snapshot().uiLanguage==="es"?"No se pudo abrir Ajustes. Volvé a abrir Autocomplete Everywhere.":"Settings could not be opened. Reopen Autocomplete Everywhere."),
    });
    disposeTray=createProductTray({state,resume:()=>controls.resume(),pause:choice=>controls.pause(choice),setAppEnabled:(id,enabled)=>controls.setAppEnabled(id,enabled),requestSuggestion,showSettings:()=>settings?.show(),quit:()=>app.quit()}).dispose;
    coordinator=createSuggestionBootstrap({environment:process.env,
      remoteSource:new ContextualSuggestionSource({transport,trace,context:contextController.engine,preferencesForApp:appId=>learner.preferencesForApp(appId),isAllowed:appId=>{
        const s=state.snapshot();return s.enabled&&s.account.state==="signed_in"&&s.permissions.accessibility==="granted"&&s.permissions.inputMonitoring==="granted"&&s.apps[appId]!==false&&(appId!=="com.autocompletion.settings"||exerciseActive);
      }}),
      onSourceDecision:decision=>fixtureDiagnostics.sourceDecision(decision),
      onFinalResult:result=>fixtureDiagnostics.coordinatorFinalResult(result),trace,
      send:message=>{
        helperManager?.send(message);
        activity?.observe(message);
        if(message.type==="suggestion_final"){
          runtime.request("final");runtime.pipeline("response_final");fixtureDiagnostics.responseSent("final");
          state.update({connection:"ready"});
          if(exerciseRequests.has(message.identity.requestId)&&!("text" in message.payload))state.update({exercise:"unavailable"});
        }else if(message.type==="request_failed"){
          runtime.request("failed",message.payload.code);runtime.pipeline("request_failed",message.payload.code);fixtureDiagnostics.responseSent("failed");
          if(message.payload.code==="unauthorized")session.expire();
          else state.update({connection:message.payload.code==="network"||message.payload.code==="timeout"?"offline":"error"});
          if(exerciseRequests.has(message.identity.requestId))state.update({exercise:"unavailable"});
        }
      },
    });
    fixtureModeActive=process.env.AUTOCOMPLETION_VISUAL_FIXTURE==="1"&&coordinator!==null;
    engineLabModeActive=process.env.AUTOCOMPLETION_ENGINE_LAB==="1"&&coordinator!==null;
    helperManager=new HelperProcessManager({helperPath:app.isPackaged?resolvePackagedHelperPath(process.resourcesPath):join(__dirname,"../../../../native/macos/.build/release/AutocompleteHelper"),
      onMessage:message=>{
        if(contextController?.observe(message))return;
        // Corrections travel only through the private learning path, never diagnostics or foreground generation.
        if(message.type==="user_activity"){learner.userActivity();return;}
        if(message.type==="correction_observed"){learner.observe(message.identity.requestId,message.payload);return;}
        if(message.type==="interaction")learner.interaction(message.identity.requestId,message.payload.outcome);
        if(message.type==="permission_state"){
          runtime.permission(message.payload.accessibility,message.payload.inputMonitoring);fixtureDiagnostics.permissionState(message.payload.accessibility,message.payload.inputMonitoring);
        }else if(message.type==="suggestion_request"){
          learner.registerRequest(message.identity.requestId,message.payload.appId);
          runtime.request("observed");runtime.pipeline("capture_observed");fixtureDiagnostics.suggestionRequestObserved();
          if(exerciseActive&&message.payload.appId==="com.autocompletion.settings"){exerciseRequests.clear();exerciseRequests.add(message.identity.requestId);state.update({exercise:"waiting"});}
        }else if(message.type==="cancel_request"){
          runtime.request("cancelled",message.payload.reason);
          if(exerciseRequests.delete(message.identity.requestId))state.update({exercise:"idle"});
        }
        applyHelperMessage(state,message);
        if(message.type==="suggestion_request"){
          if(!configuration().payload.enabled||state.snapshot().apps[message.payload.appId]===false)return;
        }
        if(message.type==="transform_request"&&!configuration().payload.enabled)return;
        if(message.type==="transform_request")coordinator?.stop();
        if(message.type==="suggestion_request")transformCoordinator?.stop();
        void transformCoordinator?.handle(message);
        activity?.observe(message);
        if(message.type==="interaction")runtime.interaction(message.payload.outcome);
        coordinator?.handle(message);
      },
      onDiagnostic:diagnostic=>{
        runtime.helperDiagnostic(diagnostic.code);fixtureDiagnostics.helperEvent(diagnostic.code);
        if (diagnostic.code === "manual_request_received" || diagnostic.code === "manual_request_target_unavailable") {
          trace.record({event:"manual_request",attrs:{stage:diagnostic.code === "manual_request_received" ? "received" : "target_unavailable"}});
        }
        // Already validated, content-free helper codes. Retain rewrite failure
        // evidence beyond the short status ring, without recording selection text.
        if (/^fixture_(geometry_request_|presenter_|presentation_)/.test(diagnostic.code)) {
          trace.record({event:"render_diagnostic",attrs:{code:diagnostic.code}});
        }
        if (/^fixture_(transform_|capture_skipped_|typography_|web_read_)/.test(diagnostic.code)) {
          trace.record({event:"rewrite_diagnostic",attrs:{code:diagnostic.code}});
        }
      },
      onTimeline:event=>{
        trace.recordHelper(event);
        if(!exerciseActive||!event.requestId||!exerciseRequests.has(event.requestId))return;
        if(event.event==="presented")state.update({exercise:"shown"});
        else if(event.event==="present_rejected")state.update({exercise:"unavailable"});
        else if(event.event==="interaction"){
          const outcome=event.attrs.outcome;
          if(outcome==="accepted_full"||outcome==="accepted_partial")state.update({exercise:"accepted"});
          else if(outcome==="dismissed")state.update({exercise:"dismissed"});
        }
      },
      onStateChange:helperState=>state.update({helperState:helperState==="running"?"running":helperState==="starting"?"starting":"unavailable"}),
      onReady:()=>{runtime.pipeline("helper_running");lastConfiguration="";sync();syncTransforms();},
    });
    unsubscribe=state.subscribe(()=>{contextController?.setEnvironment(state.snapshot());syncLearning();sync();settings?.publish();});syncLearning();contextController.setEnvironment(state.snapshot());
    powerMonitor.on("lock-screen",()=>contextController?.setLocked(true,state.snapshot()));
    powerMonitor.on("unlock-screen",()=>contextController?.setLocked(false,state.snapshot()));
    powerMonitor.on("suspend",()=>contextController?.setLocked(true,state.snapshot()));
    powerMonitor.on("resume",()=>{contextController?.setLocked(false,state.snapshot());session.library?.expire();void controls.expirePause().catch(()=>{});});
    app.on("activate",()=>settings?.show());
    settings.show();
    await Promise.allSettled([helperManager.start(),session.initialize()]);
  }).catch(error=>dialog.showErrorBox("Autocomplete Everywhere",error instanceof MissingRuntimeConfigError?`${error.message} See "Hosted mode" in the README.`:"Autocomplete Everywhere could not start. Your saved data has not been changed. Reopen the app to try again."));
  app.on("window-all-closed",()=>{});
  app.on("before-quit",()=>{contextController?.dispose();outcomeUploader?.dispose();globalShortcut.unregisterAll();unsubscribe?.();disposeTray?.();settings?.stop();account?.dispose();learning?.dispose();preferences?.dispose();coordinator?.stop();transformCoordinator?.stop();helperManager?.stop();});
}
if(claimSingleInstance(app,()=>settings?.show()))startPrimaryInstance();
