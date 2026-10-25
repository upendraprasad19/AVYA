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
// a shared Edge Function file keeps a historical comment that names the
// removed function on purpose. It scans lib/ and supabase/functions/ only, so
// it cannot match this file. Vacuity guards fail if the scan found too few
// files or missed a canary file, so a wrong root or extension cannot go green.
//
// The stripper is URL-safe: a `//` that follows a colon (`https://...`) and a
// `/*` that follows a quote, a word character, `/` or `*` (a glob inside a
// string) are NOT comment openers, so a removed name placed after a URL or a
// glob on the same line is still seen. The price is the fail-closed direction:
// a real `x/* c */` comment glued to a word is left in and flagged loudly.
// A `//` inside a non-URL string still hides the rest of its line; the scan of
// the real tree below proves no removed token sits on such a line today.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/badge_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/models/achievement_badge.dart';

import '../helpers/hive_test_setup.dart';

/// Tokens that must not appear in code (comments excluded). All lower-case:
/// [_tokensIn] lower-cases the source, so `BeatMyCoachCard`, `BEAT-MY-COACH`
/// and `ChallengeCard` are all caught, and the snake_case file name of the
/// deleted widget (`challenge_card`) is a token of its own.
const _removedTokens = <String>[
  'beat-my-coach',
  'beat_my_coach',
  'beatmycoach',
  'challengecard',
  'challenge_card',
  'hasbeatcoach',
  'challengewon',
];

String _stripComments(String src) => src
    .replaceAll(RegExp(r'''(?<![\w"'`/*])/\*[\s\S]*?\*/'''), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

List<String> _tokensIn(String code) {
  final lower = code.toLowerCase();
  return _removedTokens.where(lower.contains).toList();
}

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
      // Parent control: from a wrong working directory every existsSync below
      // is false and the absence check would be vacuous (a --plain-name run of
      // this one test has no other guard).
      expect(Directory('supabase/functions/ai-proxy').existsSync(), isTrue,
          reason: 'cwd is not the package root, so the absence checks are vacuous');
      // A File(...) check would be vacuous on a directory.
      expect(Directory('supabase/functions/beat-my-coach').existsSync(), isFalse,
          reason:
              'the beat-my-coach source directory was deleted (OI-395). If a new '
              'function is wanted, give it a new name and a new plan.');
      // Supabase accepts underscores in a function slug too.
      expect(Directory('supabase/functions/beat_my_coach').existsSync(), isFalse,
          reason: 'the underscore spelling of the removed function came back');
    });

    test('(b) positive control: the stripper flags code and ignores comments',
        () {
      expect(_tokensIn(_stripComments("final x = 'ChallengeCard';")),
          contains('challengecard'));
      expect(_tokensIn(_stripComments('// ChallengeCard beat-my-coach')),
          isEmpty);
      expect(_tokensIn(_stripComments('/** beat_my_coach hasBeatCoach */')),
          isEmpty);
      // Mirror 1: a removed name after `scheme://` on the same line is CODE.
      expect(
          _tokensIn(_stripComments(
              'final u = "https://x.co/functions/v1/beat-my-coach";')),
          contains('beat-my-coach'));
      // ... while a real trailing comment after a URL is still a comment.
      expect(
          _tokensIn(_stripComments('final u = "https://x.co"; // beat-my-coach')),
          isEmpty);
      // Mirror 2: a `/*` inside a string (a glob) must not open a comment that
      // swallows the code up to the next `*/`.
      expect(
          _tokensIn(_stripComments('const g = "supabase/functions/*/index.ts";\n'
              'await invoke("beat-my-coach");\n/** doc */')),
          contains('beat-my-coach'));
      // Spelling variants: case, camel/snake, the deleted widget's file name.
      expect(_tokensIn(_stripComments('class BeatMyCoachCard {}')),
          contains('beatmycoach'));
      expect(_tokensIn(_stripComments('"BEAT-MY-COACH"')),
          contains('beat-my-coach'));
      expect(_tokensIn(_stripComments("import 'x/challenge_card.dart';")),
          contains('challenge_card'));
    });

    test('(b) no code under lib/ or supabase/functions/ names the removed things',
        () {
      final dart = _filesUnder('lib', '.dart');
      final ts = _filesUnder('supabase/functions', '.ts');
      // Vacuity guards: measured 570 .dart and 254 .ts files when this was
      // written. The floors sit at about 90%, so a half-walked tree fails
      // too, and two canary files prove the walk reached known code.
      expect(dart.length, greaterThanOrEqualTo(500),
          reason: 'scanned only ${dart.length} .dart files under lib/');
      expect(ts.length, greaterThanOrEqualTo(220),
          reason: 'scanned only ${ts.length} .ts files under supabase/functions/');
      final scanned = {
        for (final f in [...dart, ...ts]) f.path.replaceAll(r'\', '/'),
      };
      for (final canary in [
        'lib/core/services/badge_service.dart',
        'supabase/functions/ai-proxy/index.ts',
      ]) {
        expect(scanned, contains(canary),
            reason: 'the scan never reached $canary');
      }

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
          final text = _read(f).toLowerCase();
          expect(
              text.contains('beat-my-coach') || text.contains('beat_my_coach'),
              isFalse,
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
          reason: 'the stale key is ignored: only the seeded firstWorkout '
              'counts as unlocked');
    });
  });
}
