# Plan — Home insight follows today's row (v6)

Status: **v6 — CONVERGED (round 6, 2026-10-03; mechanical edits applied below).** Founder decisions (chat): 2 batches (2026-10-02); U5 split out
(2026-10-03); after round 5, "Option A: ship U1 alone, then plan OI-284 + OI-294" ("OK proceed", 2026-10-03).
Branch/worktree: `swap-cross-device-reconcile` (base `origin/main` c2bb0f75). Tier **M** (not S: the bug is a
recurrence of the b3c9d4 invalidation-list class ⇒ full template). Blast radius **feature** (measured:
`scripts/blast_radius_from_diff.dart` on `lib/features/home/providers/home_provider.dart` + test + board).
Execution mode: inline, one coordinator. No migration, no Edge Function, no sync code, no live write.

**Review rounds (v5 lineage).** Round 5 reviewed U1 in v5 (mechanism sound; scope wording too wide). Round 6
reviews this v6. Record: `review_rounds: 2`.

## 0. History

v1-v4 (rounds 1-4) and v5 (round 5): each round found a new design defect in the sync-side units, which were
split out to the OI board (§6). U1 is the one unit whose mechanism held.

## 1. Observation (founder, 2026-10-01) and what this batch covers

After a day swap the Home insight sentence kept the old workout name. This batch fixes the insight for every
writer that refreshes Home's Today card (`invalidate(todayWorkoutProvider)`); ref-less writers that refresh
neither (`deload_evaluator.dart:223`, lazy writes in `workout_schedule_read_service.dart:~278-577`) are OI-295. It does NOT fix the cross-device case: the launch restore never invalidates
`todayWorkoutProvider` (OI-294), and the completed-row title is frozen (OI-284). After this batch the insight is
exactly as fresh as Home's Today card — never staler.

## 2. Ground truth (verified in rounds 4-5 and re-read for v6)

- Reader: `AiInsightNotifier.build` (`lib/features/home/providers/home_provider.dart:649-664`) watches only
  `authUserIdTokenProvider`; `_computeScheduleInsight` reads today's row with
  `ref.read(workoutScheduleServiceProvider).getScheduleForDate(now)` (`:670-671`). It recomputes only when
  someone invalidates `aiInsightProvider`.
- Writers of today's row invalidate `todayWorkoutProvider` at 21 sites; only 7 files invalidate
  `aiInsightProvider`. Misses include the day-swap batch (`lib/features/train/providers/day_swap_provider.dart:75-82`),
  swap sheets, edit-log sheet, chat log, coach tools, template edits.
- `TodayWorkoutNotifier.build` (`home_provider.dart:519-529`) returns
  `ref.read(workoutScheduleServiceProvider).getScheduleForDate(DateTime.now())` — the SAME read the insight does,
  same clock (`DateTime.now()`), and it watches only `authUserIdTokenProvider` (no cycle back to the insight).
  `getScheduleForDate` returns a fresh Map each call, so each rebuild notifies.
- Precedent: `StreakWarningEligibilityNotifier` already `ref.watch(todayWorkoutProvider)` (`home_provider.dart:369`).
- Rollover: `lib/core/services/day_rollover_service.dart` invalidates both providers (`:205`, `:282`).
- The only `aiInsightProvider` invalidations NOT paired with `todayWorkoutProvider` are nutrition writes
  (`lib/app.dart:65`, `lib/core/services/nutrition_write_service.dart:942`): they rebuild the insight, which then
  reads the cached today row — correct, because a meal does not change today's row.

## 3. Bug-history (§4.1.5)

Recurrence of b3c9d4 ("THE omission", a forgotten entry in a per-screen invalidation list,
`lib/features/home/screens/home_screen.dart:144`) and F5 (`test/providers/ai_insight_invalidation_test.dart`).
Known-good fix pattern for that class: derive instead of list (b3c9d4 made the three name providers derive from
`userProfileProvider`). Sweep before coding (`git grep` whole repo): `_computeScheduleInsight`,
`AiInsightNotifier`, `aiInsightProvider`, `workoutScheduleServiceProvider` in `test/`; pins that must survive:
`test/providers/ai_insight_invalidation_test.dart` (call sites stay), `test/contracts/training_day_predicate_wiring_test.dart:42`
(`PlanEngineFlags.isRestDayConsideringLogged` stays in `home_provider.dart`),
`test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart:45-48`,
`test/contracts/cold_start_day_rollover_test.dart:122`, `test/contracts/phase_unlock_end_to_end_test.dart:194`.

## 4. The change (U1)

`AiInsightNotifier.build`: `final schedule = ref.watch(todayWorkoutProvider);` and pass it to
`_computeScheduleInsight(schedule)`, which drops its own `ref.read(...)` (logic and strings unchanged).
KEEP `ref.watch(authUserIdTokenProvider)` (pinned per Notifier by
`test/contracts/auth_invalidation_contract_test.dart:34`). `_getLatestCoachTip` unchanged. Existing explicit `invalidate(aiInsightProvider)` calls stay. Not an §4.6 area
(UI provider; no payment/sync/auth/AI-prompt/plan-generator) ⇒ no kill switch. Comment cites b3c9d4 and the
diagnose id.

## 5. Tests (rule 21)

New `test/contracts/ai_insight_follows_today_row_test.dart` (pattern of
`test/contracts/streak_warning_eligibility_logged_test.dart`: real Hive session, real `ProviderContainer`):
1. Behavioural (the regression): real `todayWorkoutProvider` (not overridden); write `schedule_<today>` named
   "Push + Core" planned; read the insight; overwrite the row as "Pull + Core"; invalidate ONLY
   `todayWorkoutProvider`; the insight now contains "Pull + Core". Fails on main (insight keeps "Push + Core").
2. Byte-identity (passes on main AND on the branch; NO `todayWorkoutProvider` override — main ignores one):
   real `schedule_<today>` rows for completed, rest, `type:'logged'` with the OI-126 flag OFF ("No workout
   scheduled…") and ON ("…is scheduled…"), a terminal `moved` row (null path), and no row → each existing
   sentence exactly.
Setup: `streak_warning_eligibility_logged_test.dart` setUp as-is (`HiveUserSession.openForUser` opens
`coachBox`, needed by `_getLatestCoachTip`); override `authUserIdTokenProvider` with a value (`:69-73`); keys via
`formatDateKey`. Mutation: restore `ref.read(workoutScheduleServiceProvider).getScheduleForDate(now)` in place of
the watch; `grep -c` confirms; record the red count (expected: test 1 only, since test 2 reads Hive either way).

## 6. Not in this batch (each on the OI board with evidence; uncommitted board edits ride this batch's commit)

OI-284 completed title + completions name · OI-294 launch restore never refreshes Home · OI-292 morning-alert
reads yesterday's snapshot · OI-293 restore outcomes unobservable · OI-285 merge lock · OI-286 replaced-swap
notice · OI-287 allowance cross-device · OI-288 residual-text gate · OI-289 nutrition probe · OI-290
`week_number` · OI-295 ref-less schedule writers · OI-261 displaced (existing) · OI-279/280/281 (resilient-client session). OI-291 was
minted then released (its kill switches no longer exist). Next plan, per the
founder: OI-284 + OI-294 together.

## 7. Order, gates, artifacts

1. Round 6 on v6. 2. Record `docs/plan-reviews/swap-cross-device-reconcile.md` (`review_rounds: 2`,
`ground_truth_verified: true`, `verdict: converged`, `blast_radius: feature`). 3. Test first (watch RED on
main), then the change. 4. Full gate loop after the last edit (§4.12.8): `flutter analyze lib/`,
`TZ=Asia/Kolkata flutter test`, `sh scripts/pre-commit.sh`. 5. Diagnose-doc (full template, recurrence b3c9d4,
`touched_layers_checked`), SoT registry: UPDATE the existing `aiInsightProvider` reader row
(`docs/sot_registry.yaml:474-478`: `line_range` → 649-690, `fields_read` → via `todayWorkoutProvider`), `lib/features/home/CLAUDE.md`,
bug-class red flag ("derive, don't list"). 6. Closure ledger `docs/audit/swap-cross-device-reconcile.closure.yaml`
(U1 `closed_in_commit`; each §6 item `blocked_on_user`, `reason:` founder's Option-A scope split 2026-10-03 + its OI). 7. Code review before
the merge. 8. Commit/push/merge/APK only on an explicit ask.
