// Tests for scripts/context_budget_lib.dart — the pure half of
// `check_context_artifact_budget.dart`.
//
// Written to REDDEN when the gate's protection is neutered, not merely to
// exercise the happy path (§4.4 rule 24). The three protective legs each have a
// test that fails if that leg is removed:
//
//   1. the hard band          — delete it and everything degrades to warn
//   2. fail-open on unknowns  — treat an unreadable file as a breach instead
//   3. the key-set UNION      — iterate baselines only and a newly tracked
//                               artifact escapes the budget silently
//   4. the SHRINK floor       — drop it and a file truncated to zero bytes
//                               reports a clean PASS
//
// Leg 4 exists because review round 1 found it missing: the first version
// treated every negative drift as ok, so a CLAUDE.md truncated to 0 B was
// indistinguishable from no drift. The ONE shrink test at the time exercised a
// proportionate 45% reclaim — green under the bug, which is exactly the
// author-blind-spot shape §4.12 warns about.
//
// Boundary cases are pinned with `>` / `<` semantics deliberately: exactly-at-band
// is NOT a breach, so a `>=` typo reddens.

import 'package:test/test.dart';

import '../../scripts/context_budget_lib.dart';

void main() {
  group('evaluateOne — bands', () {
    test('growth inside the soft band is ok', () {
      final f = evaluateOne('a', baseline: 1000, actual: 1100); // +10%
      expect(f.status, BudgetStatus.ok);
      expect(f.drift, closeTo(0.10, 1e-9));
    });

    test('a DELIBERATE reclaim stays ok — the real -45.5% from this batch', () {
      // open_issues.md 357,664 -> 194,850 B. A gate that fired on its own
      // reclaim would be worse than useless, so the shrink floor sits BELOW
      // this real value on purpose. If someone tightens kSoftShrink past
      // -45.5%, this reddens and tells them why.
      final f = evaluateOne('a', baseline: 357664, actual: 194850);
      expect(f.status, BudgetStatus.ok);
      expect(f.drift, closeTo(-0.4552, 1e-3));
      expect(f.driftLabel, startsWith('-'));
    });

    test('TRUNCATED TO ZERO fails — reddens if the shrink floor is removed', () {
      // THE MIRROR CASE. Round 1's finding, verbatim: a CLAUDE.md truncated to
      // 0 B reported "PASS: 3 within band". Delete the hardShrink branch and
      // this returns ok again.
      final f = evaluateOne('CLAUDE.md', baseline: 95297, actual: 0);
      expect(f.status, BudgetStatus.fail,
          reason: 'losing a governing file whole must never read as clean');
      expect(f.drift, closeTo(-1.0, 1e-9));
    });

    test('losing most of a file warns before it fails', () {
      // -60%: past the soft floor, inside the hard one. Warns, never blocks —
      // the next person archiving a pile of closed entries must not be stopped.
      expect(evaluateOne('a', baseline: 1000, actual: 400).status,
          BudgetStatus.warn);
    });

    test('EXACTLY at each shrink floor is the gentler verdict', () {
      expect(evaluateOne('a', baseline: 1000, actual: 500).status,
          BudgetStatus.ok, reason: '-50.0% exactly is not yet a warn');
      expect(evaluateOne('a', baseline: 1000, actual: 100).status,
          BudgetStatus.warn, reason: '-90.0% exactly is not yet a fail');
    });

    test('a hard shrink BLOCKS, same as a hard growth', () {
      expect(anyBlocking(evaluateAll({'a': 1000}, {'a': 5})), isTrue);
    });

    test('past the soft band warns', () {
      final f = evaluateOne('a', baseline: 1000, actual: 1200); // +20%
      expect(f.status, BudgetStatus.warn);
    });

    test('EXACTLY at the soft band is ok, not a warn', () {
      expect(evaluateOne('a', baseline: 1000, actual: 1150).status,
          BudgetStatus.ok);
    });

    test('past the hard band FAILS — reddens if the hard band is removed', () {
      final f = evaluateOne('a', baseline: 1000, actual: 1600); // +60%
      expect(f.status, BudgetStatus.fail,
          reason: 'delete the hardBand branch and this degrades to warn');
    });

    test('EXACTLY at the hard band warns, does not fail', () {
      expect(evaluateOne('a', baseline: 1000, actual: 1500).status,
          BudgetStatus.warn);
    });

    test('the real drift this gate was born from lands well past hard', () {
      // OPEN_INDEX.md 3,759 -> 18,958 B between 2026-07-29 and 2026-08-30.
      final f = evaluateOne('docs/audit/OPEN_INDEX.md',
          baseline: 3759, actual: 18958);
      expect(f.status, BudgetStatus.fail);
      expect(f.drift, greaterThan(4.0)); // +404%
    });

    test('custom bands are honoured', () {
      final f = evaluateOne('a',
          baseline: 100, actual: 105, softBand: 0.01, hardBand: 0.02);
      expect(f.status, BudgetStatus.fail);
    });
  });

  group('evaluateOne — fails open', () {
    test('an unreadable file is SKIPPED, never a breach', () {
      final f = evaluateOne('a', baseline: 1000, actual: null);
      expect(f.status, BudgetStatus.skipped,
          reason: 'treating unreadable as fail would wedge every commit');
      expect(f.reason, contains('not readable'));
    });

    test('an unbaselined artifact is SKIPPED and says so', () {
      final f = evaluateOne('a', baseline: null, actual: 1000);
      expect(f.status, BudgetStatus.skipped);
      expect(f.reason, contains('--record'));
    });

    test('a zero or negative baseline cannot divide — SKIPPED', () {
      expect(evaluateOne('a', baseline: 0, actual: 1000).status,
          BudgetStatus.skipped);
      expect(evaluateOne('a', baseline: -5, actual: 1000).status,
          BudgetStatus.skipped);
    });

    test('SKIPPED is distinct from ok — bad news must not look like no news', () {
      // feedback_bad_news_vs_no_news: an unaskable question and a satisfied one
      // rendering identically IS the bug.
      final unknown = evaluateOne('a', baseline: null, actual: 1);
      final clean = evaluateOne('a', baseline: 1000, actual: 1000);
      expect(unknown.status, isNot(clean.status));
    });
  });

  group('evaluateAll', () {
    test('reports an artifact present in the tree but absent from baselines', () {
      // Reddens if the union is narrowed to baselines.keys: a newly tracked
      // always-loaded doc would then escape the budget forever.
      final out = evaluateAll({'old': 100}, {'old': 100, 'brand_new': 999});
      expect(out.map((f) => f.path), containsAll(['old', 'brand_new']));
      final fresh = out.firstWhere((f) => f.path == 'brand_new');
      expect(fresh.status, BudgetStatus.skipped);
    });

    test('reports a baselined artifact missing from the tree', () {
      final out = evaluateAll({'gone': 100}, {});
      expect(out.single.status, BudgetStatus.skipped);
    });

    test('is sorted by path so output is stable across runs', () {
      final out = evaluateAll({}, {'z': 1, 'a': 1, 'm': 1});
      expect(out.map((f) => f.path), ['a', 'm', 'z']);
    });
  });

  group('anyBlocking', () {
    test('only a hard-band breach blocks', () {
      expect(anyBlocking(evaluateAll({'a': 1000}, {'a': 1600})), isTrue);
    });

    test('warnings do NOT block', () {
      expect(anyBlocking(evaluateAll({'a': 1000}, {'a': 1200})), isFalse);
    });

    test('skips do NOT block', () {
      expect(anyBlocking(evaluateAll({}, {'a': 1})), isFalse);
      expect(anyBlocking(evaluateAll({'a': 1000}, {'a': null})), isFalse);
    });

    test('one failure among many clean artifacts still blocks', () {
      final out = evaluateAll(
          {'a': 1000, 'b': 1000, 'c': 1000}, {'a': 1000, 'b': 1000, 'c': 9000});
      expect(anyBlocking(out), isTrue);
    });
  });

  group('reporting helpers', () {
    test('driftLabel signs growth and shrinkage', () {
      expect(evaluateOne('a', baseline: 1000, actual: 1200).driftLabel, '+20.0%');
      expect(evaluateOne('a', baseline: 1000, actual: 800).driftLabel, '-20.0%');
      expect(evaluateOne('a', baseline: null, actual: 1).driftLabel, 'n/a');
    });

    test('approxTokens tracks the measured ~3.6 chars/token', () {
      // 94,291 was CLAUDE.md's size at cbd0267d, BEFORE this batch's own edits
      // to it (95,297 as committed). Kept as a fixed input because this asserts
      // a pure function, not a live file — but labelled honestly, since round 1
      // caught the original comment claiming it "matches the live report".
      expect(approxTokens(94291), 26191);
      expect(approxTokens(0), 0);
    });
  });
}
