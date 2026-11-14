# Mutation record - L2b Landing B (`coach-measurement-sheet-ui`)

Generated from the specs and logs of every run (the six original ones, the survivor re-runs and the re-run of the whole earlier set on the final tree); each mutant is a text edit applied to the file named, confirmed applied (`grep -c`) before the run, restored byte for byte in a `finally` (SHA-256 compared) and `git diff --stat` read after each run. `RED n` = n tests failed; `GREEN` = nothing failed. A mutant that was GREEN in an earlier run and RED in a later one was killed by a test added or strengthened in between (the history column). The full before and after text is given, so none of this depends on the scratch runner.

**183 mutants, 178 RED, 5 GREEN at their last run** (the GREEN ones are listed under *Survivors* with a reason).

## Survivors (last run GREEN)

| id | file | reason |
|---|---|---|
| W4-site-clause-dropped (expected equivalent) | `lib/core/services/health_write_service.dart` | Equivalent: `isValidBodyMeasurementCm(site, stored)` already returns false for a site with no spec (`spec != null &&` is its first clause), so the dropped clause refuses nothing the remaining one does not, with the same event. |
| Q10-stored-date-any-type | `lib/features/profile/providers/measurement_prompt_provider.dart` | Equivalent: a stored value that is not a String stringifies to text the strict `^\d{4}-\d{2}-\d{2}$` shape check of `parseIstKeyStrict` rejects (an int, or a `DateTime` that renders `2026-10-12 00:00:00.000`), so the prompt sees an absent stamp either way. The cast form `v as String?` is a different mutant (MUT-3) and is RED. |
| M24-save-short | `lib/features/profile/widgets/body_measurements_sheet.dart` | Equivalent for the 48 dp rule: Material's default `MaterialTapTargetSize.padded` wraps the button in a 48 dp input target and `lib/core/theme` sets no global `shrinkWrap` or `visualDensity`, so a shorter `minimumSize` does not change the size a widget test can measure (re-derived with BPB-B18). |
| Wt6-link-short | `lib/features/home/widgets/weight_log_sheet.dart` | Equivalent for the 44 dp rule, for the same reason as M24: the padded 48 dp target is at least 44 whatever `minimumSize` says. |
| U7-nonfinite-guard-dropped | `lib/core/utils/measurement_units.dart` | Equivalent: the FIRST guard (`!v.isFinite`) is covered by the second (`cm.isFinite ? cm : null`), since NaN and Infinity stay non-finite through both conversions. The second guard alone is NOT covered (finite `1e308` in inches overflows to Infinity): U7b is RED through the `'1e308'` row, and U7c (both dropped) is RED. |

## All mutants

### W1-empty-guard - RED 1

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 1; run 9 (re-run on the final tree, writer): RED 1
- note:  

before:
```dart
    if (sites.isEmpty) {
      return WriteResult.fail('logMeasurements: no sites');
    }

```
after:
```dart
(deleted)
```

### W2-raw-not-rounded - RED 2

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 2; run 9 (re-run on the final tree, writer): RED 2
- note:  

before:
```dart
      final stored = roundMeasurementToTenth(entry.value);
      if (!isBodyMeasurementSite(site) ||
```
after:
```dart
      final stored = entry.value;
      if (!isBodyMeasurementSite(site) ||
```

### W3-last-offender - RED 1

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 1; run 9 (re-run on the final tree, writer): RED 1
- note:  

before:
```dart
rejected ??= measurementRejectionMessage('writer', site, stored);
```
after:
```dart
rejected = measurementRejectionMessage('writer', site, stored);
```

### W4-site-clause-dropped (expected equivalent) - GREEN

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): GREEN; run 9 (re-run on the final tree, writer): GREEN
- note:  

before:
```dart
      if (!isBodyMeasurementSite(site) ||
          !isValidBodyMeasurementCm(site, stored)) {
```
after:
```dart
      if (!isValidBodyMeasurementCm(site, stored)) {
```

### W5-no-event - RED 6

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 6; run 9 (re-run on the final tree, writer): RED 6
- note:  

before:
```dart
        unawaited(ErrorTelemetry.logEvent('measurement_value_rejected',
            message: rejected));
      }
      return WriteResult.fail(
          'logMeasurements: unknown site or value out of range');
```
after:
```dart
      }
      return WriteResult.fail(
          'logMeasurements: unknown site or value out of range');
```

### W6-valid-ignored (partial write) - RED 4

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 3; run 9 (re-run on the final tree, writer): RED 4
- note:  

before:
```dart
    if (!valid) {
      if (rejected != null) {
```
after:
```dart
    if (!valid && rounded.isEmpty) {
      if (rejected != null) {
```

### W7-wrong-catch-reason - RED 1

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 1; run 9 (re-run on the final tree, writer): RED 1
- note:  

before:
```dart
reason: 'health_write_service_log_measurements'
```
after:
```dart
reason: 'health_write_service_log_measurement'
```

### W8-rejected-value-in-event - RED 6

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`
- history: run 1 (writer, B1/B2): RED 6; run 9 (re-run on the final tree, writer): RED 6
- note:  

before:
```dart
        rejected ??= measurementRejectionMessage('writer', site, stored);
```
after:
```dart
        rejected ??= measurementRejectionMessage('writer', site, stored) == null ? null : 'tier=writer site=$site side=below v=$stored';
```

### S1-invalidate-before-await - RED 1

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 1; run 9 (re-run on the final tree, writer): RED 1
- note: contended; relies on VM timer-vs-file-IO ordering 

before:
```dart
    final tokenBefore = ref.read(authUserIdTokenProvider);
    final result = await HealthWriteService.instance.logMeasurements(
```
after:
```dart
    final tokenBefore = ref.read(authUserIdTokenProvider);
    ref.invalidate(bodyMeasurementsProvider);
    final result = await HealthWriteService.instance.logMeasurements(
```

### S1b-no-invalidate - RED 4

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 3; run 9 (re-run on the final tree, writer): RED 4
- note:  

before:
```dart
    ref.invalidate(bodyMeasurementsProvider);
    return result;
```
after:
```dart
    return result;
```

### S2-anon-clause-dropped - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 2; run 9 (re-run on the final tree, writer): RED 2
- note:  

before:
```dart
saved && tokenBefore != '<anon>' && tokenNow == tokenBefore
```
after:
```dart
saved && tokenNow == tokenBefore
```

### S3-agreement-dropped - RED 3

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 3; run 9 (re-run on the final tree, writer): RED 3
- note:  

before:
```dart
saved && tokenBefore != '<anon>' && tokenNow == tokenBefore
```
after:
```dart
saved && tokenBefore != '<anon>'
```

### S4-saved-dropped - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 2; run 9 (re-run on the final tree, writer): RED 2
- note:  

before:
```dart
saved && tokenBefore != '<anon>' && tokenNow == tokenBefore
```
after:
```dart
tokenBefore != '<anon>' && tokenNow == tokenBefore
```

### S5-token-read-before-await - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 2; run 9 (re-run on the final tree, writer): RED 2
- note:  

before:
```dart
    final tokenNow = ref.read(authUserIdTokenProvider);
    if (shouldRememberUnit(
```
after:
```dart
    final tokenNow = tokenBefore;
    if (shouldRememberUnit(
```

### S6-unit-swapped - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 2; run 9 (re-run on the final tree, writer): RED 2
- note:  

before:
```dart
inchesUsed ? 'in' : 'cm'
```
after:
```dart
inchesUsed ? 'cm' : 'in'
```

### S7-saved-always-true - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 2; run 9 (re-run on the final tree, writer): RED 2
- note:  

before:
```dart
saved: result.success,
```
after:
```dart
saved: true,
```

### S8-or-connective - RED 5

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`
- history: run 1 (writer, B1/B2): RED 5; run 9 (re-run on the final tree, writer): RED 5
- note:  

before:
```dart
saved && tokenBefore != '<anon>' && tokenNow == tokenBefore
```
after:
```dart
saved && (tokenBefore != '<anon>' || tokenNow == tokenBefore)
```

### P1a-due-27 - RED 5

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 5; run 10 (re-run, prompt): RED 5
- note:  

before:
```dart
const int kMeasurementDueIntervalDays = 28;
```
after:
```dart
const int kMeasurementDueIntervalDays = 27;
```

### P1b-due-29 - RED 6

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 5; run 10 (re-run, prompt): RED 6
- note:  

before:
```dart
const int kMeasurementDueIntervalDays = 28;
```
after:
```dart
const int kMeasurementDueIntervalDays = 29;
```

### P2a-snooze-27 - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 2; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
const int kMeasurementBaselineSnoozeDays = 28;
```
after:
```dart
const int kMeasurementBaselineSnoozeDays = 27;
```

### P2b-snooze-29 - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 2; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
const int kMeasurementBaselineSnoozeDays = 28;
```
after:
```dart
const int kMeasurementBaselineSnoozeDays = 29;
```

### P3a-dismiss-6 - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 2; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
const int kMeasurementDismissSnoozeDays = 7;
```
after:
```dart
const int kMeasurementDismissSnoozeDays = 6;
```

### P3b-dismiss-8 - RED 4

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 3; run 10 (re-run, prompt): RED 4
- note:  

before:
```dart
const int kMeasurementDismissSnoozeDays = 7;
```
after:
```dart
const int kMeasurementDismissSnoozeDays = 8;
```

### P4a-tenure-6 - RED 4

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 3; run 10 (re-run, prompt): RED 4
- note:  

before:
```dart
const int kMeasurementBaselineFromTenureDays = 7;
```
after:
```dart
const int kMeasurementBaselineFromTenureDays = 6;
```

### P4b-tenure-8 - RED 4

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 3; run 10 (re-run, prompt): RED 4
- note:  

before:
```dart
const int kMeasurementBaselineFromTenureDays = 7;
```
after:
```dart
const int kMeasurementBaselineFromTenureDays = 8;
```

### P5a-flag-gate-dropped - RED 1

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
if (!flagOn || !historyKnown || today == null)
```
after:
```dart
if (!historyKnown || today == null)
```

### P5b-history-gate-dropped - RED 2

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 2; run 10 (re-run, prompt): RED 2
- note:  

before:
```dart
if (!flagOn || !historyKnown || today == null)
```
after:
```dart
if (!flagOn || today == null)
```

### P5c-today-null-gate-dropped - RED 1

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
if (!flagOn || !historyKnown || today == null) return MeasurementPrompt.none;
```
after:
```dart
if (!flagOn || !historyKnown) return MeasurementPrompt.none;
  if (today == null) return MeasurementPrompt.due;
```

### P6-future-not-absent - RED 4

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 3; run 10 (re-run, prompt): RED 4
- note:  

before:
```dart
return (d == null || d.isAfter(today)) ? null : d;
```
after:
```dart
return d;
```

### P7-due-gt - RED 5

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 4; run 10 (re-run, prompt): RED 5
- note:  

before:
```dart
return daysSince(lastEntry) >= kMeasurementDueIntervalDays
```
after:
```dart
return daysSince(lastEntry) > kMeasurementDueIntervalDays
```

### P8-dismiss-le - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 2; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
daysSince(dismissed) < kMeasurementDismissSnoozeDays
```
after:
```dart
daysSince(dismissed) <= kMeasurementDismissSnoozeDays
```

### P9-skip-le - RED 2

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 2
- note:  

before:
```dart
daysSince(skipped) < kMeasurementBaselineSnoozeDays
```
after:
```dart
daysSince(skipped) <= kMeasurementBaselineSnoozeDays
```

### P10-tenure-gt - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 2; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
daysSince(onboarded) >= kMeasurementBaselineFromTenureDays
```
after:
```dart
daysSince(onboarded) > kMeasurementBaselineFromTenureDays
```

### P11-skip-applies-to-measured - RED 1

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
  if (lastEntry == null) {
    if (skipped != null &&
        daysSince(skipped) < kMeasurementBaselineSnoozeDays) {
      return MeasurementPrompt.none;
    }
```
after:
```dart
  if (skipped != null &&
      daysSince(skipped) < kMeasurementBaselineSnoozeDays) {
    return MeasurementPrompt.none;
  }
  if (lastEntry == null) {
```

### P12-roundtrip-dropped - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 3; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
if (t.year != y || t.month != m || t.day != d) return null;
```
after:
```dart
(deleted)
```

### P13-shape-dropped - RED 3

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 3; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
if (v is! String || !_kIstKeyShape.hasMatch(v)) return null;
```
after:
```dart
if (v is! String) return null;
```

### P14-dismiss-and-skip-or - RED 30

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 20; run 10 (re-run, prompt): RED 30
- note:  

before:
```dart
if (dismissed != null && daysSince(dismissed) < kMeasurementDismissSnoozeDays) {
```
after:
```dart
if (dismissed == null && daysSince(today) < kMeasurementDismissSnoozeDays) {
```

### Q1-anon-return-dropped - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
    if (token == '<anon>') return MeasurementPrompt.none;

```
after:
```dart
(deleted)
```

### Q2-flag-dropped - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`, `test/contracts/measurement_prompt_state_behavioral_test.dart`
- history: run 2 (prompt, history, rules): GREEN; run 5 (re-run after strengthened tests): RED 1; run 10 (re-run, prompt): GREEN; run 13 (re-run, strengthened-test set): RED 1
- note:  

before:
```dart
    if (!flagOn) return MeasurementPrompt.none;

```
after:
```dart
(deleted)
```

### Q3-history-known-true - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
historyKnown: history.loaded,
```
after:
```dart
historyKnown: true,
```

### Q4-stamp-first-ten - RED 2

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 2
- note:  

before:
```dart
onboardedIst: parsed == null ? null : istDateStr(parsed),
```
after:
```dart
onboardedIst: raw is String && raw.length >= 10 ? raw.substring(0, 10) : null,
```

### Q5-no-build-failed-event - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
      unawaited(ErrorTelemetry.logEvent('measurement_prompt_build_failed',
          message: 'stage=prompt'));

```
after:
```dart
(deleted)
```

### Q6-dismiss-owner-guard-dropped - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
  Future<void> dismiss() async {
    if (HiveUserSession.currentOwnerFullId == null) return;
```
after:
```dart
  Future<void> dismiss() async {
```

### Q6b-skip-owner-guard-dropped - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
  Future<void> skipBaseline() async {
    if (HiveUserSession.currentOwnerFullId == null) return;
```
after:
```dart
  Future<void> skipBaseline() async {
```

### Q7-dismiss-writes-skip-key - RED 3

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 3
- note:  

before:
```dart
    await MigratedKey.write(
        'body_measurement_prompt_dismissed_at', istTodayStr());
```
after:
```dart
    await MigratedKey.write(
        'body_measurement_prompt_baseline_skipped_at', istTodayStr());
```

### Q8-dismiss-no-invalidate - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
        'body_measurement_prompt_dismissed_at', istTodayStr());
    ref.invalidateSelf();
```
after:
```dart
        'body_measurement_prompt_dismissed_at', istTodayStr());
```

### Q8b-skip-no-invalidate - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
        'body_measurement_prompt_baseline_skipped_at', istTodayStr());
    ref.invalidateSelf();
```
after:
```dart
        'body_measurement_prompt_baseline_skipped_at', istTodayStr());
```

### Q9-token-read-not-watched - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
final token = ref.watch(authUserIdTokenProvider); // c4055a
```
after:
```dart
final token = ref.read(authUserIdTokenProvider); // c4055a
```

### Q10-stored-date-any-type - GREEN

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): GREEN; run 10 (re-run, prompt): GREEN
- note:  

before:
```dart
return v is String ? v : null;
```
after:
```dart
return v?.toString();
```

### H1-anon-return-dropped - RED 1

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
    if (token == '<anon>') return const BodyMeasurementsState();

```
after:
```dart
(deleted)
```

### H2-token-read-not-watched - RED 1

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
final token = ref.watch(authUserIdTokenProvider); // c4055a
    // The window
```
after:
```dart
final token = ref.read(authUserIdTokenProvider); // c4055a
    // The window
```

### H3-last-entry-oldest - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 2
- note:  

before:
```dart
lastEntryDate: history.isEmpty ? null : history.first.date,
```
after:
```dart
lastEntryDate: history.isEmpty ? null : history.last.date,
```

### H4-no-history-failed-event - RED 1

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 1; run 10 (re-run, prompt): RED 1
- note:  

before:
```dart
      unawaited(ErrorTelemetry.logEvent('measurement_history_read_failed',
          message: 'stage=history'));

```
after:
```dart
(deleted)
```

### H5-loaded-false-on-success - RED 16

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`, `test/contracts/measurement_sign_out_lifecycle_test.dart`
- history: run 2 (prompt, history, rules): RED 7; run 10 (re-run, prompt): RED 16
- note:  

before:
```dart
      return BodyMeasurementsState(
        loaded: true,
```
after:
```dart
      return BodyMeasurementsState(
        loaded: false,
```

### H6-has-equality - RED 1

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/day_rollover_provider_invalidation_behavioral_test.dart`
- history: run 2 (prompt, history, rules): GREEN; run 5 (re-run after strengthened tests): RED 1; run 10 (re-run, prompt): GREEN; run 13 (re-run, strengthened-test set): RED 1
- note: equality filter: a rollover refresh with an equal summary must still reach the prompt 

before:
```dart
  final String? lastEntryDate;
}
```
after:
```dart
  final String? lastEntryDate;
  @override
  bool operator ==(Object o) => o is BodyMeasurementsState && o.loaded == loaded && o.lastEntryDate == lastEntryDate;
  @override
  int get hashCode => Object.hash(loaded, lastEntryDate);
}
```

### M3-saving-guard-dropped - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
    if (_saving) return;

```
after:
```dart
(deleted)
```

### M4-saving-not-reset - RED 2

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 2
- note:  

before:
```dart
    } finally {
      _saving = false;
    }
```
after:
```dart
    } finally {
    }
```

### M5-mounted-dropped - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
    if (!mounted) return;
    if (!result.success) {
```
after:
```dart
    if (!result.success) {
```

### M6-before-after-await - RED 3

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 3; run 11 (re-run, sheet and units): RED 3
- note: history captured after the await (whitespace-tolerant anchor)

before:
```dart
    final history = ref.read(bodyMeasurementsProvider);
    final before = Map.of(history.latest);
    final known = history.loaded;
    final inchesUsed = _inches;
    final sites = {for (final s in edited) s: _cmOf(s)!};
    final notifier = ref.read(measurementWriteProvider.notifier);
    WriteResult result;
    _saving = true; // checked above, before the first await: a second tap is a no-op
    try {
      result = await notifier.save(
        sites: sites,
        source: WriteSource.manual,
        inchesUsed: inchesUsed,
      );
    } finally {
      _saving = false;
    }
```
after:
```dart
    final inchesUsed = _inches;
    final sites = {for (final s in edited) s: _cmOf(s)!};
    final notifier = ref.read(measurementWriteProvider.notifier);
    WriteResult result;
    _saving = true; // checked above, before the first await: a second tap is a no-op
    try {
      result = await notifier.save(
        sites: sites,
        source: WriteSource.manual,
        inchesUsed: inchesUsed,
      );
    } finally {
      _saving = false;
    }
    final history = ref.read(bodyMeasurementsProvider);
    final before = Map.of(history.latest);
    final known = history.loaded;
```

### M7-known-ignored - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
    if (known) {
      if (sites.length == 1
```
after:
```dart
    if (true) {
      if (sites.length == 1
```

### M9-baseline-one-site-only - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
if (sites.keys.every((s) => !before.containsKey(s))) {
```
after:
```dart
if (sites.length == 1 && sites.keys.every((s) => !before.containsKey(s))) {
```

### M10-every-to-any - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
if (sites.keys.every((s) => !before.containsKey(s))) {
```
after:
```dart
if (sites.keys.any((s) => !before.containsKey(s))) {
```

### M12-invalid-not-blocking - RED 5

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 4; run 11 (re-run, sheet and units): RED 5
- note:  

before:
```dart
    if (invalid.isNotEmpty) {
      // Show every
```
after:
```dart
    if (false) {
      // Show every
```

### M13-focus-last-invalid - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
_nodes[invalid.first]!.requestFocus();
```
after:
```dart
_nodes[invalid.last]!.requestFocus();
```

### M14-only-first-invalid-shown - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): GREEN; run 5 (re-run after strengthened tests): RED 1; run 11 (re-run, sheet and units): RED 1; run 13 (re-run, strengthened-test set): RED 1
- note:  

before:
```dart
setState(() => _touched.addAll(edited));
```
after:
```dart
setState(() => _touched.add(invalid.first));
```

### M15a-save-never-enabled - RED 19

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 17; run 11 (re-run, sheet and units): RED 19
- note:  

before:
```dart
onPressed: edited.isEmpty ? null : _save,
```
after:
```dart
onPressed: null,
```

### M15b-save-always-enabled - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
onPressed: edited.isEmpty ? null : _save,
```
after:
```dart
onPressed: _save,
```

### M16-metric-inverted - RED 20

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 18; run 11 (re-run, sheet and units): RED 20
- note:  

before:
```dart
parseMeasurementInput(_controllers[site]!.text, metric: !_inches);
```
after:
```dart
parseMeasurementInput(_controllers[site]!.text, metric: _inches);
```

### M17-touched-gate-dropped - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
      _touched.contains(site) && !_isBlank(site) && !_isValid(site);
```
after:
```dart
      !_isBlank(site) && !_isValid(site);
```

### M18-suggest-without-problem - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): GREEN; run 5 (re-run after strengthened tests): RED 1; run 11 (re-run, sheet and units): RED 1; run 13 (re-run, strengthened-test set): RED 1
- note:  (whitespace-tolerant anchor)

before:
```dart
    final suggest = problem &&
        suggestOtherUnit(
```
after:
```dart
    final suggest =
        suggestOtherUnit(
```

### M19-stored-line-without-valid - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): GREEN; run 5 (re-run after strengthened tests): RED 1; run 11 (re-run, sheet and units): RED 1; run 13 (re-run, strengthened-test set): RED 1
- note:  

before:
```dart
if (_inches && !_isBlank(site) && cm != null && _isValid(site))
```
after:
```dart
if (_inches && !_isBlank(site) && cm != null)
```

### M20-action-always-next - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  (whitespace-tolerant anchor)

before:
```dart
isLastRow ? TextInputAction.done : TextInputAction.next,
```
after:
```dart
TextInputAction.next,
```

### M21-formatter-wider - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
RegExp(r'^\d{0,3}\.?\d{0,1}')
```
after:
```dart
RegExp(r'^\d{0,4}\.?\d{0,1}')
```

### M22-hint-noop - RED 3

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 3; run 11 (re-run, sheet and units): RED 3
- note:  

before:
```dart
onTap: () => _setInches(!_inches),
```
after:
```dart
onTap: () => _setInches(_inches),
```

### M23-unit-option-short - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
```
after:
```dart
constraints: const BoxConstraints(minWidth: 52, minHeight: 30),
```

### M24-save-short - GREEN

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): GREEN; run 11 (re-run, sheet and units): GREEN
- note:  

before:
```dart
minimumSize: const Size.fromHeight(48),
```
after:
```dart
minimumSize: const Size.fromHeight(30),
```

### M25-retry-noop - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
                        onPressed: () =>
                            ref.invalidate(bodyMeasurementsProvider),
```
after:
```dart
                        onPressed: () {},
```

### M26-intro-inverted - RED 3

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 2; run 11 (re-run, sheet and units): RED 3
- note:  

before:
```dart
history.loaded && history.latest.isEmpty
                      ? MeasurementCopy.introFirst
                      : MeasurementCopy.introLater,
```
after:
```dart
history.loaded && history.latest.isEmpty
                      ? MeasurementCopy.introLater
                      : MeasurementCopy.introFirst,
```

### M27-no-scroll-view - RED 52

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 40; run 11 (re-run, sheet and units): RED 52
- note:  

before:
```dart
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
```
after:
```dart
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
```

### M28-viewinsets-padding-dropped (expected equivalent) - RED 2

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): GREEN; run 11 (re-run, sheet and units): anchor missed (re-run); run 14 (re-anchored after dart format and the chat telemetry): RED 2
- note: equivalence label RETRACTED (the /dev route is outside the shell); anchor re-derived after dart format 

before:
```dart
EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
```
after:
```dart
EdgeInsets.zero,
```

### M29-inch-hint-dropped - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
inches: _inches ? inchesFromCm(last.cm) : null,
```
after:
```dart
inches: null,
```

### M30-no-pop - RED 3

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 3; run 11 (re-run, sheet and units): RED 3
- note:  

before:
```dart
    Navigator.of(context).pop();
    messenger.showSnackBar
```
after:
```dart
    messenger.showSnackBar
```

### M31-source - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
        source: WriteSource.manual,
        inchesUsed: inchesUsed,
```
after:
```dart
        source: WriteSource.aiCoach,
        inchesUsed: inchesUsed,
```

### M32-inches-used-false - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
        inchesUsed: inchesUsed,
      );
    } finally
```
after:
```dart
        inchesUsed: false,
      );
    } finally
```

### M33-haptic-dropped (expected equivalent) - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): GREEN; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
    unawaited(HapticFeedback.lightImpact());

```
after:
```dart
(deleted)
```

### M34-failed-no-message - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 1; run 11 (re-run, sheet and units): RED 1
- note:  

before:
```dart
      setState(() => _saveFailed = true);
      return;
```
after:
```dart
      return;
```

### M35-sites-all-rows - RED 5

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 5; run 11 (re-run, sheet and units): RED 5
- note:  

before:
```dart
    final sites = {for (final s in edited) s: _cmOf(s)!};
```
after:
```dart
    final sites = {for (final s in kBodyMeasurementSites) s: _cmOf(s) ?? 0.0};
```

### M36-delta-before-after-swapped - RED 2

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 3 (sheet and units, main tree): RED 2; run 11 (re-run, sheet and units): RED 2
- note:  

before:
```dart
          before[site]!.cm,
          sites[site]!,
```
after:
```dart
          sites[site]!,
          before[site]!.cm,
```

### B1-variants-swapped - RED 6

- file: `lib/features/home/widgets/measurement_due_banner.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 6
- note:  

before:
```dart
baseline
                            ? MeasurementCopy.bannerBaseline
                            : MeasurementCopy.bannerDue,
```
after:
```dart
baseline
                            ? MeasurementCopy.bannerDue
                            : MeasurementCopy.bannerBaseline,
```

### B2-card-tap-dismisses - RED 2

- file: `lib/features/home/widgets/measurement_due_banner.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 2; run 12 (re-run, surfaces, chat, lists, flag): RED 2
- note:  

before:
```dart
              onTap: onOpen,
```
after:
```dart
              onTap: onDismiss,
```

### B3-x-short - RED 3

- file: `lib/features/home/widgets/measurement_due_banner.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
                width: 44,
                height: 44,
```
after:
```dart
                width: 44,
                height: 30,
```

### B4-no-semantics-label - RED 2

- file: `lib/features/home/widgets/measurement_due_banner.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 2
- note:  

before:
```dart
            label: MeasurementCopy.bannerDismissLabel,

```
after:
```dart
(deleted)
```

### B5-x-opens - RED 7

- file: `lib/features/home/widgets/measurement_due_banner.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 7
- note:  

before:
```dart
              onTap: onDismiss,
              child: const SizedBox(
```
after:
```dart
              onTap: onOpen,
              child: const SizedBox(
```

### L1-flag-check-dropped - RED 1

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
    if (!ref.watch(measurementsEnabledProvider)) return const SizedBox.shrink();

```
after:
```dart
(deleted)
```

### L2-none-shows - RED 3

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
    if (prompt == MeasurementPrompt.none) return const SizedBox.shrink();

```
after:
```dart
(deleted)
```

### L3-baseline-inverted - RED 6

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 6
- note:  

before:
```dart
final baseline = prompt == MeasurementPrompt.baseline;
```
after:
```dart
final baseline = prompt != MeasurementPrompt.baseline;
```

### L4-dismiss-routes-swapped - RED 3

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 2; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
        if (baseline) {
          notifier.skipBaseline();
        } else {
          notifier.dismiss();
        }
```
after:
```dart
        if (baseline) {
          notifier.dismiss();
        } else {
          notifier.skipBaseline();
        }
```

### L5-open-noop - RED 1

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
      onOpen: () => BodyMeasurementsSheet.show(context),
```
after:
```dart
      onOpen: () {},
```

### Wt1-flag-clause-dropped - RED 3

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
    _showMeasurementsLink = ref.read(measurementsEnabledProvider) &&
        ref.read(measurementPromptProvider) != MeasurementPrompt.none;
```
after:
```dart
    _showMeasurementsLink =
        ref.read(measurementPromptProvider) != MeasurementPrompt.none;
```

### Wt2-prompt-inverted - RED 21

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 12; run 12 (re-run, surfaces, chat, lists, flag): RED 21
- note:  

before:
```dart
ref.read(measurementPromptProvider) != MeasurementPrompt.none;
```
after:
```dart
ref.read(measurementPromptProvider) == MeasurementPrompt.none;
```

### Wt3-decision-in-build - RED 3

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
  Widget build(BuildContext context) {
    return Container(
```
after:
```dart
  Widget build(BuildContext context) {
    _showMeasurementsLink = ref.watch(measurementsEnabledProvider) &&
        ref.watch(measurementPromptProvider) != MeasurementPrompt.none;
    return Container(
```

### Wt4-no-scroll-wrap - RED 10

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 10
- note:  

before:
```dart
      _showMeasurementsLink ? SingleChildScrollView(child: column) : column;
```
after:
```dart
      column;
```

### Wt5-no-pop - RED 2

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 2; run 12 (re-run, surfaces, chat, lists, flag): RED 2
- note:  

before:
```dart
                Navigator.pop(context);
                BodyMeasurementsSheet.show(context);
```
after:
```dart
                BodyMeasurementsSheet.show(context);
```

### Wt6-link-short - GREEN

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): GREEN; run 12 (re-run, surfaces, chat, lists, flag): GREEN
- note:  

before:
```dart
                minimumSize: const Size.fromHeight(44),
                foregroundColor: AppColors.accent,
```
after:
```dart
                minimumSize: const Size.fromHeight(20),
                foregroundColor: AppColors.accent,
```

### Wt7-link-always-built - RED 4

- file: `lib/features/home/widgets/weight_log_sheet.dart`; tests run: `test/home/weight_sheet_measurements_link_test.dart`, `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 4
- note:  

before:
```dart
          if (_showMeasurementsLink)
            TextButton(
```
after:
```dart
          if (true)
            TextButton(
```

### C1-flag-guard-dropped - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
    final notifier = MeasurementFlags.bodyMeasurementsEnabled
        ? _tryMeasurementNotifier()
        : null;
```
after:
```dart
    final notifier = _tryMeasurementNotifier();
```

### C2-success-guard-dropped - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
    if (result.success) {
      try {
        notifier?.noteWritten();
```
after:
```dart
    if (true) {
      try {
        notifier?.noteWritten();
```

### C3-note-try-dropped - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): anchor missed (re-run); run 14 (re-anchored after dart format and the chat telemetry): RED 1
- note: re-anchored: the catch now records an event 

before:
```dart
try {
        notifier?.noteWritten();
      } catch (_) {
        // The write succeeded; only the history refresh failed. Record it (the
        // history would otherwise stay stale with no trace) and carry on.
        unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
            message: 'stage=note'));
      }
```
after:
```dart
notifier?.noteWritten();
```

### C4-lookup-try-dropped - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): GREEN; run 5 (re-run after strengthened tests): RED 1; run 12 (re-run, surfaces, chat, lists, flag): anchor missed (re-run); run 13 (re-run, strengthened-test set): anchor missed (re-run); run 14 (re-anchored after dart format and the chat telemetry): RED 1
- note: re-anchored: the catch now records an event 

before:
```dart
try {
      return ref.read(measurementWriteProvider.notifier);
    } catch (_) {
      unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
          message: 'stage=lookup'));
      return null;
    }
```
after:
```dart
return ref.read(measurementWriteProvider.notifier);
```

### C5-note-before-write - RED 3

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): anchor missed (re-run); run 14 (re-anchored after dart format and the chat telemetry): RED 3
- note: re-anchored: the catch now records an event 

before:
```dart
if (result.success) {
      try {
        notifier?.noteWritten();
      } catch (_) {
        // The write succeeded; only the history refresh failed. Record it (the
        // history would otherwise stay stale with no trace) and carry on.
        unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
            message: 'stage=note'));
      }
    }
    return result.success;
```
after:
```dart
return result.success;
```

### R1-rollover-invalidate-dropped - RED 2

- file: `lib/core/services/day_rollover_service.dart`; tests run: `test/contracts/day_rollover_provider_invalidation_behavioral_test.dart`, `test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 2; run 12 (re-run, surfaces, chat, lists, flag): RED 2
- note:  

before:
```dart
    ref.invalidate(bodyMeasurementsProvider);

```
after:
```dart
(deleted)
```

### HS1-retry-invalidate-dropped - RED 1

- file: `lib/features/home/screens/home_screen.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
    ref.invalidate(bodyMeasurementsProvider);
  }
```
after:
```dart
  }
```

### F1-not-false - RED 3

- file: `lib/core/services/measurement_flags.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
HiveService.instance.configBox.get('enable_body_measurements') ==
          true;
```
after:
```dart
HiveService.instance.configBox.get('enable_body_measurements') !=
          false;
```

### F2-catch-true - RED 1

- file: `lib/core/services/measurement_flags.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
      return false; // no Hive
```
after:
```dart
      return true; // no Hive
```

### F3-key-renamed - RED 4

- file: `lib/core/services/measurement_flags.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 4; run 12 (re-run, surfaces, chat, lists, flag): RED 4
- note:  

before:
```dart
configBox.get('enable_body_measurements')
```
after:
```dart
configBox.get('enable_body_measurement')
```

### FP1-token-not-watched - RED 1

- file: `lib/features/profile/providers/measurement_flag_provider.dart`; tests run: `test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
  ref.watch(authUserIdTokenProvider); // c4055a — rebuild on auth change
```
after:
```dart
  ref.read(authUserIdTokenProvider); // c4055a — rebuild on auth change
```

### D1-dev-order-swapped - RED 1

- file: `lib/features/dev/dev_panel_screen.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 1; run 12 (re-run, surfaces, chat, lists, flag): RED 1
- note:  

before:
```dart
    ref.invalidate(measurementsEnabledProvider);
    await DayRolloverObserver.instance.runRolloverNow(ref);
```
after:
```dart
    await DayRolloverObserver.instance.runRolloverNow(ref);
    ref.invalidate(measurementsEnabledProvider);
```

### U1-cm-per-inch - RED 25

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 25; run 12 (re-run, surfaces, chat, lists, flag): RED 25
- note:  

before:
```dart
const double _kCmPerInch = 2.54;
```
after:
```dart
const double _kCmPerInch = 2.5;
```

### U2-parse-swapped - RED 26

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 25; run 12 (re-run, surfaces, chat, lists, flag): RED 26
- note:  

before:
```dart
final cm = metric ? roundMeasurementToTenth(v) : cmFromInches(v);
```
after:
```dart
final cm = metric ? cmFromInches(v) : roundMeasurementToTenth(v);
```

### U3-suggest-valid-here-ignored - RED 12

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 12; run 12 (re-run, surfaces, chat, lists, flag): RED 12
- note:  

before:
```dart
  if (isValidBodyMeasurementCm(site, here)) return false;

```
after:
```dart
(deleted)
```

### U4-suggest-other-ignored - RED 13

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 13; run 12 (re-run, surfaces, chat, lists, flag): RED 13
- note:  

before:
```dart
  return isValidBodyMeasurementCm(site, other);
```
after:
```dart
  return true;
```

### U5-year-compare - RED 2

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 2; run 12 (re-run, surfaces, chat, lists, flag): RED 2
- note:  

before:
```dart
return year == currentYear ? base : '$base $year';
```
after:
```dart
return base;
```

### U6-month-off-by-one - RED 3

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 3; run 12 (re-run, surfaces, chat, lists, flag): RED 3
- note:  

before:
```dart
final base = '$day ${_kMonthNames[month - 1]}';
```
after:
```dart
final base = '$day ${_kMonthNames[month % 12]}';
```

### U7-nonfinite-guard-dropped - GREEN

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): GREEN; run 12 (re-run, surfaces, chat, lists, flag): GREEN
- note:  

before:
```dart
if (v == null || !v.isFinite) return null;
```
after:
```dart
if (v == null) return null;
```

### U8-bounds-first-last - RED 4

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 4 (surfaces, chat, lists, flag; scratch copy): RED 4; run 12 (re-run, surfaces, chat, lists, flag): RED 4
- note:  

before:
```dart
      lo ??= inch;
      hi = inch;
```
after:
```dart
      lo = inch;
      hi = inch;
```

### U7b-second-guard-dropped - RED 1

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 5 (re-run after strengthened tests): GREEN; run 13 (re-run, strengthened-test set): RED 1
- note: expected equivalent: first guard covers 

before:
```dart
  return cm.isFinite ? cm : null;
```
after:
```dart
  return cm;
```

### U7c-both-guards-dropped - RED 2

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`
- history: run 5 (re-run after strengthened tests): RED 1; run 13 (re-run, strengthened-test set): RED 2
- note: both guards gone must redden 

before:
```dart
if (v == null || !v.isFinite) return null;
  final cm = metric ? roundMeasurementToTenth(v) : cmFromInches(v);
  return cm.isFinite ? cm : null;
```
after:
```dart
if (v == null) return null;
  final cm = metric ? roundMeasurementToTenth(v) : cmFromInches(v);
  return cm;
```

### MUT-1 - RED 1

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
d.isAfter(today)
```
after:
```dart
d.isAfter(today.add(const Duration(days: 1)))
```

### MUT-2 - RED 2

- file: `lib/features/profile/services/measurement_prompt_rules.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
RegExp(r'^\d{4}-\d{2}-\d{2}$')
```
after:
```dart
RegExp(r'^\d{4}-\d{2}-\d{2}$', multiLine: true)
```

### MUT-3 - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
return v is String ? v : null;
```
after:
```dart
return v as String?;
```

### MUT-4 - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
'body_measurement_prompt_dismissed_at', istTodayStr()
```
after:
```dart
'body_measurement_prompt_dismissed_at', istDateStr(DateTime.now())
```

### MUT-5 - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
'body_measurement_prompt_dismissed_at', istTodayStr()
```
after:
```dart
'body_measurement_prompt_dismissed_at', nowWall().toUtc().toIso8601String().substring(0, 10)
```

### MUT-6 - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
'body_measurement_prompt_baseline_skipped_at', istTodayStr()
```
after:
```dart
'body_measurement_prompt_baseline_skipped_at', istDateStr(DateTime.now())
```

### MUT-7 - RED 2

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
todayIst: istTodayStr(),
```
after:
```dart
todayIst: nowWall().toUtc().toIso8601String().substring(0, 10),
```

### MUT-8 - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_prompt_state_behavioral_test.dart`

before:
```dart
final flagOn = ref.watch(measurementsEnabledProvider);
```
after:
```dart
final flagOn = ref.read(measurementsEnabledProvider);
```

### MUT-9 - RED 1

- file: `lib/features/profile/providers/measurement_prompt_provider.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`

before:
```dart
final flagOn = ref.watch(measurementsEnabledProvider);
```
after:
```dart
ref.watch(userProfileProvider);
    final flagOn = ref.watch(measurementsEnabledProvider);
```

### MUT-10 - RED 1

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`

before:
```dart
  void noteWritten() {
    ref.invalidate(bodyMeasurementsProvider);
  }
```
after:
```dart
  void noteWritten() {
    final _ = ref.refresh(bodyMeasurementsProvider);
  }
```

### MUT-11 - RED 2

- file: `lib/features/profile/providers/body_measurements_provider.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/contracts/measurement_save_unit_rule_test.dart`

before:
```dart
    ref.invalidate(bodyMeasurementsProvider);
    return result;
```
after:
```dart
    if (result.success) ref.invalidate(bodyMeasurementsProvider);
    return result;
```

### MUT-12 - RED 2

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`

before:
```dart
        sites: rounded,
        source: source,
```
after:
```dart
        sites: rounded,
        source: WriteSource.aiCoach,
```

### MUT-13 - RED 2

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/sync/measurement_batch_push_test.dart`

before:
```dart
      unawaited(SyncService.instance.syncMeasurementsNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurements]
```
after:
```dart
      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurements]
```

### MUT-13b - RED 1

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/sync/measurement_batch_push_test.dart`

before:
```dart
      unawaited(SyncService.instance.syncMeasurementsNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurements]
```
after:
```dart
      unawaited(SyncService.instance.syncMeasurementsNow());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurements]
```

### MUT-13c - RED 2

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`, `test/sync/measurement_batch_push_test.dart`

before:
```dart
      unawaited(SyncService.instance.syncMeasurementsNow());
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurements]
```
after:
```dart
      unawaited(SyncService.instance.pushSnapshot());

      return WriteResult.ok(key);
    } catch (e, st) {
      debugPrint('[HealthWriteService.logMeasurements]
```

### MUT-14 - RED 1

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`

before:
```dart
        sites: rounded,
        source: source,
      );
      await box.put(key, record);
```
after:
```dart
        sites: rounded,
        source: source,
      );
      box.put(key, record);
```

### MUT-15 - RED 1

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`

before:
```dart
    final lockKey = '$dateStr::measurement';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final record = measurementRecordWith(
        box.get(key),
        dateStr: dateStr,
        sites: rounded,
```
after:
```dart
    final lockKey = '$dateStr::measurement_batch';
    final c = await _acquireLock(lockKey);
    try {
      final box = HiveService.instance.healthBox;
      final record = measurementRecordWith(
        box.get(key),
        dateStr: dateStr,
        sites: rounded,
```

### MUT-16 - RED 2

- file: `lib/core/services/health_write_service.dart`; tests run: `test/contracts/measurement_write_batch_behavioral_test.dart`

before:
```dart
        box.get(key),
        dateStr: dateStr,
        sites: rounded,
```
after:
```dart
        box.get(key) as Map<String, dynamic>?,
        dateStr: dateStr,
        sites: rounded,
```

### MUT-17 - RED 1

- file: `lib/features/dev/dev_panel_screen.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`

before:
```dart
final next = !MeasurementFlags.bodyMeasurementsEnabled;
```
after:
```dart
final next = MeasurementFlags.bodyMeasurementsEnabled;
```

### MUT-18 - RED 1

- file: `lib/features/dev/dev_panel_screen.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`

before:
```dart
MeasurementFlags.bodyMeasurementsEnabled ? 'ON' : 'off')
```
after:
```dart
MeasurementFlags.bodyMeasurementsEnabled ? 'off' : 'ON')
```

### MUT-19 - RED 1

- file: `lib/features/home/screens/home_screen.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`

before:
```dart
        const MeasurementDueSlot(),
```
after:
```dart
        const SizedBox.shrink(),
```

### MUT-20 - RED 1

- file: `lib/features/home/screens/home_screen.dart`; tests run: `test/contracts/measurement_flag_off_identity_test.dart`

before:
```dart
    ref.invalidate(bodyMeasurementsProvider);
  }
```
after:
```dart
    if (DateTime.now().year < 2000) ref.invalidate(bodyMeasurementsProvider);
  }
```

### MUT-21 - RED 2

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`

before:
```dart
final prompt = ref.watch(measurementPromptProvider);
```
after:
```dart
final prompt = ref.read(measurementPromptProvider);
```

### MUT-22 - RED 1

- file: `lib/features/home/widgets/measurement_due_slot.dart`; tests run: `test/home/measurement_slots_test.dart`
- history: run 6 (B-pass reviewer B's 36 + new protections): GREEN; run 7 (survivor fixes: MUT-22 and MUT-34 against the new rows, and two replacement mutants for MUT-36): RED 1
- note:  

before:
```dart
if (!ref.watch(measurementsEnabledProvider))
```
after:
```dart
if (!ref.read(measurementsEnabledProvider))
```

### MUT-23 - RED 1

- file: `lib/features/home/widgets/measurement_due_banner.dart`; tests run: `test/home/measurement_slots_test.dart`

before:
```dart
            button: true,
```
after:
```dart
            button: false,
```

### MUT-24 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
_touched.contains(site) && !_isBlank(site) && !_isValid(site)
```
after:
```dart
_touched.contains(site) && !_isValid(site)
```

### MUT-25 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
history.loaded && history.latest.isEmpty
```
after:
```dart
history.latest.isEmpty
```

### MUT-26 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
HapticFeedback.lightImpact()
```
after:
```dart
HapticFeedback.heavyImpact()
```

### MUT-26b - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
    unawaited(HapticFeedback.lightImpact());

```
after:
```dart
(deleted)
```

### MUT-27 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
                      disabledBackgroundColor: AppColors.input,
                      disabledForegroundColor: AppColors.textDim,

```
after:
```dart
(deleted)
```

### MUT-28 - RED 2

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
final selected = inches == isInches;
```
after:
```dart
final selected = inches != isInches;
```

### MUT-29 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
```
after:
```dart
keyboardType: TextInputType.number,
```

### MUT-30 - RED 6

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
          child: SingleChildScrollView(

```
after:
```dart
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),

```

### MUT-31 - RED 2

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
bottom: MediaQuery.of(context).viewInsets.bottom,
```
after:
```dart
bottom: 0,
```

### MUT-32 - RED 4

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
      isScrollControlled: true,
```
after:
```dart
      isScrollControlled: false,
```

### MUT-33 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
      isScrollControlled: true,
```
after:
```dart
      isScrollControlled: true,
      useRootNavigator: true,
```

### MUT-34 - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`
- history: run 6 (B-pass reviewer B's 36 + new protections): GREEN; run 7 (survivor fixes: MUT-22 and MUT-34 against the new rows, and two replacement mutants for MUT-36): RED 1
- note:  

before:
```dart
final todayIst = istTodayStr();
```
after:
```dart
final todayIst = istDateStr(DateTime.now());
```

### MUT-35 - RED 1

- file: `lib/core/utils/measurement_units.dart`; tests run: `test/utils/measurement_units_test.dart`

before:
```dart
  return cm.isFinite ? cm : null;
```
after:
```dart
  return cm;
```

### MUT-36 - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- history: run 6 (B-pass reviewer B's 36 + new protections): COMPILE; run 8 (MUT-36 as proposed, with its import added): RED 1
- note:  

before:
```dart
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
--- and, in the same file ---
final notifier = MeasurementFlags.bodyMeasurementsEnabled
        ? _tryMeasurementNotifier()
        : null;
```
after:
```dart
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
--- and, in the same file ---
final notifier = ref.read(measurementsEnabledProvider)
        ? _tryMeasurementNotifier()
        : null;
```

### N1-safe-area - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
      useSafeArea: true,

```
after:
```dart
(deleted)
```

### N2-hint-not-button - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
            Semantics(
              button: true,
              child: InkWell(
```
after:
```dart
            Semantics(
              child: InkWell(
```

### N3-hint-focusable - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
                canRequestFocus: false,

```
after:
```dart
(deleted)
```

### N4-field-no-label - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
            label: spec.label,
            textField: true,
```
after:
```dart
            textField: true,
```

### N5-unit-not-selected - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
        selected: selected,

```
after:
```dart
        selected: false,

```

### N6-unit-labels-swapped - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
            ? MeasurementCopy.unitInSemantics
            : MeasurementCopy.unitCmSemantics,
```
after:
```dart
            ? MeasurementCopy.unitCmSemantics
            : MeasurementCopy.unitInSemantics,
```

### N7-last-hint-mute - RED 1

- file: `lib/features/profile/widgets/body_measurements_sheet.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
shortDate: shortDate,
              ),
              style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
```
after:
```dart
shortDate: shortDate,
              ),
              style: AppTypography.bodyS.copyWith(color: AppColors.textMute),
```

### N8a-chat-note-event - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`

before:
```dart
        unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
            message: 'stage=note'));
```
after:
```dart
(deleted)
```

### N8b-chat-lookup-event - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`

before:
```dart
      unawaited(ErrorTelemetry.logEvent('measurement_chat_refresh_failed',
          message: 'stage=lookup'));

```
after:
```dart
(deleted)
```

### N9-slice-strings - RED 4

- file: `test/helpers/dart_source_slice.dart`; tests run: `test/contracts/dart_source_slice_helper_test.dart`

before:
```dart
    if (c == "'" || c == '"') {
```
after:
```dart
    if (false) {
```

### N9b-slice-line-first - RED 3

- file: `test/helpers/dart_source_slice.dart`; tests run: `test/contracts/dart_source_slice_helper_test.dart`

before:
```dart
    if (c == '/' && next == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
```
after:
```dart
    if (c == '/' && next == '/') {
      i = n;
      continue;
    }
```

### N10-rollover-invalidate - RED 2

- file: `lib/core/services/day_rollover_service.dart`; tests run: `test/contracts/day_rollover_provider_invalidation_behavioral_test.dart`, `test/contracts/day_rollover_provider_invalidation_writer_to_reader_test.dart`

before:
```dart
    ref.invalidate(bodyMeasurementsProvider);
```
after:
```dart
    // ref.invalidate(bodyMeasurementsProvider);
```

### N11-copy-emdash - RED 4

- file: `lib/core/copy/measurement_copy.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`, `test/home/measurement_slots_test.dart`

before:
```dart
'Looks like inches · switch?'
```
after:
```dart
'Looks like inches — switch?'
```

### N12-banner-copy - RED 1

- file: `lib/core/copy/measurement_copy.dart`; tests run: `test/home/measurement_slots_test.dart`

before:
```dart
'Set your baseline: four tape measures, about a minute.'
```
after:
```dart
'Set your baseline: four tape measures, about a minute!'
```

### N13-guide-copy - RED 1

- file: `lib/core/constants/body_measurement_specs.dart`; tests run: `test/features/profile/body_measurements_sheet_test.dart`

before:
```dart
Around the widest part of your hips, feet together.
```
after:
```dart
Around the widest part of your hips, feet apart.
```

### MUT-36b-flag-ignored - RED 1

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- note:  

before:
```dart
final notifier = MeasurementFlags.bodyMeasurementsEnabled
        ? _tryMeasurementNotifier()
        : null;
```
after:
```dart
final notifier = true
        ? _tryMeasurementNotifier()
        : null;
```

### MUT-36c-never-refresh - RED 4

- file: `lib/features/ai_coach/services/conversational_log_handler.dart`; tests run: `test/contracts/measurement_chat_path_off_identity_test.dart`
- note:  

before:
```dart
final notifier = MeasurementFlags.bodyMeasurementsEnabled
        ? _tryMeasurementNotifier()
        : null;
```
after:
```dart
final notifier = false
        ? _tryMeasurementNotifier()
        : null;
```
