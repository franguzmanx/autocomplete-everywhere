/** History augments current captured context; a stalled local service cannot stall writing. */
export async function prepareContext<T>(
  work: (signal: AbortSignal) => Promise<T>,
  parent: AbortSignal,
): Promise<T | undefined> {
  parent.throwIfAborted();
  const controller = new AbortController();
  let finish!: (value: undefined) => void;
  const interrupted = new Promise<undefined>(resolve => { finish = resolve; });
  const cancel = () => { controller.abort(); finish(undefined); };
  parent.addEventListener("abort", cancel, { once: true });
  const timer = setTimeout(cancel, 100);
  try {
    const result = await Promise.race([work(controller.signal).catch(() => undefined), interrupted]);
    parent.throwIfAborted();
    return result;
  } finally {
    clearTimeout(timer);
    parent.removeEventListener("abort", cancel);
  }
}
