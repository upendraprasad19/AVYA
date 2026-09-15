# APK Test #8 — Design Spec

**Date:** 2026-05-02
**Branch (target):** `feat/apk-test-8-batch`
**Predecessor:** APK Test #7 (merged to main, commit `9c815ba`, 2026-05-01)
**Source observations:** on-device install of Test #7 APK, three categories of bugs reported.

---

## 1. Context

User installed the Test #7 APK and surfaced three categories of issues that ship Test #8:

1. **Workout receipt shows "0 sets" everywhere** despite Supabase showing the workout was logged correctly (1 `workout_logs` row, 7 `workout_log_exercises` rows, 19 `workout_log_sets` rows for 2026-05-02).
2. **Profile rank pill** consumes its own row of vertical space; the banner-overlap area between avatar and `GO PRO` pill sits empty.
3. **Profile card stack** has 16 dp rounded corners + 8 dp gaps between Daily Goals / Badges / Journey / Body Stats / My Targets, which feels loose and was supposedly tightened in a prior batch.

Investigation surfaced two more issues worth addressing in the same batch:

4. **`wake_up_time` is collected at onboarding but never read by any Edge Function.** The morning-alert push fires at fixed 7 AM IST for everyone regardless of their wake time. Internal data going unused.
5. **Test gap:** the receipt bug shipped because no test exercises the `WorkoutWriteService` → consumer round-trip. Every consumer is unit-tested against synthetic Hive input using legacy field names.

Test #8 ships as five themes (A–E).

---

## 2. Ground truth from Supabase

User: `upendraprasad19@gmail.com`, id `d7a67a37-0b05-4f0a-b13c-388bff3cb59b`.

| Table | Rows | Notes |
|---|---|---|
| `users` | 1 | `terms_accepted_at: NULL` (separate sync gap, deferred) |
| `user_profile` | 1 | `wake_up_time = 07:00:00`, `session_duration_minutes = 90`, `diet_preference = 'vegetarian'`, `current_rank_code = 'SD2'` — onboarding writes these correctly |
| `workout_logs` | 1 | `BACK DAY A`, duration 5433 s, parent row |
| `workout_log_exercises` | 7 | `set_number` field correctly carries total sets per exercise |
| `workout_log_sets` | 19 | per-set rows, Test #6 architecture working |
| `nutrition_logs` | 0 | (user hadn't logged meals) |
| `scheduled_workouts` | 0 | (separate gap — Hive schedule not syncing to cloud, **deferred**) |

**Conclusion:** Test #6 `WorkoutWriteService` 3-tier cloud sync (workout_logs + workout_log_exercises + workout_log_sets) is working end-to-end. The receipt bug is purely client-side rendering — a Hive field-name contract mismatch.

---

## 3. Theme A — Receipt sync field rename

### Root cause

Test #6 architectural rewrite renamed Hive `exlog_*` fields to align with cloud column names. `WorkoutReceiptData.fromExerciseLogs` was not updated.

| Field semantics | `WorkoutWriteService` writes | `WorkoutReceiptData` reads | Impact |
|---|---|---|---|
| Total sets for the exercise | `set_number` (int) | `sets_completed` | Always 0 → "0 sets" badge + summary |
| Per-set breakdown list | `sets` (List of Map) | `sets_detail` | Empty → falls through to legacy single-chip path |
| Total reps across sets | `reps_completed` | `reps_completed` | OK |
| Best weight across sets | `weight_kg` | `weight_kg` | OK |
| Total volume | `volume_kg` | `volume_kg` | OK (1840 kg displayed) |
| PR flag | `is_pr` | `is_pr` | OK (PRs displayed) |

### Fix

`lib/features/train/widgets/workout_receipt_card.dart`:

```dart
// line 274 (current)
final sets = (log['sets_completed'] as num?)?.toInt() ?? 0;

// becomes
final sets = (log['set_number'] as num?)?.toInt()
    ?? (log['sets_completed'] as num?)?.toInt()
    ?? 0;
```

```dart
// line 287 (current)
final setsDetail = log['sets_detail'];

// becomes
final setsDetail = log['sets'] ?? log['sets_detail'];
```

The fall-back to legacy keys (`sets_completed`, `sets_detail`) keeps any pre-Test-#6 Hive entries (if they survive in current users' devices) rendering correctly.

### Regression test

`test/train/receipt_after_write_service_test.dart` (NEW):

```dart
group('WorkoutReceiptData.fromExerciseLogs after WorkoutWriteService', () {
  test('renders sets/reps/weight/PR for weight_reps exercise', () async {
    await _initInMemoryHive();
    await WorkoutWriteService.instance.logExercise(
      date: DateTime(2026, 5, 2),
      exerciseName: 'Bench Press',
      sets: [
        ExerciseSet(weightKg: 60, reps: 10),
        ExerciseSet(weightKg: 62.5, reps: 8),
        ExerciseSet(weightKg: 65, reps: 6),
      ],
      source: WriteSource.activeWorkout,
    );

    final r = WorkoutReceiptData.fromExerciseLogs(DateTime(2026, 5, 2));
    expect(r, isNotNull);
    expect(r!.totalSets, 3);
    expect(r.exercises.length, 1);
    expect(r.exercises.first.sets, 3);
    expect(r.exercises.first.maxWeightKg, 65);
    expect(r.exercises.first.totalReps, 24);
    expect(r.exercises.first.perSetBreakdown.length, 3);
  });

  test('renders timed exercise correctly', () async { … });
});
```

This is the test that should have existed after Test #6.

---

## 4. Theme B — Rank pill in banner row

### Locked decisions

| Decision | Value |
|---|---|
| Banner row layout | avatar (L) · rank chip (CENTER) · GO PRO (R) |
| Chip label | compact short code only (e.g., `SD2`) |
| Chip composition | 22 dp `WardRankInsignia` + short code mono · 11 sp · letterspacing 1.4 + caret |
| Tap surface | bottom sheet (not inline accordion, not full-screen route) |
| Inline `WardRankPill` | **removed** from the scrollable column (line 533–547 of `profile_screen.dart`) |

### Bottom-sheet contents (expanded from current `_buildRankServiceRecord`)

```
┌─────────────────────────────────────┐
│ ──── (grab handle)                  │
│                                     │
│ SERVICE RECORD                      │  mono 10sp eyebrow
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ ✶✶  Seaman 2                    │ │  current rank big card
│ │     CURRENT                     │ │
│ └─────────────────────────────────┘ │
│                                     │
│ ┌──────────┐ ┌──────────┐           │
│ │ STREAK   │ │ FREEZES  │           │  NEW · status tiles
│ │ 7 days   │ │ 2 / 3    │           │
│ └──────────┘ └──────────┘           │
│ ─────                               │
│ UPCOMING                            │  mono 10sp eyebrow
│ ✶✶✶  Seaman 1                       │
│      14-day streak · 80% completion │
│ ⚓    Leading Seaman                 │
│      28-day streak · Phase 1 complete│
│ ─────                               │
│ PROMOTION HISTORY                   │  NEW · mono 10sp eyebrow
│ • Promoted to Seaman 2     01 MAY   │
│ • Promoted to Seaman Recruit 25 APR │
│                                     │
│ VIEW FULL ROADMAP →                 │  link to /train/roadmap
└─────────────────────────────────────┘
```

### Data sources

| Field | Source |
|---|---|
| Current rank | `RankService.instance.getCurrentRank()` (existing) |
| Upcoming 2 ranks | `RankService.instance.getLadder()` skipped past current (existing) |
| Streak count | `WorkoutRepository.calculateCurrentStreak()` (existing — used by home banner) |
| Freezes available | Hive `streak_freezes_available` from `userBox` (Hive-only per CLAUDE.md) |
| Freezes used | Hive `streak_freezes_used_dates` length |
| Promotion history | `SELECT rank_code, achieved_at FROM rank_promotions WHERE user_id = $uid ORDER BY achieved_at DESC LIMIT 5` (Test #6 schema, UNIQUE on `(user_id, rank_code)`) |

Promotion history fetch is a one-shot Supabase query when the bottom sheet opens, not pre-loaded — sheet shows a lightweight skeleton (3 dotted-line rows) until the query returns. Cache locally for the session in a Riverpod provider so re-opens are instant.

### Files touched

- `lib/features/profile/widgets/profile_identity.dart` — extend banner-overlap row to host the rank chip in the centered slot
- `lib/features/profile/screens/profile_screen.dart` — remove the inline `WardRankPill` block (lines 533–547), wire the chip's `onTap` to a new bottom-sheet builder
- `lib/features/profile/widgets/rank_service_record_sheet.dart` (NEW) — extracted bottom-sheet content; reuses existing `WardRankInsignia`, adds the two new sections
- `lib/features/profile/providers/promotion_history_provider.dart` (NEW) — Riverpod async provider, queries `rank_promotions`, caches per session

### What stays the same

- `WardRankInsignia` primitive (existing 11-rank CustomPaint)
- `RankService` math + ladder definition
- `current_rank_code` source of truth (`user_profile`)
- `/train/roadmap` destination link
- 8 proactive triggers + their cron infra (untouched here, see Theme E)

---

## 5. Theme C — Profile cards + edit defaults

### 5.1 — Sharp + flush stack

Cards in the Profile tab section visible in user image 3 (Daily Goals → Badges → Journey → Body Stats → My Targets) collapse into a single visual block:

| Decision | Value |
|---|---|
| Outer corner radius | `AppRadius.sharp` (6 dp) — applied only to top-left/right of Daily Goals and bottom-left/right of My Targets |
| Inner card boundaries | square (radius 0) |
| Inter-card gaps | removed (`SizedBox(height: 8)` deleted) |
| Card border treatment | shared 1 px `var(--border)` rail; top border dropped on every card except the first |
| Card padding | unchanged (14 dp) |

Vertical rhythm gain ≈ 32 dp (4 × 8 dp gaps eliminated).

**Out of scope for this batch:** REPORTS card, SHARE & GROW, SETTINGS — these keep their current 16 dp radius + 8 dp gaps. If the locked aesthetic looks right on-device, sweep the rest in Test #9.

### 5.2 — Edit Profile defaults

`lib/features/profile/screens/edit_profile_screen.dart`:

```dart
// line 145 (current)
_dietPreference = (profile['diet_preference'] as String?) ?? 'non_veg';

// becomes
_dietPreference = (profile['diet_preference'] as String?) ?? 'veg';
```

```dart
// line 147 (current)
_sessionDuration = profile['session_duration_minutes'] as int?;

// becomes
_sessionDuration = (profile['session_duration_minutes'] as int?) ?? 90;
```

User-visible effect: when an existing user opens Edit Profile and these fields are unset (legacy / pre-onboarding row / cloud-restored profile missing fields), the pickers come up pre-selected at sensible defaults instead of blank.

### 5.3 — NOT in scope

- ❌ ROUTINE strip displaying `wake_up_time` / `session_duration_minutes` / `diet_preference` in read-only profile (these are internal data feeding plan generator + Theme E push; no display value to the user).
- ❌ Wider sharp+flush sweep across the Profile tab.

### Files touched

- `lib/features/profile/screens/profile_screen.dart` — `_buildCard` callsites for the 5 cards in the stack switch to a new variant signature: `_buildCardSharp({required position})` where `position ∈ {first, middle, last}`
- `lib/features/profile/screens/edit_profile_screen.dart` — two-line default change

---

## 6. Theme D — Testing gap

### 6.1 — Round-trip contract tests

**`test/contracts/workout_write_to_read_contract_test.dart`** (NEW):

For each consumer of `WorkoutWriteService` Hive output:

| Consumer | Assertion |
|---|---|
| `WorkoutReceiptData.fromExerciseLogs` | sets/reps/weight/perSetBreakdown all non-default |
| `WorkoutRepository.getExerciseLogsForDate` | exact log map round-trips |
| `AiCoachRepository.buildAiContext` | today's exercise appears in `recent_logs` |
| PR detector / `_rescanAllPrsFor` | new max weight flagged is_pr=true |
| `SyncService.syncWorkoutData` projection | cloud row shape matches `workout_log_exercises` schema |

Each test: `WorkoutWriteService.logExercise(...)` → call consumer → assert non-zero / correct values.

**`test/contracts/nutrition_write_to_read_contract_test.dart`** (NEW):

Analogous coverage for `NutritionWriteService` consumers (TodaysMealsCard, nutrition snapshot, AI coach context, day rollover).

### 6.2 — CLAUDE.md additions

New sub-section under §15 "Source of Truth Rules":

```markdown
### Hive field-name contract

WriteService output keys are a contract with every consumer. Field renames must:

1. Update the writer.
2. Update every consumer in the same PR (grep for the old field name).
3. Update or add a round-trip test in `test/contracts/`.

Current contracts:
- `exlog_*` (WorkoutWriteService) — fields: exercise_name, date, sets[],
  set_number, reps_completed, weight_kg, volume_kg, logging_type, is_pr,
  source, updated_at_ms.
  Consumers: WorkoutReceiptData.fromExerciseLogs, WorkoutRepository
  .getExerciseLogsForDate, AiCoachRepository.buildAiContext, calendar week
  provider, PR detector / _rescanAllPrsFor, SyncService.syncWorkoutData.
- `nlog_*` (NutritionWriteService) — fields: <enumerate during D.1 test
  authoring>. Consumers: TodaysMealsCard, NutritionRepository.getMealsForDate,
  AiCoachRepository.buildAiContext nutrition section, day rollover, dietary
  fiber rollup.
```

### 6.3 — `/pre-commit-check` skill update

`.claude/commands/pre-commit-check.md` gains one bullet:

> ☐ If I changed a WriteService output field, did I grep for every consumer of that field name and update them in the same commit? Did I add or update a round-trip test in `test/contracts/`?

### What's NOT in Theme D

- Typed schema layer (`class ExerciseLogView`) — too much refactor for benefit. Revisit if drift recurs.
- Auditing every consumer for current correctness beyond what the new tests reveal.
- Fixing the 4 pre-existing test failures from Test #6 (`rank_service_test` LS/PO/SubLt static gate mirrors + `sync_gap_test` `DeleteNutritionLogNotifier`). Not field-rename drift; deferred to a separate cleanup PR.

---

## 7. Theme E — Personalize morning-alert to wake_up_time

### Existing infrastructure (verified against production)

The morning-alert function ALREADY runs as 2 stages in production. The existing 2-cron + `mode` branching is sound architecture; Theme E only changes the **delivery cadence** and adds a **wake-time filter**.

| Cron job (existing) | UTC | IST | Edge body | What it does |
|---|---|---|---|---|
| `morning_alert_generate` | 20:30 | 02:00 | `{"mode":"generate"}` | Builds Gemini message per active user, writes `user_daily_snapshots.snapshot_json.morning_alert` |
| `morning_alert_deliver` | 01:30 | 07:00 | `{"mode":"deliver"}` | Iterates today's snapshots with non-null `morning_alert`, sends OneSignal + Telegram, dedups via `shouldSendProactive(... 'morning_brief')` |

`wake_up_time` is collected during onboarding, stored as `time without time zone`, but **never read** by `morning-alert/index.ts` (verified via grep). Every user gets the push at fixed 07:00 IST regardless of when they actually wake up.

### Architecture for Theme E

```
GENERATE — UNCHANGED
  cron: morning_alert_generate at 20:30 UTC (02:00 IST)
  body: {"mode":"generate"}
  Existing logic continues to write snapshot_json.morning_alert per user.

DELIVER — RESCHEDULED + FILTER ADDED
  cron: replace single 07:00 IST run with two cron rows running every 15 min,
        spanning UTC midnight to cover IST 04:00–11:59.
  body: {"mode":"deliver"}
  deliverAlerts(supabase, todayIST):
    current_quarter = floor(IST_now.time_of_day, 15 min)   // e.g. '07:15:00'
    is_fallback_quarter = (current_quarter == '07:00:00')
    SELECT s.user_id, s.snapshot_json
    FROM   user_daily_snapshots s
    JOIN   user_profile p ON p.user_id = s.user_id
    WHERE  s.snapshot_date = todayIST
      AND  s.snapshot_json->'morning_alert' IS NOT NULL
      AND  (
             /* normal: wake matches this quarter */
             (p.wake_up_time IS NOT NULL
              AND floor_to_quarter(p.wake_up_time) = current_quarter)
             OR
             /* fallback: NULL wake gets the 07:00 IST quarter */
             (p.wake_up_time IS NULL AND is_fallback_quarter)
           )
    LIMIT page_size OFFSET …
    /* per-row inside the loop: shouldSendProactive(... 'morning_brief')
       for dedup, then push + telegram, then markProactiveSent. Existing
       dedup type 'morning_brief' is preserved unchanged. */
```

`floor_to_quarter` can be expressed in SQL with `date_trunc` after casting, or computed in TS by extracting hours+minutes from `wake_up_time` text and rounding minutes to the nearest 15. Either approach is fine; implementation chooses.

### Decisions

| Decision | Value | Why |
|---|---|---|
| Granularity | 15 min | matches typical cron cadence; tighter is overkill |
| Lead/lag | 0 — fire at exact wake_up_time | morning brief reads on phone pickup |
| Window | 04:00–11:59 IST | covers early risers + late wakers; outliers logged |
| Dedup | `shouldSendProactive(supabase, user_id, 'morning_brief')` (existing) | already used by all 8 proactive triggers; **type stays as `'morning_brief'`** to match existing behavior |
| Fallback if `wake_up_time IS NULL` | deliver at the 07:00 IST quarter | matches today's behavior for legacy / restored profiles |

### Edge cases

| Case | Behavior |
|---|---|
| Wake time outside 04:00–11:59 (e.g., 3 AM, 1 PM) | logged, no push fired in v1; widen window if real users complain |
| User opens app before push arrives | push still fires; no conflict, AI brief is identical to coach view |
| New user (no snapshot row yet) | Stage 2 join is silently empty; Stage 1 next morning catches them |
| User changes wake_up_time mid-day | takes effect tomorrow morning |
| DST | India doesn't observe DST; `wake_up_time` is `time without time zone` so no math |

### Migration `046_morning_alert_personalized_delivery_cron.sql`

```sql
-- Existing morning_alert_generate cron is UNCHANGED (02:00 IST).
-- Replace the single-shot 07:00 IST delivery cron with two rows running
-- every 15 min, spanning UTC midnight to cover IST 04:00–11:59.

SELECT cron.unschedule('morning_alert_deliver');

-- IST 04:00–11:59  ⇔  UTC 22:30 (prev day) → UTC 06:29 (same day).
-- pg_cron only supports integer hour ranges, so we approximate with two
-- cron rows that combined cover IST 04:00–11:59 with 15-min cadence.
-- Each fires the existing function with mode=deliver; deliverAlerts
-- self-filters to the current quarter.

SELECT cron.schedule(
  'morning_alert_deliver_late',
  '*/15 22-23 * * *',                     -- IST 03:30–05:59
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()),
      body := jsonb_build_object('mode','deliver')
    );
  $$
);

SELECT cron.schedule(
  'morning_alert_deliver_early',
  '*/15 0-6 * * *',                       -- IST 05:30–12:14
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/morning-alert',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()),
      body := jsonb_build_object('mode','deliver')
    );
  $$
);
```

### Edge Function changes — `supabase/functions/morning-alert/index.ts`

The `mode='generate'` path is untouched. The `mode='deliver'` path picks up two changes:

1. `deliverAlerts` computes `current_quarter` (IST hour:floor-15min) at the top of the function.
2. The paginated `SELECT` from `user_daily_snapshots` now JOINs `user_profile` and adds the wake-time filter shown above.

```ts
async function deliverAlerts(
  supabaseClient: SupabaseClient,
  todayIST: string,
): Promise<{ totalAlerts: number; pushSent: number; telegramSent: number }> {
  const currentQuarter = floorToQuarterIst(new Date());        // e.g. '07:15:00'
  const isFallbackQuarter = currentQuarter === '07:00:00';

  // ... pagination loop, but query is wake-time-filtered:
  const { data: snapshots, error } = await supabaseClient.rpc(
    'morning_alert_pick_quarter',
    { p_today: todayIST, p_quarter: currentQuarter, p_fallback: isFallbackQuarter, p_offset: offset, p_limit: PAGE_SIZE },
  );
  // OR equivalent inline query joining user_daily_snapshots + user_profile.
  // Implementation may choose RPC vs inline; behavior identical.

  // ... existing per-row delivery loop unchanged
  // (shouldSendProactive 'morning_brief' / sendPushToUser / markProactiveSent / Telegram).
}
```

A small RPC `morning_alert_pick_quarter` keeps the join + quarter-floor math out of the TS layer; alternatively, do it inline. Either is acceptable.

### Telemetry

Add `morning_alert_delivered_at` to `user_daily_snapshots.snapshot_json` so we can compare `wake_up_time` ↔ `delivered_at` over time and confirm the window-hit rate. Surface as a debug field in `coach_memory` if needed.

### Files touched

- `supabase/functions/morning-alert/index.ts` — `mode='generate'` unchanged; `mode='deliver'` (`deliverAlerts`) gets quarter-aware filter
- `supabase/migrations/046_morning_alert_personalized_delivery_cron.sql` (NEW) — drops `morning_alert_deliver` 07:00 IST cron; adds `morning_alert_deliver_late` + `morning_alert_deliver_early` running every 15 min
- `lib/features/profile/screens/edit_profile_screen.dart` — already has `wake_up_time` picker; verify it round-trips correctly through `_save` (no code change expected, just a contract test)

---

## 8. Out of scope for Test #8

- `terms_accepted_at` cloud-write gap on signup (separate sync issue)
- `scheduled_workouts` Hive→cloud sync gap (separate, low priority — schedule is local-first by design)
- Wider sharp+flush sweep across REPORTS / SHARE & GROW / SETTINGS sections
- Typed schema layer (`ExerciseLogView`-style accessors)
- 4 pre-existing test failures inherited from Test #6 (rank_service LS/PO/SubLt + sync_gap DeleteNutritionLogNotifier)
- Push delivery for users whose wake_up_time falls outside 04:00–11:59 IST (deferred to future widening if real users surface)

---

## 9. Risk register

| Risk | Mitigation |
|---|---|
| Theme A patch fixes receipt but breaks legacy logs from before Test #6 | Fall-back chain reads new key first then legacy key — both shapes render |
| Theme B promotion-history Supabase query is slow on cold cache, sheet hangs | Render skeleton placeholder rows; query in `Future` w/ 3s timeout, show empty state on timeout |
| Theme C sharp-flush stack regression on phones with very narrow widths (<340 dp) | Flush stack does not change widths; pure radius + spacing change. Existing card content already responsive. |
| Theme D contract tests reveal multiple drifts beyond receipt | Each becomes its own commit in this batch; do not let scope balloon — only fix what tests find |
| Theme E migration 046 leaves stale cron rows during rollout | `cron.unschedule` is idempotent; if names don't match, the migration succeeds and we manually clean up |
| Theme E push fires twice (legacy + new) during rollout | Stage 2 delivery checks `shouldSendProactive` which uses `coach_memory.last_proactive_type`; legacy 7 AM run will be deactivated by the same migration |
| Theme E user with `wake_up_time = NULL` and no snapshot misses morning push | Stage 2 fallback path for `wake_up_time IS NULL` delivers at 7 AM IST quarter |

---

## 10. Approval & next step

User approved the bundle (Themes A–E, ~750 LOC, 6–9 hours) on 2026-05-02.

**Next:** invoke the `superpowers:writing-plans` skill to convert this spec into a step-by-step implementation plan with explicit task ordering, test-driven development sub-tasks, and dispatch points for parallel agents.
