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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart'
    show predictionProvider;
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

  Future<void> boot(WidgetTester tester, Map<String, dynamic> profile,
      {bool pro = false, bool dietStrategy = false, bool inShell = false}) async {
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
      await MigratedKey.delete('isPro');
      await MigratedKey.delete('expiresAt');
      if (pro) {
        await MigratedKey.write('isPro', true);
        await MigratedKey.write('expiresAt',
            DateTime.now().add(const Duration(days: 30)).toIso8601String());
      }
    });
    SyncService.pausedForSimulation = true;
    DietStrategyFlags.debugEnabledOverride = dietStrategy;
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

    final routes = <RouteBase>[
      GoRoute(path: '/', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const Scaffold(body: Text('PROFILE'))),
    ];
    // `inShell`: the app's shape, where the screen lives in a nested navigator
    // and a dialog sits on the root one, so a route change can remove the screen
    // while its question stays up.
    router = GoRouter(
        routes: inShell
            ? [ShellRoute(builder: (_, __, child) => child, routes: routes)]
            : routes);
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

  /// [settle] until [done] holds (bounded), then once more: the Save writes to disk
  /// in real time, which a loaded machine does not finish in a fixed number of rounds.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 20 && !done(); i++) {
      await settle(tester, rounds: 2);
    }
    await settle(tester);
  }

  // Two sinks: the Save's own failure event, and the non-fatal the profile-surface refresh logs
  // for one provider (it catches each failure so one bad provider never stops the rest).
  bool reportedUnmountedRef() =>
      events.any((e) =>
          e.op == 'profile_edit_save_failed' && (e.message ?? '').contains('unmounted')) ||
      nonFatals.any((s) => s.contains('unmounted'));

  /// EVERY Save failure, not only the unmounted-ref one: a Save that stops half way
  /// for any reason must show up here.
  List<String> saveFailures() => [
        for (final e in events)
          if (e.op == 'profile_edit_save_failed') e.message ?? ''
      ];

  bool skippedReschedule() =>
      events.any((e) => e.op == 'profile_edit_reschedule_skipped_closed');

  /// Closes the screen (the app's ProviderScope stays).
  Future<void> closeScreen(WidgetTester tester) async {
    router.go('/profile');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Map<dynamic, dynamic>> storedProfile(WidgetTester tester) async =>
      Map<dynamic, dynamic>.from((await tester.runAsync(
          () async => HiveService.instance.userBox.get('profile')))! as Map);

  ProviderContainer appContainer(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

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
    await settleUntil(
        tester,
        () => (HiveService.instance.userBox.get('profile') as Map)['daily_calories'] != 2000);

    final after = Map<dynamic, dynamic>.from(
        (await tester.runAsync(() async => HiveService.instance.userBox.get('profile')))! as Map);
    expect(after['pace_preference'], isNot('balanced'), reason: 'the edit itself was written');
    expect(after['daily_calories'], isNot(2000),
        reason: 'recalculateTargets ran after the screen closed');
    expect(reportedUnmountedRef(), isFalse,
        reason: 'events were $events, non-fatals were $nonFatals');
    expect(saveFailures(), isEmpty);
    expect(skippedReschedule(), isFalse,
        reason: 'mirror: no plan, so no reschedule was owed');
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
    expect(saveFailures(), isEmpty);
    expect((await storedProfile(tester))['days_per_week'], 5,
        reason: 'the plan-affecting edit was really saved');
    expect(skippedReschedule(), isTrue,
        reason: 'the plan keeps its old days: that must be recorded');
  });

  testWidgets('a target change closed right after SAVE still refreshes the prediction card',
      (tester) async {
    await boot(tester, _profile());
    final container = appContainer(tester);
    final sub = container.listen(predictionProvider, (_, __) {});
    addTearDown(sub.close);
    expect(container.read(predictionProvider).isStale, isFalse);

    final target = find.widgetWithText(TextField, 'Target Weight (kg)');
    await tester.ensureVisible(target);
    await tester.enterText(target, '72.0');
    await tester.pump();
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await closeScreen(tester);
    await settle(tester);

    expect(saveFailures(), isEmpty);
    expect((await storedProfile(tester))['target_weight_kg'], 72.0);
    // A free account marks the prediction stale; only invalidating the provider
    // after that makes the already-open card say so.
    expect(container.read(predictionProvider).isStale, isTrue);
  });

  const assessment = <String, dynamic>{
    'body_fat_percent': 18.0,
    'body_fat_assessed_at': '2026-11-26T04:00:00.000Z',
    'body_fat_range': '16-20%',
  };

  testWidgets('a body-fat result is stored even after the screen has closed',
      (tester) async {
    await boot(tester, _profile());
    final container = appContainer(tester);
    await closeScreen(tester);

    final saved = await tester.runAsync(() => saveBodyFatAssessment(
        container: container,
        ownerAtStart: _user,
        ownerNow: _user,
        updates: Map<String, dynamic>.from(assessment)));
    await settle(tester);

    expect(saved, isTrue);
    expect((await storedProfile(tester))['body_fat_percent'], 18.0);
  });

  testWidgets('mirror: a body-fat result is NOT written when the account changed',
      (tester) async {
    await boot(tester, _profile());
    final container = appContainer(tester);

    final saved = await tester.runAsync(() => saveBodyFatAssessment(
        container: container,
        ownerAtStart: _user,
        ownerNow: 'aaaa0000-0000-0000-0000-000000000000',
        updates: Map<String, dynamic>.from(assessment)));
    await settle(tester);

    expect(saved, isFalse);
    expect((await storedProfile(tester))['body_fat_percent'], isNull);
    expect(events.any((e) => e.op == 'body_fat_assessment_owner_changed'), isTrue);
  });

  testWidgets(
      'the screen removed while the reschedule question is open: Reschedule skips and says so',
      (tester) async {
    await boot(tester, _profile(), inShell: true);
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
    await settle(tester);
    expect(find.text('Reschedule Workouts?'), findsOneWidget);
    expect(skippedReschedule(), isFalse, reason: 'the question is on screen');

    await closeScreen(tester);
    expect(find.byType(EditProfileScreen), findsNothing);
    await tester.tap(find.text('Reschedule'));
    await settle(tester);

    expect(skippedReschedule(), isTrue);
    expect(saveFailures(), isEmpty);
    expect(
        (await tester.runAsync(() async =>
            HiveService.instance.workoutBox.get('current_plan')) as Map)['plan'],
        'x',
        reason: 'no regeneration ran for a screen that is gone');
  });

  // ── Body fat: a result that lands while the form is open ─────────────────

  Map<String, dynamic> withBodyFat() => <String, dynamic>{
        ..._profile(),
        'body_fat_percent': 22.0,
        'body_fat_assessed_at': '2026-09-01T04:00:00.000Z',
      };

  final bodyFatField = find.widgetWithText(TextField, 'Body Fat % (optional)');

  String bodyFatText(WidgetTester tester) =>
      tester.widget<TextField>(bodyFatField).controller!.text;

  /// A result stored from an earlier, closed copy of the screen.
  Future<void> landResult(WidgetTester tester) async {
    final container = appContainer(tester);
    await tester.runAsync(() => saveBodyFatAssessment(
        container: container,
        ownerAtStart: _user,
        ownerNow: _user,
        updates: Map<String, dynamic>.from(assessment)));
    await settle(tester);
  }

  Future<void> editCityAndSave(WidgetTester tester) async {
    final city = find.widgetWithText(TextField, 'City');
    await tester.ensureVisible(city);
    await tester.enterText(city, 'Pune');
    await tester.pump();
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await tester.pump();
  }

  testWidgets('a result landing while the form is open is shown and survives SAVE',
      (tester) async {
    await boot(tester, withBodyFat());
    expect(bodyFatText(tester), '22.0');

    await landResult(tester);
    expect(bodyFatText(tester), '18.0');
    expect(find.text('Last assessed: 26 Nov 2026'), findsOneWidget);

    await editCityAndSave(tester);
    await settle(tester);

    final stored = await storedProfile(tester);
    expect(stored['city'], 'Pune', reason: 'the Save really ran');
    expect(stored['body_fat_percent'], 18.0);
    expect(stored['body_fat_assessed_at'], '2026-11-26T04:00:00.000Z');
  });

  testWidgets(
      'a result landing while SAVE is asking about the diet strategy is not written over',
      (tester) async {
    await boot(tester, withBodyFat(), pro: true, dietStrategy: true);
    final keto = find.text('Keto');
    await tester.ensureVisible(keto.first);
    await tester.tap(keto.first);
    await tester.pump();
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await settle(tester);
    final confirm = find.byKey(const ValueKey('diet_strategy_confirm_switch'));
    expect(confirm, findsOneWidget, reason: 'the Save is waiting on the question');

    // The Save has already collected what it will write.
    await landResult(tester);
    await tester.tap(confirm);
    await settle(tester);

    final stored = await storedProfile(tester);
    expect(stored['diet_strategy'], 'keto', reason: 'the Save really ran');
    expect(stored['body_fat_percent'], 18.0);
    expect(stored['body_fat_assessed_at'], '2026-11-26T04:00:00.000Z');
  });

  testWidgets('mirror: a body-fat value the user typed is saved', (tester) async {
    await boot(tester, withBodyFat());
    await tester.ensureVisible(bodyFatField);
    await tester.enterText(bodyFatField, '15');
    await tester.pump();

    await editCityAndSave(tester);
    await settle(tester);

    expect((await storedProfile(tester))['body_fat_percent'], 15.0);
  });

  testWidgets('mirror: a typed value is not replaced by a result that lands after it',
      (tester) async {
    await boot(tester, withBodyFat());
    await tester.ensureVisible(bodyFatField);
    await tester.enterText(bodyFatField, '15');
    await tester.pump();

    await landResult(tester);
    expect(bodyFatText(tester), '15');
    await editCityAndSave(tester);
    await settle(tester);

    expect((await storedProfile(tester))['body_fat_percent'], 15.0);
  });

  // ── Body fat: the REAL AI Assess flow ────────────────────────────────────
  // The photo picker is answered on its platform channel and the Edge Function
  // by a loopback server, so the real `functions.invoke` runs.

  const otherUser = 'aaaa0000-0000-0000-0000-000000000000';
  const result = <String, Object?>{
    'bf_low': 16,
    'bf_high': 20,
    'confidence': 'medium',
    'assessed_at': '2026-11-26T04:00:00.000Z',
  };

  /// Taps AI Assess and returns once the function has been called; the answer is
  /// held back until the returned callback runs.
  Future<Future<void> Function()> startAssessment(
      WidgetTester tester, int status, Map<String, Object?> body) async {
    late HttpServer server;
    final answer = Completer<void>();
    var hits = 0;
    await tester.runAsync(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        if (req.uri.path.endsWith('/functions/v1/assess-body-composition')) {
          hits++;
          await answer.future;
          req.response.statusCode = status;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(body));
        } else {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write('{}');
        }
        await req.response.close();
      });
      final client = SupabaseClient(
          'http://127.0.0.1:${server.port}', 'anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false));
      await client.auth.setInitialSession(jsonEncode(<String, dynamic>{
        'access_token': 'stub-access-token',
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': DateTime.now()
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch ~/
            1000,
        'refresh_token': 'stub-refresh-token',
        'user': <String, dynamic>{
          'id': _user,
          'aud': 'authenticated',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }));
      SupabaseService.clientOverrideForTest = client;
    });
    addTearDown(() async {
      await tester.runAsync(() => server.close(force: true));
    });

    final photo = File('${tempDir.path}/body.jpg')..writeAsBytesSync([1, 2, 3]);
    const picker = MethodChannel('plugins.flutter.io/image_picker');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        picker, (call) async => call.method == 'pickImage' ? photo.path : null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, null));

    final button = find.text('AI Assess');
    await tester.ensureVisible(button);
    await tester.runAsync(() async {
      await tester.tap(button);
    });
    for (var i = 0; i < 100 && hits == 0; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(hits, 1, reason: 'the real flow reached the Edge Function');
    return () async {
      await tester.runAsync(() async => answer.complete());
      await settle(tester, rounds: 16);
    };
  }

  testWidgets('AI Assess: the screen closed during the call, the result is still stored',
      (tester) async {
    await boot(tester, withBodyFat(), pro: true);
    final reply = await startAssessment(tester, 200, result);
    await closeScreen(tester);
    await reply();

    final stored = await storedProfile(tester);
    expect(stored['body_fat_percent'], 18.0);
    expect(stored['body_fat_assessed_at'], '2026-11-26T04:00:00.000Z');
    expect(stored['body_fat_range'], '16-20%');
    expect(nonFatals.where((s) => s.startsWith('body_fat_assessment')), isEmpty,
        reason: '$nonFatals');
  });

  testWidgets(
      'AI Assess mirror: another account signed in during the call gets nothing',
      (tester) async {
    await boot(tester, withBodyFat(), pro: true);
    final reply = await startAssessment(tester, 200, result);
    await tester.runAsync(() async {
      await HiveUserSession.openForUser(otherUser);
      await HiveService.instance.userBox.clear();
    });
    await reply();

    final theirs = await tester.runAsync(
        () async => HiveService.instance.userBox.get('profile')) as Map?;
    expect(theirs?['body_fat_percent'], isNull, reason: 'stored: $theirs');
    expect(bodyFatText(tester), '22.0',
        reason: 'the open form must not take another account\'s result');
    expect(events.any((e) => e.op == 'body_fat_assessment_owner_changed'), isTrue,
        reason: '$events');

    await tester.runAsync(() => HiveUserSession.openForUser(_user));
    expect((await storedProfile(tester))['body_fat_percent'], 22.0,
        reason: 'the account that asked is left as it was');
  });

  testWidgets('AI Assess: the monthly limit says when the next one is allowed',
      (tester) async {
    await boot(tester, withBodyFat(), pro: true);
    final reply = await startAssessment(tester, 429, const {
      'error': 'Body composition can only be assessed once every 30 days.',
      'code': 'rate_limited',
      'next_allowed_at': '2026-12-20T10:00:00.000Z',
    });
    await reply();

    expect(find.text('Next assessment available: 20 Dec 2026'), findsOneWidget,
        reason: 'events were $events, non-fatals were $nonFatals');
    expect(nonFatals.where((s) => s.startsWith('body_fat_assessment')), isEmpty,
        reason: 'an expected refusal is not an error report');
  });
}
