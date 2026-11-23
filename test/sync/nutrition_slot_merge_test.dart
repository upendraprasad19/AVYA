// OI-348 Landing 1a-ii — the pure merge module (spec
// docs/plans/nutrition-slot-sync.md §4.1-§4.5, §4.11 admission).
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';

Map<String, dynamic> _entry({
  num cal = 300,
  num p = 20,
  num c = 30,
  num f = 10,
  num? fib = 5,
  List<Map<String, dynamic>>? items,
}) =>
    {
      'total_calories': cal,
      'total_protein': p,
      'total_carbs': c,
      'total_fat': f,
      'total_fiber': fib,
      'items': items ??
          [
            {
              'name': 'Dal',
              'quantity_g': 150,
              'calories': 300,
              'protein': 20,
              'carbs': 30,
              'fat': 10,
              'fiber': 5,
            },
          ],
    };

NslotEntryView _v(String id, String sig, String loggedAt) =>
    NslotEntryView(id: id, signature: sig, loggedAt: loggedAt);

void main() {
  group('§4.2 numbers and text', () {
    test('3 decimals, zero and negative zero both 0.000', () {
      expect(nslotNumText(0.1 + 0.2), '0.300');
      expect(nslotNumText(-0.0), '0.000');
      expect(nslotNumText(-0.0004), '0.000');
      expect(nslotNumText(100), '100.000');
      expect(nslotNumText(100.0), '100.000');
      expect(nslotNumText(1.23456), '1.235');
      expect(nslotNumText(-2.5), '-2.500');
      expect(nslotNumText(null), '0.000');
      expect(nslotNumText('12'), '0.000');
      expect(nslotNumText(double.nan), '0.000');
      expect(nslotNumText(double.infinity), '0.000');
    });

    test('projection is a fixed point (a round trip never moves a value)', () {
      for (final v in [0.1 + 0.2, 1.23456, 99.9995, 14999.9994, -0.0]) {
        final once = nslotProjectNum(v);
        expect(nslotProjectNum(once), once);
        expect(nslotNumText(once), nslotNumText(v));
      }
    });

    test('ASCII-only lowercasing leaves non-ASCII letters alone', () {
      expect(nslotAsciiLower('ÀBc Dal'), 'Àbc dal');
      expect(nslotAsciiLower('İ'), 'İ');
    });

    test('canonical text, exact', () {
      expect(
        nslotCanonicalText(_entry()),
        '300.000|20.000|30.000|10.000|5.000;'
        'dal|150.000|300.000|20.000|30.000|10.000|5.000',
      );
    });
  });

  group('§4.2 signature', () {
    // B-pass seat B P3: the payload sends `name ?? food_name`, and the cloud
    // copy comes back with `name`; the signature must read the same fallback.
    test('an item carrying only food_name signs like its cloud copy (name)',
        () {
      Map<String, dynamic> item(String key) => {
            key: 'Dal',
            'quantity_g': 150,
            'calories': 300,
            'protein': 20,
            'carbs': 30,
            'fat': 10,
            'fiber': 5,
          };
      final local = _entry(items: [item('food_name')]);
      final cloud = _entry(items: [item('name')]);
      expect(nslotSignature(local), nslotSignature(cloud));
      // The mirror: a different name still changes the signature.
      final other = _entry(items: [
        {...item('food_name'), 'food_name': 'Rice'},
      ]);
      expect(nslotSignature(other), isNot(nslotSignature(cloud)));
    });

    test('int and double of one value give one signature', () {
      final a = _entry(cal: 300);
      final b = _entry(cal: 300.0);
      expect(nslotSignature(a), nslotSignature(b));
    });

    test('name case and surrounding spaces do not change it', () {
      final a = _entry();
      final b = _entry(items: [
        {
          'name': '  DAL ',
          'quantity_g': 150.0,
          'calories': 300,
          'protein': 20,
          'carbs': 30,
          'fat': 10,
          'fiber': 5,
        },
      ]);
      expect(nslotSignature(a), nslotSignature(b));
    });

    test('a quantity, a macro, a total or the item order changes it', () {
      final base = nslotSignature(_entry());
      Map<String, dynamic> item(String n, num q) => {
            'name': n,
            'quantity_g': q,
            'calories': 300,
            'protein': 20,
            'carbs': 30,
            'fat': 10,
            'fiber': 5,
          };
      expect(nslotSignature(_entry(items: [item('Dal', 151)])), isNot(base));
      expect(nslotSignature(_entry(fib: 6)), isNot(base));
      expect(nslotSignature(_entry(fib: null)), isNot(base));
      final ab = _entry(items: [item('a', 1), item('b', 1)]);
      final ba = _entry(items: [item('b', 1), item('a', 1)]);
      expect(nslotSignature(ab), isNot(nslotSignature(ba)));
    });

    test('an edit below 0.0005 is invisible (accepted, §4.2)', () {
      expect(nslotSignature(_entry(cal: 300.0004)),
          nslotSignature(_entry(cal: 300)));
    });

    test('S10: projecting an entry keeps its signature', () {
      final raw = _entry(cal: 0.1 + 0.2, p: 1.23456);
      final projected = {
        for (final k in [
          'total_calories',
          'total_protein',
          'total_carbs',
          'total_fat',
          'total_fiber',
        ])
          k: nslotProjectNum(raw[k]),
        'items': [
          for (final i in raw['items'] as List)
            {
              'name': (i as Map)['name'],
              for (final k in [
                'quantity_g',
                'calories',
                'protein',
                'carbs',
                'fat',
                'fiber',
              ])
                k: nslotProjectNum(i[k]),
            },
        ],
      };
      expect(nslotSignature(projected), nslotSignature(raw));
    });

    test('signature is a lowercase uuid string', () {
      expect(nslotSignature(_entry()),
          matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-')));
    });
  });

  group('§4.1 synthetic entry id', () {
    test('deterministic, changes with rev and with the row', () {
      const row = '0b6f1a2e-1111-4222-8333-444455556666';
      expect(nslotSyntheticEntryId(row, 3), nslotSyntheticEntryId(row, 3));
      expect(nslotSyntheticEntryId(row, 4), isNot(nslotSyntheticEntryId(row, 3)));
      expect(
        nslotSyntheticEntryId('0b6f1a2e-1111-4222-8333-444455556667', 3),
        isNot(nslotSyntheticEntryId(row, 3)),
      );
    });
  });

  group('§4.5 logged_at text', () {
    test('microseconds and milliseconds of one instant compare equal', () {
      expect(nslotNormLoggedAt('2026-11-23T04:30:12.345678Z'),
          nslotNormLoggedAt('2026-11-23T04:30:12.345Z'));
      expect(nslotNormLoggedAt('2026-11-23T04:30:12.345678Z'),
          '2026-11-23T04:30:12.345');
    });

    test('no fraction or a short one is zero-padded', () {
      expect(nslotNormLoggedAt('2026-11-23T04:30:12Z'), '2026-11-23T04:30:12.000');
      expect(nslotNormLoggedAt('2026-11-23T04:30:12.5'), '2026-11-23T04:30:12.500');
      expect(nslotNormLoggedAt('2026-11-23T04:30:12+00:00'),
          '2026-11-23T04:30:12.000');
    });

    test('absent or short sorts oldest', () {
      expect(nslotNormLoggedAt(null), '');
      expect(nslotNormLoggedAt('2026-11-23'), '');
      expect(nslotNormLoggedAt(12), '');
      expect(''.compareTo(nslotNormLoggedAt('2026-01-01T00:00:00Z')) < 0, isTrue);
    });
  });

  group('§4.5 mergeSlot rules', () {
    const t1 = '2026-11-23T04:00:00.000';
    const t2 = '2026-11-23T05:00:00.000';

    test('rule 1: L == C keeps', () {
      final r = nslotMergeSlot(
        base: {'a': 'x'},
        local: {'a': _v('a', 's1', t1)},
        cloud: {'a': _v('a', 's1', t2)},
      );
      expect(r, {'a': NslotChoice.keepLocal});
    });

    test('rule 1: removed on both sides since the base stays removed', () {
      final r = nslotMergeSlot(base: {'a': 's1'}, local: {}, cloud: {});
      expect(r, {'a': NslotChoice.remove});
    });

    test('rule 2: local unchanged → take the cloud edit', () {
      final r = nslotMergeSlot(
        base: {'a': 's1'},
        local: {'a': _v('a', 's1', t2)},
        cloud: {'a': _v('a', 's2', t1)},
      );
      expect(r, {'a': NslotChoice.takeCloud});
    });

    test('rule 2: local unchanged, cloud deleted → remove', () {
      final r = nslotMergeSlot(
        base: {'a': 's1'},
        local: {'a': _v('a', 's1', t2)},
        cloud: {},
      );
      expect(r, {'a': NslotChoice.remove});
    });

    test('rule 3: cloud unchanged → keep the local edit', () {
      final r = nslotMergeSlot(
        base: {'a': 's1'},
        local: {'a': _v('a', 's2', t1)},
        cloud: {'a': _v('a', 's1', t2)},
      );
      expect(r, {'a': NslotChoice.keepLocal});
    });

    test('rule 3: cloud unchanged, local deleted → stays removed', () {
      final r = nslotMergeSlot(
        base: {'a': 's1'},
        local: {},
        cloud: {'a': _v('a', 's1', t2)},
      );
      expect(r, {'a': NslotChoice.remove});
    });

    test('rule 4: both edited → the newer logged_at wins, both ways', () {
      final older = _v('a', 's2', t1);
      final newer = _v('a', 's3', t2);
      expect(
        nslotMergeSlot(base: {'a': 's1'}, local: {'a': newer}, cloud: {'a': older}),
        {'a': NslotChoice.keepLocal},
      );
      expect(
        nslotMergeSlot(base: {'a': 's1'}, local: {'a': older}, cloud: {'a': newer}),
        {'a': NslotChoice.takeCloud},
      );
    });

    test('rule 4 tie: the larger signature wins on BOTH devices', () {
      final small = _v('a', 'aaa', t1);
      final large = _v('a', 'bbb', t1);
      // Device A holds small, device B holds large: both end on large.
      expect(
        nslotMergeSlot(base: {'a': 's1'}, local: {'a': small}, cloud: {'a': large}),
        {'a': NslotChoice.takeCloud},
      );
      expect(
        nslotMergeSlot(base: {'a': 's1'}, local: {'a': large}, cloud: {'a': small}),
        {'a': NslotChoice.keepLocal},
      );
    });

    test('rule 5 (S9): edited on one side, deleted on the other → kept', () {
      expect(
        nslotMergeSlot(
            base: {'a': 's1'}, local: {'a': _v('a', 's2', t1)}, cloud: {}),
        {'a': NslotChoice.keepLocal},
      );
      expect(
        nslotMergeSlot(
            base: {'a': 's1'}, local: {}, cloud: {'a': _v('a', 's2', t1)}),
        {'a': NslotChoice.takeCloud},
      );
    });

    test('S6/S7: empty base → union by entry id, no content matching', () {
      final r = nslotMergeSlot(
        base: {},
        local: {'a': _v('a', 'same', t1)},
        cloud: {'b': _v('b', 'same', t1)},
      );
      expect(r, {'a': NslotChoice.keepLocal, 'b': NslotChoice.takeCloud});
    });

    test('mixed slot: each id decided on its own', () {
      final r = nslotMergeSlot(
        base: {'a': 's1', 'b': 's1', 'c': 's1'},
        local: {'a': _v('a', 's1', t1), 'c': _v('c', 's9', t1), 'd': _v('d', 'n', t1)},
        cloud: {'a': _v('a', 's2', t1), 'b': _v('b', 's1', t1), 'c': _v('c', 's1', t1)},
      );
      expect(r, {
        'a': NslotChoice.takeCloud,
        'b': NslotChoice.remove,
        'c': NslotChoice.keepLocal,
        'd': NslotChoice.keepLocal,
      });
    });

    test('two devices merging the same three states end on the same content',
        () {
      // Exhaustive over small signature alphabets: device A sees (L=x, C=y),
      // device B sees (L=y, C=x), both from base b. The surviving signature
      // must agree.
      const sigs = [null, 's1', 's2', 's3'];
      const times = [t1, t2];
      String? survivor(NslotChoice ch, NslotEntryView? l, NslotEntryView? c) =>
          switch (ch) {
            NslotChoice.keepLocal => l?.signature,
            NslotChoice.takeCloud => c?.signature,
            NslotChoice.remove => null,
          };
      for (final b in sigs) {
        for (final x in sigs) {
          for (final y in sigs) {
            for (final tx in times) {
              for (final ty in times) {
                if (b == null && x == null && y == null) continue;
                final vx = x == null ? null : _v('a', x, tx);
                final vy = y == null ? null : _v('a', y, ty);
                final base = b == null ? <String, String>{} : {'a': b};
                final ra = nslotMergeSlot(
                  base: base,
                  local: {if (vx != null) 'a': vx},
                  cloud: {if (vy != null) 'a': vy},
                )['a']!;
                final rb = nslotMergeSlot(
                  base: base,
                  local: {if (vy != null) 'a': vy},
                  cloud: {if (vx != null) 'a': vx},
                )['a']!;
                expect(survivor(ra, vx, vy), survivor(rb, vy, vx),
                    reason: 'b=$b x=$x@$tx y=$y@$ty');
              }
            }
          }
        }
      }
    });
  });

  group('§4.5 day pass', () {
    const t1 = '2026-11-23T04:00:00.000';
    const t2 = '2026-11-23T05:00:00.000';
    NslotDayCopy copy(String id, String sig, String t, String meal, String key) =>
        NslotDayCopy(view: _v(id, sig, t), mealType: meal, key: key);

    test('S4b: the newer logged_at copy is kept', () {
      final r = nslotDayPass([
        copy('a', 's1', t1, 'lunch', 'nlog_2026-11-23_lunch_aaaaaaaa'),
        copy('a', 's2', t2, 'dinner', 'nlog_2026-11-23_dinner_aaaaaaaa'),
      ]);
      expect(r, {'nlog_2026-11-23_lunch_aaaaaaaa'});
    });

    test('tie → larger signature, then larger key; order-independent', () {
      final x = copy('a', 's1', t1, 'lunch', 'k1');
      final y = copy('a', 's2', t1, 'dinner', 'k2');
      expect(nslotDayPass([x, y]), {'k1'});
      expect(nslotDayPass([y, x]), {'k1'});
      final p = copy('a', 's1', t1, 'lunch', 'k1');
      final q = copy('a', 's1', t1, 'dinner', 'k2');
      expect(nslotDayPass([p, q]), {'k1'});
      expect(nslotDayPass([q, p]), {'k1'});
    });

    test('three copies keep one; singletons are untouched', () {
      final r = nslotDayPass([
        copy('a', 's1', t1, 'breakfast', 'k1'),
        copy('a', 's1', t2, 'lunch', 'k2'),
        copy('a', 's1', t1, 'dinner', 'k3'),
        copy('b', 's1', t1, 'dinner', 'k4'),
      ]);
      expect(r, {'k1', 'k3'});
    });
  });

  group('§4.5 placement', () {
    const d = '2026-11-23';
    const id = '9f8e7d6c-5b4a-4321-8abc-def012345678';
    const own = 'nlog_2026-11-23_lunch_1a2b3c4d';

    test('same-slot holder key wins', () {
      expect(
        nslotPlaceKey(
          date: d,
          meal: 'lunch',
          entryId: id,
          cloudKey: own,
          sameSlotKey: 'nlog_2026-11-23_lunch_ffffffff_2',
          taken: (_) => true,
        ),
        'nlog_2026-11-23_lunch_ffffffff_2',
      );
    });

    test('own key when free, else the first free occurrence of its base', () {
      expect(
        nslotPlaceKey(
            date: d, meal: 'lunch', entryId: id, cloudKey: own, sameSlotKey: null,
            taken: (_) => false),
        own,
      );
      final taken = {own, '${own}_2'};
      expect(
        nslotPlaceKey(
            date: d,
            meal: 'lunch',
            entryId: id,
            cloudKey: '${own}_7',
            sameSlotKey: null,
            taken: (k) => taken.contains(k) || k == '${own}_7'),
        '${own}_3',
      );
    });

    test('a key naming another slot, or malformed, is derived from the id', () {
      for (final bad in [
        'nlog_2026-11-23_dinner_1a2b3c4d',
        'nlog_2026-11-22_lunch_1a2b3c4d',
        'garbage',
        null,
      ]) {
        expect(
          nslotPlaceKey(
              date: d, meal: 'lunch', entryId: id, cloudKey: bad,
              sameSlotKey: null, taken: (_) => false),
          'nlog_2026-11-23_lunch_9f8e7d6c',
          reason: '$bad',
        );
      }
    });
  });

  group('§4.11 slot admission', () {
    test('only the four meal types', () {
      for (final m in ['breakfast', 'lunch', 'dinner', 'snacks']) {
        expect(nslotAdmitMealType(m), isTrue);
      }
      for (final m in [null, '', 'snack', 'Lunch', 'supper', 3]) {
        expect(nslotAdmitMealType(m), isFalse, reason: '$m');
      }
    });
  });
}
