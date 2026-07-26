// test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart
//
// THREE scripts independently duplicate the whole path-glob tier-computation
// engine — none of them import each other:
//   - scripts/blast_radius_from_diff.dart (informational, printed by hooks)
//   - scripts/check_plan_review_record_exists.dart (CI merge-to-main gate)
//   - scripts/check_code_review_pass_exists.dart (BLOCKING local pre-commit
//     gate — auto-wired into pre-commit.sh's `for GATE in scripts/check_*.dart`
//     loop, confirmed NOT in scripts/check_gate_scripts_wired.dart's allowlist)
//
// A content-aware escalation rule (SECURITY DEFINER migrations forcing
// catastrophic tier regardless of filename) wired into only some of them
// leaves the others blind — and check_code_review_pass_exists.dart is the
// one that actually blocks a LOCAL commit, so missing it isn't a lesser gap,
// it's the most load-bearing one. This pins all three.
//
// Two layers of proof, per feedback_source_grep_false_confidence.md
// ("source-grep tests count for presence only — also need a behavioral
// test"):
//   1. Source-grep (comment-stripped) that each script imports the shared
//      lib AND calls contentForcesCatastrophic( from inside an `if (...)`
//      guard (not just referenced/unused).
//   2. A real subprocess behavioral test: feed blast_radius_from_diff.dart
//      the path of a REAL on-disk migration in this repo
//      (093_founder_metrics_admin_function.sql — genuinely contains
//      SECURITY DEFINER, filename doesn't match any catastrophic glob) and
//      assert the actual printed tier is `catastrophic`, not just `platform`
//      (what the path-only glob would say). This proves the wiring is used,
//      not just present.
//
// Run: flutter test test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scriptPaths = [
    'scripts/blast_radius_from_diff.dart',
    'scripts/check_plan_review_record_exists.dart',
    'scripts/check_code_review_pass_exists.dart',
  ];

  // c9f1d3 (2026-07-27): the same three scripts must ALSO be >= platform tier
  // in the registry, or a change to one of them clears no review gate at all.
  //
  // The 2026-07-19 sweep that promoted enforcement scripts wrote, in its own
  // comment in docs/blast_radius.yaml, "A change to the reviewer must not be
  // exempt from review" — and then missed check_code_review_pass_exists.dart,
  // one word away in name from the gate it did promote and named by THIS
  // file's header as "the most load-bearing one". It fell through the
  // `scripts/** -> feature` catch-all, so the file deciding whether a
  // catastrophic diff has an accepted review could itself be edited with no
  // review at all.
  //
  // A prose comment did not prevent that; this test does. Checked against the
  // registry rather than a hardcoded list so the two cannot drift apart.
  group('registry tiering — a change to the reviewer is not exempt', () {
    late List<({String glob, String tier})> rules;

    setUpAll(() {
      final f = File('docs/blast_radius.yaml');
      expect(f.existsSync(), isTrue);
      rules = <({String glob, String tier})>[];
      var inPaths = false;
      for (final raw in f.readAsStringSync().split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (line == 'paths:') {
          inPaths = true;
          continue;
        }
        if (!inPaths || !line.startsWith('-')) continue;
        final g = RegExp(r'glob:\s*"([^"]+)"').firstMatch(line);
        final t = RegExp(r'tier:\s*([a-z]+)').firstMatch(line);
        if (g != null && t != null) {
          rules.add((glob: g.group(1)!, tier: t.group(1)!));
        }
      }
      expect(rules, isNotEmpty, reason: 'registry parsed to zero rules');
    });

    // FIRST match wins (docs/blast_radius.yaml header), so an exact-path rule
    // only counts if it precedes the scripts/** catch-all.
    String tierFor(String path) {
      for (final r in rules) {
        final pattern = RegExp(
          '^${RegExp.escape(r.glob).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*')}\$',
        );
        if (pattern.hasMatch(path)) return r.tier;
      }
      return 'feature';
    }

    test('the classifier itself resolves scripts/** to feature '
        '(so an exact rule is the ONLY thing that can save these)', () {
      expect(tierFor('scripts/some_unrelated_helper.dart'), 'feature',
          reason: 'if this is not feature, the assertions below could pass '
              'for the wrong reason and prove nothing');
    });

    for (final path in scriptPaths) {
      test('$path is >= platform', () {
        expect(
          ['platform', 'catastrophic'].contains(tierFor(path)),
          isTrue,
          reason: '$path implements the tier engine that decides whether a '
              'change needs review. At feature tier a change to it clears no '
              'review gate — the exemption docs/blast_radius.yaml explicitly '
              'exists to close. Got tier: ${tierFor(path)}.',
        );
      });
    }

    test('scripts/blast_radius_content_rules_lib.dart is >= platform', () {
      // The shared library all three delegate to; weakening it weakens all
      // three at once, so it cannot sit below them.
      expect(
        ['platform', 'catastrophic']
            .contains(tierFor('scripts/blast_radius_content_rules_lib.dart')),
        isTrue,
      );
    });
  });

  for (final path in scriptPaths) {
    group(path, () {
      late String src;

      setUpAll(() {
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$path must exist');
        src = _stripDartComments(f.readAsStringSync());
      });

      test('imports the shared content-rules library', () {
        expect(
          src.contains("import 'blast_radius_content_rules_lib.dart'"),
          isTrue,
          reason:
              '$path must import the shared library, not re-implement the rule',
        );
      });

      test('calls contentForcesCatastrophic( from inside an if-guard '
          '(not just referenced/unused)', () {
        // Matches e.g. `if (tier != 'catastrophic' && contentForcesCatastrophic(p)) {`,
        // `if (tierRank('catastrophic') > tierRank(t) && contentForcesCatastrophic(p)) {`,
        // or the staged-content-aware call with named args spanning multiple
        // lines: `if (tier != 'catastrophic' &&\n    contentForcesCatastrophic(p,\n
        // fileExists: ..., readFile: ...)) {` — an `if (` whose condition
        // contains a real call to the function (one required positional arg,
        // optionally followed by more args/named params), ending in `) {`.
        // A dead call (unused return value, no surrounding `if`) would not
        // match this shape.
        final ifGuardPattern = RegExp(
            r'if\s*\([^;{]*contentForcesCatastrophic\(\w+[^)]*\)[^;{]*\)\s*\{');
        expect(
          ifGuardPattern.hasMatch(src),
          isTrue,
          reason: '$path must call contentForcesCatastrophic( as part of an '
              'if-guard that actually branches on the result, not merely '
              'reference the function',
        );
      });
    });
  }

  test('the shared library itself is not duplicated — exactly one definition file', () {
    final matches = Directory('scripts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('blast_radius_content_rules_lib.dart'));
    expect(matches.length, 1,
        reason: 'exactly one blast_radius_content_rules_lib.dart should exist');
  });

  group('behavioral (real subprocess, real on-disk migration)', () {
    test('blast_radius_from_diff.dart actually escalates a real SECURITY '
        'DEFINER migration with an innocuous filename to catastrophic', () async {
      const fixturePath =
          'supabase/migrations/093_founder_metrics_admin_function.sql';
      expect(File(fixturePath).existsSync(), isTrue,
          reason: 'fixture migration must exist in this repo — if renamed/'
              'deleted, swap in another migration from the SECURITY DEFINER '
              'set with an innocuous filename (verified via the full-corpus '
              'scan in blast_radius_content_rules_lib_test.dart)');
      expect(
        File(fixturePath).readAsStringSync().toLowerCase(),
        contains('security definer'),
        reason: 'fixture must genuinely contain SECURITY DEFINER — this '
            'test proves nothing if the fixture drifted',
      );

      final process = await Process.start(
          'dart', ['run', 'scripts/blast_radius_from_diff.dart', '-'],
          runInShell: true);
      process.stdin.write('$fixturePath\n');
      await process.stdin.close();
      final stdout = await process.stdout.transform(utf8.decoder).join();
      await process.exitCode;

      expect(
        stdout,
        contains('Blast-radius: catastrophic'),
        reason: 'a SECURITY DEFINER migration with an innocuous filename '
            '(no security_definer/rls/pseudonymize/subscriptions_rls '
            'substring) must escalate to catastrophic via CONTENT, since '
            'its path-only tier is merely platform '
            '(supabase/migrations/** catch-all)',
      );
    });
  });
}

/// Strips `/* */` blocks then `// ...` line comments so assertions match real
/// code, not explanatory prose. Mirrors
/// test/contracts/blast_radius_positional_ref_guard_test.dart's helper.
String _stripDartComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock.split('\n').map((l) {
    final i = l.indexOf('//');
    return i >= 0 ? l.substring(0, i) : l;
  }).join('\n');
}
