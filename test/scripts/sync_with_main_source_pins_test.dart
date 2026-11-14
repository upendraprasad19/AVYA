// test/scripts/sync_with_main_source_pins_test.dart
//
// Source-grep pins for the guards of scripts/sync_with_main.dart, scripts/sync_with_main.sh and
// scripts/sync_resolver_lib.dart that no end-to-end scenario can observe from outside (docs/plans/sync-resolver.md
// section 5). Source-grep tests prove PRESENCE only (CLAUDE.md rule 21); the behaviour behind each pin is covered by
// the e2e files, and each pin is mutated in the plan's mutation table.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String path) => File(path).readAsStringSync();

/// The code lines of [text]: comment-only lines dropped, so prose that mentions a command cannot satisfy or break a pin.
String _code(String text) => text.split('\n').where((l) => !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('#')).join('\n');

void main() {
  final cli = _code(_src('scripts/sync_with_main.dart'));
  final lib = _code(_src('scripts/sync_resolver_lib.dart'));
  final sh = _code(_src('scripts/sync_with_main.sh'));
  final helper = _code(_src('scripts/_dart_bin.sh'));

  group('the CLI', () {
    test('catches an asynchronous leak in a guarded zone and funnels every exit through one latch', () {
      expect(cli, contains('runZonedGuarded('));
      expect(RegExp(r'if \(_finished\) return;\s*_finished = true;').hasMatch(cli), isTrue);
      expect(RegExp(r'\bexit\(').allMatches(cli).length, 1, reason: 'exit() is called in exactly one place, _finish');
      expect(RegExp(r"stdout\.writeln\('result: ").allMatches(cli).length, 1, reason: 'the result line is printed in exactly one place');
    });

    test('never aborts, resets, cleans, stashes, checks out or rebases (the undo is named, never run)', () {
      for (final verb in ['abort', 'reset', 'clean', 'stash', 'checkout', 'rebase', 'restore']) {
        expect(cli, isNot(contains("'$verb'")), reason: '`$verb` as an argv element');
      }
      expect(cli, isNot(contains("'--abort'")));
      expect(cli, isNot(contains('--hard\'')));
    });

    test('reads no environment variable', () {
      expect(cli, isNot(contains('Platform.environment')));
      expect(cli, isNot(contains('includeParentEnvironment')));
    });

    test('merges the SHA it resolved once, with --no-ff, and never an octopus or a ref name', () {
      expect(cli, contains("'--no-ff'"));
      expect(cli, contains('tip,\n      ]'));
      expect(cli, contains("'refs/remotes/origin/main^{commit}'"));
      expect(RegExp(r"'rev-parse',\s*'--verify',\s*'--quiet',\s*'refs/remotes/origin/main\^\{commit\}'").allMatches(cli).length, 1, reason: 'the tip is resolved in exactly one place');
    });

    test('fetches through Process.start with a kill on timeout, a closed stdin and no prompt', () {
      expect(cli, contains("Process.start(\n        'git',"));
      expect(cli, contains('ProcessSignal.sigkill'));
      expect(cli, contains("'GIT_TERMINAL_PROMPT': '0'"));
      expect(cli, contains('p.stdin.close()'));
      expect(cli, contains("'--no-tags'"));
    });

    test('writes through a temp file and a rename, never directly into the target', () {
      expect(cli, contains('tmp.renameSync(path)'));
      // the temp lives under the state directory (inside the git dir, same filesystem, never in the work tree); no scenario can
      // observe where a CRASH would leave it, so this is a presence pin
      expect(cli, contains("final tmp = File('\$stateDir/tmp/\${path.replaceAll('/', '_')}.\$pid');"));
      expect(cli, isNot(contains('File(path).writeAs')));
      expect(cli, isNot(contains('file.writeAs(')));
    });

    test('takes a backup before every overwrite and treats a failed backup as no overwrite', () {
      expect(RegExp(r'if \(!_backup\(path, cur\)\) return').hasMatch(cli), isTrue);
      expect(RegExp(r'if \(!_writeAtomic\(path, outBytes\)\) return').hasMatch(cli), isTrue);
    });

    test('uses the protected-branch rule of retire_worktree_lib and the marker rule of no_conflict_markers_lib', () {
      expect(cli, contains("import 'retire_worktree_lib.dart';"));
      expect(cli, contains("import 'no_conflict_markers_lib.dart';"));
      expect(cli, contains('protectedBranchReason(branch)'));
    });

    test('has no canonical gate header line (build_gate_index.dart hard-fails on one)', () {
      expect(_src('scripts/sync_with_main.dart'), isNot(matches(RegExp(r'^// Gate: \d+', multiLine: true))));
      expect(_src('scripts/sync_resolver_lib.dart'), isNot(matches(RegExp(r'^// Gate: \d+', multiLine: true))));
    });
  });

  group('the library', () {
    test('imports only dart:convert (no File: check_gate_existssync_file_vs_dir.dart guards *_lib.dart)', () {
      final imports = RegExp(r"^import '([^']+)';", multiLine: true).allMatches(lib).map((m) => m.group(1)).toList();
      expect(imports, ['dart:convert']);
      expect(RegExp(r'\bFile\(').hasMatch(lib), isFalse);
      expect(RegExp(r'\bProcess\.').hasMatch(lib), isFalse);
    });
  });

  group('the wrapper', () {
    test('forwards TERM to its child, waits again after a trapped signal and clamps a status above 4', () {
      expect(sh, contains('run_dart_cli "\$DART_BIN" "\$here/sync_with_main.dart" "\$@"'));
      expect(sh, isNot(contains('trap ')), reason: 'one signal block, in run_dart_cli (OI-483)');
      expect(helper, contains('trap _dart_cli_on_signal TERM INT HUP'));
      expect(helper, contains('kill -TERM "\$_dart_cli_child"'));
      expect(helper, contains('while kill -0 "\$_dart_cli_child"'));
      expect(sh, contains('if [ "\$rc" -gt 4 ]; then'));
      expect(sh, contains('echo "result: error"'));
      expect(sh, contains('echo "result: refused"'));
    });

    test('normalises backslashes in its own path before locating the .dart next to it (a Windows-form path)', () {
      expect(sh, contains("tr '\\\\' '/'"));
    });

    test('does not use set -e (the wait status must reach the clamp)', () {
      expect(sh, isNot(contains('set -e')));
      expect(sh, isNot(contains('set -eu')));
    });
  });
}
