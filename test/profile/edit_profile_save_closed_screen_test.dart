// Edit Profile SAVE when the screen is closed while the Save is still running.
//
// Founder walk 2026-11-25 (A20, AAB +50): the app logged `profile_edit_save_failed`: 'Using "ref"
// when a widget is about to or has been unmounted is unsafe'. `_save` awaits the profile write, the
// target recompute and, after the "Reschedule Workouts?" dialog, the whole plan regeneration (10+
// seconds on that phone), and then used the screen's `ref` with no `mounted` check. A screen closed
// in the meantime (back button, a restore redirect) made the Save throw half way: the targets were
// not recomputed, the plan providers were not refreshed and the failure was reported.
//
// BEHAVIOURAL: the REAL EditProfileScreen is pumped against real Hive, SAVE is tapped, the screen is
// closed while the Save's first real await is pending, and the written profile and the telemetry are
// read back. Harness copied from edit_profile_target_impact_test.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/profile/screens/edit_profile_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

const _user = 'ffff7777-ffff-ffff-ffff-ffffffffffff';

Map<String, dynamic> _profile() => {
      'full_name': 'Test Recruit',
      'primary_goal': 'lose_fat',
      'current_weight_kg': 75.0,
      'target_weight_kg': 71.0,
      'height_cm': 175.0,
      'gender': 'male',
      'date_of_birth': '1995-06-15',
      'activity_level': 'moderate',
      'lifestyle_activity': 'moderate',
      'days_per_week': 4,
      'fitness_experience': 'intermediate',
      'equipment_access': 'full_gym',
      'pace_preference': 'balanced',
      'physique_focus': 'balanced',
      'injuries': ['none'],
      'daily_calories': 2000,
      'protein_grams': 150,
    };

void main() {
  late Directory tempDir;
  var hiveReady = false;
  late GoRouter router;
  final events = <({String op, String? message})>[];
  final nonFatals = <String>[];

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('edit_profile_closed_');
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    DietStrategyFlags.debugEnabledOverride = null;
    SupabaseService.clientOverrideForTest = null;
    SyncService.pausedForSimulation = false;
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    // A Save that outlives its screen leaves a Hive write started inside the fake-async zone,
    // which never completes and makes `closeAll` / `close` wait for ever (the known 12-minute
    // tearDownAll hang). The process ends with the suite, so a bounded wait is enough here.
    const bound = Duration(seconds: 10);
    await Future.any<void>([
      HiveUserSession.closeAll(),
      Future<void>.delayed(bound),
    ]);
    await Future.any<void>([Hive.close(), Future<void>.delayed(bound)]);
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // FIRST, Hive-free and path_provider-free by design (see edit_profile_target_impact_test.dart).
  testWidgets('primes google_fonts fallbacks before path_provider is mocked',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(child: Column(children: [
        for (final w in const [
          FontWeight.w400,
          FontWeight.w500,
          FontWeight.w600,
          FontWeight.w700,
          FontWeight.w800,
          FontWeight.w900,
        ]) ...[
          Text('warm', style: GoogleFonts.getFont('DM Sans', fontWeight: w)),
          Text('warm', style: GoogleFonts.getFont('JetBrains Mono', fontWeight: w)),
          Text('warm', style: GoogleFonts.getFont('Fraunces', fontWeight: w)),
        ],
      ])),
    ));
    await tester.pumpAndSettle();
  });

  Future<void> boot(WidgetTester tester, Map<String, dynamic> profile) async {
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await tester.runAsync(() async {
      if (!hiveReady) {
        Hive.init(tempDir.path);
        hiveReady = true;
      }
      for (final b in [
        HiveService.exerciseBoxName,
        HiveService.foodBoxName,
        HiveService.syncBoxName,
        HiveService.configBoxName,
        HiveService.migrationBoxName,
      ]) {
        if (!Hive.isBoxOpen(b)) await Hive.openBox(b);
      }
      HiveService.debugMarkInitializedForTests();
      GuardedBox.testBypassOwnership = true;
      await HiveUserSession.closeAll();
      await HiveUserSession.openForUser(_user);
      await HiveService.instance.userBox.clear();
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        ...profile,
        'units_system': 'metric',
      });
      await MigratedKey.delete('prediction_stale');
    });
    SyncService.pausedForSimulation = true;
    DietStrategyFlags.debugEnabledOverride = false;
    SupabaseService.clientOverrideForTest =
        SupabaseClient('http://127.0.0.1:1', 'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false));
    events.clear();
    nonFatals.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add((op: op, message: message));
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (error, stack, {required reason, extra}) => nonFatals.add('$reason: $error');

    tester.view.physicalSize = const Size(900, 7000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('PROFILE'))),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        authUserIdTokenProvider.overrideWithValue(_user),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      final closing = HiveUserSession.closeAll();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
      }
      await closing;
    });
  }

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  // Two sinks: the Save's own failure event, and the non-fatal the profile-surface refresh logs
  // for one provider (it catches each failure so one bad provider never stops the rest).
  bool reportedUnmountedRef() =>
      events.any((e) =>
          e.op == 'profile_edit_save_failed' && (e.message ?? '').contains('unmounted')) ||
      nonFatals.any((s) => s.contains('unmounted'));

  testWidgets('the screen closed right after SAVE: the Save still recomputes the targets and reports nothing',
      (tester) async {
    await boot(tester, _profile());
    final tile = find.text('Aggressive');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();

    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await tester.pump(); // `_save` runs up to its first real await (the profile write)
    // The screen is replaced (a back gesture, a restore redirect); the app's ProviderScope stays.
    // Fake time moves past the page transition BEFORE any real I/O finishes, so the screen is
    // already disposed when the Save resumes (a screen still in its exit transition is mounted).
    router.go('/profile');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    final after = Map<dynamic, dynamic>.from(
        (await tester.runAsync(() async => HiveService.instance.userBox.get('profile')))! as Map);
    expect(after['pace_preference'], isNot('balanced'), reason: 'the edit itself was written');
    expect(after['daily_calories'], isNot(2000),
        reason: 'recalculateTargets ran after the screen closed');
    expect(reportedUnmountedRef(), isFalse,
        reason: 'events were $events, non-fatals were $nonFatals');
  });

  // Everything `_save` does after its first await runs in this test with no screen behind it
  // (the targets recompute, the impact read, the provider refreshes, the final plan refresh), so
  // the "no unmounted-ref failure" line covers each of those provider calls.
  testWidgets('a plan-affecting edit (5 days) closed right after SAVE also finishes without the failure',
      (tester) async {
    await boot(tester, _profile());
    await tester.runAsync(() async {
      await HiveService.instance.workoutBox
          .put('current_plan', <String, dynamic>{'plan': 'x'});
    });
    final five = find.text('5');
    await tester.ensureVisible(five.first);
    await tester.tap(five.first);
    await tester.pump();

    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    router.go('/profile');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    // The screen is already disposed when the Save resumes, so it must not open the dialog; if a
    // build ever lets it through, answer it so the Save can finish and be judged.
    final keep = find.text('Keep Current Plan');
    if (keep.evaluate().isNotEmpty) {
      await tester.tap(keep, warnIfMissed: false);
      await settle(tester);
    }
    expect(find.text('Reschedule Workouts?'), findsNothing);
    expect(find.text('PROFILE'), findsOneWidget);
    expect(reportedUnmountedRef(), isFalse, reason: 'events were $events');
  });
}
