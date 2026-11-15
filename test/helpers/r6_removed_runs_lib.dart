// Unit 1B-F, Ruling 3 (docs/plans/2026-11-10-generator-1bf-flip.md): the CI hard test over the 2,637 runs where the
// deleted R6 refill used to act (test/fixtures/r6_removed_runs.txt, provenance in its header). Eight files, one per goal
// and domain (`r9`: the round-9 domain plus the 95 thin runs; `ext`: the round-10 extension), one `test()` per tier.
//
// Per run (the floor sweep's own `scan` and `expectSafe`): no empty day, no unsafe / unperformable / unresolved /
// duplicate pick, no retired, skill or olympic id, none of Ruling 12's 14 jump rows for a hip-injured run. Per test: the
// thin (1-2 exercises) and one-exercise day counts over weeks 1-2 are EXACT ratchets recorded on the final tree (a rise is
// a regression, a fall means the number here is stale), and the run count equals the fixture's. The ratchet is a NET
// count per tier: a run that thins while another fills stays green (B-pass seat C); the per-run zeros above are exact.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

import 'generator_golden_personas.dart' show namesByDay;
import 'injury_floor_sweep_lib.dart';

class R6Run {
  const R6Run(this.domain, this.block, this.tier, this.goal, this.level, this.days, this.phase, this.injuries);
  final String domain, block, tier, goal, level;
  final int days, phase;
  final List<String> injuries;
  String get label => '${injuries.join('+')}|$tier|$goal|$level|${days}d|p$phase|$block';
}

const kR6RunsFixture = 'test/fixtures/r6_removed_runs.txt';
const kR6Blocks = {'pairs', 'pairs_repeat', 'triples', 'pairs9_exclall', 'triples_eq', 'quads_all', 'all9_all'};

List<R6Run> loadR6Runs() => [
      for (final l in File(kR6RunsFixture).readAsLinesSync())
        if (l.isNotEmpty && !l.startsWith('#'))
          () {
            final f = l.split('|');
            if (f.length != 8 || !kR6Blocks.contains(f[1])) throw StateError('bad fixture line: $l');
            return R6Run(f[0], f[1], f[2], f[3], f[4], int.parse(f[5]), int.parse(f[6]), f[7].split('+'));
          }(),
    ];

/// Defines one test per tier of [domain] x [goal]. [ceilings] maps a tier to its exact (thin, one-exercise) day counts
/// and [runCounts] to its number of fixture runs; a tier present in the fixture but missing here fails.
void defineR6RemovedRunsTests(
  SweepHarness h, {
  required String domain,
  required String goal,
  required Map<String, int> runCounts,
  required Map<String, (int thin, int one)> ceilings,
}) {
  final all = loadR6Runs();
  final mine = all.where((r) => r.domain == domain && r.goal == goal).toList();
  test('fixture: $domain $goal runs per tier are the recorded counts', () {
    final byTier = <String, int>{};
    for (final r in mine) {
      byTier[r.tier] = (byTier[r.tier] ?? 0) + 1;
    }
    expect(all.length, 2637, reason: 'the whole fixture');
    expect(byTier, runCounts);
    expect(ceilings.keys.toSet(), runCounts.keys.toSet());
    // Every counted tier is one the per-tier tests below run (B-pass seat C): a typo would be counted, never run.
    expect(kSweepTiers.toSet().containsAll(runCounts.keys), isTrue, reason: '${runCounts.keys} vs $kSweepTiers');
  });
  for (final tier in kSweepTiers) {
    if (!runCounts.containsKey(tier)) continue;
    test('$domain $goal [$tier]: no empty day, no flagged pick, thin and one-exercise days at the recorded counts', () {
      final sw = Stopwatch()..start();
      final t = SweepTally();
      final pinCache = <String, Map<int, ({List<String> a, List<String> b})>>{};
      final excludeAll = EquipmentVocab.tierItems['bodyweight']!;
      for (final r in mine.where((r) => r.tier == tier)) {
        Map<int, ({List<String> a, List<String> b})>? pins;
        if (r.block == 'pairs_repeat') {
          pins = pinCache.putIfAbsent(
              '${r.goal}|${r.level}|${r.days}',
              () => namesByDay(h.gen(
                  tier: tier, goal: r.goal, level: r.level, days: r.days, phase: 1, injuries: const [])));
        }
        final Phase p = h.gen(
          tier: tier,
          goal: r.goal,
          level: r.level,
          days: r.days,
          phase: r.phase,
          injuries: r.injuries,
          pins: pins,
          exclusions: r.block == 'pairs9_exclall' ? excludeAll : const [],
        );
        h.scan(t, p, r.injuries, r.label, r.days, exclusions: r.block == 'pairs9_exclall' ? excludeAll : const []);
      }
      h.report('$domain $goal $tier', t, sw);
      expect(t.runs, runCounts[tier]);
      h.expectSafe(t);
      final c = ceilings[tier]!;
      expect((t.thin, t.oneExercise.length), c,
          reason: '$domain $goal $tier: (thin, one-exercise) days moved from the recorded $c; thin by ${t.thinBy}; '
              'one-exercise ${t.oneExercise.take(10).toList()}');
    });
  }
}
