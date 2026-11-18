import type {
  ManualContextConnection,
  ManualContextProfile,
} from "./manual-context.js";
import type { AuthenticatedPostgresRunner } from "./postgres-client.js";

type ManualContextRow = {
  personal_context: string | null;
  company_context: string | null;
};

export function createPostgresManualContextConnection(
  runner: AuthenticatedPostgresRunner,
): ManualContextConnection {
  return {
    save: (subject, profile) =>
      runner.run(subject, async (transaction) => {
        await transaction`
          select public.replace_manual_context(
            ${profile.personal},
            ${profile.company}
          )
        `;
      }),
    read: (subject) =>
      runner.run(subject, async (transaction) => {
        const rows = await transaction<ManualContextRow[]>`
          select personal_context, company_context
          from public.read_manual_context()
        `;
        const row = rows[0];
        return {
          personal: row?.personal_context ?? "",
          company: row?.company_context ?? "",
        } satisfies ManualContextProfile;
      }),
  };
}
