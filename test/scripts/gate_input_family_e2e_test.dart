// test/scripts/gate_input_family_e2e_test.dart
//
// Per-file negative controls for the gate-input family (OI-70 / OI-71).
// Each test isolates ONE guarantee — a source-grep that the new code EXISTS
// would prove nothing here, because every one of these bugs was a gate that ran
// and returned the wrong answer. See feedback_source_grep_false_confidence.md.
//
// The OI-58a / OI-58b scenarios that lived here were REMOVED on 2026-07-27 when
// that half of the batch was split out (§4.12.1). They return with it.
//
// TWO KINDS OF TEST, labelled honestly (round-1B review P2-1 caught the header
// claiming all of them were the first kind):
//   REVERT-CONTROL — fails against the pre-fix gate. Most tests here.
//   DESIGN-LOCK    — passes against the pre-fix gate too, and pins a REJECTED
//                    alternative design instead. Marked in place. Worth keeping;
//                    not worth mislabelling.
//
// Sibling to plan_review_record_gate_e2e_test.dart, which keeps its own repo
// and its own accumulated merge history.
//
// ENV SCRUBBING IS LOAD-BEARING. Run inside `pre-commit`, a test that spawns
// its own git repo inherits GIT_DIR / GIT_WORK_TREE, which override BOTH
// `workingDirectory:` and `-C <path>` — the child git would operate on the REAL
// repo and every assertion would be meaningless (or destructive).
// feedback_mistake_git_hook_env_leak.

@Timeout(Duration(minutes: 8))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _cleanEnv() {
  final env = Map<String, String>.from(Platform.environment);
  // GIT_*  — a surrounding git hook exports GIT_DIR / GIT_WORK_TREE, which
  //          override BOTH `workingDirectory:` and `-C <path>`, so the child
  //          git would operate on the REAL repo (feedback_mistake_git_hook_env_leak).
  //
  // GITHUB_* — added 2026-07-28 after this file went RED in CI while green
  //          locally. The gate's range-base resolution falls back to parsing
  //          `GITHUB_EVENT_PATH`, and in CI that payload is real: its `before`
  //          names a commit on the ACTUAL repo, which does not exist in this
  //          throwaway one. The gate then correctly reported
  //          "supplied but unresolvable" and hard-failed — the right behaviour
  //          on a bogus base, triggered by an input the test never meant to
  //          give it. Each test re-supplies the GITHUB_* keys it actually wants
  //          via `extra:`, so the spawned gate sees only what the scenario
  //          declares. Hermetic by construction rather than by luck.
  env.removeWhere((k, _) {
    final u = k.toUpperCase();
    return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
  });
  return env;
}

ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String>? extra}) {
  final env = _cleanEnv();
  if (extra != null) env.addAll(extra);
  return Process.runSync(exe, args,
      workingDirectory: cwd,
      environment: env,
      includeParentEnvironment: false,
      runInShell: true);
}

/// A throwaway repo carrying the gate, its imports, and a registry.
///
/// [registry] lets a test supply a MINIMAL tier registry. The OI-70 case needs
/// that: `docs/blast_radius.yaml` is itself a governed path in the real
/// registry, so a branch deleting a rule would be caught by its own edit and
/// the test would pass for the wrong reason.
String _makeRepo(String srcRoot, String label, String registry) {
  final tmp = Directory.systemTemp.createTempSync('gate_input_$label');
  final repo = tmp.path;
  _run('git', ['init', '-q', '-b', 'main', '.'], repo);
  _run('git', ['config', 'user.email', 'test@example.invalid'], repo);
  _run('git', ['config', 'user.name', 'Test'], repo);
  _run('git', ['remote', 'add', 'origin',
      'git@github.com:upendraprasad19/AVYA.git'], repo);

  final top = (_run('git', ['rev-parse', '--show-toplevel'], repo).stdout as String).trim();
  if (!top.toLowerCase().contains('gate_input_')) {
    throw StateError('ENV LEAK: throwaway git resolved to "$top". Aborting '
        'rather than running assertions against the real repository.');
  }

  Directory('$repo/scripts').createSync(recursive: true);
  for (final f in const [
    'check_plan_review_record_exists.dart',
    'plan_review_record_lib.dart',
    'blast_radius_content_rules_lib.dart',
  ]) {
    File('$srcRoot/scripts/$f').copySync('$repo/scripts/$f');
  }
  Directory('$repo/docs/plan-reviews').createSync(recursive: true);
  Directory('$repo/docs/reviews').createSync(recursive: true);
  File('$repo/docs/blast_radius.yaml').writeAsStringSync(registry);

  File('$repo/seed.txt').writeAsStringSync('seed\n');
  _run('git', ['add', '-A'], repo);
  _run('git', ['commit', '-qm', 'seed'], repo);
  return repo;
}

/// Runs the gate over `PUSH_BEFORE..HEAD`, the way CI does.
({int code, String out}) _gate(String repo, String pushBefore) {
  final r = _run('dart', ['scripts/check_plan_review_record_exists.dart'], repo,
      extra: {
        'GITHUB_REF': 'refs/heads/main',
        'GITHUB_REPOSITORY_OWNER': 'upendraprasad19',
        'PUSH_BEFORE': pushBefore,
      });
  return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
}

String _head(String repo) =>
    (_run('git', ['rev-parse', 'HEAD'], repo).stdout as String).trim();

/// Registry mirroring the shape of the real one, minimal enough to isolate a
/// single rule under test.
const _registry = '''
default_tier: feature
paths:
  - { glob: "pubspec.yaml", tier: platform }
  - { glob: "lib/core/constants/app_constants.dart", tier: platform }
  - { glob: "lib/features/auth/**", tier: account }
  - { glob: "docs/**", tier: feature }
  - { glob: "scripts/**", tier: feature }
''';

/// Same, minus the `pubspec.yaml` rule — what a self-exempting branch would
/// leave behind.
const _registryRuleDeleted = '''
default_tier: feature
paths:
  - { glob: "lib/core/constants/app_constants.dart", tier: platform }
  - { glob: "lib/features/auth/**", tier: account }
  - { glob: "docs/**", tier: feature }
  - { glob: "scripts/**", tier: feature }
''';

void main() {
  final srcRoot = Directory.current.path;
  final repos = <String>[];

  tearDownAll(() {
    for (final r in repos) {
      try {
        Directory(r).deleteSync(recursive: true);
      } catch (_) {/* best effort on Windows file locks */}
    }
  });

  String newRepo(String label, [String registry = _registry]) {
    final r = _makeRepo(srcRoot, label, registry);
    repos.add(r);
    return r;
  }

  // ── OI-58a (2026-07-28) ──────────────────────────────────────────────────
  // Direct-to-main commits are judged again. The exemption compares each
  // touched file's BLOB before and after with the version token normalised —
  // it parses nothing, because the commit author writes the diff.
  //
  // Attack-shaped controls for the exemption itself live in
  // test/scripts/version_bump_exemption_test.dart; these five cover the gate's
  // end-to-end behaviour on real commits.
  group('OI-58a — direct-to-main landings are judged', () {
    /// A real bump: `version:` in pubspec, `appVersion` in constants.
    void writeBump(String repo, String v) {
      Directory('$repo/lib/core/constants').createSync(recursive: true);
      File('$repo/pubspec.yaml').writeAsStringSync('name: probe\nversion: $v\n');
      File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
          'class AppConstants {\n'
          "  static const String appVersion = '$v';\n"
          '}\n');
    }

    test('an account-tier commit pushed STRAIGHT to main FAILS', () {
      final repo = newRepo('oi58direct');
      final before = _head(repo);
      Directory('$repo/lib/features/auth').createSync(recursive: true);
      File('$repo/lib/features/auth/reset.dart').writeAsStringSync('// x\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'fix(auth): straight to main'], repo);

      final r = _gate(repo, before);
      expect(r.code, 1,
          reason: 'this is `be3b4baf` and `8c38c855` — account-tier auth '
              'commits that landed on main unreviewed because the gate exited '
              'at `rev-parse HEAD^2` before looking');
      expect(r.out, contains('DIRECTLY on main'));
    });

    test('a bare version bump PASSES (blobs identical modulo the version)', () {
      final repo = newRepo('oi58bump');
      writeBump(repo, '1.0.0+36');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed version'], repo);
      final before = _head(repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'chore: bump versionCode'], repo);

      final r = _gate(repo, before);
      expect(r.code, 0,
          reason: '`2c4cbddd` is platform tier but its entire diff is the four '
              'version lines; the release flow bumps these on main by design');
      expect(r.out, contains('version-bump exemption'));
    });

    test('THE ATTEMPT-2 BYPASS: bump-shaped paths, non-version lines → FAILS',
        () {
      // The exact defect that failed round 1 of this branch's review.
      // `paths.every(allowList)`
      // is an all-of test over an ALLOW-LIST, so it accepts every subset — a
      // commit touching ONLY app_constants.dart passed at account tier while
      // rewriting prices and free-tier caps, with no version line anywhere.
      // Confirmed by execution before the split; this is the control that must
      // exist for attempt 3 to mean anything.
      final repo = newRepo('oi58bypass');
      Directory('$repo/lib/core/constants').createSync(recursive: true);
      File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
          'class AppConstants {\n'
          "  static const String appVersion = '1.0.0+36';\n"
          '  static const int monthlyPriceInr = 349;\n'
          '  static const int freeAiMessagesPerDay = 10;\n'
          '}\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed constants'], repo);
      final before = _head(repo);

      // Version line untouched; the money and the free-tier cap rewritten.
      File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
          'class AppConstants {\n'
          "  static const String appVersion = '1.0.0+36';\n"
          '  static const int monthlyPriceInr = 1;\n'
          '  static const int freeAiMessagesPerDay = 9999;\n'
          '}\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'chore: bump versionCode'], repo);

      final r = _gate(repo, before);
      expect(r.code, 1,
          reason: 'the paths are exactly the allow-list, so a path-level test '
              'exempts this. Only reading the CONTENT can refuse it.');
      // Assert on the GRANT form specifically. The failure message itself says
      // "The version-bump exemption did not apply", so a bare substring check
      // matches the refusal too — it would pass whether the gate granted or
      // refused, which is no assertion at all.
      expect(r.out, isNot(contains('NOTE (version-bump exemption)')),
          reason: 'the exemption must not be GRANTED here');
      expect(r.out, contains('did not apply'),
          reason: 'and the failure should say why, so the author is not left '
              'guessing which half of the rule they missed');
    });

    test('a version bump with ONE extra file loses the exemption', () {
      final repo = newRepo('oi58bumpplus');
      writeBump(repo, '1.0.0+36');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed'], repo);
      final before = _head(repo);
      writeBump(repo, '1.0.0+38');
      Directory('$repo/lib/features/auth').createSync(recursive: true);
      File('$repo/lib/features/auth/sneak.dart').writeAsStringSync('// y\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'chore: bump versionCode'], repo);

      expect(_gate(repo, before).code, 1,
          reason: 'the full path list disqualifies it even though the bump '
              'lines themselves are valid — an auth edit must not ride along');
    });

    // ── Round-2 review: three breaks in the INPUT PLUMBING ────────────────
    // The blob-comparison exemption itself survived every attack. These three
    // are how a commit reached (or crashed) it with the wrong inputs, and all
    // three sit in `_diffPaths` / blob reading — code the direct-commit loop
    // newly exercises.

    test('P1-1: deleting a governed file BY RENAME is still judged', () {
      // `git diff --name-only` with rename detection ON prints only the
      // DESTINATION, so renaming a platform-tier file into docs/ made the
      // governed path invisible and the commit graded `feature`. Verified
      // against real git: --name-only gives 1 path, --no-renames gives 2.
      final repo = newRepo('oi58rename');
      Directory('$repo/lib/features/auth').createSync(recursive: true);
      File('$repo/lib/features/auth/reset.dart').writeAsStringSync('// x');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed governed file'], repo);
      final before = _head(repo);

      Directory('$repo/docs').createSync(recursive: true);
      _run('git', ['mv', 'lib/features/auth/reset.dart', 'docs/archived.bak'], repo);
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'docs: archive an old note'], repo);

      final r = _gate(repo, before);
      expect(r.code, 1,
          reason: 'the account-tier file is DELETED by this commit; a subject '
              'saying "docs:" must not make it feature tier');
      expect(r.out, contains('account'));
    });

    test('P1-2: a governed file with a NON-ASCII name is still judged', () {
      // git C-quotes such paths by default ("lib/…/rÃ©sumÃ©.dart"),
      // and the glob matcher anchors ^…$, so the quoted form matched no rule and
      // fell to default_tier: feature.
      final repo = newRepo('oi58nonascii');
      final before = _head(repo);
      Directory('$repo/lib/features/auth').createSync(recursive: true);
      File('$repo/lib/features/auth/résumé.dart').writeAsStringSync('// x');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'feat: add resume screen'], repo);

      expect(_gate(repo, before).code, 1,
          reason: 'core.quotePath=false must be set, or an accented filename '
              'silently downgrades its own tier');
    });

    test('P1-3: a BINARY file does not crash the gate', () {
      // `Process.runSync`'s default stdoutEncoding is a STRICT Utf8Decoder on
      // Linux — it THROWS on the first invalid byte. The direct-commit loop
      // reads blobs, and the repo tracks 79 binary files, so a push touching a
      // PNG would have crashed CI with an uncaught FormatException. Windows
      // hides it: its ACP decoder is total.
      //
      // NOT fixable with allowMalformed: 0x80 and 0x81 both decode to U+FFFD,
      // which would turn the crash into a byte-equality COLLISION.
      //
      // The payload MUST sit at pubspec.yaml, not an arbitrary path: _gitBlob is
      // only called for isMigrationSqlPath or versionBumpPaths, so a PNG under
      // lib/features/auth/ never reaches it and the test would pass with the
      // guard deleted. B-pass mutation-tested exactly that and it was vacuous.
      final repo = newRepo('oi58binary');
      final before = _head(repo);
      Directory('$repo/lib/features/auth').createSync(recursive: true);
      File('$repo/pubspec.yaml').writeAsBytesSync(
          <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x80, 0x81, 0xFF, 0xFE]);
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'feat: add asset'], repo);

      final r = _gate(repo, before);
      expect(r.out, isNot(contains('FormatException')),
          reason: 'a binary blob must never crash the gate');
      expect(r.out, isNot(contains('Unhandled exception')));
      expect(r.code, 1,
          reason: 'and it must still be JUDGED — account tier, no record');
    });

    test('the release push (bump commit + docs commit) PASSES', () {
      // DESIGN-LOCK, not a revert-control. Verified: this is the one test in
      // the group that also passes against main's pre-fix gate (which does not
      // judge direct commits at all, so everything passes there). What it pins
      // is ATTEMPT 1's defect — a per-PUSH union that tested all direct commits
      // together, so this standard two-commit release failed on the very bump
      // the exemption exists for. Keeping it stops a future "simplification"
      // back to per-push.
      //
      // Discrimination measured, not assumed: against main's gate the group
      // scores 4 failures and this pass; against an attempt-2 reconstruction
      // (path-level exemption) exactly one test fails — the bypass control.
      final repo = newRepo('oi58release');
      writeBump(repo, '1.0.0+36');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed'], repo);
      final before = _head(repo);

      writeBump(repo, '1.0.0+37');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'chore: bump versionCode'], repo);

      File('$repo/docs/shipped.md').writeAsStringSync('APK +37 shipped\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'docs(audit): close OI-52'], repo);

      expect(_gate(repo, before).code, 0,
          reason: 'per-commit, not per-push: a feature-tier docs commit in the '
              'same push must not poison the bump\'s exemption');
    });
  });

  test('OI-71 — content written BY the merge commit is inspected', () {
    // The branch itself touches only a feature-tier file. The platform-tier
    // file appears in the merge commit, exactly as it would when resolving a
    // conflict. `HEAD^1...HEAD^2` (three-dot, merge-base..branch-tip) cannot
    // see it; `HEAD^1..HEAD` (two-dot) can.
    final repo = newRepo('mergecontent');
    _run('git', ['checkout', '-q', '-B', 'sidebranch', 'main'], repo);
    File('$repo/notes.txt').writeAsStringSync('branch side\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'feature-tier change only'], repo);
    _run('git', ['checkout', '-q', 'main'], repo);
    final before = _head(repo);

    _run('git', ['merge', '--no-ff', '--no-commit', '-q', 'sidebranch'], repo);
    File('$repo/pubspec.yaml').writeAsStringSync('version: 9.9.9\n');
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', "Merge branch 'sidebranch' — resolved"], repo);

    // Proves the setup really is the OI-71 shape rather than a trivial pass.
    final threeDot = (_run('git',
            ['diff', '--name-only', 'HEAD^1...HEAD^2'], repo).stdout as String);
    expect(threeDot, isNot(contains('pubspec.yaml')),
        reason: 'setup guard: the old three-dot diff must be blind to it, '
            'otherwise this test proves nothing');

    final r = _gate(repo, before);
    expect(r.code, 1,
        reason: 'a platform file introduced during conflict resolution must '
            'still demand a record; three-dot stopped at the branch tip');
    expect(r.out, contains('no plan-review record'));
  });

  test('OI-70 — deleting the rule that governs your own change does not exempt it', () {
    // Branch edits pubspec.yaml (platform) AND removes the rule that makes it
    // platform. Judged against the MERGED tree alone it reads `feature` and
    // sails through. The base registry still has the rule.
    final repo = newRepo('selfexempt');
    _run('git', ['checkout', '-q', '-B', 'self-exempt', 'main'], repo);
    File('$repo/pubspec.yaml').writeAsStringSync('version: 1.2.3\n');
    File('$repo/docs/blast_radius.yaml').writeAsStringSync(_registryRuleDeleted);
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'relax my own rule'], repo);
    _run('git', ['checkout', '-q', 'main'], repo);
    final before = _head(repo);
    _run('git', ['merge', '--no-ff', '-q', 'self-exempt', '-m',
        "Merge branch 'self-exempt'"], repo);

    final r = _gate(repo, before);
    expect(r.code, 1,
        reason: 'max(base registry, merged registry) — a commit cannot lower '
            'its own tier by deleting the rule in the same change');
    expect(r.out, contains('no plan-review record'));
  });

  test('OI-70 — a rule that arrives WITH the change also binds it', () {
    // The mirror case, and why HEAD^1-only would have been half a fix:
    // `904e6961` landed .github/workflows/test.yml when only a BROADER
    // `.github/** -> feature` rule covered it; the narrower platform promotion
    // came a batch later in `9e3ce5d8`. Here the branch adds BOTH the governed
    // file and the rule governing it — the merged registry must bind.
    //
    // HONEST SCOPE (round-1B review P2-1): this is a DESIGN-LOCK test, not a
    // revert-control. The pre-fix gate read the merged tree only, which already
    // contains the new rule, so it FAILS here too. What this pins is the
    // REJECTED alternative — reading the base registry alone, as OI-70 as filed
    // proposed — which would pass. Keeping it is worthwhile; calling it a
    // revert-control would not be true.
    final repo = newRepo('ruleadded', _registryRuleDeleted);
    _run('git', ['checkout', '-q', '-B', 'adds-rule', 'main'], repo);
    File('$repo/pubspec.yaml').writeAsStringSync('version: 4.5.6\n');
    File('$repo/docs/blast_radius.yaml').writeAsStringSync(_registry);
    _run('git', ['add', '-A'], repo);
    _run('git', ['commit', '-qm', 'promote pubspec to platform'], repo);
    _run('git', ['checkout', '-q', 'main'], repo);
    final before = _head(repo);
    _run('git', ['merge', '--no-ff', '-q', 'adds-rule', '-m',
        "Merge branch 'adds-rule'"], repo);

    expect(_gate(repo, before).code, 1,
        reason: 'the branch that introduces a promotion is itself subject to '
            'it; reading only the base registry would exempt exactly the '
            'commits that tighten the rules');
  });

  // ── Round-1 independent review findings ────────────────────────────────
  // Six defects the first draft shipped. Each test below fails without its fix.
  group('round-1 review regressions', () {
    test('P2-1 — a supplied-but-unresolvable base FAILS instead of narrowing',
        () {
      // The first draft silently fell back to HEAD^1 and printed a clean PASS.
      // Realistic trigger: a force-push to main, where github.event.before
      // names a commit no ref reaches and actions/checkout fetches refs, not
      // orphans — so only the tip of an N-commit push was ever inspected.
      final repo = newRepo('unresolvablebase');
      File('$repo/notes.txt').writeAsStringSync('x\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'something'], repo);

      final r = _gate(repo, 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef');
      expect(r.code, 1, reason: 'refusing to evaluate a partial range');
      expect(r.out, contains('does not resolve'));
    });

    test('P2-1b — an all-zero base is a NEW-BRANCH sentinel, not an error', () {
      final repo = newRepo('zerobase');
      File('$repo/notes.txt').writeAsStringSync('x\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'feature-tier only'], repo);

      expect(_gate(repo, '0000000000000000000000000000000000000000').code, 0,
          reason: 'git uses all-zeros for "this ref did not exist"; there is '
              'nothing earlier to diff against, so failing would be wrong');
    });

    test('P2-2 — content escalation is judged at the commit that introduced it',
        () {
      // A SECURITY DEFINER migration added by a merge and REMOVED later in the
      // same push. The first draft read the working tree (final HEAD), where
      // the file is absent — and the shared library fails OPEN on a missing
      // file — so that merge never had to carry hermes: accepted.
      final repo = newRepo('contentatrev');
      _run('git', ['checkout', '-q', '-B', 'sd-branch', 'main'], repo);
      Directory('$repo/supabase/migrations').createSync(recursive: true);
      File('$repo/supabase/migrations/999_probe.sql').writeAsStringSync(
          'create function f() returns void security definer as \$\$ \$\$;');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'add definer migration'], repo);
      _run('git', ['checkout', '-q', 'main'], repo);
      final before = _head(repo);
      _run('git', ['merge', '--no-ff', '-q', 'sd-branch', '-m',
          "Merge branch 'sd-branch'"], repo);
      // ... then deleted, still inside the same pushed range.
      File('$repo/supabase/migrations/999_probe.sql').deleteSync();
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'docs: remove probe'], repo);

      expect(File('$repo/supabase/migrations/999_probe.sql').existsSync(), isFalse,
          reason: 'setup guard: the file must be ABSENT at HEAD, or this test '
              'proves nothing about reading the commit\'s own tree');

      final r = _gate(repo, before);
      expect(r.code, 1,
          reason: 'the merge that introduced SECURITY DEFINER must still be '
              'escalated, even though a later commit in the push removed it');
      expect(r.out, contains('SECURITY DEFINER'));
    });

    test('P1-2 — a shallow clone never yields a clean PASS over a >=account range',
        () {
      // The first draft's `_git()` returned '' on ANY git failure, so a diff
      // that ERRORED produced an empty path list, resolved to `feature`, and
      // waved the merge through with a reassuring NOTE. The old gate had an
      // explicit `if (diff.isEmpty) die(...)` for exactly this and the rewrite
      // dropped it.
      //
      // HONEST SCOPE. The reachable shallow-clone shape trips the P2-1
      // unresolvable-base guard rather than the null-diff guard: to get a merge
      // INTO the range the base must be older than it, and in a shallow clone
      // that base is itself absent. The null-diff `fail()` covers odder
      // topologies (partial/filtered clones) and is defensive — its exact
      // trigger is confirmed by hand (`git diff <graft>^1..<graft>` exits 128,
      // `fatal: ambiguous argument`) but is not what this test drives.
      //
      // So this asserts the INVARIANT that actually matters and is stable
      // across which guard fires: truncated history must never read as "all
      // clear". Without either guard the gate exits 0 here.
      final repo = newRepo('shallowsrc');
      _run('git', ['checkout', '-q', '-B', 'deep', 'main'], repo);
      File('$repo/pubspec.yaml').writeAsStringSync('version: 1.0.0\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'platform change, no record'], repo);
      _run('git', ['checkout', '-q', 'main'], repo);
      final deepBase = _head(repo);
      _run('git', ['merge', '--no-ff', '-q', 'deep', '-m', "Merge branch 'deep'"], repo);
      File('$repo/notes.txt').writeAsStringSync('tip\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'docs: tip'], repo);

      final shallowDir =
          Directory.systemTemp.createTempSync('gate_input_shallowdst');
      repos.add(shallowDir.path);
      final clone = '${shallowDir.path}/repo';
      final uri = 'file:///${repo.replaceAll(r'\', '/')}';
      final cl = _run('git', ['clone', '-q', '--depth', '2', uri, clone],
          shallowDir.path);
      expect(cl.exitCode, 0, reason: 'setup: shallow clone must succeed');

      // Setup guard: history really is truncated, or this proves nothing.
      final boundary = _run('git', ['rev-list', '--count', 'HEAD'], clone);
      expect(int.parse((boundary.stdout as String).trim()), lessThanOrEqualTo(2),
          reason: 'setup guard: the clone must actually be shallow');

      for (final f in const [
        'check_plan_review_record_exists.dart',
        'plan_review_record_lib.dart',
        'blast_radius_content_rules_lib.dart',
      ]) {
        File('$srcRoot/scripts/$f').copySync('$clone/scripts/$f');
      }

      final r = _gate(clone, deepBase);
      expect(r.code, 1,
          reason: 'the platform merge carries no record; truncated history must '
              'produce a loud failure, never a clean PASS. An empty or errored '
              'diff read as `feature` is how this went silent.');
    });

    test('P3-1 — record fields are read from frontmatter, not from prose', () {
      final repo = newRepo('prosefield');
      _run('git', ['checkout', '-q', '-B', 'prose', 'main'], repo);
      File('$repo/pubspec.yaml').writeAsStringSync('version: 1.0.0\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'change'], repo);
      _run('git', ['checkout', '-q', 'main'], repo);

      // Frontmatter is missing `verdict:`; the body mentions it.
      File('$repo/docs/plan-reviews/prose.md').writeAsStringSync('''
---
branch: prose
review_rounds: 2
ground_truth_verified: true
bpass: accepted
bpass_review: docs/reviews/probe.md
---

Round 2 reviewed the sibling batch and recorded:
verdict: converged
''');
      File('$repo/docs/reviews/probe.md').writeAsStringSync('verdict: accepted\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'record'], repo);
      _run('git', ['merge', '--no-ff', '-q', 'prose', '-m', "Merge branch 'prose'"], repo);

      final r = _gate(repo, 'HEAD^1');
      expect(r.code, 1,
          reason: 'a verdict quoted in prose must not satisfy the gate; '
              'recordBranchFieldMatches already scoped branch: this way and '
              'the other eight fields did not');
      expect(r.out, contains('verdict'));
    });
  });

}
