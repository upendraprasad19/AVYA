---
hermes_pass_id: 2026-06-01-hermes-derive-only-coach
ran_at: 2026-06-01T14:20:00+05:30
batch_scope: working-tree on main — "derive-only AI-coach tool-surface" batch (66 files, +1284/-1868)
lens_set: [L1, L14, L21, L26, L28, L34, L37, L40]
agents_dispatched: 8
findings_total: 4
findings_by_severity: { P0: 0, P1: 1, P2: 3, false_alarm: 1 }
verdict: accepted  # founder triaged 2026-06-01: P1 + 1 P2 fixed in-batch; 2 P2 accepted as-is
---

# Hermes Pass — derive-only AI-coach tool-surface batch

8 fresh, context-blind **Opus** lens agents (one per lens), each told to find bugs (not validate),
to verify every claim with a tool, and to propose no fixes. Every finding below was **re-verified by
the consolidating agent** against the cited file:line / live schema before action (per
`feedback_audit_verifier_cannot_trust_own_subagent.md`).

## Summary
- **0 P0**, **1 P1**, **3 P2**, **1 false_alarm**.
- **5 lenses fully clean:** L1 (writer/reader drift), L14 (onConflict natural-key arbiter — verified live), L21 (Edge Function semantic correctness), L26 (CQRS/pure-function), L34 (async failure-leg telemetry), L40 (telemetry PII).
- **Fixed in-batch (this session):** the P1 (snapshot enrich-after-trim re-breach) + one P2 (SoT doc drift).
- **Awaiting founder triage:** 2 P2s — one defense-in-depth hardening (safe today), one **pre-existing** divergence outside this batch's scope.
- **No ship-blockers.**

## Findings by lens

### L1 — writer/reader drift — CLEAN
Checked the nutrition_logs payload field set, the new `_ExerciseLine` reader (verified it uses the
canonical `WorkoutReadService.bestPerSetDuration` matching its sibling `expanded_exercises.dart`
per-set semantic), `tool_dispatcher` write-intent → WriteService field mapping, `ai_snapshot_builder`
keep-set (all 19 names verified emitted), and the server `logSet.ts`/`logMealByText.ts` (diff = zod
import swap only). No name or semantic drift introduced.
- _Out-of-lens false_alarm:_ the L1 agent flagged apparent `\` syntax corruption at
  `workout_write_service.dart:422,429` + `plan_engine/models.dart:72`. **Verified FALSE** — those are
  ordinary `//` comment lines (read directly), and the full suite compiles green (+2495), which is
  impossible with a real `\` syntax error. Dismissed.

### L14 — onConflict natural-key LIVE arbiter — CLEAN (all 4 sub-claims verified live)
The c9f2a7 nutrition FK fix is sound. Verified against project `dedsavbjuwgarrhphgnl`:
1. `uniq_nutrition_logs_user_date_meal` UNIQUE on exactly (user_id, date, meal_type) exists.
2. It is **non-partial** (no WHERE) and all 3 arbiter columns are `NOT NULL` live — no 42P10 risk
   (migration 057 created it partial; migration 064 set `meal_type NOT NULL` + dropped/recreated
   non-partial — the §2.4 cure).
3. `parentPayload` omits `id` (verified Read + the `sync_nutrition_log_id_resolved_before_upsert_test`
   asserting `'id':` absent); FK `nutrition_log_items_log_id_fkey` = ON DELETE CASCADE / ON UPDATE NO
   ACTION, so omitting `id` means DO UPDATE never rewrites the PK → 23503 cannot recur; INSERT PK from
   `gen_random_uuid()` default.
4. Client guard skips (continue + telemetry) on null/empty date/meal_type; `user_id` is the non-null
   method param. Diagnose c9f2a7's tier-3 live claims independently reproduced.

### L21 — Edge Function semantic correctness — CLEAN
`geminiChatWithTools` retry loop verified **bounded** (outer `pass<2` × inner `[Flash,Flash-Lite]` =
worst-case 4 fetches then throw; `canRetry` false on pass 1; 20s wall-clock as secondary cutoff).
Success path unchanged (1 fetch, no `_sleepMs` reached, `usedFallback:false`). Classification correct
(429/5xx/empty = retriable; AbortError/timeout + non-429 4xx + SAFETY/RECITATION/PROHIBITED = not).
No TDZ/hoisting. The 4 removed tools leave **zero** dangling refs (grep across `supabase/`). zod
URL→npm swap applied uniformly (no dual-instance hazard).

### L26 — CQRS / pure-function — CLEAN
The completion-derivation write (`markCompleted`) is invoked only from `_executeLogSet` (the `log_set`
command case), never from a getter/provider build. All 7 read-only coach tools verified non-mutating
(zero `.insert(/.update(/.upsert(/.delete(/.rpc(`). `is_pr` mutated only in write paths
(`logExercise:183`, `_rescanAllPrsFor` via `editLog`/`deleteLog`). `getPromotionStatus` derives
streak/deployments in-memory and returns them (compute-don't-persist — the safe inverse).

### L28 — service-level invariants — 3 FINDINGS

**Finding 1 — P2 — guard locality (PARTIAL; defense-in-depth, safe today) → TRIAGE**
- The derive-only completion guards (rest-day `raw['type']=='rest'`, schedule-exists, already-completed)
  live in `tool_dispatcher._maybeCompleteScheduledDay` (`:331-335`), NOT in the shared writer
  `WorkoutWriteService.markCompleted`. In fact `markCompleted` deliberately *synthesizes* a
  `status:completed` schedule row when none exists (`:361-368`, for AI-coach-only / active-workout
  finish).
- **Verified:** the derive-only flow is **safe today** — its only caller passes through the guards.
  The concern is a *future* entry point (deep link, migrator, new tool) calling `markCompleted` on a
  rest date. Same shape as the `swapDays()` UI-only-guard precedent.
- **Why not auto-fixed:** moving the rest-day guard into `markCompleted` would risk breaking
  legitimate completions (UI finish of an unscheduled/rest-day workout the user *did* do). This is a
  design call (where should "don't auto-complete a rest day" live?), not a clear bug. **Founder triage.**

**Finding 2 — P2 — SoT doc drift (REAL) → FIXED IN-BATCH**
- `lib/features/train/CLAUDE.md:57` `workout_completion_status` named writer
  `WorkoutWriteService.completeWorkout` — **that method does not exist** (verified grep; the method is
  `markCompleted`; `completeWorkout` exists only on `ActiveWorkoutNotifier`). The entry also omitted the
  new coach-derivation path.
- **Fix:** corrected to `markCompleted` + documented the `_maybeCompleteScheduledDay → markCompleted`
  derivation (ADR-0012). (The `ai_coach/CLAUDE.md` `coach_derived_completion` SoT was already correct.)

**Finding 3 — P2 — second completion writer divergence (REAL, PRE-EXISTING) → TRIAGE**
- `WorkoutScheduleWriteService.markCompleted` (calendar "mark trained outside app" path) writes
  `completed_at` (ISO string) + no `wlog_<date>` row, whereas `WorkoutWriteService.markCompleted`
  (UI finish + coach derivation) writes `completed_at_ms` (int) + a `wlog_` row.
- **Verified:** the batch's claim "derived completion matches the UI finish button" **holds** (both use
  `WorkoutWriteService.markCompleted`). The calendar path's divergence is **pre-existing**, not
  introduced here, and may be intentional (a day "trained outside app" has no logged session → arguably
  no `wlog_`). Out of this batch's scope. **Founder triage** (accept-as-intentional or spawn a
  follow-up to unify).

### L34 — async failure-leg telemetry — CLEAN
`_sleepMs` is awaited (sole callsite `:462`); the final failure re-throws with model/reason logged per
attempt (greppable); `tool-loop.ts` catch `console.error`s before the apology (not silent). All
`unawaited(` callsites in `tool_dispatcher.dart` (13) + `sync_nutrition.dart` (12) wrap never-throw
telemetry helpers or futures with top-level try/catch + `recordNonFatal` sinks. New
`_maybeCompleteScheduledDay` is awaited with its own internal try/catch +
`tool_dispatch_derived_completion_failed` sink.

### L37 — empty/null-shape readers — 1 FINDING

**Finding 4 — P1 — AI-snapshot enrich-after-trim re-breach (REAL) → FIXED IN-BATCH**
- `buildAiContext` trims the BASE snapshot to 8500 (`ai_snapshot_builder.dart:165/183`), but the send
  path (`ai_coach_provider.dart:633-634`, retry `:698-699`) calls `enrichContextForQuery` **after** the
  trim, which appends **unbounded** history — `weight_trend` (`getWeightHistory(days:90)`),
  `workout_adherence` (90d), `nutrition_trend` (12w) — and returned without re-trimming (`:326`). The
  server hard-rejects `> 10000` (`ai-proxy/index.ts:547`). A 90-entry `weight_trend` (~3600 chars)
  alone blows the ~1500-char headroom, so a power user's **historical** query re-breaches the cap and
  re-bricks the coach — **the exact symptom a9c3e2 set out to fix**, just gated behind a historical
  keyword. (Verified all cited file:line + the server gate myself.)
- **Fix:** `enrichContextForQuery` now `return trimSnapshotToBudget(context, budget: 9500)` — the
  enriched payload is re-capped (500-char margin under 10000); the `keep` allowlist shrinks the
  non-critical trends first, never the core. Non-historical queries unaffected (no-op when under
  budget). Regression: `ai_snapshot_budget_trim_test.dart` gained an enriched-shape behavioral case +
  a source-grep wiring pin. a9c3e2 diagnose-doc updated with a "Follow-up" section.
- The lens also confirmed `bestPerSetDuration`, the sync null-key guard, and `_ExerciseLine` readers
  are all null/empty/wrong-type safe (NO findings there).

### L40 — telemetry PII — CLEAN
All new/changed sinks classified **NoPII**: gemini.ts retry logs carry only model/reason/pass/elapsed
(reason = HTTP status + Gemini *response*-body preview, not the user prompt); `sync_skipped_null_natural_key`
`key=$key` is the nlog Hive key `nlog_<istDate>_<mealType>_<itemsHash>` (one-way v5-UUID digest, no raw
food text — verified `nutrition_write_service.dart`); `tool_dispatch_derived_completion_failed` logs a
Dart exception only. The removed tools' clipped-error-string telemetry is gone.

## Founder triage

| # | Lens | Severity | Status | Decision needed |
|---|---|---|---|---|
| 4 | L37 | P1 | **fixed in-batch** | none |
| 2 | L28 | P2 | **fixed in-batch** (doc) | none |
| 1 | L28 | P2 | **accepted as-is** (founder 2026-06-01) | none — guard stays at the coach entry point; `markCompleted` is intentionally permissive (UI finish of a rest-day workout the user actually did must still complete). |
| 3 | L28 | P2 | **accepted as-is** (founder 2026-06-01) | none — pre-existing/intentional (a day "trained outside app" has no logged session, so no `wlog_`). |

## Action items
- [x] Fix P1 (Finding 4) — enrich re-trim + regression test + diagnose-doc follow-up — **done**.
- [x] Fix P2 (Finding 2) — SoT doc drift in `train/CLAUDE.md:57` — **done**.
- [x] Founder decision on Finding 1 (guard locality) — **accepted as-is** (2026-06-01); documented as intended design.
- [x] Founder decision on Finding 3 (pre-existing calendar divergence) — **accepted as-is** (2026-06-01); pre-existing/intentional.

## Self-evolution (per skill §7)
- date: 2026-06-01 / batch: derive-only-ai-coach / lens set: L1,L14,L21,L26,L28,L34,L37,L40 (8) / dispatch: 8 Opus parallel.
- findings: 4 real (1 P1, 3 P2) + 1 false_alarm. Real-finding signal: L28 3/3, L37 1/1; clean lenses L1/L14/L21/L26/L34/L40.
- Lens signal-to-noise: high. The one false_alarm (L1 "syntax corruption") was a render artifact, not a lens-prompt problem. No lens flagged for retirement/tuning.
- Notable: L37 caught a correct-cap-at-wrong-pipeline-point gap that 5 clean lenses + the B-pass missed — validates running L37 on any "we added a size/budget cap" change.
