import { expect,test } from "vitest";
import { ProductState } from "../src/main/state";
import { statusLabel } from "../src/main/product-menu";
test("status tells why suggestions are unavailable and follows app language",()=>{
 const s=new ProductState();expect(statusLabel(s.snapshot())).toBe("Sign in");
 s.setSignedIn();expect(statusLabel(s.snapshot())).toBe("Needs permission");
 s.setPermissions({accessibility:"granted",inputMonitoring:"granted"});expect(statusLabel(s.snapshot())).toBe("Helper unavailable");
 s.update({helperState:"running",enabled:true,automaticSuggestions:false});expect(statusLabel(s.snapshot())).toBe("On request");
 s.update({uiLanguage:"es"});expect(statusLabel(s.snapshot())).toBe("A pedido");
 s.update({account:{state:"expired",identity:null}});expect(statusLabel(s.snapshot())).toBe("Volvé a iniciar sesión");
});
