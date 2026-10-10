// test/scripts/safe_pr_merge_e2e_test.dart
//
// END-TO-END for scripts/safe_pr_merge.dart: the REAL program is run with a FAKE
// `gh` (a POSIX shell script passed through the test-only `--gh` flag; a PATH
// stub cannot work on Windows because Process.run resolves gh.exe, not an
// extensionless script). It proves the wiring the pure-lib test cannot:
//   - the merge command is issued ONLY after the checks pass, with
//     `--match-head-commit <sha>`;
//   - every failure to READ (gh api exits non-zero, PR unreadable) is a REFUSAL
//     with NO `pr merge` call -- the fail-closed contract;
//   - a head that moves between the first and second PR read is refused.
// The "no merge call" assertions read the fake gh's call log, so a program that
// printed "refused" but still merged would fail.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

String _posix(String p) {
  var s = p.replaceAll('\\', '/');
  final m = RegExp(r'^([A-Za-z]):/').firstMatch(s);
  if (m != null) s = '/${m.group(1)!.toLowerCase()}/${s.substring(3)}';
  return s;
}

final String _sha = 'c' * 40;
final String _sha2 = 'd' * 40;

void main() {
  late Directory tmp;
  late File fakeGh;
  late File green;
  late File red;
  var seq = 0;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('safe_pr_merge_e2e_');
    green = File('test/scripts/fixtures/safe_pr_merge_pr96_check_runs.json').absolute;
    // A copy with Unit Tests failed.
    red = File('${tmp.path}/red.json')
      ..writeAsStringSync(green.readAsStringSync().replaceFirstMapped(
          RegExp(r'("name": "Unit Tests",[\s\S]*?"conclusion": )"success"'),
          (m) => '${m.group(1)}"failure"'));
    expect(red.readAsStringSync(), isNot(green.readAsStringSync()), reason: 'red fixture must differ');

    fakeGh = File('${tmp.path}/fake_gh.sh')
      ..writeAsStringSync(r'''#!/bin/sh
echo "$@" >> "$GH_LOG"
case "$1" in
  repo) echo '{"nameWithOwner":"o/r"}' ;;
  pr)
    case "$2" in
      view)
        n=$(cat "$GH_COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$GH_COUNT"
        sha="$PR_SHA"; if [ "$n" -ge 2 ] && [ -n "$PR_SHA_SECOND" ]; then sha="$PR_SHA_SECOND"; fi
        state="${PR_STATE:-OPEN}"; if [ "$n" -ge 3 ]; then state="${PR_STATE_AFTER:-MERGED}"; fi
        printf '{"state":"%s","isDraft":%s,"headRefOid":"%s","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","baseRefName":"%s"}\n' "$state" "${PR_DRAFT:-false}" "$sha" "${PR_BASE:-main}"
        ;;
      merge)
        if [ -n "$MERGE_FAIL" ]; then echo "$MERGE_FAIL" >&2; exit 1; fi
        echo "Merged"
        ;;
    esac
    ;;
  api)
    case "$2" in
      */files)
        if [ -n "$FILES_FAIL" ]; then echo "HTTP 502" >&2; exit 1; fi
        if [ -n "$FILES_JSON" ]; then echo "$FILES_JSON"; else echo '[{"filename":"lib/a.dart"}]'; fi
        ;;
      *)
        if [ -n "$API_FAIL" ]; then echo "HTTP 502" >&2; exit 1; fi
        cat "$CHECKS_FILE"
        ;;
    esac
    ;;
esac
''');
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ({int code, String out, String err, List<String> calls}) run(
    List<String> args, {
    File? checks,
    Map<String, String> env = const {},
  }) {
    final id = seq++;
    final log = File('${tmp.path}/calls_$id.log')..writeAsStringSync('');
    final count = File('${tmp.path}/count_$id.txt');
    final r = runSpawn(
      dartBin(),
      ['scripts/safe_pr_merge.dart', ...args, '--gh', 'sh ${_posix(fakeGh.path)}'],
      why: 'safe_pr_merge.dart with a fake gh, args=$args env=$env',
      extraEnv: {
        'GH_LOG': _posix(log.path),
        'GH_COUNT': _posix(count.path),
        'CHECKS_FILE': _posix((checks ?? green).path),
        'PR_SHA': _sha,
        ...env,
      },
    );
    final calls = log.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    return (code: r.exitCode, out: r.stdout.toString(), err: r.stderr.toString(), calls: calls);
  }

  bool merged(List<String> calls) => calls.any((c) => c.startsWith('pr merge'));

  test('all green: merges with --merge --match-head-commit <sha>', () {
    final r = run(['96']);
    expect(r.code, 0, reason: 'out:\n${r.out}\nerr:\n${r.err}');
    expect(r.calls, contains('pr merge 96 --merge --match-head-commit $_sha'));
    expect(r.out, contains('merged PR #96'));
    // the check-runs were read for the head SHA, paginated
    expect(r.calls, contains('api repos/o/r/commits/$_sha/check-runs --paginate'));
  });

  test('--dry-run evaluates but never merges', () {
    final r = run(['96', '--dry-run']);
    expect(r.code, 0, reason: r.err);
    expect(merged(r.calls), isFalse);
    expect(r.out, contains('--dry-run'));
  });

  test('a failed required job: refused, exit 1, NO merge call, reason names the job', () {
    final r = run(['96'], checks: red);
    expect(r.code, 1);
    expect(merged(r.calls), isFalse, reason: 'calls: ${r.calls}');
    expect(r.err, contains('REFUSED'));
    expect(r.err, contains('"Unit Tests"'));
  });

  test('gh api failing (network/auth) FAILS CLOSED: no merge', () {
    final r = run(['96'], env: {'API_FAIL': '1'});
    expect(r.code, 1);
    expect(merged(r.calls), isFalse, reason: 'calls: ${r.calls}');
    expect(r.err, contains('REFUSED'));
  });

  test('a draft PR is refused', () {
    final r = run(['96'], env: {'PR_DRAFT': 'true'});
    expect(r.code, 1);
    expect(merged(r.calls), isFalse);
    expect(r.err, contains('draft'));
  });

  test('a PR that is no longer OPEN is refused', () {
    final r = run(['96'], env: {'PR_STATE': 'MERGED'});
    expect(r.code, 1);
    expect(merged(r.calls), isFalse);
  });

  test('the head moving between the two PR reads is refused', () {
    final r = run(['96'], env: {'PR_SHA_SECOND': _sha2});
    expect(r.code, 1);
    expect(merged(r.calls), isFalse, reason: 'calls: ${r.calls}');
    expect(r.err, contains('head moved'));
  });

  test('a merge that gh itself rejects is reported, with the conversation hint', () {
    final r = run(['96'], env: {'MERGE_FAIL': 'Pull request has unresolved conversation threads'});
    expect(r.code, 1);
    expect(r.err, contains('required_conversation_resolution'));
  });

  test('a PR into a branch other than main/develop is refused (CI does not run for it)', () {
    final r = run(['96'], env: {'PR_BASE': 'release'});
    expect(r.code, 1);
    expect(merged(r.calls), isFalse);
    expect(r.err, contains('not main/develop'));
  });

  test('a PR that edits .github/ is refused without the acknowledgement flag, merged with it', () {
    const files = '[{"filename":"lib/a.dart"},{"filename":".github/workflows/test.yml"}]';
    final refused = run(['96'], env: {'FILES_JSON': files});
    expect(refused.code, 1);
    expect(merged(refused.calls), isFalse, reason: 'calls: ${refused.calls}');
    expect(refused.err, contains('.github/workflows/test.yml'));
    expect(refused.err, contains('--allow-workflow-change'));

    final allowed = run(['96', '--allow-workflow-change'], env: {'FILES_JSON': files});
    expect(allowed.code, 0, reason: 'out:\n${allowed.out}\nerr:\n${allowed.err}');
    expect(merged(allowed.calls), isTrue);
    expect(allowed.out, contains('WARNING'));
  });

  test('an unreadable changed-files list FAILS CLOSED', () {
    final r = run(['96'], env: {'FILES_FAIL': '1'});
    expect(r.code, 1);
    expect(merged(r.calls), isFalse);
    expect(r.err, contains('changed files'));
  });

  test('gh pr merge exiting 0 while the PR is NOT merged is UNVERIFIED (exit 2), never "merged"', () {
    final r = run(['96'], env: {'PR_STATE_AFTER': 'OPEN'});
    expect(r.code, 2, reason: 'out:\n${r.out}\nerr:\n${r.err}');
    expect(r.err, contains('UNVERIFIED'));
    expect(r.out, isNot(contains('state read back')));
  });

  test('the sh entry point hands the PR number to the Dart program (not just its own arg check)', () {
    // 'abc' is exactly one argument, so it passes the sh wrapper's own count check
    // and reaches the Dart program, which is what rejects it. A typo in the exec
    // line (wrong script name, dropped "$1") would not produce this message.
    final r = runSpawn('sh', ['scripts/safe_pr_merge.sh', 'abc'],
        why: 'safe_pr_merge.sh hand-off to safe_pr_merge.dart');
    expect(r.exitCode, 2, reason: 'out:\n${r.stdout}\nerr:\n${r.stderr}');
    expect(r.stderr.toString(), contains('unexpected argument "abc"'));
  });

  test('the sh entry point forwards EXACTLY the PR number (and the one literal flag) to the Dart program', () {
    // A verbatim COPY of the wrapper in a scratch git repo with a stub `dart` on
    // PATH that records what it was called with. No _dart_bin.sh is copied, so the
    // wrapper falls back to a bare `dart` and the stub is what runs.
    final repo = Directory('${tmp.path}/sh_fwd')..createSync();
    runSpawn('git', ['init', '--quiet'], why: 'safe_pr_merge.sh forwarding fixture', workingDirectory: repo.path);
    Directory('${repo.path}/scripts').createSync();
    File('scripts/safe_pr_merge.sh').copySync('${repo.path}/scripts/safe_pr_merge.sh');
    final stubDir = Directory('${tmp.path}/sh_fwd_bin')..createSync();
    final log = File('${tmp.path}/sh_fwd.log')..writeAsStringSync('');
    File('${stubDir.path}/dart').writeAsStringSync('#!/bin/sh\necho "\$*" >> "\$FWD_LOG"\nexit 0\n');
    runSpawn('chmod', ['+x', '${stubDir.path}/dart'], why: 'safe_pr_merge.sh forwarding fixture: chmod stub dart');

    List<String> forwarded(List<String> args) {
      log.writeAsStringSync('');
      final r = runSpawn(
        'sh',
        [
          '-c',
          'PATH="${_posix(stubDir.path)}:\$PATH"; export PATH; exec sh scripts/safe_pr_merge.sh ${args.join(' ')}',
        ],
        why: 'safe_pr_merge.sh copy with stub dart, args=$args',
        workingDirectory: repo.path,
        extraEnv: {'FWD_LOG': _posix(log.path)},
      );
      expect(r.exitCode, 0, reason: 'args=$args out:\n${r.stdout}\nerr:\n${r.stderr}');
      return log.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
    }

    expect(forwarded(['96']), ['scripts/safe_pr_merge.dart 96']);
    expect(forwarded(['96', '--allow-workflow-change']),
        ['scripts/safe_pr_merge.dart 96 --allow-workflow-change']);
  });

  test('the sh entry point forwards ONLY the literal --allow-workflow-change as a second argument', () {
    for (final extra in ['--gh', '--dry-run', 'true']) {
      final r = runSpawn('sh', ['scripts/safe_pr_merge.sh', '96', extra],
          why: 'safe_pr_merge.sh must not forward arbitrary second argument $extra');
      expect(r.exitCode, 2, reason: 'extra=$extra out:\n${r.stdout}\nerr:\n${r.stderr}');
      expect(r.stderr.toString(), contains('usage'));
    }
  });

  test('a non-numeric or missing PR number is a usage error (exit 2), gh untouched', () {
    for (final args in [<String>[], ['abc'], ['96; rm -rf /'], ['96', '97']]) {
      final r = run(args);
      expect(r.code, 2, reason: 'args=$args out:\n${r.out}\nerr:\n${r.err}');
      expect(r.calls, isEmpty, reason: 'args=$args made gh calls: ${r.calls}');
    }
  });

  test('the sh entry point forwards exactly one argument (the test-only --gh flag is unreachable)', () {
    final r = runSpawn('sh', ['scripts/safe_pr_merge.sh', '96', '--gh', 'true'],
        why: 'safe_pr_merge.sh with an extra --gh argument must be a usage error');
    expect(r.exitCode, 2, reason: 'out:\n${r.stdout}\nerr:\n${r.stderr}');
    expect(r.stderr.toString(), contains('usage'));
  });
}
