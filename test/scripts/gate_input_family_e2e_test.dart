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

import '../helpers/git_tree_fixture.dart';
import '../helpers/spawn.dart';

// Scrubbing is now done by the shared spawn helper (`runSpawn`); the history of
// why each family is stripped:
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

ProcessResult _run(String exe, List<String> args, String cwd,
    {Map<String, String>? extra}) {
  return runSpawn(exe == 'dart' ? dartBin() : exe, args,
      why: 'gate input-family e2e: $exe ${args.join(' ')}',
      workingDirectory: cwd,
      extraEnv: extra ?? const <String, String>{},
      // GITHUB_REF / GITHUB_REPOSITORY_OWNER / PUSH_BEFORE are set on purpose.
      allowControl: (extra ?? const <String, String>{}).keys.toSet(),
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
    'version_bump_git_lib.dart',
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

  // ── Helpers for the B-pass findings of OI-275 batch B2 (diagnose 34e764 instances 5+) ───────
  // F1: `git diff` honours a `.gitmodules` `ignore = all` and then OMITS the submodule's pointer move
  // from `--name-only`. `.gitmodules` is a tracked file the pusher writes.
  const gitmodulesIgnoreAll =
      '[submodule "vendor/x"]\n\tpath = vendor/x\n\turl = https://example.invalid/x.git\n\tignore = all\n';

  /// Stages a gitlink at vendor/x pointing at [sha] without any submodule checkout (git never looks a
  /// gitlink target up).
  void stageGitlink(String repo, String sha) {
    final u = _run('git', ['update-index', '--add', '--cacheinfo', '160000,$sha,vendor/x'], repo);
    expect(u.exitCode, 0, reason: 'setup: ${u.stdout}${u.stderr}');
  }

  /// The paths plain git lists for [from]..[to] (NUL-separated, raw), with or without the flag the
  /// gate's reader passes. Used as a SETUP guard: the attack fixture must really hide the gitlink.
  List<String> namesBetween(String repo, String from, String to, {required bool seeSubmodules}) {
    final out = _run('git', [
      'diff',
      '--no-renames',
      if (seeSubmodules) '--ignore-submodules=none',
      '--name-only',
      '-z',
      '$from..$to',
    ], repo).stdout as String;
    return out.split('\u0000').where((s) => s.isNotEmpty).toList();
  }

  // F2: every "git could not answer" path in the gate. A shallow clone is how it happens in CI
  // (`fatal: unable to read tree`, exit 128). The ROOT TREE of [commit] is renamed out of the object
  // store, so `git diff <commit>..` fails while `rev-list`, `log` and the commit objects still work.
  // Renamed, not deleted: loose objects are read-only, which makes `File.delete` fail on Windows.
  void hideRootTree(String repo, String commit) {
    // `runSpawn`, not `_run`: `_run` goes through a shell, and cmd.exe on Windows eats the `^` in `<sha>^{tree}`.
    ProcessResult git(List<String> args) => runSpawn('git', args,
        why: 'gate input-family e2e: git ${args.join(' ')}', workingDirectory: repo);
    final tree = (git(['rev-parse', '$commit^{tree}']).stdout as String).trim();
    final obj = File('$repo/.git/objects/${tree.substring(0, 2)}/${tree.substring(2)}');
    expect(obj.existsSync(), isTrue, reason: 'setup: the root tree of $commit must be a loose object');
    obj.renameSync('${obj.path}.hidden');
    expect(git(['cat-file', '-e', tree]).exitCode, isNot(0),
        reason: 'setup: the tree must really be unreadable now');
    expect(git(['cat-file', '-e', commit]).exitCode, 0,
        reason: 'setup: the commit object itself must stay readable (the gate walks commits first)');
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

    test('a LOOK-ALIKE file (leading space) cannot ride along a bump: the exemption is refused', () {
      // `git diff --name-only` prints ' pubspec.yaml' raw. A trimming path normaliser turned it
      // into the real version file, so a file of arbitrary content under that name was exempted
      // together with the bump (found by probing the CLI, OI-275 batch B2; the bug predates B2).
      final repo = newRepo('oi58spoof');
      writeBump(repo, '1.0.0+36');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed'], repo);
      final before = _head(repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], repo);
      File('$repo/.payload').writeAsStringSync('SPOOF PAYLOAD\n');
      final blob = (_run('git', ['hash-object', '-w', '.payload'], repo).stdout as String).trim();
      File('$repo/.payload').deleteSync();
      final u = _run('git', ['update-index', '--add', '--cacheinfo', '100644,$blob, pubspec.yaml'], repo);
      expect(u.exitCode, 0, reason: 'setup: git must accept a leading-space path: ${u.stdout}${u.stderr}');
      _run('git', ['commit', '-qm', 'chore: bump versionCode'], repo);

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains('NOTE (version-bump exemption)')),
          reason: 'the exemption must not be GRANTED to a bump carrying a look-alike file');
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
          reason: 'paths must be read NUL-separated (-z, never C-quoted), or an accented '
              'filename silently downgrades its own tier');
    });

    // A file NAME may hold a line terminator on Linux. The tier globs compile `**` to `.*`, and a
    // bare `.` does not match a line terminator, so such a name matched no rule and fell to
    // default_tier: feature. Found while sweeping the gate for the path-exactness class (OI-275 B2,
    // diagnose 34e764); the bug predates B2 (git's C-quoting dropped the same name out of every
    // anchored glob). The fixture is built with `mktree` (`commitFileNamed`, in
    // test/helpers/git_tree_fixture.dart), the only route that also works on a Windows dev machine.
    for (final lt in const <(String, String)>[
      ('LF', '\n'),
      ('CR', '\r'),
      ('U+2028', '\u2028'),
      ('U+2029', '\u2029'),
    ]) {
      test('a governed file whose NAME holds a line terminator (${lt.$1}) is still judged', () {
        final repo = newRepo('oi275lb${lt.$1.replaceAll('+', '')}');
        final before = _head(repo);
        commitFileNamed(repo, 'lib/features/auth/re${lt.$2}set.dart', 'feat: add reset screen');

        final r = _gate(repo, before);
        expect(r.code, 1,
            reason: 'an account-tier directory must not be escaped by a ${lt.$1} in the file name: ${r.out}');
        expect(r.out, contains('DIRECTLY on main'));
        expect(r.out, contains('account'));
      });
    }

    test('MIRROR: a line terminator in a name under a FEATURE-tier directory stays feature (dotAll does not over-tighten)', () {
      final repo = newRepo('oi275lbfeature');
      final before = _head(repo);
      commitFileNamed(repo, 'docs/no\nte.md', 'docs: add a note');

      final r = _gate(repo, before);
      expect(r.code, 0, reason: 'docs/** is feature tier with or without a line break in the name: ${r.out}');
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

    // ── B-pass of OI-275 batch B2 ─────────────────────────────────────────────────────────────

    test('F1 CONTROL: a repo carrying .gitmodules (ignore = all) still gets a plain bump exempted', () {
      final repo = newRepo('oi275gmctl');
      File('$repo/.gitmodules').writeAsStringSync(gitmodulesIgnoreAll);
      writeBump(repo, '1.0.0+36');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed: version files and .gitmodules'], repo);
      final before = _head(repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'chore: bump versionCode'], repo);

      final r = _gate(repo, before);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains('NOTE (version-bump exemption)'),
          reason: 'without a passing control the attack test below proves nothing');
    });

    test('F1: a gitlink move hidden by .gitmodules `ignore = all` cannot ride along a bump', () {
      // `.gitmodules` lands first (feature tier: needs no record); the NEXT commit is a genuine bump
      // that also moves a gitlink at vendor/x. Plain `git diff --name-only` omits the gitlink, so the
      // path list read exactly the two version files and the commit was exempted as a bare bump.
      final repo = newRepo('oi275gm');
      File('$repo/.gitmodules').writeAsStringSync(gitmodulesIgnoreAll);
      writeBump(repo, '1.0.0+36');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed: version files and .gitmodules'], repo);
      final before = _head(repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], repo);
      stageGitlink(repo, before);
      final c = _run('git', ['commit', '-qm', 'chore: bump versionCode (and a gitlink)'], repo);
      expect(c.exitCode, 0, reason: 'setup: ${c.stdout}${c.stderr}');
      // The attack must be REAL: plain git hides the gitlink, the flag reveals it.
      expect(namesBetween(repo, before, 'HEAD', seeSubmodules: false), isNot(contains('vendor/x')),
          reason: 'setup: under .gitmodules ignore = all plain `git diff --name-only` omits the gitlink');
      expect(namesBetween(repo, before, 'HEAD', seeSubmodules: true), contains('vendor/x'),
          reason: 'setup: --ignore-submodules=none reveals it');

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains('NOTE (version-bump exemption)')),
          reason: 'the exemption must not be GRANTED to a bump whose path list was edited by .gitmodules');
      expect(r.out, contains('vendor/x'), reason: 'the refusal lists the path that used to be hidden');
    });

    test('F2: a diff git cannot answer FAILS the landing closed instead of grading it feature tier', () {
      // CONTROL first: the very same commit passes while git can answer. Then the parent's root tree
      // goes missing (what a shallow clone looks like) and the gate must say so, not wave it through.
      final repo = newRepo('oi275nodiff');
      final before = _head(repo);
      File('$repo/docs/note.md').writeAsStringSync('hello\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'docs: a note'], repo);
      expect(_gate(repo, before).code, 0, reason: 'setup: a docs-only landing is feature tier and passes');

      hideRootTree(repo, before);
      final r = _gate(repo, before);
      expect(r.code, 1, reason: 'an unreadable diff is "git could not answer", never "nothing to see": ${r.out}');
      expect(r.out, contains('could not diff'));
    });

    test('F2: a path that is not valid UTF-8 fails the landing closed (never decoded leniently)', () {
      // The name is under docs/** (feature tier). Decoded with allowMalformed the bytes FF FE become
      // two U+FFFD, the path still reads docs/..., and the landing PASSES as feature - a silent
      // collapse of distinct bad names. Strict decoding makes the whole list "could not answer".
      final repo = newRepo('oi275badutf8');
      final before = _head(repo);
      commitFileNamed(repo, 'docs/ÿþ.md', 'docs: a name that is not UTF-8', rawNames: true);

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, contains('could not diff'));
    });

    test('F2 MIRROR: a VALID non-ASCII name under a feature-tier directory still passes', () {
      final repo = newRepo('oi275utf8docs');
      final before = _head(repo);
      commitFileNamed(repo, 'docs/résumé.md', 'docs: a note');
      final r = _gate(repo, before);
      expect(r.code, 0, reason: 'strictness must apply to INVALID bytes only: ${r.out}');
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

  // ── OI-275 batch B2 (2026-10-11), U1(b) ──────────────────────────────────
  // A version bump that arrives as a PR MERGE is exempt by CONTENT, like a direct
  // bump (OI-58a above): the merge's net change against its first parent
  // (`<sha>^1..<sha>`) must be nothing but the two version lines. The exemption sits
  // BEFORE the switch on the merge subject, so the subject is never consulted
  // (OI-58b untouched). Every test below that must NOT be exempt asserts BOTH the
  // exit code and that the GRANT line is absent: the refusal message also contains
  // the words "version-bump", so a bare substring check would pass either way.
  group('U1b — a merge whose net change is a bare version bump', () {
    const grant = 'NOTE (version-bump exemption)';

    void writeBump(String repo, String v, {bool constants = true}) {
      File('$repo/pubspec.yaml').writeAsStringSync('name: probe\nversion: $v\n');
      if (constants) {
        Directory('$repo/lib/core/constants').createSync(recursive: true);
        File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
            'class AppConstants {\n'
            "  static const String appVersion = '$v';\n"
            '}\n');
      }
    }

    void commitAll(String repo, String msg) {
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', msg], repo);
    }

    /// main carries version 1.0.0+36; returns the repo.
    String bumpRepo(String label) {
      final repo = newRepo(label);
      writeBump(repo, '1.0.0+36');
      commitAll(repo, 'seed version');
      return repo;
    }

    /// Branch [name] off main with [edit] applied and committed; leaves main checked out.
    void branchWith(String repo, String name, void Function() edit, {String msg = 'chore: bump versionCode'}) {
      _run('git', ['checkout', '-q', '-B', name, 'main'], repo);
      edit();
      commitAll(repo, msg);
      _run('git', ['checkout', '-q', 'main'], repo);
    }

    /// Merges [name] into main with [subject] and returns main's tip BEFORE the merge.
    String mergeWith(String repo, String name, String subject) {
      final before = _head(repo);
      final r = _run('git', ['merge', '--no-ff', '-q', name, '-m', subject], repo);
      expect(r.exitCode, 0, reason: 'setup: merge failed: ${r.stdout}${r.stderr}');
      return before;
    }

    test('a PR merge that is ONLY a version bump PASSES with no record', () {
      final repo = bumpRepo('u1bpr');
      branchWith(repo, 'bump-x', () => writeBump(repo, '1.0.0+37'));
      final before = mergeWith(repo, 'bump-x', 'Merge pull request #7 from upendraprasad19/bump-x');

      final r = _gate(repo, before);
      expect(r.code, 0, reason: 'a release bump has no plan to review; this is exactly the case '
          'that demanded a record + B-pass + a second PR CI round: ${r.out}');
      expect(r.out, contains(grant));
      expect(r.out, contains('is a merge at'), reason: 'the NOTE must say it was the MERGE path');
    });

    test('a pubspec-ONLY bump merge PASSES (pinned to isVersionBumpCommit, which accepts one file)', () {
      // Gate 51 (check_app_version_matches_pubspec.dart) forces both files at COMMIT time;
      // this gate's predicate deliberately accepts either alone (17 historical bumps).
      final repo = bumpRepo('u1bpubonly');
      branchWith(repo, 'bump-pub', () => writeBump(repo, '1.0.0+37', constants: false));
      final before = mergeWith(repo, 'bump-pub', 'Merge pull request #8 from upendraprasad19/bump-pub');
      final r = _gate(repo, before);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains(grant));
    });

    test('the merge SUBJECT is never consulted: a local-merge, an unrecognised and a foreign-owner subject all pass by content', () {
      for (final subject in [
        "Merge branch 'bump-s'",
        'totally unrecognisable subject',
        'Merge pull request #9 from someone-else/bump-s', // foreign owner: normally fails closed
      ]) {
        final repo = bumpRepo('u1bsubj');
        branchWith(repo, 'bump-s', () => writeBump(repo, '1.0.0+37'));
        final before = mergeWith(repo, 'bump-s', subject);
        final r = _gate(repo, before);
        expect(r.code, 0, reason: 'subject "$subject": ${r.out}');
        expect(r.out, contains(grant), reason: 'subject "$subject"');
      }
    });

    test('a bump plus ONE docs file is NOT a bump (all-or-nothing)', () {
      final repo = bumpRepo('u1bplusdoc');
      branchWith(repo, 'bump-doc', () {
        writeBump(repo, '1.0.0+37');
        Directory('$repo/docs').createSync(recursive: true);
        File('$repo/docs/note.md').writeAsStringSync('hello\n');
      });
      final before = mergeWith(repo, 'bump-doc', 'Merge pull request #10 from upendraprasad19/bump-doc');
      final r = _gate(repo, before);
      expect(r.code, 1, reason: 'the docs file is feature tier, but it is still a third path: ${r.out}');
      expect(r.out, isNot(contains(grant)));
      expect(r.out, contains('no plan-review record'));
    });

    test('a bump plus a change to the tier registry is NOT a bump (OI-70)', () {
      final repo = bumpRepo('u1bregistry');
      branchWith(repo, 'bump-reg', () {
        writeBump(repo, '1.0.0+37');
        File('$repo/docs/blast_radius.yaml').writeAsStringSync(_registryRuleDeleted);
      });
      final before = mergeWith(repo, 'bump-reg', 'Merge pull request #11 from upendraprasad19/bump-reg');
      final r = _gate(repo, before);
      expect(r.code, 1, reason: 'relaxing the rule that grades your own change must not exempt it: ${r.out}');
      expect(r.out, isNot(contains(grant)));
    });

    test('content written BY the merge commit while resolving conflicts disqualifies it', () {
      // The branch is a perfect bump; the MERGE adds a third file (as a conflict
      // resolution would). `<sha>^1..<sha>` sees it, `sha^2...` or the branch alone cannot.
      final repo = bumpRepo('u1bmergewrote');
      branchWith(repo, 'bump-mw', () => writeBump(repo, '1.0.0+37'));
      final before = _head(repo);
      _run('git', ['merge', '--no-ff', '--no-commit', '-q', 'bump-mw'], repo);
      Directory('$repo/lib/features/auth').createSync(recursive: true);
      File('$repo/lib/features/auth/sneak.dart').writeAsStringSync('// sneaked in by the merge\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'Merge pull request #12 from upendraprasad19/bump-mw'], repo);

      final r = _gate(repo, before);
      expect(r.code, 1, reason: 'an account-tier file introduced by the merge itself: ${r.out}');
      expect(r.out, isNot(contains(grant)));
    });

    test('a SYMLINK swapped in for pubspec.yaml is NOT a bump (mode 120000)', () {
      // A symlink entry whose TARGET TEXT reads like a bumped pubspec. `git show`
      // returns that text as if it were file content; only the tree mode betrays it.
      // The target text is EXACTLY the pubspec a genuine bump would write (same `name:`
      // line, newline-terminated). A shorter text such as `version: 1.0.0+37` differs from
      // the base file once normalised, so the content comparison refuses it and the mode
      // check is never what saves us: mutation G4 (drop the regular-file mode check)
      // survived the first version of this fixture.
      final repo = bumpRepo('u1bsymlink');
      _run('git', ['checkout', '-q', '-B', 'bump-link', 'main'], repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', 'lib/core/constants/app_constants.dart'], repo);
      File('$repo/.linktarget').writeAsStringSync('name: probe\nversion: 1.0.0+37\n');
      final blob =
          (_run('git', ['hash-object', '-w', '.linktarget'], repo).stdout as String).trim();
      File('$repo/.linktarget').deleteSync();
      _run('git', ['update-index', '--add', '--cacheinfo', '120000,$blob,pubspec.yaml'], repo);
      _run('git', ['commit', '-qm', 'chore: bump versionCode (symlink)'], repo);
      _run('git', ['checkout', '-q', '-f', 'main'], repo);

      final before = mergeWith(repo, 'bump-link', 'Merge pull request #13 from upendraprasad19/bump-link');
      // Setup guard: the merged tree really holds a symlink entry at pubspec.yaml.
      final entry = (_run('git', ['ls-tree', 'HEAD', '--', 'pubspec.yaml'], repo).stdout as String);
      expect(entry, startsWith('120000'), reason: 'setup: pubspec.yaml must be a symlink entry: $entry');

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
    });

    test('a SECOND version token (duplicate key) is NOT a bump', () {
      // The BASE carries the duplicate key too. With one token before and two after, the
      // normalised blobs differ anyway and the exactly-one-token rule is never what refuses
      // the merge: mutation G9 (allow more than one token) survived the first fixture. Here
      // both sides collapse to the same placeholders, so ONLY the count can refuse it - and
      // line 2 changing silently (1.0.0+36 -> 9.9.9+9) is the B-pass P0-1 attack itself.
      final repo = bumpRepo('u1bdup');
      File('$repo/pubspec.yaml')
          .writeAsStringSync('name: probe\nversion: 1.0.0+36\nversion: 1.0.0+36\n');
      commitAll(repo, 'seed: duplicate top-level version key');
      branchWith(repo, 'bump-dup', () {
        File('$repo/pubspec.yaml').writeAsStringSync('name: probe\nversion: 1.0.0+37\nversion: 9.9.9+9\n');
        Directory('$repo/lib/core/constants').createSync(recursive: true);
        File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
            "class AppConstants {\n  static const String appVersion = '1.0.0+37';\n}\n");
      });
      final before = mergeWith(repo, 'bump-dup', 'Merge pull request #14 from upendraprasad19/bump-dup');
      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
    });

    test('a SECOND appVersion declaration in app_constants.dart is NOT a bump', () {
      // The same attack on the other exempt file: valid, compiling Dart with a second
      // class declaring its own appVersion, whose value changes silently. Base carries both
      // declarations so only the exactly-one-token rule can refuse it (see the test above).
      final repo = bumpRepo('u1bdupc');
      File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
          'class AppConstants {\n  static const String appVersion = \'1.0.0+36\';\n}\n'
          'class Other {\n  static const String appVersion = \'1.0.0+36\';\n}\n');
      commitAll(repo, 'seed: second appVersion declaration');
      branchWith(repo, 'bump-dupc', () {
        File('$repo/pubspec.yaml').writeAsStringSync('name: probe\nversion: 1.0.0+37\n');
        File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
            'class AppConstants {\n  static const String appVersion = \'1.0.0+37\';\n}\n'
            'class Other {\n  static const String appVersion = \'9.9.9+9\';\n}\n');
      });
      final before = mergeWith(repo, 'bump-dupc', 'Merge pull request #16 from upendraprasad19/bump-dupc');
      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
    });

    test('a LOOK-ALIKE file (leading space) riding a bump merge is NOT a bump', () {
      // The merge-path twin of the OI-58a test above: ' pubspec.yaml' is a distinct, valid git
      // path holding arbitrary content, and a trimming normaliser made it the real version file.
      final repo = bumpRepo('u1bspoof');
      _run('git', ['checkout', '-q', '-B', 'bump-spoof', 'main'], repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], repo);
      File('$repo/.payload').writeAsStringSync('SPOOF PAYLOAD\n');
      final blob = (_run('git', ['hash-object', '-w', '.payload'], repo).stdout as String).trim();
      File('$repo/.payload').deleteSync();
      final u = _run('git', ['update-index', '--add', '--cacheinfo', '100644,$blob, pubspec.yaml'], repo);
      expect(u.exitCode, 0, reason: 'setup: git must accept a leading-space path: ${u.stdout}${u.stderr}');
      _run('git', ['commit', '-qm', 'chore: bump versionCode plus a look-alike'], repo);
      _run('git', ['checkout', '-q', '-f', 'main'], repo);
      final before = mergeWith(repo, 'bump-spoof', 'Merge pull request #17 from upendraprasad19/bump-spoof');
      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
    });

    test('non-version content in app_constants.dart riding a bump is NOT a bump', () {
      final repo = bumpRepo('u1bprice');
      branchWith(repo, 'bump-price', () {
        writeBump(repo, '1.0.0+37', constants: false);
        File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(
            'class AppConstants {\n'
            "  static const String appVersion = '1.0.0+37';\n"
            '  static const int monthlyPriceInr = 1;\n'
            '}\n');
      });
      final before = mergeWith(repo, 'bump-price', 'Merge pull request #15 from upendraprasad19/bump-price');
      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
    });

    test('a push carrying a bump merge AND an unreviewed auth merge fails ONLY for the auth merge', () {
      final repo = bumpRepo('u1btwo');
      branchWith(repo, 'bump-two', () => writeBump(repo, '1.0.0+37'));
      branchWith(repo, 'auth-two', () {
        Directory('$repo/lib/features/auth').createSync(recursive: true);
        File('$repo/lib/features/auth/reset.dart').writeAsStringSync('// x\n');
      }, msg: 'fix(auth): something');
      final before = _head(repo);
      _run('git', ['merge', '--no-ff', '-q', 'bump-two', '-m', 'Merge pull request #16 from upendraprasad19/bump-two'], repo);
      _run('git', ['merge', '--no-ff', '-q', 'auth-two', '-m', 'Merge pull request #17 from upendraprasad19/auth-two'], repo);

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, contains(grant), reason: 'the bump merge is still granted');
      expect(r.out, contains('auth-two'), reason: 'and the auth merge is the one that fails');
      expect(r.out, isNot(contains('bump-two: ')), reason: 'no failure line may name the bump branch');
    });

    test('a bump WITH a valid record still passes through the record route (no regression)', () {
      final repo = bumpRepo('u1brecord');
      branchWith(repo, 'bump-rec', () {
        writeBump(repo, '1.0.0+37');
        File('$repo/docs/plan-reviews/bump-rec.md').writeAsStringSync('---\n'
            'branch: bump-rec\n'
            'review_rounds: 2\n'
            'ground_truth_verified: true\n'
            'verdict: converged\n'
            'bpass: accepted\n'
            'bpass_review: docs/reviews/bump-rec-bpass.md\n'
            '---\nbody\n');
        File('$repo/docs/reviews/bump-rec-bpass.md').writeAsStringSync('verdict: accepted\n');
      });
      final before = mergeWith(repo, 'bump-rec', 'Merge pull request #18 from upendraprasad19/bump-rec');
      final r = _gate(repo, before);
      expect(r.code, 0, reason: r.out);
      expect(r.out, isNot(contains(grant)),
          reason: 'a bump that also carries docs files is judged on its record, not exempted');
    });

    // ── B-pass of OI-275 batch B2 ─────────────────────────────────────────────────────────────

    test('F1: a gitlink hidden by .gitmodules `ignore = all` riding a bump MERGE is NOT a bump', () {
      final repo = bumpRepo('u1bgm');
      File('$repo/.gitmodules').writeAsStringSync(gitmodulesIgnoreAll);
      commitAll(repo, 'chore: add .gitmodules');
      _run('git', ['checkout', '-q', '-B', 'bump-gm', 'main'], repo);
      writeBump(repo, '1.0.0+37');
      _run('git', ['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], repo);
      stageGitlink(repo, _head(repo));
      final c = _run('git', ['commit', '-qm', 'chore: bump versionCode (and a gitlink)'], repo);
      expect(c.exitCode, 0, reason: 'setup: ${c.stdout}${c.stderr}');
      _run('git', ['checkout', '-q', '-f', 'main'], repo);
      final before = mergeWith(repo, 'bump-gm', 'Merge pull request #23 from upendraprasad19/bump-gm');
      expect(namesBetween(repo, before, 'HEAD', seeSubmodules: false), isNot(contains('vendor/x')),
          reason: 'setup: plain `git diff` must hide the gitlink under .gitmodules ignore = all');
      expect(namesBetween(repo, before, 'HEAD', seeSubmodules: true), contains('vendor/x'),
          reason: 'setup: --ignore-submodules=none must reveal it');

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
    });

    test('F2: a merge whose diff git cannot answer FAILS closed (never read as feature tier)', () {
      final repo = bumpRepo('u1bnodiff');
      branchWith(repo, 'bump-nd', () => writeBump(repo, '1.0.0+37'));
      final before = mergeWith(repo, 'bump-nd', 'Merge pull request #22 from upendraprasad19/bump-nd');
      final ok = _gate(repo, before);
      expect(ok.code, 0, reason: 'setup (control): the same merge passes while git can answer: ${ok.out}');
      expect(ok.out, contains(grant));

      hideRootTree(repo, before);
      final r = _gate(repo, before);
      expect(r.code, 1, reason: 'an unreadable merge diff must not be graded feature and waved through: ${r.out}');
      expect(r.out, contains('could not diff'));
      expect(r.out, isNot(contains(grant)));
    });

    test('REVERSE: main moved ahead with a bump while the BRANCH carries real content - NOT exempt', () {
      // The exemption is decided on <merge>^1..<merge>, the net change against main's tip AT THE MERGE.
      // Here main's own newer commit is a perfect bump and the branch is an auth change: the merge
      // brings the auth file and nothing else. A rule that exempted the merge when EITHER parent's diff
      // is a bump (the bump hiding in <merge>^2..<merge> = what main gained since the branch was cut)
      // would let any branch ride a release.
      final repo = bumpRepo('u1brev');
      branchWith(repo, 'auth-rev', () {
        Directory('$repo/lib/features/auth').createSync(recursive: true);
        File('$repo/lib/features/auth/reset.dart').writeAsStringSync('// x\n');
      }, msg: 'fix(auth): something');
      writeBump(repo, '1.0.0+37');
      commitAll(repo, 'chore: bump versionCode');
      final before = mergeWith(repo, 'auth-rev', 'Merge pull request #24 from upendraprasad19/auth-rev');

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
      expect(r.out, contains('no plan-review record'));
    });

    test('FORWARD MIRROR: main moved ahead with a DOCS commit while the branch is a bare bump - exempt', () {
      // The other direction of the pair above: what main gained since the cut (a docs file) is already
      // in the first parent, so the merge's net change is still just the two version lines.
      final repo = bumpRepo('u1bfwd');
      branchWith(repo, 'bump-fwd', () => writeBump(repo, '1.0.0+37'));
      File('$repo/docs/landed-after-the-cut.md').writeAsStringSync('main moved on\n');
      commitAll(repo, 'docs: lands on main after the branch was cut');
      final before = mergeWith(repo, 'bump-fwd', 'Merge pull request #25 from upendraprasad19/bump-fwd');

      final r = _gate(repo, before);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains(grant), reason: 'it must be the EXEMPTION that passes it, not the feature-tier skip');
      expect(r.out, contains('pubspec.yaml'));
    });
  });

  // ── The Dependabot exemption compares manifest paths EXACTLY (diagnose 34e764) ──────────
  // The sibling of the version-bump look-alike tests above: `dependabotDiffIsManifestOnly`
  // used to trim each path, so ' pubspec.lock' (a distinct, valid git path holding anything)
  // counted as the real lock file and rode along on a bot-shaped merge whose record was waived.
  // The unit test pins the predicate; this one pins that the gate hands it the EXACT paths.
  group('Dependabot exemption — manifest paths are compared exactly', () {
    const grant = 'NOTE (Dependabot exemption)';
    const botBranch = 'dependabot/pub/foo-1.2.3';

    /// main carries both manifests; returns the repo.
    String depRepo(String label) {
      final repo = newRepo(label);
      File('$repo/pubspec.yaml')
          .writeAsStringSync('name: probe\nversion: 1.0.0+36\ndependencies:\n  foo: ^1.0.0\n');
      File('$repo/pubspec.lock').writeAsStringSync('packages:\n  foo: 1.0.0\n');
      _run('git', ['add', '-A'], repo);
      _run('git', ['commit', '-qm', 'seed manifests'], repo);
      return repo;
    }

    /// A Dependabot-authored branch that bumps BOTH manifests (and, when [lookAlike] is set,
    /// also adds a file at exactly that path), merged as a PR. Returns main's tip BEFORE the merge.
    String mergeBotBranch(String repo, {String? lookAlike}) {
      _run('git', ['checkout', '-q', '-B', botBranch, 'main'], repo);
      File('$repo/pubspec.yaml')
          .writeAsStringSync('name: probe\nversion: 1.0.0+36\ndependencies:\n  foo: ^1.2.3\n');
      File('$repo/pubspec.lock').writeAsStringSync('packages:\n  foo: 1.2.3\n');
      _run('git', ['add', '-A'], repo);
      if (lookAlike != null) {
        File('$repo/.payload').writeAsStringSync('LOOK-ALIKE PAYLOAD\n');
        final blob = (_run('git', ['hash-object', '-w', '.payload'], repo).stdout as String).trim();
        File('$repo/.payload').deleteSync();
        final u = _run('git', ['update-index', '--add', '--cacheinfo', '100644,$blob,$lookAlike'], repo);
        expect(u.exitCode, 0, reason: 'setup: git must accept the path "$lookAlike": ${u.stdout}${u.stderr}');
      }
      // The AUTHOR is the bot (the gate reads `%ae`); the committer stays the test identity.
      _run('git', ['commit', '-qm', 'Bump foo from 1.0.0 to 1.2.3'], repo, extra: {
        'GIT_AUTHOR_NAME': 'dependabot[bot]',
        'GIT_AUTHOR_EMAIL': '49699333+dependabot[bot]@users.noreply.github.com',
      });
      _run('git', ['checkout', '-q', '-f', 'main'], repo);
      final before = _head(repo);
      final m = _run('git', ['merge', '--no-ff', '-q', botBranch, '-m',
          'Merge pull request #30 from upendraprasad19/$botBranch'], repo);
      expect(m.exitCode, 0, reason: 'setup: merge failed: ${m.stdout}${m.stderr}');
      return before;
    }

    test('CONTROL: a bot-authored merge touching only the two manifests is exempt', () {
      final repo = depRepo('depctl');
      final before = mergeBotBranch(repo);
      final r = _gate(repo, before);
      expect(r.code, 0, reason: r.out);
      expect(r.out, contains(grant), reason: 'without a passing control the look-alike test proves nothing');
    });

    test('a LOOK-ALIKE manifest (leading space) riding a bot-shaped merge is NOT exempt', () {
      final repo = depRepo('depspoof');
      final before = mergeBotBranch(repo, lookAlike: ' pubspec.lock');
      // Setup guard: the merged range really contains the look-alike path, byte for byte.
      final names = (_run('git', ['diff', '--no-renames', '--name-only', '-z', '$before..HEAD'], repo).stdout as String)
          .split('\u0000');
      expect(names, contains(' pubspec.lock'), reason: 'setup: the look-alike path must be in the diff: $names');

      final r = _gate(repo, before);
      expect(r.code, 1, reason: r.out);
      expect(r.out, isNot(contains(grant)));
      expect(r.out, contains('outside the dependency manifests'),
          reason: 'it must be refused as a non-manifest path, not for some other reason');
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
      // topologies (partial/filtered clones); its exact trigger is confirmed by
      // hand (`git diff <graft>^1..<graft>` exits 128, `fatal: ambiguous
      // argument`) and it is driven by the two F2 tests of this file (the
      // parent's root tree is hidden so `git diff` exits 128), not by this one.
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
        'version_bump_git_lib.dart',
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
