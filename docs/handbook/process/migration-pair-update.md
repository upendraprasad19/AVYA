---
title: Migration apply + applied_migrations.json update is atomic
category: process
source_memory: feedback_migration_apply_record_pair.md
last_reviewed: 2026-05-28
---

# Migration apply + applied_migrations.json update is atomic

## The rule

Apply + record are a single atomic operation, even though the tool surfaces are separate.

When applying a migration:

1. Call `mcp__supabase__apply_migration` (or dashboard equivalent) → cloud changes.
2. **In the SAME commit as the SQL file:** add the migration's numeric/timestamp prefix to `backups/applied_migrations.json`.
3. Commit + push together. Don't split.

## How to detect missing pairing

- `/build-apk` Gate 14 (`scripts/check_migrations_applied.dart`) fires `UNAPPLIED: <migration>` at APK pre-flight.
- Diff context for the migration SQL doesn't include `backups/applied_migrations.json`.

## Why this regresses without enforcement

- The MCP tool returns `{"success": true}` and feels final.
- The matching JSON snapshot lives under `backups/` and doesn't surface in the same diff context as the `.sql` file just written.
- Gate 14 only fires at APK build time, hours-to-days later. By then the migration commit has shipped and the fix is a separate hygiene commit.

## How to apply

Whenever you call `mcp__supabase__apply_migration`, the IMMEDIATE next step is:

1. `Read backups/applied_migrations.json`.
2. `Edit` to add the migration prefix (e.g. `"051"`) in numeric order.
3. Stage + include in the same commit as the migration SQL file.

If you forget and Gate 14 catches it later, the fix is a 2-line edit + commit — but the cleaner discipline is to never split the pair.

## References

- Gate: `scripts/check_migrations_applied.dart` (Gate 14 in `/build-apk`).
- CLAUDE.md §4.5 (migration apply paired with `backups/applied_migrations.json` in same commit).
- Migration apply protocol: `supabase/migrations/CLAUDE.md`.
