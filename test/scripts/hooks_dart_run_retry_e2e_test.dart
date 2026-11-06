// test/scripts/hooks_dart_run_retry_e2e_test.dart
//
// OI-482: the five git hooks, run FOR REAL (the verbatim scripts/*.sh and scripts/_dart_bin.sh copied into a
// throwaway git repo), against a stub `dart` on PATH whose FIRST call of every script dies the way the
// native-assets race kills it: exit 254, `File not formatted as yaml: .` on stderr, no work done. Plan:
// docs/plans/2026-11-06-oi482-hook-dart-run-race.md (D7.4).
//
// Every case has a SWITCH-OFF TWIN: the same fixture with AVYA_DART_RUN_RETRY=0 (today's call). The twin is
// the "where today's call fails" baseline the retry cases claim to beat, and the proof that the kill switch
// restores the old behaviour at the hook level, not only inside the function.
//
// What each hook proves:
//   pre-merge-commit    a lost race at the board build / numbering gate no longer fails the merge
//   commit-msg          a lost race at check_closes_oi_cited / validate_diagnose_doc no longer rejects a commit
//   prepare-commit-msg  a lost race no longer SILENTLY drops the `Blast-radius:` line (stderr is /dev/null there)
//   pre-push            a lost race in the tier pipeline (stdin through a retry) no longer falls into the full suite
//   pre-commit          the explicit runs and the parallel gate loop retry; the loop PRINTS what a failing gate said
//                       (head and tail of a long output, its exit status, a distinct sentence for a KILLED gate),
//                       a retried-but-passing gate's note, and leaves no temp directory behind
//
// D5 (the installed-copy matrix) is run here too: an OLD hook copy against the NEW helper, and a NEW hook against the
// OLD helper (both frozen from origin/main in test/scripts/fixtures/pre_oi482_hooks/).

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

/// Set on purpose: `CONTRACT_SWEEP_SKIP` keeps a hook run from recursing into the sweep runner (the stub
/// handles that script anyway); `AVYA_DART_RUN_RETRY` is the switch-off twin.
const _setOnPurpose = {'CONTRACT_SWEEP_SKIP', 'AVYA_DART_RUN_RETRY'};

/// Stubs on a PATH, /bin symlinks, chmod and `sh`: POSIX only. A Windows (Git Bash) check is the founder's A/B with the kill switch.
final String? _posixOnly = Platform.isWindows ? 'POSIX-only: stub dart/sleep on PATH, /bin links, chmod (the Windows check is the kill-switch A/B)' : null;

void posixGroup(String name, void Function() body) => group(name, body, skip: _posixOnly);

late Directory shared; // stubs shared by every run
var _seq = 0;

const _stubDart = r'''#!/bin/sh
# Stub dart for the hook e2e. argv: run <script> [args]. The FIRST call of each script (counter per script path in
# $STUB_DIR) dies like a lost native-assets race, WITHOUT reading stdin; later calls behave per script basename.
# STUB_FAIL_FIRST lists the basenames that fail first (default ALL).
script=$2
key=$(printf '%s' "$script" | tr '/.' '__')
n=$(( $(cat "$STUB_DIR/$key.n" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$STUB_DIR/$key.n"
echo "$*" >> "$STUB_DIR/calls.log"
base=$(basename "$script")
case " ${STUB_FAIL_FIRST:-ALL} " in
  *" ALL "*|*" $base "*)
    if [ "$n" -le "${STUB_FAIL_N:-1}" ]; then
      printf 'Running build hooks...'
      echo 'File not formatted as yaml: .' >&2
      exit 254
    fi ;;
esac
case "$base" in
  blast_radius_from_diff.dart)
    if [ "${3:-}" = "-" ]; then cat > /dev/null; fi
    [ -z "${TIER_STUB:-}" ] || printf 'Running build hooks...Blast-radius: %s\n' "$TIER_STUB"
    exit 0 ;;
  check_bad.dart)
    i=0; while [ "$i" -lt 80 ]; do echo "bad line $i"; i=$((i+1)); done
    exit 1 ;;
  check_bad2.dart)
    echo "second gate says: DIFFERENT TEXT"; echo "and this one on stderr" >&2
    exit 1 ;;
  check_killed.dart) exit 137 ;;
  check_rc127.dart) exit 127 ;;
  check_rc128.dart) exit 128 ;;
  check_rc129.dart) exit 129 ;;
  check_rc192.dart) exit 192 ;;
  check_rc193.dart) exit 193 ;;
  check_rc254.dart) exit 254 ;;
  check_rc255.dart) exit 255 ;;
  check_noeol.dart) printf 'LAST-no-eol'; exit 1 ;;
  check_long.dart) head -c 5000 /dev/zero | tr '\0' 'x'; echo; exit 1 ;;
  check_long2.dart)
    head -c 5000 /dev/zero | tr '\0' 'x'; echo
    i=2; while [ "$i" -le 69 ]; do echo "mid-$i"; i=$((i + 1)); done
    head -c 5000 /dev/zero | tr '\0' 'x'; echo
    exit 1 ;;
  check_midline.dart)
    printf 'Running build hooks...[dart-run-retry] native-assets race: retry 1 of 2 | scripts/x.dart | exit=254 | stderr=y\n'
    exit 0 ;;
  check_flaky_bad.dart) echo "flaky, then really bad"; exit 1 ;;
  check_unreadable.dart)
    chmod 000 /dev/stdout 2>/dev/null || true
    # record whether the chmod really denied reading (it does not for root): the test needs to know
    if [ -r /dev/stdout ]; then echo yes > "$STUB_DIR/readable_after_chmod"; fi
    echo "this output cannot be read back"
    exit 1 ;;
  check_nul.dart)
    printf 'abc\000def\n[dart-run-retry] native-assets race: retry 1 of 2 | scripts/x.dart | exit=254 | stderr=y\n'
    exit 0 ;;
  check_tokenonly.dart) echo 'the word [dart-run-retry] alone in a gate output'; exit 0 ;;
  check_l100nul.dart)
    i=1; while [ "$i" -le 100 ]; do if [ "$i" -eq 7 ]; then printf 'row\000%s\n' "$i"; else echo "row $i"; fi; i=$((i+1)); done
    exit 1 ;;
  check_l50.dart) i=1; while [ "$i" -le 50 ]; do echo "row $i"; i=$((i+1)); done; exit 1 ;;
  check_l60.dart) i=1; while [ "$i" -le 60 ]; do echo "row $i"; i=$((i+1)); done; exit 1 ;;
  check_l61.dart) i=1; while [ "$i" -le 61 ]; do echo "row $i"; i=$((i+1)); done; exit 1 ;;
  check_l62.dart) i=1; while [ "$i" -le 61 ]; do echo "row $i"; i=$((i+1)); done; printf 'row 62'; exit 1 ;;
  check_cap*.dart) num=${base#check_cap}; echo "cap output ${num%.dart}"; exit 1 ;;
esac
exit 0
''';

class Hooked {
  Hooked(this.id, this.r, this.runDir);
  final int id;
  final ProcessResult r;
  final Directory runDir;
  String get out => '${r.stdout}';
  String get err => '${r.stderr}';
  int get exit => r.exitCode;
  List<String> get calls =>
      File('${runDir.path}/calls.log').existsSync() ? File('${runDir.path}/calls.log').readAsLinesSync() : <String>[];
  int callsOf(String script) => calls.where((c) => c.startsWith('run $script')).length;
  List<String> get sleeps =>
      File('${runDir.path}/sleep.log').existsSync() ? File('${runDir.path}/sleep.log').readAsLinesSync() : <String>[];
}

String _git(Directory repo, List<String> args) {
  final r = runSpawn('git', args,
      why: 'hook e2e fixture: git ${args.join(' ')}',
      workingDirectory: repo.path,
      extraEnv: {'CONTRACT_SWEEP_SKIP': '1'},
      allowControl: _setOnPurpose);
  expect(r.exitCode, 0, reason: 'git ${args.join(' ')}: ${r.stderr}');
  return '${r.stdout}'.trim();
}

/// A throwaway repo holding the verbatim [hooks] and the helper (or [helperText] / [hookTexts] overrides).
Directory makeRepo(
  String prefix, {
  List<String> hooks = const [],
  List<String> gates = const [],
  Map<String, String> files = const {},
  bool commitAhead = false,
  String? helperText,
  Map<String, String> hookTexts = const {},
}) {
  final repo = Directory.systemTemp.createTempSync(prefix);
  _git(repo, ['init', '--quiet']);
  _git(repo, ['config', 'user.email', 'test@example.com']);
  _git(repo, ['config', 'user.name', 'test']);
  File('${repo.path}/seed.txt').writeAsStringSync('seed\n');
  _git(repo, ['add', '-A']);
  _git(repo, ['commit', '--quiet', '--no-verify', '-m', 'seed']);
  _git(repo, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
  if (commitAhead) {
    Directory('${repo.path}/docs').createSync();
    File('${repo.path}/docs/note.md').writeAsStringSync('note\n');
    _git(repo, ['add', '-A']);
    _git(repo, ['commit', '--quiet', '--no-verify', '-m', 'docs: note']);
  }
  Directory('${repo.path}/scripts').createSync();
  File('${repo.path}/scripts/_dart_bin.sh')
      .writeAsStringSync(helperText ?? File('scripts/_dart_bin.sh').readAsStringSync());
  for (final h in hooks) {
    File('${repo.path}/scripts/$h.sh').writeAsStringSync(hookTexts[h] ?? File('scripts/$h.sh').readAsStringSync());
  }
  for (final g in gates) {
    File('${repo.path}/scripts/$g').writeAsStringSync('// stub gate; the stub dart decides what it does\n');
  }
  files.forEach((path, content) {
    final f = File('${repo.path}/$path')..createSync(recursive: true);
    f.writeAsStringSync(content);
  });
  return repo;
}

/// Runs [command] (a literal such as `sh scripts/pre-push.sh`, so the recursion detector in
/// spawn_env_manifest_test.dart can SEE that this file executes the real pre-push hook) with [args] in [repo],
/// the stub dart first on PATH.
Hooked runHook(
  Directory repo,
  String command,
  List<String> args, {
  Map<String, String> env = const {},
  String? stdinText,
  bool switchOff = false,
}) {
  final id = _seq++;
  final runDir = Directory('${shared.path}/run$id')..createSync();
  final stdinFile = File('${runDir.path}/stdin.txt')..writeAsStringSync(stdinText ?? '');
  final r = runSpawn(
    'sh',
    [
      '-c',
      'PATH="\$SHARED/bin:\$PATH"; export PATH; '
          'exec $command ${args.map((a) => "'$a'").join(' ')} < "${stdinFile.path}"',
    ],
    why: 'hook e2e: $command ${switchOff ? '(switch off)' : ''}',
    workingDirectory: repo.path,
    extraEnv: {
      'SHARED': shared.path,
      'STUB_DIR': runDir.path,
      'CONTRACT_SWEEP_SKIP': '1',
      if (switchOff) 'AVYA_DART_RUN_RETRY': '0',
      ...env,
    },
    allowControl: _setOnPurpose,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return Hooked(id, r, runDir);
}

void main() {
  setUpAll(() {
    shared = Directory.systemTemp.createTempSync('hooks_retry_e2e_');
    Directory('${shared.path}/bin').createSync();
    File('${shared.path}/bin/dart').writeAsStringSync(_stubDart);
    File('${shared.path}/bin/sleep').writeAsStringSync('#!/bin/sh\necho "\$1" >> "\$STUB_DIR/sleep.log"\n');
    File('${shared.path}/bin/flutter').writeAsStringSync('#!/bin/sh\necho "\$1" >> "\$STUB_DIR/flutter.log"\nexit 0\n');
    expect(
        runSpawn('chmod', ['+x', '${shared.path}/bin/dart', '${shared.path}/bin/sleep', '${shared.path}/bin/flutter'],
                why: 'hook e2e: make the stubs executable')
            .exitCode,
        0);
  });
  tearDownAll(() {
    try {
      shared.deleteSync(recursive: true);
    } catch (_) {}
  });

  posixGroup('pre-merge-commit', () {
    late Directory repo;
    setUpAll(() => repo = makeRepo('hk_pmc_',
        hooks: ['pre-merge-commit'], files: {'.gitignore': 'docs/audit/OPEN_INDEX.md\n'}));
    tearDownAll(() => repo.deleteSync(recursive: true));

    test('a lost race at the board build and the numbering gate is retried: the merge passes', () {
      final h = runHook(repo, 'sh scripts/pre-merge-commit.sh', const []);
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect(h.out, contains('[pre-merge-commit] OK'));
      expect(h.callsOf('scripts/build_oi_index.dart'), 2);
      expect(h.callsOf('scripts/check_oi_numbering_unique.dart'), 2);
      expect(h.sleeps, ['1', '1'], reason: 'one backoff per retried script');
    });

    test('SWITCH OFF: today\'s call loses the same race and the merge is rejected', () {
      final h = runHook(repo, 'sh scripts/pre-merge-commit.sh', const [], switchOff: true);
      expect(h.exit, 1);
      expect(h.err, contains('the merged OI board did not validate'));
      expect(h.callsOf('scripts/build_oi_index.dart'), 1);
      expect(h.sleeps, isEmpty);
    });
  });

  posixGroup('commit-msg', () {
    late Directory repo;
    late String feat;
    late String fix;
    setUpAll(() {
      repo = makeRepo('hk_cm_', hooks: ['commit-msg'], files: {
        'docs/diagnoses/2026-01-01-thing-abc123.md': '---\nid: abc123\n---\n',
      });
      feat = '${repo.path}/MSG_FEAT';
      fix = '${repo.path}/MSG_FIX';
      File(feat).writeAsStringSync('feat: a thing\n\nbody\n');
      File(fix).writeAsStringSync('fix(a): a thing\n\nbody\n\ncloses-diagnose: abc123\n');
    });
    tearDownAll(() => repo.deleteSync(recursive: true));

    test('a lost race at check_closes_oi_cited is retried: the commit is accepted', () {
      final h = runHook(repo, 'sh scripts/commit-msg.sh', [feat]);
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect(h.callsOf('scripts/check_closes_oi_cited.dart'), 2);
    });

    test('a lost race inside the SILENT diagnose validation is retried: OK, not "does not validate"', () {
      final h = runHook(repo, 'sh scripts/commit-msg.sh', [fix]);
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect(h.out, contains('OK: docs/diagnoses/2026-01-01-thing-abc123.md validates'));
      expect(h.callsOf('scripts/validate_diagnose_doc.dart'), 2);
    });

    test('SWITCH OFF: today\'s call rejects the same commits', () {
      final a = runHook(repo, 'sh scripts/commit-msg.sh', [feat], switchOff: true);
      expect(a.exit, 1);
      final b = runHook(repo, 'sh scripts/commit-msg.sh', [fix], switchOff: true, env: {'STUB_FAIL_FIRST': 'validate_diagnose_doc.dart'});
      expect(b.exit, 1);
      expect(b.out, contains('does not validate'));
    });
  });

  posixGroup('prepare-commit-msg (bash)', () {
    late Directory repo;
    setUpAll(() => repo = makeRepo('hk_pcm_', hooks: ['prepare-commit-msg']));
    tearDownAll(() => repo.deleteSync(recursive: true));

    String msg(String id) {
      final f = '${repo.path}/MSG_$id';
      File(f).writeAsStringSync('subject\n\nbody\n');
      return f;
    }

    test('a lost race no longer silently drops the Blast-radius line', () {
      final f = msg('retry');
      final h = runHook(repo, 'bash scripts/prepare-commit-msg.sh', [f, ''], env: {'TIER_STUB': 'platform'});
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect(File(f).readAsStringSync(), contains('Blast-radius: platform'));
      expect(h.callsOf('scripts/blast_radius_from_diff.dart'), 2);
    });

    test('SWITCH OFF: today\'s call drops the line without a word (stderr is /dev/null there)', () {
      final f = msg('off');
      final h = runHook(repo, 'bash scripts/prepare-commit-msg.sh', [f, ''],
          env: {'TIER_STUB': 'platform'}, switchOff: true);
      expect(h.exit, 0);
      expect(File(f).readAsStringSync(), isNot(contains('Blast-radius')));
      expect(h.out + h.err, isNot(contains('dart-run-retry')), reason: 'silent by design');
    });
  });

  posixGroup('pre-push', () {
    late Directory repo;
    final zeros = '0' * 40;
    final sha = 'a' * 40;
    final refs = 'refs/heads/oi482 $sha refs/heads/oi482 $zeros\n';
    setUpAll(() => repo = makeRepo('hk_pp_', hooks: ['pre-push'], commitAhead: true));
    tearDownAll(() => repo.deleteSync(recursive: true));

    List<String> flutterCalls(Hooked h) => File('${h.runDir.path}/flutter.log').existsSync()
        ? File('${h.runDir.path}/flutter.log').readAsLinesSync()
        : <String>[];

    test('the tier pipeline survives a lost race: its stdin reaches the retry and the branch push skips the suite', () {
      final h = runHook(repo, 'sh scripts/pre-push.sh', const [], stdinText: refs, env: {'TIER_STUB': 'platform'});
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect(h.out, contains('blast-radius=platform on a branch push'));
      expect(flutterCalls(h), ['analyze'], reason: 'the local suite is SKIPPED');
      expect(h.callsOf('scripts/blast_radius_from_diff.dart'), 2);
      expect(h.callsOf('scripts/contract_sweep.dart'), 2);
    });

    test('SWITCH OFF: today\'s call loses the race, the tier is empty, and the hook falls into the full suite', () {
      final h = runHook(repo, 'sh scripts/pre-push.sh', const [], stdinText: refs, env: {'TIER_STUB': 'platform'}, switchOff: true);
      expect(flutterCalls(h), contains('test'), reason: 'the fail-safe: unknown tier runs everything');
      expect(h.callsOf('scripts/blast_radius_from_diff.dart'), 1);
    });
  });

  posixGroup('pre-commit: the explicit runs and the parallel gate loop', () {
    Directory tmpDirFor(String id) => Directory('${shared.path}/tmp_$id')..createSync();
    bool empty(Directory d) => d.listSync().isEmpty;

    test('a clean tree: every gate and every explicit run loses the race once and passes; notes are shown; no temp dir leaks', () {
      final repo = makeRepo('hk_pc_ok_', hooks: ['pre-commit'], gates: ['check_a.dart', 'check_b.dart']);
      addTearDown(() => repo.deleteSync(recursive: true));
      final t = tmpDirFor('ok');
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'TMPDIR': t.path});
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect(h.out, contains('[pre-commit] All decluttering gates passed.'));
      expect(h.out, contains('NOTE: check_a.dart needed a native-assets retry: [dart-run-retry]'));
      expect(h.out, contains('NOTE: check_b.dart needed a native-assets retry: [dart-run-retry]'));
      expect(h.callsOf('scripts/check_a.dart'), 2);
      expect(h.callsOf('scripts/validate_audit_closure.dart'), 2, reason: 'an explicit (non-loop) site retries too');
      expect(empty(t), isTrue, reason: 'both temp dirs are removed on the pass path: ${t.listSync()}');
    });

    test('a gate that loses the race TWICE shows BOTH notes (every note, not the first)', () {
      final repo = makeRepo('hk_pc_two_', hooks: ['pre-commit'], gates: ['check_a.dart']);
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'STUB_FAIL_N': '2'});
      expect(h.exit, 0, reason: '${h.out}|${h.err}');
      expect('NOTE: check_a.dart needed a native-assets retry'.allMatches(h.out).length, 2);
      expect(h.out, contains('retry 1 of 2'));
      expect(h.out, contains('retry 2 of 2'));
      expect(h.callsOf('scripts/check_a.dart'), 3);
    });

    /// The text of one gate's printed block: from its `output` header up to its `exited` line.
    String blockOf(String out, String gate) {
      final start = out.indexOf('--- $gate output ---');
      expect(start, isNonNegative, reason: '$gate has an output block');
      final end = out.indexOf('--- $gate exited', start);
      expect(end, greaterThan(start), reason: '$gate has an exit line after its block');
      return out.substring(start, end);
    }

    test('failing gates: their output is PRINTED (head+tail of a long one), attributed correctly, with exit status, '
        'a KILLED gate gets its own sentence and still blocks, and the GATE FAIL lines come after the output blocks', () {
      final gates = [
        'check_ok.dart', 'check_bad.dart', 'check_bad2.dart', 'check_killed.dart', 'check_flaky_bad.dart',
        'check_noeol.dart', 'check_long.dart', 'check_long2.dart', 'check_midline.dart', 'check_nul.dart', 'check_tokenonly.dart',
      ];
      final repo = makeRepo('hk_pc_bad_', hooks: ['pre-commit'], gates: gates);
      addTearDown(() => repo.deleteSync(recursive: true));
      final t = tmpDirFor('bad');
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'TMPDIR': t.path, 'STUB_FAIL_FIRST': 'check_ok.dart check_flaky_bad.dart'});
      expect(h.exit, 1, reason: '${h.out}|${h.err}');
      final out = h.out;
      // attribution
      expect(out, contains('--- check_bad.dart output ---'));
      expect(out, contains('--- check_bad2.dart output ---'));
      final bad2 = blockOf(out, 'check_bad2.dart');
      expect(bad2, contains('second gate says: DIFFERENT TEXT'));
      expect(bad2, isNot(contains('bad line')));
      // long output: first 20 and last 30 of 80 lines, the middle omitted, the count right IN THAT BLOCK
      final bad = blockOf(out, 'check_bad.dart');
      expect(bad, contains('bad line 0\n'));
      expect(bad, contains('bad line 19\n'));
      expect(bad, isNot(contains('bad line 20\n')));
      expect(bad, contains('bad line 79'));
      expect(bad, contains('bad line 50\n'));
      expect(bad, isNot(contains('bad line 49\n')));
      expect(bad, contains('... 30 lines omitted ...'));
      expect(blockOf(out, 'check_long2.dart'), contains('... 20 lines omitted ...'));
      // exit statuses and the killed-gate sentence
      expect(out, contains('--- check_bad.dart exited 1 ---'));
      expect(out, contains('--- check_killed.dart exited 137 ---'));
      expect(out, contains('check_killed.dart was KILLED by signal 9'));
      expect(out, isNot(contains('check_bad.dart was KILLED')));
      // an output without a trailing newline does not glue to the next header; one huge line is cut at 2000
      expect(out, contains('LAST-no-eol\n[pre-commit] --- check_noeol.dart exited 1 ---'));
      expect(RegExp('x{2001}').hasMatch(out), isFalse, reason: 'a printed line is capped at 2000 characters');
      // three capped lines: the single long line (whole-output branch) and the first and last of the 70-line output (head and tail branches)
      expect(RegExp('x{2000}').allMatches(out).length, 3);
      expect(out, contains('mid-69'), reason: 'the 70-line output is cut head 20 / tail 30, so its last 30 lines are printed');
      expect(out, isNot(contains('mid-25')), reason: 'and its middle is omitted');
      // a note that follows other text on the same line is still found (the grep is unanchored)
      expect(out, contains('NOTE: check_midline.dart needed a native-assets retry: [dart-run-retry] native-assets race: retry 1 of 2'));
      // ... and so is one in an output that holds a NUL byte (grep -a: without it grep calls the file binary and says nothing)
      expect(out, contains('NOTE: check_nul.dart needed a native-assets retry: [dart-run-retry] native-assets race: retry 1 of 2'));
      // the bare token without the full phrase is not a retry note
      expect(out, isNot(contains('NOTE: check_tokenonly.dart')));
      // a passing gate prints no output block
      expect(out, isNot(contains('--- check_ok.dart output ---')));
      // a retried-but-passing gate shows its note; a retried-then-failed gate shows its note AND its output
      expect(out, contains('NOTE: check_ok.dart needed a native-assets retry'));
      expect(out, contains('NOTE: check_flaky_bad.dart needed a native-assets retry'));
      expect(out, contains('flaky, then really bad'));
      // every failing gate is still reported and the verdict stands
      for (final g in ['check_bad', 'check_bad2', 'check_killed', 'check_flaky_bad', 'check_noeol', 'check_long', 'check_long2']) {
        expect(out, contains('GATE FAIL: $g.dart'), reason: g);
      }
      for (final g in ['check_ok', 'check_midline', 'check_nul', 'check_tokenonly']) {
        expect(out, isNot(contains('GATE FAIL: $g.dart')), reason: 'a passing gate with a note is not a failed gate: $g');
      }
      expect(out, contains('One or more gates failed'));
      // order: the diagnostics come BEFORE the first GATE FAIL line
      expect(out.indexOf('--- check_bad.dart output ---'), lessThan(out.indexOf('GATE FAIL:')));
      expect(out.indexOf('NOTE: check_ok.dart'), lessThan(out.indexOf('GATE FAIL:')));
      expect(empty(t), isTrue, reason: 'both temp dirs are removed on the fail path too: ${t.listSync()}');
    });

    test('exit statuses: 129..192 is a death by signal, 254 has its own sentence, 127/128/193/255 get neither; every one still blocks', () {
      final gates = [
        'check_ok.dart', 'check_rc127.dart', 'check_rc128.dart', 'check_rc129.dart', 'check_rc192.dart', 'check_rc193.dart',
        'check_rc254.dart', 'check_rc255.dart',
      ];
      final repo = makeRepo('hk_pc_rc_', hooks: ['pre-commit'], gates: gates);
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'STUB_FAIL_FIRST': 'NONE'});
      expect(h.exit, 1, reason: '${h.out}|${h.err}');
      final out = h.out;
      // the boundary: 128 is not a signal death (128+N, N>=1); 129 is signal 1; 127 is "command not found"
      expect(out, contains('--- check_rc127.dart exited 127 ---'));
      expect(out, isNot(contains('check_rc127.dart was KILLED')));
      expect(out, contains('--- check_rc128.dart exited 128 ---'));
      expect(out, isNot(contains('check_rc128.dart was KILLED')));
      expect(out, contains('check_rc129.dart was KILLED by signal 1'));
      expect(out, contains('check_rc192.dart was KILLED by signal 64'));
      expect(out, isNot(contains('check_rc193.dart was KILLED')), reason: 'above 192 is not a signal death');
      expect(out, contains('--- check_rc193.dart exited 193 ---'));
      // 254 and 255 are Dart's own statuses: 254 gets its own sentence, 255 neither
      expect(out, contains('check_rc254.dart exited 254: the Dart front end could not load the gate'));
      expect(out, isNot(contains('check_rc254.dart was KILLED')));
      expect(out, contains('--- check_rc255.dart exited 255 ---'));
      expect(out, isNot(contains('check_rc255.dart was KILLED')));
      expect(out, isNot(contains('check_rc255.dart exited 254')));
      for (final g in ['check_rc127', 'check_rc128', 'check_rc129', 'check_rc192', 'check_rc193', 'check_rc254', 'check_rc255']) {
        expect(out, contains('GATE FAIL: $g.dart'), reason: g);
      }
    });

    test('the 60-line boundary and the omitted count: 50 and 60 lines print whole, 61 prints 20 + 30 and says 11, an unterminated 62nd line counts', () {
      final gates = ['check_l50.dart', 'check_l60.dart', 'check_l61.dart', 'check_l62.dart', 'check_l100nul.dart'];
      final repo = makeRepo('hk_pc_lines_', hooks: ['pre-commit'], gates: gates);
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'STUB_FAIL_FIRST': 'NONE'});
      expect(h.exit, 1, reason: '${h.out}|${h.err}');
      final out = h.out;
      for (final g in ['check_l50.dart', 'check_l60.dart']) {
        final b = blockOf(out, g);
        expect(b, isNot(contains('omitted')), reason: '$g prints whole');
        expect(b, contains('row 1\n'), reason: g);
        expect(b, contains(g == 'check_l50.dart' ? 'row 50\n' : 'row 60\n'), reason: g);
      }
      final l61 = blockOf(out, 'check_l61.dart');
      expect(l61, contains('row 20\n'));
      expect(l61, isNot(contains('row 21\n')));
      expect(l61, contains('... 11 lines omitted ...'));
      expect(l61, isNot(contains('row 31\n')));
      expect(l61, contains('row 32\n'));
      expect(l61, contains('row 61\n'));
      final l62 = blockOf(out, 'check_l62.dart');
      expect(l62, contains('... 12 lines omitted ...'), reason: 'wc -l would say 11: it does not count an unterminated last line');
      expect(l62, contains('row 62\n'));
      expect(blockOf(out, 'check_l100nul.dart'), contains('... 50 lines omitted ...'), reason: 'a NUL byte must not count a line twice (grep without -a says 101 lines)');
    });

    test('a broken shared library: only the first 8 failing gates print their output, the rest keep their status line and their GATE FAIL', () {
      final gates = [for (var i = 1; i <= 11; i++) 'check_cap${i.toString().padLeft(2, '0')}.dart'];
      final repo = makeRepo('hk_pc_cap_', hooks: ['pre-commit'], gates: gates);
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'STUB_FAIL_FIRST': 'NONE'});
      expect(h.exit, 1, reason: '${h.out}|${h.err}');
      final out = h.out;
      for (var i = 1; i <= 8; i++) {
        final n = i.toString().padLeft(2, '0');
        expect(out, contains('--- check_cap$n.dart output ---'), reason: n);
        expect(out, contains('cap output $n\n'), reason: n);
      }
      for (var i = 9; i <= 11; i++) {
        final n = i.toString().padLeft(2, '0');
        expect(out, contains('--- check_cap$n.dart output not printed (the first 8 failing gates printed theirs) ---'), reason: n);
        expect(out, isNot(contains('cap output $n')), reason: n);
        expect(out, contains('--- check_cap$n.dart exited 1 ---'), reason: n);
      }
      for (var i = 1; i <= 11; i++) {
        expect(out, contains('GATE FAIL: check_cap${i.toString().padLeft(2, '0')}.dart'));
      }
    });

    test('an output the loop cannot read back (mode 000): the gate still blocks and the loop prints no arithmetic noise', () {
      final repo = makeRepo('hk_pc_unr_', hooks: ['pre-commit'], gates: ['check_unreadable.dart', 'check_midline.dart']);
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], env: {'STUB_FAIL_FIRST': 'NONE'});
      expect(h.exit, 1, reason: '${h.out}|${h.err}');
      expect(h.out, contains('GATE FAIL: check_unreadable.dart'));
      expect(h.out, contains('--- check_unreadable.dart exited 1 ---'));
      // the retry note of a PASSING sibling survives an unreadable output (grep -l exits 2 when any listed file is unreadable)
      expect(h.out, contains('NOTE: check_midline.dart needed a native-assets retry'));
      if (File('${h.runDir.path}/readable_after_chmod').existsSync()) {
        // root (or a platform where /dev/stdout is not the output file): chmod 000 did not deny the read, so the
        // noise assertions below would prove nothing. Say so instead of passing silently.
        markTestSkipped('chmod 000 does not deny reading here (root?): the unreadable-output assertions need a denied read');
        return;
      }
      expect(h.out, isNot(contains('-50 lines omitted')), reason: 'an unreadable line count must fall back to the whole-output branch');
      expect(h.err, isNot(contains('Illegal number')));
      expect(h.err, isNot(contains('integer expression expected')));
    });

    test('SWITCH OFF: a gate that loses the race once is a failed gate again (today\'s call)', () {
      final repo = makeRepo('hk_pc_off_', hooks: ['pre-commit'], gates: ['check_ok.dart']);
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-commit.sh', const [], switchOff: true, env: {'STUB_FAIL_FIRST': 'check_ok.dart'});
      expect(h.exit, 1);
      expect(h.out, contains('GATE FAIL: check_ok.dart'));
      expect(h.out, contains('File not formatted as yaml'), reason: 'the output is shown now even for a lost race');
      expect(h.out, isNot(contains('needed a native-assets retry')));
      expect(h.callsOf('scripts/check_ok.dart'), 1);
    });
  });

  posixGroup('D5: the installed-copy matrix', () {
    final oldHookText = File('test/scripts/fixtures/pre_oi482_hooks/pre-merge-commit.sh.txt').readAsStringSync();
    final oldHelperText = File('test/scripts/fixtures/pre_oi482_hooks/_dart_bin.sh.txt').readAsStringSync();

    test('NEW hook + a helper whose use_dart_race_retry RETURNS 1: the hook line must not abort the hook', () {
      final repo = makeRepo('hk_ret1_',
          hooks: ['pre-merge-commit'],
          helperText: '$oldHelperText\nuse_dart_race_retry() { return 1; }\n',
          files: {'.gitignore': 'docs/audit/OPEN_INDEX.md\n'});
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-merge-commit.sh', const [], env: {'STUB_FAIL_FIRST': 'NONE'});
      expect(h.exit, 0, reason: 'the `|| true` is what survives a future function that fails: ${h.out}|${h.err}');
    });

    test('the frozen fixtures are what origin/main had: the old hook has no retry line, the old helper no function', () {
      expect(oldHookText, isNot(contains('use_dart_race_retry')));
      expect(oldHelperText, isNot(contains('_dart_run_retrying')));
    });

    test('OLD hook copy + NEW helper: the old copy never calls the function and behaves as today (the race is not retried)', () {
      final repo = makeRepo('hk_old_hook_',
          hooks: ['pre-merge-commit'],
          hookTexts: {'pre-merge-commit': oldHookText},
          files: {'.gitignore': 'docs/audit/OPEN_INDEX.md\n'});
      addTearDown(() => repo.deleteSync(recursive: true));
      final h = runHook(repo, 'sh scripts/pre-merge-commit.sh', const []);
      expect(h.exit, 1, reason: 'no retry without the hook line: ${h.out}|${h.err}');
      expect(h.callsOf('scripts/build_oi_index.dart'), 1);
    });

    test('NEW hook + OLD helper (a tree that predates the functions): the guard makes the new line a no-op, nothing wedges', () {
      final repo = makeRepo('hk_old_helper_',
          hooks: ['pre-merge-commit'],
          helperText: oldHelperText,
          files: {'.gitignore': 'docs/audit/OPEN_INDEX.md\n'});
      addTearDown(() => repo.deleteSync(recursive: true));
      final ok = runHook(repo, 'sh scripts/pre-merge-commit.sh', const [], env: {'STUB_FAIL_FIRST': 'NONE'});
      expect(ok.exit, 0, reason: 'the new hook still works on an old tree: ${ok.out}|${ok.err}');
      expect(ok.err, isNot(contains('not found')), reason: 'the `type` guard keeps the new line silent on an old helper');
      final lost = runHook(repo, 'sh scripts/pre-merge-commit.sh', const []);
      expect(lost.exit, 1, reason: 'and behaves exactly as today when the race is lost');
    });
  });
}
