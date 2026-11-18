import { prepareContext } from "./context-preparation";
import { PROTOCOL_VERSION, TransformOutputSchema, type ProtocolMessage, type TransformInput, type TransformSettings } from '@autocompletion/protocol';

export class TransformCoordinator {
  private active: { id: string; controller: AbortController } | null = null;
  constructor(private readonly options: {
    getSettings(): TransformSettings;
    context?:{prepare(id:string,query:string,appId:string,signal:AbortSignal):Promise<import("@autocompletion/protocol").PreparedContext|undefined>;valid(id:string,signal:AbortSignal):Promise<boolean>};
    transform(input: TransformInput, signal: AbortSignal): Promise<string>;
    send(message: ProtocolMessage): void;
  }) {}

  invalidate(requestIds:string[]):void {if(this.active&&requestIds.includes(this.active.id))this.stop();}
  stop(): void { this.active?.controller.abort(); this.active = null; }

  async handle(message: ProtocolMessage): Promise<void> {
    if (message.type === 'cancel_request' && this.active?.id === message.identity.requestId) { this.stop(); return; }
    if (message.type !== 'transform_request') return;
    this.stop();
    const settings = this.options.getSettings();
    const transform = settings.transforms.find(t => t.id === message.payload.transformId);
    const send = (payload: Extract<ProtocolMessage, { type: 'transform_result' }>['payload']) => this.options.send({ protocolVersion: PROTOCOL_VERSION, type: 'transform_result', identity: message.identity, payload });
    if (!settings.enabled || !transform) { send({ error: 'unavailable' }); return; }
    const active = { id: message.identity.requestId, controller: new AbortController() };
    this.active = active;
    const timeout = setTimeout(() => active.controller.abort(), 16_000);
    try {
      const preparedContext=this.options.context ? await prepareContext(signal=>this.options.context!.prepare(active.id,message.payload.text,message.payload.appId,signal),active.controller.signal) : undefined;
      if(active.controller.signal.aborted)return;
      const text = await this.options.transform({ ...(preparedContext?{preparedContext}:{}),text: message.payload.text, singleLine: message.payload.singleLine, transform }, active.controller.signal);
      if (this.active !== active) return;
      if(preparedContext&&!await prepareContext(signal=>this.options.context!.valid(active.id,signal),active.controller.signal)){send({error:"unavailable"});return;}
      const result = TransformOutputSchema.safeParse({ text });
      if (active.controller.signal.aborted || !result.success || (message.payload.singleLine && /[\r\n\u2028\u2029]/u.test(text))) send({ error: 'unavailable' });
      else send(result.data);
    } catch { if (this.active === active) send({ error: 'unavailable' }); }
    finally { clearTimeout(timeout); if (this.active === active) this.active = null; }
  }
}
