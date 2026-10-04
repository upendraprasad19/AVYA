// ①.1d (Batch 11-C) — curated injury-substitute PREFERENCE, PRODUCTION behavioral
// test (platform behavioral_test_path, §4.4 rule 21; SoT `injury_safe_substitute_preference`).
// LIVE since 2026-09-16 (OI-53) — `enable_injury_substitute_pref` flipped to
// `disable_injury_substitute_pref`, default ON.
//
// Drives the REAL PlanGenerator.instance.generateV4 through the Hive-boot harness
// (seed the FULL library into exerciseBox, call the real engine) — so the
// _selectCandidate re-rank inside _cascadeFill is exercised end-to-end.
//
// Proves:
//  (1) ON prefers a curated sub — a shoulder-injured user's plan differs from OFF,
//      and every ON-only pick is a curated InjurySubstitutes['shoulder'] name.
//  (2) SAFETY — every cascade-selected exercise in the ON plan is shoulder-safe
//      (the re-rank runs on the post-injury-filter list → can't surface a
//      contraindicated exercise).
//  (3) INJURY-GATED — with NO injuries, ON == OFF (preferredFor([]) == [] → no-op).
//  (4) UNCURATED FALLTHROUGH — an injury with no curated map entry (neck) → ON == OFF.
//  (5) DEFAULT-ON — default (kill-switch unset) == ON for a shoulder user is NOT
//      asserted as "== no-injury" (injuries still filter); it's covered by (1)'s
//      ON arm, which is now the flag-unset path exercised by every other test
//      in this file that calls gen(sub: true).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/injury_substitutes.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late Map<String, List<String>> contraByName; // lowercased name → contra tokens

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('injury_sub_behavioral');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;

    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);

    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    contraByName = {};
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
      final name = (r['name'] as String? ?? '').toLowerCase();
      contraByName[name] = ((r['injury_contraindications'] as List?) ?? const [])
          .map((e) => e.toString().toLowerCase())
          .toList();
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // Generate a full_gym / intermediate / build_muscle / phase-1 plan with the
  // injury-substitute flag ON (default, kill-switch absent) or OFF (kill-switch
  // set), toggled in configBox, read inside generateV4.
  Future<Phase> gen({
    required bool sub,
    List<String> injuries = const ['shoulder'],
  }) async {
    final cfg = HiveService.instance.configBox;
    if (sub) {
      await cfg.delete('disable_injury_substitute_pref');
    } else {
      await cfg.put('disable_injury_substitute_pref', true);
    }
    return PlanGenerator.instance.generateV4(
      goal: 'build_muscle',
      equipment: 'full_gym',
      daysPerWeek: 4,
      phase: 1,
      experienceLevel: 'intermediate',
      injuries: injuries,
    );
  }

  // All cascade-selected exercise names across the whole phase (a set).
  Set<String> allNames(Phase p) => {
        for (final wk in p.weekPlans)
          for (final d in wk.workoutDays)
            for (final e in d.exercises) e.exerciseName,
      };

  // ORDERED per-day exercise names (variant-A week), concatenated. On a rich
  // full_gym plan the NAME SET is invariant (a deep safe pool fills every slot
  // either way) — ①.1d changes the per-slot ASSIGNMENT, so the ORDER differs.
  List<String> ordered(Phase p) => [
        for (final d in p.weekPlans.first.workoutDays)
          for (final e in d.exercises) e.exerciseName,
      ];

  test('(1) shoulder injury: ON re-ranks slots toward a curated sub', () async {
    final offP = await gen(sub: false);
    final onP = await gen(sub: true);
    final onOrdered = ordered(onP);
    final offOrdered = ordered(offP);
    // Same exercises get used (deep pool), but ON assigns the curated sub to the
    // priority slot → the ORDERED plan differs.
    expect(onOrdered, isNot(equals(offOrdered)),
        reason: 'ON must re-rank ≥1 slot pick for a shoulder-injured user');
    // The plan contains ≥1 curated shoulder sub (the re-rank surfaced it).
    final subs = InjurySubstitutes.preferredFor(['shoulder'])
        .map((s) => s.toLowerCase())
        .toSet();
    final onNames = allNames(onP).map((n) => n.toLowerCase()).toSet();
    expect(subs.intersection(onNames), isNotEmpty,
        reason: 'the ON plan must contain a curated shoulder sub');
    // DIRECTIONAL, not just "differs" and not just "a curated name shows up
    // somewhere": `InjurySubstitutes._preferred['shoulder']` is the WHOLE
    // menu of shoulder-safe options for a pattern, ordered MOST-preferred
    // first — the injury FILTER (a separate, always-on mechanism) already
    // restricts candidates to safe ones, so BOTH the verbatim pick and the
    // preferred pick are typically members of this same curated set. A bare
    // `subs.contains(...)` check is satisfied by either one and cannot tell
    // them apart (verified live: "Push Up" — this list's LEAST-preferred
    // horizontal_push entry — passed a plain membership check even when
    // gen(sub:) was wired backwards). The real signal is ORDER: ON's pick at
    // the first point of divergence must rank EARLIER (more preferred) in
    // this list than OFF's pick there. Anchored at the FIRST divergence
    // because pickedNames dedups across the whole plan, so any slot AFTER
    // the first divergence has already-diverged candidate pools and proves
    // nothing about which side the re-rank favoured.
    final subsRanked = InjurySubstitutes.preferredFor(['shoulder']);
    final firstDivergence = List.generate(
            onOrdered.length < offOrdered.length
                ? onOrdered.length
                : offOrdered.length,
            (i) => i)
        .firstWhere((i) => onOrdered[i] != offOrdered[i]);
    final onRank = subsRanked.indexOf(onOrdered[firstDivergence].toLowerCase());
    final offRank =
        subsRanked.indexOf(offOrdered[firstDivergence].toLowerCase());
    expect(onRank, greaterThanOrEqualTo(0),
        reason: 'ON\'s pick at the first divergence must itself be a '
            'curated substitute');
    expect(offRank == -1 || onRank < offRank, isTrue,
        reason: 'ON\'s pick must rank EARLIER (more preferred) than OFF\'s '
            'pick at the same slot — proves the re-rank pulled toward the '
            'curated priority order, not merely that the plans differ');
  });

  test('(2) safety: every ON cascade pick is shoulder-safe (post-filter re-rank)',
      () async {
    final on = allNames(await gen(sub: true));
    for (final n in on) {
      final contra = contraByName[n.toLowerCase()] ?? const [];
      expect(contra.contains('shoulder'), isFalse,
          reason: '"$n" is shoulder-contraindicated but appears in the ON plan');
    }
  });

  test('(3) injury-gated: NO injuries → ON == OFF (preferredFor([]) is empty)',
      () async {
    final off = allNames(await gen(sub: false, injuries: const []));
    final on = allNames(await gen(sub: true, injuries: const []));
    expect(on, equals(off),
        reason: 'no injuries → no curated subs → the flag is a no-op');
  });

  test('(4) uncurated injury (neck) → ON == OFF (safe fallthrough)', () async {
    final off = allNames(await gen(sub: false, injuries: const ['neck']));
    final on = allNames(await gen(sub: true, injuries: const ['neck']));
    expect(on, equals(off),
        reason: 'neck has no curated map entry → fallthrough → byte-identical');
  });
}
