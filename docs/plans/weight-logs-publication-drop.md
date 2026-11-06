---
plan: weight-logs-publication-drop
revision: 2
date: 2026-11-05
blast_radius: platform   # supabase/migrations/** and backups/applied_migrations.json
tier: L                  # schema (publication membership) + Edge Function deploy record
execution_mode: inline   # one worktree (.claude/worktrees/weight-logs-publication-drop)
closes_oi: [OI-464, OI-465]
---

# Drop weight_logs from the supabase_realtime publication; record the log-client-error redeploy

Follow-up to PR #214 (`realtime-weight-off`, merged as 58d0d817), which removed the client's only
Realtime subscription. Plan: `docs/plans/realtime-weight-off.md` sections 6 and 8 (live follow-ups) and OI-464 / OI-465.

## Execution order and state (stated honestly: the live steps ran BEFORE this review)

The founder gave an explicit per-action go for both live steps on 2026-11-05 (CLAUDE.md 4.3). Both were
executed, verified, and are recorded here; this plan-review covers the paper trail that lands them on `main`
and tests whether the live state is correct and reversible.

1. **Edge Function.** `log-client-error` redeployed from main 58d0d817 (`emit_payload.js` then
   `deploy_via_api.js ... true --yes`): live v20 -> v21 per the Management API response (`ezbr_sha256` 71bfd352...), `verify_jwt` true unchanged, smoke HTTP 401 (reachable).
   Source change vs v20: `HIGH_PRIORITY_OP_TYPES` lost `realtime_subscribe_skipped_free_tier` (the client
   twin was removed in PR #214; parity test `high_priority_op_types_parity_test.dart`). Archive
   `backups/edge_function_payloads/log-client-error/v5_58d0d81.json` added, two oldest pruned (last 3 kept).
2. **Migration 168** (`supabase/migrations/168_weight_logs_realtime_publication_drop.sql`, number minted by
   `mint_migration.sh`, which skipped 167): idempotent `DO` block, `ALTER PUBLICATION
   supabase_realtime DROP TABLE public.weight_logs` only when the table is a member. Applied with
   `.claude/apply_migration_via_api.js` (HTTP 201). Before: `pg_publication_tables` for `supabase_realtime`
   listed exactly one row, `weight_logs`. After: 0 rows; `weight_logs` row count 79 before and after.
   Rollback (inline, commented at file end): `ALTER PUBLICATION supabase_realtime ADD TABLE public.weight_logs`.
3. **Ledger.** `backups/applied_migrations.json` entry 168 with the sha256 from
   `scripts/migration_ledger_hash.dart 168`; applier `claude-via-node-api`.
4. **Board.** OI-464 and OI-465 moved from `open_issues.md` to the end of `closed_issues.md` (append only,
   Status CLOSED, resolution lines); the commit carries `closes-oi: OI-464` and `closes-oi: OI-465`.

## Why this is safe

- No client subscribes any more (PR #214, guard `test/contracts/no_client_realtime_subscription_test.dart`),
  and the only published table was `weight_logs`. Dropping it removes server-side WAL decoding for no
  subscriber; no table, row, policy or grant changed.
- Old app builds that still contain the subscription (anything before PR #214, commit f7617370) now meet an
  EMPTY publication, the state migration 079 was written to cure. What they do is bounded, read from
  `git show f7617370^:lib/core/services/sync/sync_realtime.dart` (`onError`, lines ~111-125, and the reconnect
  helper): each `channelError` writes one `client_errors` row (`realtime_stream_weight_logs`, not in
  `HIGH_PRIORITY_OP_TYPES`); the first one refreshes the session and re-attaches (BUG-H a7f2e9, b750ce76), and the
  second tears the channel down (Obs#8 a3d7e2, 551215f6) with the subscription left null, so there is no spin.
  This holds for builds from 551215f6 (2026-06-13) on; older builds had no teardown and a dead channel stayed
  attached, which is far too old to be in testers' hands but cannot be proven from the repo. The cost is per
  foreground (`day_rollover_service.dart` on resume; PRO users also attach after a restore from
  `sync_service.dart`): the next foreground attaches again, about two `refreshSession` calls and two
  `client_errors` rows per attach, for PRO users (builds older than the PRO gate e4a7c9 also attach for free
  users). 079's own header describes only the earlier, unbounded behaviour. This is the same noise class as the
  113-row recurrence behind a7f2e9; it lasts only until a tester takes a post-#214 build, and the app is not
  live in any store (CLAUDE.md section 1). Which builds the testers hold cannot be proven from the repo. The
  accepted cross-device weight gap is tracked in OI-279 item 8.
- A DDL statement fires `pgrst_ddl_watch` and a PostgREST schema reload (`docs/plans/realtime-weight-off.md`
  section 0 records the hourly reload pattern; the cause of the 2026-11-04 reload is NOT established). The
  statement ran in the early morning; an ALTER PUBLICATION is not a table change.

## What the reviewers must test

- The live-state claims above against the files (migration text, ledger entry, hash, payload archive,
  parity test, OI moves, no deleted lines in `closed_issues.md`).
- The mirror: is there any other reader of `supabase_realtime` membership (tests, gates, SoT registry,
  `backups/live_schema_columns.json`, docs) that now disagrees with the live state?
- Whether re-applying the migration on a fresh DB or a branch DB is safe (idempotence, publication absent).
- Whether `weight_logs` should also be considered for `REPLICA IDENTITY` or other 079 leftovers
  (migration 079 text).

## Review round 1 folds (P2s)

- `e4a7c9` (migration header, ledger `diagnose`) is the Realtime-subscribe lineage diagnose-doc
  (`docs/diagnoses/2026-08-13-realtime-subscribe-not-pro-gated-e4a7c9.md`); no new diagnose-doc because the commit
  is `chore`, not a bug fix.
- OI-464's "Do" said to pair the migration with `backups/live_schema_columns.json`: that file records columns and
  a publication change alters none, so it is intentionally not touched.
- The cold-start log check (new build opens no Realtime tenant init, with a positive control) was prose in the
  closed OI-464 text; it now has its own tracked item, OI-470, blocked on the next `/build-apk`.
