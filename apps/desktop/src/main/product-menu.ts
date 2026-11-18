import type { ProductStatus } from "../shared/contracts";
export function statusLabel(status:ProductStatus):string{
  const es=status.uiLanguage==="es";
  if(status.account.kind==="api_key"&&status.account.state!=="signed_in")return es?"Falta la clave de AI Gateway":"Add your AI Gateway key";
  if(status.account.state==="expired")return es?"Volvé a iniciar sesión":"Sign in again";
  if(status.account.state!=="signed_in")return es?"Iniciá sesión":"Sign in";
  if(status.permissions.accessibility!=="granted"||status.permissions.inputMonitoring!=="granted")return es?"Faltan permisos":"Needs permission";
  if(status.helperState!=="running")return es?"Ayudante no disponible":"Helper unavailable";
  if(status.pausedUntil!==null)return (es?"Pausado hasta ":"Paused until ")+new Intl.DateTimeFormat(es?"es":"en",{weekday:"short",hour:"numeric",minute:"2-digit"}).format(status.pausedUntil);
  if(status.connection!=="ready")return es?"Problema de conexión":"Connection problem";
  if(!status.automaticSuggestions)return es?"A pedido":"On request";
  return es?"Listo":"Ready";
}
export function buildProductMenuModel(status:ProductStatus){
  return {stateLabel:statusLabel(status),toggleEnabled:status.account.state==="signed_in"};
}
