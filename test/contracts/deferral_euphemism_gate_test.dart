// test/contracts/deferral_euphemism_gate_test.dart
//
// Behavioural coverage for Gate-DEU (scripts/check_no_deferral_euphemism.dart)
// and its phrase list (docs/deferral_euphemisms.yaml).
//
// WHY THIS EXISTS (a3d7b1, 2026-07-27)
// ------------------------------------
// Until now this gate had NO test of its own behaviour. It is hard-fail in
// pre-commit, runs vacuously in CI (no staged diff there), and fails OPEN on a
// git error — so a bad edit's first detector was production behaviour. That
// combination is why it was promoted to platform tier.
//
// The same batch moved the phrase list OUT of the script into a feature-tier
// data file, so that adding a banned phrase stays a one-line edit while the
// matching logic stays gated. That split introduces exactly one new risk: the
// data file could go missing or empty and the gate would look healthy while
// matching nothing. These tests pin that it fails CLOSED instead.
//
// Runs the real script as a subprocess against throwaway repos. Environment is
// scrubbed of GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE — run inside pre-commit
// those are exported by git and override BOTH `workingDirectory:` and
// `git -C`, so without scrubbing every git call here would operate on the REAL
// repo (b7e4c2, feedback_mistake_git_hook_env_leak).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gate = 'scripts/check_no_deferral_euphemism.dart';
const _phrases = 'docs/deferral_euphemisms.yaml';

void main() {
  late String repoRoot;

  /// Parent environment minus the three variables git exports to its hooks.
  /// Case-insensitive: Windows env keys are, a copied Map is not.
  Map<String, String> scrubbedEnv() {
    const leaky = {'git_dir', 'git_work_tree', 'git_index_file'};
    return {
      for (final e in Platform.environment.entries)
        if (!leaky.contains(e.key.toLowerCase())) e.key: e.value,
    };
  }

  setUpAll(() {
    repoRoot = Directory.current.path;
    expect(File('$repoRoot/$_gate').existsSync(), isTrue);
  });

  /// Builds a throwaway git repo containing the real gate + a phrase file,
  /// stages [markdown] as `doc.md`, runs the gate there, returns its exit code.
  ///
  /// [phrasesContent] null => copy the real docs/deferral_euphemisms.yaml.
  ({int exitCode, String out}) runGateOn(
    String? markdown, {
    String? phrasesContent,
    bool omitPhrasesFile = false,
  }) {
    final repo = Directory.systemTemp.createTempSync('deu_gate_');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });

    ProcessResult git(List<String> args) => Process.runSync('git', args,
        workingDirectory: repo.path,
        environment: scrubbedEnv(),
        includeParentEnvironment: false,
        runInShell: true);

    expect(git(['init']).exitCode, 0, reason: 'temp repo init failed');
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);

    // The gate resolves both paths relative to its CWD.
    Directory('${repo.path}/scripts').createSync(recursive: true);
    Directory('${repo.path}/docs').createSync(recursive: true);
    File('$repoRoot/$_gate').copySync('${repo.path}/$_gate');
    if (!omitPhrasesFile) {
      File('${repo.path}/$_phrases').writeAsStringSync(
        phrasesContent ?? File('$repoRoot/$_phrases').readAsStringSync(),
      );
    }

    // Seed commit so `git diff --cached` is meaningful.
    File('${repo.path}/seed.txt').writeAsStringSync('seed\n');
    git(['add', 'seed.txt']);
    git(['commit', '-m', 'seed']);

    if (markdown != null) {
      File('${repo.path}/doc.md').writeAsStringSync(markdown);
      git(['add', 'doc.md']);
    }

    final r = Process.runSync('dart', ['run', _gate],
        workingDirectory: repo.path,
        environment: scrubbedEnv(),
        includeParentEnvironment: false,
        runInShell: true);
    return (exitCode: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  group('Gate-DEU — phrase list is real data, and the gate fails closed', () {
    test('the phrase file exists and parses to a non-trivial list', () {
      final f = File(_phrases);
      expect(f.existsSync(), isTrue, reason: '$_phrases must exist');
      final entries = f
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.startsWith('-'))
          .length;
      expect(entries, greaterThan(10),
          reason: 'A near-empty list is a silently disabled gate. Found '
              '$entries entries.');
    });

    test('the script no longer hardcodes the phrase list', () {
      // Regression guard: re-inlining the list would silently re-impose the
      // platform-tier review cost on every phrase addition, which is the exact
      // thing the split removed.
      final src = File(_gate).readAsStringSync();
      expect(src.contains('const List<String> _euphemisms'), isFalse,
          reason: 'The list belongs in $_phrases at feature tier.');
      expect(src.contains(_phrases), isTrue,
          reason: 'The gate must read the phrase file by path.');
    });

    test('POSITIVE CONTROL: a staged euphemism is caught (exit 1)', () {
      final r = runGateOn('# Plan\n\nWe will handle this in a dedicated batch.\n');
      expect(r.exitCode, 1,
          reason: 'Without this, every absence assertion below is vacuous.\n'
              '${r.out}');
      expect(r.out, contains('dedicated batch'));
    });

    test('clean staged markdown passes (exit 0)', () {
      final r = runGateOn('# Plan\n\nEvery finding is closed in this commit.\n');
      expect(r.exitCode, 0, reason: r.out);
    });

    test('a phrase added ONLY to the data file is honoured — proving the '
        'list is read from disk, not compiled in', () {
      const custom = "phrases:\n  - 'punting this to later'\n";
      final r = runGateOn('# Plan\n\nWe are punting this to later.\n',
          phrasesContent: custom);
      expect(r.exitCode, 1,
          reason: 'A phrase present only in the data file must be enforced — '
              'this is the whole point of the split.\n${r.out}');
      expect(r.out, contains('punting this to later'));
    });

    test('FAILS CLOSED when the phrase file is missing (exit 1)', () {
      final r = runGateOn('# Plan\n\nWe will handle this in a dedicated batch.\n',
          omitPhrasesFile: true);
      expect(r.exitCode, 1,
          reason: 'Deleting the data file must not silently disable a '
              'hard-fail gate.\n${r.out}');
      expect(r.out, contains('not found'));
    });

    test('FAILS CLOSED when the phrase file parses to zero phrases (exit 1)',
        () {
      final r = runGateOn('# Plan\n\nWe will handle this in a dedicated batch.\n',
          phrasesContent: 'phrases:\n');
      expect(r.exitCode, 1,
          reason: 'An empty list would pass everything forever while looking '
              'healthy.\n${r.out}');
      expect(r.out, contains('ZERO phrases'));
    });
  });
}
