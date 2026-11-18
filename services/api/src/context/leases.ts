import { randomUUID } from "node:crypto";
import type { AuthenticatedPostgresRunner } from "../../../../packages/database/src/postgres-client.js";
export type ContextLeasePool = {
  acquire(userId: string): Promise<null | (() => Promise<void>)>;
};
export function createContextLeasePool(
  runner: AuthenticatedPostgresRunner,
): ContextLeasePool {
  return {
    async acquire(userId) {
      const id = randomUUID();
      const acquired = await runner.run(userId, async (tx) => {
        const rows =
          await tx`select public.acquire_context_background_lease(${id}::uuid) as acquired`;
        return rows[0]?.acquired === true;
      });
      if (!acquired) return null;
      return async () => {
        await runner.run(userId, async (tx) => {
          await tx`delete from public.context_background_leases where lease_id=${id}::uuid`;
        });
      };
    },
  };
}
