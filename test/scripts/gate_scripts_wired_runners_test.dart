// test/scripts/gate_scripts_wired_runners_test.dart
//
// Red-path tests for check_gate_scripts_wired.dart (Gate 33)'s typed allowlist
// (OI-155). The gate's filename is stated here so the rule-24 ledger's
// `namesGate` check resolves.
//
// Until this batch `_allowList` was `Map<String, String>` — gate name to free
// prose — and the prose was read by nothing. Six entries claimed a runner
// ("runs in /build-apk skill Gate 14b") that did not exist, and Gate 33 said
// PASS on every commit because an allowlisted gate was simply skipped. These
// tests pin the replacement: every runner is a CLAIM the gate can check —
//   file(path)   : the file INVOKES the gate (`run scripts/<gate>` on a
//                  non-comment line — a comment or a prose mention is not
//                  an invocation);
//   loop(name)   : the named dynamic loop exists and does NOT case-skip it;
//   manual(OI-N) : the cited OI is OPEN or IN_PROGRESS on the merged boards —
//                  CLOSED, absent, or an unreadable board all FAIL, so closing
//                  the blocker without giving the gate a real runner turns
//                  this gate red (the forcing function).
// Plus the mirror: an allowlist key with no script on disk is a violation.
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/gate_scripts_wired_lib.dart';

const _preCommit = '''
for GATE in scripts/check_*.dart; do
  case "\$GATE_NAME" in
    check_skipped.dart|\\
    check_other.dart)
      continue ;;
  esac
done
# dart run scripts/check_commented.dart   <- a comment is not a runner
Run check_prose.dart before every release.   <- prose naming a gate is not a runner
"\$DART_BIN" run scripts/check_explicit.dart
''';

const _statuses = <String, String>{
  'OI-165': 'OPEN',
  'OI-77': 'IN_PROGRESS',
  'OI-9': 'CLOSED',
};

void main() {
  String? read(String p) => p == 'scripts/pre-commit.sh' ? _preCommit : null;
  Set<String> skips(String c) => extractCaseSkips(c, caseSkipRegex);
  List<String> check(String gate, GateRunner r,
          {Map<String, String>? statuses = _statuses}) =>
      runnerViolations(
          gate: gate,
          runners: [r],
          read: read,
          caseSkipsOf: skips,
          boardStatuses: statuses);

  test('fixture sanity: the case block parses to exactly its two real skips '
      'under the REAL caseSkipRegex', () {
    expect(extractCaseSkips(_preCommit, caseSkipRegex),
        {'check_skipped.dart', 'check_other.dart'});
  });

  group('invokesGate', () {
    test('comment-only mention is NOT an invocation',
        () => expect(invokesGate(_preCommit, 'check_commented.dart'), isFalse));
    test('prose naming the gate WITHOUT the invocation shape is NOT an invocation',
        () => expect(invokesGate(_preCommit, 'check_prose.dart'), isFalse));
    test(
        'prose CARRYING the invocation shape (`run scripts/<gate>`) DOES count '
        '-- a skill doc is executed by reading it',
        () => expect(
            invokesGate(
                'Then run `dart run scripts/check_doc.dart --record` before the upload.\n',
                'check_doc.dart'),
            isTrue));
    test('case-skip line is NOT an invocation',
        () => expect(invokesGate(_preCommit, 'check_skipped.dart'), isFalse));
    test('`run scripts/<gate>` on a live line IS',
        () => expect(invokesGate(_preCommit, 'check_explicit.dart'), isTrue));

    // B-pass finding 1 (gate-integrity, 2026-09-19): the first version was a
    // bare `contains('run scripts/<gate>')` on non-comment lines, so PRINTED
    // text registered as an invocation -- the same shape extractCaseSkips was
    // hardened against one function above it. Two mirrors, one test each.
    test('B-PASS F1: a heredoc BODY naming the gate is printed, not executed',
        () => expect(
            invokesGate(
                "cat <<'EOF'\nReminder: dart run scripts/check_heredoc.dart\nEOF\n",
                'check_heredoc.dart'),
            isFalse));
    test('B-PASS F1: prose without an invoker token ("You should run scripts/x '
        'by hand") is NOT an invocation',
        () => expect(
            invokesGate(
                'You should run scripts/check_byhand.dart by hand before releasing.\n',
                'check_byhand.dart'),
            isFalse));
    test('MIRROR: an invocation whose STDIN is a heredoc still counts',
        () => expect(
            invokesGate(
                'dart run scripts/check_stdin.dart <<EOF\nsome input\nEOF\n',
                'check_stdin.dart'),
            isTrue));
    test('MIRROR: every invoker spelling the repo uses counts', () {
      for (final line in [
        '"\$DART_BIN" run scripts/check_v.dart',
        '\$DART_BIN run scripts/check_v.dart',
        '\${DART_BIN} run scripts/check_v.dart',
        'if ! "\$DART_BIN" run scripts/check_v.dart; then',
        '        run: dart run scripts/check_v.dart',
        'dart run scripts/check_v.dart --record',
      ]) {
        expect(invokesGate('$line\n', 'check_v.dart'), isTrue, reason: line);
      }
    });
  });

  group('runnerViolations', () {
    test('file runner satisfied by a live invocation', () {
      expect(check('check_explicit.dart', GateRunner.file('scripts/pre-commit.sh', 'x')),
          isEmpty);
    });
    test('RED PATH: file runner whose only mention is a comment', () {
      final violations =
          check('check_commented.dart', GateRunner.file('scripts/pre-commit.sh', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: file runner whose only mention is prose', () {
      final violations =
          check('check_prose.dart', GateRunner.file('scripts/pre-commit.sh', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: file runner naming an unreadable file', () {
      final violations =
          check('check_x.dart', GateRunner.file('.claude/commands/missing.md', 'x'));
      expect(violations, isNotEmpty);
    });
    test('loop runner satisfied when the loop file does not case-skip the gate', () {
      expect(check('check_explicit.dart', GateRunner.loop('preCommit', 'x')), isEmpty);
    });
    test('RED PATH: loop runner for a gate the loop case-skips', () {
      final violations = check('check_skipped.dart', GateRunner.loop('preCommit', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: loop runner naming an unknown loop', () {
      final violations = check('check_explicit.dart', GateRunner.loop('nightly', 'x'));
      expect(violations, isNotEmpty);
    });
    test('manual runner satisfied by an OPEN OI', () {
      expect(check('check_live.dart', GateRunner.manual('OI-165', 'x')), isEmpty);
    });
    test(
        'manual runner satisfied by an IN_PROGRESS OI (the session about to fix '
        'it must not be blocked)', () {
      expect(check('check_live.dart', GateRunner.manual('OI-77', 'x')), isEmpty);
    });
    test('RED PATH: manual runner citing a CLOSED OI fails -- the forcing function',
        () {
      final violations = check('check_live.dart', GateRunner.manual('OI-9', 'x'));
      expect(violations, isNotEmpty);
      expect(violations.single, contains('CLOSED'));
    });
    test('RED PATH: manual runner citing an OI on neither board fails', () {
      final violations = check('check_live.dart', GateRunner.manual('OI-9999', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: manual runner with an unreadable board fails CLOSED', () {
      final violations =
          check('check_live.dart', GateRunner.manual('OI-165', 'x'), statuses: null);
      expect(violations, isNotEmpty);
      expect(violations.single, contains('unreadable'));
    });
    test('RED PATH: manual runner whose target is not OI-NNN shaped fails', () {
      final violations =
          check('check_live.dart', GateRunner.manual('founder said so', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: an entry declaring NO runner at all is a violation', () {
      final violations = runnerViolations(
          gate: 'check_none.dart',
          runners: const [],
          read: read,
          caseSkipsOf: skips,
          boardStatuses: _statuses);
      expect(violations, isNotEmpty);
    });
  });

  group('staleAllowlistViolations', () {
    test('an allowlist key with no script on disk is a violation (mirror of the '
        'ledger gate)', () {
      final violations =
          staleAllowlistViolations({'check_a.dart'}, ['check_a.dart', 'check_gone.dart']);
      expect(violations, isNotEmpty);
      expect(violations.single, contains('check_gone.dart'));
    });
    test('no stale keys, no violations', () {
      expect(staleAllowlistViolations({'check_a.dart'}, ['check_a.dart']), isEmpty);
    });
  });
}
