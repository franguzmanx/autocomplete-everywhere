import postgres from "postgres";

export type AuthenticatedTransaction = postgres.TransactionSql<
  Record<string, never>
>;

/// Runs one operation as the verified Clerk subject. The role and JWT claims
/// are transaction-local, so the checked-in RLS policies authorize every row
/// and nothing leaks between users sharing a pooled connection.
export type AuthenticatedPostgresRunner = {
  run<T>(
    subject: string,
    operation: (transaction: AuthenticatedTransaction) => Promise<T>,
  ): Promise<T>;
};

function requireDatabaseUrl(databaseUrl: string): string {
  if (!databaseUrl.trim()) throw new Error("Database URL is required");
  return databaseUrl;
}

export function createAuthenticatedPostgresRunner(
  databaseUrl: string,
): AuthenticatedPostgresRunner {
  const sql = postgres(requireDatabaseUrl(databaseUrl), {
    connect_timeout: 10,
    idle_timeout: 20,
    max: 3,
    prepare: false,
    ssl: "require",
  });

  return {
    run: async (subject, operation) => {
      const result = await sql.begin(async (transaction) => {
        await transaction.unsafe("set local role authenticated");
        await transaction`
          select set_config(
            'request.jwt.claims',
            ${JSON.stringify({ sub: subject, role: "authenticated" })},
            true
          )
        `;
        return { value: await operation(transaction) };
      });
      return result.value;
    },
  };
}
