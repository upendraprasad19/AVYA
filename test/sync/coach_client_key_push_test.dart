// BEHAVIORAL TEST — OI-503 push (plan docs/plans/2026-11-13-coach-chat-time-dup.md
// section 4 C4, tests p1-p9; migration 178; diagnose d4a7c9).
//
// Writer: SyncService._syncCoachInteractions (lib/core/services/sync/sync_coach.dart)
//   — the client_key lookup first, the text lookup second, then the orphan
//   upsert (keyed), and the fresh-read id stamp.
// Reader: the cloud ai_coach_interactions row, read back by the restore.
//
// The stub answers ai_coach_interactions with REAL PostgREST filter semantics
// (pagedTables): an unknown column is a 400 / 42703, which is exactly a database
// that does not have the column yet (p5).
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';

import '../helpers/hive_test_setup.dart';
import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

const _k = 'coach_1763000000000';
const _cloudId = 'aaaaaaaa-0000-4000-8000-000000000001';

Map<String, dynamic> _serverRow({String? key = _k, String user = 'q', DateTime? at}) => {
      'id': _cloudId,
      'user_id': kTestUserId,
      'channel': 'app',
      'user_message': user,
      'ai_response': 'a',
      'model_used': 'gemini',
      'created_at': (at ?? DateTime.now().toUtc().subtract(const Duration(hours: 2)))
          .toIso8601String(),
      'client_key': key,
    };

Map _bodyRow(Object? body) => body is List ? body.single as Map : body! as Map;

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    CoachInteractionRepository.clearInFlight();
    // The harness's server object (and its request log) outlives a test.
    h.server.clear();
    h.server.pagedTables.clear();
    h.server.pagedErrors.clear();
    h.server.getResponders.clear();
  });
  tearDown(h.tearDown);

  final box = () => HiveService.instance.coachBox;
  Future<void> seed(String key, {String user = 'q', String? source, String? id}) =>
      box().put(key, {
        'id': id ?? key,
        'user_message': user,
        'ai_response': 'a',
        'model_used': 'gemini',
        'created_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String(),
        'source': ?source,
      });
  Future<void> push() => SyncService.instance.pushCoachInteractionsForSyncDomain();
  List<StubRequest> reads() => h.server.requests
      .where((r) => r.method == 'GET' && r.table == 'ai_coach_interactions')
      .toList();
  List<StubRequest> writes() => h.server.writesTo('ai_coach_interactions');
  // OI-505: the push now reads up to three times per unlinked turn: the key
  // lookup, step 1 (a created_at RANGE: gte and lte), step 2 (the old text
  // lookup: one created_at bound).
  bool isStep1(StubRequest r) =>
      r.queryAll['user_message'] != null && (r.queryAll['created_at']?.length ?? 0) == 2;
  bool isStep2(StubRequest r) =>
      r.queryAll['user_message'] != null && (r.queryAll['created_at']?.length ?? 0) == 1;

  test('p1: a keyed cloud row stamps the local row, and nothing is upserted', () async {
    h.server.pagedTables['ai_coach_interactions'] = [_serverRow()];
    await seed(_k);
    await push();
    expect(writes(), isEmpty);
    expect((box().get(_k) as Map)['id'], _cloudId);
    expect(reads().first.query['client_key'], 'eq.$_k', reason: 'the key lookup runs first');
    expect(reads(), hasLength(1), reason: 'a key hit needs no text lookup');
  });

  test('p2: no keyed row: the text lookup runs and a text hit stamps', () async {
    h.server.pagedTables['ai_coach_interactions'] = [
      _serverRow(key: null, at: DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
    ];
    await seed(_k);
    await push();
    expect(reads(), hasLength(3),
        reason: 'the key lookup, step 1 (anchored to the 2025 key: a miss), step 2');
    expect(isStep1(reads()[1]), isTrue);
    expect(isStep2(reads()[2]), isTrue);
    expect(reads()[2].query['user_message'], 'eq.q');
    expect(writes(), isEmpty);
    expect((box().get(_k) as Map)['id'], _cloudId);
  });

  test('p3: the orphan upsert carries client_key; a coach_<hex> key upserts without it', () async {
    h.server.pagedTables['ai_coach_interactions'] = [];
    await seed(_k);
    await seed('coach_1a2b3c', user: 'other');
    await push();
    final rows = writes().map((w) => _bodyRow(w.body)).toList();
    final keyed = rows.firstWhere((r) => r['user_message'] == 'q');
    expect(keyed['client_key'], _k);
    expect(keyed['channel'], 'in_app_orphan');
    final hex = rows.firstWhere((r) => r['user_message'] == 'other');
    expect(hex.containsKey('client_key'), isFalse,
        reason: 'the CHECK would refuse coach_<hex> on every pass');
    expect(reads().where((r) => r.query['client_key'] == 'eq.coach_1a2b3c'), isEmpty,
        reason: 'no lookup for a key the server can never hold');
    expectWritesMatchLiveSchema(h.server);
  });

  test('p4: the restore runs and then the push: no upsert of the restored row', () async {
    h.server.pagedTables['ai_coach_interactions'] = [];
    await SyncService.instance.restoreCoachInteractionsForTest(kTestUserId, preFetched: [
      _serverRow(key: null),
      _serverRow(key: _k)..['id'] = 'aaaaaaaa-0000-4000-8000-000000000002',
    ]);
    h.server.clear();
    await push();
    expect(writes(), isEmpty);
    expect(reads(), isEmpty, reason: 'restored rows are not even looked up');
  });

  test('p5: the key lookup throws (no column): the text lookup still runs; the orphan goes up without client_key',
      () async {
    // Rows WITHOUT a client_key column: the paged model answers 400 / 42703.
    h.server.pagedTables['ai_coach_interactions'] = [
      {
        'id': 'bbbbbbbb-0000-4000-8000-000000000009',
        'user_id': kTestUserId,
        'user_message': 'unrelated',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    ];
    await seed(_k);
    await push();
    expect(h.server.pagedErrors.any((e) => e.contains('client_key')), isTrue,
        reason: 'precondition: the key lookup failed on the missing column');
    for (final textLookup in reads().where((r) => r.query['user_message'] == 'eq.q')) {
      expect(textLookup.query['select'], isNot(contains('client_key')),
          reason: 'a database without the column would fail the text lookup too');
      expect(textLookup.query.containsKey('client_key'), isFalse,
          reason: 'step 1 must not filter on the missing column either');
    }
    final row = _bodyRow(writes().single.body);
    expect(row.containsKey('client_key'), isFalse);
  });

  test('p6: an in-flight row is skipped', () async {
    h.server.pagedTables['ai_coach_interactions'] = [];
    await seed(_k);
    CoachInteractionRepository.beginInFlight(_k);
    await push();
    expect(h.server.requests.where((r) => r.table == 'ai_coach_interactions'), isEmpty);
    CoachInteractionRepository.endInFlight(_k);
    await push();
    expect(writes(), hasLength(1));
  });

  test('p7: a restore fill landing during the lookup survives the stamp (fresh read)', () async {
    h.server.pagedTables.remove('ai_coach_interactions');
    await box().put(_k, {
      'id': _k,
      'user_message': 'q',
      'ai_response': '',
      'failed': true,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    h.server.getResponders['ai_coach_interactions'] = (r) {
      if (r.query['client_key'] == 'eq.$_k') {
        // The restore fills the row while the push awaits this answer.
        final cur = Map<String, dynamic>.from(box().get(_k) as Map)
          ..['ai_response'] = 'filled'
          ..['failed'] = false;
        box().put(_k, cur);
        return [
          {'id': _cloudId},
        ];
      }
      return const [];
    };
    await push();
    final r = box().get(_k) as Map;
    expect(r['id'], _cloudId);
    expect(r['ai_response'], 'filled', reason: 'the stale pre-await copy was not written back');
    expect(r['failed'], isFalse);
  });

  test('p8: a row deleted during the lookup is not re-created', () async {
    h.server.pagedTables.remove('ai_coach_interactions');
    await seed(_k);
    h.server.getResponders['ai_coach_interactions'] = (r) {
      if (r.query['client_key'] == 'eq.$_k') {
        box().delete(_k);
        return [
          {'id': _cloudId},
        ];
      }
      return const [];
    };
    await push();
    expect(box().get(_k), isNull);
  });

  test('p10: a text hit that carries ANOTHER turn\'s key is not stamped; this turn goes up as its own keyed orphan (B-pass A-F1)',
      () async {
    const k2 = 'coach_1763000020000';
    h.server.pagedTables['ai_coach_interactions'] = [
      _serverRow(key: k2, at: DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
    ];
    await seed(_k); // K1: same words, its own send never reached the server
    await push();
    expect(reads().firstWhere(isStep2).query['select'], contains('client_key'),
        reason: 'the text lookup must read the hit\'s key to tell the turns apart');
    expect((box().get(_k) as Map)['id'], isNot(_cloudId),
        reason: 'K2\'s cloud id must not be stamped onto K1');
    final row = _bodyRow(writes().single.body);
    expect(row['client_key'], _k);
    expect(row['channel'], 'in_app_orphan');
  });

  test('p9: a cloud_restore row with a non-uuid id (old restore loop) is neither looked up nor upserted',
      () async {
    h.server.pagedTables['ai_coach_interactions'] = [];
    await seed(_k, source: 'cloud_restore');
    await push();
    expect(h.server.requests.where((r) => r.table == 'ai_coach_interactions'), isEmpty);
  });
}
