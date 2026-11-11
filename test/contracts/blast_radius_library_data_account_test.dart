// test/contracts/blast_radius_library_data_account_test.dart
//
// d30de7 B-pass F6 (2026-10-24). The exercise library's `injury_contraindications` tags are the
// only thing the generator, the warm-up picker and the curated substitutes filter on, so a
// data-only retag (13-B, c2d5e8, d30de7) is a SAFETY change. Under the `assets/**` and
// `scripts/**` feature defaults it classified as `feature` and skipped the B-pass and the
// plan-review record; the earlier retags escaped only because they also touched plan_engine code.
//
// Three layers (the shape of blast_radius_data_deleting_paths_catastrophic_test.dart):
//   1. CLASSIFICATION  the library JSON and every `library_injury_additions_*.json` on disk are
//                      `account`, and it is the NEW rule that claims them, per the classifier AND
//                      the commit-time review gate's own copy of the rules reader.
//   2. ORDER           first match wins: both rules sit above `assets/**` and `scripts/**`.
//   3. MIRRORS         look-alikes keep their tier: another asset file and the applier script
//                      stay `feature`, so the rule does not widen to every data file.
//
// Run: flutter test test/contracts/blast_radius_library_data_account_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `as classifier`: that script also defines main().
import '../../scripts/blast_radius_from_diff.dart' as classifier;
// `as reviewGate`: the commit-time review-acceptance gate; it also defines main().
import '../../scripts/check_code_review_pass_exists.dart' as reviewGate;

const _libraryGlob = 'assets/data/exercise_library.json';
const _tablesGlob = 'scripts/data/library_injury_additions_*.json';
// Batch M1: the media upload tool (service-role key, can delete a bucket) and the provenance table it reads.
const _uploadToolGlob = 'scripts/upload_exercise_media.js';
const _mediaTableGlob = 'scripts/data/library_media_v16.json';
// Batch C2a (OI-460): the removals file decides which library rows leave every install and the cloud.
const _removalsGlob = 'scripts/data/library_batch_c2_removals.json';
// Batch C2c (OI-474): the E230 retag record decides what the importer writes into that row and what the migration's rollback restores.
const _retagGlob = 'scripts/data/library_e230_retag.json';
// Library Batch S1a: the core-levels record decides which core lists the kept rows sit on.
const _coreLevelsGlob = 'scripts/data/library_s1_core_levels.json';
// Library Batch S1b-2: the suitable_for record decides which levels E010 / E045 are offered to (every user's queryV4).
const _suitableForGlob = 'scripts/data/library_s1b2_suitable_for.json';
// Library Batch S1b-3 (OI-147): the merges record decides which rows leave every install; the name_aliases record decides
// what the migration's rollback restores.
const _mergesGlob = 'scripts/data/library_s1b3_merges.json';
const _namesGlob = 'scripts/data/library_s1b3_name_aliases.json';
const _assetsGlob = 'assets/**';
const _scriptsGlob = 'scripts/**';

void main() {
  final yaml = File('docs/blast_radius.yaml').readAsStringSync();
  final reg = classifier.parseRegistry(yaml);
  String tier(String p) => classifier.tierFor(p, reg);

  /// The first rule whose glob claims [p], or null when only default_tier would.
  classifier.TierRule? ruleFor(String p) {
    for (final r in reg.rules) {
      if (classifier.globToRegExp(r.glob).hasMatch(p)) return r;
    }
    return null;
  }

  List<String> tablesOnDisk() => Directory('scripts/data')
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .where((p) {
        final n = p.split('/').last;
        return n.startsWith('library_injury_additions_') && n.endsWith('.json');
      })
      .toList()
    ..sort();

  group('1. classification', () {
    test('the library JSON and every injury-tag table on disk are account', () {
      final tables = tablesOnDisk();
      expect(tables, isNotEmpty, reason: 'positive control: the v14 table exists');
      // Unit 1B-F (seed v25): the injury-tag record for kept rows is claimed by the same rule (a SAFETY change).
      expect(tables, contains('scripts/data/library_injury_additions_v25.json'),
          reason: 'the v25 injury-tag record is on disk and matched by the tables rule');
      for (final p in [_libraryGlob, ...tables]) {
        expect(tier(p), 'account', reason: p);
        expect(ruleFor(p)?.glob, p == _libraryGlob ? _libraryGlob : _tablesGlob,
            reason: '$p must be claimed by the NEW rule, not a later catch-all');
      }
    });

    test("the commit-time review gate's own engine reads them as account too", () {
      final rules = reviewGate.parseRules(yaml);
      ({String glob, String tier}) gateRule(String p) {
        for (final r in rules) {
          if (reviewGate.globToRegExp(r.glob).hasMatch(p)) {
            return (glob: r.glob, tier: r.tier);
          }
        }
        return (glob: '', tier: 'feature');
      }

      expect(gateRule(_libraryGlob), (glob: _libraryGlob, tier: 'account'));
      for (final p in tablesOnDisk()) {
        expect(gateRule(p), (glob: _tablesGlob, tier: 'account'), reason: p);
      }
    });
  });

  group('1b. the media upload tool and its provenance table (Batch M1)', () {
    test('both are account, claimed by their own rules, and both files exist', () {
      for (final p in [_uploadToolGlob, _mediaTableGlob]) {
        expect(File(p).existsSync(), isTrue, reason: 'positive control: $p exists');
        expect(tier(p), 'account', reason: p);
        expect(ruleFor(p)?.glob, p, reason: '$p must be claimed by its own rule, not the scripts/** catch-all');
      }
    });

    test("the commit-time review gate's own engine reads them as account too", () {
      final rules = reviewGate.parseRules(yaml);
      String gateTier(String p) {
        for (final r in rules) {
          if (reviewGate.globToRegExp(r.glob).hasMatch(p)) return r.tier;
        }
        return 'feature';
      }

      expect(gateTier(_uploadToolGlob), 'account');
      expect(gateTier(_mediaTableGlob), 'account');
    });
  });

  group('1c. the C2a removals file', () {
    test('it is account, claimed by its own rule above scripts/**, and the file exists', () {
      expect(File(_removalsGlob).existsSync(), isTrue, reason: 'positive control');
      expect(tier(_removalsGlob), 'account');
      expect(ruleFor(_removalsGlob)?.glob, _removalsGlob);
      int index(String glob) => reg.rules.indexWhere((r) => r.glob == glob);
      expect(index(_removalsGlob), lessThan(index(_scriptsGlob)));
    });

    test('mirror: its generator and sibling data file keep the scripts/** tier', () {
      expect(tier('scripts/library_batch_c2_removals_gen.js'), 'feature');
      expect(tier('scripts/data/library_batch_c2_other.json'), 'feature');
    });
  });

  group('1d. the C2c E230 retag record', () {
    test('it is account, claimed by its own rule above scripts/**, and the file exists', () {
      expect(File(_retagGlob).existsSync(), isTrue, reason: 'positive control');
      expect(tier(_retagGlob), 'account');
      expect(ruleFor(_retagGlob)?.glob, _retagGlob);
      int index(String glob) => reg.rules.indexWhere((r) => r.glob == glob);
      expect(index(_retagGlob), lessThan(index(_scriptsGlob)));
    });

    test("the commit-time review gate's own engine reads the record as account too", () {
      final rules = reviewGate.parseRules(yaml);
      String gateTier(String p) {
        for (final r in rules) {
          if (reviewGate.globToRegExp(r.glob).hasMatch(p)) return r.tier;
        }
        return 'feature';
      }

      expect(gateTier(_retagGlob), 'account');
      expect(gateTier('scripts/data/library_e230_retag_other.json'), 'feature', reason: 'mirror: a look-alike stays feature');
    });

    test('mirror: the importer that applies it and a sibling data file keep the scripts/** tier', () {
      expect(tier('scripts/add_library_batch_c_v15.js'), 'feature');
      expect(tier('scripts/data/library_e230_retag_other.json'), 'feature');
    });
  });

  group('1e. the S1a core-levels record', () {
    test('it is account, claimed by its own rule above scripts/**, and the file exists', () {
      expect(File(_coreLevelsGlob).existsSync(), isTrue, reason: 'positive control');
      expect(tier(_coreLevelsGlob), 'account');
      expect(ruleFor(_coreLevelsGlob)?.glob, _coreLevelsGlob);
      int index(String glob) => reg.rules.indexWhere((r) => r.glob == glob);
      expect(index(_coreLevelsGlob), lessThan(index(_scriptsGlob)));
    });

    test("the commit-time review gate's own engine reads it as account too; a look-alike stays feature", () {
      final rules = reviewGate.parseRules(yaml);
      String gateTier(String p) {
        for (final r in rules) {
          if (reviewGate.globToRegExp(r.glob).hasMatch(p)) return r.tier;
        }
        return 'feature';
      }

      expect(gateTier(_coreLevelsGlob), 'account');
      expect(gateTier('scripts/data/library_s1_core_levels_other.json'), 'feature');
      expect(tier('scripts/data/library_s1_core_levels_other.json'), 'feature');
    });
  });

  group('1f. the S1b-2 suitable_for record', () {
    test('it is account, claimed by its own rule above scripts/**, and the file exists', () {
      expect(File(_suitableForGlob).existsSync(), isTrue, reason: 'positive control');
      expect(tier(_suitableForGlob), 'account');
      expect(ruleFor(_suitableForGlob)?.glob, _suitableForGlob);
      int index(String glob) => reg.rules.indexWhere((r) => r.glob == glob);
      expect(index(_suitableForGlob), lessThan(index(_scriptsGlob)));
    });

    test("the commit-time review gate's own engine reads it as account too; a look-alike stays feature", () {
      final rules = reviewGate.parseRules(yaml);
      String gateTier(String p) {
        for (final r in rules) {
          if (reviewGate.globToRegExp(r.glob).hasMatch(p)) return r.tier;
        }
        return 'feature';
      }

      expect(gateTier(_suitableForGlob), 'account');
      expect(gateTier('scripts/data/library_s1b2_suitable_for_other.json'), 'feature');
      expect(tier('scripts/data/library_s1b2_suitable_for_other.json'), 'feature');
    });
  });

  for (final (label, glob, lookAlike) in [
    ('1g. the S1b-3 merges record', _mergesGlob, 'scripts/data/library_s1b3_merges_other.json'),
    ('1h. the S1b-3 name_aliases record', _namesGlob, 'scripts/data/library_s1b3_name_aliases_other.json'),
  ]) {
    group(label, () {
      test('it is account, claimed by its own rule above scripts/**, and the file exists', () {
        expect(File(glob).existsSync(), isTrue, reason: 'positive control');
        expect(tier(glob), 'account');
        expect(ruleFor(glob)?.glob, glob);
        int index(String g) => reg.rules.indexWhere((r) => r.glob == g);
        expect(index(glob), lessThan(index(_scriptsGlob)));
      });

      test("the commit-time review gate's own engine reads it as account too; a look-alike stays feature", () {
        final rules = reviewGate.parseRules(yaml);
        String gateTier(String p) {
          for (final r in rules) {
            if (reviewGate.globToRegExp(r.glob).hasMatch(p)) return r.tier;
          }
          return 'feature';
        }

        expect(gateTier(glob), 'account');
        expect(gateTier(lookAlike), 'feature');
        expect(tier(lookAlike), 'feature');
      });
    });
  }

  group('2. order', () {
    test('both rules sit above the assets/** and scripts/** feature defaults', () {
      int index(String glob) => reg.rules.indexWhere((r) => r.glob == glob);
      expect(index(_libraryGlob), isNonNegative);
      expect(index(_tablesGlob), isNonNegative);
      expect(index(_assetsGlob), isNonNegative);
      expect(index(_scriptsGlob), isNonNegative);
      expect(index(_libraryGlob), lessThan(index(_assetsGlob)));
      expect(index(_tablesGlob), lessThan(index(_scriptsGlob)));
    });

    test('the media tool and table rules sit above scripts/**', () {
      int index(String glob) => reg.rules.indexWhere((r) => r.glob == glob);
      expect(index(_uploadToolGlob), isNonNegative);
      expect(index(_mediaTableGlob), isNonNegative);
      expect(index(_uploadToolGlob), lessThan(index(_scriptsGlob)));
      expect(index(_mediaTableGlob), lessThan(index(_scriptsGlob)));
    });
  });

  group('3. mirrors', () {
    test('look-alikes keep their tier (the rule does not widen to every data file)', () {
      expect(tier('assets/data/food_database.json'), 'feature');
      expect(tier('scripts/add_library_injury_tags_v14.js'), 'feature');
      expect(tier('scripts/data/some_other_table.json'), 'feature');
      // The media rules are exact paths: the builder, the map and a sibling tool stay feature.
      expect(tier('scripts/build_library_media_v16.js'), 'feature');
      expect(tier('scripts/data/library_batch_c_media_map.json'), 'feature');
      expect(tier('scripts/upload_exercise_media_other.js'), 'feature');
    });
  });
}
