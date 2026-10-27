// BEHAVIORAL TEST — paginate_all (free-tier-hold durability #4)
//
// Writer: lib/core/services/paginate_all.dart (paginateAll) — the pure loop
//         `_restoreScheduledWorkouts` now uses instead of a single
//         `.range(0, 999)` (which silently dropped the current phase from a
//         >1000-row holder's status merge).
//
// FAILS if the loop stops after one page, mis-computes the offset, or fails to
// stop on a short/empty final page.

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/paginate_all.dart';

void main() {
  group('paginateAll', () {
    test('single short page → returned as-is, one fetch', () async {
      var calls = 0;
      final rows = await paginateAll<int>(
        pageSize: 1000,
        fetchPage: (offset, pageSize) async {
          calls++;
          return List.generate(500, (i) => offset + i);
        },
      );
      expect(rows.length, 500);
      expect(calls, 1, reason: 'a short first page means no further fetch');
    });

    test('multiple full pages then a short one → all rows concatenated in order',
        () async {
      // 2500 total: pages of 1000, 1000, 500.
      final offsets = <int>[];
      final rows = await paginateAll<int>(
        pageSize: 1000,
        fetchPage: (offset, pageSize) async {
          offsets.add(offset);
          final remaining = 2500 - offset;
          final take = remaining >= pageSize ? pageSize : remaining;
          return List.generate(take, (i) => offset + i);
        },
      );
      expect(rows.length, 2500);
      expect(offsets, [0, 1000, 2000],
          reason: 'offset advances by pageSize each round');
      // Order preserved end to end.
      expect(rows.first, 0);
      expect(rows.last, 2499);
    });

    test('exactly a full final page → one extra empty fetch stops the loop',
        () async {
      // 1000 total: page 1 = full (1000) → must fetch again → empty → stop.
      var calls = 0;
      final rows = await paginateAll<int>(
        pageSize: 1000,
        fetchPage: (offset, pageSize) async {
          calls++;
          if (offset >= 1000) return <int>[];
          return List.generate(1000, (i) => offset + i);
        },
      );
      expect(rows.length, 1000);
      expect(calls, 2, reason: 'a full page cannot be assumed to be the last');
    });

    test('empty first page → empty result', () async {
      final rows = await paginateAll<int>(
        pageSize: 1000,
        fetchPage: (offset, pageSize) async => <int>[],
      );
      expect(rows, isEmpty);
    });
  });
}
