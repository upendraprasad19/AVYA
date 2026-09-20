# APK Test #12 — observation batch (2026-05-06)

**Branch:** `feat/apk-test-12-batch` (to create)
**Source APK:** 11.1 (built 2026-05-05 from main `3a74097`)
**Observation source:** Founder install of APK 11.1 on 2026-05-05/06.

## Scope

Six themes from 8 founder observations. Theme F (proactive coach) deferred.

| Theme | Severity | Obs | Effort |
|---|---|---|---|
| **Critical** | P0 — paying user blocked | #8 PRO upgrade pills not unlocking | M |
| **A** | P0 — data integrity | #1 May 4 receipt shows wrong exercises | M-L |
| **B** | P1 — visual polish | #2 Today card: duplicate "Relaxed", height mismatch | S |
| **C** | P1 — chart correctness | #3 Weight graph y-axis loses decimals | S |
| **D** | P1 — workout flow | #4 Active-workout swap doesn't update logging_type | S |
| **E** | P2 — visual consistency | #5 + #6 Unify workout card format (chips win) | M |

Out of scope (deferred to a later batch):
- Theme F — AI coach proactiveness (weight trend / hydration / sleep gap nudges).

---

## Theme Critical: PRO upgrade pills don't unlock

### Symptom
User completed Razorpay payment → "PRO activated" toast appeared → pills (the ones gated by `gate(...)`) still show paywall. Persists across cold restart.

### Investigation findings (already done)
- `RazorpayService._handlePaymentSuccess` (line 216) does an **optimistic write** of `isPro=true` + computed end date via `SubscriptionService.writeSubscriptionState(...)` — which routes through `MigratedKey.write` (correct, lands in per-user `userBox`).
- Toast fires at line 233; provider invalidation fires at line 302 (`subscriptionInfoProvider`, `trialInfoProvider`, `messageLimitProvider`).
- Polling (lines 358-409) writes again on webhook confirmation, also via `MigratedKey`.
- **No raw `configBox.put('isPro' | 'expiresAt' | 'plan' | …)` left in the codebase** — Test #10.1 swept all writes correctly.

### Candidate root causes (ranked, need verification)
1. **`verifyFromServer` downgrades optimistic state when webhook lags.** `SubscriptionService.verifyFromServer` calls `verify-subscription` Edge Function. If the `subscriptions` row hasn't been inserted yet (Razorpay → webhook lag, sometimes 30–60s), the function returns `is_pro: false`, the client calls `_downgradeLocally()` → wipes the optimistic state. On cold restart, splash's `checkAndSync()` re-runs `verifyFromServer`, hits the same race if the user restarted within minutes, downgrades again.
2. **Direct `isPro()` callers don't reactively rebuild.** 30 files call `SubscriptionService.instance.isPro()` directly. Only 5 use `ref.watch(subscriptionInfoProvider).isPro`. Direct callers cache the value at first paint and don't rebuild after `subscriptionInfoProvider` invalidation.
3. **Cross-account guard race.** `isPro()` line 91 reads `_hive.userBox.get('profile')`. If the profile map's `id` field isn't yet populated (or is stale across a session swap), the guard could downgrade incorrectly.

### Fix plan

**Task C-1 — Payment grace window in `verifyFromServer`.**
Add a `paymentInFlightUntil` Hive key written by `_handlePaymentSuccess` and `_pollAndActivate` set to `now + 10 min`. In `verifyFromServer`, if `paymentInFlightUntil > now`, the "server says NOT pro" branch must NOT call `_downgradeLocally()` — instead, log + return current local `isPro()`. Allows the webhook → polling cascade to settle without the splash-time verify killing the optimistic state.

**Task C-2 — Migrate direct `isPro()` callsites to `subscriptionInfoProvider`.**
Sweep the 25 widget files that call `SubscriptionService.instance.isPro()` directly. For widgets:
- Replace with `ref.watch(subscriptionInfoProvider).isPro`.
- Where the file is a `StatelessWidget` w/o `WidgetRef`, convert to `ConsumerWidget`.
- Where the call is in a callback (onTap, onPressed), keep direct call — those don't need reactive rebuilds.
Service-layer callers (sync_service, razorpay_service, ai_coach_provider, profile_provider, tool_dispatcher, progress_photo_repository) keep direct `isPro()` calls — they aren't widgets.

**Task C-3 — Add observability.**
`verifyFromServer` should `debugPrint` what server returned (is_pro, plan, expires_at) AND what local action was taken (downgrade vs trust). User-side this won't surface, but next test cycle's logs will pinpoint the exact failure mode.

**Task C-4 — Surface "verifying payment" state in pills.**
When `paymentInFlightUntil > now` AND local `isPro()=true` AND no server confirmation yet, show a subtle "verifying" hint (e.g. ⟳ glyph) instead of regular PRO badge. Truthful state UI — user knows the payment is mid-confirm rather than wondering why a PRO badge appeared without server-side confirmation.

Implementation: extend `subscriptionInfoProvider` (in `profile_provider.dart`) to expose a third field `isVerifying` alongside `isPro`. Widgets that show pills/badges read both. Default styling: PRO pill stays gold, but adds a small ⟳ glyph (or similar non-distracting indicator) next to the label while verifying. Once webhook confirms (or grace window expires), `isVerifying` flips to false and provider invalidation triggers a re-render.

### Acceptance
- Upgrade → toast → all pills (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`, `scan_meal_pro`, `cart_auditor_pro`, `ai_text_log_pro`, `morning_alert_pro`, `prediction_monthly`, `weekly_ai_report`) instantly reflect PRO state without restart.
- Cold restart within 10 min of payment preserves PRO state even if webhook hasn't fired.
- After webhook fires, server-confirmed state replaces optimistic.

### Regression tests
- `test/subscription/payment_grace_window_test.dart` — verifyFromServer in grace window doesn't downgrade.
- `test/subscription/widget_subscription_watch_test.dart` — assert no widget file calls `SubscriptionService.instance.isPro()` directly without justification (regex test). Allowlist documented.

---

## Theme A: Receipt integrity (#1)

### Symptom
May 4 receipt for completed PUSH A shows 12 exercises mixing pull/legs/calisthenics. User did one workout. Some exercises in receipt overlap with May 5's PULL A, suggesting cross-day pollution OR cross-session aggregation.

### Investigation findings (already done)
- `WorkoutWriteService` writes IST-correct dates everywhere (line 615 `istDateStr` shifts to UTC+5:30 regardless of input). Index key + row's `date` field both IST-correct. ✓
- `WorkoutReceiptData.fromExerciseLogs(date)` (line 253) reads `formatDateKey(date)` → `lib/core/utils/date_utils.dart` line 9-11 — this helper is **NOT IST-aware**. It uses `date.year/month/day` directly. On a device whose locale ≠ IST, or where `date` is a UTC-stamped DateTime, the read key disagrees with the IST-stamped write key.
- `WorkoutReceiptData.fromExerciseLogs` aggregates ALL exlogs for a date — no scoping by `workout_log_id` or schedule entry. **A user with multiple workout sessions on one IST day gets them all merged.**
- Active-workout swap (`train_provider.swapExercise` line 980) is pure state replacement. If sets were checked on the OLD exercise before the swap, those sets get logged on `completeWorkout` and the OLD exercise's exlog persists. Both old + new exercise show on the receipt.

### Fix plan

**Task A-1 — Make `formatDateKey` IST-aware.**
Replace `lib/core/utils/date_utils.dart` `formatDateKey` body with `return istDateStr(date);` (import from `ist_date.dart`). All 14 callsites of `formatDateKey` then become IST-correct without per-callsite changes. Add a unit test: `formatDateKey(DateTime.utc(2026,5,4,20,0))` returns `'2026-05-05'` (UTC 20:00 = IST 01:30 next day).

**Task A-2 — Stamp `workout_log_id` on every exlog.**
Extend `WorkoutWriteService.logExercise` to accept an optional `workoutLogId` parameter (defaults to `wlogKey(date)`). Stamp it on the row. Update active workout's set-logging path to thread the workout_log_id through.

**Task A-3 — Scope receipt by workout_log_id when available.**
Extend `WorkoutReceiptData.fromExerciseLogs` to accept optional `workoutLogId`. When provided, filter exlogs by `row['workout_log_id'] == workoutLogId`. When absent, fall back to current "all logs on this date" behavior (legacy data).

**Task A-4 — Audit swap-with-checked-sets flow.**
At the active-workout swap site, before replacing the exercise:
- If any sets are checked on the old exercise → prompt user: "Log completed sets for [old name] before swapping?" with [Yes, log them] / [Discard them] options.
- If "Discard": clear `checkedSets` entries for that exercise index AND drop input values. No exlog write happens.
- If "Yes, log them": write exlog for old exercise immediately, then proceed with swap.

**Task A-5 — Receipt header shows session name + sequence.**
When a user has multiple sessions on a single IST date, the receipt for each session shows:
- Header: `<workout_name> · Session N` (e.g. "PUSH A · Session 1", "LEG DAY · Session 2") where N is the chronological order on that date.
- Session count derived from distinct `workout_log_id` values for that IST date.

When only one session exists, header stays clean (no "Session 1" suffix).

If schedule's `workout_name` is missing for a session (ad-hoc workout, no schedule entry), fall back to: most-frequent exercise category in that session's exlogs (e.g. "LEG-FOCUSED" if 70%+ of exercises are knee/hip-dominant), else generic "WORKOUT".

### Acceptance
- May 4 receipt shows ONLY exercises performed in the user's PUSH A session for May 4.
- A user who logs two separate workouts on May 4 sees two distinct receipts (each via own `workout_log_id`).
- Sets checked on a swapped-out exercise either get logged on user confirm OR get cleanly discarded — no orphan entries leaking into receipts.

### Regression tests
- `test/contracts/receipt_scoping_test.dart` — log 2 workouts same IST date, assert each receipt has correct exercise list.
- `test/contracts/format_date_key_ist_test.dart` — IST date discipline at the helper level.

---

## Theme B: Today card polish (#2)

### Tasks

**Task B-1 — Remove duplicate "Relaxed" tagline.**
In whichever widget renders the workout title row (likely `today_card.dart` or `home_screen._buildTodayRow`), drop the middle `· *Relaxed*` italic. Keep only the `PHASE 1 Relaxed` chip top-right.

**Task B-2 — Equalize card heights.**
Wrap the workout-card / macro-card row in `IntrinsicHeight`. Both children adopt the taller card's height.

### Acceptance
- "Relaxed" appears exactly once on the home Today area.
- Workout card and macro card have identical height regardless of content.

### Regression tests
- Widget golden-ish test: render `TodayCard` with sample workout, assert single "Relaxed" string in widget tree.

---

## Theme C: Weight graph y-axis (#3)

### Task

**Task W-1 — Dynamic tick decimal precision.**
In the y-axis tick formatter (likely `lib/features/profile/widgets/weight_trend_card.dart` or shared chart utility), compute decimals from data range:
```dart
final range = (maxY - minY).abs();
final decimals = range < 0.5 ? 2 : range < 2 ? 1 : 0;
final label = value.toStringAsFixed(decimals);
```

### Acceptance
- 77.0 / 77.5 / 78.0 series renders ticks like `78.0 / 77.5 / 77.0` — never duplicate values.
- 75 / 80 / 85 series still renders integer ticks (no unnecessary trailing zeros).

### Regression tests
- Unit test the tick formatter helper for 4 ranges: <0.5, 0.5-2, 2-50, >50.

---

## Theme D: Active-workout swap loses logging_type (#4)

### Task

**Task D-1 — Apply LoggingTypeResolver at active-workout swap.**
In `train_provider.swapExercise(exerciseIndex, newExercise)`, before assigning, resolve the correct logging_type via `LoggingTypeResolver.resolve(newExercise.toMap(), exerciseLibrary, customLibrary)`. If `newExercise.loggingType` is missing or wrong, replace with the resolved value.

Investigate where `ExerciseSwapSheet` constructs the `ExerciseData` it returns — if it passes the picker's row directly without normalizing logging_type, that's the upstream root cause and the resolver runs as a safety net.

### Acceptance
- Swap timed → weight+reps: slot UI switches to KG/REPS columns.
- Swap weight+reps → timed: slot UI switches to DURATION secs.
- Swap to any exercise: header label + UI columns + rest behavior all consistent.

### Regression tests
- `test/train/swap_logging_type_test.dart` — instantiate ActiveWorkoutNotifier, swap timed→weight, assert state.exercises[i].loggingType.

---

## Theme E: Unify workout card format (#5 + #6) — chips win

### Decision (locked)
Per-set chip format wins. Train expanded view migrates from single summary line (`4 sets · 33 reps · 110 kg`) to chip Wrap (`20 kg × 10 reps` × 3, with newline wrapping when needed).

### Task

**Task E-1 — Promote chip renderer to a shared widget.**
Extract the chip-rendering logic from `workout_receipt_card.dart` into a shared widget (e.g. `lib/shared/widgets/wardroom/ward_set_chips.dart` — fits the Wardroom primitive convention). Inputs: `loggingType`, `perSetBreakdown`. Output: `Wrap` of chips with consistent border (`1px AppColors.line2`), 6dp radius, 12sp DM Sans.

**Task E-2 — Replace single-line summary in Train expanded view with WardSetChips.**
Find the renderer (likely `lib/features/train/screens/train_screen.dart` expanded card section around the per-exercise listing). Swap `Text('4 sets · 33 reps · 110 kg')` for the new shared widget. Keep the trailing `4 sets` count label on the right.

**Task E-3 — Receipt continues using same shared widget.**
Refactor `WorkoutReceiptCard` to use `WardSetChips` instead of inline chip building. Visual parity required (no regression in receipt look).

### Acceptance
- Train expanded view + Receipt + any future surface all render exercise sets identically.
- Chips for `weight_reps`: `20 kg × 10 reps`.
- Chips for `bodyweight_reps`: `× 10 reps`.
- Chips for `weighted_bodyweight`: `+10 kg × 8 reps`.
- Chips for `timed`: `60 secs`.
- Chips for `cardio`: `15 secs · 2 km` or appropriate.

### Regression tests
- Widget snapshot test for `WardSetChips` covering all 5 logging types.

---

## Migration / deploy notes

- **No DB migrations.** All fixes are client-side or Edge Function logic.
- **No Edge Function deploys.** `verify-subscription` is read-only — payment grace window is client-side.
- **Hive shape changes:**
  - New optional key `paymentInFlightUntil` (timestamp string).
  - New optional `workout_log_id` field on `exlog_*` rows (existing rows untouched; receipt code falls back when absent).

## Acceptance — full batch

1. Pay for monthly → toast → all 9 PRO pills unlock without restart.
2. Cold restart within 5 min of payment → PRO state preserved.
3. Receipt for any completed workout shows ONLY that workout's exercises.
4. Today card: one "Relaxed", equal heights.
5. Weight chart: decimals when range < 2 kg.
6. Swap timed↔weight+reps in active workout: UI updates correctly.
7. Train + Receipt + future surfaces all render set chips identically.
8. Test suite still 1063+ pass / 0 fail.
9. APK builds clean from main.

## Out of scope — Theme F (deferred)

- Weight trend nudge (stagnation / drop / gain detection)
- Hydration gap proactive nudge
- Sleep gap proactive nudge

To be designed in a follow-up brainstorm.

## Execution order

1. Critical (PRO bug) — paying user blocked, ship first
2. Theme A (receipt integrity) — data correctness > polish
3. Theme D (swap logging_type) — small but data-correctness adjacent
4. Theme C (weight graph) — small
5. Theme B (today card polish) — small
6. Theme E (card unification) — last, largest visual reach

Each theme: implement → test → commit → next.
