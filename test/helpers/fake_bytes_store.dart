// test/helpers/fake_bytes_store.dart
//
// A COMPLETE scripted fake of ExerciseMediaBytesStore (Batch M2a, Task 5), plus a minimal fake LazyBox for the web store.
// No test may rely on a fake rule that is not written here (round 9's P1 was a case that depended on when a delete takes
// effect). The rules, per operation:
//
//   | Operation        | Snapshot taken                   | Latency key     | Effect, applied                      | Throw switch                | Log entry (at the CALL) |
//   | read(name)       | the stored blob, at the call     | read#n          | none                                 | armThrowOnRead(k)           | read:<name>             |
//   | write(name, b)   | none                             | write#n         | stores the bytes AFTER the latency   | armThrowOnWrite(k)          | write:<name>            |
//   | delete(name)     | none                             | delete#n        | removes the blob AFTER the latency   | armThrowOnDelete(k)         | delete:<name>           |
//   | list()           | the name -> length map, at call  | list#n          | none                                 | armThrowOnList(k)           | list                    |
//   | readMeta()       | the meta, at the call            | readMeta#n      | none                                 | none                        | readMeta                |
//   | writeMeta(json)  | none                             | writeMeta#n     | stores the meta AFTER the latency    | armThrowOnWriteMeta(k)      | writeMeta               |
//
// A throw switch throws AFTER its latency and has NO effect; `k` is the number of the next calls that throw (-1 = always),
// counted from the arming, so a test arms AFTER seeding. `armLatency(map)` takes keys `<op>#n` mapped to a Duration or a
// test-supplied Completer gate (default Duration.zero, which waits one microtask only, so it also runs under `fakeAsync`
// without elapsing time); the ordinal `n` counts only the calls of that operation made AFTER `armLatency`.
//
// Direct, synchronous, un-logged and un-counted helpers: seedBlob (also the way to REPLACE a blob), removeBlob, seedMeta, and the
// read-only peekBlob / peekMeta for assertions (inside fakeAsync an assertion uses these, never `await fake.readMeta()`).
// Counters: blob reads, and write, delete and writeMeta ATTEMPTS (a throwing call counts).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:hive_flutter/hive_flutter.dart' show LazyBox;
import 'package:icanbefitter/core/services/exercise_media/exercise_media_store.dart';

class FakeBytesStore implements ExerciseMediaBytesStore {
  final Map<String, Uint8List> _blobs = <String, Uint8List>{};
  String? _meta;

  /// Every call, in order, written at the CALL.
  final List<String> log = <String>[];

  /// Blob reads, and write / delete / writeMeta ATTEMPTS (a throwing call counts).
  int blobReads = 0;
  int writeAttempts = 0;
  int deleteAttempts = 0;
  int writeMetaAttempts = 0;

  Map<String, Object> _latency = <String, Object>{};
  final Map<String, int> _ordinal = <String, int>{};
  final Map<String, int> _throwLeft = <String, int>{};

  // ---- scripting ----------------------------------------------------------------------------------------------------------

  /// Keys `<op>#n` -> a [Duration] or a [Completer] gate. Resets the ordinals: `n` counts calls made AFTER this call.
  void armLatency(Map<String, Object> latency) {
    _latency = Map<String, Object>.of(latency);
    _ordinal.clear();
  }

  void armThrowOnRead(int k) => _throwLeft['read'] = k;
  void armThrowOnWrite(int k) => _throwLeft['write'] = k;
  void armThrowOnDelete(int k) => _throwLeft['delete'] = k;
  void armThrowOnList(int k) => _throwLeft['list'] = k;
  void armThrowOnWriteMeta(int k) => _throwLeft['writeMeta'] = k;

  // ---- direct helpers -------------------------------------------------------------------------------------------------------

  void seedBlob(String name, Uint8List bytes) => _blobs[name] = bytes;
  void removeBlob(String name) => _blobs.remove(name);
  void seedMeta(String json) => _meta = json;
  Uint8List? peekBlob(String name) => _blobs[name];
  String? peekMeta() => _meta;
  Set<String> get blobNames => _blobs.keys.toSet();

  // ---- internals ----------------------------------------------------------------------------------------------------------------

  /// Takes the next ordinal of [op] and whether this call is armed to throw. Called at the CALL.
  ({String key, bool shouldThrow}) _begin(String op) {
    final n = (_ordinal[op] ?? 0) + 1;
    _ordinal[op] = n;
    var shouldThrow = false;
    final left = _throwLeft[op];
    if (left != null && left != 0) {
      shouldThrow = true;
      if (left > 0) _throwLeft[op] = left - 1;
    }
    return (key: '$op#$n', shouldThrow: shouldThrow);
  }

  Future<void> _wait(String key) async {
    final l = _latency[key];
    if (l is Completer) {
      await l.future;
    } else if (l is Duration && l > Duration.zero) {
      await Future<void>.delayed(l);
    } else {
      await Future<void>.value(); // one microtask
    }
  }

  // ---- ExerciseMediaBytesStore ------------------------------------------------------------------------------------------------

  @override
  Future<Uint8List?> read(String name) async {
    log.add('read:$name');
    blobReads++;
    final snapshot = _blobs[name];
    final b = _begin('read');
    await _wait(b.key);
    if (b.shouldThrow) throw StateError('FakeBytesStore: scripted read failure');
    return snapshot;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    log.add('write:$name');
    writeAttempts++;
    final b = _begin('write');
    await _wait(b.key);
    if (b.shouldThrow) throw StateError('FakeBytesStore: scripted write failure');
    _blobs[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> delete(String name) async {
    log.add('delete:$name');
    deleteAttempts++;
    final b = _begin('delete');
    await _wait(b.key);
    if (b.shouldThrow) throw StateError('FakeBytesStore: scripted delete failure');
    _blobs.remove(name);
  }

  @override
  Future<Map<String, int?>> list() async {
    log.add('list');
    final snapshot = <String, int?>{for (final e in _blobs.entries) e.key: e.value.length};
    final b = _begin('list');
    await _wait(b.key);
    if (b.shouldThrow) throw StateError('FakeBytesStore: scripted list failure');
    return snapshot;
  }

  @override
  Future<String?> readMeta() async {
    log.add('readMeta');
    final snapshot = _meta;
    final b = _begin('readMeta');
    await _wait(b.key);
    return snapshot;
  }

  @override
  Future<void> writeMeta(String json) async {
    log.add('writeMeta');
    writeMetaAttempts++;
    final b = _begin('writeMeta');
    await _wait(b.key);
    if (b.shouldThrow) throw StateError('FakeBytesStore: scripted writeMeta failure');
    _meta = json;
  }
}

/// A minimal LazyBox for the web store: it implements only what `HiveExerciseMediaBytesStore` calls (`get`, `put`, `delete`,
/// `keys`) and counts them. `noSuchMethod` makes any other call fail loudly.
class FakeLazyBox implements LazyBox<dynamic> {
  FakeLazyBox([Map<String, Object?>? initial]) : data = <String, Object?>{...?initial};

  /// key -> stored value (any type, so a test can hand back a `List<int>` or a `String`).
  final Map<String, Object?> data;

  /// Every value passed to `put`, in order.
  final List<Object?> putValues = <Object?>[];

  /// `get` calls for keys other than the meta key `_meta`.
  int blobGets = 0;
  int deleteCount = 0;

  /// Keys whose `get` throws.
  final Set<String> throwOnGet = <String>{};

  @override
  Future<dynamic> get(dynamic key, {dynamic defaultValue}) async {
    if ('$key' != '_meta') blobGets++;
    if (throwOnGet.contains('$key')) throw StateError('FakeLazyBox: scripted get failure for $key');
    return data.containsKey('$key') ? data['$key'] : defaultValue;
  }

  @override
  Future<void> put(dynamic key, dynamic value) async {
    putValues.add(value);
    data['$key'] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    deleteCount++;
    data.remove('$key');
  }

  @override
  Iterable<dynamic> get keys => data.keys.toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('FakeLazyBox.${invocation.memberName}');
}
