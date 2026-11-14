// test/scripts/merge_scope_lib_test.dart
//
// scripts/merge_scope_lib.dart with a FAKE git runner: every precondition of the rule, the exact
// reason strings, the sequence and argv of the git calls, the byte-string set logic and the NOTE
// text. No process is spawned. The same lib against real git is test/scripts/merge_scope_git_test.dart.
//
// Rule 21: a `Fallback` is asserted with its EXACT reason (the lib's catch-all returns
// [internalErrorReason], so a test that only checked the type would pass for a mutant that throws).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/merge_scope_lib.dart';

const String kMh = '1111111111111111111111111111111111111111';
const String kTip = '2222222222222222222222222222222222222222';

({int exitCode, List<int> stdout}) _ok(String s) => (exitCode: 0, stdout: utf8.encode(s));
({int exitCode, List<int> stdout}) _exit(int code) => (exitCode: code, stdout: const <int>[]);

List<int> _nul(List<String> paths) => <int>[
      for (final p in paths) ...<int>[...utf8.encode(p), 0],
    ];

/// A scripted git. [answers] maps `args.join(' ')` to the reply; an unexpected call throws, which
/// the lib turns into [internalErrorReason] (and these tests then fail on the reason).
class _Git {
  _Git(this.answers);
  final Map<String, ({int exitCode, List<int> stdout})?> answers;
  final List<List<String>> calls = <List<String>>[];

  ({int exitCode, List<int> stdout})? run(List<String> args) {
    calls.add(args);
    final k = args.join(' ');
    if (!answers.containsKey(k)) throw StateError('unexpected git call: $k');
    return answers[k];
  }
}

const String _kGitPath = 'rev-parse --git-path MERGE_HEAD';
const String _kTipRef = 'rev-parse --verify --quiet refs/remotes/origin/main^{commit}';
String _kAnc(String mh, String tip) => 'merge-base --is-ancestor $mh $tip';
String _kDi(String treeish) => diffIndexArgv(treeish).join(' ');

/// The happy-path script; [over] replaces entries.
Map<String, ({int exitCode, List<int> stdout})?> _script({
  String mh = kMh,
  String tip = kTip,
  List<String> head = const <String>['a.md', 'b.md'],
  List<String> tipDiff = const <String>['b.md', 'c.md'],
  Map<String, ({int exitCode, List<int> stdout})?> over = const {},
}) =>
    <String, ({int exitCode, List<int> stdout})?>{
      _kGitPath: _ok('.git/MERGE_HEAD\n'),
      _kTipRef: _ok('$tip\n'),
      _kAnc(mh, tip): _exit(0),
      _kDi('HEAD'): (exitCode: 0, stdout: _nul(head)),
      _kDi(tip): (exitCode: 0, stdout: _nul(tipDiff)),
      ...over,
    };

MergeScope _run(
  _Git g, {
  String? mergeHeadText = '$kMh\n',
  List<String> staged = const <String>['a.md', 'b.md'],
  ReadMergeHead? read,
}) =>
    computeMergeScope(g.run, readMergeHead: read ?? (_) => mergeHeadText, staged: staged);

void _fallsBack(MergeScope s, String reason) {
  expect(s, isA<Fallback>(), reason: 'got $s');
  expect((s as Fallback).reason, reason);
}

void main() {
  group('argv builders (presence pins)', () {
    test('the staged reader and the diff-index calls carry the hardened flags and the -- terminator', () {
      expect(stagedPathsArgv, <String>['diff', '--cached', '--no-renames', '--ignore-submodules=none', '--name-only', '-z']);
      expect(diffIndexArgv('abc'), <String>['diff-index', '--cached', '--name-only', '-z', '--ignore-submodules=none', 'abc', '--']);
    });
  });

  group('happy path', () {
    test('1 grades the staged paths that the tip diff also lists, sorted, with the tip and MERGE_HEAD', () {
      final g = _Git(_script());
      final s = _run(g);
      expect(s, isA<Scoped>());
      s as Scoped;
      expect(s.paths, <String>['b.md']);
      expect(s.tip, kTip);
      expect(s.mergeHead, kMh);
    });

    test('2 issues exactly these git calls, in this order, with the tip passed as its hex name', () {
      final g = _Git(_script());
      _run(g);
      expect(g.calls.map((c) => c.join(' ')).toList(), <String>[
        _kGitPath,
        _kTipRef,
        _kAnc(kMh, kTip),
        _kDi('HEAD'),
        _kDi(kTip),
      ]);
    });

    test('3 an empty graded set is Scoped with no paths', () {
      final s = _run(_Git(_script(tipDiff: <String>['zzz.md'])));
      expect(s, isA<Scoped>());
      expect((s as Scoped).paths, isEmpty);
    });

    test('4 a 64-digit object name is accepted for MERGE_HEAD and the tip', () {
      final mh = 'a' * 64;
      final tip = 'b' * 64;
      final s = _run(_Git(_script(mh: mh, tip: tip)), mergeHeadText: '$mh\n');
      expect(s, isA<Scoped>());
    });

    test('5 the graded paths come from the decoded staged list and are sorted', () {
      final s = _run(
        _Git(_script(head: <String>['z.md', 'a.md'], tipDiff: <String>['a.md', 'z.md'])),
        staged: <String>['z.md', 'a.md'],
      );
      expect((s as Scoped).paths, <String>['a.md', 'z.md']);
    });
  });

  group('byte-string set logic', () {
    test('6 names whose UTF-8 byte order differs from their UTF-16 order are both graded', () {
      // U+FF5E (a BMP character) sorts before U+10000 in UTF-8 bytes, after it in UTF-16 code units.
      final a = 'docs/${String.fromCharCode(0xff5e)}.md';
      final b = 'docs/${String.fromCharCodes(const <int>[0xd800, 0xdc00])}.md'; // U+10000 as a surrogate pair
      final s = _run(
        _Git(_script(head: <String>[a, b], tipDiff: <String>[a, b])),
        staged: <String>[a, b],
      );
      expect((s as Scoped).paths.toSet(), <String>{a, b});
    });

    test('7 an undecodable name that only the tip diff lists does not disable scoping', () {
      final g = _Git(_script(over: {
        _kDi(kTip): (exitCode: 0, stdout: <int>[...utf8.encode('b.md'), 0, 0xff, 0xfe, 0]),
      }));
      final s = _run(g);
      expect(s, isA<Scoped>());
      expect((s as Scoped).paths, <String>['b.md']);
    });

    test('8 leading and trailing spaces, an embedded newline and a leading BOM survive unchanged', () {
      final odd = <String>[' lead.md', 'trail.md ', 'a\nb.md', '${String.fromCharCode(0xfeff)}bom.md'];
      final s = _run(
        _Git(_script(head: odd, tipDiff: odd)),
        staged: odd,
      );
      expect((s as Scoped).paths.toSet(), odd.toSet());
    });

    test('9 parseNulPaths: no trimming, final empty element dropped, strict UTF-8, BOM kept', () {
      expect(parseNulPaths(_nul(<String>[' a ', 'b'])), <String>[' a ', 'b']);
      expect(parseNulPaths(const <int>[]), isEmpty);
      expect(parseNulPaths(<int>[0x61, 0xff, 0]), isNull);
      expect(parseNulPaths(_nul(<String>['${String.fromCharCode(0xfeff)}x'])), <String>['${String.fromCharCode(0xfeff)}x']);
    });

    test('10 splitNulBytes keeps one char per byte and byteString is its inverse for valid UTF-8', () {
      final raw = <int>[0xc3, 0xa9, 0, 0xff, 0];
      expect(splitNulBytes(raw), <String>['Ã©', 'ÿ']);
      expect(byteString('é'), 'Ã©');
    });

    test('11 duplicates in the diff-index answers do not matter (unmerged entries list a path more than once)', () {
      final s = _run(_Git(_script(head: <String>['a.md', 'a.md', 'b.md'], tipDiff: <String>['b.md', 'b.md'])));
      expect((s as Scoped).paths, <String>['b.md']);
    });
  });

  group('condition 1: is a merge pending', () {
    test('12 an ordinary commit costs exactly one git call and is NotAMerge', () {
      final g = _Git(_script());
      final s = _run(g, mergeHeadText: null);
      expect(s, isA<NotAMerge>());
      expect(g.calls.length, 1);
      expect(g.calls.single.join(' '), _kGitPath);
    });

    test('13 git cannot run: the first call returns null', () {
      _fallsBack(_run(_Git(_script(over: {_kGitPath: null}))), 'git could not run');
    });

    test('14 rev-parse --git-path fails or prints nothing', () {
      _fallsBack(_run(_Git(_script(over: {_kGitPath: _exit(128)}))), 'git rev-parse --git-path failed');
      _fallsBack(_run(_Git(_script(over: {_kGitPath: _ok('\n')}))), 'git rev-parse --git-path printed nothing');
    });

    test('15 an unreadable MERGE_HEAD is a Fallback, not an exception', () {
      final s = _run(_Git(_script()), read: (_) => throw const FormatException('unreadable'));
      _fallsBack(s, 'MERGE_HEAD unreadable');
    });

    test('16 an octopus merge (several lines) and an empty file fall back', () {
      _fallsBack(_run(_Git(_script()), mergeHeadText: '$kMh\n$kTip\n'), 'MERGE_HEAD has 2 lines (octopus merge or empty file)');
      _fallsBack(_run(_Git(_script()), mergeHeadText: ''), 'MERGE_HEAD has 0 lines (octopus merge or empty file)');
    });

    test('17 only a full lowercase 40- or 64-digit hex name is accepted for MERGE_HEAD', () {
      for (final bad in <String>[
        '1' * 39,
        '1' * 41,
        '1' * 63,
        '1' * 65,
        '${'1' * 39}A',
        '-${'1' * 39}',
        '-${'1' * 40}',
        '-${'1' * 64}',
        '${'1' * 40} junk',
        'x' * 40,
      ]) {
        _fallsBack(_run(_Git(_script()), mergeHeadText: '$bad\n'), 'MERGE_HEAD is not a full object name');
      }
      expect(isFullHexObjectName('1' * 40), isTrue);
      expect(isFullHexObjectName('f' * 64), isTrue);
      expect(isFullHexObjectName('${'1' * 40}\n'), isFalse);
      expect(isFullHexObjectName('-${'1' * 40}'), isFalse, reason: 'a leading dash would reach git as an option');
    });
  });

  group('condition 2 and 3: the tip and the ancestor test', () {
    test('18 no refs/remotes/origin/main, or one that is not a commit', () {
      _fallsBack(_run(_Git(_script(over: {_kTipRef: _exit(1)}))), 'refs/remotes/origin/main is missing or not a commit');
    });

    test('19 the tip must resolve to a full object name (a runner answering --foo falls back)', () {
      _fallsBack(_run(_Git(_script(over: {_kTipRef: _ok('--foo\n')}))), 'refs/remotes/origin/main did not resolve to a full object name');
      _fallsBack(_run(_Git(_script(over: {_kTipRef: _ok('abc\n')}))), 'refs/remotes/origin/main did not resolve to a full object name');
      _fallsBack(_run(_Git(_script(over: {_kTipRef: _ok('-${'1' * 40}\n')}))), 'refs/remotes/origin/main did not resolve to a full object name');
    });

    test('20 a MERGE_HEAD that is not an ancestor of the tip falls back; any other failure is its own reason', () {
      _fallsBack(_run(_Git(_script(over: {_kAnc(kMh, kTip): _exit(1)}))),
          'MERGE_HEAD is not an ancestor of origin/main (or the history is shallow)');
      _fallsBack(_run(_Git(_script(over: {_kAnc(kMh, kTip): _exit(128)}))), 'git merge-base --is-ancestor failed');
    });

    test('21 the ancestor test names MERGE_HEAD first and the tip second', () {
      final g = _Git(_script());
      _run(g);
      expect(g.calls[2], <String>['merge-base', '--is-ancestor', kMh, kTip]);
    });

    test('22 a null runner answer fails closed at every step', () {
      final keys = <String>[_kGitPath, _kTipRef, _kAnc(kMh, kTip), _kDi('HEAD'), _kDi(kTip)];
      for (final k in keys) {
        _fallsBack(_run(_Git(_script(over: {k: null}))), 'git could not run');
      }
    });
  });

  group('condition 4 and 5: the two index reads', () {
    test('23 a non-zero diff-index exit falls back with its own reason', () {
      _fallsBack(_run(_Git(_script(over: {_kDi('HEAD'): _exit(128)}))), 'git diff-index against HEAD failed');
      _fallsBack(_run(_Git(_script(over: {_kDi(kTip): _exit(128)}))), 'git diff-index against origin/main failed');
    });

    test('24 the HEAD diff must equal the staged list as a set: both directions, and an empty HEAD diff', () {
      // staged is a superset of the HEAD diff
      _fallsBack(_run(_Git(_script(head: <String>['a.md'])), staged: <String>['a.md', 'b.md']), 'index reads disagree');
      // the HEAD diff is a superset of staged (an intent-to-add entry)
      _fallsBack(_run(_Git(_script(head: <String>['a.md', 'b.md', 'ita.md'])), staged: <String>['a.md', 'b.md']), 'index reads disagree');
      // an empty HEAD diff with a non-empty staged list
      _fallsBack(_run(_Git(_script(head: <String>[])), staged: <String>['a.md']), 'index reads disagree');
      // a different path of the same size
      _fallsBack(_run(_Git(_script(head: <String>['a.md', 'x.md'])), staged: <String>['a.md', 'b.md']), 'index reads disagree');
    });

    test('25 the equality check comes before the tip diff: a disagreement issues no tip-diff call', () {
      final g = _Git(_script(head: <String>['a.md']));
      _run(g, staged: <String>['a.md', 'b.md']);
      expect(g.calls.map((c) => c.join(' ')), isNot(contains(_kDi(kTip))));
      expect(g.calls.length, 4);
    });

    test('26 two empty lists agree and give Scoped with no paths', () {
      final s = _run(_Git(_script(head: <String>[], tipDiff: <String>[])), staged: <String>[]);
      expect(s, isA<Scoped>());
      expect((s as Scoped).paths, isEmpty);
    });
  });

  group('never throws', () {
    test('27 a throwing runner becomes the internal-error reason', () {
      final s = computeMergeScope((_) => throw StateError('boom'), readMergeHead: (_) => '$kMh\n', staged: const <String>['a.md']);
      _fallsBack(s, internalErrorReason);
    });

    test('28 a runner that returns a malformed shape is also contained', () {
      final s = computeMergeScope((_) => (exitCode: 0, stdout: const <int>[]), readMergeHead: (_) => '$kMh\n', staged: const <String>['a.md']);
      // the first answer is an empty path: a Fallback, not an exception
      expect(s, isA<Fallback>());
    });
  });

  group('the NOTE', () {
    test('29 escapeForNote: backslash, C0, DEL, C1, U+2028, U+2029 and the bidi controls', () {
      String c(int r) => String.fromCharCode(r);
      final bs = c(0x5c); // the backslash, built from its code point
      expect(escapeForNote('a${bs}b'), 'a$bs${bs}b');
      expect(escapeForNote('a${c(10)}b'), '${'a'}${bs}x0a${'b'}');
      expect(escapeForNote('a${c(0x1b)}b'), 'a${bs}x1bb');
      expect(escapeForNote('a${c(0x7f)}b'), 'a${bs}x7fb');
      expect(escapeForNote('a${c(0x85)}b'), 'a${bs}x85b');
      expect(escapeForNote('a${c(0x2028)}b${c(0x2029)}'), 'a${bs}u2028b${bs}u2029');
      expect(escapeForNote('a${c(0x202e)}b'), 'a${bs}u202eb');
      expect(escapeForNote('a${c(0x2066)}b'), 'a${bs}u2066b');
      // both edges of every escaped range, and the character just outside each one
      expect(escapeForNote('a${c(0x1f)}b'), 'a${bs}x1fb');
      expect(escapeForNote('a${c(0x20)}b'), 'a b');
      expect(escapeForNote('a${c(0x7e)}b'), 'a~b');
      expect(escapeForNote('a${c(0x80)}b'), 'a${bs}x80b');
      expect(escapeForNote('a${c(0x9f)}b'), 'a${bs}x9fb');
      expect(escapeForNote('a${c(0xa0)}b'), 'a${c(0xa0)}b');
      expect(escapeForNote('a${c(0x202a)}b'), 'a${bs}u202ab');
      expect(escapeForNote('a${c(0x2029)}b'), 'a${bs}u2029b');
      expect(escapeForNote('a${c(0x202f)}b'), 'a${c(0x202f)}b');
      expect(escapeForNote('a${c(0x2065)}b'), 'a${c(0x2065)}b');
      expect(escapeForNote('a${c(0x2069)}b'), 'a${bs}u2069b');
      expect(escapeForNote('a${c(0x206a)}b'), 'a${c(0x206a)}b');
      // the literal text backslash-x0a stays distinguishable from an escaped newline
      expect(escapeForNote('a${bs}x0ab'), 'a$bs${bs}x0ab');
      expect(escapeForNote('plain name.md'), 'plain name.md');
    });

    test('30 formatScopeNote: NotAMerge prints nothing, the others print the exact text', () {
      expect(formatScopeNote(const NotAMerge(), 3), isNull);
      expect(
        formatScopeNote(const Fallback('refs/remotes/origin/main is missing or not a commit'), 7),
        'branch-sync scoping not applied (refs/remotes/origin/main is missing or not a commit): grading all 7 staged path(s)',
      );
      expect(
        formatScopeNote(const Scoped(<String>['a.md', 'b${'\n'}c.md'], tip: kTip, mergeHead: kMh), 40),
        'branch sync of origin/main (tip 2222222, MERGE_HEAD 1111111): grading 2 path(s) whose entry matches '
        r'neither HEAD nor origin/main, of 40 staged: a.md, b\x0ac.md. Unmerged paths are graded.',
      );
      expect(
        formatScopeNote(const Scoped(<String>[], tip: kTip, mergeHead: kMh), 5),
        'branch sync of origin/main (tip 2222222, MERGE_HEAD 1111111): grading 0 path(s) whose entry matches '
        'neither HEAD nor origin/main, of 5 staged. Unmerged paths are graded.',
      );
    });

    test('31 a long graded list is cut after 20 names and says how many more', () {
      final many = <String>[for (var i = 0; i < 25; i++) 'p${i.toString().padLeft(2, '0')}.md'];
      final note = formatScopeNote(Scoped(many, tip: kTip, mergeHead: kMh), 99)!;
      expect(note, contains('p19.md'));
      expect(note, isNot(contains('p20.md')));
      expect(note, contains('(+5 more)'));
      // the cut is exactly at 20: 20 names print whole, 21 print the 21st as a count
      final twenty = formatScopeNote(Scoped(many.take(20).toList(), tip: kTip, mergeHead: kMh), 99)!;
      expect(twenty, contains('p19.md'));
      expect(twenty, isNot(contains('more)')));
      final twentyOne = formatScopeNote(Scoped(many.take(21).toList(), tip: kTip, mergeHead: kMh), 99)!;
      expect(twentyOne, contains('(+1 more)'));
      expect(twentyOne, isNot(contains('p20.md')));
    });
  });
}
