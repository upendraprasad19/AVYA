---
reviewed_at: 2026-09-27T22:14:18+05:30
staged_against: aee7dfb3bf10
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — aee7dfb3bf10

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** `supabase/functions/daily-snapshot/index.ts:282-289` (watermark write inside `extractCoachingNotes`) vs `:578-585` (handler's `mergeCoachingNotes`/`mergeCoachMemoryFields` calls) — pre-remediation line numbers
- **claim:** The watermark advanced the instant Gemini returned a parseable response — before `mergeCoachingNotes` (writes `user_preferences.coaching_notes`, `user_profile`, `memory_embeddings`) or `mergeCoachMemoryFields` (writes `coach_memory`) ever ran. Neither of those two functions' primary writes had its own try/catch — only the embedding sub-step did. If either upsert threw, the exception propagated to the handler's outer catch and was logged as "non-fatal" — but the watermark was already advanced past the very rows that produced these now-lost facts, and nothing re-reads a window once its watermark clears it.
- **verification:** Confirmed by reading `daily-snapshot/index.ts` directly: `mergeCoachingNotes` (then lines 292-366) had no local try/catch around its `user_preferences`/`user_profile` upserts; the handler called it unwrapped inside the outer `catch (extractErr)` scope. No test in the original `index_test.ts` simulated a merge-write failure after a successful `extractCoachingNotes` call.
- **suggested-fix:** Move the watermark advance to run only after the merge succeeds (or there is nothing to merge).
- **status:** fixed — `extractCoachingNotes` now takes injectable `mergeCoachingNotesFn`/`mergeCoachMemoryFieldsFn` params, calls them itself inside a try immediately after a non-empty extraction, and only reaches the watermark-advance block when there was nothing to merge or both calls succeeded. Mutation-proven (mutation P in the diagnose-doc, reddens exactly the 2 new tests written for this).

## Finding 2 — P2 — guard_without_its_mirror / missing_input
- **file:line:** `supabase/functions/daily-snapshot/index.ts:255-264` (JSON.parse try/catch, pre-remediation) and `:578` (`Object.keys(result.facts)`)
- **claim:** `JSON.parse("null")` does not throw, so a syntactically valid but non-object Gemini reply (`null`, `[]`, a bare string, a number) slipped past the malformed-JSON catch. A `null` result crashed the caller's `Object.keys()` check after the watermark had already advanced (Finding 1's mechanism); a bare string silently iterated character indices into garbage `key:char` pairs written into `coaching_notes`.
- **verification:** Confirmed via `grep`: no test exercised a non-object-but-valid-JSON Gemini reply before this review.
- **suggested-fix:** Explicitly validate `typeof extracted === "object" && extracted !== null && !Array.isArray(extracted)` after JSON.parse, treating a shape failure the same as malformed JSON.
- **status:** fixed — exactly the suggested fix, implemented inside the existing try/catch (throws into the same catch as malformed JSON, same no-advance behavior). Mutation-proven (mutation O, reddens exactly the 1 new test).

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** `supabase/functions/daily-snapshot/index.ts:127-135` (`bucketStartMs`/`consume_quota` call)
- **claim:** `consume_quota`'s atomicity is scoped to one `(user_id, quota_key, window_start)` tuple. Two near-simultaneous `daily-snapshot` invocations for the same user straddling an exact 6h UTC boundary (00:00/06:00/12:00/18:00, to the millisecond) compute different `bucketStart` values independently, so both can pass the meter and both call Gemini — a narrow, low-probability double-spend the reservation pattern otherwise closes.
- **verification:** Confirmed by reading `bucketStartMs = Math.floor(Date.now() / SIX_HOURS_MS) * SIX_HOURS_MS` — each call recomputes independently from its own `Date.now()`, with no shared/locked boundary.
- **suggested-fix:** Document as an accepted residual risk given the low likelihood (pushSnapshot fires per-mutation, not on a fixed cron schedule) and bounded blast radius (at most 2 calls that day, not unbounded).
- **status:** accepted as documented residual risk, no code change — added to the diagnose-doc's `forbidden_patterns_checked`.

## Finding 4 — P3 — asserted_fixture_value (documentation accuracy)
- **file:line:** `docs/diagnoses/2026-09-27-daily-snapshot-extraction-unmetered-whole-day-reread-a2b1c7.md` (proposed_fix section)
- **claim:** The diagnose-doc described the read-window fallback as `.gt(lastExtractionAt ?? "1970-01-01")`. The actual shipped code uses a 48-hour floor (`floorIso`) compared via `Date.parse()`, never an epoch string literal.
- **verification:** Confirmed via `grep -n "1970\|48 \* 60\|floorIso"` across both files — the doc had the epoch literal, the code has the 48h floor and no `1970` anywhere.
- **suggested-fix:** Fix the doc's prose to describe the 48h floor accurately.
- **status:** fixed — doc corrected in place, with the correction called out explicitly (per this repo's own "verify by grep, not by citation" convention) rather than silently rewritten.

## Finding 5 — P3 — function_exception_swallow (pre-existing, retained through rewrite)
- **file:line:** `supabase/functions/daily-snapshot/index.ts:96` (pre-remediation)
- **claim:** `const { data: convos } = await supabase.from(...)` never destructured `error`. A genuine query failure fell into the same branch as "nothing new since the watermark," with no log — every other failure branch in this function logs.
- **verification:** Confirmed via `grep -n "const { data: convos }"` — no `error` in the destructure; pre-existing shape, unchanged by this batch's rewrite of the surrounding query.
- **suggested-fix:** Destructure `error: convosError` and log it before the empty-check.
- **status:** fixed — exactly the suggested fix. Mutation-proven (mutation Q, reddens exactly the 1 new test).

## Finding 6 — P3 — asserted_fixture_value
- **file:line:** `supabase/functions/daily-snapshot/index_test.ts:313-364` (pre-remediation) — `runFilters`'s `gt`/`lte`/`order` cases
- **claim:** The in-memory test fixture's `gt`/`lte` operators do plain string comparison, not real Postgres `timestamptz` comparison — the production code's own comment says its cross-format comparison must go through `Date.parse()`, but the fixture standing in for the query does raw string comparison for row-filtering.
- **verification:** Confirmed the gap exists exactly as described. Then verified the reviewer's OWN suggested fix against the production code's actual rationale for using `Date.parse()`: that comparison is specifically a cross-format one (Postgres-native text vs JS `toISOString()` output); `Date.parse()` truncates to millisecond precision. Switching `runFilters`'s row-level `gt`/`lte` to `Date.parse()` would DEFEAT the microsecond-precision exclusion this whole fix is about — the fixture would become LESS faithful to real Postgres semantics, not more, for the exact scenario the "row exactly AT the watermark (microsecond-identical)" test proves.
- **suggested-fix:** REJECTED as stated (would introduce a regression). Documented instead.
- **status:** fixed differently than suggested — added a header comment on `runFilters` explaining why raw string comparison is correct here (given consistent-format inputs via `pgTs()`) and naming the real hazard (a future test mixing timestamp formats within one comparison), rather than adopting the reviewer's `Date.parse()` suggestion.

## Founder triage notes

All 6 findings verified against live code (not taken on the reviewer's word), 3 real bugs fixed (1, 2, 5), 1 doc-accuracy fix (4), 1 accepted residual risk documented (3), 1 finding's own suggested fix rejected after verification proved it would regress microsecond-precision fidelity, with the actual gap closed via documentation instead (6). Full detail, including mutation proofs for every new fix, in `docs/diagnoses/2026-09-27-daily-snapshot-extraction-unmetered-whole-day-reread-a2b1c7.md`'s "B-pass remediation" section.
