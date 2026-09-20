// Writer/reader contract for the safe_push.sh terminal push-result record.
//
// The writer is SHELL (`scripts/safe_push.sh`) and the reader is DART
// (`scripts/push_result_lib.dart`). Nothing in either language can see the
// other, so a renamed or dropped field is invisible at both ends: the reader
// would simply find the key absent, default it to '', and classify UNVERIFIED
// forever. That is fail-SAFE, which is exactly what makes it dangerous — the
// record would degrade to "I never know anything" and no test, gate, or user
// would notice.
//
// This file pins the SEAM statically, in both directions. The behavioural
// counterpart is the WRITER -> READER case in test/scripts/safe_push_test.dart,
// which runs the real script and parses its real output with the real reader;
// and the reader's own rules are pinned in test/scripts/push_result_lib_test.dart.
// Source-greps prove PRESENCE only (rule 21), which is why all three exist.
//
// No subprocesses and no repo: this is a pure text contract, so it needs no
// @Timeout.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips shell `#` comments so an absent-pattern assertion cannot be satisfied
/// by a line that only DISCUSSES the pattern.
///
/// This file's own subject matter is full of prose about `mv -T` and
/// `--absolute-git-dir`, so without stripping, every "the script must use X"
/// assertion would pass on the strength of a comment explaining X.
String _stripShellComments(String src) => src
    .split('\n')
    .map((l) {
      final t = l.trimLeft();
      if (t.startsWith('#')) return '';
      return l;
    })
    .join('\n');

/// Strips `//` line comments from Dart source, leaving `://` (URLs) alone.
String _stripDartComments(String src) => src
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

void main() {
  final shellSrc =
      File('scripts/safe_push.sh').readAsStringSync();
  final shellCode = _stripShellComments(shellSrc);
  final readerSrc = File('scripts/push_result_lib.dart').readAsStringSync();
  final readerCode = _stripDartComments(readerSrc);

  /// Keys the writer actually emits, from the `echo "key=..."` lines inside
  /// _write_push_result. Read from the CODE, not the comments.
  Set<String> writerKeys() => RegExp(r'echo "([a-z_]+)=')
      .allMatches(shellCode)
      .map((m) => m.group(1)!)
      .toSet();

  /// Keys the reader looks up: every `at('key')` plus `result`, which is read
  /// directly rather than through the helper because its absence means "no
  /// record at all".
  Set<String> readerKeys() => {
        ...RegExp(r"""at\('([a-z_]+)'\)""")
            .allMatches(readerCode)
            .map((m) => m.group(1)!),
        'result',
      };

  test('the writer emits a non-trivial set of keys (guards a vacuous pass)', () {
    // Without this, a regex that silently matched nothing would make every
    // set-comparison below pass by comparing two empty sets.
    expect(writerKeys().length, greaterThanOrEqualTo(12),
        reason: 'extracted only ${writerKeys()} — the regex probably stopped '
            'matching, which would make the comparisons below vacuous');
    expect(readerKeys().length, greaterThanOrEqualTo(12),
        reason: 'extracted only ${readerKeys()}');
  });

  test('EVERY key the shell writer emits is a key the Dart reader knows', () {
    final unread = writerKeys().difference(readerKeys());
    expect(unread, isEmpty,
        reason: 'safe_push.sh writes these fields and push_result_lib.dart '
            'never reads them, so they are dead weight or a rename half-done: '
            '$unread');
  });

  test('EVERY key the Dart reader looks up is a key the shell writer emits '
      '(the MIRROR — without it a rename passes the check above)', () {
    final unwritten = readerKeys().difference(writerKeys());
    expect(unwritten, isEmpty,
        reason: 'push_result_lib.dart reads these fields and safe_push.sh never '
            'writes them, so they silently default to empty and the reader '
            'quietly degrades to UNVERIFIED forever: $unwritten');
  });

  test('the fields the reader CLASSIFIES on are all actually written', () {
    // A subset of the above, called out separately because these four are the
    // ones a wrong answer depends on. Membership in the whole set is not the
    // same claim as membership of the load-bearing four.
    for (final k in ['result', 'ref', 'local_sha', 'pid']) {
      expect(writerKeys(), contains(k),
          reason: '$k is load-bearing in classifyPushResult / isInFlight');
    }
  });

  test('the writer publishes with `mv -T`, never plain `mv`', () {
    // Measured: with a DIRECTORY at the destination, plain `mv` exits 0 and
    // moves the record INSIDE it, so the record lands where no reader looks
    // while the push reports success. `mv -T` refuses.
    expect(shellCode, contains('mv -T "\$RESULT_PATH.tmp"'),
        reason: 'the atomic publish must use -T');
    expect(RegExp(r'^\s*mv\s+"\$RESULT_PATH\.tmp"', multiLine: true)
        .hasMatch(shellCode), isFalse,
        reason: 'a plain `mv` of the candidate would silently nest the record '
            'inside a directory squatting at the path');
  });

  test('the record path resolves through --absolute-git-dir, not --git-dir', () {
    // `--git-dir` is RELATIVE in the primary worktree, so a reader standing
    // anywhere else resolves it against its own cwd.
    expect(shellCode, contains('--absolute-git-dir'));
    expect(shellCode, contains('.safe_push_result'));
    // And NOT in the worktree: a gitignored file there makes the worktree
    // permanently unretirable (three prior instances).
    expect(shellCode, isNot(contains('.claude/.last_push_result')));
    expect(shellCode, isNot(contains('--git-common-dir')),
        reason: 'a shared path would not be serialised by the lock, which is '
            'keyed on --git-dir');
  });

  test('every record write is unconditional — the record cannot fail the push',
      () {
    // _write_push_result always `return 0`s, and no call site branches on it.
    expect(shellCode, contains('return 0'),
        reason: '_write_push_result must always succeed from its caller\'s view');
    final calls = RegExp(r'_write_push_result [A-Z]')
        .allMatches(shellCode)
        .length;
    expect(calls, 5,
        reason: 'expected exactly 5 writes: STARTED + four terminal verdicts, '
            'found $calls');
    expect(
        RegExp(r'(if|&&|\|\|)[^\n]*_write_push_result').hasMatch(shellCode),
        isFalse,
        reason: 'no write may be conditional on anything — a record is advisory '
            'and the push verdict is not');
  });

  test('the four pre-push exits write NOTHING', () {
    // Writing FAILED before any push was attempted would claim a push failed
    // when none happened. `:63` (lock refused) is the sharpest case: "another
    // push is running" and "this push failed" share exit code 1.
    final firstWrite = shellCode.indexOf('_write_push_result STARTED');
    expect(firstWrite, greaterThan(0));
    final beforeAnyWrite = shellCode.substring(0, firstWrite);
    expect(beforeAnyWrite, contains('git_lock_acquire'),
        reason: 'sanity: the lock acquire really does precede the first write');
    expect(beforeAnyWrite, isNot(contains('_write_push_result FAILED')));
    expect(beforeAnyWrite, isNot(contains('_write_push_result UNVERIFIED')));
  });

  test('the reader treats an absent record as UNVERIFIED, never FAILED', () {
    // The single most important rule: reading absent as failed re-creates the
    // bad-news-vs-no-news inversion the record exists to kill.
    expect(readerCode,
        contains('if (record == null) return PushVerdict.unverified;'));
    expect(readerCode, isNot(contains('record == null) return PushVerdict.failed')));
  });

  test('the reader requires BOTH ref and local_sha to match', () {
    // Not the sha alone: two refs legitimately share a tip after a
    // fast-forward merge or on a freshly-cut branch.
    expect(readerCode, contains('record.ref != wantRef'));
    expect(readerCode, contains('record.localSha != wantSha'));
  });

  test('UNVERIFIED never maps to failed in the reader', () {
    // Guards diagnose d4f9b2 at the reader layer.
    expect(readerCode, contains("case 'UNVERIFIED':"));
    expect(
        RegExp(r"case 'UNVERIFIED':\s*return PushVerdict\.failed")
            .hasMatch(readerCode),
        isFalse);
    expect(readerCode, contains('default:'),
        reason: 'an unrecognised result value must degrade, not throw');
  });

  test('the reason field is sanitized before it is written', () {
    // It carries raw git stderr; a newline would inject a bogus key=value line
    // and corrupt the record for every parser.
    expect(shellCode, contains('_sanitize_reason'));
    expect(shellCode, contains(r'echo "reason=$(_sanitize_reason "$4")"'),
        reason: 'the reason must go through the sanitizer at the write site, '
            'not merely have a sanitizer defined somewhere');
  });
}
