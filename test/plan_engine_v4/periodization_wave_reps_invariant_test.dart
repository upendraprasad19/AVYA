// §4.11 gate (W2.1 F2) — proves the shared `parseRepRange` refactor of
// PeriodizationEngine._applyWave is INERT.
//
// `_applyWave`'s rep output is a pure function of the parsed `(minReps, maxReps)`
// (archetype selects min/max/mid, then wave-nudge + clamp). So proving the shared
// `parseRepRange` extracts the SAME `(min,max)` the old per-part parse did — for
// every rep_range that actually reaches the wave — proves the wave output is
// unchanged. (The end-to-end apply() output is additionally pinned by the
// existing *_archetype_test.dart suite, which runs green post-refactor.)
//
// Verified against the live library: every rep-based `rep_range` is a clean
// "N-M" with lo<hi; timed ranges ("30-60") never reach the parse (isRepBased
// early-returns). The shared parser also REMOVES a latent `clamp(lo>hi)` throw
// the old per-part path carried for a reversed range.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';

void main() {
  group('parseRepRange — identical (min,max) for every real library range', () {
    // The full set of rep-based ranges present in exercise_library.json.
    const realRanges = {
      '5-8': (5, 8),
      '8-12': (8, 12),
      '10-12': (10, 12),
      '10-15': (10, 15),
      '12-15': (12, 15),
      '12-20': (12, 20),
      '15-20': (15, 20),
      '20-30': (20, 30),
    };
    realRanges.forEach((range, expected) {
      test('"$range" → $expected', () {
        expect(parseRepRange(range), expected,
            reason: 'shared parser must extract the same (min,max) the old '
                'per-part split produced for a clean N-M range → wave unchanged');
      });
    });
  });

  group('parseRepRange — fallback (→ null → _applyWave baseReps path)', () {
    test('null / empty / whitespace → null', () {
      expect(parseRepRange(null), isNull);
      expect(parseRepRange(''), isNull);
      expect(parseRepRange('   '), isNull);
    });
    test('single number (no dash) → null', () {
      expect(parseRepRange('12'), isNull);
    });
    test('reversed (lo>hi) → null (removes the old clamp(lo>hi) throw)', () {
      expect(parseRepRange('12-8'), isNull);
    });
    test('malformed part → null', () {
      expect(parseRepRange('8-x'), isNull);
      expect(parseRepRange('x-8'), isNull);
    });
    test('non-positive → null', () {
      expect(parseRepRange('0-5'), isNull);
      expect(parseRepRange('-5-8'), isNull);
    });
    test('3+ parts → null', () {
      expect(parseRepRange('5-8-10'), isNull);
    });
    test('trims whitespace around parts', () {
      expect(parseRepRange(' 8 - 12 '), (8, 12));
    });
  });
}
