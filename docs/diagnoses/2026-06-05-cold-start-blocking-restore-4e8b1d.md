---
bug_id: 4e8b1d
date: 2026-06-05
batch: apk-obs-2026-06-05
status: fixed
blast_radius: platform
symptom: >
  First cold start was very slow. Live telemetry (restore_completed) showed the
  full cloud restore = 37.6s and it BLOCKED the RestoringScreen before /home.
  Step A alone = 25.8s, dominated by the FIRST user_profile fetch at ~24s — a
  cold-backend / edge_function_cold_start_retry penalty.
concept: restore_completeness
sot_registry_entry: restore_completeness
writers: >
  SyncService.restoreFromCloudForUser (lib/core/services/sync_service.dart) —
  internal Step A→B→C order UNCHANGED. New: backend-warm
  SupabaseService.warmConnection (lib/core/services/supabase_service.dart) +
  restoreCompletedTick notifier + bumpRestoreCompleted.
readers: >
  lib/features/auth/screens/splash_screen.dart (_runDeferredInit fires
  warmConnection unawaited). lib/features/auth/screens/restoring_screen.dart
  (_goHome flag branch + ref-free _healAfterRestoreInBackground).
  lib/features/home/screens/home_screen.dart (listens to restoreCompletedTick →
  invalidateOnRetry).
hive_key_prefix: not_applicable (touches the restore orchestration, not a key)
hive_key_formula: not_applicable
sync_methods:
  - restoreFromCloudForUser
restore_methods:
  - restoreFromCloudForUser
cloud_table: user_profile
cloud_columns: not_applicable (warm-up selects user_id only)
contract_test_path: test/contracts/background_restore_test.dart
ist_handling: not_applicable
provider_invalidations:
  - home_screen.invalidateOnRetry (full home provider set) on the restore tick
telemetry_op_types:
  - restore_completed
  - edge_function_cold_start_retry
cross_account_guard: >
  Preserved and BLOCKING in the bg path — HiveUserSession.openForUser completes
  before context.go('/home') (APK #15.4). The bg heals are ref-free singletons;
  the in-flight restore is NOT cancelled (single restore, no double-write race).
forbidden_patterns_checked:
  - "Background-restore path navigating to /home before the ownership gate (openForUser) completes — the test pins openForUser BEFORE context.go in _goHome's bg branch; cross-account safety (APK #15.4) stays blocking."
proposed_fix: >
  (1) Backend-warm (un-flagged, low-risk): fire SupabaseService.warmConnection
  during splash so the restore's first query skips the ~24s cold-start penalty.
  (2) Background-restore behind a default-off flag bg_restore_enabled (§4.6): for a
  RETURNING user (local profile populated), establish ownership BLOCKING + a
  fresh-paint rollover, navigate to /home, and let the already-in-flight cloud
  restore finish in the background; ref-free post-restore heals (key migrators +
  reconciler + refill) then bump restoreCompletedTick → home invalidateOnRetry.
  Internal restore order unchanged; default path (flag off / fresh install)
  preserved verbatim.
regression_test_planned: >
  test/contracts/background_restore_test.dart (comment-stripped source-grep +
  ordering via indexOf): warmConnection exists + splash fires it unawaited;
  restoreCompletedTick + bumpRestoreCompleted on SyncService; home adds+removes
  the listener + invalidateOnRetry; bg path gated by bg_restore_enabled;
  openForUser completes BEFORE navigation; in-flight restore NOT cancelled;
  default path keeps await-restore → ownership → go; heals run post-restore + bump.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "warm-up + flagged bg restore + tick bridge; flutter analyze clean on all 5 touched files; background_restore_test 9/9 green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "ownership gate openForUser stays blocking before nav; bg heals reuse the existing migrators/reconciler ref-free" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "restoreFromCloudForUser Step A→B→C order unchanged; warm-up is a user_id-only select on user_profile" }
impact_analysis: >
  Platform blast radius — touches the restore/boot path (a known-fragile area).
  The background-restore is shipped behind a DEFAULT-OFF feature flag (§4.6) so
  production behavior is unchanged until manually rolled after device verify; the
  backend-warm ships un-flagged and is pure latency hygiene (best-effort, never
  blocks). Risk concentrated in cross-account ownership + restore-completeness,
  both contained: ownership gate stays blocking; internal restore order
  unchanged; single (un-cancelled) restore. Found via the founder's APK obs 4 +
  live restore telemetry.
---

# Cold start: 37.6s blocking restore (~24s cold-backend)

## What happened
The full cloud restore blocked RestoringScreen for ~37s; ~24s of it was the
first query hitting a cold backend.

## Root cause
`restoreFromCloudForUser` was awaited before navigation; the first `user_profile`
fetch ate the cold-start / retry penalty.

## Fix
Backend-warm during splash (un-flagged) kills the cold-start penalty. A
default-off `bg_restore_enabled` flag lets a returning user reach /home in ~3s
while the (un-cancelled, in-flight) restore + ref-free heals finish in the
background and bump a tick the home screen bridges to `invalidateOnRetry`. The
ownership gate stays blocking; the internal Step A→B→C order is unchanged.

## Verification
`flutter analyze` clean; `background_restore_test.dart` (9 cases incl.
ownership-before-nav + no-cancel + default-path-preserved). Flag rolls after
device verify (§4.6).

## See also
- `lib/features/auth/screens/restoring_screen.dart`, `sync_service.dart`,
  `supabase_service.dart`, `splash_screen.dart`, `home_screen.dart`
- Theme D / 4a3b08 (the prior threshold bump that deferred this refactor).
