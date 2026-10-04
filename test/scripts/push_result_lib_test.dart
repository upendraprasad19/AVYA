// Unit tests for scripts/push_result_lib.dart — the reader contract for
// safe_push.sh's terminal push-result record (OI-172).
//
// NO @Timeout annotation and no subprocesses: every function under test is
// pure, so this file spawns nothing, waits on nothing it does not control, and
// cannot flake under full-suite contention. That is the point of the lib being
// pure — the CLAUDE.md §4.9 "green targeted, red in the suite" class (5 prior
// recurrences) does not apply to a file that starts no processes.

import 'package:test/test.dart';

import '../../scripts/push_result_lib.dart';

/// A complete, well-formed LANDED record, as safe_push.sh writes it.
String record({
  String result = 'LANDED',
  String exit = '0',
  String branch = 'main',
  String ref = 'refs/heads/main',
  String remote = 'origin',
  String localSha = 'aaaa111',
  String remoteSha = 'aaaa111',
  String verifiedRef = 'refs/heads/main',
  String pid = '4242',
  String reason = '',
}) =>
    'result=$result\n'
    'exit=$exit\n'
    'branch=$branch\n'
    'ref=$ref\n'
    'remote=$remote\n'
    'local_sha=$localSha\n'
    'remote_sha=$remoteSha\n'
    'verified_ref=$verifiedRef\n'
    'pid=$pid\n'
    'started=2026-09-10T10:00:00Z\n'
    'ended=2026-09-10T10:01:00Z\n'
    'worktree=/repo\n'
    'reason=$reason\n';

void main() {
  group('parsePushResult', () {
    test('parses a complete record', () {
      final r = parsePushResult(record())!;
      expect(r.result, 'LANDED');
      expect(r.ref, 'refs/heads/main');
      expect(r.localSha, 'aaaa111');
      expect(r.verifiedRef, 'refs/heads/main');
      expect(r.pid, '4242');
    });

    test('an empty, blank, or result-less file is null — the same as absent',
        () {
      // All four must be indistinguishable from a missing file, because
      // classifyPushResult's rule 1 keys on null to return UNVERIFIED.
      expect(parsePushResult(null), isNull);
      expect(parsePushResult(''), isNull);
      expect(parsePushResult('   \n\n  '), isNull);
      expect(parsePushResult('branch=main\nexit=0\n'), isNull);
      expect(parsePushResult('result=\n'), isNull, reason: 'empty value');
    });

    test('a torn or foreign file does not throw', () {
      // A half-written file must degrade to "no information", never raise: an
      // exception here would invite a catch-all that turns unknown into failed.
      expect(() => parsePushResult('resu'), returnsNormally);
      expect(() => parsePushResult('=novalue\n'), returnsNormally);
      // Built with fromCharCode rather than written as literal escapes: a real
      // NUL in the SOURCE makes git treat this whole file as binary, which kills
      // every diff and review of it. (It did — caught at `git add` time.)
      final controlChars = String.fromCharCodes([0, 1]);
      expect(() => parsePushResult('${controlChars}binary'), returnsNormally);
      expect(parsePushResult('result=LANDED\ngarbage line with no equals\n')!.result,
          'LANDED');
    });

    test('unknown keys survive in fields so a newer writer is not lost', () {
      final r = parsePushResult('${record()}future_field=hello\n')!;
      expect(r.fields['future_field'], 'hello');
    });

    test('a value containing = keeps everything after the FIRST =', () {
      final r = parsePushResult('result=FAILED\nreason=a=b=c\n')!;
      expect(r.reason, 'a=b=c');
    });
  });

  group('classifyPushResult — rule 1: absent is UNVERIFIED, never FAILED', () {
    test('a null record is UNVERIFIED', () {
      expect(
        classifyPushResult(null, wantRef: 'refs/heads/main', wantSha: 'aaaa111'),
        PushVerdict.unverified,
      );
    });

    test('a null record is specifically NOT failed', () {
      // Stated as its own assertion because this is the whole point: the
      // inversion being guarded against is absent->failed, and a test that only
      // checks == unverified reads as covering it without naming it.
      expect(
        classifyPushResult(null, wantRef: 'refs/heads/main', wantSha: 'a'),
        isNot(PushVerdict.failed),
      );
    });
  });

  group('classifyPushResult — rule 2: STARTED is not a verdict', () {
    test('STARTED is UNVERIFIED even when ref and sha match', () {
      final r = parsePushResult(record(result: 'STARTED', exit: '-'));
      expect(r!.isInFlight, isTrue);
      expect(
        classifyPushResult(r, wantRef: 'refs/heads/main', wantSha: 'aaaa111'),
        PushVerdict.unverified,
      );
    });
  });

  group('classifyPushResult — rule 3: ref AND sha must both match', () {
    test('matching ref and sha yields the recorded verdict', () {
      expect(
        classifyPushResult(parsePushResult(record()),
            wantRef: 'refs/heads/main', wantSha: 'aaaa111'),
        PushVerdict.landed,
      );
    });

    test('a sha mismatch is UNVERIFIED — a stale record is not a fresh verdict',
        () {
      expect(
        classifyPushResult(parsePushResult(record()),
            wantRef: 'refs/heads/main', wantSha: 'bbbb222'),
        PushVerdict.unverified,
      );
    });

    // CASE 10 — the reason this lib exists as code.
    //
    // Two refs legitimately share a tip: right after a fast-forward merge, or
    // on a freshly-cut branch with no new commits. A sha-ONLY check therefore
    // lets branch A's LANDED verdict be read as proof about branch B. Plan
    // review round 1 (F2) raised it; round 2 (F-R2-2) caught that the fix had
    // shipped with no assertion behind it.
    //
    // MUTATION TARGET: delete `if (record.ref != wantRef) return unverified;`
    // from classifyPushResult and this test must redden. It is a mutation of
    // real shipped code — through plan v3 the "reader" lived only in this test
    // file, so the mutation would have edited the fixture and proved nothing.
    test('two refs at the SAME sha do not borrow each other\'s verdict', () {
      final landedOnMain = parsePushResult(record(
        branch: 'main',
        ref: 'refs/heads/main',
        localSha: 'shared00',
        remoteSha: 'shared00',
      ));

      expect(
        classifyPushResult(landedOnMain,
            wantRef: 'refs/heads/main', wantSha: 'shared00'),
        PushVerdict.landed,
        reason: 'the ref the record IS about must still read as landed',
      );

      expect(
        classifyPushResult(landedOnMain,
            wantRef: 'refs/heads/release', wantSha: 'shared00'),
        PushVerdict.unverified,
        reason: 'IDENTICAL sha, DIFFERENT ref: main\'s verdict says nothing '
            'about release, and answering landed here would be a confident '
            'wrong answer',
      );
    });

    test('an absent ref field fails closed rather than matching anything', () {
      final noRef = parsePushResult('result=LANDED\nlocal_sha=aaaa111\n');
      expect(
        classifyPushResult(noRef, wantRef: 'refs/heads/main', wantSha: 'aaaa111'),
        PushVerdict.unverified,
      );
    });
  });

  group('classifyPushResult — rule 4: the three outcomes stay distinct', () {
    test('FAILED reads as failed', () {
      expect(
        classifyPushResult(parsePushResult(record(result: 'FAILED', exit: '1')),
            wantRef: 'refs/heads/main', wantSha: 'aaaa111'),
        PushVerdict.failed,
      );
    });

    test('UNVERIFIED does NOT collapse into failed', () {
      // Guards diagnose d4f9b2: safe_push.sh exit 2 exists precisely so "could
      // not check" is distinguishable from "did not land". A reader that folds
      // them together re-creates the bug one layer out.
      final v = classifyPushResult(
          parsePushResult(record(result: 'UNVERIFIED', exit: '2', remoteSha: '')),
          wantRef: 'refs/heads/main',
          wantSha: 'aaaa111');
      expect(v, PushVerdict.unverified);
      expect(v, isNot(PushVerdict.failed));
    });

    test('an unrecognised result value degrades to UNVERIFIED', () {
      expect(
        classifyPushResult(parsePushResult(record(result: 'SOMETHING_NEW')),
            wantRef: 'refs/heads/main', wantSha: 'aaaa111'),
        PushVerdict.unverified,
      );
    });
  });

  group('probedTheWrongNamespace — the tag residual is self-diagnosing', () {
    test('a tag pushed as a branch flags its own verdict as unreliable', () {
      // safe_push.sh's probe hardcodes refs/heads/$BRANCH, so a tag name passed
      // positionally lands but probes the wrong namespace and reports FAILED.
      // The verdict stays as the script recorded it — the record must not
      // silently disagree with stdout — but the reader can SEE why it is wrong.
      final r = parsePushResult(record(
        result: 'FAILED',
        exit: '1',
        branch: 'v1.2.3',
        ref: 'refs/tags/v1.2.3',
        verifiedRef: 'refs/heads/v1.2.3',
        remoteSha: '',
      ))!;
      expect(r.probedTheWrongNamespace, isTrue);
      expect(
        describePushResult(r,
            wantRef: 'refs/tags/v1.2.3', wantSha: 'aaaa111'),
        contains('unreliable'),
      );
    });

    test('a normal branch push does not flag itself', () {
      expect(parsePushResult(record())!.probedTheWrongNamespace, isFalse);
    });

    test('a missing verified_ref does not flag — absent is not a mismatch', () {
      expect(parsePushResult(record(verifiedRef: ''))!.probedTheWrongNamespace,
          isFalse);
    });
  });

  group('describePushResult', () {
    test('an absent record says it is not evidence of failure', () {
      final s = describePushResult(null,
          wantRef: 'refs/heads/main', wantSha: 'aaaa111');
      expect(s, contains('UNVERIFIED'));
      expect(s, contains('NOT evidence the push failed'));
    });

    test('LANDED disclaims CI in the same breath', () {
      final s = describePushResult(parsePushResult(record()),
          wantRef: 'refs/heads/main', wantSha: 'aaaa111');
      expect(s, contains('LANDED'));
      expect(s, contains('nothing about CI'));
    });

    test('an in-flight record names the pid to check', () {
      final s = describePushResult(
          parsePushResult(record(result: 'STARTED', pid: '9911')),
          wantRef: 'refs/heads/main',
          wantSha: 'aaaa111');
      expect(s, contains('9911'));
      expect(s, contains('alive'));
    });
  });
}
