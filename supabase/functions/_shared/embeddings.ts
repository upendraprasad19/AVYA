/**
 * Shared Gemini text-embedding-004 helper.
 *
 * Model specs:
 *   - 768 dimensions (fixed)
 *   - Free tier: 1,500 requests/minute, $0 cost
 *   - Max input: 2,048 tokens
 *   - Asymmetric task types: use RETRIEVAL_DOCUMENT when storing,
 *     RETRIEVAL_QUERY when searching. This measurably improves recall.
 *
 * Used by: ai-proxy, ai-proxy-pro, rolling-context
 */

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;

const EMBEDDING_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent";

export type EmbeddingTaskType =
  | "RETRIEVAL_DOCUMENT" // use when storing content into the index
  | "RETRIEVAL_QUERY"; // use when embedding a user query for search

/**
 * Call Gemini text-embedding-004 and return a 768-dimensional vector.
 *
 * Returns null on any failure — callers must handle null gracefully.
 * Embedding failures must NEVER break the primary chat response.
 */
export async function getEmbedding(
  text: string,
  taskType: EmbeddingTaskType = "RETRIEVAL_DOCUMENT",
): Promise<number[] | null> {
  if (!GEMINI_API_KEY) {
    console.error("[embeddings] GEMINI_API_KEY not configured");
    return null;
  }

  const cleanedText = text.trim().replace(/\s+/g, " ");
  if (!cleanedText) return null;

  try {
    const response = await fetch(
      `${EMBEDDING_URL}?key=${GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "models/text-embedding-004",
          content: {
            parts: [{ text: cleanedText }],
          },
          taskType,
        }),
      },
    );

    if (!response.ok) {
      const errBody = await response.text();
      console.error(`[embeddings] API error ${response.status}:`, errBody);
      return null;
    }

    const data = await response.json();
    const values = data?.embedding?.values as number[] | undefined;

    if (!Array.isArray(values) || values.length !== 768) {
      console.error("[embeddings] Unexpected shape:", values?.length);
      return null;
    }

    return values;
  } catch (err) {
    console.error("[embeddings] Fetch failed:", err);
    return null;
  }
}
