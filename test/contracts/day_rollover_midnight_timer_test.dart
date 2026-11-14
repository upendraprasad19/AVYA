// Regression coverage for the foreground midnight-timer backstop
// (day_rollover_service.dart — durationUntilNextIstMidnight +
// DayRolloverObserver._scheduleMidnightTimer/_onMidnightTimerFired).
//
// Design gap this closes: DayRolloverObserver's ONLY triggers used to be
// app resume (didChangeAppLifecycleState) and cold launch (runRolloverNow
// from splash). An app left open in the FOREGROUND straight through
// midnight — no background/foreground transition — never hit either
// trigger, so daily-scoped providers went stale until the next resume.
//
// Two groups here:
//   A. Pure arithmetic on durationUntilNextIstMidnight() — no Hive, no
//      widget tree, no Timer. Fast and directly pins the formula.
//   B. One end-to-end test: freezes a REAL Timer (constructed inside
//      tester.runAsync so it escapes the ambient FakeAsync zone testWidgets
//      wraps every body in) a fraction of a second before a synthetic IST
//      midnight, lets real wall-clock time pass, and asserts the rollover
//      pipeline actually ran — proving the TIMER itself is a working
//      trigger, independent of resume/cold-launch.
//
// Run: flutter test test/contracts/day_rollover_midnight_timer_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
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

typedef _CaptureCallback = void Function(WidgetRef ref);

class _RefCaptureWidget extends ConsumerStatefulWidget {
  const _RefCaptureWidget({required this.onCapture});
  final _CaptureCallback onCapture;

  @override
  ConsumerState<_RefCaptureWidget> createState() => _RefCaptureWidgetState();
}

class _RefCaptureWidgetState extends ConsumerState<_RefCaptureWidget> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCapture(ref);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('durationUntilNextIstMidnight (pure arithmetic)', () {
    setUp(() {});
    tearDown(() => resetTestClock());

    test('mid-morning IST → ~14h remaining', () {
      // 2026-09-28 04:30 UTC == 2026-09-28 10:00 IST.
      setTestClockTo(DateTime.utc(2026, 9, 28, 4, 30));
      final d = durationUntilNextIstMidnight();
      expect(d, const Duration(hours: 14),
          reason: '10:00 IST → next IST midnight (00:00) is exactly 14h away');
    });

    test('one second before IST midnight → ~1s remaining', () {
      // 2026-09-28 18:29:59 UTC == 2026-09-28 23:59:59 IST.
      setTestClockTo(DateTime.utc(2026, 9, 28, 18, 29, 59));
      final d = durationUntilNextIstMidnight();
      expect(d, const Duration(seconds: 1),
          reason: '23:59:59 IST → 1 second until 00:00:00 IST');
    });

    test('exactly at IST midnight → next fire is ~24h away (the FOLLOWING '
        'midnight, not a zero/negative duration)', () {
      // 2026-09-28 18:30:00 UTC == 2026-09-29 00:00:00 IST exactly.
      setTestClockTo(DateTime.utc(2026, 9, 28, 18, 30, 0));
      final d = durationUntilNextIstMidnight();
      expect(d, const Duration(hours: 24),
          reason:
              'at the boundary itself, the next fire must be the FOLLOWING '
              'midnight (24h), never zero/negative — the defensive '
              'while-loop guard exists for exactly this shape of input');
    });

    test('one millisecond after IST midnight → ~24h remaining', () {
      setTestClockTo(
          DateTime.utc(2026, 9, 28, 18, 30, 0, 1)); // 00:00:00.001 IST
      final d = durationUntilNextIstMidnight();
      expect(d, const Duration(hours: 24) - const Duration(milliseconds: 1),
          reason: 'just after midnight → almost a full 24h until the next one');
    });

    test('never returns a zero or negative duration for any hour of the day',
        () {
      // Sweep every UTC hour of 2026-09-28 (24 distinct instants, each
      // landing on a different IST hour too since the offset is fixed).
      for (var hour = 0; hour < 24; hour++) {
        setTestClockTo(DateTime.utc(2026, 9, 28, hour, 0));
        final d = durationUntilNextIstMidnight();
        expect(d > Duration.zero, isTrue,
            reason: 'utc hour=$hour produced a non-positive duration: $d');
        expect(d <= const Duration(hours: 24), isTrue,
            reason: 'utc hour=$hour produced more than 24h: $d');
      }
    });
  });

  group('foreground midnight timer — end-to-end', () {
    late Directory tempDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = Directory.systemTemp.createTempSync('day_rollover_timer_');
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      Hive.init(tempDir.path);
      await Hive.openBox(HiveService.exerciseBoxName);
      await Hive.openBox(HiveService.foodBoxName);
      await Hive.openBox(HiveService.syncBoxName);
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.debugMarkInitializedForTests();
      GuardedBox.testBypassOwnership = true;
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await HiveUserSession.closeAll();
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      await HiveUserSession.closeAll();
      await HiveService.instance.configBox.clear();
      DayRolloverObserver.instance.dispose();
    });

    tearDown(() {
      DayRolloverObserver.instance.dispose();
      resetTestClock();
    });

    const testUser = 'test-day-rollover-timer-e2e-0099';

    testWidgets(
        'a real Timer fires _checkAndRollover across a synthetic IST '
        'midnight with NO resume/cold-launch call', (tester) async {
      await tester.runAsync(() async {
        await HiveUserSession.openForUser(testUser);
      });

      final refCompleter = Completer<WidgetRef>();
      await tester.pumpWidget(
        ProviderScope(
          child: _RefCaptureWidget(onCapture: refCompleter.complete),
        ),
      );
      await tester.pump();
      final ref = await tester.runAsync(() => refCompleter.future);

      // Anchor a clock that ADVANCES IN LOCKSTEP with real wall time
      // (not frozen) — the Timer fires on REAL time, so "now" must keep
      // moving for _checkAndRollover's date comparison to actually see a
      // change once the timer fires. Start ~90ms before the synthetic IST
      // midnight of 2026-09-29.
      //
      // Anchored AFTER the widget pump and ref capture, immediately before
      // init() (day-swapper-sync-load, 2026-09-29): anchored before them,
      // the pump could itself take longer than 90ms on a loaded machine, so
      // the synthetic clock crossed midnight BEFORE init() stored "today" —
      // preInitDate then already read the new day and the post-timer
      // assertion failed with Expected: not '2026-09-29', Actual:
      // '2026-09-29' (2 of 3 isolated runs, and the pre-push full suite).
      final targetMidnightUtc = istMidnightUtc(DateTime.utc(2026, 9, 29));
      final syntheticStart =
          targetMidnightUtc.subtract(const Duration(milliseconds: 90));
      final realStart = DateTime.now();
      final offset = syntheticStart.difference(realStart);
      setTestClock(() => DateTime.now().add(offset));

      final preInitDate = istTodayStr();
      expect(preInitDate, istDateStr(syntheticStart),
          reason: 'precondition: synthetic clock reads the day BEFORE the '
              'target midnight at the moment init() is about to run');

      // init() constructed on the REAL zone (via runAsync) so the Timer it
      // schedules is a genuine dart:async Timer tied to real wall-clock
      // time, not a FakeAsync-intercepted one that would need
      // tester.pump(duration)/async.elapse to fire — which would then hang
      // on _checkAndRollover's real Hive awaits (see the "await-ing real
      // disk I/O inside testWidgets hangs" pitfall in CLAUDE.md).
      await tester.runAsync(() async {
        DayRolloverObserver.instance.init(ref!);
      });

      final configBox = HiveService.instance.configBox;
      expect(configBox.get('last_known_date'), preInitDate,
          reason: 'init() stores "today" (pre-midnight) via '
              '_storeCurrentDate — no rollover has happened yet');

      // Let real wall-clock time pass so the ~90ms-away real Timer
      // actually fires and its chained Hive awaits resolve — entirely on
      // the real event loop (runAsync), no FakeAsync elapse anywhere in
      // this test.
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 600));
      });

      final postDate = configBox.get('last_known_date') as String?;
      expect(postDate, isNot(preInitDate),
          reason:
              'the foreground midnight timer must have fired and driven '
              '_checkAndRollover → _doRolloverWithRef, advancing '
              'last_known_date — with NO didChangeAppLifecycleState resume '
              'and NO runRolloverNow call anywhere in this test');
      expect(postDate, istDateStr(targetMidnightUtc),
          reason: 'the new stored date must be the synthetic midnight\'s '
              'IST date');
    });
  });
}
