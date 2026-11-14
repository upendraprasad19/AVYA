---
bug_id: e3f1a7
date: 2026-05-30
batch: web-e2e-2026-05-30
status: fixed
symptom: >
  Live web (amar@gmail.com): recurring console "[realtime] weight_logs stream
  error: RealtimeSubscribeException(status: channelError, ...)" (3x in 14 min)
  and 156 client_errors rows op_type=realtime_stream_weight_logs. The PRO
  realtime cross-device / Telegram-relay instant sync never delivered — it
  silently fell back to the 24h batch pull.
concept: weight_logs_realtime_stream
sot_registry_entry: weight_logs
blast_radius: feature
writers:
  - { file: supabase/migrations/079_enable_weight_logs_realtime.sql, method: ALTER PUBLICATION supabase_realtime ADD TABLE weight_logs, line: 1 }
readers:
  - { file: lib/core/services/sync/sync_realtime.dart, method: _attachRealtimeStream, line: 41 }
hive_key_prefix: "weight_<date> (handler writes into healthBox on delivery)"
hive_key_formula: "'weight_' + row['date']"
sync_methods: [subscribeToRealtimeSync]
restore_methods: []
cloud_table: weight_logs
cloud_columns: [id, user_id, date, weight_kg, created_at]
contract_test_path: test/contracts/weight_logs_realtime_publication_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [realtime_stream_weight_logs, realtime_handler_weight_logs]
cross_account_guard: >
  RLS weight_logs_select_own (auth.uid() = user_id) gates realtime delivery to
  the owning user; the client stream also filters .eq('user_id', userId).
forbidden_patterns_checked:
  - { pattern: "supabase_realtime publication missing weight_logs", absent: true }
proposed_fix: >
  The supabase_realtime publication contained ZERO tables, so the client's PRO
  realtime subscription (sync_realtime.dart:41 .from('weight_logs').stream())
  channelError'd on every subscribe — weight_logs was not a publication member.
  The onError reconnect path only handles "token expired", so the error recurred
  indefinitely. Migration 079: ALTER PUBLICATION supabase_realtime ADD TABLE
  public.weight_logs. RLS already enabled with weight_logs_select_own; replica
  identity 'd' (default/PK) is sufficient because the feature consumes INSERTs
  (new weights relayed from Telegram) which Realtime delivers with the PK.
regression_test_planned:
  - test/contracts/weight_logs_realtime_publication_test.dart
touched_layers_checked:
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "pg_publication_tables(supabase_realtime) was empty; after migration 079 it returns public.weight_logs" }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "pg_policy weight_logs: select_own/insert_own/update_own/delete_own all auth.uid()=user_id; realtime delivers per-user rows" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "migration 079 applied via Management API; backups/applied_migrations.json paired (sha256:8937723834...)" }
  - { tier: 12, layer: end_to_end_contract, status: verified, evidence: "live: last realtime_stream_weight_logs error 17:07 UTC (pre-migration 17:35 UTC); after migration + web reload at 17:57 UTC, ZERO new errors — stream subscribes cleanly" }
impact_analysis: >
  Feature-tier (PRO realtime/Telegram instant sync). No crash, no data loss —
  the stream error was caught and logged; weights still synced via the 24h batch
  pull, just not instantly. The fix turns on a real PRO feature that had never
  worked (publication was empty from the start). Live-verified: the recurring
  channelError stopped after enabling the publication. Replica identity left at
  default (PK) — INSERT delivery is all the stream needs; if a future UPDATE/
  DELETE-old-row use case is added, bump to REPLICA IDENTITY FULL then.
---

# e3f1a7 — weight_logs realtime stream channelError (publication was empty)

## What happened
`SyncServiceRealtime.subscribeToRealtimeSync` opens
`_supabase.client.from('weight_logs').stream(primaryKey:['id']).eq('user_id',
uid)` for PRO cross-device / Telegram-relay instant sync. Supabase Realtime
"Postgres Changes" requires the table to be a member of the `supabase_realtime`
publication — which was **empty**. Every subscribe raised
`RealtimeSubscribeException(channelError)`; the `onError` reconnect only handles
"token expired," so it recurred forever (156 `realtime_stream_weight_logs`
client_errors rows; 3 in a 14-minute live window).

## Why it was invisible
The error was caught + logged as a non-fatal and weights still arrived via the
24h batch pull, so nothing user-facing broke hard — the *instant* part of the
feature was just silently dead. No test exercised live realtime (it needs a
live socket + publication), and the publication state isn't covered by any
schema gate.

## Fix
Migration 079: `ALTER PUBLICATION supabase_realtime ADD TABLE
public.weight_logs`. RLS (`weight_logs_select_own`) already scopes delivery per
user; default replica identity (PK) covers the INSERT-delivery use case.

## Verification
Live: last `realtime_stream_weight_logs` error at 17:07 UTC (before the 17:35
UTC migration); after the migration + a fresh web reload at 17:57 UTC, zero new
errors — the stream subscribes cleanly. `pg_publication_tables` now lists
`public.weight_logs`. Source-grep contract test pins the migration.
