---
reviewed_at: 2026-08-15T13:40:00+05:30
staged_against: b6b0c89e
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 1
verdict: accepted
---

# Code Review (B-pass) — e4a7c9 realtime PRO gate

Commit under review: `b6b0c89e` (`fix(sync): gate the realtime WAL subscription on PRO, at the sink`).
Diff assembled from `main..HEAD`; the review ran after commit rather than staged,
so the file is named for the batch (the `<staging-hash>` convention in the skill
serves `check_code_review_pass_exists.dart`, which only BLOCKS at catastrophic
tier — this is platform, where the verdict is advisory).

## Finding 1 — P0 — guard_without_its_mirror

- **file:line:** `lib/core/services/sync/sync_realtime.dart:193` (the reset);
  trigger at `lib/core/services/day_rollover_service.dart:76` (pre-existing,
  unconditional).
- **claim:** `unsubscribeRealtime()` reset the new free-tier skip latch
  (`_realtimeSkipLogged = false`), and `day_rollover_service` calls it on EVERY
  `AppLifecycleState.paused`. So the latch — whose entire purpose is "log the
  skip per transition, not per resume" — was re-armed on every background /
  foreground cycle. A free user therefore re-fired
  `realtime_subscribe_skipped_free_tier` on every resume: an Edge Function
  invocation plus a `client_errors` row, across essentially the whole user base.
- **why it matters:** this is bug-class 2.13 (telemetry flood) reintroduced *by
  the anti-flood mechanism itself*, in the fix whose own diagnose-doc names that
  class as the thing to avoid. It restores per-foreground network + DB load
  across the free population — the same category of problem the fix exists to
  remove, wearing a different mechanism.
- **why the shipped test missed it:** the case named "the skip is logged ONCE"
  called `subscribeToRealtimeSync()` three times **with no pause between**. That
  is not the production call pattern. The test was written from the same mental
  model as the code and modelled the same half — exactly what lens 6 says not to
  accept as evidence.
- **verification:** `flutter test test/contracts/realtime_pro_gate_behavioral_test.dart`
  — the case `THE B-PASS P0: a pause/resume CYCLE does not re-fire the skip event`
  fails `Expected: <1> Actual: <5>` against the pre-fix code (reproduced by the
  reviewer with a throwaway probe, then re-measured here as mutation 5).
- **fix applied:** the reset moved OUT of `unsubscribeRealtime()` and into
  `SyncService._onUserChanged` only. The latch means "I have already reported
  that THIS user is unentitled", so the only thing that should clear it is the
  user changing. A downgrade needs no reset either — a PRO user's latch is
  already false, so their first post-lapse attempt logs once on its own.
  Deliberately NOT the reviewer's suggested `unsubscribeRealtime({bool
  resetSkipLatch})` parameter: that leaves a footgun default and touches a
  public signature pinned by `sync_service_public_api_snapshot_test.dart`.
  Also rejected the reviewer's explicitly-warned-against alternative (gating the
  reset on `_realtimeSubscription != null`), which would leak the latch across
  users on account swap.
- **regression tests added:** two, and both mutation-proven —
  `THE B-PASS P0: a pause/resume CYCLE…` (restoring the P0 → 1 red, 1 vs 5) and
  `an account swap DOES re-arm the latch` (deleting the swap reset → 3 red).
  The second is the mirror: deleting the reset entirely would have passed the
  first test and broken cross-user isolation.
- **status:** fixed

## Lenses that returned clean

Each with the command run, per the skill's anti-pattern rule against defaulting
to "no findings".

- **writer_reader_drift** — `git show b6b0c89e -- lib | grep -nE "\.put\(|MigratedKey\.write|\.write\("` → 0 hits. The only new mutable state is the
  in-memory bool `_realtimeSkipLogged`; not a Hive field, no cloud counterpart.
  The `sot_registry.yaml` diff is line-range-only.
- **function_exception_swallow** — `git show b6b0c89e -- lib test | grep -n "functions.invoke("` → 0 hits.
- **blast_radius_mismatch** — `docs/blast_radius.yaml:63` tiers
  `lib/core/services/sync/**` as platform, requiring regression_test,
  behavioral_test_path, code_review_b_pass, feature_flag. Kill-switch
  `disable_realtime_pro_gate` present and reachable at the real gate site (not
  dead code); behavioral test present; this review is the B-pass. The reviewer
  noted the substantive gap was that the behavioral test did not prove its
  claimed property — filed as Finding 1 rather than a separate mismatch.
- **secrets_in_tree** — `git show b6b0c89e -- lib test | grep -nE "sk-|rzp_live_|AKIA|-----BEGIN"` → 0 hits.
- **unawaited_no_error_sink** — one `unawaited(` added
  (`ErrorTelemetry.logEvent`). `error_telemetry.dart` wraps its whole body
  including the network call in `try { … } catch (_) {}` — a declared sink.

## Mirror cases checked and found correct

Recorded so they are not re-derived: gate-before-`currentUser` ordering for the
unauthenticated / sign-out-gap case (the unchanged `userId == null` return still
catches it before any network work); `onDowngrade` null before initState / after
dispose (silent no-op, matching the accepted `onStateChanged` pattern, and no
entitlement evaluation runs before `runApp()`); the `pausedForSimulation` early
return skipping the hook (correct — sim deliberately preserves PRO); all 8
downgrade call sites (every one a downgrade-for-cause, teardown correct in each);
and the `_onUserChanged` inline→method collapse (behaviourally identical apart
from the intended latch reset).

## Triage

One finding, P0, accepted and fixed in-batch per `feedback_no_deferrals.md`.
False-alarm rate 0/1.

**Tuning note for the skill:** lens 6 found the only defect, in a diff where the
other five lenses were clean — the fourth consecutive pass in which
`guard_without_its_mirror` is the lens that earns the review. It also held to
its own method note: the finding came from MUTATING and RUNNING the guard, not
reading it. The author's four pre-review mutations all targeted "delete the
guard"; the escape was in a *different* guard's interaction with a pre-existing
unconditional caller, which no delete-the-line mutation would surface.
