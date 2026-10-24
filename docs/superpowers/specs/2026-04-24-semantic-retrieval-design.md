# Semantic retrieval for AI coach — design spec

**Date:** 2026-04-24
**Scope:** AVYA / ICANBEFITTER Flutter app — `supabase/functions/ai-proxy/` chat path only.

## Context

Phase A of the semantic-memory system has been running silently in production since migration `20260331000001_add_pgvector_memory.sql` (2026-03-31). Every chat turn and every nightly rolling-context summary embeds its content via `_shared/embeddings.ts` and inserts it into `memory_embeddings` — see [ai-proxy/index.ts:635](supabase/functions/ai-proxy/index.ts:635) and [rolling-context/index.ts:210](supabase/functions/rolling-context/index.ts:210).

**Phase B has never shipped.** The retrieval RPC [`match_memories(p_user_id, p_query_embedding, p_match_count, p_similarity_threshold)`](supabase/migrations/20260331000001_add_pgvector_memory.sql:70) is defined and indexed (IVFFlat, cosine) but no function calls it. The AI coach currently builds its system prompt by dumping full `coaching_notes` text into the snapshot and relying on `_compactContext` to truncate at 9.5 KB — losing old context when newer notes accumulate.

Observable symptom: the coach can't reference older conversations. A user who said "squats aggravate my knee" in March and asks about knee pain in April gets a generic reply because the March note was truncated out.

**This spec wires Phase B end-to-end, scoped to chat only.**

## Decisions (locked via AskUserQuestion, 2026-04-24)

| Decision | Value | Rationale |
|----------|-------|-----------|
| **Gating** | All users (free + PRO) | Embedding query cost is ~$0.00001/turn. PRO-gating adds branching complexity with negligible savings. Coaching fidelity is a product differentiator for both tiers. |
| **Parameters** | Top-5 @ 0.65 cosine similarity | Matches the RPC's defaults. Permissive enough to catch loose semantic matches ("knee pain" → "meniscus strain"); tight enough that unrelated notes don't bleed in. Tunable after launch. |
| **Fallback** | Recent-N coaching_notes (current behavior) | When retrieval returns 0 matches or fails, the existing full-dump + 9.5 KB-truncate path runs unchanged. Zero regression for new users, Gemini outages, or users without embeddings yet. |
| **Backfill** | Skip | Phase A started 2026-03-31. Active users have rebuilt useful memory since then. Older notes still reach the coach via the recent-N fallback. Zero ops burden. |
| **Scope** | `ai-proxy` chat path only | Morning-alert and weekly-report don't have a clean "user query" to embed against. Defer until observed value justifies defining a synthetic query for each. |

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  ai-proxy/index.ts — CHAT path                                   │
│                                                                  │
│  1. Receive message + JWT                                        │
│  2. Validate + auth + isPro lookup          (existing)           │
│  3. Rate-limit check                        (existing)           │
│  4. ★ retrieveRelevantMemories(userId, message)   ← NEW          │
│     ↓                                                            │
│  5. Build system prompt + snapshot_json     (modified, §Prompt)  │
│  6. tool-loop → Gemini                      (existing)           │
│  7. Write embedding for THIS turn           (existing — Phase A) │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│  _shared/memory_retrieval.ts  (NEW, ~60 lines)                   │
│                                                                  │
│  type RetrievalResult = {                                        │
│    memories: Memory[];    // empty array on any failure mode     │
│    source: 'retrieval' | 'no_embedding' | 'rpc_error' | 'empty'; │
│  }                                                               │
│                                                                  │
│  retrieveRelevantMemories(supabaseClient, userId, query):        │
│    Promise<RetrievalResult>                                      │
│      └─ getEmbedding(query, "RETRIEVAL_QUERY")                   │
│      └─ supabaseClient.rpc('match_memories', { ... })            │
│      └─ try/catch everywhere; log warn on error                  │
└──────────────────────────────────────────────────────────────────┘
```

## Components

### `_shared/memory_retrieval.ts` (new)

Single public function: `retrieveRelevantMemories(supabaseClient, userId, query, options?)`.

- Calls `getEmbedding(query, "RETRIEVAL_QUERY")` from the existing `_shared/embeddings.ts`. **Important:** query-side uses the `"RETRIEVAL_QUERY"` task type, not `"RETRIEVAL_DOCUMENT"` (Phase A's write-side). Gemini's embedding model is asymmetric — querying with the wrong task type degrades recall.
- Calls `supabaseClient.rpc('match_memories', { p_user_id, p_query_embedding, p_match_count: 5, p_similarity_threshold: 0.65 })`.
- Defaults are hardcoded to match the locked parameters; `options?: { matchCount?, threshold? }` supports future tuning from a different caller (e.g. weekly-report) without code changes.
- Catches every error path — Gemini timeout, pgvector error, network — and returns `{ memories: [], source: '<error code>' }`. Never throws to the caller.
- Logs a one-line warning on failure with a short request ID: `console.warn('[memory_retrieval] request_id=%s source=%s ...', id, source)` — matches the existing Edge Function error-logging pattern in CLAUDE.md §11.

Return shape:

```ts
type Memory = {
  id: string;
  content: string;
  source_type: 'conversation' | 'daily_summary' | 'coaching_note' | 'pattern_insight';
  metadata: Record<string, unknown>;  // has { date, ... }
  created_at: string;                 // ISO
  similarity: number;                 // 0.0 – 1.0
};
```

### `ai-proxy/index.ts` chat path (modified)

Two changes:

1. **After auth + rate-limit + before snapshot build:** call `retrieveRelevantMemories(supabaseClient, userId, message)`. Await the result. Keep the write-path at the end of the chat turn unchanged — we still embed and store this turn's message/response as always.
2. **In the prompt builder:** if `memories.length > 0`, insert a new block in the system prompt between `fitness_summary` and `coaching_notes`:

   ```
   Relevant context from earlier conversations (semantic match):
   - [2026-03-18, coaching_note] Complained that squats aggravate left knee; switched to leg press.
   - [2026-04-02, daily_summary] Hit a protein PR at 180g — first time clearing target.
   ...
   ```

   Format: `- [<ISO-date>, <source_type>] <content>`. One line per match. Content truncated at 200 chars per line to bound prompt growth (5 × 200 = 1 KB extra max). Ordered by similarity descending.
3. **When `memories.length == 0`:** the new block is omitted. Prompt is byte-identical to today.

The existing full-dump `coaching_notes` section stays in place in both cases. When retrieval succeeds, Gemini sees both: retrieval (prioritized, highly relevant) and recent-N (ambient freshness). When retrieval returns nothing, the recent-N is the only coaching-notes source — fully equivalent to today.

## Data flow

```
User sends chat: "my knee hurts after squats"
    │
    ▼
ai-proxy receives → auth → rate-limit OK
    │
    ▼
retrieveRelevantMemories(userId, "my knee hurts after squats")
    │
    ├─ getEmbedding("my knee...", "RETRIEVAL_QUERY") → [768 floats]
    │
    ├─ rpc('match_memories', {
    │     p_user_id: "1574f...",
    │     p_query_embedding: [768 floats],
    │     p_match_count: 5,
    │     p_similarity_threshold: 0.65,
    │   })
    │
    └─ returns:
       [
         { content: "March: squats aggravate left knee", similarity: 0.87, ... },
         { content: "April: switched to leg press for knees", similarity: 0.79, ... }
       ]
    │
    ▼
System prompt built with:
    - existing blocks (profile, fitness_summary, today_nutrition, ...)
    + NEW: "Relevant context from earlier conversations: ..."
    - existing coaching_notes block (full dump, truncated if over)
    │
    ▼
tool-loop → Gemini → response: "Good reminder — you flagged knee issues on squats in March..."
    │
    ▼
Write path (unchanged): embed this turn's message + response, insert into memory_embeddings
```

## Error handling

| Failure mode | Behavior | User-visible |
|--------------|----------|--------------|
| Embedding API 500 / timeout (> 3 s hard cap) | Skip retrieval; recent-N fallback runs. Log warn with request_id. | No — normal response, just no retrieval block. |
| pgvector RPC error | Same: skip + fall back + log. | No. |
| Zero matches above 0.65 threshold | Retrieval block omitted; recent-N fallback runs. | No. |
| User has zero `memory_embeddings` rows (brand-new account) | `match_memories` returns `[]` → same as zero matches. | No. |
| Both retrieval AND recent-N produce nothing | System prompt ships without any coaching-notes section. This is already how today's code handles a new user. | No — response is just less personalized, identical to today's new-user path. |

All failure paths share the same property: **the chat never errors because of retrieval.** Retrieval is additive. Worst case equals today's behavior.

## Testing

### Unit (`ai-proxy/__tests__/memory_retrieval.test.ts` — new)

- Success path: mock `getEmbedding` returns valid vector, mock RPC returns 2 matches → assert `{ memories.length == 2, source: 'retrieval' }`.
- Zero matches: mock RPC returns `[]` → assert `{ memories: [], source: 'empty' }`.
- Embedding failure: mock `getEmbedding` returns null → assert `{ memories: [], source: 'no_embedding' }`.
- RPC failure: mock RPC throws → assert `{ memories: [], source: 'rpc_error' }` and warning was logged.

### Integration (manual, documented in the verification section of the implementation plan)

Before deploy — using Supabase SQL editor on a Supabase preview branch:

1. Pick a beta test user ID who has ≥ 10 rows in `memory_embeddings`.
2. Call `rpc('match_memories', {...})` directly with a known query to confirm IVFFlat index is used and results come back < 100 ms.
3. Deploy ai-proxy to a dev slot; smoke-test via the Flutter app by asking the coach something that references an old topic.

### No regression checks

- Chat path latency stays ≤ +200 ms p95 (one embedding call on the critical path).
- Existing chat response shape unchanged — client needs zero updates.
- Rate-limit counter behavior unchanged (embeddings are a separate Gemini quota, not the chat rate limit).

## What this explicitly does NOT change

- Phase A write path — continues writing every chat turn's embedding as today.
- `coaching_notes` Hive / Supabase persistence — unchanged.
- `snapshot_json` structure; `_compactContext` trimming rules — unchanged.
- Client-side Dart code — zero changes.
- Rate limiting — unchanged. Embeddings don't count against chat limits.
- Morning-alert, weekly-report, any other cron-driven Edge Function — unchanged this PR, candidates for later.

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Gemini embedding API rate-limits a spike | Low (separate quota from chat completions) | Hard 3s timeout + fallback to recent-N ensures no user-visible error. Monitor `rpc_error` / `no_embedding` source counts in logs first week. |
| pgvector IVFFlat recall degrades when corpus < lists count | Low | IVFFlat recall is worst on small per-user corpora. Gets better as users accumulate. Worst-case failure mode is just "zero matches" → fallback path. |
| Retrieval pulls irrelevant context that confuses Gemini | Medium | 0.65 threshold filters weak matches. Content truncated to 200 chars/line bounds noise. Can tune down after observing responses in logs. |
| Embedding API cost explosion | Very low | $0.00001/query × ~5 chat turns/user/day × 10K users = ~$15/month ceiling. Monitor via existing per-function cost telemetry. |
| `retrieveRelevantMemories` latency pushes chat TTFB past acceptable | Low | Typical Gemini embedding + pgvector RPC latency ~150 ms p50. Hard 3 s timeout with fallback for outliers. Monitor p95 post-launch. |

## Open questions

**None.** All design decisions locked in the brainstorm above.

## Out of scope / deferred

Flagged here so they don't get lost:

- **Morning-alert + weekly-report retrieval.** Needs synthetic query ("upcoming workout", "week summary") per function. Defer until chat retrieval shows value.
- **Per-source-type weighting** (e.g. prefer `coaching_note` over `conversation`). Current design treats all source types equally. Could tune if noise shows up.
- **Retrieval quality telemetry.** Log `similarity` distribution + counts per `source` code to inform later tuning. Stretch; not blocking launch.
- **Client-side retrieval-result display** (show the user which memories were used). Transparency feature; not a launch requirement.

## Follow-on work (not this PR)

- Observe 1-week metrics: `{retrieval_hit_rate, avg_similarity, p95_latency, error_rate}` in Edge Function logs.
- If `retrieval_hit_rate < 30%` for active users, tune threshold down to 0.55 or revisit Phase A source-type mix (maybe too many short `conversation` embeddings crowding out more signal-dense `coaching_note` ones).
- If `error_rate > 2%`, audit the specific failures. Gemini timeouts handled as expected? pgvector errors recurring?

---

**Files to create / modify (summary — detail in the implementation plan):**

| File | Change | LOC estimate |
|------|--------|--------------|
| `supabase/functions/_shared/memory_retrieval.ts` | NEW | ~60 |
| `supabase/functions/ai-proxy/index.ts` | Add retrieval call + prompt-builder injection | ~25 |
| `supabase/functions/ai-proxy/__tests__/memory_retrieval.test.ts` | NEW unit tests | ~80 |

No migrations. No client changes. No dependencies added.
