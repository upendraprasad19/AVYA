// test/scripts/discipline_hook_local_indexes_e2e_test.dart
//
// Executes the REAL scripts/discipline_hook.dart (a Claude Code hook) in a throwaway git repo to
// pin the two A2 additions (merge-conflict-treadmill, plan section 6):
//
//   1. the LOCAL-INDEXES NUDGE: docs/audit/OPEN_INDEX.md and docs/diagnoses/INDEX.md are
//      gitignored build products, so a fresh worktree has neither. At SessionStart, and on a
//      bug-shaped prompt, the hook adds ONE context line when either is stale or missing. It reads
//      stat() of each input and the first 256 bytes of each output: no spawn, no document body,
//      and (decision D7) NO rebuild: builds are automatic in git hooks and CI only;
//   2. the HOOKS-NOT-REINSTALLED WARNING: hooks are COPIES, shared by every worktree. A tree that
//      has the A2 builder but an installed `pre-commit` or `pre-merge-commit` without the A2-only
//      literal `build_local_indexes.dart` gets one SessionStart warning with the reinstall command.
//
// Each case names the mutant it kills (rule 21):
//   fresh -> silent; stale -> ONE line; missing -> ONE line   [the nudge always / never fires]
//   a tree without the builder -> silent                      [the existence guard dropped]
//   an unwritable docs/diagnoses/ -> the OTHER parts still    [the nudge's own try/catch dropped]
//   a bug prompt + stale -> ONE JSON document, both parts     [two `_emit` calls]
//   a non-bug prompt -> nothing; a bug prompt + fresh -> hot-set only
//   the hooks warning: A0-only hooks warn, the REAL A2 hooks do not, one stale hook is named alone,
//   a missing hook counts as stale, SessionStart only, silent without the builder
//                                                             [keyed on A0's guard line instead of the
//                                                              A2 literal; both hooks not checked]
//   the hooks warning from a LINKED worktree (`.git` is a FILE), as every session runs: current hooks
//   in the shared hooks directory do not warn, A0-only ones do   [the hooks directory taken as
//                                                                  `<cwd>/.git/hooks`: it does not exist there,
//                                                                  so every session warned forever]
//   an unreadable installed hook file -> the OTHER SessionStart parts still print
//                                                             [the warning's own try/catch dropped]
//   STRUCTURE: the nudge function spawns nothing and reads no document body
//   the REAL settings.json SessionStart command, run from a SUBDIRECTORY, still nudges

@Timeout(Duration(minutes: 8))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/build_local_indexes.dart' show runLocalIndexes;
import '../../scripts/discipline_hook.dart' show formatHooksNotReinstalledWarning, formatLocalIndexesNudge, localIndexesNudge;
import '../../scripts/local_indexes_lib.dart';
import '../helpers/dart_source_slice.dart';
import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart';

const _nudge = 'Local indexes stale/missing — run: dart run scripts/build_local_indexes.dart --lenient';
const _hooksWarn = 'GIT HOOKS: the installed';
const _startup = '{"hook_event_name":"SessionStart","source":"startup"}';
const _bugPrompt = '{"hook_event_name":"UserPromptSubmit","prompt":"the coach reply is wrong after the sync"}';
const _plainPrompt = '{"hook_event_name":"UserPromptSubmit","prompt":"hello there, what is the plan today"}';

enum _Hooks { a2, a0Only, none, onlyPreCommitA2 }

void main() {
  late String repoRoot;
  late Directory tmp;
  var n = 0;

  setUpAll(() {
    repoRoot = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('hook_idx_');
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  ProcessResult gitRun(String exe, List<String> args, String cwd) => runSpawn(exe, args,
      why: 'discipline_hook_local_indexes_e2e fixture: $exe ${args.join(' ')}',
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8);

  /// A git repo holding the real hook script and (unless [builder] is false) the A2 orchestrator
  /// with everything they import. [built] runs the strict build; [hooks] installs hook copies:
  /// the REAL A2 sources, hooks that carry only A0's guard line, none, or just pre-commit.
  String fixture({bool builder = true, bool built = true, _Hooks hooks = _Hooks.a2}) {
    final w = '${tmp.path}/w${n++}';
    Directory(w).createSync(recursive: true);
    gitRun('git', ['init', '-q', '-b', 'main', '.'], w);
    copyScriptClosure(repoRoot, w, [
      'scripts/discipline_hook.dart',
      if (builder) 'scripts/build_local_indexes.dart',
    ]);
    Directory('$w/docs/audit').createSync(recursive: true);
    Directory('$w/docs/diagnoses').createSync(recursive: true);
    File('$w/docs/audit/open_issues.md').writeAsStringSync(
        '# Open issues\n\n## OI-1 — one\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n\n');
    File('$w/docs/diagnoses/2026-10-01-seed-aaaaaa.md')
        .writeAsStringSync('---\nbug_id: aaaaaa\ndate: 2026-10-01\nsymptom: it broke\n---\n# aaaaaa\n');
    if (builder && built) {
      expect(runLocalIndexes(w), 0, reason: 'fixture: the strict build must pass');
    }
    final dir = Directory('$w/.git/hooks')..createSync(recursive: true);
    switch (hooks) {
      case _Hooks.a2:
        for (final h in const ['pre-commit', 'pre-merge-commit']) {
          File('$repoRoot/scripts/$h.sh').copySync('${dir.path}/$h');
        }
      case _Hooks.a0Only:
        // What an A0 install carries: the tracked-only guard line, never the A2 literal.
        for (final h in const ['pre-commit', 'pre-merge-commit']) {
          File('${dir.path}/$h').writeAsStringSync(
              '#!/bin/sh\nif git ls-files --error-unmatch -- docs/diagnoses/INDEX.md >/dev/null 2>&1; then\n'
              '  git add -u -- docs/diagnoses/INDEX.md\nfi\n');
        }
      case _Hooks.onlyPreCommitA2:
        File('$repoRoot/scripts/pre-commit.sh').copySync('${dir.path}/pre-commit');
      case _Hooks.none:
        break;
    }
    return w;
  }

  /// stdout of the hook, run from [cwd] (default: the fixture root). The sync-warning kill switch
  /// keeps the run offline and fast; nothing under test reads it.
  Future<String> run(String w, String stdinJson, {String? cwd}) async {
    final r = await runSpawnWithInput(dartBin(), ['run', '$w/scripts/discipline_hook.dart'],
        why: 'discipline_hook in $w',
        stdin: stdinJson,
        workingDirectory: cwd ?? w,
        extraEnv: const {'DISCIPLINE_HOOK_SYNC_SKIP': '1'},
        allowControl: const {'DISCIPLINE_HOOK_SYNC_SKIP'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(r.exitCode, 0, reason: 'the hook must never fail a session\n${r.stdout}\n${r.stderr}');
    return r.stdout;
  }

  /// Every `additionalContext` the hook printed (one per JSON line).
  List<String> contexts(String out) => [
        for (final l in const LineSplitter().convert(out).where((l) => l.trim().isNotEmpty))
          ((jsonDecode(l) as Map)['hookSpecificOutput'] as Map)['additionalContext'] as String,
      ];

  int count(String hay, String needle) => needle.allMatches(hay).length;

  void bump(String w, String rel) {
    final f = File('$w/$rel');
    f.setLastModifiedSync(f.lastModifiedSync().add(const Duration(hours: 1)));
  }

  group('the nudge', () {
    test('fresh indexes -> no nudge', () async {
      final w = fixture();
      expect(await run(w, _startup), isNot(contains('Local indexes')));
    });

    test('a STALE index -> exactly ONE nudge line, with the lenient command', () async {
      final w = fixture();
      bump(w, 'docs/audit/open_issues.md');
      final ctx = contexts(await run(w, _startup));
      expect(ctx, hasLength(1), reason: 'one JSON document per event');
      expect(count(ctx.single, _nudge), 1, reason: ctx.single);
      expect(ctx.single, contains('docs/audit/OPEN_INDEX.md / docs/diagnoses/INDEX.md'));
    });

    test('a MISSING index -> the same ONE line (a fresh worktree)', () async {
      final w = fixture(built: false);
      final ctx = contexts(await run(w, _startup));
      expect(count(ctx.join('\n'), _nudge), 1, reason: ctx.join('\n'));
    });

    test('BOTH stale or missing still yields ONE line, not one per index', () async {
      final w = fixture(built: false);
      bump(w, 'docs/audit/open_issues.md');
      expect(count(contexts(await run(w, _startup)).join('\n'), _nudge), 1);
    });

    test('a tree WITHOUT the A2 builder (a pre-A2 checkout, a test fixture) -> silent', () async {
      // STALE hooks on purpose: with the real A2 hooks installed no warning could appear anyway,
      // and dropping the builder-exists guard would be invisible (the mutant survived that way).
      final w = fixture(builder: false, built: false, hooks: _Hooks.a0Only);
      final out = await run(w, _startup);
      expect(out, isNot(contains('Local indexes')));
      expect(out, isNot(contains(_hooksWarn)), reason: 'and no hooks warning either');
    });

    test('an unreadable docs/diagnoses/ never takes the OTHER SessionStart parts down with it', () async {
      final w = fixture();
      bump(w, 'docs/audit/open_issues.md');
      // Mode 111, NOT 000: the index file inside must stay readable (so the staleness path goes on
      // to list the directory), while listing it throws. With 000 the output reads as missing
      // before anything is listed and nothing throws (the nudge-own-catch mutant survived that way).
      gitRun('chmod', ['111', '$w/docs/diagnoses'], w);
      try {
        expect(() => localIndexReports(w), throwsA(isA<FileSystemException>()),
            reason: 'precondition: the staleness path really throws in this state');
        // The primary-worktree warning is another self-guarded part of the SAME document.
        final out = await run(w, _startup);
        expect(out, contains('WORKTREE'),
            reason: 'a nudge that throws and is not caught inside itself empties the whole SessionStart');
      } finally {
        gitRun('chmod', ['755', '$w/docs/diagnoses'], w);
      }
    }, skip: Platform.isWindows || gitRun('id', ['-u'], '.').stdout.toString().trim() == '0'
        ? 'needs POSIX permissions and a non-root user'
        : false);

    test('a bug-shaped prompt + a stale index -> ONE JSON document holding the hot-set AND the nudge', () async {
      final w = fixture();
      bump(w, 'docs/audit/open_issues.md');
      final out = await run(w, _bugPrompt);
      final ctx = contexts(out);
      expect(ctx, hasLength(1), reason: 'two `_emit` calls would print two JSON lines\n$out');
      expect(ctx.single, contains('DISCIPLINE HOT-SET'));
      expect(ctx.single, contains('build it first if absent'));
      expect(count(ctx.single, _nudge), 1);
    });

    test('a bug-shaped prompt + fresh indexes -> the hot-set only', () async {
      final w = fixture();
      final ctx = contexts(await run(w, _bugPrompt));
      expect(ctx, hasLength(1));
      expect(ctx.single, contains('DISCIPLINE HOT-SET'));
      expect(ctx.single, isNot(contains('Local indexes')));
    });

    test('a NON-bug prompt -> nothing at all, even with a stale index', () async {
      final w = fixture(built: false);
      expect((await run(w, _plainPrompt)).trim(), isEmpty);
    });

    test('the hooks warning is SessionStart only: a bug prompt never carries it', () async {
      final w = fixture(hooks: _Hooks.a0Only);
      expect(await run(w, _bugPrompt), isNot(contains(_hooksWarn)));
    });
  });

  group('the hooks-not-reinstalled warning', () {
    test('hooks that carry only A0\'s guard line WARN, naming both hooks and the reinstall command', () async {
      final w = fixture(hooks: _Hooks.a0Only);
      final text = contexts(await run(w, _startup)).join('\n');
      expect(text, contains('$_hooksWarn pre-commit and pre-merge-commit hook(s) predate'));
      expect(text, contains('git fetch origin main && git merge --ff-only origin/main && sh scripts/setup-hooks.sh'));
      // The consequences it names are the ones the old hook really has (pre_commit_index_add_e2e_test
      // 9k: it blocks on a failed index write; pre_merge_commit_e2e_test: it prints the `git add`
      // advice for an index that is now ignored).
      expect(text, contains('stop on a failed index write'));
      expect(text, contains('to `git add` an index that is now ignored'));
    });

    test('the REAL A2 hook sources do not warn (they carry the A2-only literal)', () async {
      final w = fixture(hooks: _Hooks.a2);
      expect(await run(w, _startup), isNot(contains(_hooksWarn)));
    });

    test('ONE stale hook is named alone', () async {
      final w = fixture(hooks: _Hooks.onlyPreCommitA2);
      final text = contexts(await run(w, _startup)).join('\n');
      expect(text, contains('$_hooksWarn pre-merge-commit hook(s) predate'));
      expect(text, isNot(contains('pre-commit and')));
    });

    test('NO installed hooks counts as stale', () async {
      final w = fixture(hooks: _Hooks.none);
      expect(contexts(await run(w, _startup)).join('\n'), contains('$_hooksWarn pre-commit and pre-merge-commit'));
    });

    // Every session runs in a LINKED worktree (CLAUDE.md 4.13), where `.git` is a one-line FILE
    // and the hooks live in the PRIMARY's git directory. The fixture above can only be a plain
    // repo, where `<cwd>/.git/hooks` happens to be right.
    String linkedWorktreeOf(String primary) {
      File('$primary/.gitignore')
          .writeAsStringSync('docs/audit/OPEN_INDEX.md\ndocs/diagnoses/INDEX.md\n.dart_tool/\n');
      for (final a in const [
        ['config', 'user.email', 't@t.t'],
        ['config', 'user.name', 't'],
        ['config', 'commit.gpgsign', 'false'],
        ['add', '-A'],
        ['commit', '-q', '-m', 'seed'],
      ]) {
        final r = gitRun('git', a, primary);
        expect(r.exitCode, 0, reason: 'git ${a.join(' ')}: ${r.stdout}${r.stderr}');
      }
      final linked = '${tmp.path}/linked${n++}';
      final add = gitRun('git', ['worktree', 'add', '-q', '-b', 'wt${n++}', linked], primary);
      expect(add.exitCode, 0, reason: '${add.stdout}${add.stderr}');
      expect(FileSystemEntity.isFileSync('$linked/.git'), isTrue,
          reason: 'precondition: `.git` is a FILE in a linked worktree');
      expect(runLocalIndexes(linked), 0, reason: 'fixture: the linked worktree needs its own build');
      return linked;
    }

    test('from a LINKED worktree the shared hooks are found: the REAL A2 hooks do not warn  [`<cwd>/.git/hooks`]', () async {
      final linked = linkedWorktreeOf(fixture(hooks: _Hooks.a2));
      expect(await run(linked, _startup), isNot(contains(_hooksWarn)),
          reason: 'the hooks sit in the primary\'s git directory; looking in `<cwd>/.git/hooks` finds '
              'nothing, counts both as absent and warns on EVERY session of a correctly installed machine');
    });

    test('from a LINKED worktree the shared hooks are READ: A0-only hooks do warn', () async {
      final linked = linkedWorktreeOf(fixture(hooks: _Hooks.a0Only));
      final text = contexts(await run(linked, _startup)).join('\n');
      expect(text, contains('$_hooksWarn pre-commit and pre-merge-commit hook(s) predate'));
    });

    test('an unreadable hook file never takes the OTHER SessionStart parts down with it', () async {
      final w = fixture(hooks: _Hooks.a2);
      gitRun('chmod', ['000', '$w/.git/hooks/pre-commit'], w);
      try {
        expect(() => File('$w/.git/hooks/pre-commit').readAsBytesSync(), throwsA(isA<FileSystemException>()),
            reason: 'precondition: reading the hook really throws in this state');
        final out = await run(w, _startup);
        expect(out, contains('WORKTREE'),
            reason: 'the warning is one part among several built before the single JSON document is '
                'emitted; one that throws and is not caught inside itself empties the whole SessionStart');
      } finally {
        gitRun('chmod', ['644', '$w/.git/hooks/pre-commit'], w);
      }
    }, skip: Platform.isWindows || gitRun('id', ['-u'], '.').stdout.toString().trim() == '0'
        ? 'needs POSIX permissions and a non-root user'
        : false);

    test('the pure formatter: each hook is judged on its own, `null` (absent) is stale', () {
      expect(formatHooksNotReinstalledWarning(preCommit: 'x build_local_indexes.dart y', preMergeCommit: 'build_local_indexes.dart'), '');
      expect(formatHooksNotReinstalledWarning(preCommit: 'build_local_indexes.dart', preMergeCommit: null), contains('pre-merge-commit'));
      expect(formatHooksNotReinstalledWarning(preCommit: null, preMergeCommit: 'build_local_indexes.dart'), isNot(contains('pre-merge-commit')));
      expect(formatHooksNotReinstalledWarning(preCommit: 'git ls-files --error-unmatch', preMergeCommit: 'git check-ignore'), contains('pre-commit and pre-merge-commit'),
          reason: 'A0\'s guard line and check-ignore are NOT the marker');
    });
  });

  group('structure', () {
    test('the nudge reads stat() and 256 bytes of each output: one stat per input, nothing else', () {
      final w = fixture();
      final stats = <String>[];
      final heads = <int>[];
      final line = localIndexesNudge(
          root: w,
          stat: (p) {
            stats.add(p);
            return FileStat.statSync(p);
          },
          readHead: (p, max) {
            heads.add(max);
            return readHeadBytes(p, max);
          });
      expect(line, '', reason: 'fresh');
      final inputs = [...indexInputPaths(w, kOiIndexSpec), ...indexInputPaths(w, kBugIndexSpec)];
      // One stat per (index, input) pair: the shared lib is an input of BOTH indexes, so it is
      // stat'd twice and nothing else is stat'd at all.
      expect(stats.toList()..sort(), inputs.map((p) => '$w/$p').toList()..sort(),
          reason: 'stat only the stamp inputs, each once per index');
      expect(heads, [kStampHeadBytes, kStampHeadBytes]);
    });

    test('formatLocalIndexesNudge: silent only when EVERY report is fresh', () {
      const oi = IndexReport(kOiIndexSpec, IndexState.fresh);
      expect(formatLocalIndexesNudge([oi, const IndexReport(kBugIndexSpec, IndexState.fresh)]), '');
      expect(formatLocalIndexesNudge([oi, const IndexReport(kBugIndexSpec, IndexState.stale)]), contains(_nudge));
      expect(formatLocalIndexesNudge([oi, const IndexReport(kBugIndexSpec, IndexState.missing)]), contains(_nudge));
    });

    test('STRUCTURE: localIndexesNudge spawns nothing and reads no document body', () {
      final src = stripDartComments(File('scripts/discipline_hook.dart').readAsStringSync());
      final body = functionBody(src, 'String localIndexesNudge(');
      for (final banned in const [
        'Process.',
        'readAsStringSync',
        'readAsBytesSync',
        'readAsLinesSync',
        'readAsString(',
        'openRead(',
      ]) {
        expect(body, isNot(contains(banned)),
            reason: 'the nudge runs on every SessionStart and bug-shaped prompt: stat-only, no spawn ($banned)');
      }
    });
  });

  test('the REAL settings.json SessionStart command, run from a SUBDIRECTORY of a stale checkout, still nudges', () async {
    final settings = jsonDecode(File('.claude/settings.json').readAsStringSync()) as Map<String, dynamic>;
    final starts = ((settings['hooks'] as Map)['SessionStart'] as List)
        .expand((g) => (g as Map)['hooks'] as List)
        .map((h) => (h as Map)['command'] as String)
        .where((c) => c.contains('scripts/discipline_hook.dart'))
        .toList();
    expect(starts, hasLength(1), reason: 'exactly one SessionStart registration of the discipline hook');
    final w = fixture(built: false);
    Directory('$w/lib/deep').createSync(recursive: true);
    final r = await runSpawnWithInput('sh', ['-c', starts.single],
        why: 'the real SessionStart command from a subdirectory',
        stdin: _startup,
        workingDirectory: '$w/lib/deep',
        extraEnv: const {'DISCIPLINE_HOOK_SYNC_SKIP': '1'},
        allowControl: const {'DISCIPLINE_HOOK_SYNC_SKIP'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(count(contexts(r.stdout).join('\n'), _nudge), 1, reason: '${r.stdout}\n${r.stderr}');
  });
}
