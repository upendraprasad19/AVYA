---
scope: migrations
parent: ../../CLAUDE.md
created: 2026-05-18
updated: 2026-05-21
status: active
---

# Supabase Migrations — Local Rules

> This file is auto-loaded by Claude Code when working under `supabase/migrations/`.
> Root CLAUDE.md (../../CLAUDE.md) contains process invariants and a pointer index.

## Migration header convention

Every new migration file MUST begin with the following four-line header
(in this exact order, as SQL comments). The pre-commit hook and any future
gate scripts grep for these tags — keep the casing and the colon-space.

```sql
-- Intent: <one-line description of what this migration accomplishes>
-- Destructive?: <yes | no>   -- "yes" if it DROPs, TRUNCATEs, alters constraints in a way that loses data, or rewrites rows
-- Rollback strategy: <inline | migration NNN | not applicable>   -- if inline, include a commented-out reverse DDL block at end of file
-- Linked diagnose-doc: <bug-id from docs/diagnoses/ | n/a>
```

### Example

```sql
-- Intent: Add NOT NULL constraint to subscriptions.end_date with backfill of NOW() for legacy rows.
-- Destructive?: no   -- backfill is forward-only; existing rows survive
-- Rollback strategy: migration 072   -- drops the NOT NULL; rerun migration 071 to restore
-- Linked diagnose-doc: 7bd154

ALTER TABLE subscriptions ALTER COLUMN end_date SET NOT NULL;
-- ...
```

### Why this matters
- `Destructive?: yes` migrations require an explicit dry-run on a Supabase branch + founder sign-off before apply on prod.
- `Rollback strategy: inline` requires the reverse DDL be present (commented) at file-end — used when an emergency revert is needed before a follow-up migration can be authored.
- `Linked diagnose-doc:` lets future audits trace each schema change back to the bug or feature plan that motivated it. `n/a` is valid only for pure infra hygiene (e.g., reindex, vacuum).

### Backups manifest pairing

Every `mcp__supabase__apply_migration` call MUST be paired with a `backups/applied_migrations.json` update in the same git commit (CLAUDE.md §4.5 `feedback_migration_apply_record_pair.md`). The pre-commit hook does not enforce this yet; manual gate via review.

### An APPLIED migration is IMMUTABLE — including its comments (b8f4c2, 2026-09-04)

Once a migration has been applied to prod, **do not edit the file at all** — not the
DDL, not the four-tag header, not a typo in a comment. The `hash` field in
`backups/applied_migrations.json` is a sha256 of the file *as applied*, so any edit
silently falsifies the audit trail: the ledger then claims a hash that no version of
the file has.

⚠ **Nothing catches this.** `scripts/check_applied_migrations_ledger.dart` (Gate 39)
checks only that the `hash` key is PRESENT and non-empty — it never recomputes or
compares it. Board item **OI-135** already documents the class as open and explicitly
non-gated. So the only guard is this rule.

**Measured 2026-09-04.** A review correctly flagged that migration 127's header called
itself the "FOURTH definition" when there are three (026 / 113 / 127). Correcting that
one word changed the file's hash from `305622fb…` to `bbbbaf8a…` while the ledger still
recorded the former. The live function was unaffected (a comment cannot change
`pg_get_functiondef` output), which is exactly what makes it dangerous — nothing
anywhere reports a problem. Caught only by a later review recomputing the sha256 by
hand.

**Where a correction goes instead:** the diagnose-doc, and — if it is a durable trap —
a row in root `CLAUDE.md` §4.9. Both are readable by the next person and neither is
hashed. The wrong word stays in the migration file; that is the cost of an immutable
artifact, and it is cheaper than a lying ledger.

**Corollary for reviewers:** "fix the comment in migration NNN" is only safe advice if
NNN has not been applied. Check `backups/applied_migrations.json` before suggesting it.

## Single-source-of-truth contracts

Migrations themselves are not SoT-bearing objects, but each migration **lands a
schema change that becomes part of an existing SoT concept**. The full
writer→DB-target table mapping lives in `docs/sot_registry.yaml` (each entry's
`cloud:` block lists the canonical `table:` + `columns:`).

Selected canonical table → concept mappings ("when you touch this table, which
SoT concept's columns must stay in sync"):

| Table | SoT concept(s) | Canonical writer |
|---|---|---|
| `workout_log_exercises` | `workout_receipt_rendering`, `exercise_logs_read_path` | `WorkoutWriteService.logExercise` |
| `workout_logs` | `workout_completion_status` | `WorkoutWriteService.completeWorkout` |
| `scheduled_workouts` | `scheduled_workouts_mutations` | `WorkoutScheduleService.upsertScheduled` → `WorkoutWriteService` |
| `nutrition_logs` + `nutrition_log_items` | `nutrition_total_calories`, `food_log_delete_with_undo` | `NutritionWriteService.logMeal` |
| `water_logs` / `weight_logs` / `sleep_logs` | `water_logs` / `weight_logs` / `sleep_logs` | `HealthWriteService` |
| `users` | `user_full_name` | onboarding `completeOnboarding` + `users` upsert |
| `user_profile` | `onboarding_completed_at` + most profile fields | `ProfileWriteService` + onboarding |
| `subscriptions` | `subscription_state`, `subscription_payment_grace_window` | `verify-payment` Edge Function + `razorpay-webhook` |
| `ai_coach_interactions` | `coach_interactions`, `food_text_analysis_daily_cap` | `ai-proxy` Edge Function + `ai_coach_repository` |
| `coach_memory` | `coach_memory_coach_notes_upward_sync` | `ai_coach_repository` upward sync |
| `rank_promotion_log` | `rank_promotion_log` | server-side `evaluate-rank-promotions` cron |
| `client_errors` | `log_client_error_payload` | client `ErrorTelemetry.recordNonFatal` → `log-client-error` Edge Function |

When adding a column, drop a column, or change a constraint:
1. Confirm the migration header tags (above) — `Destructive?` + `Rollback strategy` + `Linked diagnose-doc`.
2. Update the matching SoT registry entry's `cloud.columns` list in the **same git commit**.
3. Update `backups/applied_migrations.json` in the same commit.
4. Update any contract test under `test/contracts/` whose `behavioral_test_path` exercises the column.

## Filename scheme history

Three migration filename schemes coexist in `supabase/migrations/`. This is bookkeeping debt, not active drift — every applied migration has been verified against live cloud schema. See `README_RECONCILIATION_2026-05-11.md` for the full mismatch table.

| Scheme | Pattern | Origin | Status |
|---|---|---|---|
| Sequential numeric | `0NN_<slug>.sql` (e.g., `068b_drift_fix_batch.sql`) | Default — used for every new migration since 2026-03. Number-collision convention: suffix with letter (`050b`, `068b`) per the `050b` precedent. | Active — use this for every new migration. |
| Timestamp-prefixed | `YYYYMMDD…_<slug>.sql` (e.g., `20260328000001_video_renders.sql`) | Three early migrations created via `supabase migration new` before the numeric convention was codified. | Frozen — do not re-introduce. |
| Cloud internal version | 14-digit `YYYYMMDDHHMMSS` returned by `mcp__list_migrations` | Supabase Dashboard SQL editor rewrites the source filename to a timestamp when applying — see README_RECONCILIATION §A. | Cloud-only. The actual DDL applied matches the source file verbatim. |

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| `null user_id` rows from migration 049 pseudonymization | After Test #11 migration 049, FKs on `user_custom_exercises`, `user_custom_foods`, `community_reviews` (note: column is `reviewer_id`), `food_corrections`, `promo_code_uses` are `ON DELETE SET NULL`. When an account is hard-deleted via `delete-account`, these rows survive with `user_id = NULL` ("deleted user" pseudonymization for community signal preservation). **Read consumers MUST tolerate NULL.** Already-fixed in Test #11 cleanup: `promote-community-item` now guards `if (source.user_id)` before `notifySubmitter`. Any new consumer that joins on user_id must add the same guard or the query risks silent skip / false negative. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Partial UNIQUE index + ON CONFLICT → 42P10 | Partial UNIQUE indexes need NOT NULL arbiter columns OR you must convert to a non-partial index before using as `ON CONFLICT` target. Pattern caught migration 064 (APK Test #16). Live INSERT...ON CONFLICT inside a rollback txn is the only reliable test — source-grep contract tests miss this. | `feedback_partial_unique_arbiter_trap.md` |
| `public` SECURITY DEFINER function is anon-executable despite `REVOKE ALL FROM PUBLIC` | Supabase's platform default privileges GRANT EXECUTE on every new `public`-schema function DIRECTLY to `anon`+`authenticated` (not via PUBLIC), so `REVOKE FROM PUBLIC` is a no-op for them. Migration 093 dodged this only by living in `private` (PostgREST-invisible). For a service-role-only `public` function you MUST `revoke execute ... from anon, authenticated` explicitly, then VERIFY live: `has_function_privilege('anon', 'public.fn()', 'execute')` must be false. Static review can't see it (the grant isn't in any migration) — the live post-apply check (§6 tier 8) is the only guard. Migration 103 / diagnose a9d3f1. **RECURRED 2026-08-26 (migration 123 / e4a1b7)** — a SECURITY *INVOKER* function this time, so the exposure was inert (anon's `auth.uid()` is NULL, which the `user_id NOT NULL` rejects), but the ACL was still wrong and only the live check saw it. The trap is not DEFINER-specific: it is that the grant lives in no migration, so no amount of reading the .sql file reveals it. Run the check after EVERY new `public` function, invoker or definer. | `feedback_revoke_from_public_not_role.md` |

## Tests pinning the rules here

- `test/contracts/applied_migrations_parity_test.dart` — every `mcp__supabase__apply_migration` call must be reflected in `backups/applied_migrations.json`.
- `test/contracts/dead_columns_dropped_test.dart` — flags columns dropped via migration but still referenced in code.
- Migration 4-tag header — there is **no** standalone `migration_header_contract_test.dart`; the header is enforced by the migration-header convention above (the pre-commit hook greps for the four tags).
- `test/sql/onconflict_live_arbiter.sql` + `scripts/check_onconflict_live_arbiter.dart` — the live-Postgres ON CONFLICT arbiter check (every client `onConflict` pair resolves on the real schema). Runs at `/build-apk` against a live DB, so there is **no** unit-suite `onconflict_live_arbiter_test.dart`. (NB 2026-06-03: the scaffold carries broad pre-existing schema drift — ~10 blocks reference columns that no longer exist; a dedicated schema-sync pass is tracked as a follow-up. The 082/083 arbiter blocks were updated in this batch.)

## See also

- `docs/architecture/database.md` — full 47-table schema.
- `docs/sot_registry.yaml` — per-concept `cloud.table` + `cloud.columns`.
- `backups/applied_migrations.json` — manifest of applied migrations.
- Root CLAUDE.md §4.5 — `feedback_migration_apply_record_pair.md` enforcement.
