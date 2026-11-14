---
hermes_pass_id: 2026-08-01-hermes-reengagement-prefilter
ran_at: 2026-08-01T07:00:00+05:30
batch_scope: working-tree (branch re-engagement-prefilter, uncommitted)
lens_set: [L1, L13, L21, L23, L31, L34, L35, L37]
agents_dispatched: 8
findings_total: 9
findings_by_severity: { P0: 0, P1: 1, P2: 3, P3: 5, false_alarm: 5 }
verdict: accepted
---

# Hermes Pass — re-engagement-prefilter (Unit 5, OI-48)

Catastrophic tier, so the Hermes pass is mandatory per §4.12.3. Run AFTER
2 independent context-blind rounds + a B-pass had already found and fixed
17 issues. 8 lenses selected for the batch shape (one new Postgres RPC +
privilege grants + a cron Edge Function rewrite): the cron/backend-relevant
subset rather than the p0-blockers default.

## Summary

- 1 P1, 3 P2, 5 P3, 5 false_alarm.
- **Ship-blockers: none.** The core change (RPC anti-join semantics, types,
  privilege narrowing, rollback safety, wiring) was independently re-verified
  correct by every lens that touched it.
- **1 finding refuted a fix from the previous round** — the single most
  valuable result of this pass (see L21/F3 below).
- 2 findings filed as new board items (OI-78 from round 1, OI-79 here).

## Findings by lens

### L34 — telemetry coverage on async failure legs (4 findings)

The highest-yield lens. It observed that the ×2 rounds and the B-pass all
assessed the batch's core tradeoff (Path B's per-user skip-and-continue →
one whole-invocation throw) on **correctness** grounds and cleared it, but
none assessed its **observability** — leaving `cron_call_log.error_summary`,
now the only durable record of a Path B failure, blind two ways.

- **F1 (P2, REAL, fixed):** `errorSummary: String(err)` yields
  `"[object Object]"` for a supabase-js `PostgrestError` (a plain
  `{message,details,hint,code}` object, not an `Error`). Catalogued
  bug-class (Hermes 2026-07-26 F3); the shipped fix existed at
  `compute-coach-signals/index.ts:92-98` and — grep-verified across all 25
  `errorSummary` callsites — **nowhere else**. Fixed here.
- **F2 (P2, REAL, fixed):** Path A and Path B failures were byte-identical
  in `cron_call_log`. Both throws now carry a `path_a …` / `path_b …` tag
  (convention from `morning-alert:809` / `rolling-context:161`).
- **F3 (P2, REFUTED by L21 — see below):** claimed a `markProactiveSent`
  throw double-counted a user into `sent` and `errors`.
- **F4 (P3, REAL, fixed):** the zero-candidate early return omitted
  `prefs_off`, so the two success shapes disagreed.

### L21 — Edge Function semantic correctness (1 finding, high value)

- **Refuted L34's F3, and the fix built on it (P2).** `markProactiveSent`
  **cannot throw**: `_shared/proactive_dedup.ts:87-95` wraps its whole body
  in try/catch and only `console.warn`s, with the doc comment *"Non-fatal on
  failure (the push already went out)"*. The double-count was unreachable;
  the identity `sent + dedup_skipped + prefs_off + errors == candidate
  count` already held. The "fix" was worse than the non-bug: a
  `mark_failures` counter could only ever be `0`, and emitting it in the log
  line + both responses would have **affirmatively asserted "dedup
  bookkeeping never failed"** while real failures are silently swallowed
  inside the helper. Fully reverted; all 9 sibling cron functions call the
  helper bare after `sent++` for the same reason.
  - The regression test was rewritten to pin the **premise**, not the shape:
    it re-reads `proactive_dedup.ts` and fails if `markProactiveSent` ever
    grows a throwing path, and separately fails if `markFailures` reappears.
  - Recurrence class: `feedback_audit_verifier_cannot_trust_own_subagent`.
    The finding quoted the call site accurately and reasoned wrongly about
    the callee; the fix shipped before the callee was read.

### L31 — cron job efficiency (1 finding, 2 refutations)

- **P1, REAL/PARTIAL → filed as OI-79.** Un-ranged PostgREST reads truncate
  at `db-max-rows` (1000), and **supabase-js does not surface the 206** —
  `error` is null, `data` is silently short. Empirically confirmed live
  (`Content-Range: 0-999/1431`). Neither Path A nor Path B paginates.
  - **Not introduced by this batch, which strictly improves it:** the old
    Path B truncated an *unordered, unfiltered* all-users fetch at 1000
    *before* filtering; the RPC returns up to 1000 *already-filtered* ones.
  - RPC leg is PARTIAL — the cap could not be empirically proven on the RPC
    code path (no anon-executable SRF here returns >1000 rows).
  - In scope and shipped: **saturation detection** on both paths (a loud
    `console.warn` naming OI-79 at >= 1000 rows). Pagination filed as OI-79
    with the `morning-alert:583-594` precedent.
- **Refuted (P3):** Path A does NOT become the next O(all users) bottleneck
  — `idx_coach_memory_dropout_risk` is usable (`Index Cond` under forced
  seqscan-off; the default Seq Scan is just an 18-row/1-page artifact).
- **Refuted (P3):** an earlier partial run claimed `last_active_at` lands as
  a Filter not an Index Cond. Re-verified: it is a **BitmapOr of two Bitmap
  Index Scans on `idx_users_last_active`** with real `Index Cond`s. The
  outer `users` scan does not grow unboundedly.

### L23 — authorization defense-in-depth on service-role paths (clean)

Verified directly rather than by subagent: `isAuthorizedCronCall` gate at
`index.ts:114` → service-role client at `:126` → RPC call at `:192`. The
gate strictly precedes both. The 5th-instance privilege sweep was run
independently in round 2 and returned exactly the 4 known functions
(`find_orphan_chat_media` + OI-78's 3); no 5th instance.

### L35 — migration reversibility / forward-compat (clean, 3 verifications)

- Forward ordering safe: live deploy is v10 (old code, grep-confirmed);
  applying 117 against it is inert (Part 1 adds an uncalled function; Part 2
  narrows a grant its only service-role caller retains).
- No collision: `find_reengagement_silent_candidates` does not exist live.
- Grant narrowing verified three independent ways (repo-wide grep,
  `cron.job` command scan, DB-trigger body scan) — `clean-orphan-media` is
  the sole caller.
- Rollback-coupling warning present and explicit.

### L1 — writer/reader drift (clean)

`RETURNS TABLE (user_id uuid, full_name text)` fixes the output column names
and types, matching `mapFallbackCandidates`' `row.user_id` / `row.full_name`
exactly. Downstream reads only the id and the name; the old code's extra
reads (`last_active_at`, `is_deleted`) are internalized into the RPC's
`WHERE` with no orphaned reader.

### L13 — migration apply pair-update (answered in round 2 as N1)

`backups/applied_migrations.json` must be updated **after** the live apply
(the entry carries a real `applied_at`/`hash`), so the sequence is
authorize → apply → ledger → commit, not commit → apply.
`applied_migrations_parity_test.dart` fails with 117 staged and no ledger
entry, which structurally enforces this ordering.

### L37 — empty/null-shape readers (clean; 3 false_alarm, 1 partial)

- Malformed-row handling in `mapFallbackCandidates`: **unreachable**.
  `users.id` is `uuid NOT NULL` live and `RETURNS TABLE` fixes the output
  keys/types, so a missing/wrong-type `user_id` is not producible. A
  non-array response `TypeError`s into the outer catch — loud.
- NULL `p_cutoff_date`/`p_cutoff_ts`: **structurally untransmittable**.
  `SILENCE_DAYS_FALLBACK` is a module literal; `new Date(NaN).toISOString()`
  throws *before* the RPC call; an omitted key → no matching PostgREST
  signature → the tagged `path_b` throw. Every degenerate variant is loud.
  - Fair sub-point, actioned: the migration COALESCE-guards the exclude
    array on a "not reachable, zero cost" rationale while leaving the
    cutoffs unguarded on the same reachability argument, without stating
    why. The asymmetry is correct (silent vs loud failure) and is now
    documented in the migration.
- null `full_name` greeting: degrades to an empty greeting, never a literal
  `"null"`. Verified clean.
- **PARTIAL (P3):** `index_test.ts` has no malformed/wrong-type row case.
  Bounded by the unreachability above — a test for a shape the writer cannot
  emit pins nothing about production behavior.

## Founder triage

All findings resolved in-batch (fixed, reverted, or filed as a board item
with its own OI number). No deferrals.

- fixed: L34 F1, F2, F4; L37's migration-comment asymmetry
- reverted: L34 F3 (false premise, verified against the callee)
- spawned: OI-79 (L31 P1 pagination), OI-78 (round-1, privilege sweep)
- false_alarm: L31 ×2, L37 ×3

## Verdict: accepted

## Self-evolution notes

- **L34 earned its place on any batch that changes an error-handling
  contract.** Its finding class ("the tradeoff was cleared on correctness
  but never on observability") is invisible to correctness-focused lenses by
  construction — 3 prior rounds all missed it.
- **Lens-vs-lens contradiction is a feature, not noise.** L21 refuting
  L34's F3 was the single most valuable output of this pass: it caught a bad
  fix that had already shipped into the working tree. Worth preserving the
  practice of running a semantic-correctness lens AFTER other lenses'
  fixes land, not only before.
- **New red flag for the code-review + hermes skills:** a finding that
  proposes hardening a *call site* must verify the *callee's* contract
  first. Recorded against `feedback_audit_verifier_cannot_trust_own_subagent`.
