// test/contracts/streak_warning_eligibility_logged_test.dart
//
// Proves the wiring at home_provider.dart:375 (StreakWarningEligibilityNotifier
// .build, isWorkoutDayToday) actually changes when the OI-126 flag flips, by
// reading the REAL provider through a real ProviderContainer — not a
// hand-duplicated reconstruction of its logic (round-2 review's finding
// against this task's first draft).
//
// NOTE: no existing test file covers StreakWarningEligibility (the file named
// in lib/features/home/CLAUDE.md, streak_warning_banner_threshold_test.dart,
// does not exist on disk — confirmed via a live search before writing this;
// do not trust that CLAUDE.md line without re-checking it yourself too).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

class _FakeTodayWorkoutNotifier extends TodayWorkoutNotifier {
  _FakeTodayWorkoutNotifier(this._schedule);
  final Map<String, dynamic>? _schedule;
  @override
  Map<String, dynamic>? build() => _schedule;
}

class _FakeStreakNotifier extends StreakNotifier {
  @override
  int build() => 5;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUp(() async {
    // WorkoutRepository.instance.getRecentWorkoutCompletionHours (called
    // inside the real StreakWarningEligibilityNotifier.build(), not mocked)
    // reads the user-scoped workoutBox — needs the same session-open pattern
    // phase_adherence_rate_test.dart uses, not just configBox.
    tempDir = await Directory.systemTemp.createTemp('oi126_streak_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.workoutBoxName);
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDown(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('a logged today-schedule flips isWorkoutDayToday once the flag is on', () {
    final container = ProviderContainer(overrides: [
      todayWorkoutProvider.overrideWith(
        () => _FakeTodayWorkoutNotifier({'type': 'logged', 'status': 'planned'}),
      ),
      streakProvider.overrideWith(() => _FakeStreakNotifier()),
      authUserIdTokenProvider.overrideWithValue('oi126-test-user'),
    ]);
    addTearDown(container.dispose);

    // Flag OFF (default): 'logged' does not count as a workout day today.
    final off = container.read(streakWarningEligibilityProvider);
    expect(off.isWorkoutDayToday, isFalse, reason: 'flag off: logged is not a workout day today');

    HiveService.instance.configBox
        .put('enable_logged_counts_as_phase_training_day', true);
    container.invalidate(streakWarningEligibilityProvider);

    // Flag ON: 'logged' now counts as a workout day today.
    final on = container.read(streakWarningEligibilityProvider);
    expect(on.isWorkoutDayToday, isTrue, reason: 'flag on: logged now counts as a workout day today');
  });
}
