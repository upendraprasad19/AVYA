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
(in this exact order, as SQL comments). Keep the casing and the colon-space.

⚠ **NOTHING ENFORCES THIS. This section claimed "the pre-commit hook and any
future gate scripts grep for these tags" and that was FALSE** — corrected
2026-09-05 (B-pass on `004af467`). `grep -rn Destructive scripts/pre-commit.sh`
returns nothing, and no `check_*.dart` reads the tags either. ⚠ Precisely: the
only hit for `Destructive?:` anywhere under `scripts/` is
`seed_exercise_library.js:74`, which WRITES the tag into a migration it
generates. Nothing READS or validates one. The same section
is cited elsewhere in this file under "Tests pinning the rules here" as
"enforced by the migration-header convention above (the pre-commit hook greps
for the four tags)" — also false, and both statements have been believed.

**It has already cost one migration.** 129 shipped with only `Intent:` and
`Rollback strategy:`, missing `Destructive?:` and `Linked diagnose-doc:`, and
its diagnose-doc asserted in writing that it "carries the four-tag header".
Nobody noticed until a context-blind reviewer grepped for the tags instead of
reading the sentence claiming they were there. Because an applied migration is
immutable (see below), that omission is now permanent.

**Until a gate exists, the header is checked by whoever writes the migration
and by review — treat it exactly as self-attested**, the same trust model as
rule 21's `presence_only:` and rule 24's ledger. Do not assume a red gate will
catch a missing tag; there is no gate. Same shape as the OI board's
"fixed by `check_open_issues_reconciled.dart`" note describing a script that
was never written.

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

Every `mcp__supabase__apply_migration` call MUST be paired with a `backups/applied_migrations.json` update in the same git commit (CLAUDE.md §4.5 `feedback_migration_apply_record_pair.md`). Enforced file → ledger by `check_migration_ledger_paired.dart` (a staged migration needs a staged ledger entry; matches top-level `NNN[x]_*.sql`, letter suffixes and timestamp-scheme files, NOT `041_chunks/`) and Gate 14 `check_migrations_applied.dart` (every file needs an entry); the entry's `hash` is verified by Gate 39 (see the immutability section below). **Nothing enforces live → ledger** — a migration applied to prod that nobody recorded is invisible to every gate (OI-272).

### Allocating a migration number — `scripts/mint_migration.sh` (OI-263)

Never read the next number off `ls supabase/migrations/`: a number applied **live** from an unmerged branch is invisible to every other branch's tree (148 → the 145→147→148→149 renumber, 2026-09-28). Reserve it:

```bash
sh scripts/mint_migration.sh --stub <slug>   # reserves refs/heads/mig/N (server-side compare-and-swap), writes the four-tag stub
sh scripts/mint_migration.sh --next          # read-only: NEXT=<n> and UNFILED=<n,n>
```

Also `--reserve N <slug>` (adopt a number already used), `--release N` (drop an UNFILED reservation), `--prune`, `--live snap.json`. Offline ⇒ it refuses (exit 2). Only top-level 3-digit `NNN_*.sql` names count (a naive `[0-9]+` reads a timestamp file as the ceiling; `041_chunks/` is not migration 041); letter suffixes are manual follow-ups needing their base published or reserved. Gate `scripts/check_migration_number_reserved.dart` (pre-commit + CI) requires a reservation for every ADDED `NNN_*.sql` and fails a number already taken on `origin/main` by a different file; it fails OPEN offline.

⚠ A reservation proves a `mig/N` ref EXISTS — not that this branch owns N — and cannot see a raw apply that never registered a row (OI-223). The apply-time "refuse a number already live" check is **OI-272**. Mechanism, reader-side limits, live-name coverage: `docs/architecture/migrations-detail.md`.

### An APPLIED migration is IMMUTABLE — including its comments (b8f4c2, 2026-09-04)

Once a migration has been applied to prod, **do not edit the file at all** — not the
DDL, not the four-tag header, not a typo in a comment. The `hash` field in
`backups/applied_migrations.json` is a sha256 of the file *as applied*, so any edit
falsifies the audit trail: the ledger then claims a hash that no version of the file has.

**Since 2026-09-29 Gate 39 VERIFIES the hash** (`check_applied_migrations_ledger.dart` + `migration_ledger_hash_lib.dart`): `sha256:<64 hex>` (or an `unverifiable:` sentinel, only for a migration with no `.sql` of its own, e.g. `120b`), equal to the sha256 of the file under its LF **or** CRLF form. **Write a ledger hash with `dart run scripts/migration_ledger_hash.dart <NNN|path>`, never a raw `sha256sum`.** It catches the FORGOTTEN re-stamp, not an edit plus a re-stamp in the same commit, and it reads the working tree, not staged blobs. Five historical drifts (057, 069, 070, 108, 123) are grandfathered BY NAME with a pinned sha — a closed list, never add. Migration 120's note "the hash tracks the FILE" is superseded: the hash is of the file **as applied**. Detail (dual-form limits, why each of the five drifted): `docs/architecture/migrations-detail.md`.

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

⚠ **`git checkout -- <migration>` IS NOT A SAFE RESTORE HERE (2026-09-05, B-pass on
`303c57af`).** If you mutate an applied migration to prove a test — which rule 21 requires —
the obvious undo silently converts the file's line endings. `.gitattributes` sets `eol=lf`,
so a checkout writes LF where the committed working copy had CRLF. **The sha256 changes; the
ledger no longer matches; and `git status` / `git diff` both read CLEAN throughout**, because
git is comparing normalized content while the ledger hashes bytes on disk.

Restore with **`cp` from a copy you made first**, then prove it:

```bash
cp supabase/migrations/NNN_x.sql "$SCRATCH/NNN.bak"   # BEFORE mutating
# ... mutate, run the test, then:
cp "$SCRATCH/NNN.bak" supabase/migrations/NNN_x.sql
dart run scripts/migration_ledger_hash.dart NNN      # MUST equal the ledger entry (LF form)
```

Gate 39 now hashes both line-ending forms (above), so a CRLF/LF flip no longer reddens it — but
that is a safety net, not a licence: the restore is still `cp`, because a `git checkout` that
silently rewrites bytes is the wrong tool for an immutable file. This was the OI-135 class
arriving through a completely ordinary action rather than a deliberate edit, which is
what made it worth its own note. A `git status` that says "M" on such a file after a restore
is expected (an eol attribute artifact) and is NOT evidence of drift; **the sha256 is the only
thing that settles it, in either direction.**

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
| `coach_memory` | `coach_memory_coach_notes_upward_sync`, `coach_extraction_locked_fields` (conflict-marker half) | `ai_coach_repository` upward sync; `daily-snapshot`'s `mergeCoachingNotes` (conflict markers) |
| `user_profile` (`coach_extraction_locked_fields` column) | `coach_extraction_locked_fields` | `lock_coach_extraction_fields` RPC (migration 148), ONLY writer — never a plain UPDATE |
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
| **A pg_cron command is ONE transaction — `VACUUM` can never share it with another statement** | With `cron.use_background_workers=off` (live), pg_cron sends a job's whole command as one libpq simple query, which Postgres runs as a single implicit transaction. `VACUUM` refuses to run in a transaction block, so a command holding `VACUUM` beside ANY other statement fails EVERY run — and the error rolls the other statements back too. Give each `VACUUM` its own single-statement job. Consolidating jobs is a semantics change, not a tidy-up: check every statement you fold in. Pinned for every migration (any dollar-quote style) by `test/contracts/cron_vacuum_single_statement_test.dart`. | 2026-09-26 (diagnose d6b2f9) — migration 141 folded 4 cleanups + 2 VACUUMs into `db_maintenance_nightly`; it failed 5/5 nights and no retention ran; nothing alerted (OI-178). Repaired by migration 144. |
| A GUC with `context=postmaster` cannot be flipped by any migration — `ALTER DATABASE ... SET` fails with `55P02` ("cannot be changed without restarting the server"), not a syntax error | Before drafting a migration that sets any server-level parameter (`cron.*`, `shared_buffers`, `max_connections`-class settings), check its context first: `select context from pg_settings where name = '<setting>'`. Only `sighup`/`superuser`/`user` are migration-reachable; `postmaster` needs a full server restart (Supabase dashboard/support); `internal` is not settable at all. | 2026-09-22 (diagnose e8b4a1) — `cron.log_run` was authorized as "a simple reversible GUC toggle"; the restart requirement was discovered only on `apply_migration`, after authorization, forcing the migration to be withdrawn. |
| `idx_scan=0` proves an index was never used by a QUERY — it says nothing about whether the same index backs a FOREIGN KEY, which Postgres also needs for referential-integrity checks on the referenced table's side | Before dropping any `idx_scan=0` index, check `pg_constraint` for a foreign key on the same column(s): `select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = '<table>'::regclass and contype = 'f'`. If it's the sole covering index for that FK, dropping it creates a NEW `unindexed_foreign_keys` finding in `get_advisors` that wasn't there before — verify `get_advisors` again post-drop, not just pre-drop. | 2026-09-22 (diagnose e8b4a1) — `idx_nutrition_log_items_food_id` dropped as "verified-dead" (true for query access, per `pg_stat_user_indexes`) while being the sole FK-support index for `nutrition_log_items_food_id_fkey`; caught by a self-triggered B-pass before commit, required a same-day follow-up migration (142) to restore it. |
| `null user_id` rows from migration 049 pseudonymization | After Test #11 migration 049, FKs on `user_custom_exercises`, `user_custom_foods`, `community_reviews` (note: column is `reviewer_id`), `food_corrections`, `promo_code_uses` are `ON DELETE SET NULL`. When an account is hard-deleted via `delete-account`, these rows survive with `user_id = NULL` ("deleted user" pseudonymization for community signal preservation). **Read consumers MUST tolerate NULL.** Already-fixed in Test #11 cleanup: `promote-community-item` now guards `if (source.user_id)` before `notifySubmitter`. Any new consumer that joins on user_id must add the same guard or the query risks silent skip / false negative. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Partial UNIQUE index + ON CONFLICT → 42P10 | Partial UNIQUE indexes need NOT NULL arbiter columns OR you must convert to a non-partial index before using as `ON CONFLICT` target. Pattern caught migration 064 (APK Test #16). Live INSERT...ON CONFLICT inside a rollback txn is the only reliable test — source-grep contract tests miss this. | `feedback_partial_unique_arbiter_trap.md` |
| `public` SECURITY DEFINER function is anon-executable despite `REVOKE ALL FROM PUBLIC` | Supabase's platform default privileges GRANT EXECUTE on every new `public`-schema function DIRECTLY to `anon`+`authenticated` (not via PUBLIC), so `REVOKE FROM PUBLIC` is a no-op for them. Migration 093 dodged this only by living in `private` (PostgREST-invisible). For a service-role-only `public` function you MUST `revoke execute ... from anon, authenticated` explicitly, then VERIFY live: `has_function_privilege('anon', 'public.fn()', 'execute')` must be false. Static review can't see it (the grant isn't in any migration) — the live post-apply check (§6 tier 8) is the only guard. Migration 103 / diagnose a9d3f1. **RECURRED 2026-08-26 (migration 123 / e4a1b7)** — a SECURITY *INVOKER* function this time, so the exposure was inert (anon's `auth.uid()` is NULL, which the `user_id NOT NULL` rejects), but the ACL was still wrong and only the live check saw it. The trap is not DEFINER-specific: it is that the grant lives in no migration, so no amount of reading the .sql file reveals it. Run the check after EVERY new `public` function, invoker or definer. | `feedback_revoke_from_public_not_role.md` |
| A deliberately-narrowed function ACL survives `CREATE OR REPLACE` but NOT a signature change | `CREATE OR REPLACE FUNCTION` preserves an existing function's grants/revokes (a body-only edit is safe). A later migration that changes the SIGNATURE (adds/removes/retypes a parameter) requires `DROP FUNCTION` + `CREATE FUNCTION` instead — and a freshly created function gets the schema's default-privilege grants again, which on this project already include `anon`/`authenticated` (migration 128's `ALTER DEFAULT PRIVILEGES` regime — see the row above). That silently REOPENS a gap a prior migration deliberately closed, with no diff anywhere flagging it as a regression. Migration 130 (`f2c8d5`) narrows `consume_quota`'s ACL to `service_role` only; if a future migration ever needs to change its signature, the narrowing must be re-applied in that SAME migration, and the live `has_function_privilege` check is the only thing that would catch a silent regression here — nothing else does. | Flagged by the OI-162 slice 4 B-pass review, Finding 4, 2026-09-11 (hash-named file — `docs/plan-reviews/oi162-slice4-windowed-counters.md`'s `bpass_review:` field is the stable pointer) |

## Tests pinning the rules here

- `test/contracts/applied_migrations_parity_test.dart` — every `mcp__supabase__apply_migration` call must be reflected in `backups/applied_migrations.json`.
- `test/contracts/dead_columns_dropped_test.dart` — flags columns dropped via migration but still referenced in code.
- Migration 4-tag header — there is **no** standalone `migration_header_contract_test.dart` **and no gate of any kind**. This line previously said the header "is enforced by ... (the pre-commit hook greps for the four tags)"; it does not, and never did. See the correction under "Migration header convention" above. The header is self-attested.
- `test/sql/onconflict_live_arbiter.sql` + `scripts/check_onconflict_live_arbiter.dart` — the live-Postgres ON CONFLICT arbiter check (every client `onConflict` pair resolves on the real schema). Runs at `/build-apk` against a live DB, so there is **no** unit-suite `onconflict_live_arbiter_test.dart`. (NB 2026-06-03: the scaffold carries broad pre-existing schema drift — ~10 blocks reference columns that no longer exist; a dedicated schema-sync pass is tracked as a follow-up. The 082/083 arbiter blocks were updated in this batch.)

## See also

- `docs/architecture/database.md` — full 47-table schema.
- `docs/sot_registry.yaml` — per-concept `cloud.table` + `cloud.columns`.
- `backups/applied_migrations.json` — manifest of applied migrations.
- Root CLAUDE.md §4.5 — `feedback_migration_apply_record_pair.md` enforcement.
