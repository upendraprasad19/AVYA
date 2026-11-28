---
bug_id: a7d2e6
date: 2026-11-02
batch: freeze-order-d1
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Founder rule (D1, confirmed 2026-11-02): a streak freeze is a KEPT stock; days up to Saturday are settled
  first (a missed scheduled day spends a freeze, a Sunday rest is free); on Monday's app-open +1 is credited
  (cap 1 free / 3 PRO) regardless of last week's misses; a PRO user at 3 freezes who misses 6 days keeps the
  streak 3 days and loses it on the 4th; next Monday's +1 covers a missed Monday (settled Tuesday). The code
  did the opposite on the rollover path: `refillIfNewWeek` (credit) ran BEFORE `reckonStreakDecayAndPersist`
  (spend) at day_rollover_service.dart:230 vs :247, and on the post-restore heal (heal_after_restore.dart:52,
  reckon later in reckonAndNotifyAfterRestore), so with stock 0 and a missed Saturday the fresh Monday +1 was
  silently spent on Saturday and the streak survived. Separately the streak walk is STATELESS: a break only
  ended that walk, so any later credit re-funded a missed day that could not be paid when it was missed.
concept: streaks
sot_registry_entry: |
  streaks: extends the EXISTING streak concept in docs/sot_registry.yaml (behavioral_test_path
  test/contracts/streak_freeze_refill_race_behavioral_test.dart; new additional_tests
  freeze_settle_then_credit_behavioral_test.dart).
related_bugs: [f9d2e7, e5c9b1, b4e7a1, c9d2f6, 9c8958, 5e8a1c, d7a3e5]
recurrence: |
  Partial. f9d2e7 (D1/D2, 2026-06) made the reckon the single consume site and the ledger permanent and ordered
  "refill FIRST, then reckon" on purpose (a comment in day_rollover_service.dart said so); the founder's rule
  reverses that order, so this is a changed requirement, not a regression of that fix. b4e7a1 added the settled
  marker that now also gates the credit. The writer-pair-without-an-order-contract class is new (bug-class 2.143).
writers:
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "refillIfNewWeek (credit; now: defer until the restore settled, reckon, commitRefill, reckon)", line: 214 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "_calculateStreak (spend; new cutoff + horizon rules) via reckonStreakDecayAndPersist", line: 420 }
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "istMondayKey (the ONE Monday key for the credit and the walk)", line: 113 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "currentStreak (read-only, same walk: Home/Train/rank/AI snapshot)", line: 286 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "StreakNotifier.build / StreakFreezeNotifier.build", line: 270 }
hive_key_prefix: "user_progress (userBox['progress'])"
hive_key_formula: "UserRepository.getProgress()['streak_freezes_available'] / ['streak_freeze_used_dates'] / ['streak_freezes_last_refill'] (read through the typed accessor UserRepository.getFreezeLastRefill)"
sync_methods:
  - "SyncService.syncFreezes -> RPC update_streak_progress (unchanged; up to three un-coalesced pushes per Monday open now: reckon #1 consume, refill, reckon #2 consume; each retry round re-reads Hive so they converge)"
restore_methods:
  - "UserRepository._mergeFreezeFamily / StreakProgressService.mergeFreezeProgress (unchanged)"
cloud_table: user_progress
cloud_columns:
  - streak_freezes_available
  - streak_freezes_last_refill
  - streak_freezes_used_dates
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "istMondayKey formats mondayOfIst's components directly (never through formatDateKey/istDateStr: that converts the instant twice and is a day early east of IST)", line: 113 }
provider_invalidations:
  - "none new; the previous batch's restoreCompletedTickProvider rebuilds the chips after the restore tick"
telemetry_op_types:
  success: []
  failure:
    - streak_freeze_refill_deferred
    - streak_freeze_refill_settle_failed
cross_account_guard: "the deferral reads SyncService.restoreSettledForCurrentUser, which already requires marker == live uid == Hive owner."
forbidden_patterns_checked:
  - { pattern: "the weekly credit landing before the restore for this account settled", absent: true }
  - { pattern: "a missed day before the credited Monday being funded by a later credit", absent: true }
proposed_fix: |
  Two rules INSIDE the walk (_calculateStreak, shared by the read-only display and the consuming reckon):
  CUTOFF: while the weekly credit is DUE (a non-null stamp older than this IST Monday) a fresh missed day on or
  after this Monday is skipped (neither spent nor chain-breaking), so before the credit only days before this
  Monday are settled, with the old stock. HORIZON: a fresh missed day strictly before streak_freezes_last_refill
  is unfundable (break), so a broken chain is durable and a later credit never resurrects it. Both are off under
  the kill switch disable_settle_before_refill, the legacy gate switch disable_streak_reckon_user_gate and
  the dev simulation (SyncService.pausedForSimulation).
  refillIfNewWeek: when enabled it DEFERS (no write, LOW event streak_freeze_refill_deferred) until the restore for
  this account has settled; then reckon (settles only pre-Monday days by the cutoff), commitRefill, reckon again
  (Monday-onward misses against the new stock, persists the streak count). A throwing walk never costs the credit.
  _doRolloverWithRef is NOT reordered: the choke point holds for every caller (round-3 finding: any reckon that
  runs before the credit, e.g. completeWorkout, would otherwise spend Monday-onward misses with the old stock).
  ACCEPTED CONSEQUENCES (written down, testers only: the app is not live):
  (a) A restore that never settles (offline cold start, CONTINUE, a streak-critical op failing every launch) gets
  no credit that week and weeks do not accumulate: an unsettled week's +1 is lost for good, not just late
  (today those users still get the credit and only the decay is off). A bounded fallback would reopen the
  credit-before-settle path.
  (b) A NULL stamp (legacy / clamp-migrated account) keeps the old order for its FIRST credit (Monday may spend
  first, Saturday breaks); pinned by a test.
  (c) Founder-visible: stock 0, Saturday missed (chain breaks), +1 arrives; if Monday was also missed the credit is
  burned on Monday behind an already-broken chain (stock 0, streak 0). The newest-first walk cannot know the
  chain is broken behind.
  (d) Mixed-version devices: an older build credits first and spends on Saturday (0), the new build credits 1 with
  the same stamp; the same-week LOWER merge takes 0. Not a regression versus today.
  (e) Cross-device restore / push-conflict merge can adopt a newer cloud stamp over unspent local misses (a lost
  consume push after a landed credit push): the horizon turns a double charge into a chain break (rare with the
  3-attempt push retry).
  (f) The horizon unfunds a pre-stamp miss whose schedule row appears AFTER the stamp lands (PRO phase ensure, a
  late restore, an un-pause), and stock changed after the stamp (first-PRO grant, mid-week upgrade, lapse reset)
  cannot fund pre-stamp days. Legacy testers whose old unspent misses precede the stamped Monday lose that old
  chain at the next walk. Named late writer: PlanIntegrityReconciler.reconcile writes schedule_* rows AFTER the
  restore marker settles (heal_after_restore), so a rollover firing in that window credits and stamps on partial
  rows and a late-added past miss then breaks instead of consuming stock.
  (g) While the credit is due but cannot land the cutoff hides this week's misses in the display and the reckon
  is gated too, so the Home chain is optimistic for up to a week; when a credit of 1 arrives with two misses
  (Mon, Tue, stock 0) the newest-first walk funds Tue and breaks at Mon, so the display drops then.
  (h) One Monday open can write three times (reckon #1 consume, refill, reckon #2 consume): up to three syncFreezes
  pushes, and the notice reads "N freezes used" with the chip showing the post-credit stock.
  (i) The dev year-simulation keeps the old walk (rules off under pausedForSimulation).
  (j) A brand-new account gets its first credit only from the next rollover after the restore marker is set (the
  refill callers are rollover, the post-restore heal and the restoring screen; onboarding reaches none of them), so
  day one has no credit; no miss is possible on day one (the anchor blocks earlier days).
  (k) If reckon #1 throws and reckon #2 succeeds, the credit stamps this Monday and the horizon then breaks a
  pre-Monday miss that old stock could have funded: "a throwing walk never costs the credit" holds, the chain can
  cost. Needs a walk that throws once then succeeds; the alternative (skip the credit when #1 throws) reopens a
  lost-credit path, so it is accepted as is.
  NOT CHANGED: grantFirstProFreezes (OI-448), the push retry, mergeFreezeProgress, the chip providers, any Edge
  Function (verified: no server twin of the walk; rank_engine.ts reads the persisted count), any migration.
contract_test_path: test/contracts/freeze_settle_then_credit_behavioral_test.dart
regression_test_planned: |
  - test/contracts/freeze_settle_then_credit_behavioral_test.dart (26 tests, behavioral, pinned Monday/Tuesday/
    Wednesday clocks): Monday with stock 0 and stock 1; second refill is a no-op; Tue/Wed first opens (incl. the
    notice count and display == persisted); a bare reckon with the credit due; a completed Monday; PRO-style
    stock 3 / six misses with the next Monday's credit; stamp boundary; future-dated stamp; NULL stamp; deferral
    (unsettled, reinstall with an EMPTY box, throwing walk); kill switch; legacy switch with the tick already > 0
    and with tick 0 then bumped; simulation; istMondayKey around the Sunday/Monday IST midnight plus a source pin.
  - MUTANTS (each confirmed applied; none a compile error): drop reckon #1 (5 red), drop the deferral (2),
    invert it (10), kill switch backwards (11), drop the cutoff (3), drop reckon #2 (3), drop the horizon (3),
    cutoff > instead of >= (3), simulation bypass dropped in the refill (1) and in the walk (1), horizon not
    guarded against a future stamp (1), settle failure rethrown (1), NULL stamp treated as due (1), cutoff
    before the completed arm (1), horizon <= (3), Monday key through formatDateKey (1: the source-grep pin only;
    the double conversion is a no-op in IST, a behavioural kill needs a non-IST process), legacy still runs the
    refill settle (2), cutoff continue->break (3). All 18 reddened at least one test.
impact_analysis: |
  The streak walk is read by Home, Train, rank gates, the AI snapshot and the profile; all read through
  currentStreak() / the gated reckon, so they agree. Server: no twin of the walk. Value semantics of
  streak_freezes_available / used_dates / last_refill are unchanged; what changes is WHEN a miss can be funded
  (the horizon) and WHEN the credit lands (the deferral). 4.1.5 point 3 grep of test/ and supabase/functions/
  done: tests that seed an OLD stamp and miss days in the current week were repointed (see the repointed list in
  the commit); EF code only reads the persisted count.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "streak_progress_service.dart (refill flow), workout_repository.dart (walk rules), ist_date.dart (istMondayKey), sync_flags.dart (switch), user_repository.dart (typed accessor). 18 mutants killed." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "the behavioral tests read userBox['progress'] (stock, ledger, stamp, notice count) on real Hive after every step." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "grep of supabase/functions: no streak walk or freeze logic; rank_engine.ts countBlankDays and the guardian crons read the persisted streak count only." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the push (update_streak_progress), the merge rule and the RPC are untouched; two pushes per Monday open are accepted (consequence h)." }
---

# Settle-then-credit: the weekly streak-freeze credit follows the settled days, and a broken chain stays broken

## What the founder asked
The rule above, applied on every path ("I have already cleared you what I want"), not asked again.

## What the code did
Credit first (rollover, post-restore heal, restoring screen), spend after; and a stateless walk that re-funded any
unpaid missed day the next time stock was positive. With stock 0 and a missed Saturday, the Monday +1 was spent on
Saturday and the streak survived; next Monday's +1 could resurrect a chain lost a week earlier.

## Fix
See `proposed_fix`. Plan `docs/plans/2026-11-02-freeze-order-settle-then-credit.md`: 6 plan-review rounds (each
folded; round 6 found no P0/P1 in the mechanism and one P1 in the test plan, folded). The unit was simplified in
round 3 (a separate pre-pass and a caller reorder were deleted: the rule moved into the walk).

## Not done here
OI-448 (first-PRO grant), the account cloud-row heal (live prod write, held by the founder), the device check
(a Monday session on a Train-first web account).
