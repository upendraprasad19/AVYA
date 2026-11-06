# Readiness Sensor + Deload Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flip `enable_readiness` and `enable_triggered_deload` from dark to live, with sleep measured automatically instead of self-reported.

**Architecture:** Both flags invert from opt-in `enable_*` keys to `disable_*` kill-switches (the `e6a8a8ae` precedent), each gaining a dev-panel writer. Sleep is read from the existing `sleep_log_<istDate>` Hive key — which already has a manual/coach writer — and a new Health Connect fetch populates it. A pure `sleepAxisFromHours` maps measured hours onto the existing 0/1/2 readiness axis, so the scoring formula is untouched.

**Tech Stack:** Flutter, Riverpod, Hive, `health: ^13.3.1` (Health Connect), Supabase.

**Spec:** `docs/superpowers/specs/2026-09-01-readiness-sensor-and-deload-engine-design.md`
**Revision:** 2 (post round-1)

## Global Constraints

- **Commits go through `sh scripts/safe_commit.sh "<message>"`** — never raw `git commit` (a PreToolUse hook blocks it). ONE positional arg; a flag becomes the message.
- **Work in the `readiness-flip` worktree**, never the shared main folder (§4.13).
- Commit type is **`feat:`** — no diagnose-doc (nothing is broken; a dormant feature is being activated).
- Sleep thresholds, founder-locked: `> 6.5h → 0`, `>= 4.5h && <= 6.5h → 1`, `< 4.5h → 2`. **Both boundary values fall in the middle band.**
- Auto-filled sleep row marker copy: **`◆ SYNCED`**. Fallback nudge copy: **"Sync your sleep for a sharper read."**
- Dart formatting: `AppTypography` styles only, never raw `GoogleFonts.getFont` (Gate 37).
- Run `flutter test <path>` for targeted runs. Do **not** run the full suite manually — pre-push and CI are the full-suite gates.

---

## ⚠⚠ CORRECTION 1 (round 1, BLOCKING) — `SLEEP_ASLEEP` is the WRONG data type

Revision 1 of this plan used `HealthDataType.SLEEP_ASLEEP`. **Verified against the plugin's
own Android source, that returns nothing for most users** and would have shipped the batch's
headline feature as a silent no-op.

`health-13.3.1/android/.../HealthDataReader.kt`, `handleSleepData`:

```kotlin
if (rec is SleepSessionRecord) {
    if (dataType == SLEEP_SESSION) {
        healthConnectData.addAll(dataConverter.convertRecord(rec, dataType))   // whole session
    } else {
        for (recStage in rec.stages) {                                          // stages only
            if (dataType == HealthConstants.mapSleepStageToType[recStage.stage]) { ... }
```

and `HealthConstants.kt`'s `mapSleepStageToType`: `2 → SLEEP_ASLEEP`, `4 → SLEEP_LIGHT`,
`5 → SLEEP_DEEP`, `6 → SLEEP_REM`.

So asking for `SLEEP_ASLEEP` matches ONLY stage-type 2 and yields **zero points** when:
- the session has **no stages** — manual Health Connect entries, Google Fit imports, basic
  trackers; `rec.stages` is empty and the loop never runs; or
- the tracker writes **granular** stages — Fitbit / Galaxy Watch / Oura emit light/deep/REM
  (4/5/6), none of which equal `SLEEP_ASLEEP`.

**Nothing in this repo could have caught it** — no `flutter test` reaches the plugin, so it
would have surfaced only as "State A never appears on my phone."

**Use `HealthDataType.SLEEP_SESSION`**, which `HealthDataConverter` turns into one interval per
session (`MINUTES.between(startTime, endTime)`) regardless of staging.

⚠ **Keep `_sleepPermissions` the same LENGTH as `_sleepTypes`** — `health_plugin.dart` throws
`ArgumentError` on a mismatch, so hardcoding `[HealthDataAccess.READ]` is a trap the moment a
second type is added. Derive it, mirroring `:32`.

## ⚠ Design correction to the spec — read before Task 2

The spec §3.1 says "add `HealthDataType.SLEEP_ASLEEP` to the type list at `health_sync_service.dart:28-29`". **Implemented literally, that breaks steps and weight sync for any user who denies sleep permission.**

`_checkPermissionsQuietly` (`:71-74`) calls `hasPermissions(_types)` and sets `_permissionsGranted = hasPerms == true`. `_syncToHiveLocked` (`:209-221`) aborts the ENTIRE sync when that is false. Adding sleep to `_types` therefore makes a sleep denial abort steps and weight too — a regression for existing users who never asked for sleep tracking.

**Task 2 keeps sleep on a SEPARATE permission track** so a denial degrades to "no sleep data" and nothing else. This satisfies the spec's own requirement that "sleep sync must fail soft — never block the steps/weight sync that works today."

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/core/utils/readiness.dart` | **Modify.** Gains the pure `sleepAxisFromHours`. Already holds `ReadinessCheckin` + `readinessLevelFor`; no Hive/Flutter imports — keep it that way. |
| `lib/core/services/health_sync_service.dart` | **Modify.** Separate sleep permission track + `fetchSleepHoursLastNight()` + a `sleep_log_` write that yields to a manual entry. |
| `lib/shared/repositories/plan_engine/plan_engine_flags.dart` | **Modify.** Two getters invert to kill-switches; three docstrings corrected. |
| `lib/features/dev/dev_panel_screen.dart` | **Modify.** Two toggles + two status rows — without these, neither kill-switch is reachable. |
| `lib/features/train/widgets/readiness_sheet.dart` | **Modify.** Two states (sleep known / unknown). |
| `lib/features/profile/screens/reports_screen.dart` | **Modify.** Remove the free-user paywall branch. |
| `test/contracts/readiness_sleep_axis_test.dart` | **Create.** Pure boundary tests. |
| `test/contracts/readiness_flag_no_hive_default_test.dart` | **Create.** No Hive init — covers the catch-block default. |
| `test/contracts/readiness_sheet_states_test.dart` | **Create.** State A vs B. |
| 5 existing test files | **Modify.** **7** breaking repoints + **6** vestigial deletions (round 1 moved one from the vestigial list to the break list). |

---

### Task 1: Pure sleep→axis mapping

**Files:**
- Modify: `lib/core/utils/readiness.dart`
- Test: `test/contracts/readiness_sleep_axis_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `int sleepAxisFromHours(double hours)` — returns 0, 1 or 2. Used by Tasks 2 and 6.

- [ ] **Step 1: Write the failing test**

Create `test/contracts/readiness_sleep_axis_test.dart`:

```dart
// Founder-locked sleep→axis thresholds (2026-09-01). Both boundary values
// fall in the MIDDLE band — that is the whole point of these tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/readiness.dart';

void main() {
  group('sleepAxisFromHours — founder-locked thresholds', () {
    test('above 6.5h → 0 (Solid)', () {
      expect(sleepAxisFromHours(8.0), 0);
      expect(sleepAxisFromHours(6.6), 0);
    });

    test('exactly 6.5h → 1 (Okay) — upper boundary is MIDDLE', () {
      expect(sleepAxisFromHours(6.5), 1);
    });

    test('between → 1 (Okay)', () {
      expect(sleepAxisFromHours(5.5), 1);
    });

    test('exactly 4.5h → 1 (Okay) — lower boundary is MIDDLE', () {
      expect(sleepAxisFromHours(4.5), 1);
    });

    test('below 4.5h → 2 (Rough)', () {
      expect(sleepAxisFromHours(4.4), 2);
      expect(sleepAxisFromHours(0.5), 2);
    });

    test('feeds readinessLevelFor unchanged — 3 worst axes → red', () {
      expect(
        readinessLevelFor(
            sleep: sleepAxisFromHours(3.0), soreness: 2, energy: 2),
        ReadinessLevel.red,
      );
    });

    test('good sleep prevents red even with 2 bad axes', () {
      expect(
        readinessLevelFor(
            sleep: sleepAxisFromHours(8.0), soreness: 2, energy: 2),
        ReadinessLevel.yellow,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/contracts/readiness_sleep_axis_test.dart`
Expected: FAIL — `sleepAxisFromHours` is not defined.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/core/utils/readiness.dart` (after `readinessLevelFor`):

```dart
/// Maps MEASURED sleep hours onto the readiness sleep axis (0 best → 2 worst),
/// so a Health-Connect reading feeds the same flag-count as a tapped answer.
///
/// Founder-locked 2026-09-01. Both boundary values belong to the MIDDLE band:
///   > 6.5      → 0 (Solid)
///   4.5 … 6.5  → 1 (Okay)   ← 6.5 and 4.5 both land here
///   < 4.5      → 2 (Rough)
///
/// Because this returns the same 0/1/2 an answer does, [readinessLevelFor]
/// needs no change at all.
int sleepAxisFromHours(double hours) {
  if (hours > 6.5) return 0;
  if (hours >= 4.5) return 1;
  return 2;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/contracts/readiness_sleep_axis_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(readiness): map measured sleep hours onto the 0/1/2 axis

Founder-locked thresholds; both boundaries fall in the middle band so
readinessLevelFor needs no change.

Test: test/contracts/readiness_sleep_axis_test.dart"
```

---

### Task 2: Pull sleep from Health Connect, fail-soft

**Files:**
- Modify: `lib/core/services/health_sync_service.dart`

**Interfaces:**
- Consumes: `sleepAxisFromHours` (not directly — this task only writes hours).
- Produces: `Future<double?> fetchSleepHoursLastNight()`; a `sleep_log_<istDate>` Hive row with `sleep_hours` (double), `source: 'health_connect'`. Task 6 reads it via the EXISTING `HealthReadService.sleepHoursForDate`.

⚠ Sleep permission is tracked SEPARATELY (see the design correction above). Do not add `SLEEP_ASLEEP` to `_types`.

- [ ] **Step 1: Add the separate sleep permission track**

In `lib/core/services/health_sync_service.dart`, immediately after the existing `_permissions` line (`:32`):

```dart
  /// ⚠ Sleep is tracked SEPARATELY from [_types] on purpose. Health Connect
  /// treats sleep as its own permission; folding it into [_types] would make
  /// `hasPermissions(_types)` false for anyone who denies sleep, and
  /// `_syncToHiveLocked` aborts the WHOLE sync on that — silently breaking
  /// steps + weight for existing users. Sleep must fail soft.
  /// ⚠ SLEEP_SESSION, never SLEEP_ASLEEP — the plugin returns the whole
  /// session only for SLEEP_SESSION; every other sleep type matches individual
  /// STAGES, so a stageless session (manual entry, Google Fit import) or a
  /// granular tracker (light/deep/REM) yields ZERO points.
  static const _sleepTypes = [HealthDataType.SLEEP_SESSION];
  // Derived, not hardcoded: the plugin throws ArgumentError when the
  // permissions list length differs from the types list length.
  static final _sleepPermissions =
      _sleepTypes.map((_) => HealthDataAccess.READ).toList();
  bool _sleepPermissionGranted = false;
```

- [ ] **Step 2: Add the fetch method**

Add after `fetchLatestWeight()` (mirrors its guard/telemetry shape exactly):

```dart
  /// Total asleep-hours for LAST NIGHT (18:00 yesterday → now), or null.
  ///
  /// Returns null on every failure path — no permission, no data, plugin
  /// error. A null here must never abort the steps/weight sync.
  /// Total slept hours for LAST NIGHT, or null.
  ///
  /// ⚠ NEVER requests permission — it only READS an already-granted one.
  /// Requesting here would fire a Health Connect dialog at cold launch with no
  /// user gesture, and re-fire every launch (the granted flag is in-memory on a
  /// singleton, so it resets each cold start); Android throttles repeated
  /// requests and then silently refuses, burning the grant. The ASK lives on a
  /// user action — see Task 7's tappable "Sync your sleep" nudge.
  Future<double?> fetchSleepHoursLastNight() async {
    if (kIsWeb) return null; // native-only, mirrors steps/weight
    if (_health == null) return null;
    try {
      if (!_sleepPermissionGranted) {
        final has = await _health!
            .hasPermissions(_sleepTypes, permissions: _sleepPermissions);
        _sleepPermissionGranted = has == true;
        if (!_sleepPermissionGranted) {
          debugPrint('[HealthSync] sleep permission absent — skipping (no prompt)');
          return null;
        }
      }
      // Window: 18:00 yesterday → now, clamped per-interval below so a session
      // starting before the window is not counted whole.
      final now = DateTime.now();
      final windowStart = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(hours: 6));
      final points = await _health!.getHealthDataFromTypes(
        startTime: windowStart,
        endTime: now,
        types: _sleepTypes,
      );
      if (points.isEmpty) return null;
      var minutes = 0.0;
      for (final p in points) {
        final from = p.dateFrom.isBefore(windowStart) ? windowStart : p.dateFrom;
        final to = p.dateTo.isAfter(now) ? now : p.dateTo;
        final m = to.difference(from).inMinutes;
        if (m > 0) minutes += m.toDouble();
      }
      if (minutes <= 0) return null;
      return minutes / 60.0;
    } catch (e, st) {
      debugPrint('[HealthSync] fetchSleepHoursLastNight error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_fetch_sleep'));
      return null;
    }
  }

  /// Requests the sleep permission. Call ONLY from an explicit user action.
  Future<bool> requestSleepPermission() async {
    if (kIsWeb) return false;
    try {
      _ensureConfigured();
      _sleepPermissionGranted = await _health!
          .requestAuthorization(_sleepTypes, permissions: _sleepPermissions);
      return _sleepPermissionGranted;
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'health_sync_request_sleep_permission'));
      return false;
    }
  }
```

- [ ] **Step 3: Write it into `sleep_log_` inside `_syncToHiveLocked`**

⚠ **Round 1 (M1): route the write through `HealthWriteService.logSleep`, NOT a raw
`healthBox.put`.** A raw put omits `duration_hrs`, and `sync_health.dart:291` pushes
`log['duration_hrs']` with **no fallback** to `sleep_hours` (its sibling at `:146-147` has
one). The column is nullable, so it would not 400 — it would write NULL and, via
`onConflict: 'user_id,date'`, **overwrite a good cloud row**. `_restoreSleepLogs` then writes
that back verbatim, so `sleepHoursForDate` returns null forever on a reinstall. Going through
the writer gets the lock, the `duration_hrs` alias and `syncSleepNow()` for free, and honours
rule 4 (repository pattern).

⚠ **Placement (M6): put this block ABOVE the steps/weight permission gate**, not at the end.
`_syncToHiveLocked` returns early when steps/weight permission is denied — appending sleep
after that means a steps denial silently kills sleep, which is the same coupling this task
exists to remove, just reversed.

Insert immediately after `final todayStr = istTodayStr();`:

```dart
    // ── Sleep ────────────────────────────────────────────────
    // Feeds the readiness check-in's SLEEP axis. Placed ABOVE the steps/weight
    // permission gate on purpose: the two tracks must not be able to disable
    // each other in EITHER direction.
    // A manual / AI-coach entry ALWAYS wins — same precedence as Weight below.
    final sleepHours = await fetchSleepHoursLastNight();
    if (sleepHours != null &&
        hive.healthBox.get('sleep_log_$todayStr') == null) {
      // Through the WriteService, not a raw put: it stamps `duration_hrs`
      // alongside `sleep_hours` (the cloud push reads duration_hrs with no
      // fallback), takes the per-day lock, and fires the cloud sync.
      await HealthWriteService.instance.logSleep(
        date: now,
        hours: sleepHours,
        quality: 'auto',
        source: WriteSource.healthConnect,
      );
      debugPrint('[HealthSync] synced sleep: ${sleepHours}h for $todayStr');
    }
```

⚠ Verify `WriteSource.healthConnect` exists before using it (`grep -n "enum WriteSource" -A8
lib/core/services/write_result.dart`). If it does not, use the nearest existing member rather
than inventing one, and say which in the commit.
⚠ Do **not** set `_lastSyncWroteData = true` here — that field is documented at `:21-22` as
"new **step/weight** data" and its consumers invalidate step/weight providers (m1).

- [ ] **Step 4: Verify it compiles and nothing regressed**

Run: `flutter analyze lib/core/services/health_sync_service.dart`
Expected: no new warnings (CI is zero-warnings).

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(health): pull sleep from Health Connect on a separate permission track

Sleep rides the existing sync but keeps its OWN permission check: folding
SLEEP_ASLEEP into _types would make hasPermissions() false for anyone who
denies sleep, and _syncToHiveLocked aborts the whole sync on that -- which
would silently break steps + weight for existing users.

Writes sleep_log_<istDate> only when no manual/coach entry exists, matching
the Weight block's precedence."
```

---

### Task 3: Flip `enable_readiness` → `disable_readiness`

**Files:**
- Modify: `lib/shared/repositories/plan_engine/plan_engine_flags.dart:179-192`
- Test: `test/contracts/readiness_flag_no_hive_default_test.dart` (create)

**Interfaces:**
- Produces: `PlanEngineFlags.readinessEnabled` now defaults **true**; kill-switch key is `disable_readiness`.

- [ ] **Step 1: Write the failing no-Hive test**

Create `test/contracts/readiness_flag_no_hive_default_test.dart`. ⚠ It must NOT init Hive — that is the whole point (it exercises the getter's `catch` branch):

```dart
// Covers the catch-block half of the flag getter — the half with NO other
// coverage, because every other readiness test opens a config box in setUp.
// Precedent for a no-Hive context in this suite:
// test/plan_generator/generator_matrix.dart:183-185.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  test('readinessEnabled defaults TRUE when Hive is unavailable', () {
    expect(PlanEngineFlags.readinessEnabled, isTrue);
  });

  test('triggeredDeloadEnabled defaults TRUE when Hive is unavailable', () {
    expect(PlanEngineFlags.triggeredDeloadEnabled, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/contracts/readiness_flag_no_hive_default_test.dart`
Expected: FAIL — both currently return `false` from their catch blocks.

- [ ] **Step 3: Invert the getter and fix its docstring**

Replace `plan_engine_flags.dart:179-192` (docstring + getter) with:

```dart
  /// ⑥ Batch 6 (W2.3) readiness check-in + session adjustment + PRO trends.
  /// LIVE since 2026-09-01 (OI-53 flag 1 of 12). Kill-switch
  /// `configBox['disable_readiness'] = true` reverts to the pre-flip path:
  /// no sheet, no `readiness_*` read/write, no session adjustment.
  /// ⚠ The kill-switch stops new collection; it does NOT retroactively hide
  /// readiness history already rendered by the Reports trend card.
  static bool get readinessEnabled {
    try {
      return HiveService.instance.configBox.get('disable_readiness') != true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }
```

- [ ] **Step 4: Run to verify the readiness half passes**

Run: `flutter test test/contracts/readiness_flag_no_hive_default_test.dart`
Expected: the readiness test PASSES; the deload test still FAILS (Task 4 fixes it).

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(readiness): flip enable_readiness ON as a disable_ kill-switch

Both halves invert -- key name and catch-block default -- matching the
enable_equipment_exclusions precedent (e6a8a8ae).

Test: test/contracts/readiness_flag_no_hive_default_test.dart"
```

---

### Task 4: Flip `enable_triggered_deload` → `disable_triggered_deload`

**Files:**
- Modify: `lib/shared/repositories/plan_engine/plan_engine_flags.dart` — the
  `triggeredDeloadEnabled` docstring + getter (**getter body starts at `:217`**; the docstring
  runs `:208-216`). Verified 2026-09-01.

**Interfaces:**
- Produces: `PlanEngineFlags.triggeredDeloadEnabled` defaults **true**; key `disable_triggered_deload`.

- [ ] **Step 1: Invert the getter and fix its docstring**

Replace the `triggeredDeloadEnabled` docstring + getter with:

```dart
  /// ⑥ Batch 7-B (W2.4) triggered deload — week 4's deload can be lifted to a
  /// working week at rollover when recovery evidence is good.
  /// LIVE since 2026-09-01 (OI-53 flag 2 of 12). Kill-switch
  /// `configBox['disable_triggered_deload'] = true`.
  ///
  /// ⚠ Flipped in the SAME commit as `disable_readiness`, and that coupling is
  /// mechanical, not convenience: `plan_generator.dart` gates
  /// `stashWorkingBase` on THIS flag, so a plan generated while it was OFF
  /// carries no stash and can never be lifted (`deload_evaluator.dart` guards
  /// on stash presence). The eval also early-returns without readiness.
  static bool get triggeredDeloadEnabled {
    try {
      return HiveService.instance.configBox.get('disable_triggered_deload') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → default: ON
    }
  }
```

- [ ] **Step 2: Run to verify both halves pass**

Run: `flutter test test/contracts/readiness_flag_no_hive_default_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 3: Commit**

```bash
sh scripts/safe_commit.sh "feat(deload): flip enable_triggered_deload ON as a disable_ kill-switch

Coupled to the readiness flip by code, not convenience: stashWorkingBase is
gated on this flag at generation time, so a plan generated with it OFF can
never be lifted.

Test: test/contracts/readiness_flag_no_hive_default_test.dart"
```

---

### Task 5: Dev-panel writers for both kill-switches

**Files:**
- Modify: `lib/features/dev/dev_panel_screen.dart`

⚠ Without this task **neither kill-switch is reachable in any build** — §4.6 requires the old path stay reachable when the gate is closed. The equipment precedent hit this identical gap; its fix records why at `:267-271`.

**Interfaces:**
- Consumes: `PlanEngineFlags.readinessEnabled`, `.triggeredDeloadEnabled` (Tasks 3-4).

- [ ] **Step 1: Add both toggle handlers**

Add after `_toggleEquipmentExclusions` (ends `:288`). ⚠ The toast copy deliberately differs from the equipment one — "regenerate a plan" is wrong for readiness:

```dart
  /// Readiness kill-switch. Deleting the key returns to the default (ON).
  Future<void> _toggleReadiness() async {
    final nextEnabled = !PlanEngineFlags.readinessEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_readiness');
    } else {
      await cfg.put('disable_readiness', true);
    }
    if (!mounted) return;
    setState(() {});
    _toast('readiness = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '— applies on your next Start Workout');
  }

  /// Triggered-deload kill-switch. ⚠ Turning this OFF also stops NEW plans
  /// stashing their working base, so a plan generated while it is off can
  /// never be lifted later.
  Future<void> _toggleTriggeredDeload() async {
    final nextEnabled = !PlanEngineFlags.triggeredDeloadEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_triggered_deload');
    } else {
      await cfg.put('disable_triggered_deload', true);
    }
    // Both existing toggles do this; for deload it is load-bearing —
    // runRolloverNow is what invokes DeloadEvaluator.maybeEvaluate(), so
    // without it the toggle has no observable effect until the next real
    // rollover (round 1, m7).
    await DayRolloverObserver.instance.runRolloverNow(ref);
    if (!mounted) return;
    setState(() {});
    _toast('triggered deload = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '— generate a new plan for the stash to apply');
  }
```

- [ ] **Step 2: Add the two status rows**

After the existing `_kv('equipment exclusions …')` row (`:369-370`):

```dart
              _kv('readiness',
                  PlanEngineFlags.readinessEnabled ? 'ON' : 'KILLED'),
              _kv('triggered deload',
                  PlanEngineFlags.triggeredDeloadEnabled ? 'ON' : 'KILLED'),
```

- [ ] **Step 3: Add the two buttons**

After the existing equipment-exclusions `_btn` (`:382-387`):

```dart
                  _btn(
                    PlanEngineFlags.readinessEnabled
                        ? 'KILL readiness'
                        : 'Restore readiness',
                    _toggleReadiness,
                  ),
                  _btn(
                    PlanEngineFlags.triggeredDeloadEnabled
                        ? 'KILL triggered deload'
                        : 'Restore triggered deload',
                    _toggleTriggeredDeload,
                  ),
```

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/features/dev/dev_panel_screen.dart`
Expected: no new warnings.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(dev): dev-panel writers for both new kill-switches

A gate nothing can close is not reachable (CLAUDE.md 4.6). Neither
disable_readiness nor disable_triggered_deload had a writer anywhere in the
app -- the same gap the equipment-exclusions flip hit and fixed."
```

---

### Task 6: Repoint the 6 breaking tests + delete the 7 vestigial writes

**Files:**
- Modify: `test/contracts/readiness_checkin_behavioral_test.dart`
- Modify: `test/contracts/plateau_escalation_behavioral_test.dart`
- Modify: `test/contracts/plateau_rotation_behavioral_test.dart`
- Modify: `test/contracts/deload_eval_behavioral_test.dart`
- Modify: `test/contracts/deload_working_base_stash_behavioral_test.dart`

⚠ These fail for a subtle reason: they write `enable_*` keys the getters no longer read, so the switch they think they are flipping is disconnected. Repoint them at the kill-switch — **never delete or loosen an assertion**; each is still a true statement about real behaviour.

- [ ] **Step 1: Confirm they fail first (the F1 discipline)**

Run:
```
flutter test test/contracts/readiness_checkin_behavioral_test.dart test/contracts/plateau_escalation_behavioral_test.dart test/contracts/plateau_rotation_behavioral_test.dart test/contracts/deload_eval_behavioral_test.dart test/contracts/deload_working_base_stash_behavioral_test.dart
```
Expected: **exactly 7 failures**, at `readiness_checkin:207`, `plateau_escalation:213`,
`plateau_rotation:324`, `deload_eval:287`, `deload_eval:296`, **`deload_eval:644`**,
`deload_working_base_stash:81`. If the count differs, STOP — the enumeration is wrong and the
spec must be corrected before continuing.

⚠ **`deload_eval:644` was found by round 1 and is a genuine 7th break — revision 1 of this
plan mis-filed it as a vestigial write to DELETE, which would have repaired nothing.** The
test at `:639-645` (`'reader gate: flag OFF → null even with a stamped key'`) writes
`enable_readiness` but **never** writes `enable_triggered_deload` — it relies on that flag's
default being OFF. Post-flip, `workout_schedule_read_service.dart:1111`
(`if (!triggeredDeloadEnabled) return null;`) stops firing, the stamped
`deload_reason_phase_2` key is returned, and `expect(..., isNull)` fails. It is the exact
shape of break #1, applied to the other flag.

- [ ] **Step 2: `readiness_checkin_behavioral_test.dart`**

1. Header `:3` — replace `Behind \`enable_readiness\` (default OFF, ship dark).` with `Behind \`disable_readiness\` (kill-switch; readiness is LIVE since 2026-09-01).`
2. Delete the `enableReadiness()` helper (`:154-155`) **and its three call sites** at `:182`, `:195`, `:202` — deleting the helper alone will not compile.
3. Rename those three tests from `flag ON + …` to `default (readiness ON) + …`.
4. In the test at `:207`, add as the FIRST line of the body:
```dart
      await HiveService.instance.configBox.put('disable_readiness', true);
```
and rename it to `kill-switch ON + Red stored → NO drop (byte-identical), no level`.

- [ ] **Step 3: `plateau_escalation_behavioral_test.dart` + `plateau_rotation_behavioral_test.dart`**

In each, delete the `enable_readiness` write in `setUp` (`:184` / `:155`), and replace the in-test write with the kill-switch:

```dart
      await cb.put('disable_readiness', true);
```
(`plateau_escalation:214`, `plateau_rotation:325`.)

- [ ] **Step 4: `deload_eval_behavioral_test.dart`**

Replace `enableFlags` (`:203-206`) — the conditional skip is what makes both branches rely on defaults:

```dart
  Future<void> enableFlags({bool deload = true, bool readiness = true}) async {
    // Both flags default ON since 2026-09-01, so "off" must now be written
    // as an explicit kill-switch — skipping the write no longer disables.
    if (deload) {
      await cb.delete('disable_triggered_deload');
    } else {
      await cb.put('disable_triggered_deload', true);
    }
    if (readiness) {
      await cb.delete('disable_readiness');
    } else {
      await cb.put('disable_readiness', true);
    }
  }
```
Then **repair break #6 at `:639-645`** — this is a BREAK, not a vestigial write. Replace the
`enable_readiness` line at `:643` with the kill-switch the test actually depends on:

```dart
      // The reader gate is triggeredDeloadEnabled — write it EXPLICITLY. Before
      // the 2026-09-01 flip this test relied on that flag's default being OFF.
      await cb.put('disable_triggered_deload', true);
```

- [ ] **Step 5: `deload_working_base_stash_behavioral_test.dart`**

Replace `setFlag` (`:61-68`):

```dart
  Future<void> setFlag(bool on) async {
    final cfg = Hive.box(HiveService.configBoxName);
    if (on) {
      await cfg.delete('disable_triggered_deload');
    } else {
      await cfg.put('disable_triggered_deload', true);
    }
  }
```
Update the header line `:8` from `Flag \`enable_triggered_deload\` (ship-dark DEFAULT OFF).` to `Kill-switch \`disable_triggered_deload\` (LIVE since 2026-09-01).`

- [ ] **Step 6: Run all five files green**

Run the same command as Step 1.
Expected: PASS, zero failures.

- [ ] **Step 7: Commit**

```bash
sh scripts/safe_commit.sh "test(readiness,deload): repoint 6 tests at the kill-switches, drop 7 vestigial writes

The 6 breaks fail for a subtle reason: they write enable_* keys the getters
no longer read, so the switch they think they are flipping is disconnected.
The 7 vestigial writes are the more dangerous half -- they stay GREEN while
testing nothing, including three tests literally named 'flag ON + ...'.

Assertions are repointed, never loosened."
```

---

### Task 7: The readiness sheet's two states

**Files:**
- Modify: `lib/features/train/widgets/readiness_sheet.dart`
- Test: `test/contracts/readiness_sheet_states_test.dart` (create)

**Interfaces:**
- Consumes: `sleepAxisFromHours` (Task 1), `HealthReadService.sleepHoursForDate` (existing, `health_read_service.dart:60`).
- Produces: the logged `readiness_<date>` row carries the mapped sleep axis in State A.

- [ ] **Step 1: Write the failing test**

Create `test/contracts/readiness_sheet_states_test.dart`.

⚠ **Round 1 (M3): revision 1's draft asserted only `sleepAxisFromHours`, which Task 1 already
covers — it never touched the sheet.** It must assert the OBSERVABLE EFFECT: which state the
sheet selects, and what lands in the logged row.
⚠ Read CLAUDE.md §4.9's GoogleFonts/`path_provider` row before choosing `testWidgets` — this
sheet renders `AppTypography` styles AND needs Hive open, which is that trap's exact recipe.
The round-trip below avoids it by testing the seam, not the pixels.

```dart
// State A (sleep known) vs State B (unknown), asserted through the OBSERVABLE
// effect: the resolved axis and the logged readiness_<date> row.
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';

void main() {
  // NOTE: the executing agent must mirror the Hive bootstrap used by
  // readiness_checkin_behavioral_test.dart's `setUpAll`/`setUp` (temp dir +
  // path_provider mock + HiveUserSession.openForUser + markInitializedForTests).
  // Copy it verbatim from that file rather than inventing one.

  group('readiness sheet state selection', () {
    test('State A: a sleep_log row resolves the axis with no tap', () async {
      final today = istDateStr(nowWall());
      await HealthWriteService.instance.logSleep(
        date: nowWall(), hours: 7.33, quality: 'auto',
        source: WriteSource.manual,
      );
      final hours = HealthReadService.instance.sleepHoursForDate(nowWall());
      expect(hours, isNotNull, reason: 'State A requires a readable sleep row');
      expect(sleepAxisFromHours(hours!), 0);

      await HealthWriteService.instance.logReadiness(
        date: nowWall(), sleep: sleepAxisFromHours(hours),
        soreness: 1, energy: 0, source: WriteSource.manual,
      );
      final row = HiveService.instance.healthBox.get('readiness_$today') as Map;
      expect(row['sleep'], 0, reason: 'the MEASURED axis must reach the row');
      expect(row['level'], 'green');
    });

    test('State B: no sleep_log → reader null → the sheet must ask', () {
      // A date with no sleep_log row.
      final past = nowWall().subtract(const Duration(days: 400));
      expect(HealthReadService.instance.sleepHoursForDate(past), isNull);
    });
  });
}
```

⚠ Drop any import this file does not use — `unused_import` is a WARNING and blocks pre-push
(round 1, M5).
- [ ] **Step 2: Run to verify it FAILS**

Run: `flutter test test/contracts/readiness_sheet_states_test.dart`
Expected: FAIL — the sheet does not yet resolve measured sleep. (If it passes, the test is not exercising the new behaviour; fix the test before the code.)

- [ ] **Step 3: Add the sleep resolution to the sheet state**

In `_ReadinessSheetState`, replace **line `:64` ONLY** (the `int _sleep, _soreness, _energy` declaration) with the block below. ⚠ Do NOT touch `:66-68` — `_sleepLabels`/`_soreLabels`/`_energyLabels` are still used by State B and by `:113`/`:120` (round 1, m5).

```dart
  // 0 = best, 1 = mid, 2 = worst. Default mid (a neutral starting point).
  int _sleep = 1, _soreness = 1, _energy = 1;

  /// Measured sleep for today, or null when we have none. Non-null puts the
  /// sheet in STATE A (sleep is shown, not asked).
  double? _measuredSleepHours;

  @override
  void initState() {
    super.initState();
    _measuredSleepHours =
        HealthReadService.instance.sleepHoursForDate(nowWall());
    if (_measuredSleepHours != null) {
      _sleep = sleepAxisFromHours(_measuredSleepHours!);
    }
  }

  // Reuse the existing label list rather than a second copy (round 1, m6 —
  // two copies is a drift seam).
  String get _sleepBandLabel => _sleepLabels[_sleep];

  String get _sleepHoursLabel {
    // Round 1 (m4): round to minutes FIRST, then divide, or h = 7.999 renders
    // as "7h 60m". A manual/AI logSleep can supply any double.
    final totalMins = (_measuredSleepHours! * 60).round();
    return '${totalMins ~/ 60}h ${totalMins % 60}m';
  }
```

⚠ **Do NOT add a `health_read_service` import** — `readiness_sheet.dart:9` already has it
(round 1, M4). `duplicate_import` is an analyzer WARNING, and `--no-fatal-infos` suppresses
infos, not warnings, so it would fail pre-push with git printing only
`error: failed to push some refs`.

- [ ] **Step 4: Render the two states**

Replace the `_Row(label: 'SLEEP', …)` block with:

```dart
            if (_measuredSleepHours != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SLEEP',
                      style: AppTypography.monoXs
                          .copyWith(color: AppColors.textDim, letterSpacing: 1.9)),
                  Text('◆ SYNCED',
                      style: AppTypography.monoXs
                          .copyWith(color: AppColors.ok, letterSpacing: 0.9)),
                ],
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.ok.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.ok.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_sleepHoursLabel,
                            style: AppTypography.h3
                                .copyWith(fontSize: 15, color: AppColors.ok)),
                        Text(_sleepBandLabel,
                            style: AppTypography.bodyS
                                .copyWith(color: AppColors.textDim)),
                      ],
                    ),
                    Text('Already synced\n— nothing to tap',
                        textAlign: TextAlign.right,
                        style: AppTypography.monoXs
                            .copyWith(color: AppColors.textDim, height: 1.35)),
                  ],
                ),
              ),
            ] else ...[
              _Row(
                label: 'SLEEP',
                options: _sleepLabels,
                selected: _sleep,
                onSelect: (i) => setState(() => _sleep = i),
              ),
              const SizedBox(height: 5),
              Text('Sync your sleep for a sharper read.',
                  style: AppTypography.monoXs
                      .copyWith(color: AppColors.textMute, height: 1.4)),
            ],
```

- [ ] **Step 5: Verify it compiles + the mapping tests still pass**

Run: `flutter analyze lib/features/train/widgets/readiness_sheet.dart`
Then: `flutter test test/contracts/readiness_sheet_states_test.dart test/contracts/readiness_sleep_axis_test.dart`
Expected: no new warnings; PASS.

- [ ] **Step 6: Commit**

```bash
sh scripts/safe_commit.sh "feat(readiness): two-state sheet -- sleep shown when known, asked when not

Reads sleep_log_<date> via the existing HealthReadService.sleepHoursForDate,
so a manual or AI-coach sleep entry auto-fills exactly like a Health Connect
one. Two taps when sleep is known, three when it is not.

Test: test/contracts/readiness_sheet_states_test.dart"
```

---

### Task 8: Readiness becomes free — remove the paywall branch

**Files:**
- Modify: `lib/features/profile/screens/reports_screen.dart:530-571`

- [ ] **Step 1: Remove the lock icon**

Delete the `if (!isPro) const Icon(Icons.lock_outline, …)` block from the Readiness card's title `Row` (`:534-536`).

- [ ] **Step 2: Make the trend unconditional**

Replace `if (isPro) ...[ … ] else GestureDetector( … showPaywallSheet … )` with the trend body alone — delete the `else` branch (`:561-571`) and the `if (isPro)` wrapper, keeping the `Wrap` strip and the summary line. **Remove the `isPro` local unconditionally** — `unused_local_variable` is a WARNING and WILL block pre-push (round 1, m8). Also delete its now-stale Rule-5 comment above it.

- [ ] **Step 3: Verify**

Run: `flutter analyze lib/features/profile/screens/reports_screen.dart`
Expected: no new warnings, and no unused-variable warning for `isPro`.

- [ ] **Step 4: Commit**

```bash
sh scripts/safe_commit.sh "feat(reports): readiness trends are free for all

Founder decision 2026-08-31. Removes the paywall branch outright rather than
gating it -- flipping an engine flag should not introduce a monetization
surface."
```

---

### Task 9: Correct every document this batch falsifies

**Files:** `docs/sot_registry.yaml`, `docs/ship_dark_pending_review.yaml`, `lib/shared/repositories/plan_engine/CLAUDE.md`, `lib/shared/repositories/plan_engine/volume_titration.dart`, `docs/plans/batch9-volume-titration.md`, `docs/audit/open_issues.md`, plus the docstrings listed below.

⚠ `plan_engine/CLAUDE.md` is **auto-loaded** for anyone working in that subtree — leaving it wrong hands the next flip author a false assurance.

- [ ] **Step 1: The four falsified titration invariants**

Each says titration is safe *because* readiness is dark. Correct all four to state that readiness rows now accumulate and `_recovered()` (`volume_titration.dart:112-132`) has no readiness gate — it is inert only because `volumeTitrationEnabled` (`:56`) is still OFF:
`plan_engine/CLAUDE.md:122` · `volume_titration.dart:14` · `sot_registry.yaml:8246` · `docs/plans/batch9-volume-titration.md:111-112` and `:237`.

⚠ Do **not** add a guard inside `_recovered()` — `plateau_scan` (`:81`,`:83`) and `deload_evaluator` (`:55-56`) gate at their entry points; a third style buried in a helper diverges from the pattern for an unreachable path.

- [ ] **Step 2: The ship-dark ledger**

`docs/ship_dark_pending_review.yaml`: set `flip_reviewed: true` on `enable_readiness` (`:215-227`) and `enable_triggered_deload` (`:237-246`), each with a `note:` naming branch `readiness-flip` and its discriminating test. **Keep both in `pending:`** — `resolved:` (`:471`) is empty and unused and the equipment precedent stayed in `pending:`. Leave `flip_commit: null` (a commit cannot record its own sha).
⚠ `:245` is `enable_triggered_deload`'s note and its dependency IS code-enforced — do not rewrite it as a warning. `enable_volume_titration` (`:256-262`) has **no `note:`**; ADD one recording that its readiness dependency is now live and unguarded.

- [ ] **Step 3: The SoT registry**

`docs/sot_registry.yaml:7854-7897` — update the kill-switch name/default. `reader_manifest_complete: true` (`:7876`) is FALSE; add all four missing readers: `reports_screen.dart:505`, `deload_evaluator.dart:169`, `plateau_scan.dart:195-210`, `volume_titration.dart:112-132`. Fix `:7867` (cites `exercise_card.dart:89`; the prefill is `:91`, and the path must be the FULL `lib/features/train/screens/active_workout/exercise_card.dart` — two files share that basename, round 1 m12), `:7875` ("both START buttons" — there are three), `:7886-7889` ("one multiplication" — there are three).

- [ ] **Step 4: Docstrings naming a retired key or falsified default**

`plan_engine_flags.dart:212-214`, `:378-380` · `deload_evaluator.dart:14` · `plateau_scan.dart:18` · `day_rollover_service.dart:174` · `plan_engine/CLAUDE.md:68`, `:215` · `sot_registry.yaml:7986`, `:8031`, `:8317`, `:8373`.
Also `readiness_sheet.dart:3-4` and `sot_registry.yaml:7875` say "the two START buttons" — there are three.
⚠ Do NOT rewrite `docs/plan-reviews/*` or `docs/reviews/*` — historical records.

- [ ] **Step 4b: The stale Reports docstring**

`reports_screen.dart:502-504` describes a "PRO readiness trend… Free users see a locked teaser
→ paywall". Task 8 makes that false. Correct it (round 1, m9).

- [ ] **Step 5: Dead import**

`lib/features/train/screens/train/screen.dart:32` imports `readiness_sheet.dart` and uses nothing from it. Remove it.

- [ ] **Step 6: The OI board**

`docs/audit/open_issues.md` OI-53: 12 → **10** remaining; record both flips and the founder's dated decision (the entry currently reads `Blocked on: FOUNDER`, unverifiable from the repo).

- [ ] **Step 7: Verify + commit**

Run: `flutter analyze` (scoped to the touched Dart files).
```bash
sh scripts/safe_commit.sh "docs(readiness,deload): correct every claim this flip falsifies

Four documents asserted titration is safe BECAUSE readiness is dark -- true
until this batch, false after it, and one of them is an auto-loaded nested
CLAUDE.md that would hand the next flip author a false assurance.

Also: SoT reader manifest was missing four readers while claiming complete."
```

---

### Task 10: Mutation-prove the protection (rule 21)

No code changes. Tests written by a fix's author inherit its blind spot; this is the only cheap way out.

- [ ] **Step 1: Mutation A — revert the readiness getter in place**

Change `plan_engine_flags.dart` `readinessEnabled` back to `get('enable_readiness') == true` / `catch → false`. Confirm it applied: `grep -c "disable_readiness" lib/shared/repositories/plan_engine/plan_engine_flags.dart` must DROP.
Run the five test files from Task 6 plus the two new ones.
**Expected:** the no-Hive test and the "default → engages" test REDDEN. ⚠ The 6 repointed tests stay GREEN — that is expected and is NOT protection (they write `disable_readiness`, the reverted getter reads `enable_readiness`, finds null, falls to the old `false`, and lands on OFF for an unrelated reason). Record this.

- [ ] **Step 2: Restore from backup, then Mutation B — flip the polarity**

Restore the file (from a file copy — ⚠ never `git checkout <file>`, it reverts uncommitted work). Then change `!= true` to `== true`.
Run the same files.
**Expected:** the repointed tests REDDEN — `readiness_checkin:207` now drops a set and asserts `'3'`. This is the mutation that proves they pin the kill-switch.

- [ ] **Step 3: Restore, then Mutation C — the catch-block half**

Change `catch (_) => true` back to `=> false`, keeping the new key.
Run `flutter test test/contracts/readiness_flag_no_hive_default_test.dart`.
**Expected:** REDDENS. If it does not, the test is not reaching the catch branch — report that rather than re-running until something breaks.

- [ ] **Step 4: Restore and confirm the tree is clean**

Restore the file, then assert it is byte-clean with `git diff --exit-code lib/shared/repositories/plan_engine/plan_engine_flags.dart` (round 1, m11 — a grep COUNT is unreliable here because Tasks 4 and 9 both add occurrences to this same file before Task 10 runs). Run the seven files once more — all green.

- [ ] **Step 5: Record the evidence in the final commit body**

There is no diagnose-doc for a `feat:`, so the mutation record lives in the commit body and is mirrored in the plan-review record (Task 11). State per run: what was mutated, whether the mutation applied, how many tests reddened.

---

### Task 11: Plan-review record + B-pass

⚠ **CI hard-fails the merge without the record** (`check_plan_review_record_exists.dart`); at ≥platform it also requires `bpass: accepted`.

- [ ] **Step 1: Run the FULL local gate loop before dispatching any review (§4.12.5)**

Run: `sh scripts/pre-commit.sh`
⚠ Run the loop, not a hand-picked subset — "which gates are relevant" is the judgement the loop exists to remove. Fix everything it reports BEFORE dispatching the B-pass; three prose rounds on this batch already lost budget to citation errors a gate catches for free.

- [ ] **Step 2: Self-initiate `/code-review` (B-pass)**

Blast-radius is `platform`, so this is mandatory and self-triggered — do not wait to be asked (§4.3).

- [ ] **Step 3: Write `docs/plan-reviews/readiness-flip.md`**

`---` frontmatter, line-anchored `^key:` fields (a bullet header yields null fields → CI hard-fail):

```yaml
---
branch: readiness-flip
date: 2026-09-01
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/<id>-review.md
hermes: not_required
---
```
No `tier: ship_dark_build` — §4.12.4 forbids it on a flip. The body MUST state the two-flag coupling openly (§1 of the spec) rather than presenting this as a single-flag flip.

- [ ] **Step 4: Append the §5.1 tuning entry**

A commit adding `docs/reviews/<x>-review.md` must also append a same-dated entry to `.claude/skills/code-review/SKILL.md`'s Tuning history, or `check_skill_tuning_history.dart` blocks the commit.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "docs(review): plan-review record + B-pass for the readiness/deload flip

review_rounds: 3, verdict converged, bpass accepted. Records the two-flag
coupling explicitly -- this is ONE review covering TWO flags, justified by a
code-enforced dependency, not flag-batching."
```

---

## Self-Review

**Spec coverage:** §3.1 sleep acquisition → Task 2 (with a documented correction). §3.2 mapping → Task 1. §3.3 two states → Task 7. §3.4 flag mechanics + dev-panel writers → Tasks 3, 4, 5. §3.5 paywall removal → Task 8. §4 behavioral surface → covered across 3, 4, 7, 8. §5.1 six breaks + §5.2 seven vestigial → Task 6. §5.3 new tests → Tasks 1, 3, 7. §6 mutations → Task 10. §7 non-code artifacts → Tasks 9, 11. §8.3 (fresh plan needed to observe the deload) is a device-test note, not a code task — carried to the handoff below. **No gaps.**

**Placeholder scan:** clean — every code step carries real code; no "TBD", no "similar to Task N", no "add error handling".

**Type consistency:** `sleepAxisFromHours(double) → int` is defined in Task 1 and consumed in Tasks 2 and 7 under that exact name. `fetchSleepHoursLastNight() → Future<double?>` defined in Task 2, used only there. `HealthReadService.sleepHoursForDate(DateTime) → double?` is pre-existing and used verbatim in Task 7. Kill-switch key strings `disable_readiness` / `disable_triggered_deload` are identical across Tasks 3–6, 10.

---

## ⚠ Device-test note (spec §8.3)

**The founder's current plan cannot demonstrate the deload.** It was generated with the flag OFF, so it carries no `working_sets` stash and `deload_evaluator` will keep the deload. Observing the lift requires a **freshly generated plan** (phase advance or regeneration) plus ≥3 readiness check-ins inside a 14-day window, on week 4. Plan the APK test accordingly, or nothing will happen and it will read as a bug.

---

## Round-1 disposition

Context-blind review of revision 1 → `not_converged`: 2 BLOCKING, 7 MAJOR, 12 MINOR.
**Both blockers were independently re-verified against source before acceptance** — B1 against
the plugin's own Kotlin (`HealthDataReader.handleSleepData` + `HealthConstants.mapSleepStageToType`),
B2 against `deload_eval_behavioral_test.dart:639-645` + `workout_schedule_read_service.dart:1111`.
All 21 findings ACCEPTED; none rejected.

| # | Sev | Finding | Landed |
|---|---|---|---|
| B1 | BLOCKING | `SLEEP_ASLEEP` matches sleep STAGES, not the session → returns nothing for stageless sessions and for granular trackers. The headline feature would be a silent no-op. | CORRECTION 1 + Task 2 (`SLEEP_SESSION`, derived permissions list) |
| B2 | BLOCKING | A **7th** breaking test (`deload_eval:644`) that rev 1 mis-filed as a vestigial write to DELETE — which repairs nothing and trips the plan's own stop-rule. | Task 6 Steps 1 + 4 |
| M1 | MAJOR | Raw `healthBox.put` omits `duration_hrs`; `sync_health.dart:291` pushes it with no fallback → NULL overwrites a good cloud row, and restore then yields null forever. | Task 2 Step 3 routes through `HealthWriteService.logSleep` |
| M2 | MAJOR | The deload kill-switch cannot revert a lift already applied — the week stays `working` and only the reason strip vanishes. | §Risks below |
| M3 | MAJOR | Task 7's test asserted only Task 1's function — it never touched the sheet, so the batch's largest UI change had no test and rule 21 was unmet. | Task 7 Step 1 rewritten as a round-trip |
| M4 | MAJOR | Duplicate import (`readiness_sheet.dart:9` already has it) — a WARNING, blocks pre-push. | Step removed |
| M5 | MAJOR | Three unused imports in the new test — WARNINGS, block pre-push. | Task 7 note |
| M6 | MAJOR | Fail-soft was one-directional: sleep no longer breaks steps, but a steps denial silently killed sleep. | Task 2 Step 3 hoists the block above the gate |
| M7 | MAJOR | `requestAuthorization` at cold launch = an unprompted dialog, re-fired every launch (flag is in-memory), which Android throttles then silently refuses. | Task 2 splits `requestSleepPermission()` for a user action |
| m1–m12 | MINOR | `_lastSyncWroteData` semantics · IST/`nowWall` mixing · interval clamping · "7h 60m" · `:64` ambiguity · label duplication · missing `runRolloverNow` · conditional `isPro` removal · stale Reports docstring · `:208-216` · grep-count vs `git diff` · ambiguous `exercise_card` path | All landed in Tasks 2, 5, 7, 8, 9, 10 |

## Ordering — why intermediate red is acceptable here

Tasks 3/4 land with the suite red and Task 6 repairs it. **This does not violate rule 20**, and
the plan should say so rather than leave a cold reader to flag it: rule 20 scopes to `main`;
`pre-commit.sh` runs no tests at all since ADR-0018; and pre-push evaluates the pushed range at
its tip. An intermediate red commit on `readiness-flip` therefore never meets a gate.

A safer order exists — Task 6 first, writing `disable_*` keys that are inert pre-flip, then 3/4
— and costs nothing. **Either order is acceptable; the executing agent may take Task 6 first.**
If the current order is kept, the plan-review record must note why intermediate red is fine.

## Risks carried into the plan-review record

- **M2 — the deload kill-switch is not a full revert.** Once `deload_evaluator` has rewritten
  week 4 to `week_character: 'working'` and stamped its idempotency flag, killing the switch
  leaves the user prescribed a hard week where the plan says deload; only the reason strip
  disappears (`workout_schedule_read_service.dart:1111`). The evaluator's own guard 6 documents
  this shape as a deliberate no-op. This is materially worse than the readiness-side residue
  the spec already names, and must be recorded as an accepted, named risk.
- **B1's class:** an external API's *name* was right and its *semantics* were wrong, and no
  in-repo test could see it. The on-device APK test must explicitly confirm State A appears —
  if sleep silently never resolves, everything still "works", just never in the 2-tap state.
