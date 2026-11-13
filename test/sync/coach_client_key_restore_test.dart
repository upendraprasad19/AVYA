// BEHAVIORAL TEST — OI-503 restore (plan docs/plans/2026-11-13-coach-chat-time-dup.md
// section 4 C5, tests k1-k23; migration 178; diagnose d4a7c9).
//
// Writer: SyncService._restoreCoachInteractions -> _restoreCoachRowsKeyed
//   (lib/core/services/sync/sync_coach.dart), which writes a cloud row that
//   carries `client_key` back AT that key.
// Readers: ChatHistoryNotifier.build (one bubble pair per turn) and
//   CoachInteractionRepository.getTodayUserMessageCount (counted once).
//
// The founder's case (2026-11-13 07:00 IST): the phone keyed its row by its own
// clock (coach_<phone ms>), the restore keyed the server copy by the server's
// created_at (coach_<server ms>, 17 s later), and the turn showed twice.
//
// Real Hive; the restore runs through the `restoreCoachInteractionsForTest`
// seam with pre-fetched rows (no network).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/repositories/coach_interaction_repository.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../helpers/hive_test_setup.dart';

const _kMs = 1763000000000; // the phone's key
const _k = 'coach_$_kMs';
final _localAt = DateTime.fromMillisecondsSinceEpoch(_kMs, isUtc: true);
final _serverAt = _localAt.add(const Duration(seconds: 17));

String _uuid(int n) => 'aaaaaaaa-0000-4000-8000-${n.toString().padLeft(12, '0')}';

String _plus00(DateTime t) =>
    t.toUtc().toIso8601String().replaceFirst('Z', '+00:00');

Map<String, dynamic> _cloud({
  required int n,
  String? key = _k,
  String user = 'what is my workout today',
  String ai = 'Push day: bench, rows, press.',
  String model = 'gemini-3.1-flash-lite',
  String channel = 'app',
  DateTime? at,
}) =>
    {
      'id': _uuid(n),
      'user_id': kTestUserId,
      'channel': channel,
      'user_message': user,
      'ai_response': ai,
      'model_used': model,
      'created_at': _plus00(at ?? _serverAt),
      'client_key': key,
    };

Map<String, dynamic> _local({
  String user = 'what is my workout today',
  String ai = 'Push day: bench, rows, press.',
  String? id,
  bool pending = false,
  bool failed = false,
  DateTime? at,
  String mode = 'quick',
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id ?? _k,
      'user_message': user,
      'ai_response': ai,
      'model_used': 'gemini-3.1-flash-lite',
      'mode': mode,
      'is_user_message': true,
      'created_at': (at ?? _localAt).toIso8601String(),
      'pending': pending,
      'failed': failed,
      if (failed) 'error_text': 'Network error',
      ...extra,
    };

void main() {
  late Directory dir;
  var liveUid = kTestUserId;

  setUpAll(() async {
    dir = await setUpHiveForTests();
    // ignore: invalid_use_of_visible_for_testing_member
    HiveUserSession.debugCurrentUidResolverForTests = () => liveUid;
  });

  tearDownAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    HiveUserSession.debugCurrentUidResolverForTests = null;
    await tearDownHiveForTests(dir);
  });

  setUp(() async {
    liveUid = kTestUserId;
    CoachInteractionRepository.clearInFlight();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.configBox.delete(kDisableCoachClientKeyRestore);
  });

  final box = () => HiveService.instance.coachBox;
  Map row(String k) => box().get(k) as Map;
  List<String> chatKeys() => box()
      .keys
      .whereType<String>()
      .where((k) => kCoachRowKeyPattern.hasMatch(k))
      .toList()
    ..sort();

  Future<void> restore(List<Map<String, dynamic>> rows) => SyncService.instance
      .restoreCoachInteractionsForTest(kTestUserId, preFetched: rows);

  group('the founder case', () {
    test('k1: a complete local row and its keyed cloud row (17 s later) are ONE row; id stamped',
        () async {
      await box().put(_k, _local());
      await restore([_cloud(n: 1)]);
      expect(chatKeys(), [_k]);
      expect(row(_k)['id'], _uuid(1));
      expect(row(_k)['created_at'], _localAt.toIso8601String(),
          reason: 'created_at is never touched (a hidden row stays hidden, k14)');
    });

    test('k1 through the readers: one user bubble, one coach bubble, counted once', () async {
      final now = DateTime.now().toUtc();
      final key = 'coach_${now.millisecondsSinceEpoch}';
      await box().put(key, _local(id: key, at: now));
      await restore([
        _cloud(n: 1, key: key, at: now.add(const Duration(seconds: 17))),
      ]);
      final c = ProviderContainer(overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
      ]);
      addTearDown(c.dispose);
      final msgs = c.read(chatHistoryProvider);
      expect(msgs.where((m) => m.isUser), hasLength(1));
      expect(msgs.where((m) => !m.isUser && m.text.startsWith('Push day')), hasLength(1));
      expect(CoachInteractionRepository.instance.getTodayUserMessageCount(), 1);
    });

    test('the pre-OI-503 loop (kill switch, k12) reproduces the double', () async {
      await HiveService.instance.configBox.put(kDisableCoachClientKeyRestore, true);
      await box().put(_k, _local());
      await restore([_cloud(n: 1)]);
      expect(chatKeys(), hasLength(2),
          reason: 'old loop: coach_<server ms> next to the phone key');
      expect(row('coach_${_serverAt.millisecondsSinceEpoch}')['id'],
          'coach_${_serverAt.millisecondsSinceEpoch}',
          reason: 'the old loop is kept verbatim: id = the Hive key');
    });
  });

  group('fill rules', () {
    test('k2: a failed local row plus a complete cloud row: one completed row', () async {
      await box().put(_k, _local(ai: 'Sorry, network.', failed: true));
      await restore([_cloud(n: 1)]);
      final r = row(_k);
      expect(r['failed'], isFalse);
      expect(r['pending'], isFalse);
      expect(r['ai_response'], 'Push day: bench, rows, press.');
      expect(r.containsKey('error_text'), isFalse);
      expect(chatKeys(), [_k]);
    });

    test('k3: a pending row IN FLIGHT is only id-stamped; k3b: not in flight it is completed',
        () async {
      await box().put(_k, _local(ai: '', pending: true));
      CoachInteractionRepository.beginInFlight(_k);
      await restore([_cloud(n: 1)]);
      expect(row(_k)['pending'], isTrue);
      expect(row(_k)['ai_response'], '');
      expect(row(_k)['id'], _uuid(1));
      CoachInteractionRepository.endInFlight(_k);
      await restore([_cloud(n: 1)]);
      expect(row(_k)['pending'], isFalse);
      expect(row(_k)['ai_response'], 'Push day: bench, rows, press.');
    });

    test('k4: a complete local row plus a cloud pending placeholder: unchanged', () async {
      await box().put(_k, _local(id: _uuid(1)));
      final before = Map.of(row(_k));
      await restore([_cloud(n: 1, ai: '', model: 'pending')]);
      expect(row(_k), before);
    });

    test('k5: a failure-shaped cloud row never fills; the row keeps Retry', () async {
      for (final shape in [
        {'ai': '[failed] runToolLoop threw', 'model': 'failed'},
        {'ai': 'I had trouble reaching the model. Try again in a moment.', 'model': 'gemini'},
      ]) {
        await box().clear();
        await box().put(_k, _local(ai: 'err', failed: true));
        await restore([_cloud(n: 1, ai: shape['ai']!, model: shape['model']!)]);
        expect(row(_k)['failed'], isTrue, reason: shape.toString());
        expect(row(_k)['ai_response'], 'err');
        expect(row(_k)['id'], _uuid(1), reason: 'the id is still stamped');
      }
    });

    test('k6: a retry is two cloud rows with one key: one local row, the complete reply',
        () async {
      await box().put(_k, _local(ai: 'err', failed: true));
      await restore([
        _cloud(n: 1, ai: '', model: 'pending', at: _serverAt),
        _cloud(n: 2, at: _serverAt.add(const Duration(seconds: 40))),
      ]);
      expect(chatKeys(), [_k]);
      expect(row(_k)['ai_response'], 'Push day: bench, rows, press.');
      expect(row(_k)['id'], _uuid(2));
    });

    test('k17: a complete local reply A and a complete cloud reply B leave A', () async {
      await box().put(_k, _local(ai: 'Reply A'));
      await restore([_cloud(n: 1, ai: 'Reply B')]);
      expect(row(_k)['ai_response'], 'Reply A');
    });

    test('k18: each incomplete shape is filled when not in flight', () async {
      for (final local in [
        _local(ai: 'x', failed: true),
        _local(ai: '', pending: true),
        _local(ai: ''),
      ]) {
        await box().clear();
        await box().put(_k, local);
        await restore([_cloud(n: 1)]);
        expect(row(_k)['ai_response'], 'Push day: bench, rows, press.', reason: '$local');
      }
    });

    test('k19: two overlapping sends share a key: in flight until the SECOND ends', () async {
      CoachInteractionRepository.beginInFlight(_k);
      CoachInteractionRepository.beginInFlight(_k);
      CoachInteractionRepository.endInFlight(_k);
      expect(CoachInteractionRepository.isInFlight(_k), isTrue);
      await box().put(_k, _local(ai: '', pending: true));
      await restore([_cloud(n: 1)]);
      expect(row(_k)['pending'], isTrue, reason: 'still live: not filled');
      CoachInteractionRepository.endInFlight(_k);
      expect(CoachInteractionRepository.isInFlight(_k), isFalse);
      CoachInteractionRepository.endInFlight(_k); // a stray end is a no-op
      expect(CoachInteractionRepository.inFlightCountForTests(_k), 0);
    });

    test('k20: a failed turn the user already re-sent (newer, same text, within 60 s) is not filled',
        () async {
      const k2 = 'coach_${_kMs + 20000}';
      await box().put(_k, _local(ai: 'err', failed: true));
      await box().put(k2, _local(id: k2, at: _localAt.add(const Duration(seconds: 20))));
      await restore([_cloud(n: 1)]);
      expect(row(_k)['failed'], isTrue);
      expect(row(_k)['id'], _uuid(1), reason: 'the id is still stamped');
      // The same re-send 90 s later is a separate exchange: fill.
      await box().delete(k2);
      const k3 = 'coach_${_kMs + 90000}';
      await box().put(k3, _local(id: k3, at: _localAt.add(const Duration(seconds: 90))));
      await restore([_cloud(n: 1)]);
      expect(row(_k)['failed'], isFalse);
    });
  });

  group('media', () {
    test('k7: another device gets the row AT the key, id = uuid, media mode recognized', () async {
      await restore([_cloud(n: 1, user: '[Photo: image] my squat form')]);
      expect(chatKeys(), [_k]);
      expect(row(_k)['id'], _uuid(1));
      expect(row(_k)['mode'], 'media');
      expect(row(_k)['source'], 'cloud_restore');
    });

    test('k8 + k21: a failed local [Photo] row and the cloud [Photo: image] / [Video] row: stamped, filled, media fields kept',
        () async {
      for (final cloudText in ['[Photo: image] cap', '[Video] cap']) {
        await box().clear();
        await box().put(_k, _local(
          user: '[Photo] cap',
          ai: 'err',
          failed: true,
          mode: 'media',
          extra: {'media_url': 'https://x/y.jpg', 'media_save_state': 'saved', 'refunded': true},
        ));
        await restore([_cloud(n: 1, user: cloudText)]);
        final r = row(_k);
        expect(r['id'], _uuid(1), reason: cloudText);
        expect(r['failed'], isFalse, reason: cloudText);
        expect(r['ai_response'], 'Push day: bench, rows, press.');
        expect(r['media_save_state'], 'saved');
        expect(r['refunded'], isTrue);
        expect(r['media_url'], 'https://x/y.jpg');
        expect(r['user_message'], '[Photo] cap', reason: 'the phone text is kept');
        expect(chatKeys(), [_k]);
      }
    });

    test('coachTurnText strips exactly one leading media tag and trims', () {
      expect(coachTurnText('[Photo] cap'), 'cap');
      expect(coachTurnText('[Photo: image] cap'), 'cap');
      expect(coachTurnText('[Photo: video] cap '), 'cap');
      expect(coachTurnText('[Video] cap'), 'cap');
      expect(coachTurnText('  hello  '), 'hello');
      expect(coachTurnText(null), '');
      expect(coachTurnText('see [Photo] cap'), 'see [Photo] cap');
      expect(coachTurnText('[Photos] cap'), '[Photos] cap');
    });
  });

  group('stale copies, echoes and occupied keys', () {
    test('k9: a stale cloud_restore copy at coach_<server ms> is deleted; a different-text one is kept',
        () async {
      final copyKey = 'coach_${_serverAt.millisecondsSinceEpoch}';
      await box().put(_k, _local());
      await box().put(copyKey, {
        ..._local(id: copyKey, at: _serverAt),
        'source': 'cloud_restore',
      });
      await restore([_cloud(n: 1)]);
      expect(chatKeys(), [_k]);

      await box().put(copyKey, {
        ..._local(id: copyKey, at: _serverAt, user: 'something else'),
        'source': 'cloud_restore',
      });
      await restore([_cloud(n: 1)]);
      expect(chatKeys(), [_k, copyKey]..sort());
    });

    test('k10: a row without a key is written at coach_<server ms> with id = uuid', () async {
      await restore([_cloud(n: 1, key: null)]);
      final k = 'coach_${_serverAt.millisecondsSinceEpoch}';
      expect(chatKeys(), [k]);
      expect(row(k)['id'], _uuid(1));
    });

    test('a malformed client_key is treated as no key', () async {
      await restore([_cloud(n: 1, key: 'coach_abc')]);
      expect(chatKeys(), ['coach_${_serverAt.millisecondsSinceEpoch}']);
    });

    test('k15: a key occupied by a different-text incomplete row: neither stamped nor filled; the cloud row lands at coach_<server ms>',
        () async {
      await box().put(_k, _local(user: 'a different question', ai: '', pending: true));
      await restore([_cloud(n: 1)]);
      expect(row(_k)['id'], _k);
      expect(row(_k)['pending'], isTrue);
      final k = 'coach_${_serverAt.millisecondsSinceEpoch}';
      expect(row(k)['user_message'], 'what is my workout today');
    });

    test('k16: a keyed row plus its unkeyed same-instant echo give ONE row, in both input orders',
        () async {
      for (final order in [0, 1]) {
        await box().clear();
        await box().put(_k, _local());
        final keyed = _cloud(n: 1);
        final echo = _cloud(n: 2, key: null, channel: 'in_app_orphan');
        await restore(order == 0 ? [keyed, echo] : [echo, keyed]);
        expect(chatKeys(), [_k], reason: 'order $order');
      }
    });

    test('k22: coach_memory and a coach_<hex> key are never targeted, deleted or compared', () async {
      await box().put('coach_memory', {'why_now': 'x'});
      await box().put('coach_1a2b3c', {'user_message': 'what is my workout today', 'source': 'cloud_restore'});
      await box().put(_k, _local());
      await restore([_cloud(n: 1)]);
      expect(box().get('coach_memory'), {'why_now': 'x'});
      expect(box().get('coach_1a2b3c'), isNotNull);
      expect(kCoachRowKeyPattern.hasMatch('coach_memory'), isFalse);
      expect(kCoachRowKeyPattern.hasMatch('coach_1a2b3c'), isFalse);
    });

    test('k22b: a cloud row with an unparseable created_at never deletes a coach_<hex> row', () async {
      final cloud = _cloud(n: 1)..['created_at'] = 'not-a-date';
      final hexKey = coachUnkeyedRestoreKey(cloud);
      expect(kCoachRowKeyPattern.hasMatch(hexKey), isFalse, reason: 'precondition: a hex key');
      await box().put(_k, _local());
      await box().put(hexKey, {..._local(id: hexKey), 'source': 'cloud_restore'});
      await restore([cloud]);
      expect(box().get(hexKey), isNotNull);
      expect(row(_k)['id'], _uuid(1));
    });
  });

  group('safety', () {
    test('k11: the owner changes mid-pass: nothing lands after the change', () async {
      var checks = 0;
      // ignore: invalid_use_of_visible_for_testing_member
      HiveUserSession.debugCurrentUidResolverForTests = () {
        checks++;
        return checks <= 1 ? kTestUserId : 'someone-else';
      };
      addTearDown(() {
        // ignore: invalid_use_of_visible_for_testing_member
        HiveUserSession.debugCurrentUidResolverForTests = () => liveUid;
      });
      await restore([
        _cloud(n: 1, key: 'coach_1763000000001'),
        _cloud(n: 2, key: 'coach_1763000000002', user: 'q2'),
        _cloud(n: 3, key: null, user: 'q3'),
      ]);
      expect(chatKeys(), ['coach_1763000000001'],
          reason: 'only the group checked before the switch is written');
    });

    test('k13: a second pass changes nothing', () async {
      await box().put(_k, _local(ai: 'err', failed: true));
      final rows = [_cloud(n: 1), _cloud(n: 2, key: null, user: 'other', at: _serverAt.add(const Duration(minutes: 5)))];
      await restore(rows);
      final snap = {for (final k in chatKeys()) k: Map.of(row(k))};
      await restore(rows);
      expect({for (final k in chatKeys()) k: Map.of(row(k))}, snap);
    });

    test('pick tiers: complete beats a LATER incomplete; latest of two complete; equal instants take the later row',
        () {
      final complete = _cloud(n: 1, at: _serverAt);
      final laterPending = _cloud(n: 2, ai: '', model: 'pending', at: _serverAt.add(const Duration(minutes: 1)));
      expect(pickKeyedCloudCoachRow([complete, laterPending])['id'], _uuid(1));
      expect(pickKeyedCloudCoachRow([laterPending, complete])['id'], _uuid(1));
      final later = _cloud(n: 3, at: _serverAt.add(const Duration(minutes: 2)));
      expect(pickKeyedCloudCoachRow([later, complete])['id'], _uuid(3));
      final same = _cloud(n: 4, at: _serverAt);
      expect(pickKeyedCloudCoachRow([complete, same])['id'], _uuid(4));
    });

    test('k23: the decision slice holds no await between the in-flight check and the put(', () {
      final src = File('lib/core/services/sync/sync_coach.dart').readAsStringSync();
      final start = src.indexOf('final inFlight = CoachInteractionRepository.isInFlight(key);');
      final end = src.indexOf('if (next != null) await box.put(key, next);', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      expect(src.substring(start, end), isNot(contains('await')));
    });
  });
}
