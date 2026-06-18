// BEHAVIORAL contract for day_rollover_provider_invalidation:
//
// DayRolloverObserver.runRolloverNow(ref) is the public unconditional
// entry point (cold-start path from restoring_screen). After it completes:
//
//   1. configBox['last_known_date'] is updated to today's IST date.
//   2. Daily-scoped providers (e.g. waterIntakeProvider) are INVALIDATED,
//      so the next read rebuilds with fresh data for the new IST day.
//
// Design note — WidgetRef + testWidgets + runAsync:
//   runRolloverNow requires a real WidgetRef (it calls ref.invalidate on
//   ~20 providers). WidgetRef is a sealed class in flutter_riverpod — it
//   cannot be instantiated outside a widget tree.
//
//   We obtain a WidgetRef by mounting a ConsumerStatefulWidget inside a
//   ProviderScope, letting it capture `ref` in initState into a Completer,
//   then driving the rollover from the test body via `tester.runAsync()`.
//   `tester.runAsync()` is MANDATORY here: testWidgets runs inside
//   FakeAsync, which intercepts all Future machinery — Hive's async
//   `box.put()` calls would NEVER complete if awaited inside the
//   FakeAsync zone. runAsync escapes that zone to the real event loop.
//
// Observable assertions:
//   A. configBox['last_known_date'] updates from yesterday → today IST.
//   B. waterIntakeProvider rebuilds: after invalidation, reading the
//      provider returns the value in today's Hive key (not yesterday's).
//      Note: WaterIntakeNotifier.build() uses istDateStr(DateTime.now())
//      (raw DateTime.now(), NOT the test-clock seam), so water keys are
//      written with istDateStr(DateTime.now()) in these tests to match.
//
// Run: flutter test test/contracts/day_rollover_provider_invalidation_behavioral_test.dart

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
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
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

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('day_rollover_behavioral_');
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
    // Close user sessions and clear shared boxes between tests.
    await HiveUserSession.closeAll();
    await HiveService.instance.configBox.clear();
    // Reset the DayRolloverObserver singleton: clears _ref + _attached so each
    // testWidgets body gets a clean singleton (no stale ref from prior test).
    DayRolloverObserver.instance.dispose();
  });

  const testUser = 'test-day-rollover-behav-0055-aabbccdd';

  // ── 'last_known_date' string literal (field _hiveKey is private) ───────────

  group('day_rollover_provider_invalidation', () {
    // ── Test A: configBox['last_known_date'] updates from yesterday → today ──

    testWidgets(
        'runRolloverNow updates last_known_date in configBox from yesterday to today',
        (tester) async {
      await tester.runAsync(() async {
        await HiveUserSession.openForUser(testUser);
      });

      final configBox = HiveService.instance.configBox;

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = istDateStr(yesterday);
      final todayStr = istTodayStr();
      expect(yesterdayStr, isNot(equals(todayStr)),
          reason: 'precondition: yesterday IST ≠ today IST');

      // Seed configBox with yesterday as the last known date.
      await tester.runAsync(() async {
        await configBox.put('last_known_date', yesterdayStr);
      });
      expect(configBox.get('last_known_date'), yesterdayStr,
          reason: 'precondition: yesterday stored');

      // Capture the WidgetRef from the widget tree.
      final refCompleter =
          Completer<({WidgetRef ref, ProviderContainer container})>();

      await tester.pumpWidget(
        ProviderScope(
          child: _RefCaptureWidget(onCapture: refCompleter.complete),
        ),
      );
      await tester.pump(); // process initState + postFrameCallback
      final captured = await tester.runAsync(() => refCompleter.future);

      // Drive rollover on the real event loop (escapes FakeAsync so Hive IO
      // futures complete normally).
      await tester.runAsync(() async {
        await DayRolloverObserver.instance.runRolloverNow(captured!.ref);
      });

      final storedDateA = configBox.get('last_known_date') as String?;

      expect(storedDateA, todayStr,
          reason:
              'runRolloverNow must update configBox["last_known_date"] '
              'to today\'s IST date string');
      // Also verify directly from the box:
      expect(configBox.get('last_known_date'), todayStr,
          reason: 'configBox must persist the new date');
    });

    // ── Test B: waterIntakeProvider returns 0 when only yesterday has water ──

    testWidgets(
        'waterIntakeProvider rebuilds to 0 after rollover when only '
        "yesterday's water was written", (tester) async {
      await tester.runAsync(() async {
        await HiveUserSession.openForUser(testUser);
      });

      final configBox = HiveService.instance.configBox;
      final healthBox = HiveService.instance.healthBox;

      await tester.runAsync(() async {
        await healthBox.clear();
      });

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = istDateStr(yesterday);
      // WaterIntakeNotifier.build() uses istDateStr(DateTime.now()) — no seam.
      final todayStr = istDateStr(DateTime.now());

      // Write 2000ml for YESTERDAY only.
      await tester.runAsync(() async {
        await healthBox.put('water_ml_$yesterdayStr', 2000);
        await configBox.put('last_known_date', yesterdayStr);
      });
      expect(healthBox.get('water_ml_$todayStr'), isNull,
          reason: "precondition: today's water key absent");

      // Capture the WidgetRef and ProviderContainer.
      final refCompleter = Completer<({WidgetRef ref, ProviderContainer container})>();

      await tester.pumpWidget(
        ProviderScope(
          child: _RefCaptureWidget(
            onCapture: refCompleter.complete,
          ),
        ),
      );
      await tester.pump();
      final captured = await tester.runAsync(() => refCompleter.future);

      // Pre-rollover: waterIntakeProvider returns 0 for today.
      final waterBefore = captured!.container.read(waterIntakeProvider);
      expect(waterBefore, 0,
          reason:
              "today's water key absent → waterIntakeProvider = 0 before rollover");

      // Rollover — invalidates waterIntakeProvider.
      await tester.runAsync(() async {
        await DayRolloverObserver.instance.runRolloverNow(captured.ref);
      });

      final storedDate = configBox.get('last_known_date') as String?;
      // After invalidation, re-read provider (rebuilds from Hive).
      final waterAfter = captured.container.read(waterIntakeProvider);

      expect(storedDate, todayStr,
          reason: 'last_known_date must be today after rollover');
      expect(waterAfter, 0,
          reason:
              "waterIntakeProvider must rebuild to 0 after rollover when "
              "today's water_ml key has no data");
    });

    // ── Test C: waterIntakeProvider returns today's value when it was pre-written ──

    testWidgets(
        "waterIntakeProvider rebuilds with today's 750ml after rollover "
        'when the key was pre-written to healthBox', (tester) async {
      await tester.runAsync(() async {
        await HiveUserSession.openForUser(testUser);
      });

      final configBox = HiveService.instance.configBox;
      final healthBox = HiveService.instance.healthBox;

      await tester.runAsync(() async {
        await healthBox.clear();
      });

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStr = istDateStr(yesterday);
      // WaterIntakeNotifier.build() uses istDateStr(DateTime.now()) — no seam.
      final todayStr = istDateStr(DateTime.now());

      // Write water for both days.
      await tester.runAsync(() async {
        await healthBox.put('water_ml_$yesterdayStr', 1500);
        await healthBox.put('water_ml_$todayStr', 750);
        // Seed configBox with yesterday (simulates stale state).
        await configBox.put('last_known_date', yesterdayStr);
      });

      // Capture the WidgetRef and ProviderContainer.
      final refCompleter = Completer<({WidgetRef ref, ProviderContainer container})>();

      await tester.pumpWidget(
        ProviderScope(
          child: _RefCaptureWidget(
            onCapture: refCompleter.complete,
          ),
        ),
      );
      await tester.pump();
      final captured = await tester.runAsync(() => refCompleter.future);

      // Rollover — invalidates waterIntakeProvider.
      await tester.runAsync(() async {
        await DayRolloverObserver.instance.runRolloverNow(captured!.ref);
      });

      final storedDate = configBox.get('last_known_date') as String?;
      final waterAfter = captured!.container.read(waterIntakeProvider);

      expect(storedDate, todayStr,
          reason: 'last_known_date must be today after rollover');
      expect(waterAfter, 750,
          reason:
              "waterIntakeProvider must rebuild with today's 750ml after "
              'runRolloverNow invalidates the provider');
    });
  });
}

// ── Widget bridge to obtain a real WidgetRef + ProviderContainer ──────────
//
// runRolloverNow(WidgetRef ref) calls ref.invalidate(...) on ~20 Riverpod
// providers. WidgetRef is a sealed class in flutter_riverpod — it is NOT
// implementable outside a widget tree and ProviderContainer does NOT
// implement it.
//
// Strategy: mount a minimal ConsumerStatefulWidget inside ProviderScope.
// In initState, schedule a postFrameCallback that fires after the first
// build (ensuring ProviderScope.containerOf(context) is valid), then
// completes the Completer with both the WidgetRef and ProviderContainer.
// The test body awaits the Completer via tester.runAsync() to escape
// FakeAsync, then drives the rollover with tester.runAsync() to ensure
// Hive IO futures complete normally.

typedef _CaptureCallback = void Function(
    ({WidgetRef ref, ProviderContainer container}) captured);

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
      final container = ProviderScope.containerOf(context);
      widget.onCapture((ref: ref, container: container));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
