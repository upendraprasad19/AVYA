// scripts/sync_with_main.dart
//
// Sync the CURRENT branch with origin/main and resolve, BY RECORD, the conflicts that are two independent
// appends to a ledger (landing C2 of the merge-conflict-treadmill plan, docs/plans/sync-resolver.md; parent
// docs/plans/merge-conflict-treadmill.md, OI-309). Run it through scripts/sync_with_main.sh.
//
//   sh scripts/sync_with_main.sh            fetch, merge origin/main (no commit), resolve + stage what it can
//   sh scripts/sync_with_main.sh --commit   the same, then conclude the merge (clean: git itself; conflicted:
//                                           scripts/safe_commit.sh, the full pre-commit loop, takes minutes)
//
// EXIT CODES. 0 done (staged and ready, committed, fast-forwarded or already up to date); 1 the merge is in
// progress and paths remain for a human; 2 refused or failed before anything was changed; 3 `--commit` failed
// (the merge is pending and staged); 4 internal error (state unknown, the merge may be pending). The LAST
// stdout line is always `result: <ready|pending|committed|fast-forwarded|up-to-date|refused|commit-failed|error>`.
//
// WHAT IT TOUCHES. Only UNMERGED paths of the allow-list in scripts/sync_resolver_lib.dart (`kResolvableFiles`),
// in this worktree. Nothing is aborted, ever (`git merge --abort` is not run); a path it cannot place is left
// exactly as git wrote it. Before a conflicted file is overwritten its bytes are copied to
// `<git dir>/sync_with_main_backup/<HEAD>-<n>/`; a file a human has resolved or edited is never overwritten.
//
// This file reads NO environment variable; every child inherits the parent's environment, and the fetch adds
// `GIT_TERMINAL_PROMPT=0`. The test-only switches are argv flags the wrapper does not forward (`--no-fetch`,
// `--fetch-timeout-ms=N`).

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart_race_retry_lib.dart';
import 'no_conflict_markers_lib.dart';
import 'retire_worktree_lib.dart';
import 'sync_resolver_lib.dart';

const String kGateIndexPath = 'docs/audit/GATE_INDEX.md';
const int kKeepBackupRuns = 20;
const int kDefaultFetchTimeoutMs = 120000;
const String kUsage = 'usage: sh scripts/sync_with_main.sh [--commit]';

/// Thrown for a refusal (exit 2, nothing changed).
class _Refused implements Exception {
  _Refused(this.message);

  final String message;
}

class _Outcome {
  const _Outcome(this.result, this.code);

  final String result;
  final int code;
}

class _R {
  _R(this.code, this.out, this.err);

  final int code;
  final List<int> out;
  final List<int> err;

  String get text => utf8.decode(out, allowMalformed: true).trim();
  String get errText => utf8.decode(err, allowMalformed: true).trim();
  String get both => [text, errText].where((s) => s.isNotEmpty).join('\n');
}

Future<_R> _git(List<String> args) async {
  try {
    final r = await Process.run('git', args, stdoutEncoding: null, stderrEncoding: null);
    return _R(r.exitCode, r.stdout as List<int>, r.stderr as List<int>);
  } on ProcessException {
    throw _Refused('git could not be started (is it on the PATH?)');
  }
}

_R _gitSync(List<String> args) {
  try {
    final r = Process.runSync('git', args, stdoutEncoding: null, stderrEncoding: null);
    return _R(r.exitCode, r.stdout as List<int>, r.stderr as List<int>);
  } on ProcessException {
    throw _Refused('git could not be started (is it on the PATH?)');
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _Stage {
  _Stage(this.mode, this.sha);

  final String mode;
  final String sha;
}

class _Line {
  _Line(this.status, this.path, this.detail);

  final String status;
  final String path;
  final String detail;
}

bool _finished = false;

/// The ONE exit point: the latch keeps a late error (after the kill of the fetch, an EPIPE) from printing a second result.
Future<void> _finish(String result, int code) async {
  if (_finished) return;
  _finished = true;
  try {
    stdout.writeln('result: $result');
    await stdout.flush();
  } catch (_) {
    // stdout is gone (EPIPE): the exit code still carries the answer.
  }
  exit(code);
}

void main(List<String> args) {
  runZonedGuarded(() async {
    _Outcome o;
    try {
      o = await _parse(args).run();
    } on _Refused catch (e) {
      stdout.writeln('sync_with_main: refused: ${e.message}');
      o = const _Outcome('refused', 2);
    } catch (e, st) {
      stdout.writeln('sync_with_main: internal error: $e');
      stderr.writeln(st);
      o = const _Outcome('error', 4);
    }
    await _finish(o.result, o.code);
  }, (e, st) {
    if (!_finished) {
      try {
        stdout.writeln('sync_with_main: internal error: $e');
        stderr.writeln(st);
      } catch (_) {}
    }
    unawaited(_finish('error', 4));
  });
}

_Sync _parse(List<String> args) {
  var commit = false;
  var fetch = true;
  var timeoutMs = kDefaultFetchTimeoutMs;
  for (final a in args) {
    if (a == '--commit') {
      commit = true;
    } else if (a == '--no-fetch') {
      fetch = false;
    } else if (a.startsWith('--fetch-timeout-ms=')) {
      final v = int.tryParse(a.substring('--fetch-timeout-ms='.length));
      if (v == null || v <= 0) throw _Refused('bad value in $a');
      timeoutMs = v;
    } else {
      throw _Refused('unknown argument "$a" ($kUsage)');
    }
  }
  return _Sync(commit: commit, fetch: fetch, fetchTimeoutMs: timeoutMs);
}

class _Sync {
  _Sync({required this.commit, required this.fetch, required this.fetchTimeoutMs});

  final bool commit;
  final bool fetch;
  final int fetchTimeoutMs;

  late String branch;
  late String tip;
  late String old;
  late String stateDir;
  late String backupRoot;
  late String mergeHeadPath;
  String? backupRun;
  int _seq = 0;
  final List<_Line> lines = [];
  final Set<String> byLine = {};

  String get mergeMessage => "Merge remote-tracking branch 'origin/main' into $branch";

  Future<String> _gitPath(String name) async {
    final r = await _git(['rev-parse', '--path-format=absolute', '--git-path', name]);
    if (r.code != 0 || r.text.isEmpty) throw _Refused('cannot locate the git path "$name": ${r.errText}');
    return r.text;
  }

  Future<_Outcome> run() async {
    // ---- step 1: refusals that need no network ------------------------------------------------------
    final top = await _git(['rev-parse', '--show-toplevel']);
    if (top.code != 0 || top.text.isEmpty) throw _Refused('not inside a git work tree');
    Directory.current = top.text;
    final head0 = await _git(['rev-parse', '--verify', '--quiet', 'HEAD^{commit}']);
    if (head0.code != 0) throw _Refused('HEAD is not a commit');
    old = head0.text;
    final br = await _git(['symbolic-ref', '--quiet', '--short', 'HEAD']);
    if (br.code != 0 || br.text.isEmpty) throw _Refused('HEAD is detached; check out a branch first');
    branch = br.text;
    final prot = protectedBranchReason(branch);
    if (prot != null) {
      throw _Refused('branch "$branch" is a $prot; the sync belongs on a feature branch');
    }
    final shallow = await _git(['rev-parse', '--is-shallow-repository']);
    if (shallow.text == 'true') throw _Refused('the repository is shallow (git fetch --unshallow first)');
    for (final n in const ['rebase-merge', 'rebase-apply', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'BISECT_LOG', 'sequencer']) {
      final p = await _gitPath(n);
      if (FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound) {
        throw _Refused('a rebase, am, cherry-pick, revert or bisect is in progress ($n exists); finish or abort it first');
      }
    }
    mergeHeadPath = await _gitPath('MERGE_HEAD');
    stateDir = await _gitPath('sync_with_main');
    backupRoot = await _gitPath('sync_with_main_backup');
    String? pendingHead;
    if (File(mergeHeadPath).existsSync()) {
      final heads = File(mergeHeadPath).readAsLinesSync().map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (heads.length != 1) throw _Refused('a merge with ${heads.length} parents is pending (octopus); conclude or abort it by hand');
      pendingHead = heads.single;
    }
    final unmerged0 = await _unmerged();
    if (pendingHead == null) {
      if (unmerged0.isNotEmpty) {
        throw _Refused('${unmerged0.length} unmerged path(s) but no merge in progress; resolve them or reset the index first');
      }
      final st = await _git(['status', '--porcelain=v1', '--untracked-files=no']);
      if (st.code != 0) throw _Refused('git status failed: ${st.errText}');
      if (st.text.isNotEmpty) {
        throw _Refused('tracked files are modified or staged and no merge is pending; commit or set that work aside first');
      }
    } else if (commit) {
      throw _Refused('a merge is already pending; `--commit` only concludes a merge this tool starts. '
          'Conclude it with: sh scripts/safe_commit.sh "$mergeMessage"');
    }

    // ---- the fetch, then the tip is resolved ONCE ---------------------------------------------------
    if (fetch) await _fetch();
    final t = await _git(['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/main^{commit}']);
    if (t.code != 0 || t.text.isEmpty) throw _Refused('refs/remotes/origin/main is missing or not a commit');
    tip = t.text;
    if (pendingHead != null) {
      final anc = await _git(['merge-base', '--is-ancestor', pendingHead, tip]);
      if (anc.code == 1) throw _Refused('the pending merge is not of origin/main (MERGE_HEAD is not an ancestor of $tip)');
      if (anc.code != 0) throw _Refused('could not compare MERGE_HEAD with origin/main: ${anc.errText}');
    }

    // ---- step 2: up to date / fast-forward ------------------------------------------------------------
    if (pendingHead == null) {
      final has = await _git(['merge-base', '--is-ancestor', tip, 'HEAD']);
      if (has.code == 0) {
        stdout.writeln('up to date: $branch already contains origin/main (${_short(tip)})');
        return const _Outcome('up-to-date', 0);
      }
      if (has.code != 1) throw _Refused('merge-base failed: ${has.errText}');
      final ff = await _git(['merge-base', '--is-ancestor', 'HEAD', tip]);
      if (ff.code == 0) {
        stdout.writeln('the branch has no commit of its own: fast-forwarding from ${_short(old)}');
        final m = await _git(['merge', '--ff-only', tip]);
        if (m.code != 0) throw _Refused('git merge --ff-only failed:\n${m.both}');
        final now = await _git(['rev-parse', 'HEAD']);
        stdout.writeln('fast-forwarded: ${_short(old)} -> ${_short(now.text)} (old HEAD $old)');
        return const _Outcome('fast-forwarded', 0);
      }
      if (ff.code != 1) throw _Refused('merge-base failed: ${ff.errText}');
    }

    // ---- step 3: start the merge ----------------------------------------------------------------------
    if (pendingHead == null) {
      _clearState();
      final m = await _git([
        'merge',
        '--no-ff',
        '-m',
        mergeMessage,
        commit ? '--no-edit' : '--no-commit',
        tip,
      ]);
      if (m.both.isNotEmpty) stdout.writeln(m.both);
      final mergeHead = File(mergeHeadPath).existsSync();
      final unmerged = await _unmerged();
      if (mergeHead && unmerged.isEmpty) {
        // clean --no-commit, rerere resolved everything, or a failed pre-merge-commit hook: step 6.
      } else if (!mergeHead) {
        final parents = await _git(['rev-list', '--parents', '-n', '1', 'HEAD']);
        final ps = parents.text.split(' ');
        if (ps.length == 3 && ps[1] == old && ps[2] == tip) {
          stdout.writeln('git concluded the merge: ${_short(ps[0])}');
          return const _Outcome('committed', 0);
        }
        final st = await _git(['status', '--porcelain=v1', '--untracked-files=no']);
        final cached = await _git(['diff', '--cached', '--quiet']);
        final headNow = await _git(['rev-parse', 'HEAD']);
        if (headNow.text == old && st.text.isEmpty && cached.code == 0) {
          throw _Refused('git did not start the merge (exit ${m.code}); nothing was changed');
        }
        stdout.writeln('git stopped in an unexpected state; to undo to where this run began: git reset --hard $old '
            '(NOT run by this tool). Check `git status`.');
        return const _Outcome('error', 4);
      }
    }

    // ---- step 4: the unmerged paths -------------------------------------------------------------------
    final stages = await _unmergedStages();
    if (stages.isNotEmpty) await _resolveAll(stages);

    // ---- step 5: the gate index, then what remains ----------------------------------------------------
    var remaining = (await _unmerged()).toSet();
    if (remaining.length == 1 && remaining.single == kGateIndexPath) {
      await _gateIndex();
      remaining = (await _unmerged()).toSet();
    }
    _report();
    if (remaining.isNotEmpty) {
      stdout.writeln('${remaining.length} path(s) remain: edit them (or `git checkout --merge -- <path>` to see git\'s '
          'version again), `git add` each, then conclude with:\n'
          '  sh scripts/safe_commit.sh "$mergeMessage"');
      _prune();
      return const _Outcome('pending', 1);
    }

    // ---- step 6: nothing is unmerged ------------------------------------------------------------------
    final unstaged = (await _git(['diff', '--name-only'])).text;
    if (unstaged.isNotEmpty) {
      stdout.writeln('NOT in the merge commit (changed in the work tree after staging; `git add` them if they belong):\n  '
          '${unstaged.split('\n').join('\n  ')}');
    }
    if (!commit) {
      stdout.writeln('all conflicts resolved and staged; review `git diff --cached`, then:\n'
          '  sh scripts/safe_commit.sh "$mergeMessage"');
      _prune();
      return const _Outcome('ready', 0);
    }
    if (!File('scripts/safe_commit.sh').existsSync()) {
      stdout.writeln('scripts/safe_commit.sh is missing in this tree; the merge is pending and staged');
      return const _Outcome('commit-failed', 3);
    }
    stdout.writeln('concluding the merge with scripts/safe_commit.sh (the full pre-commit loop; this can take minutes) ...');
    await stdout.flush();
    final p = await Process.start('sh', ['scripts/safe_commit.sh', mergeMessage], mode: ProcessStartMode.inheritStdio);
    final code = await p.exitCode;
    _prune();
    if (code == 0) {
      _clearState();
      return const _Outcome('committed', 0);
    }
    stdout.writeln('safe_commit.sh failed (exit $code); the merge is still pending and staged');
    return const _Outcome('commit-failed', 3);
  }

  String _short(String sha) => sha.length > 8 ? sha.substring(0, 8) : sha;

  // ---- git plumbing --------------------------------------------------------------------------------
  Future<List<String>> _unmerged() async => (await _unmergedStages()).keys.toList();

  /// path -> stage number -> entry, from `git ls-files -u -z`.
  Future<Map<String, Map<int, _Stage>>> _unmergedStages() async {
    final r = await _git(['ls-files', '-u', '-z']);
    if (r.code != 0) throw StateError('git ls-files -u failed (exit ${r.code}): ${r.errText}');
    final out = <String, Map<int, _Stage>>{};
    for (final rec in utf8.decode(r.out).split('\u0000')) {
      if (rec.isEmpty) continue;
      final tab = rec.indexOf('\t');
      final meta = tab < 0 ? const <String>[] : rec.substring(0, tab).split(' ');
      final stage = meta.length == 3 ? int.tryParse(meta[2]) : null;
      if (stage == null) throw StateError('unexpected `git ls-files -u -z` record: "$rec"');
      out.putIfAbsent(rec.substring(tab + 1), () => {})[stage] = _Stage(meta[0], meta[1]);
    }
    return out;
  }

  Future<void> _fetch() async {
    final Process p;
    try {
      p = await Process.start(
        'git',
        ['fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main'],
        environment: {'GIT_TERMINAL_PROMPT': '0'},
      );
    } on ProcessException catch (e) {
      throw _Refused('could not start git fetch: ${e.message}');
    }
    unawaited(p.stdin.close().catchError((_) {}));
    unawaited(p.stdout.drain<void>().catchError((_) {}));
    final err = <int>[];
    p.stderr.listen(err.addAll, onError: (_) {});
    var timedOut = false;
    final code = await p.exitCode.timeout(Duration(milliseconds: fetchTimeoutMs), onTimeout: () {
      timedOut = true;
      p.kill(ProcessSignal.sigkill);
      return -1;
    });
    if (timedOut) throw _Refused('git fetch timed out after ${fetchTimeoutMs ~/ 1000}s and was killed');
    if (code != 0) {
      final tail = utf8.decode(err, allowMalformed: true).trim();
      throw _Refused('git fetch failed (exit $code)${tail.isEmpty ? '' : ': $tail'}');
    }
  }

  // ---- state ---------------------------------------------------------------------------------------
  void _clearState() {
    try {
      final f = File('$stateDir/identity');
      if (f.existsSync()) f.deleteSync();
      final w = Directory('$stateDir/written');
      if (w.existsSync()) w.deleteSync(recursive: true);
    } catch (_) {
      // a leftover is discarded by the identity check
    }
  }

  /// Writes `identity` BEFORE any temp file; a `written/` of another merge is discarded. False when the state
  /// directory cannot be used (every path is then left).
  bool _prepareState() {
    try {
      final head = _gitSync(['rev-parse', 'HEAD']).text;
      final mh = File(mergeHeadPath);
      final id = '$head\n${mh.readAsStringSync().trim()}\n${FileStat.statSync(mergeHeadPath).modified.millisecondsSinceEpoch}\n';
      final f = File('$stateDir/identity');
      var same = false;
      try {
        same = f.existsSync() && f.readAsStringSync() == id;
      } catch (_) {}
      if (!same) {
        final w = Directory('$stateDir/written');
        if (w.existsSync()) w.deleteSync(recursive: true);
      }
      Directory(stateDir).createSync(recursive: true);
      if (!same) f.writeAsStringSync(id, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  TextMerge _textMerge() => (String base, String ours, String theirs) {
        final dir = Directory('$stateDir/tmp')..createSync(recursive: true);
        final id = '$pid-${_seq++}';
        final fo = File('${dir.path}/$id.ours');
        final fb = File('${dir.path}/$id.base');
        final ft = File('${dir.path}/$id.theirs');
        try {
          fo.writeAsStringSync(ours);
          fb.writeAsStringSync(base);
          ft.writeAsStringSync(theirs);
          final r = Process.runSync(
            'git',
            ['merge-file', '-p', '--diff3', '-L', 'HEAD', '-L', 'base', '-L', 'origin/main', fo.path, fb.path, ft.path],
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
          );
          if (r.exitCode < 0 || r.exitCode > 127) throw Unresolvable('git merge-file failed (exit ${r.exitCode})');
          return (text: r.stdout as String, conflicted: r.exitCode != 0);
        } on ProcessException catch (e) {
          throw Unresolvable('git merge-file could not start: ${e.message}');
        } on FileSystemException catch (e) {
          throw Unresolvable('could not write a temp file for git merge-file: ${e.message}');
        } finally {
          for (final f in [fo, fb, ft]) {
            try {
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
          }
        }
      };

  // ---- step 4 --------------------------------------------------------------------------------------
  Future<void> _resolveAll(Map<String, Map<int, _Stage>> stages) async {
    final stateOk = _prepareState();
    final merge = _textMerge();
    final paths = stages.keys.toList()..sort();
    for (final path in paths) {
      try {
        lines.add(await _resolveOne(path, stages[path]!, stateOk, merge));
      } on Unresolvable catch (e) {
        lines.add(_Line('left', path, e.reason));
      } catch (e) {
        // one unreadable or unwritable path must not stop the others; nothing was staged for it
        lines.add(_Line('left', path, 'internal error: ${e.toString().split('\n').first}'));
      }
    }
  }

  Future<_Line> _resolveOne(String path, Map<int, _Stage> st, bool stateOk, TextMerge merge) async {
    final spec = specFor(path);
    if (spec == null) return _Line('left', path, 'not on the resolvable list (left exactly as git wrote it)');
    for (final n in const [1, 2, 3]) {
      if (!st.containsKey(n)) {
        return _Line('left', path, 'no stage $n (add/add or delete/modify conflict): a human decides');
      }
    }
    final modes = {st[1]!.mode, st[2]!.mode, st[3]!.mode};
    if (modes.length != 1 || modes.single != '100644') {
      return _Line('left', path, 'file mode ${modes.join('/')} (only plain 100644 files are resolved)');
    }
    if (!stateOk) return _Line('left', path, 'the state directory $stateDir could not be created');
    final blobs = <int, String>{};
    for (final n in const [1, 2, 3]) {
      final b = await _git(['cat-file', 'blob', st[n]!.sha]);
      if (b.code != 0) return _Line('left', path, 'could not read stage $n: ${b.errText}');
      try {
        blobs[n] = utf8.decode(b.out);
      } on FormatException {
        return _Line('left', path, 'stage $n is not valid UTF-8');
      }
    }
    final base = blobs[1]!, ours = blobs[2]!, theirs = blobs[3]!;
    final r = resolveFile(spec, base: base, ours: ours, theirs: theirs, textMerge: merge);
    final problem = verifyResolution(spec, r, base: base, ours: ours, theirs: theirs, textMerge: merge);
    if (problem != null) return _Line('left', path, problem);
    return _apply(path, r);
  }

  /// D5: the per-path write rules.
  Future<_Line> _apply(String path, Resolution r) async {
    final outBytes = utf8.encode(r.text);
    final outMarkers = conflictsInFile(path, r.text).isNotEmpty;
    final file = File(path);
    if (!file.existsSync()) return _Line('left', path, 'the file is missing from the work tree');
    final cur = file.readAsBytesSync();
    final writtenFile = File('$stateDir/written/$path');

    // (1) the file already holds the output
    if (_sameBytes(cur, outBytes)) {
      try {
        if (!writtenFile.existsSync() || !_sameBytes(writtenFile.readAsBytesSync(), outBytes)) {
          writtenFile.parent.createSync(recursive: true);
          writtenFile.writeAsBytesSync(outBytes, flush: true);
        }
      } catch (_) {}
      return _finishPath(path, r, outMarkers, wrote: false);
    }
    // (2) no marker line left: a human (or rerere) resolved it
    final String curText;
    try {
      curText = utf8.decode(cur);
    } on FormatException {
      return _Line('left', path, 'the file in the work tree is not valid UTF-8');
    }
    if (conflictsInFile(path, curText).isEmpty) {
      return _Line('left', path, 'resolved but not staged: review it, then `git add $path`');
    }
    // (3) the tool wrote it and a human edited it since
    if (writtenFile.existsSync()) {
      List<int> prev;
      try {
        prev = writtenFile.readAsBytesSync();
      } catch (_) {
        prev = const [];
      }
      if (!_sameBytes(prev, cur)) {
        return _Line('left', path, 'edited since the tool wrote it (remove ${writtenFile.path} to let the tool redo this path)');
      }
    }
    // (4) overwrite, after a backup
    if (!_backup(path, cur)) return _Line('left', path, 'could not back up the current file; it was not touched');
    if (!_writeAtomic(path, outBytes)) return _Line('left', path, 'could not write (the file was not changed; the backup is kept)');
    try {
      writtenFile.parent.createSync(recursive: true);
      writtenFile.writeAsBytesSync(outBytes, flush: true);
    } catch (_) {
      // without the record the next run backs up again: harmless
    }
    return _finishPath(path, r, outMarkers, wrote: true);
  }

  Future<_Line> _finishPath(String path, Resolution r, bool outMarkers, {required bool wrote}) async {
    if (r.partial || outMarkers) {
      final keys = r.conflictedKeys.isEmpty ? 'a conflict' : r.conflictedKeys.join(', ');
      return _Line('partial', path, 'markers kept for: $keys${wrote ? '' : ' (unchanged since the last run)'}');
    }
    final add = await _git(['add', '--', path]);
    if (add.code != 0) {
      return _Line('left', path, 'written, NOT staged: git add failed (${add.errText}); run `git add $path`');
    }
    if (r.mergedByLine.isNotEmpty) {
      byLine.add('$path: ${r.mergedByLine.join(', ')}');
      return _Line('merged-by-line', path, 'staged; read these records: ${r.mergedByLine.join(', ')}');
    }
    return _Line('resolved', path, wrote ? 'staged' : 'staged (already in place)');
  }

  // ---- backups and writes ---------------------------------------------------------------------------
  bool _backup(String path, List<int> bytes) {
    try {
      backupRun ??= _newBackupRun();
      final dest = File('$backupRun/$path');
      dest.parent.createSync(recursive: true);
      dest.writeAsBytesSync(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _newBackupRun() {
    final head = _short(_gitSync(['rev-parse', 'HEAD']).text);
    Directory(backupRoot).createSync(recursive: true);
    for (var n = 1;; n++) {
      final d = Directory('$backupRoot/$head-$n');
      if (!d.existsSync()) {
        d.createSync();
        return d.path;
      }
    }
  }

  void _prune() {
    if (backupRun == null) return;
    try {
      final root = Directory(backupRoot);
      final runs = <({Directory dir, int modified, bool holds})>[];
      for (final e in root.listSync()) {
        if (e is! Directory) continue;
        final holds = e.listSync(recursive: true).any((x) => x is File);
        runs.add((dir: e, modified: FileStat.statSync(e.path).modified.millisecondsSinceEpoch, holds: holds));
      }
      runs.sort((a, b) {
        final c = b.modified.compareTo(a.modified);
        return c != 0 ? c : b.dir.path.compareTo(a.dir.path);
      });
      var kept = 0;
      for (final r in runs) {
        if (r.holds && kept < kKeepBackupRuns) {
          kept++;
          continue;
        }
        r.dir.deleteSync(recursive: true);
      }
    } catch (_) {
      // pruning is housekeeping only
    }
  }

  bool _writeAtomic(String path, List<int> bytes) {
    final tmp = File('$stateDir/tmp/${path.replaceAll('/', '_')}.$pid');
    try {
      tmp.parent.createSync(recursive: true);
      tmp.writeAsBytesSync(bytes, flush: true);
      tmp.renameSync(path);
      return true;
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      return false;
    }
  }

  // ---- step 5 --------------------------------------------------------------------------------------
  /// D4: the generated gate index is a pure function of tracked inputs; when it is the ONLY unmerged path the
  /// builder is the merge. A failing builder restores git's conflicted file.
  Future<void> _gateIndex() async {
    final file = File(kGateIndexPath);
    if (!file.existsSync() || !File('scripts/build_gate_index.dart').existsSync()) {
      lines.add(_Line('left', kGateIndexPath, 'scripts/build_gate_index.dart or the file is missing; regenerate it by hand'));
      return;
    }
    final snapshot = file.readAsBytesSync();
    ProcessResult r;
    try {
      r = await retryDartProcess(
        () => Process.run(Platform.resolvedExecutable, ['scripts/build_gate_index.dart'], stdoutEncoding: utf8, stderrEncoding: utf8),
        label: 'build_gate_index.dart',
      );
    } on ProcessException catch (e) {
      file.writeAsBytesSync(snapshot);
      lines.add(_Line('left', kGateIndexPath, 'could not start the builder: ${e.message}'));
      return;
    }
    final fresh = file.existsSync() ? file.readAsStringSync() : '';
    if (r.exitCode != 0 || conflictsInFile(kGateIndexPath, fresh).isNotEmpty) {
      file.writeAsBytesSync(snapshot);
      final tail = '${r.stdout}${r.stderr}'.trim().split('\n').where((l) => l.trim().isNotEmpty).take(3).join(' | ');
      lines.add(_Line('left', kGateIndexPath, 'the builder failed (exit ${r.exitCode}); git\'s version is restored. $tail'));
      return;
    }
    final add = await _git(['add', '--', kGateIndexPath]);
    if (add.code != 0) {
      lines.add(_Line('left', kGateIndexPath, 'regenerated, NOT staged: git add failed; run `git add $kGateIndexPath`'));
      return;
    }
    lines.removeWhere((l) => l.path == kGateIndexPath);
    lines.add(_Line('resolved', kGateIndexPath, 'regenerated by scripts/build_gate_index.dart and staged'));
  }

  void _report() {
    for (final l in lines) {
      stdout.writeln('  ${l.status.padRight(14)} ${l.path}  ${l.detail}');
    }
    if (backupRun != null) stdout.writeln('backups of overwritten files: $backupRun');
    if (byLine.isNotEmpty) {
      stdout.writeln('merged by line - two edits to ONE record; read them before the commit:\n  ${byLine.join('\n  ')}');
    }
  }
}
