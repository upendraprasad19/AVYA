// Source-scanning tests for Theme E4 + E5 on the Identity onboarding screen.
//
// E4: sex must be nullable (no silent 'male' default), with an inline error
//     gate in _onContinue that blocks progress until the user picks a pill.
//
// E5: the header eyebrow must read '01 · 05' (middle dot U+00B7), matching
//     the convention used by all other stepped onboarding screens.
//
// These are pure-Dart string checks — no Flutter framework required, no device,
// no Hive.  They guard against accidental regressions when other PRs touch the
// identity screen.  See flow_integrity_test.dart for the established pattern.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    final file = File('lib/features/onboarding/screens/identity_screen.dart');
    if (!file.existsSync()) {
      fail('Expected file not found: ${file.path}');
    }
    src = file.readAsStringSync();
  });

  // ─── Theme E4 ──────────────────────────────────────────────────────────────

  group('E4: sex field is nullable with required-field gate', () {
    test('_sex is declared as String? (nullable)', () {
      // Must have "String? _sex" — nullable, no non-null default assignment.
      expect(
        src.contains('String? _sex'),
        isTrue,
        reason:
            "_sex must be declared as 'String? _sex' — was 'late String _sex' "
            "with a hard-coded 'male' default that skewed every female user's BMR.",
      );
    });

    test("_sex does NOT have a hard-coded 'male' default", () {
      // The old pattern: `_sex = ... ?? 'male'` must be gone.
      expect(
        src.contains("?? 'male'"),
        isFalse,
        reason:
            "Hard-coded 'male' default must be removed — it silently gave "
            "every user who skipped the pill selector male-BMR targets.",
      );
    });

    test("_sexError state field is declared", () {
      expect(
        src.contains('String? _sexError'),
        isTrue,
        reason:
            "_sexError state field must exist to hold the inline validation "
            "message shown below the sex pill row.",
      );
    });

    test('_onContinue gates on _sex == null', () {
      expect(
        src.contains('_sex == null'),
        isTrue,
        reason:
            '_onContinue must check _sex == null and set _sexError before '
            'returning early — without this gate the sex field is effectively '
            'optional.',
      );
    });

    test("error message copy is correct", () {
      const expectedCopy =
          'Please pick one to calibrate your plan accurately.';
      expect(
        src.contains(expectedCopy),
        isTrue,
        reason:
            "Error copy must be '$expectedCopy' — this is the user-visible "
            "string that explains WHY the field is required.",
      );
    });

    test('pill onTap clears _sexError', () {
      // Clearing the error on tap is the UX contract: as soon as the user
      // acts, the red message should disappear.
      expect(
        src.contains('_sexError = null'),
        isTrue,
        reason:
            '_sexError must be cleared to null inside the pill onTap so the '
            'error dismisses as soon as the user makes a selection.',
      );
    });

    test('AppColors.bad is used for the error text color', () {
      expect(
        src.contains('AppColors.bad'),
        isTrue,
        reason:
            'Error text must use AppColors.bad — no raw color literals allowed '
            'per CLAUDE.md §4.4 rules 11/12 (token-first).',
      );
    });

    test('_sex is written with null-assertion (!!) in route extras', () {
      // After the null gate passes, _sex must be non-null so the route
      // extras can carry it as String (not String?).
      expect(
        src.contains("'sex': _sex!") || src.contains("'sex': _sex !"),
        isTrue,
        reason:
            "Route extras must write _sex! (null-asserted) — the gate at the "
            "top of _onContinue guarantees it is non-null at this point.",
      );
    });
  });

  // ─── Theme E5 ──────────────────────────────────────────────────────────────

  group('E5: step-label eyebrow reads 01 · 05', () {
    test("header eyebrow reads '01 · 05' (middle dot U+00B7 or literal ·)", () {
      // Accept either the unicode escape (·) or the literal middle dot.
      final hasUnicodeEscape = src.contains('01 \\u00B7 05');
      final hasLiteralDot = src.contains('01 · 05');
      expect(
        hasUnicodeEscape || hasLiteralDot,
        isTrue,
        reason:
            "The eyebrow / progress indicator must show '01 · 05' (middle dot "
            "U+00B7), matching the convention used by goal/stats/details/plan "
            "screens.  Was showing 'QUESTION 0'.",
      );
    });

    test("old 'QUESTION 0' eyebrow is removed", () {
      expect(
        src.contains("'QUESTION 0'"),
        isFalse,
        reason:
            "The old eyebrow 'QUESTION 0' must be gone — it was inconsistent "
            "with every other stepped onboarding screen which uses the 'NN · 05' "
            "format.",
      );
    });
  });
}
