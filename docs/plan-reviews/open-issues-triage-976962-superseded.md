# Plan (DRAFT — ROUND 1 REVIEW: **NOT CONVERGED**) — OI-60 flip-on: FOB-1,2,3,4,5,7

> ## ⛔ DO NOT IMPLEMENT THIS PLAN AS WRITTEN — 2 P0s + 6 P1s, round 1, 2026-08-12
>
> Status: DRAFT, **NOT CONVERGED**, no `---` frontmatter deliberately (it is not a valid
> plan-review record and must not satisfy the merge-to-main keystone gate). Round 1 was an
> independent context-blind review; **two of its P0s were re-verified by direct file read** and
> both are correct. Sections below carry inline `⛔ REFUTED` / `⚠ REVISED` markers — a section
> without a marker was verified clean by round 1 and may be trusted; a marked section is WRONG
> and its prescription must not be followed.
>
> **The headline finding is scope, not any single defect:** round 1 (not round 5) surfaced
> structural redesigns in 4 of the 6 items. Per §4.12.1 that is the signal the unit is too
> large — this is 5+ batches, not one. See "§4.12.1 split" at the bottom, which supersedes the
> single-batch framing throughout the body of this file.
>
> FOB-6 (selectable past hold weeks) was already out of scope — founder decision 2026-08-12,
> split out as its own follow-on feature.
>
> Round-1 P0/P1 index: **P0-A** FOB-2 (fix disables the streak) · **P0-B** FOB-7(b) (scan IS
> the trigger; zero healing gain) · **P1-C/D/E** FOB-5 (unsatisfiable filter; cannot be
> `CREATE OR REPLACE`; misses 2 EFs + a model + a contract test) · **P1-F** FOB-3
> (`AiSnapshotBuilder` has no `Ref`) · **P1-G** FOB-1/7(a) (row-field branches ignore the
> kill-switch) · **P1-H** FOB-4 (pins a known-broken baseline).

## Context

`enable_hold_weeks` (default OFF) ships the free-tier "Hold the Line" mechanic (`holdWeek()`,
diagnose `d7f3a9`) plus its display slices (`hold_display_read_path` SoT). Flip-on requires
closing 7 flip-on-blocker items (FOB-1…FOB-7, `docs/ship_dark_pending_review.yaml`) plus its own
full ×2 review + `bpass: accepted` per §4.12.4. This plan covers FOB-1,2,3,4,5,7. FOB-6 is a
distinct new feature (selectable past hold weeks, 6 named lifecycle traps) and ships separately.

All six items below were re-verified against **current on-disk source** (2026-08-12), not taken
from the 2026-07-25 FOB filing verbatim — several file:line citations in the ledger have
shifted, and two claims (day_detail_sheet write-time formula; ai-media-proxy wrapper) turned out
to be either worse or already-fixed than the filing stated. Discrepancies are called out per item.

---

## FOB-1 — Week-identity coherence ("a hold suppresses the week number; Hn is the identity")

### Already fixed (verify only, no new work)
- `lib/features/train/screens/train/plan_header.dart:62-65,129` — branches on `holdStatusProvider`, shows `HOLDING · Hn` pill, drops `WK n OF m`.
- `lib/features/train/screens/train/screen.dart:235-238` — same branch.
- `lib/features/train/widgets/hero_cards.dart`, `hold_chip_group.dart`, `hold_roadmap_strip.dart`, `plan_expired_card.dart` — per `lib/features/train/CLAUDE.md`'s `hold_display_read_path` SoT entry, already shipped Slices 2-6.
- `lib/features/train/screens/phase_roadmap_screen.dart:50-54` — uses `getProgramWeek` (never `getCurrentWeekNumber`), and per that function's own doc comment (`workout_schedule_read_service.dart:829-831`) is **deliberately** hold-blind (roadmap position is program-week, unaffected by a hold). Not a bug — no change.

### Stale FOB claim — drop from scope
- `lib/features/train/screens/train/preview_workout_screen.dart` — investigation confirms this is **not** a hold-row reader at all. Its `week` param is a route query param supplied only by (a) a free user tapping a locked PRO week chip (`screen.dart:333-336`, weeks 5-12) and (b) hardcoded literals in `phase_roadmap_screen.dart:109,122`. Hold chips route to a separate sheet (`week_selector.dart:300` `_showHoldWeekSheet`). No fix needed; the original FOB-1 filing was wrong about this file.

### Still broken — fix in this batch
For each, add a hold branch reading `ref.watch(holdStatusProvider).isHolding` (or the schedule row's own `is_hold` field where the surface already has the row in hand) and render `HOLDING · Hn` (or omit the week number) instead of the clamped `getCurrentWeekNumber()`-derived value. Never project `4 + hold_ordinal` as a substitute week number (c9f4a2's forbidden pattern) — the fix is to suppress/replace with the hold identity, not compute a "correct" week number.

1. **`lib/features/home/screens/home_screen.dart:310-317`** — eyebrow text `'DAILY · ... · WK $weekInPhase · PHASE $currentPhase'`. Fix: `ref.watch(holdStatusProvider)`; when `isHolding`, render `'DAILY · ... · HOLDING · H${todayHoldOrdinal} · PHASE $currentPhase'`.
2. **`lib/features/profile/providers/profile_provider.dart:330`** (`UserStatsData.currentWeek`) → consumed by **`journey_timeline.dart:87,108,170`** (`'WEEK N OF 4'`, a progress bar `pct: currentWeek/4.0`, and `'(4-currentWeek) weeks to complete Phase 1'`). Fix: add `bool isHolding` + `int? holdOrdinal` to `UserStatsData` (sourced from `holdStatusProvider` in the provider, not a raw Hive read — per the repository-pattern rule), and branch all three `journey_timeline.dart` sites: holding → `'HOLDING · Hn'` label, progress bar shows the hold's `sessionProgress` (already computed by `HoldStatusData`) instead of `currentWeek/4.0`, and the "weeks to complete" line is suppressed (a hold has no completion countdown by definition).
3. **`lib/features/profile/screens/reports_screen.dart:1379`** (`triggerWorkoutVideo` `inputProps['weekNumber']`) — the Share-as-Video render payload. Fix: same branch; pass `holdStatus.isHolding ? null : getCurrentWeekNumber()` and update the video-render template's copy to omit the week line when null (needs checking what `triggerWorkoutVideo`'s consumer — likely a Remotion/video-render Edge Function or client-side renderer — does with a null `weekNumber`; if the render pipeline requires a non-null int, pass a sentinel the template already knows to suppress, e.g. `0`, and update the template. **Flag for review**: need to confirm the video-render consumer's contract before finalizing — this is the one FOB-1 surface with a downstream consumer outside `lib/`.)
4. **`telegram-bot/bot.py:336-337,345`** — `f"📅 Phase {phase}, Week {week}\n"`, reading synced `user_progress.current_week`. This is the ONE surface with no client-side hold signal available (bot reads Postgres, not Hive) — `user_progress` has no hold column (confirmed: is_hold/hold_ordinal are Hive+plan_json only). Fix options: (a) have the bot also fetch `plan_json`, parse today's schedule row for `is_hold`/`hold_ordinal` (Python, one more query — plan_json is jsonb, already exposed to server-side readers per FOB-3 investigation), or (b) skip this surface in this batch since the bot is a separate project not gated by `enable_hold_weeks` review scope. **Recommend (a)** — same information source FOB-3/FOB-4 will already be reading server-side (see below), so add a small shared helper (`telegram-bot` already has its own Postgres client) rather than leave the bot alone as the one surface never fixed. Render: `f"📅 Phase {phase} — HOLDING · H{ordinal}\n"` when holding.
5. **`lib/features/home/widgets/day_detail_sheet.dart:102,124-127`** — reads `schedule?['week']`. The row's own `week` field is literal `4 + hold_ordinal` (write-time stamp, `workout_schedule_write_service.dart:284`), which is wrong for a phase-2+ holder (should not be interpreted as a program week at all). Fix: read `schedule?['is_hold']` / `schedule?['hold_ordinal']` directly off the same row (already stamped there, no new lookup needed) and branch to `'HOLDING · Hn'` before falling back to the existing `'WEEK $week'` render. **Do NOT touch the write-time `'week' = 4+n` stamp** — `holdWeek()` already shipped its own full ×2 review (d7f3a9) and that field is otherwise inert (zero EF/cron readers of `week_number`, confirmed in that diagnose's `forbidden_patterns_checked`); reading `is_hold` first at this one call site fully resolves the display bug without reopening reviewed code.

### Out of scope (belongs to FOB-6, not this batch)
- `lib/features/train/providers/train_provider.dart:801` (`phaseArcProvider`) and `:902` (`SelectedWeekNotifier.build`) — which week tab defaults to selected / phase-arc wave-strip index during a hold. `lib/features/train/CLAUDE.md`'s own SoT entry states hold chips must **never** drive `selectedWeekProvider` — this is deliberate, and any change to which week auto-selects during a hold is exactly the kind of lifecycle question FOB-6 (traps (b) and (d)) is scoped to resolve. Leaving unchanged here.
- `lib/features/ai_coach/services/ai_snapshot_builder.dart` — covered by FOB-3 below (a proper `hold` block with real semantics), not duplicated here as a display suppression.

### Tests
`test/contracts/hold_week_identity_display_test.dart` (new) — one case per fixed surface (2-5 above): flag ON + `is_hold`/hold-status present → renders hold identity, never the clamped week number; flag OFF → byte-identical to current (pre-fix) output. Each case fails on a revert of its specific site (mutation-proof per rule 24 spirit, though this is a behavioral test not a `check_*.dart` gate).

---

## FOB-2 — Weekly streak dead during a hold

### Current state (verified)
- `getCurrentWeekNumber()` (`workout_schedule_read_service.dart:1025-1033`) clamps `(days-since-plan_start ~/ 7 + 1)` to `[1,4]`.
- `train_provider.dart:1765` sets `currentWeekNum = getCurrentWeekNumber()`; `:1782` writes `last_streak_week: currentWeekNum`; `:1774` gates the increment on `currentWeekNum != lastStreakWeek` — always `4 != 4` → false for every hold completion after the first.
- `train_provider.dart:1786-1789` computes the streaks-row key as `weekStart = plan_start + 7*(currentWeekNum-1)` → also always the phase's week-4 Monday during any hold, so every hold-week completion **overwrites** that one row (`onConflict: user_id,week_start`, `sync_workout.dart:585-586`).
- `HoldWeekInfo` (`workout_schedule_read_service.dart:71-95`) **already exists** with a `weekStart` field populated by-date (via `_holdDatesByOrdinal`, parsing actual `schedule_<date>` keys) — the correct source is already built, just not consumed here.
- `streaks.week_start` is `date NOT NULL` with `UNIQUE(user_id, week_start)` (migrations 004, 012) — keying by date needs no migration.
- `last_streak_week` must stay an `int` — `train_provider.dart:1770` casts `as int?`, and `completeWorkout()` (`:1514`+) has no try/catch around the write.

### ⛔ REFUTED — Fix below is WRONG (round-1 P0-A, re-verified by direct read)
The fix as written **disables the streak during a hold — strictly worse than the freeze it
fixes.** It enumerates three uses of `currentWeekNum` and says "use `weekIdentity` everywhere";
there is a **fourth**, one line later, that it missed:
`lib/features/train/providers/train_provider.dart:1766` — `final weekDays = repo.getWeek(currentWeekNum);`
`getWeek` is a pure date walk (`workout_schedule_read_service.dart:932-937`,
`weekStart = planStart.add(Duration(days: (weekNumber - 1) * 7))`), so an epoch-week index
(~2953) walks ~56 years forward → empty list → `planned == 0`. That kills the increment gate
(`:1771`, `planned > 0 && …`) **and** the entire streaks-row block (`:1787`,
`if (planStart != null && planned > 0)`) — no increment *and* no row at all.

**Correct shape: THREE values, not two** — `weekIdentity` (int, for the `!= lastStreakWeek` gate
and the `last_streak_week` write), `weekStartDate` (the row key), and a separate **day source**
that fetches the hold week's 7 rows BY DATE (`HoldWeekInfo.weekStart` + `getScheduleForDate`),
never `getWeek(weekIdentity)`. Add a test case asserting `planned > 0` on a hold completion —
the plan's own test list would not have caught this.

Also: P1-G applies here — the new branch must gate on `PlanEngineFlags.holdWeeksEnabled` (via
`holdStatusProvider`, which already returns `.empty` when OFF), so flag-OFF is byte-identical.

### Fix (superseded by the correction above — retained to show what round 1 rejected)
In `train_provider.dart`'s `completeWorkout()`, before the existing `currentWeekNum`/`lastStreakWeek` block:
```dart
final holdStatus = ref.read(holdStatusProvider);
DateTime weekStartDate;
int weekIdentity;
if (holdStatus.isHolding) {
  final info = holdStatus.holds.firstWhere((h) => h.ordinal == holdStatus.todayHoldOrdinal);
  weekStartDate = info.weekStart;
  // Absolute epoch-week index: monotonic, always outside [1,4], never
  // collides with a non-hold currentWeekNum, and distinct per calendar
  // week even across a late-return date gap (never `plan_start + 7*ordinal`).
  weekIdentity = weekStartDate.difference(DateTime(2020, 1, 1)).inDays ~/ 7;
} else {
  weekIdentity = getCurrentWeekNumber();               // UNCHANGED non-hold path
  final planStart = WorkoutScheduleService.instance.getPlanStartDate();
  weekStartDate = planStart!.add(Duration(days: (weekIdentity - 1) * 7));
}
```
Then use `weekIdentity` everywhere `currentWeekNum` was used (the `!= lastStreakWeek` gate, the `last_streak_week` write — still an int, still `!= -1`-init-safe) and `weekStartDate` for the streaks-row key (`formatDateKey(weekStartDate)`), replacing the `plan_start + 7*(currentWeekNum-1)` expression. The non-hold branch is **byte-identical** to current behavior (same value, same formula) — only the hold branch is new, so no risk to the existing (well-tested) non-hold streak logic.

### Tests
`test/contracts/hold_streak_test.dart` (new): (a) two consecutive hold-week completions at the same ordinal advance `current_streak_weeks` (fails today — reverting the branch reproduces the freeze); (b) two different hold ordinals produce two distinct `streaks` rows keyed by their own Mondays (fails today — reverting collapses to one row); (c) a late-return hold (ordinal 1 materializing at date-week 8, matching the existing late-return case in `hold_display_read_path_test.dart`) still gets a correct, date-derived row key; (d) `last_streak_week` stays an `int` in all branches (type-level regression guard); (e) flag OFF → byte-identical to pre-fix output.

---

## FOB-3 — AI coach snapshot is hold-blind (needs ai-proxy redeploy — separate authorization)

### Current state (verified — FOB-3's literal premise is stale, underlying complaint still true)
- `ai_snapshot_builder.dart:92-96` and `:1218-1221` both already emit `getProgramWeek` (post-c9f4a2), not a hardcoded 4 as the 2026-07-25 filing describes — **but** `getProgramWeek` is itself hold-blind (climbs/derives purely from phase+date), so the snapshot still tells no story about a hold and keeps advancing the number a holder is deliberately not advancing past.
- Zero `is_hold`/`hold_ordinal` reads anywhere in `supabase/functions/` (confirmed by grep).
- `trimSnapshotToBudget` (`ai_snapshot_builder.dart:236-287`) has an explicit `keep` set (`:241-248`) of ~17 fields never trimmed; anything else is iteratively halved/dropped by size. A new `hold` block MUST be added to `keep`, or it can be silently dropped under budget pressure.
- `captain_manual.ts:108` — "Phases II–XII auto-generated (free locks at Phase I after 4 weeks)" — the exact sentence that manufactures the false "you've hit the wall, upgrade" narrative for a holder, with zero hold-awareness anywhere in the file.
- `is_hold`/`hold_ordinal` already reach cloud `plan_json` (confirmed: `sync_workout.dart:1040` copies every `schedule_*` key verbatim into the pushed bundle, and `holdWeek()` explicitly awaits `pushWorkoutPlanForSyncDomain()` for durability) — so ai-proxy CAN read hold state from `plan_json` server-side without a new column or migration.

### Fix
1. **Client** (`ai_snapshot_builder.dart`): add a top-level `hold` block next to `current_plan_summary`:
   ```dart
   'hold': holdStatus.isHolding
       ? {'is_holding': true, 'ordinal': holdStatus.todayHoldOrdinal,
          'sessions_completed': holdStatus.sessionsCompleted, 'sessions_total': holdStatus.sessionsTotal}
       : {'is_holding': false},
   ```
   sourced from `holdStatusProvider` (same provider FOB-1/FOB-2 use — no new read path). Add `'hold'` to `trimSnapshotToBudget`'s `keep` set (`:241-248`).
2. **`_shared/captain_manual.ts`**: add a short paragraph after the `:108` sentence — "If the user's snapshot carries `hold.is_holding: true`, they are intentionally repeating a week via the free-tier 'Hold the Line' mechanic, NOT stuck or out of runway. Never tell a holding user they've hit the 4-week limit or push an upgrade off that framing; acknowledge the repeat and encourage consistency." Keep the existing free-tier framing sentence for non-holders unchanged.
3. **Deploy**: `_shared/captain_manual.ts` is bundled into the `ai-proxy` function — this fix requires an `ai-proxy` redeploy, which needs its own explicit founder go per §4.3 (plan approval ≠ deploy approval) even after this plan converges.

### Tests
`test/contracts/ai_snapshot_hold_block_test.dart` (new): snapshot includes `hold.is_holding: true` + correct ordinal when `holdStatusProvider` reports holding; `hold.is_holding: false` otherwise; `hold` key survives `trimSnapshotToBudget` even under simulated budget pressure (fails today by reverting the `keep`-set addition — demonstrates the silent-drop risk named above). Server-side: no automated test for `captain_manual.ts` prose (house convention — it's reviewed by the coach-response smoke test in the deploy-rollback skill, not a behavioral test); note this explicitly rather than claim coverage that doesn't exist.

---

## FOB-4 — Sunday push + weekly report need hold copy (needs its own EF redeploy — separate authorization)

### Current state (verified)
- `weekly-recap-ready/index.ts:73-79` — `` `${firstName} — Week ${currentWeek} debrief ready. Stand to.` `` — `currentWeek` from `user_progress.current_week` only (`:223-231` query — no `plan_json` fetched).
- `weekly-report/index.ts:482` — `` `- Current week: ${userProgress?.current_week ?? 1}` `` fed into the Gemini brief; query (`:147-151`) selects `current_phase, current_week, current_streak_weeks, total_workouts_done` — no `plan_json`.
- Neither EF has any existing `plan_json`-reading helper in `_shared/` (confirmed zero hits) — this is a new server-side read pattern, not an existing convention to follow.

### Fix
Both functions add `plan_json` to their existing per-user query (already-cheap jsonb column, ≤17 users today), then derive "was this user holding as of the recap/report date" the same way the client does: find the schedule row for the target date/week inside `plan_json.schedules`, check `is_hold`/`hold_ordinal`.
- **`weekly-recap-ready`**: when holding, push copy becomes `` `${firstName} — Hold week H${ordinal} complete. Stand to — full recap inside.` `` instead of the week-number line.
- **`weekly-report`**: when holding, the Gemini brief line becomes `` `- Current status: Holding (repeating a week, H${ordinal}) — not advancing this week by design.` `` instead of `Current week: N`, so the Gemini-generated narrative doesn't independently invent an advancing-week story that contradicts the push.

Add a small shared helper in `supabase/functions/_shared/` (e.g. `hold_status.ts`, `resolveHoldStatus(planJson, targetDate)`) rather than duplicating the plan_json-parsing logic in both functions — this is the first EF-side reader of `plan_json` for a conditional, so establishing one small shared parser now avoids a third copy when FOB-1's telegram-bot fix (item 4 above) needs the same logic in Python (parallel implementation, can't share the TS module, but the *shape* of the parse should match to avoid drift).

**Deploy**: both `weekly-recap-ready` and `weekly-report` need redeploys — separate, explicit founder authorization per §4.3, on top of the ai-proxy redeploy for FOB-3. Three EF deploys total for this batch, each its own go/no-go.

### Tests
`test/contracts/weekly_recap_hold_copy_test.dart` / equivalent Deno test colocated with the EF (match house convention — check how existing `weekly-recap-ready`/`weekly-report` tests are structured before adding, likely `supabase/functions/weekly-recap-ready/index.test.ts` if one exists): holding user → hold-aware copy; non-holding → unchanged current-week copy (byte-identical regression guard for the non-hold path).

---

## FOB-5 — Hold telemetry has zero consumers; `ai_messages_today` inflated by non-chat channels

### Current state (verified)
- The five `phase_1_day_29_*` events (`plan_expired_card.dart:52,60,103,112` + one more) write via `AppEventsService.log()` → `ai_coach_interactions` with `channel: 'app_event'`. Confirmed zero readers repo-wide (no query/cron/dashboard/alert references any of the five event strings).
- `founder_metrics_engagement()` (`supabase/migrations/101_admin_dashboard_metrics_functions.sql:82-84`) counts `ai_coach_interactions` for `ai_messages_today` with **no** `channel` filter — every `app_event` row (plus `food_text_analysis`, `scan_meal`, `cart_auditor`, image-analysis, paywall-view channels — all confirmed non-chat channel values on this table) inflates the "AI messages today" tile.

### Fix
1. **Migration**: `CREATE OR REPLACE FUNCTION public.founder_metrics_engagement()` — add `and channel = 'app'` to the `ai_messages_today` subquery (line 82-84). No other column/signature change (safe `CREATE OR REPLACE`, same return type). Needs `backups/applied_migrations.json` update in the same commit (§4.5) and its own explicit apply-authorization per §4.3 (live prod apply).
2. **New event with a real consumer**: `holdWeek()` (`workout_schedule_write_service.dart`, near the `is_hold`/`hold_ordinal` stamps at `:287-288`) fires `AppEventsService.instance.log('hold_week_started')` once per materialize (not per row — the mutex already guards re-entrancy). Give it a real consumer by extending `founder_metrics_engagement()`'s same migration to add a `hold_weeks_started_7d bigint` column, counting `ai_coach_interactions where channel='app_event' and event_name='hold_week_started' and created_at >= now() - interval '7 days'` (exact column name for the event-name field to be confirmed against `AppEventsService.log()`'s actual insert shape before finalizing — the investigation agent did not report the column name it writes the event string into, only that it inserts into `ai_coach_interactions`). This makes the metric genuinely consumed (the admin dashboard already calls `founder_metrics_engagement()`), rather than repeating the four-events-zero-consumers mistake this very FOB item flags.
3. **Explicitly out of scope**: the four pre-existing `phase_1_day_29_*` events stay consumer-less after this fix — FOB-5 asks for a NEW event with a real consumer plus the channel-filter fix, not a retrofit of the old ones. Documenting this so it isn't later assumed fixed.

### Tests
`test/contracts/hold_telemetry_test.dart` (new, or extend an existing `founder_metrics_engagement` test if one exists — check first): `ai_messages_today` excludes `app_event`-channel rows (fails today without the filter — a seeded `app_event` row currently inflates the count); `hold_week_started` fires exactly once per `holdWeek()` call even under the existing re-entrancy mutex (source-wiring assertion); `hold_weeks_started_7d` reflects seeded rows.

---

## FOB-7 — Four residuals

### (a) `currentPhaseCompletionRate` folds hold days into the PRO-advance gate
**Verified**: `workout_schedule_read_service.dart:998-1022`, phase≥2 branch, `getWeek(w)` for `w in 5..12` is a pure date walk with no `is_hold` filter; hold days occupying dates in that window are folded into `days` and thus into the ratio `phaseCompletionRate(days)` gating PRO phase-advance. (Corrects the FOB filing's "phase>=2 branch" framing slightly: this can affect a PRO user holding at phase 2+, not just the free-tier phase-1 case.)
**Fix**: in the day-collection loop, `if (day['is_hold'] == true) continue;` before folding into `days` — excludes hold days from BOTH the numerator and denominator symmetrically, so a hold (a deliberate non-advancing repeat) simply doesn't count toward or against the advance gate. Minimal, symmetric, no denominator/numerator skew.
**Test**: extend the existing completion-rate contract test (locate it first) with a case seeding a mix of real + hold days — completion rate must match the real-days-only calculation. Fails today (reverting the `continue` folds hold days back in and shifts the ratio).

### (b) `PlanIntegrityReconciler` never heals a hold week — ⚠ CONFLICTS WITH A PRIOR EXPLICIT DECISION, flag for review
**Verified**: `plan_integrity_reconciler.dart:127-133` hardcodes `for (w = 1; w <= 4; w++) local.addAll(scheduleService.getWeek(w));` for its local pre-check, so a hold week (which lives beyond week 4 indefinitely, per `workout_schedule_read_service.dart:779-781`) is never inspected.
**BUT**: `docs/diagnoses/2026-07-21-free-tier-hold-mechanic-d7f3a9.md`'s own "Deliberately out of scope" section says widening this exact scan was considered and explicitly rejected: *"Widening the PlanIntegrityReconciler 1..4 scan to heal it is deliberately NOT done — that makes the reconciler fire more (the P0-11 concern the #1 re-anchor addresses; see closure finding D2)."* The P0-11 finding (`docs/plan-reviews/free-tier-hold-findings.md:58`) frames the reconciler as "both the bug and the proposed fix" — because its symptom-check triggers a `plan_end`/`plan_start` re-anchor write, widening the scan makes that write fire MORE often for hold users, which was the exact class of collapse (P0-1) the batch was built to fix. The `#1 PlanWindowReanchor` guard (now monotonic + phase-gated) mitigates but was explicitly NOT considered sufficient justification to widen the scan in that batch — the reviewers wanted the guard proven first, in isolation.
**⛔ REFUTED by round 1 (P0-B), re-verified by direct read. The recommendation below is FALSE.**
The claim "doesn't touch the re-anchor trigger condition at all, only the healing scan's read
range" is wrong: **the scan IS the trigger.** `plan_integrity_reconciler.dart:130-137` feeds the
1..4 scan straight into `if (!needsHeal(local)) return PlanReconcileOutcome.skipped('healthy');`
— and everything downstream, including the cloud fetch (`:145`) and the `PlanWindowReanchor`
re-anchor writes (`:167-176`), is reached ONLY when `needsHeal` fires. The source comment at
`:163-164` says so verbatim: *"Reached only when needsHeal fires — a healthy hold is a no-op
above."* Widening the scan strictly enlarges the set of boots reaching the re-anchor write. That
is P0-11 verbatim, not a different code path.

**And decisively, the widening buys NOTHING:** the heal loop at `:180-194` iterates **every**
`schedule_*` key in the cloud bundle with no week filter, so the reconciler **already heals hold
rows whenever it runs at all.** The 1..4 scan limits only *whether* it runs. So the proposed
change has zero new healing capability and its entire effect is "make the re-anchor fire more
often" — precisely and only what P0-11 objected to.

**Correct shape (round 1's prescription): split the trigger from the write.** Keep
`needsHeal(weeks 1-4)` as the sole gate for the re-anchor (`:167-176`) so its firing frequency is
provably unchanged and byte-identical for everyone, and add a *separate* hold-only symptom path
that reaches the merge loop while **skipping `:167-176` entirely**. That delivers the healing with
an unchanged re-anchor frequency.

Note FOB-7(b) **as filed is also half-wrong**: "never heals a hold week" → never *detects* one.
Also the plan's `:148-150` citation for "the re-anchor WRITE path" is stale d7f3a9-era numbering —
`:148-149` is `.eq('user_id', userId).limit(1)`; the re-anchor is at `:159-176`.

### Superseded recommendation (retained to show what round 1 rejected)
Propose a NARROW widening — extend only the **local, read-only symptom-check range** to also include the CURRENT active hold week's date range, while leaving the re-anchor WRITE path untouched.
**Test** (once approved): a hold week with a corrupted/missing-exercise row heals on next reconcile; a non-hold, non-widened scenario is byte-identical to current (regression guard that the re-anchor firing frequency is unchanged for non-holders).

### (c) `ai-media-proxy` size check / FC7 wrapper — ALREADY FIXED, no action needed
**Verified**: `supabase/functions/ai-media-proxy/index.ts:586-601` already has both the 10,000-char size check (`if (snapshotText.length > 10000) throw new HttpError(...)`) and the nonce-fenced untrusted-data wrapper (`fenceAsData`, matching `ai-proxy`'s own FC7 pattern). The surrounding comment documents this was a prior gap that has since been closed (cites CLAUDE.md §4.4 rule 18 and a prior B-pass finding). **FOB-7(c) as filed does not match current on-disk state — closing as already-remediated, not re-doing the work.**

### (d) `ai-proxy` size-envelope comment cites the wrong line
**Verified**: `ai-proxy/index.ts:827-834` comment says "snapshot_json ≤ 10 KB (input check at line 412)"; line 412 is actually the header for the unrelated "Vision abuse cap" block. The real check is at line 654.
**Fix**: one-line comment edit, `line 412` → `line 654`. No behavioral test needed (comment-only fix) — but per rule 21's spirit this is trivial enough that a `presence_only: true` note in whatever registry entry (if any) covers this comment suffices; more likely this doesn't touch a registered SoT concept at all and needs no registry entry.

---

## Cross-cutting

- **Blast radius**: `lib/core/services/**`, `lib/features/train/**`, `lib/features/home/**`, `lib/features/profile/**`, `lib/features/ai_coach/**`, `supabase/functions/**`, `supabase/migrations/**`, `telegram-bot/**` — run `scripts/blast_radius_from_diff.dart` on the real diff once implemented; expect `platform` given the EF + migration touches, matching the `enable_hold_weeks` build-tier precedent.
- **EF redeploys needed, each its own founder go**: `ai-proxy` (FOB-3), `weekly-recap-ready` (FOB-4), `weekly-report` (FOB-4).
- **Migration needed, its own founder go for apply**: `founder_metrics_engagement()` channel filter + new `hold_weeks_started_7d` column (FOB-5).
- **The flip-on commit itself** (flipping `enable_hold_weeks` to default ON) is a SEPARATE, later step after FOB-1,2,3,4,5,7 are closed and verified live — it needs its own full ×2 review + `bpass: accepted` per §4.12.4, clearing BOTH `ship_dark_pending_review.yaml` entries in one commit. Not attempted in the same commit(s) as the FOB fixes themselves.
- **FOB-6 split-out**: filed as its own new OI in `docs/audit/open_issues.md` (separate task), carrying forward the 6 named lifecycle traps verbatim so they aren't lost.

## Open questions — ANSWERED by round 1
1. **FOB-7(b) safety → NO, not safe.** See the ⛔ REFUTED block in FOB-7(b) above. Use the
   split-trigger shape.
2. **FOB-1 item 3 (video-share `weekNumber`) → NOT ANSWERABLE FROM THIS REPO.**
   `reports_screen.dart:1379` passes the value into
   `triggerWorkoutVideo(compositionId: 'WeeklyRecap', inputProps: …)` and there is **no in-repo
   consumer** — no Remotion template, no render Edge Function. The key crosses to an external
   renderer, so the null/sentinel contract must be confirmed out-of-band or the key omitted
   rather than a sentinel guessed. This is a genuine **blocked-on-external-contract** terminal
   state, not a deferral.
3. **FOB-5 event-name column → THERE IS NO SUCH COLUMN; the proposed filter is unsatisfiable.**
   `lib/core/services/app_events_service.dart:41-58` embeds the event string inside
   **`user_message`** as a `Map.toString()` truncated to 500 chars
   (`{'event': event, …}.toString()`), so a row reads `{event: hold_week_started}`.
   `where event_name = 'hold_week_started'` cannot be written. Options: a brittle
   `user_message like '{event: hold_week_started%'`, or add a real `event_name` column /
   dedicated table — materially bigger than this plan scoped.

## Additional round-1 findings not folded in above (P1/P2)

- **P1-D — FOB-5's migration CANNOT be `CREATE OR REPLACE`.** Adding `hold_weeks_started_7d`
  changes the `returns table (…)` signature (`101_admin_dashboard_metrics_functions.sql:65-72`),
  which Postgres rejects (`42P13`). It needs `DROP FUNCTION` + recreate, which **drops all
  grants** — so `:100-101`'s revoke/grant AND migration `103_admin_metrics_revoke_from_roles.sql`
  must be re-applied in the same migration. The plan's "safe `CREATE OR REPLACE`, same return
  type" is self-contradictory with its own item 2 and would fail on apply. (Also: the
  `ai_messages_today` subquery is at `:81-84`, not `:82-84`.)
- **P1-E — FOB-5 blast radius misses 3 consumers + 2 EFs.** `admin-dashboard-data/index.ts:198`
  and `compute-admin-metrics-daily/index.ts:134` both `.rpc("founder_metrics_engagement")`;
  `lib/features/admin/models/admin_dashboard_data.dart:105` parses the shape;
  `test/contracts/admin_metrics_functions_role_revoke_test.dart:43` pins its grants. So **five EF
  deploys are potentially in play, not three**, plus the daily-snapshot table (migration 102) may
  need its own column.
- **P1-F — FOB-3's mechanism does not exist at the call site.** `ai_snapshot_builder.dart:45` is a
  plain `class AiSnapshotBuilder {` with **no `Ref`** — `holdStatusProvider`
  (`train_provider.dart:866`) is unreachable from it. "sourced from `holdStatusProvider` … no new
  read path" is doubly wrong: unavailable, *and* it would force a second derivation of hold state
  outside the provider — the repo's #1 recurring bug class (writer/reader drift). Correct shape:
  extract a pure shared helper both the provider and the builder call, register it in
  `docs/sot_registry.yaml`, pin the agreement with a behavioral test.
- **P1-G — two new hold branches would ignore the kill-switch.** `holdStatusProvider:868` returns
  `HoldStatusData.empty` when the flag is OFF (that is *why* the display slices are byte-identical
  when OFF). But FOB-1 item 5 (`day_detail_sheet.dart:102`, `schedule?['is_hold']`) and FOB-7(a)
  (`if (day['is_hold'] == true) continue;`) branch on the **row field**, which persists in
  Hive/plan_json regardless of the flag — so flipping the flag back OFF would not restore prior
  behavior, and the plan's own per-item "flag OFF → byte-identical" test claim is unachievable at
  those two sites. Every new hold branch must gate on `PlanEngineFlags.holdWeeksEnabled` **in
  addition to** the row field.
- **P1-H — FOB-4 pins a known-broken value as its regression baseline.** Per
  `docs/plan-reviews/free-tier-hold-findings.md`, `user_progress.current_week` is documented as
  permanently `1` (every writer sets the literal), so today's push says "Week 1 debrief ready" to
  *everyone*. The plan's non-hold test ("unchanged current-week copy, byte-identical") would lock
  that bug in. Must state whether the non-hold path is fixed here or carries an explicit terminal
  state on the OI board — silently preserving it is a §4.2 deferral.
  ⚠ **PARTLY REFUTED — I verified this myself and round 1's source is STALE.** c9f4a2
  (2026-07-21) already fixed the frozen column and the fix IS live in code:
  `sync_profile.dart:284-291` calls
  `WorkoutScheduleReadService.instance.currentWeekColumnProjection(frozenWeek:, phase:, disabled:)`
  under the **default-ON** projection (`disable_program_week_projection` is the OFF-switch), and
  its own comment at `:276-279` names exactly the two EF symptoms the reviewer re-reported. The
  `free-tier-hold-findings.md` P1 the reviewer cited pre-dates that fix. **Residual that IS real:**
  the projection is forward-only — a user's column self-corrects on their *next* profile sync, so
  live rows can still read `1` for anyone who hasn't synced since 2026-07-21. So FOB-4's non-hold
  baseline is "whatever the projection wrote", not "permanently 1"; the test should assert against
  the projection's value, and the live-data residual is a query-to-confirm, not a code fix. This is
  the `feedback_audit_verifier_cannot_trust_own_subagent` class — an in-repo citation that was
  accurate when written and has since been superseded.
- **P2 corrections to my citations** (verdicts unaffected, evidence wrong): `getProgramWeek` is at
  `workout_schedule_read_service.dart:1075-1082`, and the "deliberately hold-blind" statement is at
  `:749-756` — `:829-831` (which I cited) is `holdWeeks()`'s doc comment. `train_provider.dart`
  `:1765`→1764, `:1782`→1783. `phase_roadmap_screen.dart:50-54`→`52-54`. `keep` set holds 19
  fields, not "~17".
- **P2 — FOB-7(a) is inert for the entire free phase-1 population.** `currentPhaseCompletionRate`
  sets `totalWeeks = 4` when `phase <= 1`, so hold rows (dated `plan_start+28`+) are never
  collected. The fix affects **only PRO holders at phase ≥ 2** — state that plainly rather than
  implying it protects free holders.
- **P2 — `channel = 'app'` silently over-narrows.** Real coach interactions also land on
  `in_app`, `promotion_ceremony`, `proactive_i_see_you`, `weekly_report`, `in_app_orphan`. The
  stated bug is only that `app_event` inflates, so `channel <> 'app_event'` matches the intent;
  `= 'app'` would additionally delete Telegram/proactive from the tile.
- **P2 — Deno test convention confirmed**: repo uses `*_test.ts`
  (`_shared/paged_fetch_test.ts`, `admin-dashboard-data/index_test.ts`) and CI runs
  `deno test … supabase/functions/` (`.github/workflows/test.yml:159`). Target
  `_shared/hold_status_test.ts`, not the guessed `index.test.ts`.
- **P2 — cross-feature import violation**: FOB-1 items 1-2 and FOB-3 pull `holdStatusProvider`
  from `features/train` into `home`/`profile`/`ai_coach`, against §4.4 rule 15. Promote the
  provider (or the pure helper from P1-F) to `core`/`shared`.

## Verified clean by round 1 (trust these; no work needed)

- **FOB-7(c)** — `ai-media-proxy/index.ts:586-601` genuinely has both the 10,000-char cap and
  `fenceAsData`. "Already remediated" is **correct**, nothing hiding behind the dismissal.
- **FOB-7(d)** — exact. `:833` claims "input check at line 412"; `:412` is the Vision abuse cap;
  the real check is `:654`.
- **FOB-1 "stale claim, drop from scope"** (`preview_workout_screen`) — correct, all four
  citations exact; hold chips route to `week_selector.dart:300 _showHoldWeekSheet`.
- **FOB-1 already-fixed** (`plan_header.dart:62-65`, `screen.dart:235-238`) — both really branch
  on `holdStatus.isHolding` and really drop the `WK n OF 4` segment.
- **FOB-2 / FOB-3 / FOB-4 current-state citations** — the clamp, the `onConflict` key,
  `HoldWeekInfo.weekStart`, the `as int?` cast, `:92-96`, `:1218-1221`, the `keep` set, and all
  four FOB-4 citations all verified exact.

## §4.12.1 split — this supersedes the single-batch framing above

Round 1 (not round 5) surfaced structural redesigns in 4 of 6 items. §4.12.1: *"When successive
reviews keep surfacing new material issues, that is the signal the unit is too large — split it
and ship the smallest converged piece, don't review the large thing a fifth time."* Applying that
now rather than after three more rounds. Proposed pieces, smallest-converged-first — each takes
its own ×2 review; **none of these is a deferral, they are separately-scoped units of one
already-open issue (OI-60), which stays OPEN until the flag flips**:

1. **Zero-work closures** — FOB-7(c) (already remediated) + FOB-7(d) (one-line comment). Record
   the verified terminal states; no behavioral change.
2. **FOB-2 streak** — one file (`train_provider.dart`), clear shape now that P0-A named the
   day-source problem. Self-contained, no EF, no migration.
3. **FOB-1 client display** — items 1, 2, 5 + the P1-G kill-switch gating + the P2-6 provider
   promotion. Item 3 (video-share) is **blocked-on-external-contract**; item 4 (telegram-bot) is
   a separate repo.
4. **FOB-7(a) + FOB-7(b)** — the `continue` exclusion (PRO phase≥2 only) plus the split-trigger
   reconciler redesign. Grouped because both touch hold-day filtering in read-path services, and
   7(b) is the highest-risk file in the batch.
5. **FOB-3 + FOB-4 server/AI** — the shared pure hold helper + SoT entry (P1-F), `captain_manual`
   copy, both weekly EFs, and the P1-H `current_week` baseline decision. 3 EF deploys, each its
   own §4.3 go.
6. **FOB-5 telemetry + metrics** — the DROP+recreate migration with grant re-application (P1-D),
   the `event_name` storage decision (P1-C), and up to 2 further EF deploys + the admin model +
   the grants contract test (P1-E).
7. **The flip itself** — `enable_hold_weeks` default ON. Own full ×2 + `bpass: accepted` per
   §4.12.4, clearing BOTH `ship_dark_pending_review.yaml` entries in one commit.

Plus, already split out by founder decision 2026-08-12: **FOB-6** (selectable past hold weeks,
6 lifecycle traps) as its own follow-on feature.
