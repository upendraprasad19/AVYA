---
bug_id: e6b1a4
date: 2026-07-07
batch: opt-a-rls-initplan
status: fixed
blast_radius: catastrophic
symptom: >
  The Supabase performance advisor reports 137 `auth_rls_initplan` warnings and
  5 `multiple_permissive_policies` warnings. Each flagged RLS policy calls
  `auth.uid()` bare, so Postgres re-evaluates it PER ROW instead of once per
  query — a query-CPU cost that grows with table size. Not a user-visible bug
  today (~7 users), but a real pre-scale performance debt on the last privacy
  fence; the `multiple_permissive` warnings are one redundant SELECT policy on
  `saved_diet_plans`.
concept: rls_initplan_auth_uid_wrap
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is a database RLS
  policy-shape optimization. The contract: every RLS policy that references
  `auth.uid()` wraps it as `(select auth.uid())` so the planner evaluates it
  once per query (initplan), and no table carries redundant permissive policies
  for the same command. Behavior (which rows each user may read/write) is
  IDENTICAL before and after. Pinned by the live A/B leak check
  (test/sql/rls_initplan_ab_verify.sql) + the advisor re-run.
writers:
  - "{ file: supabase/migrations/100_rls_initplan_select_wrap.sql, method: alter_policies, line: 34 } — 136 ALTER POLICY statements wrapping auth.uid()→(select auth.uid()) in USING/WITH CHECK per cmd, generated blind-textually from live pg_policies (zero transcription)."
  - "{ file: supabase/migrations/100_rls_initplan_select_wrap.sql, method: consolidate_saved_diet_plans, line: 195 } — DROP the redundant saved_diet_plans SELECT policy; the ALL policy (altered above) still gates SELECT + all writes."
readers:
  - "{ file: lib/core/services/supabase_service.dart, method: authed queries, line: 1 } — every client .from(<table>) read/write executes under these RLS policies; behavior unchanged by the wrap."
  - "{ file: supabase/functions/_shared/tools/progress/getProgressSummary.ts, method: handler, line: 49 } — a representative server reader whose per-user queries are RLS-gated by these policies (service-role paths bypass RLS and are unaffected)."
hive_key_prefix: n/a (database RLS policy shapes; no keyed Hive concept)
hive_key_formula: n/a
sync_methods: >
  n/a — no client sync path changes. RLS governs which rows the existing sync
  reads/writes may touch; that set is identical after the wrap.
restore_methods: n/a (restore reads are RLS-gated identically before/after)
cloud_table: >
  40 tables (all public tables with own-row RLS): ai_coach_interactions,
  body_measurements, client_errors, coach_memory, community_reviews, daily_steps,
  food_corrections, memory_embeddings, notifications_inbox, nutrition_log_items,
  nutrition_logs, progress_photos, promo_code_uses, rank_promotions,
  referral_codes, referral_redemptions, saved_diet_plans, scheduled_workouts,
  sleep_logs, streaks, subscriptions, telegram_connections, template_exercises,
  user_custom_exercises, user_custom_foods, user_daily_snapshots, user_preferences,
  user_profile, user_progress, user_saved_meals, user_stat_snapshots, users,
  video_renders, water_logs, weight_logs, workout_log_exercises, workout_log_sets,
  workout_logs, workout_schedule_completions, workout_templates.
cloud_columns: >
  No column added/dropped/renamed. Only the RLS policy expressions on the tables
  above change (auth.uid() → (select auth.uid())); the columns each policy
  references (user_id / id / reviewer_id / referrer_id / referee_id, and the
  EXISTS join keys log_id / template_id) are unchanged.
contract_test_path: >
  test/sql/rls_initplan_ab_verify.sql (live A/B leak check — plain / EXISTS /
  OR-shape / consolidated shapes) + must add a source-presence contract test
  asserting migration 100 exists and is listed in backups/applied_migrations.json
  once applied.
ist_handling: n/a (no date logic in RLS policy expressions)
provider_invalidations: n/a (no client state change; RLS is server-side)
telemetry_op_types: >
  No new op type. The success signal is the advisor re-run: auth_rls_initplan
  137 → ~0 and multiple_permissive 5 → 0.
cross_account_guard: >
  This change IS a cross-account guard (RLS is the last privacy fence). The A/B
  leak check (test/sql/rls_initplan_ab_verify.sql) proves user A cannot read or
  write user B's rows after the wrap, across plain / EXISTS / OR / consolidated
  policy shapes. Service-role / SECURITY DEFINER paths BYPASS RLS and are
  unaffected by the wrap.
forbidden_patterns_checked: >
  Live-verified 2026-07-07 that the rewrite is uniformly safe: 0 policies
  reference auth.jwt()/auth.role()/current_setting (so wrapping only auth.uid()
  can't change a jwt/role-dependent decision), 0 RESTRICTIVE policies, 0
  asymmetric USING-vs-WITH-CHECK, 0 already-wrapped (no double-wrap). The
  migration must NOT drop the saved_diet_plans ALL policy (that would remove
  write RLS → lockout); it drops only the redundant SELECT. The saved_diet_plans
  SELECT is EXCLUDED from the ALTER set so there is no DROP-before-ALTER
  "policy not found" ordering hazard.
proposed_fix: >
  One transactional migration (100_rls_initplan_select_wrap.sql): 136
  ALTER POLICY statements wrapping auth.uid()→(select auth.uid()) (generated
  blind-textually from live pg_policies, per-cmd clause structure preserved),
  plus DROP the redundant saved_diet_plans SELECT policy (the ALL policy still
  gates SELECT + writes). Behavior-preserving; verified by the A/B leak check +
  the advisor re-run. Uses ALTER POLICY (proven in migration 055) so there is no
  window where a policy is absent. Live apply is founder-gated (§4.3).
regression_test_planned: >
  test/sql/rls_initplan_ab_verify.sql (live A/B leak check, rollback-txn) run at
  apply time; plus a source-presence contract test that migration 100 exists +
  is recorded in backups/applied_migrations.json. The durable proof is the
  advisor re-run (auth_rls_initplan 137→~0, multiple_permissive 5→0) captured in
  the closure YAML.
touched_layers_checked:
  - "{ layer: postgres_schema, status: fixed_in_this_batch, evidence: 136 ALTER POLICY + 1 DROP POLICY in migration 100; verified 171/171 auth.uid() occurrences wrapped, 0 bare, in the executable SQL; per-cmd clause structure (USING/WITH CHECK) preserved from live pg_policies. }"
  - "{ layer: rls_policies, status: fixed_in_this_batch, evidence: all 137 auth.uid()-referencing policies wrapped; saved_diet_plans multiple_permissive consolidated (redundant SELECT dropped, ALL policy retained). Live re-pull 2026-07-07 confirmed 129 simple + 8 EXISTS = 137, 0 jwt/role/restrictive/asymmetric. }"
  - "{ layer: postgres_data, status: verified, evidence: no data change — policy-expression rewrite only; the row set each user may access is identical (proven by test/sql/rls_initplan_ab_verify.sql). }"
  - "{ layer: client_code, status: verified, evidence: no client change — RLS is server-side; existing .from() queries behave identically. }"
  - "{ layer: migrations_applied, status: not_applicable, evidence: authored not yet applied — the founder-gated apply pairs backups/applied_migrations.json in the same commit as the apply. }"
impact_analysis: >
  Pre-change: 137 RLS policies re-evaluate auth.uid() per row. Post-change: each
  evaluates it once per query (initplan) — behavior-identical, a pure query-CPU
  reduction that matters at scale. The 5 multiple_permissive warnings (a
  redundant saved_diet_plans SELECT) collapse to 0 by dropping the redundant
  policy while preserving all four verbs via the ALL policy. Risk is a bad RLS
  edit leaking cross-user data; mitigated by (a) the rewrite being behavior-
  preserving by construction — 0 jwt/role/restrictive/asymmetric policies,
  verified live — and (b) the A/B leak check across every policy shape. The
  migration uses ALTER POLICY (no absent-policy window) inside one transaction
  (all-or-nothing). Catastrophic-tier: ×2 review + B-pass + Hermes before merge;
  live apply needs its own explicit founder go.
closes-diagnose: e6b1a4
---

# e6b1a4 — RLS initplan wrap: auth.uid() → (select auth.uid()) across 137 policies

## What / why
The Supabase performance advisor flags 137 `auth_rls_initplan` warnings — every
RLS policy that calls `auth.uid()` bare, causing Postgres to re-evaluate it once
PER ROW instead of once per query. Wrapping as `(select auth.uid())` turns it
into an initplan (evaluated once). Supabase-recommended, behavior-identical, and
the biggest query-CPU win at scale. Plus 5 `multiple_permissive_policies`
warnings, all one redundant SELECT policy on `saved_diet_plans`.

## Fix
Migration `100_rls_initplan_select_wrap.sql`: 136 `ALTER POLICY` statements
(generated blind-textually from live `pg_policies`, so the OR-shape on
`referral_redemptions` and both correlated-EXISTS tables are wrapped uniformly,
and per-cmd clause structure is preserved), plus `DROP POLICY "Users see own
diet plan"` — the `saved_diet_plans` ALL policy already gates SELECT, so all
four verbs remain covered and no user is locked out. Wrapped in one transaction;
uses `ALTER POLICY` (proven in migration 055) so no policy is ever briefly absent.

## Safety (catastrophic-tier)
A bad RLS edit = cross-user data leak. This rewrite is behavior-preserving by
construction: live re-pull 2026-07-07 confirmed 129 simple + 8 EXISTS = 137, and
**0** policies reference `auth.jwt()`/`auth.role()`/`current_setting`, **0**
RESTRICTIVE, **0** asymmetric USING-vs-WITH-CHECK, **0** already-wrapped. The
`saved_diet_plans` SELECT is excluded from the ALTER set (dropped separately) so
there's no DROP-before-ALTER rollback hazard. Belt-and-braces: the A/B leak
check (`test/sql/rls_initplan_ab_verify.sql`) proves A can't see/write B's rows
across plain / EXISTS / OR / consolidated shapes, and the advisor re-run must
show `auth_rls_initplan` 137→~0 and `multiple_permissive` 5→0.

## Recurrence
First instance of an initplan-wrap migration. Related class: §2.22 (RLS/policy
mechanics) and the `REVOKE-from-PUBLIC` policy-privilege lessons — but this is a
distinct, purely-performance policy-shape change, behavior-preserving.

## Ship
×2 context-blind review of this migration design + self-triggered B-pass +
Hermes (catastrophic) + the CI merge-record. The live `apply_migration` needs
its own explicit founder go, separate from plan/merge approval (§4.3); pair
`backups/applied_migrations.json` in the same commit as the apply.
