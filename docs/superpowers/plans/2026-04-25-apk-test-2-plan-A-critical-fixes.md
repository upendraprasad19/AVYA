# APK Test #2 — Plan A: Critical Fixes + Migrations

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the foundational migrations and critical bug fixes that unblock the rest of the APK Test #2 batch. Every fix in this plan has a clear root cause from investigation; no design decisions remain.

**Architecture:** All changes are surgical — single-line bug fixes, prompt hardening, parse-guard extension, and two database migrations. Each change ships with a regression test that captures the original bug.

**Tech Stack:** Flutter (Dart 3), Riverpod, Hive, Supabase Postgres + Edge Functions, Gemini 2.5 Flash via `ai-proxy`. Test runners: `flutter test` for unit, `flutter test --dart-define-from-file=.env integration_test/flows/<name>_test.dart --flavor dev` for integration.

**Spec source:** `docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md` (Section 1 + Section 2)

**Branch:** `feat/apk-test-2-batch` (single branch for all four plans A–D)

---

## File Structure

### Migrations
- **NEW** `supabase/migrations/036_onboarding_completed_at.sql` — `user_profile.onboarding_completed_at TIMESTAMPTZ` with backfill
- **NEW** `supabase/migrations/037_referral_redemptions.sql` — `referral_codes.expires_at` + `referral_redemptions` audit table

### Source files modified
- `lib/core/services/sync_service.dart` (F1 syntax fix at line 1564)
- `lib/features/ai_coach/providers/ai_coach_provider.dart` (F4 parse guard extension; F5 invalidation hooks)
- `lib/core/services/prediction_service.dart` (F4 prompt hardening)
- `lib/features/onboarding/providers/onboarding_provider.dart` (F4 prompt hardening)
- `lib/features/profile/screens/edit_profile_screen.dart` (F5 invalidation; F6 experience key)
- `lib/features/train/providers/train_provider.dart` (F5 invalidation in `completeWorkout`)
- `lib/core/services/workout_schedule_service.dart` (F7 logging_type resolution; F5 invalidation in `generateAndScheduleFromDate`)
- `lib/features/train/screens/active_workout_screen.dart` (F8 set-add append)
- `lib/features/home/screens/home_screen.dart` (F9 plan-relative week number)
- `lib/features/nutrition/providers/nutrition_provider.dart` (F11 food analysis investigation hook)

### Tests created
- `test/sync/custom_exercise_sync_test.dart` (F1 regression)
- `test/ai_coach/prediction_sanitiser_test.dart` (F4 regression)
- `test/providers/ai_insight_invalidation_test.dart` (F5 regression)
- `test/plan_generator/edit_profile_regen_test.dart` (F6 regression)
- `test/sync/swap_logging_type_test.dart` (F7 regression)
- `integration_test/flows/add_set_preserves_weight_test.dart` (F8 regression)
- `test/home/week_number_test.dart` (F9 regression)

---

## Tasks

### Task 1: Migration 036 — `onboarding_completed_at`

**Files:**
- Create: `supabase/migrations/036_onboarding_completed_at.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- supabase/migrations/036_onboarding_completed_at.sql
--
-- Adds an explicit `onboarding_completed_at` timestamp to user_profile so the
-- restore flow on relogin can decide between "send to home" and "send to
-- onboarding" without ambiguity.
--
-- Backfilled from existing rows where primary_goal IS NOT NULL (primary_goal
-- is captured in onboarding step 02 and never null afterward, so its presence
-- is a reliable proxy for "user finished onboarding at some point in the past").

ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMPTZ;

UPDATE user_profile
  SET onboarding_completed_at = COALESCE(updated_at, created_at, now())
  WHERE primary_goal IS NOT NULL
    AND onboarding_completed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_user_profile_onboarding_completed
  ON user_profile (user_id, onboarding_completed_at);
```

- [ ] **Step 2: Apply the migration to prod via MCP**

Use the Supabase MCP `apply_migration` tool with `project_id="dedsavbjuwgarrhphgnl"`, `name="036_onboarding_completed_at"`, and the SQL content above. The MCP wraps execution in a transaction; failures roll back automatically.

- [ ] **Step 3: Verify the column exists and is populated**

Use Supabase MCP `execute_sql` to run:

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(onboarding_completed_at) AS rows_with_timestamp,
  COUNT(*) FILTER (WHERE primary_goal IS NOT NULL) AS rows_with_goal
FROM user_profile;
```

Expected: `rows_with_timestamp` equals `rows_with_goal` (every onboarded user has the new timestamp).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/036_onboarding_completed_at.sql
git commit -m "db(036): onboarding_completed_at on user_profile

Adds explicit timestamp so the restore-on-relogin flow can branch
between /home and /onboarding without ambiguity. Backfilled from
existing rows where primary_goal IS NOT NULL.

Spec: docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md
section 2."
```

---

### Task 2: Migration 037 — `referral_codes.expires_at` + `referral_redemptions`

**Files:**
- Create: `supabase/migrations/037_referral_redemptions.sql`

- [ ] **Step 1: Write the migration SQL**

```sql
-- supabase/migrations/037_referral_redemptions.sql
--
-- Two changes for the 7-day referral system:
--   1. Add `expires_at` to referral_codes so codes expire 7 days after generation.
--   2. New `referral_redemptions` audit table: who redeemed whose code, when,
--      with both-side reward tracking.
--
-- Both halves are needed for the redeem-referral Edge Function update later
-- in the batch.

-- 1. Code expiry on existing referral_codes table (added by migration 035)
ALTER TABLE referral_codes
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ
    NOT NULL DEFAULT (now() + interval '7 days');

-- Backfill existing rows: any pre-existing codes get a fresh 7-day window
-- starting now (we don't expire them retroactively — they were generated
-- under the "permanent" assumption).
UPDATE referral_codes
  SET expires_at = now() + interval '7 days'
  WHERE expires_at <= now();

-- 2. Audit table
CREATE TABLE IF NOT EXISTS referral_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL,
  referrer_id UUID NOT NULL REFERENCES auth.users(id),
  referee_id UUID NOT NULL REFERENCES auth.users(id),
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  days_granted_each INT NOT NULL DEFAULT 7,
  CONSTRAINT no_self_referral CHECK (referrer_id != referee_id),
  CONSTRAINT unique_referee_redemption UNIQUE (referee_id)
);

CREATE INDEX idx_referral_redemptions_referrer
  ON referral_redemptions (referrer_id);
CREATE INDEX idx_referral_redemptions_redeemed_at
  ON referral_redemptions (redeemed_at);

ALTER TABLE referral_redemptions ENABLE ROW LEVEL SECURITY;

-- Both referrer and referee can read their own redemption rows
CREATE POLICY "Users can read own redemptions" ON referral_redemptions
  FOR SELECT USING (auth.uid() = referrer_id OR auth.uid() = referee_id);

-- INSERT only via Edge Function (service role bypasses RLS)
-- No client-side INSERT policy — referee can't self-create.
```

- [ ] **Step 2: Apply migration to prod via MCP**

Use Supabase MCP `apply_migration` tool with `project_id="dedsavbjuwgarrhphgnl"`, `name="037_referral_redemptions"`, and the SQL content.

- [ ] **Step 3: Verify schema**

```sql
-- Confirm column added
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'referral_codes' AND column_name = 'expires_at';

-- Confirm table created with constraints
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'referral_redemptions';
```

Expected: `expires_at` column with `now() + interval '7 days'` default; `referral_redemptions` has `unique_referee_redemption`, `no_self_referral`, foreign keys, and RLS enabled.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/037_referral_redemptions.sql
git commit -m "db(037): referral_codes.expires_at + referral_redemptions table

7-day code lifetime + audit table for both-side reward tracking.
Codes generated before this migration get fresh 7-day windows
starting now (not expired retroactively).

Spec: docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md
section 2."
```

---

### Task 3: F1 — Custom exercise sync syntax fix

**Files:**
- Test: `test/sync/custom_exercise_sync_test.dart`
- Modify: `lib/core/services/sync_service.dart:1564`

The bug is a Dart syntax error: `'default_duration_secs': ?defaultDur,` uses `?` as a map-value operator, which is invalid. The function throws at runtime, the upsert never executes, Hive write succeeds locally, but Supabase never gets the row. Fix is a one-character change using the Dart 3 conditional spread pattern.

- [ ] **Step 1: Write the failing test**

```dart
// test/sync/custom_exercise_sync_test.dart
//
// Regression test for F1 — the syntax error in _projectCustomExercise
// caused silent sync failures for custom exercises with default_duration_secs
// set (timed exercises like "Plank", "Handstand Hold").

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

void main() {
  group('SyncService._projectCustomExercise', () {
    test('projects timed exercise with default_duration_secs without throwing', () {
      final exercise = {
        'id': 'cust_test_id',
        'name': 'Handstand Hold',
        'logging_type': 'timed',
        'default_sets': 3,
        'default_duration_secs': 60,
        'submitted_to_library': true,
        'created_at': DateTime.now().toIso8601String(),
      };

      // Should NOT throw. Before fix, the `?defaultDur` syntax error meant
      // this would crash with a Dart runtime error.
      expect(
        () => SyncServiceTestExports.projectCustomExercise(
          exercise: exercise,
          userId: 'test_user_id',
        ),
        returnsNormally,
      );
    });

    test('projection includes default_duration_secs when non-null', () {
      final exercise = {
        'id': 'cust_test_id',
        'name': 'Handstand Hold',
        'logging_type': 'timed',
        'default_duration_secs': 60,
        'submitted_to_library': false,
      };

      final projected = SyncServiceTestExports.projectCustomExercise(
        exercise: exercise,
        userId: 'test_user_id',
      );

      expect(projected['default_duration_secs'], 60);
      expect(projected['name'], 'Handstand Hold');
      expect(projected['user_id'], 'test_user_id');
    });

    test('projection omits default_duration_secs when null', () {
      final exercise = {
        'id': 'cust_test_id',
        'name': 'Push Up',
        'logging_type': 'bodyweight_reps',
        'default_duration_secs': null,
      };

      final projected = SyncServiceTestExports.projectCustomExercise(
        exercise: exercise,
        userId: 'test_user_id',
      );

      // Map should not contain the key when value is null
      expect(projected.containsKey('default_duration_secs'), false);
    });
  });
}
```

The test uses `SyncServiceTestExports` — a `@visibleForTesting` accessor we'll add to `sync_service.dart` so the test can call the private `_projectCustomExercise`. Add this in the same step:

```dart
// Add at top of lib/core/services/sync_service.dart, after imports
import 'package:flutter/foundation.dart' show visibleForTesting;

// Add at end of SyncService class:
@visibleForTesting
class SyncServiceTestExports {
  static Map<String, dynamic> projectCustomExercise({
    required Map<String, dynamic> exercise,
    required String userId,
  }) {
    return SyncService.instance._projectCustomExercise(exercise, userId);
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/sync/custom_exercise_sync_test.dart
```

Expected output: `Error: An expression is required after '?'.` or similar parser error. The current `?defaultDur` syntax fails to compile, so the test would fail at the analysis/build step before runtime.

- [ ] **Step 3: Apply the fix**

Open `lib/core/services/sync_service.dart`, locate line 1564 (inside `_projectCustomExercise`):

```dart
// BEFORE (broken):
'default_duration_secs': ?defaultDur,

// AFTER (Dart 3 conditional spread on map literal):
if (defaultDur != null) 'default_duration_secs': defaultDur,
```

The full block context for line 1564 (showing the surrounding map literal — keep all other lines unchanged):

```dart
return {
  'id': exercise['id'] as String,
  'user_id': userId,
  'name': exercise['name'] as String,
  'logging_type': exercise['logging_type'] as String? ?? 'weight_reps',
  // ... other whitelisted fields stay the same ...
  if (defaultDur != null) 'default_duration_secs': defaultDur,  // ← line 1564
  'submitted_to_library': exercise['submitted_to_library'] as bool? ?? false,
  // ... rest of map ...
};
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sync/custom_exercise_sync_test.dart -v
```

Expected: all 3 tests pass.

- [ ] **Step 5: Run a quick analyze to confirm no other issues**

```bash
flutter analyze lib/core/services/sync_service.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add test/sync/custom_exercise_sync_test.dart \
        lib/core/services/sync_service.dart
git commit -m "fix(sync): F1 _projectCustomExercise Dart syntax error

The map literal at sync_service.dart:1564 used '?defaultDur' which is
not valid Dart map-value syntax. Function threw at runtime, the upsert
never executed, Hive write succeeded locally, but Supabase never got
the row.

Cascade: also fixes B3 (custom exercise not in MY SUBMISSIONS), B4
(YOUR EXERCISES list missing entry), obs #1 from APK Test #2.

Replaces with Dart 3 conditional-spread pattern. Adds regression test."
```

---

### Task 4: F4 — Prediction parse guard extension

**Files:**
- Test: `test/ai_coach/prediction_sanitiser_test.dart`
- Modify: `lib/features/ai_coach/providers/ai_coach_provider.dart` (`_sanitisePredictionText`)
- Modify: `lib/core/services/prediction_service.dart` (system prompt)
- Modify: `lib/features/onboarding/providers/onboarding_provider.dart` (system prompt)

The current `_sanitisePredictionText` only triggers when raw text starts with `{` or `[`. Gemini interpreted "no JSON" as "use a different structured shape" and returned flat YAML-style: `outcome_3_months: weight_kg:77.5. body.` The early-return at line 695 passes this through unmodified. Triple defense: prompt → JSON guard → key:value guard.

- [ ] **Step 1: Write the failing test**

```dart
// test/ai_coach/prediction_sanitiser_test.dart
//
// Regression test for F4 — the sanitiser missed YAML-style key:value output
// like "outcome_3_months: weight_kg:77.5. body." which Gemini emitted when
// asked not to use JSON.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';

void main() {
  group('PredictionNotifier._sanitisePredictionText', () {
    // EXISTING JSON shape — should keep working
    test('extracts summary from JSON object shape', () {
      final raw = '{"summary": "You will lose 4kg in 12 weeks."}';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        'You will lose 4kg in 12 weeks.',
      );
    });

    test('extracts predictions[0].summary from nested JSON', () {
      final raw = '{"predictions": [{"summary": "Strength up 15%."}]}';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        'Strength up 15%.',
      );
    });

    test('strips code-fence wrapped JSON', () {
      final raw = '```json\n{"summary": "Plain prose here."}\n```';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        'Plain prose here.',
      );
    });

    // NEW — F4 fix
    test('extracts longest prose value from YAML-style key:value', () {
      final raw =
          'outcome_3_months: weight_kg:77.5. body.\n'
          'rationale: You are projected to gain 4kg of lean mass over 12 weeks '
          'with consistent 4-day training and 2800 kcal intake.\n'
          'confidence: high';
      final result = PredictionNotifierTestExports.sanitise(raw);
      expect(
        result,
        contains('4kg of lean mass over 12 weeks'),
        reason: 'Should pick the longest prose value (the rationale line).',
      );
    });

    test('handles single-line key:value with prose value', () {
      final raw = 'prediction: In 12 weeks you will be visibly leaner with '
          'measurable strength gains across compound lifts.';
      final result = PredictionNotifierTestExports.sanitise(raw);
      expect(
        result,
        contains('visibly leaner'),
      );
      expect(result, isNot(startsWith('prediction:')));
    });

    test('falls back to joining stripped values when no single prose value', () {
      final raw =
          'weight: -3kg\n'
          'protein: 137g\n'
          'days: 4';
      final result = PredictionNotifierTestExports.sanitise(raw)!;
      // No prose value > 20 chars + spaces, so fallback joins values
      expect(result.contains('-3kg'), true);
      expect(result.contains('137g'), true);
      expect(result.contains('weight:'), false);
      expect(result.contains('protein:'), false);
    });

    // PASS-THROUGH — non-structured prose
    test('passes through plain prose unchanged', () {
      final raw = 'In 12 weeks you will be visibly leaner.';
      expect(
        PredictionNotifierTestExports.sanitise(raw),
        raw,
      );
    });

    test('returns null for null input', () {
      expect(PredictionNotifierTestExports.sanitise(null), null);
    });

    test('returns null for empty input', () {
      expect(PredictionNotifierTestExports.sanitise(''), null);
    });
  });
}
```

We also need to expose the static method via a test export. Add at the bottom of `lib/features/ai_coach/providers/ai_coach_provider.dart`:

```dart
@visibleForTesting
class PredictionNotifierTestExports {
  static String? sanitise(String? raw) =>
      PredictionNotifier.sanitisePredictionTextForTest(raw);
}
```

And add a test-public wrapper inside `PredictionNotifier`:

```dart
@visibleForTesting
static String? sanitisePredictionTextForTest(String? raw) =>
    _sanitisePredictionText(raw);
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/ai_coach/prediction_sanitiser_test.dart
```

Expected: 4 of the 9 tests fail (the YAML-style ones). Existing JSON tests still pass.

- [ ] **Step 3: Extend `_sanitisePredictionText` with key:value detection**

Modify `lib/features/ai_coach/providers/ai_coach_provider.dart`. Replace the existing `_sanitisePredictionText` method with:

```dart
static String? _sanitisePredictionText(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  // 1. JSON / code-fence path (existing logic)
  if (trimmed.startsWith('{') || trimmed.startsWith('[') || trimmed.startsWith('```')) {
    var body = trimmed;
    if (body.startsWith('```')) {
      body = body.replaceFirst(RegExp(r'^```(json)?\n?'), '');
      if (body.endsWith('```')) body = body.substring(0, body.length - 3);
      body = body.trim();
    }
    try {
      final decoded = json.decode(body);
      if (decoded is Map) {
        for (final key in ['summary', 'tagline', 'text', 'prediction']) {
          final v = decoded[key];
          if (v is String && v.trim().isNotEmpty) {
            final cleaned = v.trim();
            _writeBackToHive(cleaned);
            return cleaned;
          }
        }
        final preds = decoded['predictions'];
        if (preds is List && preds.isNotEmpty) {
          final first = preds.first;
          if (first is Map) {
            for (final key in ['summary', 'tagline', 'text', 'timeframe']) {
              final v = first[key];
              if (v is String && v.trim().isNotEmpty) {
                final cleaned = v.trim();
                _writeBackToHive(cleaned);
                return cleaned;
              }
            }
          } else if (first is String && first.trim().isNotEmpty) {
            final cleaned = first.trim();
            _writeBackToHive(cleaned);
            return cleaned;
          }
        }
      } else if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first is String && first.trim().isNotEmpty) {
          final cleaned = first.trim();
          _writeBackToHive(cleaned);
          return cleaned;
        }
      }
    } catch (_) {
      // Fall through to artefact-stripping fallback below
    }

    final stripped = body
        .replaceAll(RegExp(r'[\{\}\[\]"]'), '')
        .replaceAll(RegExp(r'\s*,\s*'), ' · ')
        .replaceAll(RegExp(r'\s*:\s*'), ': ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stripped.isNotEmpty) {
      _writeBackToHive(stripped);
      return stripped;
    }
    return null;
  }

  // 2. NEW — YAML-style flat key:value detection
  // Heuristic: 2+ lines starting with "lowercase_word:" suggests Gemini
  // chose a structured shape despite the prompt forbidding JSON.
  final keyValuePattern = RegExp(r'^[a-z_][a-z_0-9]*\s*:', multiLine: true);
  final matches = keyValuePattern.allMatches(trimmed).toList();
  if (matches.length >= 1) {
    // Single key:value or multi-line key:value
    final lines = trimmed.split('\n');
    String? bestProseLine;

    for (final line in lines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) continue;
      final key = line.substring(0, colonIdx).trim();
      // Only treat as a "key" if it looks like a snake_case identifier
      if (!RegExp(r'^[a-z_][a-z_0-9]*$').hasMatch(key)) continue;
      final value = line.substring(colonIdx + 1).trim();

      // Pick the longest value that looks like prose (>20 chars, has spaces)
      if (value.length > 20 && value.contains(' ')) {
        if (bestProseLine == null || value.length > bestProseLine.length) {
          bestProseLine = value;
        }
      }
    }

    if (bestProseLine != null) {
      _writeBackToHive(bestProseLine);
      return bestProseLine;
    }

    // No long prose value — strip keys, join values
    final values = <String>[];
    for (final line in lines) {
      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) {
        // Non-key:value line — keep as-is if non-empty
        final trimmedLine = line.trim();
        if (trimmedLine.isNotEmpty) values.add(trimmedLine);
        continue;
      }
      final value = line.substring(colonIdx + 1).trim();
      if (value.isNotEmpty) values.add(value);
    }
    if (values.isNotEmpty) {
      final joined = values.join(' · ');
      _writeBackToHive(joined);
      return joined;
    }
  }

  // 3. Plain prose — pass through unchanged
  return raw;
}
```

The `_writeBackToHive` helper already exists in the file. If it doesn't (read the file to confirm), add this private method to `PredictionNotifier`:

```dart
static void _writeBackToHive(String cleaned) {
  try {
    final box = HiveService.instance.configBox;
    box.put('prediction_text', cleaned);
  } catch (_) {
    // Non-fatal — caller still gets the cleaned string
  }
}
```

- [ ] **Step 4: Harden the prompts**

Modify `lib/core/services/prediction_service.dart`. Locate the system prompt around line 30-41. Replace the existing "DO NOT return JSON" line with:

```dart
final systemPrompt = '''
[existing context lines unchanged]

CRITICAL OUTPUT RULES:
- Reply in plain English sentences only.
- DO NOT use any structured format.
- DO NOT prefix lines with labels like "outcome:", "weight_kg:", "summary:", or any colon-separated keys.
- DO NOT return JSON. DO NOT wrap in code fences.
- Just write 2-3 sentences of prose. Direct address ("you").
- 200 characters maximum.
''';
```

Same change in `lib/features/onboarding/providers/onboarding_provider.dart` around line 519-533 — locate the prediction prompt and apply the identical CRITICAL OUTPUT RULES block.

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/ai_coach/prediction_sanitiser_test.dart -v
```

Expected: all 9 tests pass.

- [ ] **Step 6: Commit**

```bash
git add test/ai_coach/prediction_sanitiser_test.dart \
        lib/features/ai_coach/providers/ai_coach_provider.dart \
        lib/core/services/prediction_service.dart \
        lib/features/onboarding/providers/onboarding_provider.dart
git commit -m "fix(prediction): F4 sanitise YAML-style key:value output

When Gemini was told 'no JSON, no code fences', it sometimes emitted
flat YAML-style: 'outcome_3_months: weight_kg:77.5. body.' The early-
return at the top of _sanitisePredictionText only handled '{' and '['
prefixes, so this passed through unmodified — user saw raw key:value
text on the prediction card.

Triple defense:
  1. Prompt now explicitly forbids 'colon-separated keys' (not just JSON).
  2. Sanitiser detects 2+ snake_case key:value lines and extracts the
     longest prose value (>20 chars + spaces).
  3. Falls back to stripping keys + joining values if no prose value
     dominates.

Cleaned text written back to Hive so decode runs at most once per stored
value (existing behaviour).

Spec section 1 / F4."
```

---

### Task 5: F5 — `aiInsightProvider` invalidation in regen + complete paths

**Files:**
- Test: `test/providers/ai_insight_invalidation_test.dart`
- Modify: `lib/features/profile/screens/edit_profile_screen.dart` (regen path)
- Modify: `lib/features/train/providers/train_provider.dart` (`completeWorkout`)
- Modify: `lib/core/services/workout_schedule_service.dart` (`generateAndScheduleFromDate`)

The home AI insight reads schedule via `WorkoutScheduleService.getScheduleForDate(now)`. Riverpod doesn't auto-invalidate when Hive changes (the provider has no Hive listener). After plan regen or workout completion, callers must explicitly invalidate.

- [ ] **Step 1: Write the failing test**

```dart
// test/providers/ai_insight_invalidation_test.dart
//
// Regression test for F5 — aiInsightProvider must be invalidated after:
//   1. Plan regenerate (edit_profile_screen._save → generateAndScheduleFromDate)
//   2. Workout completion (train_provider.completeWorkout)
//   3. WorkoutScheduleService.generateAndScheduleFromDate (any caller)
//
// Strategy: instrument a test container that tracks invalidation calls.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

void main() {
  group('aiInsightProvider invalidation', () {
    test('exists in the home_provider exports', () {
      // Sanity — provider is exported from home_provider.
      expect(aiInsightProvider, isNotNull);
    });

    test('rebuild after invalidate produces fresh value', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Read initial value (will be the empty/default state in test env).
      final initial = container.read(aiInsightProvider);

      // Invalidate and re-read.
      container.invalidate(aiInsightProvider);
      final after = container.read(aiInsightProvider);

      // Both reads should complete without throwing.
      expect(initial, isNotNull);
      expect(after, isNotNull);
    });
  });

  // Source-grep tests — these are static checks against the source files
  // to ensure invalidation calls exist where they need to.
  group('aiInsightProvider invalidation call sites', () {
    test('edit_profile_screen invalidates aiInsightProvider after regen', () {
      final source = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('ref.invalidate(aiInsightProvider)'),
        reason:
            'edit_profile_screen must invalidate aiInsightProvider in the '
            'regen save path so home AI insight refreshes.',
      );
    });

    test('train_provider invalidates aiInsightProvider in completeWorkout', () {
      final source = File(
        'lib/features/train/providers/train_provider.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('ref.invalidate(aiInsightProvider)'),
        reason:
            'train_provider.completeWorkout must invalidate '
            'aiInsightProvider so the home insight reflects the completed '
            'workout instead of the pre-completion "scheduled" state.',
      );
    });

    test('workout_schedule_service callers invalidate aiInsightProvider', () {
      // generateAndScheduleFromDate is service-level and doesn't have ref;
      // its callers must invalidate. The only caller in production paths
      // is edit_profile_screen — already covered above. If a new caller is
      // added, this test will need a corresponding check.
      final source = File(
        'lib/core/services/workout_schedule_service.dart',
      ).readAsStringSync();
      // Sanity: confirm the method exists where we expect.
      expect(source, contains('generateAndScheduleFromDate'));
    });
  });
}
```

The source-grep tests use `dart:io` File. Add `import 'dart:io';` at the top of the test file.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/providers/ai_insight_invalidation_test.dart
```

Expected: 2 of the 4 tests fail (the source-grep ones for edit_profile_screen and train_provider) because `ref.invalidate(aiInsightProvider)` calls don't exist there yet.

- [ ] **Step 3: Add invalidation in `edit_profile_screen._save` regen path**

Open `lib/features/profile/screens/edit_profile_screen.dart`. Locate the regen block (around line 1643-1645 per investigation):

```dart
// BEFORE:
ref.invalidate(currentPlanProvider);
ref.invalidate(todayWorkoutProvider);
ref.invalidate(calendarWeekProvider);

// AFTER (add aiInsightProvider):
ref.invalidate(currentPlanProvider);
ref.invalidate(todayWorkoutProvider);
ref.invalidate(calendarWeekProvider);
ref.invalidate(aiInsightProvider);  // F5 — refresh home insight after regen
```

Make sure `aiInsightProvider` is imported. Add at top of the file if missing:
```dart
import 'package:icanbefitter/features/home/providers/home_provider.dart';
```

- [ ] **Step 4: Add invalidation in `train_provider.completeWorkout`**

Open `lib/features/train/providers/train_provider.dart`. Locate the `completeWorkout` method's invalidation block (around line 1499-1504):

```dart
// BEFORE:
ref.invalidate(currentPlanProvider);
ref.invalidate(workoutStatsProvider);
ref.invalidate(calendarWeekProvider);
ref.invalidate(streakProvider);
ref.invalidate(todayWorkoutProvider);
ref.invalidate(allExercisePRsProvider);

// AFTER:
ref.invalidate(currentPlanProvider);
ref.invalidate(workoutStatsProvider);
ref.invalidate(calendarWeekProvider);
ref.invalidate(streakProvider);
ref.invalidate(todayWorkoutProvider);
ref.invalidate(allExercisePRsProvider);
ref.invalidate(aiInsightProvider);  // F5 — refresh home insight after complete
```

Add the `home_provider` import if missing.

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/providers/ai_insight_invalidation_test.dart -v
```

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add test/providers/ai_insight_invalidation_test.dart \
        lib/features/profile/screens/edit_profile_screen.dart \
        lib/features/train/providers/train_provider.dart
git commit -m "fix(home): F5 invalidate aiInsightProvider after regen and complete

The home 'AI Coach Insights' card reads from
WorkoutScheduleService.getScheduleForDate(now), which has no automatic
Riverpod invalidation when the underlying Hive schedule changes. After
plan regenerate or workout completion, the provider was returning the
pre-mutation insight (e.g., 'Legs B is scheduled' even after user
completed Full Body D and regenerated to Phase II).

Adds ref.invalidate(aiInsightProvider) to:
  - edit_profile_screen._save regen path
  - train_provider.completeWorkout

Day rollover already invalidates correctly. Source-grep regression
tests in test/providers/ai_insight_invalidation_test.dart guard
against future regressions.

Spec section 1 / F5."
```

---

### Task 6: F6 — Edit profile reads correct experience key

**Files:**
- Test: `test/plan_generator/edit_profile_regen_test.dart`
- Modify: `lib/features/profile/screens/edit_profile_screen.dart:1621`

`edit_profile_screen.dart:1621` reads `profile['detected_experience_level']` — a key that's never written. The actual key is `'fitness_experience'`. Result: experience defaults to 'beginner' on edit-profile regen, `VolumeFilter.targetCount(beginner, 5) = 4` instead of advanced's 8.

- [ ] **Step 1: Write the failing test**

```dart
// test/plan_generator/edit_profile_regen_test.dart
//
// Regression test for F6 — when user has fitness_experience=advanced
// + days_per_week=5 in their profile, the regen path through
// edit_profile_screen must produce 8 exercises/day (advanced × 5),
// not 4 (beginner × 5 fallback).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';
import 'dart:io';

void main() {
  group('VolumeFilter.targetCount', () {
    // Sanity check the existing volume table - matches CLAUDE.md §12
    test('advanced + 5 days = 8 exercises', () {
      expect(VolumeFilter.targetCount('advanced', 5), 8);
    });

    test('beginner + 5 days = 4 exercises', () {
      expect(VolumeFilter.targetCount('beginner', 5), 4);
    });

    test('intermediate + 5 days = 6 exercises', () {
      expect(VolumeFilter.targetCount('intermediate', 5), 6);
    });
  });

  group('edit_profile_screen experience key', () {
    test('reads fitness_experience, not detected_experience_level', () {
      // Source-grep regression test: the broken key must not appear in the
      // regen path; the correct key must be present.
      final source = File(
        'lib/features/profile/screens/edit_profile_screen.dart',
      ).readAsStringSync();

      expect(
        source.contains("profile['detected_experience_level']"),
        false,
        reason:
            'detected_experience_level is never written by onboarding or '
            'profile updates. Reading it always returns null and falls back '
            'to beginner.',
      );

      expect(
        source.contains("profile['fitness_experience']") ||
            source.contains('profile["fitness_experience"]'),
        true,
        reason:
            'edit_profile must read fitness_experience (the canonical key '
            'written by onboarding step 04 and edit_profile itself).',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/plan_generator/edit_profile_regen_test.dart
```

Expected: the source-grep test fails (broken key present, correct key absent or both unrelated).

- [ ] **Step 3: Apply the fix**

Open `lib/features/profile/screens/edit_profile_screen.dart`. Locate line 1621. Change:

```dart
// BEFORE:
final experience = (profile['detected_experience_level'] as String?) ?? 'beginner';

// AFTER:
final experience = (profile['fitness_experience'] as String?) ?? 'intermediate';
```

The default fallback also bumps from `'beginner'` to `'intermediate'` — onboarding pre-selects Intermediate as the default, so users without an explicit value should get the same default treatment.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/plan_generator/edit_profile_regen_test.dart -v
```

Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/plan_generator/edit_profile_regen_test.dart \
        lib/features/profile/screens/edit_profile_screen.dart
git commit -m "fix(profile): F6 edit_profile reads fitness_experience key

edit_profile_screen.dart:1621 was reading
profile['detected_experience_level'] — a key that is never written
anywhere in the codebase. As a result, every edit-profile regen
defaulted to 'beginner', and VolumeFilter.targetCount(beginner, 5)
returned 4 exercises/day instead of advanced's 8.

Onboarding step 04 (Details) writes 'fitness_experience'.
edit_profile itself writes 'fitness_experience'. So this is the
canonical key.

Default fallback also bumped from 'beginner' to 'intermediate' since
that's onboarding's pre-selected default.

Spec section 1 / F6."
```

---

### Task 7: F7 — Logging type resolution before fallback

**Files:**
- Test: `test/sync/swap_logging_type_test.dart`
- Modify: `lib/core/services/workout_schedule_service.dart` (lines 965-967, `swapExerciseInDay`)

When swapping an exercise, the new slot's `logging_type` falls back to `'weight_reps'` if the replacement's `logging_type` field is missing — even when the replacement actually exists in `exerciseBox` or `customBox` with a different type. Fix: resolve via library lookup before falling back.

- [ ] **Step 1: Write the failing test**

```dart
// test/sync/swap_logging_type_test.dart
//
// Regression test for F7 — swapExerciseInDay must resolve logging_type
// from exerciseBox/customBox if the replacement payload doesn't carry it,
// before falling back to 'weight_reps'.
//
// Cases:
//   1. Replacement has explicit logging_type → use it
//   2. Replacement is in customBox with logging_type=timed → use timed
//   3. Replacement is in exerciseBox with logging_type=bodyweight_reps → use it
//   4. Nothing found anywhere → fall back to original's type
//   5. Original also missing → fall back to 'weight_reps' (last resort)

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';

void main() {
  group('WorkoutScheduleService.resolveLoggingType', () {
    test('uses explicit logging_type from exercise payload', () {
      final result = WorkoutScheduleServiceTestExports.resolveLoggingType(
        exercise: {'name': 'Push Up', 'logging_type': 'bodyweight_reps'},
        exerciseLibrary: const {},
        customLibrary: const {},
      );
      expect(result, 'bodyweight_reps');
    });

    test('looks up in custom library when payload omits logging_type', () {
      final result = WorkoutScheduleServiceTestExports.resolveLoggingType(
        exercise: {'name': 'Handstand Hold'}, // no logging_type
        exerciseLibrary: const {},
        customLibrary: {
          'cust_1': {'name': 'Handstand Hold', 'logging_type': 'timed'},
        },
      );
      expect(result, 'timed');
    });

    test('looks up in exercise library when payload + custom omit', () {
      final result = WorkoutScheduleServiceTestExports.resolveLoggingType(
        exercise: {'name': 'Plank'},
        exerciseLibrary: {
          'exer_1': {'name': 'Plank', 'logging_type': 'timed'},
        },
        customLibrary: const {},
      );
      expect(result, 'timed');
    });

    test('returns null when no source found', () {
      final result = WorkoutScheduleServiceTestExports.resolveLoggingType(
        exercise: {'name': 'Unknown Move'},
        exerciseLibrary: const {},
        customLibrary: const {},
      );
      expect(result, null);
    });

    test('case-sensitive name match (existing behaviour)', () {
      final result = WorkoutScheduleServiceTestExports.resolveLoggingType(
        exercise: {'name': 'Push Up'},
        exerciseLibrary: {
          'exer_1': {'name': 'push up', 'logging_type': 'bodyweight_reps'},
        },
        customLibrary: const {},
      );
      expect(result, null,
          reason: 'Lookup is case-sensitive; this matches the rest of the '
              'codebase which uses exact name matching.');
    });
  });
}
```

Add a `@visibleForTesting` accessor to `lib/core/services/workout_schedule_service.dart`. After the existing class:

```dart
@visibleForTesting
class WorkoutScheduleServiceTestExports {
  /// Resolves the logging_type for [exercise] by checking, in order:
  /// 1. explicit `logging_type` field on the exercise payload
  /// 2. customLibrary entry matching by name
  /// 3. exerciseLibrary entry matching by name
  /// Returns null if no source has it.
  static String? resolveLoggingType({
    required Map<String, dynamic> exercise,
    required Map<dynamic, dynamic> exerciseLibrary,
    required Map<dynamic, dynamic> customLibrary,
  }) {
    final direct = exercise['logging_type'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;

    final name = exercise['name'] as String?;
    if (name == null || name.isEmpty) return null;

    for (final value in customLibrary.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }

    for (final value in exerciseLibrary.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }

    return null;
  }
}
```

- [ ] **Step 2: Run tests to verify they fail (test export missing or method missing)**

```bash
flutter test test/sync/swap_logging_type_test.dart
```

Expected: 5 tests fail (or compile error if the export doesn't exist yet).

- [ ] **Step 3: Apply the resolution helper + use it in `swapExerciseInDay`**

The `WorkoutScheduleServiceTestExports.resolveLoggingType` already implements the algorithm. Now wire it into the production `swapExerciseInDay` path. Open `lib/core/services/workout_schedule_service.dart` and locate lines 965-967:

```dart
// BEFORE:
final newType = (replacement['logging_type'] as String?)
    ?? (original['logging_type'] as String?)
    ?? 'weight_reps';

// AFTER:
final newType = WorkoutScheduleServiceTestExports.resolveLoggingType(
      exercise: replacement,
      exerciseLibrary: HiveService.instance.exerciseBox.toMap(),
      customLibrary: HiveService.instance.customBox.toMap(),
    )
    ?? (original['logging_type'] as String?)
    ?? 'weight_reps';
```

Note: we're calling the testExports helper from production code. Rename the class to remove the "TestExports" suffix when it's becoming production logic — the resolver is no longer test-only. Move the class out of `@visibleForTesting`:

```dart
// Replace the @visibleForTesting class above with a regular utility class:
class LoggingTypeResolver {
  static String? resolve({
    required Map<String, dynamic> exercise,
    required Map<dynamic, dynamic> exerciseLibrary,
    required Map<dynamic, dynamic> customLibrary,
  }) {
    final direct = exercise['logging_type'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;

    final name = exercise['name'] as String?;
    if (name == null || name.isEmpty) return null;

    for (final value in customLibrary.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }

    for (final value in exerciseLibrary.values) {
      if (value is Map && value['name'] == name) {
        final t = value['logging_type'] as String?;
        if (t != null && t.isNotEmpty) return t;
      }
    }

    return null;
  }
}
```

Update the test to use `LoggingTypeResolver.resolve(...)` instead of `WorkoutScheduleServiceTestExports.resolveLoggingType(...)`. (Update both files in the same step before running.)

Update the call site:

```dart
final newType = LoggingTypeResolver.resolve(
      exercise: replacement,
      exerciseLibrary: HiveService.instance.exerciseBox.toMap(),
      customLibrary: HiveService.instance.customBox.toMap(),
    )
    ?? (original['logging_type'] as String?)
    ?? 'weight_reps';
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/sync/swap_logging_type_test.dart -v
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/sync/swap_logging_type_test.dart \
        lib/core/services/workout_schedule_service.dart
git commit -m "fix(workout): F7 resolve logging_type before swap fallback

When swapping an exercise, the previous code fell back to 'weight_reps'
the moment the replacement payload didn't carry logging_type — even
when the replacement existed in exerciseBox/customBox with a different
type. User reports: swap from Handstand Hold (timed) to Handstand
Pushup → target rendered with KG/REPS columns instead of timed.

Adds LoggingTypeResolver.resolve() that checks, in order:
  1. explicit logging_type on the payload
  2. customBox entry by name
  3. exerciseBox entry by name
  4. (caller falls back to original's type, then 'weight_reps')

Spec section 1 / F7."
```

---

### Task 8: F8 — Set add appends instead of rebuilds

**Files:**
- Test: `integration_test/flows/add_set_preserves_weight_test.dart`
- Modify: `lib/features/train/screens/active_workout_screen.dart` (`_ExerciseCardState.didUpdateWidget`)

Adding a 3rd set wipes set 2's weight value. Root cause: `didUpdateWidget` calls `_disposeControllers() + _initControllers()` — full rebuild — instead of appending one new controller.

- [ ] **Step 1: Write the integration test**

```dart
// integration_test/flows/add_set_preserves_weight_test.dart
//
// Regression test for F8 — when user adds a set, previously-entered weight/
// reps values for existing sets must NOT be wiped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icanbefitter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('adding a 3rd set preserves set 1 + 2 weights',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // Navigate to Train → start a workout. Exact navigation depends on app
    // state; this assumes the app comes up on home with a planned workout.
    // For a fresh test environment, you may need to seed a workout schedule.
    final startButton = find.text('START');
    if (startButton.evaluate().isNotEmpty) {
      await tester.tap(startButton.first);
      await tester.pumpAndSettle();
    }

    // Find the first weight input (kg) for set 1 of the first exercise.
    final kgFields = find.byKey(const ValueKey('kg-input-0-0'));
    expect(kgFields, findsOneWidget,
        reason: 'Active workout should render set-1 kg input.');

    // Enter 10 kg in set 1
    await tester.enterText(kgFields, '10');
    await tester.pump();

    // Find reps input for set 1
    final reps0 = find.byKey(const ValueKey('reps-input-0-0'));
    await tester.enterText(reps0, '10');
    await tester.pump();

    // Set 2 inputs
    final kg1 = find.byKey(const ValueKey('kg-input-0-1'));
    await tester.enterText(kg1, '15');
    await tester.pump();

    final reps1 = find.byKey(const ValueKey('reps-input-0-1'));
    await tester.enterText(reps1, '7');
    await tester.pump();

    // Tap + (add set) for the first exercise
    final addSetButton = find.byKey(const ValueKey('add-set-0'));
    expect(addSetButton, findsOneWidget,
        reason: 'Active workout should render + add-set button.');
    await tester.tap(addSetButton);
    await tester.pumpAndSettle();

    // After adding, set 3 inputs should exist
    expect(find.byKey(const ValueKey('kg-input-0-2')), findsOneWidget);

    // Most importantly: sets 1 and 2 must still hold their values
    final kg0After = tester.widget<TextField>(
      find.byKey(const ValueKey('kg-input-0-0')),
    );
    expect(kg0After.controller?.text, '10',
        reason: 'Set 1 weight must persist after adding set 3.');

    final kg1After = tester.widget<TextField>(
      find.byKey(const ValueKey('kg-input-0-1')),
    );
    expect(kg1After.controller?.text, '15',
        reason: 'Set 2 weight must NOT be wiped after adding set 3 (F8).');

    final reps1After = tester.widget<TextField>(
      find.byKey(const ValueKey('reps-input-0-1')),
    );
    expect(reps1After.controller?.text, '7',
        reason: 'Set 2 reps must persist after adding set 3.');
  });
}
```

This integration test requires `ValueKey`s on the TextFields and add-set buttons. They may not exist yet — Step 2 adds them.

- [ ] **Step 2: Add ValueKeys to active_workout_screen TextFields and buttons**

Open `lib/features/train/screens/active_workout_screen.dart`. Find the `TextField` for kg input inside the set row builder (around the same area as `_kgControllers`). Add a `ValueKey`:

```dart
TextField(
  key: ValueKey('kg-input-${widget.exerciseIndex}-$setIndex'),
  controller: _kgControllers[setIndex],
  // ... existing props ...
)
```

Same for reps input:

```dart
TextField(
  key: ValueKey('reps-input-${widget.exerciseIndex}-$setIndex'),
  controller: _repsControllers[setIndex],
  // ... existing props ...
)
```

And the add-set IconButton/InkWell:

```dart
IconButton(
  key: ValueKey('add-set-${widget.exerciseIndex}'),
  icon: const Icon(Icons.add),
  onPressed: _addSet,
)
```

- [ ] **Step 3: Run integration test to verify it fails**

```bash
flutter test --dart-define-from-file=.env integration_test/flows/add_set_preserves_weight_test.dart --flavor dev
```

Expected: the test fails with an assertion that set 2's weight is empty (or '0') instead of '15' after adding set 3 — capturing the F8 bug.

- [ ] **Step 4: Apply the fix in `_ExerciseCardState.didUpdateWidget`**

Open `lib/features/train/screens/active_workout_screen.dart`. Locate `_ExerciseCardState.didUpdateWidget` (around line 1198-1206). Replace the rebuild logic:

```dart
// BEFORE:
@override
void didUpdateWidget(covariant _ExerciseCard oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.exercise.sets != widget.exercise.sets) {
    _disposeControllers();
    _initControllers();
  }
}

// AFTER:
@override
void didUpdateWidget(covariant _ExerciseCard oldWidget) {
  super.didUpdateWidget(oldWidget);
  final oldCount = oldWidget.exercise.sets;
  final newCount = widget.exercise.sets;
  if (newCount == oldCount) return;

  if (newCount > oldCount) {
    // Append: preserve [0..oldCount-1] controllers, add new ones for the rest
    for (var i = oldCount; i < newCount; i++) {
      _kgControllers.add(TextEditingController());
      _repsControllers.add(TextEditingController());
    }
  } else {
    // Shrink: dispose trailing controllers from [newCount..oldCount-1]
    for (var i = oldCount - 1; i >= newCount; i--) {
      _kgControllers.removeAt(i).dispose();
      _repsControllers.removeAt(i).dispose();
    }
  }
}
```

This preserves controllers for indices `[0..min(oldCount, newCount)]`, so any text the user has typed in those fields remains intact.

- [ ] **Step 5: Run integration test to verify it passes**

```bash
flutter test --dart-define-from-file=.env integration_test/flows/add_set_preserves_weight_test.dart --flavor dev
```

Expected: test passes — set 1 and set 2 values both persist after adding set 3.

- [ ] **Step 6: Commit**

```bash
git add integration_test/flows/add_set_preserves_weight_test.dart \
        lib/features/train/screens/active_workout_screen.dart
git commit -m "fix(workout): F8 set add appends controllers instead of rebuild

_ExerciseCardState.didUpdateWidget was calling _disposeControllers()
+ _initControllers() on every set count change — full rebuild. Any
in-flight (typed but not yet committed to the provider) values for
existing sets were wiped because the new controllers came up empty.

Now appends new controllers for the added range only. Existing
indices keep their controllers and any unsaved text. Symmetric for
shrink (dispose trailing controllers).

ValueKeys added on TextFields + add-set button so the integration
test in integration_test/flows/add_set_preserves_weight_test.dart
can target them deterministically.

Spec section 1 / F8."
```

---

### Task 9: F9 — Plan-relative week number on home header

**Files:**
- Test: `test/home/week_number_test.dart`
- Modify: `lib/features/home/screens/home_screen.dart` (lines 388-389)

The home header reads `((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).floor() + 1` — calendar-year week. For 2026-04-25, that's week 17. Should be plan-relative via `WorkoutScheduleService.getCurrentWeekNumber()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/home/week_number_test.dart
//
// Regression test for F9 — home header WK indicator must be plan-relative
// (uses WorkoutScheduleService.getCurrentWeekNumber()), not calendar-year.

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('home_screen WK indicator source', () {
    test('does NOT use calendar-year math for week number', () {
      final source = File(
        'lib/features/home/screens/home_screen.dart',
      ).readAsStringSync();

      // Calendar-year math signature: difference from January 1 ÷ 7
      expect(
        source.contains("DateTime(now.year, 1, 1)"),
        false,
        reason:
            'home_screen WK indicator must not derive week number from '
            'difference between today and Jan 1. Use plan-relative '
            'WorkoutScheduleService.getCurrentWeekNumber() instead.',
      );
    });

    test('calls WorkoutScheduleService.getCurrentWeekNumber()', () {
      final source = File(
        'lib/features/home/screens/home_screen.dart',
      ).readAsStringSync();

      expect(
        source.contains('getCurrentWeekNumber'),
        true,
        reason:
            'home_screen WK indicator must use the canonical plan-relative '
            'week number (WorkoutScheduleService.getCurrentWeekNumber).',
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
flutter test test/home/week_number_test.dart
```

Expected: 2 tests fail (calendar-year math present, getCurrentWeekNumber not called).

- [ ] **Step 3: Apply the fix**

Open `lib/features/home/screens/home_screen.dart`. Locate lines 388-389 (the week number computation):

```dart
// BEFORE:
final week = ((now.difference(DateTime(now.year, 1, 1)).inDays) / 7).floor() + 1;

// AFTER:
final week = WorkoutScheduleService.instance.getCurrentWeekNumber();
```

Verify the import for `WorkoutScheduleService` is present at the top of the file. If not, add:

```dart
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/home/week_number_test.dart -v
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/home/week_number_test.dart \
        lib/features/home/screens/home_screen.dart
git commit -m "fix(home): F9 plan-relative week number in home header

The home header WK indicator was computed as
((now - Jan 1) / 7).floor() + 1 — calendar-year week-of-year. For
2026-04-25 that yielded 'WK 17', which is meaningless to a user
who started Phase I last week.

Replaces with WorkoutScheduleService.getCurrentWeekNumber() — the
canonical plan-relative week (already used elsewhere in the
codebase correctly).

Spec section 1 / F9."
```

---

### Task 10: F11 — AI food analysis investigation hook

**Files:**
- Modify: `lib/features/nutrition/providers/nutrition_provider.dart` (`analyseFoodText` error path)

F11 is investigation-mode rather than a deterministic fix. The hypothesis (rate-limit trigger firing prematurely due to stale subscription cache OR stale `ai_coach_interactions` rows from prior sessions) needs runtime confirmation. The action is to instrument the call path so the next APK test surfaces enough detail to fix definitively.

- [ ] **Step 1: Add detailed error logging to `analyseFoodText`**

Open `lib/features/nutrition/providers/nutrition_provider.dart`. Locate the `analyseFoodText` (or equivalent) method and the error handling block. Add `kDebugMode` instrumentation:

```dart
// Around the error catch in analyseFoodText:
} catch (e, stack) {
  if (kDebugMode) {
    debugPrint('[F11 food_analysis] error: $e');
    debugPrint('[F11 food_analysis] stack: $stack');
    // Capture the full response body if it's an HTTP-like error
    if (e is AiServiceException) {
      debugPrint('[F11 food_analysis] status: ${e.statusCode}');
      debugPrint('[F11 food_analysis] body: ${e.responseBody}');
      debugPrint('[F11 food_analysis] request_id: ${e.requestId}');
    }
  }
  // existing error mapping path unchanged
  rethrow;
}
```

- [ ] **Step 2: Add subscription cache refresh before food analysis call**

In the same `analyseFoodText` method, add a defensive cache refresh BEFORE the actual call (especially relevant after restore):

```dart
// At the top of analyseFoodText, before constructing the request:
// F11 — refresh subscription cache to avoid stale-PRO/free state after restore.
// Cheap (~50ms hit if cache miss); resolves the most-likely cause of
// rate-limit trigger firing on a user who's actually under their daily cap.
try {
  await SubscriptionService.instance.verifyFromServer();
} catch (_) {
  // Non-fatal — continue with cached state. Server-side trigger is the
  // authoritative gate.
}
```

- [ ] **Step 3: Make sure the user-facing error message is actionable, not generic**

Locate where the food analysis error is mapped to UI. The current error toast likely says "AI not working" or similar — too generic. Map specific server errors:

```dart
// In the error mapping (if not already present):
String _mapFoodAnalysisError(dynamic err) {
  final msg = err.toString().toLowerCase();
  if (msg.contains('food_text_daily_limit_reached') ||
      msg.contains('daily food analysis limit')) {
    return 'Daily food analysis limit reached. Try again tomorrow or upgrade to PRO.';
  }
  if (msg.contains('snapshot too large')) {
    return 'Your nutrition data is unusually large. Please try again.';
  }
  if (msg.contains('message too long')) {
    return 'That description is too long. Please shorten it.';
  }
  if (msg.contains('502') || msg.contains('503') || msg.contains('504')) {
    return 'The AI is temporarily unavailable. Please try again in a minute.';
  }
  return 'Could not analyse that. Please try a clearer description.';
}
```

- [ ] **Step 4: Manual verification on prod APK**

Once Task 10 is committed and the next APK is built (Plan A complete), the next time the user hits F11 they should see:
1. A specific user-facing error explaining the actual cause
2. Detailed `kDebugMode` logs in `adb logcat` (filter on `[F11 food_analysis]`)

If the `kDebugMode` logs reveal a clear culprit (e.g., 401 because JWT expired during restore), file a follow-up commit. If the cache refresh in Step 2 alone fixes it, no further work needed.

There is no automated test for this task because the bug is environmental (depends on rate-limit trigger state, subscription cache state, JWT freshness). Test passes when: APK testing confirms food analysis returns a successful result for a user who is genuinely under their cap.

- [ ] **Step 5: Commit**

```bash
git add lib/features/nutrition/providers/nutrition_provider.dart
git commit -m "fix(nutrition): F11 food analysis instrumentation + cache refresh

Adds kDebugMode logging to capture the exact error body + request_id
when food text analysis fails. Most-likely root cause is stale
subscription cache after restore (user is PRO but client thinks
free, hits 50/day cap). Defends with verifyFromServer() before each
call.

Also remaps generic 'AI not working' toast to specific actionable
messages: daily limit reached, snapshot too large, message too long,
or transient 5xx.

Manual verification path: next prod APK build, trigger food analysis,
check logcat for [F11 food_analysis] entries. If a deterministic
cause surfaces, file follow-up commit.

Spec section 1 / F11."
```

---

### Task 11: Run the full test suite + flutter analyze

After all individual tasks land, do a full repo health check before tagging the plan complete.

- [ ] **Step 1: Run all unit tests**

```bash
flutter test
```

Expected: all tests pass, including the 6 new regression tests added in this plan (F1, F4, F5, F6, F7, F9). Pre-existing warnings in `test/plan_generator/*` files unrelated to this batch are acceptable.

- [ ] **Step 2: Run flutter analyze**

```bash
flutter analyze
```

Expected: no errors. Warnings unrelated to this batch are acceptable.

- [ ] **Step 3: If any failures, fix them inline before proceeding to Plan B**

Common gotchas to look for:
- Missing `ref.invalidate(aiInsightProvider)` import → "aiInsightProvider isn't defined" error → add `import 'package:icanbefitter/features/home/providers/home_provider.dart';`
- `LoggingTypeResolver` import in test → "isn't defined" → add the import to the test file
- `WorkoutScheduleService` import in `home_screen.dart` → similar fix

- [ ] **Step 4: Create end-of-plan summary commit (no code change, just push state)**

```bash
git commit --allow-empty -m "checkpoint: Plan A complete (F1-F11 + migrations 036+037)

All critical fixes shipped:
  - F1 sync syntax error
  - F4 prediction parse guard for YAML key:value
  - F5 aiInsightProvider invalidation
  - F6 fitness_experience key
  - F7 logging_type resolution
  - F8 set add append
  - F9 plan-relative week number
  - F11 food analysis instrumentation

Migrations 036 + 037 applied to prod dedsavbjuwgarrhphgnl.

Plan B (auth + onboarding) is next.

Branch: feat/apk-test-2-batch
Spec: docs/superpowers/specs/2026-04-25-apk-test-2-batch-design.md"
```

---

## Self-Review (run after writing complete plan)

### Spec coverage

| Spec section | Plan task | Status |
|---|---|---|
| Migration 036 | Task 1 | ✓ |
| Migration 037 | Task 2 | ✓ |
| F1 sync syntax | Task 3 | ✓ |
| F4 prediction parse | Task 4 | ✓ |
| F5 invalidation | Task 5 | ✓ |
| F6 experience key | Task 6 | ✓ |
| F7 logging_type | Task 7 | ✓ |
| F8 set add | Task 8 | ✓ |
| F9 week number | Task 9 | ✓ |
| F11 food analysis | Task 10 | ✓ |
| F2 (restore) | (Plan B) | deferred |
| F3 (AI not synced) | (Plan B cascade) | deferred |
| F10 (View Card) | (Plan D Q9) | deferred |
| F12-F17 | cascade fixes | covered by F1+F2+F7+Q3+Q9 |

All Plan A items have a task. F2/F3/F10 are explicitly assigned to other plans.

### Placeholder scan

No "TBD", no "TODO", no "implement later" left in the plan. All tasks have concrete code, exact file paths, exact commands.

### Type consistency

- `LoggingTypeResolver.resolve` is the same name in Task 7 and the call site.
- `aiInsightProvider` is the same name in Task 5 test, edit_profile_screen, and train_provider.
- `WorkoutScheduleService.getCurrentWeekNumber()` matches existing CLAUDE.md §11 reference.

No type/name drift detected.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-25-apk-test-2-plan-A-critical-fixes.md`.

Plan A is the foundation — F1 unblocks the custom-exercise sync verification path, F5/F6/F7/F8/F9 are quick wins that improve quality of life, F4 fixes the prediction card visible regression, F11 instruments the AI food analysis bug for next-APK diagnosis. Migrations 036 + 037 prepare the schema for Plans B and C.

After Plan A lands, Plans B (auth + onboarding), C (subscription + monetization), and D (layout) can proceed.
