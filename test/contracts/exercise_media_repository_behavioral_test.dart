// test/contracts/exercise_media_repository_behavioral_test.dart
//
// Batch M2a (plan Task 7): the repository behind one exercise animation: store hit, else ONE download, else a miss. A fake client
// (counts calls, scripted results, scripted latency that advances the injected `now`) sits over a REAL store on the scripted
// FakeBytesStore. Each case states its assertion; the letter in brackets is the Task 7 Step 4 mutation that case must turn red.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_client.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_repository.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_store.dart';

import '../helpers/dart_source_slice.dart';
import '../helpers/fake_bytes_store.dart';
import '../helpers/webp_fixture.dart';

/// A clock the tests move by hand (and the fake client moves by its scripted latency).
class _Clock {
  DateTime t = DateTime.utc(2026, 1, 1, 12);
  DateTime call() => t;
  void advance(Duration d) => t = t.add(d);
}

class _Plan {
  _Plan(this.result, {this.latency = Duration.zero, this.realDelay = Duration.zero});
  final MediaFetchResult result;

  /// Advances the injected clock when the call completes ("the client took 30 s").
  final Duration latency;

  /// Real (or fakeAsync-virtual) time the call waits, for the concurrency cases.
  final Duration realDelay;
}

MediaFetchResult _ok(Uint8List b) => MediaFetchResult(MediaFetchOutcome.fetched, bytes: b, status: 200);
MediaFetchResult _refused([int? status = 404]) => MediaFetchResult(MediaFetchOutcome.refused, status: status);
MediaFetchResult _unreachable() => const MediaFetchResult(MediaFetchOutcome.unreachable);
MediaFetchResult _unauth() => const MediaFetchResult(MediaFetchOutcome.unauthenticated);

class _FakeClient implements ExerciseMediaClient {
  _FakeClient(this.clock);
  final _Clock clock;
  final List<_Plan> script = <_Plan>[];
  final List<String> calls = <String>[];

  @override
  Future<MediaFetchResult> fetch(String objectName) async {
    calls.add(objectName);
    final plan = script.removeAt(0); // an unscripted extra call throws, and shows in `calls`
    if (plan.realDelay > Duration.zero) await Future<void>.delayed(plan.realDelay);
    clock.advance(plan.latency);
    return plan.result;
  }
}

/// Wraps the real store and counts `read` calls (for the kill-switch case).
class _CountingReadStore implements ExerciseMediaStore {
  _CountingReadStore(this.inner);
  final ExerciseMediaStore inner;
  int reads = 0;
  @override
  Future<void> get ready => inner.ready;
  @override
  bool has(String name) => inner.has(name);
  @override
  int get totalBytes => inner.totalBytes;
  @override
  Future<Uint8List?> read(String name) {
    reads++;
    return inner.read(name);
  }

  @override
  Future<void> put(String name, Uint8List bytes) => inner.put(name, bytes);
  @override
  Future<void> delete(String name) => inner.delete(name);
}

/// A store whose `read` always throws (the real store's `read` is total, so only a fake reaches `ensure`'s own guard); its
/// `put` and `delete` do nothing.
class _ThrowingReadStore implements ExerciseMediaStore {
  @override
  Future<void> get ready => Future<void>.value();
  @override
  bool has(String name) => false;
  @override
  int get totalBytes => 0;
  @override
  Future<Uint8List?> read(String name) async => throw StateError('store read failed');
  @override
  Future<void> put(String name, Uint8List bytes) async {}
  @override
  Future<void> delete(String name) async {}
}

/// A store whose `delete` always throws.
class _ThrowingDeleteStore extends _ThrowingReadStore {
  @override
  Future<Uint8List?> read(String name) async => null;
  @override
  Future<void> delete(String name) async => throw StateError('store delete failed');
}

class _Rig {
  _Rig({bool Function()? enabled, int alert = 100 * 1024 * 1024, ExerciseMediaStore? store, FakeBytesStore? fake})
      : fake = fake ?? FakeBytesStore() {
    client = _FakeClient(clock);
    realStore = ExerciseMediaStore(bytes: this.fake, capBytes: 10 * 1024 * 1024, now: clock.call);
    repo = ExerciseMediaRepository(
      client: client,
      store: store ?? realStore,
      now: clock.call,
      enabled: enabled,
      sessionBytesAlert: alert,
    );
  }
  final _Clock clock = _Clock();
  final FakeBytesStore fake;
  late final _FakeClient client;
  late final ExerciseMediaStore realStore;
  late final ExerciseMediaRepository repo;
}

ExerciseMedia _media(String slug) => ExerciseMedia(slug: slug, version: 1);
Uint8List _bytes(int n, [int seed = 1]) => webpBytes(n, seed);

T settle<T>(FakeAsync async, Future<T> f, {Duration by = const Duration(seconds: 5)}) {
  late T value;
  Object? error;
  StackTrace? stack;
  var done = false;
  f.then((v) {
    value = v;
    done = true;
  }, onError: (Object e, StackTrace s) {
    error = e;
    stack = s;
    done = true;
  });
  async.elapse(by);
  if (!done) throw StateError('the future did not complete within $by of virtual time');
  if (error != null) Error.throwWithStackTrace(error!, stack!);
  return value;
}

void main() {
  final events = <String>[];

  setUp(() {
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) => events.add('$opType|$message');
    ErrorTelemetry.debugOnRecordNonFatalForTests = (e, s, {required reason, extra}) {};
  });
  tearDown(() {
    ErrorTelemetry.debugOnLogEventForTests = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
  });

  group('hit and miss', () {
    test('[t] stored: zero client calls and the stored bytes; missing: one call, the bytes, store.has true afterwards', () async {
      final rig = _Rig();
      final stored = _bytes(400, 1);
      await rig.realStore.put(_media('hit').objectName, stored);
      expect(await rig.repo.ensure(_media('hit')), stored);
      expect(rig.client.calls, isEmpty);

      final fetched = _bytes(400, 2);
      rig.client.script.add(_Plan(_ok(fetched)));
      expect(await rig.repo.ensure(_media('miss')), fetched);
      expect(rig.client.calls, [_media('miss').objectName]);
      expect(rig.realStore.has(_media('miss').objectName), isTrue);
    });
  });

  group('concurrency', () {
    test('[a] two concurrent ensure of one name make ONE client call and both return equal bytes', () {
      fakeAsync((async) {
        final rig = _Rig();
        final b = _bytes(400, 3);
        rig.client.script.addAll([_Plan(_ok(b), realDelay: const Duration(milliseconds: 10)), _Plan(_ok(b))]);
        settle(async, rig.realStore.ready);
        final first = rig.repo.ensure(_media('x'));
        async.elapse(const Duration(milliseconds: 5)); // the second caller arrives while the first is in flight
        final second = rig.repo.ensure(_media('x'));
        final got = settle(async, Future.wait([first, second]));
        expect(rig.client.calls, hasLength(1));
        expect(got[0], b);
        expect(got[1], b);
      });
    });

    test('[ae] the second caller arrives DURING a slow store write (30 ms; the write ends at 60 ms): still ONE client call', () {
      fakeAsync((async) {
        final rig = _Rig();
        final b = _bytes(400, 4);
        rig.client.script.addAll([_Plan(_ok(b), realDelay: const Duration(milliseconds: 10)), _Plan(_ok(b))]);
        settle(async, rig.realStore.ready);
        rig.fake.armLatency({'write#1': const Duration(milliseconds: 50)}); // armed AFTER ready
        final first = rig.repo.ensure(_media('x')); // t=0: the client answers at 10 ms, the write ends at 60 ms
        async.elapse(const Duration(milliseconds: 30));
        final second = rig.repo.ensure(_media('x')); // t=30, mid-write
        final got = settle(async, Future.wait([first, second]));
        expect(rig.client.calls, hasLength(1));
        expect(got[0], b);
        expect(got[1], b);
      });
    });
  });

  group('refused and the on-demand back-off', () {
    test('[b] refused: null and nothing written; once the interval has passed a scripted success is returned and stored', () async {
      final rig = _Rig();
      rig.client.script.add(_Plan(_refused()));
      expect(await rig.repo.ensure(_media('x')), isNull);
      expect(rig.fake.writeAttempts, 0);
      expect(rig.realStore.has(_media('x').objectName), isFalse);

      rig.clock.advance(kOnDemandMinInterval + const Duration(seconds: 1));
      final b = _bytes(400, 5);
      rig.client.script.add(_Plan(_ok(b)));
      expect(await rig.repo.ensure(_media('x')), b);
      expect(rig.realStore.has(_media('x').objectName), isTrue);
    });

    for (final failing in <String, MediaFetchResult Function()>{'refused [ac]': _refused, 'unreachable [k]': _unreachable}.entries) {
      test('the back-off schedule for ${failing.key}: blocked at T+5 s and T+6 s, one call at T+11 s [f][j][l]', () async {
        final rig = _Rig();
        final b = _bytes(400, 6);
        // The client takes 30 s and fails at completion time T.
        rig.client.script.addAll([_Plan(failing.value(), latency: const Duration(seconds: 30)), _Plan(_ok(b))]);
        expect(await rig.repo.ensure(_media('x')), isNull);
        expect(rig.client.calls, hasLength(1));

        rig.clock.advance(const Duration(seconds: 5)); // T+5
        expect(await rig.repo.ensure(_media('x')), isNull);
        expect(rig.client.calls, hasLength(1), reason: 'blocked: zero client calls');

        rig.clock.advance(const Duration(seconds: 1)); // T+6: a second blocked attempt, still zero
        expect(await rig.repo.ensure(_media('x')), isNull);
        expect(rig.client.calls, hasLength(1));

        rig.clock.advance(const Duration(seconds: 5)); // T+11: the interval since the COMPLETION has passed
        expect(await rig.repo.ensure(_media('x')), b);
        expect(rig.client.calls, hasLength(2), reason: 'a blocked attempt must not have extended the interval');
      });
    }

    test('[m] a success arms nothing: after a success the blob is deleted and an ensure 1 s later calls the client at once', () async {
      final rig = _Rig();
      final b = _bytes(400, 7);
      rig.client.script.addAll([_Plan(_ok(b)), _Plan(_ok(b))]);
      expect(await rig.repo.ensure(_media('x')), b);
      await rig.realStore.delete(_media('x').objectName);
      rig.clock.advance(const Duration(seconds: 1));
      expect(await rig.repo.ensure(_media('x')), b);
      expect(rig.client.calls, hasLength(2));
    });

    test('[d] unauthenticated: null, and the next ensure calls the client again (no back-off recorded)', () async {
      final rig = _Rig();
      final b = _bytes(400, 8);
      rig.client.script.addAll([_Plan(_unauth()), _Plan(_ok(b))]);
      expect(await rig.repo.ensure(_media('x')), isNull);
      expect(await rig.repo.ensure(_media('x')), b);
      expect(rig.client.calls, hasLength(2));
    });
  });

  group('kill switch at the sink', () {
    test('[c][v] disabled: null with ZERO client calls and ZERO store reads, although the blob is pre-stored', () async {
      final rig = _Rig();
      final name = _media('x').objectName;
      await rig.realStore.put(name, _bytes(400, 9));
      final counting = _CountingReadStore(rig.realStore);
      final repo = ExerciseMediaRepository(client: rig.client, store: counting, now: rig.clock.call, enabled: () => false);
      expect(await repo.ensure(_media('x')), isNull);
      expect(rig.client.calls, isEmpty);
      expect(counting.reads, 0);
    });
  });

  group('unwritable store', () {
    test('[h][n][o] a store that throws on every write: bytes still returned, no put while the back-off is armed, a put again after it', () async {
      final rig = _Rig();
      await rig.realStore.ready;
      rig.fake.armThrowOnWrite(-1);
      final b = _bytes(400, 10);
      rig.client.script.addAll([_Plan(_ok(b)), _Plan(_ok(b)), _Plan(_ok(b))]);

      expect(await rig.repo.ensure(_media('x')), b, reason: '[n] a throwing write never makes ensure return null');
      final w = rig.fake.writeAttempts;
      expect(w, greaterThan(0));

      rig.clock.advance(const Duration(seconds: 1));
      expect(await rig.repo.ensure(_media('x')), b);
      expect(rig.client.calls, hasLength(2), reason: 'the store stayed empty, so the client is asked again');
      expect(rig.fake.writeAttempts, w, reason: '[h] no put while the back-off is armed');

      rig.clock.advance(kStoreUnwritableBackoff + const Duration(seconds: 1));
      expect(await rig.repo.ensure(_media('x')), b);
      expect(rig.fake.writeAttempts, greaterThan(w), reason: '[o] the back-off expires');
    });
  });

  group('totality', () {
    test('[g][i] a store whose read always throws: ensure returns the fetched bytes (one client call), and a second ensure fetches again', () async {
      final rig = _Rig(store: _ThrowingReadStore());
      final x = _bytes(400, 11);
      final y = _bytes(400, 12);
      rig.client.script.addAll([_Plan(_ok(x)), _Plan(_ok(y))]);
      expect(await rig.repo.ensure(_media('x')), x);
      expect(rig.client.calls, hasLength(1), reason: '[g] the failing read is a miss, not a failed ensure');
      expect(await rig.repo.ensure(_media('x')), y);
      expect(rig.client.calls, hasLength(2), reason: '[i] the in-flight entry was cleared');
    });

    test('[u] a telemetry hook that THROWS: both calls still return their bytes and no uncaught async error surfaces', () async {
      ErrorTelemetry.debugOnRecordNonFatalForTests = (e, s, {required reason, extra}) => throw StateError('hook failed');
      final rig = _Rig(store: _ThrowingReadStore());
      final x = _bytes(400, 13);
      final y = _bytes(400, 14);
      rig.client.script.addAll([_Plan(_ok(x)), _Plan(_ok(y))]);
      final uncaught = <Object>[];
      Uint8List? first;
      Uint8List? second;
      await (runZonedGuarded(() async {
            first = await rig.repo.ensure(_media('x'));
            second = await rig.repo.ensure(_media('x'));
            await Future<void>.delayed(Duration.zero); // let a late async error surface
          }, (e, s) => uncaught.add(e)) ??
          Future<void>.value());
      expect(first, x);
      expect(second, y);
      expect(uncaught, isEmpty);
    });
  });

  group('evict', () {
    test('[p][e][w] evict drops the blob and bans that name only: the next ensure makes zero client calls; an unrelated name works', () async {
      final rig = _Rig();
      final b = _bytes(400, 15);
      rig.client.script.add(_Plan(_ok(b)));
      expect(await rig.repo.ensure(_media('x')), b);
      expect(rig.realStore.has(_media('x').objectName), isTrue);

      await rig.repo.evict(_media('x'));
      expect(rig.realStore.has(_media('x').objectName), isFalse, reason: '[p]');
      expect(await rig.repo.ensure(_media('x')), isNull);
      expect(rig.client.calls, hasLength(1), reason: '[e] a banned name makes zero client calls');

      rig.client.script.add(_Plan(_ok(b)));
      expect(await rig.repo.ensure(_media('other')), b, reason: '[w] an unrelated name is not banned');
    });

    test('[x] evict is total: a store whose delete throws, evict returns normally and the name is still banned', () async {
      final rig = _Rig(store: _ThrowingDeleteStore());
      await rig.repo.evict(_media('x'));
      expect(await rig.repo.ensure(_media('x')), isNull);
      expect(rig.client.calls, isEmpty);
    });
  });

  group('session cost net', () {
    test('[q][r] four fetches of 1,000 bytes of four DISTINCT names: exactly ONE over-budget event, sent during the third, bytes=3000', () async {
      final rig = _Rig(alert: 2500);
      rig.client.script.addAll([for (var i = 0; i < 4; i++) _Plan(_ok(_bytes(1000, 20 + i)))]);
      for (var i = 0; i < 2; i++) {
        await rig.repo.ensure(_media('n$i'));
      }
      expect(events.where((e) => e.startsWith('exercise_media_session_over_budget')), isEmpty, reason: 'fewer than three fetches');
      await rig.repo.ensure(_media('n2'));
      final during = events.where((e) => e.startsWith('exercise_media_session_over_budget')).toList();
      expect(during, hasLength(1));
      expect(during.single, contains('bytes=3000'));
      await rig.repo.ensure(_media('n3'));
      expect(events.where((e) => e.startsWith('exercise_media_session_over_budget')), hasLength(1));
    });

    test('[s] on an unwritable store the first put throws and arms the back-off; three distinct fetches still send ONE event, bytes=3000', () async {
      final rig = _Rig(alert: 2500);
      await rig.realStore.ready;
      rig.fake.armThrowOnWrite(-1);
      rig.client.script.addAll([for (var i = 0; i < 3; i++) _Plan(_ok(_bytes(1000, 30 + i)))]);
      for (var i = 0; i < 3; i++) {
        await rig.repo.ensure(_media('n$i'));
      }
      final sent = events.where((e) => e.startsWith('exercise_media_session_over_budget')).toList();
      expect(sent, hasLength(1));
      expect(sent.single, contains('bytes=3000'));
    });
  });

  group('first-outcome breadcrumbs', () {
    test('[y] two refused results (status 400) of different names send exactly ONE first_refused event carrying status=400', () async {
      final rig = _Rig();
      rig.client.script.addAll([_Plan(_refused(400)), _Plan(_refused(400))]);
      await rig.repo.ensure(_media('a'));
      await rig.repo.ensure(_media('b'));
      final sent = events.where((e) => e.startsWith('exercise_media_first_refused')).toList();
      expect(sent, ['exercise_media_first_refused|status=400']);
    });

    test('[z] an unreachable result sends exactly one first_unreachable event (status=none)', () async {
      final rig = _Rig();
      rig.client.script.addAll([_Plan(_unreachable()), _Plan(_unreachable())]);
      await rig.repo.ensure(_media('a'));
      await rig.repo.ensure(_media('b'));
      expect(events.where((e) => e.startsWith('exercise_media_first_unreachable')), ['exercise_media_first_unreachable|status=none']);
    });

    test('[ab] a fetched and an unauthenticated result send neither event', () async {
      final rig = _Rig();
      rig.client.script.addAll([_Plan(_ok(_bytes(400, 40))), _Plan(_unauth())]);
      await rig.repo.ensure(_media('a'));
      await rig.repo.ensure(_media('b'));
      expect(events.where((e) => e.startsWith('exercise_media_first_')), isEmpty);
    });
  });

  group('platform switch', () {
    test('[aa] animationsPlatformEnabled returns isWeb ? webSwitch : nativeSwitch over all eight combinations', () {
      for (final isWeb in [false, true]) {
        for (final web in [false, true]) {
          for (final native in [false, true]) {
            expect(animationsPlatformEnabled(isWeb: isWeb, webSwitch: web, nativeSwitch: native), isWeb ? web : native,
                reason: 'isWeb=$isWeb web=$web native=$native');
          }
        }
      }
    });

    test('[ad][af] the provider wires the switches uncrossed and passes the kill switch to the repository (source pins, comments stripped)', () {
      final src = stripDartComments(File('lib/shared/providers/exercise_media_provider.dart').readAsStringSync());
      expect(src, contains('animationsPlatformEnabled('));
      expect(src, contains('isWeb: kIsWeb'));
      expect(src, contains('webSwitch: kWebAnimationsFetchEnabled'));
      expect(src, contains('nativeSwitch: kNativeAnimationsFetchEnabled'));
      expect(src, contains('enabled: () => PlateFlags.animationsEnabled'), reason: '[af] the repository default is () => true; an omitted argument would leave the sink guard dead');
    });

    test('both ship switches are true until a spike verdict says otherwise', () {
      expect(kWebAnimationsFetchEnabled, isTrue);
      expect(kNativeAnimationsFetchEnabled, isTrue);
    });
  });
}
