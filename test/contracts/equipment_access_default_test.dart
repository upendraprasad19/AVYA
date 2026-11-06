// ⑦ OI-89 Task 7 — one fallback for a missing `equipment_access`.
//
// 14 production sites disagreed across FOUR values. That is not cosmetic: the
// capability floor is scoped to the bodyweight tier, so a profile that lost the
// key and defaulted to `full_gym` did not merely get wrong exercises — it turned
// the floor OFF.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/equipment_defaults.dart';

/// Strip `//` and `/* */` before an absent-pattern source grep, or the doc
/// comments this very batch adds match the pattern being banned.
String _stripComments(String src) {
  final noBlock = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  return noBlock
      .split('\n')
      .map((l) {
        final at = l.indexOf('//');
        return at < 0 ? l : l.substring(0, at);
      })
      .join('\n');
}

void main() {
  group('equipmentAccessOf', () {
    test('an absent key yields the fail-safe default', () {
      expect(equipmentAccessOf(<String, dynamic>{}), 'bodyweight');
    });

    test('a null value yields the default', () {
      expect(equipmentAccessOf({'equipment_access': null}), 'bodyweight');
    });

    test('an EMPTY string yields the default, not an empty tier', () {
      // ai_snapshot_builder defaulted to '' and handed that to the AI coach.
      expect(equipmentAccessOf({'equipment_access': ''}), 'bodyweight');
      expect(equipmentAccessOf({'equipment_access': '   '}), 'bodyweight');
    });

    test('a non-String value yields the default', () {
      expect(equipmentAccessOf({'equipment_access': 42}), 'bodyweight');
    });

    test('a real value passes through, trimmed', () {
      expect(equipmentAccessOf({'equipment_access': 'full_gym'}), 'full_gym');
      expect(equipmentAccessOf({'equipment_access': ' basic_gym '}), 'basic_gym');
    });

    test('the default is the FAIL-SAFE direction', () {
      // A bodyweight plan is performable by a gym user; the reverse is not. And
      // the capability floor is scoped to this tier, so defaulting anywhere else
      // silently disables it.
      expect(kDefaultEquipmentAccess, 'bodyweight');
    });
  });

  group('no production site hard-codes its own fallback', () {
    test('every equipment_access default goes through the constant', () {
      final offenders = <String>[];
      final re = RegExp(
          r"equipment_access'\]\s*(?:as\s+String\?)?\s*\)?\s*\?\?\s*'[^']*'");
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart')) continue;
        // lib/features/dev/ is the simulator: it drives EXPLICIT personas, so a
        // hard-coded tier there is the point, not a defect. Without this
        // exemption the regex matches 16 sites and the test stays red forever
        // after the fix.
        if (path.contains('/features/dev/')) continue;
        // The constant's own doc comment describes the pattern it replaces.
        if (path.endsWith('core/constants/equipment_defaults.dart')) continue;
        final src = _stripComments(f.readAsStringSync());
        if (re.hasMatch(src)) offenders.add(path);
      }
      expect(offenders, isEmpty,
          reason: 'use equipmentAccessOf(profile):\n${offenders.join('\n')}');
    });
  });
}
