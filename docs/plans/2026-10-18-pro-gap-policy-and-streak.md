# PRO long-gap policy, streak gap fix, gap-aware ranks, coach plan_status (Piece B)

Branch `pro-gap-policy-and-streak`. Follows Piece A (PR #120, `be0d8f89`: the next PRO phase appears on app open).
Execution mode: **inline** (one worktree, no subagent integration). Tier: L (plan engine start date, streak, rank).
Founder decisions (2026-10-17/18, chat): D1 + Option B, freezes zeroed after a blank gap, empty days count as missed for the
completion-rate ranks, `plan_status` coach fact now (Edge Function prompt change = a separate go).

## Policy (what the user sees)

1. **In-phase absence** (phase still running): nothing changes. Past planned rows are missed, the streak breaks, freezes drain
   through the missed rows. (Already true; pinned by a test.)
2. **Return after the phase ended, gap under about four weeks** (the next phase, started the day after the old one ended, still
   contains today): the next phase starts at `plan_end + 1` (a Monday). Every day that already passed is a planned, uncompleted
   row, shown as missed. The phase number goes up by 1. Weights are already reduced by the detraining table (unchanged).
3. **Return after a longer gap**: ONE phase is generated, starting the Monday of today (the pre-existing behaviour). The weeks in
   between have no rows ("blank"). The phase number goes up by 1.
4. **PRO only; Phase 1 -> 2 is always a fresh start (see below).** The advance already requires `isPro()`; a lapsed PRO user is a free user (unchanged, untouched).
5. **Graduation (explicit unlock tap) is a fresh start**: it keeps the old rule (`gapStart: false`): never backdated.
6. **Streak**: an unscheduled (rowless) day before today that has a LATER schedule row after it (a mid gap: a new phase followed)
   ends the chain even when the streak so far is 0. No freeze is spent for it. Today with no row yet stays tolerated (day-boundary
   generation lag). A TRAILING gap (no row after it: a free user whose plan expired, a PRO user whose advance has not run yet) is
   skipped as before: a paywall or an offline phone is not a miss (B-pass P1). Previously a rowless day with streak 0 was always
   skipped, so the walk crossed a mid gap and counted old completed days (the Home "1 DAY" symptom).
7. **Freezes**: when a phase is generated after a blank gap of at least 7 days (new start later than `old plan_end + 1`),
   freezes go to 0 AFTER the phase counter commit succeeded (a declined or owner-swapped commit touches nobody's freezes). The
   weekly refill (+1 per Monday opened, cap 3 PRO / 1 free) continues from there. Math: 7 blank days hold at least 3 planned
   days (the smallest plan is 3 days a week), which equals the PRO cap of 3, so zeroing equals simulating the missed days.
   The automatic path always leaves 28+ blank days; only the graduation unlock (fresh start) can leave a shorter one, hence the
   7-day floor (`kMinBlankGapDaysForFreezeReset`, review round 1). A restore cannot refund the zero when `last_refill` is equal
   on both sides (`mergeFreezeProgress` takes the lower); a strictly newer cloud `last_refill` with `available > 0` and an
   unlanded push could, which is the disclosed edge (the push runs right after the write).
8. **Completion-rate ranks** (MCPO, officer track): rowless days after the user's first schedule row, before the LAST schedule row
   and before today count as scheduled AND missed (a trailing gap is not a miss, same reason as the streak) in `completionRateOverWindow`. A 13-week break now costs the rate instead of being ignored. No rank is
   ever demoted (`shouldPromote` stays monotonic). The SERVER rank cron (`evaluate-rank-promotions`, `_shared/rank_engine.ts`)
   gets the same rule behind an opt-in `countBlankDays` parameter and env `DISABLE_LAPSE_GAP_POLICY` (review round 2, P1);
   future-prediction's 4-week adherence keeps the old semantics. Deploying the Edge Function is a separate founder go.
9. **Coach `plan_status`** (client snapshot only): present only when there is a lapse signal, else the key is omitted (byte
   identical for everyone else). It is a STATE, not a flag: present while the user has had >= 14 idle days, or a blank gap sits
   before the current phase AND they have not trained since it began. Present while >= 14 idle days, or a blank gap of >= 7 days precedes the phase and the user has not trained since it began. The idle days come from `progress.last_workout_date` (cheap), falling back to the box scan. Fields: `days_since_last_workout`, `current_phase`, `phase_started_on`,
   `blank_gap_days_before_phase`, `missed_days_in_phase`, `lapsed`. The Edge Function prompt rule that tells the coach
   how to use it is OUT of this PR (needs its own go).

## Writers and readers

| Concept | Writer | Reader |
|---|---|---|
| next phase start | `WorkoutScheduleReadService.nextPhaseStartDate({gapStart})` (new pure `phaseStartAfterGap` in `lib/core/utils/gap_policy.dart`) | `autoGenerateNextPhaseIfNeeded`, `runGraduationPhaseAdvance` |
| streak walk | `WorkoutRepository._calculateStreak` | `currentStreak`, `reckonStreakDecayAndPersist`, rank gates, Home |
| freeze zero | new `StreakProgressService.resetFreezesAfterGap` (pushes via `syncFreezes`), called from `_runAdvanceWith` and `runGraduationPhaseAdvance` only after `commitPhaseAdvance` returned true | Home refill, `mergeFreezeProgress` (same-week takes the LOWER `available`, so a zero sticks) |
| completion rate | `WorkoutRepository.completionRateOverWindow` | `RankService._qualifies` |
| plan_status | `AiSnapshotBuilder` (null-aware key) | ai-proxy prompt (untouched here) |
| server completion rate | `_shared/rank_engine.ts` `completionRateOverWindow(countBlankDays)` | `evaluate-rank-promotions` (cron) |

## Kill switch (section 4.6)

One switch, `disable_lapse_gap_policy` (configBox, default absent = policy LIVE; `true` restores items 2, 3, 6, 7, 8, 9 verbatim:
start date `max(today, plan_end + 1)`, streak skip-at-zero, completion rate ignoring rowless days, no freeze zeroing, no
`plan_status`). Logged in `docs/ship_dark_pending_review.yaml` is NOT needed (default live, full review applies).

## Tests (behavioral, each mutated)

- `test/core/gap_policy_test.dart`: pure `phaseStartAfterGap` table (gap 0, 20, 27, 28, 70 days; non-Monday inputs; flag off).
- `test/contracts/lapse_gap_policy_behavioral_test.dart`: Hive-backed: (a) streak probe cases (completed days, blank gap, today
  with and without a row; with and without freezes; blank gap spends no freeze); (b) planned gap rows drain freezes then break;
  (c) completion rate with a blank 13-week gap; (d) `resetFreezesAfterGap`; (e) `plan_status` omitted for a normal user and
  present for a returned one; (f) kill switch restores old outputs.
- Repoint `test/contracts/phase_unlock_start_date_test.dart` (greps `candidate.isAfter(today)`).
- Existing streak / rank / phase-advance suites run unchanged.

## Out of scope (stated, not deferred)

Edge Function prompt change for `plan_status` (founder-owned go). Re-entry volume rule: founder deferred the question until
after B; not part of this PR.

Free user who upgrades (founder decision 2026-10-18): leaving Phase 1 is a fresh start. Phase 1 is the free phase, so
`autoGenerateNextPhaseIfNeeded` passes `gapStart: currentPhase > 1`: a Phase 1 -> 2 advance starts on THIS week's Monday (or
`plan_end + 1` when that is later), with no backdated days. No PRO-activation date is stored and no subscription code changes.
Side effect: a PRO user who lapsed during the tail of Phase 1 also gets a blank gap instead of missed days (accepted).

## Review log

Round 1 (fresh Sonnet, plan + diff): 7 findings, all fixed or disclosed (freeze reset moved behind the commit; 7-day floor;
`plan_status` as a state; mid-week snap-back pinned; restore edge disclosed). Round 2 (post-round-1 plan): P1 server rank cron
used the old rate -> mirrored in `_shared/rank_engine.ts`; stale registry/doc text fixed. B-pass (third reader, final diff): P1 the
streak break hit free users with an expired plan -> mid-gap only; P2 `plan_status` cost -> `last_workout_date` first; P2 sync-lag
caveat documented for the server rate; P3 test strength (flip-ascending fake), 7-day floor for `plan_status`, date-shaped keys only.
