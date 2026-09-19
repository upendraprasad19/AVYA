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
//
// TIMEOUT: the behavioural tests here spawn real subprocesses (`dart run` on a
// real on-disk migration). One test already carried an explicit 120s for that
// reason; the rest inherited the 30s default and timed out under the
// merge-commit regression walk's parallelism. Raised file-wide rather than
// per-test so the next subprocess test added here inherits it. Diagnose: c3f9a7.
//
// The live annotation is the 3-minute one below, from diagnose 4f2a9e — a
// CONCURRENT, independent diagnosis of the same symptom by another session,
// landed on main while this branch was in flight. A duplicate 2-minute
// annotation sat here; two `library;` directives in one file is a syntax error,
// and git auto-merged them without conflict because they sat at different line
// numbers. The more generous value wins.

@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
// This file spawns real subprocesses (`dart run` / shell), and a cold `dart run`
// costs seconds on its own — VM start plus kernel compile. Under the
// merge-commit regression-catalog walk, which runs ~700 tests concurrently,
// those subprocesses take long enough to blow the 30s PER-TEST default, and the
// walk reports failures for tests that pass standalone every time. Measured: one
// such file takes 33s wall with ZERO contention.
// Applied to the whole subprocess-spawning class, not only the files observed
// failing — fixing just the observed instances is what let this recur twice.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const scriptPaths = [
    'scripts/blast_radius_from_diff.dart',
    'scripts/check_plan_review_record_exists.dart',
    'scripts/check_code_review_pass_exists.dart',
  ];

  /// Enforcement scripts that are NOT tier engines, but whose compromise is
  /// just as total. Promoted 2026-07-27 (founder decision) after the c9f1d3
  /// sweep found the same 2026-07-19 omission had left these behind too.
  ///
  /// Each is either the SOLE path for an operation or a hard-fail gate, and
  /// between them they carry almost no test coverage:
  ///   - pre-push.sh          self-referential — it decides whether the full
  ///                          suite runs before a push, so an edit disabling
  ///                          it skips the suite on the very push that lands
  ///                          it. CI is no substitute: golden-image tests run
  ///                          ONLY in that local suite.
  ///   - safe_commit.sh /     the only sanctioned write paths (git_safety_hook
  ///     safe_push.sh         exists purely to force them); zero behavioural
  ///                          coverage of their own verification logic.
  ///   - validate_audit_      Gate 40 — the structural no-deferrals invariant.
  ///     closure.dart
  ///   - check_no_deferral_   one commit ever, zero tests, hard-fail,
  ///     euphemism.dart       local-only, and it fails OPEN on error.
  const enforcementPaths = [
    'scripts/pre-push.sh',
    'scripts/commit-msg.sh',
    'scripts/safe_commit.sh',
    'scripts/safe_push.sh',
    'scripts/validate_audit_closure.dart',
    'scripts/check_no_deferral_euphemism.dart',
    // The rule-22 diagnose-doc chain that commit-msg.sh drives.
    'scripts/validate_diagnose_doc.dart',
    'scripts/validate_diagnose_doc_lib.dart',
    'scripts/check_bugfix_commits_have_diagnose.dart',
    // Third member of the blast-radius trio named in CLAUDE.md §7.
    'scripts/check_blast_radius_coverage.dart',
  ];

  /// Hook sources that setup-hooks.sh installs but which are deliberately NOT
  /// platform tier. Every exclusion needs a reason recorded here — the point of
  /// the derived assertion below is that being in the set is the DEFAULT and
  /// leaving something out must be argued.
  const declinedHookSources = {
    // Its own header (:9-10) states the Blast-radius line it writes is
    // informational; verified no gate parses `^Blast-radius:` back out.
    'scripts/prepare-commit-msg.sh',
  };

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

    for (final path in enforcementPaths) {
      test('$path is >= platform', () {
        expect(
          ['platform', 'catastrophic'].contains(tierFor(path)),
          isTrue,
          reason: '$path is either the SOLE path for a git operation or a '
              'hard-fail gate, and carries little or no test coverage. At '
              'feature tier a change to it clears no review gate — the same '
              'omission c9f1d3 closed for the review-acceptance gate. '
              'Got tier: ${tierFor(path)}.',
        );
      });
    }

    // THE assertion that stops a fourth partial sweep.
    //
    // The list above is still hand-typed, and a hand-typed list is what failed
    // in the 2026-07-19 sweep, again in c9f1d3, and again in this batch's own
    // first draft (which promoted two of the four installed hooks and missed
    // commit-msg.sh). So the hook family is DERIVED from setup-hooks.sh: add a
    // fifth hook there and this fails until its tier is decided.
    test('every hook source setup-hooks.sh installs is >= platform', () {
      final f = File('scripts/setup-hooks.sh');
      expect(f.existsSync(), isTrue);
      final installed = RegExp(r'install_hook\s+"\$REPO_ROOT/(scripts/[^"]+)"')
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(1)!)
          .toList();

      expect(installed.length, greaterThanOrEqualTo(4),
          reason: 'Parsed ${installed.length} install_hook lines from '
              'setup-hooks.sh — the regex has probably drifted from the '
              'script, which would make this assertion vacuous.');

      final unprotected = installed
          .where((p) => !declinedHookSources.contains(p))
          .where((p) => !['platform', 'catastrophic'].contains(tierFor(p)))
          .toList();

      expect(
        unprotected,
        isEmpty,
        reason: 'These git hook sources gate every future git operation but '
            'resolve below platform tier, so editing them clears no review '
            'gate: $unprotected. Either promote them in docs/blast_radius.yaml '
            'or add them to declinedHookSources with a written reason.',
      );
    });

    // P2-3 from the B-pass: tierFor() re-implements the glob engine, so it
    // could in principle drift from the real gates. Verified faithful today
    // across all registry globs, but "verified today" is not a guard. This
    // asserts agreement against the ACTUAL classifier binary, which is
    // drift-proof by construction. One subprocess for the whole set — the
    // classifier prints the MAX tier across its positional args.
    test('the real classifier agrees: promoted set is platform, control is not',
        () {
      String classify(List<String> paths) {
        final r = Process.runSync(
          'dart',
          ['run', 'scripts/blast_radius_from_diff.dart', ...paths],
          runInShell: true,
        );
        final m = RegExp(r'Blast-radius:\s*(\w+)')
            .firstMatch((r.stdout as String).trim());
        expect(m, isNotNull,
            reason: 'classifier printed no tier for $paths:\n${r.stdout}');
        return m!.group(1)!;
      }

      expect(classify(['docs/diagnoses/x.md']), 'feature',
          reason: 'Control failed — the classifier is not answering correctly, '
              'so the assertion below would prove nothing.');
      expect(classify([...scriptPaths, ...enforcementPaths]), 'platform',
          reason: 'The real gate must see the promoted set as >= platform, not '
              'just this test\'s reimplementation of the glob engine.');
    }, timeout: const Timeout(Duration(minutes: 3)));

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
