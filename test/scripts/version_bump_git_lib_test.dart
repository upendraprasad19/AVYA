// test/scripts/version_bump_git_lib_test.dart
//
// scripts/version_bump_git_lib.dart (rangeIsVersionBump and the blob / mode / path
// readers it owns) driven THROUGH its CLI, scripts/version_bump_range.dart, against
// real throwaway git repos. The decision itself (`isVersionBumpCommit`) is covered
// as a pure function by version_bump_exemption_test.dart; what this file adds is the
// part that function cannot see - how the git READERS feed it:
//
//   - which revs are diffed (base..head, two-dot, `--no-renames`, NUL-separated `-z`);
//   - that blobs are read raw and decoded strictly (a binary pubspec must not crash
//     and must not collide);
//   - that the tree MODE is read (a symlink's target text reads like a bumped file);
//   - that every way git can fail is "not a bump" (exit 1), never an exemption.
//
// The CLI is run with `workingDirectory:` = the throwaway repo, so the lib's git calls
// resolve there. ENV SCRUBBING IS LOAD-BEARING (feedback_mistake_git_hook_env_leak):
// runSpawn strips GIT_DIR / GIT_WORK_TREE, which would otherwise override
// `workingDirectory:` and point the child at the REAL repository.

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/git_tree_fixture.dart';
import '../helpers/spawn.dart';

ProcessResult _git(List<String> args, String cwd) =>
    runSpawn('git', args, why: 'version_bump_git_lib e2e: git ${args.join(' ')}', workingDirectory: cwd);

String _pub(String v, {String eol = '\n'}) => 'name: probe\nversion: $v\ndependencies:\n  foo: ^1.0.0\n'.replaceAll('\n', eol);

String _con(String v, {String extra = ''}) =>
    "class AppConstants {\n  static const String appVersion = '$v';\n  static const int monthlyPriceInr = 349;\n$extra}\n";

void main() {
  final script = File('scripts/version_bump_range.dart').absolute.path;
  final repos = <Directory>[];

  tearDownAll(() {
    for (final d in repos) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {/* best effort on Windows file locks */}
    }
  });

  /// A repo whose `main` carries version 1.0.0+36 in both files. Returns its path.
  String newRepo(String label) {
    final tmp = Directory.systemTemp.createTempSync('vbump_$label');
    repos.add(tmp);
    final r = tmp.path;
    _git(['init', '-q', '-b', 'main', '.'], r);
    _git(['config', 'user.email', 'test@example.invalid'], r);
    _git(['config', 'user.name', 'Test'], r);
    // core.symlinks=false is the Windows default; pin it so `git add` never tries a real link.
    _git(['config', 'core.autocrlf', 'false'], r);
    final top = (_git(['rev-parse', '--show-toplevel'], r).stdout as String).trim();
    if (!top.toLowerCase().contains('vbump_')) {
      throw StateError('ENV LEAK: throwaway git resolved to "$top"; aborting rather than '
          'asserting against the real repository.');
    }
    Directory('$r/lib/core/constants').createSync(recursive: true);
    File('$r/pubspec.yaml').writeAsStringSync(_pub('1.0.0+36'));
    File('$r/lib/core/constants/app_constants.dart').writeAsStringSync(_con('1.0.0+36'));
    _git(['add', '-A'], r);
    _git(['commit', '-qm', 'seed'], r);
    return r;
  }

  String head(String repo) => (_git(['rev-parse', 'HEAD'], repo).stdout as String).trim();

  /// Commits the working tree and returns (base, head) revs around that commit.
  ({String base, String head}) commit(String repo, [String msg = 'chore: change']) {
    final base = head(repo);
    _git(['add', '-A'], repo);
    final c = _git(['commit', '-qm', msg], repo);
    expect(c.exitCode, 0, reason: 'setup: commit failed: ${c.stdout}${c.stderr}');
    return (base: base, head: head(repo));
  }

  ProcessResult range(String repo, String base, String headRev) =>
      runSpawn(dartBin(), [script, base, headRev],
          why: 'version_bump_range $base $headRev', workingDirectory: repo);

  void bumpBoth(String repo, String v) {
    File('$repo/pubspec.yaml').writeAsStringSync(_pub(v));
    File('$repo/lib/core/constants/app_constants.dart').writeAsStringSync(_con(v));
  }

  // ── B-pass of OI-275 batch B2, finding F1 (diagnose 34e764 instance 5) ──────────────────────
  // `git diff` honours a `.gitmodules` `ignore = all` and then OMITS that submodule's pointer move
  // from `--name-only`. `.gitmodules` is a tracked file the pusher writes, so the path list - the
  // exemption's first precondition - was something the commit author could edit.
  const gitmodulesIgnoreAll =
      '[submodule "vendor/x"]\n\tpath = vendor/x\n\turl = https://example.invalid/x.git\n\tignore = all\n';

  /// [newRepo] whose history already carries a committed `.gitmodules` saying `ignore = all` for vendor/x.
  String newRepoWithGitmodules(String label) {
    final r = newRepo(label);
    File('$r/.gitmodules').writeAsStringSync(gitmodulesIgnoreAll);
    _git(['add', '.gitmodules'], r);
    final c = _git(['commit', '-qm', 'chore: add .gitmodules'], r);
    expect(c.exitCode, 0, reason: 'setup: ${c.stdout}${c.stderr}');
    return r;
  }

  /// Commits the version bump to [v] together with a gitlink at vendor/x (set with `update-index`, so
  /// no submodule is ever cloned; git does not look a gitlink target up).
  ({String base, String head}) commitBumpWithGitlink(String repo, String v) {
    final base = head(repo);
    bumpBoth(repo, v);
    _git(['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], repo);
    final u = _git(['update-index', '--add', '--cacheinfo', '160000,$base,vendor/x'], repo);
    expect(u.exitCode, 0, reason: 'setup: ${u.stdout}${u.stderr}');
    final c = _git(['commit', '-qm', 'chore: bump versionCode (and a gitlink)'], repo);
    expect(c.exitCode, 0, reason: 'setup: ${c.stdout}${c.stderr}');
    return (base: base, head: head(repo));
  }

  /// What git itself lists for base..head, NUL-separated and raw - with or without the flag the lib passes.
  List<String> listedByGit(String repo, String base, String headRev, {required bool seeSubmodules}) {
    final out = _git([
      'diff',
      '--no-renames',
      if (seeSubmodules) '--ignore-submodules=none',
      '--name-only',
      '-z',
      '$base..$headRev',
    ], repo).stdout as String;
    return out.split('\u0000').where((s) => s.isNotEmpty).toList();
  }

  /// A throwaway Dart program that calls `diffPathsBetween` ITSELF and prints the answer. The CLI cannot
  /// show it: `rangeIsVersionBump` folds "git could not answer" (null) and "nothing changed" (empty) into
  /// the same exit 1, and the gate's two call sites treat those two very differently (null is a hard
  /// failure; an empty list reads as feature tier). Output is `NULL` or `PATHS:<json>`, each path as a
  /// list of UTF-16 code units so no console code page can mangle a non-ASCII name.
  late final String driver;
  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('vbump_driver');
    repos.add(dir);
    final lib = Uri.file(File('scripts/version_bump_git_lib.dart').absolute.path).toString();
    File('${dir.path}/driver.dart').writeAsStringSync('''
import 'dart:convert';
import 'dart:io';

import '$lib';

void main(List<String> args) {
  final r = diffPathsBetween(args[0], args[1]);
  stdout.write(r == null ? 'NULL' : 'PATHS:' + jsonEncode(r.map((p) => p.codeUnits).toList()));
}
''');
    driver = '${dir.path}/driver.dart';
  });

  /// Runs the driver in [repo]; returns null for `NULL`, else the listed paths.
  List<String>? diffPaths(String repo, String base, String headRev) {
    final res = runSpawn(dartBin(), [driver, base, headRev],
        why: 'diffPathsBetween driver $base $headRev', workingDirectory: repo);
    expect(res.exitCode, 0, reason: 'the driver must not crash: ${res.stdout}${res.stderr}');
    final out = res.stdout as String;
    if (out == 'NULL') return null;
    expect(out, startsWith('PATHS:'), reason: 'unexpected driver output: $out');
    return [
      for (final units in jsonDecode(out.substring('PATHS:'.length)) as List)
        String.fromCharCodes((units as List).cast<int>()),
    ];
  }

  group('rangeIsVersionBump through the CLI — what IS a bump', () {
    test('both files bumped -> exit 0', () {
      final r = newRepo('both');
      bumpBoth(r, '1.0.0+37');
      final c = commit(r);
      final res = range(r, c.base, c.head);
      expect(res.exitCode, 0);
      expect(res.stdout as String, contains('is a bare version bump'));
    });

    test('pubspec.yaml alone -> exit 0 (pinned to isVersionBumpCommit; Gate 51 forces both at commit time)', () {
      final r = newRepo('pubonly');
      File('$r/pubspec.yaml').writeAsStringSync(_pub('1.0.0+37'));
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 0);
    });

    test('CRLF line endings do not break a genuine bump', () {
      final r = newRepo('crlf');
      File('$r/pubspec.yaml').writeAsBytesSync(_pub('1.0.0+36', eol: '\r\n').codeUnits);
      _git(['add', '-A'], r);
      _git(['commit', '-qm', 'crlf seed'], r);
      File('$r/pubspec.yaml').writeAsBytesSync(_pub('1.0.0+37', eol: '\r\n').codeUnits);
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 0);
    });

    test('the NET change across several commits counts, not each commit alone', () {
      final r = newRepo('net');
      final base = head(r);
      bumpBoth(r, '1.0.0+37');
      commit(r, 'chore: bump 37');
      bumpBoth(r, '1.0.0+38');
      final c = commit(r, 'chore: bump 38');
      expect(range(r, base, c.head).exitCode, 0,
          reason: 'two bump commits whose net diff is +36 -> +38 are still only version lines');
    });

    test('works from a merge base while main has moved on (the safe_merge.sh shape)', () {
      final r = newRepo('mergebase');
      _git(['checkout', '-q', '-B', 'bump', 'main'], r);
      bumpBoth(r, '1.0.0+37');
      commit(r, 'chore: bump');
      _git(['checkout', '-q', 'main'], r);
      File('$r/other.txt').writeAsStringSync('main moved on\n');
      commit(r, 'main: unrelated change');
      final mb = (_git(['merge-base', 'main', 'bump'], r).stdout as String).trim();
      expect(range(r, mb, 'bump').exitCode, 0, reason: 'merge-base..branch ignores what main did since');
      expect(range(r, 'main', 'bump').exitCode, 1,
          reason: 'setup guard: the TWO-dot main..bump also contains main\'s own change, which is '
              'why safe_merge.sh must pass the merge base');
    });
  });

  group('rangeIsVersionBump through the CLI — what is NOT a bump (every one fails closed to exit 1)', () {
    test('a bump plus ONE other file', () {
      final r = newRepo('plusfile');
      bumpBoth(r, '1.0.0+37');
      Directory('$r/docs').createSync();
      File('$r/docs/note.md').writeAsStringSync('hi\n');
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 1);
    });

    test('a bump plus a non-version line in app_constants.dart', () {
      final r = newRepo('price');
      File('$r/pubspec.yaml').writeAsStringSync(_pub('1.0.0+37'));
      File('$r/lib/core/constants/app_constants.dart')
          .writeAsStringSync(_con('1.0.0+37').replaceAll('349', '1'));
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 1);
    });

    test('an empty range (nothing changed) is not a bump', () {
      final r = newRepo('empty');
      expect(range(r, head(r), head(r)).exitCode, 1);
    });

    test('the version token unchanged but other content changed', () {
      final r = newRepo('notoken');
      File('$r/pubspec.yaml').writeAsStringSync('${_pub('1.0.0+36')}evil: true\n');
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 1);
    });

    test('deleting a version file is not a bump', () {
      final r = newRepo('delete');
      File('$r/lib/core/constants/app_constants.dart').deleteSync();
      File('$r/pubspec.yaml').writeAsStringSync(_pub('1.0.0+37'));
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 1);
    });

    test('moving a file out of the way beside the bump is not a bump', () {
      // (--no-renames and -z matter to the gate's TIER computation, which
      // shares diffPathsBetween with this function; those flags are pinned there, by
      // gate_input_family_e2e_test.dart P1-1 / P1-2. --ignore-submodules=none is pinned by
      // the F1 tests below, through the CLI and on diffPathsBetween directly. For bump
      // detection any extra path - however git spells it - already disqualifies, so THIS
      // test cannot discriminate the first two.)
      final r = newRepo('rename');
      Directory('$r/docs').createSync();
      _git(['mv', 'pubspec.yaml', 'docs/pubspec.bak'], r);
      File('$r/pubspec.yaml').writeAsStringSync(_pub('1.0.0+37'));
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 1,
          reason: 'a copy of the old pubspec appears under docs/: a second changed path');
    });

    test('a non-ASCII path riding along disqualifies the bump', () {
      final r = newRepo('nonascii');
      bumpBoth(r, '1.0.0+37');
      Directory('$r/lib/features/auth').createSync(recursive: true);
      File('$r/lib/features/auth/résumé.dart').writeAsStringSync('// x\n');
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 1);
    });

    test('a pubspec.yaml that is not valid UTF-8 does not crash and is not a bump', () {
      final r = newRepo('binary');
      File('$r/pubspec.yaml').writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47, 0x80, 0x81, 0xFF, 0xFE]);
      final c = commit(r);
      final res = range(r, c.base, c.head);
      expect(res.exitCode, 1);
      expect('${res.stdout}${res.stderr}', isNot(contains('FormatException')));
      expect('${res.stdout}${res.stderr}', isNot(contains('Unhandled exception')));
    });

    test('a symlink entry whose target text reads like a bumped pubspec (mode 120000)', () {
      final r = newRepo('symlink');
      File('$r/.target').writeAsStringSync('name: probe\nversion: 1.0.0+37\ndependencies:\n  foo: ^1.0.0\n');
      final blob = (_git(['hash-object', '-w', '.target'], r).stdout as String).trim();
      File('$r/.target').deleteSync();
      _git(['rm', '-q', '--cached', 'pubspec.yaml'], r);
      File('$r/pubspec.yaml').deleteSync();
      _git(['update-index', '--add', '--cacheinfo', '120000,$blob,pubspec.yaml'], r);
      final base = head(r);
      final c = _git(['commit', '-qm', 'chore: symlinked pubspec'], r);
      expect(c.exitCode, 0, reason: '${c.stdout}${c.stderr}');
      final mode = (_git(['ls-tree', 'HEAD', '--', 'pubspec.yaml'], r).stdout as String);
      expect(mode, startsWith('120000'), reason: 'setup: the entry must really be a symlink');
      expect(range(r, base, head(r)).exitCode, 1);
    });

    test('a file whose path differs from a version file only by whitespace cannot ride along a genuine bump', () {
      // `git diff --name-only` prints ' pubspec.yaml' raw. A trimming path normaliser turned it
      // into the real version file, so this commit - a genuine bump PLUS a file holding arbitrary
      // content under a look-alike name - was reported as a bare version bump. Found by probing the
      // CLI, not by an earlier review. The look-alike is written with `update-index --cacheinfo`
      // because the working tree never needs the file (and Windows cannot hold some of these names).
      // Each variant runs in its own repo; a variant THIS git refuses outright (git on Windows
      // rejects a trailing space) is skipped, but the leading-space one must be accepted by every git.
      const spoofs = [
        ' pubspec.yaml',
        '\tpubspec.yaml',
        '\u00a0pubspec.yaml',
        ' lib/core/constants/app_constants.dart',
        'pubspec.yaml ',
        'lib/core/constants/app_constants.dart ',
      ];
      final applied = <String>[];
      for (final spoof in spoofs) {
        final r = newRepo('spoof${applied.length}');
        final base = head(r);
        bumpBoth(r, '1.0.0+37');
        _git(['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], r);
        File('$r/.payload').writeAsStringSync('SPOOF PAYLOAD\n');
        final blob = (_git(['hash-object', '-w', '.payload'], r).stdout as String).trim();
        File('$r/.payload').deleteSync();
        final u = _git(['update-index', '--add', '--cacheinfo', '100644,$blob,$spoof'], r);
        if (u.exitCode != 0) continue; // this git refuses the path outright: nothing to guard
        final c = _git(['commit', '-qm', 'chore: bump versionCode plus a look-alike file'], r);
        expect(c.exitCode, 0, reason: 'setup: ${c.stdout}${c.stderr}');
        applied.add(spoof);
        // Setup guard: the committed range really contains the look-alike path. ASCII names only:
        // the test helper decodes git's output with the platform code page, which would mangle a
        // non-breaking space on Windows and fail the SETUP rather than the code.
        if (spoof.codeUnits.every((c) => c < 128)) {
          final names = (_git(['diff', '--no-renames', '--name-only', '-z', '$base..HEAD'], r).stdout as String)
              .split('\u0000');
          expect(names, contains(spoof), reason: 'setup: the look-alike path must be in the diff');
        }
        final res = range(r, base, head(r));
        expect(res.exitCode, 1,
            reason: 'a bump plus the look-alike ${spoof.codeUnits} is not a bare bump: '
                '${res.stdout}${res.stderr}');
      }
      expect(applied, contains(' pubspec.yaml'),
          reason: 'every git accepts a leading space in a path; if this fails the setup is broken, '
              'not the code');
    });

    test('MIRROR: a symlink pubspec on the BASE side turned back into a regular file is not a bump (120000 -> 100644)', () {
      // The test above guards the AFTER side. The mode check has two operands; a guard written
      // for the case the author just hit (a file BECOMING a symlink) leaves the symmetric case
      // (a symlink becoming a file) to whatever the code does by accident.
      final r = newRepo('symlinkbase');
      File('$r/.target').writeAsStringSync(_pub('1.0.0+36'));
      final blob = (_git(['hash-object', '-w', '.target'], r).stdout as String).trim();
      File('$r/.target').deleteSync();
      _git(['rm', '-q', '--cached', 'pubspec.yaml'], r);
      File('$r/pubspec.yaml').deleteSync();
      _git(['update-index', '--add', '--cacheinfo', '120000,$blob,pubspec.yaml'], r);
      final seed = _git(['commit', '-qm', 'pubspec.yaml as a symlink'], r);
      expect(seed.exitCode, 0, reason: '${seed.stdout}${seed.stderr}');
      // Head entry is written with `update-index --cacheinfo 100644`, not `git add`: with
      // core.symlinks=false (the Windows default) `git add` KEEPS an existing symlink entry's
      // mode when the working file is plain text, so the "regular file" would stay a symlink.
      final base = head(r);
      File('$r/.target2').writeAsStringSync(_pub('1.0.0+37'));
      final blob2 = (_git(['hash-object', '-w', '.target2'], r).stdout as String).trim();
      File('$r/.target2').deleteSync();
      _git(['update-index', '--add', '--cacheinfo', '100644,$blob2,pubspec.yaml'], r);
      final bumped = _git(['commit', '-qm', 'chore: bump back to a regular file'], r);
      expect(bumped.exitCode, 0, reason: '${bumped.stdout}${bumped.stderr}');
      final c = (base: base, head: head(r));
      final before = (_git(['ls-tree', c.base, '--', 'pubspec.yaml'], r).stdout as String);
      final after = (_git(['ls-tree', c.head, '--', 'pubspec.yaml'], r).stdout as String);
      expect(before, startsWith('120000'), reason: 'setup: base entry must be a symlink: $before');
      expect(after, startsWith('100644'), reason: 'setup: head entry must be a regular file: $after');
      expect(range(r, c.base, c.head).exitCode, 1);
    });

    test('an invalid UTF-8 byte is never treated as the U+FFFD it would decode to (no byte-equality collision)', () {
      // gitBlobAt decodes STRICTLY on purpose. With `allowMalformed: true`, a stray 0x80 decodes to
      // U+FFFD, so a file whose base holds a genuine U+FFFD and whose head holds a raw 0x80 at that
      // spot would compare equal once the version token is normalised - a bump, by accident.
      // The test above (a PNG header) cannot tell the two apart: it has no version token at all.
      final r = newRepo('collision');
      List<int> pubspec(String v, List<int> mark) => <int>[
            ...'name: probe\nversion: $v\n# note: '.codeUnits,
            ...mark,
            ...'\n'.codeUnits,
          ];
      File('$r/pubspec.yaml').writeAsBytesSync(pubspec('1.0.0+36', <int>[0xEF, 0xBF, 0xBD])); // a real U+FFFD
      _git(['add', '-A'], r);
      expect(_git(['commit', '-qm', 'seed with a real U+FFFD'], r).exitCode, 0);
      File('$r/pubspec.yaml').writeAsBytesSync(pubspec('1.0.0+37', <int>[0x80])); // an INVALID byte
      final c = commit(r);
      final res = range(r, c.base, c.head);
      expect(res.exitCode, 1, reason: '${res.stdout}${res.stderr}');
      expect('${res.stdout}${res.stderr}', isNot(contains('Unhandled exception')));
    });

    test('an unresolvable rev is exit 1, not an exception', () {
      final r = newRepo('badrev');
      final res = range(r, 'no-such-rev', 'HEAD');
      expect(res.exitCode, 1);
      expect('${res.stdout}${res.stderr}', isNot(contains('Unhandled exception')));
    });
  });

  group('B-pass of OI-275 B2 - CONTROLS (each must pass, or the attack tests below prove nothing)', () {
    test('a repo that carries .gitmodules (ignore = all) still gets its plain bump exempted', () {
      final r = newRepoWithGitmodules('gmctl');
      bumpBoth(r, '1.0.0+37');
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 0,
          reason: 'the same repo WITHOUT the gitlink is a bare bump; only the hidden gitlink may change that');
    });

    test('a UTF-8 byte-order mark present on BOTH sides does not break a genuine bump', () {
      final r = newRepo('bomboth');
      List<int> bytes(String v) => [0xEF, 0xBB, 0xBF, ..._pub(v).codeUnits];
      File('$r/pubspec.yaml').writeAsBytesSync(bytes('1.0.0+36'));
      _git(['add', '-A'], r);
      expect(_git(['commit', '-qm', 'seed with a BOM'], r).exitCode, 0);
      File('$r/pubspec.yaml').writeAsBytesSync(bytes('1.0.0+37'));
      final c = commit(r);
      expect(range(r, c.base, c.head).exitCode, 0, reason: 'a BOM that did not change is not a change');
    });

    test('a file that is executable on BOTH sides still gets its bump exempted (equality, not "must be 100644")', () {
      final r = newRepo('execboth');
      _git(['update-index', '--chmod=+x', 'pubspec.yaml'], r);
      expect(_git(['commit', '-qm', 'seed executable'], r).exitCode, 0);
      final base = head(r);
      bumpBoth(r, '1.0.0+37');
      _git(['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], r);
      // `git add` may re-derive the mode from the working file (Linux, core.filemode=true): pin the index.
      _git(['update-index', '--chmod=+x', 'pubspec.yaml'], r);
      expect(_git(['commit', '-qm', 'chore: bump versionCode'], r).exitCode, 0);
      String modeAt(String rev) => (_git(['ls-tree', rev, '--', 'pubspec.yaml'], r).stdout as String);
      expect(modeAt(base), startsWith('100755'), reason: 'setup: base is executable');
      expect(modeAt('HEAD'), startsWith('100755'), reason: 'setup: head is executable');
      expect(range(r, base, head(r)).exitCode, 0);
    });
  });

  group('B-pass of OI-275 B2 - what is NOT a bump (findings F1 and F4)', () {
    test('F1: a gitlink move hidden by .gitmodules `ignore = all` cannot ride along a bump', () {
      final r = newRepoWithGitmodules('gmattack');
      final c = commitBumpWithGitlink(r, '1.0.0+37');
      // The attack must be REAL or this proves nothing: plain `git diff` has to hide the gitlink.
      expect(listedByGit(r, c.base, c.head, seeSubmodules: false), isNot(contains('vendor/x')),
          reason: 'setup: under .gitmodules ignore = all plain `git diff --name-only` omits the gitlink');
      expect(listedByGit(r, c.base, c.head, seeSubmodules: true), contains('vendor/x'),
          reason: 'setup: --ignore-submodules=none reveals it');
      final res = range(r, c.base, c.head);
      expect(res.exitCode, 1,
          reason: 'a third path (vendor/x) is in the range, so this is not a bare version bump: '
              '${res.stdout}${res.stderr}');
    });

    test('F4: a byte-order mark ADDED beside a bump is not a bump, and neither is one REMOVED', () {
      for (final (label, baseBom, headBom) in const [('added', false, true), ('removed', true, false)]) {
        final r = newRepo('bom$label');
        List<int> bytes(String v, bool bom) => [if (bom) ...[0xEF, 0xBB, 0xBF], ..._pub(v).codeUnits];
        if (baseBom) {
          // newRepo's seed has no BOM; only a BOM base needs a commit of its own (an identical
          // rewrite would leave nothing to commit).
          File('$r/pubspec.yaml').writeAsBytesSync(bytes('1.0.0+36', true));
          _git(['add', '-A'], r);
          expect(_git(['commit', '-qm', 'seed with a BOM'], r).exitCode, 0);
        }
        File('$r/pubspec.yaml').writeAsBytesSync(bytes('1.0.0+37', headBom));
        final c = commit(r);
        // Dart's UTF-8 decoder drops a leading BOM, so before the fix BOTH read as the same text.
        final res = range(r, c.base, c.head);
        expect(res.exitCode, 1, reason: 'BOM $label: ${res.stdout}${res.stderr}');
      }
    });

    test('F4: flipping the executable bit beside a bump is not a bump (gained and lost)', () {
      for (final (label, baseExec, headExec) in const [('gained', false, true), ('lost', true, false)]) {
        final r = newRepo('exec$label');
        if (baseExec) {
          _git(['update-index', '--chmod=+x', 'pubspec.yaml'], r);
          expect(_git(['commit', '-qm', 'seed executable'], r).exitCode, 0);
        }
        final base = head(r);
        bumpBoth(r, '1.0.0+37');
        _git(['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart'], r);
        _git(['update-index', '--chmod=${headExec ? '+x' : '-x'}', 'pubspec.yaml'], r);
        expect(_git(['commit', '-qm', 'chore: bump versionCode and the mode'], r).exitCode, 0);
        final mode = (_git(['ls-tree', 'HEAD', '--', 'pubspec.yaml'], r).stdout as String);
        expect(mode, startsWith(headExec ? '100755' : '100644'), reason: 'setup ($label): $mode');
        final res = range(r, base, head(r));
        expect(res.exitCode, 1, reason: 'mode flip ($label): ${res.stdout}${res.stderr}');
      }
    });

    test('F4: appVersion changed to something that is not a version is not a bump', () {
      final r = newRepo('constval');
      File('$r/pubspec.yaml').writeAsStringSync(_pub('1.0.0+37'));
      File('$r/lib/core/constants/app_constants.dart').writeAsStringSync(_con('x'));
      final c = commit(r);
      final res = range(r, c.base, c.head);
      expect(res.exitCode, 1, reason: 'the pubspec half is a genuine bump; the constant became \'x\': ${res.stdout}${res.stderr}');
    });
  });

  group('diffPathsBetween read directly (the CLI cannot tell "git could not answer" from "nothing changed")', () {
    test('an unresolvable rev is NULL - not an empty list', () {
      final r = newRepo('dpbad');
      expect(diffPaths(r, 'no-such-rev', 'HEAD'), isNull,
          reason: 'the gate treats null as a hard failure; an empty list reads as feature tier and PASSES');
    });

    test('MIRROR: an empty range is an empty list - not NULL', () {
      final r = newRepo('dpempty');
      final paths = diffPaths(r, 'HEAD', 'HEAD');
      expect(paths, isNotNull);
      expect(paths, isEmpty);
    });

    test('a real change is listed exactly, one entry per path', () {
      final r = newRepo('dpreal');
      bumpBoth(r, '1.0.0+37');
      final c = commit(r);
      expect(diffPaths(r, c.base, c.head), ['lib/core/constants/app_constants.dart', 'pubspec.yaml']);
    });

    test('a path that is not valid UTF-8 makes the whole answer NULL, never a lenient decode', () {
      final r = newRepo('dpbadutf8');
      final base = head(r);
      commitFileNamed(r, 'docs/ÿþ.md', 'docs: a name that is not UTF-8', rawNames: true);
      expect(diffPaths(r, base, 'HEAD'), isNull,
          reason: '0xFF 0xFE decode to U+FFFD under allowMalformed, so distinct bad names would collapse '
              'into one and the answer would look complete');
    });

    test('MIRROR: a valid non-ASCII path is listed verbatim', () {
      final r = newRepo('dputf8');
      final base = head(r);
      commitFileNamed(r, 'docs/résumé.md', 'docs: a note');
      expect(diffPaths(r, base, 'HEAD'), ['docs/résumé.md']);
    });

    test('a path with a leading space is listed as stored - never trimmed', () {
      final r = newRepo('dplead');
      final base = head(r);
      File('$r/.payload').writeAsStringSync('x\n');
      final blob = (_git(['hash-object', '-w', '.payload'], r).stdout as String).trim();
      File('$r/.payload').deleteSync();
      expect(_git(['update-index', '--add', '--cacheinfo', '100644,$blob, pubspec.yaml'], r).exitCode, 0);
      expect(_git(['commit', '-qm', 'a look-alike'], r).exitCode, 0);
      expect(diffPaths(r, base, 'HEAD'), [' pubspec.yaml']);
    });

    test('F1: a gitlink hidden by .gitmodules `ignore = all` IS listed', () {
      final r = newRepoWithGitmodules('dpgm');
      final c = commitBumpWithGitlink(r, '1.0.0+37');
      expect(listedByGit(r, c.base, c.head, seeSubmodules: false), isNot(contains('vendor/x')),
          reason: 'setup: the plain list hides it');
      expect(diffPaths(r, c.base, c.head), contains('vendor/x'));
    });
  });

  group('the CLI contract', () {
    test('usage errors exit 64 with a usage line and no verdict on stdout', () {
      final r = newRepo('usage');
      for (final args in [
        <String>[],
        ['only-one'],
        ['a', 'b', 'c'],
        ['', 'HEAD'],
        ['HEAD', '  '],
      ]) {
        final res = runSpawn(dartBin(), [script, ...args], why: 'usage $args', workingDirectory: r);
        expect(res.exitCode, 64, reason: 'args $args');
        expect((res.stdout as String).trim(), isEmpty, reason: 'args $args');
        expect(res.stderr as String, contains('usage:'));
      }
    });

    test('outside a git repository it fails closed (exit 1), never 0', () {
      final tmp = Directory.systemTemp.createTempSync('vbump_norepo');
      repos.add(tmp);
      final res = runSpawn(dartBin(), [script, 'HEAD~1', 'HEAD'], why: 'no repo', workingDirectory: tmp.path);
      expect(res.exitCode, 1);
    });
  });
}
