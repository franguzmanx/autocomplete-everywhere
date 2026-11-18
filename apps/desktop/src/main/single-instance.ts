type SingleInstanceApp={requestSingleInstanceLock():boolean;quit():void;on(event:"second-instance",listener:()=>void):unknown};
export function claimSingleInstance(app:SingleInstanceApp,showPrimary:()=>void):boolean{
  if(!app.requestSingleInstanceLock()){app.quit();return false;}
  app.on("second-instance",showPrimary);return true;
}
