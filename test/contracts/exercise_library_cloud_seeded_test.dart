// test/contracts/exercise_library_cloud_seeded_test.dart
//
// Contract for closes-diagnose ada3fb (2026-05-27):
//
// Cloud `exercise_library` must be seeded — `beat-my-coach` Edge
// Function depends on a populated library for bodyweight/cardio
// fallback queries. Until 2026-05-27 it was empty (bundled seed
// shipped to Hive but never to cloud), silently degrading the PRO
// coach feature.
//
// This is a source-grep contract — it asserts that the seed
// migration file exists with the expected INSERT row count, and
// that the ledger records the apply. It does NOT hit live cloud
// (that requires integration test infra). The behavioral assertion
// "live cloud has rows" is enforced via the build-time Gate path:
//   `node .claude/apply_migration_via_api.js dedsavbjuwgarrhphgnl supabase/migrations/074_seed_exercise_library.sql`
// is re-runnable; any future schema-wipe is caught by the
// supabase/migrations apply ledger pair-update rule.
//
// See:
//   - docs/diagnoses/2026-05-27-exercise-library-cloud-empty-ada3fb.md
//   - scripts/seed_exercise_library.js (regenerator)
//   - supabase/functions/beat-my-coach/index.ts:193 (the broken reader)

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// The highest-numbered `*_*seed_exercise_library.sql` on disk.
///
/// Sorted by the numeric prefix, not lexically: '99' sorts above '125' as a
/// string, which would silently pick an older file the day the numbering passes
/// three digits -- and it already has.
File _newestSeedMigration() {
  final dir = Directory('supabase/migrations');
  final seeds = dir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'[/\\]\d+_\w*seed_exercise_library\.sql$')
          .hasMatch(f.path))
      .toList();
  int num(File f) =>
      int.parse(RegExp(r'[/\\](\d+)_').firstMatch(f.path)!.group(1)!);
  seeds.sort((a, b) => num(a).compareTo(num(b)));
  return seeds.last;
}

void main() {
  group('exercise_library cloud seed (diagnose ada3fb)', () {
    // 074 was the ORIGINAL seed (259 rows) and is applied, therefore immutable.
    // A library change mints the NEXT seed migration rather than rewriting it, so
    // this resolves the newest one instead of naming a number that goes stale on
    // the next re-seed -- which is exactly what happened when OI-89 grew the
    // library to 271 and this test still measured 074.
    final seedFile = _newestSeedMigration();
    final originalSeed =
        File('supabase/migrations/074_seed_exercise_library.sql');
    final ledgerFile = File('backups/applied_migrations.json');
    final bundledSeed = File('assets/data/exercise_library.json');

    test('074_seed_exercise_library.sql exists with required header tags', () {
      expect(seedFile.existsSync(), isTrue,
          reason: 'Seed migration must be present on disk for re-apply.');
      expect(originalSeed.existsSync(), isTrue,
          reason: '074 is referenced by the applied ledger and must stay on '
              'disk -- it is also the rollback path for every later re-seed.');
      final content = seedFile.readAsStringSync();
      expect(content, contains('-- Intent:'),
          reason: 'Migration must have Intent header per supabase/migrations/CLAUDE.md.');
      expect(content, contains('-- Destructive?:'),
          reason: 'Migration must declare Destructive flag.');
      expect(content, contains('-- Rollback strategy:'),
          reason: 'Migration must declare Rollback strategy.');
      expect(content, contains('-- Linked diagnose-doc:'),
          reason: 'Migration must link to a diagnose-doc.');
      expect(content, contains('INSERT INTO exercise_library'),
          reason: 'Migration must perform the seed INSERT.');
      expect(content, contains('ON CONFLICT (id) DO UPDATE'),
          reason: 'Migration must be idempotent via ON CONFLICT DO UPDATE.');
    });

    test('seed row count matches bundled JSON entry count', () {
      final jsonData = jsonDecode(bundledSeed.readAsStringSync()) as List;
      final expectedRows = jsonData.length;
      // Count VALUES tuples by counting opening `(` at start of a line — each
      // single-line VALUES tuple from the generator begins with `(`.
      final sql = seedFile.readAsStringSync();
      final tupleStarts =
          RegExp(r"^\('[0-9a-f]{8}-", multiLine: true).allMatches(sql).length;
      expect(tupleStarts, equals(expectedRows),
          reason:
              'Seed SQL must contain one VALUES tuple per bundled exercise '
              '(json=$expectedRows, sql=$tupleStarts). Re-run '
              'scripts/seed_exercise_library.js if drift detected.');
      // Sanity floor — beat-my-coach needs a healthy library.
      expect(expectedRows, greaterThanOrEqualTo(250),
          reason:
              'Bundled exercise_library shrank below 250 entries; '
              'verify intentional curation OR investigate accidental deletion.');
    });

    test('backups/applied_migrations.json records the 074 apply', () {
      expect(ledgerFile.existsSync(), isTrue);
      final raw = jsonDecode(ledgerFile.readAsStringSync()) as List;
      final entries = raw
          .map((e) => e is String ? {'migration': e} : e as Map<String, dynamic>)
          .toList();
      final has074 = entries.any((e) => e['migration'] == '074');
      expect(has074, isTrue,
          reason:
              'Migration 074 must be in backups/applied_migrations.json '
              'per CLAUDE.md §4.5 (feedback_migration_apply_record_pair.md).');
      final entry = entries.firstWhere((e) => e['migration'] == '074');
      expect(entry['diagnose'], equals('ada3fb'),
          reason: 'Entry should link to diagnose ada3fb for traceability.');
      expect(entry['hash'], isNotNull,
          reason: 'Entry must carry sha256 hash for integrity audit.');
    });

    test('beat-my-coach Edge Function reader is unchanged + still targets exercise_library', () {
      // Pin the cloud-reader contract — if someone refactors beat-my-coach
      // away from exercise_library, this test reminds them to update the
      // SoT model in docs/architecture/database.md.
      final beatMyCoach = File('supabase/functions/beat-my-coach/index.ts');
      expect(beatMyCoach.existsSync(), isTrue);
      final src = beatMyCoach.readAsStringSync();
      expect(src, contains(".from(\"exercise_library\")"),
          reason:
              'beat-my-coach is the canonical cloud reader for exercise_library. '
              'If you removed this read, also update docs/architecture/database.md '
              'and consider deleting migration 074.');
    });
  });
}
