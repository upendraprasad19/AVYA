// test/contracts/beat_my_coach_removed_test.dart
//
// Beat My Coach was dropped entirely (OI-395, plan
// docs/plans/2026-10-25-drop-beat-my-coach.md): the Edge Function, the
// never-mounted challenge card widget, two AppConstants, the badge that could
// never unlock, and every registry entry that named them. This test keeps the
// removal from re-entering quietly.
//
// What protects what (the plan's unit 9; mutation-checked, not just run):
//   (a) the Edge Function directory stays gone;
//   (b) no code under lib/ or supabase/functions/ names the removed things;
//   (c) the registries that used to list the slug do not list it again;
//   (d) the badge enum and the badge list agree, and the removed id is not in
//       either (the type system forces list ids into the enum; the real
//       direction of the mirror is an enum value with no list entry);
//   (e) behavioral: a stored badge map that still holds the old id (written by
//       a hypothetical old build) is ignored by the reader.
//
// Source-grep (b) strips comments first (feedback_source_grep_strip_comments_first.md):
// three shared Edge Function files keep a historical comment that names the
// removed function on purpose. It scans lib/ and supabase/functions/ only, so
// it cannot match this file. A vacuity guard fails if the scan found too few
// files, so a wrong root or extension cannot go green.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

import '../helpers/hive_test_setup.dart';

/// Tokens that must not appear in code (comments excluded).
const _removedTokens = <String>[
  'beat-my-coach',
  'beat_my_coach',
  'ChallengeCard',
  'hasBeatCoach',
  'challengeWon',
  'beatMyCoach',
];

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

List<String> _tokensIn(String code) =>
    _removedTokens.where(code.contains).toList();

List<File> _filesUnder(String root, String extension) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith(extension))
      .toList();
}

String _read(File f) =>
    utf8.decode(f.readAsBytesSync(), allowMalformed: true);

void main() {
  group('Beat My Coach stays removed (OI-395)', () {
    test('(a) the Edge Function directory does not exist', () {
      // A File(...) check would be vacuous on a directory.
      expect(Directory('supabase/functions/beat-my-coach').existsSync(), isFalse,
          reason:
              'supabase/functions/beat-my-coach was deleted (OI-395). If a new '
              'function is wanted, give it a new name and a new plan.');
    });

    test('(b) positive control: the stripper flags code and ignores comments',
        () {
      expect(_tokensIn(_stripComments("final x = 'ChallengeCard';")),
          contains('ChallengeCard'));
      expect(_tokensIn(_stripComments('// ChallengeCard beat-my-coach')),
          isEmpty);
      expect(_tokensIn(_stripComments('/** beat_my_coach hasBeatCoach */')),
          isEmpty);
    });

    test('(b) no code under lib/ or supabase/functions/ names the removed things',
        () {
      final dart = _filesUnder('lib', '.dart');
      final ts = _filesUnder('supabase/functions', '.ts');
      // Vacuity guard: measured 570 .dart and 254 .ts files when this was
      // written; a scan far below that means a wrong root or extension.
      expect(dart.length, greaterThanOrEqualTo(200),
          reason: 'scanned only ${dart.length} .dart files under lib/');
      expect(ts.length, greaterThanOrEqualTo(30),
          reason: 'scanned only ${ts.length} .ts files under supabase/functions/');

      final offenders = <String>[];
      for (final f in [...dart, ...ts]) {
        final hits = _tokensIn(_stripComments(_read(f)));
        if (hits.isNotEmpty) {
          offenders.add('${f.path.replaceAll(r'\', '/')}: ${hits.join(', ')}');
        }
      }
      expect(offenders, isEmpty,
          reason: 'Beat My Coach was removed (OI-395); these files name it in '
              'code:\n${offenders.join('\n')}');
    });

    group('(c) registries do not list the slug again', () {
      const registries = <String>[
        '.claude/deploy_via_api.js',
        'docs/snapshot_contract.yaml',
        'docs/blast_radius.yaml',
        'test/contracts/runbook_deploy_verify_jwt_test.dart',
      ];
      for (final path in registries) {
        test(path, () {
          final f = File(path);
          expect(f.existsSync(), isTrue, reason: '$path moved or was deleted');
          expect(_read(f).contains('beat-my-coach'), isFalse,
              reason: '$path lists the removed slug again. Note that '
                  'runbook_deploy_verify_jwt_test.dart is the ONLY guard on its '
                  'own expectedVerifyJwt map: it stays green with the key '
                  're-added.');
        });
      }
    });

    test('(d) the badge enum and the badge list agree and omit challengeWon',
        () {
      final enumNames = BadgeId.values.map((b) => b.name).toList();
      expect(enumNames, isNot(contains('challengeWon')),
          reason: 'the Coach Slayer badge was removed with the feature');

      final listed = AchievementBadge.all.map((b) => b.id.name).toList();
      expect(listed.toSet().length, listed.length,
          reason: 'duplicate id in AchievementBadge.all: $listed');
      expect(listed.toSet(), enumNames.toSet(),
          reason: 'BadgeId.values and AchievementBadge.all must list the same '
              'ids. An enum value with no list entry is invisible in the '
              'profile grid; nothing else pins the two together.');
    });

    test('(e) a stale challengeWon key in the stored badge map is ignored',
        () async {
      final dir = await setUpHiveForTests();
      addTearDown(() => tearDownHiveForTests(dir));

      final iso = DateTime.utc(2026, 10, 1).toIso8601String();
      await HiveService.instance.configBox.put('unlockedBadges', {
        'challengeWon': iso, // what an old build could have written
        'firstWorkout': iso,
      });

      final all = BadgeService.instance.getAllWithStatus();
      expect(all.length, AchievementBadge.all.length);
      expect(all.map((b) => b.id.name), isNot(contains('challengeWon')));
      expect(all.firstWhere((b) => b.id == BadgeId.firstWorkout).isUnlocked,
          isTrue);
      expect(all.where((b) => b.isUnlocked).length, 1,
          reason: 'the stale key must neither unlock nor count as a badge');
    });
  });
}
