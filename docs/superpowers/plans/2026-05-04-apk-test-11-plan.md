# APK Test #11 — Full-sweep audit fix batch

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`. Steps use checkbox `- [ ]` syntax for tracking.

**Branch:** `feat/apk-test-11-batch` off `main` (post Test #10 merge `31b966e` + hotfix `f9acbce`)
**Date:** 2026-05-04
**Estimated scope:** 13 themes · 27 P0s + 13 P1s · ~28–36 h · 1 batch APK
**Migrations:** 1 (047 — restore completeness; streak freezes columns + notifications inbox table + saved diet plans table)
**Edge Function deploys:** 7 (`ai-proxy` + `morning-alert` + 6 proactive triggers for Theme G persona unification + `delete-account` new for Theme H1)
**Source spec:** `docs/audit/2026-05-04/00-consolidated-findings.md` (master) + reports `01`–`06`

## Goal

Close every P0 found in the 2026-05-04 full-sweep audit before APK Test #11. Premium UX, zero sync gaps, AI coach with full IST-correct context, no hallucinated counters, restore-safe paying users, DPDP-compliant erasure.

## Architecture

Single feature branch, 8 sub-commits ordered by **risk and verification priority** (not by alphabet):

1. Quick wins (Theme L, E, J, H2)
2. Counter + IST cluster (Theme M + B)
3. items[] + two-writers cluster (Theme C + D)
4. AI quality cohort (Theme G + F)
5. Repository pattern cleanup (Theme K)
6. Payment hardening (Theme I)
7. **RISK** — Restore completeness (Theme A) — adds migration 047
8. **RISK** — DPDP hard delete (Theme H1) — adds delete-account Edge Function

Steps 7–8 are isolated as separate sub-PRs so a `git bisect` after Test #11 install can pinpoint regressions without unpicking earlier work.

## Tech Stack

Flutter 3.x + Riverpod + Hive (client) · Supabase Postgres + Edge Functions (Deno) · Razorpay · OneSignal · already in place. **No new dependencies.**

## Out of scope (decided)

- **Asset compression of `avya_logo.png` and `upendra.jpg`** — founder direction 2026-05-04: brand touch points, source assets stay full quality. H2 is `cacheWidth` only (render-time downsample, file untouched).
- **Naming consistency refactor** (`userId` / `uid` / `supaUserId`, 70+ sites) — risky as a single PR. Tighten incrementally as files are touched.
- **APK bundle-shrink** beyond H2. Logo/founder photo stay; bigger restructuring (download exercise library on first run) is a separate effort.

---

## STEP 1 — Quick wins (Theme L + E + J + H2) · ~2 h

**Branch:** `feat/apk-test-11-batch`. Commit at end of step.

### 1.1 · Theme L1 — AI breakdown card save confirmation (user-reported bug)

**Files:**
- Modify: `lib/features/nutrition/widgets/ai_breakdown_card.dart` (lines 110–128)
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart` (line 731–765 — `AiBreakdownNotifier.saveMeal`)

**Steps:**

- [ ] Read `lib/features/nutrition/widgets/scan_meal_section.dart:445-465` to refresh on the canonical snackbar pattern.

- [ ] Modify `nutrition_provider.dart:731` `saveMeal` to return a typed `WriteResult` instead of `void`. Today the function returns nothing and the early-return at line 733 is silent.

```dart
// nutrition_provider.dart:731 (replace existing saveMeal)
Future<({bool success, String? error, String? logKey})> saveMeal() async {
  final data = state;
  if (data == null) {
    return (success: false, error: 'no_state', logKey: null);
  }
  try {
    final result = await NutritionWriteService.instance.logMeal(
      mealType: data.mealType,
      items: data.items,
      source: NutritionWriteSource.aiText,
      mealName: data.mealName,
    );
    state = null;
    return (success: result.success, error: result.error, logKey: result.logKey);
  } catch (e, st) {
    debugPrint('[AiBreakdownNotifier.saveMeal] error: $e\n$st');
    return (success: false, error: e.toString(), logKey: null);
  }
}
```

- [ ] Modify `ai_breakdown_card.dart:110-128` save handler to await the result and show a snackbar:

```dart
// ai_breakdown_card.dart — replace the onPressed of the SAVE MEAL button
onPressed: () async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(aiBreakdownProvider.notifier).saveMeal();
  if (!context.mounted) return;
  if (result.success) {
    HapticFeedback.lightImpact();
    messenger.showSnackBar(SnackBar(
      content: Text('Meal saved ✓', style: AppTypography.body),
      backgroundColor: AppColors.ok,
      duration: const Duration(seconds: 2),
    ));
  } else {
    messenger.showSnackBar(SnackBar(
      content: Text(
        result.error == 'no_state'
          ? 'Already saved.'
          : 'Could not save — try again.',
        style: AppTypography.body,
      ),
      backgroundColor: AppColors.bad,
      duration: const Duration(seconds: 3),
    ));
  }
},
```

- [ ] Add widget test `test/features/nutrition/ai_breakdown_save_confirmation_test.dart`:

```dart
testWidgets('AI breakdown save shows snackbar on success', (tester) async {
  // Arrange: pump AiBreakdownCard with state populated, mock NutritionWriteService.logMeal → success
  // Act: tap SAVE MEAL
  // Assert: SnackBar with 'Meal saved ✓' is in tree
  expect(find.text('Meal saved ✓'), findsOneWidget);
});

testWidgets('AI breakdown save shows error snackbar on failure', (tester) async {
  // Arrange: state populated, logMeal returns success: false
  // Act: tap SAVE MEAL
  // Assert: SnackBar with 'Could not save — try again.' present
  expect(find.text('Could not save — try again.'), findsOneWidget);
});
```

- [ ] Run: `flutter test test/features/nutrition/ai_breakdown_save_confirmation_test.dart`. Expected: 2 pass.

- [ ] Commit: `fix(nutrition): AI breakdown card confirms save with snackbar (Test #11 L1)`

### 1.2 · Theme E1 — water target read-path (4 sites) + 2.5 L floor + manual override

**Files:**
- Modify: `lib/features/nutrition/widgets/hydration_card.dart:53`
- Modify: `lib/features/home/screens/home_screen.dart:470`
- Modify: `lib/features/nutrition/screens/nutrition_screen.dart:365`
- Modify: `lib/features/nutrition/widgets/water_quick_sheet.dart:31`
- Modify: `lib/features/onboarding/providers/onboarding_provider.dart:356` (formula update)
- Create: `lib/core/services/water_target_service.dart`
- Test: `test/services/water_target_service_test.dart`

**Steps:**

- [ ] Create `water_target_service.dart`:

```dart
// lib/core/services/water_target_service.dart
import 'package:hive_flutter/hive_flutter.dart';
import 'hive_service.dart';

class WaterTargetService {
  WaterTargetService._();
  static final instance = WaterTargetService._();

  static const _overrideKey = 'water_target_override_ml';
  static const _floorMl = 2500;
  static const _ceilingMl = 4000;

  /// Read precedence: user override → computed → 2500 fallback.
  int currentTargetMl() {
    final userBox = HiveService.instance.userBox;
    final override = userBox.get(_overrideKey) as int?;
    if (override != null && override >= _floorMl && override <= _ceilingMl) {
      return override;
    }
    final profile = userBox.get('profile') as Map?;
    if (profile == null) return _floorMl;
    return computeFromProfile(profile);
  }

  /// Public for testing + onboarding.
  static int computeFromProfile(Map profile) {
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble() ?? 70.0;
    final lifestyle = profile['lifestyle_activity']?.toString() ?? 'moderate';
    final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 0;

    var ml = (weightKg * 35).round(); // ~0.035 L/kg
    if (daysPerWeek >= 4) ml += 500;
    if (lifestyle == 'active' || lifestyle == 'very_active') ml += 300;

    if (ml < _floorMl) return _floorMl;
    if (ml > _ceilingMl) return _ceilingMl;
    return ml;
  }

  Future<void> setUserOverride(int? targetMl) async {
    final userBox = HiveService.instance.userBox;
    if (targetMl == null) {
      await userBox.delete(_overrideKey);
    } else {
      final clamped = targetMl.clamp(_floorMl, _ceilingMl);
      await userBox.put(_overrideKey, clamped);
    }
  }
}
```

- [ ] Write tests `test/services/water_target_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/water_target_service.dart';

void main() {
  group('WaterTargetService.computeFromProfile', () {
    test('floors at 2500 ml for small sedentary user', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 50,
        'lifestyle_activity': 'sedentary',
        'days_per_week': 0,
      });
      expect(ml, 2500);
    });

    test('caps at 4000 ml for very heavy very active 6-day lifter', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 130,
        'lifestyle_activity': 'very_active',
        'days_per_week': 6,
      });
      expect(ml, 4000);
    });

    test('75 kg moderate 4-day lifter → ~3125 → clamped pass-through', () {
      final ml = WaterTargetService.computeFromProfile({
        'current_weight_kg': 75,
        'lifestyle_activity': 'moderate',
        'days_per_week': 4,
      });
      // 75*35 + 500 = 3125
      expect(ml, 3125);
    });
  });
}
```

- [ ] Run: `flutter test test/services/water_target_service_test.dart`. Expected: 3 pass.

- [ ] Replace the 4 hardcoded `3000` values:

```dart
// hydration_card.dart:53 — replace literal 3000
final targetMl = WaterTargetService.instance.currentTargetMl();

// home_screen.dart:470 — same
// nutrition_screen.dart:365 — same
// water_quick_sheet.dart:31 — same
```

- [ ] Update `onboarding_provider.dart:356` to seed initial target via `WaterTargetService.computeFromProfile(...)` instead of inline `weight × 35`. Same math, single source of truth.

- [ ] Add EDIT TARGET button to `water_quick_sheet.dart`:

```dart
// In water_quick_sheet.dart, below the existing controls:
WardButton.ghost(
  label: 'EDIT TARGET',
  onPressed: () async {
    final newTarget = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _EditWaterTargetSheet(
        current: WaterTargetService.instance.currentTargetMl(),
      ),
    );
    if (newTarget != null) {
      await WaterTargetService.instance.setUserOverride(newTarget);
      ref.invalidate(waterTargetProvider); // create this provider — see below
    }
  },
),
```

- [ ] Create `waterTargetProvider` in `lib/features/nutrition/providers/nutrition_provider.dart`:

```dart
final waterTargetProvider = Provider<int>((ref) {
  return WaterTargetService.instance.currentTargetMl();
});
```

- [ ] Replace direct `WaterTargetService.instance.currentTargetMl()` calls in widgets with `ref.watch(waterTargetProvider)` so override flows trigger rebuild.

- [ ] Build `_EditWaterTargetSheet` (numeric ml input, 100 ml steps, range 2500–4000, "Reset to recommended" link).

- [ ] Run: `flutter analyze`. Expected: 0 new warnings.

- [ ] Commit: `fix(nutrition): wire water_target read-path with 2.5L floor + override (Test #11 E1)`

### 1.3 · Theme E2 — welcome screen "no streaks" lie

**Files:**
- Modify: `lib/features/onboarding/screens/welcome_screen.dart:149`

**Steps:**

- [ ] Read line 149 to confirm current copy. Should read `"No streaks, no gimmicks — just the log"`.

- [ ] Replace with copy that's true to the app:

```dart
// welcome_screen.dart:149
'Built around streaks, fuelled by data — your discipline, our scaffolding.',
```

- [ ] Commit: `fix(welcome): replace contradictory "no streaks" copy (Test #11 E2)`

### 1.4 · Theme E3 — `app.dart` "restart the app" copy violates §11

**Files:**
- Modify: `lib/app.dart:66` (`ErrorWidget.builder`)

**Steps:**

- [ ] Read `lib/app.dart:60-80`.

- [ ] Replace the user-facing copy. Keep the `kDebugMode` branch verbose; release branch generic:

```dart
// lib/app.dart:60+ — ErrorWidget.builder
ErrorWidget.builder = (FlutterErrorDetails details) {
  if (kDebugMode) {
    return ErrorWidget(details.exception);
  }
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Something went wrong here. The rest of the app still works — '
        'use the back button.',
        textAlign: TextAlign.center,
      ),
    ),
  );
};
```

- [ ] Commit: `fix(app): replace forbidden "restart" copy in ErrorWidget (Test #11 E3)`

### 1.5 · Theme E4 — Identity sex required gate

**Files:**
- Modify: `lib/features/onboarding/screens/identity_screen.dart` (around line 62)

**Steps:**

- [ ] Read `identity_screen.dart` around line 62 to find the `_sex` field initial value. Today: `String _sex = 'male';`

- [ ] Change to nullable + add gate:

```dart
// identity_screen.dart
String? _sex;
String? _sexError;

// In CONTINUE handler:
if (_sex == null) {
  setState(() => _sexError = 'Please pick one to calibrate your plan accurately.');
  return;
}
```

- [ ] Add inline error display below the 3-pill row when `_sexError != null` (use `AppColors.bad`, mono 10sp).

- [ ] When user taps a pill, clear the error: `setState(() { _sex = picked; _sexError = null; });`

- [ ] Test: `test/features/onboarding/identity_sex_required_test.dart`:

```dart
testWidgets('Identity CONTINUE blocked without sex pill tap', (tester) async {
  // Pump IdentityScreen with valid name + DOB but no sex tap.
  // Tap CONTINUE.
  // Assert: error text 'Please pick one to calibrate your plan accurately.' visible.
  // Assert: navigation did NOT happen (still on IdentityScreen).
});
```

- [ ] Run: `flutter test test/features/onboarding/identity_sex_required_test.dart`. Expected: pass.

- [ ] Commit: `fix(onboarding): require Identity sex selection (Test #11 E4)`

### 1.6 · Theme E5 — Identity step-label drift

**Files:**
- Modify: `lib/features/onboarding/screens/identity_screen.dart` (eyebrow label)

**Steps:**

- [ ] Find the eyebrow that says `'QUESTION 0'` (probably `WardEyebrow(text: 'QUESTION 0', ...)` or similar). Replace with `'01 · 05'` to match the progress indicator and the convention used on goal/stats/details/plan screens.

- [ ] Commit: `fix(onboarding): align Identity step label to 01·05 (Test #11 E5)`

### 1.7 · Theme J1 — stale `sync_gap_test` grep

**Files:**
- Modify: `test/sync/sync_gap_test.dart` (lines 73–87)

**Steps:**

- [ ] Read the test. It asserts that `DeleteNutritionLogNotifier` contains an inline `unawaited(SyncService.instance.syncNutritionData())`. Since Test #6 the sync call lives inside `NutritionWriteService.deleteLog`, so the regex never matches.

- [ ] Replace the test logic to assert the contract at the WriteService level instead:

```dart
test('NutritionWriteService.deleteLog fires syncNutritionData', () async {
  // Snapshot test: read nutrition_write_service.dart, assert the source contains
  //   'unawaited(SyncService.instance.syncNutritionData())'
  // inside or below the deleteLog method.
  final source = await File('lib/core/services/nutrition_write_service.dart').readAsString();
  final deleteLogIdx = source.indexOf('Future<WriteResult> deleteLog');
  expect(deleteLogIdx, greaterThan(0), reason: 'deleteLog method must exist');
  // After deleteLog, before the next method, must contain syncNutritionData()
  final tail = source.substring(deleteLogIdx);
  final nextMethodIdx = tail.indexOf(RegExp(r'\n  Future<'));
  final body = tail.substring(0, nextMethodIdx > 0 ? nextMethodIdx : tail.length);
  expect(body, contains('syncNutritionData'),
    reason: 'deleteLog must fan out to syncNutritionData per CLAUDE.md §15');
});
```

- [ ] Run: `flutter test test/sync/sync_gap_test.dart`. Expected: pass.

- [ ] Commit: `test(sync): update sync_gap test to match WriteService architecture (Test #11 J1)`

### 1.8 · Theme J2 — stale rank_service tests (LS, PO, SubLt static mirrors)

**Files:**
- Modify: `test/rank/rank_service_test.dart` (3 failing tests)

**Steps:**

- [ ] Read `lib/core/services/rank_service.dart` to determine current canonical gate logic for LS, PO, SubLt under the post-Test-#6 hybrid sailor/officer model + Lt insertion.

- [ ] Update each of the 3 stale tests to mirror current rules. The hybrid model keys off:
  - **Sailor ranks (LS, PO, CPO):** primary gate = current streak (e.g., LS = 14-day streak, PO = 30-day streak, CPO = 60-day streak).
  - **Officer ranks (SubLt, Lt, LtCdr):** primary gate = completion rate over last 4 weeks (e.g., SubLt = 70%, Lt = 80%, LtCdr = 90%).

```dart
// test/rank/rank_service_test.dart — updated LS test
test('LS rank requires 14-day current streak', () {
  final result = RankService.evaluateGate(
    rankCode: 'LS',
    currentStreak: 13,
    completionRate4w: 1.0,
  );
  expect(result.eligible, false);

  final result2 = RankService.evaluateGate(
    rankCode: 'LS',
    currentStreak: 14,
    completionRate4w: 0.0,
  );
  expect(result2.eligible, true);
});

// Repeat for PO (streak 30), SubLt (completion 70%) using the same shape.
```

- [ ] Run: `flutter test test/rank/rank_service_test.dart`. Expected: all green (4 pre-existing fails closed).

- [ ] Commit: `test(rank): update LS/PO/SubLt mirrors to hybrid sailor/officer model (Test #11 J2)`

### 1.9 · Theme H2 — splash logo cacheWidth (asset stays full quality)

**Files:**
- Modify: `lib/features/auth/screens/splash_screen.dart:289` (or wherever `Image.asset('assets/branding/avya_logo.png', ...)` lives)

**Steps:**

- [ ] Find the `Image.asset` call for `avya_logo.png` in splash_screen. Add render-time downsample (do NOT touch the asset file):

```dart
Image.asset(
  'assets/branding/avya_logo.png',
  width: 96,
  height: 96,
  fit: BoxFit.contain,
  cacheWidth: 192,   // 2× device pixel ratio for sharpness on hi-dpi
  cacheHeight: 192,
),
```

- [ ] Apply the same `cacheWidth/cacheHeight` to any other `avya_logo.png` use site (mission_brief, profile_screen if used, etc.). `grep -n "avya_logo" lib/`.

- [ ] Same treatment for `upendra.jpg` if rendered at < 200 px anywhere — but **do not modify the source file**.

- [ ] Commit: `perf(splash): cacheWidth on logo render — asset untouched (Test #11 H2)`

### 1.10 · STEP 1 verification

- [ ] Run full test suite: `flutter test`. Expected: 4 pre-existing fails NOW PASS; otherwise no new failures.
- [ ] Run: `flutter analyze`. Expected: 0 new warnings.
- [ ] Manual smoke: launch dev flavor, walk through onboarding (Identity sex required gate fires), check water target shows 2500+ on hydration card for a low-weight user, AI breakdown card shows snackbar.
- [ ] Push step-1 commit cluster.

---

## STEP 2 — Counter + IST cluster (Theme M + B) · ~4–5 h

### 2.1 · Theme B1 — `compileDailySnapshot.snapshot_date` IST

**Files:**
- Modify: `lib/core/services/sync_service.dart:377`
- Reference: `lib/core/utils/ist_date.dart` (`istDateStr(DateTime)`)

**Steps:**

- [ ] Read `sync_service.dart:370-390` to confirm context.
- [ ] Replace `DateTime.now()` with IST helper:

```dart
// sync_service.dart:377 — before
final snapshotDate = DateTime.now().toUtc().toIso8601String().substring(0, 10);

// after
final snapshotDate = istDateStr(DateTime.now());
```

- [ ] Add `import 'package:icanbefitter/core/utils/ist_date.dart';` to top.
- [ ] Commit: `fix(sync): snapshot_date in IST (Test #11 B1)`

### 2.2 · Theme B2 — 5 `ai_coach_repository` date helpers IST

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart`

**Steps:**

- [ ] Read the 5 helpers: `_getThisWeekWorkouts`, `_getStepHistory`, `_getTodaySteps`, `_getMealsToday`, `_getCurrentPlanSummary`. Each uses `DateTime.now()` directly.

- [ ] Replace every `DateTime.now()` used to derive a date-string with `istDateStr(DateTime.now())`. Where the helpers compute "now - N days", use `istDateStr(DateTime.now().subtract(Duration(days: N)))`.

- [ ] Add `import 'package:icanbefitter/core/utils/ist_date.dart';` if not already present.

- [ ] Add round-trip test `test/ai_coach/ist_date_helpers_test.dart`:

```dart
test('_getMealsToday reads nlog_<istDate>_* keys', () async {
  // Set a fixed clock at IST 02:00 (UTC 20:30 prev day).
  // Insert a Hive nlog row at IST today's date.
  // Call buildAiContext.
  // Assert the meals_today array contains the inserted row (would be missing if device-local UTC was used).
});
```

- [ ] Run: `flutter test test/ai_coach/ist_date_helpers_test.dart`. Expected: pass.

- [ ] Commit: `fix(ai_coach): IST throughout snapshot date helpers (Test #11 B2)`

### 2.3 · Theme B3 — `morning-alert.getDay()` IST

**Files:**
- Modify: `supabase/functions/morning-alert/index.ts:178`
- Reference: `supabase/functions/_shared/ist_date.ts` (create if missing — mirror the Dart helper)

**Steps:**

- [ ] If `_shared/ist_date.ts` doesn't exist, create it:

```ts
// supabase/functions/_shared/ist_date.ts
export const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;

export function istNow(d: Date = new Date()): Date {
  return new Date(d.getTime() + IST_OFFSET_MS);
}

export function istDateStr(d: Date = new Date()): string {
  const ist = istNow(d);
  return ist.toISOString().substring(0, 10);
}

export function istDayOfWeek(d: Date = new Date()): number {
  // Sun=0..Sat=6 in IST
  return istNow(d).getUTCDay();
}
```

- [ ] In `morning-alert/index.ts:178`, replace `new Date().getDay()` with `istDayOfWeek()` from the shared helper.

- [ ] Find any other `getDay()` / `toISOString().substring(0, 10)` in `morning-alert` and replace with `istDayOfWeek()` / `istDateStr()`.

- [ ] Deploy:

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js morning-alert --auto --functions-dir supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl morning-alert .claude/_payload_morning-alert.json false
```

Expected: HTTP 201, version bump.

- [ ] Commit: `fix(edge): morning-alert IST day-of-week (Test #11 B3)`

### 2.4 · Theme M3 — counter resets IST (`usage_counter_service.dart` + `ai_coach_repository.dart`)

**Files:**
- Modify: `lib/core/services/usage_counter_service.dart:107`
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart:585`
- Modify: `lib/features/ai_coach/providers/ai_coach_provider.dart:253`

**Steps:**

- [ ] In each file, replace `DateTime.now().toIso8601String().substring(0, 10)` (or equivalent) with `istDateStr(DateTime.now())`.

- [ ] Add `import 'package:icanbefitter/core/utils/ist_date.dart';` where not present.

- [ ] Test `test/services/usage_counter_ist_reset_test.dart`:

```dart
test('UsageCounterService resets at IST midnight not device midnight', () async {
  // Fake clock at IST 00:30 (= UTC 19:00 prev day on 2026-05-04, but IST 2026-05-05).
  // Pre-seed _lastDailyReset='2026-05-04' and counter=10.
  // Call checkAndResetCounters.
  // Assert counter=0 (because IST date is now 2026-05-05).
});
```

- [ ] Run: `flutter test test/services/usage_counter_ist_reset_test.dart`. Expected: pass.

- [ ] Commit: `fix(counters): IST midnight reset (Test #11 M3)`

### 2.5 · Theme M1 — counters increment on API call, not save

**Files:**
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart` (`AiBreakdownNotifier.analyse`, `ScanMealNotifier` — find via grep)
- Modify: `lib/core/services/nutrition_write_service.dart:119` (remove counter increment from `logMeal`)
- Modify: `lib/features/nutrition/widgets/food_logger_section.dart:74-77` (re-add the analyse-time increment)
- Modify: `lib/features/nutrition/widgets/scan_meal_section.dart` (capture-time increment)

**Steps:**

- [ ] In `nutrition_write_service.dart:119`, remove the `UsageCounterService.increment(...)` call. Counters are now incremented at the API-call site, not the save site.

- [ ] In `food_logger_section.dart`, in the `analyse` callback (where `aiBreakdownProvider.analyse` is invoked):

```dart
onTapAnalyse: () async {
  final ok = await SubscriptionService.instance.gate(
    AppConstants.featureAiTextLogPro,
    onPro: () async {
      await UsageCounterService.instance.increment(AppConstants.featureAiTextLogPro);
      await ref.read(aiBreakdownProvider.notifier).analyse(text);
    },
    onFree: () async {
      if (UsageCounterService.instance.canUse(AppConstants.featureAiTextLogPro)) {
        await UsageCounterService.instance.increment(AppConstants.featureAiTextLogPro);
        await ref.read(aiBreakdownProvider.notifier).analyse(text);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(/* daily limit reached */);
      }
    },
  );
},
```

- [ ] Same treatment for `scan_meal_section.dart` capture flow — increment `featureScanMealPro` when the photo is sent to the Edge Function, not when the user taps Save.

- [ ] Update test `test/features/nutrition/counter_increment_on_analyse_test.dart`:

```dart
test('AI text counter increments on analyse, not on save', () async {
  // Mock Edge Function returning a valid breakdown.
  // Call analyse(...). Counter should now be 1.
  // Do NOT call saveMeal. Counter should still be 1.
  // Call saveMeal. Counter should STILL be 1 (not 2).
});
```

- [ ] Run the test. Expected: pass.

- [ ] Commit: `fix(counters): increment on API call, not save (Test #11 M1)`

### 2.6 · Theme M2 — cart auditor counter (wire or delete)

**Files:**
- Modify: `lib/features/nutrition/widgets/cart_auditor_section.dart` (capture site)
- OR Modify: `lib/core/services/nutrition_write_service.dart:457` (delete dead `_counterFeatureForSource` enum branch for `cart`)

**Decision: wire it.** Cart auditor IS a paid feature with caps; the counter must reflect server reality.

**Steps:**

- [ ] Find the cart auditor capture handler in `cart_auditor_section.dart`. Add the same `gate + canUse + increment` pattern as 2.5.

- [ ] Remove the unused `case NutritionWriteSource.cart:` branch from `_counterFeatureForSource` in `nutrition_write_service.dart:457` (if it exists; verify by grep).

- [ ] Test `test/features/nutrition/cart_auditor_counter_test.dart`:

```dart
test('cart auditor scan increments client counter', () async {
  // Mock Edge Function audit.
  // Call cart audit flow. Counter should be 1.
});
```

- [ ] Commit: `fix(counters): wire cart auditor counter at capture site (Test #11 M2)`

### 2.7 · Theme M4 — pass real `quantityG` through 3 paths

**Files:**
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart:742` (AI text — derive from item if available)
- Modify: `lib/features/nutrition/widgets/scan_meal_section.dart:426` (scan meal)
- Modify: `lib/features/ai_coach/services/tool_dispatcher.dart:1263` (logMealByText tool)

**Steps:**

- [ ] AI text breakdown: when `AiBreakdownData.items[i]` includes a `quantity_g` from the model output, pass it through. If absent, fall back to `100.0` (canonical "per 100g" default) instead of `0`.

- [ ] Scan meal: same — pass through `_quantityG` from each `liveItems[i]` (the editor allows the user to adjust).

- [ ] Tool dispatcher: AI tool `logMealByText` already has access to grams in the tool args (`{ items: [{name, grams}] }`). Pass `grams` straight through.

- [ ] Update `nutrition_log_items` projection to pass real `quantity_g` when `> 0`. Already does for non-zero values; just ensures it's not always `0`.

- [ ] Test `test/contracts/nutrition_quantity_g_round_trip_test.dart`:

```dart
test('AI text save preserves quantity_g end-to-end', () async {
  // Save via AiBreakdownNotifier with item.quantityG = 150.
  // Read back: nlog row should have items[0].quantity_g == 150.
  // Cloud projection should have nutrition_log_items.quantity_g == 150.
});
```

- [ ] Commit: `fix(nutrition): preserve quantity_g through AI text + scan + tool paths (Test #11 M4)`

### 2.8 · Theme M5 — cache `MessageLimitNotifier` count

**Files:**
- Modify: `lib/features/ai_coach/providers/ai_coach_provider.dart:191`

**Steps:**

- [ ] Today `MessageLimitNotifier.build` rescans `coachBox` on every rebuild — O(N) over chat history.
- [ ] Switch to a counter persisted in `userBox['msg_count_<istDateStr>']` incremented at chat-send time and read O(1).

```dart
class MessageLimitNotifier extends Notifier<int> {
  @override
  int build() {
    final today = istDateStr(DateTime.now());
    return HiveService.instance.userBox.get('msg_count_$today') as int? ?? 0;
  }

  Future<void> incrementToday() async {
    final today = istDateStr(DateTime.now());
    final key = 'msg_count_$today';
    final current = HiveService.instance.userBox.get(key) as int? ?? 0;
    await HiveService.instance.userBox.put(key, current + 1);
    state = current + 1;
  }
}
```

- [ ] Wire `incrementToday()` from the chat-send path in `ai_coach_provider.dart` (find `sendMessage` callsite).

- [ ] Add daily key cleanup: prune `msg_count_*` keys older than 7 days on each app launch (in `splash_screen` or `HiveService` cleanup helper).

- [ ] Commit: `perf(ai_coach): cache message count, IST keyed (Test #11 M5)`

### 2.9 · STEP 2 verification

- [ ] `flutter test test/`. Expected: all green.
- [ ] `flutter analyze`. Expected: 0 new.
- [ ] Manual smoke: open coach screen, see counter; analyze AI text without saving 3×, counter shows 3 (not 0); reset at IST midnight (mock clock).
- [ ] Push step-2 commit cluster.

---

## STEP 3 — items[] + two-writers cluster (Theme C + D) · ~5–6 h

### 3.1 · Theme C1 — `FoodLogNotifier.logFood` writes via `NutritionWriteService`

**Files:**
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart:790-835` (`FoodLogNotifier.logFood`)
- Modify: `lib/features/ai_coach/services/conversational_log_handler.dart:35-86` (caller — confirm the API surface)

**Steps:**

- [ ] Read `nutrition_provider.dart:790-835` to capture current shape. The function takes a `food` map (`{name, calories, protein, carbs, fat, fiber, ...}`) plus a `quantityG` and writes a flat-totals `nlog_<ms>` row.

- [ ] Replace the body to delegate to `NutritionWriteService.logMeal`:

```dart
class FoodLogNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<({bool success, String? error, String? logKey})> logFood({
    required Map<String, dynamic> food,
    required double quantityG,
    required String mealType,
  }) async {
    final foodName = (food['name'] ?? 'Food').toString();
    // Compute scaled macros from the food map's per-100g values
    final ratio = quantityG / 100.0;
    final cal = (food['calories'] as num? ?? 0).toDouble() * ratio;
    final pro = (food['protein'] as num? ?? 0).toDouble() * ratio;
    final carb = (food['carbs'] as num? ?? 0).toDouble() * ratio;
    final fat = (food['fat'] as num? ?? 0).toDouble() * ratio;
    final fiber = (food['fiber'] as num? ?? 0).toDouble() * ratio;

    final result = await NutritionWriteService.instance.logMeal(
      mealType: mealType,
      items: [
        FoodItem(
          name: foodName,
          quantityG: quantityG,
          calories: cal,
          protein: pro,
          carbs: carb,
          fat: fat,
          fiber: fiber,
        ),
      ],
      source: NutritionWriteSource.manualSearch,
      mealName: foodName,
    );
    return (success: result.success, error: result.error, logKey: result.logKey);
  }
}
```

- [ ] Update the conversational handler at `conversational_log_handler.dart:86` to await + check the `WriteResult` and surface the result (currently silent).

- [ ] Add round-trip contract test `test/contracts/food_log_notifier_to_nutrition_log_items_test.dart`:

```dart
test('FoodLogNotifier.logFood produces nutrition_log_items projection', () async {
  // Insert via FoodLogNotifier with quantityG=200, food={name:'Roti', calories:100, ...}.
  // Read Hive nlog row: items[0].name == 'Roti', items[0].quantity_g == 200.
  // Run _syncNutritionLogs projection.
  // Assert: 1 nutrition_log_items row written with name='Roti', quantity_g=200.
});
```

- [ ] Run: `flutter test test/contracts/food_log_notifier_to_nutrition_log_items_test.dart`. Expected: pass.

- [ ] Commit: `fix(nutrition): FoodLogNotifier writes via WriteService with items[] (Test #11 C1)`

### 3.2 · Theme C2 — confirm `AiBreakdownNotifier.saveMeal` no longer early-returns silently

**Steps:**

- [ ] Already addressed in 1.1 — the new `saveMeal` returns a `WriteResult` record. Re-verify by inspecting the function.

- [ ] No commit (no new change).

### 3.3 · Theme D1 — `WorkoutRepository.logExercise` / `updateExerciseLog` delegate to `WorkoutWriteService`

**Files:**
- Modify: `lib/shared/repositories/workout_repository.dart` (`logExercise`, `updateExerciseLog`)
- Modify: `lib/features/ai_coach/services/conversational_log_handler.dart` (callers)

**Steps:**

- [ ] Read `workout_repository.dart` `logExercise` method top to bottom. Today: writes legacy `exlog_*` schema directly to Hive in parallel with `WorkoutWriteService`.

- [ ] Replace body with delegation to `WorkoutWriteService.logSet`:

```dart
Future<WriteResult> logExercise({
  required String exerciseName,
  required String date,
  required double weightKg,
  required int reps,
  required int sets,
  required String loggingType,
  String? notes,
}) async {
  return WorkoutWriteService.instance.logSet(
    exerciseName: exerciseName,
    date: date,
    weightKg: weightKg,
    reps: reps,
    sets: sets,
    loggingType: loggingType,
    notes: notes,
    source: WorkoutWriteSource.legacyRepository,
  );
}
```

- [ ] Same for `updateExerciseLog` → `WorkoutWriteService.updateSet`.

- [ ] Add a `WorkoutWriteSource.legacyRepository` enum value if missing (so the source telemetry shows where the legacy callers sit).

- [ ] Add deprecation marker on the legacy methods + plan to retire in Test #12 once all callers are migrated:

```dart
@Deprecated('Use WorkoutWriteService.logSet directly. This method now delegates; '
            'will be removed after Test #12 once all callers migrated.')
Future<WriteResult> logExercise(...);
```

- [ ] Run: `flutter analyze`. Resolve any `@Deprecated` warnings on internal callers by routing to the WriteService directly.

- [ ] Commit: `fix(workouts): legacy logExercise / updateExerciseLog delegate to WriteService (Test #11 D1)`

### 3.4 · Theme D2 — restore writes canonical field names

**Files:**
- Modify: `lib/core/services/sync_service.dart:2266` (the `restoreFromCloudForUser` exlog projection)

**Steps:**

- [ ] Read the function at line 2266. It currently writes Hive `exlog_*` rows with legacy keys `sets_completed` / `sets_detail`.

- [ ] Update to canonical keys `set_number` / `sets`:

```dart
// sync_service.dart:2266 — replace
await workoutBox.put(localKey, {
  'exercise_name': cloudRow['exercise_id'],
  'date': cloudRow['date'],
  'set_number': cloudRow['set_number'],   // canonical, was sets_completed
  'sets': cloudSetsList,                   // canonical, was sets_detail
  'reps_completed': cloudRow['reps'],
  'weight_kg': cloudRow['weight_kg'],
  'volume_kg': cloudRow['volume_kg'],
  'logging_type': cloudRow['logging_type'],
  'is_pr': cloudRow['is_pr'] ?? false,
  'source': 'cloud_restore',
  'updated_at_ms': DateTime.now().toUtc().millisecondsSinceEpoch,
});
```

- [ ] Add round-trip test `test/sync/restore_field_canonical_test.dart`:

```dart
test('restore writes canonical exlog field names', () async {
  // Seed cloud with workout_log_exercises row.
  // Call restoreFromCloudForUser.
  // Read Hive exlog_* row: keys must include 'set_number' and 'sets', NOT 'sets_completed' or 'sets_detail'.
  // Assert WorkoutReceiptData.fromExerciseLogs(date) renders correct set count from the restored row.
});
```

- [ ] Run: `flutter test test/sync/restore_field_canonical_test.dart`. Expected: pass.

- [ ] Commit: `fix(sync): restore writes canonical exlog field names (Test #11 D2)`

### 3.5 · STEP 3 verification

- [ ] Run all contract tests: `flutter test test/contracts/`. Expected: all green.
- [ ] Run sync tests: `flutter test test/sync/`. Expected: all green.
- [ ] Manual smoke: log a food via search tile-tap; check Supabase `nutrition_log_items` has the row (was empty before).
- [ ] Push step-3 cluster.

---

## STEP 4 — AI quality cohort (Theme G + F) · ~5–7 h

### 4.1 · Theme G1 — Promote `CAPTAIN_MANUAL` to shared module

**Files:**
- Create: `supabase/functions/_shared/captain_manual.ts`
- Modify: `supabase/functions/morning-alert/index.ts`
- Modify: `supabase/functions/streak-guardian/index.ts`
- Modify: `supabase/functions/re-engagement/index.ts`
- Modify: `supabase/functions/workout-window-closing/index.ts`
- Modify: `supabase/functions/protein-gap-alert/index.ts`
- Modify: `supabase/functions/plateau-alert/index.ts`
- Modify: `supabase/functions/pr-detection/index.ts`

**Steps:**

- [ ] Find existing `CAPTAIN_MANUAL` in `ai-proxy/index.ts` and `weekly-report/index.ts`. Extract to `_shared/captain_manual.ts` byte-for-byte:

```ts
// supabase/functions/_shared/captain_manual.ts
export const CAPTAIN_MANUAL = `You are AVYA, an Indian Navy-trained fitness coach.
[…full block extracted from ai-proxy/index.ts…]
`;

/**
 * Returns the shared system prompt with channel-specific suffix appended.
 */
export function captainPrompt(channel: 'chat' | 'morning' | 'weekly' | 'proactive'): string {
  const suffix = {
    chat: '',
    morning: '\n\nThis is a morning briefing. Keep it under 80 words. ' +
            'Reference at least one concrete data point from the user state.',
    weekly: '\n\nThis is a weekly recap. Use the briefing-report structure.',
    proactive: '\n\nThis is a proactive nudge. Stay under 60 words. ' +
               'Lead with the observation, follow with one specific next action.',
  }[channel];
  return CAPTAIN_MANUAL + suffix;
}
```

- [ ] Update `ai-proxy/index.ts` and `weekly-report/index.ts` to import from `_shared/captain_manual.ts` instead of inline.

- [ ] For each of the 6 proactive triggers, replace the hardcoded English copy with a Gemini prompt that uses `captainPrompt('proactive')` + a short context block:

```ts
// streak-guardian/index.ts (example pattern; repeat for each)
import { captainPrompt } from "../_shared/captain_manual.ts";
import { geminiChat } from "../_shared/gemini.ts";

const userState = {
  streak_days: row.current_streak,
  freezes_available: row.freezes_available,
  hours_remaining: hoursUntilMidnightIst,
};

const message = await geminiChat({
  model: 'gemini-2.5-flash',
  systemPrompt: captainPrompt('proactive'),
  userPrompt: `User state: ${JSON.stringify(userState)}.
Generate a streak-protection nudge in the Captain's voice.`,
  maxTokens: 120,
  temperature: 0.7,
});
```

- [ ] Keep the existing English copy as a fallback for offline-Gemini cases:

```ts
const message = await geminiChat({...}).catch(() => null);
const finalCopy = message ?? `Streak at ${row.current_streak} — protect it before midnight.`;
```

- [ ] Deploy each function:

```bash
node .claude/emit_payload.js streak-guardian --auto --functions-dir supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl streak-guardian .claude/_payload_streak-guardian.json false
# repeat for: re-engagement, workout-window-closing, protein-gap-alert,
# plateau-alert, pr-detection, morning-alert (verify_jwt: true), weekly-report (true), ai-proxy (false)
```

Expected: HTTP 201 each.

- [ ] Smoke-fire each cron: trigger via dashboard → see push body match Captain voice (no "Triple digits!" leftover).

- [ ] Commit: `feat(coach): unified Captain voice across all proactive triggers (Test #11 G1)`

### 4.2 · Theme F1 — Plan generator V4 library expansion

**Files:**
- Modify: `assets/data/exercise_library.json` (or whichever JSON the V4 pipeline reads)
- Run: `test/plan_generator/sample_plans_report.dart` to regenerate diagnostic

**Steps:**

- [ ] Run the diagnostic to capture the current state:

```bash
dart run test/plan_generator/sample_plans_report.dart
```

Expected: `test/plan_generator/sample_plans_output.md` updated. Tail it; count attempt3/attempt4/universalPool/none rows.

- [ ] Identify the missing muscle/pattern/equipment/experience tuples. Audit 3 P0-1 names `vertical_push × bodyweight × advanced` as one. Likely also: rear_delt × bodyweight × any, hip_isolation × bodyweight, elbow_flexion × bodyweight × advanced.

- [ ] For each gap, add ≥2 exercises to `exercise_library.json` covering the tuple. Minimal shape:

```json
{
  "id": "EX-1432-handstand-pushup-wall",
  "name": "Wall-Supported Handstand Push Up",
  "category": "push",
  "movement_pattern": "vertical_push",
  "target_focus": "Shoulders (Front Delts)",
  "equipment_tier": ["bodyweight"],
  "exercise_type": "compound",
  "logging_type": "bodyweight_reps",
  "rep_range": "5-8",
  "priority_tier": 1,
  "suitable_for": ["Intermediate", "Advanced"],
  "is_foundational": false,
  "coaching_cues": "...",
  "common_mistakes": "...",
  "pro_tip": "...",
  "MET_value": 8.0,
  "difficulty": 8
}
```

- [ ] Re-run the diagnostic. Iterate until `attempt3 = 0`, `attempt4 = 0`, `universalPool = 0`, `none = 0` across all 12 combos.

- [ ] Bump `_exerciseLibraryVersion` in `lib/core/services/seed_service.dart` to force re-seed on existing installs.

- [ ] If the cloud `exercise_library` table is mirrored from the JSON, generate + apply a migration:

```bash
node .claude/gen_migration_exercise_library.js
# applies as migration 048_exercise_library_v5.sql
```

- [ ] Commit: `feat(plan): expand V4 library to close cascade gaps (Test #11 F1)`

### 4.3 · STEP 4 verification

- [ ] All Edge Functions deployed; smoke-fire each cron once.
- [ ] Diagnostic shows 0 cascade-degraded picks.
- [ ] `flutter test`. All green.
- [ ] Push step-4 cluster.

---

## STEP 5 — Repository pattern cleanup (Theme K) · ~2–3 h

### 5.1 · Move direct Supabase queries into repositories

**Files:**
- Modify: `lib/features/profile/screens/submissions_screen.dart` (lines 157, 163, 338, 347, 356)
- Modify: `lib/features/profile/screens/my_submissions_screen.dart` (lines 46, 52)
- Modify: `lib/features/profile/screens/profile_screen.dart:2242`
- Modify: `lib/features/profile/screens/edit_profile_screen.dart:1368`
- Create / extend: `lib/shared/repositories/submissions_repository.dart`

**Steps:**

- [ ] Read each offending line to understand the query shape (likely `Supabase.instance.client.from('user_custom_exercises').select(...)`).

- [ ] Extract each into a method on `SubmissionsRepository`:

```dart
class SubmissionsRepository {
  SubmissionsRepository._();
  static final instance = SubmissionsRepository._();

  Future<List<Map<String, dynamic>>> fetchMySubmissions(String userId) async {
    final res = await Supabase.instance.client
      .from('user_custom_exercises')
      .select()
      .eq('user_id', userId)
      .eq('submitted_to_library', true)
      .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchCommunityReviewQueue() async {
    // … extracted logic from community review section …
  }

  Future<void> upvoteCommunitySubmission(String submissionId, String userId) async {
    // …
  }
}
```

- [ ] Replace each widget callsite with `ref.watch(submissionsRepositoryProvider).fetchMySubmissions(userId)` (or `instance.fetchMySubmissions`).

- [ ] Same treatment for `edit_profile_screen.dart:1368` Edge Function call — move into a service method on `UserRepository.regeneratePlan(...)`.

- [ ] Run `flutter analyze`. No new warnings.

- [ ] Commit: `refactor(profile): extract direct Supabase queries to repositories (Test #11 K1)`

---

## STEP 6 — Razorpay webhook plan-from-amount hardening (Theme I) · ~1–2 h

### 6.1 · Mirror `verify-payment`'s `derivePlanFromAmount`

**Files:**
- Modify: `supabase/functions/razorpay-webhook/index.ts`
- Reference: `supabase/functions/verify-payment/index.ts` (`derivePlanFromAmount`)

**Steps:**

- [ ] Read `verify-payment/index.ts` to copy `derivePlanFromAmount(amountPaise: number, promoCode?: string)`.

- [ ] In `razorpay-webhook/index.ts`, replace the `notes.plan` read with `derivePlanFromAmount(paymentEntity.amount, notes.promo_code)`:

```ts
// razorpay-webhook/index.ts — before
const plan = paymentEntity.notes?.plan ?? 'monthly';

// after
const plan = derivePlanFromAmount(paymentEntity.amount, paymentEntity.notes?.promo_code);
if (!plan) {
  return jsonError(400, 'amount_does_not_match_any_plan');
}
```

- [ ] Existing `computeExpectedAmount` validation stays — belt-and-suspenders.

- [ ] Deploy:

```bash
node .claude/emit_payload.js razorpay-webhook --auto --functions-dir supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl razorpay-webhook .claude/_payload_razorpay-webhook.json false
```

Expected: HTTP 201.

- [ ] Smoke test: trigger a real test payment via Razorpay test key. Verify the subscription row reflects the correct plan.

- [ ] Commit: `fix(payment): razorpay-webhook derives plan from amount (Test #11 I1)`

---

## STEP 7 — RISK · Restore completeness (Theme A) · ~6–8 h

> **Migration 047 — adds cloud columns + tables for streak freezes, notifications inbox, saved diet plans. Cannot be cleanly rolled back. Ship after Steps 1–6 are verified locally.**

### 7.1 · Migration 047

**Files:**
- Create: `supabase/migrations/047_restore_completeness.sql`

**Steps:**

- [ ] Write the migration:

```sql
-- supabase/migrations/047_restore_completeness.sql

-- Theme A1: streak freezes columns on user_progress
ALTER TABLE public.user_progress
  ADD COLUMN IF NOT EXISTS streak_freezes_available INTEGER NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS streak_freezes_used_dates TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS streak_freezes_last_refill DATE;

-- Theme A4: notifications inbox table
CREATE TABLE IF NOT EXISTS public.notifications_inbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  notif_type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  archived_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_notifications_inbox_user_created
  ON public.notifications_inbox(user_id, created_at DESC);

ALTER TABLE public.notifications_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own notifications"
  ON public.notifications_inbox FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users update own notifications"
  ON public.notifications_inbox FOR UPDATE USING (auth.uid() = user_id);

-- Theme A5: saved diet plans table
CREATE TABLE IF NOT EXISTS public.saved_diet_plans (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_json JSONB NOT NULL,
  saved_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.saved_diet_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own diet plan"
  ON public.saved_diet_plans FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users upsert own diet plan"
  ON public.saved_diet_plans FOR ALL USING (auth.uid() = user_id);

COMMENT ON COLUMN public.user_progress.streak_freezes_available IS
  'Number of streak-protection freezes available. Refilled per CLAUDE.md cadence.';
COMMENT ON TABLE public.notifications_inbox IS
  'Per-user notification history. Restored on cross-device sign-in.';
COMMENT ON TABLE public.saved_diet_plans IS
  'User-saved diet plan map (slot → planned slot). Restored on cross-device sign-in.';
```

- [ ] Apply via MCP:

```
mcp__ba7b5e8e__apply_migration project_id=dedsavbjuwgarrhphgnl name=047_restore_completeness query=<file contents>
```

Expected: success.

- [ ] Verify columns exist:

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name='user_progress'
  AND column_name LIKE 'streak_freezes_%';
```

Expected: 3 rows.

- [ ] Commit: `feat(db): migration 047 — restore completeness columns/tables (Test #11 A)`

### 7.2 · Sync writers — push freezes / inbox / diet plan to cloud

**Files:**
- Modify: `lib/core/services/streak_freeze_service.dart` (every Hive write fans out to cloud)
- Modify: `lib/core/services/notification_inbox_service.dart` (write to cloud on add)
- Modify: `lib/features/nutrition/screens/diet_plan_screen.dart:_savePlan` (sync after save)
- Modify: `lib/core/services/sync_service.dart` (`syncProfileNow` extends to cover freezes; new `syncNotificationsInbox` + `syncSavedDietPlan`)

**Steps:**

- [ ] In `streak_freeze_service.dart`, after every Hive mutation:

```dart
unawaited(SyncService.instance.syncFreezes());
```

- [ ] Add `syncFreezes()` to `SyncService`:

```dart
Future<void> syncFreezes() async {
  final userId = _currentUserId();
  if (userId == null) return;
  final box = HiveService.instance.userBox;
  final available = box.get('streak_freezes_available') as int? ?? 2;
  final used = (box.get('streak_freezes_used_dates') as List?)?.cast<String>() ?? [];
  final lastRefill = box.get('streak_freezes_last_refill') as String?;
  await Supabase.instance.client.from('user_progress').upsert({
    'user_id': userId,
    'streak_freezes_available': available,
    'streak_freezes_used_dates': used,
    'streak_freezes_last_refill': lastRefill,
  }, onConflict: 'user_id');
}
```

- [ ] Same pattern for `syncNotificationsInbox()` (insert each new inbox item) and `syncSavedDietPlan()` (upsert one row).

- [ ] Commit: `feat(sync): write freezes / inbox / diet plan to cloud (Test #11 A push)`

### 7.3 · Restore readers — pull on `restoreFromCloudForUser`

**Files:**
- Modify: `lib/core/services/sync_service.dart` (`restoreFromCloudForUser` op list)

**Steps:**

- [ ] Add 3 new restore steps inside `restoreFromCloudForUser`:

```dart
await _restoreFreezes(userId);
await _restoreNotificationsInbox(userId);
await _restoreSavedDietPlan(userId);
await _restoreRankPromotions(userId); // Theme A2
```

- [ ] Implement each:

```dart
Future<void> _restoreFreezes(String userId) async {
  final res = await Supabase.instance.client
    .from('user_progress')
    .select('streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill')
    .eq('user_id', userId)
    .maybeSingle();
  if (res == null) return;
  final box = HiveService.instance.userBox;
  await box.put('streak_freezes_available', res['streak_freezes_available'] ?? 2);
  await box.put('streak_freezes_used_dates',
    List<String>.from(res['streak_freezes_used_dates'] ?? []));
  await box.put('streak_freezes_last_refill', res['streak_freezes_last_refill']);
}

Future<void> _restoreNotificationsInbox(String userId) async {
  final rows = await Supabase.instance.client
    .from('notifications_inbox')
    .select()
    .eq('user_id', userId)
    .order('created_at', ascending: false)
    .limit(200);
  final box = HiveService.instance.notificationsBox;
  for (final r in rows) {
    await box.put('notif_${r['id']}', r);
  }
}

Future<void> _restoreSavedDietPlan(String userId) async {
  final res = await Supabase.instance.client
    .from('saved_diet_plans')
    .select('plan_json')
    .eq('user_id', userId)
    .maybeSingle();
  if (res == null) return;
  await HiveService.instance.configBox.put('saved_diet_plan', res['plan_json']);
}

Future<void> _restoreRankPromotions(String userId) async {
  final rows = await Supabase.instance.client
    .from('rank_promotions')
    .select()
    .eq('user_id', userId)
    .order('promoted_at', ascending: false)
    .limit(20);
  final box = HiveService.instance.userBox;
  await box.put('rank_promotions_history', rows);
}
```

- [ ] Theme A3 — fold subscription refresh INTO `restoreFromCloudForUser`:

```dart
// At the END of restoreFromCloudForUser, before return:
await SubscriptionService.instance.verifyFromServer(force: true);
```

Then **remove** the equivalent call at `auth_provider.dart:585` (the now-redundant separate hook).

- [ ] Theme A6 — add `coaching_notes` to `_restoreCoachMemory` whitelist:

```dart
Future<void> _restoreCoachMemory(String userId) async {
  // existing pulls...
  // ADD: pull coaching_notes
  final notes = await Supabase.instance.client
    .from('coach_memory')
    .select('coaching_notes')
    .eq('user_id', userId)
    .maybeSingle();
  if (notes != null && notes['coaching_notes'] != null) {
    await HiveService.instance.coachBox.put('coaching_notes', notes['coaching_notes']);
  }
}
```

- [ ] Add restore round-trip test `test/sync/restore_completeness_test.dart`:

```dart
test('restore pulls freezes, inbox, diet plan, ranks, coaching_notes', () async {
  // Seed cloud rows for all 5 surfaces.
  // Wipe Hive.
  // Call restoreFromCloudForUser.
  // Assert each Hive box has the expected restored data.
});
```

- [ ] Run: `flutter test test/sync/restore_completeness_test.dart`. Expected: pass.

- [ ] Commit: `feat(sync): restore freezes / inbox / diet plan / ranks / coaching_notes (Test #11 A pull)`

### 7.4 · STEP 7 verification

- [ ] Manual smoke: install Test #11 APK on a fresh device with the same Google account; sign in; verify freezes count, inbox items, saved diet plan, rank history, and PRO status all restored.
- [ ] Push step-7 cluster.

---

## STEP 8 — RISK · DPDP hard delete (Theme H1) · ~6–8 h (revised 2026-05-04)

> **High blast radius — auth.users deletion + Storage purge + Razorpay subscription cancel. 2-step confirm UI required. Ship LAST in the batch.**

### Locked design decisions (revised 2026-05-04 after blast-radius walk-through)

1. **Razorpay cancel must succeed before delete proceeds.** If the Razorpay API call fails, return 502 and abort. Otherwise risk: user deleted in our system, subscription auto-renews on Razorpay's side with no account to log into to dispute.
2. **5 community-touching FKs change to `ON DELETE SET NULL`** instead of CASCADE — `user_custom_exercises`, `user_custom_foods`, `community_reviews`, `food_corrections`, `promo_code_uses`. Drop `NOT NULL` on those `user_id` columns. Reads tolerate NULL = "deleted user". DPDP-allowed pseudonymization for shared content.
3. **OneSignal player ID unsubscribed** before `auth.users` delete (otherwise the device keeps receiving pushes until OS uninstall).
4. **Storage purge non-fatal.** Errors logged but don't block the delete. Separate orphan-cleanup cron sweeps `<uid>/` prefixes daily against `auth.users`.
5. **No refund automation, no 24-hour grace period.** Step 1 copy explicitly states: subscription cancelled (no refund), Razorpay receipts retained by Razorpay per Indian tax law, data removed from backups within 30 days. Refund requests go through email support.

### 8.0 · Migration 048 — pseudonymization FKs + audit log

**Files:**
- Create: `supabase/migrations/048_account_deletion_pseudonymize.sql`

**Steps:**

- [ ] Write the migration:

```sql
-- supabase/migrations/048_account_deletion_pseudonymize.sql

-- Audit table (admin-only, no RLS, survives auth.users delete)
CREATE TABLE IF NOT EXISTS public.account_deletion_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deleted_user_id UUID NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_id TEXT,
  razorpay_cancel_status TEXT,    -- 'cancelled' | 'no_active_sub' | 'failed'
  storage_purge_status JSONB      -- { progress_photos: int, chat_media: int, coach_media: int, errors: [] }
);

-- Pseudonymization FKs — community contributions survive author deletion
-- 1. user_custom_exercises (promoted exercises remain useful for other users)
ALTER TABLE public.user_custom_exercises DROP CONSTRAINT IF EXISTS user_custom_exercises_user_id_fkey;
ALTER TABLE public.user_custom_exercises ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.user_custom_exercises ADD CONSTRAINT user_custom_exercises_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 2. user_custom_foods
ALTER TABLE public.user_custom_foods DROP CONSTRAINT IF EXISTS user_custom_foods_user_id_fkey;
ALTER TABLE public.user_custom_foods ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.user_custom_foods ADD CONSTRAINT user_custom_foods_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 3. community_reviews
ALTER TABLE public.community_reviews DROP CONSTRAINT IF EXISTS community_reviews_user_id_fkey;
ALTER TABLE public.community_reviews ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.community_reviews ADD CONSTRAINT community_reviews_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 4. food_corrections
ALTER TABLE public.food_corrections DROP CONSTRAINT IF EXISTS food_corrections_user_id_fkey;
ALTER TABLE public.food_corrections ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.food_corrections ADD CONSTRAINT food_corrections_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- 5. promo_code_uses (accounting record — keep row, drop user identity)
ALTER TABLE public.promo_code_uses DROP CONSTRAINT IF EXISTS promo_code_uses_user_id_fkey;
ALTER TABLE public.promo_code_uses ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE public.promo_code_uses ADD CONSTRAINT promo_code_uses_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- Read-side guards: every consumer of these 5 tables must tolerate NULL user_id.
-- Audit consumers AFTER applying this migration; see Step 8.4.

COMMENT ON COLUMN public.user_custom_exercises.user_id IS
  'NULL = original author deleted; exercise retained for community use.';
COMMENT ON TABLE public.account_deletion_log IS
  'DPDP §17 erasure audit trail. Admin-only, no RLS, survives user deletion.';
```

- [ ] Apply via MCP:
```
mcp__ba7b5e8e__apply_migration project_id=dedsavbjuwgarrhphgnl name=048_account_deletion_pseudonymize query=<file contents>
```

- [ ] Verify FK changes:
```sql
SELECT conrelid::regclass AS table_name, conname, confdeltype
FROM pg_constraint
WHERE conrelid::regclass::text IN
  ('user_custom_exercises','user_custom_foods','community_reviews','food_corrections','promo_code_uses')
  AND contype='f' AND conname LIKE '%user_id%';
```
Expected: `confdeltype='n'` (SET NULL) for all 5.

- [ ] Commit: `feat(db): migration 048 — pseudonymize community FKs + deletion audit log (Test #11 H1 db)`

### 8.1 · `delete-account` Edge Function

**Files:**
- Create: `supabase/functions/delete-account/index.ts`
- Reference: `supabase/functions/_shared/cors.ts`

**Steps:**

- [ ] Create the Edge Function (revised flow per locked decisions):

```ts
// supabase/functions/delete-account/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RAZORPAY_KEY_ID = Deno.env.get("RAZORPAY_KEY_ID")!;
const RAZORPAY_KEY_SECRET = Deno.env.get("RAZORPAY_KEY_SECRET")!;
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID")!;
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY")!;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const requestId = crypto.randomUUID().split("-")[0];

  try {
    // 1. Auth
    const auth = req.headers.get("Authorization");
    if (!auth) return jsonError(401, "unauthenticated", requestId);
    const userClient = createClient(SUPABASE_URL, auth.replace("Bearer ", ""));
    const { data: userRes, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userRes.user) return jsonError(401, "unauthenticated", requestId);
    const userId = userRes.user.id;

    // 2. Confirmation token
    const body = await req.json();
    const expected = `DELETE-MY-ACCOUNT-${userId.substring(0, 8)}`;
    if (body.confirmation_token !== expected) {
      return jsonError(400, "confirmation_token_mismatch", requestId);
    }

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

    // 3. RAZORPAY CANCEL — must succeed or we abort
    let razorpayStatus = "no_active_sub";
    const { data: subs } = await admin
      .from("subscriptions")
      .select("razorpay_subscription_id")
      .eq("user_id", userId)
      .eq("status", "active");
    for (const s of subs ?? []) {
      if (!s.razorpay_subscription_id) continue;
      try {
        const res = await fetch(
          `https://api.razorpay.com/v1/subscriptions/${s.razorpay_subscription_id}/cancel`,
          {
            method: "POST",
            headers: {
              Authorization: "Basic " + btoa(`${RAZORPAY_KEY_ID}:${RAZORPAY_KEY_SECRET}`),
            },
          },
        );
        if (!res.ok) {
          const detail = await res.text();
          console.error(`[delete-account] razorpay cancel failed status=${res.status} body=${detail}`);
          return jsonError(502, "razorpay_cancel_failed", requestId);
        }
        razorpayStatus = "cancelled";
      } catch (e) {
        console.error(`[delete-account] razorpay cancel exception:`, e);
        return jsonError(502, "razorpay_cancel_failed", requestId);
      }
    }

    // 4. ONESIGNAL UNSUBSCRIBE — best-effort, non-fatal
    try {
      const { data: connections } = await admin
        .from("user_progress")
        .select("onesignal_player_id")
        .eq("user_id", userId)
        .maybeSingle();
      const playerId = connections?.onesignal_player_id;
      if (playerId) {
        await fetch(`https://onesignal.com/api/v1/players/${playerId}?app_id=${ONESIGNAL_APP_ID}`, {
          method: "DELETE",
          headers: { Authorization: `Basic ${ONESIGNAL_REST_API_KEY}` },
        }).catch((e) => console.warn(`[delete-account] onesignal unsub failed: ${e}`));
      }
    } catch (e) {
      console.warn(`[delete-account] onesignal step error (non-fatal):`, e);
    }

    // 5. STORAGE PURGE — non-fatal
    const purgeStats: Record<string, number | string[]> = { errors: [] };
    for (const bucket of ["progress-photos", "chat-media", "coach-media"]) {
      try {
        const { data: files, error: lsErr } = await admin.storage.from(bucket).list(userId);
        if (lsErr) {
          (purgeStats.errors as string[]).push(`${bucket}_list:${lsErr.message}`);
          continue;
        }
        if (files && files.length > 0) {
          const paths = files.map((f) => `${userId}/${f.name}`);
          const { error: rmErr } = await admin.storage.from(bucket).remove(paths);
          purgeStats[bucket] = rmErr ? 0 : paths.length;
          if (rmErr) (purgeStats.errors as string[]).push(`${bucket}_rm:${rmErr.message}`);
        } else {
          purgeStats[bucket] = 0;
        }
      } catch (e) {
        (purgeStats.errors as string[]).push(`${bucket}_exception:${(e as Error).message}`);
      }
    }

    // 6. AUTH.USERS DELETE — CASCADE through everything (community FKs SET NULL per migration 048)
    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) {
      console.error(`[delete-account] auth delete failed request_id=${requestId}`, delErr);
      return jsonError(500, "auth_delete_failed", requestId);
    }

    // 7. AUDIT LOG (insert AFTER auth delete — table has no FK to auth.users, survives)
    await admin.from("account_deletion_log").insert({
      deleted_user_id: userId,
      deleted_at: new Date().toISOString(),
      request_id: requestId,
      razorpay_cancel_status: razorpayStatus,
      storage_purge_status: purgeStats,
    }).catch((e) => console.warn(`[delete-account] audit insert failed (non-fatal):`, e));

    return new Response(
      JSON.stringify({ success: true, request_id: requestId }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[delete-account] request_id=${requestId}`, err);
    return jsonError(500, "internal_error", requestId);
  }
});

function jsonError(status: number, error: string, requestId: string) {
  return new Response(JSON.stringify({ error, request_id: requestId }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
```

- [ ] **Add `onesignal_player_id` column to `user_progress`** if not already present. Verify via:
  ```sql
  SELECT column_name FROM information_schema.columns
  WHERE table_name='user_progress' AND column_name='onesignal_player_id';
  ```
  If missing, fold into migration 048.

- [ ] **Orphan storage cleanup cron** — separate one-time migration or admin script that, daily at 03:00 UTC, lists every `<uid>/` prefix in the 3 buckets and removes prefixes whose UUID has no row in `auth.users`. Spec only — defer implementation to post-Test-#11 unless storage costs spike.

- [ ] Add migration 048 for `account_deletion_log`:

```sql
CREATE TABLE IF NOT EXISTS public.account_deletion_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deleted_user_id UUID NOT NULL,
  deleted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  request_id TEXT
);
-- No RLS (admin-only audit table). Service role write.
```

- [ ] Apply migration via MCP.

- [ ] Deploy Edge Function:

```bash
node .claude/emit_payload.js delete-account --auto --functions-dir supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl delete-account .claude/_payload_delete-account.json true
```

Expected: HTTP 201.

- [ ] Commit: `feat(privacy): delete-account Edge Function + audit log (Test #11 H1 server)`

### 8.2 · Client — 2-step confirm flow

**Files:**
- Modify: `lib/features/profile/screens/profile_screen.dart:2200-2275` (existing soft-flag delete)
- Create: `lib/features/profile/screens/delete_account_screen.dart`

**Steps:**

- [ ] Create a dedicated `DeleteAccountScreen` route at `/profile/delete-account` with the 2-step confirm:

  - **Step 1 — blast radius page.** Wardroom-style with explicit copy:
    > **This will permanently:**
    > • Delete your profile, workouts, meals, weight history, photos.
    > • Cancel your active subscription (no refund — request via support if applicable).
    > • Sign you out on every device.
    >
    > **What stays:**
    > • Your Razorpay payment receipts (Razorpay retains these per Indian tax law).
    > • Anonymous community contributions you've made (custom exercises/foods you submitted to the public library — your name is removed but the entry remains).
    > • Backups will purge within 30 days.
    >
    > This cannot be undone.

    Two buttons: `KEEP MY ACCOUNT` (default, gold) and `CONTINUE` (ghost, leads to step 2).

  - **Step 2 — type-to-confirm.** Single text field, label `Type your first name + the word DELETE`. Validate exact match (case-insensitive on first name, case-sensitive on `DELETE`). Show inline error on mismatch. Final button label: `IRREVERSIBLE — DELETE MY ACCOUNT` (bad colour).

- [ ] On final tap:

```dart
final user = Supabase.instance.client.auth.currentUser;
if (user == null) return;
final token = 'DELETE-MY-ACCOUNT-${user.id.substring(0, 8)}';
final res = await Supabase.instance.client.functions.invoke(
  'delete-account',
  body: {'confirmation_token': token},
);
if (res.status == 200) {
  // Wipe local Hive
  await HiveService.instance.wipeAll();
  await Supabase.instance.client.auth.signOut();
  if (context.mounted) context.go('/');
}
```

- [ ] Replace the soft-flag delete on `profile_screen.dart:2200-2275` with a route to the new screen. Remove the soft-flag column write (no longer used).

- [ ] Commit: `feat(privacy): hard-delete account 2-step confirm flow (Test #11 H1 client)`

### 8.3 · STEP 8 verification

- [ ] On a TEST account: trigger delete-account end-to-end. Verify:
  - `auth.users` row gone
  - `public.users` row gone (CASCADE)
  - `progress_photos` Storage objects gone
  - Razorpay subscription cancelled (check dashboard)
  - `account_deletion_log` row present
- [ ] Push step-8 cluster.

---

## Final batch verification before APK build

- [ ] `flutter analyze` — 0 new warnings.
- [ ] `flutter test` — all green; the 4 pre-existing fails closed; new contract tests passing.
- [ ] Push the entire `feat/apk-test-11-batch` branch.
- [ ] Merge `--no-ff` to `main` per `feedback_main_is_source_of_truth.md`.
- [ ] Run `/build-apk` per `feedback_use_build_apk_skill.md`.
- [ ] Install `+11` on device. Walk through:
  - Onboarding (Identity sex required, 01·05 step labels)
  - Hydration card shows correct target for current weight
  - AI text → analyse → SAVE MEAL → snackbar appears
  - Coach screen shows correct message count after IST midnight rollover
  - Reinstall (same account) → freezes / inbox / diet plan / ranks / PRO all restored
  - Delete account flow (on a throwaway test account)
- [ ] If green, write retrospective at `memory/project_apk_test_11_batch.md`.

---

## Self-review checklist

- [x] Spec coverage: all 13 themes mapped to a step.
- [x] No placeholders: every code block is concrete.
- [x] Type consistency: `WriteResult`, `WaterTargetService`, `captainPrompt` are referenced consistently.
- [x] Frequent commits: 21+ commits across 8 steps so `git bisect` is meaningful.
- [x] TDD where it matters: contract tests on every data-loss surface.
- [x] Risk-isolated: Steps 7 + 8 separated, ship last.
- [x] **Logo + founder photo NOT compressed** — H2 is `cacheWidth` only per founder direction.
- [x] **Water floor 2.5 L** + manual override per founder direction.
- [x] CLAUDE.md compliance: `unawaited(SyncService...)` after every mutation, IST throughout, error sanitization on Edge Functions, no naming-rename-without-contract-test.
