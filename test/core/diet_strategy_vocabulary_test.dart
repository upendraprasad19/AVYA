// Diet plan Unit 3b-2 (2026-11-14, docs/plans/diet-strategy-3b.md §5): the
// client's tolerant read of `diet_strategy` against the vocabulary vector
// the server test reads too (supabase/functions/_shared/diet_strategies_test.ts),
// so `dietStrategyOf` and `normalizeDietStrategy` cannot drift apart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/diet_strategies.dart';

void main() {
  final fixture = jsonDecode(File(
          'supabase/functions/_shared/testdata/diet_strategy_vocabulary.json')
      .readAsStringSync()) as Map<String, dynamic>;
  final rows = (fixture['rows'] as List).cast<Map<String, dynamic>>();

  test('the vector is non-trivial and covers every strategy', () {
    expect(rows.length, greaterThanOrEqualTo(10));
    expect(rows.map((r) => r['expected']).toSet(),
        containsAll(DietStrategy.values.map((s) => s.storageKey)));
  });

  for (final r in rows) {
    test('dietStrategyOf(${jsonEncode(r['input'])}) == ${r['expected']}', () {
      expect(dietStrategyOf(r['input']).storageKey, r['expected']);
    });
  }

  test('a non-string value is balanced', () {
    for (final v in <Object?>[null, 5, <String, dynamic>{}, ['keto'], true]) {
      expect(dietStrategyOf(v), DietStrategy.balanced, reason: '$v');
    }
  });
}
