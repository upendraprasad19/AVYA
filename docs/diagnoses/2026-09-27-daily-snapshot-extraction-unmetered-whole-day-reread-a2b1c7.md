---
bug_id: a2b1c7
date: 2026-09-27
batch: single-owner-a2b-1 (single-owner remediation batch, docs/plans/2026-09-26-single-owner-batch-a.md — a2b-1, converged in review round 3 with zero material findings against this scope)
status: fixed
blast_radius: platform
symptom: |
  `daily-snapshot/index.ts`'s `extractCoachingNotes` (before this fix) had
  three defects, all present after a2a's own fix to the same function landed
  (diagnose c3f8e6, which fixed a DIFFERENT set of problems in the same
  extraction path — untestability, missing kill switch, privacy-gate
  ordering — and explicitly left this batch's scope untouched):
    1. **Unmetered.** No `consume_quota` call anywhere in the extraction
       path. Every run that decided to extract (per the wall-clock
       `isStale` check below) spent a real Gemini Flash call with nothing
       counting or capping it — the exact OI-162 unmetered-Gemini-call
       shape (most recently recurring at `ai-proxy`'s `prediction` type,
       diagnose 125b81, 2026-09-26).
    2. **Whole-day re-read via a wall-clock guard, not a watermark.** The
       pre-fix `isStale` check was `now - lastExtractionAt > 6h`, and the
       read itself queried the CURRENT day's conversations unconditionally
       (`.gte(dayStartIso)`), not "since the watermark". Once `isStale`
       tripped, EVERY conversation from that day — including ones already
       extracted in an earlier run the same day — was re-read and
       re-submitted to Gemini. Read cost scaled with the day's message
       count on every stale tick, not with new messages since the last run.
    3. **`mergeCoachMemoryFields`'s own `last_extraction_at` write used
       `DateTime`... no — this file is server-side Deno, not Dart.** The
       server wrote `last_extraction_at: new Date().toISOString()`, which
       IS UTC-correct on the server side; the actual client-side root cause
       of a SEPARATE but related symptom (a future-dated `in_app_orphan` row
       that a naive watermark bound would then wrongly exclude — plan
       round-2 finding) was `DateTime.now().toIso8601String()` MISSING
       `.toUtc()` at three client call sites: `coach_interaction_repository.dart:53,121`
       and `sync_coach.dart:208`. `DateTime.now()` returns device-LOCAL
       time; `.toIso8601String()` on a local `DateTime` still prints a
       bare-offset-less string that downstream Postgres/JS readers parse as
       UTC. A device in IST (+5:30) writes a `created_at` that reads as
       5.5 hours in the FUTURE to any UTC-anchored consumer — which is
       exactly the shape a microsecond-precision watermark bound needs to
       reason about correctly (a future-dated row must be EXCLUDED from the
       current read, not silently included past the bound, and re-included
       forever on every subsequent run since it always looks "in the
       future" relative to a correctly-advancing watermark).
  Found during the a2 brainstorm/review cycle (converged plan round 3,
  after two prior rounds each found the same recurrence class from a
  different angle) and re-confirmed by reading the live code before
  touching it, per §4.1.5.
concept: coaching_notes / coach_memory extraction (same concept as c3f8e6;
  this fix is scoped to the read-window + metering half c3f8e6 explicitly
  deferred to this unit, not a re-litigation of c3f8e6's own fix)
sot_registry_entry: coaching_notes (writer citation for mergeCoachingNotes
  repointed to its new post-rewrite line range in this same commit — see
  Related below)
related_bugs:
  - 125b81 — ai-proxy prediction type had no consume_quota call at all before
    OI-162's reservation pattern was applied to it; same unmetered-call shape,
    different endpoint.
  - d3a7f1 / e7c4b2 / f4a2d8 / c4f9e2 / f2c8d5 / a9d4e7 — the OI-162 slice
    family: several other quota readers were secretly counting a table
    `rolling-context` prunes nightly, silently resetting caps that appeared
    to work. Not the identical defect here (this path had NO counting
    mechanism at all, not a broken one) but the same root class: an
    AI-calling endpoint whose spend was not durably, atomically metered.
  - c3f8e6 — a2a's own fix to the SAME function, same day, explicitly
    scoped OUT this unit's concerns (see its `forbidden_patterns_checked`)
    so the two units could converge independently without one blocking
    the other.
recurrence: "yes — unmetered AI-endpoint spend (OI-162 class), 3rd+ instance
  in this app in one week (125b81, then this). Applying the established
  reservation pattern (consume_quota BEFORE the paid call, not after) exactly
  as ai-media-proxy/delete-account/verify-payment already do."
writers:
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes — consume_quota('coach_extraction', <6h UTC-epoch-floor bucket>, cap=1) called BEFORE geminiChatFn, ordered ahead of the Gemini call so a capped run never pays for a model call it can't keep (reservation pattern)", line: 76 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes — watermark-bounded read: .gt(readFromIso) (lastExtractionAt or a 48h floor, whichever is later), .lte(readStartIso) upper bound captured BEFORE the Gemini call so a message that arrives mid-extraction is picked up next run, not dropped", line: 76 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "extractCoachingNotes — tri-state ExtractionResult ({ok:true, facts} incl. empty, or {ok:false}); NOW OWNS THE MERGE STEP TOO (B-pass finding 1, 2026-09-27): calls mergeCoachingNotesFn + mergeCoachMemoryFieldsFn (injectable) itself, and only advances the watermark — via a non-fatal upsertCoachMemory write to coach_memory.last_extraction_at — when there was nothing to merge OR the merge succeeded. A merge failure now correctly blocks the advance instead of the pre-remediation design, which advanced unconditionally on any parseable Gemini response BEFORE the (then handler-owned, unguarded) merge call could even run.", line: 76 }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method_or_widget: "saveInteraction / saveUserMessagePending — created_at now DateTime.now().toUtc().toIso8601String()", line: 53 }
  - { file: lib/features/ai_coach/repositories/coach_interaction_repository.dart, method_or_widget: "updateInteractionWithResponse (or sibling write path) — created_at now .toUtc()'d", line: 121 }
  - { file: lib/core/services/sync/sync_coach.dart, method_or_widget: "_syncCoachInteractions — in_app_orphan fallback upsert's created_at now .toUtc()'d", line: 208 }
readers:
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "handler() — reads Object.keys(result.facts).length > 0 to set the response's coaching_extracted flag ONLY; no longer calls mergeCoachingNotes/mergeCoachMemoryFields itself (B-pass finding 1 moved that ownership into extractCoachingNotes)", line: 628 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "DIGEST_KEYS — new coach_extraction entry, kind: 'subday' (totals only, matching delete_account/verify_payment precedent)", line: 1 }
  - { file: supabase/functions/daily-snapshot/index.ts, method_or_widget: "mergeCoachMemoryFields — no longer writes last_extraction_at itself (deleted); its own `> 0` (was `> 1`) guard now fires on a single-fact patch with no timestamp key, since the timestamp write moved to the non-fatal watermark-advance path above", line: 433 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: coach_memory
cloud_columns: [user_id, last_extraction_at]
contract_test_path: supabase/functions/daily-snapshot/index_test.ts
ist_handling:
  - "The 6h metering bucket is deliberately a UTC-epoch floor (bucketStartMs = Math.floor(Date.now() / SIX_HOURS_MS) * SIX_HOURS_MS), NOT IST-aligned, matching the delete-account/verify-payment precedent for sub-day rate-limit buckets — a sub-day bucket has no user-visible reset moment, so there is nothing to align to IST midnight for."
  - "The watermark itself is a raw Postgres timestamptz string, never round-tripped through a JS Date — new Date(pgString).toISOString() truncates to millisecond precision and would silently re-admit a row whose real created_at differs from the stored watermark by microseconds only. The watermark advances to convos[convos.length-1].created_at's RAW STRING, relying on Postgres's own .order() for correct chronological placement."
provider_invalidations: []
telemetry_op_types: []
cross_account_guard: Not applicable — server-side gate on the JWT-derived user id only; no client-side account state read or written by the metering/watermark change. The two .toUtc() sites are per-user Hive writes with no cross-account exposure.
forbidden_patterns_checked:
  - "recomputing the watermark as max(created_at) over the read set instead of trusting the query's own .order() + last-element read — rejected per the plan's explicit mutation requirement (item 15): a recompute masks the exact class of bug (out-of-order rows) the watermark exists to be robust against, and the query's sort order IS the source of truth here."
  - "folding the -1 (quota exhausted) and RPC-error branches into one 'skip extraction' path — kept as two distinct code paths with two distinct tests (item 16), since a future change to one must not silently change the other's behavior."
  - "advancing the watermark on a Gemini failure so a permanently-broken Gemini call doesn't get retried every run forever — rejected: a permanently-broken call needs to keep being visible as a retry candidate (and the meter, not the watermark, is what actually bounds the retry cost to 1 per 6h), not silently marked 'done'."
  - "distributed-locking or a shared/coordinated bucket boundary to close the sub-second 6h-boundary double-consume race (B-pass finding 3, 2026-09-27, ACCEPTED as a residual risk, no code change) — two daily-snapshot invocations for the SAME user whose bucketStartMs computations straddle an exact 6h UTC boundary (00:00/06:00/12:00/18:00, to the millisecond) can both pass consume_quota (different window_start values, no row conflict) and both call Gemini. Rejected a fix: pushSnapshot fires per-mutation, not on a fixed cron schedule, so the odds of two calls from the same user landing in that exact sub-second window are low; the atomicity guarantee this reservation pattern actually needs — no unbounded double-spend — still holds, since a run that DOES win two buckets in a row is still capped at 2 calls that day, not unbounded. Distributed locking to close a sub-second edge case is not proportionate here; documenting it is."
proposed_fix: |
  - New module-scope consts: `COACH_EXTRACTION_QUOTA_KEY = "coach_extraction"`,
    `COACH_EXTRACTION_CAP = 1`, `SIX_HOURS_MS`.
  - New `type ExtractionResult = { ok: true; facts: ExtractedFacts } | { ok: false };`
    — the tri-state contract items 12 (Gemini-failure) and its round-2-added
    third state (malformed JSON) both need, so `!rawText` and a JSON.parse
    catch both return `{ok:false}` rather than one silently reading as
    `ok:true` with empty facts.
  - `extractCoachingNotes` rewritten: reads conversations `.gt(readFromIso)`
    and `.lte(readStartIso)` (captured before the Gemini call), where
    `readFromIso` is `lastExtractionAt` if it parses to later than a
    **48-hour floor** (`floorIso = new Date(Date.now() - 48*60*60*1000)`,
    compared via `Date.parse()` on both sides — a genuine cross-format
    comparison, `lastExtractionAt` being Postgres-native text vs `floorIso`
    being JS `toISOString()` output), else the floor itself — **corrected
    2026-09-27, B-pass finding 4**: this section originally described the
    fallback as a bare `?? "1970-01-01"` epoch, which was never what shipped;
    a 48h floor bounds how far back a long-offline user's first-ever read
    scans, an unbounded epoch fallback would not have. Filters out
    `app_event`-shaped `user_message` content even inside an allowlisted
    channel, then calls `consume_quota(COACH_EXTRACTION_QUOTA_KEY,
    <6h bucket>, COACH_EXTRACTION_CAP)` BEFORE `geminiChatFn` — `-1` or an RPC
    error both skip Gemini entirely and return `{ok:false}` (no watermark
    advance); only a positive integer proceeds to the Gemini call.
  - Old `isStale` wall-clock guard deleted; the handler's extraction block
    now calls `extractCoachingNotes(supabaseClient, userId,
    existing?.last_extraction_at ?? null)` unconditionally (the meter is now
    the sole gate on call frequency) and reads `result.ok &&
    Object.keys(result.facts).length > 0` only to set the response's
    `coaching_extracted` flag — **B-pass finding 1 (2026-09-27) moved the
    actual merge calls OUT of the handler and INTO `extractCoachingNotes`**
    (see below), so the handler no longer calls
    `mergeCoachingNotes`/`mergeCoachMemoryFields` directly at all.
  - `mergeCoachMemoryFields`'s own `patch.last_extraction_at = new
    Date().toISOString();` line deleted (the watermark advance now happens
    via a separate, non-fatal `upsertCoachMemory` call in the same commit
    as a successful extraction, decoupled from whether any FACT patch
    exists at all) — paired, in the same change, with widening the
    sibling `if (Object.keys(patch).length > 1)` guard to `> 0`, since a
    single-fact patch with no timestamp key would otherwise never clear
    the old `> 1` threshold.
  - **B-pass finding 1 (2026-09-27, P1) — merge-gates-watermark redesign.**
    The first draft advanced the watermark inside `extractCoachingNotes`
    the instant Gemini returned a parseable response, THEN returned to the
    handler, which called `mergeCoachingNotes`/`mergeCoachMemoryFields`
    afterward with no guard on the first call. A `mergeCoachingNotes`
    write failure (its two structural upserts had no local try/catch)
    propagated to the handler's outer catch and was logged "non-fatal" —
    but the watermark had ALREADY moved past the rows that produced those
    facts, so they were lost permanently (no re-read path). Fixed:
    `extractCoachingNotes` now takes `mergeCoachingNotesFn`/
    `mergeCoachMemoryFieldsFn` (injectable, same DI pattern as
    `geminiChatFn`), calls them itself inside a `try` immediately after a
    non-empty extraction, and only reaches the watermark-advance block
    when there was nothing to merge OR both calls succeeded. Either merge
    throwing returns `{ok:true, facts}` WITHOUT advancing — the next
    bucket's run re-reads (and re-meters, and re-merges — merges are
    idempotent upserts) the same rows.
  - **B-pass finding 2 (2026-09-27, P2) — non-object Gemini reply.**
    `JSON.parse("null")` does not throw, so a syntactically valid but
    wrong-shaped Gemini reply (`null`, `[]`, a bare string, a number —
    `jsonMode: true` does not guarantee an object) slipped past the
    malformed-JSON catch as `extracted = null`/etc., either crashing the
    caller's `Object.keys()` check after the watermark had already
    advanced, or (for a string) silently iterating character indices into
    garbage `key:char` pairs written into `coaching_notes`. Fixed: after
    `JSON.parse`, explicitly reject `typeof parsed !== "object" || parsed
    === null || Array.isArray(parsed)`, throwing into the SAME catch as
    genuinely malformed JSON — same discriminant, same no-advance behavior.
  - **B-pass finding 5 (2026-09-27, P3) — silent read-error branch.**
    `const { data: convos }` never destructured `error`, so a genuine
    query failure (RLS, connection blip) fell into the identical
    `!convos` branch as the ordinary "nothing new since the watermark"
    case, with no log at all — every OTHER failure branch in this
    function logs. Pre-existing (unchanged shape from before this batch's
    rewrite), but this rewrite touched every line around it without
    closing the gap. Fixed: destructure `error: convosError`, log it
    distinctly when present, before the empty-check.
  - Three client-side `.toUtc()` fixes (`coach_interaction_repository.dart:53,121`,
    `sync_coach.dart:208`) so a device's local-clock `created_at` never
    reads as future-dated to a UTC-anchored watermark comparison.
  - `founder_digest_content.ts`'s `DIGEST_KEYS` gained a `coach_extraction`
    entry (`kind: "subday"`, no `cap` field — totals-only, matching the
    `delete_account`/`verify_payment` precedent) so the founder digest
    surfaces this new metered key instead of silently omitting it.
  - `usage_quota_ledger_writer_to_reader_test.dart`'s direct-`consume_quota`-caller
    allowlist gained `daily-snapshot/index.ts` (this endpoint has no
    Postgres trigger to hang the check off, same shape as
    `_shared/prediction_handler.ts`'s existing entry).
regression_test_planned: |
  18 new Deno tests in daily-snapshot/index_test.ts (14 genuine behavioral —
  10 from the original a2b-1 draft + 4 from the B-pass remediation below —
  via a dynamic-import-with-pre-set-env-vars pattern plus an in-memory
  Postgres-filter-engine fixture, and 4 source-grep/absence checks — see
  Mutation proof below for the full list and CLAUDE.md's supabase/functions
  section for why daily-snapshot specifically can now carry behavioral
  coverage where 4 sibling functions still cannot). Plus one new dedicated
  Dart test (`founder_digest_caps_mirror_test.dart`, pinning p_limit=1 for
  coach_extraction, since the general mirror test structurally skips cap
  validation for sub-day keys) and one allowlist-line addition in
  `usage_quota_ledger_writer_to_reader_test.dart`.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ clean (0 warnings/errors, 45 pre-existing unrelated infos); flutter test on all 5 CoachInteractionRepository-touching files (37/37) + all 13 sync_coach.dart/in_app_orphan-referencing files (77/77, 0 failures) — no regression from the two .toUtc() sites or the sync_coach.dart:208 fix." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "coach_chat_history_replay_writer_to_reader_test.dart and coach_interactions_writer_to_reader_test.dart, both touching the exact write paths edited, green." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none supabase/functions/daily-snapshot/index.ts clean; deno test --no-check --allow-all --node-modules-dir=none supabase/functions/daily-snapshot/ — 27/27 green. Not yet deployed; deploy needs its own founder go per §4.3, tracked with the rest of this batch's deploy list." }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "This function touches Postgres tables only, no Storage." }
  - { tier: 12, name: "Client → server contract", status: verified, evidence: "The 200 response shape is unchanged; coaching_extracted is now result.ok && Object.keys(result.facts).length > 0, semantically equivalent to the pre-fix extractedFacts !== null for every case that previously returned non-null (empty {} was previously falsy-checked the same way downstream)." }
impact_analysis: |
  No user-visible behavior change for the extracted-content itself (same
  facts get extracted, same merge into coaching_notes/user_profile). What
  changes: (1) a stale-but-not-yet-6h-old run no longer re-reads and
  re-bills the whole day's conversations on every tick — cost now scales
  with genuinely-new messages since the watermark, not with the day's
  total; (2) the extraction path is now durably capped at 1 Gemini call per
  6h per user, closing an unmetered-spend gap that had no cap at all before;
  (3) a device with local-clock skew (e.g. IST) no longer risks writing a
  future-dated in_app_orphan row that a watermark comparison would
  perpetually mis-handle. The founder digest gains one new visible line
  (coach_extraction totals); no other cron/alert surface is affected.
---

# daily-snapshot coaching-notes extraction: unmetered Gemini spend + whole-day re-read (OI-162 recurrence)

## Mutation proof (rule 21)

Each mutation applied by exact-string replacement (anchor confirmed present
via `grep -c` before mutating), full `daily-snapshot/index_test.ts` Deno
suite run, then reverted byte-for-byte and re-confirmed clean (`deno check`
clean, all 27 tests green) before moving to the next mutation.

| Mutation | Red |
|---|---|
| A — reverted the microsecond-precision watermark bound (`.gt(lastExtractionAt)`) to a coarse whole-day `.gte(dayStartIso)` bound | 1/27 (`a row exactly AT the watermark (microsecond-identical) is NOT re-read`) |
| B — removed the `.lte(readStartIso)` future-dated exclusion | 1/27 (`a future-dated row (beyond the read-start bound) is excluded...`) |
| C — dropped the `app_event`-shaped `user_message` content filter | 1/27 (`an app_event-shaped user_message is excluded even inside an allowlisted channel`) |
| D — made an empty `{}` extraction NOT advance the watermark (`if (Object.keys(facts).length > 0)` guard around the watermark write) | 1/27 (`an empty {} extraction is ok:true and still advances the watermark`) |
| E — round-tripped the watermark advance through `new Date(...).toISOString()` instead of the raw last-row string | 1/27 (`advances the watermark to the RAW last-row string, byte-exact...`) |
| F — collapsed the `!rawText` branch to `{ok:true, facts:{}}` instead of `{ok:false}` | 1/27 (`a Gemini call failure (!rawText) is ok:false and does NOT advance the watermark`) |
| G — removed the malformed-JSON `catch` block's `{ok:false}` return (let it throw uncaught / fall through to `ok:true`) | 1/27 (`a malformed (non-empty, unparseable) Gemini reply is ok:false and does NOT advance the watermark`) |
| H — changed the `-1` quota-exhaustion branch to proceed to Gemini anyway | 1/27 (`quota-meter exhaustion (-1) skips Gemini and does NOT advance the watermark`) |
| I — changed the RPC-error branch to fail OPEN (proceed to Gemini) instead of closed | 1/27 (`a quota-meter RPC error fails CLOSED...`) |
| J — reverted `p_limit` argument from `1` to `4` | 1/27 (`the quota meter is called with p_limit=1...`, plus the separate Dart `founder_digest_caps_mirror_test.dart` pin) |
| K — moved the `consume_quota` call to AFTER the `geminiChatFn` call | 1/27 (`the quota meter is called with p_limit=1 (item 8/9), and BEFORE the Gemini call (item 13)`) |
| L — reverted `mergeCoachMemoryFields`'s guard from `> 0` back to `> 1` | 1/27 (`a single-fact patch (no timestamp key) still triggers upsertCoachMemory (item 11)`) |
| M — restored `mergeCoachMemoryFields`'s deleted `patch.last_extraction_at = new Date().toISOString();` line | 1/27 (`mergeCoachMemoryFields no longer writes last_extraction_at (source presence/absence check)`) |
| N — reverted `sync_coach.dart:208`'s `.toUtc()` | N/A — this is a client-side Dart fix; proven by removing `.toUtc()` and re-running `flutter test test/contracts/sync_coach_cross_channel_dedup_test.dart` plus the other 12 candidate files: none of the 13 existing files assert on timezone offset directly (confirmed no false-negative masking), so this fix's own correctness rests on the documented root-cause read (`DateTime.now()` is local, `.toIso8601String()` on a local `DateTime` carries no offset) rather than a dedicated new assertion — flagged here rather than silently assumed proven. |

Each mutation reddened exactly the test(s) written for that behavior and no
others — confirmed by diffing the full 27-line pass/fail summary against
the clean baseline for each of the fourteen runs (A–M via `deno test`; N via
`flutter test`).

## Related

Third recurrence this week of the OI-162 unmetered-AI-call class (125b81,
then several already-metered-but-secretly-broken slices, now this
never-metered-at-all instance). The reservation pattern (consume BEFORE the
paid call) is by now the established idiom across `ai-media-proxy`,
`delete-account`, `verify-payment`, `ai-proxy`'s `prediction` type, and now
`daily-snapshot`'s extraction — any NEW AI-calling endpoint should reach for
this pattern by default rather than rediscovering the need for it.

Same file, same day, as a2a's own fix (c3f8e6) — deliberately scoped apart
(c3f8e6 fixed testability/kill-switch/privacy-ordering; this fixes
metering/read-window/timezone) so the two units could each converge
independently in review without one blocking the other, per the plan's
explicit split rationale.

## B-pass remediation (context-blind review, agent aa7af51e1cbfa6747)

Six findings, all verified against live code before acting (neither taken
on the reviewer's word alone) — three real bugs fixed in this same commit
(P1 finding 1, P2 finding 2, P3 finding 5), one documentation inaccuracy
fixed (P3 finding 4, already folded into `proposed_fix` above), one
accepted residual risk documented rather than code-fixed (P3 finding 3,
already folded into `forbidden_patterns_checked` above), and one finding's
own suggested fix REJECTED after verification proved it would regress the
very property it claimed to protect (P3 finding 6):

- **Finding 1 (P1, guard_without_its_mirror — CONFIRMED, fixed).** See
  `proposed_fix` above. Root cause: the watermark advance and the merge
  call lived in different functions with no ordering guarantee between
  them, so "Gemini succeeded" and "the facts actually got persisted" were
  silently conflated.
- **Finding 2 (P2, guard_without_its_mirror / missing_input — CONFIRMED,
  fixed).** See `proposed_fix` above.
- **Finding 3 (P3, guard_without_its_mirror — CONFIRMED, accepted residual
  risk, no code change).** See `forbidden_patterns_checked` above.
- **Finding 4 (P3, asserted_fixture_value / documentation accuracy —
  CONFIRMED, fixed).** This diagnose-doc's own `proposed_fix` section
  described the read-window fallback as `?? "1970-01-01"`; the shipped
  code has never used that literal — it uses a 48h floor compared via
  `Date.parse()`. Corrected in place above. Exactly the "verify by grep,
  not by citation" class this repo's own common-pitfalls table warns
  about, caught by the review rather than by re-deriving the doc from the
  code.
- **Finding 5 (P3, function_exception_swallow — CONFIRMED, fixed).** See
  `proposed_fix` above.
- **Finding 6 (P3, asserted_fixture_value — CONFIRMED the gap, REJECTED
  the suggested fix, documentation instead).** The reviewer correctly
  found that `index_test.ts`'s in-memory `runFilters` compares
  `gt`/`lte`/`order` via raw string `>`/`<=`, not `Date.parse()` — and
  suggested switching to `Date.parse()` to match "what real Postgres does
  and what the production code itself insists on." Verified this
  suggestion against the actual reason the production code uses
  `Date.parse()` in ONE specific place (`readFromIso` vs `floorIso`,
  described in Finding 4's correction above): that comparison is a
  genuine CROSS-FORMAT one (Postgres-native text vs JS `toISOString()`
  output). `Date.parse()` TRUNCATES TO MILLISECOND precision — switching
  `runFilters`'s row-level `gt`/`lte` to it would DEFEAT the exact
  microsecond-precision exclusion the "a row exactly AT the watermark
  (microsecond-identical) is NOT re-read" test exists to prove, making
  the fixture LESS faithful to real Postgres `timestamptz` comparison,
  not more. Fixed instead with a header comment on `runFilters`
  explaining this precisely, so a future well-intentioned "fix" doesn't
  make the same mistake the reviewer's suggestion would have.

### Mutation proof — B-pass remediation (new tests)

Same protocol as above: exact-string mutation (anchor confirmed present),
full `daily-snapshot/index_test.ts` Deno suite run, reverted byte-for-byte,
re-confirmed clean (`deno check` clean, all 31 tests green) before the next.

| Mutation | Red |
|---|---|
| O — replaced the object-shape guard (`if (typeof parsed !== "object" \|\| parsed === null \|\| Array.isArray(parsed))`) with `if (false)` | 1/31 (`a syntactically-valid but non-object Gemini reply...`) |
| P — removed the early `return { ok: true, facts: extracted };` inside the merge-failure catch block (so a merge failure fell through to the watermark-advance code below it) | 2/31 (`a mergeCoachingNotesFn failure does NOT advance the watermark...`, `a mergeCoachMemoryFieldsFn failure ALSO does NOT advance the watermark...`) |
| Q — deleted the `if (convosError) { console.error(...) }` branch entirely | 1/31 (`a genuine conversation-read error is LOGGED...`) |

Each mutation reddened exactly the test(s) written for that fix and no
others — confirmed by diffing the full 31-line pass/fail summary against
the clean baseline for each of the three runs.
