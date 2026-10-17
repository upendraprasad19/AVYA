# Semantic Retrieval (Phase B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Phase B of the semantic-memory system. The AI coach's chat path at `supabase/functions/ai-proxy/index.ts` queries `memory_embeddings` via the existing `match_memories` RPC and injects the top-5 most-relevant past notes (> 0.65 cosine similarity) into the system prompt before calling Gemini. Fallback to today's recent-N coaching_notes behavior when retrieval returns nothing or fails.

**Architecture:** Single new helper `_shared/memory_retrieval.ts` exposes `retrieveRelevantMemories(supabaseClient, userId, query)`. `ai-proxy/index.ts` calls it once per chat turn, after auth + rate limit, and injects the result into the system prompt as a "Relevant context from earlier conversations" block. All failure modes degrade silently to the existing full-dump path — never user-visible.

**Tech Stack:**
- Deno runtime (Supabase Edge Functions)
- Existing `_shared/embeddings.ts` → Gemini `gemini-embedding-001`
- Existing pgvector `match_memories(p_user_id, p_query_embedding, p_match_count, p_similarity_threshold)` RPC (migration `20260331000001_add_pgvector_memory.sql`)
- `supabase-js` already in scope in `ai-proxy`
- Deno built-in `Deno.test` for unit tests — no new framework

**Reference spec:** [docs/superpowers/specs/2026-04-24-semantic-retrieval-design.md](../specs/2026-04-24-semantic-retrieval-design.md)

---

## File Structure

| File | Status | Responsibility |
|------|--------|----------------|
| `supabase/functions/_shared/memory_retrieval.ts` | NEW | Single public function: `retrieveRelevantMemories`. Embeds query, calls RPC, handles every error path. Returns `RetrievalResult = { memories, source }`. |
| `supabase/functions/_shared/memory_retrieval.test.ts` | NEW | Deno.test unit tests for all four branches (happy path, zero matches, embedding failure, RPC failure). Co-located next to source per Deno convention. |
| `supabase/functions/ai-proxy/index.ts` | MODIFY | Import helper. Call it once between auth/rate-limit and prompt build (~line 800 area — will confirm during task). Inject retrieval block into the system prompt between `fitness_summary` and `coaching_notes` sections. |

Spec placed tests under `ai-proxy/__tests__/`; relocating next to `_shared` source because the helper lives in shared and could later be imported from other functions (morning-alert, weekly-report). Co-location is the Deno standard.

---

## Task 1: Module scaffold + types

**Files:**
- Create: `supabase/functions/_shared/memory_retrieval.ts`

- [ ] **Step 1: Create the file with type exports + stub function**

```typescript
// _shared/memory_retrieval.ts
//
// Phase B of the semantic-memory system: retrieves the top-N most
// semantically similar past memories for a user, given a query string.
//
// Phase A (accumulation) has been running since migration
// 20260331000001_add_pgvector_memory.sql — every chat turn and nightly
// summary embeds its content and inserts into memory_embeddings.
// This module reads from that table via the pgvector `match_memories`
// RPC and hands ranked matches back to the caller.
//
// Design spec: docs/superpowers/specs/2026-04-24-semantic-retrieval-design.md

import { getEmbedding } from "./embeddings.ts";

export type MemorySourceType =
  | "conversation"
  | "daily_summary"
  | "coaching_note"
  | "pattern_insight";

export type Memory = {
  id: string;
  content: string;
  source_type: MemorySourceType;
  metadata: Record<string, unknown>;
  created_at: string;
  similarity: number;
};

export type RetrievalSource =
  | "retrieval"      // success with >= 1 match
  | "empty"          // RPC returned [] (no user embeddings OR nothing above threshold)
  | "no_embedding"   // getEmbedding returned null (Gemini error)
  | "rpc_error";     // pgvector / network error

export type RetrievalResult = {
  memories: Memory[];
  source: RetrievalSource;
};

export type RetrievalOptions = {
  matchCount?: number;
  threshold?: number;
};

/**
 * Retrieve the most semantically relevant past memories for this user.
 *
 * Never throws. All failure modes return `{ memories: [], source: <code> }`
 * so the caller can unconditionally proceed to fallback behavior.
 */
// deno-lint-ignore no-explicit-any
export async function retrieveRelevantMemories(
  // deno-lint-ignore no-explicit-any
  supabaseClient: any,
  userId: string,
  query: string,
  options: RetrievalOptions = {},
): Promise<RetrievalResult> {
  // Will be implemented in Task 2.
  const _unused = { supabaseClient, userId, query, options };
  return { memories: [], source: "empty" };
}
```

- [ ] **Step 2: Verify the file compiles**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno check supabase/functions/_shared/memory_retrieval.ts`
Expected: no errors. (If deno isn't installed on the host, the function still deploys — type-checking happens server-side on deploy. Skip if `deno: command not found` and rely on deploy-time check in Task 9.)

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/_shared/memory_retrieval.ts
git commit -m "feat(ai-proxy): scaffold memory_retrieval helper module

Types + stub function. Implementation follows in subsequent commits.
Part of Phase B of the semantic-memory system wired in migration
20260331000001_add_pgvector_memory.sql."
```

---

## Task 2: Happy-path unit test + implementation

**Files:**
- Create: `supabase/functions/_shared/memory_retrieval.test.ts`
- Modify: `supabase/functions/_shared/memory_retrieval.ts` (fill in the stub)

- [ ] **Step 1: Write the failing test**

```typescript
// _shared/memory_retrieval.test.ts
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
```

- [ ] **Step 2: Run the test — expect failure**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno test --allow-net --allow-env supabase/functions/_shared/memory_retrieval.test.ts`
Expected: FAIL. The stub returns 2 matches but the current implementation returns `{ memories: [], source: 'empty' }`. Assertion on `result.source === 'retrieval'` fails.

If deno isn't installed locally, skip this step and rely on deploy-time verification in Task 9. (Mark the step complete with a note.)

- [ ] **Step 3: Implement the happy path**

Replace the stub function body in `_shared/memory_retrieval.ts` with:

```typescript
export async function retrieveRelevantMemories(
  // deno-lint-ignore no-explicit-any
  supabaseClient: any,
  userId: string,
  query: string,
  options: RetrievalOptions = {},
): Promise<RetrievalResult> {
  const matchCount = options.matchCount ?? 5;
  const threshold = options.threshold ?? 0.65;

  // 1. Embed the query — RETRIEVAL_QUERY task type is critical for Gemini's
  //    asymmetric embedding model. Phase A writes use RETRIEVAL_DOCUMENT;
  //    mixing them degrades recall significantly.
  const queryEmbedding = await getEmbedding(query, "RETRIEVAL_QUERY");
  if (!queryEmbedding) {
    return { memories: [], source: "no_embedding" };
  }

  // 2. Call the existing RPC — match_memories filters by user_id then uses
  //    the IVFFlat index on embedding column. Fast even on large corpora.
  const { data, error } = await supabaseClient.rpc("match_memories", {
    p_user_id: userId,
    p_query_embedding: queryEmbedding,
    p_match_count: matchCount,
    p_similarity_threshold: threshold,
  });

  if (error) {
    console.warn(
      "[memory_retrieval] rpc_error",
      JSON.stringify({ user_id: userId, error: error.message ?? error }),
    );
    return { memories: [], source: "rpc_error" };
  }

  const memories = (data ?? []) as Memory[];
  return {
    memories,
    source: memories.length > 0 ? "retrieval" : "empty",
  };
}
```

Also delete the `getEmbedding` mock carve-out at the top of the file — add this import block if not already present:

```typescript
// Import is already present from Task 1 scaffold. If not, add:
// import { getEmbedding } from "./embeddings.ts";
```

- [ ] **Step 4: Run the test — expect pass**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno test --allow-net --allow-env supabase/functions/_shared/memory_retrieval.test.ts`
Expected: PASS (1 test, 1 passed).

Caveat: this test does NOT actually call Gemini — the stub Supabase client is enough to exercise the RPC path. `getEmbedding` DOES run against Gemini unless the embedding module exposes a test mode. If the test fails with a Gemini API error, either (a) ensure `GEMINI_API_KEY` is set in the shell env, or (b) stub `getEmbedding` by importing a different module in tests. For launch, (a) is acceptable.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/memory_retrieval.ts supabase/functions/_shared/memory_retrieval.test.ts
git commit -m "feat(ai-proxy): memory_retrieval happy-path implementation + test

Embeds the query via getEmbedding(RETRIEVAL_QUERY), calls the
match_memories RPC with p_match_count=5, p_similarity_threshold=0.65,
returns ranked Memory[]. Stub Supabase client in the test exercises
the RPC path without hitting pgvector."
```

---

## Task 3: Zero-matches branch

**Files:**
- Modify: `supabase/functions/_shared/memory_retrieval.test.ts` (add test)

- [ ] **Step 1: Write the failing test**

Append to `memory_retrieval.test.ts`:

```typescript
Deno.test("retrieveRelevantMemories — zero matches returns source:empty", async () => {
  const stub = stubSupabase((_name, _args) => ({ data: [], error: null }));

  const result = await retrieveRelevantMemories(
    stub,
    "00000000-0000-0000-0000-000000000000",
    "unrelated query that matches nothing",
  );

  assertEquals(result.source, "empty");
  assertEquals(result.memories.length, 0);
});
```

- [ ] **Step 2: Run the new test — expect pass immediately**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno test --allow-net --allow-env supabase/functions/_shared/memory_retrieval.test.ts`
Expected: both tests PASS (Task 2's implementation already handles empty data — `memories.length > 0 ? 'retrieval' : 'empty'`).

This is a confirmation-pattern test, not a new-behavior test. If it fails, Task 2's final return expression is wrong.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/_shared/memory_retrieval.test.ts
git commit -m "test(ai-proxy): memory_retrieval zero-matches branch"
```

---

## Task 4: Embedding-failure branch

**Files:**
- Modify: `supabase/functions/_shared/memory_retrieval.test.ts`

- [ ] **Step 1: Write the failing test**

Add a helper that stubs the embedding import + a new test. Append to `memory_retrieval.test.ts`:

```typescript
// To test the no_embedding branch we shadow the getEmbedding import by
// using an import map or a specialised test module. Simpler option: stub
// at the Deno module level via import.meta trick. Cleanest in practice:
// export an internal seam.

// Deno.test("retrieveRelevantMemories — embedding failure returns no_embedding", ...)
// SKIPPED in Task 4.
// Rationale: Deno doesn't support jest.mock-style module-level substitution
// without an import-map or rewriting the source to take an injected
// embedding function. Rather than restructure the API surface for a single
// test case, we rely on the explicit `if (!queryEmbedding)` early-return in
// the implementation + manual smoke verification in Task 9 (trigger
// Gemini timeout by pointing GEMINI_API_KEY at an invalid host).

Deno.test({
  name: "retrieveRelevantMemories — embedding failure path (manual verify)",
  ignore: true, // see comment above
  fn: () => {},
});
```

- [ ] **Step 2: Run the test suite — expect pass (ignored test skipped)**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno test --allow-net --allow-env supabase/functions/_shared/memory_retrieval.test.ts`
Expected: 2 PASS, 1 IGNORED. Suite green.

- [ ] **Step 3: Verify the implementation branch exists**

Confirm `_shared/memory_retrieval.ts` has this early return (from Task 2):

```typescript
if (!queryEmbedding) {
  return { memories: [], source: "no_embedding" };
}
```

If absent, add it. This is defensive — the branch SHOULD already be there from Task 2.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/_shared/memory_retrieval.test.ts
git commit -m "test(ai-proxy): memory_retrieval embedding-failure branch (deferred to manual)

Deno's lack of jest-style module mocking makes this case awkward to unit
test without restructuring the API. The early-return on null embedding
is straightforward enough that manual smoke verification (Task 9) is
sufficient."
```

---

## Task 5: RPC-failure branch

**Files:**
- Modify: `supabase/functions/_shared/memory_retrieval.test.ts`

- [ ] **Step 1: Write the failing test**

Append:

```typescript
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
  );

  assertEquals(result.source, "rpc_error");
  assertEquals(result.memories.length, 0);
});
```

- [ ] **Step 2: Run the test — expect pass**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno test --allow-net --allow-env supabase/functions/_shared/memory_retrieval.test.ts`
Expected: all non-ignored tests PASS. The implementation from Task 2 already guards on `error` and returns `rpc_error`.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/_shared/memory_retrieval.test.ts
git commit -m "test(ai-proxy): memory_retrieval rpc-error branch"
```

---

## Task 6: Wire retrieval into ai-proxy chat path

**Files:**
- Modify: `supabase/functions/ai-proxy/index.ts`

- [ ] **Step 1: Find the chat-path landmarks**

Run: `grep -n "isPro\|auth.getUser\|rate_limit\|buildSystemPrompt\|system_prompt\|snapshot_json\|channel === 'chat'\|channel === \"chat\"" "C:/Upendra/Claude Code/Fitness App/supabase/functions/ai-proxy/index.ts" | head -40`

Expected output lists the exact lines that do auth validation, rate-limit check, prompt construction, and the tool-loop call. You need to confirm two line ranges:
1. **Where `message`, `userId`, `supabaseClient` are all in scope AND rate-limit has passed** — the insertion point.
2. **Where the system prompt string is assembled** — often a `systemPrompt = \`...\` + coachingNotesBlock + \`...\`` or a template-string concatenation.

If the chat channel handler is isolated in its own function, the insertion point is at the top of that function body after rate-limit.

Record the two line numbers before editing.

- [ ] **Step 2: Add the import**

At the top of `ai-proxy/index.ts` (alongside the existing `import { getEmbedding } from "../_shared/embeddings.ts";`), add:

```typescript
import { retrieveRelevantMemories } from "../_shared/memory_retrieval.ts";
```

- [ ] **Step 3: Call retrieval after rate-limit + before prompt build**

Insert, at the landmark line identified in Step 1 (post-rate-limit, pre-prompt-build, chat channel only — guard with `if (channel === 'chat')` if the handler is shared across channels like food_text_analysis or scan_meal):

```typescript
// Phase B — semantic retrieval. Embed the user's message, look up top-5
// past memories above 0.65 cosine similarity. All failure modes return
// empty memories + a `source` code; no throws. We fall back to the
// existing full-dump coachingNotes path when memories is empty.
// Spec: docs/superpowers/specs/2026-04-24-semantic-retrieval-design.md
const retrieval = await retrieveRelevantMemories(
  supabaseClient,
  userId,
  message,
);
if (retrieval.source !== "retrieval" && retrieval.source !== "empty") {
  console.warn(
    `[ai-proxy] memory_retrieval fallback: source=${retrieval.source} user_id=${userId}`,
  );
}
```

Variable names (`supabaseClient`, `userId`, `message`) must match the identifiers already in scope at the insertion point. If they differ (e.g. `user.id`, `body.message`, `sb`), rename in the snippet — do not rename the surrounding code.

- [ ] **Step 4: Verify the file still type-checks**

Run: `cd "C:/Upendra/Claude Code/Fitness App" && deno check supabase/functions/ai-proxy/index.ts`
Expected: no new errors. Skip if `deno` not installed locally; Step 8's deploy will catch type errors server-side.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/ai-proxy/index.ts
git commit -m "feat(ai-proxy): call retrieveRelevantMemories in chat path

Embeds user message + queries match_memories via pgvector. Retrieval
result passed to prompt builder in the next commit. Fallback paths (no
embedding, RPC error, zero matches) log a warning but never throw."
```

---

## Task 7: Inject retrieval block into system prompt

**Files:**
- Modify: `supabase/functions/ai-proxy/index.ts`

- [ ] **Step 1: Find the prompt-build landmark**

From Task 6 Step 1 you already know the prompt-build region. Locate the exact concatenation or template literal that produces the final `systemPrompt` string passed to Gemini. Look for where `coaching_notes` or `coachingNotes` or `fitness_summary` appears inside the prompt.

- [ ] **Step 2: Add the formatter helper**

Near the prompt-build region (above the concatenation, same file — keep it local; not worth moving to `_shared` for one consumer), add:

```typescript
/**
 * Format retrieved memories as a bulleted block for system-prompt
 * injection. Content capped at 200 chars/line to bound prompt growth
 * (5 matches × 200 chars = 1 KB max). Empty string when no memories —
 * caller concatenates unconditionally.
 */
function formatRetrievalBlock(
  memories: Array<{
    content: string;
    source_type: string;
    created_at: string;
  }>,
): string {
  if (memories.length === 0) return "";
  const lines = memories.map((m) => {
    const date = (m.created_at ?? "").slice(0, 10); // YYYY-MM-DD
    const snippet = m.content.length > 200
      ? m.content.slice(0, 197) + "..."
      : m.content;
    return `- [${date}, ${m.source_type}] ${snippet}`;
  });
  return (
    "\n\nRelevant context from earlier conversations (semantic match):\n" +
    lines.join("\n")
  );
}
```

- [ ] **Step 3: Splice the block into the prompt**

At the exact location in the prompt assembly where `fitness_summary` ends and `coaching_notes` begins, insert `formatRetrievalBlock(retrieval.memories)`. The precise syntax depends on how the prompt is currently built — two common patterns:

**Pattern A — template literal:**
```typescript
const systemPrompt = `
  ${profileBlock}
  ${fitnessSummaryBlock}${formatRetrievalBlock(retrieval.memories)}
  ${coachingNotesBlock}
  ...
`;
```

**Pattern B — string concatenation:**
```typescript
systemPrompt += fitnessSummaryBlock;
systemPrompt += formatRetrievalBlock(retrieval.memories);
systemPrompt += coachingNotesBlock;
```

Use whichever pattern the surrounding code already uses. Do not convert from one to the other.

- [ ] **Step 4: Smoke-check the output string locally if possible**

If you have a REPL or can add a temporary `console.log(systemPrompt)` at the end of the assembly block, deploy to a staging slot and trigger a chat from the Flutter app pointed at that slot. Confirm the block appears when retrieval returns matches and is absent when it returns empty.

If staging isn't set up, skip — Task 9 will verify via a real production smoke test.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/ai-proxy/index.ts
git commit -m "feat(ai-proxy): inject retrieval block into system prompt

formatRetrievalBlock renders top-5 matches as bulleted lines with date
+ source_type tags, capped at 200 chars/line. Block omitted when
retrieval returned zero matches — prompt is byte-identical to today
in that case."
```

---

## Task 8: Deploy to Supabase

**Files:** None modified; deployment only.

- [ ] **Step 1: Emit the deployment payload**

Run from the main working directory:

```bash
cd "C:/Upendra/Claude Code/Fitness App" && node .claude/emit_payload.js ai-proxy --auto --functions-dir "C:/Upendra/Claude Code/Fitness App/supabase/functions"
```

Expected: writes `.claude/_payload_ai-proxy.json` containing the function source byte-identical to the `feat/*` branch's contents. Confirm stdout reports "ai-proxy: N files packaged" where N matches the count in `ls supabase/functions/ai-proxy/**`.

- [ ] **Step 2: Dry-run deploy**

```bash
cd "C:/Upendra/Claude Code/Fitness App" && node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy .claude/_payload_ai-proxy.json false --dry-run
```

Expected: prints the deploy metadata + a "DRY RUN — would POST to https://api.supabase.com/v1/projects/..." line. No HTTP call made.

`verify_jwt=false` matches the current deployed config — ai-proxy does manual JWT validation after the Supabase gateway (per CLAUDE.md §11 "Edge Function Auth").

- [ ] **Step 3: Real deploy**

```bash
cd "C:/Upendra/Claude Code/Fitness App" && node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy .claude/_payload_ai-proxy.json false
```

Expected: HTTP 201 + "Function deployed: ai-proxy version V" where V > current version number.

If HTTP 403 "account does not have privileges": token at `supabase/.supabase/supabase access token.txt` is for the wrong account. See CLAUDE.md deploy-workflow section.

If HTTP 400 with a Deno type-check error: fix the error in source, re-emit payload (Step 1), re-deploy.

- [ ] **Step 4: Verify deployed version is reachable**

Run:
```bash
cd "C:/Upendra/Claude Code/Fitness App" && node -e "
const fetch = require('node-fetch');
fetch('https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/ai-proxy', { method: 'OPTIONS' })
  .then(r => console.log('OPTIONS:', r.status))
  .catch(e => console.error('ERR:', e.message));
"
```

Expected: `OPTIONS: 200` or `OPTIONS: 204`. A 404 means the function didn't deploy — re-run Step 3. A 5xx means a crash in cold start — check Supabase Edge Function logs:
```bash
mcp__ba7b5e8e__get_logs (service: "edge-function")
```

- [ ] **Step 5: Commit (deploy side-effect only, no source change)**

Skip this commit — no source files changed in this task. The git state at Task 7's commit is the deployed code.

---

## Task 9: Production smoke test + retrieval verification

**Files:** None modified; verification only.

- [ ] **Step 1: Verify a test user has embeddings**

Pick a beta-tester account with chat history. Run in Supabase SQL editor (or via `mcp__ba7b5e8e__execute_sql` on project `dedsavbjuwgarrhphgnl`):

```sql
SELECT user_id, count(*) AS n_embeddings,
       min(created_at) AS first, max(created_at) AS latest,
       array_agg(DISTINCT source_type) AS types
FROM memory_embeddings
GROUP BY user_id
ORDER BY n_embeddings DESC
LIMIT 5;
```

Expected: at least one user with `n_embeddings >= 10`. Record that `user_id`.

If no user has ≥10 embeddings, the smoke test is weaker. Either (a) sign in to the Flutter app as yourself, chat 15 times with varied topics, wait an hour for embeddings to accumulate, then re-run. Or (b) proceed with a user who has 3-5 embeddings and accept limited match diversity.

- [ ] **Step 2: Directly test the RPC on the picked user**

```sql
-- Generate a query embedding manually via Gemini (use the embeddings.ts
-- logic in a Deno one-liner OR embed in a test script). For quick verify,
-- pull an existing embedding from a known note and use it as the query:
WITH q AS (
  SELECT embedding FROM memory_embeddings
  WHERE user_id = '<user_id_from_step_1>' LIMIT 1
)
SELECT content, source_type, similarity
FROM match_memories(
  '<user_id_from_step_1>'::uuid,
  (SELECT embedding FROM q),
  5,
  0.0   -- drop the threshold so we see the full ranking
);
```

Expected: first row has `similarity ~= 1.0` (self-match). Subsequent rows ranked descending. Confirms the RPC + pgvector index are healthy.

- [ ] **Step 3: Flutter app smoke test — retrieval hit**

On a dev APK pointed at prod (`flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart`):

1. Sign in as the user from Step 1.
2. Open AI Coach.
3. Ask a question that references a topic you know is in their memory (from Step 1's embeddings). Example: if the embedding history shows past discussion of knee pain, ask "how is my knee feeling in this week's training?"
4. Confirm the AI's response references specifics from earlier conversations — dates, prior advice given, specific exercises that were swapped out. If the response is generic ("take it easy, listen to your body"), retrieval either didn't run or didn't find matches.

- [ ] **Step 4: Check logs for retrieval diagnostics**

In Supabase Dashboard → Edge Functions → ai-proxy → Logs (or `mcp__ba7b5e8e__get_logs` with service `edge-function`), filter on the test user's sign-in window. Look for:

- Any `[memory_retrieval]` warn lines → if present, retrieval fell back (check the `source` code).
- Absence of warnings → retrieval succeeded.
- Any `no_embedding` → Gemini embedding API failed; check `GEMINI_API_KEY` secret.

If `rpc_error` appears: re-run Step 2's SQL to confirm the RPC works directly. If it works in SQL but fails via Edge Function, it's a permissions issue (service-role vs anon role).

- [ ] **Step 5: Flutter app smoke test — retrieval miss (fallback)**

Ask the AI something unrelated to any past conversation (example: "what's the capital of France" — coach will deflect, but this verifies no crash / latency spike when retrieval returns zero matches).

Expected: normal response, no user-visible degradation. Logs may show a `[memory_retrieval]` entry with `source=empty` — that's fine.

- [ ] **Step 6: Record outcome in memory**

Write a short memory note per the global CLAUDE.md retrospective rule:

```bash
# Create: C:/Users/upend/.claude/projects/C--Upendra-Claude-Code-Fitness-App/memory/project_semantic_retrieval_phase_b.md
```

Content: what shipped, Gemini cost observed in the first 24h, retrieval hit-rate at 24h (from logs), any tuning decisions for threshold/match_count.

Also append a one-line pointer in MEMORY.md under `## Project`.

---

## Self-Review Notes

Ran the three-point check per writing-plans skill:

**Spec coverage:**
- ✅ New helper module — Task 1 + 2
- ✅ Happy / zero / embedding-fail / rpc-fail branches — Tasks 2 / 3 / 4 / 5 (4 deferred to manual verify for pragmatic reasons, documented)
- ✅ ai-proxy integration — Tasks 6 + 7
- ✅ System prompt injection at the fitness_summary / coaching_notes boundary — Task 7 Step 3
- ✅ Error logging format + fallback behavior — Task 2 implementation + Task 6 Step 3
- ✅ Deploy + verify — Tasks 8 + 9
- ✅ Observability follow-up (retrieval hit-rate, cost) — Task 9 Step 6 (memory note)

**Placeholder scan:** No "TBD" / "add appropriate error handling" / "similar to Task N". All code blocks are complete. Two pragmatic deferrals (Task 4 embedding-mock test + Task 7 Step 4 staging smoke) are explicitly justified inline, not placeholders.

**Type consistency:** `RetrievalResult = { memories, source }` used consistently in Tasks 1, 2, 6. `Memory` type fields match the RPC's return columns (id, content, source_type, metadata, created_at, similarity). `retrieveRelevantMemories` signature stable across tasks.

**Deviation from spec:** Test file location moved from `ai-proxy/__tests__/` to co-located with source in `_shared/`. Rationale in File Structure table — helper is shared.
