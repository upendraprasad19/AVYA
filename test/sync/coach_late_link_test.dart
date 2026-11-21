// BEHAVIORAL TEST — OI-505 fix 1, the push's late link anchored to the turn
// (plan docs/plans/2026-11-13-coach-late-link-timeout-retry.md section 4 fix 1,
// section 5 tests L1-L11; diagnose b7e1f3).
//
// Writer: SyncService._syncCoachInteractions (lib/core/services/sync/sync_coach.dart)
//   — the key lookup, then step 1 (`_lookupCoachTurnWindowRow`, a created_at
//   RANGE around the turn instant read from the key), then step 2 (the old
//   `now - 5 min` text lookup, kept verbatim), then the keyed orphan upsert.
// Reader: the cloud ai_coach_interactions row (and the restore, L10).
//
// Which tests discriminate (fail on the pre-OI-505 code) and which are
// regression guards that the old code also passes:
//   discriminate: L1, L3, L6, L10, L11, L12, L13.
//   guards:       L1b (step 2 is the old query), L4, L5, L8, L9.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _u1 = 'aaaaaaaa-0000-4000-8000-000000000001';
const _u2 = 'aaaaaaaa-0000-4000-8000-000000000002';
const _text = "tell me about today's workout";

String _keyAt(DateTime t) => 'coach_${t.millisecondsSinceEpoch}';

Map<String, dynamic> _row(
  String id,
  DateTime at, {
  String? key,
  String channel = 'app',
  String text = _text,
}) =>
    {
      'id': id,
      'user_id': kTestUserId,
      'channel': channel,
      'user_message': text,
      'ai_response': 'a',
      'model_used': 'gemini',
      'created_at': at.toUtc().toIso8601String(),
      'client_key': key,
    };

/// The local row's created_at: the key's instant, or now for a key the
/// DateTime range cannot hold (L4b's 16-digit key).
DateTime _seedInstant(String key) {
  final ms = int.tryParse(key.replaceFirst('coach_', ''));
  try {
    return DateTime.fromMillisecondsSinceEpoch(ms ?? 0, isUtc: true);
  } on Object {
    return DateTime.now().toUtc();
  }
}

Map _bodyRow(Object? body) => body is List ? body.single as Map : body! as Map;

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    CoachInteractionRepository.clearInFlight();
    h.server.clear();
    h.server.pagedTables.clear();
    h.server.pagedErrors.clear();
    h.server.getResponders.clear();
  });
  tearDown(h.tearDown);

  final box = () => HiveService.instance.coachBox;
  final now = DateTime.now().toUtc();

  Future<void> seed(String key, {String text = _text, String? id}) => box().put(key, {
        'id': id ?? key,
        'user_message': text,
        'ai_response': 'a',
        'model_used': 'gemini',
        'created_at': _seedInstant(key).toIso8601String(),
      });
  Future<void> push() => SyncService.instance.pushCoachInteractionsForSyncDomain();
  List<StubRequest> reads() => h.server.requests
      .where((r) => r.method == 'GET' && r.table == 'ai_coach_interactions')
      .toList();
  List<StubRequest> writes() => h.server.writesTo('ai_coach_interactions');
  bool isStep1(StubRequest r) =>
      r.queryAll['user_message'] != null && (r.queryAll['created_at']?.length ?? 0) == 2;
  bool isStep2(StubRequest r) =>
      r.queryAll['user_message'] != null && (r.queryAll['created_at']?.length ?? 0) == 1;

  group('pure helpers', () {
    test('coachTurnInstantFromKey: a valid key, a non-client key, an out-of-range key', () {
      final t = DateTime.utc(2026, 11, 13, 1, 30, 27, 975);
      expect(coachTurnInstantFromKey(_keyAt(t)), t);
      expect(coachTurnInstantFromKey('coach_1a2b3c'), isNull,
          reason: 'a coach_<hex> key is not a client key');
      expect(coachTurnInstantFromKey('coach_123456789'), isNull, reason: '9 digits');
      // 16 digits match the pattern but exceed DateTime's range: null, not a throw.
      expect(coachTurnInstantFromKey('coach_9999999999999999'), isNull);
      expect(coachTurnInstantFromKey('completion_prompt_2026-11-13'), isNull);
    });

    test('nearestRowToInstant: nearest wins, ties keep the earlier, bad rows and excluded ids are skipped', () {
      final t = DateTime.utc(2026, 11, 13, 1, 30);
      final rows = [
        _row('far', t.subtract(const Duration(minutes: 4))),
        _row('near', t.add(const Duration(seconds: 10))),
        {'id': 'no-time', 'created_at': null},
        {'id': '', 'created_at': t.toIso8601String()},
      ];
      expect(nearestRowToInstant(rows, t)!['id'], 'near');
      expect(nearestRowToInstant(rows, t, excludeIds: {'near'})!['id'], 'far');
      expect(nearestRowToInstant(rows, t, excludeIds: {'near', 'far'}), isNull);
      expect(nearestRowToInstant(const [], t), isNull);
      final tie = [
        _row('first', t.subtract(const Duration(seconds: 5))),
        _row('second', t.add(const Duration(seconds: 5))),
      ];
      expect(nearestRowToInstant(tie, t)!['id'], 'first');
    });
  });

  test('L1: the 07:00 case: a server row 5.5 h old with no key is linked, nothing is uploaded', () async {
    final turn = now.subtract(const Duration(hours: 5, minutes: 30));
    final key = _keyAt(turn);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, turn.add(const Duration(seconds: 23))),
    ];
    await seed(key);
    await push();
    expect(writes(), isEmpty, reason: 'the old window (last 5 min) missed this row and uploaded a second one');
    expect((box().get(key) as Map)['id'], _u1);
    expect(reads(), hasLength(2), reason: 'the key lookup and step 1; a hit needs no step 2');
    expect(isStep1(reads()[1]), isTrue);
  });

  test('L1b (guard): a phone clock 8 min ahead: step 1 misses, step 2 (the old query) still links', () async {
    final real = now.subtract(const Duration(minutes: 3));
    final key = _keyAt(real.add(const Duration(minutes: 8))); // the phone's clock
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, real.add(const Duration(seconds: 20))),
    ];
    await seed(key);
    await push();
    expect(writes(), isEmpty);
    expect((box().get(key) as Map)['id'], _u1);
    expect(reads(), hasLength(3));
    expect(isStep2(reads()[2]), isTrue);
  });

  test('L3: a cross-channel row 60 s after the turn is linked whenever the sync runs (now - T over 5 min)', () async {
    final turn = now.subtract(const Duration(hours: 2));
    final key = _keyAt(turn);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, turn.add(const Duration(seconds: 60)), channel: 'food_text_analysis'),
    ];
    await seed(key);
    await push();
    expect(writes(), isEmpty);
    expect((box().get(key) as Map)['id'], _u1);
  });

  test('L4 (guard): a key with no valid instant: only the old query runs, no range', () async {
    h.server.pagedTables['ai_coach_interactions'] = [];
    await seed('coach_1a2b3c');
    await push();
    final r = reads().single;
    expect(isStep2(r), isTrue);
    expect(r.queryAll['created_at']!.single, startsWith('gte.'));
    expect(r.queryAll['created_at']!.single, isNot(contains('lte.')));
  });

  test('L4b: an out-of-range 16-digit key: the key lookup runs, step 1 returns null without throwing, step 2 runs', () async {
    h.server.pagedTables['ai_coach_interactions'] = [];
    await seed('coach_9999999999999999');
    await push();
    final rs = reads();
    expect(rs.first.query['client_key'], 'eq.coach_9999999999999999');
    expect(rs.where(isStep1), isEmpty);
    expect(rs.where(isStep2), hasLength(1));
    expect(writes(), hasLength(1), reason: 'no server row: the turn goes up as its own keyed orphan');
  });

  test('L5 (guard): the kill switch skips step 1: the old window only, the old (duplicating) outcome', () async {
    await HiveService.instance.configBox.put(kDisableCoachTurnTimeWindow, true);
    final turn = now.subtract(const Duration(hours: 5));
    final key = _keyAt(turn);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, turn.add(const Duration(seconds: 23))),
    ];
    await seed(key);
    await push();
    expect(reads().where(isStep1), isEmpty);
    expect(writes(), hasLength(1), reason: 'the pre-OI-505 behavior, byte for byte');
  });

  test('L6: the step 1 request shape: both bounds, client_key is null, ordered, limit 10', () async {
    final turn = DateTime.utc(now.year, now.month, now.day).subtract(const Duration(hours: 3));
    final key = _keyAt(turn);
    h.server.pagedTables['ai_coach_interactions'] = [];
    await seed(key);
    await push();
    final r = reads().firstWhere(isStep1);
    final t = coachTurnInstantFromKey(key)!;
    expect(r.queryAll['created_at'],
        containsAll([
          'gte.${t.subtract(kCoachTurnWindowBefore).toIso8601String()}',
          'lte.${t.add(kCoachTurnWindowAfter).toIso8601String()}',
        ]));
    expect(kCoachTurnWindowBefore, const Duration(minutes: 5));
    expect(kCoachTurnWindowAfter, const Duration(minutes: 10));
    expect(r.query['client_key'], 'is.null');
    expect(r.query['order'], 'created_at.asc.nullslast');
    expect(r.query['limit'], '10');
    expect(r.query['user_id'], 'eq.$kTestUserId');
    expect(r.query['user_message'], 'eq.$_text');
  });

  test('L8 (guard): a row that carries ANOTHER turn\'s key is not a candidate; this turn uploads keyed', () async {
    final turn = now.subtract(const Duration(hours: 4));
    final key = _keyAt(turn);
    final other = _keyAt(turn.add(const Duration(seconds: 30)));
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u2, turn.add(const Duration(seconds: 30)), key: other),
    ];
    await seed(key);
    await push();
    final w = _bodyRow(writes().single.body);
    expect(w['client_key'], key);
    expect((box().get(key) as Map)['id'], isNot(_u2));
  });

  test('L9 (guard): the same words typed a day later are a different turn: not linked to the first turn\'s row', () async {
    final t1 = now.subtract(const Duration(hours: 26));
    final t2 = now.subtract(const Duration(hours: 2));
    final k1 = _keyAt(t1);
    final k2 = _keyAt(t2);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, t1.add(const Duration(seconds: 20))), // the first turn's real row
    ];
    await seed(k1);
    await seed(k2); // the second turn never reached the server
    await push();
    expect((box().get(k1) as Map)['id'], _u1);
    final up = writes().map((w) => _bodyRow(w.body)).toList();
    expect(up, hasLength(1));
    expect(up.single['client_key'], k2, reason: 'k2 uploads as its own row, never stamped with u1');
    expect((box().get(k2) as Map)['id'], isNot(_u1));
  });

  test('L10: the documented bound: after the stamp, a restore of the unkeyed row still writes it at its server key', () async {
    final turn = now.subtract(const Duration(hours: 5));
    final key = _keyAt(turn);
    final serverAt = turn.add(const Duration(seconds: 23));
    h.server.pagedTables['ai_coach_interactions'] = [_row(_u1, serverAt)];
    await seed(key);
    await push();
    expect((box().get(key) as Map)['id'], _u1);
    await SyncService.instance.restoreCoachInteractionsForTest(kTestUserId, preFetched: [
      _row(_u1, serverAt),
    ]);
    final sibling = 'coach_${serverAt.millisecondsSinceEpoch}';
    expect(box().get(sibling), isNotNull,
        reason: 'fix 1 stops NEW server doubles; a device already showing the turn twice keeps doing so until its next sign-in');
    expect(box().get(key), isNotNull);
  });

  test('L13 (B-pass A-F1): restore BEFORE push: the restored sibling of the server row does not bar that row from the unlinked local turn', () async {
    final turn = now.subtract(const Duration(hours: 5));
    final key = _keyAt(turn);
    final serverAt = turn.add(const Duration(seconds: 23));
    h.server.pagedTables['ai_coach_interactions'] = [_row(_u1, serverAt)];
    await seed(key); // the local turn, no cloud id yet
    await SyncService.instance.restoreCoachInteractionsForTest(kTestUserId, preFetched: [
      _row(_u1, serverAt),
    ]);
    final sibling = 'coach_${serverAt.millisecondsSinceEpoch}';
    final restored = box().get(sibling) as Map;
    expect(restored['source'], 'cloud_restore');
    expect(restored['id'], _u1, reason: 'the restored copy carries the cloud id');
    await push();
    expect(writes(), isEmpty,
        reason: 'the server row already exists: no second keyed row may be uploaded');
    expect((box().get(key) as Map)['id'], _u1);
  });

  test('L15 (B-pass A-F2): step 1 throws: step 2 and the upload still run (no turn is stranded behind a bad window read)', () async {
    h.server.pagedTables.remove('ai_coach_interactions');
    final turn = now.subtract(const Duration(hours: 3));
    final key = _keyAt(turn);
    h.server.getResponders['ai_coach_interactions'] = (r) {
      // Only the step-1 read (two created_at bounds) answers a body the client
      // cannot parse as a row list.
      if ((r.queryAll['created_at']?.length ?? 0) == 2) return {'unexpected': 'object'};
      return const [];
    };
    await seed(key);
    await push();
    expect(reads().where(isStep1), hasLength(1), reason: 'step 1 ran and failed');
    expect(reads().where(isStep2), hasLength(1), reason: 'step 2 still ran after the failed step 1');
    final up = writes().map((w) => _bodyRow(w.body)).toList();
    expect(up, hasLength(1));
    expect(up.single['client_key'], key, reason: 'the turn is not stranded: it uploads as its own keyed row');
  });

  test('L14 (B-pass A-F2): a 16-digit key above year 9999 skips step 1 (no request with a +010000 timestamp)', () async {
    const key = 'coach_1763000000000';
    expect(coachTurnInstantFromKey(key), isNotNull, reason: 'a 13-digit key is a normal instant');
    // 253402300800000 ms = year 10000-01-01; 15 digits, inside DateTime's range.
    const beyond = 'coach_253402300800000';
    expect(coachTurnInstantFromKey(beyond), isNull, reason: 'year 10000 prints as +010000-...');
    await box().put(beyond, {
      'id': beyond,
      'user_message': _text,
      'ai_response': 'a',
      'model_used': 'gemini',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await push();
    expect(reads().where(isStep1), isEmpty);
    for (final r in h.server.requests) {
      for (final v in r.queryAll.values.expand((l) => l)) {
        expect(v.contains('+0'), isFalse, reason: 'no out-of-range timestamp on the wire: $v');
      }
    }
  });

  test('L11: two candidates in the window: the one NEAREST to the turn wins, not the first by time', () async {
    final turn = now.subtract(const Duration(hours: 3));
    final key = _keyAt(turn);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, turn.subtract(const Duration(minutes: 4))), // earlier, FIRST in created_at order
      _row(_u2, turn.add(const Duration(seconds: 10))), // nearest
    ];
    await seed(key);
    await push();
    expect((box().get(key) as Map)['id'], _u2);
    expect(writes(), isEmpty);
  });

  test('L12: a server row already stamped onto ANOTHER local turn is not stamped onto this one', () async {
    final t1 = now.subtract(const Duration(hours: 3));
    final t2 = t1.add(const Duration(minutes: 2)); // inside u1's window as well
    final k1 = _keyAt(t1);
    final k2 = _keyAt(t2);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, t1.add(const Duration(seconds: 15))),
    ];
    await seed(k1, id: _u1); // already linked to u1
    await seed(k2); // its own request never reached the server
    await push();
    expect((box().get(k1) as Map)['id'], _u1);
    expect((box().get(k2) as Map)['id'], isNot(_u1),
        reason: 'u1 belongs to k1; k2 uploads as its own row');
    final up = writes().map((w) => _bodyRow(w.body)).toList();
    expect(up.single['client_key'], k2);
  });

  test('L12b: within ONE pass, the row the first turn took is not taken again by the second', () async {
    final t1 = now.subtract(const Duration(hours: 3));
    final t2 = t1.add(const Duration(minutes: 2));
    final k1 = _keyAt(t1);
    final k2 = _keyAt(t2);
    h.server.pagedTables['ai_coach_interactions'] = [
      _row(_u1, t1.add(const Duration(seconds: 15))),
    ];
    await seed(k1);
    await seed(k2);
    await push();
    expect((box().get(k1) as Map)['id'], _u1);
    expect((box().get(k2) as Map)['id'], isNot(_u1));
    expect(writes().map((w) => _bodyRow(w.body)['client_key']).toList(), [k2]);
  });

  test('L13: step 1 also runs after a failed key lookup, WITHOUT the client_key filter (the column may not exist)', () async {
    final turn = now.subtract(const Duration(hours: 5));
    final key = _keyAt(turn);
    // Rows without a client_key column: the paged model answers 400 / 42703.
    h.server.pagedTables['ai_coach_interactions'] = [
      {
        'id': _u1,
        'user_id': kTestUserId,
        'user_message': _text,
        'created_at': turn.add(const Duration(seconds: 23)).toIso8601String(),
      },
    ];
    await seed(key);
    await push();
    final step1 = reads().firstWhere(isStep1);
    expect(step1.query.containsKey('client_key'), isFalse);
    expect(step1.query['select'], isNot(contains('client_key')));
    expect((box().get(key) as Map)['id'], _u1, reason: 'a hit stamps even on a database without the column');
    expect(writes(), isEmpty);
  });
}
