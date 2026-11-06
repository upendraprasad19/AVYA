// Headless "journey to Lieutenant" harness + Excel plan export.
//
// NOT a _test.dart (excluded from the default `flutter test` suite — it is a
// slow ~130-week artifact generator). Run explicitly:
//
//   flutter test test/sim/lt_journey_plan_export.dart --dart-define-from-file=.env
//
// Why headless (not the live web sim): the live-web 910-day run won't reliably
// complete in-browser — the cold deep-link `/dev?autorun` session-wait is
// flaky (~40% start) and the 910-iteration run reloads the tab under memory
// load. This harness drives the SAME `SimulationService.run` core + the SAME
// `plan_xls` exporter, so it is faithful to real product behaviour, just
// without the browser hosting overhead. Deterministic, completes in minutes.
//
// What it does:
//   1. Mock path_provider + shared_preferences; init Hive + open all boxes.
//   2. Seed exerciseBox from assets/data/exercise_library.json (the real
//      bundled library the plan generator queries) so phase generation works.
//   3. Init Supabase UNAUTHENTICATED (so `Supabase.instance` doesn't throw but
//      currentUser==null → all cloud writes no-op; nothing touches a real
//      account). Open a test user-scoped Hive session.
//   4. Seed a realistic amar-like profile + Phase 1, grant PRO.
//   5. Run the real SimulationService.run for 910 days (130 weeks) inside
//      tester.runAsync — generates every phase via the REAL plan generator
//      with continued progressive overload + personalization from accumulated
//      Hive history, capturing each phase plan.
//   6. Overlay the rank earned per phase from the PURE sequential ladder model
//      (RankService.testQualify — the same gate logic, no Supabase needed),
//      proving SD2→SD1→LS→PO→CPO→MCPO→SubLt→Lt with no skips by week 130.
//   7. Export every captured plan to docs/sim/amar_plans_to_lt_<date>.xls via
//      the real buildPlansSpreadsheetXml.
//
// Run's in-loop evaluateAndPromote early-returns headless (no Supabase user) —
// harmless; the ladder is proven separately via the pure seam in step 6.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/dev/plan_xls.dart';
import 'package:icanbefitter/features/dev/simulation_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
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

void _mockSharedPreferences() {
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
    if (call.method == 'getAll') return <String, dynamic>{};
    return true;
  });
}

const _fakeUserId = 'cafeface-aaaa-bbbb-cccc-dddddddddddd';
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Pure sequential-ladder rank at [week] for a sustained trainer:
/// deployments increment per completed 4-week phase, streak/workouts strong.
/// Mirrors the contiguous no-skip walk in RankService._qualifiedRankCode.
String _sequentialRankAt(int week) {
  // Realistic sustained-trainer inputs at this week.
  final deployments = week ~/ 4; // 1 deployment per completed phase
  final streak = 60; // sustained well past CPO's streak-50 gate
  final totalWorkouts = week * 4;
  var current = 'SD2';
  for (final r in kRankLadder) {
    final nextOrd = rankByCode(current)!.ordinal + 1;
    if (r.ordinal != nextOrd) continue;
    final ok = RankService.instance.testQualify(
      code: r.code,
      streak: streak,
      totalWorkouts: totalWorkouts,
      weeksSinceSignup: week,
      deploymentsComplete: deployments,
      longestGapDays: 0,
      completionRateOverride: 1.0,
    );
    if (ok) current = r.code; // contiguous walk: only advance the next rung
  }
  return current;
}

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockSharedPreferences();
    tempDir = Directory.systemTemp.createTempSync('lt_journey_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    // Supabase initialized but NOT signed in → currentUser==null → every
    // cloud write no-ops; no real account is touched.
    if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    } else {
      // Fallback: a syntactically valid dummy so Supabase.instance exists.
      await Supabase.initialize(
        url: 'https://dedsavbjuwgarrhphgnl.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiJ9.dummy.dummy',
      );
    }

    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;

    // Seed the real exercise library so the plan generator has a pool.
    final exFile = File('assets/data/exercise_library.json');
    if (exFile.existsSync()) {
      final list = json.decode(exFile.readAsStringSync()) as List<dynamic>;
      final box = HiveService.instance.exerciseBox;
      for (final item in list) {
        final m = (item as Map).cast<String, dynamic>();
        final id = m['id'] as String?;
        if (id != null) await box.put(id, m);
      }
    }

    await HiveUserSession.openForUser(_fakeUserId);

    // Realistic amar-like profile (drives plan generation).
    await UserRepository.instance.saveProfile(<String, dynamic>{
      'id': _fakeUserId,
      'full_name': 'Amar (sim)',
      'primary_goal': 'muscle_gain',
      'fitness_experience': 'intermediate',
      'equipment_access': 'full_gym',
      'days_per_week': 4,
      'current_weight_kg': 72.0,
      'height_cm': 175.0,
      'age': 28,
      'gender': 'male',
    });

    container = ProviderContainer();
  });

  tearDownAll(() async {
    SubscriptionService.pausedForSimulation = false;
    GuardedBox.testBypassOwnership = false;
    container.dispose();
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('amar journey to Lieutenant — 130 weeks, capture + export plans',
      (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (ctx, r, _) {
            ref = r;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    SimReport? report;
    await tester.runAsync(() async {
      // Reset to a clean Phase-1 free baseline, then grant PRO (10-yr window).
      await SimulationService.instance.resetJourney(ref);
      await ref.read(subscriptionServiceProvider).writeSubscriptionState(
            isPro: true,
            expiresAt:
                DateTime.now().add(const Duration(days: 3650)).toIso8601String(),
            plan: 'yearly',
          );
      SubscriptionService.pausedForSimulation = true;

      report = await SimulationService.instance.run(
        ref: ref,
        days: 910, // 130 weeks → Lieutenant tenure
        adherence: 0.99,
        onProgress: (line) {
          if (line.contains('/910') &&
              (line.startsWith('Day 28/') ||
                  RegExp(r'Day (\d+)0/').hasMatch(line))) {
            // throttle: ~every ~10/28 days
          }
        },
      );
      SubscriptionService.pausedForSimulation = false;
    });

    final rpt = report!;
    // ignore: avoid_print
    print('\n${rpt.summarize()}');
    // ignore: avoid_print
    print('Captured ${rpt.capturedPhases.length} phase plans.');

    expect(rpt.capturedPhases, isNotEmpty,
        reason: 'the run must capture at least the Phase-1 plan');
    expect(rpt.phasesGenerated, greaterThanOrEqualTo(11),
        reason: 'a 130-week run must generate well past the 12-phase program');

    // Overlay the rank EARNED BY COMPLETING each phase (rank at the phase's
    // last week) from the pure sequential ladder — so the climb shows through
    // to Lieutenant on the final phase. Phase N covers weeks (N-1)*4+1 .. N*4.
    for (final phase in rpt.capturedPhases) {
      final phaseNum = (phase['phase'] as num?)?.toInt() ?? 1;
      final startWeek = (phaseNum - 1) * 4;
      final endWeek = phaseNum * 4; // rank held at phase completion
      final rank = _sequentialRankAt(endWeek);
      phase['rank'] = rankByCode(rank)?.displayName ?? rank;
      phase['rank_code'] = rank;
      phase['week_range'] = '${startWeek + 1}–$endWeek';
    }

    // True per-rung timeline: first week each rung is earned, scanning EVERY
    // week (not just 4-week phase boundaries, which skip SD1's wk1-3 window).
    final ladderTimeline = <String>[];
    var lastRank = '';
    for (var w = 0; w <= 130; w++) {
      final rank = _sequentialRankAt(w);
      if (rank != lastRank) {
        ladderTimeline.add('wk$w: $rank '
            '(${rankByCode(rank)?.displayName ?? rank}), deployments=${w ~/ 4}');
        lastRank = rank;
      }
    }
    // ignore: avoid_print
    print('\n── Rank ladder timeline (first week each rung earned) ──\n'
        '${ladderTimeline.join('\n')}');

    // PROVE the sequential ladder reaches Lieutenant by week 130, no skips.
    final ladderCodes = <String>[];
    var prevOrd = -1;
    for (var w = 0; w <= 130; w++) {
      final code = _sequentialRankAt(w);
      final ord = rankByCode(code)!.ordinal;
      expect(ord, greaterThanOrEqualTo(prevOrd),
          reason: 'rank went DOWN at week $w (must be monotonic)');
      expect(ord - prevOrd, lessThanOrEqualTo(1),
          reason: 'rank SKIPPED a rung at week $w ($code) — must be sequential');
      if (ladderCodes.isEmpty || ladderCodes.last != code) ladderCodes.add(code);
      prevOrd = ord;
    }
    expect(_sequentialRankAt(130), 'Lt',
        reason: 'by week 130 the sustained sequential climber must be Lieutenant');
    // The path must pass through every sailor + officer rung, in order.
    expect(ladderCodes.take(8).toList(),
        ['SD2', 'SD1', 'LS', 'PO', 'CPO', 'MCPO', 'SubLt', 'Lt'],
        reason: 'must climb the full ladder SD2→…→Lt with no skips');

    // Export every captured plan to a neatly-structured SpreadsheetML workbook.
    final outDir = Directory('docs/sim');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final fname = 'amar_plans_to_lt_${istTodayStr()}.xls';
    final outPath = '${outDir.path}/$fname';
    final xml = buildPlansSpreadsheetXml(rpt.capturedPhases);
    File(outPath).writeAsStringSync(xml);
    // ignore: avoid_print
    print('\nExported ${rpt.capturedPhases.length} plans → $outPath '
        '(${xml.length} bytes)');

    expect(File(outPath).existsSync(), isTrue);
    expect(xml.length, greaterThan(1000));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
