// test/contracts/exercise_media_store_behavioral_test.dart
//
// Batch M2a (plan Task 5): the exercise-animation cache. Every case states its assertion; the letter in brackets is the
// mutation (plan Task 5 Step 4) that case must turn red. The scripted fake's rules are written in
// test/helpers/fake_bytes_store.dart (ONE table); nothing here relies on a fake rule that is not in that table.
//
// Virtual time: the ordering-sensitive cases run under `fakeAsync` (no jitter). The helper [settle] elapses time and returns the
// future's value, or throws when it did not complete, so a hang reads as a failure and not as a timeout.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_store.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/dart_source_slice.dart';
import '../helpers/fake_bytes_store.dart';
import '../helpers/hive_test_setup.dart';
import '../helpers/webp_fixture.dart';

/// Advances by one second on every call, starting at 1000 ms.
class _StepClock {
  int _n = 0;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(1000 * ++_n);
}

DateTime Function() _fixed(int ms) => () => DateTime.fromMillisecondsSinceEpoch(ms);

Duration _ms(int n) => Duration(milliseconds: n);

/// Elapses [by] of virtual time and returns the value of [f]; throws if it did not complete (or rethrows its error).
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

ExerciseMediaStore _store(FakeBytesStore fake, {int cap = 100, DateTime Function()? now}) =>
    ExerciseMediaStore(bytes: fake, capBytes: cap, now: now ?? _StepClock().call);

Uint8List _blob(int n, [int seed = 1]) => webpBytes(n, seed);

/// A blob of the right length whose RIFF size field is wrong (the length check cannot catch it).
Uint8List _wrongRiffSize(int n) => webpBytes(n, 1)..[4] = (n - 8 - 1) & 0xff;

final List<String> _reported = <String>[];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _reported.clear();
    ErrorTelemetry.debugOnRecordNonFatalForTests = (error, stack, {required reason, extra}) => _reported.add(reason);
  });
  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
  });

  group('basics', () {
    test('before ready the store reports the empty state; put then read returns equal bytes; an unknown name reads null', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      expect(s.has('a'), isFalse);
      expect(s.totalBytes, 0);
      await s.ready;
      final b = _blob(40);
      await s.put('a', b);
      expect(s.has('a'), isTrue);
      expect(await s.read('a'), b);
      expect(await s.read('nope'), isNull);
    });

    test('[q] writing the same name twice leaves totalBytes at ONE copy and read returns the second payload', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.put('a', _blob(40, 1));
      final second = _blob(40, 2);
      await s.put('a', second);
      expect(s.totalBytes, 40);
      expect(await s.read('a'), second);
    });
  });

  group('eviction', () {
    test('[a] cap 100, a b c of 40 bytes: a is gone, b and c remain, total 80', () async {
      final s = _store(FakeBytesStore());
      await s.put('a', _blob(40, 1));
      await s.put('b', _blob(40, 2));
      await s.put('c', _blob(40, 3));
      expect(s.has('a'), isFalse);
      expect(s.has('b'), isTrue);
      expect(s.has('c'), isTrue);
      expect(s.totalBytes, 80);
    });

    test('[a] with read(a) before the third put, b is the victim (recency, not name order)', () async {
      final s = _store(FakeBytesStore());
      await s.put('a', _blob(40, 1));
      await s.put('b', _blob(40, 2));
      expect(await s.read('a'), isNotNull);
      await s.put('c', _blob(40, 3));
      expect(s.has('a'), isTrue);
      expect(s.has('b'), isFalse);
      expect(s.has('c'), isTrue);
    });

    test('[ak] under a fixed clock every shown is equal and the LOWER name goes first (puts in the order c, a, b)', () async {
      final s = _store(FakeBytesStore(), now: _fixed(5000));
      await s.put('c', _blob(40, 3));
      await s.put('a', _blob(40, 1));
      await s.put('b', _blob(40, 2));
      expect(s.has('a'), isFalse, reason: 'tie on shown: the lower name is the victim');
      expect(s.has('b'), isTrue);
      expect(s.has('c'), isTrue);
    });

    test('[p] a single 150-byte entry is kept; a following 12-byte put evicts it, never the new one', () async {
      final s = _store(FakeBytesStore());
      await s.put('big', _blob(150));
      expect(s.has('big'), isTrue);
      expect(s.totalBytes, 150);
      await s.put('small', _blob(12));
      expect(s.has('big'), isFalse);
      expect(s.has('small'), isTrue);
      expect(s.totalBytes, 12);
    });
  });

  group('concurrency', () {
    test('[d] three concurrent puts leave the PERSISTED meta holding a, b and c (the queue serialises them)', () {
      fakeAsync((async) {
        final fake = FakeBytesStore();
        final s = _store(fake, cap: 1000);
        settle(async, s.ready);
        // Armed AFTER ready so the load's own calls never consume an ordinal: the first blob write is 20 ms, the first meta
        // write 30 ms (slower than the blob write), every other call instant.
        fake.armLatency({'write#1': _ms(20), 'writeMeta#1': _ms(30)});
        settle(async, Future.wait([s.put('a', _blob(40, 1)), s.put('b', _blob(50, 2)), s.put('c', _blob(60, 3))]));
        final meta = jsonDecode(fake.peekMeta()!) as Map<String, dynamic>;
        expect(meta.keys.toSet(), {'a', 'b', 'c'});
        expect((meta['a'] as Map)['bytes'], 40);
        expect((meta['b'] as Map)['bytes'], 50);
        expect((meta['c'] as Map)['bytes'], 60);
        expect(s.totalBytes, 150);
      });
    });

    test('[e] on an EMPTY store the first put throws after ONE attempt and a second put is indexed (a failed task never breaks the chain)', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.ready;
      fake.armThrowOnWrite(1);
      await expectLater(s.put('a', _blob(40)), throwsA(isA<StateError>()));
      expect(fake.writeAttempts, 1);
      await s.put('b', _blob(40, 2));
      expect(s.has('b'), isTrue);
    });

    test('[u] a put made BEFORE ready waits for the load (the load keeps its t=0 snapshots, the put must land after it)', () {
      fakeAsync((async) {
        final fake = FakeBytesStore()..armLatency({'list#1': _ms(50), 'readMeta#1': _ms(50)});
        final s = _store(fake, cap: 1000);
        final r = s.ready; // t=0: the load issues list() and readMeta() together; both snapshot NOW (empty folder, no meta)
        final b = _blob(40);
        final p = s.put('a', b); // still t=0, before the load ends
        settle(async, Future.wait([r, p]), by: const Duration(seconds: 1));
        expect(s.has('a'), isTrue, reason: 'the late load must not replace the index and lose the put');
        expect(s.totalBytes, b.length);
        expect((jsonDecode(fake.peekMeta()!) as Map).containsKey('a'), isTrue);
      });
    });

    test('[f] a read racing a delete returns the bytes it holds, and the entry stays gone', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      final a = _blob(40, 1);
      await s.put('a', a);
      await s.put('b', _blob(40, 2));
      final gate = Completer<void>();
      fake.armLatency({'read#1': gate});
      final pending = s.read('a');
      await pumpEventQueue(); // the read has reached the fake and snapshotted the blob
      await s.delete('a');
      final totalAfterDelete = s.totalBytes;
      gate.complete();
      final got = await pending;
      expect(got, a, reason: 'non-null: a throw absorbed by the totality guard would return null');
      expect(s.has('a'), isFalse);
      expect(s.totalBytes, totalAfterDelete);
      expect(totalAfterDelete, 40);
    });
  });

  group('read failure modes', () {
    test('[g] bytes.read throws: read returns null, REPORTS it, and the entry stays', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.put('a', _blob(40));
      fake.armThrowOnRead(1);
      expect(await s.read('a'), isNull);
      expect(s.has('a'), isTrue, reason: 'a transient read error must not delete a good file');
      expect(_reported, contains('exercise_media_store_read'), reason: 'the inner guard reports; the outer one is silent');
    });

    test('[r] the blob vanished after load: read returns null, has becomes false, totalBytes drops by its length', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.put('a', _blob(40, 1));
      await s.put('b', _blob(30, 2));
      fake.removeBlob('a');
      expect(await s.read('a'), isNull);
      expect(s.has('a'), isFalse);
      expect(s.totalBytes, 30);
    });

    test('[ab][ap] a blob of the right length with a wrong RIFF size field: null, and the blob is ALREADY deleted when read returns', () {
      fakeAsync((async) {
        final fake = FakeBytesStore();
        final s = _store(fake, cap: 1000);
        settle(async, s.ready);
        settle(async, s.put('a', _blob(40)));
        fake.seedBlob('a', _wrongRiffSize(40)); // same length as the index, bad RIFF size
        fake.armLatency({'delete#1': _ms(20)}); // the fake applies a delete at COMPLETION: an un-awaited cleanup is 20 ms from done
        Uint8List? result = Uint8List(1);
        Uint8List? blobWhenReadReturned = Uint8List(1);
        var done = false;
        s.read('a').then((v) {
          result = v;
          blobWhenReadReturned = fake.peekBlob('a');
          done = true;
        });
        async.elapse(const Duration(seconds: 1));
        expect(done, isTrue);
        expect(result, isNull, reason: '[ab] the RIFF check is what rejects this body');
        expect(blobWhenReadReturned, isNull, reason: '[ap] the cleanup is awaited before read returns');
        expect(s.has('a'), isFalse);
      });
    });

    test('[b] a RIFF-consistent truncated blob whose length differs from the indexed length reads null', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.put('a', _blob(40, 1));
      await s.ready;
      fake.seedBlob('a', _blob(30, 1)); // replaced AFTER the load; a valid 30-byte file, the index still says 40
      expect(await s.read('a'), isNull);
    });
  });

  group('ready and repair', () {
    test('[l] a throwing list() leaves a working empty store (ready completes, put and read round-trip)', () async {
      final fake = FakeBytesStore()..armThrowOnList(1);
      final s = _store(fake, cap: 1000);
      await s.ready;
      final b = _blob(40);
      await s.put('a', b);
      expect(await s.read('a'), b);
    });

    test('[aq] a good meta pre-seeded in the fake is untouched when the load FAILED', () async {
      const good = '{"a":{"bytes":40,"shown":5}}';
      final fake = FakeBytesStore()
        ..seedMeta(good)
        ..armThrowOnList(1);
      final s = _store(fake, cap: 1000);
      await s.ready;
      expect(fake.peekMeta(), good);
      expect(fake.writeMetaAttempts, 0);
    });

    test('[ad] the persisted meta holds every entry with its bytes AND shown', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000); // _StepClock: the first put stamps 1000, the second 2000
      await s.put('a', _blob(40, 1));
      await s.put('b', _blob(50, 2));
      expect(jsonDecode(fake.peekMeta()!), {
        'a': {'bytes': 40, 'shown': 1000},
        'b': {'bytes': 50, 'shown': 2000},
      });
    });

    for (final variant in <String, String?>{'missing': null, 'unparsable': 'not json at all', 'empty list': '[]'}.entries) {
      test('[ae] a ${variant.key} meta rebuilds the index from list() without throwing', () async {
        final fake = FakeBytesStore()
          ..seedBlob('a', _blob(40, 1))
          ..seedBlob('b', _blob(40, 2));
        if (variant.value != null) fake.seedMeta(variant.value!);
        final s = _store(fake, cap: 1000, now: _fixed(1000));
        await s.ready;
        expect(s.has('a'), isTrue);
        expect(s.has('b'), isTrue);
        expect(s.totalBytes, 80);
      });
    }

    test('[k] a meta with one good and one wrong-shape entry is unparsable AS A WHOLE (both adopted, the tie goes to the lower name)', () async {
      final fake = FakeBytesStore()
        ..seedBlob('a', _blob(40, 1))
        ..seedBlob('b', _blob(40, 2))
        ..seedMeta('{"b":{"bytes":40,"shown":100},"a":{"bytes":"x","shown":1}}');
      final s = _store(fake, cap: 80, now: _fixed(1000));
      await s.ready;
      await s.put('c', _blob(40, 3));
      expect(s.has('a'), isFalse, reason: 'strict: both adopted at 1000, the lower name is evicted; lenient would evict b (shown 100)');
      expect(s.has('b'), isTrue);
      expect(s.has('c'), isTrue);
    });

    test('[af] a blob without an entry is adopted', () async {
      final fake = FakeBytesStore()
        ..seedBlob('a', _blob(40, 1))
        ..seedBlob('b', _blob(40, 2))
        ..seedMeta('{"a":{"bytes":40,"shown":5}}');
      final s = _store(fake, cap: 1000, now: _fixed(1000));
      await s.ready;
      expect(s.has('b'), isTrue);
      expect(s.totalBytes, 80);
    });

    test('[ag] an entry without a blob is dropped and totalBytes does not count it', () async {
      final fake = FakeBytesStore()
        ..seedBlob('a', _blob(40, 1))
        ..seedMeta('{"a":{"bytes":40,"shown":5},"b":{"bytes":40,"shown":6}}');
      final s = _store(fake, cap: 1000);
      await s.ready;
      expect(s.has('b'), isFalse);
      expect(s.totalBytes, 40);
    });

    test('[at] a meta entry whose recorded length differs from the listed length is dropped and the blob adopted with the listed one', () async {
      final fake = FakeBytesStore()
        ..seedBlob('a', _blob(80, 1))
        ..seedMeta('{"a":{"bytes":100,"shown":5}}');
      final s = _store(fake, cap: 1000);
      await s.ready;
      expect(s.has('a'), isTrue);
      expect(s.totalBytes, 80);
    });

    test('[z] a web adoption whose get returns null or throws is dropped AND the orphan blob is deleted', () async {
      for (final throwing in [false, true]) {
        final box = FakeLazyBox({'a': throwing ? _blob(40) : null});
        if (throwing) box.throwOnGet.add('a');
        final s = ExerciseMediaStore(bytes: HiveExerciseMediaBytesStore(() async => box), capBytes: 1000);
        await s.ready;
        expect(s.has('a'), isFalse, reason: 'throwing=$throwing');
        expect(s.totalBytes, 0);
        expect(box.deleteCount, 1, reason: 'throwing=$throwing: the orphan must be deleted');
      }
    });

    test('[bp11] the mirror of [z]: a VALID web blob with no meta entry (a lost meta) is adopted with its real length and NOT deleted', () async {
      final box = FakeLazyBox({'a': _blob(40, 1), 'b': _blob(25, 2)});
      final s = ExerciseMediaStore(bytes: HiveExerciseMediaBytesStore(() async => box), capBytes: 1000);
      await s.ready;
      expect(s.has('a'), isTrue);
      expect(s.has('b'), isTrue);
      expect(s.totalBytes, 65, reason: 'the web listing carries no lengths, so adoption must read each blob to measure it');
      expect(box.deleteCount, 0, reason: 'an adopted blob is kept');
      expect(await s.read('a'), isNotNull);
    });
  });

  group('write and meta failures, total deletes', () {
    test('[j][o] a write that throws once: the victim is deleted BEFORE the second write, put succeeds', () async {
      final fake = FakeBytesStore();
      final s = _store(fake);
      await s.put('v', _blob(40, 1));
      fake.armThrowOnWrite(1); // armed AFTER the victim is seeded: throws on the next write only
      fake.log.clear();
      await s.put('x', _blob(40, 2));
      expect(s.has('x'), isTrue);
      expect(s.has('v'), isFalse);
      expect(fake.peekBlob('x'), isNotNull);
      final firstWrite = fake.log.indexOf('write:x');
      final del = fake.log.indexOf('delete:v');
      final secondWrite = fake.log.lastIndexOf('write:x');
      expect(firstWrite, greaterThanOrEqualTo(0));
      expect(del, greaterThan(firstWrite));
      expect(secondWrite, greaterThan(del), reason: '[o] the victim goes BEFORE the retry');
    });

    test('[j] a fake that always throws, with one victim: put rethrows after exactly 2 write attempts', () async {
      final fake = FakeBytesStore();
      final s = _store(fake);
      await s.put('v', _blob(40, 1));
      fake.armThrowOnWrite(-1);
      final before = fake.writeAttempts;
      await expectLater(s.put('x', _blob(40, 2)), throwsA(isA<StateError>()));
      expect(fake.writeAttempts - before, 2);
    });

    test('[bp12] a write that keeps failing, with THREE other entries: ONE victim is evicted and the put gives up after 2 attempts', () async {
      final fake = FakeBytesStore();
      final s = _store(fake);
      await s.put('v1', _blob(20, 1));
      await s.put('v2', _blob(20, 2));
      await s.put('v3', _blob(20, 3));
      fake.armThrowOnWrite(-1);
      final before = fake.writeAttempts;
      await expectLater(s.put('x', _blob(20, 4)), throwsA(isA<StateError>()));
      expect(fake.writeAttempts - before, 2, reason: 'retry ONCE, not once per remaining victim');
      expect(fake.blobNames, {'v2', 'v3'}, reason: 'only the least recently shown (v1) was sacrificed; the cache is not emptied');
      expect(s.has('v1'), isFalse);
      expect(s.has('v2') && s.has('v3'), isTrue);
    });

    test('[ah] with no victim (the only entry is the name being written) the error is rethrown after exactly 1 attempt', () async {
      final fake = FakeBytesStore();
      final s = _store(fake);
      await s.put('a', _blob(40, 1));
      fake.armThrowOnWrite(-1);
      final before = fake.writeAttempts;
      await expectLater(s.put('a', _blob(40, 2)), throwsA(isA<StateError>()));
      expect(fake.writeAttempts - before, 1);
    });

    test('[ar] a writeMeta failure is NOT a put failure: put completes, has is true, the blob is stored', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.ready;
      fake.armThrowOnWriteMeta(1);
      final b = _blob(40);
      await s.put('a', b);
      expect(s.has('a'), isTrue);
      expect(fake.peekBlob('a'), b);
      expect(_reported, contains('exercise_media_store_write_meta'));
    });

    test('[al] delete is total: a throwing bytes.delete returns normally and the entry is gone', () async {
      final fake = FakeBytesStore();
      final s = _store(fake, cap: 1000);
      await s.put('a', _blob(40));
      fake.armThrowOnDelete(-1);
      await s.delete('a');
      expect(s.has('a'), isFalse);
      expect(s.totalBytes, 0);
    });

    test('delete of a missing name does not throw', () async {
      final s = _store(FakeBytesStore());
      await s.delete('nope');
      expect(s.has('nope'), isFalse);
    });

    test('[am] a put that must evict a victim whose delete throws still succeeds and indexes the new entry', () async {
      final fake = FakeBytesStore();
      final s = _store(fake);
      await s.put('a', _blob(40, 1));
      await s.put('b', _blob(40, 2));
      fake.armThrowOnDelete(-1);
      await s.put('c', _blob(40, 3));
      expect(s.has('c'), isTrue);
      expect(s.has('a'), isFalse, reason: 'the victim left the index although its blob delete failed');
    });
  });

  group('sign-out survival [c]', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });
    tearDown(() async => tearDownHiveForTests(tempDir));

    test('the index survives the REAL clearAllData() on the file store and on a web-style LazyBox (eviction order intact)', () async {
      final folder = await Directory.systemTemp.createTemp('media_signout');
      addTearDown(() {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      });
      // The REAL web box name, so a future wipe that lists it by name (rather than a differently named test box) would show here.
      final lazy = await Hive.openLazyBox(HiveService.mediaBlobStoreName);
      final backends = <String, ExerciseMediaBytesStore>{
        'file': FileExerciseMediaBytesStore(() async => folder),
        'web': HiveExerciseMediaBytesStore(() async => lazy),
      };

      // The same history on each backend: cap 200; a, b, c of 40 bytes under a clock that advances one second per call, then
      // read('a') (the ALPHABETICALLY FIRST entry, so recency differs from name order) and a fourth put d to persist the bump.
      for (final bytes in backends.values) {
        final s = ExerciseMediaStore(bytes: bytes, capBytes: 200, now: _StepClock().call);
        await s.ready;
        await s.put('a', _blob(40, 1));
        await s.put('b', _blob(40, 2));
        await s.put('c', _blob(40, 3));
        expect(await s.read('a'), isNotNull);
        await s.put('d', _blob(40, 4)); // shown: a 4000, b 2000, c 3000, d 5000
      }

      await HiveService.instance.configBox.put('zz_media_sentinel', 1);
      final result = await UserRepository.instance.clearAllData();
      expect(result.isClean, isTrue, reason: '$result');
      expect(HiveService.instance.configBox.get('zz_media_sentinel'), isNull, reason: 'the wipe really ran');

      for (final e in backends.entries) {
        // A FIXED now so an adoption tie goes to the lower name and the outcome cannot depend on the filesystem's listing order.
        final s = ExerciseMediaStore(bytes: e.value, capBytes: 200, now: _fixed(9000));
        await s.ready;
        for (final n in ['a', 'b', 'c', 'd']) {
          expect(s.has(n), isTrue, reason: '${e.key}: $n');
        }
        expect(s.totalBytes, 160, reason: e.key);
        await s.put('e', _blob(80, 5)); // 240 > 200
        expect(s.has('b'), isFalse, reason: '${e.key}: b is the least recently shown');
        expect(s.has('a'), isTrue, reason: '${e.key}: a was read after b was put; a lost meta would evict a (the lower name)');
      }
    });
  });

  group('file store', () {
    late Directory base;
    late Directory dir;

    setUp(() {
      base = Directory.systemTemp.createTempSync('media_file_store');
      dir = Directory('${base.path}/store')..createSync();
    });
    tearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });

    test('[y] a folder that does not exist yet is created on the first list() and on the first write', () async {
      final d1 = Directory('${base.path}/fresh1');
      expect(await FileExerciseMediaBytesStore(() async => d1).list(), isEmpty);
      expect(d1.existsSync(), isTrue);

      final d2 = Directory('${base.path}/fresh2/nested');
      await FileExerciseMediaBytesStore(() async => d2).write('a', _blob(40));
      expect(File('${d2.path}/a').existsSync(), isTrue);
    });

    test('[bp13] an index file that is not valid UTF-8 is treated as an unreadable index: the blobs are re-adopted, none is lost', () async {
      final fs = FileExerciseMediaBytesStore(() async => dir);
      await fs.write('a', _blob(40, 1));
      await fs.write('b', _blob(25, 2));
      File('${dir.path}/_meta.json').writeAsBytesSync(<int>[0xff, 0xfe, 0x7b, 0x80, 0x00]); // not UTF-8
      expect(await fs.readMeta(), isA<String>(), reason: 'reading a corrupt index must not throw');

      final s = ExerciseMediaStore(bytes: fs, capBytes: 1000, now: _fixed(5000));
      await s.ready;
      expect(s.has('a'), isTrue);
      expect(s.has('b'), isTrue);
      expect(s.totalBytes, 65);
    });

    test('round trip, delete of a missing name, and [ai] read of a missing name returns null', () async {
      final fs = FileExerciseMediaBytesStore(() async => dir);
      final b = _blob(40);
      await fs.write('a', b);
      expect(await fs.read('a'), b);
      expect((await fs.list())['a'], 40);
      await fs.writeMeta('{"x":1}');
      expect(await fs.readMeta(), '{"x":1}');
      expect((await fs.list()).containsKey('_meta.json'), isFalse, reason: 'the meta is never listed as a blob');
      await fs.delete('a');
      expect(await fs.read('a'), isNull);
      await fs.delete('a'); // missing: no throw
      expect(await fs.read('never-written'), isNull);
    });

    test('[n] a name containing /, \\ or .. is rejected before any file is touched', () async {
      final fs = FileExerciseMediaBytesStore(() async => dir);
      for (final bad in ['../escape.webp', 'a/b.webp', r'a\b.webp', 'x..y.webp']) {
        expect(() => fs.write(bad, _blob(40)), throwsArgumentError, reason: bad);
        expect(() => fs.read(bad), throwsArgumentError, reason: bad);
        expect(() => fs.delete(bad), throwsArgumentError, reason: bad);
      }
      expect(File('${base.path}/escape.webp').existsSync(), isFalse);
      expect(dir.listSync(), isEmpty);
    });

    test('[x] a stale x.7.tmp is deleted at the first list() and never appears in the index; list() skips *.tmp', () async {
      File('${dir.path}/x.7.tmp').writeAsBytesSync([1, 2, 3]);
      File('${dir.path}/keep.webp').writeAsBytesSync(_blob(40));
      final fs = FileExerciseMediaBytesStore(() async => dir);
      final first = await fs.list();
      expect(first.keys, ['keep.webp']);
      expect(File('${dir.path}/x.7.tmp').existsSync(), isFalse, reason: 'the first list() deletes stale temp files');
      File('${dir.path}/y.9.tmp').writeAsBytesSync([9]);
      expect((await fs.list()).keys, ['keep.webp'], reason: 'list() skips *.tmp');
    });

    test('[h] a failed write (the rename fails because the target is a directory) leaves no *.tmp behind', () async {
      Directory('${dir.path}/a').createSync();
      final fs = FileExerciseMediaBytesStore(() async => dir);
      await expectLater(fs.write('a', _blob(40)), throwsA(isA<FileSystemException>()));
      final temps = dir.listSync().where((e) => e.path.endsWith('.tmp')).toList();
      expect(temps, isEmpty);
    });

    test('[i] two concurrent writes of the SAME name use two distinct temp names', () async {
      final fs = FileExerciseMediaBytesStore(() async => dir);
      final p1 = _blob(40, 1);
      final p2 = _blob(40, 2);
      await Future.wait([fs.write('a', p1), fs.write('a', p2)]);
      expect(fs.debugTempNames.toSet().length, 2);
      expect(await fs.read('a'), anyOf(equals(p1), equals(p2)));
    });
  });

  group('web store', () {
    test('a real Hive LazyBox in a temp directory stores a Uint8List and reads back a Uint8List (the TYPE only)', () async {
      final tmp = await Directory.systemTemp.createTemp('media_hive_vm');
      addTearDown(() async {
        await Hive.close();
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      Hive.init(tmp.path);
      final box = await Hive.openLazyBox('media_vm_test');
      final s = HiveExerciseMediaBytesStore(() async => box);
      final b = _blob(40);
      await s.write('a', b);
      final r = await s.read('a');
      expect(r, isA<Uint8List>());
      expect(r, b);
      expect((await s.list()).keys, ['a']);
    });

    test('[m] a LazyBox that hands back a List<int> yields an equal Uint8List; a String yields null', () async {
      final b = _blob(40);
      final box = FakeLazyBox({'a': b.toList(), 'b': 'not bytes'});
      final s = HiveExerciseMediaBytesStore(() async => box);
      final r = await s.read('a');
      expect(r, isA<Uint8List>());
      expect(r, b);
      expect(await s.read('b'), isNull);
    });

    test('[aj] a consistent meta costs ZERO blob gets on first use', () async {
      final a = _blob(40, 1);
      final b = _blob(50, 2);
      final box = FakeLazyBox({
        'a': a,
        'b': b,
        '_meta': jsonEncode({
          'a': {'bytes': 40, 'shown': 5},
          'b': {'bytes': 50, 'shown': 6},
        }),
      });
      final s = ExerciseMediaStore(bytes: HiveExerciseMediaBytesStore(() async => box), capBytes: 1000);
      await s.ready;
      expect(s.has('a'), isTrue);
      expect(s.has('b'), isTrue);
      expect(s.totalBytes, 90);
      expect(box.blobGets, 0);
    });

    test('[as] an open that yields null still serves the session: put/read round-trip and persistent == false', () async {
      final bytes = HiveExerciseMediaBytesStore(() async => null);
      final s = ExerciseMediaStore(bytes: bytes, capBytes: 1000);
      await s.ready;
      final b = _blob(40);
      await s.put('a', b);
      expect(await s.read('a'), b);
      expect(bytes.persistent, isFalse);
    });

    test('[aa] write copies: a 40-byte view into a bigger buffer reaches the box as an exact 40-byte buffer', () async {
      final buf = Uint8List(100);
      final view = Uint8List.view(buf.buffer, 8, 40);
      final box = FakeLazyBox();
      await HiveExerciseMediaBytesStore(() async => box).write('a', view);
      final stored = box.putValues.single! as Uint8List;
      expect(stored.length, 40);
      expect(stored.buffer.lengthInBytes, 40);
    });
  });

  group('HiveService.openMediaBlobBox', () {
    test('[w] isWeb false returns null without calling the opener', () async {
      var opens = 0;
      final r = await HiveService.openMediaBlobBox(isWeb: false, opener: (_) async {
        opens++;
        return FakeLazyBox();
      });
      expect(r, isNull);
      expect(opens, 0);
    });

    test('[v] an opener that never completes returns null within the timeout and the deleter is NOT called', () {
      fakeAsync((async) {
        var deletes = 0;
        final r = settle(
          async,
          HiveService.openMediaBlobBox(
            isWeb: true,
            opener: (_) => Completer<LazyBox>().future,
            deleter: (_) async => deletes++,
            timeout: const Duration(seconds: 3),
          ),
          by: const Duration(seconds: 4),
        );
        expect(r, isNull);
        expect(deletes, 0, reason: 'a timeout is not an open ERROR: no delete');
      });
    });

    test('[t] an opener that throws on its first call and succeeds on its second returns the box; the deleter ran exactly once', () async {
      var opens = 0;
      var deletes = 0;
      final box = FakeLazyBox();
      final r = await HiveService.openMediaBlobBox(
        isWeb: true,
        opener: (_) async {
          opens++;
          if (opens == 1) throw StateError('corrupt box');
          return box;
        },
        deleter: (_) async => deletes++,
      );
      expect(r, same(box));
      expect(deletes, 1);
      expect(opens, 2);
    });

    test('[t] an opener that always throws returns null after exactly one deleter call and two open attempts, and never throws', () async {
      var opens = 0;
      var deletes = 0;
      final r = await HiveService.openMediaBlobBox(
        isWeb: true,
        opener: (_) async {
          opens++;
          throw StateError('always');
        },
        deleter: (_) async => deletes++,
      );
      expect(r, isNull);
      expect(deletes, 1);
      expect(opens, 2);
    });

    test('[an] a deleter that throws returns null and never throws', () async {
      final r = await HiveService.openMediaBlobBox(
        isWeb: true,
        opener: (_) async => throw StateError('corrupt'),
        deleter: (_) async => throw StateError('cannot delete'),
      );
      expect(r, isNull);
    });

    test('[ao] a deleter that never completes returns null within the timeout', () {
      fakeAsync((async) {
        final r = settle(
          async,
          HiveService.openMediaBlobBox(
            isWeb: true,
            opener: (_) async => throw StateError('corrupt'),
            deleter: (_) => Completer<void>().future,
            timeout: const Duration(seconds: 3),
          ),
          by: const Duration(seconds: 4),
        );
        expect(r, isNull);
      });
    });
  });

  group('source pins', () {
    test('[s] boot is never delayed: openMediaBlobBox( is not called inside HiveService.init()', () {
      final src = stripDartComments(File('lib/core/services/hive_service.dart').readAsStringSync());
      final initBody = functionBody(src, 'Future<void> init(');
      expect(initBody, contains('Hive.initFlutter'), reason: 'the slice must be init(), not another function');
      expect(initBody.contains('openMediaBlobBox('), isFalse);
      expect(src.contains('static Future<LazyBox?> openMediaBlobBox('), isTrue, reason: 'the definition exists (non-vacuous)');
    });

    test('[bp14] the web media box is in NO wipe list: its name is used exactly three times in hive_service.dart (the definition, the open, the remove) and never in user_repository.dart', () {
      final hive = stripDartComments(File('lib/core/services/hive_service.dart').readAsStringSync());
      final users = stripDartComments(File('lib/shared/repositories/user_repository.dart').readAsStringSync());
      expect(RegExp(r'\bmediaBlobStoreName\b').allMatches(hive).length, 3,
          reason: 'a fourth use would be a list the name was added to: read it before accepting the number');
      expect("exerciseMediaBlobs".allMatches(hive).length, 1, reason: 'the literal is spelled once, in the definition');
      for (final needle in ['mediaBlobStoreName', 'exerciseMediaBlobs', 'openMediaBlobBox', 'exercise_media']) {
        expect(users.contains(needle), isFalse, reason: 'clearAllData must not know the media store: $needle');
      }
      expect(users.contains('clearAllData'), isTrue, reason: 'non-vacuous: the file scanned is the one that holds the wipe');
    });
  });
}
