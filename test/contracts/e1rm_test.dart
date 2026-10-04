// Batch 9 (W2.7) — shared `sessionMaxE1rm` helper (lib/core/utils/e1rm.dart),
// extracted from DeloadE1rmScan so the deload trigger (W2.4) + volume titration
// (W2.7) share ONE Epley loop. Pure (no Hive). The DeloadE1rmScan byte-identity
// is separately pinned by `deload_eval_behavioral_test.dart`.

import 'package:flutter_test/flutter_test.dart';

import 'package:icanbefitter/core/utils/e1rm.dart';

void main() {
  group('sessionMaxE1rm — MAX Epley over a session', () {
    test('single set → Epley w*(1+reps/30)', () {
      final e = sessionMaxE1rm({
        'sets': [
          {'weight_kg': 100, 'reps_completed': 5}
        ],
      });
      expect(e, closeTo(100 * (1 + 5 / 30.0), 1e-9)); // 116.67
    });

    test('MAX not heaviest-weight — a high-rep set can out-e1RM the heaviest', () {
      // 100×3 → 110 ; 80×12 → 112 (the real max). Heaviest-by-weight would pick
      // 110 and MASK a decline — the exact bug the MAX form prevents.
      final e = sessionMaxE1rm({
        'sets': [
          {'weight_kg': 100, 'reps_completed': 3},
          {'weight_kg': 80, 'reps_completed': 12},
        ],
      });
      expect(e, closeTo(112.0, 1e-9));
    });

    test('falls back to top-level weight/reps when no `sets` array', () {
      final e = sessionMaxE1rm({'weight_kg': 90, 'reps_completed': 5});
      expect(e, closeTo(90 * (1 + 5 / 30.0), 1e-9)); // 105
    });

    test('reps 0 → weight as-is (no Epley multiplier)', () {
      final e = sessionMaxE1rm({
        'sets': [
          {'weight_kg': 120, 'reps_completed': 0}
        ],
      });
      expect(e, closeTo(120.0, 1e-9));
    });

    test('no positive load (bodyweight / timed) → null', () {
      expect(
          sessionMaxE1rm({
            'sets': [
              {'weight_kg': 0, 'reps_completed': 10}
            ]
          }),
          isNull);
      expect(sessionMaxE1rm(const {}), isNull);
      expect(sessionMaxE1rm({'weight_kg': 0, 'reps_completed': 8}), isNull);
    });

    test('coerces String numerics (restored/legacy rows)', () {
      final e = sessionMaxE1rm({
        'sets': [
          {'weight_kg': '100', 'reps_completed': '5'}
        ],
      });
      expect(e, closeTo(100 * (1 + 5 / 30.0), 1e-9));
    });
  });
}
