---
bug_id: a3d7e2
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: account
symptom: >
  Obs#8 (live web E2E console): "[realtime] weight_logs stream error:
  RealtimeSubscribeException channelError" recurring (WS close 1006/1000). The
  PRO realtime weight_logs subscription (Telegram→app instant sync) kept erroring
  on the backgrounded web tab. Live verification (read-only, dedsavbjuwgarrhphgnl)
  shows the cloud is CORRECT — weight_logs IS in the supabase_realtime
  publication, RLS is enabled with a select-own policy — so this is NOT the §2.23
  missing-publication class. The reconnect was already bounded (attempt < 2) and
  already handled channelError (BUG-H a7f2e9) + refreshed the JWT. The remaining
  defect: on reconnect-budget EXHAUSTION the dead channel was left attached, so
  the Supabase realtime client kept auto-reconnecting the WS and re-firing
  channelError into the console + client_errors — the "recurring" the founder saw.
concept: realtime_teardown_on_reconnect_exhaustion
sot_registry_entry: not_applicable
contract_test_path: test/contracts/weight_realtime_teardown_on_exhaustion_test.dart
writers: >
  lib/core/services/sync/sync_realtime.dart — _attachRealtimeStream onError now
  calls unsubscribeRealtime() when the reconnect budget is exhausted (channelError
  / token-expired but attempt >= 2), tearing the channel down.
readers: >
  The Supabase realtime client (stops auto-reconnecting once the subscription is
  cancelled); client_errors (no more recurring realtime_stream_weight_logs rows
  after teardown).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: [subscribeToRealtimeSync]
restore_methods: []
cloud_table: weight_logs
cloud_columns: "not_applicable (realtime channel lifecycle; no schema change)"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [realtime_stream_weight_logs]
cross_account_guard: false
forbidden_patterns_checked:
  - "Reconnect-budget exhaustion that leaves the dead realtime channel attached → Supabase client keeps auto-reconnecting + spamming channelError. Now unsubscribeRealtime() on exhaustion. Pinned by test/contracts/weight_realtime_teardown_on_exhaustion_test.dart."
proposed_fix: >
  In _attachRealtimeStream's onError, after the bounded reconnect path, add an
  else-branch: when the failure is a channelError/token-expired but the attempt
  budget is exhausted, call unsubscribeRealtime() to cancel the subscription so
  the Supabase realtime client stops auto-reconnecting the WS. The 24h batch pull
  remains the fallback (no data loss — weight_logs still sync). No cloud change is
  needed (publication + RLS live-verified correct).
regression_test_planned: >
  test/contracts/weight_realtime_teardown_on_exhaustion_test.dart — source-grep
  (comment-stripped): the onError path tears the channel down
  (unsubscribeRealtime) on the non-reconnect (exhausted) branch, within proximity
  of the `attempt < 2` guard.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "unsubscribeRealtime() on reconnect exhaustion; flutter analyze clean; weight_realtime_teardown_on_exhaustion_test green" }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "live pg_policy: weight_logs_select_own[r] + insert/update/delete own; RLS enabled — realtime authorization policy present + correct" }
  - { tier: 9, layer: storage_buckets_publication, status: verified, evidence: "live pg_publication_tables: weight_logs IS in supabase_realtime — NOT a missing-publication (§2.23) case" }
impact_analysis: >
  Account blast radius, PRO realtime (Telegram→app instant weight sync), web-
  centric. No data loss (batch pull is the fallback); the bug was console +
  client_errors noise (a dead channel auto-reconnecting forever) on a stale-token
  / backgrounded web tab. The live cloud verification rules out the §2.23 class
  (the first suspect) and the fix is a clean channel teardown on exhaustion. The
  underlying recurring-channelError trigger is the same web-background-tab token/
  WS staleness class as Obs#4; tearing down stops the symptom cleanly rather than
  looping.
---

# weight_logs realtime channelError spam on reconnect exhaustion (a3d7e2)

## What happened
The PRO weight_logs realtime channel errored repeatedly on a backgrounded web
tab. Cloud is correct (publication + RLS live-verified). The reconnect was bounded
+ handled channelError, but on budget exhaustion left the dead channel attached →
the Supabase client kept auto-reconnecting + re-firing channelError ("recurring").

## Fix
On exhaustion (channelError/token-expired, attempt >= 2), `unsubscribeRealtime()`
tears the channel down → no more auto-reconnect spam; batch pull is the fallback.

## See also
- lib/core/services/sync/sync_realtime.dart
- test/contracts/weight_realtime_teardown_on_exhaustion_test.dart
- docs/diagnoses/...-a7f2e9 (BUG-H — the bounded channelError reconnect this builds on)
