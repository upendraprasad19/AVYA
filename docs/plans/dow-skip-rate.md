---
plan: dow-skip-rate
revision: 5
date: 2026-10-22
blast_radius: account   # classifier on the planned file set: workout_repository.dart (feature), pattern_detector.dart, new lib/core/utils file, simulation_service.dart (feature, dev), sot_registry.yaml, tests
tier: M                 # §4.12.6: ai_coach ⇒ M. The nested lib/features/ai_coach/CLAUDE.md line fix does not make it L (precedent: docs/plans/train-coach-log-refresh.md R3A-P3, "CLAUDE.md" in the L list means the ROOT file).
execution_mode: inline  # §4.12.7; one worktree (.claude/worktrees/dow-skip-rate)
closes_oi: [OI-390]
---

# The coach stops telling a user they skip a weekday they never train, or one they did not single out

## Revision history

**rev 1 → rev 2.** Round 1 found 6 P1s:
- the east-of-IST key;
- `custom_template` days dropped;
- the contrast fires on a lapse;
- a recurrence of OBS-3;
- the stale copies.

**rev 2 → rev 3.** Round 2 found 2 P1s:
- T3 could not fire;
- D4(a)/(b) deferred bugs of the same class.

Rev 3 therefore added `getWorkoutAdherence` (U4), the `lapseFacts` walk (U5) and the streak anchor stop (U6).

**rev 3 → rev 4.** Round 3 found 3 P1s. All of them are in the rev-3 additions:
- B: adherence still reports `rate_percent: 0` when nothing was eligible.
- A: the T13 parity spec cannot pass on the old body.
- A: the T14 and upendra numbers were wrong.

Round 3 also found a new same-class writer defect. Device-generated schedule rows are keyed by local midnight east of IST (A P2-4). The IST tail keeps growing, so **§4.12.1 applies**: split, and ship the smallest converged piece.

**This batch (A) is:**
- the day-of-week fix (U1–U3, converged in design across rounds 1–3);
- `getWorkoutAdherence` (U4). It is the same class (a) as the bug, and it shares U2's walk.

**Batch B: IST-throughout for workout dates.** It takes the streak anchor stop, the `lapseFacts` walk,
`_getPlanStatus` / `getDaysSinceLastWorkout`, the generator's local-midnight keys, the remaining `DateTime.now()`
sites and the DST gap math. It becomes one OI with the full inventory (§5 D4), planned and reviewed on its own right
after this batch. In this batch's closure ledger it is `blocked_on_user` (the founder's scheduling go). It is a split
under §4.12.1, not a deferral.

Every finding is mapped in §7.

**rev 4 → rev 5.** Round 4 **converged** (A and B: no P0/P1). Rev 5 folds their P2s and P3s:
- **U3 week key:** a UTC-calendar `weekMondayIstDate` on each walked day. The naive `mondayOfIst(DateTime.parse(..))`
  shifts Mondays east of IST (A P2-1).
- **The U6 seeding recipe, made executable** (A P2-2/P2-3, B P2-2):
  - PRO first, or ≤ 28 days;
  - a dev-panel control;
  - a pure `simSkipsDay` seam;
  - a real read path for `coach_notices`.
- **A third recurrence**, Bug C, APK Test #3 (A P2-4).
- **The server tool `getProgressSummary.ts` `adherence_pct`** has the same class (a): a third D4 OI (B P2-1).
- **The D3 sequence** accounts for device-side history replay (B P2-3).
- **The P3s:**
  - the east-of-IST qualification;
  - mutations for the anchor, `|O| >= 2` and the tie-break;
  - Gate-42 path for `schedule_day_eligibility`;
  - tier 12 status;
  - M6 wording;
  - T14's today row;
  - `tryParse`;
  - citations;
  - U1's relation to `isTrainingDayType`;
  - the top-5 crowding note.

## 0. Evidence

**Observation** (founder, 2026-10-22, upendraprasad19@gmail.com): the "Status check" reply said "100% skip rate on
Sunday workouts". Sunday is always a rest day on that plan.

**Live `scheduled_workouts`** (56 IST days before today, upendra; "rest" is a status, because there is no `type`
column):
- Sunday: 0 workout rows, 5 `rest`.
- Rows in the window start 2026-09-14. The 90-day window also holds 2026-08-19..08-25:
  - 6 eligible `planned` rows, 3 of them templates;
  - 08-25 is `rest`.
- Until 10-02 every workout was completed except Fri 09-25.
- From Sat 10-03 he completed 3 of the next 16.
- Under the old code, with the 3 template completions (Mon 09-28, Thu 09-24, Sat 09-26) restored as
  `custom_template` and dropped, the walk goes Monday 0.4 → Saturday 0.25 → Sunday 0.0.

**Live check of the new rule** (round 2 B, SQL over every account): **0 accounts fire**. The old rule fires on 22,
nearly all of which scheduled days and completed none.

**For upendra under the T-file clock (T7):**

| Weekday | eligible | completed | isolated misses |
|---|---|---|---|
| Monday | 6 | 3 | 0 |
| Tuesday | 6 | 3 | |
| Wednesday | 6 | 5 | |
| Thursday | 6 | 3 | |
| Friday | 5 | 3 | 1 |
| Saturday | 5 | 2 | 1 |

There is no Sunday key, and **no insight** fires.

**Stale copies of false weekday-skip claims** (verified in rounds 1–3):
- **`memory_embeddings`: exactly 10 rows.**
  - upendra Sunday: `abcea8e9-ee4f-420a-a139-c47921da45df`. It was live-embedded by `ai-proxy:1319`, 4 s after the
    reply.
  - upendra Monday: 8 rows, from interactions that no longer exist:
    - `6a02dd2e-4190-4885-a3e0-63529324cd39`
    - `39c37011-9d46-4dbf-901a-d8118b1aea21`
    - `4562997e-d9af-4e09-80fb-92982f989508`
    - `94816c78-353e-44a0-98d9-616753549789`
    - `cb5f1afe-e9b3-4a5a-b94b-7e3dba20f762`
    - `10f082af-45d0-445b-a7a5-3f028515fce5`
    - `406058e1-37b5-48a7-8404-edcec53cfb7d`
    - `172b13a7-9e4f-4e19-b7f7-7d197c6f32b3`
  - shabaaadh: `59038339-fb3d-4f64-8f3f-d9a10e2fa258`.
  - `match_memories` ranks by cosine similarity only, so none of these age out.
- **`ai_coach_interactions`: exactly 3 rows** (claim in `ai_response`):
  - upendra `1dcf5d22…`, the newest of his 89 rows;
  - shabaaadh `17d62b49…`;
  - shabaaadh `1ecefd07…`. This is a v5 id, so an old build could upsert it again (OI-204).
  - `rolling-context` only processes rows older than a user's last 10, so tonight's run will not embed `1dcf5d22`.
  - **Until the fixed build is on the device, every Status check recreates the claim**, because `ai-proxy` embeds
    each reply live.
- **No other store holds the claim:** `coach_memory.*`, `user_preferences`, `notifications_inbox`, and every
  `snapshot_json` key except past `coach_notices` are clean. No in-repo reader uses a past day's `coach_notices`.
- **On the device:** the Hive `coachBox` reply is replayed in `history` for 8 exchanges
  (`ai_coach_repository.dart:175-178`).

## 1. Writers and readers (main `cbfa8884`)

### Writer: `getDayOfWeekCompletionRates` (`workout_repository.dart:1246-1291`)

**Primary defect (`:1287`):** `rates[name] = total > 0 ? done / total : 0`.

**Secondary defects:**
1. today is counted while undone;
2. travel and paused days count as misses;
3. `type != 'workout'` drops `custom_template` rows (`template_service.dart:146-155`; restore
   `sync_workout.dart` ~:2808-2815);
4. it uses `DateTime.now()`;
5. the weekday is taken in local time;
6. there is no anchor.

### Same class (a), fixed here (U4): `getWorkoutAdherence` (`workout_repository.dart:1180-1201`)

Its only caller is `ai_snapshot_builder.dart:442` (`days: 90`, for progress questions). It has the same defects,
plus `rate_percent: 0` when nothing is planned (`:1201`).

**upendra, 90 days:**

| Clock | eligible | completed | rate |
|---|---|---|---|
| 10-22, old code | 34 | 16 | 47% |
| T-file clock (Fri 23 Oct 00:30 IST; walk 07-25..10-22, where 10-22 is a planned Thursday), new rule | 40 | 19 | 47% |

U4 barely moves upendra's number. Its case is correctness: templates, travel and paused days, the anchor, today,
and an empty denominator.

### Reader: `PatternDetector._dayOfWeekPattern` (`pattern_detector.dart:405-428`)

It takes the lowest rate below 0.5 and emits `"Skips <Day> workouts <100-pct>% of the time."` at `medium`.

### Who sees it: only the coach

- `_getCoachNotices` (`ai_snapshot_builder.dart:998-1005`) feeds `snapshot.coach_notices`.
- The `ai-proxy` anti-fabrication rule (`index.ts:1119-1127`) **allows** percentage claims that `coach_notices`
  supports.
- `userMessage` reaches no live UI. `InsightCard` / `DeepAnalysisCard` are not mounted; the mounted widgets are
  `CoachDeepAnalysisCard`, `CoachInsightSection` (`welcome_view.dart:18,21`) and Home `AiInsightCard`
  (`aiInsightProvider`, `home_provider.dart:723`).
- `lib/features/ai_coach/CLAUDE.md` names the dead `insight_card.dart` in two rows: `:42`, and the
  `bodyweight_trend_nudge` row. Both are fixed.

### Not changed in this batch (Batch B inventory, §5 D4)

- the streak anchor stop: `workout_repository.dart:387-389`;
- `_earliestUserAnchor`'s `wlog_` source parsed as local midnight: `:174-186`;
- the `lapseFacts` walk: `workout_schedule_read_service.dart:2155-2159`;
- `_getPlanStatus` `since`/`sinceStart`: `ai_snapshot_builder.dart:1361-1376`;
- `getDaysSinceLastWorkout`: `workout_repository.dart:1298-1322`;
- generator keys local midnights through `istDateStr`: `workout_schedule_read_service.dart:238,271-276` →
  `workout_write_service.dart:1600`;
- `DateTime.now()` at `workout_repository.dart:1024,1118,1218,1328` and `pattern_detector.dart:84,118,168,359`;
- `blankGapBeforePlan` local `inDays`.

Every item is the same class (b): a date derived outside IST. None changes in IST, the CI zone, where the app's
users are.

**Known interaction:** east of IST, rows a device generated sit one key early (round 3 A P2-4).
- This batch's IST-keyed walk reads them as their keys say.
- **West of IST** the new code is strictly better.
- **East of IST** (e.g. UTC+9, local 00:00–03:30), the old code read the shifted row and labelled it with the local
  weekday, which was correct by accident. The new code labels it with the key's IST weekday, so a Monday row read
  under the Sunday key is labelled Sunday (round 4 B P3-4).
- **Exposure today:** none. Users are in India, pre-launch, and condition 3 needs 2 isolated misses.
- **Batch B acceptance case:** "DOW notice weekday under `TZ=Asia/Tokyo` with device-generated rows". Batch B fixes
  the writer.

## 2. Bug history (§4.1.5)

**Recurrence of Bug C, APK Test #3 (2026-04-26):** an "invented '100% skip' stat" / "100% skip Monday workouts"
(`test/contracts/ai_proxy_day_injection_test.dart:4-7,32`). It was fixed prompt-side, with the day injection.

**Recurrence of APK Test #4 OBS-3: "you skip Mondays 100% of the time".**
- Sources: `test/ai_coach/anti_fabrication_regression_test.dart:7-10,87`; the "Wrong" example at
  `captain_manual.ts:411`.
- It was fixed as model fabrication. **The writer was this method.**
- Live rows kept repeating it:
  - shabaaadh, 2026-05-13;
  - upendra, 2026-05-20: "My notes indicate you skip Monday workouts 100% of the time".

**Classes:**
- (a) an absent denominator reported as 0%;
- (b) a date derived outside IST, as in **bb3acc**;
- (c) a coach "fabrication" that quotes `coach_notices` is a writer bug.

**Eligibility precedents:** **d7a3e5 / C1** and `lapseFacts`.

**Value-semantics sweep:** these patterns were grepped across `lib/`, `test/` and `supabase/functions/`:
`Skips .* workouts`, `skip.*100%`, `day_of_week_pattern`, `workout_adherence`, `rate_percent`. The only server
mention of `coach_notices` is the anti-fabrication rule. Nothing parses the notice text or pattern id.
`workout_adherence` values are pinned nowhere; `ai_snapshot_budget_trim_test.dart:104` uses it only as filler.

**Diagnose-doc:** full template. `related_bugs: [bb3acc, d7a3e5]`; `recurrence:` Bug C (APK Test #3), OBS-3 (APK
Test #4), and the live rows. Both earlier tests get a pointer comment to the new T-file.

## 3. The fix (Batch A)

### U1: one eligibility rule (`lib/core/utils/schedule_day_eligibility.dart`, new, pure)

`ScheduleDayKind classifyScheduleDay(Map? row)` returns `excluded`, `pending` (eligible, not completed) or
`completed`.

| Row | Kind |
|---|---|
| null | excluded |
| type `rest`/`off`, or status `rest` | excluded |
| status `travel` | excluded |
| status `paused`/`moved`/`dropped` | excluded |
| `reason == 'pre_onboarding'` | excluded |
| status `completed`, any type (`workout`, `custom_template`, `logged`, unknown) | completed |
| type `logged`, not completed | excluded (an unscheduled ad-hoc session; no writer produces it) |
| anything else | pending |

**Why `logged` + `completed` counts:** the concurrent restore can stamp a scheduled completion as `logged`
(`sync_workout.dart:1267-1294`; `sync_service.dart:1800-1825`). Counting it can only raise a rate.

**Callers in this batch:** U2 and U4. `lapseFacts` adopts it in Batch B.

**Relation to the existing type rules** (`phase_completion.dart` `isTrainingDayType` / `isPhaseCompletionTrainingType`,
reached through `PlanEngineFlags.isRestDayConsideringLogged`, OI-126; round 4 A P3-5):
- Those rules classify a row's **type** only.
- U1 classifies **type + status + reason** for "was this day due, and was it done".
- U1 calls `isTrainingDayType(type)` for its rest/off line instead of re-listing the types, so the type half cannot
  drift.
- U1 is documented in that module's doc comment as the status-aware layer above them.

### U2: the walk and the writer (`workout_repository.dart`)

**One private walk:**
`List<({String istDate, int isoWeekday, String weekMondayIstDate, ScheduleDayKind kind})> _eligibleDaysBack(int days, {bool includeTodayIfCompleted = false})`.

`weekMondayIstDate` is computed with UTC calendar arithmetic from the IST date parts:
`DateTime.utc(y, m, d).subtract(Duration(days: isoWeekday - 1))`, formatted from its parts.
- Never `mondayOfIst(DateTime.parse(istDate))`. That parses to local midnight, and in Tokyo it puts every Monday in
  the previous week (round 4 A P2-1).
- It is a pure helper, `istWeekMondayOf(String istDate)`, in `lib/core/utils/ist_date.dart`. Its test lives in the
  T-file.

- **Step:** for `i` in `1 ..= days`, `t = nowWall().subtract(Duration(days: i))`.
  - `row = _schedule.getScheduleForDate(t)`, keyed by `formatDateKey(t)`.
  - `isoWeekday = istDateOf(t).weekday`.
  - When `includeTodayIfCompleted` is set, `i = 0` is added only if its kind is `completed`.
- **Anchor:** skip any day whose key is `< anchorKey` (U2a).
- **Excluded days** are dropped.
- Both U2 and U4 call it, so mutations to the walk redden both.
- Round 2 A probed it in 6 zones, including a DST crossing and ±1 minute around IST midnight. It is correct.
- **Reads go through `getScheduleForDate`.** That hides `moved`/`dropped` rows. It also demotes a `completed` row
  whose `completed_at` IST date falls before the row's date (0 live rows).

**U2a, anchor key:** `String? _earliestUserAnchorKey()` is new. It never uses `istMidnight`.
- onboarding: `istDateStr(DateTime.tryParse(profile['onboarding_completed_at']))`. A null or malformed value is
  skipped, as in `progression_resolver.dart:123-137`. Writers store a UTC instant with
  `Z` (`onboarding_provider.dart:505,864`; `auth_session_bootstrapper.dart:445`), so this is the same in every zone.
- `wlog_`: the earliest `date` string as written. The first 10 characters are taken only when the string is at least 10
  long and matches `^\d{4}-\d{2}-\d{2}`. It is already an IST key (`workout_repository.dart:637,645`).
- The result is the smaller string, or null when neither source exists. A null key means no anchor.
- Streak keeps the old `_earliestUserAnchor` until Batch B. Both helpers coexist, and the registry notes it.

**`getDayOfWeekCompletionStats({int weeks = 8})` replaces `getDayOfWeekCompletionRates`.** It has no other callers.

`DayOfWeekStats` holds:
- `byIsoWeekday`: `Map<int, ({int eligible, int completed, String firstIstDate})>`. Only weekdays with
  `eligible > 0` appear. `firstIstDate` is that weekday's first counted day.
- `days`: the walk output, oldest first.

### U3: reader (`pattern_detector.dart` `_dayOfWeekPattern`)

**Isolated miss.** Day D of an IST Mon–Sun week (grouped by `weekMondayIstDate`) counts when all of these hold:
- D is `pending`;
- the other *walked* eligible days of that week number at least 2 (call that set O);
- `3 * completed(O) >= 2 * |O|`.

Today and days outside the window are not walked. So a miss in the current, partial week rarely counts as isolated.

**Fires for D only if all four conditions hold:**
1. `eligible >= 3`;
2. `completed / eligible < 0.5`;
3. at least 2 isolated misses;
4. some eligible day of D falls in the last 14 walked days.

**Choice:** the most isolated misses, then the lowest rate, then Mon→Sun.

**Copy:**
- `coachNotice`: `"Missed $missed of $eligible scheduled $day workouts since $firstIstDate."` This matches Captain
  Manual rule 2's "Right" example.
- `userMessage`: the sentence is kept, with true numbers. It is not shown anywhere.

**Verified clean:** `_weekendNutrition` (`pattern_detector.dart:470-471`).

### U4: `getWorkoutAdherence` (`workout_repository.dart:1180-1202`)

Change:
- `_eligibleDaysBack(days, includeTodayIfCompleted: true)`. Today counts only if it is done, so a user who just
  trained sees it.
- `planned` = eligible days.
- `completed` = completed days.
- `missed` = pending days.

**When `planned == 0`, `rate_percent` is omitted** (class (a), round 3 B P1-1). The map stays `Map<String, int>`.
The snapshot reader passes it through as is; a model with no rate cannot cite one.

All other keys are unchanged.

### U5: no feature flag (§4.6 deviation, stated)

- The batch changes data in a notice and in one snapshot field, not a prompt template.
- It is account tier. `docs/blast_radius.yaml:20-25` requires a flag from platform tier.
- Rounds 1–3 agreed.
- If a switch is ever wanted, it is `disable_day_of_week_pattern`, which returns null. Never the old body.

### U6: on-device seeding (`lib/features/dev/simulation_service.dart` + `lib/features/dev/dev_panel_screen.dart`, feature tier)

Both files are reachable only in debug: the `/dev` route is `kDebugMode`-only (`app_router.dart:379-383,685`), and
`run()` returns early when not a debug build (`simulation_service.dart:222`).

**The seam.** A pure static
`SimulationService.simSkipsDay({required int isoWeekday, required Set<int> skipIsoWeekdays, required bool inBreakWindow, required double roll, required double adherence})`
decides skip vs complete:
- When the set is non-empty, it skips iff the weekday is in the set; the break window is ignored.
- Otherwise it keeps today's rule (`inBreakWindow || roll >= adherence`).
- `_simulateDay` (`:361-372`) calls it.
- **The RNG draw order is unchanged when the set is empty**, so default runs stay byte-identical.

**The API.** `run(...)` gains `skipIsoWeekdays` (default empty).

**The dev-panel control.** One button, "Sim +4 wk, skip Mondays", calls `run(ref: ref, days: 28, skipIsoWeekdays: {1})`.

**The recipe** (round 4 A P2-2, B P2-2):
1. `reset-test-user` on a test account.
2. Onboard with a **3-day plan**. Its pattern is Mon/Wed/Fri (`workout_schedule_read_service.dart:2189-2192`), which
   includes Monday.
3. Press "Sim +4 wk, skip Mondays" once. 28 days is Phase 1, so a free account still has rows, and there are 4
   Mondays, so `eligible >= 3` holds.
4. **Read the assertion** without needing a debug view:
   - the deterministic notice, via a read-only SELECT of
     `user_daily_snapshots.snapshot_json->'coach_notices'` for that user at the simulated date (the run ends with
     `flush('snapshot', sync.pushSnapshot)`);
   - plus a Status check whose reply quotes the Monday counts.
   - Coach turns are matched by content, not timestamp (e2e skill §8).
   - `_getCoachNotices` keeps the top 5 non-low insights. If the account has more than 5 high/medium insights, the
     check reads the full `PatternDetector.analyze()` list through a debug-only `debugPrint` added to that dev
     button's handler (round 4 A P3-6).
5. Clean up with `reset-test-user`.

### U7: docs, registry, process artifacts

**SoT** (`docs/sot_registry.yaml`):
- new `day_of_week_completion` (`behavioral_test_path`: the T-file);
- new `schedule_day_eligibility` (`behavioral_test_path`: the T-file, T12 and T7; Gate 42);
- update `workout_completion_status` (`:3933-3937`);
- the onboarding-anchor entry (`:5951-5963`) gains the new `_earliestUserAnchorKey` reader and a note that the old
  helper's `wlog_` source is wrong east of IST (Batch B);
- `workout_adherence`, if registered.

**Docs:**
- `lib/features/ai_coach/CLAUDE.md:42`, the `bodyweight_trend_nudge` row's dead `insight_card.dart` reader;
- `docs/architecture/ai-coach-detail.md:45`, the same claim plus a stale `ai_snapshot_builder.dart:911`.
- `docs/naming_conventions.md`: `ScheduleDayKind`, `classifyScheduleDay`, `DayOfWeekStats`, `_eligibleDaysBack`,
  `_earliestUserAnchorKey`, `istWeekMondayOf`, `simSkipsDay`, `skipIsoWeekdays`.

**Diagnose-doc** `docs/diagnoses/2026-10-22-dow-skip-rate-<id>.md`, full template. `touched_layers_checked`:
- tiers 1, 2: fixed_in_this_batch;
- tier 4: verified (§0);
- tier 12: `fixed_in_this_batch`; device evidence is added after the on-device run (round 4 B P3-6);
- others: not_applicable, with reasons.

**Closure** `docs/audit/dow-skip-rate.closure.yaml`. Every entry is terminal:
- the primary defect, 6 secondaries and U4: `closed_in_commit`;
- D3: `blocked_on_user`;
- D4 Batch B: `blocked_on_user`;
- D4 rolling-context OI: `blocked_on_user`;
- D4 `getProgressSummary` OI: `blocked_on_user`;
- `_weekendNutrition`: `verified_clean`.

**Before merge:**
- the plan-review record `docs/plan-reviews/dow-skip-rate.md`: `review_rounds ≥ 2`,
  `ground_truth_verified: true`, `verdict: converged`;
- a `/code-review` B-pass.

**Memory pair:** `feedback_absent_denominator_as_zero.md` (with the "fabrication was a writer" rule) and the
retrospective.

**Debugging skill:** red flags citing the T-file.

**On-device:**
- the U6 seeded account fires the Monday notice (recipe in U6);
- upendra: no day named. This is checked only once the old reply has left the 8-exchange history window, which takes
  at least 8 exchanges on the fixed build (round 4 B P2-3).

**OI board:** close OI-390.

## 4. Tests

**New file:** `test/contracts/day_of_week_completion_writer_to_reader_test.dart`.
- Real Hive, `bodyweight_trend_nudge_test.dart` harness.
- UTC-flagged clock `setTestClockTo(DateTime.utc(2026,10,22,19,0))` (Fri 23 Oct 00:30 IST). The walk covers
  2026-08-28..10-22 for 56 days, and 07-25..10-22 for 90.
- Every fixture states each walked day.
- Rows are seeded by literal key strings.
- Assertions filter `patternId == 'day_of_week_pattern'`.
- Counts and notice strings are exact.
- **CI coverage:** keys come from `istDateStr` of UTC instants, and the anchor sources are UTC instants or verbatim
  strings, so every case here is zone-independent and runs in CI.

| # | Fixture | Expected |
|---|---|---|
| T1 | Mon–Sat `workout` completed, Sun `rest` | no Sunday key; no insight |
| T2 | Mon/Wed/Fri completed; others `rest`/absent | keys {1,3,5}; no insight |
| T3 | Mon/Wed/Fri. Mondays 08-31, 09-07, 09-14, 09-21, 09-28 missed with Wed+Fri done; 10-05, 10-12, 10-19 done | `"Missed 5 of 8 scheduled Monday workouts since 2026-08-31."` |
| T3b | T3 plus a completed `workout` row on Fri 08-28 and Thu 10-22 | `days.first.istDate == '2026-08-28'`, `days.last.istDate == '2026-10-22'` |
| T3c | `istWeekMondayOf` on '2026-10-19' (Mon), '2026-10-25' (Sun), '2026-01-01' (Thu) | '2026-10-19', '2026-10-19', '2025-12-29' |
| T3d | tie-break: Monday and Wednesday each with 2 isolated misses, Monday rate 0.4 and Wednesday 0.25 | fires Wednesday (lower rate beats Mon→Sun order) |
| T3e | Mondays missed in weeks where only ONE other eligible day exists (done) | no isolated misses; no insight |
| T4 | T3's Monday shape; clock `DateTime.utc(2026,10,26,4,30)` (Mon 10:00 IST); today a `planned` Monday; 08-31 walked but has no row | Monday `eligible == 7` |
| T5 | Mondays: 2 missed (isolated), 2 done, 2 `travel`, 1 `paused`, 1 `moved`; Wed/Fri done | Monday {4, 2}; no insight |
| T6 | 6-day plan, every day missed for 8 weeks | no insight |
| T7 | upendra's live rows (§0, incl. `custom_template`) | no insight; counts as §0 |
| T8 | T3 with 08-31 as a missed `custom_template` | T3's string |
| T9 | `logged`+`completed` rows on unplanned Sundays; a late-restored `logged`+`completed` Monday | Sunday key {n, n}, no insight; Monday counts as completed |
| T10 | anchor from `onboarding_completed_at` = `2026-09-13T20:00:00Z` (IST 09-14 01:30); missed rows on 09-13 and 09-14 | 09-14 counted, 09-13 not |
| T10b | anchor from a `wlog_` row only, `date: '2026-09-14'`; same rows | same |
| T11 | Monday pattern in weeks 8–5 only; no Monday rows in weeks 4–1 | no insight |
| T12 | `classifyScheduleDay` table, one row per U1 line | kinds as listed |
| T14 | `getWorkoutAdherence(days: 90)` on upendra's live rows incl. 08-19..08-24 (fixture notes say why), plus today 10-23 as a `planned` Friday | `{planned: 40, completed: 19, missed: 21, rate_percent: 47}` (today not counted) |
| T14b | `getWorkoutAdherence` with anchor = today; and with every day `travel` | `planned: 0`, no `rate_percent` key |
| T14c | today's row `completed`; another clock where today's row is `planned` | counted / not counted |
| T16 | Monday eligible exactly 2, both isolated misses, one in the last 14 days | no insight |
| T17 | `SimulationService.simSkipsDay` table: in the set → skip regardless of roll and break; not in the set with a non-empty set → complete even in the break window; empty set → today's rule | as listed (`test/features/dev/sim_skips_day_test.dart`) |

**Mutations (§4.4 rule 21).** Each is applied, confirmed with `grep -c`, and run; reddened counts are recorded.

| M | Mutation | Must redden |
|---|---|---|
| M1 | zero-count weekdays back, plus condition 3 dropped | T1, T2 |
| M2 | walk `i = 0 ..< days` | T4 (Monday 8); T14 (10-23 counted: {41, 19, 22, 46}) |
| M3 | `travel`/`paused` → `pending` | T5 (2/7, fires) |
| M4 | condition 3 dropped | T6, T7 (Saturday) |
| M5 | `isoWeekday = t.weekday` (local) | T3, any zone |
| M6 | walk `DateTime(now.y, now.m, now.d - i)` | T3b, through `days.last` (10-21 in IST, UTC and the west; 10-19 in Tokyo, Kiritimati and Lord_Howe) |
| M7 | condition 1 dropped | T16 |
| M8 | `custom_template` → excluded | T7, T8, T14 |
| M9 | anchor key from `istMidnight(DateTime.tryParse(wlogDate))` parts | T10b under `TZ=Asia/Tokyo` (recorded; CI zone cannot redden it) |
| M10 | condition 4 dropped | T11 |
| M11 | `logged`+`completed` → excluded | T9 |
| M12 | `rate_percent` back to `: 0` | T14b |
| M13 | `includeTodayIfCompleted` ignored | T14c |
| M14 | `skipIsoWeekdays` ignored in `simSkipsDay` | T17 |
| M15 | anchor ignored entirely | T10, T10b (in CI) |
| M16 | isolated rule `|O| >= 1` | T3e |
| M17 | tie-break by Mon→Sun only | T3d (would fire Monday) |
| M18 | week key via `mondayOfIst(DateTime.parse(istDate))` | T3c under `TZ=Asia/Tokyo` (recorded) |

**Must stay green:**
- the streak tests, incl. `onboarding_streak_anchor_ist_midnight_test.dart` (streak code is untouched);
- `lapse_gap_policy_behavioral_test.dart`;
- `ai_snapshot_budget_trim_test.dart`.

All run in the full gate loop.

## 5. Founder decisions

**Founder, 2026-10-23: plan approved as written** (D1 the recommended rule, D2 keep). **D3 approved**, run in the
sequence below (steps 1-2 come first, so the deletes wait for the fixed build on device). **D4 minted:** (a) OI-397,
(b) OI-398, (c) OI-399.

- **D1, the "singled out" rule.** Recommended: at least 2 isolated misses, in weeks where at least 2/3 of the other
  days were done. Today 0 live accounts fire it; 22 fire the old rule.
- **D2, `userMessage` copy.** It is not shown anywhere. Keep it.
- **D3, stale false claims.** These are live prod deletes, so each one needs your go (§4.3). Sequence (round 4 B
  P2-3):
  1. Put the fixed build on upendra's device. Before that, every Status check recreates the claim.
  2. Have 8 or more coach exchanges. The phone replays its own Hive history, which no cloud delete can reach, and a
     repeat would be live-embedded again.
  3. Delete the 3 `ai_coach_interactions` rows (upendra `1dcf5d22…`, shabaaadh `17d62b49…`, `1ecefd07…`) and the 10
     `memory_embeddings` rows.
  4. A day later, re-run the full phrase-sweep SELECT, not only the 13 ids. Any new hits are deleted under the same go.
  - Past `user_daily_snapshots` stay; nothing reads them.
- **D4, three new OIs.** All are filed with `mint_oi.sh`, which pushes.
  - **(a) Batch B: IST-throughout for workout dates.** The inventory is in §1, "Not changed". It includes a writer
    (the generator's keys) and the streak. Planned and ×2-reviewed on its own, right after this batch.
  - **(b) `rolling-context` re-embeds the same interaction on several nights**, with no dedupe on
    `original_interaction_id` (31 repeats in the week of 10-12). It is a catastrophic-tier EF with its own
    authorisation, and it is not this batch's class.
  - **(c) The server coach tool `getProgressSummary` `adherence_pct`** (`supabase/functions/_shared/tools/progress/getProgressSummary.ts:63-65,138-140`):
    - it reports 0 when nothing was planned (class (a));
    - it counts today before it is done;
    - it counts travel days (`_shared/workout_statuses.ts`).
    - It is a FREE tool answering "how am I tracking". It is an Edge Function, so it needs a deploy go: L tier, its
      own batch.
    - Live exposure: none of 357 interactions mention adherence.
    - Sweep pattern used to find it: `(adherence|rate)_?(pct|percent)` with `> 0 ? … : 0` (round 4 B P2-1).

## 6. Round 4 answers

- **Q1.** Yes. There is no double count; U2 never sets the flag (round 4 A).
- **Q2.** Yes, confined to dev. Existing sim tests stay green with an empty default set (round 4 A, B).

## 7. Finding map

| Round, finding | Severity | Disposition |
|---|---|---|
| R1 A1/B1 east-of-IST key | P1 | U2 instant walk; M5, M6 |
| R1 A2/B7 `custom_template` | P1/P2 | U1; T7, T8, T12; M8 |
| R1 B2 lapse fires | P1 | U3; T6, T7; M4 |
| R1 B3 recurrence OBS-3 | P1 | §2 |
| R1 B4 stale copies | P1 | §0, D3 |
| R1 P2/P3 (Home unmounted, CI zone, T4/M2, drift wording, flag, artifacts, copy, misc) | P2/P3 | folded in revs 2–4 |
| R2 A1/B T3 cannot fire | P1 | T3 5-of-8, per-weekday date |
| R2 B P1-1 D4(a)(b) deferral | P1 | rev 3 took them in; rev 4 keeps (b) in (U4) and splits (a) into Batch B under §4.12.1 (D4a), `blocked_on_user` |
| R2 P2/P3 (M7, anchor, "scheduled", parity, `logged`, citations, read views, D3, assert filter, edges, copy, seeding) | P2/P3 | folded |
| **R3 B P1-1 adherence 0% on empty** | **P1** | U4 omits `rate_percent`; T14b; M12 |
| **R3 A P1-1 T13 parity cannot pass on old body** | **P1** | `lapseFacts` moves to Batch B; T13 leaves this batch |
| **R3 A P1-2 T14 / upendra numbers** | **P1** | §1, U4 and T14 = {40, 19, 21, 47}; Aug rows noted |
| R3 A P2-1/B P2-1 anchor key east of IST (`wlog_`) | P2 | U2a per-source key; T10, T10b; M9 |
| R3 A P2-2 M6 cannot redden | P2 | T3b; M6 |
| R3 A P2-3 M9 zone | P2 | M9 recorded under Tokyo; T10/T10b CI-safe by construction |
| R3 A P2-4 generator keys east of IST | P2 | §1 known interaction; Batch B (D4a) |
| R3 B P2-2 nothing in CI guards zone fixes | P2 | U2/U2a keys are zone-independent by construction (UTC instants, verbatim strings); remaining zone code is Batch B |
| R3 B P2-3 U2/U4 share walk in prose only | P2 | `_eligibleDaysBack` shared; M2, M8 hit T14 |
| R3 B P2-4 same-class sites | P2 | §1 inventory → Batch B (D4a) |
| R3 B P2-5 on-device seeding | P2 | U6 `skipIsoWeekdays`; T17; M14 |
| R3 B P2-6 SoT anchor entry, comments | P2 | U7 registry note; the comments change with Batch B, which changes that code |
| R3 A P3, B P3-1..5 | P3 | T4 wording; today-if-completed (U4); D3 timing and re-check; tier note (frontmatter); `bodyweight_trend_nudge` row (U7) |
| **R4 A, B** | — | **CONVERGED** (no P0/P1) |
| R4 A P2-1 / B (none) week key east of IST | P2 | `istWeekMondayOf`; T3c; M18 |
| R4 A P2-2 / B P2-2 free account runs out | P2 | U6 recipe: 28 days, 3-day plan |
| R4 A P2-3 / B P2-2 sim seam, dev control, read path | P2 | `simSkipsDay`; dev button; snapshot SELECT; T17 |
| R4 A P2-4 Bug C recurrence | P2 | §2; diagnose-doc |
| R4 B P2-1 `getProgressSummary` adherence | P2 | D4(c) OI, ledger entry |
| R4 B P2-3 D3 vs device replay | P2 | D3 sequence; on-device line |
| R4 A P3-1..6, B P3-4..6 | P3 | M6 wording; T14 today row; `tryParse` and length guard; citations; U1 relation; top-5 note; east-of-IST qualification; M15–M17; Gate-42 path; tier 12 |
