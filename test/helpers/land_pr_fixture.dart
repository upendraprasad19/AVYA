// test/helpers/land_pr_fixture.dart
//
// Throwaway repositories plus the STUB protocol for the end-to-end tests of scripts/land_pr.dart and its wrapper
// (landing D, docs/plans/merge-train.md section 5). Built on [SyncCli] (a bare `origin`, branch `feature`, hermetic git).
//
// A stub directory (no spaces in its path) holds `gh`, three wrapper stubs and a record-gate stub. Every stub appends
// `<seq> <name> <argv>` to ONE shared log and answers from queue files `q/<kind>.<n>` (n = the call number of that kind;
// an exhausted queue repeats its last file): line 1 `exit=<status>`, then (gh) optional `stderr:` lines, then the body.
// `gh` kinds: repo, pr-pre, pr-head, pr-state, pr-files, check-runs; an unmatched argv exits 99. The token `@HEAD@` in a gh
// body becomes `git rev-parse HEAD` of the fixture repo at run time. `pre_<kind>.<n>` runs before the reply. The sync stub
// really merges (`mode=merge|ff|none` on line 2), the push stub really pushes. `git fetch` / `ls-remote` are real.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'spawn.dart';
import 'sync_cli_fixture.dart';

const List<String> requiredJobs = <String>[
  'Analyze',
  'Unit Tests',
  'Deno Edge-Function tests',
  'Audit Gates',
  'Build Check (APK)',
];

/// A check-runs body for [jobs] (name -> `status/conclusion`, conclusion `-` = none yet).
String checkRunsBody(Map<String, String> jobs) => checkRunsList([for (final e in jobs.entries) (e.key, e.value)]);

/// The same for a LIST (a job name may repeat: a rerun). Later entries get higher ids.
String checkRunsList(List<(String, String)> jobs) {
  var id = 100;
  final runs = <Map<String, Object?>>[
    for (final e in jobs)
      () {
        final parts = e.$2.split('/');
        return <String, Object?>{
          'id': id++,
          'name': e.$1,
          'status': parts[0],
          'conclusion': parts.length > 1 && parts[1] != '-' ? parts[1] : null,
          'app': <String, Object?>{'slug': 'github-actions'},
        };
      }(),
  ];
  return jsonEncode(<String, Object?>{'total_count': runs.length, 'check_runs': runs});
}

Map<String, String> allGreen() => <String, String>{
      for (final j in requiredJobs) j: 'completed/success',
      'Unit Tests shard 1/4': 'completed/success',
      'Plan-review record (>=account merge-to-main)': 'completed/skipped',
    };

const String _lib = r'''
D="__D__"
log() { s=$(( $(cat "$D/seq" 2>/dev/null || echo 0) + 1 )); echo "$s" > "$D/seq"; echo "$s $*" >> "$D/log"; }
bump() { n=$(( $(cat "$D/count.$1" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$D/count.$1"; echo "$n"; }
qfile() {
  f="$D/q/$1.$2"
  if [ ! -f "$f" ]; then f=$(ls "$D/q" 2>/dev/null | grep "^$1\." | sort -t. -k2 -n | tail -1); [ -n "$f" ] && f="$D/q/$f"; fi
  echo "$f"
}
''';

class LandFixture {
  LandFixture._(this.cli, this.stub);

  final SyncCli cli;
  final String stub;

  String get dir => cli.dir;
  String get scriptsDir => '$stub/scripts';
  String get ghPath => '$stub/gh';
  String get gatePath => '$stub/gate.sh';
  String get landCli => '${cli.srcRoot}/scripts/land_pr.dart';
  String get landWrapper => '${cli.srcRoot}/scripts/land_pr.sh';

  /// A fixture on `feature` (pushed to origin), PR #191 OPEN from `feature` to `main`, CI green, everything stubbed.
  static LandFixture create({Map<String, String>? files}) {
    final cli = SyncCli.create(files: files);
    cli.repo.must(['push', '-q', '-u', 'origin', 'feature']);
    final stub = '${cli.repo.root.path}/stub';
    Directory('$stub/q').createSync(recursive: true);
    Directory('$stub/scripts').createSync(recursive: true);
    final fx = LandFixture._(cli, stub);
    fx._writeStubs();
    fx._defaults();
    return fx;
  }

  void _exe(String path, String body) {
    File(path).writeAsStringSync('#!/bin/sh\n${_lib.replaceAll('__D__', stub)}\n$body\n');
    runSpawn('chmod', ['+x', path], why: 'land_pr_fixture: chmod ${path.split('/').last}');
  }

  void _writeStubs() {
    final repo = dir;
    _exe(ghPath, '''
case "\$*" in
  "repo view"*) kind=repo;;
  "pr view "*"--json state,isDraft"*) kind=pr-pre;;
  "pr view "*"--json headRefOid"*) kind=pr-head;;
  "pr view "*"--json state") kind=pr-state;;
  "api repos/"*"/pulls/"*"/files"*) kind=pr-files;;
  "api repos/"*"/commits/"*"/check-runs"*) kind=check-runs;;
  *) echo "gh stub: unknown argv: \$*" >&2; exit 99;;
esac
n=\$(bump "\$kind")
log "gh \$kind \$*"
[ "\$kind" = check-runs ] && [ -f "\$D/slow_ci" ] && { : > "\$D/ready"; sleep 2; }
[ -x "\$D/pre_\$kind.\$n" ] && "\$D/pre_\$kind.\$n"
f=\$(qfile "\$kind" "\$n")
[ -n "\$f" ] || { echo "gh stub: no queue for \$kind" >&2; exit 98; }
st=\$(sed -n 1p "\$f" | sed 's/^exit=//')
sed -n '2,\$p' "\$f" | grep '^stderr:' | sed 's/^stderr://' >&2
if [ "\$st" = "0" ]; then
  head=\$(git -C "$repo" rev-parse HEAD 2>/dev/null)
  sed -n '2,\$p' "\$f" | grep -v '^stderr:' | sed "s/@HEAD@/\$head/g"
fi
exit "\$st"
''');
    _exe('$scriptsDir/sync_with_main.sh', '''
n=\$(bump sync); log "sync \$*"; f=\$(qfile sync "\$n")
[ -x "\$D/pre_sync.\$n" ] && "\$D/pre_sync.\$n"
[ -f "\$D/slow_sync" ] && { : > "\$D/ready"; sleep 2; }
[ -n "\$f" ] || { echo "no queue for sync"; exit 98; }
st=\$(sed -n 1p "\$f" | sed 's/^exit=//'); mode=\$(sed -n 2p "\$f" | sed 's/^mode=//')
case "\$mode" in
  merge) git merge --no-ff --no-edit -q refs/remotes/origin/main >/dev/null 2>&1;;
  ff) git merge --ff-only -q refs/remotes/origin/main >/dev/null 2>&1;;
esac
sed -n '3,\$p' "\$f"
exit "\$st"
''');
    _exe('$scriptsDir/safe_push.sh', '''
n=\$(bump push); log "push \$*"; f=\$(qfile push "\$n")
st=0; [ -n "\$f" ] && st=\$(sed -n 1p "\$f" | sed 's/^exit=//')
if [ "\$st" = "0" ]; then git push -q origin "\$2" >/dev/null 2>&1 || st=1; echo "pushed"; fi
exit "\$st"
''');
    _exe('$scriptsDir/safe_pr_merge.sh', '''
n=\$(bump merge); log "merge \$*"; f=\$(qfile merge "\$n")
[ -f "\$D/slow_merge" ] && { : > "\$D/ready"; sleep 2; }
[ -n "\$f" ] || { echo "no queue for merge"; exit 98; }
st=\$(sed -n 1p "\$f" | sed 's/^exit=//')
sed -n '2,\$p' "\$f"
exit "\$st"
''');
    _exe(gatePath, '''
n=\$(bump gate); log "gate"; f=\$(qfile gate "\$n")
if [ -z "\$f" ]; then echo "[plan-review-record] PASS: every landing in a..b is accounted for — 1 merge(s)"; exit 0; fi
st=\$(sed -n 1p "\$f" | sed 's/^exit=//')
sed -n '2,\$p' "\$f"
exit "\$st"
''');
  }

  void _defaults() {
    q('repo', 1, '{"nameWithOwner":"acme/avya"}');
    prPre(1);
    q('pr-head', 1, '{"headRefOid":"@HEAD@"}');
    q('pr-state', 1, '{"state":"MERGED"}');
    q('pr-files', 1, '[{"filename":"lib/a.dart"}]');
    q('check-runs', 1, checkRunsBody(allGreen()));
    sync(1);
    merge(1);
  }

  /// A queue file. [body] is the gh body (or, for the scripts, the stdout text).
  void q(String kind, int n, String body, {int exit = 0, String stderr = '', String? mode}) {
    final lines = <String>['exit=$exit', ?(mode == null ? null : 'mode=$mode')];
    if (stderr.isNotEmpty) lines.addAll(stderr.split('\n').map((l) => 'stderr:$l'));
    lines.add(body);
    File('$stub/q/$kind.$n').writeAsStringSync('${lines.join('\n')}\n');
  }

  void prPre(int n, {String state = 'OPEN', bool draft = false, String head = 'feature', String base = 'main', bool fork = false}) {
    q('pr-pre', n,
        '{"state":"$state","isDraft":$draft,"headRefName":"$head","headRefOid":"@HEAD@","baseRefName":"$base","isCrossRepository":$fork}');
  }

  void sync(int n, {String word = 'up-to-date', int exit = 0, String mode = 'none', String? text}) {
    q('sync', n, text ?? 'result: $word', exit: exit, mode: mode);
  }

  void push(int n, {int exit = 0}) => q('push', n, '', exit: exit);

  void merge(int n, {int exit = 0, String out = 'safe_pr_merge: merged'}) => q('merge', n, out, exit: exit);

  void gate(int n, {int exit = 0, String? out}) => q('gate', n, out ?? '[plan-review-record] PASS: every landing in a..b is accounted for — 1 merge(s)', exit: exit);

  /// An executable hook that runs before the reply of call [n] of [kind].
  void pre(String kind, int n, String body) {
    final f = File('$stub/pre_$kind.$n')..writeAsStringSync('#!/bin/sh\n$body\n');
    runSpawn('chmod', ['+x', f.path], why: 'land_pr_fixture: chmod hook');
  }

  /// A hook that lands a commit on origin/main from a second clone (how "main moved during CI" happens).
  void movesMain(String kind, int n, {String file = 'moved.txt', bool fetchLocal = false}) {
    final other = '${cli.repo.root.path}/other';
    if (!Directory(other).existsSync()) {
      final r = runSpawn('git', ['clone', '-q', cli.origin, other],
          why: 'land_pr_fixture: second clone', extraEnv: cli.repo.env, allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'});
      expect(r.exitCode, 0);
      cli.repo.must(['-C', other, 'config', 'user.email', 't@example.com']);
      cli.repo.must(['-C', other, 'config', 'user.name', 'T']);
    }
    pre(kind, n, '''
cd "$other" && git checkout -q main && date +%s%N >> $file && git add -A && git commit -q -m "main moved" && git push -q origin main
${fetchLocal ? 'git -C "$dir" fetch -q origin +refs/heads/main:refs/remotes/origin/main\n' : ''}''');
  }

  /// Everything the stubs logged, as `<seq> <name> <argv>` lines.
  List<String> get log {
    final f = File('$stub/log');
    return f.existsSync() ? f.readAsLinesSync() : <String>[];
  }

  /// The logged call names in order (`sync`, `push`, `merge`, `gate`, `gh <kind>`).
  List<String> get calls => [
        for (final l in log)
          () {
            final p = l.split(' ');
            return p[1] == 'gh' ? 'gh ${p[2]}' : p[1];
          }()
      ];

  int count(String name) => calls.where((c) => c == name).length;

  /// Runs the land_pr CLI with the stubs wired in ([extra] are added after the PR number).
  ProcessResult land({
    String pr = '191',
    List<String> extra = const [],
    String? cwd,
    String? path,
    Map<String, String> env = const {},
    Set<String> allow = const {},
    int pollMs = 20,
    int ciTimeoutMs = 4000,
  }) =>
      runLand(this, [pr, ...seamArgs(this, pollMs: pollMs, ciTimeoutMs: ciTimeoutMs), ...extra],
          cwd: cwd, path: path, env: env, allow: allow);

  /// The wrapper script (only the wrapper's own arguments).
  ProcessResult runWrapper(List<String> args, {String? path, Map<String, String> env = const {}}) {
    return runSpawn('sh', [landWrapper, ...args],
        why: 'land_pr wrapper ${args.join(' ')}',
        workingDirectory: dir,
        extraEnv: {...cli.repo.env, 'PATH': ?path, ...env},
        allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8);
  }
}

/// Runs the land_pr CLI itself (not sync_with_main): [SyncCli.run] always targets sync_with_main.dart, so this helper
/// spawns land_pr.dart with the same hermetic environment.
ProcessResult runLand(LandFixture fx, List<String> args,
    {String? cwd, String? path, Map<String, String> env = const {}, Set<String> allow = const {}}) {
  return runSpawn(dartBin(), [fx.landCli, ...args],
      why: 'land_pr ${args.join(' ')}',
      workingDirectory: cwd ?? fx.dir,
      extraEnv: {...fx.cli.repo.env, 'PATH': ?path, ...env},
      allowControl: {'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', ...allow},
      stdoutEncoding: utf8,
      stderrEncoding: utf8);
}

/// The standard seam arguments for [runLand].
List<String> seamArgs(LandFixture fx, {int pollMs = 20, int ciTimeoutMs = 4000, bool recordGate = true}) => <String>[
      '--gh', fx.ghPath,
      '--scripts-dir', fx.scriptsDir,
      if (recordGate) ...['--record-gate', fx.gatePath],
      '--poll-ms', '$pollMs',
      '--ci-timeout-ms', '$ciTimeoutMs',
      '--fetch-timeout-ms', '20000',
      '--gh-timeout-ms', '20000',
    ];
