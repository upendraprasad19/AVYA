---
bug_id: f9d2e7
date: 2026-06-18
batch: discipline-overhaul
status: fixed
blast_radius: account
symptom: >
  Founder report: PRO had been active 7 days but the Home streak-freeze chip
  still showed "1/1", not "3/3"; and on deeper investigation the streak read 1
  and freezes read 1 even though the last two days had no workout logged (a
  Wednesday with Mon+Tue empty). Four distinct model defects compound here:
  (1) the freeze DENOMINATOR (max freezes) was computed from the non-reactive
  one-shot SubscriptionService.isPro() captured at provider-build time, so after
  a PRO grant the chip kept rendering the stale free-tier /1 until a full app
  restart; (2) there was NO first-PRO instant grant — a freshly-upgraded PRO
  user stayed at the free cap (1) until the next Monday weekly refill, so "/3"
  never appeared promptly; (3) the freeze used-dates ledger was cleared every
  refill (per-week), so a freeze consumed in a prior week was forgotten and the
  decay walk could not see it; (4) streak decay was reckoned ad-hoc at multiple
  call-sites with no single authority + no restore-gating, so a cold start on an
  un-restored device could under- or over-count the streak.
concept: streak_freeze_denominator_grant_decay
sot_registry_entry: streaks
writers: >
  Phase 2 Unit C grant/lapse: streak_progress_service.dart grantFirstProFreezes
  (idempotent first-PRO instant-3, max(current,3), sets the grant-done flag) +
  resetToFreeCapOnLapse (clamp available to 1 on lapse, preserve the flag);
  fired from subscription_service.dart writeSubscriptionState (genuine
  free->PRO transition, session-owned) + _downgradeLocally (lapse, session-owned).
  Unit B reactive denominator: home_provider.dart streakFreezeMaxProvider +
  StreakFreezeNotifier now read ref.watch(subscriptionInfoProvider).isPro.
  Unit D1 permanent ledger: streak_progress_service.dart commitRefill (stops
  clearing streak_freeze_used_dates; prunes >365d) + mergeFreezeProgress
  (always-union used_dates). Unit D2 decay: the gated single consume site
  workout_repository.dart reckonStreakDecayAndPersist (rollover +
  completeWorkout) delegates the persist to StreakProgressService.commitConsume.
  Sync/restore: sync/sync_restore_completeness.dart syncFreezes (push, flag
  only-if-true) + _restoreFreezes (cloud-true-wins flag, refill-aware merge).
readers: >
  workout_repository.dart _calculateStreak reads streak_freeze_used_dates to
  decide which past days were frozen; home_provider.dart streakFreezeProvider +
  streakFreezeMaxProvider render the Home freeze chip numerator/denominator;
  the streak badge reads current_streak_days.
hive_key_prefix: "userBox['progress'] map (streak_freezes_available, streak_freeze_used_dates [Hive singular], streak_freezes_last_refill, streak_freezes_first_pro_grant_done)"
hive_key_formula: not_applicable (fields on the single progress map)
sync_methods: syncFreezes
restore_methods: _restoreFreezes
cloud_table: user_progress
cloud_columns: "streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill, streak_freezes_first_pro_grant_done"
contract_test_path: test/contracts/streak_freeze_first_pro_grant_behavioral_test.dart
ist_handling: >
  streak_freezes_last_refill is an IST-Monday date string compared lexically
  (unchanged). The Unit D2 decay reckon keys off istDateStr(DateTime.now())
  for the day-walk so a late-evening UTC boot does not mis-bucket the day.
provider_invalidations:
  - "subscriptionInfoProvider -> streakFreezeMaxProvider / streakFreezeProvider (Unit B reactive denominator)"
telemetry_op_types:
  success: ["streak_freeze_first_pro_grant", "streak_freeze_lapse_reset", "streak_freeze_consume_done", "streak_freeze_refill_done"]
  failure: ["sync_service_sync_freezes"]
cross_account_guard: true
forbidden_patterns_checked:
  - "Non-reactive isPro() captured at provider build for the freeze denominator — replaced by ref.watch(subscriptionInfoProvider).isPro (Unit B) so a PRO grant flips /1 to /3 without a restart."
  - "Unconditional first-PRO grant on every writeSubscriptionState — gated to a genuine free->PRO transition (oldIsPro==false && isPro) AND an idempotent grant-done flag AND session-owned, so boot-refresh/renewal/cross-account never phantom-grant."
  - "DELIBERATELY NOT gating the GRANT on restoreCompletedTick (the converged plan named it): the tick is bumped only from the returning-user bg-restore heal (restoring_screen.dart:677), never for a brand-new user who buys PRO in their first session — gating there would permanently deny that purchaser the instant grant (no transition on later boots). The grant-done flag + the cloud-wins restore merge (local last_refill null => cloud authoritative) already make the grant robust to the reinstall race; the weekly refill (max 3) backstops any miss. restoreCompletedTick STILL gates the Unit D2 decay engine, where pre-restore state is genuinely unknown."
  - "commitRefill clearing streak_freeze_used_dates each week (per-week ledger) — Unit D1 stops the clear (prune >365d instead) so the ledger is permanent and mergeFreezeProgress always-unions; this supersedes the a8f3d1 per-week merge assumption."
proposed_fix: >
  Four ordered units on the discipline-overhaul branch. B (shipped 7ad54a8,
  feat): reactive /3 denominator via ref.watch(subscriptionInfoProvider).isPro.
  C (this commit, fix): migration 095 adds streak_freezes_first_pro_grant_done
  (default false) + backfills true for every ever-PRO / has-subscription user;
  grantFirstProFreezes (idempotent max(current,3)+flag) on a genuine free->PRO
  transition; resetToFreeCapOnLapse (clamp 1, keep flag) on lapse; both
  session-owned; flag plumbed through syncFreezes (only-if-true) + _restoreFreezes
  (cloud-true-wins). D1 (fix): commitRefill stops clearing used_dates (permanent
  ledger, prune >365d) + mergeFreezeProgress always-union + fix the live RPC
  update_streak_progress column-ref singular->plural. D2 (fix): single
  reckonStreakDecayAndPersist consume site (rollover + completeWorkout, in-process
  lock, restoreCompletedTick + non-empty-schedule gated so a cold-start-empty
  device never decays).
regression_test_planned: >
  test/contracts/streak_freeze_first_pro_grant_behavioral_test.dart (Unit C):
  grant fires once on free->PRO (max(current,3)+flag); idempotent no-op when flag
  already true (boot-refresh/renewal); lapse clamps to 1 and PRESERVES the flag
  so re-purchase does not re-grant; cross-account no-session no-op. Unit B is
  pinned by the reactive-denominator widget/provider test. Unit D1+D2 add
  test/contracts/streak_decay_reckon_permanent_ledger_test.dart (commitRefill
  preserves the recent ledger + prunes >365d; a frozen day survives a refill;
  reckon gated OFF on tick==0 and on empty schedule do NOT persist; reckon gated
  ON persists). restore_freezes_merge_test is extended for the permanent-ledger
  always-union (the two newer-refill cases now assert the union, pre-D1 empty),
  and streak_freeze_refill_race_behavioral_test is updated (refill no longer
  clears the ledger). Each fails against its pre-fix path.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "grantFirstProFreezes / resetToFreeCapOnLapse + writeSubscriptionState/_downgradeLocally hooks (session-guarded) + reactive denominator; flutter analyze clean on the three service files" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "streak_freeze_first_pro_grant_behavioral_test 5/5 incl. idempotency + lapse-preserves-flag + no-session no-op; reader-manifest gate green" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 095 ADD COLUMN streak_freezes_first_pro_grant_done boolean NOT NULL DEFAULT false; verified live via information_schema after apply" }
  - { tier: 4, layer: postgres_data, status: fixed_in_this_batch, evidence: "migration 095 backfill marks every users.subscription_status<>'free' OR any subscriptions-row user as already-granted; verified by post-apply count of flagged rows" }
  - { tier: 5, layer: migrations_applied, status: fixed_in_this_batch, evidence: "095 recorded in backups/applied_migrations.json (paired same commit) + live_schema_columns.json regenerated" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "flag is plural streak_freezes_first_pro_grant_done in BOTH the Hive progress map and the user_progress cloud column — no writer/reader name drift across grant, syncFreezes push, and _restoreFreezes" }
impact_analysis: >
  Account blast radius (subscription + streak state, per-user). The defects hit
  exactly the engaged PRO users who maintain streaks: a paid user who could not
  see or use their 3 freezes (stale /1, no instant grant) and a streak that
  could break spuriously when the per-week ledger forgot a prior consume. The
  fix is offline-first (Hive writes; cloud is projection) and cross-account
  guarded. Related: a8f3d1 (restore freeze-merge — its per-week used_dates
  assumption is superseded by Unit D1's permanent ledger), 9c4a17 (the
  available/last_refill merge leg), c5a1f2 (additive local-wins restore, same
  bg-flip window class). The restoreCompletedTick-gate deviation for the GRANT
  (kept for the DECAY engine) is documented above and surfaced to the B-pass /
  Hermes review per CLAUDE.md 4.12.
---

# Streak-freeze denominator / first-PRO grant / permanent ledger / decay (f9d2e7)

## What happened
The Home streak-freeze chip showed `1/1` for a user who had been PRO for 7 days,
and the streak/freeze counts looked wrong after idle days. Four compounding
model defects:

1. **Stale denominator.** `streakFreezeMaxProvider` / `StreakFreezeNotifier`
   computed the cap from a one-shot `SubscriptionService.isPro()` captured at
   provider-build, so a PRO grant did not flip the displayed `/1` to `/3` until a
   full restart.
2. **No first-PRO grant.** A freshly-upgraded PRO user stayed at the free cap (1)
   until the next Monday refill — `/3` slots never filled promptly.
3. **Per-week ledger.** `commitRefill` cleared `streak_freeze_used_dates` every
   week, so a freeze consumed in a prior week was forgotten by the decay walk.
4. **Ad-hoc decay.** Streak decay was reckoned at multiple call-sites with no
   single authority and no restore-gating.

## Root cause
The freeze model conflated "current available" with "entitlement" and had no
permanent ledger or single decay authority; the denominator read a non-reactive
value. PRO entitlement (3) is only reachable via the weekly refill, so a
new PRO user saw the free cap until Monday.

## Fix (four ordered units, discipline-overhaul branch)
- **B** (7ad54a8, feat): reactive denominator — `ref.watch(subscriptionInfoProvider).isPro`.
- **C** (this commit, fix): migration 095 flag + ever-PRO backfill;
  `grantFirstProFreezes` (idempotent `max(current,3)` + flag) on a genuine
  free→PRO transition; `resetToFreeCapOnLapse` (clamp 1, keep flag) on lapse;
  both session-owned; flag plumbed through sync + restore.
- **D1** (fix): permanent ledger — `commitRefill` stops clearing `used_dates`
  (prune >365d) + `mergeFreezeProgress` always-union; live RPC column-ref fix.
- **D2** (fix): single `reckonStreakDecayAndPersist` consume site, restore-gated.

## Deviation from the converged plan (surfaced, not silent)
The plan specified the grant be `restoreCompletedTick`-gated. During
implementation I found the tick is bumped **only** from the returning-user
bg-restore heal (`restoring_screen.dart:677`) — never for a brand-new user who
buys PRO in their first session. Gating the **grant** on it would permanently
deny that purchaser the instant grant (no transition fires on later boots). The
grant-done flag (idempotent) + the cloud-wins restore merge already make the
grant robust to the reinstall race, and the weekly refill backstops any miss, so
the grant is **intentionally not** tick-gated. `restoreCompletedTick` **does**
gate the Unit D2 decay engine, where decaying before restore confirms state is
genuinely harmful. Logged for B-pass / Hermes scrutiny.

## Verification
- `test/contracts/streak_freeze_first_pro_grant_behavioral_test.dart` 5/5.
- Reader-manifest gate green; `flutter analyze` clean on the three service files.
- Migration 095 applied live; flag column + backfill verified via
  `information_schema` + a flagged-row count.

## See also
- lib/core/services/streak_progress_service.dart (`grantFirstProFreezes`, `resetToFreeCapOnLapse`, `commitRefill`, `prunePastHorizon`, `mergeFreezeProgress`, `commitConsume`)
- lib/features/train/repositories/workout_repository.dart (`reckonStreakDecayAndPersist` — the D2 gated single consume site)
- lib/core/services/day_rollover_service.dart + lib/features/train/providers/train_provider.dart (the two reckon triggers)
- lib/core/services/subscription_service.dart (`writeSubscriptionState` grant hook, `_downgradeLocally` lapse hook)
- supabase/migrations/096_update_streak_progress_column_ref_fix.sql (D1 RPC plural column-ref fix)
- lib/core/services/sync/sync_restore_completeness.dart (`syncFreezes`, `_restoreFreezes`)
- lib/features/home/providers/home_provider.dart (`streakFreezeMaxProvider`, `StreakFreezeNotifier`)
- supabase/migrations/095_streak_freezes_first_pro_grant_flag.sql
- docs/diagnoses/2026-06-11-restore-freezes-used-dates-clobber-a8f3d1.md (superseded per-week assumption)
