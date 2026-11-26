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

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileObject;

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
  });
}
