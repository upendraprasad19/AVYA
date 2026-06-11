---
bug_id: a8f3d1
date: 2026-06-11
batch: audit-2026-06-10
status: fixed
blast_radius: account
symptom: >
  Quarterly audit (L27 concurrency lens) finding. The slow-boot flip (ADR-0014)
  lands a returning user on /home BEFORE the restore's Step C (_restoreFreezes)
  runs. On /home the streak walk (_calculateStreak consume:true) may consume a
  streak-freeze, writing streak_freeze_used_dates=[D] + a decremented
  streak_freezes_available locally (its syncFreezes is fire-and-forget, may not
  have landed). _restoreFreezes then UNCONDITIONALLY overwrote
  streak_freeze_used_dates with the stale cloud snapshot (which lacked D) and —
  because equal-refill was lumped into the cloud-wins branch — also reset
  available to cloud's higher value. Result: the just-consumed freeze D is wiped
  and the freeze is refunded → a spurious streak break / double-spend.
concept: streak_freeze_progress_merge
sot_registry_entry: streaks
writers: >
  sync/sync_restore_completeness.dart _restoreFreezes (the restore writer) +
  streak_progress_service.dart commitConsume / commitRefill (the live writers).
  The new pure merge StreakProgressService.mergeFreezeProgress is the single
  reconciliation point.
readers: >
  workout_repository.dart _calculateStreak reads streak_freeze_used_dates to
  decide which past days were frozen (streak-break decision); the streak badge UI
  reads streak_freezes_available.
hive_key_prefix: "userBox['progress'] map (streak_freezes_available, streak_freeze_used_dates, streak_freezes_last_refill)"
hive_key_formula: not_applicable (fields on the single progress map)
sync_methods: syncFreezes
restore_methods: _restoreFreezes
cloud_table: user_progress
cloud_columns: "streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill"
contract_test_path: test/contracts/restore_freezes_merge_test.dart
ist_handling: not_applicable (last_refill is an IST Monday string, compared lexically — unchanged)
provider_invalidations: []
telemetry_op_types:
  success: ["streak_freeze_consume_done", "streak_freeze_refill_done"]
  failure: ["sync_service_if_23 (restore_freezes)"]
cross_account_guard: true
forbidden_patterns_checked:
  - "_restoreFreezes unconditionally overwriting streak_freeze_used_dates with cloud — replaced by the refill-aware mergeFreezeProgress (same-week UNION used_dates + lower available)."
  - "equal-refill lumped into cloud-wins (>= 0) — now strictly-newer (> 0) with a separate equal-refill UNION branch."
proposed_fix: >
  Extract a pure, refill-aware merge StreakProgressService.mergeFreezeProgress.
  Because used_dates is PER-WEEK (commitRefill clears it), the merge keys on
  last_refill: (a) SAME week (equal last_refill) → UNION used_dates (never lose a
  consume from the bg-restore window or another device) + take the LOWER available
  (never refund a freeze); (b) cloud refill STRICTLY newer → cloud is the
  current-week truth; (c) local refill strictly newer (or cloud null) → keep local
  + schedule a syncFreezes to push it up. _restoreFreezes now calls it instead of
  overwriting. Clamp(0,3) preserved.
regression_test_planned: >
  test/contracts/restore_freezes_merge_test.dart — pure-function behavioral test:
  THE BUG (same-week local consume cloud hasn't seen → consume survives + no
  refund), cross-device different-day consumes → union, cloud-refill-newer → cloud,
  local-refill-newer → local + scheduleSyncUp, cloud-null-refill → local, clamp.
  6 cases, all green; THE BUG case fails against the pre-fix overwrite.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "mergeFreezeProgress pure helper + _restoreFreezes rewire; flutter analyze clean on streak_progress_service.dart + sync_service.dart" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "the progress map's used_dates leg is no longer clobbered on restore; restore_freezes_merge_test 6/6 incl. THE BUG case" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live read of founder user_progress (d7a67a37) — streak fields coherent; the cloud columns unchanged by this client-side merge fix" }
impact_analysis: >
  Account blast radius. The window is narrow (a missed-day freeze-consume firing on
  /home during the ~tens-of-seconds bg-restore window before its syncFreezes lands),
  but the effect is a user-visible spurious streak break + a double-spent/refunded
  freeze — high annoyance for the exact engaged users who maintain streaks. The
  flip (ADR-0014) created the window; the (available, last_refill) max-merge half
  was already guarded (9c4a17), this closes the unguarded used_dates leg. Found by
  the quarterly L27 concurrency lens; verified by direct read of the cited code +
  the commitRefill clear-on-refill semantics. related: 9c4a17 (the available leg),
  c5a1f2 (additive log-row restore — same bg-flip class, different shared state).
---

# Restore clobbers a concurrently-consumed streak-freeze (a8f3d1)

## What happened
The slow-boot flip (ADR-0014) lands a returning user on /home before the cloud
restore's Step C (`_restoreFreezes`). If the on-/home streak walk consumes a freeze
(writing `used_dates=[D]` + a decremented `available` locally, its `syncFreezes`
fire-and-forget and not yet landed), `_restoreFreezes` then **unconditionally
overwrote `streak_freeze_used_dates`** with the stale cloud snapshot and — because
equal-refill fell into the cloud-wins branch — **reset `available`** to cloud's
higher value. The consume D is wiped and the freeze refunded → spurious streak break.

## Root cause
`used_dates` is **per-week** (`commitRefill` clears it). The old merge guarded only
the `(available, last_refill)` legs (Bug 9c4a17) and treated `used_dates` as
"cloud authoritative" unconditionally — the unguarded half — and lumped equal
last_refill into cloud-wins (`>= 0`).

## Fix
A pure, refill-aware `StreakProgressService.mergeFreezeProgress`: same week → UNION
`used_dates` + LOWER `available`; cloud-refill-newer → cloud; local-refill-newer →
local + schedule sync up. `_restoreFreezes` calls it instead of overwriting.

## Verification
- `test/contracts/restore_freezes_merge_test.dart` 6/6 (incl. THE BUG case).
- `flutter analyze` clean; founder account streak fields coherent (live read).

## See also
- lib/core/services/streak_progress_service.dart (`mergeFreezeProgress`, `commitRefill`, `commitConsume`)
- lib/core/services/sync/sync_restore_completeness.dart (`_restoreFreezes`)
- docs/adr/0014-additive-local-wins-restore.md (the flip that opened the window)
