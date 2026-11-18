export type ManualContextProfile = {
  personal: string;
  company: string;
};

export type ManualContextConnection = {
  save(subject: string, profile: ManualContextProfile): Promise<void>;
  read(subject: string): Promise<ManualContextProfile>;
};

import {
  classifyDatabaseCode,
  classifyDatabaseReason,
  requireSubject as normalizeSubject,
} from "./database-failure.js";

export class ManualContextFailure extends Error {
  constructor(
    readonly operation: "read" | "save",
    readonly code: string,
    readonly reason: string,
  ) {
    super(`Manual context ${operation} failed`);
    this.name = "ManualContextFailure";
  }
}

function requireSubject(subject: string, operation: "read" | "save"): string {
  const normalized = normalizeSubject(subject);
  if (normalized === null) {
    throw new ManualContextFailure(
      operation,
      "INVALID_SUBJECT",
      "rejected",
    );
  }
  return normalized;
}

function failureFor(
  operation: "read" | "save",
  error: unknown,
): ManualContextFailure {
  if (error instanceof ManualContextFailure) return error;
  const candidate = error as { code?: unknown; message?: unknown };
  return new ManualContextFailure(
    operation,
    classifyDatabaseCode(candidate?.code),
    classifyDatabaseReason(candidate?.message),
  );
}

export class ManualContextRepository {
  constructor(private readonly connection: ManualContextConnection) {}

  async save(
    subject: string,
    profile: ManualContextProfile,
  ): Promise<void> {
    const verifiedSubject = requireSubject(subject, "save");
    try {
      await this.connection.save(verifiedSubject, profile);
    } catch (error) {
      throw failureFor("save", error);
    }
  }

  async read(subject: string): Promise<ManualContextProfile> {
    const verifiedSubject = requireSubject(subject, "read");
    try {
      return await this.connection.read(verifiedSubject);
    } catch (error) {
      throw failureFor("read", error);
    }
  }
}
