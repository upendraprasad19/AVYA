import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { retrieveRelevantMemories } from "./memory_retrieval.ts";

// Deno's module resolver makes mocking imported functions awkward. We
// inject dependencies via a second-argument pattern in production, but
// the simplest unit-test surface is a stub Supabase client whose rpc()
// returns whatever the test sets up. We do NOT mock getEmbedding here —
// it's tested separately; we feed the stub Supabase client the exact
// vector the real embedding call would emit for the test query.

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
  );

  assertEquals(result.source, "retrieval");
  assertEquals(result.memories.length, 2);
  assertEquals(result.memories[0].similarity, 0.87);
});
