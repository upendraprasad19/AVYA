// test/scripts/setup_hooks_atomic_install_e2e_test.dart
//
// Executes the REAL scripts/setup-hooks.sh in throwaway repos.
//
// WHY. The installed hooks live in ONE directory shared by every worktree, and
// the installer used to `cp` over them in place. Two failure shapes followed:
//   * a git process that was mid-way through running the old hook had the script
//     rewritten underneath it (sh reads a script in blocks);
//   * an installer run from a STALE tree silently downgraded the hooks for every
//     concurrent session (18 of 21 worktrees were stale-based when this was found).
// The installer now copies to a temp file, verifies it, makes it executable and
// read-only, and renames it over the old hook. A rename swaps the directory entry
// (a running hook keeps its inode) and a plain `cp` over a read-only hook fails
// with "Permission denied", so an OLD tree's installer fails loudly.
//
// Each case names the mutant it kills (rule 21):
//   4   re-install over read-only hooks works; result is read-only AND executable
//       [drop `chmod a-w`; drop `chmod +x`]
//   5   a plain `cp` over an installed hook fails, bytes unchanged   [drop `a-w`]
//   6   a hook MID-RUN survives a re-install (needs the end marker)  [in-place write]
//   7   a missing middle source: the others install, exit 1          [stop at first]
//   8   a failing `mv`: exit 1, no temp left, old hook intact and read-only; a
//       fresh dir names all five                [drop mode restore; drop `|| true`]
//   9   a directory at the destination: refused, directory stays empty [drop guard]
//   10  the REAL sources install, Gate 32 says PASS, call shape is canonical
//   11  a lying `mv` (exit 0, moves nothing)                [drop the post-swap cmp]
//   12  a foreign temp file survives                         [widen the trap glob]
//   13  SIGTERM mid-install leaves no temp (dash only)       [drop the signal traps]
//   14  a corrupting `cp` never replaces a live hook         [drop the pre-swap cmp]
//   15  behind / diverged / unreadable origin/main -> REFUSES (hooks untouched); a stale
//       LINKED worktree is refused; --allow-stale installs with a warning; up to date, ahead,
//       no ref -> silent (empty stderr); a tree off main with unmerged hook sources is
//       refused (--allow-unmerged), on main it only warns; unknown arguments exit 2; a
//       subdirectory run is not a linked worktree
//       [drop the refusal; HEAD -> main; drop 2>&1; [ -n "$1" ]; drop -C; drop the diff guard]
//   16  a failing README write is a warning, not a failed hook, and leaves no temp
//       [count it as a hook failure; drop the EXIT trap]
//   17  the README carries the recipe markers and no `$`     [drop the README write]
//   18  a stale .git/config.lock is a recorded failure, not an abort  [drop the || record]
//   19  a failing chmod +x installs NOTHING and says why; a failing chmod a-w only warns
//   20  a recording mv stub proves: mode set BEFORE the rename, temp beside the hook, mv -f
//       [chmod after the swap; /dev/shm temp; mv without -f]
//   21  a Git-Bash-like mv (refuses a read-only target) still reinstalls  [drop the u+w retry]
//   22  a cmp that cannot run is a persistent "cannot compare", not a "differs"
//       [collapse every cmp failure to "differs"]
//
// POSIX-only, and skipped as root (root ignores permission bits).

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

const _hookNames = ['pre-commit', 'pre-push', 'commit-msg', 'prepare-commit-msg', 'pre-merge-commit'];

String _run(List<String> cmd, String cwd, {Map<String, String> env = const {}}) {
  final r = runSpawn(
    cmd.first,
    cmd.sublist(1),
    why: 'setup_hooks_atomic_install_e2e: ${cmd.join(' ')}',
    workingDirectory: cwd,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    extraEnv: env,
  );
  return '${r.exitCode}\u0000${r.stdout}\u0000${r.stderr}';
}

class _Res {
  _Res(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
  String get all => '$out$err';
  String diag() => 'exit=$code\nstdout:\n$out\nstderr:\n$err';
}

_Res _res(String packed) {
  final p = packed.split('\u0000');
  return _Res(int.parse(p[0]), p[1], p[2]);
}

void _git(String cwd, List<String> args) {
  final r = _res(_run(['git', ...args], cwd));
  if (r.code != 0) throw StateError('git ${args.join(' ')} failed:\n${r.diag()}');
}

String _source(String name, String v) => '#!/bin/sh\n# $name $v\necho $name $v\n';

// Dart has no octal literals: 0o222 / 0o111.
const _wBits = 0x92;
// chmod +x honours the umask, so only the OWNER exec bit is asserted (umask 077 gives 0500).
const _ownerX = 0x40;

int _mode(String path) => File(path).statSync().mode & 0x1FF;

/// Anything that looks like a leftover temp: `.tmp` anywhere in the NAME (not only
/// `.tmp.<pid>`), so a temp name that lost its pid component is still seen.
List<String> _tmpFiles(String dir) => Directory(dir)
    .listSync(recursive: true)
    .map((e) => e.path)
    .where((p) => p.split('/').last.contains('.tmp'))
    .toList();

bool _same(String a, String b) {
  final x = File(a).readAsBytesSync();
  final y = File(b).readAsBytesSync();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

void main() {
  final isRoot = !Platform.isWindows &&
      runSpawn('id', ['-u'], why: 'is root', stdoutEncoding: utf8).stdout.toString().trim() == '0';
  if (Platform.isWindows || isRoot) {
    test('POSIX non-root only', () {}, skip: 'needs POSIX permission semantics and a non-root user');
    return;
  }

  late Directory tmp;
  late String repoRoot;
  late String realMv;
  // Eager: `skip:` of a test() is evaluated at declaration time, before setUpAll runs.
  final shIsDash = runSpawn('readlink', ['-f', '/bin/sh'], why: 'is sh dash', stdoutEncoding: utf8)
      .stdout
      .toString()
      .trim()
      .endsWith('/dash');

  setUpAll(() {
    repoRoot = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('sethooks_');
    final w = runSpawn('which', ['mv'], why: 'locate mv', stdoutEncoding: utf8);
    realMv = '${w.stdout}'.trim().split('\n').first;
  });

  tearDownAll(() {
    try {
      runSpawn('chmod', ['-R', 'u+w', tmp.path], why: 'teardown chmod');
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  var n = 0;

  /// A repo holding the REAL installer and five fixture hook sources written 0644
  /// (so `chmod +x` in the installer is load-bearing).
  String fixture({bool realSources = false, String version = 'v1'}) {
    final root = '${tmp.path}/r${n++}';
    Directory('$root/scripts').createSync(recursive: true);
    _git(root, ['init', '-q', '-b', 'main', '.']);
    _git(root, ['config', 'user.email', 't@t.t']);
    _git(root, ['config', 'user.name', 't']);
    _git(root, ['config', 'commit.gpgsign', 'false']);
    File('$repoRoot/scripts/setup-hooks.sh').copySync('$root/scripts/setup-hooks.sh');
    for (final h in _hookNames) {
      if (realSources) {
        File('$repoRoot/scripts/$h.sh').copySync('$root/scripts/$h.sh');
      } else {
        File('$root/scripts/$h.sh').writeAsStringSync(_source(h, version));
      }
    }
    return root;
  }

  void setSources(String root, String version) {
    for (final h in _hookNames) {
      File('$root/scripts/$h.sh').writeAsStringSync(_source(h, version));
    }
  }

  String stub(String root, String name, String body) {
    final dir = '$root/stubbin';
    Directory(dir).createSync(recursive: true);
    File('$dir/$name').writeAsStringSync('#!/bin/sh\n$body\n');
    runSpawn('chmod', ['+x', '$dir/$name'], why: 'stub chmod +x');
    return dir;
  }

  Map<String, String> pathWith(String? stubDir) => {'PATH': '${stubDir == null ? '' : '$stubDir:'}/usr/bin:/bin'};

  _Res install(String root, {String? stubDir, List<String> args = const []}) =>
      _res(_run(['sh', 'scripts/setup-hooks.sh', ...args], root, env: pathWith(stubDir)));

  String hooksOf(String root) => '$root/.git/hooks';

  test('4: re-install over read-only hooks succeeds; the result is read-only AND executable', () {
    final r = fixture();
    expect(install(r).code, 0);
    setSources(r, 'v2');
    final res = install(r);
    expect(res.code, 0, reason: res.diag());
    for (final h in _hookNames) {
      final p = '${hooksOf(r)}/$h';
      expect(_same('$r/scripts/$h.sh', p), isTrue, reason: '$h must carry the NEW source');
      expect(_mode(p) & _wBits, 0, reason: '$h must stay non-writable (mode ${_mode(p).toRadixString(8)})');
      expect(_mode(p) & _ownerX, _ownerX, reason: '$h must be executable (sources are 0644, so chmod +x is load-bearing)');
    }
  });

  test('5: an old-style plain cp over an installed hook fails and the bytes are unchanged', () {
    final r = fixture();
    expect(install(r).code, 0);
    setSources(r, 'v2');
    final before = File('${hooksOf(r)}/pre-commit').readAsBytesSync();
    final cp = _res(_run(['cp', 'scripts/pre-commit.sh', '${hooksOf(r)}/pre-commit'], r));
    expect(cp.code, isNot(0), reason: 'a stale installer doing an in-place cp must be refused\n${cp.diag()}');
    expect(File('${hooksOf(r)}/pre-commit').readAsBytesSync(), before);
  });

  test('6: a hook that is RUNNING while it is re-installed finishes with its OLD content', () async {
    final r = fixture();
    // v1 > 16 KiB: "started" marker and the wait loop sit in the first 8 KiB block, the
    // end marker is the LAST line, so an in-place rewrite that shrinks the file makes sh
    // read EOF where the end marker was.
    final padding = List.filled(300, '# ${'x' * 70}').join('\n');
    File('$r/scripts/pre-commit.sh').writeAsStringSync('#!/bin/sh\n'
        'echo started > "\$1/started"\n'
        'while [ ! -f "\$1/go" ]; do sleep 0.05; done\n'
        '$padding\n'
        'echo end > "\$1/end"\n');
    for (final h in _hookNames.where((h) => h != 'pre-commit')) {
      File('$r/scripts/$h.sh').writeAsStringSync(_source(h, 'v1'));
    }
    expect(install(r).code, 0);
    expect(File('${hooksOf(r)}/pre-commit').lengthSync(), greaterThan(16 * 1024));

    final marks = Directory('$r/marks')..createSync();
    final p = await startSpawn('sh', ['${hooksOf(r)}/pre-commit', marks.path],
        workingDirectory: r, extraEnv: pathWith(null));
    // The hook spins until `go` exists; never leave it orphaned if an expectation throws.
    addTearDown(() {
      File('${marks.path}/go').writeAsStringSync('go');
      p.kill();
    });
    final out = p.stdout.transform(utf8.decoder).join();
    final err = p.stderr.transform(utf8.decoder).join();
    for (var i = 0; i < 200 && !File('${marks.path}/started').existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(File('${marks.path}/started').existsSync(), isTrue, reason: 'the hook never started');

    File('$r/scripts/pre-commit.sh').writeAsStringSync(_source('pre-commit', 'v2'));
    final res = install(r);
    File('${marks.path}/go').writeAsStringSync('go');
    final code = await p.exitCode;
    reportSpawn(code, await out, await err, 'setup_hooks_atomic_install_e2e: running hook');

    expect(res.code, 0, reason: res.diag());
    expect(_same('$r/scripts/pre-commit.sh', '${hooksOf(r)}/pre-commit'), isTrue,
        reason: 'the NEW content must be in place');
    expect(File('${marks.path}/end').existsSync(), isTrue,
        reason: 'the running hook must still reach its last line; an in-place rewrite truncates it');
  });

  test('7: a missing middle source -> the other four install, exit 1, the hook is named', () {
    final r = fixture();
    File('$r/scripts/commit-msg.sh').deleteSync();
    final res = install(r);
    expect(res.code, 1, reason: res.diag());
    expect(res.err, contains('  - commit-msg: source '), reason: 'the list names the hook, not a path\n${res.diag()}');
    expect(res.err, contains('fix the tree'));
    for (final h in _hookNames.where((h) => h != 'commit-msg')) {
      expect(File('${hooksOf(r)}/$h').existsSync(), isTrue, reason: '$h must still be installed');
    }
    expect(File('${hooksOf(r)}/commit-msg').existsSync(), isFalse);
  });

  test('8: a failing mv -> exit 1, no temp left, old hooks intact AND read-only; a fresh dir names all five', () {
    final r = fixture();
    expect(install(r).code, 0);
    final v1 = {for (final h in _hookNames) h: File('${hooksOf(r)}/$h').readAsBytesSync()};
    setSources(r, 'v2');
    final stubDir = stub(r, 'mv', 'exit 1');
    final res = install(r, stubDir: stubDir);
    expect(res.code, 1, reason: res.diag());
    expect(_tmpFiles(hooksOf(r)), isEmpty, reason: 'no temp may be left under the hooks dir');
    for (final h in _hookNames) {
      final p = '${hooksOf(r)}/$h';
      expect(File(p).readAsBytesSync(), v1[h], reason: '$h must keep its old bytes');
      expect(_mode(p) & _wBits, 0, reason: '$h must be restored to read-only after the failed retry');
    }

    // Fresh hooks dir: nothing to chmod, so a bare `chmod` failing under set -e would abort early.
    final f = fixture();
    final fres = install(f, stubDir: stub(f, 'mv', 'exit 1'));
    expect(fres.code, 1, reason: fres.diag());
    for (final h in _hookNames) {
      expect(fres.err, contains(h), reason: 'every hook must be named; the installer must not abort early\n${fres.diag()}');
    }
    expect(fres.err, contains('retry when no commit is running'));
    expect(_tmpFiles(hooksOf(f)), isEmpty);
  });

  test('9: a directory at the destination is refused and left EMPTY', () {
    final r = fixture();
    Directory('${hooksOf(r)}/pre-commit').createSync(recursive: true);
    final res = install(r);
    expect(res.code, 1, reason: res.diag());
    expect(res.err, contains('is a directory'));
    expect(Directory('${hooksOf(r)}/pre-commit').listSync(), isEmpty,
        reason: 'mv would have moved the temp INTO the directory');
    expect(_tmpFiles(hooksOf(r)), isEmpty);
    expect(File('${hooksOf(r)}/pre-push').existsSync(), isTrue);
  });

  test('10: the REAL sources install and Gate 32 says PASS; the call shape stays canonical', () {
    final r = fixture(realSources: true);
    File('$repoRoot/scripts/check_hooks_installed.dart').copySync('$r/scripts/check_hooks_installed.dart');
    expect(install(r).code, 0);
    final gate = _res(_run([dartBin(), 'run', 'scripts/check_hooks_installed.dart'], r, env: pathWith(null)));
    expect(gate.code, 0, reason: gate.diag());
    expect(gate.out, contains('PASS: all 5 hook(s)'), reason: gate.diag());
    expect(gate.all, isNot(contains('WARN')), reason: gate.diag());
    expect(gate.all.toLowerCase(), isNot(contains('stale')), reason: gate.diag());
    for (final h in _hookNames) {
      expect(_mode('${hooksOf(r)}/$h') & _ownerX, _ownerX);
    }
    final src = File('$repoRoot/scripts/setup-hooks.sh').readAsStringSync();
    expect(RegExp(r'install_hook\s+"').allMatches(src).length, 5,
        reason: 'only the five canonical calls may use the quoted call shape (Gate 32 and two tests parse it)');
    expect(src, contains('\ninstall_hook() {\n'), reason: 'the definition keeps its exact signature');
  });

  test('11: a lying mv (exit 0, moves nothing) -> exit 1, hook named, no "installed" line', () {
    final r = fixture();
    final res = install(r, stubDir: stub(r, 'mv', 'exit 0'));
    expect(res.code, 1, reason: res.diag());
    for (final h in _hookNames) {
      expect(res.err, contains(h));
    }
    // hooksOf() is absolute but the installer prints the path git gave it (relative at the top
    // of a primary worktree), so a path-qualified isNot(contains(...)) could never fail.
    expect(res.out, isNot(contains('[setup-hooks] installed')), reason: res.diag());
    expect(res.err, contains('retry when no commit is running'));
    expect(_tmpFiles(hooksOf(r)), isEmpty);
  });

  test('12: a foreign temp file survives; our own is gone', () {
    final r = fixture();
    Directory(hooksOf(r)).createSync(recursive: true);
    // One non-numeric and one NUMERIC foreign name: a trap glob widened to `*.tmp.[0-9]*`
    // would delete the second, and a concurrent installer's temp is exactly that shape.
    File('${hooksOf(r)}/pre-commit.tmp.foreign').writeAsStringSync('someone else');
    File('${hooksOf(r)}/pre-push.tmp.1').writeAsStringSync('another installer');
    final res = install(r, stubDir: stub(r, 'mv', 'exit 1'));
    expect(res.code, 1, reason: res.diag());
    expect(_tmpFiles(hooksOf(r))..sort(),
        ['${hooksOf(r)}/pre-commit.tmp.foreign', '${hooksOf(r)}/pre-push.tmp.1'],
        reason: 'the EXIT trap must remove only this process\'s own temp files');
  });

  test('13: SIGTERM during the install leaves no temp file', () {
    final r = fixture();
    final res = install(r, stubDir: stub(r, 'mv', 'kill -TERM \$PPID\nexit 0'));
    expect(res.code, isNot(0), reason: res.diag());
    expect(_tmpFiles(hooksOf(r)), isEmpty, reason: 'dash skips the EXIT trap on signal death; the TERM trap fixes that');
  }, skip: shIsDash ? false : 'sh is not dash here: the residual is recorded in the diagnose doc');

  test('14: a cp that corrupts its output never replaces a live hook', () {
    final r = fixture();
    expect(install(r).code, 0);
    final v1 = {for (final h in _hookNames) h: File('${hooksOf(r)}/$h').readAsBytesSync()};
    setSources(r, 'v2');
    final stubDir = stub(r, 'cp', 'for a; do last="\$a"; done\nprintf CORRUPT > "\$last"\nexit 0');
    final res = install(r, stubDir: stubDir);
    expect(res.code, 1, reason: res.diag());
    for (final h in _hookNames) {
      expect(File('${hooksOf(r)}/$h').readAsBytesSync(), v1[h], reason: '$h must keep its old bytes');
    }
    expect(res.err, contains('retry when no commit is running'), reason: res.diag());
    expect(_tmpFiles(hooksOf(r)), isEmpty);
  });

  group('15: behind origin/main', () {
    String twoCommits(String root) {
      File('$root/seed.txt').writeAsStringSync('seed\n');
      _git(root, ['add', 'seed.txt']);
      _git(root, ['commit', '-q', '-m', 'seed']);
      return _res(_run(['git', 'rev-parse', 'HEAD'], root)).out.trim();
    }

    /// HEAD stays put; origin/main points at a child of it, so HEAD is BEHIND.
    void makeBehind(String root) {
      final head = twoCommits(root);
      final tree = _res(_run(['git', 'rev-parse', 'HEAD^{tree}'], root)).out.trim();
      final ahead = _res(_run(['git', 'commit-tree', tree, '-p', head, '-m', 'ahead'], root)).out.trim();
      _git(root, ['update-ref', 'refs/remotes/origin/main', ahead]);
    }

    test('behind -> REFUSES before replacing anything: exit 1, hooks untouched', () {
      final r = fixture();
      makeBehind(r);
      final res = install(r);
      expect(res.code, 1, reason: res.diag());
      expect(res.err, allOf(contains('REFUSING'), contains('behind origin/main'), contains('--allow-stale')),
          reason: res.diag());
      expect(Directory(hooksOf(r)).listSync().where((e) => !e.path.endsWith('.sample')), isEmpty,
          reason: 'nothing may be installed, and no README either');
    });

    test('a stale tree cannot DOWNGRADE hooks that a newer tree installed', () {
      final newer = fixture(version: 'v2');
      expect(install(newer).code, 0);
      final v2 = {for (final h in _hookNames) h: File('${hooksOf(newer)}/$h').readAsBytesSync()};
      // The "stale tree": same hooks dir (point its git common dir at the newer one), older sources.
      final stale = fixture(version: 'v1');
      makeBehind(stale);
      Directory('${stale}/.git/hooks').deleteSync(recursive: true);
      Link('${stale}/.git/hooks').createSync(hooksOf(newer));
      final res = install(stale);
      expect(res.code, 1, reason: res.diag());
      for (final h in _hookNames) {
        expect(File('${hooksOf(newer)}/$h').readAsBytesSync(), v2[h], reason: '$h must stay at v2');
      }
    });

    test('--allow-stale installs from a behind tree, with a warning', () {
      final r = fixture();
      makeBehind(r);
      final res = install(r, args: ['--allow-stale']);
      expect(res.code, 0, reason: res.diag());
      expect(res.all, contains('behind relative to origin/main'), reason: res.diag());
      expect(res.all, contains('--allow-stale'));
      for (final h in _hookNames) {
        expect(File('${hooksOf(r)}/$h').existsSync(), isTrue);
      }
    });

    test('behind + --allow-stale + a failed hook -> the README is still written before the exit 1', () {
      final r = fixture();
      makeBehind(r);
      File('$r/scripts/commit-msg.sh').deleteSync();
      final res = install(r, args: ['--allow-stale']);
      expect(res.code, 1, reason: res.diag());
      expect(res.all, contains('behind relative to origin/main'), reason: res.diag());
      expect(File('${hooksOf(r)}/AVYA-HOOKS-README.txt').existsSync(), isTrue);
    });

    test('up to date -> silent', () {
      final r = fixture();
      final head = twoCommits(r);
      _git(r, ['update-ref', 'refs/remotes/origin/main', head]);
      final res = install(r);
      expect(res.code, 0, reason: res.diag());
      expect(res.all, isNot(contains('behind')), reason: res.diag());
      expect(res.err, isEmpty, reason: 'silent means silent: no git fatal, no WARNING\n${res.diag()}');
    });

    test('ahead of origin/main (merged but not pushed) -> installs, silent', () {
      final r = fixture();
      final head = twoCommits(r);
      _git(r, ['update-ref', 'refs/remotes/origin/main', head]);
      File('$r/more.txt').writeAsStringSync('more\n');
      _git(r, ['add', 'more.txt']);
      _git(r, ['commit', '-q', '-m', 'local only']);
      final res = install(r);
      expect(res.code, 0, reason: res.diag());
      expect(res.all, isNot(contains('behind')), reason: res.diag());
      expect(res.err, isEmpty, reason: 'silent means silent: no git fatal, no WARNING\n${res.diag()}');
    });

    test('no origin/main ref at all (exit 128) -> silent', () {
      final r = fixture();
      twoCommits(r);
      final res = install(r);
      expect(res.code, 0, reason: res.diag());
      expect(res.all, isNot(contains('behind')), reason: res.diag());
      expect(res.err, isEmpty, reason: 'silent means silent: no git fatal, no WARNING\n${res.diag()}');
    });

    test('a STALE linked worktree is refused even though the primary main is current (HEAD, not main, is compared)', () {
      // The scenario that actually hurt: 18 of 21 trees were stale-based. Comparing the PRIMARY's
      // local main instead of the tree being installed from would let this one through.
      final r = fixture();
      File('$r/a.txt').writeAsStringSync('a\n');
      _git(r, ['add', 'a.txt']);
      _git(r, ['commit', '-q', '-m', 'A']);
      final older = _res(_run(['git', 'rev-parse', 'HEAD'], r)).out.trim();
      File('$r/b.txt').writeAsStringSync('b\n');
      _git(r, ['add', 'b.txt']);
      _git(r, ['commit', '-q', '-m', 'B']);
      _git(r, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
      final wt = '$r-stale';
      _git(r, ['worktree', 'add', '-q', '-b', 'stale', wt, older]);
      addTearDown(() {
        try {
          Directory(wt).deleteSync(recursive: true);
        } catch (_) {}
      });
      Directory('$wt/scripts').createSync(recursive: true);
      for (final f in ['setup-hooks.sh', ..._hookNames.map((h) => '$h.sh')]) {
        File('$r/scripts/$f').copySync('$wt/scripts/$f');
      }
      final res = install(wt);
      expect(res.code, 1, reason: res.diag());
      expect(res.err, contains('REFUSING'), reason: res.diag());
      expect(Directory(hooksOf(r)).listSync().where((e) => !e.path.endsWith('.sample')), isEmpty);

      // The converse: a worktree branched from the current main installs.
      final fresh = '$r-fresh';
      _git(r, ['worktree', 'add', '-q', '-b', 'fresh', fresh, 'main']);
      addTearDown(() {
        try {
          Directory(fresh).deleteSync(recursive: true);
        } catch (_) {}
      });
      Directory('$fresh/scripts').createSync(recursive: true);
      for (final f in ['setup-hooks.sh', ..._hookNames.map((h) => '$h.sh')]) {
        File('$r/scripts/$f').copySync('$fresh/scripts/$f');
      }
      final ok = install(fresh);
      expect(ok.code, 0, reason: ok.diag());
    });

    test('a DIVERGED tree is told to merge or push, not to fast-forward (which cannot work)', () {
      final r = fixture();
      final head = twoCommits(r);
      final tree = _res(_run(['git', 'rev-parse', 'HEAD^{tree}'], r)).out.trim();
      // origin/main and HEAD are siblings of one parent: neither contains the other.
      final sibling = _res(_run(['git', 'commit-tree', tree, '-p', head, '-m', 'origin side'], r)).out.trim();
      _git(r, ['update-ref', 'refs/remotes/origin/main', sibling]);
      File('$r/local.txt').writeAsStringSync('local\n');
      _git(r, ['add', 'local.txt']);
      _git(r, ['commit', '-q', '-m', 'local side']);
      final res = install(r);
      expect(res.code, 1, reason: res.diag());
      expect(res.err, allOf(contains('diverged'), contains('Merge origin/main'), contains('--allow-stale')),
          reason: res.diag());
      expect(res.err, isNot(contains('--ff-only')), reason: 'a fast-forward cannot fix a divergence');
    });

    test('an unreadable history is reported with git\'s own words, not as "behind"', () {
      final r = fixture();
      makeBehind(r);
      final gitPath = _res(_run(['which', 'git'], r)).out.trim();
      final stubDir = stub(
          r,
          'git',
          'case "\$*" in\n'
              '  *merge-base*--is-ancestor*origin/main*HEAD*) echo "error: Could not read 0123abcd" >&2; exit 1 ;;\n'
              'esac\n'
              'exec $gitPath "\$@"');
      final res = install(r, stubDir: stubDir);
      expect(res.code, 1, reason: res.diag());
      expect(res.err, allOf(contains('unreadable'), contains('Could not read 0123abcd')), reason: res.diag());
      expect(res.err, isNot(contains('--ff-only')));
    });

    test('an unknown argument exits 2 before touching anything, and never overrides a refusal', () {
      final r = fixture();
      makeBehind(r);
      final res = install(r, args: ['--typo']);
      expect(res.code, 2, reason: res.diag());
      expect(res.err, contains('unknown argument: --typo'));
      expect(Directory(hooksOf(r)).existsSync() && Directory(hooksOf(r)).listSync().any((e) => !e.path.endsWith('.sample')),
          isFalse);
    });

    test('the two overrides are independent: --allow-unmerged does not excuse a stale tree', () {
      final r = fixture();
      makeBehind(r);
      final res = install(r, args: ['--allow-unmerged']);
      expect(res.code, 1, reason: res.diag());
      expect(res.err, contains('REFUSING'), reason: res.diag());
    });

    test('--help prints the usage and installs nothing', () {
      final r = fixture();
      final res = install(r, args: ['--help']);
      expect(res.code, 0, reason: res.diag());
      expect(res.out, allOf(contains('usage:'), contains('--allow-stale'), contains('--allow-unmerged')));
      expect(Directory(hooksOf(r)).existsSync() && Directory(hooksOf(r)).listSync().any((e) => !e.path.endsWith('.sample')),
          isFalse);
    });

    test('run from a SUBDIRECTORY of the primary: exit 0 and no linked-worktree note', () {
      // Both rev-parse calls need -C <toplevel>; from a subdirectory the git dir prints absolute
      // and the common dir prints ../.git, so an un-anchored comparison would cry wolf.
      final r = fixture();
      final res = _res(_run(['sh', 'setup-hooks.sh'], '$r/scripts', env: pathWith(null)));
      expect(res.code, 0, reason: res.diag());
      expect(res.all, isNot(contains('linked worktree')), reason: res.diag());
    });

    group('unmerged hook sources', () {
      /// Hook sources TRACKED and committed; origin/main at that commit; a second commit on `branch`
      /// changes pre-commit.sh. The installer then sees an AHEAD tree whose hook sources differ.
      String ahead({required String branch}) {
        final r = fixture();
        for (final h in _hookNames) {
          _git(r, ['add', 'scripts/$h.sh']);
        }
        _git(r, ['commit', '-q', '-m', 'base']);
        _git(r, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
        if (branch != 'main') _git(r, ['checkout', '-q', '-b', branch]);
        File('$r/scripts/pre-commit.sh').writeAsStringSync(_source('pre-commit', 'EXPERIMENTAL'));
        _git(r, ['add', 'scripts/pre-commit.sh']);
        _git(r, ['commit', '-q', '-m', 'experimental hook']);
        return r;
      }

      test('a feature branch with changed hook sources is REFUSED; --allow-unmerged installs with a warning', () {
        final r = ahead(branch: 'feature');
        final res = install(r);
        expect(res.code, 1, reason: res.diag());
        expect(res.err, allOf(contains('REFUSING'), contains('scripts/pre-commit.sh'), contains('--allow-unmerged')),
            reason: res.diag());
        expect(Directory(hooksOf(r)).listSync().where((e) => !e.path.endsWith('.sample')), isEmpty);

        final ok = install(r, args: ['--allow-unmerged']);
        expect(ok.code, 0, reason: ok.diag());
        expect(ok.out, allOf(contains('WARNING'), contains('scripts/pre-commit.sh')), reason: ok.diag());
        expect(File('${hooksOf(r)}/pre-commit').readAsStringSync(), contains('EXPERIMENTAL'));
      });

      test('--allow-stale does not excuse unmerged hook sources', () {
        final r = ahead(branch: 'feature');
        final res = install(r, args: ['--allow-stale']);
        expect(res.code, 1, reason: res.diag());
        expect(res.err, allOf(contains('REFUSING'), contains('--allow-unmerged')), reason: res.diag());
      });

      test('on main (merged but not pushed) the same difference is only a warning', () {
        final r = ahead(branch: 'main');
        final res = install(r);
        expect(res.code, 0, reason: res.diag());
        expect(res.out, allOf(contains('WARNING'), contains('scripts/pre-commit.sh')), reason: res.diag());
      });

      test('an UNCOMMITTED edit to a hook source is seen too (the installer copies working-tree bytes)', () {
        final r = fixture();
        for (final h in _hookNames) {
          _git(r, ['add', 'scripts/$h.sh']);
        }
        _git(r, ['commit', '-q', '-m', 'base']);
        _git(r, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
        _git(r, ['checkout', '-q', '-b', 'feature']);
        File('$r/scripts/pre-push.sh').writeAsStringSync(_source('pre-push', 'DIRTY'));
        final res = install(r);
        expect(res.code, 1, reason: res.diag());
        expect(res.err, contains('scripts/pre-push.sh'), reason: res.diag());
      });

      test('identical hook sources on a feature branch install silently', () {
        final r = fixture();
        for (final h in _hookNames) {
          _git(r, ['add', 'scripts/$h.sh']);
        }
        _git(r, ['commit', '-q', '-m', 'base']);
        _git(r, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
        _git(r, ['checkout', '-q', '-b', 'feature']);
        final res = install(r);
        expect(res.code, 0, reason: res.diag());
        expect(res.err, isEmpty, reason: res.diag());
      });
    });

    test('a linked worktree gets a note (the hooks are shared), a primary does not', () {
      final r = fixture();
      twoCommits(r);
      expect(install(r).all, isNot(contains('linked worktree')));
      final wt = '$r-wt';
      _git(r, ['worktree', 'add', '-q', '-b', 'wtb', wt]);
      addTearDown(() {
        try {
          Directory(wt).deleteSync(recursive: true);
        } catch (_) {}
      });
      Directory('$wt/scripts').createSync(recursive: true);
      for (final f in ['setup-hooks.sh', ..._hookNames.map((h) => '$h.sh')]) {
        File('$r/scripts/$f').copySync('$wt/scripts/$f');
      }
      final res = install(wt);
      expect(res.code, 0, reason: res.diag());
      expect(res.out, contains('linked worktree'), reason: res.diag());
    });
  });

  test('16: a failing README write is a warning, not a failed hook, and leaves no temp', () {
    final r = fixture();
    final stubDir = stub(r, 'mv', 'for a; do last="\$a"; done\ncase "\$last" in\n  *AVYA-HOOKS-README.txt) exit 1 ;;\nesac\nexec $realMv "\$@"');
    final res = install(r, stubDir: stubDir);
    expect(res.code, 0, reason: res.diag());
    expect(res.all, contains('could not write AVYA-HOOKS-README.txt'), reason: res.diag());
    for (final h in _hookNames) {
      expect(File('${hooksOf(r)}/$h').existsSync(), isTrue);
    }
    expect(_tmpFiles(hooksOf(r)), isEmpty, reason: 'the README temp has no explicit rm: only the EXIT trap removes it');
  });

  test('17: the README carries the recipe markers and no dollar sign', () {
    final r = fixture();
    expect(install(r).code, 0);
    final readme = File('${hooksOf(r)}/AVYA-HOOKS-README.txt');
    expect(readme.existsSync(), isTrue);
    final text = readme.readAsStringSync();
    for (final marker in ['ff-only', 'Permission denied', '*.tmp.*', 'primary']) {
      expect(text, contains(marker));
    }
    expect(text, isNot(contains('\$')), reason: 'the env scanner reads every dollar-name in the installer');
  });

  test('18: a stale .git/config.lock is a recorded TRANSIENT failure, not an abort before the summary', () {
    final r = fixture();
    File('$r/.git/config.lock').writeAsStringSync('');
    final res = install(r);
    expect(res.code, 1, reason: res.diag());
    expect(res.err, contains('core.sshCommand'), reason: res.diag());
    expect(res.err, contains('retry when no commit is running'), reason: 'a lock is transient\n${res.diag()}');
    expect(res.err, isNot(contains('fix the tree')), reason: 'no persistent failure in this run');
    expect(File('${hooksOf(r)}/AVYA-HOOKS-README.txt').existsSync(), isTrue,
        reason: 'the README is written before the failure list, so an aborted run would have skipped it');
  });

  test('19: a failing chmod +x installs NOTHING and says why; a failing chmod a-w only warns', () {
    final r = fixture();
    final res = install(r, stubDir: stub(r, 'chmod', 'exit 1'));
    expect(res.code, 1, reason: res.diag());
    for (final h in _hookNames) {
      expect(res.err, contains(h));
      expect(File('${hooksOf(r)}/$h').existsSync(), isFalse, reason: 'a non-executable hook is silently skipped by git');
    }
    expect(res.err, contains('executable'));
    expect(res.err, contains('fix the tree'), reason: 'retrying a chmod failure cannot help');
    expect(res.err, isNot(contains('retry when no commit is running')), reason: res.diag());
    expect(_tmpFiles(hooksOf(r)), isEmpty);

    // A filesystem where chmod fails but the file is ALREADY executable (sources written 0755) is accepted.
    final x = fixture();
    for (final h in _hookNames) {
      runSpawn('chmod', ['+x', '$x/scripts/$h.sh'], why: 'make the source executable');
    }
    final accepted = install(x, stubDir: stub(x, 'chmod', 'exit 1'));
    expect(accepted.code, 0, reason: accepted.diag());

    final w = fixture();
    final warn = install(w,
        stubDir: stub(w, 'chmod', 'case "\$*" in\n  *a-w*) exit 1 ;;\nesac\nexec /bin/chmod "\$@"'));
    expect(warn.code, 0, reason: warn.diag());
    expect(warn.err, contains('could not make'), reason: warn.diag());
    for (final h in _hookNames) {
      expect(File('${hooksOf(w)}/$h').existsSync(), isTrue);
    }
  });

  test('20: mode is set on the TEMP before the rename, the temp sits beside the hook, mv gets -f', () {
    final r = fixture();
    final log = '$r/mvlog.txt';
    final stubDir = stub(
        r,
        'mv',
        'src=""; dst=""\n'
            'for a; do src="\$dst"; dst="\$a"; done\n'
            'mode=BAD; if [ -x "\$src" ] && [ ! -w "\$src" ]; then mode=OK; fi\n'
            'dir=BAD; if [ "\$(dirname "\$src")" = "\$(dirname "\$dst")" ]; then dir=OK; fi\n'
            'f=BAD; if [ "\$1" = "-f" ]; then f=OK; fi\n'
            'echo "\$(basename "\$dst") mode=\$mode dir=\$dir f=\$f" >> $log\n'
            'exec $realMv "\$@"');
    final res = install(r, stubDir: stubDir);
    expect(res.code, 0, reason: res.diag());
    final lines = File(log).readAsLinesSync();
    for (final h in _hookNames) {
      expect(lines, contains('$h mode=OK dir=OK f=OK'),
          reason: '$h: a chmod AFTER the rename leaves the live hook briefly non-executable; a temp outside the '
              'hooks dir makes mv a copy+delete; mv without -f can prompt on a tty\n${lines.join('\n')}');
    }
  });

  test('21: a Git-Bash-like mv that refuses a read-only target still reinstalls (the u+w retry)', () {
    final r = fixture();
    expect(install(r).code, 0);
    setSources(r, 'v2');
    final stubDir = stub(
        r,
        'mv',
        'for a; do dst="\$a"; done\n'
            'if [ -e "\$dst" ] && [ ! -w "\$dst" ]; then echo "mv: cannot overwrite read-only" >&2; exit 1; fi\n'
            'exec $realMv "\$@"');
    final res = install(r, stubDir: stubDir);
    expect(res.code, 0, reason: res.diag());
    for (final h in _hookNames) {
      final p = '${hooksOf(r)}/$h';
      expect(_same('$r/scripts/$h.sh', p), isTrue, reason: '$h must carry the NEW source');
      expect(_mode(p) & _wBits, 0, reason: '$h must end read-only again');
    }
  });

  test('22: a cmp that cannot run is a persistent "cannot compare", not a "differs"', () {
    final r = fixture();
    final res = install(r, stubDir: stub(r, 'cmp', 'exit 127'));
    expect(res.code, 1, reason: res.diag());
    expect(res.err, allOf(contains('could not compare'), contains('is cmp installed?'), contains('fix the tree')),
        reason: res.diag());
    expect(res.err, isNot(contains('retry when no commit is running')),
        reason: 'retrying will not help when cmp is missing');
  });
}
