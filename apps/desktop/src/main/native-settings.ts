import type { TransformSettings } from "@autocompletion/protocol";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { StringDecoder } from "node:string_decoder";
import { parseNativeRequest, type NativeRequest } from "./native-settings-protocol";
import type { LibraryEntry, ProductStatus } from "../shared/contracts";

type Options = {
  executable: string;
  snapshot(): {status:ProductStatus;entries:LibraryEntry[];transforms:TransformSettings;context?:import("./context-engine").ContextSnapshot};
  handle(request:NativeRequest): Promise<unknown>;
  closed(): void;
  unavailable(): void;
};
/** Private parent/child pipe, no sockets, browser renderer or credential exposure. */
export class NativeSettings {
  private child: ChildProcessWithoutNullStreams | null = null;
  private stopping = false;
  private lastPublished="";
  constructor(private readonly options:Options) {}
  show(): void {
    if (this.child) { this.publish(); this.send({type:"show"}); return; }
    this.stopping=false;this.lastPublished="";
    const child=spawn(this.options.executable,[],{stdio:["pipe","pipe","pipe"],env:{...process.env}});
    this.child=child;
    // stderr may contain AppKit diagnostics, but must never be copied to product logs.
    child.stderr.resume();
    child.stdin.on("error",()=>{});
    let closed=false;
    const cleanup=():void=>{ if(closed)return; closed=true; if(this.child===child){this.child=null;this.options.closed();} };
    child.on("error",()=>{cleanup();if(!this.stopping)this.options.unavailable();});
    child.on("exit",(code)=>{cleanup();if(code && !this.stopping)this.options.unavailable();});
    let pending=0;
    const onLine=(line:string):void=>{
      if (this.child!==child)return;
      let request:NativeRequest;
      try {request=parseNativeRequest(line);} catch {child.kill();return;}
      if(pending>=16){this.send({type:"result",id:request.id,ok:false,error:this.errorText()});return;}
      pending++;
      const subject=this.options.snapshot().status.account.identity?.subject;
      void this.options.handle(request).then(value=>{
        if(this.child!==child)return;
        if((request.action.startsWith("library") || request.action.startsWith("context_")) && subject!==this.options.snapshot().status.account.identity?.subject)throw new Error("Account changed");
        this.send({type:"result",id:request.id,ok:true,value:value??null});this.publish();
      }).catch(()=>{
        if(this.child===child)this.send({type:"result",id:request.id,ok:false,error:(request.action === "setShortcut" || request.action === "setInteractionShortcut") ? (this.options.snapshot().status.uiLanguage === "es" ? "El atajo no está disponible o no pudo guardarse. Elegí otro." : "The shortcut is unavailable or could not be saved. Choose another.") : this.errorText()});
      }).finally(()=>{pending--;});
    };
    const decoder=new StringDecoder("utf8");let buffer="";
    child.stdout.on("data",(chunk:Buffer)=>{
      buffer+=decoder.write(chunk);
      if(Buffer.byteLength(buffer)>1_000_000){child.kill();return;}
      let boundary:number;
      while((boundary=buffer.indexOf("\n"))>=0){const line=buffer.slice(0,boundary);buffer=buffer.slice(boundary+1);if(line.trim())onLine(line);}
    });
    this.publish();
  }
  private errorText():string {return this.options.snapshot().status.uiLanguage==="es"?"No se pudo completar el cambio. Revisá los datos o la conexión e intentá de nuevo.":"The change could not be completed. Check the details or connection and try again.";}
  publish():void{
    if(!this.child)return;
    const value={type:"state",...this.options.snapshot()};const serialized=JSON.stringify(value);
    if(serialized===this.lastPublished)return;
    this.lastPublished=serialized;this.send(value);
  }
  private send(value:unknown):void {
    if(this.child?.stdin.writable && !this.child.stdin.destroyed){
      if(this.child.stdin.writableLength>8_000_000){this.child.kill();return;}
      this.child.stdin.write(JSON.stringify(value)+"\n");
    }
  }
  stop():void{this.stopping=true;this.child?.stdin.end();this.child?.kill();this.child=null;}
}
