// test/scripts/local_indexes_e2e_test.dart
//
// Executes the REAL index builders, the REAL orchestrator and the REAL staleness predicate of
// landing A2 (merge-conflict-treadmill): docs/audit/OPEN_INDEX.md and docs/diagnoses/INDEX.md are
// gitignored LOCAL BUILD PRODUCTS (scripts/local_indexes_lib.dart, build_oi_index.dart,
// build_bug_index.dart, build_local_indexes.dart). The two hooks that call the builders are pinned
// in pre_commit_index_add_e2e_test.dart and pre_merge_commit_e2e_test.dart; the SessionStart nudge
// in discipline_hook_local_indexes_e2e_test.dart; the pure validation in bug_index_strict_test.dart.
//
// Each case names the mutant it kills (rule 21). Most run the builders IN PROCESS against a temp
// tree (exit codes are return values, which is the point of the refactor: a builder that still
// called `exit()` would end the test runner and show as a crashed run); the CLI contract
// (exit codes, stderr, root resolution) is checked through a real `dart run`.
//
//   stamp, staleness   deleted doc / added doc / mtime alone / size alone / each BUILDER input /
//                      an unsorted input list                    [each term of statDigest dropped]
//                      a MILLISECOND-only mtime change           [the ms term truncated to seconds]
//                      editor backup, README, INDEX.md          [predicate not shared with the builder]
//                      a directory / dangling link named *.md    [the `is! File` skip dropped]
//                      stat ONCE per input, 256 bytes of output [a contents read in the staleness path;
//                                                                the structural slice test]
//                      a head cut inside a multibyte character   [utf8.decode without allowMalformed]
//   builders           duplicate OI: 1 strict AND lenient        [duplicate fails open in lenient]
//                      unknown status / missing field            [strict made lenient; the OI-68 scar]
//                      lenient FLAGS rather than drops           [`continue` on an unknown status]
//                      a header the section regexp cannot read   [hyphen / en dash / U+2028 vanish silently]
//                      zero issues / no board / no docs dir      [an empty index written; lenient == success]
//                      an unreadable board / docs directory      [an exception instead of exit 1]
//                      dateless or non-ISO doc date              [validation dropped; lenient == strict]
//                      lenient build leaves the nudge silent     [a skipped doc makes the stamp stale forever]
//                      the standalone `dart run` of each builder [main ignores the code / the flag]
//   atomic write       the output's INODE changes on a rebuild   [a non-atomic write]
//                      a non-empty directory at the path -> 3    [write failure exits 1; directory deleted]
//                      temp file unwritable / rename refused -> 3, old output stays   [either failure exits 1]
//                      a rename that succeeds on the RETRY       [the one retry removed]
//                      another build's temp file is never touched [the pid dropped from the temp name]
//                      an empty directory is replaced; stale tmp swept, a non-.tmp file never
//   orchestrator       runs BOTH builders; worst code; self-check [early return; self-check dropped]
//                      a builder that THROWS counts as 1 and the other still runs   [no guard around a builder]
//                      ensureLocalIndexes builds only a MISSING OI index  [the build dropped]
//                      ensureBugIndexFresh builds a missing or stale diagnose index, leaves a fresh one
//                      root: git toplevel from a subdirectory; a `git archive` tree (no .git)
//
// A source-order pin states that each builder takes its stat digest BEFORE reading its inputs
// (review R5D-8); it is presence-only, like every source-grep test.

@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/build_bug_index.dart' show runBugIndex;
import '../../scripts/build_local_indexes.dart';
import '../../scripts/build_oi_index.dart' show runOiIndex, unparseableHeadings;
import '../../scripts/local_indexes_lib.dart';
import '../../scripts/regression_catalog_lib.dart' show extractRecentTestPaths;
import '../helpers/dart_source_slice.dart';
import '../helpers/script_closure_fixture.dart';
import '../helpers/spawn.dart';

String _board(List<String> sections) => '# Open issues\n\n${sections.join()}';

String _oi(int id, {String status = 'OPEN', String? blocked = 'nothing', String? verified = 'never'}) =>
    '## OI-$id — issue $id\n\n'
    '- **Status**: $status\n'
    '${blocked == null ? '' : '- **Blocked on**: $blocked\n'}'
    '${verified == null ? '' : '- **Verified**: $verified\n'}\n';

String _doc(String id,
    {String? date = '2026-10-01', String? symptom = 'it broke', String? bugId, String? testPath}) {
  final b = StringBuffer('---\nbug_id: ${bugId ?? id}\n');
  if (date != null) b.writeln('date: $date');
  if (symptom != null) b.writeln('symptom: $symptom');
  if (testPath != null) b.writeln('contract_test_path: $testPath');
  b.writeln('---\n# $id');
  return b.toString();
}

void main() {
  late String repoRoot;
  late Directory tmp;
  var n = 0;

  setUpAll(() {
    repoRoot = Directory.current.path;
    tmp = Directory.systemTemp.createTempSync('local_indexes_');
  });
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A tree with the real builder scripts (closure of the orchestrator), one open issue and one
  /// diagnose doc. [git] makes it a repo so root resolution can find a toplevel.
  String tree({bool git = false, bool seed = true}) {
    final root = '${tmp.path}/t${n++}';
    Directory(root).createSync(recursive: true);
    copyScriptClosure(repoRoot, root, const ['scripts/build_local_indexes.dart']);
    Directory('$root/docs/audit').createSync(recursive: true);
    Directory('$root/docs/diagnoses').createSync(recursive: true);
    if (seed) {
      File('$root/docs/audit/open_issues.md').writeAsStringSync(_board([_oi(1), _oi(2)]));
      File('$root/docs/diagnoses/2026-10-01-seed-aaaaaa.md').writeAsStringSync(_doc('aaaaaa'));
    }
    if (git) {
      for (final a in const [
        ['init', '-b', 'main', '.'],
        ['config', 'user.email', 't@t.t'],
        ['config', 'user.name', 't'],
      ]) {
        _run('git', a, root);
      }
    }
    return root;
  }

  File f(String root, String rel) => File('$root/$rel');
  String text(String root, String rel) => f(root, rel).readAsStringSync();
  bool has(String root, String rel) => f(root, rel).existsSync(); // file-only: a generated FILE

  ProcessResult cli(String root, List<String> args, {String? cwd, String? script}) => _run(
      dartBin(), ['run', script ?? '$root/scripts/build_local_indexes.dart', ...args], cwd ?? root);

  void bump(String root, String rel, {Duration by = const Duration(hours: 1)}) =>
      f(root, rel).setLastModifiedSync(f(root, rel).lastModifiedSync().add(by));

  group('stamp and staleness', () {
    test('a built tree is fresh; touching the board makes ONLY the OI index stale', () {
      final r = tree();
      expect(isStale(r), isTrue,
          reason: 'never built: both outputs are MISSING, and a missing output counts as stale');
      expect(runLocalIndexes(r), 0);
      expect(isStale(r), isFalse);
      bump(r, 'docs/audit/open_issues.md');
      expect(isStale(r), isTrue);
      final by = {for (final x in localIndexReports(r)) x.spec.id: x.state};
      expect(by['oi'], IndexState.stale);
      expect(by['bug'], IndexState.fresh, reason: 'each index covers ITS OWN inputs');
    });

    test('a rebuild with no input change is BYTE-identical (the stamp is a function of the inputs)', () {
      final r = tree();
      expect(runLocalIndexes(r), 0);
      final oi = text(r, kOiIndexPath), bug = text(r, kBugIndexPath);
      expect(runLocalIndexes(r), 0);
      expect(text(r, kOiIndexPath), oi);
      expect(text(r, kBugIndexPath), bug);
    });

    test('a DELETED diagnose doc changes the stamp  [deletions ignored]', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-02-second-bbbbbb.md').writeAsStringSync(_doc('bbbbbb'));
      expect(runLocalIndexes(r), 0);
      f(r, 'docs/diagnoses/2026-10-02-second-bbbbbb.md').deleteSync();
      expect(indexState(r, kBugIndexSpec), IndexState.stale);
    });

    test('an ADDED diagnose doc changes the stamp  [additions ignored]', () {
      final r = tree();
      expect(runLocalIndexes(r), 0);
      f(r, 'docs/diagnoses/2026-10-02-second-bbbbbb.md').writeAsStringSync(_doc('bbbbbb'));
      expect(indexState(r, kBugIndexSpec), IndexState.stale);
    });

    test('a deleted BOARD changes the OI stamp (a missing input is recorded, not skipped)', () {
      final r = tree();
      expect(runLocalIndexes(r), 0);
      f(r, kOiBoardPath).deleteSync();
      expect(indexState(r, kOiIndexSpec), IndexState.stale);
    });

    test('mtime ALONE changes the digest  [mtime omitted]', () {
      final r = tree();
      final inputs = indexInputPaths(r, kBugIndexSpec);
      final before = statDigest(r, inputs);
      bump(r, 'docs/diagnoses/2026-10-01-seed-aaaaaa.md');
      expect(statDigest(r, inputs), isNot(before));
    });

    test('size ALONE changes the digest  [size omitted]', () {
      final r = tree();
      final inputs = indexInputPaths(r, kBugIndexSpec);
      final file = f(r, 'docs/diagnoses/2026-10-01-seed-aaaaaa.md');
      // Pin the mtime to a WHOLE SECOND first, then restore that same value: File.lastModified and
      // File.setLastModified have SECOND resolution on the Dart VM (measured), so restoring a
      // millisecond mtime moves it by up to 999 ms and the digest would change for the wrong
      // reason (this test once survived the size-omitted mutant that way).
      final fixed = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      file.setLastModifiedSync(fixed);
      final before = statDigest(r, inputs);
      file.writeAsStringSync('${file.readAsStringSync()}x');
      file.setLastModifiedSync(fixed);
      expect(FileStat.statSync(file.path).modified.millisecondsSinceEpoch, fixed.millisecondsSinceEpoch,
          reason: 'the fixture must change the SIZE only: the mtime is back to the same millisecond');
      expect(statDigest(r, inputs), isNot(before));
    });

    test('a MILLISECOND-only mtime change changes the digest  [the ms term truncated to seconds]', () {
      final r = tree();
      final inputs = indexInputPaths(r, kOiIndexSpec);
      final file = '$r/$kOiBoardPath';
      // `touch -d @<sec>.<frac>` because File.setLastModified has SECOND resolution on the Dart VM.
      // Two instants in the SAME second: a scripted edit (`sed -i`, a formatter) right after a
      // build leaves the size alone and moves the mtime by milliseconds, and only the ms term sees it.
      _run('touch', ['-d', '@1700000000.250', file], r);
      final first = statDigest(r, inputs);
      final ms1 = FileStat.statSync(file).modified.millisecondsSinceEpoch;
      _run('touch', ['-d', '@1700000000.750', file], r);
      final second = statDigest(r, inputs);
      final ms2 = FileStat.statSync(file).modified.millisecondsSinceEpoch;
      if (ms2 - ms1 != 500 || ms1 ~/ 1000 != ms2 ~/ 1000) {
        printOnFailure('SKIPPED: this filesystem keeps a coarser mtime than a millisecond ($ms1, $ms2)');
        return;
      }
      expect(second, isNot(first),
          reason: 'same size, same second, mtime $ms1 vs $ms2: the stamp must call it stale');
    }, skip: Platform.isLinux ? false : 'GNU touch -d @seconds.fraction');

    test('the digest does not depend on the ORDER of the input list  [unsorted]', () {
      final r = tree();
      final inputs = indexInputPaths(r, kBugIndexSpec);
      expect(inputs.length, greaterThan(3));
      expect(statDigest(r, inputs.reversed.toList()), statDigest(r, inputs));
    });

    for (final c in const [
      (spec: 'oi', input: 'scripts/build_oi_index.dart'),
      (spec: 'oi', input: 'scripts/local_indexes_lib.dart'),
      (spec: 'bug', input: 'scripts/build_bug_index.dart'),
      (spec: 'bug', input: 'scripts/bug_index_lib.dart'),
      (spec: 'bug', input: 'scripts/local_indexes_lib.dart'),
    ]) {
      test('editing the BUILDER input ${c.input} makes the ${c.spec} index stale  [builder inputs omitted]', () {
        final r = tree();
        expect(runLocalIndexes(r), 0);
        bump(r, c.input);
        final spec = c.spec == 'oi' ? kOiIndexSpec : kBugIndexSpec;
        expect(indexState(r, spec), IndexState.stale);
      });
    }

    test('an editor backup, a README and a TEMPLATE never make the diagnose index stale', () {
      final r = tree();
      expect(runLocalIndexes(r), 0);
      f(r, 'docs/diagnoses/2026-10-01-seed-aaaaaa.md~').writeAsStringSync('backup');
      f(r, 'docs/diagnoses/README.md').writeAsStringSync('# readme');
      f(r, 'docs/diagnoses/TEMPLATE.md').writeAsStringSync('# template');
      expect(indexState(r, kBugIndexSpec), IndexState.fresh);
      expect(runLocalIndexes(r), 0, reason: 'and they do not break the strict build either');
    });

    test('a DIRECTORY or a dangling link named *.md is not a document: never listed, never read  [`is! File` dropped]', () {
      final r = tree();
      Directory('$r/docs/diagnoses/2026-10-05-a-directory-ffffff.md').createSync();
      if (!Platform.isWindows) {
        Link('$r/docs/diagnoses/2026-10-05-dangling-eeeeee.md').createSync('$r/does/not/exist.md');
      }
      expect(diagnoseDocNames(r), ['2026-10-01-seed-aaaaaa.md']);
      expect(runLocalIndexes(r), 0, reason: 'reading a directory would be a reported problem and fail the strict build');
      expect(isStale(r), isFalse);
      expect(text(r, kBugIndexPath), contains('aaaaaa'));
    });

    test('state: missing / no stamp / wrong stamp / fresh', () {
      final r = tree();
      expect(indexState(r, kOiIndexSpec), IndexState.missing);
      f(r, kOiIndexPath).writeAsStringSync('# an index with no stamp\n');
      expect(indexState(r, kOiIndexSpec), IndexState.stale);
      f(r, kOiIndexPath).writeAsStringSync('${stampLine('0' * 64)}\n# body\n');
      expect(indexState(r, kOiIndexSpec), IndexState.stale);
      expect(runOiIndex(r), 0);
      expect(indexState(r, kOiIndexSpec), IndexState.fresh);
    });

    test('a DIRECTORY at the output path reads as missing, not as an exception', () {
      final r = tree();
      Directory('$r/$kOiIndexPath').createSync();
      expect(indexState(r, kOiIndexSpec), IndexState.missing);
    });

    test('parseStamp reads ONLY line 1 and exactly 64 hex digits', () {
      final d = 'a' * 64;
      expect(parseStamp('${stampLine(d)}\n# x'), d);
      expect(parseStamp('${stampLine(d)}\r\n# x'), d, reason: 'a CRLF checkout');
      expect(parseStamp('# title\n${stampLine(d)}\n'), isNull, reason: 'line 2 is not a stamp');
      expect(parseStamp('<!-- local-build: ${'a' * 63} -->\n'), isNull);
      expect(parseStamp('<!-- local-build: ${'A' * 64} -->\n'), isNull, reason: 'lowercase hex only');
      expect(parseStamp(''), isNull);
    });

    test('a head cut INSIDE a multibyte character is still read: the stamp is line 1  [allowMalformed dropped]', () {
      final r = tree();
      final digest = statDigest(r, indexInputPaths(r, kOiIndexSpec));
      // Line 1 is 87 bytes with its newline; 600 bytes of 3-byte characters follow. The 256-byte
      // head therefore ends one byte INTO the 57th character. A strict decode throws on that cut.
      final head = utf8.encode('${stampLine(digest)}\n${'—' * 200}');
      expect(head.length, greaterThan(kStampHeadBytes));
      expect((kStampHeadBytes - 87) % 3, isNonZero, reason: 'the fixture must cut mid-character');
      f(r, kOiIndexPath).writeAsBytesSync(head);
      expect(indexState(r, kOiIndexSpec), IndexState.fresh);
      // And a head of pure garbage is stale, not an exception.
      f(r, kOiIndexPath).writeAsBytesSync(List<int>.filled(300, 0xff));
      expect(indexState(r, kOiIndexSpec), IndexState.stale);
    });

    test('the staleness path stats each input ONCE and reads 256 bytes of each output', () {
      final r = tree();
      expect(runLocalIndexes(r), 0);
      final stats = <String>[];
      final heads = <int>[];
      final stale = isStale(r,
          stat: (p) {
            stats.add(p);
            return FileStat.statSync(p);
          },
          readHead: (p, max) {
            heads.add(max);
            return readHeadBytes(p, max);
          });
      expect(stale, isFalse);
      final expected = [
        ...indexInputPaths(r, kOiIndexSpec),
        ...indexInputPaths(r, kBugIndexSpec),
      ].map((p) => '$r/$p').toList()
        ..sort();
      expect(stats.toList()..sort(), expected, reason: 'one stat per input per index, nothing else');
      expect(heads, [kStampHeadBytes, kStampHeadBytes]);
      // The constant is a bound on both sides: the stamp line must fit (too small and every output
      // reads as stale), and the head stays a few hundred bytes (the nudge must never read a body).
      expect(stampLine('a' * 64).length + 1, lessThanOrEqualTo(kStampHeadBytes));
      expect(kStampHeadBytes, lessThanOrEqualTo(1024));
    });

    test('STRUCTURE: no function of the staleness path reads a document body', () {
      final src = stripDartComments(File('scripts/local_indexes_lib.dart').readAsStringSync());
      // Every function the nudge's staleness check runs, INCLUDING the two that list every
      // diagnose doc on every SessionStart: a read added to either would cost one file read per
      // document there and no other pin would notice.
      for (final header in const [
        'String statDigest(',
        'IndexState indexState(',
        'List<IndexReport> localIndexReports(',
        'bool isStale(',
        'List<String> diagnoseDocNames(',
        'List<String> indexInputPaths(',
      ]) {
        final body = functionBody(src, header);
        for (final read in const ['readAsStringSync', 'readAsBytesSync', 'readAsLinesSync', 'readAsString(', 'readAsBytes(', 'openRead(']) {
          expect(body, isNot(contains(read)),
              reason: '$header must stay stat-only (the nudge runs on every SessionStart): $read');
        }
      }
    });

    test('STRUCTURE: each builder takes its stat digest BEFORE it reads an input (R5D-8)', () {
      for (final c in const [
        (file: 'scripts/build_oi_index.dart', read: 'readAsStringSync('),
        (file: 'scripts/build_bug_index.dart', read: 'readAsStringSync('),
      ]) {
        final src = stripDartComments(File(c.file).readAsStringSync());
        final digest = src.indexOf('statDigest(');
        final read = src.indexOf(c.read);
        expect(digest, isNonNegative, reason: '${c.file} must stamp from a stat digest');
        expect(read, isNonNegative);
        expect(digest, lessThan(read),
            reason: '${c.file}: stats taken AFTER the read would stamp a newer mtime on older content');
      }
    });
  });

  group('the OI builder', () {
    test('a duplicate `## OI-N` fails in STRICT and in LENIENT, and writes nothing', () {
      for (final strict in [true, false]) {
        final r = tree();
        f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2), _oi(2)]));
        expect(runOiIndex(r, strict: strict), 1, reason: 'strict=$strict');
        expect(has(r, kOiIndexPath), isFalse, reason: 'strict=$strict');
      }
    });

    test('an UNKNOWN status fails strict; lenient renders it FLAGGED (the OI-68 scar: never dropped)', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2, status: 'PENDING')]));
      expect(runOiIndex(r), 1);
      expect(has(r, kOiIndexPath), isFalse);
      expect(runOiIndex(r, strict: false), 0);
      final out = text(r, kOiIndexPath);
      expect(out, contains('| OI-2 | ⚠ unknown status "PENDING": issue 2 |'));
      expect(out, contains('## Needs attention (lenient build)'));
      expect(out, contains('OI-2'), reason: 'the offender is listed');
    });

    test('a MISSING field fails strict; lenient renders `⚠ missing`', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2, blocked: null)]));
      expect(runOiIndex(r), 1);
      expect(runOiIndex(r, strict: false), 0);
      final row = text(r, kOiIndexPath).split('\n').firstWhere((l) => l.startsWith('| OI-2 |'));
      expect(row, contains('⚠ missing'));
    });

    test('an entry with NO Status line is flagged in lenient, an error in strict', () {
      final r = tree();
      f(r, kOiBoardPath)
          .writeAsStringSync(_board([_oi(1), '## OI-3 — no status\n\n- **Blocked on**: none\n- **Verified**: never\n\n']));
      expect(runOiIndex(r), 1);
      expect(runOiIndex(r, strict: false), 0);
      expect(text(r, kOiIndexPath), contains('⚠ no Status line'));
    });

    test('ZERO open issues is refused in both modes (an empty index looks like a clean backlog)', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1, status: 'CLOSED')]));
      expect(runOiIndex(r), 1);
      expect(runOiIndex(r, strict: false), 1);
      expect(has(r, kOiIndexPath), isFalse);
    });

    test('a missing board is a failure in BOTH modes, not a crash and not a success', () {
      final r = tree();
      f(r, kOiBoardPath).deleteSync();
      expect(runOiIndex(r), 1);
      expect(runOiIndex(r, strict: false), 1,
          reason: 'lenient skips offending ROWS; with no board there is nothing to build, and ensureLocalIndexes '
              '(lenient) must not report success for an index it did not write');
      expect(has(r, kOiIndexPath), isFalse);
    });

    test('a board that is not valid UTF-8 is a reported failure (exit 1) in both modes, not an exception', () {
      for (final strict in [true, false]) {
        final r = tree();
        // An em dash re-saved as the single byte 0x97 by a Windows editor.
        f(r, kOiBoardPath).writeAsBytesSync([...utf8.encode(_board([_oi(1)])), 0x97, 0x0a]);
        expect(runOiIndex(r, strict: strict), 1, reason: 'strict=$strict');
        expect(has(r, kOiIndexPath), isFalse, reason: 'strict=$strict');
      }
    });

    // The OI-68 scar one step earlier: `_sectionRe` is the first thing every check applies, so a
    // header it cannot read is invisible to all of them and the issue vanishes with exit 0.
    // U+2028 is built from its code point: a literal one in this source would split the line.
    for (final c in <(String, String)>[
      ('a hyphen instead of the em dash', '## OI-3 - typed where there is no em dash key'),
      ('an en dash instead of the em dash', '## OI-3 ${String.fromCharCode(0x2013)} en dash'),
      ('a Unicode line separator inside the title', '## OI-3 — split${String.fromCharCode(0x2028)}title'),
      ('no title at all', '## OI-3'),
    ]) {
      test('a header the section regexp cannot read (${c.$1}): strict fails, lenient lists it', () {
        final r = tree();
        f(r, kOiBoardPath).writeAsStringSync(_board([
          _oi(1),
          '${c.$2}\n\n- **Status**: OPEN\n- **Blocked on**: none\n- **Verified**: never\n\n',
        ]));
        expect(runOiIndex(r), 1, reason: 'the issue would be silently absent from the index');
        expect(has(r, kOiIndexPath), isFalse);
        expect(runOiIndex(r, strict: false), 0);
        final out = text(r, kOiIndexPath);
        expect(out, contains('## Needs attention (lenient build)'));
        expect(out, contains('- line 9: '), reason: 'the header sits on line 9 of this board');
        expect(out, contains('| OI-1 |'), reason: 'the readable issue is still indexed');
      });
    }

    test('unparseableHeadings: only a header-looking line that does NOT parse; sub-headings and prose are not headers', () {
      expect(unparseableHeadings('## OI-1 — fine\n## OI-2 - bad\n### OI-3 - a sub-heading\ntext ## OI-4 - prose\n'),
          hasLength(1));
      expect(unparseableHeadings('## OI-1 — fine\r\n## OI-2 — also fine\r\n'), isEmpty,
          reason: 'a CRLF board has no unreadable headers');
      expect(unparseableHeadings('## OI-2 - bad').single, startsWith('line 1: '));
    });

    test('the REAL board has no unreadable header (the rule is satisfiable by the repo)', () {
      expect(unparseableHeadings(File(kOiBoardPath).readAsStringSync()), isEmpty);
    });

    test('the header carries the reader-side guard and the new re-run command', () {
      final r = tree();
      expect(runOiIndex(r), 0);
      final t = text(r, kOiIndexPath);
      expect(t, startsWith('<!-- local-build: '));
      expect(t, contains('must be `## OI-N —`'));
      expect(t, contains('dart run scripts/build_local_indexes.dart --lenient'));
    });
  });

  group('the diagnose builder', () {
    test('a dateless doc: strict 1 (nothing written), lenient 0 (skipped, rest written)', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-02-wip-cccccc.md').writeAsStringSync(_doc('cccccc', date: null));
      expect(runBugIndex(r), 1);
      expect(has(r, kBugIndexPath), isFalse);
      expect(runBugIndex(r, strict: false), 0);
      final t = text(r, kBugIndexPath);
      expect(t, contains('aaaaaa'));
      expect(t, isNot(contains('cccccc')), reason: 'a skipped doc is absent, and the run said so');
    });

    test('a lenient build leaves the nudge silent for a dateless WIP doc (its stats are inputs, so the stamp is fresh)', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-02-wip-cccccc.md').writeAsStringSync(_doc('cccccc', date: null));
      expect(runLocalIndexes(r, strict: false), 0);
      expect(isStale(r), isFalse,
          reason: 'otherwise every WIP doc would nag every session until it is finished');
    });

    for (final c in <(String, String Function())>[
      ('no frontmatter', () => '# just prose\n'),
      ('no symptom', () => _doc('dddddd', symptom: null)),
      ('a bug_id that is not the suffix', () => _doc('dddddd', bugId: 'zzz999')),
    ]) {
      test('strict refuses a doc with ${c.$1}', () {
        final r = tree();
        f(r, 'docs/diagnoses/2026-10-03-bad-dddddd.md').writeAsStringSync(c.$2());
        expect(runBugIndex(r), 1);
        expect(has(r, kBugIndexPath), isFalse);
      });
    }

    test('the 12 legacy shapes: a doc whose bug_id is the WHOLE STEM is indexed', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-05-16-health-write-service.md')
          .writeAsStringSync(_doc('x', bugId: '2026-05-16-health-write-service'));
      expect(runBugIndex(r), 0);
      expect(text(r, kBugIndexPath), contains('2026-05-16-health-write-service'));
    });

    test('an unreadable doc (invalid UTF-8) is a reported problem, not a crash', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-03-binary-eeeeee.md').writeAsBytesSync([0xff, 0xfe, 0xfd, 0x00]);
      expect(runBugIndex(r), 1);
      expect(runBugIndex(r, strict: false), 0);
    });

    test('the output keeps the pre-A2 body: newest first, one row per doc', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-05-newer-bbbbbb.md').writeAsStringSync(_doc('bbbbbb', date: '2026-10-05'));
      expect(runBugIndex(r), 0);
      final rows = text(r, kBugIndexPath).split('\n').where((l) => l.startsWith('| 2026-')).toList();
      expect(rows.first, startsWith('| 2026-10-05 | bbbbbb |'));
      expect(rows.last, startsWith('| 2026-10-01 | aaaaaa |'));
    });

    test('docs sharing a DATE are listed by path: a stable total order, however many there are (f4d1b7)', () {
      final r = tree();
      // 80 docs on ONE date. Dart's List.sort is not stable above its insertion-sort threshold, so
      // without the path tiebreak the order of equal dates is whatever the algorithm leaves behind.
      for (var i = 0; i < 80; i++) {
        final id = 'a${i.toString().padLeft(5, '0')}';
        f(r, 'docs/diagnoses/2026-10-09-same-day-$id.md')
            .writeAsStringSync(_doc(id, date: '2026-10-09'));
      }
      expect(runBugIndex(r), 0);
      final rows = text(r, kBugIndexPath).split('\n').where((l) => l.startsWith('| 2026-10-09 |')).toList();
      expect(rows, hasLength(80));
      final ids = [for (final l in rows) l.split('|')[2].trim()];
      expect(ids, [...ids]..sort(), reason: 'equal dates are ordered by path, so a rebuild is deterministic');
    });

    test('no docs/diagnoses directory: 1 in BOTH modes and nothing written (a tree without the docs is not a success)', () {
      final r = tree();
      Directory('$r/docs/diagnoses').deleteSync(recursive: true);
      expect(runBugIndex(r), 1);
      expect(runBugIndex(r, strict: false), 1,
          reason: 'lenient skips offending DOCS; with no directory there is nothing to index');
      expect(has(r, kBugIndexPath), isFalse);
    });

    // The date is the only column the merge-commit regression walk reads from the index
    // (regression_catalog_lib.dart keeps a row only when its first cell is YYYY-MM-DD), and Gate 25
    // is gone: a date the walk cannot read must be refused HERE, or that bug's regression test
    // silently stops running at merges.
    for (final c in <(String, String)>[
      ('a quoted ISO date', '"2026-10-24"'),
      ('free text', 'soon'),
      ('a day-first date', '24/10/2026'),
      ('an ISO date with a time', '2026-10-24T09:00:00'),
    ]) {
      test('a doc whose date is ${c.$1}: strict refuses it, lenient skips it and says so', () {
        final r = tree();
        f(r, 'docs/diagnoses/2026-10-24-odd-date-bbbbbb.md')
            .writeAsStringSync(_doc('bbbbbb', date: c.$2, testPath: 'test/contracts/odd_date_test.dart'));
        expect(runBugIndex(r), 1);
        expect(has(r, kBugIndexPath), isFalse);
        expect(runBugIndex(r, strict: false), 0);
        expect(text(r, kBugIndexPath), isNot(contains('odd_date_test')),
            reason: 'a skipped doc is absent from the index');
      });
    }

    test('every row the index renders is one the regression walk can read (render -> extractRecentTestPaths)', () {
      final r = tree();
      // Lenient on purpose: the odd-date docs must be SKIPPED, not rendered as unreadable rows.
      f(r, 'docs/diagnoses/2026-10-02-good-bbbbbb.md')
          .writeAsStringSync(_doc('bbbbbb', date: '2026-10-02', testPath: 'test/contracts/good_b_test.dart'));
      f(r, 'docs/diagnoses/2026-10-03-good-cccccc.md')
          .writeAsStringSync(_doc('cccccc', date: '2026-10-03', testPath: 'test/contracts/good_c_test.dart'));
      f(r, 'docs/diagnoses/2026-10-04-quoted-dddddd.md')
          .writeAsStringSync(_doc('dddddd', date: '"2026-10-04"', testPath: 'test/contracts/quoted_test.dart'));
      f(r, 'docs/diagnoses/2026-10-05-free-eeeeee.md')
          .writeAsStringSync(_doc('eeeeee', date: 'soon', testPath: 'test/contracts/free_test.dart'));
      expect(runBugIndex(r, strict: false), 0);
      final index = text(r, kBugIndexPath);
      final rows = index.split('\n').where((l) => l.startsWith('| ') && !l.startsWith('| Date')).toList();
      expect(rows, hasLength(3), reason: 'the seed doc and the two good ones');
      for (final l in rows) {
        expect(RegExp(r'^\|\s*\d{4}-\d{2}-\d{2}\s*\|').hasMatch(l), isTrue,
            reason: 'the regression walk drops a row whose first cell is not YYYY-MM-DD: $l');
      }
      expect(extractRecentTestPaths(index, DateTime(2000)),
          {'test/contracts/good_b_test.dart', 'test/contracts/good_c_test.dart'});
    });

    test('an unreadable docs/diagnoses directory is a reported failure in both modes, not an exception', () {
      final r = tree();
      // Mode 111: the directory can be entered but not listed.
      _run('chmod', ['111', '$r/docs/diagnoses'], r);
      addTearDown(() => _run('chmod', ['755', '$r/docs/diagnoses'], r));
      var listable = true;
      try {
        Directory('$r/docs/diagnoses').listSync();
      } on FileSystemException {
        listable = false;
      }
      if (listable) {
        printOnFailure('SKIPPED: the permission bit does not bind this user (root?)');
        return;
      }
      expect(runBugIndex(r), 1);
      expect(runBugIndex(r, strict: false), 1);
      expect(has(r, kBugIndexPath), isFalse);
      // The orchestrator turns it into 1 as well, and the OI index is still built.
      expect(runLocalIndexes(r), 1);
      expect(has(r, kOiIndexPath), isTrue, reason: 'one unreadable directory must not hide the OI index');
    }, skip: Platform.isWindows ? 'POSIX-only: chmod' : false);
  });

  group('the atomic write', () {
    String inode(String path) =>
        (_run('ls', ['-i', path], Directory.current.path).stdout as String).trim().split(RegExp(r'\s+')).first;

    test('the output inode CHANGES across a rebuild (temp + rename, never an in-place write)', () {
      final r = tree();
      expect(runOiIndex(r), 0);
      final before = inode('$r/$kOiIndexPath');
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2), _oi(3)]));
      expect(runOiIndex(r), 0);
      expect(inode('$r/$kOiIndexPath'), isNot(before),
          reason: 'an in-place write lets a reader see half a file and keeps the inode');
    }, skip: Platform.isWindows ? 'POSIX-only: inodes' : false);

    test('a NON-EMPTY directory at the path: 3, a warning, the directory and its content untouched', () {
      final r = tree();
      Directory('$r/$kOiIndexPath').createSync();
      f(r, '$kOiIndexPath/keep.txt').writeAsStringSync('x');
      final warned = <String>[];
      expect(writeLocalIndex(r, kOiIndexPath, 'body', warn: warned.add), kWriteFailedExit);
      expect(warned.single, contains('non-empty directory'));
      expect(has(r, '$kOiIndexPath/keep.txt'), isTrue);
      expect(runOiIndex(r), kWriteFailedExit, reason: 'the builder reports it as 3, not 1');
    });

    test('the temp file cannot be written (.dart_tool is a FILE): 3, a warning, the old output stays', () {
      final r = tree();
      expect(runOiIndex(r), 0);
      final before = text(r, kOiIndexPath);
      Directory('$r/.dart_tool').deleteSync(recursive: true);
      f(r, '.dart_tool').writeAsStringSync('not a directory');
      final warned = <String>[];
      expect(writeLocalIndex(r, kOiIndexPath, 'new body', warn: warned.add), kWriteFailedExit);
      expect(warned.single, contains('could not write the temp file'));
      expect(text(r, kOiIndexPath), before, reason: 'a failed write leaves the old output in place');
      expect(runOiIndex(r), kWriteFailedExit, reason: 'a builder reports it as 3, not 1');
    });

    test('the rename is refused (a read-only parent directory): 3, a warning, the old output stays, no temp left', () {
      final r = tree();
      expect(runOiIndex(r), 0);
      final before = text(r, kOiIndexPath);
      final parent = '$r/docs/audit';
      _run('chmod', ['555', parent], r);
      addTearDown(() => _run('chmod', ['755', parent], r));
      // Some CI containers run as root, where a read-only directory still accepts writes: probe,
      // and say so instead of asserting something the platform cannot produce.
      final probe = File('$parent/.probe');
      var bound = true;
      try {
        probe.writeAsStringSync('x');
        probe.deleteSync();
        bound = false;
      } on FileSystemException {
        bound = true;
      }
      if (!bound) {
        printOnFailure('SKIPPED: the permission bit does not bind this user (root?)');
        return;
      }
      final warned = <String>[];
      expect(
          writeLocalIndex(r, kOiIndexPath, 'new body',
              warn: warned.add, retryDelay: Duration.zero),
          kWriteFailedExit);
      expect(warned.single, contains('could not replace'));
      expect(text(r, kOiIndexPath), before, reason: 'a failed rename leaves the old output in place');
      expect(Directory('$r/.dart_tool/local_indexes').listSync(), isEmpty,
          reason: 'the temp file of the failed write is removed');
      expect(runOiIndex(r), kWriteFailedExit, reason: 'a builder reports it as 3, not 1');
    }, skip: Platform.isWindows ? 'POSIX-only: chmod' : false);

    test('a rename that is refused ONCE and then allowed succeeds on the retry  [the one retry removed]', () async {
      final r = tree();
      final parent = '$r/docs/audit';
      _run('chmod', ['555', parent], r);
      addTearDown(() => _run('chmod', ['755', parent], r));
      var bound = true;
      try {
        File('$parent/.probe').writeAsStringSync('x');
        File('$parent/.probe').deleteSync();
        bound = false;
      } on FileSystemException {
        bound = true;
      }
      if (!bound) {
        printOnFailure('SKIPPED: the permission bit does not bind this user (root?)');
        return;
      }
      // A sibling process lifts the restriction 300 ms after this process's TEMP file appears.
      // The temp file is written immediately before the first rename, so that rename is refused;
      // the retry (after 1500 ms) finds the directory writable. Anchoring on the temp file rather
      // than on a bare delay keeps the order deterministic on a loaded machine.
      final temp = '$r/.dart_tool/local_indexes/OPEN_INDEX.md.$pid.tmp';
      final lifter = runSpawnAsync(
        'sh',
        [
          '-c',
          'i=0; while [ ! -e "\$1" ] && [ \$i -lt 500 ]; do sleep 0.02; i=\$((i+1)); done; '
              'sleep 0.3; chmod 755 "\$2"',
          'sh',
          temp,
          parent,
        ],
        why: 'local_indexes_e2e: lift the read-only parent after the first rename was refused',
      );
      await Future<void>.delayed(const Duration(milliseconds: 150)); // let the sibling start
      final warned = <String>[];
      final rc = writeLocalIndex(r, kOiIndexPath, 'retried body',
          warn: warned.add, retryDelay: const Duration(milliseconds: 1500));
      await lifter;
      expect(rc, 0, reason: 'the second rename must succeed once the directory is writable: $warned');
      expect(warned, isEmpty);
      expect(text(r, kOiIndexPath), 'retried body');
    }, skip: Platform.isWindows ? 'POSIX-only: chmod' : false);

    test('an EMPTY directory at the path is replaced by the output', () {
      final r = tree();
      Directory('$r/$kOiIndexPath').createSync();
      expect(runOiIndex(r), 0);
      expect(FileSystemEntity.isFileSync('$r/$kOiIndexPath'), isTrue);
    });

    test('a validation failure still wins over a write failure: duplicate OI + blocked path = 1', () {
      final r = tree();
      Directory('$r/$kOiIndexPath').createSync();
      f(r, '$kOiIndexPath/keep.txt').writeAsStringSync('x');
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(1)]));
      expect(runOiIndex(r), 1);
    });

    test('no temp file is left behind, and temp files older than an hour are swept (fresh ones and non-.tmp files kept)', () {
      final r = tree();
      final dir = Directory('$r/.dart_tool/local_indexes')..createSync(recursive: true);
      final old = File('${dir.path}/old.tmp')..writeAsStringSync('x');
      old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
      final fresh = File('${dir.path}/fresh.tmp')..writeAsStringSync('x');
      // Old, but NOT a temp file: the sweep is for `*.tmp` only and must never delete anything else
      // that happens to live in the directory.
      final notes = File('${dir.path}/notes.txt')..writeAsStringSync('keep me');
      notes.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 2)));
      expect(writeLocalIndex(r, kOiIndexPath, 'body'), 0);
      expect(old.existsSync(), isFalse, reason: 'a leftover of a killed build'); // file-only: a temp FILE
      expect(fresh.existsSync(), isTrue, reason: 'it may belong to a build in flight'); // file-only: a temp FILE
      expect(notes.existsSync(), isTrue, reason: 'only `*.tmp` is swept'); // file-only: a plain FILE
      expect(dir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last),
          unorderedEquals(['fresh.tmp', 'notes.txt']),
          reason: 'this process\'s own temp file was renamed away');
    });
  });

  group('the atomic write: concurrent builds', () {
    test('another build\'s temp file is never touched: the name carries this process\'s pid', () {
      final r = tree();
      final dir = Directory('$r/.dart_tool/local_indexes')..createSync(recursive: true);
      // A different pid, and the pid-LESS name a build that forgot its pid would use.
      final other = File('${dir.path}/OPEN_INDEX.md.12345.tmp')..writeAsStringSync('other build');
      final pidless = File('${dir.path}/OPEN_INDEX.md.tmp')..writeAsStringSync('pid-less build');
      expect(runOiIndex(r), 0);
      expect(other.readAsStringSync(), 'other build'); // file-only: a temp FILE
      expect(pidless.readAsStringSync(), 'pid-less build',
          reason: 'with a pid-less temp name two concurrent builds write and rename ONE file: a torn index');
    });
  });

  group('the orchestrator', () {
    test('worstExit: 1 beats 3 beats 0, and an unknown non-zero code counts as 1', () {
      expect(worstExit([0, 0]), 0);
      expect(worstExit([0, 3]), 3);
      expect(worstExit([3, 0]), 3);
      expect(worstExit([3, 3]), 3);
      expect(worstExit([3, 1]), 1);
      expect(worstExit([1, 3]), 1);
      expect(worstExit([0, 2]), 1);
    });

    test('BOTH builders run even when the first fails (one bad index must not hide the other)', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(1)]));
      expect(runLocalIndexes(r), 1);
      expect(has(r, kOiIndexPath), isFalse);
      expect(has(r, kBugIndexPath), isTrue, reason: 'the diagnose index was still built');
    });

    test('a board that is not valid UTF-8: exit 1, and the diagnose index is STILL built (both builders run)', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsBytesSync([...utf8.encode(_board([_oi(1)])), 0x97, 0x0a]);
      expect(runLocalIndexes(r), 1);
      expect(runLocalIndexes(r, strict: false), 1);
      expect(has(r, kOiIndexPath), isFalse);
      expect(has(r, kBugIndexPath), isTrue, reason: 'the header promises both builders always run');
    });

    test('a builder that THROWS counts as 1, is named, and does not stop the other  [no guard around a builder]', () {
      for (final first in [true, false]) {
        final r = tree();
        int boom(String root, {bool? strict}) => throw StateError('boom in the ${first ? 'oi' : 'bug'} builder');
        final rc = runLocalIndexes(r,
            oiBuilder: first ? boom : runOiIndex, bugBuilder: first ? runBugIndex : boom);
        expect(rc, 1, reason: 'first=$first');
        expect(has(r, first ? kBugIndexPath : kOiIndexPath), isTrue,
            reason: 'the OTHER builder still ran (first=$first)');
        expect(has(r, first ? kOiIndexPath : kBugIndexPath), isFalse, reason: 'first=$first');
      }
    });

    test('a write failure on one index and success on the other is exit 3', () {
      final r = tree();
      Directory('$r/$kBugIndexPath').createSync();
      f(r, '$kBugIndexPath/keep.txt').writeAsStringSync('x');
      expect(runLocalIndexes(r), kWriteFailedExit);
      expect(has(r, kOiIndexPath), isTrue);
    });

    test('the SELF-CHECK turns "built but stale" into a failure', () {
      final r = tree();
      expect(runLocalIndexes(r, staleCheck: (_) => true), 1);
      expect(runLocalIndexes(r, staleCheck: (_) => false), 0);
    });

    test('ensureLocalIndexes builds a MISSING OI index, and only that', () {
      final r = tree();
      expect(has(r, kOiIndexPath), isFalse);
      expect(ensureLocalIndexes(r), 0);
      expect(has(r, kOiIndexPath), isTrue, reason: 'the build was dropped');
      expect(has(r, kBugIndexPath), isFalse, reason: 'nothing in test/ reads the diagnose index');
      // A SENTINEL, not an mtime: File.lastModified has second resolution, so a rewrite within the
      // same second is invisible to it (the always-rebuild mutant survived that way).
      f(r, kOiIndexPath).writeAsStringSync('SENTINEL: an existing index is left alone\n');
      expect(ensureLocalIndexes(r), 0);
      expect(text(r, kOiIndexPath), startsWith('SENTINEL'),
          reason: 'an existing index is left alone, even a stale one: ensure is for a MISSING one');
    });

    test('ensureLocalIndexes is LENIENT: a board with an unknown status still gets an index', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2, status: 'PENDING')]));
      expect(ensureLocalIndexes(r), 0);
      expect(text(r, kOiIndexPath), contains('unknown status'));
    });

    // ensureBugIndexFresh is what check_regression_catalog.dart calls before it walks the index:
    // an installed pre-commit hook that predates A2 never builds it (hooks are copies).
    test('ensureBugIndexFresh builds a MISSING diagnose index', () {
      final r = tree();
      expect(has(r, kBugIndexPath), isFalse);
      expect(ensureBugIndexFresh(r), 0);
      expect(indexState(r, kBugIndexSpec), IndexState.fresh);
      expect(has(r, kOiIndexPath), isFalse, reason: 'it builds the diagnose index and nothing else');
    });

    test('ensureBugIndexFresh REBUILDS a stale diagnose index (a merge brought in new docs)', () {
      final r = tree();
      expect(runBugIndex(r), 0);
      f(r, 'docs/diagnoses/2026-10-06-merged-in-bbbbbb.md')
          .writeAsStringSync(_doc('bbbbbb', date: '2026-10-06', testPath: 'test/contracts/merged_in_test.dart'));
      expect(indexState(r, kBugIndexSpec), IndexState.stale);
      expect(ensureBugIndexFresh(r), 0);
      expect(text(r, kBugIndexPath), contains('merged_in_test.dart'));
      expect(indexState(r, kBugIndexSpec), IndexState.fresh);
    });

    test('ensureBugIndexFresh leaves a FRESH index alone and is LENIENT about a doc strict would refuse', () {
      final r = tree();
      expect(runBugIndex(r), 0);
      f(r, kBugIndexPath).writeAsStringSync(
          '${stampLine(statDigest(r, indexInputPaths(r, kBugIndexSpec)))}\nSENTINEL: a fresh index is left alone\n');
      expect(ensureBugIndexFresh(r), 0);
      expect(text(r, kBugIndexPath), contains('SENTINEL'));
      // A doc strict would refuse (no date): the walk's build skips it instead of blocking a merge.
      f(r, 'docs/diagnoses/2026-10-07-wip-cccccc.md').writeAsStringSync(_doc('cccccc', date: null));
      expect(ensureBugIndexFresh(r), 0);
      expect(text(r, kBugIndexPath), isNot(contains('SENTINEL')), reason: 'the new doc made it stale: rebuilt');
      expect(text(r, kBugIndexPath), isNot(contains('cccccc')));
    });
  });

  group('root resolution', () {
    test('a subdirectory of a repo that holds the script resolves to the git toplevel', () {
      final r = tree(git: true);
      final sub = Directory('$r/docs/audit');
      final resolved = resolveLocalIndexesRoot(cwd: sub.path);
      expect(Directory(resolved).resolveSymbolicLinksSync(), Directory(r).resolveSymbolicLinksSync());
    });

    // Compared as canonical paths: on Windows `File.fromUri` yields backslashes while the fixture
    // path is mixed, and the two spellings name the same directory.
    String canon(String p) => Directory(p).resolveSymbolicLinksSync();

    test('a directory outside any repo falls back to the parent of the script directory', () {
      final r = tree();
      final elsewhere = Directory('${tmp.path}/elsewhere${n++}')..createSync();
      expect(
          canon(resolveLocalIndexesRoot(
              cwd: elsewhere.path, script: Uri.file('$r/scripts/build_local_indexes.dart'))),
          canon(r));
    });

    test('a repo that does NOT hold the script is not used as the root', () {
      final r = tree();
      final other = '${tmp.path}/other${n++}';
      Directory(other).createSync();
      _run('git', ['init', '-b', 'main', '.'], other);
      expect(
          canon(resolveLocalIndexesRoot(
              cwd: other, script: Uri.file('$r/scripts/build_local_indexes.dart'))),
          canon(r));
    });
  });

  group('the CLI (a real `dart run`)', () {
    test('strict: a duplicate OI exits 1 and names it; the diagnose index is still built', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2), _oi(2)]));
      final res = cli(r, const []);
      expect(res.exitCode, 1, reason: _diag(res));
      expect('${res.stderr}', contains('OI-2 appears 2 times'));
      expect(has(r, kOiIndexPath), isFalse);
      expect(has(r, kBugIndexPath), isTrue);
    });

    test('--lenient: an unknown status exits 0 with a WARNING that names it', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2, status: 'PENDING')]));
      final res = cli(r, const ['--lenient']);
      expect(res.exitCode, 0, reason: _diag(res));
      expect('${res.stderr}', contains('WARNING (lenient)'));
      expect('${res.stderr}', contains('OI-2'));
    });

    test('--lenient: a dateless doc is SKIPPED and named; strict names the missing field', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-02-wip-cccccc.md').writeAsStringSync(_doc('cccccc', date: null));
      final strict = cli(r, const []);
      expect(strict.exitCode, 1, reason: _diag(strict));
      expect('${strict.stderr}', contains('missing `date:`'));
      final lenient = cli(r, const ['--lenient']);
      expect(lenient.exitCode, 0, reason: _diag(lenient));
      expect('${lenient.stderr}', contains('SKIPPED'));
      expect('${lenient.stderr}', contains('2026-10-02-wip-cccccc.md'));
    });

    test('a write failure exits 3 (not 1) with the reason on stderr', () {
      final r = tree();
      Directory('$r/$kOiIndexPath').createSync();
      f(r, '$kOiIndexPath/keep.txt').writeAsStringSync('x');
      final res = cli(r, const []);
      expect(res.exitCode, 3, reason: _diag(res));
      expect('${res.stderr}', contains('non-empty directory'));
      expect(has(r, kBugIndexPath), isTrue);
    });

    test('a board that is not valid UTF-8 exits 1 (not 255 with a stack trace) and names the file', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsBytesSync([...utf8.encode(_board([_oi(1)])), 0x97, 0x0a]);
      for (final args in const [<String>[], ['--lenient']]) {
        final res = cli(r, args);
        expect(res.exitCode, 1, reason: _diag(res));
        expect('${res.stderr}', contains('open_issues.md is unreadable'));
        expect('${res.stderr}', isNot(contains('Unhandled exception')));
        expect(has(r, kBugIndexPath), isTrue, reason: 'the diagnose index was still built (${args.join(' ')})');
        f(r, kBugIndexPath).deleteSync();
      }
    });

    test('run from a SUBDIRECTORY (cwd != root) it builds at the git toplevel', () {
      final r = tree(git: true);
      final res = cli(r, const [], cwd: '$r/docs');
      expect(res.exitCode, 0, reason: _diag(res));
      expect(has(r, kOiIndexPath), isTrue);
      expect(has(r, kBugIndexPath), isTrue);
      expect(Directory('$r/docs/docs').existsSync(), isFalse, reason: 'nothing is written relative to the cwd');
    });

    test('a `git archive` tree (no .git) builds beside its own scripts directory', () {
      final r = tree();
      expect(Directory('$r/.git').existsSync(), isFalse);
      final elsewhere = Directory('${tmp.path}/cwd${n++}')..createSync();
      final res = cli(r, const [], cwd: elsewhere.path);
      expect(res.exitCode, 0, reason: _diag(res));
      expect(has(r, kOiIndexPath), isTrue);
      expect(elsewhere.listSync(), isEmpty);
    });
  });

  // pre-commit, pre-merge-commit and CI run the STANDALONE builders (`dart run
  // scripts/build_oi_index.dart`), not the orchestrator. Their `main` is one line that turns the
  // builder's return value into the process exit code; a `main` that ran the builder and exited 0
  // would turn every validation failure into a green commit and none of the in-process tests above
  // could see it.
  group('the standalone builders (a real `dart run` of each script)', () {
    ProcessResult standalone(String r, String script, [List<String> args = const []]) =>
        _run(dartBin(), ['run', '$r/scripts/$script', ...args], r);

    test('build_oi_index.dart forwards the builder\'s code: 0 written, 1 validation, 3 write', () {
      final ok = tree();
      final good = standalone(ok, 'build_oi_index.dart');
      expect(good.exitCode, 0, reason: _diag(good));
      expect(has(ok, kOiIndexPath), isTrue);

      final dup = tree();
      f(dup, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(1)]));
      final bad = standalone(dup, 'build_oi_index.dart');
      expect(bad.exitCode, 1, reason: _diag(bad));
      expect('${bad.stderr}', contains('OI-1 appears 2 times'));

      final blocked = tree();
      Directory('$blocked/$kOiIndexPath').createSync();
      f(blocked, '$kOiIndexPath/keep.txt').writeAsStringSync('x');
      final three = standalone(blocked, 'build_oi_index.dart');
      expect(three.exitCode, 3, reason: _diag(three));
    });

    test('build_oi_index.dart passes --lenient through to the builder', () {
      final r = tree();
      f(r, kOiBoardPath).writeAsStringSync(_board([_oi(1), _oi(2, status: 'PENDING')]));
      expect(standalone(r, 'build_oi_index.dart').exitCode, 1);
      final lenient = standalone(r, 'build_oi_index.dart', const ['--lenient']);
      expect(lenient.exitCode, 0, reason: _diag(lenient));
      expect(text(r, kOiIndexPath), contains('unknown status'));
    });

    test('build_bug_index.dart forwards the builder\'s code: 0 written, 1 validation, 3 write', () {
      final ok = tree();
      final good = standalone(ok, 'build_bug_index.dart');
      expect(good.exitCode, 0, reason: _diag(good));
      expect(has(ok, kBugIndexPath), isTrue);

      final dateless = tree();
      f(dateless, 'docs/diagnoses/2026-10-02-wip-cccccc.md').writeAsStringSync(_doc('cccccc', date: null));
      final bad = standalone(dateless, 'build_bug_index.dart');
      expect(bad.exitCode, 1, reason: _diag(bad));
      expect('${bad.stderr}', contains('missing `date:`'));

      final blocked = tree();
      Directory('$blocked/$kBugIndexPath').createSync();
      f(blocked, '$kBugIndexPath/keep.txt').writeAsStringSync('x');
      final three = standalone(blocked, 'build_bug_index.dart');
      expect(three.exitCode, 3, reason: _diag(three));
    });

    test('build_bug_index.dart passes --lenient through to the builder', () {
      final r = tree();
      f(r, 'docs/diagnoses/2026-10-02-wip-cccccc.md').writeAsStringSync(_doc('cccccc', date: null));
      expect(standalone(r, 'build_bug_index.dart').exitCode, 1);
      final lenient = standalone(r, 'build_bug_index.dart', const ['--lenient']);
      expect(lenient.exitCode, 0, reason: _diag(lenient));
      expect('${lenient.stderr}', contains('SKIPPED'));
    });
  });
}

String _diag(ProcessResult r) => 'exit=${r.exitCode}\nstdout:\n${r.stdout}\nstderr:\n${r.stderr}';

ProcessResult _run(String exe, List<String> args, String cwd) => runSpawn(
      exe,
      args,
      why: 'local_indexes_e2e: $exe ${args.join(' ')}',
      workingDirectory: cwd,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
