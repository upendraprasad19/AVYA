// OI-191, door 2: Edit Profile. The goal and the target weight must agree at
// Save, and changing the goal in the form must not leave a target that breaks it.
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
    tempDir = Directory.systemTemp.createTempSync('edit_profile_goal_target_');
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
  String textOf(WidgetTester t, String label) =>
      t.widget<TextField>(field(label)).controller!.text;

  Future<void> chooseGoal(WidgetTester tester, String label) async {
    final dd = find.widgetWithText(DropdownButtonFormField<String>, 'Goal');
    await tester.ensureVisible(dd);
    await tester.tap(dd);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// Taps SAVE and lets the real Hive I/O behind the save chain finish: the
  /// fake-async zone of a testWidgets never completes a disk write by itself.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    // The Save leaves fire-and-forget work behind (profile sync, snapshot push,
    // prediction refresh). Drain it in real time AND pump the fake clock, so no
    // operation on the user box is still pending when the next test re-opens it.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<Map<dynamic, dynamic>> storedProfile(WidgetTester tester) async =>
      (await tester.runAsync(
              () async => HiveService.instance.userBox.get('profile')))!
          as Map;

  testWidgets('the form opens on the stored target when it fits the goal',
      (tester) async {
    await boot(tester, _profile());
    expect(textOf(tester, 'Target Weight (kg)'), '71.0');
  });

  testWidgets('goal Cut -> Build prefills the seed (current + 3 kg)',
      (tester) async {
    await boot(tester, _profile());
    await chooseGoal(tester, 'Build');
    expect(textOf(tester, 'Target Weight (kg)'), '78.0');
  });

  testWidgets('Cut 71 -> Build -> Cut restores 71 (a valid target is never lost)',
      (tester) async {
    await boot(tester, _profile());
    await chooseGoal(tester, 'Build');
    expect(textOf(tester, 'Target Weight (kg)'), '78.0');
    await chooseGoal(tester, 'Cut');
    expect(textOf(tester, 'Target Weight (kg)'), '71.0');
  });

  testWidgets('a typed valid target survives a goal change', (tester) async {
    await boot(tester, _profile());
    await tester.enterText(field('Target Weight (kg)'), '80.0');
    await chooseGoal(tester, 'Build');
    expect(textOf(tester, 'Target Weight (kg)'), '80.0');
  });

  testWidgets('a legacy 0.0 target opens as the goal\'s seed', (tester) async {
    await boot(tester, _profile(target: 0.0));
    expect(textOf(tester, 'Target Weight (kg)'), '70.0');
  });

  testWidgets('Save with a contradicting typed target shows the popup and writes nothing',
      (tester) async {
    await boot(tester, _profile());
    await chooseGoal(tester, 'Build');
    await tester.enterText(field('Target Weight (kg)'), '70.0');
    await tapSave(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsOneWidget);
    expect(find.textContaining('higher than your current weight'), findsOneWidget);
    expect(find.textContaining('Adjust it and save.'), findsOneWidget);
    final p = await storedProfile(tester);
    expect(p['primary_goal'], 'lose_fat');
    expect(p['target_weight_kg'], 71.0);
  });

  testWidgets('Save with an empty target shows the missing message', (tester) async {
    await boot(tester, _profile());
    await tester.enterText(field('Target Weight (kg)'), '');
    await tapSave(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsOneWidget);
    expect(find.text('Enter your target weight to save.'), findsOneWidget);
    expect((await storedProfile(tester))['target_weight_kg'], 71.0);
  });

  testWidgets('Save after a goal change writes goal, the seeded target and new targets',
      (tester) async {
    await boot(tester, _profile());
    await chooseGoal(tester, 'Build');
    await tapSave(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing);
    final p = await storedProfile(tester);
    expect(p['primary_goal'], 'build_muscle');
    expect(p['target_weight_kg'], 78.0, reason: 'an untouched prefilled target saves exactly the seed');
    expect(p['daily_calories'], isNot(2000), reason: 'the targets follow the goal');
    expect(MigratedKey.read<bool>('prediction_stale'), isTrue,
        reason: 'a goal-only change marks the free prediction stale');
  });

  testWidgets('imperial: an untouched Save of a valid Maintain 75 / 78 kg pair neither refuses nor drifts',
      (tester) async {
    await boot(tester, _profile(goal: 'general_fitness', target: 78.0), metric: false);
    expect(textOf(tester, 'Weight (lbs)'), '165');
    expect(textOf(tester, 'Target Weight (lbs)'), '172');
    await tapSave(tester);
    expect(find.byKey(const ValueKey('target_weight_dialog')), findsNothing,
        reason: '165 / 172 lbs re-read as 74.84 / 78.02 kg (3.18 apart) without the stored-kg rule');
    final p = await storedProfile(tester);
    expect(p['current_weight_kg'], 75.0);
    expect(p['target_weight_kg'], 78.0);
  });

  testWidgets('a legacy strength profile with a valid target: an untouched Save is not a goal change',
      (tester) async {
    await boot(tester, _profile(goal: 'strength', target: 80.0));
    await tapSave(tester);
    expect(MigratedKey.read<bool>('prediction_stale'), isNot(true));
  });
}
