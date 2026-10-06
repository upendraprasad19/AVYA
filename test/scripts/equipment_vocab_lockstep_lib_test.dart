// test/scripts/equipment_vocab_lockstep_lib_test.dart
//
// Unit test for the pure logic behind `check_equipment_vocab_lockstep.dart`
// (rule 24: a gate ships with a test that can go RED, not merely a happy path).
//
// WHY THIS GATE EXISTS. `EquipmentVocab` keeps four structures that describe the
// same token set, and three of them are silent when they disagree:
//
//   1. `canonicalTokens` — the set itself.
//   2. `_precedence`     — `normalizeToken` does `_precedence.indexOf(c)` and the
//                          `rank >= 0` guard SKIPS a token that is absent. An
//                          OR-compound then resolves to `[]`, i.e. "no equipment
//                          required" — the MOST PERMISSIVE possible answer, and
//                          exactly wrong for a capability floor.
//   3. `_chipLabels`     — `chipLabel` falls back to the raw token, so a missing
//                          entry ships `elevated surface` as UI copy.
//   4. `_aliases`        — `_mapPart` checks `canonicalTokens` FIRST, so an alias
//                          key that is also canonical is unreachable dead code.
//
// None of those produce an error. They produce a quietly wrong answer, which is
// how the OI-89 class survived this long.
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/equipment_vocab_lockstep_lib.dart';

void main() {
  group('lockstepViolations', () {
    test('reports nothing when every structure agrees', () {
      final violations = lockstepViolations(
        canonical: {'bodyweight', 'wall'},
        precedence: ['bodyweight', 'wall'],
        chipLabels: {'wall': 'Wall'},
        aliasKeys: {'freestanding'},
      );
      expect(violations, isEmpty);
    });

    // ── red paths ────────────────────────────────────────────────────────
    test('a canonical token missing from _precedence is a violation', () {
      final violations = lockstepViolations(
        canonical: {'bodyweight', 'wall', 'plyo box'},
        precedence: ['bodyweight', 'wall'],
        chipLabels: {'wall': 'Wall', 'plyo box': 'Plyo Box'},
        aliasKeys: const {},
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('plyo box'));
      expect(violations.join('\n'), contains('_precedence'));
    });

    test('a _precedence entry that is not canonical is a violation', () {
      final violations = lockstepViolations(
        canonical: {'bodyweight'},
        precedence: ['bodyweight', 'ghost token'],
        chipLabels: const {},
        aliasKeys: const {},
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('ghost token'));
    });

    test('a duplicate _precedence entry is a violation', () {
      final violations = lockstepViolations(
        canonical: {'bodyweight', 'wall'},
        precedence: ['bodyweight', 'wall', 'wall'],
        chipLabels: {'wall': 'Wall'},
        aliasKeys: const {},
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('duplicate'));
    });

    test('a canonical token with no chip label is a violation', () {
      final violations = lockstepViolations(
        canonical: {'bodyweight', 'wall'},
        precedence: ['bodyweight', 'wall'],
        chipLabels: const {},
        aliasKeys: const {},
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('chipLabel'));
    });

    test('an alias key that shadows a canonical token is a violation', () {
      // `_mapPart` checks canonicalTokens first, so this alias row is dead code.
      final violations = lockstepViolations(
        canonical: {'bodyweight', 'wall'},
        precedence: ['bodyweight', 'wall'],
        chipLabels: {'wall': 'Wall'},
        aliasKeys: {'wall'},
      );
      expect(violations, isNotEmpty);
      expect(violations.join('\n'), contains('shadow'));
    });

    test('bodyweight is exempt from the chip-label requirement', () {
      // It is never rendered as a Customize chip — it is the floor.
      final violations = lockstepViolations(
        canonical: {'bodyweight'},
        precedence: ['bodyweight'],
        chipLabels: const {},
        aliasKeys: const {},
      );
      expect(violations, isEmpty);
    });

    test('every violation names the offending token', () {
      // A gate message that does not say WHAT is wrong costs an hour each time.
      final violations = lockstepViolations(
        canonical: {'bodyweight', 'towel'},
        precedence: ['bodyweight'],
        chipLabels: const {},
        aliasKeys: {'towel'},
      );
      expect(violations.length, greaterThanOrEqualTo(3));
      for (final v in violations) {
        expect(v, contains('towel'));
      }
    });
  });

  group('the live EquipmentVocab satisfies its own lockstep', () {
    test('no violations against the shipped constants', () {
      // The regression this gate exists for: adding a canonical token and
      // forgetting one of the other three structures.
      expect(liveLockstepViolations(), isEmpty);
    });
  });
}
