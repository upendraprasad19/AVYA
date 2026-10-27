@Timeout(Duration(minutes: 8))
library;

// End-to-end coverage for scripts/check_bug_class_numbers_unique.dart against the REAL script
// process (landing B of the merge-conflict-treadmill plan, OI-167; plan:
// docs/plans/bug-class-uniqueness.md section 5, tests 11-15). The lib test proves the parser and
// the checker; this proves main() is WIRED to them: that a finding computed by the library is
// printed to stderr, ends the run with exit 1, never prints PASS, that the input guards fire, and
// that the root is read from the cwd or from --root=. Fixtures are written to a temp dir; the
// gate is spawned with `dart run`, so every spawn pays the VM start (hence the file-level Timeout).
//
// NOTE on stdout: `dart run` may print "Running build hooks..." before the script's own output on
// some toolchains, so stdout is asserted with `contains` / last-line, never with equality.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn.dart';

late final String _repoRoot;
late final String _gate;

const String _classesRel = '.claude/skills/debugging/bug-classes.md';
const String _skillRel = '.claude/skills/debugging/SKILL.md';

ProcessResult _run(String cwd, [List<String> args = const []]) => runSpawn(
      dartBin(),
      ['run', _gate, ...args],
      why: 'bug-class number gate against a fixture catalog',
      workingDirectory: cwd,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      runInShell: true,
    );

String _skill(List<String> rows, {List<String> extra = const []}) => [
      '# Skill',
      '',
      '### Bug-class index (bodies live elsewhere)',
      '',
      '| id | title | trigger | regression test |',
      '|---|---|---|---|',
      ...rows,
      '',
      '---',
      '',
      '## 3. Red flags',
      ...extra,
      '',
    ].join('\n');

String _row(String id, String title) => '| $id | $title | a trigger | - |';

String _classes(List<String> headings) => ['# Bodies', '', ...headings.expand((h) => [h, 'body', ''])].join('\n');

/// A last non-empty stdout line, so a toolchain banner above the script's own output is ignored.
String _lastLine(String out) =>
    out.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).last;

/// Lines of stderr in the finding format `<path>:<line>: <message>`.
List<String> _findingLines(String err) => err
    .split('\n')
    .where((l) => RegExp(r'^\S+:\d+: ').hasMatch(l))
    .toList();

void main() {
  late Directory tmp;

  setUpAll(() {
    _repoRoot = Directory.current.path;
    _gate = '$_repoRoot/scripts/check_bug_class_numbers_unique.dart';
    expect(File(_gate).existsSync(), isTrue, reason: 'the gate must exist where this test spawns it from');
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('bug_class_gate_e2e_'));

  tearDown(() {
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // never mask the real failure with a cleanup error
    }
  });

  Directory fixture(String name, {String? classes, String? skill}) {
    final root = Directory('${tmp.path}/$name')..createSync(recursive: true);
    Directory('${root.path}/.claude/skills/debugging').createSync(recursive: true);
    if (classes != null) File('${root.path}/$_classesRel').writeAsStringSync(classes);
    if (skill != null) File('${root.path}/$_skillRel').writeAsStringSync(skill);
    return root;
  }

  group('11 a clean catalog', () {
    test('exits 0, prints the PASS line with counts and the root, and no finding on stderr', () {
      final root = fixture('clean',
          classes: _classes(['### 2.1 Writer drift', '### 2.2 Date drift']),
          skill: _skill([_row('2.1', 'Writer drift'), _row('2.2', 'Date drift')]));
      final r = _run(root.path);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('PASS bug-class numbers unique (headings=2 rows=2, root='));
      expect(_findingLines(r.stderr), isEmpty);
    });
  });

  group('12 every finding kind is wired to stderr and exit 1', () {
    void expectFailure(
      ProcessResult r, {
      required String finding,
      required String nextFree,
    }) {
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains(finding));
      expect(r.stderr, contains('next free id: $nextFree'));
      expect(r.stdout, isNot(contains('PASS')), reason: 'a failing run must never print PASS');
    }

    test('a duplicate heading names the id and every line', () {
      final root = fixture('dup_heading',
          classes: _classes(['### 2.1 A', '### 2.1 B']), skill: _skill([_row('2.1', 'A')]));
      expectFailure(_run(root.path),
          finding: '$_classesRel:3: id 2.1 is used by 2 headings (lines 3, 6)', nextFree: '2.2');
    });

    test('a duplicate index row names the id and every line', () {
      final root = fixture('dup_row',
          classes: _classes(['### 2.1 A']), skill: _skill([_row('2.1', 'A'), _row('2.1', 'A')]));
      expectFailure(_run(root.path),
          finding: '$_skillRel:7: id 2.1 is used by 2 index rows (lines 7, 8)', nextFree: '2.2');
    });

    test('a heading without a row', () {
      final root = fixture('no_row',
          classes: _classes(['### 2.1 A', '### 2.2 B']), skill: _skill([_row('2.1', 'A')]));
      expectFailure(_run(root.path),
          finding: '$_classesRel:6: id 2.2 has a heading but no row in the SKILL.md index', nextFree: '2.3');
    });

    test('a row without a heading', () {
      final root = fixture('no_heading',
          classes: _classes(['### 2.1 A']), skill: _skill([_row('2.1', 'A'), _row('2.4', 'Z')]));
      expectFailure(_run(root.path),
          finding: '$_skillRel:8: id 2.4 has an index row but no heading in bug-classes.md', nextFree: '2.5');
    });

    test('a major other than 2 in a heading', () {
      final root = fixture('major_heading',
          classes: _classes(['### 2.1 A', '### 3.1 B']), skill: _skill([_row('2.1', 'A'), _row('3.1', 'B')]));
      final r = _run(root.path);
      expectFailure(r, finding: '$_classesRel:6: id 3.1 is not in major 2', nextFree: '2.2');
      expect(r.stderr, contains('$_skillRel:8: id 3.1 is not in major 2'));
    });

    test('a lookalike heading in bug-classes.md', () {
      final root = fixture('lookalike_classes',
          classes: '${_classes(['### 2.1 A'])}\n### 2.2: not a heading\n', skill: _skill([_row('2.1', 'A')]));
      expectFailure(_run(root.path),
          finding: '$_classesRel:6: line looks like a class heading but does not parse', nextFree: '2.2');
    });

    test('a lookalike heading in SKILL.md', () {
      final root = fixture('lookalike_skill',
          classes: _classes(['### 2.1 A']),
          skill: _skill([_row('2.1', 'A')], extra: ['##### 2.9 stray']));
      expectFailure(_run(root.path),
          finding: '$_skillRel:12: line looks like a class heading but does not parse', nextFree: '2.2');
    });

    test('a numeric heading inside SKILL.md', () {
      final root = fixture('numeric_in_skill',
          classes: _classes(['### 2.1 A']),
          skill: _skill([_row('2.1', 'A')], extra: ['### 2.5 a body in the wrong file']));
      expectFailure(_run(root.path),
          finding: '$_skillRel:12: numeric heading "### 2.5" in SKILL.md', nextFree: '2.2');
    });

    test('a malformed index line', () {
      final root = fixture('malformed_row',
          classes: _classes(['### 2.1 A']), skill: _skill([_row('2.1', 'A'), '| 2.2 | too few cells |']));
      expectFailure(_run(root.path),
          finding: '$_skillRel:8: index table line is not a row with an id and four cells', nextFree: '2.2');
    });

    test('an id attached to a different class in the two files', () {
      final root = fixture('title_mismatch',
          classes: _classes(['### 2.1 A completely different heading text']),
          skill: _skill([_row('2.1', 'Unrelated index wording here')]));
      expectFailure(_run(root.path),
          finding: '$_skillRel:7: id 2.1 names different classes', nextFree: '2.2');
    });
  });

  group('13 input guards', () {
    test('a missing bug-classes.md exits 1 and names the file', () {
      final root = fixture('no_classes', skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('$_classesRel: cannot read the file'));
      expect(r.stdout, isNot(contains('PASS')));
    });

    test('a missing SKILL.md exits 1 and names the file', () {
      final root = fixture('no_skill', classes: _classes(['### 2.1 A']));
      final r = _run(root.path);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('$_skillRel: cannot read the file'));
    });

    test('invalid UTF-8 exits 1 with the file named, not an uncaught exception', () {
      final root = fixture('bad_utf8', skill: _skill([_row('2.1', 'A')]));
      File('${root.path}/$_classesRel').writeAsBytesSync([0x23, 0x23, 0x23, 0x20, 0xff, 0xfe, 0x0a]);
      final r = _run(root.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('$_classesRel: '));
      expect(r.stderr, anyOf(contains('cannot read the file'), contains('is not valid UTF-8')),
          reason: 'this SDK says "Failed to decode", another may throw a FormatException');
    });

    test('no index section and zero headings: the index-section reason, not a per-heading flood', () {
      final root = fixture('no_section', classes: '# Bodies\n', skill: '# Skill\n\nno table here\n');
      final r = _run(root.path);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('the index section "### Bug-class index" is missing'));
      expect(r.stderr, isNot(contains('has a heading but no row')));
    });

    test('both empty with the index section present and a header-only table: the failed-parse reason', () {
      final root = fixture('both_empty', classes: '# Bodies\n', skill: _skill(const []));
      final r = _run(root.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('parsed 0 headings and 0 index rows'));
      expect(r.stdout, isNot(contains('PASS')));
    });

    test('an unknown argument exits 2 with the usage line', () {
      final root = fixture('bad_arg', classes: _classes(['### 2.1 A']), skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path, ['--bogus']);
      expect(r.exitCode, 2);
      expect(r.stderr, contains('unknown argument "--bogus"'));
      expect(r.stderr, contains('usage: dart run scripts/check_bug_class_numbers_unique.dart'));
    });

    test('an empty --root= exits 2', () {
      final root = fixture('empty_root', classes: _classes(['### 2.1 A']), skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path, ['--root=']);
      expect(r.exitCode, 2);
    });
  });

  group('14 --next', () {
    test('prints the number and exits 0 on a clean catalog', () {
      final root = fixture('next_clean',
          classes: _classes(['### 2.1 A', '### 2.7 B']), skill: _skill([_row('2.1', 'A'), _row('2.7', 'B')]));
      final r = _run(root.path, ['--next']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(_lastLine(r.stdout), '2.8');
      expect(_findingLines(r.stderr), isEmpty);
    });

    test('the maximum only in the rows is found', () {
      final root = fixture('next_rows',
          classes: _classes(['### 2.1 A']), skill: _skill([_row('2.1', 'A'), _row('2.7', 'Z')]));
      final r = _run(root.path, ['--next']);
      expect(r.exitCode, 0);
      expect(_lastLine(r.stdout), '2.8');
    });

    test('the maximum only in the headings is found', () {
      final root = fixture('next_headings',
          classes: _classes(['### 2.1 A', '### 2.7 Z']), skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path, ['--next']);
      expect(r.exitCode, 0);
      expect(_lastLine(r.stdout), '2.8');
    });

    test('with findings present stdout holds only the number and stderr holds the findings, exit 0', () {
      final root = fixture('next_findings',
          classes: _classes(['### 2.1 A', '### 2.1 B']), skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path, ['--next']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(_lastLine(r.stdout), '2.2');
      expect(r.stdout, isNot(contains('is used by')));
      expect(r.stderr, contains('id 2.1 is used by 2 headings'));
    });

    test('a missing file, a missing index section and an empty union all exit 1', () {
      final missing = fixture('next_missing', skill: _skill([_row('2.1', 'A')]));
      expect(_run(missing.path, ['--next']).exitCode, 1);
      final noSection = fixture('next_nosection', classes: '### 2.1 A\n', skill: '# Skill\n');
      expect(_run(noSection.path, ['--next']).exitCode, 1);
      final empty = fixture('next_empty', classes: '# Bodies\n', skill: _skill(const []));
      final r = _run(empty.path, ['--next']);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('no major-2 id found'));
    });
  });

  group('15 root resolution', () {
    Directory goodFixture(String name) => fixture(name,
        classes: _classes(['### 2.1 A', '### 2.2 B']), skill: _skill([_row('2.1', 'A'), _row('2.2', 'B')]));

    test('(a) the cwd is the root when --root is absent', () {
      final root = goodFixture('cwd_root');
      final r = _run(root.path);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('headings=2 rows=2'));
    });

    test('(b) --root= wins over the cwd', () {
      final root = goodFixture('flag_root');
      final elsewhere = Directory('${tmp.path}/elsewhere')..createSync();
      final r = _run(elsewhere.path, ['--root=${root.path}']);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('headings=2 rows=2'));
    });

    test('(c) a --root= pointing at an empty directory fails even when the cwd is a good fixture', () {
      final root = goodFixture('cwd_good');
      final empty = Directory('${tmp.path}/empty_dir')..createSync();
      final r = _run(root.path, ['--root=${empty.path}']);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('cannot read the file'));
    });

    test('the REAL catalog passes from the repo root and the counts are equal and large', () {
      final r = _run(_repoRoot);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final m = RegExp(r'headings=(\d+) rows=(\d+)').firstMatch(r.stdout as String);
      expect(m, isNotNull, reason: '${r.stdout}');
      final headings = int.parse(m!.group(1)!);
      final rows = int.parse(m.group(2)!);
      expect(headings, rows);
      expect(headings, greaterThan(100));
    });
  });
  group('B-pass additions: the wiring of the later rules', () {
    test('the 16th alphanumeric character is compared, the 17th is not', () {
      final bad = fixture('boundary_16',
          classes: _classes(['### 2.1 Alpha beta gamma Delta']),
          skill: _skill([_row('2.1', 'Alpha beta gamma Dxlta')]));
      final r = _run(bad.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('$_skillRel:7: id 2.1 names different classes'));
      final good = fixture('boundary_17',
          classes: _classes(['### 2.1 Alpha beta gamma Delta']),
          skill: _skill([_row('2.1', 'Alpha beta gamma Dexta')]));
      final ok = _run(good.path);
      expect(ok.exitCode, 0, reason: '${ok.stdout}${ok.stderr}');
    });

    test('an indented class heading is a finding, not a silent pass', () {
      final root = fixture('indented_heading',
          classes: '${_classes(['### 2.1 A'])}\n ### 2.1 Another class entirely\n',
          skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('$_classesRel:6: line looks like a class heading but does not parse'));
      expect(r.stdout, isNot(contains('PASS')));
    });

    test('an unclosed code fence is a finding that names the opening line', () {
      final root = fixture('unclosed_fence',
          classes: '${_classes(['### 2.1 A'])}\n```\n### 2.1 hidden duplicate\n',
          skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('$_classesRel:6: code fence opened here is never closed'));
    });

    test('a parse that finds nothing still prints the findings that explain it', () {
      final root = fixture('tab_after_id',
          classes: '# Bodies\n\n### 2.1\tWriter drift\nbody\n', skill: _skill([_row('2.1', 'Writer drift')]));
      final r = _run(root.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('$_classesRel:3: line looks like a class heading but does not parse'));
      expect(r.stderr, contains('parsed 0 headings and 1 index rows'));
    });

    test('a missing file names the root the gate looked in', () {
      final root = fixture('names_root', skill: _skill([_row('2.1', 'A')]));
      final r = _run(root.path);
      expect(r.exitCode, 1);
      expect(r.stderr, contains('(root: '));
      expect(r.stderr, contains('names_root'));
    });

    test('with no major-2 id at all the failure output has no "next free id" line', () {
      final root = fixture('only_major3',
          classes: _classes(['### 3.1 B']), skill: _skill([_row('3.1', 'B')]));
      final r = _run(root.path);
      expect(r.exitCode, 1, reason: '${r.stdout}${r.stderr}');
      expect(r.stderr, contains('id 3.1 is not in major 2'));
      expect(r.stderr, isNot(contains('next free id')));
      expect(r.stderr, isNot(contains('null')));
    });
  });
}
