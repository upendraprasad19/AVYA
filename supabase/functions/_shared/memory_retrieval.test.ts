import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { retrieveRelevantMemories } from "./memory_retrieval.ts";

// Tests inject a stub `getEmbeddingFn` via `RetrievalOptions` so we never
// hit the real Gemini API in the test environment. The stub returns a
// fake 768-length vector — the exact contents don't matter because the
// stub Supabase client's rpc() is also fake; all it needs is a non-null
// value to exercise the RPC branch.

const FAKE_EMBEDDING = new Array<number>(768).fill(0.1);
const okEmbed = async (_text: string, _taskType: string) => FAKE_EMBEDDING;
const nullEmbed = async (_text: string, _taskType: string) => null;
const hangEmbed = (_text: string, _taskType: string) =>
  new Promise<number[] | null>(() => {
    // never resolves — exercises the withTimeout path
  });

function stubSupabase(rpcImpl: (name: string, args: unknown) => unknown) {
  return {
    rpc: (name: string, args: unknown) => Promise.resolve(rpcImpl(name, args)),
  };
}

Deno.test("retrieveRelevantMemories — happy path returns ranked matches", async () => {
  const stub = stubSupabase((_name, _args) => ({
    data: [
      {
        id: "m1",
        content: "User complained squats aggravate knee; switched to leg press",
        source_type: "coaching_note",
        metadata: { date: "2026-03-18" },
        created_at: "2026-03-18T04:00:00Z",
        similarity: 0.87,
      },
      {
        id: "m2",
        content: "Hit protein PR 180g",
        source_type: "daily_summary",
        metadata: { date: "2026-04-02" },
        created_at: "2026-04-02T23:00:00Z",
        similarity: 0.72,
      },
    ],
    error: null,
  }));

  const result = await retrieveRelevantMemories(
    stub,
    "1574f7c6-5cf1-411b-9ebc-61471445285a",
    "my knee hurts after squats",
    { getEmbeddingFn: okEmbed },
  );

  assertEquals(result.source, "retrieval");
  assertEquals(result.memories.length, 2);
  assertEquals(result.memories[0].similarity, 0.87);
});

Deno.test("retrieveRelevantMemories — zero matches returns source:empty", async () => {
  const stub = stubSupabase((_name, _args) => ({ data: [], error: null }));

  const result = await retrieveRelevantMemories(
    stub,
    "00000000-0000-0000-0000-000000000000",
    "unrelated query that matches nothing",
    { getEmbeddingFn: okEmbed },
  );

  assertEquals(result.source, "empty");
  assertEquals(result.memories.length, 0);
});

Deno.test("retrieveRelevantMemories — embedding returns null → source:no_embedding", async () => {
  // The stub should never be called because the function short-circuits.
  const stub = stubSupabase(() => {
    throw new Error("rpc should not be called when embedding failed");
  });

  const result = await retrieveRelevantMemories(
    stub,
    "1574f7c6-5cf1-411b-9ebc-61471445285a",
    "anything",
    { getEmbeddingFn: nullEmbed },
  );

  assertEquals(result.source, "no_embedding");
  assertEquals(result.memories.length, 0);
});

Deno.test("retrieveRelevantMemories — embedding hang triggers timeout → source:no_embedding", async () => {
  // Stub that hangs forever; the withTimeout wrapper should abandon it.
  const stub = stubSupabase(() => {
    throw new Error("rpc should not be called when embedding timed out");
  });

  const result = await retrieveRelevantMemories(
    stub,
    "1574f7c6-5cf1-411b-9ebc-61471445285a",
    "anything",
    {
      getEmbeddingFn: hangEmbed,
      embeddingTimeoutMs: 50, // fast test — real default is 3000 ms
    },
  );

  assertEquals(result.source, "no_embedding");
  assertEquals(result.memories.length, 0);
});

Deno.test("retrieveRelevantMemories — rpc error returns source:rpc_error", async () => {
  // Simulate an RPC failure — supabase-js returns { data: null, error: {...} }
  const stub = stubSupabase((_name, _args) => ({
    data: null,
    error: { message: "connection to server at pgvector lost" },
  }));

  const result = await retrieveRelevantMemories(
    stub,
    "1574f7c6-5cf1-411b-9ebc-61471445285a",
    "anything",
    { getEmbeddingFn: okEmbed },
  );

  assertEquals(result.source, "rpc_error");
  assertEquals(result.memories.length, 0);
});
