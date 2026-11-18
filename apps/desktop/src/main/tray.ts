import { join } from "node:path";
import { app, Menu, Tray, nativeImage, dialog, type MenuItemConstructorOptions } from "electron";
import { buildProductMenuModel } from "./product-menu";
import { ProductState } from "./state";
import type { PauseChoice } from "../shared/contracts";

type ProductTrayOptions={state:ProductState;resume():Promise<void>;pause(choice:PauseChoice):Promise<void>;setAppEnabled(id:string,enabled:boolean):Promise<void>;requestSuggestion():void;showSettings():void;quit():void};
export function createProductTray(options:ProductTrayOptions):{tray:Tray;dispose():void}{
  const icon=nativeImage.createFromPath(join(app.getAppPath(), "resources/brand/trayTemplate.png"));icon.setTemplateImage(true);
  const tray=new Tray(icon);tray.setToolTip("Autocomplete Everywhere");
  const run=(action:()=>Promise<void>):void=>{void action().catch(()=>dialog.showErrorBox("Autocomplete Everywhere",options.state.snapshot().uiLanguage==="es"?"No se pudo guardar el cambio. Intentá de nuevo.":"Your change could not be saved. Please try again."));};
  const render=():void=>{
    const status=options.state.snapshot();const es=status.uiLanguage==="es";const model=buildProductMenuModel(status);
    const appId=status.currentApplication==="com.autocompletion.settings"?null:status.currentApplication;
    const name=status.applications.find(app=>app.id===appId)?.name??appId;
    const enabled=model.toggleEnabled&&status.enabled&&status.helperState==="running"&&status.permissions.accessibility==="granted"&&status.permissions.inputMonitoring==="granted";
    const template:MenuItemConstructorOptions[]=[
      {label:es?"Abrir Autocomplete Everywhere":"Open Autocomplete Everywhere",accelerator:"CommandOrControl+,",click:options.showSettings},
      ...(!enabled || !status.automaticSuggestions ? [{label:model.stateLabel,enabled:false}] : []),
      {type:"separator"},
      status.pausedUntil===null?{label:es?"Pausar…":"Pause…",submenu:(['15m','30m','1h','tomorrow'] as const).map((choice,i)=>({label:(es?["15 minutos","30 minutos","1 hora","Hasta mañana"]:["15 minutes","30 minutes","1 hour","Until tomorrow"])[i]!,click:()=>run(()=>options.pause(choice))}))}
        :{label:es?"Reanudar ahora":"Resume now",click:()=>run(options.resume)},
      ...(appId?[{label:es?`Activar en ${name}`:`Enable in ${name}`,type:"checkbox" as const,checked:status.apps[appId]!==false,click:()=>run(()=>options.setAppEnabled(appId,status.apps[appId]===false))}]:[]),
      {label:es?"Sugerir texto":"Suggest text",...(status.shortcut?{accelerator:status.shortcut.accelerator}:{}),registerAccelerator:false,enabled:enabled&&!!appId&&status.apps[appId]!==false,click:options.requestSuggestion},
      {type:"separator"},
      {label:es?"Salir de Autocomplete Everywhere":"Quit Autocomplete Everywhere",click:options.quit},
    ];tray.setContextMenu(Menu.buildFromTemplate(template));
  };render();const unsubscribe=options.state.subscribe(render);return{tray,dispose:()=>{unsubscribe();tray.destroy();}};
}
