// scripts/land_pr.dart -- `sh scripts/land_pr.sh <pr> [--allow-workflow-change]`
//
// Lands the PR of the CURRENT branch (landing D of the merge-conflict-treadmill plan, docs/plans/merge-train.md, OI-309):
// sync with origin/main (scripts/sync_with_main.sh --commit), push (scripts/safe_push.sh), wait for CI on the pushed head,
// check that main and the PR head did not move (else another round, at most 3), replay CI's plan-review-record gate on the
// merge commit GitHub will create, then merge (scripts/safe_pr_merge.sh). It drives only the branch of the worktree it
// runs in, only through those wrappers, and never runs a raw git commit/push or `gh pr merge`.
//
// stdout: child output is passed through with a `<name>> ` prefix on every line, so exactly one line starts with `result:`
// and it is the last. Exit codes (the CLI's own: 0..7): 0 merged, 1 needs-human, 2 refused, 3 ci-failed|ci-timeout, 4 error,
// 5 record-failed, 6 merge-refused, 7 merge-unverified. The wrapper maps a higher status or a signal to `result: error`, 4.
//
// Flags are the PR number and `--allow-workflow-change` (forwarded to the merge wrapper). Test seams, never forwarded by the
// wrapper: --gh "<cmd>", --scripts-dir <dir>, --poll-ms, --ci-timeout-ms, --fetch-timeout-ms, --gh-timeout-ms,
// --record-gate "<cmd>". Reads no environment variable; children inherit the environment. Run directly (not through the
// wrapper) with a seam, it is a test harness: `--record-gate` skips the replay.
//
// Phases without a deadline (a supervisor signals the wrapper's process group): the sync with --commit (it can run the full
// pre-commit loop), the push, the merge wrapper. A TERM/INT/HUP stops no child: it is recorded, the running child finishes,
// the scratch clone is deleted and the run ends `result: error`. No lock excludes a second run in the same worktree (plan
// residual R1; a lock file has no safe reclaim, OI-92); do not start two.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'land_pr_lib.dart';
import 'retire_worktree_lib.dart' show protectedBranchReason;
import 'safe_pr_merge_lib.dart';

class _Stop implements Exception {
  _Stop(this.result, this.message);

  final LandResult result;
  final String message;
}

class _Interrupted implements Exception {
  _Interrupted(this.phase);

  final String phase;
}

class _Child {
  _Child(this.code, this.out, this.err, this.timedOut);

  final int code;
  final String out;
  final String err;
  final bool timedOut;
}

class _Opts {
  String pr = '';
  bool allowWorkflowChange = false;
  String gh = 'gh';
  String? scriptsDir;
  int pollMs = 30000;
  int ciTimeoutMs = 3600000;
  int fetchTimeoutMs = 120000;
  int ghTimeoutMs = 60000;
  String? recordGate;
}

bool _finished = false;
String? _interruptSignal;
int _childrenRunning = 0;
_Land? _land;

/// A write to our own stderr, same rule.
void _err(String line) {
  try {
    stderr.writeln(line);
  } catch (_) {}
}

/// A write to our own stdout that cannot fail the run: a closed terminal or pipe must not turn a landing into an
/// uncaught error while a child (the merge) is still running. The exit code still carries the answer.
void _out(String line) {
  try {
    stdout.writeln(line);
  } catch (_) {}
}

/// A message on ONE line (git and gh errors carry newlines; a later line must not start with `result:`).
String _oneLine(String s) => s.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' | ').trim();

/// The ONE exit point: the latch keeps a late error from printing a second result; the result line is the last write.
Future<void> _finish(LandResult r) async {
  if (_finished) return;
  _finished = true;
  try {
    stdout.writeln('result: ${r.word}');
    // A broken stdout never completes its flush: do not wait for it for ever.
    await stdout.flush().timeout(const Duration(seconds: 2));
  } catch (_) {
    // stdout is gone (EPIPE): the exit code still carries the answer.
  }
  exit(r.code);
}

_Opts _parse(List<String> args) {
  final o = _Opts();
  var havePr = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? valueOf(String name) {
      if (a == name) {
        if (i + 1 >= args.length) throw _Stop(resRefused, '$name needs a value');
        return args[++i];
      }
      if (a.startsWith('$name=')) return a.substring(name.length + 1);
      return null;
    }

    int intOf(String name, String v) {
      final n = int.tryParse(v);
      if (n == null || n <= 0) throw _Stop(resRefused, 'bad value for $name: "$v"');
      return n;
    }

    if (a == '--allow-workflow-change') {
      o.allowWorkflowChange = true;
    } else if (valueOf('--gh') case final v?) {
      o.gh = v;
    } else if (valueOf('--scripts-dir') case final v?) {
      o.scriptsDir = v;
    } else if (valueOf('--poll-ms') case final v?) {
      o.pollMs = intOf('--poll-ms', v);
    } else if (valueOf('--ci-timeout-ms') case final v?) {
      o.ciTimeoutMs = intOf('--ci-timeout-ms', v);
    } else if (valueOf('--fetch-timeout-ms') case final v?) {
      o.fetchTimeoutMs = intOf('--fetch-timeout-ms', v);
    } else if (valueOf('--gh-timeout-ms') case final v?) {
      o.ghTimeoutMs = intOf('--gh-timeout-ms', v);
    } else if (valueOf('--record-gate') case final v?) {
      o.recordGate = v;
    } else if (a.startsWith('-')) {
      throw _Stop(resRefused, 'unknown argument "$a" (usage: sh scripts/land_pr.sh <pr> [--allow-workflow-change])');
    } else if (!havePr && RegExp(r'^[0-9]+$').hasMatch(a)) {
      o.pr = a;
      havePr = true;
    } else {
      throw _Stop(resRefused, 'unexpected argument "$a" (usage: sh scripts/land_pr.sh <pr> [--allow-workflow-change])');
    }
  }
  if (!havePr) throw _Stop(resRefused, 'a PR number is required (usage: sh scripts/land_pr.sh <pr> [--allow-workflow-change])');
  return o;
}

class _Land {
  _Land(this.o);

  final _Opts o;
  String top = Directory.current.path;
  late String branch;
  late String repo; // owner/name
  late String owner;
  String? scratch;
  String phase = 'starting';

  void _say(String s) => _out('land_pr: ${_oneLine(s)}');

  void _checkInterrupt() {
    if (_interruptSignal != null) throw _Interrupted(phase);
  }

  /// Runs [exe] with stdin closed, optionally streaming prefixed output, killing it at [timeoutMs].
  Future<_Child> _run(
    String exe,
    List<String> args, {
    String? cwd,
    Map<String, String>? env,
    int? timeoutMs,
    String? stream,
  }) async {
    final Process p;
    try {
      p = await Process.start(exe, args, workingDirectory: cwd, environment: env);
    } on ProcessException catch (e) {
      return _Child(127, '', e.message, false);
    }
    _childrenRunning++;
    unawaited(p.stdin.close().catchError((_) {}));
    final out = StringBuffer();
    final err = StringBuffer();
    Future<void> pump(Stream<List<int>> s, StringBuffer sink, String tag) {
      // allowMalformed: a stray non-UTF-8 byte must not stop the pump (a child blocked on a full pipe would hang for ever,
      // and the `result:` line the protocol parses would be lost).
      return s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach((line) {
        sink.writeln(line);
        if (stream != null) _out('$stream$tag> ${line.replaceAll('\r', '')}');
      });
    }

    final done = Future.wait([pump(p.stdout, out, ''), pump(p.stderr, err, '!')]);
    var timedOut = false;
    Timer? timer;
    if (timeoutMs != null) {
      timer = Timer(Duration(milliseconds: timeoutMs), () {
        timedOut = true;
        p.kill(ProcessSignal.sigkill);
      });
    }
    final code = await p.exitCode;
    // A killed child can leave a grandchild holding the pipes open: do not wait for them for ever.
    await done.timeout(const Duration(seconds: 2), onTimeout: () => <void>[]).catchError((_) => <void>[]);
    timer?.cancel();
    _childrenRunning--;
    return _Child(code, out.toString(), err.toString(), timedOut);
  }

  Future<_Child> _git(List<String> args, {int? timeoutMs, Map<String, String>? extraEnv, List<String>? lead}) =>
      _run('git', [...?lead, ...args],
          cwd: top, env: {'GIT_TERMINAL_PROMPT': '0', ...?extraEnv}, timeoutMs: timeoutMs);

  /// Runs gh; stdout is null on ANY failure (non-zero exit, timeout, spawn error), like scripts/safe_pr_merge.dart.
  Future<({String? out, String err})> _gh(List<String> args) async {
    final c = splitCommand(o.gh);
    final r = await _run(c.exe, [...c.prefix, ...args], cwd: top, timeoutMs: o.ghTimeoutMs);
    return (out: (r.code == 0 && !r.timedOut) ? r.out : null, err: r.timedOut ? 'gh timed out' : r.err.trim());
  }

  Map<String, dynamic>? _obj(String? raw) {
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } on FormatException {
      return null;
    }
  }

  String get _scriptsDir => o.scriptsDir ?? File(Platform.script.toFilePath()).parent.path;

  Future<String> _headSha() async {
    final r = await _git(['rev-parse', '--verify', 'HEAD^{commit}']);
    if (r.code != 0) throw _Stop(resError, 'could not read HEAD: ${r.err.trim()}');
    return r.out.trim();
  }

  // ---------------------------------------------------------------- remote tip
  /// The remote branch tip after a fetch of it, or null when the branch is absent on the remote. A failure or timeout throws
  /// [_Stop] with [onFail].
  Future<String?> _remoteTip(LandResult onFail) async {
    final ls = await _git(['ls-remote', '--heads', 'origin', 'refs/heads/$branch'], timeoutMs: o.fetchTimeoutMs);
    if (ls.timedOut) throw _Stop(onFail, 'could not read the remote branch: git ls-remote timed out');
    if (ls.code != 0) throw _Stop(onFail, 'could not read the remote branch: ${ls.err.trim()}');
    if (ls.out.trim().isEmpty) return null;
    final f = await _git(['fetch', '--quiet', 'origin', '+refs/heads/$branch:refs/remotes/origin/$branch'],
        timeoutMs: o.fetchTimeoutMs);
    if (f.timedOut) throw _Stop(onFail, 'git fetch of the branch timed out');
    if (f.code != 0) throw _Stop(onFail, 'git fetch of the branch failed: ${f.err.trim()}');
    final t = await _git(['rev-parse', '--verify', '--quiet', 'refs/remotes/origin/$branch^{commit}']);
    if (t.code != 0) throw _Stop(onFail, 'the fetched remote branch tip is not a commit');
    return t.out.trim();
  }

  // ---------------------------------------------------------------- preconditions
  Future<void> preconditions() async {
    phase = 'preconditions';
    final topR = await _git(['rev-parse', '--show-toplevel']);
    if (topR.code != 0 || topR.out.trim().isEmpty) throw _Stop(resRefused, 'not inside a git work tree');
    top = topR.out.trim();
    Directory.current = top;
    final br = await _git(['symbolic-ref', '--quiet', '--short', 'HEAD']);
    if (br.code != 0 || br.out.trim().isEmpty) throw _Stop(resRefused, 'HEAD is detached; check out the PR branch first');
    branch = br.out.trim();
    final prot = protectedBranchReason(branch);
    if (prot != null) throw _Stop(resRefused, 'branch "$branch" is a $prot; land a feature branch');
    for (final n in inProgressStateFiles) {
      final p = await _git(['rev-parse', '--git-path', n]);
      if (p.code != 0) throw _Stop(resRefused, 'git could not resolve $n: ${p.err.trim()}');
      final path = p.out.trim();
      if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
        throw _Stop(resRefused, 'a merge, rebase, cherry-pick, revert, bisect or sequencer operation is in progress ($n exists)');
      }
    }
    final st = await _git(['status', '--porcelain=v1', '--untracked-files=no']);
    if (st.code != 0) throw _Stop(resRefused, 'git status failed: ${st.err.trim()}');
    if (st.out.trim().isNotEmpty) throw _Stop(resRefused, 'tracked files are modified or staged; commit or set that work aside first');

    final rv = await _gh(['repo', 'view', '--json', 'nameWithOwner']);
    final nwo = _obj(rv.out)?['nameWithOwner'];
    if (nwo is! String || ownerOf(nwo) == null) throw _Stop(resRefused, 'could not read the repository name from gh: ${rv.err}');
    repo = nwo;
    owner = ownerOf(nwo)!;
    final pv = await _gh(['pr', 'view', o.pr, '--json', 'state,isDraft,headRefName,headRefOid,baseRefName,isCrossRepository']);
    final pr = _obj(pv.out);
    if (pr == null) throw _Stop(resRefused, 'could not read PR #${o.pr} from gh: ${pv.err}');
    final why = prRefusal(pr, branch, allowMerged: true);
    if (why != null) throw _Stop(resRefused, why);
    if (prIsMerged(pr)) {
      _say('PR #${o.pr} is already merged');
      throw _Stop(resMerged, '');
    }
    final files = await _gh(['api', 'repos/$repo/pulls/${o.pr}/files', '--paginate']);
    List<String> changed;
    try {
      changed = files.out == null ? throw const FormatException('gh failed') : parseChangedFiles(files.out!);
    } on FormatException catch (e) {
      throw _Stop(resRefused, 'could not read the PR file list: ${e.message} ${files.err}');
    }
    final wf = workflowChangeRefusal(changed, allowWorkflowChange: o.allowWorkflowChange);
    if (wf != null) throw _Stop(resRefused, wf);

    final tip = await _remoteTip(resRefused);
    if (tip == null) {
      throw _Stop(resRefused, 'branch "$branch" does not exist on origin while PR #${o.pr} is open');
    }
    final anc = await _git(['merge-base', '--is-ancestor', tip, 'HEAD']);
    if (anc.code == 1) {
      throw _Stop(resRefused, 'origin/$branch ($tip) is not an ancestor of HEAD: someone pushed to the branch; the command never force-pushes');
    }
    if (anc.code != 0) throw _Stop(resRefused, 'could not compare origin/$branch with HEAD: ${anc.err.trim()}');
    final lg = await _git(['log', '--format=%h %s', '$tip..HEAD']);
    _say(unpushedSummary(lg.out.split('\n').where((l) => l.trim().isNotEmpty).toList()));
  }

  // ---------------------------------------------------------------- the round loop
  Future<LandResult> rounds() async {
    for (var round = 1; round <= maxRounds; round++) {
      _say('round $round of $maxRounds');
      // 1. sync
      phase = 'sync';
      final sync = await _run('sh', ['$_scriptsDir/sync_with_main.sh', '--commit'], cwd: top, stream: 'sync');
      _checkInterrupt();
      final word = parseResultWord(sync.out);
      switch (syncNext(word)) {
        case SyncNext.proceed:
          break;
        case SyncNext.needsHuman:
          throw _Stop(resNeedsHuman, 'the sync stopped (result: $word); resolve what it left, then run the command again');
        case SyncNext.refused:
          throw _Stop(resRefused, 'the sync refused${round > 1 ? ' (rounds before this one may already have pushed commits)' : ''}');
        case SyncNext.error:
          throw _Stop(resError, 'the sync ended with ${word == null ? 'no result line' : 'result: $word'} (exit ${sync.code})');
      }
      // 2. the remote tip, the local .github check, the push
      phase = 'push';
      final tip = await _remoteTip(resError);
      if (tip == null) throw _Stop(resError, 'branch "$branch" vanished from origin');
      final anc = await _git(['merge-base', '--is-ancestor', tip, 'HEAD']);
      if (anc.code == 1) throw _Stop(resNeedsHuman, 'someone pushed to origin/$branch while this ran ($tip is not an ancestor of HEAD); run the command again');
      if (anc.code != 0) throw _Stop(resError, 'could not compare origin/$branch with HEAD: ${anc.err.trim()}');
      final diff = await _git(['diff', '--name-only', 'refs/remotes/origin/main...HEAD']);
      if (diff.code != 0) throw _Stop(resError, 'git diff against origin/main failed: ${diff.err.trim()}');
      final wf = workflowChangeRefusal(diff.out.split('\n').where((l) => l.isNotEmpty).toList(),
          allowWorkflowChange: o.allowWorkflowChange);
      if (wf != null) {
        throw _Stop(resRefused, '$wf${round > 1 ? ' (rounds before this one may already have pushed commits)' : ''}');
      }
      var head = await _headSha();
      _checkInterrupt();
      if (head != tip) {
        final push = await _run('sh', ['$_scriptsDir/safe_push.sh', 'origin', branch], cwd: top, stream: 'push');
        _checkInterrupt();
        if (push.code != 0) throw _Stop(resError, 'the push did not land (safe_push exit ${push.code})');
        head = await _headSha();
      }
      // 3. CI
      phase = 'ci';
      await _waitCi(head);
      // 4. did main move?
      phase = 'fetch';
      final fm = await _git(['fetch', '--quiet', 'origin', '+refs/heads/main:refs/remotes/origin/main'], timeoutMs: o.fetchTimeoutMs);
      _checkInterrupt();
      if (fm.timedOut) throw _Stop(resError, 'git fetch of main timed out');
      if (fm.code != 0) throw _Stop(resError, 'git fetch of main failed: ${fm.err.trim()}');
      // Pin main ONCE: refs/remotes/origin/main is shared by every worktree of the clone, and any session's fetch can move it.
      // The ancestry check, the replay's PUSH_BEFORE and its merge-commit parent all use THIS sha.
      final mainRead = await _git(['rev-parse', '--verify', 'refs/remotes/origin/main^{commit}']);
      final mainSha = mainRead.out.trim();
      if (mainRead.code != 0 || mainSha.isEmpty) throw _Stop(resError, 'could not read origin/main: ${mainRead.err.trim()}');
      final ma = await _git(['merge-base', '--is-ancestor', mainSha, 'HEAD']);
      if (ma.code != 0 && ma.code != 1) throw _Stop(resError, 'could not compare origin/main with HEAD: ${ma.err.trim()}');
      switch (roundNext(round: round, mainIsAncestor: ma.code == 0)) {
        case RoundNext.nextRound:
          _say('main moved while CI ran; syncing again');
          continue;
        case RoundNext.giveUp:
          throw _Stop(resNeedsHuman, mainMovedMessage);
        case RoundNext.replayAndMerge:
          break;
      }
      // 5. the PR head is what we synced and tested
      phase = 'head check';
      final prHead = await _prHead();
      _checkInterrupt();
      if (prHead != head) {
        throw _Stop(resNeedsHuman, 'the PR head is $prHead, not the $head that was synced and tested; run the command again');
      }
      // 6. the record replay
      phase = 'record replay';
      await _recordGate(head, mainSha);
      // 7. merge
      phase = 'merge';
      return await _merge();
    }
    throw _Stop(resError, 'internal: the round loop ended without a decision');
  }

  Future<String> _prHead() async {
    for (var i = 0; i < 2; i++) {
      final r = await _gh(['pr', 'view', o.pr, '--json', 'headRefOid']);
      final v = _obj(r.out)?['headRefOid'];
      if (v is String && v.isNotEmpty) return v;
    }
    throw _Stop(resError, 'could not read the PR head from gh');
  }

  Future<bool?> _prMerged() async {
    for (var i = 0; i < 2; i++) {
      final r = await _gh(['pr', 'view', o.pr, '--json', 'state']);
      final v = _obj(r.out)?['state'];
      if (v is String) return v == 'MERGED';
    }
    return null;
  }

  Future<void> _waitCi(String sha) async {
    final watch = CiWatch();
    final deadline = DateTime.now().add(Duration(milliseconds: o.ciTimeoutMs));
    List<Map<String, dynamic>>? last;
    var polls = 0;
    while (true) {
      _checkInterrupt();
      polls++;
      final r = await _gh(['api', 'repos/$repo/commits/$sha/check-runs', '--paginate']);
      CiJudgement? j;
      if (r.out != null) {
        try {
          last = parseCheckRuns(r.out!);
          j = classifyCheckRuns(last);
        } on FormatException {
          j = null;
        }
      }
      final t = watch.update(j);
      switch (t.state) {
        case CiTickState.green:
          _say('CI is green on ${sha.substring(0, 8)} (poll $polls)');
          return;
        case CiTickState.red:
          final why = evaluateCheckRuns(last).reasons.join('; ');
          throw _Stop(resCiFailed, '${t.note.isEmpty ? '' : '${t.note}: '}$why');
        case CiTickState.ghFailing:
          throw _Stop(resError, t.note);
        case CiTickState.pending:
          break;
      }
      if (!DateTime.now().isBefore(deadline)) {
        final why = evaluateCheckRuns(last).reasons.join('; ');
        throw _Stop(resCiTimeout, 'CI did not finish within ${o.ciTimeoutMs ~/ 1000}s: $why');
      }
      await Future<void>.delayed(Duration(milliseconds: o.pollMs));
    }
  }

  // ---------------------------------------------------------------- record replay
  Future<void> _recordGate(String head, String mainSha) async {
    if (o.recordGate != null) {
      final c = splitCommand(o.recordGate!);
      final r = await _run(c.exe, c.prefix, cwd: top, stream: 'gate');
      _checkInterrupt();
      if (!replayVerdict(r.code, r.out)) {
        throw _Stop(resRecordFailed, 'the plan-review-record gate did not print its PASS line (exit ${r.code})');
      }
      return;
    }
    final commonR = await _git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
    if (commonR.code != 0) throw _Stop(resRecordFailed, 'could not resolve the git common dir: ${commonR.err.trim()}');
    final common = commonR.out.trim();
    final dir = '$common/${replayDirName(pid, DateTime.now().millisecondsSinceEpoch)}';
    scratch = dir;
    // The clone ignores an inherited GIT_DIR only when the variables are unset: run it under `env -u`.
    final clone = await _run(
        'env',
        ['-u', 'GIT_DIR', '-u', 'GIT_WORK_TREE', '-u', 'GIT_INDEX_FILE', 'git', 'clone', '--local', '--no-checkout', '--quiet', common, dir],
        cwd: top,
        env: {'GIT_TERMINAL_PROMPT': '0'},
        timeoutMs: o.fetchTimeoutMs * 2);
    _checkInterrupt();
    if (clone.code != 0) throw _Stop(resRecordFailed, 'the scratch clone failed: ${clone.err.trim()}');
    final hooks = Directory('$dir/.git/land_pr_no_hooks')..createSync();
    final lead = ['--git-dir=$dir/.git', '--work-tree=$dir', '-c', 'core.hooksPath=${hooks.path}'];
    final idx = {'GIT_INDEX_FILE': '$dir/.git/index'};
    Future<_Child> sg(List<String> a, {Map<String, String>? env}) async {
      final r = await _git(a, lead: lead, extraEnv: {...idx, ...?env}, timeoutMs: o.fetchTimeoutMs * 2);
      _checkInterrupt();
      return r;
    }

    final fetch = await sg(['fetch', '--quiet', common, '+refs/remotes/origin/main:refs/replay/main', '+refs/heads/$branch:refs/replay/head']);
    if (fetch.code != 0) throw _Stop(resRecordFailed, 'could not fetch the refs into the scratch clone: ${fetch.err.trim()}');
    final ph = (await sg(['rev-parse', '--verify', 'refs/replay/head^{commit}'])).out.trim();
    if (ph != head) throw _Stop(resRecordFailed, 'the branch ref in the scratch clone ($ph) is not HEAD ($head)');
    final pm = (await sg(['rev-parse', '--verify', 'refs/replay/main^{commit}'])).out.trim();
    if (pm != mainSha) throw _Stop(resNeedsHuman, 'origin/main moved to $pm while the replay was prepared (it was $mainSha); run the command again');
    final ident = {
      'GIT_AUTHOR_NAME': 'land_pr',
      'GIT_AUTHOR_EMAIL': 'land_pr@localhost',
      'GIT_COMMITTER_NAME': 'land_pr',
      'GIT_COMMITTER_EMAIL': 'land_pr@localhost',
      'GIT_AUTHOR_DATE': '1970-01-02T00:00:00+0000',
      'GIT_COMMITTER_DATE': '1970-01-02T00:00:00+0000',
    };
    final ct = await sg(['commit-tree', '$head^{tree}', '-p', mainSha, '-p', head, '-m', replayMergeMessage(o.pr, owner, branch)],
        env: ident);
    final mergeSha = ct.out.trim();
    if (ct.code != 0 || mergeSha.isEmpty) throw _Stop(resRecordFailed, 'commit-tree failed: ${ct.err.trim()}');
    final ur = await sg(['update-ref', '--no-deref', 'HEAD', mergeSha]);
    if (ur.code != 0) throw _Stop(resRecordFailed, 'could not detach HEAD in the scratch clone: ${ur.err.trim()}');
    final has = await sg(['cat-file', '-e', '$mergeSha:scripts/check_plan_review_record_exists.dart']);
    if (has.code != 0) throw _Stop(resRecordFailed, 'scripts/check_plan_review_record_exists.dart is missing from the merge commit');
    final rt = await sg(['read-tree', mergeSha]);
    if (rt.code != 0) throw _Stop(resRecordFailed, 'read-tree failed: ${rt.err.trim()}');
    final rs = await sg(['restore', '--source=$mergeSha', '--worktree', '--', 'scripts']);
    if (rs.code != 0) throw _Stop(resRecordFailed, 'could not check out scripts/ in the scratch clone: ${rs.err.trim()}');
    final gate = File('$dir/scripts/check_plan_review_record_exists.dart');
    if (!gate.existsSync()) throw _Stop(resRecordFailed, 'scripts/check_plan_review_record_exists.dart is missing from the merge commit');
    final r = await _run(
        Platform.resolvedExecutable,
        [gate.path],
        cwd: dir,
        env: {
          'GIT_TERMINAL_PROMPT': '0',
          'GIT_DIR': '$dir/.git',
          'GIT_WORK_TREE': dir,
          'GIT_INDEX_FILE': '$dir/.git/index',
          'PUSH_BEFORE': mainSha,
          'GITHUB_REF': 'refs/heads/main',
          'GITHUB_REPOSITORY_OWNER': owner,
          'GITHUB_EVENT_PATH': '',
        },
        stream: 'gate');
    _checkInterrupt();
    if (!replayVerdict(r.code, r.out)) {
      throw _Stop(resRecordFailed, 'the plan-review-record gate did not print its PASS line on the merge commit (exit ${r.code})');
    }
    _say('plan-review-record gate: PASS on the merge commit ${mergeSha.substring(0, 8)}');
  }

  void cleanupScratch() {
    final s = scratch;
    if (s == null) return;
    try {
      Directory(s).deleteSync(recursive: true);
    } catch (_) {
      // a leftover directory is swept by the next run (it is older than a day only after a day).
    }
    scratch = null;
  }

  Future<void> sweepStaleReplays() async {
    final c = await _git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
    if (c.code != 0) return;
    final dir = Directory(c.out.trim());
    if (!dir.existsSync()) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (e is Directory && staleReplayDir(name, now)) {
          try {
            e.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------- merge
  Future<LandResult> _merge() async {
    final args = <String>['$_scriptsDir/safe_pr_merge.sh', o.pr, if (o.allowWorkflowChange) '--allow-workflow-change'];
    final m = await _run('sh', args, cwd: top, stream: 'merge');
    final state = await _prMerged();
    if (_interruptSignal != null && state != true) throw _Interrupted('merge');
    final res = mergeOutcome(status: m.code, merged: state);
    if (res == resMergeRefused) {
      _say('the merge wrapper refused. If main is protected with "up to date" required and this head is behind main, sync and run again.');
    }
    return res;
  }

  Future<LandResult> run() async {
    await preconditions();
    await sweepStaleReplays();
    return await rounds();
  }
}

void main(List<String> args) {
  runZonedGuarded(() async {
    LandResult res;
    _Land? land;
    try {
      final opts = _parse(args);
      land = _Land(opts);
      _land = land;
      // An EPIPE/EIO on our own streams arrives as an async error: it must not end the run (a merge may be running).
      unawaited(stdout.done.catchError((_) {}));
      unawaited(stderr.done.catchError((_) {}));
      for (final sig in [ProcessSignal.sigterm, ProcessSignal.sigint, ProcessSignal.sighup]) {
        try {
          sig.watch().listen((s) => _interruptSignal ??= s.toString());
        } catch (_) {
          // a signal this platform cannot watch (SIGHUP on Windows).
        }
      }
      res = await land.run();
    } on _Stop catch (e) {
      if (e.message.isNotEmpty) _out('land_pr: ${e.result.word == 'refused' ? 'refused: ' : ''}${_oneLine(e.message)}');
      res = e.result;
    } on _Interrupted catch (e) {
      _out('land_pr: interrupted ($_interruptSignal) during the ${e.phase} phase; the running child finished first');
      res = resError;
    } catch (e, st) {
      _out('land_pr: internal error: ${_oneLine('$e')}');
      _err('$st');
      res = resError;
    } finally {
      land?.cleanupScratch();
    }
    await _finish(res);
  }, (e, st) {
    _out('land_pr: internal error: ${_oneLine('$e')}');
    _err('$st');
    // A running child (the merge wrapper) is not abandoned: wait for it, then clean up and finish.
    unawaited(() async {
      final until = DateTime.now().add(const Duration(minutes: 30));
      while (_childrenRunning > 0 && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      _land?.cleanupScratch();
      await _finish(resError);
    }());
  });
}
