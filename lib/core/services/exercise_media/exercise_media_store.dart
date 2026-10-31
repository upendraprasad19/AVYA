// lib/core/services/exercise_media/exercise_media_store.dart
//
// The on-device cache of exercise animations (Batch M2a, Task 5): files on native, a Hive LazyBox on web, ONE index of its own,
// a size cap with recency eviction.
//
// LAYERS
//   ExerciseMediaBytesStore            the raw bytes + one meta blob. Two implementations below (File, Hive) and a scripted fake
//                                      in test/helpers/fake_bytes_store.dart.
//   ExerciseMediaStore                 the index `{name: {bytes, shown}}`, the serial queue, the cap and eviction, the repair.
//
// WHY THE INDEX LIVES IN THE BYTE STORE'S OWN META (not in configBox): it shares the blobs' lifecycle. `clearAllData()` clears
// configBox and the user boxes but never this store, so an index kept in configBox would be wiped while the files stay and the
// cap would stop seeing them (a sign-out survival test pins this, mutation c).
//
// RULES THAT HOLD THE DESIGN TOGETHER (each is pinned by a lettered case in the behavioural test):
//   - ONE serial queue (`_serial`) for every change: put, delete, eviction, the cleanup after a bad read. Inside a queued task
//     and inside `_load` only RAW `_bytes.*` calls and private helpers are used, never `_serial`, `read`, `put`, `delete` or
//     `ready` (a task waiting on one queued behind itself deadlocks; `ready` waiting on itself never completes).
//   - Every async method does `await ready` FIRST, before enqueuing, never inside a queued task.
//   - `_load` is NOT queued: it is one raw sequence, and because every other method awaits `ready` first nothing else is queued
//     or running while it does. It catches everything; a failed load starts an empty index, writes NO meta, and is never sticky.
//   - `read` and `delete` are total (G15); `put` is the only rethrower (the repository handles it). A `writeMeta` failure is not
//     a `put` failure: the blob is stored and indexed, the next change persists the meta, a later launch's repair adopts what
//     the meta missed.
//   - Telemetry on these paths is never awaited: `unawaited(ErrorTelemetry.recordNonFatal(...).catchError((_) {}))`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_flutter/hive_flutter.dart' show LazyBox;

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_webp.dart';

/// The raw bytes of the cache plus ONE meta blob. A name is an object name such as `0103-barbell-standing-ab-rollout_v1.webp`.
abstract class ExerciseMediaBytesStore {
  Future<Uint8List?> read(String name);
  Future<void> write(String name, Uint8List bytes);
  Future<void> delete(String name);

  /// name -> byte length, or `null` when the backend cannot know the length without reading the blob. It never returns the meta
  /// entry and never a `*.tmp`.
  Future<Map<String, int?>> list();
  Future<String?> readMeta();
  Future<void> writeMeta(String json);
}

// ---------------------------------------------------------------------------------------------------------------------------
// Native: files in a folder.
// ---------------------------------------------------------------------------------------------------------------------------

class FileExerciseMediaBytesStore implements ExerciseMediaBytesStore {
  FileExerciseMediaBytesStore(this._dir);

  final Future<Directory> Function() _dir;
  static const String _metaName = '_meta.json';

  Future<Directory>? _folderFuture;
  int _tempCounter = 0;
  bool _swept = false;

  /// Every temp name used, in order (tests assert two concurrent writes of one name never share one).
  @visibleForTesting
  final List<String> debugTempNames = <String>[];

  /// The folder, created on first use (the provider hands over a folder that does not exist yet on a fresh install).
  Future<Directory> _folder() => _folderFuture ??= _resolveFolder();

  Future<Directory> _resolveFolder() async {
    try {
      final d = await Future<Directory>.sync(_dir);
      await d.create(recursive: true);
      return d;
    } catch (_) {
      // A failed resolution must not stick: the next call tries again.
      _folderFuture = null;
      rethrow;
    }
  }

  static void _checkName(String name) {
    if (name.isEmpty || name.contains('/') || name.contains(r'\') || name.contains('..')) {
      throw ArgumentError.value(name, 'name', 'a media file name has no path separator and no ".."');
    }
  }

  @override
  Future<Uint8List?> read(String name) async {
    _checkName(name);
    final d = await _folder();
    final f = File('${d.path}/$name');
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    _checkName(name);
    await _writeFile(name, bytes);
  }

  Future<void> _writeFile(String name, List<int> bytes) async {
    final d = await _folder();
    final tempName = '$name.${++_tempCounter}.tmp';
    debugTempNames.add(tempName);
    final temp = File('${d.path}/$tempName');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename('${d.path}/$name');
    } catch (_) {
      // A failed write (including a failed rename) leaves nothing behind.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> delete(String name) async {
    _checkName(name);
    final d = await _folder();
    final f = File('${d.path}/$name');
    if (await f.exists()) await f.delete();
  }

  @override
  Future<Map<String, int?>> list() async {
    final d = await _folder();
    final out = <String, int?>{};
    final stale = <File>[];
    await for (final e in d.list(followLinks: false)) {
      if (e is! File) continue;
      final n = e.uri.pathSegments.last;
      if (n.endsWith('.tmp')) {
        stale.add(e);
        continue;
      }
      if (n == _metaName) continue;
      try {
        out[n] = await e.length();
      } catch (_) {
        // vanished between listing and stat: not a blob any more
      }
    }
    if (!_swept) {
      _swept = true;
      for (final f in stale) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    return out;
  }

  @override
  Future<String?> readMeta() async {
    final d = await _folder();
    final f = File('${d.path}/$_metaName');
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> writeMeta(String json) => _writeFile(_metaName, utf8.encode(json));
}

// ---------------------------------------------------------------------------------------------------------------------------
// Web: a Hive LazyBox (IndexedDB).
// ---------------------------------------------------------------------------------------------------------------------------

class HiveExerciseMediaBytesStore implements ExerciseMediaBytesStore {
  HiveExerciseMediaBytesStore(this._open);

  /// Resolves the box lazily, once. The provider passes `HiveService.openMediaBlobBox`, which is async and never throws.
  final Future<LazyBox?> Function() _open;
  static const String _metaKey = '_meta';

  Future<LazyBox?>? _opening;
  bool _persistent = false;
  final Map<String, Uint8List> _mem = <String, Uint8List>{};
  String? _memMeta;

  /// True when blobs really go to the box. Valid after the first call; read by tests only.
  @visibleForTesting
  bool get persistent => _persistent;

  Future<LazyBox?> _box() {
    return _opening ??= Future<LazyBox?>.sync(_open).then<LazyBox?>((b) {
      _persistent = b != null;
      return b;
    }, onError: (Object _) {
      _persistent = false;
      return null;
    });
  }

  @override
  Future<Uint8List?> read(String name) async {
    final box = await _box();
    if (box == null) return _mem[name];
    final v = await box.get(name);
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    return null;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    // An exact-length copy: Hive web persists `value.buffer`, the whole backing buffer of a view.
    final copy = Uint8List.fromList(bytes);
    final box = await _box();
    if (box == null) {
      _mem[name] = copy;
      return;
    }
    await box.put(name, copy);
  }

  @override
  Future<void> delete(String name) async {
    final box = await _box();
    if (box == null) {
      _mem.remove(name);
      return;
    }
    await box.delete(name);
  }

  @override
  Future<Map<String, int?>> list() async {
    final box = await _box();
    if (box == null) return <String, int?>{for (final e in _mem.entries) e.key: e.value.length};
    // A LazyBox cannot give a length without `get`, so the length is null.
    return <String, int?>{
      for (final k in box.keys)
        if ('$k' != _metaKey) '$k': null,
    };
  }

  @override
  Future<String?> readMeta() async {
    final box = await _box();
    if (box == null) return _memMeta;
    final v = await box.get(_metaKey);
    return v is String ? v : null;
  }

  @override
  Future<void> writeMeta(String json) async {
    final box = await _box();
    if (box == null) {
      _memMeta = json;
      return;
    }
    await box.put(_metaKey, json);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// The store.
// ---------------------------------------------------------------------------------------------------------------------------

class _Entry {
  _Entry(this.bytes, this.shown);

  final int bytes;

  /// Milliseconds since the epoch of the last put or read.
  int shown;
}

class ExerciseMediaStore {
  ExerciseMediaStore({
    required ExerciseMediaBytesStore bytes,
    int capBytes = 150 * 1024 * 1024,
    DateTime Function()? now,
  })  : _bytes = bytes,
        _cap = capBytes,
        _now = now ?? DateTime.now;

  final ExerciseMediaBytesStore _bytes;
  final int _cap;
  final DateTime Function() _now;

  final Map<String, _Entry> _index = <String, _Entry>{};
  int _total = 0;
  Future<void> _tail = Future<void>.value();

  /// ONE memoised future (G14): created on first access, never re-run. Never completes with an error.
  late final Future<void> ready = _load();

  /// Pure reads of in-memory state; they return the empty state before [ready] completes.
  bool has(String name) => _index.containsKey(name);
  int get totalBytes => _total;

  int _nowMs() => _now().millisecondsSinceEpoch;

  static void _report(Object error, StackTrace stack, String reason) {
    unawaited(ErrorTelemetry.recordNonFatal(error, stack, reason: reason).catchError((Object _) {}));
  }

  /// Appends [task] to the single queue and returns its own result. The tail swallows a failure so one failed task never breaks
  /// or skips the chain.
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  // ---- load and repair --------------------------------------------------------------------------------------------------

  Future<void> _load() async {
    try {
      // Both calls are made before either is awaited.
      final results = await Future.wait<Object?>(<Future<Object?>>[_bytes.list(), _bytes.readMeta()]);
      final listed = results[0]! as Map<String, int?>;
      final parsed = _parseMeta(results[1] as String?);

      final next = <String, _Entry>{};
      final orphans = <String>[];
      for (final item in listed.entries) {
        final name = item.key;
        final len = item.value;
        final known = parsed?[name];
        if (known != null && (len == null || len == known.bytes)) {
          next[name] = _Entry(known.bytes, known.shown);
          continue;
        }
        // Not in the meta, or its recorded length disagrees with the listed one: adopt the blob as it is now.
        var adopted = len;
        if (adopted == null) {
          try {
            adopted = (await _bytes.read(name))?.length;
          } catch (_) {
            adopted = null;
          }
        }
        if (adopted == null) {
          orphans.add(name);
          continue;
        }
        next[name] = _Entry(adopted, _nowMs());
      }

      _index
        ..clear()
        ..addAll(next);
      _total = _sum(next);

      for (final o in orphans) {
        try {
          await _bytes.delete(o);
        } catch (e, st) {
          _report(e, st, 'exercise_media_store_delete');
        }
      }
      // The meta is written only when the repair changed it (a clean load, including an empty store with no meta, writes nothing).
      if (_differs(parsed, next)) await _persistMeta();
    } catch (_) {
      // A failed load is never sticky: an empty index, NO meta write (a good persisted meta survives a transient error).
      _index.clear();
      _total = 0;
    }
  }

  static int _sum(Map<String, _Entry> m) {
    var n = 0;
    for (final e in m.values) {
      n += e.bytes;
    }
    return n;
  }

  /// null = missing or unparsable. STRICT: one wrong-shape entry makes the whole meta unparsable.
  static Map<String, _Entry>? _parseMeta(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final out = <String, _Entry>{};
      for (final e in decoded.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) return null;
        final b = v['bytes'];
        final s = v['shown'];
        if (b is! int || s is! int) return null;
        out[e.key as String] = _Entry(b, s);
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  static bool _differs(Map<String, _Entry>? parsed, Map<String, _Entry> next) {
    if (parsed == null) return next.isNotEmpty;
    if (parsed.length != next.length) return true;
    for (final e in next.entries) {
      final p = parsed[e.key];
      if (p == null || p.bytes != e.value.bytes || p.shown != e.value.shown) return true;
    }
    return false;
  }

  String _encode() => jsonEncode(<String, Object>{
        for (final e in _index.entries) e.key: <String, int>{'bytes': e.value.bytes, 'shown': e.value.shown},
      });

  /// Raw (usable inside a queued task and inside `_load`): persists the index; a failure is reported, never thrown.
  Future<void> _persistMeta() async {
    try {
      await _bytes.writeMeta(_encode());
    } catch (e, st) {
      _report(e, st, 'exercise_media_store_write_meta');
    }
  }

  // ---- read -------------------------------------------------------------------------------------------------------------

  Future<Uint8List?> read(String name) async {
    try {
      await ready;
      final entry = _index[name];
      if (entry == null) return null;
      final expected = entry.bytes;
      final Uint8List? data;
      try {
        data = await _bytes.read(name);
      } catch (e, st) {
        // A transient read error must not delete a good file.
        _report(e, st, 'exercise_media_store_read');
        return null;
      }
      if (data == null) {
        // The blob vanished after load.
        await _serial(() => _dropVanished(name, entry));
        return null;
      }
      if (data.length != expected || !isWellFormedWebp(data)) {
        await _serial(() => _removeBad(name, entry));
        return null;
      }
      // Only if the entry still exists: a delete or eviction that ran during the read must neither throw nor resurrect it.
      final live = _index[name];
      if (live != null) live.shown = _nowMs();
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _dropVanished(String name, _Entry entry) async {
    if (!identical(_index[name], entry)) return;
    _index.remove(name);
    _total -= entry.bytes;
    await _persistMeta();
  }

  Future<void> _removeBad(String name, _Entry entry) async {
    if (!identical(_index[name], entry)) return;
    _index.remove(name);
    _total -= entry.bytes;
    try {
      await _bytes.delete(name);
    } catch (e, st) {
      _report(e, st, 'exercise_media_store_delete');
    }
    await _persistMeta();
  }

  // ---- put and eviction -------------------------------------------------------------------------------------------------

  Future<void> put(String name, Uint8List bytes) async {
    await ready;
    await _serial(() => _putLocked(name, bytes));
  }

  Future<void> _putLocked(String name, Uint8List bytes) async {
    try {
      await _bytes.write(name, bytes);
    } catch (_) {
      // Retried ONCE after evicting the oldest entry that is not this name; with no such victim the error is rethrown.
      final victim = _oldestExcept(name);
      if (victim == null) rethrow;
      await _evictRaw(victim);
      await _bytes.write(name, bytes);
    }
    final old = _index[name];
    if (old != null) _total -= old.bytes;
    _index[name] = _Entry(bytes.length, _nowMs());
    _total += bytes.length;
    while (_total > _cap) {
      final victim = _oldestExcept(name);
      if (victim == null) break; // only the entry just written remains: a file larger than the cap is still kept
      await _evictRaw(victim);
    }
    await _persistMeta();
  }

  /// The entry with the smallest `shown` (ties by name ascending) that is not [except], or null.
  String? _oldestExcept(String except) {
    String? best;
    _Entry? bestEntry;
    for (final e in _index.entries) {
      if (e.key == except) continue;
      if (best == null ||
          e.value.shown < bestEntry!.shown ||
          (e.value.shown == bestEntry.shown && e.key.compareTo(best) < 0)) {
        best = e.key;
        bestEntry = e.value;
      }
    }
    return best;
  }

  /// Total: the entry leaves the index even when the blob delete fails (the orphan is re-adopted or deleted by the next repair).
  Future<void> _evictRaw(String name) async {
    final e = _index.remove(name);
    if (e != null) _total -= e.bytes;
    try {
      await _bytes.delete(name);
    } catch (err, st) {
      _report(err, st, 'exercise_media_store_delete');
    }
  }

  // ---- delete -----------------------------------------------------------------------------------------------------------

  Future<void> delete(String name) async {
    await ready;
    await _serial(() async {
      final entry = _index.remove(name);
      if (entry != null) _total -= entry.bytes;
      // Total: a failed blob delete is reported and the entry has left the index anyway (the orphan is re-adopted next launch).
      try {
        await _bytes.delete(name);
      } catch (e, st) {
        _report(e, st, 'exercise_media_store_delete');
      }
      if (entry != null) await _persistMeta();
    });
  }
}
