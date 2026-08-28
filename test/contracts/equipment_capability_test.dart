// test/contracts/equipment_capability_test.dart
//
// ⑦ OI-89 Task 3 — the capability derivation and predicate.
//
// `effective = tierItems[tier] ∪ owned − exclusions` is the ONE derivation of
// "what equipment does this user actually have". `canPerform` is the tier-
// agnostic question "can they do this exercise". Enforcement is scoped to the
// bodyweight tier; the PREDICATE is not.
//
// It is deliberately NOT called a "bodyweight floor": that term already means
// the un-excludable none/bodyweight tokens in six files, including OI-89's own
// board entry.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/equipment_capability.dart';

void main() {
  group('effectiveItems', () {
    test('the bodyweight baseline grants the household core', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', null, null);
      expect(e, containsAll(
          ['bodyweight', 'wall', 'doorway', 'elevated surface', 'foot anchor', 'towel']));
    });

    test('the bodyweight baseline grants NOTHING you have to buy (decision 5)', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', null, null);
      for (final a in const [
        'pull-up bar', 'resistance band', 'ab wheel', 'jump rope',
        'suspension trainer', 'parallel bars', 'plyo box', 'medicine ball',
        'dumbbells', 'barbell', 'bench',
      ]) {
        expect(e, isNot(contains(a)));
      }
    });

    test('owned adds upward — the pull-up-bar case (decision 4)', () {
      // The case that forced the both-directions design: you cannot SUBTRACT
      // from a tier that grants nothing.
      final e = EquipmentVocab.effectiveItems('bodyweight', ['pull-up bar'], null);
      expect(e, contains('pull-up bar'));
      expect(e, contains('bodyweight'));
    });

    test('owned is normalized, not trusted verbatim', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', ['TRX'], null);
      expect(e, contains('suspension trainer'));
    });

    test('exclusions subtract', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', null, ['doorway']);
      expect(e, isNot(contains('doorway')));
      expect(e, contains('elevated surface'));
    });

    test('wall cannot be excluded (decision 8)', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', null, ['wall']);
      expect(e, contains('wall'));
    });

    test('bodyweight itself cannot be excluded', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', null, ['bodyweight']);
      expect(e, contains('bodyweight'));
    });

    test('the none sentinel never leaks out', () {
      // Every tierItems list begins with `none`, which the vocab explicitly
      // documents as NOT a canonical token. Inert inside canPerform, but it
      // reaches chip labels and the AI snapshot if not stripped here.
      for (final t in const ['bodyweight', 'home_dumbbells', 'basic_gym', 'full_gym']) {
        expect(EquipmentVocab.effectiveItems(t, null, null), isNot(contains('none')));
      }
    });

    test('a tier-granted owned entry does not alter the result', () {
      // Read-side reconcile. pruneToTier has ONE call site (a dropdown callback)
      // and is bypassed by onboarding AND cloud restore, so the both-lists state
      // IS reachable; reconciling here cannot be bypassed by a writer nobody
      // enumerated.
      final plain = EquipmentVocab.effectiveItems('full_gym', null, null);
      final withOwned = EquipmentVocab.effectiveItems('full_gym', ['bench'], null);
      expect(withOwned, equals(plain));
    });

    test('an UNKNOWN tier fails OPEN to every canonical token', () {
      // equipment_access is read at 14 sites with 4 different defaults and can
      // hold legacy free text. A tier miss is a DATA problem, not a capability
      // claim — failing closed here would drop every row for that user.
      final e = EquipmentVocab.effectiveItems('nonsense', null, null);
      expect(e, containsAll(EquipmentVocab.canonicalTokens));
    });
  });

  group('EquipmentCapability.canPerform', () {
    final bw = EquipmentVocab.effectiveItems('bodyweight', null, null);

    test('accepts a pure bodyweight row', () {
      expect(EquipmentCapability.canPerform(['bodyweight'], bw), isTrue);
    });

    test('accepts a household row', () {
      expect(EquipmentCapability.canPerform(['elevated surface'], bw), isTrue);
      expect(EquipmentCapability.canPerform(['doorway'], bw), isTrue);
      expect(EquipmentCapability.canPerform(['towel'], bw), isTrue);
    });

    test('rejects a pull-up bar at the baseline', () {
      expect(EquipmentCapability.canPerform(['pull-up bar'], bw), isFalse);
    });

    test('accepts a pull-up bar once owned', () {
      final e = EquipmentVocab.effectiveItems('bodyweight', ['pull-up bar'], null);
      expect(EquipmentCapability.canPerform(['pull-up bar'], e), isTrue);
    });

    test('rejects a MIXED row where only one token is off-capability', () {
      // Decline Push Up is ['bodyweight','bench'] — the bench is what matters.
      expect(EquipmentCapability.canPerform(['bodyweight', 'bench'], bw), isFalse);
    });

    test('a gym tier can perform household rows (decision 7)', () {
      final gym = EquipmentVocab.effectiveItems('full_gym', null, null);
      expect(EquipmentCapability.canPerform(['wall'], gym), isTrue,
          reason: 'a gym has walls; effective feeds the AI coach for every tier');
      expect(EquipmentCapability.canPerform(['elevated surface'], gym), isTrue);
    });

    // ── fail-CLOSED contract ────────────────────────────────────────────
    // `normalize` DROPS unmappable tokens, so an unreadable row yields [] and a
    // bare `every` would pass it VACUOUSLY. Correct for soft curation, wrong for
    // a hard capability check. 0 of 259 seed rows are affected; the live
    // population is community-synced rows and user/AI-authored customs.
    test('FAILS CLOSED on null', () {
      expect(EquipmentCapability.canPerform(null, bw), isFalse);
    });

    test('FAILS CLOSED on an empty list', () {
      expect(EquipmentCapability.canPerform(const [], bw), isFalse);
    });

    test('FAILS CLOSED on an all-unmappable list', () {
      expect(EquipmentCapability.canPerform(['moon rocks'], bw), isFalse);
    });

    test('FAILS CLOSED on a non-list scalar', () {
      expect(EquipmentCapability.canPerform(42, bw), isFalse);
    });

    test('accepts a bare String (fromProfile wraps it)', () {
      expect(EquipmentCapability.canPerform('bodyweight', bw), isTrue);
    });
  });
}
