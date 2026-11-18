/** One bounded queue shared by visual analysis, indexing, connectors and learning. */
export class BackgroundOperations {
  private active = 0;
  private pending: Array<{ start(): void; cancel(): void }> = [];

  run<T>(signal: AbortSignal, operation: () => Promise<T>): Promise<T> {
    if (signal.aborted)
      return Promise.reject(new Error("Background operation cancelled"));
    if (this.pending.length >= 32)
      return Promise.reject(new Error("Background queue full"));
    return new Promise<T>((resolve, reject) => {
      const entry = {
        cancel: () => {
          const index = this.pending.indexOf(entry);
          if (index >= 0) this.pending.splice(index, 1);
          signal.removeEventListener("abort", entry.cancel);
          reject(new Error("Background operation cancelled"));
        },
        start: () => {
          signal.removeEventListener("abort", entry.cancel);
          if (signal.aborted) {
            entry.cancel();
            return;
          }
          this.active++;
          Promise.resolve()
            .then(() => {
              signal.throwIfAborted();
              return operation();
            })
            .then(resolve, reject)
            .finally(() => {
              this.active--;
              this.drain();
            });
        },
      };
      signal.addEventListener("abort", entry.cancel, { once: true });
      this.pending.push(entry);
      this.drain();
    });
  }

  private drain(): void {
    while (this.active < 2 && this.pending.length)
      this.pending.shift()!.start();
  }
}
