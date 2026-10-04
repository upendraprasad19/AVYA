---
bug_id: a7f2e9
date: 2026-06-09
batch: apk34-obs-2026-06-09
status: fixed
blast_radius: account
symptom: >
  Two sync-resilience gaps surfaced in the APK +34 live telemetry: (BUG-H) the
  realtime weight_logs stream channelError'd 113x (WS close 1002) and never
  recovered — only "token expired" triggered a reconnect — so PRO Telegram->app
  instant-sync silently fell back to the batch pull forever; (BUG-G) a long
  restore on a heavy account can span the access-token TTL, contributing to the
  401/timeout cluster (push_snapshot etc.) during/after restore.
concept: realtime_sync_resilience
sot_registry_entry: realtime_sync_resilience
writers: >
  not_applicable (resilience/auth-path change). BUG-H:
  lib/core/services/sync/sync_realtime.dart _attachRealtimeStream onError now
  reconnects on a transient channelError (channelerror / channel_error), bounded
  attempt < 2, refreshing the JWT via _reconnectRealtimeWithRefreshedJwt — not
  only on token-expiry. BUG-G: lib/core/services/sync_service.dart restoreFromCloud
  + restoreFromCloudForUser call _supabase.ensureFreshToken() before the long
  multi-step pull.
readers: >
  Realtime subscribers (PRO Telegram relay path) get a self-healing weight_logs
  stream; the restore path's REST/EF calls run on a fresher token.
hive_key_prefix: weight_ (realtime weight_logs -> healthBox)
hive_key_formula: weight_${date}
sync_methods: subscribeToRealtimeSync / _attachRealtimeStream / _reconnectRealtimeWithRefreshedJwt
restore_methods: restoreFromCloud, restoreFromCloudForUser
cloud_table: weight_logs
cloud_columns: date, weight_kg, created_at
contract_test_path: test/contracts/sync_resilience_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  failure: [realtime_stream_weight_logs]
cross_account_guard: >
  not_applicable (realtime stream is .eq('user_id', userId); restore is user-scoped).
forbidden_patterns_checked:
  - "The realtime onError must reconnect on a transient channelError (not only token-expiry); restore must refresh the session before the long pull. Pinned by test/contracts/sync_resilience_test.dart."
proposed_fix: >
  BUG-H: broaden the realtime onError reconnect gate to (isTokenExpired ||
  isChannelError) && attempt < 2 so a transient channelError self-heals once
  (bounded — a persistent RLS/publication failure still falls back to the batch
  pull, no loop). BUG-G: await _supabase.ensureFreshToken() at the top of both
  restore entrypoints.
regression_test_planned: >
  test/contracts/sync_resilience_test.dart — comment-stripped source-grep:
  sync_realtime reconnects on isChannelError; sync_service refreshes the token in
  restore (>= 5 ensureFreshToken occurrences = 3 EF invokes from d3a1c7 + 2 restore).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "realtime channelError reconnect + restore-start token refresh; dart analyze clean; sync_resilience_test green" }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "weight_logs IS in supabase_realtime publication (pg_publication_tables) and has a SELECT RLS policy for auth.uid(); the 1002 was a transient channel/WS error, not a missing publication (that was migration 079) — so a bounded reconnect is the right recovery" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live: realtime_stream_weight_logs = 113 channelErrors over the window; the reconnect now self-heals transient ones" }
impact_analysis: >
  Account blast radius — realtime cross-device sync (PRO) + restore auth
  freshness. BUG-H makes the weight_logs stream self-heal a transient channelError
  instead of staying dead (bounded so a structural failure still degrades to the
  batch pull). BUG-G is belt-and-braces over the Supabase SDK's auto-refresh
  (proactive refresh before a long op, matching the realtime subscribe pattern);
  the broader 504/connection-abort cluster during restore is environmental (heavy
  sim-polluted account on mobile) and mitigated by the already-shipped background
  restore (c5a1f2) plus the clean-account verification baseline (LOOP-A) — i.e.
  no further distinct CLIENT bug there (verified-covered, not deferred). A full
  realtime-reconnect behavioral harness is the follow-up (behavioral_test_required
  on realtime_sync_resilience).
---

# Realtime stream stayed dead on channelError; restore didn't refresh up front

## What happened
Live telemetry: realtime weight_logs channelError'd 113x (WS 1002) and never
recovered (PRO Telegram->app instant-sync silently dead); long restores on a
heavy account contributed to the 401/timeout cluster.

## Root cause
BUG-H: `_attachRealtimeStream` onError only reconnected on "token expired"; a
channelError fell through, leaving the stream permanently dead. BUG-G: restore
did not proactively refresh the session before its long multi-step pull.

## Fix
BUG-H: reconnect on a transient channelError too (bounded attempt < 2, refreshing
the JWT). BUG-G: `ensureFreshToken()` at the start of both restore entrypoints.

## Verification
`dart analyze` clean; `sync_resilience_test.dart`. weight_logs confirmed in
supabase_realtime + SELECT RLS present (so the 1002 was transient, not a missing
publication).

## See also
- BUG-C (d3a1c7) — EF token freshness (same auth-freshness class as BUG-G).
- Debugging skill 2.23 — realtime channelError = table not in publication (REFUTED here; publication is present, so this is a transient-channelError recovery, a sibling).
