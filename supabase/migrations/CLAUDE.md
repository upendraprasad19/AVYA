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

## Single-source-of-truth contracts

(populated in Milestone 2 — when canonical writer→DB-target table mappings are extracted from the diagnose-doc history)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| `null user_id` rows from migration 049 pseudonymization | After Test #11 migration 049, FKs on `user_custom_exercises`, `user_custom_foods`, `community_reviews` (note: column is `reviewer_id`), `food_corrections`, `promo_code_uses` are `ON DELETE SET NULL`. When an account is hard-deleted via `delete-account`, these rows survive with `user_id = NULL` ("deleted user" pseudonymization for community signal preservation). **Read consumers MUST tolerate NULL.** Already-fixed in Test #11 cleanup: `promote-community-item` now guards `if (source.user_id)` before `notifySubmitter`. Any new consumer that joins on user_id must add the same guard or the query risks silent skip / false negative. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Partial UNIQUE index + ON CONFLICT → 42P10 | Partial UNIQUE indexes need NOT NULL arbiter columns OR you must convert to a non-partial index before using as `ON CONFLICT` target. Pattern caught migration 064 (APK Test #16). Live INSERT...ON CONFLICT inside a rollback txn is the only reliable test — source-grep contract tests miss this. | `feedback_partial_unique_arbiter_trap.md` |

## Tests pinning the rules here

(populated in Milestone 6)
