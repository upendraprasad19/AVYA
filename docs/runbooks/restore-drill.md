# Supabase Backup Restore Drill

> Tech-debt audit 2026-05-20 finding I15 — "We have backups" is unverified
> until a drill has happened. This runbook describes how to perform a
> backup-restore drill in a way that doesn't risk prod data.

## Cadence

Quarterly. First drill: **2026-08-03** (aligns with quarterly tech-debt
audit cadence per CLAUDE.md §4.10).

## Pre-requisites

- Supabase MCP access to the fitness app project
  (`dedsavbjuwgarrhphgnl`, account `myfitnessjourney1988@gmail.com`).
- Supabase Pro tier (PITR backups are a Pro feature — verify in
  Dashboard → Project Settings → Backups).
- A clean Supabase Branch to restore into (Branches are isolated; the
  drill never touches prod).

## Drill procedure

### 1. Create a fresh Branch off prod

```
mcp__ba7b5e8e__create_branch
  project_id: dedsavbjuwgarrhphgnl
  branch_name: drill-YYYY-MM-DD
```

### 2. Identify the backup target

Pick a PITR snapshot from ~7 days ago (representative of "what we'd
restore in a real incident"). Capture the timestamp.

### 3. Trigger restore into the Branch

Supabase Dashboard → Branches → drill-YYYY-MM-DD → Settings → Restore →
pick the PITR snapshot. This is a one-click action and may take 5-30
minutes depending on DB size.

### 4. Validate restore completeness

Run these queries against the Branch (the dashboard shows the Branch's
connection string at the top of its page):

```sql
-- Row count parity for canonical tables.
SELECT 'users' AS tbl, COUNT(*) FROM users
UNION ALL SELECT 'user_profile', COUNT(*) FROM user_profile
UNION ALL SELECT 'workout_logs', COUNT(*) FROM workout_logs
UNION ALL SELECT 'nutrition_logs', COUNT(*) FROM nutrition_logs
UNION ALL SELECT 'ai_coach_interactions', COUNT(*) FROM ai_coach_interactions
UNION ALL SELECT 'subscriptions', COUNT(*) FROM subscriptions;
```

Compare against the same query on prod (run in a separate Studio tab).
Counts should be ≤ prod (snapshot was 7d old; some growth expected).

### 5. Run the migration-applied gate against the Branch

```
dart run scripts/check_migrations_live.dart
```
(Point its DB target at the Branch by overriding env vars for the run.)
All migrations should be present.

### 5b. Run the two-user cross-account isolation gate against the Branch

```
dart run scripts/check_two_user_cross_account.dart
```

Inserts a synthetic Alice + Bob with IDENTICAL natural keys (same date / name /
workout_log_id) across every per-user table and asserts BOTH rows coexist
(count == 2). A user-less sync key would collapse them onto one row — the
cross-account leak class this gate exists for. Needs the fitness-app
Management-API PAT, which is why it cannot run in pre-commit or CI.

**Documented here 2026-08-17 because it had no invocation site at all.** It was
skip-listed in `pre-commit.sh` and `test.yml` under the "requires live DB" case
— correctly, it does — but the runbook that exercises live-DB gates never named
it, so nothing anywhere ever ran it. A gate reachable from no document is a gate
that does not run.

### 6. Spot-check a user

Pick the founder's `user_id`. Query their profile, last 7 workout_logs,
last 30 ai_coach_interactions. They should look like 7d-ago state.

### 7. Document the drill

Append a row to the table below with: date, snapshot age, restore
duration, parity check result, any anomalies surfaced.

### 8. Delete the drill Branch

```
mcp__ba7b5e8e__delete_branch
  branch_id: <drill-branch-id>
```

Branches accumulate cost; clean up immediately after the drill.

## Drill history

| Date | Snapshot age | Restore duration | Parity | Notes |
|---|---|---|---|---|
| (none yet — first drill scheduled 2026-08-03) | | | | |

## What "passing" looks like

- Restore completes without manual intervention.
- Row counts on canonical tables are within ±2% of expected (drift accounts for inserts since the snapshot).
- All migrations present (Gate 14b PASS).
- Spot-checked user looks intact.
- Drill row appended to history table in this file.

## What "failing" looks like (escalate immediately)

- Restore times out or fails with a Supabase platform error → file ticket
  with Supabase support; do NOT delete the Branch (engineer needs it).
- Row count delta > 5% → snapshot may be corrupt; try an older snapshot
  before declaring the backup unusable.
- Migration mismatch → schema-vs-migrations drift on the Branch; treat as
  a P1 (schema is the SoT and a successful restore must preserve it).
- Spot-check shows missing user data → likely a restore-scope issue (some
  Supabase backup formats exclude certain tables); read the Supabase
  Backup docs for what's covered.

## When to skip a drill

NEVER skip. If the scheduled date passes without a drill, the implicit
assumption "we have working backups" becomes increasingly load-bearing.
File a ticket to reschedule within 14 days; if 30 days pass without a
drill, escalate to the founder as a P1 ops gap.

## Related

- `docs/operations/SECRET_INVENTORY.md` — credentials needed to access
  the Branch.
- `docs/architecture/sync.md` — what's stored in cloud vs Hive (informs
  what "fully restored" means for THIS app).
- `backups/applied_migrations.json` — ledger of applied migrations
  (B3 schema migration will gain `applied_at` + `hash` per row).
