// test/scripts/bug_class_renumber_pins_test.dart
//
// Outcome pins for the one-time renumber of landing B (docs/plans/bug-class-uniqueness.md section
// 5, tests 16 and 17; OI-167). The gate (scripts/check_bug_class_numbers_unique.dart) proves ids are
// unique and that an id names the same class in both files; it cannot tell that the RIGHT class
// of each old pair kept the number, nor that a citation still points at the class it meant. These
// pins read the real files and hold that mapping.
//
// ONE table drives both tests. RETIRING OR REWORDING A PINNED CLASS MEANS EDITING THIS TABLE (a
// keyword that leaves its title turns the test red on purpose: a pointer that no longer resolves
// to its class is the defect this landing removed).

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/bug_class_ids_lib.dart';

/// One old pair: [oldId] still names the KEPT class (title contains [keptKeyword]); the other class
/// moved to [newId] (title contains [movedKeyword]) and carries the marker for [oldId].
class _Pair {
  const _Pair(this.oldId, this.keptKeyword, this.movedKeyword, this.newId);

  final int oldId;
  final String keptKeyword;
  final String movedKeyword;
  final int newId;
}

const List<_Pair> _kRenumberTable = [
  _Pair(36, 'DROP', 'thenable', 125),
  _Pair(37, 'kIsWeb', 'positive grep', 126),
  _Pair(38, 'RLS', 'FURTHER', 127),
  _Pair(39, 'half a proof', 'Native-only plugin', 128),
  _Pair(40, 'Fabricated default', 'SHARED worktree', 129),
  _Pair(41, 'ABSORBED', 'NOT-NULL', 130),
  _Pair(53, 'MIRROR', 'Nth fix', 131),
  _Pair(54, 'BOTH arms', 'invariant', 132),
  _Pair(55, 'quick checks', 'SCOPED capability', 133),
];

String _marker(int oldId) => '(was 2.$oldId; renumbered 2026-10-25)';

late final String _classesText;
late final String _skillText;

bool _has(String s, String keyword) => s.toLowerCase().contains(keyword.toLowerCase());

void main() {
  setUpAll(() {
    _classesText = File(kBugClassesPath).readAsStringSync();
    _skillText = File(kBugClassSkillPath).readAsStringSync();
  });

  group('16 renumber outcome pins (parse-based, keyed on the marker)', () {
    test('exactly nine headings and nine rows carry a renumber marker', () {
      final headings = scanHeadings(_classesText).headings.where((h) => h.title.contains('renumbered 2026-10-25)'));
      final rows = scanIndex(_skillText)!.rows.where((r) => r.title.contains('renumbered 2026-10-25)'));
      expect(headings.length, 9);
      expect(rows.length, 9);
    });

    test('each moved class holds its new id with its marker in BOTH files, and the old id has one other holder', () {
      final headings = scanHeadings(_classesText).headings;
      final rows = scanIndex(_skillText)!.rows;
      for (final p in _kRenumberTable) {
        final movedId = BugClassId(2, p.newId);
        final keptId = BugClassId(2, p.oldId);
        final movedHeading = headings.where((h) => h.id == movedId).toList();
        final movedRow = rows.where((r) => r.id == movedId).toList();
        expect(movedHeading.length, 1, reason: '2.${p.newId} heading');
        expect(movedRow.length, 1, reason: '2.${p.newId} row');
        expect(movedHeading.single.title, contains(_marker(p.oldId)), reason: '2.${p.newId} heading marker');
        expect(movedRow.single.title, contains(_marker(p.oldId)), reason: '2.${p.newId} row marker');
        expect(_has(movedHeading.single.title, p.movedKeyword), isTrue,
            reason: '2.${p.newId} heading must be the "${p.movedKeyword}" class: ${movedHeading.single.title}');
        expect(_has(movedRow.single.title, p.movedKeyword), isTrue,
            reason: '2.${p.newId} row must be the "${p.movedKeyword}" class: ${movedRow.single.title}');

        final keptHeading = headings.where((h) => h.id == keptId).toList();
        final keptRow = rows.where((r) => r.id == keptId).toList();
        expect(keptHeading.length, 1, reason: '2.${p.oldId} heading holders');
        expect(keptRow.length, 1, reason: '2.${p.oldId} row holders');
        expect(_has(keptHeading.single.title, p.keptKeyword), isTrue,
            reason: '2.${p.oldId} heading must be the "${p.keptKeyword}" class: ${keptHeading.single.title}');
        expect(_has(keptRow.single.title, p.keptKeyword), isTrue,
            reason: '2.${p.oldId} row must be the "${p.keptKeyword}" class: ${keptRow.single.title}');
        expect(_has(keptHeading.single.title, p.movedKeyword), isFalse,
            reason: 'the kept class of 2.${p.oldId} must not carry the moved keyword');
        expect(keptHeading.single.title.contains('renumbered 2026-10-25'), isFalse);
      }
    });

    test('new ids strictly increase in old-id order', () {
      final ids = _kRenumberTable.map((p) => p.newId).toList();
      for (var i = 1; i < ids.length; i++) {
        expect(ids[i], greaterThan(ids[i - 1]));
      }
      final olds = _kRenumberTable.map((p) => p.oldId).toList();
      final sorted = [...olds]..sort();
      expect(olds, sorted);
    });

    test('the normalized 16-character title prefix of each moved heading equals that of its row', () {
      final headings = scanHeadings(_classesText).headings;
      final rows = scanIndex(_skillText)!.rows;
      for (final p in _kRenumberTable) {
        final id = BugClassId(2, p.newId);
        final h = normalizeTitle(headings.singleWhere((x) => x.id == id).title);
        final r = normalizeTitle(rows.singleWhere((x) => x.id == id).title);
        expect(h.substring(0, 16), r.substring(0, 16), reason: '2.${p.newId}');
      }
    });
  });

  group('17 citation pins', () {
    // The nine red flags of SKILL.md section 3: an anchor phrase of the red flag, and the keyword
    // the class it cites must carry. A moved class is cited by its NEW id; a kept class by its old.
    const flags = <(String, String)>[
      ('The test greps for the provider name', 'positive grep'),
      ('The RPC returns the column', 'FURTHER'),
      ('Mutation-proven', 'half a proof'),
      ('I deleted the check and tests stayed green', 'ABSORBED'),
      ('keeps the grants, so I can add a return column', 'DROP'),
      ("I'll run the mutations here while the reviewers read", 'SHARED worktree'),
      ('The last fix to this file was nearly right', 'Nth fix'),
      ('It passed 5/5 under load', 'BOTH arms'),
      ("I'll just check one thing with `dart run`", 'quick checks'),
    ];

    test('each of the nine red flags cites the class it names', () {
      final headings = scanHeadings(_classesText).headings;
      final lines = _skillText.split('\n');
      for (final (anchor, keyword) in flags) {
        final matches = lines.where((l) => l.contains(anchor)).toList();
        expect(matches.length, 1, reason: 'the red flag anchored on "$anchor"');
        final m = RegExp(r'See §2\.(\d+)').firstMatch(matches.single);
        expect(m, isNotNull, reason: 'the red flag "$anchor" must carry a "See §2.N" pointer');
        final id = BugClassId(2, int.parse(m!.group(1)!));
        final target = headings.where((h) => h.id == id).toList();
        expect(target.length, 1, reason: 'See §2.${id.minor} resolves to one heading');
        expect(_has(target.single.title, keyword), isTrue,
            reason: 'the red flag "$anchor" cites §2.${id.minor} = "${target.single.title}", expected "$keyword"');
      }
    });

    // The repointed lines of the 7 external files: (path, text that must now be present, text that
    // must be gone). Anchor strings, not line numbers, so an unrelated edit above does not break them.
    const repointed = <(String, String, String)>[
      ('docs/plans/oi150-phase-delta.md', '(comments stripped, §2.126)', '(comments stripped, §2.37)'),
      ('docs/plans/oi150-phase-delta.md', '(OI-134 / §2.129)', '(OI-134 / §2.40)'),
      ('docs/superpowers/plans/2026-09-24-oi126-training-day-predicate-unification.md', '§2.126, "a positive grep', '§2.37, "a positive grep'),
      ('docs/diagnoses/2026-06-14-health-sync-web-deadend-d8f3a2.md', '§2.37/§2.128.', '§2.37/§2.39.'),
      ('docs/plans/spawn-tests-env-and-stderr.md', 'class 2.131 (heading "The Nth fix', 'class 2.53 (heading "The Nth fix'),
      ('docs/plans/progress-photos-pro-server-rule.md', 'class (2.131)', 'class (2.53)'),
      ('docs/diagnoses/2026-10-06-spawn-test-env-leak-e6c4a9.md', 'class 2.131 names the pattern', 'class 2.53 names the pattern'),
      ('docs/plans/spawn-tests-pr2-migrate-remaining.md', 'satisfied by a mention (classes 2.54 and 2.132)', 'satisfied by a mention (class 2.54)'),
    ];

    test('the eight external citation lines follow their moved class', () {
      for (final (path, present, gone) in repointed) {
        final text = File(path).readAsStringSync();
        expect(text, contains(present), reason: path);
        expect(text.contains(gone), isFalse, reason: '$path still carries "$gone"');
      }
    });

    test('the in-skill citation lines follow their moved class', () {
      expect(_skillText, contains('§2.133 NEW (was 2.55) —'));
      expect(_skillText, contains('§2.132 NEW (was 2.54) —'));
      expect(_skillText.contains('§2.55 NEW —'), isFalse);
      expect(_skillText.contains('§2.54 NEW —'), isFalse);
      expect(_classesText, contains('2.126 (a positive grep cannot see a defect in an argument), 2.54 and 2.132.'));
      expect(_classesText, contains('2.126 (a positive grep cannot see a defect in an argument).'));
      expect(_classesText.contains('2.37 (a positive grep cannot see a defect in an argument)'), isFalse);
      expect(_classesText, contains('§2.53, §2.131, §2.54, §2.132, §2.63 and §2.65 (bad-news-vs-no-news family'));
      expect(_classesText.contains('(§2.40 family)'), isFalse);
    });
  });
}
