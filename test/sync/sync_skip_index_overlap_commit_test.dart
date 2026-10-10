@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';

/// L1a-3 / D5a: two overlapping passes over ONE domain index must not
/// overwrite each other's confirmations. `commit` merges this pass's own
/// deltas into a fresh re-read of the box.
void main() {
  late Directory dir;
  late Box<dynamic> box;
  const domain = SyncSkipDomain.exlog;

  SyncSkipIndex newIndex({bool disabled = false}) => SyncSkipIndex(
        box: box,
        domain: domain,
        disabled: disabled,
        ownerChangedNow: () => false,
        reportFailure: (_, __, ___) {},
      );

  Map<String, String> stored() => SyncSkipIndex.readIndex(box, domain.indexKey);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('skip_overlap');
    Hive.init(dir.path);
    box = await Hive.openBox<dynamic>('skip_overlap_box');
  });
  tearDown(() async {
    await Hive.deleteFromDisk();
    dir.deleteSync(recursive: true);
  });

  test('overlapping passes keep each other\'s confirmations', () async {
    final a = newIndex();
    final b = newIndex(); // snapshot taken BEFORE a commits
    await a.pushIfChanged('k1', () => 'f1', () async => true);
    await b.pushIfChanged('k2', () => 'f2', () async => true);
    await a.commit(liveKeys: {'k1', 'k2'});
    await b.commit(liveKeys: {'k1', 'k2'});
    expect(stored(), {'k1': 'f1', 'k2': 'f2'});
  });

  test('a forgotten key is removed, a skipped key is untouched', () async {
    await box.put(domain.indexKey, {'k1': 'f1', 'k2': 'f2', 'k3': 'f3'});
    final a = newIndex();
    // A concurrent pass re-confirms k3 with a NEW fingerprint.
    await box.put(domain.indexKey, {'k1': 'f1', 'k2': 'f2', 'k3': 'f3new'});
    expect(await a.pushIfChanged('k1', () => 'f1', () async => true), isTrue);
    expect(a.skipped, 1);
    await a.pushIfChanged('k2', () => 'x', () async => false); // unconfirmed
    await a.commit(liveKeys: {'k1', 'k2', 'k3'});
    expect(stored(), {'k1': 'f1', 'k3': 'f3new'});
  });

  test('prunes non-live keys and writes nothing when unchanged', () async {
    await box.put(domain.indexKey, {'k1': 'f1', 'gone': 'g'});
    final a = newIndex();
    await a.commit(liveKeys: {'k1'});
    expect(stored(), {'k1': 'f1'});
    final raw = box.get(domain.indexKey);
    final b = newIndex();
    await b.commit(liveKeys: {'k1'});
    expect(identical(box.get(domain.indexKey), raw), isTrue);
  });

  test('a disabled index deletes itself at commit', () async {
    await box.put(domain.indexKey, {'k1': 'f1'});
    await newIndex(disabled: true).commit(liveKeys: {'k1'});
    expect(box.containsKey(domain.indexKey), isFalse);
  });

  test('a re-push with a NEW fingerprint at the same map size is written',
      () async {
    await box.put(domain.indexKey, {'k1': 'f1'});
    final a = newIndex();
    await a.pushIfChanged('k1', () => 'f1b', () async => true);
    await a.commit(liveKeys: {'k1'});
    expect(stored(), {'k1': 'f1b'});
  });

  test('fail then succeed on the same key in one pass keeps the confirmation',
      () async {
    final a = newIndex();
    await a.pushIfChanged('k1', () => 'f1', () async => false);
    await a.pushIfChanged('k1', () => 'f1', () async => true);
    await a.commit(liveKeys: {'k1'});
    expect(stored(), {'k1': 'f1'});
  });

  test('succeed then fail on the same key in one pass drops the entry',
      () async {
    final a = newIndex();
    await a.pushIfChanged('k1', () => 'f1', () async => true);
    await a.pushIfChanged('k1', () => 'f1b', () async => false);
    await a.commit(liveKeys: {'k1'});
    expect(stored(), isEmpty);
  });

  test('a key confirmed this pass but absent from liveKeys is pruned',
      () async {
    final a = newIndex();
    await a.pushIfChanged('gone', () => 'g', () async => true);
    await a.pushIfChanged('k1', () => 'f1', () async => true);
    await a.commit(liveKeys: {'k1'});
    expect(stored(), {'k1': 'f1'});
  });

  test('recordConfirmedAll: owner change writes nothing; else merges once',
      () async {
    await box.put(domain.indexKey, {'k1': 'f1'});
    await SyncSkipIndex.recordConfirmedAll(box, domain, {'k2': 'f2'},
        ownerChangedNow: () => true);
    expect(stored(), {'k1': 'f1'});
    await SyncSkipIndex.recordConfirmedAll(box, domain, {'k2': 'f2'},
        ownerChangedNow: () => false);
    expect(stored(), {'k1': 'f1', 'k2': 'f2'});
  });
}
