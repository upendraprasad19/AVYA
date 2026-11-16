// Unit 3C (OI-396, founder d77 / d78; plan docs/plans/2026-11-16-generator-step3c-cardio-finisher.md §2.1): an injury
// the user tells the coach about (`modifyWorkoutForInjury`, confirmed) is saved to `profile['injuries']` as its canonical
// token, through the REAL `ToolDispatcher.execute`, so the finisher rule (the profile is its only signal) and every later
// plan see it. Coach memory alone was erased by the snapshot mirror seconds later (round 5).
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/injury_swap_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/finisher_safety.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/finisher_show_context.dart';

import '../helpers/hive_test_setup.dart';

final _refProvider = Provider<Ref>((ref) => ref);

var _n = 0;
ToolIntent _injury(String part) => ToolIntent(
      id: 'c3c_injury_${_n++}',
      type: 'modify_workout_for_injury',
      payload: {'bodyPart': part, 'severity': 'mild'},
      confirmationClass: ConfirmationClass.destructive,
      previewSummary: 'test',
      createdAt: DateTime.now(),
    );

Future<void> _profile(Object? injuries) => HiveService.instance.userBox.put('profile', {
      'primary_goal': 'lose_fat',
      'injuries': ?injuries,
    });

Object? _injuries() => (HiveService.instance.userBox.get('profile') as Map?)?['injuries'];

void main() {
  late Directory dir;
  late ProviderContainer container;
  late List<String> calls;

  setUp(() async {
    dir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    SwapService.debugOnPlanPushForTests = () {};
    container = ProviderContainer();
    calls = [];
    ToolDispatcher.lockFields = (fields) async => calls.add('lock:${fields.join(',')}');
    ToolDispatcher.lockFieldsTimeout = const Duration(seconds: 4);
  });

  tearDown(() async {
    container.dispose();
    ToolDispatcher.lockFields = (fields) async {};
    ToolDispatcher.lockFieldsTimeout = const Duration(seconds: 4);
    SyncService.pausedForSimulation = false;
    SwapService.debugOnPlanPushForTests = null;
    await tearDownHiveForTests(dir);
  });

  /// Confirms [intent] with no upcoming day to change (an empty swap plan cached, as the preview caches it).
  Future<ToolExecutionResult> run(ToolIntent intent, {List<InjurySwap> swaps = const []}) {
    InjurySwapPlanner.instance.cacheSwaps(intent.id, swaps);
    return ToolDispatcher.instance.execute(container.read(_refProvider), intent);
  }

  test('knee on a none profile: saved as [knee], the field locked, the result says so', () async {
    await _profile(const ['none']);
    final res = await run(_injury('knee'));
    expect(res.success, isTrue, reason: '${res.errorMessage}');
    expect(_injuries(), ['knee']);
    expect(calls, ['lock:injuries']);
    expect((res.data! as Map)['profile_injury_added'], 'knee');
  });

  test('the four parts with no token map to the nearest joint (d78)', () async {
    for (final (part, token) in const [('quad', 'knee'), ('calf', 'ankle'), ('chest', 'shoulder'), ('upper_back', 'shoulder')]) {
      await _profile(const ['none']);
      final res = await run(_injury(part));
      expect(_injuries(), [token], reason: part);
      expect((res.data! as Map)['profile_injury_added'], token, reason: part);
    }
  });

  test('already held (a legacy alias too): nothing written, no lock', () async {
    await _profile(const ['back']);
    final res = await run(_injury('lower_back'));
    expect(_injuries(), ['back']);
    expect(calls, isEmpty);
    expect((res.data! as Map).containsKey('profile_injury_added'), isFalse);
  });

  test('no profile: nothing written', () async {
    final res = await run(_injury('knee'));
    expect(res.success, isTrue);
    expect(HiveService.instance.userBox.get('profile'), isNull);
    expect(calls, isEmpty);
  });

  test('a lock that never answers does not hold the tool (timeout)', () async {
    await _profile(const ['none']);
    ToolDispatcher.lockFieldsTimeout = const Duration(milliseconds: 50);
    ToolDispatcher.lockFields = (_) => Completer<void>().future;
    final res = await run(_injury('knee')).timeout(const Duration(seconds: 10));
    expect(res.success, isTrue);
    expect(_injuries(), ['knee']);
  });

  test('a lock that throws is non-fatal', () async {
    await _profile(const ['none']);
    ToolDispatcher.lockFields = (_) async => throw StateError('offline');
    final res = await run(_injury('knee'));
    expect(res.success, isTrue);
    expect(_injuries(), ['knee']);
  });

  test('every swap failed: the injury is still saved, the reply says so, the profile readers refresh', () async {
    await _profile(const ['none']);
    expect(container.read(userProfileProvider)['injuries'], ['none'], reason: 'the provider read before the tool');
    final day = istDateStr(DateTime.now());
    // A swap whose day has no row: SwapService refuses it.
    final res = await run(_injury('knee'), swaps: [
      InjurySwap(date: day, fromId: 'nope', fromName: 'Nope', toId: 'also_nope', toName: 'Also Nope'),
    ]);
    expect(res.success, isFalse);
    expect(res.errorMessage, "Couldn't change your workouts. Knee was added to your injuries.");
    expect((res.data! as Map)['profile_injury_added'], 'knee');
    expect(_injuries(), ['knee']);
    expect(container.read(userProfileProvider)['injuries'], ['knee'],
        reason: 'execute invalidates the profile providers before the failure early return');
  });

  test('the profile provider re-reads the new token after execute (invalidation)', () async {
    await _profile(const ['none']);
    final before = container.read(userProfileProvider);
    expect(before['injuries'], ['none']);
    await run(_injury('knee'));
    expect(container.read(userProfileProvider)['injuries'], ['knee']);
  });

  test('two injuries confirmed together keep both tokens (20 trials)', () async {
    for (var i = 0; i < 20; i++) {
      await _profile(const ['none']);
      await Future.wait([run(_injury('knee')), run(_injury('shoulder'))]);
      expect((_injuries()! as List).toSet(), {'knee', 'shoulder'}, reason: 'trial $i');
    }
  });

  test('an owner captured before the swap loop that no longer matches writes nothing', () async {
    await _profile(const ['none']);
    final added = await ToolDispatcher.instance
        .saveCoachInjuryToProfileForTest('knee', owner: 'cccccccc-0000-0000-0000-000000000000');
    expect(added, isNull);
    expect(_injuries(), ['none']);
    expect(calls, isEmpty);
    // The live owner writes.
    expect(await ToolDispatcher.instance
        .saveCoachInjuryToProfileForTest('knee', owner: HiveUserSession.currentOwnerFullId), 'knee');
  });

  test('an account switch after the swap loop: the owner captured at handler start refuses the write (seat B F2)',
      () async {
    await _profile(const ['none']);
    final first = HiveUserSession.currentOwnerFullId;
    const second = 'dddddddd-0000-0000-0000-000000000000';
    // The switch lands where a real one would: after the swaps, before the profile write. The second account has a
    // `none` profile, so a write that read the owner at write time instead would land there.
    ToolDispatcher.debugAfterInjurySwapLoop = () async {
      await HiveUserSession.openForUser(second);
      await _profile(const ['none']);
    };
    addTearDown(() => ToolDispatcher.debugAfterInjurySwapLoop = null);
    final res = await run(_injury('knee'));
    expect((res.data! as Map).containsKey('profile_injury_added'), isFalse);
    expect(_injuries(), ['none'], reason: 'the second account was not written');
    expect(calls, isEmpty, reason: 'no lock');
    await HiveUserSession.openForUser(first!);
    expect(_injuries(), ['none'], reason: 'nor the first');
  });

  test('after a snapshot mirror replaces coach memory, the profile still hides a jumping finisher', () async {
    await _profile(const ['none']);
    await run(_injury('calf'));
    // The mirror: the server copy, without the tool's local {part} entry.
    await CoachMemory(userId: 'u').writeToBox(HiveService.instance.coachBox);
    final hiit = [
      {'exercise_name': 'Burpees', 'sets': 3, 'duration_seconds': 120},
    ];
    final ctx = FinisherShowContextReader.read();
    expect(ctx.injured, isTrue);
    expect(FinisherSafety.shownFinisherMaps(hiit, enabled: ctx.enabled, injured: ctx.injured), isEmpty);
  });
}
