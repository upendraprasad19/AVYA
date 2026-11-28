// OI-348 B9 (diagnose e9a6c1): the Profile Units row.
//
// The REAL ProfileScreen, real Hive. Two behaviours the plan names:
//   1. No snap-back: a tap moves the switch at once and it stays there while
//      the profile write is still pending (real Hive I/O does not finish in
//      the fake-async zone, so the first pumps run BEFORE the write landed).
//      After the write, the profile holds `imperial`.
//   2. A completed restore (the `restoreCompletedTick` every tab listens to)
//      re-seeds the switch from the profile a restore changed behind it.
//
// Harness recipe: edit_profile_target_impact_test.dart (fonts primed first,
// Hive opened lazily inside runAsync, a Supabase client that never connects).
//
// Both run in ONE testWidgets (one boot; see the note there).
//
// Mutation (diagnose table): `_isMetric` re-read in `build` from
// `getUnitsMetric()` turns step 2 red; removing the re-seed in
// `invalidateOnBackgroundRestore` turns step 1 red.
@Timeout(Duration(minutes: 4))
library;
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/features/profile/screens/profile/screen.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/features/profile/widgets/profile_row.dart';
import 'package:icanbefitter/shared/providers/sync_state_provider.dart';
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

const _user = 'abab7777-ffff-ffff-ffff-ffffffffffff';

Map<String, dynamic> _profile(String units) => {
      'full_name': 'Test Recruit',
      'primary_goal': 'build_muscle',
      'current_weight_kg': 75.0,
      'target_weight_kg': 78.0,
      'height_cm': 175.0,
      'gender': 'male',
      'date_of_birth': '1995-06-15',
      'activity_level': 'moderate',
      'days_per_week': 4,
      'fitness_experience': 'intermediate',
      'daily_calories': 2400,
      'protein_grams': 150,
      'units_system': units,
    };

void main() {
  late Directory tempDir;
  var hiveReady = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('profile_units_row_');
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    DietStrategyFlags.debugEnabledOverride = null;
    SupabaseService.clientOverrideForTest = null;
    SyncService.pausedForSimulation = false;
    // Bounded: a shared-box write the screen started in the fake-async zone
    // never reports completion here, and an unbounded close waits forever.
    // The per-test teardown already closed the user session.
    await Future.any<void>([
      HiveUserSession.closeAll(),
      Future<void>.delayed(const Duration(seconds: 5)),
    ]);
    await Future.any<void>([
      Hive.close(),
      Future<void>.delayed(const Duration(seconds: 5)),
    ]);
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {/* a box file still held open on Windows */}
  });

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

  /// Lets the real event loop deliver the Hive file writes the screen started
  /// in the fake-async zone (a write left queued there blocks the next one).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> boot(WidgetTester tester, String units) async {
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
      await HiveService.instance.userBox.put('profile', _profile(units));
      await HiveService.instance.configBox.delete('units_metric');
      // The library seed is irrelevant here, and its thousands of writes,
      // started in the fake-async zone, would keep `Hive.close()` waiting.
      await HiveService.instance.configBox.putAll(<String, Object>{
        'seeded': true,
        'seeded_exercises': true,
        'seeded_foods': true,
        'exercise_library_version': 1 << 20,
        'food_library_version': 1 << 20,
      });
      await MigratedKey.write('prediction_text', 'seeded');
    });
    SyncService.pausedForSimulation = true;
    DietStrategyFlags.debugEnabledOverride = false;
    SupabaseService.clientOverrideForTest =
        SupabaseClient('http://127.0.0.1:1', 'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false));

    tester.view.physicalSize = const Size(900, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        authUserIdTokenProvider.overrideWithValue(_user),
        // The real notifier subscribes to the connectivity plugin and a
        // periodic drain timer; neither exists in a widget test.
        syncStateProvider.overrideWith(_IdleSync.new),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
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

  bool shownMetric(WidgetTester tester) =>
      tester.widget<UnitsSegmentedControl>(find.byType(UnitsSegmentedControl))
          .isMetric;

  Object? storedUnits() =>
      (HiveService.instance.userBox.get('profile') as Map?)?['units_system'];

  // ONE boot for both behaviours: a second boot in the same file waits on
  // Hive file writes the first screen started in the fake-async zone.
  testWidgets('the Units row: a restore re-seeds it; a tap moves it at once '
      'and it never snaps back while the write is pending', (tester) async {
    await boot(tester, 'metric');
    expect(shownMetric(tester), isTrue);

    // ── 1. a completed restore re-seeds the switch ──────────────────────
    // Another device's value arrives through a restore, behind the screen.
    // (Hive updates the in-memory value synchronously; settle delivers the
    // file write.)
    unawaited(
        HiveService.instance.userBox.put('profile', _profile('imperial')));
    await settle(tester);
    expect(storedUnits(), 'imperial');
    expect(shownMetric(tester), isTrue,
        reason: 'no re-read in build: nothing has told the screen yet');

    SyncService.instance.bumpRestoreCompleted();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(shownMetric(tester), isFalse, reason: 're-seeded on the tick');

    // ── 2. a tap moves the switch at once, no snap-back ─────────────────
    // Another write holds the profile lock, so the toggle's write is queued
    // and has NOT landed while the screen rebuilds.
    final release = Completer<void>();
    final held =
        ProfileWriteService.instance.debugHoldLockUntil(release.future);

    await tester.ensureVisible(find.text('KG/CM'));
    await tester.tap(find.text('KG/CM'));
    await tester.pump();
    expect(storedUnits(), 'imperial',
        reason: 'the harness premise: the write has not landed yet');
    expect(shownMetric(tester), isTrue);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(storedUnits(), 'imperial');
      expect(shownMetric(tester), isTrue, reason: 'no snap-back, pump $i');
    }

    // ── 3. B-pass F3: a restore tick WHILE the write is queued ──────────
    // The stored value is still the old one; the tick must not flip the
    // switch back, and the write's completion re-seeds from the store.
    SyncService.instance.bumpRestoreCompleted();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(storedUnits(), 'imperial');
    expect(shownMetric(tester), isTrue,
        reason: 'a tick during a pending write does not snap the switch back');

    release.complete();
    await held;
    await settle(tester);
    expect(storedUnits(), 'metric');
    expect(shownMetric(tester), isTrue);
  });
}

class _IdleSync extends SyncStateNotifier {
  @override
  SyncState build() => const SyncIdle();
}
