// BEHAVIOURAL tests of the free weekly slot check, the bounded orphan sweep and
// removeIfNoRow (OI-348 Landing 3c), through the repository's Storage seams
// (`debugListObjectsOverride`, `debugRowPathsOverride`,
// `debugRemoveObjectsOverride`) and the app clock (`setTestClockTo`). No
// Supabase, no picker.
//
// WHAT EACH CASE CAN FAIL ON
//  - slot: one object this week is "used"; last week's is not; a failed listing
//    is "unknown" (null), never "used".
//  - sweep: only this week's objects at least 60 min old with NO row are removed;
//    an object with a row, a young one and last week's are kept; a failed row
//    read removes nothing; a removed orphan no longer holds the slot; a failed
//    removal still holds it.
//  - removeIfNoRow: removes only after a successful read shows no row; keeps the
//    object when its row exists or the read fails, and remembers the latter for
//    the 2-minute sweep.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileObject, PostgrestException, StorageException;

FileObject _obj(String name, String? createdAt) => FileObject(
    name: name,
    bucketId: 'progress-photos',
    owner: null,
    id: null,
    updatedAt: null,
    createdAt: createdAt,
    lastAccessedAt: null,
    metadata: null,
    buckets: null);

const _u = 'user-1';
final _now = DateTime.utc(2026, 11, 26, 10); // Thu 15:30 IST

void main() {
  final repo = ProgressPhotoRepository.instance;
  late List<FileObject> listing;
  late Set<String> rowPaths;
  late List<List<String>> removed;
  late List<List<String>> rowReads;
  Object? listError;
  Object? rowError;
  Object? removeError;

  setUp(() {
    setTestClockTo(_now);
    listing = [];
    rowPaths = {};
    removed = [];
    rowReads = [];
    listError = null;
    rowError = null;
    removeError = null;
    repo.ownFailedCleanups.clear();
    ProgressPhotoRepository.debugListObjectsOverride = (userId) async {
      expect(userId, _u);
      if (listError != null) throw listError!;
      return listing;
    };
    ProgressPhotoRepository.debugRowPathsOverride = (userId, paths) async {
      expect(userId, _u);
      rowReads.add(paths);
      if (rowError != null) throw rowError!;
      return {for (final p in paths) if (rowPaths.contains(p)) p};
    };
    ProgressPhotoRepository.debugRemoveObjectsOverride = (paths) async {
      if (removeError != null) throw removeError!;
      removed.add(paths);
    };
  });

  tearDown(() {
    resetTestClock();
    ProgressPhotoRepository.debugListObjectsOverride = null;
    ProgressPhotoRepository.debugRowPathsOverride = null;
    ProgressPhotoRepository.debugRemoveObjectsOverride = null;
    repo.ownFailedCleanups.clear();
  });

  group('freeSlotOpen', () {
    test('no objects: open', () async {
      expect(await repo.freeSlotOpen(_u), isTrue);
    });

    test('a photo (with its row) this week: used, and nothing is removed',
        () async {
      listing = [_obj('a.jpg', '2026-11-24T05:00:00Z')];
      rowPaths = {'$_u/a.jpg'};
      expect(await repo.freeSlotOpen(_u), isFalse);
      expect(removed, isEmpty);
    });

    test("last week's photo does not hold this week's slot", () async {
      listing = [_obj('a.jpg', '2026-11-22T18:29:59.999Z')];
      expect(await repo.freeSlotOpen(_u), isTrue);
      expect(removed, isEmpty, reason: 'last week is never swept');
    });

    test('a failed listing is unknown (null), never "used"', () async {
      listError = Exception('offline');
      expect(await repo.freeSlotOpen(_u), isNull);
    });

    test('an orphan this week older than 60 min is removed and frees the slot',
        () async {
      listing = [_obj('o.jpg', '2026-11-26T08:59:00Z')];
      expect(await repo.freeSlotOpen(_u), isTrue);
      expect(removed, [
        ['$_u/o.jpg']
      ]);
    });

    test('a young orphan (59 min) is kept and holds the slot', () async {
      listing = [_obj('o.jpg', '2026-11-26T09:01:00Z')];
      expect(await repo.freeSlotOpen(_u), isFalse);
      expect(removed, isEmpty);
      expect(rowReads, isEmpty, reason: 'no candidate, no row read');
    });

    test('a failed row read removes nothing and the object holds the slot',
        () async {
      listing = [_obj('o.jpg', '2026-11-26T08:00:00Z')];
      rowError = Exception('500');
      expect(await repo.freeSlotOpen(_u), isFalse);
      expect(removed, isEmpty);
    });

    test('a failed removal keeps holding the slot', () async {
      listing = [_obj('o.jpg', '2026-11-26T08:00:00Z')];
      removeError = Exception('403');
      expect(await repo.freeSlotOpen(_u), isFalse);
    });

    test('rows are read ONLY for this week\'s aged candidates', () async {
      listing = [
        _obj('old.jpg', '2026-11-20T08:00:00Z'),
        _obj('young.jpg', '2026-11-26T09:30:00Z'),
        _obj('aged.jpg', '2026-11-25T08:00:00Z'),
      ];
      rowPaths = {'$_u/aged.jpg'};
      expect(await repo.freeSlotOpen(_u), isFalse);
      expect(rowReads, [
        ['$_u/aged.jpg']
      ]);
      expect(removed, isEmpty);
    });
  });

  group('removeIfNoRow', () {
    test('no row: the object is removed', () async {
      await repo.removeIfNoRow(_u, '$_u/x.jpg');
      expect(removed, [
        ['$_u/x.jpg']
      ]);
      expect(repo.ownFailedCleanups, isEmpty);
    });

    test('a row exists (the insert committed, its response was lost): kept',
        () async {
      rowPaths = {'$_u/x.jpg'};
      await repo.removeIfNoRow(_u, '$_u/x.jpg');
      expect(removed, isEmpty);
    });

    test('the row read fails: kept, and remembered for the 2-minute sweep',
        () async {
      rowError = Exception('offline');
      await repo.removeIfNoRow(_u, '$_u/x.jpg');
      expect(removed, isEmpty);
      expect(repo.ownFailedCleanups, {'$_u/x.jpg'});
    });

    test('the remembered path is swept after 2 minutes, then forgotten',
        () async {
      repo.ownFailedCleanups.add('$_u/x.jpg');
      listing = [_obj('x.jpg', '2026-11-26T09:57:00Z')]; // 3 min old
      expect(await repo.freeSlotOpen(_u), isTrue);
      expect(removed, [
        ['$_u/x.jpg']
      ]);
      expect(repo.ownFailedCleanups, isEmpty);
    });

    test('a remembered path whose row turned up is forgotten, not removed',
        () async {
      repo.ownFailedCleanups.add('$_u/x.jpg');
      listing = [_obj('x.jpg', '2026-11-26T09:57:00Z')];
      rowPaths = {'$_u/x.jpg'};
      expect(await repo.freeSlotOpen(_u), isFalse);
      expect(removed, isEmpty);
      expect(repo.ownFailedCleanups, isEmpty);
    });

    test('a hung row read times out: kept, remembered, never removed',
        () async {
      ProgressPhotoRepository.debugRowPathsOverride =
          (userId, paths) => Completer<Set<String>>().future;
      fakeAsync((async) {
        var done = false;
        repo.removeIfNoRow(_u, '$_u/x.jpg').then((_) => done = true);
        async.elapse(
            progressPhotoStorageCallTimeout - const Duration(milliseconds: 1));
        expect(done, isFalse, reason: 'waits the full timeout');
        async.elapse(const Duration(milliseconds: 2));
        expect(done, isTrue);
      });
      expect(removed, isEmpty);
      expect(repo.ownFailedCleanups, {'$_u/x.jpg'});
    });
  });

  // B-pass F4 (2026-11-26): a row insert that failed WITHOUT a server answer
  // may still commit; removing its object then leaves a row with no picture.
  group('cleanupAfterFailedInsert', () {
    test('a PostgREST error (the server answered): removed now', () async {
      await repo.cleanupAfterFailedInsert(_u, '$_u/x.jpg',
          const PostgrestException(message: 'boom', code: '23505'));
      expect(rowReads, [
        ['$_u/x.jpg']
      ]);
      expect(removed, [
        ['$_u/x.jpg']
      ]);
      expect(repo.ownFailedCleanups, isEmpty);
    });

    for (final e in <Object>[
      TimeoutException('insert'),
      Exception('SocketException: Failed host lookup'),
    ]) {
      test('a transport failure ($e): nothing read or removed now; left to '
          'the 2-minute sweep', () async {
        await repo.cleanupAfterFailedInsert(_u, '$_u/x.jpg', e);
        expect(rowReads, isEmpty);
        expect(removed, isEmpty);
        expect(repo.ownFailedCleanups, {'$_u/x.jpg'});
      });
    }

    test('then the late row is seen by the sweep: kept and forgotten',
        () async {
      await repo.cleanupAfterFailedInsert(
          _u, '$_u/x.jpg', TimeoutException('insert'));
      listing = [_obj('x.jpg', '2026-11-26T09:57:00Z')]; // 3 min old
      rowPaths = {'$_u/x.jpg'}; // the insert committed after all
      expect(await repo.freeSlotOpen(_u), isFalse);
      expect(removed, isEmpty);
      expect(repo.ownFailedCleanups, isEmpty);
    });
  });

  // Hermes (2026-11-26): one rule decides whether a failed write certainly did
  // not land (a server ANSWER) or may still land (anything else).
  group('progressPhotoServerRefused', () {
    final cases = <(Object, bool, String)>[
      (const PostgrestException(message: 'dup', code: '23505'), true, 'SQLSTATE'),
      (const PostgrestException(message: 'cap', code: 'P0001'), true, 'trigger refusal'),
      (const PostgrestException(message: 'x', code: 'PGRST116'), true, 'PostgREST code'),
      (const PostgrestException(message: '<html>', code: '400'), true, 'bare 4xx'),
      (const PostgrestException(message: '<html>', code: '502'), false, 'gateway 502'),
      (const PostgrestException(message: '<html>', code: '408'), false, 'proxy 408'),
      (const PostgrestException(message: '<html>', code: '499'), false, 'client closed 499'),
      (const PostgrestException(message: '<html>', code: '429'), true, 'rate limited 429'),
      (const PostgrestException(message: '<html>', code: '504'), false, 'gateway 504'),
      (const PostgrestException(message: 'x'), false, 'no code'),
      (const StorageException('rls', statusCode: '403'), true, 'storage 403'),
      (const StorageException('dup', statusCode: '409'), true, 'storage 409'),
      (const StorageException('gw', statusCode: '504'), false, 'storage 504'),
      (const StorageException('slow', statusCode: '408'), false, 'storage 408'),
      (const StorageException('big', statusCode: '413'), true, 'storage 413 (nothing stored)'),
      (const StorageException('net', statusCode: 'ClientException'), false, 'transport (type name)'),
      (const StorageException('net'), false, 'no status'),
      (TimeoutException('t'), false, 'timeout'),
      (Exception('SocketException'), false, 'socket'),
    ];
    for (final (e, want, label) in cases) {
      test('$label -> $want', () => expect(progressPhotoServerRefused(e), want));
    }
  });

  group('upload and delete failures (Hermes C1, C2/D1, C3)', () {
    test('a gateway 502 on the row insert is NOT an answer: left to the sweep',
        () async {
      await repo.cleanupAfterFailedInsert(_u, '$_u/x.jpg',
          const PostgrestException(message: '<html>', code: '502'));
      expect(rowReads, isEmpty);
      expect(removed, isEmpty);
      expect(repo.ownFailedCleanups, {'$_u/x.jpg'});
    });

    test('an upload refused by Storage (403) stored nothing: not remembered', () {
      repo.noteFailedUpload(
          '$_u/x.jpg', const StorageException('rls', statusCode: '403'));
      expect(repo.ownFailedCleanups, isEmpty);
    });

    for (final e in <Object>[
      const StorageException('net', statusCode: 'ClientException'),
      const StorageException('gw', statusCode: '504'),
      TimeoutException('upload'),
    ]) {
      test('an upload with no answer ($e) is remembered for the 2-minute sweep',
          () {
        repo.noteFailedUpload('$_u/x.jpg', e);
        expect(repo.ownFailedCleanups, {'$_u/x.jpg'});
      });
    }

    test('a lost upload response: the stored object is swept after 2 minutes',
        () async {
      repo.noteFailedUpload('$_u/x.jpg', TimeoutException('upload'));
      listing = [_obj('x.jpg', '2026-11-26T09:57:00Z')]; // 3 min old
      expect(await repo.freeSlotOpen(_u), isTrue);
      expect(removed, [
        ['$_u/x.jpg']
      ]);
    });

    test('a deleted photo whose object removal fails frees the slot after 2 minutes',
        () async {
      removeError = Exception('offline');
      await repo.removeDeletedPhotoObject('$_u/x.jpg');
      expect(repo.ownFailedCleanups, {'$_u/x.jpg'});
      removeError = null;
      listing = [_obj('x.jpg', '2026-11-26T09:57:00Z')];
      expect(await repo.freeSlotOpen(_u), isTrue,
          reason: 'the retake the founder allowed is open again');
      expect(removed.last, ['$_u/x.jpg']);
    });

    test('a deleted photo whose object removal succeeds is not remembered',
        () async {
      await repo.removeDeletedPhotoObject('$_u/x.jpg');
      expect(removed, [
        ['$_u/x.jpg']
      ]);
      expect(repo.ownFailedCleanups, isEmpty);
    });
  });
}
