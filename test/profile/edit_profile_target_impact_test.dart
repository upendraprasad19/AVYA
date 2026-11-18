// goal-change-targets B3: Edit Profile tells the user, with exact numbers, when a Save moved the
// calorie / protein targets (and says nothing when no derivation input really changed).
//
// Harness copied from edit_profile_target_impact_test.dart (OI-191, door 2).
//
// The FIRST pump of EditProfileScreen in this repo. Harness recipe (and the
// font-priming order) from test/widgets/diet_plan_screen_no_modal_test.dart:
// the first testWidgets renders every font family with NO path_provider mock;
// Hive opens lazily inside tester.runAsync in the tests after it.
//
// Stubs: real Hive on a temp dir + a user session; DietStrategyFlags off (else
// initState reads macroTargetsProvider and build watches the subscription
// chain); a SupabaseClient that never connects (`_save` reads client.auth);
// a GoRouter ancestor (a successful Save ends in context.go('/profile')).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
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

const _user = 'ffff6666-ffff-ffff-ffff-ffffffffffff';

Map<String, dynamic> _profile({
  String goal = 'lose_fat',
  Object? weight = 75.0,
  Object? target = 71.0,
}) =>
    {
      'full_name': 'Test Recruit',
      'primary_goal': goal,
      'current_weight_kg': weight,
      'target_weight_kg': target,
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('edit_profile_target_impact_');
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    DietStrategyFlags.debugEnabledOverride = null;
    SupabaseService.clientOverrideForTest = null;
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // FIRST, Hive-free and path_provider-free by design (see the file header).
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

  /// Boots Hive and the session lazily, seeds [profile], pumps the screen.
  Future<void> boot(
    WidgetTester tester,
    Map<String, dynamic> profile, {
    bool metric = true,
  }) async {
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
      await HiveService.instance.userBox.put('profile', profile);
      await HiveService.instance.configBox.put('units_metric', metric);
      await MigratedKey.delete('prediction_stale');
    });
    SyncService.pausedForSimulation = true;
    DietStrategyFlags.debugEnabledOverride = false;
    SupabaseService.clientOverrideForTest =
        SupabaseClient('http://127.0.0.1:1', 'anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false));

    tester.view.physicalSize = const Size(900, 7000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(routes: [
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
    // Close the session while the test zone is still alive: box.close() waits
    // for every `watch()` subscription to receive its done event, and that
    // delivery runs in the zone of the subscriber (a provider in this tree).
    // Left to the next boot, `closeAll` waits on a dead zone forever.
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

  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  final dialog = find.byKey(const ValueKey('target_impact_dialog'));

  Future<void> tapOk(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('target_impact_ok')));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a pace-only edit shows "Targets updated" with exact from -> to numbers',
      (tester) async {
    await boot(tester, _profile());
    final tile = find.text('Aggressive');
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    await tapSave(tester);
    expect(dialog, findsOneWidget);
    expect(find.text('Targets updated'), findsOneWidget);
    expect(find.textContaining('Daily calories 2,000 \u2192'), findsOneWidget);
    expect(find.textContaining('Protein 150 \u2192'), findsOneWidget);
    await tapOk(tester);
  });

  testWidgets('an unchanged Save of an ISO-DOB, fractional-height profile with stale targets shows NO dialog',
      (tester) async {
    await boot(tester, {
      ..._profile(),
      'date_of_birth': '1995-06-15T00:00:00.000',
      'height_cm': 177.8,
    });
    await tapSave(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('a name-only edit shows no dialog', (tester) async {
    await boot(tester, _profile());
    await tester.enterText(field('Full Name'), 'Other Name');
    await tapSave(tester);
    expect(dialog, findsNothing);
  });

  testWidgets('a body-fat assessment persisted while the form is open is reported by the next Save',
      (tester) async {
    await boot(tester, _profile());
    final container = ProviderScope.containerOf(
        tester.element(find.byType(EditProfileScreen)));
    await tester.runAsync(() => container
        .read(userProfileProvider.notifier)
        .updateProfile(<String, dynamic>{'body_fat_percent': 24.0}));
    await tapSave(tester);
    expect(dialog, findsOneWidget,
        reason: 'the assessment already holds body_fat_percent when Save reads the profile');
    await tapOk(tester);
  });

  testWidgets('a Save that also reschedules shows "Already updated" inside the reschedule dialog and no second dialog',
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
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.text('Reschedule Workouts?'), findsOneWidget);
    expect(find.text('ALREADY UPDATED'), findsOneWidget);
    expect(find.byKey(const ValueKey('target_impact_calories')), findsOneWidget);
    expect(dialog, findsNothing);
    await tester.tap(find.text('Keep Current Plan'));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(dialog, findsNothing, reason: 'no second dialog follows');
  });
}
