// test/contracts/equipment_tier_grants_vs_asks_test.dart
//
// ⑦ OI-89 Task 2 — a tier GRANTS one set and we ASK about a different one.
//
// Founder decision 7: the household baseline (`wall`, `doorway`,
// `elevated surface`, `foot anchor`, `towel`) is granted by EVERY tier — a gym
// has walls and benches too, and `effectiveItems` feeds the AI coach for every
// tier, so it must be true there. But a gym user is never ASKED "do you have a
// chair?"; that question is only contingent at the bodyweight tier, where a
// hostel room genuinely might not.
//
// Decision (Task 2 Step 1, 2026-08-28): ACCESSORIES are askable at gym tiers.
// A tier-2 Indian gym may genuinely lack a plyo box, battle ropes or a
// suspension trainer, which is exactly what the Customize list is for ("my gym
// has no smith machine"). The household baseline is NOT askable there.
//
// Founder decision 8: `wall` is never askable at all — it joins `bodyweight` as
// the un-excludable core, because the per-pattern floor invariant is defined
// over `{bodyweight, wall}` and a user must not be able to empty a pattern.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

const _household = ['wall', 'doorway', 'elevated surface', 'foot anchor', 'towel'];
const _allTiers = ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'];

void main() {
  group('what a tier GRANTS', () {
    test('every tier grants the whole household baseline (decision 7)', () {
      for (final t in _allTiers) {
        for (final b in _household) {
          expect(EquipmentVocab.tierItems[t], contains(b),
              reason: '$t must GRANT $b — a gym has walls and benches, and '
                  'effectiveItems feeds the AI coach for every tier');
        }
      }
    });

    test('the none/bodyweight prefix is preserved at index 0 and 1', () {
      // equipment_chip_vocab_contract_test.dart asserts list.take(2) on every
      // tier, so the baseline must be APPENDED, never prepended.
      for (final list in EquipmentVocab.tierItems.values) {
        expect(list.take(2).toList(), ['none', 'bodyweight']);
      }
    });

    test('bodyweight does NOT grant any accessory', () {
      for (final a in const [
        'pull-up bar', 'resistance band', 'ab wheel', 'jump rope',
        'suspension trainer', 'parallel bars', 'plyo box', 'medicine ball',
        'battle ropes',
      ]) {
        expect(EquipmentVocab.tierItems['bodyweight'], isNot(contains(a)),
            reason: 'decision 5 — the baseline is "nothing you have to buy"; '
                '$a is reachable only via equipment_owned');
      }
    });
  });

  group('what we ASK about', () {
    test('bodyweight asks only the contingent household items (decisions 7+8)', () {
      expect(EquipmentVocab.tierAskableItems('bodyweight'),
          ['doorway', 'elevated surface', 'foot anchor', 'towel'],
          reason: 'wall is un-excludable (decision 8); order is display order');
    });

    test('gym tiers are never asked about the household baseline', () {
      for (final t in ['home_dumbbells', 'basic_gym', 'full_gym']) {
        for (final b in _household) {
          expect(EquipmentVocab.tierAskableItems(t), isNot(contains(b)),
              reason: 'a $t user is never asked whether they own a $b');
        }
      }
    });

    test('gym tiers ARE asked about accessories they are granted', () {
      // Task 2 Step 1 decision: a tier-2 gym may genuinely lack these.
      expect(EquipmentVocab.tierAskableItems('full_gym'),
          contains('smith machine'));
      for (final t in ['basic_gym', 'full_gym']) {
        for (final a in EquipmentVocab.tierItems[t]!) {
          if (a == 'none' || a == 'bodyweight' || _household.contains(a)) continue;
          expect(EquipmentVocab.tierAskableItems(t), contains(a),
              reason: '$a is granted at $t and is plausibly absent, so it '
                  'must be askable');
        }
      }
    });

    test('wall is askable at NO tier', () {
      for (final t in _allTiers) {
        expect(EquipmentVocab.tierAskableItems(t), isNot(contains('wall')));
      }
    });

    test('an unknown tier asks nothing rather than throwing', () {
      // equipment_access is read at 14 sites with 4 different defaults and can
      // hold legacy free text; a miss must not crash the Customize screen.
      expect(EquipmentVocab.tierAskableItems('nonsense'), isEmpty);
    });
  });

  group('the un-excludable core', () {
    test('wall is stripped from the exclusion set, exactly like bodyweight', () {
      // Decision 8. Phrased as STRIPPED, not "survives": floorSanitizedExclusions
      // removes it from what the user asked to exclude, so the capability set
      // keeps it.
      expect(EquipmentVocab.floorSanitizedExclusions(['wall', 'doorway']),
          {'doorway'});
      expect(EquipmentVocab.floorSanitizedExclusions(['wall']), isEmpty);
      expect(EquipmentVocab.floorSanitizedExclusions(['bodyweight', 'wall', 'none']),
          isEmpty);
    });

    test('a genuinely contingent item is NOT stripped', () {
      expect(EquipmentVocab.floorSanitizedExclusions(['towel', 'elevated surface']),
          {'towel', 'elevated surface'});
    });
  });
}
