/** Run with Bun and an explicitly supplied environment file; never prints credentials/content. */
import { writeFile } from "node:fs/promises";
const base = process.env.CONTEXT_PROBE_API_URL,
  token = process.env.CONTEXT_PROBE_ACCESS_TOKEN;
if (!base || !token) {
  console.info(
    JSON.stringify({
      verified: false,
      status: "credentials_required",
      required: ["CONTEXT_PROBE_API_URL", "CONTEXT_PROBE_ACCESS_TOKEN"],
    }),
  );
  process.exitCode = 2;
} else {
  let origin: URL;
  try {
    origin = new URL(base);
    if (
      origin.username ||
      origin.password ||
      !(
        origin.protocol === "https:" ||
        (origin.protocol === "http:" &&
          ["127.0.0.1", "localhost"].includes(origin.hostname))
      )
    )
      throw new Error();
  } catch {
    console.info(
      JSON.stringify({ verified: false, status: "invalid_api_url" }),
    );
    process.exit(2);
  }
  const probe = async (operation: "visual" | "embeddings", body: unknown) => {
    const start = Date.now();
    try {
      const response = await fetch(
        new URL(`/v1/context/${operation}`, origin),
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify(body),
          redirect: "error",
          signal: AbortSignal.timeout(25000),
        },
      );
      const reader = response.body?.getReader();
      if (!reader) throw new Error();
      let size = 0;
      const chunks: Uint8Array[] = [];
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.length;
          if (size > 1000000) throw new Error();
          chunks.push(value);
        }
      } finally {
        await reader.cancel().catch(() => {});
      }
      const result = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      const valid =
        response.ok &&
        (operation === "visual"
          ? typeof result.text === "string" &&
            result.text.trim().length > 0 &&
            result.text.length <= 16000
          : Array.isArray(result.embedding) &&
            result.embedding.length === 768 &&
            result.embedding.every(
              (value: unknown) =>
                typeof value === "number" && Number.isFinite(value),
            ));
      return {
        operation,
        verified: valid,
        httpStatus: response.status,
        durationMs: Date.now() - start,
      };
    } catch {
      return {
        operation,
        verified: false,
        status: "probe_failed",
        durationMs: Date.now() - start,
      };
    }
  };
  // Public synthetic 64-pixel red PNG; never captures a screen or reads user documents.
  const visual = await probe("visual", {
    mimeType: "image/png",
    imageBase64:
      "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAb0lEQVR4nO3PAQkAAAyEwO9feoshgnABdLep8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3I8QUNyPEFDcjxBQ3IPanc8OLDQitxAAAAAElFTkSuQmCC",
  });
  const embedding = await probe("embeddings", {
    text: "Synthetic Autocomplete Everywhere capability probe. The blue square is beside the red circle.",
  });
  const report = {
    verified: visual.verified && embedding.verified,
    capturedAtMs: Date.now(),
    visual,
    embedding,
    models: {
      visual: "google/gemini-3.5-flash-lite",
      embedding: "google/text-multilingual-embedding-002",
    },
    dimensions: 768,
  };
  console.info(JSON.stringify(report));
  if (process.env.CONTEXT_PROBE_REPORT)
    await writeFile(
      process.env.CONTEXT_PROBE_REPORT,
      JSON.stringify(report, null, 2) + "\n",
      { mode: 0o600 },
    );
  if (!report.verified) process.exitCode = 1;
}
