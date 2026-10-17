# Day Swapper + Sync Load: One Swap Engine for Train, Home and Coach; Sync Sends Only What Changed

> **For agentic workers:** this spec is the input to `superpowers:writing-plans`. Read it in full
> before drafting the plan. Every `file:line` below was read directly on 2026-09-26 against `main`
> at `fafec56a` (origin/main was 5 commits ahead; none of those commits touch the files cited
> here). Line numbers drift, so re-grep before relying on one. Anything marked
> **(verify at plan time)** was NOT verified and must be checked, not assumed.

**Status:** design approved section by section by the founder, 2026-09-25/26 (7 sections). Spec
written 2026-09-26, awaiting founder review. Not committed (founder rule: commit only when asked).

**Batch shape:** ONE combined batch: the day swapper plus the full sync-load fix, with OI-237
folded in (founder decisions 9 and 11, §3).

**Tier:** L (CLAUDE.md §4.12.6: sync, schema, Edge Functions, AI prompt). Full ×2 context-blind
plan review, a B-pass before the `--no-ff` merge, and a Hermes pass if any written file classifies
catastrophic. Classify the REAL files once written: a not-yet-written path returns its path-glob
tier (CLAUDE.md §4.9 pitfall row).

**Trigger:** APK observation 3, 2026-09-25 (§1.1).

**Mockup:** `docs/mockups/2026-09-26-day-swapper-v1.html`. It is worktree-local and gitignored,
so every approved string is reproduced in §6.4 and this spec stands alone.

---

## 1. Problem

### 1.1 The observation

The founder asked the coach to "shift today's workout to tomorrow and tomorrow's workout to today"
(Fri 25 Pull + Core ↔ Sat 26 Legs + Core). The coach emitted `reschedule_week` with
`daysAvailable=[Fri, Sat]`, and APPLY showed "6 keep · 0 move · 0 drop": a no-op. There is no
day-swap coach tool, and two sites actively route swaps to the wrong one:

- `supabase/functions/_shared/captain_manual.ts:386`: the manual's own multi-intent example sends
  "move Friday's pull workout to today and today's pull to Friday" to rescheduleWeek.
- `supabase/functions/_shared/tools/workout/rescheduleWeek.ts:25-26`: the tool's own
  `selectionHints` claim "move Friday's pull to today".

### 1.2 The existing swap is unsafe

A day swap already exists: `SwapService.swapDays` (`lib/core/services/swap_service.dart:113-169`).
It is reached only by a long-press on the Home calendar strip (`weekly_calendar.dart:129`,
ungated → `home_screen.dart:483` → `SwapSheet`, `lib/features/home/widgets/swap_sheet.dart:13`).
Defects, each read in code:

1. **No eligibility guards.** SwapSheet lists every day of the week, including past and completed
   days. Swapping a completed day moves its completion to another date.
2. **Not atomic, and it counts failures.** It makes two separate `upsertScheduled` calls
   (`:155-164`), ignores both `WriteResult`s, and increments the counter regardless (`:166`). A
   failed or half-applied swap still costs a swap.
3. **Copies the whole row.** The other day's map is copied wholesale, keeping only
   `date`/`day_of_week` (`:143-153`). Identity fields (`week`, `phase`, `week_character`,
   `is_hold`, `hold_ordinal`) travel with the content. That is harmless today only because both
   days are always in the same week.
4. **Swap markers never clear.** `is_swapped`/`original_date` are stamped on both rows
   (`:146-147`, `:152-153`) and never cleared. Swap Fri↔Sat twice and both days still say "swapped", and
   `original_date` is overwritten with the latest origin instead of the first.
5. **The counter** is one local slot (`swap_week_start` + `swaps_this_week`, `:105-106`,
   `:479-498`). It uses the device-local week (`_normalizeToMonday`, `:567`) instead of IST,
   resets on sign-out/reinstall, and counts failures.
6. **The 3-rest-day rule over-reaches.** `_hasThreeConsecutiveRest` (`:519-530`) checks the whole
   post-swap week, so a week that already contains a 3-rest run blocks every swap. It refuses
   instead of warning.
7. **A template day leaves a stale cloud link.** The scheduled-workouts push omits a null
   `template_id` (`lib/core/services/sync/sync_workout.dart:1714`), so the cloud row keeps pointing
   at a template that moved away. On reinstall, `_restoreScheduledWorkouts` then force-hydrates
   that template onto the day (`:2095-2100`), duplicating it.
8. **Swapped days miss the deload lift.** `_liftWeekFour` skips `is_swapped` rows
   (`lib/core/services/deload_evaluator.dart:210`, added in `a99099d5` with no recorded reason).
   The `:209` skip of shortened rows is separate and stays.
9. **Dead sibling.** `WorkoutWriteService.rescheduleDay` (`workout_write_service.dart:648-721`)
   is an atomic two-date swap with no production caller. Its only caller is
   `test/workout_write_service/reschedule_day_test.dart`.

Bug history (§4.1.5): grepping `docs/diagnoses/INDEX.md` for swap terms finds only `e8f4a3` (the
rescheduleWeek move path). There is no prior day-swap diagnose, so this is **not a recurrence**.

### 1.3 A swap can undo itself after a restart

Verified chain:

1. `swapDays` never pushes the plan backup (`user_progress.plan_json`). The plan is pushed by the
   daily `weeklyFullSync` (`sync_service.dart:1369`; `_fullSyncInterval` = 1 day at `:703`) and by
   the specific writers listed under OI-189. A swap is not one of them.
2. On every launch, `restoreLightweightAlways` (`sync_service.dart:1535-1559`) runs
   `_restoreWorkoutPlan` (`sync_workout.dart:1177-1246`) BEFORE the daily sync
   (`sync_service.dart:1093-1096`). It raw-puts `PlanIntegrityReconciler.mergeScheduleEntry(...)`
   for every snapshot row (`sync_workout.dart:1238`).
3. `mergeScheduleEntry` (`plan_integrity_reconciler.dart:69-90`) keeps a completed local row and
   keeps a local row that has exercises. Otherwise it takes the snapshot's content and keeps the
   local `status`.
4. A rest row has no exercises. After a workout↔rest swap, the next launch refills the new rest
   row with the stale snapshot's workout while keeping `status: rest`. The result is a
   `type: workout` + `status: rest` hybrid. `isRestDayConsideringLogged(type)`
   (`plan_engine_flags.dart:499-504`) decides by type, so the workout renders on both dates. If the
   daily sync runs on that launch, the hybrid is persisted to the cloud.

Workout↔workout swaps survive, because both rows have exercises. For the same reason they never
reach a second device such as the web app: that device's non-empty local rows always win.

### 1.4 A second writer produces the same hybrid (found while writing this spec)

`_restoreScheduledWorkouts` (the reinstall path, `sync_workout.dart:1904-2135`) derives `type` as
"template resolved → `custom_template`, else the existing local type, else `template_id` present ?
`custom_template` : `workout`" (`:2097-2100`). It **ignores the cloud `status`**, so a cloud rest
day restored onto a fresh install becomes `type: workout` + `status: rest` with no exercises. It
stamps `source: 'cloud_restore'` (`:2132`).

Live check (read-only, 2026-09-26): **28 such rows across 3 users' `plan_json` backups**, dated
2026-05-31 → 2026-08-16. All 28 have `source = cloud_restore`, 27 have no exercises, and the
matching `scheduled_workouts` row says `rest` in every case. The daily plan push copied them into
the backup. `needsHeal` (`plan_integrity_reconciler.dart:96-107`) treats such a row as a planned
workout that lost its exercises, so the plan heal (called from `restoring_screen.dart:492` and
`heal_after_restore.dart:44`) fires on them and can never fix them.

### 1.5 Sync load (OI-237), measured live 2026-09-26 with read-only SQL

- `syncWorkoutDataNow` (`sync_workout.dart:44-84`) runs after every workout write:
  `logExercise` (`workout_write_service.dart:210`), `markCompleted` (`:547`) and
  `upsertScheduled` (`:622`). The `SyncCoalescer` (`lib/core/services/sync_coalescer.dart`) only
  merges calls that arrive while a pass is already running; there is no time debounce.
- 21 push steps exist in `lib/core/services/sync/`. 3 skip unchanged rows today. Of the other 18,
  3 push a single row (profile, progress, preferences) and **14 re-send the user's whole history on
  every pass** (§5.9 table), plus the plan backup.
- The heaviest account costs about 143 requests per workout pass. That breaks down as 5 template
  headers, 5 id SELECTs, 21 template exercises and 5 DELETEs, plus 44 workout logs,
  28 completions, 28 completed days and 7 streak weeks. Each nutrition pass re-sends 32 water days.
- Rewrites per live row (`pg_stat_user_tables`):

  | Table | Rewrites per row |
  |---|---|
  | workout_schedule_completions | about 29 |
  | workout_templates | about 30 |
  | template_exercises | about 33 (764 updates, 23 live rows) |
  | streaks | about 23 |
  | workout_logs | about 21 |
  | water_logs | about 41 |
  | scheduled_workouts | 1,377 updates vs 84 inserts |

  OI-237 (`docs/audit/open_issues.md:5595`) names the last one and template_exercises.
- Completed scheduled rows are deliberately never skipped: A-fix-1 in `_syncScheduledWorkouts`,
  diagnose `d9b2c5`'s cross-device-completion contract. They are re-sent on every pass.
- The plan backup is rewritten unconditionally once a day (`sync_service.dart:1369`). It averages
  79 KB stored, up to 184 KB (up to 656 KB of text), and holds up to 112 rows.
- Every launch downloads `plan_json` **twice**. `_restoreUserProgress` selects `*`
  (`sync_profile.dart:931-938`), and `_restoreWorkoutPlan` selects `plan_json`
  (`sync_workout.dart:1183`).
  - `UserRepository.mergeCloudProgress` copies the whole blob into Hive `userBox['progress']`,
    where nothing reads it. The progress push uses an explicit field list
    (`sync_profile.dart:99-120`), so the copy is never pushed back.
  - The plan merge then re-writes up to 112 schedule rows to Hive on every launch.
- Postgres writes a new row version on every UPDATE, even when nothing changed. Live check: none of
  the heavy tables has a user trigger (the only ones are INSERT-only rate-limit triggers on
  `ai_coach_interactions`), so the built-in `suppress_redundant_updates_trigger()` applies cleanly.

### 1.6 Workout completion times are wrong in the cloud (recurrence of `5a36ad`)

- **Writer:** `markCompleted` stamps the schedule row with `completed_at_ms` only
  (`workout_write_service.dart:502`, `:511`). The ISO `completed_at` goes on the `wlog_<date>` row
  (`:540`).
- **Readers:**
  - `_syncScheduleCompletions` sends `entry['completed_at'] ?? DateTime.now()`
    (`sync_workout.dart:628-629`), which is "now" on every pass.
  - `_syncScheduledWorkouts` sends `entry['completed_at']`, which is null (`:1707-1710`).
- **Live evidence:**
  - 17 of 37 completion records are stamped more than a day after the workout.
  - 4 records for days older than 3 days were re-stamped within the last 3 days.
  - 9 of 37 completed scheduled days have a null time.
- **Recurrence:** `5a36ad` (2026-05-08, `docs/diagnoses/2026-05-08-sync-stack-templates-streak-pill-5a36ad.md`)
  fixed "completed_at overwritten to NOW on every sync" for workout and exercise logs, using
  `_resolveCompletedAt` (`sync_workout.dart:532`) and `test/sync/completed_at_preservation_test.dart`.
  The two completion paths were never moved onto it.
- ⚠ **The resolver cannot be reused as-is.** Its order is `created_at`, `completed_at`,
  `logged_at`, **`updated_at_ms`**, `completed_at_ms` (`:518-528`). Every schedule row carries
  `updated_at_ms` from its last `upsertScheduled`, often plan generation, so the resolver would
  return the plan-generation time.
- The same class, a "now" fallback for a past timestamp, has **11 instances** in sync code (§5.12).

---

## 2. Goals and non-goals

**Goals**

- One swap engine for every entry point (Train drag, Train ⇅, Home long-press, coach), with the
  same rules and one shared weekly allowance.
- A swap is atomic, never reverts, reaches the cloud promptly, and propagates to other devices.
- The coach handles "swap these two days" correctly for PRO users, and is honest with free users
  and with old app versions.
- Sync traffic and database writes scale with what the user changes, not with account age.
- Completion times in the cloud are the real ones, and restored rest days are rest days.

**Deliberately left out** (approved, Section 1)

- moving a workout into another week
- catching up a missed day
- reshuffling more than two days in one gesture
- an undo button: swapping back is the undo, and it costs a swap

Also out of scope: the single-row sync steps (profile, progress, preferences), a remote-config
service, and the cost of the very first sync on a fresh install.

---

## 3. Locked decisions

| # | Date | Decision |
|---|---|---|
| 1 | 09-25 | Train gets a drag interaction. It is delivered as pairwise drag-to-swap (see 7). |
| 2 | 09-25 | ONE shared swap operation for Home, Train and the coach. |
| 3 | 09-26 | Allowance: free 1 per week, PRO 3 per week, one counter shared by all entry points. |
| 4 | 09-26 | Swappable days: today or later, same Mon–Sun IST week, planned workout / rest / custom-template days. Locked: completed, any logged sets, today while a workout is in progress, paused, past. The template's `displaced_<date>` backup travels with the template; the cloud `template_id` is cleared on the day the template left. |
| 5 | 09-26 | The coach tool is PRO-only. Free users get a fallback line in the Captain Manual. |
| 6 | 09-26 | Allowance = server ledger (`usage_counters` via `consume_quota`, quota key `day_swap`, IST-Monday window, no migration) plus a phone copy. The phone enforces offline; the server count wins when online; fail open; offline overage is tolerated and never undone. |
| 7 | 09-26 | Train UI = approach A: drag onto another day = one pairwise swap, plus a visible ⇅ on every movable row. A drop opens a confirm sheet first (no instant swap with undo). The "⇄ MOVED" tag stays until the day is completed. The allowance line sits under the week list. A shared "Swap <day> with…" picker replaces the Home SwapSheet. Rearrange mode (B) is rejected. Copy as mocked. |
| 8 | 09-26 | Plan backup: skip the push if unchanged (fingerprint of the last CONFIRMED push, excluding `synced_at`). Keep the immediate plan push after every swap. |
| 9 | 09-26 | OI-237 is folded into this batch. |
| 10 | 09-26 | The 3-rest-days rule warns (confirm sheet and coach card) and never blocks. It counts only runs the swap creates. |
| 11 | 09-26 | One combined batch: day swapper + full sync-load fix. |
| 12 | 09-26 | Section 6 as approved: a phone skip helper for all 14 history steps plus the plan; one server migration (ignore no-op updates, completed days can't be demoted, `sync_epoch` resync number); a single launch fetch; completion times via a correct resolver, with "now" banned as a fallback. The daily 7-day re-send safety net was dropped (§14). |
| 13 | 09-26 | Section 7 as approved: build order, testing, rollout order, reviews, rollback (§7–§12). |

---

## 4. Architecture

```
Workout tab (drag or ⇅) ─┐
Home (long-press)        ├──►  Day swap engine (one, on the phone)
Coach card (APPLY)       ┘        │
                                  ├─ checks the rules against LIVE rows, at confirm time
                                  ├─ writes both days in one locked step (both or neither)
                                  ├─ pushes the plan backup right away
                                  └─ records the swap on the server ledger in the background

Sync (every domain) ──► SyncSkipIndex: push a row only if its content changed since the
                        last CONFIRMED push; record "sent" only after the write succeeded

Server (one migration) ──► ignore no-op updates · completed days can't be demoted · sync_epoch
```

| Unit | Purpose | Depends on |
|---|---|---|
| `DaySwapRules` (new, pure) | Decides eligibility, allowance, and the 3-rest warning from plain row maps. No I/O. | nothing |
| Swap engine (`SwapService.swapDays`, rebuilt in place) | The one entry point: reads live rows, applies the rules, builds both rows, writes, fans out. | rules, `WorkoutWriteService`, allowance |
| `WorkoutWriteService.swapScheduledDays` (replaces the unused `rescheduleDay`) | Writes both rows under the existing sorted two-date lock, stamps them, fans out once, and returns one `WriteResult`. | Hive |
| `DaySwapAllowance` (new) | Phone copy per IST week, plus a background consume call to the server. | `consume-day-swap` EF |
| `consume-day-swap` EF (new) | Resolves the tier and calls `consume_quota(user, 'day_swap', IST Monday, 1|3)`. | `_shared/subscription.ts`, `_shared/ist_date.ts` |
| `SwapPickerSheet` + `SwapConfirmSheet` (new, shared) | UI for the tap path and the drag path. Replaces `SwapSheet`. | engine |
| Train week list (`week_rows.dart`) | Drag, ⇅, MOVED tag, allowance line. | picker, confirm sheet |
| Coach tool `swapWorkoutDays` | PRO tool shown only to capable clients. The client executes it through the same engine. | capability handshake |
| `SyncSkipIndex` (new) | One skip mechanism for every history push. | Hive |
| Migration `144_*` (number verified at plan time) *(corrected 2026-09-28 at implementation: `147_sync_noop_suppress_completed_guard_sync_epoch.sql`, then re-corrected the same day to `148_sync_noop_suppress_completed_guard_sync_epoch.sql` once 147 was also taken on `main` — see §5.10's own correction.)* | The three server rules. | none |

---

## 5. Detailed design

### 5.1 Engine contract

```dart
Future<DaySwapResult> swapDays({
  required String dateA,          // IST 'YYYY-MM-DD'
  required String dateB,
  required DaySwapOrigin origin,  // trainDrag | trainPicker | homePicker | coach
});

sealed class DaySwapResult
  DaySwapDone    { DayAllowance allowanceAfter; RestRunWarning? warning; }
  DaySwapRefused { DaySwapRefusal reason; String dayLabel; }   // nothing written, nothing counted
  DaySwapFailed  { }                                           // write failed, nothing counted
```

- All checks run **at confirm time** (confirm sheet, picker button, or coach APPLY), against rows
  re-read inside the write lock. They never run when a screen or card first appears. A 40-minute-old
  coach card therefore cannot swap a day that has since been completed.
- A swap is counted only after the write succeeds.
- The engine gets in-progress state from an injected probe backed by
  `ActiveWorkoutData.hasInProgressSession` (`train_provider.dart:1242`) and the session's date.

### 5.2 Rules (`DaySwapRules`, pure)

Both days must:

1. be different dates in the same Mon–Sun IST week (`mondayOfIst`, `lib/core/utils/ist_date.dart:113`);
2. be today or later (IST, `istTodayStr`);
3. have a schedule row whose `status` is `planned` or `rest`. Every other status is locked:
   `completed`, `skipped`, `paused`, `travel`, `moved`, `dropped`, `none`. So is a missing row.
   Types `workout`, `rest` and `custom_template` are all movable;
4. have no logged sets, meaning `WorkoutReadService.exerciseLogsForIstDate(date)` is empty and
   there is no `wlog_<date>`;
5. not be the date of an in-progress workout.

**Which weeks.** Swaps are allowed in any week of the current plan window, as long as both days
pass the rules above. The allowance belongs to the week the two days are in. The coach lookahead
spans two weeks, so this has to be decided; it is the literal reading of decision 4 ("today or
later, same week"), and the founder can narrow it to the current week only.

**Refusal reasons and picker labels:**

| Reason | Label |
|---|---|
| completed | DONE |
| logged sets or in progress | STARTED |
| paused | PAUSED |
| past | PAST |
| travel | TRAVEL (beyond the mockup) |
| moved/dropped by the coach | RESCHEDULED (beyond the mockup) |
| skipped | SKIPPED (beyond the mockup) |
| no row | not listed |

### 5.3 Allowance

- **Limits:** free 1, PRO 3, per IST Mon–Sun week of the swapped days.
- **Phone copy:** a new user-scoped Hive key `day_swap_allowance` holding
  `{ '<IST Monday>': {used, limit, server_seen_at_ms} }`, pruned to the current and future weeks.
  It replaces `swaps_this_week`/`swap_week_start`, which become dead keys and are deleted in the
  same batch.
- **Pre-check:** the swap is refused if `used >= limit` for that week. `limit` is the last value
  the server returned, or the built-in 1/3 if the server has never answered.
- **After a successful write:**
  1. Increment `used` locally.
  2. Fire-and-forget `SupabaseService.callFunction('consume-day-swap', {week_start})`, going
     through `ensureFreshToken` (rule 9).
  3. The reply `{allowed, used, limit}` overwrites the phone copy for that week: the server count
     wins.
  4. If the call fails, keep the phone copy (fail open). There is no retry: a retry after an
     ambiguous failure could double-count, and one uncounted swap is the accepted cost.
- **`allowed:false`** (swaps made on another device used up the week) sets the phone copy to
  `used = limit`. **The swap that already happened is never undone.**
- **Server EF `consume-day-swap`** (new):
  - Auth: service-role client plus `.auth.getUser(token)` (rule 9; gate
    `check_edge_function_auth_pattern.dart`), with `verify_jwt=true`.
  - Validates that `week_start` is an IST Monday, not before the current IST Monday, and at most
    8 weeks ahead.
  - Tier comes from `isProUser` (`supabase/functions/_shared/subscription.ts:123`), so limit =
    3 or 1.
  - Calls `consume_quota(user, 'day_swap', <IST Monday 00:00 +05:30>, limit)` (migration
    `128_usage_counters.sql:69-118`; EXECUTE is granted to service_role only, migration 130).
    `-1` → `allowed:false`.
  - This EF is the **one call site** for quota key `day_swap` (the `usage_quota_ledger` rule:
    one key, one call site, one limit).
  - Needs a new helper `istWeekStartIso()` in `_shared/ist_date.ts`, which has no Monday helper
    today.
- **Retention:** `cleanup_usage_counters()` (run by `db_maintenance_nightly`, migration 141:76)
  deletes windowed rows older than now() − 7 days. A Monday window therefore survives its whole
  week. A test pins this.
- **No read endpoint.** The "swaps left" number comes from the phone copy. Each consume reply
  corrects it. A fresh device assumes 0 used until its first reply.

### 5.4 The write: what moves and what stays

Approved Section 2. The engine builds each new row as the other day's **content** placed on this
day's **identity**:

| Moves with the workout (content) | Stays with the date (identity) |
|---|---|
| `type`, `workout_name`, `workout_focus`, `exercises` (including this week's edits: swapped exercise, injury tweak, shortened version), `warmup`/`cooldown`/`finisher`, `workout_day_index`, `template_id` (+ its `displaced_<date>` backup), `generated_*`/`shortened_*`/`rescheduled_*` markers, `status` (always planned or rest on both sides) | `date`, `day_of_week`, `week`, `phase`, `week_character`, `is_hold`, `hold_ordinal`, `reason` |

Swap markers on the two new rows:

- `is_swapped: true` and `original_date` = **the first origin** of this content. If the content
  already carries an `original_date`, it is kept.
- When content lands back on its `original_date`, both fields are removed. This is what makes the
  MOVED tag disappear after a swap-back.
- `arranged_at_ms` = the swap time, the same value on both rows, and **never removed by a
  swap-back** (§5.7).

**Template bookkeeping.** `TemplateService.assignTemplateToDate` backs up the displaced row into
`displaced_<date>` (`template_service.dart:82`, `:93`, `:121-123`), and
`unscheduleTemplateFromDate` restores it (`:235`, `:251-258`). When a template day swaps, its
`displaced_` backup moves with it: the backup is re-keyed to the new date, and the old key is
deleted. If both days carry templates, the two backups are exchanged. Removing the template later
therefore brings back the workout it originally displaced.

**Cloud template link.** The scheduled-workouts push sends an explicit `template_id: null` when the
local row has no `template_id`. It omits the field only when a local id exists but
`resolveCloudTemplateId` cannot resolve it (fix at `sync_workout.dart:1714`).

**Deload.** Remove the `is_swapped` skip at `deload_evaluator.dart:210`. The `:209`
shortened-row skip stays.

**Atomic write.** `WorkoutWriteService.swapScheduledDays(dateA, rowA, dateB, rowB)` does the
following:

- takes the two-date lock in sorted order (the pattern from `rescheduleDay`, WWS:648-721);
- re-reads both rows;
- writes both rows with `source: WriteSource.daySwap` (a new enum value in
  `write_result.dart:44`) and `updated_at_ms`;
- moves any `displaced_` backups;
- if the second write throws, restores the first row's previous value, so it is both or neither;
- fans out `syncWorkoutData()` + `pushSnapshot()` **once**;
- returns one `WriteResult`.

`rescheduleDay` is deleted, and its test is rewritten against `swapScheduledDays`.

### 5.5 After the write (the swap bundle)

1. The coalesced `syncWorkoutData()` pass sends the two changed scheduled rows. Everything else is
   skipped as unchanged (§5.9).
2. Immediate unawaited plan push: `pushWorkoutPlanForSyncDomain` (`sync_workout.dart:2201`).
3. The allowance consume call (§5.3).
4. Provider invalidation for the Train list, the Home strip and today card, and the calendar
   **(verify the exact set at plan time)**.
5. Telemetry: `day_swap_done` / `day_swap_refused` (with reason) / `day_swap_failed`, emitted
   **only at confirm time**, never while dragging.

Nothing is sent while dragging, opening the picker, or opening the Train tab.

### 5.6 Three rest days in a row: warn, never block

- Rest = a row of type `rest`. Runs are evaluated inside the Mon–Sun week.
- Let `R_before` and `R_after` be the dates that sit in runs of 3 or more rest days, before and
  after the swap. **Warn only if `R_after` contains a date that `R_before` does not**, i.e. only
  when the swap creates or extends a run.
- The warning appears as one line in the confirm sheet and on the coach card (copy in §6.4).
- The swap is always allowed. The old `_hasThreeConsecutiveRest` block is removed.

### 5.7 The restore merge: why the fix holds

Approved Section 3 ("back up right after every swap" + "the more recent arrangement wins"). While
reading the merge code, three edge cases needed a precise rule, so the approved design is made
exact in three layers:

**L1: never refill a rest row with workout content.** Every hybrid in §1.3 and §1.4 comes from
refilling. The refill in `mergeScheduleEntry` now applies only when the local row is a workout
type (the same predicate as `needsHeal`), its status is not `rest`, and it has no exercises. That
is the original `a7d3f1` symptom, and that repair is kept. A local row of type `rest`, or with
status `rest`, is kept as-is.

**L2: merge only what is new.** One stored value, `plan_bundle_cloud_fingerprint`, is the
fingerprint (excluding `synced_at`) of the plan bundle this device knows the cloud holds.

- It is set after a confirmed plan push (this is decision 8's skip index) and after a successful
  merge of a downloaded bundle.
- On launch, if the downloaded bundle's fingerprint equals it, the merge is skipped entirely.
- This alone keeps a device's own changes (swaps, regenerations, anything) from being overwritten
  by re-merging a stale backup, whether or not the latest push landed.
- It also removes up to 112 Hive writes per launch.
- When the merge does run, it writes a row only if the merged result differs from the local row.

**L3: the newer arrangement wins, per week.** This applies only when a genuinely new bundle
arrives, from another device or after a reinstall.

- For each Mon–Sun week, compare the newest `arranged_at_ms` among the snapshot's rows with the
  newest among the local rows (a missing stamp counts as 0).
- If the snapshot's is newer, take the snapshot's rows (content, status and markers) for every
  date in that week that carries a stamp on either side.
- Otherwise keep the local rows for those dates.
- Completed local rows are always kept.
- Unstamped dates follow L1 and the existing rules.
- The comparison is per week because a swap never crosses a week, and two devices swapping
  overlapping days would otherwise leave one workout on two days.

**Carry-forward.** `WorkoutWriteService.upsertScheduled` (`workout_write_service.dart:574-646`,
which stamps `source` and `updated_at_ms` at `:617-620`) gets one central rule. When it rewrites a
date whose existing row has `arranged_at_ms`, and the new entry has none, it stamps
`arranged_at_ms = now`. Sources `daySwap` (which sets it itself) and `restore` (which copies the
source's) are excluded. A later regeneration, template change or reschedule of a swapped date
therefore counts as a newer arrangement, and an older swap can never overwrite it.

**Invariants (each gets a behavioural test, §9):**

| # | Invariant |
|---|---|
| I1 | Workout↔rest swap, cold restart with a stale backup → the swap survives, and no workout appears on two days. |
| I2 | Reinstall after a pushed swap → the swap appears. |
| I3 | Swap on device A (pushed) → device B's next launch shows it, for workout↔workout too. |
| I4 | Swap, then swap back → both days back as they were, MOVED cleared, and a stale backup does not re-apply the first swap. |
| I5 | Swap (pushed), then a regeneration of those dates whose push failed, then restart → the regeneration survives. |
| I6 | Completed local rows are never changed by the merge. |
| I7 | The `a7d3f1` repair still refills a planned workout row that lost its exercises. |
| I8 | No merge path produces a `type: workout` + `status: rest` row. |

**Accepted residuals** (documented, tested as known behaviour, logged as `swap_merge_conflict`):

- If two devices swap in the same week while offline, the later swap wins that whole week. The
  earlier one is discarded, and its allowance unit stays spent.
- A completed day is always kept, so a newer arrangement from another device can leave that day's
  workout also scheduled elsewhere in the week.

**Repair of existing hybrids.** A one-time Hive migrator, with the same shape as the other
`*_migrator.dart` files, turns rows with `status: rest`, a workout type and **no** exercises into
`type: rest` rows. This covers the §1.4 rows. The next plan push carries the fix to the backup.
The single live hybrid that has exercises is left alone, with telemetry: it is ambiguous and in
the past, and choosing a winner would be a guess. The writer fix: `_restoreScheduledWorkouts`
derives `type: rest` when the cloud status is `rest` and no template resolves (`:2097-2100`).

### 5.8 Coach

**Tool.** `supabase/functions/_shared/tools/workout/swapWorkoutDays.ts`:

- name `swapWorkoutDays`, intent type `swap_workout_days`
- tier `pro`, `confirmationClass: reviewable`
- params `{dateA: string, dateB: string}` as plain Zod strings, because `zodToGemini` throws on
  unsupported Zod types (`zodToGemini.ts:95`) and the client validates the dates anyway
- `requiresCapability: 'swap_workout_days'`
- `selectionHints` covers swapping, exchanging or trading two days, and "do Friday's workout on
  Saturday instead" (a single move within the week is a swap)

It is registered in `ALL_TOOLS` (`registry.ts:31`).

**The client executes it.** A new `swap_workout_days` case in `tool_dispatcher.dart` (whose default
branch is at `:160`) calls the engine with `origin: coach`. The inline card follows the mockup
(§6.4) and carries the 3-rest warning line when it applies. Its checks run at APPLY. The intent TTL
stays 1 hour.

**Stop the misrouting.**

- Rewrite `rescheduleWeek.ts:25-26` hints as "I'm only free on these days / reshape my week
  around availability", and drop the "move Friday's pull" phrasing.
- Fix `captain_manual.ts:386`'s example and add the routing rule:
  - swap or move-within-week → `swapWorkoutDays` (PRO, capable client);
  - free user → the fallback line;
  - PRO user whose client did not declare the capability → "update the app" line.
- `captain_manual.ts:5` requires a dated amendment to
  `docs/superpowers/specs/2026-04-27-ai-coach-brilliance-design.md` §5, in the same batch.

**Capability handshake.** Today no app-version or capability field exists in the chat request.

- The client sends `client_capabilities: [...]` with every ai-proxy chat request (`ai_service.dart`
  call sites `:335`, `:388`; verify all at plan time). The list is a const in the client, bounded
  to at most 32 entries of at most 48 chars each (`[a-z_]`).
- Server side, `tool-loop.ts:265` filters `allTools(isPro)` (`registry.ts:71`) down to tools whose
  `requiresCapability` is absent or declared.
- **An absent field gets exactly today's 20-tool set.**
- The manual's per-request fallback block is chosen the same way.
- `check_ai_tool_dispatcher_coverage.dart` is extended: every tool with `requiresCapability` must
  have a dispatcher case, and its capability must be in the client const.

**Week lookahead.** `_getWeekLookahead` (`ai_snapshot_builder.dart:1241-1266`) is a rolling 7 days
and sends only `type` and `status`. It gains, per day, `name`, `can_swap` (plus a `swap_block`
reason code) and `week_start`, and at the top level `swaps_left` per week start. That is about
0.5 KB. A test pins a worst-case fixture under the 10K-char snapshot limit (rule 18).

**Tool count** goes from 20 to 21 (FREE 9 / PRO 12). Update the pin in
`test/contracts/derive_only_tool_surface_test.dart`.

### 5.9 Sync: one skip helper, every history loop

**Helper** (`lib/core/services/sync/sync_skip_index.dart`, new). One instance per domain, built
with `{box, indexKey, killSwitchKey, opType}`.

```dart
Future<bool> pushIfChanged(String rowKey, Object fingerprintInput,
                           Future<void> Function() push);
Future<void> commit(String userId);   // one Hive write per pass; skipped if ownerChangedSince(userId)
void prune(Set<String> liveKeys);
Future<void> clearAll();              // sync_epoch change
```

- **Fingerprint:** UUID v5 over canonical JSON, reusing `_deterministicId` (the existing primitive).
- **"Sent" is recorded only if `push()` returns normally.** The helper owns the try/catch: it
  reports with the domain's `opType` and returns false. Domain code has **no try/catch around a
  push**, so the known gap (`docs/architecture/sync.md:159`) cannot exist by construction. That gap
  is a swallowing catch that forgets to flip a success flag, which the count-based gate cannot see
  and which OI-204's B-pass mutation proved reachable.
- A fingerprint exception means push and don't store (fail open).
- Kill switch set means push, never store: the verbatim pre-pattern sweep.
- The `ownerChangedSince` guard applies to every domain uniformly, which closes the nutrition-only
  asymmetry that `sync.md:192-194` notes.

**Fingerprint input** = the exact payload, minus "sent-at" stamps (`updated_at` on water and urine,
`synced_at` on steps and the plan). A change to a sent-at stamp alone never triggers a push.

| Step | Where | Table(s) | Keyed by | Notes |
|---|---|---|---|---|
| `_syncWorkoutLogs` | `sync_workout.dart:87` | workout_logs | wlog key | |
| `_syncScheduleCompletions` | `:594` | workout_schedule_completions | date | completion-time fix §5.12 |
| `_syncStreaks` | `:646` | streaks | week_start | |
| `_syncWorkoutTemplates` | `:1255` | workout_templates + template_exercises | template key | one bundle = header + ordered exercises; unchanged skips the header upsert, the id SELECT, the exercise upserts and the tail DELETE |
| `_syncScheduledWorkouts` | `:1593` | scheduled_workouts | date | existing index key kept; **completed carve-out removed** once the server guard is live (§5.10, §11); fingerprint the LOCAL template ref and call `resolveCloudTemplateId` (currently before the skip, `:1700`) only for rows being pushed; explicit null `template_id` (§5.4) |
| `_syncWaterLogs` | `sync_nutrition.dart:612` | water_logs | date | exclude `updated_at` |
| `_syncSavedMeals` | `sync_nutrition.dart:650` | user_saved_meals | id | §5.12 fallback `:696` |
| `_syncStepsLogs` | `sync_health.dart:314` | daily_steps | date | exclude `synced_at` |
| `_syncUrineColorLogs` | `sync_health.dart:347` | water_logs (urine column) | date | its own index; exclude `updated_at` |
| `_syncSleepLogs` + the legacy chat-sleep list loop in `syncSleepNow` | `sync_health.dart:276`, `:139-168` | sleep_logs | date / list item | §5.12 `:160`, `:296` |
| `_syncWeightLogs` | `:206` | weight_logs | date | §5.12 `:225` |
| `_syncMeasurements` | `:239` | body_measurements | date | §5.12 `:259` |
| `_syncReadiness` | `:61` | readiness_daily | date | §5.12 `:79` |
| `_syncCustomItems` | `sync_community.dart:103` | user_custom_exercises + user_custom_foods | id | one index, prefixed keys |
| `_syncWorkoutPlan` | `sync_workout.dart:1117` | user_progress.plan_json | single bundle | its stored value **is** `plan_bundle_cloud_fingerprint` (§5.7 L2) |
| Existing: `_syncExerciseLogs`, `_syncNutritionLogs`, `_syncScheduledWorkouts` (planned rows) | `sync_workout.dart:185`, `sync_nutrition.dart:201` | as today | as today | migrated onto the helper, **keeping their index keys** (no re-push burst) and kill-switch names |

Coach (`_syncCoachInteractions`, `sync_coach.dart:127-220`) keeps its existing skip, which is a
UUID `id` in the row. The fix: after a successful orphan upsert (`:200-209`), write the
deterministic cloud id back into the Hive row, as the dedup-hit branch already does (`:186-191`),
so the row is skipped from then on. Its `created_at` fallback (`:208`) derives from the `coach_<ms>`
key (§5.12).

**The gate, not a hand count, is the enumeration** (§7 G1). Any history loop the table misses fails
the commit.

**New index keys** follow the existing literal pattern `sync_<domain>_payload_hash_index`, and new
kill switches follow `disable_<domain>_hash_skip`. They live in the same box as the existing three
(verify at plan time).

### 5.10 Server migration (one file, `144_…sql`, number verified at plan time)

*(corrected 2026-09-28 at implementation: the migration is `148_sync_noop_suppress_completed_guard_sync_epoch.sql`, not `144_…` — plan D1 said `145`, this section originally said `144`; renumbered to 147 because 145 and 146 landed on `main` first, then to 148 the same day because 147 also landed on `main` first (`147_alert_client_errors_spike_breadth.sql`), from other concurrent work.)*

1. **Ignore updates that change nothing.** Add a `BEFORE UPDATE … FOR EACH ROW EXECUTE FUNCTION
   suppress_redundant_updates_trigger()` trigger on every table a history loop writes: the
   workout, nutrition, health, custom-item and `ai_coach_interactions` tables in §5.9, plus
   `workout_log_exercises`, `workout_log_sets`, `nutrition_logs` and `nutrition_log_items`. Take
   the final list from the gate's enumeration. `scheduled_workouts` is the one exception: it gets
   rule 2's function instead, which also covers identical updates, so it never has two no-op
   triggers.
   - The built-in trigger function is not SECURITY DEFINER.
   - It also cuts database writes from app versions already installed, for every payload that is
     identical between passes: scheduled days, template exercises, workout logs and streaks.
2. **A completed day can never be turned back.** Add a `scheduled_workouts` trigger function
   (SECURITY INVOKER) that `RETURN NULL`s when the new row is identical to the old one, or when
   `OLD.status = 'completed'` and `NEW.status` differs.
   - It returns NULL and **never raises**. Raising would fail the stale device's write, the
     helper would never record it as sent, and the device would retry on every pass.
   - Corrections to a completed row's `completed_at` stay allowed.
   - Verified: nothing demotes a completed day on purpose. There is no un-complete path in
     `lib/`. `weekly-recalc`, `rank_engine.ts`, `getProgressSummary`, `workout-window-closing` and
     `future-prediction` only read the table. Migration 050b's historical UPDATE touches only
     `template_id`.
3. **`sync_epoch`.** Add `user_progress.sync_epoch integer NOT NULL DEFAULT 0`.
   - The `update_user_progress_snapshot` RPC does not touch it.
   - Ops runbook: `update user_progress set sync_epoch = sync_epoch + 1 [where user_id = …];` makes
     that user's devices clear every skip index and re-send once.
   - The client reads it from the single launch fetch (§5.11) and compares it with `sync_epoch_seen`
     (new literal Hive key). On first sight it just stores the value.
   - Regenerate `backups/live_schema_columns.json` in the same commit (`check_schema_column_refs`).

Header: the four-tag migration header required by `supabase/migrations/CLAUDE.md`, with a rollback
(`DROP TRIGGER …` / `ALTER TABLE … DROP COLUMN sync_epoch`). The post-apply verification snippets
run inside `BEGIN … ROLLBACK` (CLAUDE.md §4.9 pitfall row). The apply is paired with
`backups/applied_migrations.json` in the same commit, and **needs the founder's explicit go**.

### 5.11 Launch reads

- `restoreLightweightAlways` runs **one** `user_progress` select and hands the row to both
  `_restoreUserProgress` and `_restoreWorkoutPlan`, via their existing pre-fetched injection
  parameters.
- `_restoreUserProgress` removes `plan_json` from the cloud row before `mergeCloudProgress`, so the
  blob stops landing in `userBox['progress']`. The copy already stored there is deleted once, by
  the same migrator as §5.7.
- `sync_epoch` is read from the same row.
- The plan merge then follows §5.7 L2: skip entirely when nothing is new.

### 5.12 Past timestamps: never "now"

**Rule:** a sync payload never sends "now" as a fallback for a timestamp describing the past. The
resolution order is:

1. the recorded value;
2. derived from a `*_ms` sibling or from a timestamp in the Hive key (`coach_<ms>`, `tmpl_<ms>`);
3. otherwise, **omit the field**, so the database keeps what it has. On insert the column default
   applies.

This matches the "absence beats null on the wire" convention already written at
`sync_workout.dart:613-614`.

**Completion time** gets its own resolver order: `completed_at` (ISO), then `completed_at_ms`, then
the matching `wlog_<date>`'s `completed_at`, then omit. It never uses `updated_at_ms` (§1.6).
`_resolveCompletedAt`'s own last-resort "now" becomes "omit", keeping its telemetry event
`sync_completed_at_fallback`.

**All 11 instances** (`?? DateTime.now()` in sync payloads):

| Where | Field |
|---|---|
| `sync_workout.dart:629` | completions `completed_at` (the recurrence) |
| `sync_workout.dart:1309` | template `created_at` (use the `tmpl_<ms>` key) |
| `sync_coach.dart:208` | orphan `created_at` (use the `coach_<ms>` key) |
| `sync_nutrition.dart:696` | saved-meal `created_at` |
| `sync_health.dart:79` | readiness `created_at` |
| `sync_health.dart:160` | legacy sleep list `created_at` |
| `sync_health.dart:225` | weight `created_at` |
| `sync_health.dart:259` | measurements `created_at` |
| `sync_health.dart:296` | sleep `created_at` |
| `sync_service.dart:1483` | onboarding replay `phase_started_at` |
| `sync_service.dart:1485` | onboarding replay `plan_generated_at` |

Also `_syncScheduledWorkouts` sends the resolved completion time instead of null (`:1707-1710`).
Existing wrong cloud values heal on the first sync after the update, because every row is pushed
once (no stored fingerprints yet).

---

## 6. UI

### 6.1 Train week list (`lib/features/train/screens/train/week_rows.dart`)

- Every movable row (§5.2) shows a ⇅ control: a visible affordance per the Wardroom rule, with the
  semantics label "Swap <Day> with another day". It opens the shared picker.
- **Long-press lifts the row.**
  - Expanded days collapse first.
  - The lifted slot shows "moving…".
  - Valid targets get a dashed gold outline on a 10% gold wash; the hovered target's outline is
    solid dashed and labelled "DROP TO SWAP".
  - Locked rows fade to 32% opacity with a lock.
  - Dropping opens the confirm sheet.
- **After a swap**, both rows show "⇄ MOVED" until completed. DONE always wins over MOVED. The
  Home strip follows the same precedence, and its current glyph precedence gets checked
  **(verify at plan time)**.
- **The allowance line** sits under the week list, followed by the how-to hint. Its number comes
  from the phone copy.
- **Web:** drag works with a mouse, and the ⇅ tap path works everywhere.

### 6.2 Home

The long-press on the Home calendar strip opens the **shared picker** for that day.
`swap_sheet.dart` is deleted in the same batch; `home_screen.dart:483` is its only caller.

### 6.3 Shared picker

- Lists the source day's Mon–Sun week.
- Locked days stay listed but dimmed, with their reason label, and can't be picked.
- The subtitle shows the live allowance.
- Picking a day and pressing the button **is** the confirmation on this path, so there is no second
  sheet.
- When the allowance is spent, the picker says so before any tap. "See PRO" opens `PaywallSheet`
  (the only paywall UI, rule 7).
- Buttons are `WardButton`, replacing today's raw `ElevatedButton`.

### 6.4 Copy (approved in the mockup unless marked NEW)

**Confirm sheet (drag path)**

- Eyebrow "Swap workout days" · title "Swap Friday and Saturday?"
- Body "Each workout keeps its exercises, sets and weights. Only the day changes."
- Rows "FRI 25 · Pull + Core → SAT 26" and "SAT 26 · Legs + Core → FRI 25"
- Allowance "Uses 1 of your 3 swaps this week. 2 left after this."
- Buttons "Swap days" / "Cancel"
- **NEW** warning line: "Heads-up: this leaves Wed, Thu and Fri as rest days in a row."

**After a swap (toast)**

- "Friday and Saturday swapped." / "Legs + Core is now tomorrow. 2 swaps left this week."
- Tag: "⇄ MOVED"

**Allowance line**

- "3 swaps left this week." + "Hold a day and drag it onto another, or tap ⇅"
- **NEW** for another week: "3 swaps left for Sep 28 – Oct 4."

**Picker**

- Title "Swap Friday with…", subtitle "Pull + Core · 3 swaps left this week"
- Day rows "Mon 21 … Thu 24 · today · Sat 26 Legs + Core · Sun 27 Rest day"
- Button "Swap Fri and Sat"
- Footer "DONE, STARTED, PAUSED AND PAST DAYS STAY PUT"

**Picker, free user, allowance spent**

- Subtitle "Pull + Core · 0 of 1 swaps left this week"
- "This week's swap is spent." / "Your allowance resets Monday. PRO gets 3 swaps a week, from the
  Train tab, Home, or by asking the coach."
- "See PRO" / "Close"

**Errors** (approved Section 4)

- PRO allowance spent: "All 3 swaps used. Resets Monday."
- Stale state: "Friday is already done. Nothing was changed."
- Write failure: "Couldn't swap. Nothing was changed."
- No signal / server down: nothing shown.

**Coach, PRO**

- "Aye, Recruit. Friday and Saturday trade places: Legs + Core today, Pull + Core tomorrow. Confirm
  below and it's done."
- Card:
  - "Swap Fri 25 and Sat 26"
  - "Pull + Core FRI → SAT"
  - "Legs + Core SAT → FRI"
  - "Uses 1 of your 3 swaps this week."
  - Apply / Dismiss

**Coach, free**

- "Swapping days from here is a PRO order, Recruit. You can do it yourself in two taps: on the
  Workout tab, tap ⇅ next to Friday and pick Saturday. You have 1 swap this week."

**Coach, PRO on an old app (NEW)**

- "Swapping days from here needs the latest app. After updating, ask me again or tap ⇅ next to the
  day on the Workout tab."

---

## 7. Gates (CLAUDE.md §4.11: land first, warn-only for 24h, then hard-fail)

- **G1: extend `scripts/check_sync_hash_skip_atomicity.dart`.**
  - Replace its count-based swallow check with a structural rule. In `lib/core/services/sync/**`
    and `sync_service.dart`, every `.upsert(` / `.insert(` inside a loop over Hive rows must sit
    inside a `pushIfChanged(` closure, except an explicit allowlist: the three single-row steps,
    and the coach loop, which skips by its stamped cloud id (§5.9).
  - No code outside `sync_skip_index.dart` may write a `*_payload_hash_index` key.
  - Comment-stripped before matching.
  - Mutation-proven: unwrap one domain → red; write an index key directly → red.
  - Update its rule-24 ledger entry.
- **G2: new `scripts/check_sync_no_now_fallback.dart`.**
  - Fails on `?? DateTime.now()` inside sync payload code (the same file set), comment-stripped.
  - It must fail on today's tree (11 hits) and pass after §5.12.
    *(corrected 2026-09-28 at implementation: 14 hits, not 11 — plan D2; see §9 bug #4's own correction below for the same count.)*
  - Rule 24: a mutation-proven test plus a `docs/audit/gate_test_ledger.yaml` entry. It takes no
    gate number (the filename is the identity).
- **Existing gates the batch must satisfy:**

  | Gate | Why it applies here |
  |---|---|
  | `check_ai_tool_dispatcher_coverage.dart` | extended in §5.8 |
  | `check_edge_function_auth_pattern.dart` + `check_authed_invoke_fresh_token.dart` | the new EF and its client call |
  | `check_schema_column_refs.dart` | the `sync_epoch` column |
  | Gate 42 `check_sot_behavioral_test_paths.dart` | every new SoT entry cites a behavioural test that exists |
  | Gate 14 `check_migrations_applied.dart` | the new migration |
  | Gate 40 closure-YAML validator | the batch closure file |
  | `check_plan_review_record_exists.dart` | at the merge |

---

## 8. SoT registry, docs, naming

**New SoT concepts**, each with a `behavioral_test_path`:

- `day_swap_engine`
- `day_swap_allowance` (phone copy + server key `day_swap` under `usage_quota_ledger`)
- `schedule_arrangement_stamp` (`arranged_at_ms`)
- `sync_skip_index`, plus one `*_payload_hash_index` concept per new domain, following the existing
  three
- `plan_bundle_cloud_fingerprint`
- `sync_epoch`
- `coach_client_capabilities`

**Updated SoT entries:**

- `scheduled_workouts_mutations` (new source `daySwap`, carry-forward rule)
- `sync_scheduled_payload_hash_index` (completed carve-out removed)
- `usage_quota_ledger`
- the schedule-row field contract in `docs/architecture/sync.md` (`arranged_at_ms`, `is_swapped`,
  `original_date` semantics)

**Docs:**

| File | Change |
|---|---|
| `docs/architecture/sync.md` | pattern section rewritten for the helper, the domain list, the server rules, `sync_epoch`, the launch fetch, merge L1–L3, the past-timestamp rule |
| `lib/core/services/CLAUDE.md` | updated |
| `lib/features/train/CLAUDE.md` | day-swap SoT rows |
| `lib/features/home/CLAUDE.md` | picker replaces SwapSheet |
| `lib/features/ai_coach/CLAUDE.md` | tool + capability |
| `supabase/functions/CLAUDE.md` | new EF, tool, capability |
| `docs/architecture/ai.md` | tool list 21 |
| `docs/naming_conventions.md` | glossary term **day swap** ("exchanging the content of two dated schedule rows in the same IST week; NOT exercise swap, NOT reschedule"); §3.3 Hive keys `displaced_` (exists but was never registered), `day_swap_allowance`, `sync_epoch_seen`, the new hash-index keys |
| `docs/adr/` | an ADR: "Sync sends only what changed; the server keeps completed days and drops no-op updates; `sync_epoch` is the repair lever" |
| `docs/operations/` | a runbook line for the `sync_epoch` bump |
| `docs/superpowers/specs/2026-04-27-ai-coach-brilliance-design.md` §5 | the Captain Manual amendment |

**OI board:** OI-237 closed by the commit that lands §5.9/§5.10 (`closes-oi: OI-237`).
*(corrected 2026-09-28 at implementation: OI-237 closes only AFTER the §10 IO-saving measurement is actually taken against the applied migration, not merely once §5.9/§5.10's code lands — plan D17. Landing the code is necessary but not sufficient; the OI names the measured saving, and there is nothing to measure until migration 148 (renumbered from 147 the same day) is live.)*

**Closure file:** `docs/audit/day-swapper-sync-load.closure.yaml`, with every finding in a terminal
state (Gate 40).

---

## 9. Testing

**Bug fixes and their diagnose-docs** (rule 22; each fix gets a test that fails without it, and the
diagnose-doc records the mutation and how many tests reddened, per rule 21):

| # | Bug | Writer → reader |
|---|---|---|
| 1 | A swap reverts after a restart, and workout↔workout swaps never reach other devices | `swap_service.dart:113` → `plan_integrity_reconciler.dart:69-90` + `plan_engine_flags.dart:499-504` |
| 2 | The coach sends swaps to rescheduleWeek | `captain_manual.ts:386`, `rescheduleWeek.ts:25-26` → `tool-loop.ts:265` |
| 3 | The existing swap has no guards, is not atomic, miscounts, leaves stale markers, a stale template link and a skipped deload | `swap_service.dart:113-169`, `:479-530`, `:567`; `sync_workout.dart:1714`; `deload_evaluator.dart:210` |
| 4 | Completion times overwritten with "now" (recurrence of `5a36ad`), plus the 11-instance class *(corrected 2026-09-28 at implementation: 14 instances, not 11 — plan D2, same recount as §7 G2's correction above)* | `workout_write_service.dart:502` → `sync_workout.dart:628`, `:1707` |
| 5 | Sync write amplification (OI-237), the double plan download, and the Hive re-writes on launch | §1.5 |
| 6 | Restore types rest days as workouts (28 live rows) | `sync_workout.dart:2097-2100` → `plan_integrity_reconciler.dart:96-107` |

**Test layers:**

- **Pure rules** (`DaySwapRules`): every locked state, week boundaries on both sides of Sunday
  23:59 / Monday 00:00 IST, first-origin and back-home markers, the 3-rest warning (creates vs
  pre-existing run), the allowance maths, and the field partition (every content field moves, every
  identity field stays).
- **Engine against real Hive:**
  - atomic write (both or neither, including injected failure of the second write);
  - no count on failure;
  - `displaced_` travels, and when both days have templates the backups exchange;
  - swap-back clears MOVED and keeps `arranged_at_ms`;
  - checks run at confirm time against rows changed after the screen opened.
- **Restore merge I1–I8** (§5.7) as behavioural tests over real Hive plus a fake downloaded
  bundle, including the reinstall sequence the app actually runs (I2; verify the real ordering at
  plan time) and the hybrid migrator.
- **Sync, against a fake Supabase client:**
  - for each domain, an unchanged second pass sends 0 writes and a changed row sends exactly 1;
  - a thrown push is retried on the next pass;
  - a change only to a sent-at stamp sends nothing;
  - templates skip as one unit;
  - `resolveCloudTemplateId` is not called for skipped rows;
  - a `sync_epoch` bump re-sends everything once;
  - launch makes one `user_progress` select and no `plan_json` reaches `userBox['progress']`;
  - completion times are the true ones, and every §5.12 site omits rather than sends "now";
  - the existing three domains keep their stored indexes, with no re-push burst.
- **Live SQL** (`test/sql/*_live_verify.sql`, always `BEGIN … ROLLBACK`, never touching real rows):
  - an identical upsert creates no new row version (`xmin` unchanged) on each table;
    *(corrected 2026-09-28 at implementation: "no new row version (`ctid` unchanged)", not "`xmin` unchanged" — inside one `BEGIN … ROLLBACK`, every row's `xmin` is the test's own transaction id, so `xmin` cannot tell a suppressed update from a real one; Task 7's harness header.)*
  - a completed row cannot be demoted, but its `completed_at` can be corrected;
  - `sync_epoch` defaults to 0 and the progress RPC leaves it alone.
  - **Discrimination:** inside the same transaction, drop the new triggers and re-run each
    assertion. It must fail, which proves it measures the change (CLAUDE.md §4.9: last time, 5 of 7
    new assertions passed against the old code).
- **Deno:**
  - tool definition (PRO, reviewable, intent type);
  - capability filter: absent field → exactly the 20 legacy tools; declared → 21;
  - rescheduleWeek hints no longer contain swap phrasing;
  - manual routing, in the style of the `captain_manual_*_test.ts` files;
  - `consume-day-swap`: auth pattern, IST Monday window at the boundary, limit by tier, `-1`
    mapping, `week_start` validation;
  - `deno check --node-modules-dir=none` on every touched function.
- **Widgets:**
  - ⇅ appears only on movable rows;
  - drag states (lift, targets, locked fade), and a drop opens the confirm sheet;
  - confirm sheet copy, including the warning line;
  - the picker, including locked reasons and the spent state → PaywallSheet;
  - the allowance line (this week / another week);
  - MOVED vs DONE precedence on Train and Home;
  - the coach card.
- **Snapshot:** the lookahead fields, and a worst-case size under 10K chars.
- **Mutation:** every test written by this batch is broken once, the mutation is confirmed to have
  applied, the code still compiles, and the reds are counted and recorded in the diagnose-doc. A
  zero-red mutation is investigated, not accepted (CLAUDE.md §4.4 rule 21).
- **New tests run once inside the full suite** before they are trusted (CLAUDE.md §4.9
  timeout/contention row).

---

## 10. Measuring the IO saving

- **Baseline:** for the 3 days before rollout, record `n_tup_upd`, `n_tup_ins` and `n_tup_hot_upd`
  per table from `pg_stat_user_tables` for every table in §5.10.
- **After:** the same for the 3 days after the new build reaches the founder's devices.
  - The server rules show up immediately, even for installed app versions.
  - The client skip shows up once devices update.
- **On the device:** a `kDebugMode` log line per pass per domain ("pushed N, skipped M"). Expect
  about 0 pushed on an idle pass, and a handful plus the new sets after a workout.
- **Completion times:** re-run §1.6's query. No record for an old day should be re-stamped
  recently.
- The numbers go into the OI-237 closure note.

---

## 11. Rollout and rollback

**Order.** Each step is safe for the app versions already installed:

1. **Migration** (founder go) → verify live (triggers present; the ROLLBACK behavioural SQL
   passes) → `applied_migrations.json`.
   - Must precede the client, because the client stops re-sending completed days.
2. **Edge Functions** (founder go): `consume-day-swap`, then `ai-proxy` with the capability-gated
   tool, the manual amendment and the corrected hints.
   - Installed apps immediately stop getting the silent no-op: they declare no capability, so they
     get the fallback line.
   - Verify with a REAL user token (rule 9) and legacy-shape requests: no `client_capabilities` →
     today's 20 tools.
3. **App:** merge to `main` after the B-pass.
   - Pushing `main` redeploys the web app (Vercel `avya`).
   - The AAB is built only when the founder asks (`/build-apk` from `main`).
   - The coach tool switches on, and phone-side skipping starts.
4. **Checks:**
   - an end-to-end run on the web (`.claude/skills/e2e-sim-testing/SKILL.md`): a PRO coach swap, the
     free fallback line, the weekly limit;
   - then the founder's device test (§5 checklist, non-negotiable):
     - drag and ⇅ swaps;
     - a swap survives a restart;
     - completed days stay locked;
     - the swap after the weekly limit is blocked;
     - Home long-press opens the new picker.

**Kill switches** (CLAUDE.md §4.6: sync changes keep the old path reachable). All are local Hive
flags, since there is no remote config (`sync_service.dart:275`):

- per domain `disable_<domain>_hash_skip` (the existing three keep their names)
- `disable_plan_merge_skip_when_known` (L2)
- `disable_swap_arrangement_merge` (L3)
- `disable_rest_row_refill_guard` (L1)
- `disable_restore_single_plan_fetch`
- `disable_day_swap_train_ui` (hides drag and ⇅; the Home picker keeps working)

Pure bug fixes whose old path *is* the defect get no switch: completion times, restore type
derivation, the template null link, and the engine's guards. Preserving the old swap verbatim
would preserve the revert bug.

**Rollback:**

- Each server rule is one `DROP TRIGGER` (founder go).
- The coach tool is removed by redeploying `ai-proxy` without it (minutes, no app release).
- Phone-side pieces use their local switches; turning them off for everyone takes a release.

---

## 12. Review and execution

- **Flow:** spec → founder review → `superpowers:writing-plans` → 2 independent context-blind plan
  reviews (the second on the corrected plan) → a plan-review record at
  `docs/plan-reviews/<recordSlug(branch)>.md` → execution.
- **Before every review round with a diff:** the full gate loop, `flutter analyze lib/` and
  `flutter test`.
- **Before the merge:** a B-pass, started by the agent. A Hermes pass if any file classifies
  catastrophic.
- **Every live action gets its own go:** the migration apply and each EF deploy.
- **Execution mode** (§4.12.7, decided now): subagent-driven, at most 4 units at a time, each unit
  in its own worktree.
  - The coordinator is the only writer of shared files: everything under
    `lib/core/services/sync/`, `sync_service.dart`, `plan_integrity_reconciler.dart`,
    `workout_write_service.dart`, the registries, CLAUDE.md files, docs and backups.
  - Units by file ownership:

    | Unit | Scope |
    |---|---|
    | U1 | migration + live SQL tests |
    | U2 | `consume-day-swap` + `ist_date.ts` helper + Deno tests |
    | U3 | ai-proxy capability, the tool, manual, hints + Deno tests |
    | U4 | `DaySwapRules`, the engine, `DaySwapAllowance` + tests |
    | U5 | Train UI, picker, confirm sheet, Home wiring, SwapSheet deletion + widget tests |
    | U6 | dispatcher case, coach card, snapshot lookahead + tests |

  - Gates G1/G2 land first, in the coordinator's first commit.
- The implementation branch starts from a fresh worktree on the latest `main` (§4.13). This spec's
  worktree is 5 commits behind.

---

## 13. Plan-time verification checklist

These are checks the plan must run and record. They are not open design questions.

1. The real reinstall sequence: does anything generate schedule rows before `_restoreWorkoutPlan`
   merges? Write I2's test against the actual order.
2. The provider invalidation set after a swap (Train list, Home strip and today card, calendar,
   streak, coach insight).
3. The Home weekly strip's glyph precedence for `is_swapped` vs completed (DONE must win).
4. The next free migration number (the highest 3-digit today is 143), using the 3-digit-scheme
   listing, not a numeric sort (CLAUDE.md §4.9).
5. Blast-radius classification of the written files, via the bare `-` stdin form.
6. The full list of tables for §5.10 rule 1, from G1's enumeration.
7. Whether any upsert on those tables chains `.select()` (a suppressed update returns no row).
8. `consume_quota`'s behaviour when `p_limit` drops below `used` (a downgrade mid-week): it must
   return `-1` without incrementing.
9. The box holding the existing `disable_*_hash_skip` flags and index keys.
10. All ai-proxy chat call sites in `ai_service.dart` that must send `client_capabilities`.
11. That `zodToGemini` accepts the tool's param schema.
12. Readers of `workout_schedule_completions.completed_at` and `scheduled_workouts.completed_at`
    whose output changes once true times land.

---

## 14. Rejected alternatives

| Alternative | Why not |
|---|---|
| Rearrange mode (insert/reorder) | One gesture can spend up to 3 swaps; locked days block the shift. |
| Instant swap + undo | The cost isn't visible before paying; the undo would need a refund path. |
| Keep blocking 3 rest days in a row | Industry tools let you move freely; 0 of 13 live users had such a run; decision 10. |
| OI-237 as its own batch first | Founder decision 11. |
| Daily 7-day re-send safety net | A blind re-send of planned/rest days from a stale device would undo another device's swap. `sync_epoch` covers repair after cloud loss at zero day-to-day cost. |
| General last-write-wins on `updated_at_ms` for every schedule row | Freshly generated rows on a reinstall are "newer" than the backup, which would reintroduce `a7d3f1`. |
| Per-pair (not per-week) arrangement merge | Overlapping swaps from two devices leave one workout on two days. |
| Batched array upserts | A poison row fails the whole batch; little gain once only changed rows are sent. |
| A SECURITY DEFINER SQL function for the allowance | Forces catastrophic tier; the tier logic already lives in `_shared/subscription.ts`. |
| A server read for "swaps left" | Costs a read on every screen open; the phone copy corrected by each consume reply is enough. |
| A remote-config service | New infrastructure; rollback is a release for phone-side pieces and SQL/EF redeploys for server-side ones. |
| Retrying the consume call | An ambiguous failure plus a retry double-counts; one uncounted swap is the accepted cost. |
