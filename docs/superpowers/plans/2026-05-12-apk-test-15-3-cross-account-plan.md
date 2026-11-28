# APK Test #15.3 — Cross-Account Riverpod + 2 Adjacent Gaps (extension)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix Bug 5 (cross-account Riverpod state cache leak — surfaced by founder seeing Upendra's profile data on sumitt@gmail.com Edit Profile) + Bug 6 (EditWorkoutLogSheet reads legacy `sets_detail`) + Bug 7 (cloud `workout_log_exercises.duration_seconds` never populated). Fold into versionCode 1.0.0+23 — no further bump needed.

**Architecture:** Per-bug isolated commits with diagnose-docs + regression tests. Per `feedback_no_deferrals.md` no defer. Per `feedback_writer_reader_field_drift_recurring.md` audit all consumers in same PR.

**Scope locked with founder 2026-05-12:**
- Bug 5 — **Option B**: single `authUserIdTokenProvider` + 56 user-scoped Notifier `build()` bodies add `ref.watch(authUserIdTokenProvider)` + source-grep contract test
- Bug 7 — **populate** the dead cloud column, not drop

---

## Pre-flight

- [ ] **Step 0.1:** Verify clean tree + on main + no drift

```bash
cd "C:/Upendra/Claude Code/Fitness App"
git status --porcelain  # expect empty
git rev-parse HEAD     # expect 4a1fde1 (or newer)
git fetch origin && git pull --ff-only
```

- [ ] **Step 0.2:** Create feature branch

```bash
git checkout -b feat/apk-test-15-3-cross-account
```

---

## Bug 5 (c4055a): Cross-account Riverpod state cache leak

**Diagnosis:** `UserProfileNotifier.build()` (and 55 other user-scoped notifiers) reads from `UserRepository.getProfile()` / Hive boxes / Supabase user-scoped queries ONCE per provider lifetime. None watch an auth state source. On signOut → signUp, Hive boxes correctly switch to the new user's namespaced files (Test #15.1 / Bug C fix), but Riverpod provider state stays stale — UI sees previous user's cached data.

**Audit reference:** All 47 vulnerable + 9 partially-protected providers enumerated in conversation. Audit inventory captured in diagnose-doc.

### Files

**Create:**
- `lib/features/auth/providers/auth_invalidation_provider.dart` — the new `authUserIdTokenProvider`
- `test/contracts/auth_invalidation_contract_test.dart` — source-grep test
- `test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart` — behavioral test
- `docs/diagnoses/2026-05-12-cross-account-riverpod-cache-c4055a.md`

**Modify (~30 files, one-line `ref.watch(authUserIdTokenProvider)` add):**
- `lib/features/profile/providers/profile_provider.dart` (`userProfileProvider`, `userStatsProvider`, `subscriptionInfoProvider`, `biometricProvider`, `progressPhotosProvider`, `usageWeeksProvider`, `firstReportViewedProvider`)
- `lib/features/profile/providers/profile_completeness_provider.dart`
- `lib/features/profile/providers/weekly_report_data_provider.dart`
- `lib/features/profile/providers/notifications_inbox_provider.dart`
- `lib/features/profile/providers/promotion_history_provider.dart`
- `lib/features/profile/providers/referral_eligibility_provider.dart`
- `lib/features/home/providers/home_provider.dart` (12+ providers)
- `lib/features/train/providers/train_provider.dart` (5+ providers)
- `lib/features/train/providers/preview_plan_provider.dart`
- `lib/features/train/providers/video_render_provider.dart`
- `lib/features/nutrition/providers/diet_plan_provider.dart`
- `lib/features/nutrition/providers/nutrition_provider.dart` (12+ providers)
- `lib/features/ai_coach/providers/ai_coach_provider.dart` (8+ providers)
- `lib/features/ai_coach/providers/pending_tool_intents_provider.dart`
- `lib/features/ai_coach/widgets/insight_card.dart` (`topInsightProvider`)
- `lib/features/onboarding/providers/onboarding_provider.dart`

### Steps

- [ ] **Step 1.1:** Write the diagnose-doc with full audit inventory (all 56 providers tabulated). Validate via `dart run scripts/validate_diagnose_doc.dart`.

- [ ] **Step 1.2:** Create the auth invalidation token provider.

`lib/features/auth/providers/auth_invalidation_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Token provider whose value changes on every auth state change.
///
/// Every user-scoped provider MUST `ref.watch(authUserIdTokenProvider)`
/// in its `build()` body. When the user signs in / out / up, this
/// provider re-emits, triggering a rebuild of every downstream notifier
/// → the rebuild re-reads from now-correctly-namespaced Hive boxes
/// (via HiveUserSession.openForUser) and produces fresh state.
///
/// Closes APK Test #15.3 / Bug 5 (c4055a). Pinned by
/// test/contracts/auth_invalidation_contract_test.dart — any new
/// provider that reads user-scoped Hive / Repository / Supabase MUST
/// add the watch, or the source-grep test fails.
///
/// Anonymous sessions resolve to `'<anon>'` so providers re-emit on
/// sign-out too (state goes from `<id>` to `<anon>`).
final authUserIdTokenProvider = Provider<String>((ref) {
  final user = ref.watch(currentUserProvider);
  return user?.id ?? '<anon>';
});
```

- [ ] **Step 1.3:** Write the SOURCE-GREP contract test.

`test/contracts/auth_invalidation_contract_test.dart`:

```dart
// Source-grep — no Hive bootstrap needed. Walks lib/features/*/providers/
// and asserts every file containing user-scoped reads also imports +
// watches authUserIdTokenProvider.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every user-scoped provider watches authUserIdTokenProvider (Bug c4055a)', () {
    final providerDir = Directory('lib/features');
    final userScopedPattern = RegExp(
      r'UserRepository\.|WorkoutRepository\.|NutritionRepository\.|AiCoachRepository\.|'
      r'HiveService\.instance\.(user|workout|nutrition|health|custom|coach|sync)Box|'
      r'MigratedKey\.|SubscriptionService\.|WaterTargetService\.|'
      r"\.from\('progress_photos'\)|\.from\('rank_promotions'\)|\.from\('referral_codes'\)|"
      r"\.from\('video_renders'\)",
    );
    final watchPattern = RegExp(r'ref\.watch\(authUserIdTokenProvider\)');
    final exemptions = <String>{
      // Pre-auth crossing surfaces — intentionally shared, per CLAUDE.md §15.
      'lib/features/auth/providers/referral_code_stash_provider.dart',
      // Auth provider itself + invalidation provider must not self-watch.
      'lib/features/auth/providers/auth_provider.dart',
      'lib/features/auth/providers/auth_invalidation_provider.dart',
    };

    final violations = <String>[];
    for (final entity in providerDir.listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart')) continue;
      if (exemptions.contains(entity.path.replaceAll(r'\', '/'))) continue;
      final content = entity.readAsStringSync();
      // Only check files that DECLARE a provider/notifier
      if (!content.contains('Provider<') &&
          !content.contains('extends Notifier<') &&
          !content.contains('extends AsyncNotifier<') &&
          !content.contains('extends StateNotifier<')) continue;
      // Only check files that READ user-scoped data
      if (!userScopedPattern.hasMatch(content)) continue;
      // Must watch the auth token provider
      if (!watchPattern.hasMatch(content)) {
        violations.add(entity.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'These provider files read user-scoped data but do not '
          'ref.watch(authUserIdTokenProvider). On signOut+signUp their '
          'cached state leaks the previous user\'s data into the new '
          'session. Add ref.watch(authUserIdTokenProvider) at the top '
          'of each Notifier\'s build() body, or add the file path to '
          'the exemptions set with a justification comment.\n\n'
          'Violations:\n${violations.join("\n")}',
    );
  });
}
```

- [ ] **Step 1.4:** Run the failing contract test (expected to fail with all 56 files listed).

```bash
flutter test test/contracts/auth_invalidation_contract_test.dart
```

- [ ] **Step 1.5:** Apply the watch to every Notifier `build()` in the audit. For Notifier-extending classes:

```dart
@override
Map<String, dynamic> build() {
  ref.watch(authUserIdTokenProvider);  // c4055a — rebuild on auth change
  return UserRepository.instance.getProfile() ?? {};
}
```

For `Provider<T>((ref) { ... })` style:

```dart
final somethingProvider = Provider<X>((ref) {
  ref.watch(authUserIdTokenProvider);  // c4055a — rebuild on auth change
  return ...;
});
```

For `StreamProvider` / `FutureProvider`: same pattern — `ref.watch(authUserIdTokenProvider)` at top of builder.

Import statement to add in each file:
```dart
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
```

**For PARTIALLY PROTECTED providers** (the 9 that have a write-hook): add the watch anyway. Belt-and-suspenders.

- [ ] **Step 1.6:** Re-run contract test → must PASS.

- [ ] **Step 1.7:** Write the BEHAVIORAL test.

`test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart`:

```dart
// Verify userProfileProvider re-reads from Hive when authUserIdTokenProvider changes.
// Tests two flows:
//   1. user A's data cached → user B signs in → provider rebuilds → user B's data
//   2. sign-out (token becomes '<anon>') → provider rebuilds → empty/null
//
// Uses overrides on currentUserProvider to simulate auth state changes
// without needing a live Supabase session.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

// (Hive test bootstrap omitted — copy from existing contract tests)

void main() {
  // Stand-in for the real currentUserProvider for test fixturing
  late ProviderContainer container;

  test('userProfileProvider rebuilds when authUserIdTokenProvider changes (Bug c4055a)',
      () async {
    // Override currentUserProvider so we can swap users without Supabase
    final userIdNotifier = ValueNotifier<String?>('user-A');
    container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) {
        ref.listen(StreamProvider((_) => userIdNotifier.toStream()),
            (_, __) => ref.invalidateSelf());
        return _MockUser(userIdNotifier.value);
      }),
    ]);
    addTearDown(container.dispose);

    // Stage user A's data
    await HiveService.instance.userBox.put('profile', {
      'id': 'user-A',
      'full_name': 'Upendra',
      'height_cm': 174.0,
    });
    expect(container.read(userProfileProvider)['full_name'], 'Upendra');

    // Switch to user B — simulating sign-out + sign-in
    userIdNotifier.value = 'user-B';
    // ... reopen Hive box namespaced to user B, put user B's data
    await HiveService.instance.userBox.put('profile', {
      'id': 'user-B',
      'full_name': 'Sumit',
      'height_cm': 175.0,
    });

    // Provider must have rebuilt — Sumit's data, not Upendra's.
    expect(container.read(userProfileProvider)['full_name'], 'Sumit',
        reason: 'Bug c4055a: userProfileProvider did not rebuild on auth change');
  });
}
```

(May need to factor a test helper / refine the override pattern based on how `currentUserProvider` is implemented. If too tangled, the source-grep test alone is sufficient — note it in the report.)

- [ ] **Step 1.8:** Run full suite + analyze.

```bash
flutter analyze --no-fatal-infos
flutter test
```

- [ ] **Step 1.9:** Commit.

```bash
git add lib/features/auth/providers/auth_invalidation_provider.dart \
        lib/features/profile/providers/ \
        lib/features/home/providers/ \
        lib/features/train/providers/ \
        lib/features/nutrition/providers/ \
        lib/features/ai_coach/providers/ \
        lib/features/ai_coach/widgets/insight_card.dart \
        lib/features/onboarding/providers/onboarding_provider.dart \
        test/contracts/auth_invalidation_contract_test.dart \
        test/contracts/user_scoped_provider_rebuilds_on_auth_change_test.dart \
        docs/diagnoses/2026-05-12-cross-account-riverpod-cache-c4055a.md

git commit -m "fix(state): user-scoped providers watch authUserIdTokenProvider

Bug c4055a — cross-account Riverpod state cache leak. After signOut+signUp
on the same app session, Hive boxes correctly switched to the new user's
namespaced files via HiveUserSession.openForUser (Test #15.1 / Bug C fix),
but Riverpod provider state stayed stale because NO Notifier build() body
watched any auth state source. UI saw previous user's cached profile.

Founder reproduced 2026-05-12 morning: signed up as sumitt@gmail.com on a
session previously holding Upendra. Edit Profile screen showed Upendra's
174cm/77.8kg/1988-06-30 even though cloud user_profile for sumitt had
175cm/75kg/2001-01-01.

Audit found 47 VULNERABLE + 9 PARTIALLY-PROTECTED providers. Single
canonical fix: new authUserIdTokenProvider exposes current user.id (or
'<anon>'). Every user-scoped provider's build() adds ref.watch(authUserIdTokenProvider).
On auth change, the token re-emits and every downstream provider rebuilds
against the now-correctly-namespaced Hive.

Source-grep contract test in test/contracts/auth_invalidation_contract_test
walks lib/features/*/providers/ and fails on any provider file that reads
UserRepository/HiveService.user*Box/MigratedKey/SubscriptionService/
Supabase user-filtered tables WITHOUT watching authUserIdTokenProvider.
Prevents Test #N+1 from re-surfacing this class.

Behavioral test in test/contracts/user_scoped_provider_rebuilds_on_auth_change_test
simulates user-A → user-B switch and asserts userProfileProvider's state
updates.

closes-diagnose: c4055a

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Bug 6 (e1f8a2): EditWorkoutLogSheet reads legacy `sets_detail`

**Diagnosis:** `_ExerciseEditRow.fromLog` at `lib/features/train/widgets/edit_workout_log_sheet.dart:865` reads `log['sets_detail']` (pre-Test-#6 legacy field). Modern `WorkoutWriteService.logExercise` writes canonical `log['sets']`. Edit sheet falls back to aggregate view when canonical is absent. Editing a timed exercise log → duration input shows empty.

### Files
- Modify: `lib/features/train/widgets/edit_workout_log_sheet.dart` (`_ExerciseEditRow.fromLog`)
- Create: `test/contracts/edit_workout_log_sets_field_contract_test.dart`
- Create: `docs/diagnoses/2026-05-12-edit-log-sets-detail-legacy-e1f8a2.md`

### Steps

- [ ] **Step 2.1:** Diagnose-doc. Cite writer at `workout_write_service.dart:170` (writes `sets`), reader at `edit_workout_log_sheet.dart:865` (reads `sets_detail`).

- [ ] **Step 2.2:** Read `_ExerciseEditRow.fromLog` to confirm exact reader location. Re-cite line.

- [ ] **Step 2.3:** Write failing test — log a timed exercise (Handstand Hold, 3 × 30s) via WorkoutWriteService → open edit sheet via the factory → assert 3 set rows with duration=30 prefilled.

- [ ] **Step 2.4:** Fix the reader.

```dart
// In _ExerciseEditRow.fromLog (current line ~865):
// BEFORE: final setsDetail = log['sets_detail'] as List?;
// AFTER:
final setsList = (log['sets'] as List?) ?? (log['sets_detail'] as List?);
// then iterate setsList with per-set reps/weight/duration extraction
```

Handle BOTH field names — `sets` (canonical) AND `sets_detail` (legacy fallback for old logs).

- [ ] **Step 2.5:** Test passes.

- [ ] **Step 2.6:** Commit.

```bash
git commit -m "fix(train): edit log sheet reads canonical sets[] with sets_detail fallback

_ExerciseEditRow.fromLog read only log['sets_detail'] (pre-Test-#6 legacy
field). Modern WorkoutWriteService writes canonical log['sets']. Editing
a timed exercise log surfaced empty duration inputs because the sheet
fell back to aggregate view when canonical was absent.

Reader now prefers log['sets'] and falls back to log['sets_detail'] for
legacy rows. Same dual-name strategy as Bug 4c (6e1b45) for
duration_sec/duration_seconds.

closes-diagnose: e1f8a2

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Bug 7 (a2b3c4): Cloud `workout_log_exercises.duration_seconds` never populated

**Diagnosis:** Cloud column `workout_log_exercises.duration_seconds` exists but the writer's projection in `SyncService._syncWorkoutLogExercises` doesn't compute it. Consumers (receipt, train screen, weekly report) work around by summing per-set `duration_secs` from `workout_log_sets` child table. Column is dead data, no analytics value.

### Files
- Modify: `lib/core/services/sync_service.dart` (`_syncWorkoutLogExercises` or wherever the cloud projection is built)
- Create: `test/contracts/duration_seconds_aggregate_populated_test.dart`
- Create: `docs/diagnoses/2026-05-12-duration-seconds-dead-column-a2b3c4.md`

### Steps

- [ ] **Step 3.1:** Diagnose-doc.

- [ ] **Step 3.2:** Find the projection method. Likely in `sync_service.dart` — grep for `'workout_log_exercises'` and trace the upsert/insert. Identify where the row map is constructed.

- [ ] **Step 3.3:** Modify the projection. For each exlog being synced, if `logging_type` is `'timed'` or `'cardio'`, compute `duration_seconds = sets.map((s) => s['duration_secs'] ?? 0).fold(0, sum)`. Write to the projection map. For non-timed logging types, set to `0` or omit.

- [ ] **Step 3.4:** Contract test — write a timed exlog locally → trigger sync → assert cloud `workout_log_exercises.duration_seconds` is populated.

If the test would need a real Supabase round-trip, source-grep the projection method instead (assert presence of `duration_seconds` in the projection map's keys when logging_type is timed/cardio).

- [ ] **Step 3.5:** Commit.

```bash
git commit -m "fix(sync): populate workout_log_exercises.duration_seconds for timed exercises

Cloud column existed but writer's projection never populated it. Receipt /
train_screen / weekly_report consumers worked around by summing per-set
duration_secs from workout_log_sets, but the aggregate column was dead
data — no analytics value, future Edge Functions joining on it would see
0.

Projection now computes duration_seconds = sum of per-set durations when
logging_type is 'timed' or 'cardio'. Other logging types write 0.

closes-diagnose: a2b3c4

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Pre-merge

- [ ] **Step 4.1:** Run full suite + all gates locally.

```bash
flutter analyze --no-fatal-infos
flutter test
dart run scripts/check_generic_error_telemetry.dart
dart run scripts/check_id_injection_on_get.dart
dart run scripts/check_bugfix_commits_have_diagnose.dart
```

- [ ] **Step 4.2:** Final code-reviewer pass (dispatched subagent).

- [ ] **Step 4.3:** Push feature branch + verify pre-push.

- [ ] **Step 4.4:** Merge `--no-ff` to main + push + delete branch.

- [ ] **Step 4.5:** Update MEMORY.md + CLAUDE.md §19 with three new entries + the meta-pattern (this is the SAME class as field-name drift, but at the Riverpod cache layer — codify in `feedback_writer_reader_field_drift_recurring.md`).

- [ ] **Step 4.6:** APK build — AWAITS FOUNDER EXPLICIT ASK per `feedback_apk_build_explicit_approval.md`. versionCode already at 1.0.0+23.

---

## Self-review

- ✅ All 3 bugs have file:line writer + reader citations
- ✅ All 3 bugs have regression tests (Bug 5 has BOTH source-grep + behavioral)
- ✅ All 3 bugs have hex bug_ids (c4055a / e1f8a2 / a2b3c4)
- ✅ Bug 5 audit is exhaustive (47 + 9 + tests pinning future drift)
- ✅ No defer per `feedback_no_deferrals.md`
- ✅ versionCode bump unnecessary (still on +23, APK not built yet)
- ✅ APK build gated on explicit ask
