import { describe, expect, test } from "vitest";

import {
  ManualContextFailure,
  ManualContextRepository,
  type ManualContextConnection,
  type ManualContextProfile,
} from "../src/index";

class InMemoryConnection implements ManualContextConnection {
  readonly subjects: string[] = [];
  private profiles = new Map<string, ManualContextProfile>();

  async save(subject: string, profile: ManualContextProfile): Promise<void> {
    this.subjects.push(subject);
    this.profiles.set(subject, profile);
  }

  async read(subject: string): Promise<ManualContextProfile> {
    this.subjects.push(subject);
    return this.profiles.get(subject) ?? { personal: "", company: "" };
  }
}

describe("ManualContextRepository", () => {
  test("stores and reads context only through the verified Clerk subject", async () => {
    const connection = new InMemoryConnection();
    const repository = new ManualContextRepository(connection);
    const profile = {
      personal: "Prefiero respuestas breves.",
      company: "Autocomplete Everywhere ayuda a escribir mejor.",
    };

    await repository.save("user_verified", profile);

    await expect(repository.read("user_verified")).resolves.toEqual(profile);
    await expect(repository.read("user_other")).resolves.toEqual({
      personal: "",
      company: "",
    });
    expect(connection.subjects).toEqual([
      "user_verified",
      "user_verified",
      "user_other",
    ]);
  });

  test("rejects an empty subject before reaching Postgres", async () => {
    const connection = new InMemoryConnection();
    const repository = new ManualContextRepository(connection);

    await expect(
      repository.save(" ", { personal: "private", company: "" }),
    ).rejects.toMatchObject({
      operation: "save",
      code: "INVALID_SUBJECT",
      reason: "rejected",
    });
    expect(connection.subjects).toEqual([]);
  });

  test("classifies database failures without retaining profile content", async () => {
    const repository = new ManualContextRepository({
      save: async () => {
        throw Object.assign(new Error("permission denied"), { code: "42501" });
      },
      read: async () => ({ personal: "", company: "" }),
    });

    const failure = await repository
      .save("user_verified", {
        personal: "private-personal-context",
        company: "private-company-context",
      })
      .catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(ManualContextFailure);
    expect(failure).toMatchObject({
      operation: "save",
      code: "42501",
      reason: "rejected",
    });
    expect(String(failure)).not.toContain("private-personal-context");
    expect(String(failure)).not.toContain("private-company-context");
  });
});
