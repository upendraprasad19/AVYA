// ⑥ slice C1 — EquipmentVocab tier-map + Customize-UI chip helper contract
// (PURE, no Hive). Pins the invariants the Edit-Profile Customize UI + the
// generator's `_getEquipmentList` delegation rely on, so they can never drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';

void main() {
  group('EquipmentVocab tier map + chip helpers (⑥ C1)', () {
    test('tierItems ⊆ canonicalTokens ∪ {none} (none is the only non-canonical item)',
        () {
      final allowed = {...EquipmentVocab.canonicalTokens, 'none'};
      for (final entry in EquipmentVocab.tierItems.entries) {
        for (final t in entry.value) {
          expect(allowed.contains(t), isTrue,
              reason: '${entry.key} item "$t" must be canonical or the `none` sentinel');
        }
      }
    });

    test('tierItems covers the 4 tiers; each begins with the none+bodyweight floor',
        () {
      expect(EquipmentVocab.tierItems.keys.toSet(),
          {'bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym'});
      // ⑦ OI-89 decision 7: every tier now GRANTS the household baseline. The
      // take(2) floor below is what stays pinned -- the baseline is APPENDED.
      expect(EquipmentVocab.tierItems['bodyweight'],
          ['none', 'bodyweight', 'wall', 'doorway', 'elevated surface',
           'foot anchor', 'towel']);
      for (final list in EquipmentVocab.tierItems.values) {
        expect(list.take(2).toList(), ['none', 'bodyweight']);
      }
    });

    test('tierExcludableItems = tier minus {none,bodyweight}, ⊆ canonicalTokens', () {
      for (final tier in EquipmentVocab.tierItems.keys) {
        final excl = EquipmentVocab.tierExcludableItems(tier);
        expect(excl.contains('none'), isFalse);
        expect(excl.contains('bodyweight'), isFalse);
        for (final t in excl) {
          expect(EquipmentVocab.canonicalTokens.contains(t), isTrue,
              reason: 'excludable "$t" must be canonical');
        }
      }
      // ⑦ OI-89 decisions 7+8: the bodyweight tier now HAS something to
      // customize -- the contingent household items. `wall` is excluded: it is
      // the un-excludable core alongside `bodyweight`, because the per-pattern
      // floor invariant is defined over `{bodyweight, wall}`. (This assertion
      // previously read `isEmpty`, with the comment "the UI hides the section" --
      // which was the whole of OI-89's residual complaint: the users who most
      // needed to declare their kit were the only ones who could not.)
      expect(EquipmentVocab.tierExcludableItems('bodyweight'),
          ['doorway', 'elevated surface', 'foot anchor', 'towel']);
      // an unknown tier → the safe default (['none','bodyweight']) → empty excludable
      expect(EquipmentVocab.tierExcludableItems('nonsense'), isEmpty);
      // ⑦ OI-89: +7 accessories at full_gym, +6 at basic_gym. A tier-2 Indian
      // gym may genuinely lack a plyo box or battle ropes -- the same reason
      // `smith machine` has always been askable. The household baseline is NOT
      // counted: a gym has walls and benches, so we never ask.
      expect(EquipmentVocab.tierExcludableItems('full_gym').length, 18);
      expect(EquipmentVocab.tierExcludableItems('basic_gym').length, 13);
      for (final b in const ['wall', 'doorway', 'elevated surface',
                             'foot anchor', 'towel']) {
        expect(EquipmentVocab.tierExcludableItems('full_gym'), isNot(contains(b)));
      }
    });

    test('chipLabel is a proper (non-fallback) label for every EXCLUDABLE canonical token',
        () {
      for (final t in EquipmentVocab.canonicalTokens) {
        if (t == 'bodyweight') continue; // never excludable → never labelled in the UI
        expect(EquipmentVocab.chipLabel(t), isNot(equals(t)),
            reason: 'excludable token "$t" needs a display label');
      }
    });

    test('toggleExclusion adds/removes (NO none sentinel), returns a growable list',
        () {
      final a = EquipmentVocab.toggleExclusion(const [], 'cables');
      expect(a, ['cables']);
      final b = EquipmentVocab.toggleExclusion(a, 'barbell');
      expect(b, ['cables', 'barbell']);
      final c = EquipmentVocab.toggleExclusion(b, 'cables');
      expect(c, ['barbell']); // toggling an existing token removes it
      expect(() => c.add('x'), returnsNormally); // growable
    });

    test('pruneToTier drops exclusions invalid for the new tier (a tier downgrade)',
        () {
      // full_gym excluded machines+cables → switch to basic_gym (no machines)
      final pruned =
          EquipmentVocab.pruneToTier(const ['machines', 'cables'], 'basic_gym');
      expect(pruned, ['cables']); // machines dropped (∉ basic_gym), cables kept, order preserved
      // switch to bodyweight → everything drops (no excludable items)
      expect(EquipmentVocab.pruneToTier(const ['cables', 'machines'], 'bodyweight'),
          isEmpty);
      expect(() => pruned.add('x'), returnsNormally); // growable
    });

    test('the bodyweight floor is never excludable (floorSanitizedExclusions strips it)',
        () {
      // even if a caller tries, none/bodyweight can never be excluded
      final s = EquipmentVocab.floorSanitizedExclusions(['none', 'bodyweight', 'cables']);
      expect(s, {'cables'});
    });
  });
}
