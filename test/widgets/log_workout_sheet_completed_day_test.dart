// test/widgets/log_workout_sheet_completed_day_test.dart
//
// OI-228 (Bug A) — LogWorkoutSheet._buildEmpty() used to show the generic
// "NO WORKOUT SCHEDULED TODAY" copy for a day whose workout was already
// completed, identical to a day with nothing scheduled at all. Founder
// screenshot showed this on a day he'd genuinely finished.
//
// Real widget-pump test. Two documented pitfalls apply (root CLAUDE.md's
// common-pitfalls table), both hit live while writing this file:
//
//   1. "await-ing real disk I/O inside a testWidgets body hangs until the
//      harness gives up" — confirmed: an earlier version of this file
//      awaited HiveUserSession/Hive box calls directly inside testWidgets
//      bodies and hung past a 120s timeout with zero output. Fixed by
//      wrapping every real Hive read/write in tester.runAsync().
//
//   2. "A widget test that mocks path_provider makes GoogleFonts fail
//      LOUDLY instead of degrading" — confirmed: mocking path_provider so
//      Hive can open a box walks GoogleFonts into its fetch-and-save path
//      (it shares that channel), and the network failure surfaced as a
//      test EXCEPTION (not a silent degrade) on two of the three widget
//      tests. Fixed the way test/contracts/exercise_plate_widgets_test.dart
//      documents: Hive/path_provider mocking is LAZY (never in setUpAll),
//      and the FIRST test in the file renders every font family+weight the
//      later tests need (JetBrains Mono via AppTypography.mono, DM Sans
//      via .bodyS, Fraunces via WardButton's h3) with NO mock installed
//      yet — letting GoogleFonts fail and cache the failure the ordinary
//      way before path_provider is ever intercepted.
//
// Run: flutter test test/widgets/log_workout_sheet_completed_day_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/widgets/log_workout_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

const _fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
bool _hiveReady = false;

/// Opens Hive + mocks path_provider on first call. Idempotent, and
/// deliberately NOT a setUpAll — see the file header. Must be called from
/// inside tester.runAsync() (Hive.init/HiveService.init do real I/O).
Future<void> _ensureHive() async {
  if (_hiveReady) return;
  _hiveReady = true;
  final tmp = Directory.systemTemp.createTempSync('log_workout_sheet_').path;
  PathProviderPlatform.instance = _FakePathProvider(tmp);
  Hive.init(tmp);
  HiveService.debugMarkInitializedForTests();
  GuardedBox.testBypassOwnership = true;
}

/// Real Hive I/O — session open + box clear + optional schedule seed.
/// Always run inside tester.runAsync().
Future<void> _seed(WidgetTester tester, Map<String, dynamic>? todaySchedule) {
  return tester.runAsync(() async {
    await _ensureHive();
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser(_fakeUserId);
    await HiveService.instance.workoutBox.clear();
    if (todaySchedule != null) {
      final todayKey = istDateStr(DateTime.now());
      await HiveService.instance.workoutBox
          .put('schedule_$todayKey', todaySchedule);
    }
  });
}

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: Center(child: LogWorkoutSheet())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDownAll(() async {
    if (!_hiveReady) return;
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
  });

  // MUST run first, and MUST be the only test that touches these font
  // families before _ensureHive() ever runs — see file header pitfall 2.
  testWidgets(
      'font priming — renders every family+weight this file needs before '
      'any Hive/path_provider mock exists', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('mono',
              style: AppTypography.mono.copyWith(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent)),
          Text('body', style: AppTypography.bodyS.copyWith(color: AppColors.textMute)),
          WardButton(label: 'PRIME', onPressed: () {}),
        ]),
      ),
    ));
    await tester.pump();
    expect(find.text('mono'), findsOneWidget);
  });

  group('LogWorkoutSheet — completed-day empty state (OI-228 Bug A)', () {
    testWidgets('nothing scheduled today shows the generic empty copy',
        (tester) async {
      await _seed(tester, null);
      await _pumpSheet(tester);

      expect(find.text('NO WORKOUT SCHEDULED TODAY'), findsOneWidget);
      expect(find.text('WORKOUT ALREADY LOGGED'), findsNothing);
    });

    testWidgets(
        "today's COMPLETED workout shows distinct 'already logged' copy, "
        'not the generic empty state', (tester) async {
      await _seed(tester, {
        'type': 'workout',
        'status': 'completed',
        'exercises': [
          {'exercise_name': 'Bench Press', 'sets': 4, 'reps': 8},
        ],
      });
      await _pumpSheet(tester);

      expect(find.text('WORKOUT ALREADY LOGGED'), findsOneWidget);
      expect(find.text('NO WORKOUT SCHEDULED TODAY'), findsNothing);
      // The old generic empty-state body copy must not appear either.
      expect(
        find.textContaining('Log anything you did from the Train screen'),
        findsNothing,
      );
    });

    testWidgets('a PLANNED workout still shows the loggable form, not '
        'either empty state', (tester) async {
      await _seed(tester, {
        'type': 'workout',
        'status': 'planned',
        'exercises': [
          {'exercise_name': 'Bench Press', 'sets': 4, 'reps': 8},
        ],
      });
      await _pumpSheet(tester);

      expect(find.text('LOG TODAY\'S WORKOUT'), findsOneWidget);
      expect(find.text('WORKOUT ALREADY LOGGED'), findsNothing);
      expect(find.text('NO WORKOUT SCHEDULED TODAY'), findsNothing);
    });
  });
}
