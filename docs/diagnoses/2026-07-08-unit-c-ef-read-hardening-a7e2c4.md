---
bug_id: a7e2c4
date: 2026-07-08
batch: unit-c-ef-read-hardening
status: fixed
blast_radius: platform
symptom: >
  12 Edge-Function read sites destructure `.data` (or `await Promise.all([...])`)
  WITHOUT capturing `.error`, so a silent query failure is coerced into empty/null
  data → a silently-wrong effect, not an error. User-visible consequences:
  the AI coach reports "0 workouts done" / a wrong promotion status on a transient
  DB error (getProgressSummary, getPromotionStatus); users who DISABLED a
  notification (workout / protein / streak / subscription reminders) get pushed
  anyway when a per-user preference read errors (workout-window-closing,
  protein-gap-alert, expiry-reminder, streak-guardian); an active user gets a
  "we miss you" re-engagement nudge on a read error (re-engagement); a wrong rank
  state / blocked promotion on a transient error (evaluate-rank-promotions,
  rank_engine). §2.24 (read coerces failure → silently inert) + §2.13 (silent drop).
concept: edge_function_unchecked_read_hardening
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is an Edge-Function
  error-handling contract. The invariant: a server read that feeds a
  notification-preference gate, a coach-tool answer, or a rank computation MUST
  capture `.error` and surface it (throw for coach-tool/batch reads; per-user
  capture+skip for per-user reads in a whole-batch cron) — NEVER coerce a query
  failure into empty/default data. Codifies the §2.24 class for the EF read seam.
writers:
  - "{ file: supabase/functions/_shared/tools/progress/getProgressSummary.ts, method: handler, line: 49 } — Promise.all ×5 now captures each error + throws (tool-loop narrates honestly; never a false zero)."
  - "{ file: supabase/functions/_shared/tools/progress/getPromotionStatus.ts, method: handler, line: 94 } — 6 sequential reads now capture error + throw."
  - "{ file: supabase/functions/workout-window-closing/index.ts, method: handler, line: 162 } — batch users/templates capture + throw; per-user snapshot :192 capture + skip."
  - "{ file: supabase/functions/protein-gap-alert/index.ts, method: handler, line: 136 } — snapshots batch now captures snapErr + throws."
  - "{ file: supabase/functions/proactive-coach-promotion/index.ts, method: loadUserContext, line: 166 } — Promise.all ×3 captures error + throws."
  - "{ file: supabase/functions/expiry-reminder/index.ts, method: handler, line: 90 } — .single() PGRST116-aware: no-snapshot falls through to send (paying user), genuine error skips."
  - "{ file: supabase/functions/streak-guardian/index.ts, method: handler, line: 129 } — .single() PGRST116-aware: same guard as expiry-reminder."
  - "{ file: supabase/functions/evaluate-rank-promotions/index.ts, method: handler, line: 99 } — per-user COUNT + user_progress (:105) + rank_promotions (:136) capture + skip; pre-existing insert-error continue at :167 preserved."
  - "{ file: supabase/functions/_shared/rank_engine.ts, method: completionRateOverWindow, line: 138 } — error path returns -1.0 sentinel (gate fails, keeps earned ranks); windowWeeks<=0 guard stays 0.0."
  - "{ file: supabase/functions/re-engagement/index.ts, method: handler, line: 151 } — detection-loop 3 reads capture + skip (no mis-nudge of active users)."
readers:
  - "{ file: supabase/functions/_shared/tool-loop.ts, method: runToolLoop, line: 270 } — catches a thrown coach-tool per-tool, feeds Gemini {error:execution_failed}, continues the turn (verified — no turn poison, MAX_ROUNDS=3)."
  - "{ file: supabase/functions/_shared/rank_engine.ts, method: qualifies, line: 88 } — the completionRate gate `rate < min`; -1.0 < min → gate fails → highestQualified breaks (rank_engine.ts:106) keeping earned ranks."
  - "{ file: supabase/functions/evaluate-rank-promotions/index.ts, method: handler, line: 265 } — the outer try/catch closes cron telemetry logCronEnd(...,failed) on a batch-read throw."
hive_key_prefix: n/a (server Edge-Function error handling; no keyed Hive concept)
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: >
  reads only (no writes changed): workout_logs, workout_log_exercises, scheduled_workouts,
  weight_logs, nutrition_logs, user_profile, users, user_progress, user_daily_snapshots,
  rank_promotions.
cloud_columns: >
  no column added/dropped/renamed — the edits add `error:` to existing destructures only
  (schema-column gate: 810 refs, 0 drift).
contract_test_path: supabase/functions/_shared/tools/__tests__/unit_c_read_hardening_test.ts
ist_handling: n/a (no date-key logic changed)
provider_invalidations: n/a (server-side)
telemetry_op_types: >
  No new runtime telemetry. Per-user skips log console.error("[fn] user=X ... err"); batch
  throws surface via the existing outer try/catch → cron telemetry logCronEnd("failed").
cross_account_guard: >
  n/a (server reads are already user-scoped by .eq("user_id", …)); the fix does not relax
  any scope — it only stops coercing a failed scoped read into empty data.
forbidden_patterns_checked: >
  Every fix must SURFACE the error, never coerce to empty/default. Coach-tool + batch reads
  throw (tool-loop / outer cron catch handles it, turn/telemetry preserved). Per-user reads
  in a whole-batch cron capture + SKIP that user (console.error + continue) — NEVER a
  top-level throw (would zero the whole day's nudges) and NEVER a bare try/catch wrap around
  a swallowing read (inert — the read itself is converted to capture). Sites 6/7 `.single()`
  distinguish PGRST116 (no rows → send, preserve paying-user behavior) from a genuine error
  (skip). rank_engine error → -1.0 sentinel (not 0.0/null), keeping earned ranks.
proposed_fix: >
  Convert each of the 12 unchecked reads to capture `.error` and surface it per the
  site's kind (throw for coach-tool/invocation/batch reads; per-user capture+skip for
  per-user reads in whole-batch crons; -1.0 sentinel for the rank completionRate provider).
  Add a Deno CI job so the net-new behavioral tests actually gate at merge, and fix the
  already-red getProgressSummary maxLatencyMs test (3500→6000).
regression_test_planned: >
  supabase/functions/_shared/tools/__tests__/unit_c_read_hardening_test.ts — a fake
  ctx.sb builder chain returning {data:null, error} per site → asserts: coach tools THROW
  (never a false zero); per-user-skip sites skip exactly the failing user + still process
  the rest + never send to a preference-disabled user; sites 6/7 SEND on PGRST116 (no
  snapshot) and SKIP on a genuine error; rank_engine returns -1.0 on error. Gated by a new
  Deno CI job in .github/workflows/test.yml.
touched_layers_checked:
  - "{ layer: client_code, status: not_applicable, evidence: no Flutter client change — the client mirror (WorkoutRepository.completionRateOverWindow) is a pure-sync Hive scan with no error tuple, and client rank_service reads throw+recordNonFatal (fail-loud, not silent). EF-only scope confirmed by Review#4. }"
  - "{ layer: edge_function_code, status: fixed_in_this_batch, evidence: 10 EF/_shared files edited (12 sites); schema-column gate 810 refs/0 drift; cron adoption idioms (logCronStart/End/auth) intact in all 7 edited crons; Deno CI job added + red maxLatencyMs test fixed. }"
  - "{ layer: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: 8 EF redeploys (ai-proxy LAST — bundle holds getProgressSummary + getPromotionStatus + rank_engine; rank_engine also forces evaluate-rank-promotions); anon-Bearer boot-verify each. }"
  - "{ layer: client_to_server_contract, status: verified, evidence: tool-loop.ts:270-291 catches a thrown coach-tool and continues the turn (no poison); crons dispatch fire-and-forget once-daily (no same-tick retry / duplicate send). }"
impact_analysis: >
  Removes a class of silent-failure defects on the server read seam: the AI coach can no
  longer report a false "0 workouts / wrong promotion status" on a transient DB error (it
  narrates the failure honestly instead); users who disabled a notification are no longer
  pushed anyway when a preference read errors; an active user is no longer re-engagement-
  nudged on a read error; a transient error no longer produces a wrong rank state or blocks
  a promotion (the -1.0 sentinel keeps earned ranks). No column or write path changes — the
  edits only add error-capture to existing reads (schema-column gate 810/0). Behavior is
  identical on the healthy path; the change is what happens on a FAILED read. Ships behind no
  feature flag (the fix is strictly safer — surfacing an error vs silently coercing it), and
  the previously-unrun Deno tests now gate in CI. Deploy blast-radius platform (getProgressSummary/
  getPromotionStatus on the ai-proxy coach path); 8 EF redeploys, ai-proxy last.
closes-diagnose: a7e2c4
---

# a7e2c4 — Unit C: Edge-Function unchecked-read hardening (12 sites)

## What happened
12 EF read sites read `.data` without checking `.error`, coercing a silent query failure
into empty/null data → a silently-wrong effect. The coach reported "0 workouts" / a wrong
promotion status on a DB error; users who disabled a notification got it anyway when a
per-user preference read errored; an active user got a re-engagement nudge; a transient
error produced a wrong rank state / blocked a promotion.

## Fix (per-site, by kind)
- **Coach-tool / invocation / batch reads → `throw`** — surfaced honestly (tool-loop catches
  per-tool → Gemini narrates the error, turn continues; a batch throw hits the cron's outer
  catch → `logCronEnd("failed")`).
- **Per-user reads in a whole-batch cron → capture + skip that user** (`console.error` +
  `continue`) — never a top-level throw (would zero the whole day) and never a bare wrap
  around a swallowing read (inert; the read itself is converted).
- **Sites 6/7 `.single()` → PGRST116-aware** — a user with no snapshot row (PGRST116) falls
  through to SEND (preserves the paying/at-risk user's push); only a genuine error skips.
- **rank_engine completionRate error → `-1.0` sentinel** (gate fails, `highestQualified`
  keeps the user's earned lower ranks); the `windowWeeks<=0` guard intentionally stays `0.0`.

## Verification
- `unit_c_read_hardening_test.ts` (Deno) — per-site stubbed-failing-query behavioral test.
- New Deno CI job runs `deno test supabase/functions/` at merge (previously Deno tests never
  ran in CI — `getProgressSummary_test:27` had been red at HEAD unnoticed; now fixed 3500→6000).
- Schema-column gate 810/0; cron adoption idioms intact.

## Recurrence
Class §2.24 (EF read coerces failure → silently inert) + §2.13 (silent drop). Priors:
`d7c3f1` (completionRate 0.0-for-everyone — a nonexistent-column 42703), b9f4d2. Codifies
the class for the EF read seam. See `feedback_edge_function_selects_nonexistent_columns.md`,
`feedback_observability_silent_drop.md`, `feedback_source_grep_false_confidence.md`.
