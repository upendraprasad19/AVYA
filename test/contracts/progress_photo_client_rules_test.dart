// Pure, behavioural pins for the progress-photo client rules: the refusal
// classifier (OI-314; the storage-trigger literal leg, OI-348 Landing 3c), the
// `taken_at` wire value (OI-322), and the free weekly cap (Landing 3c): the IST
// week start that mirrors SQL `progress_photo_week_start`, the held-this-week
// count, the orphan candidates and the content type. `capture` itself needs
// ImagePicker and Supabase and is not executed here; its wiring is pinned in
// progress_photo_capture_wiring_test.dart (presence only) and the slot / sweep
// behaviour in progress_photo_free_slot_test.dart (repository seams).
//
// WHAT EACH GROUP CAN FAIL ON
//  - classifier: every branch of the conservative rule, including the cases that
//    must be FALSE (a bare 403 with another message; an offline failure whose
//    statusCode is a Dart type name; the in-flight leg at the INSERT stage).
//  - wire value: ends in Z and is the same instant for a local and a UTC input.
//  - week start: Monday 00:00 IST at the Sunday 23:59:59.999 / Monday 00:00:00.000
//    boundary, across UTC midnight and a year end, local and UTC inputs.
//  - slot / orphans: the 1-per-week boundary, the 60-minute and 2-minute ages,
//    last week and unreadable values never counted.
// ZONE MATRIX, stated honestly: this file does not vary the machine's zone. The
// week start is built from UTC instants and `istMidnightUtc` only; the local-input
// case above is the check that a device-local value gives the same answer.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileObject, PostgrestException, StorageException;

StorageException _rls({String status = '403'}) => StorageException.fromJson({
      'statusCode': status,
      'error': 'Unauthorized',
      'message': 'new row violates row-level security policy',
    });

StorageException _storage(String message, String? statusCode) =>
    StorageException(message, statusCode: statusCode);

bool _refusal(
  Object e, {
  bool upload = true,
  bool inFlight = false,
}) =>
    isProgressPhotoProRefusal(e, uploadStage: upload, paymentInFlight: inFlight);

void main() {
  group('isProgressPhotoProRefusal', () {
    test('the trigger: P0001 with the marker is a refusal at any stage', () {
      const e = PostgrestException(
          message: 'progress_photo_pro_required', code: 'P0001');
      expect(_refusal(e), isTrue);
      expect(_refusal(e, upload: false), isTrue);
    });

    test('P0001 without the marker, and the marker without P0001, are not', () {
      expect(
          _refusal(const PostgrestException(message: 'other', code: 'P0001')),
          isFalse);
      expect(
          _refusal(const PostgrestException(
              message: 'progress_photo_pro_required', code: '23505')),
          isFalse);
    });

    test('the Storage policy: the documented RLS body is a refusal', () {
      expect(_refusal(_rls()), isTrue);
      expect(_refusal(_rls(status: '400')), isTrue);
      expect(_refusal(_rls(), upload: false), isTrue,
          reason: 'the message alone decides; stage and payment do not matter');
    });

    test('the message match is case-insensitive', () {
      expect(_refusal(_storage('New Row Violates ROW-LEVEL SECURITY', '403')),
          isTrue);
    });

    test('a bare 403 with another message is NOT a refusal (expired token)', () {
      expect(_refusal(_storage('Invalid JWT', '403')), isFalse);
      expect(_refusal(_storage('Invalid JWT', '403'), inFlight: false), isFalse);
    });

    test('the just-paid leg: upload stage + in flight + 400/403 StorageException',
        () {
      expect(_refusal(_storage('Unauthorized', '403'), inFlight: true), isTrue);
      expect(_refusal(_storage('Bad Request', '400'), inFlight: true), isTrue);
    });

    test('the just-paid leg needs EVERY condition', () {
      final e = _storage('Unauthorized', '403');
      expect(_refusal(e, inFlight: true, upload: false), isFalse,
          reason: 'at the INSERT stage the trigger speaks, not this leg');
      expect(_refusal(e, inFlight: false), isFalse);
      expect(_refusal(_storage('Payload too large', '413'), inFlight: true),
          isFalse);
      expect(_refusal(_storage('Server error', '500'), inFlight: true), isFalse);
    });

    test('an offline failure is never a refusal, even in the just-paid window',
        () {
      // storage_client turns a non-HTTP failure into a StorageException whose
      // statusCode is the Dart runtime type name.
      expect(
          _refusal(_storage('SocketException: Failed host lookup', 'SocketException'),
              inFlight: true),
          isFalse);
      expect(_refusal(_storage('timeout', null), inFlight: true), isFalse);
    });

    test('unrelated errors are not refusals', () {
      expect(_refusal(Exception('boom'), inFlight: true), isFalse);
      expect(_refusal(StateError('x')), isFalse);
      expect(
          _refusal(const PostgrestException(message: 'rls', code: '42501')),
          isFalse);
    });
  });


  group('isProgressPhotoProRefusal: the storage trigger literal (Landing 3c)', () {
    test('a StorageException carrying progress_photo_pro_required is a refusal',
        () {
      expect(_refusal(_storage('progress_photo_pro_required', '403')), isTrue);
      expect(_refusal(_storage('progress_photo_pro_required', '500'),
              upload: false),
          isTrue,
          reason: 'the literal alone decides, whatever status Storage maps');
    });

    test('a different marker in a StorageException is not', () {
      expect(_refusal(_storage('progress_photo_other', '403')), isFalse);
    });
  });

  group('exceptions', () {
    test('PhotoQuotaException carries the weekly cap and the message only', () {
      const e = PhotoQuotaException(weeklyCap: 1, message: 'm');
      expect(e.weeklyCap, 1);
      expect(e.toString(), 'm');
    });

    test('ProgressPhotoProRequiredException has a stable default message', () {
      expect(const ProgressPhotoProRequiredException().toString(),
          'progress_photo_pro_required');
    });
  });

  group('progressPhotoTakenAtWire (OI-322)', () {
    test('a local time is sent as the same instant in UTC with a Z', () {
      final local = DateTime(2026, 10, 8, 23, 30); // machine-local
      final wire = progressPhotoTakenAtWire(local);
      expect(wire.endsWith('Z'), isTrue);
      expect(DateTime.parse(wire).isAtSameMomentAs(local), isTrue);
    });

    test('an IST wall time round-trips to the right UTC instant', () {
      // 2026-10-08 23:30 IST == 2026-10-08 18:00 UTC
      final utc = DateTime.utc(2026, 10, 8, 18, 0);
      expect(progressPhotoTakenAtWire(utc), '2026-10-08T18:00:00.000Z');
    });
  });

  // 2026-11-23 is a Monday. Monday 00:00 IST == 2026-11-22T18:30:00Z.
  final mon23 = DateTime.utc(2026, 11, 22, 18, 30);
  final mon30 = DateTime.utc(2026, 11, 29, 18, 30);

  group('progressPhotoWeekStartUtc (mirror of SQL progress_photo_week_start)', () {
    test('Monday 00:00:00.000 IST starts its own week', () {
      expect(progressPhotoWeekStartUtc(mon23), mon23);
      expect(progressPhotoWeekStartUtc(mon30), mon30);
    });

    test('Sunday 23:59:59.999 IST is still the week that began 6 days earlier',
        () {
      final sunLast = mon30.subtract(const Duration(milliseconds: 1));
      expect(progressPhotoWeekStartUtc(sunLast), mon23);
    });

    test('mid-week, both sides of UTC midnight', () {
      // Thu 2026-11-26 03:00 IST == Wed 21:30 UTC (the UTC date is Wednesday)
      expect(progressPhotoWeekStartUtc(DateTime.utc(2026, 11, 25, 21, 30)),
          mon23);
      // Sun 2026-11-29 05:00 IST == Sat 23:30 UTC
      expect(progressPhotoWeekStartUtc(DateTime.utc(2026, 11, 28, 23, 30)),
          mon23);
    });

    test('a local input and the same instant in UTC agree, and the result is UTC',
        () {
      final utc = DateTime.utc(2026, 11, 26, 10, 0);
      expect(progressPhotoWeekStartUtc(utc.toLocal()),
          progressPhotoWeekStartUtc(utc));
      expect(progressPhotoWeekStartUtc(utc).isUtc, isTrue);
    });

    test('a year boundary (Mon 2026-12-28 to Sun 2027-01-03)', () {
      final mon = DateTime.utc(2026, 12, 27, 18, 30);
      expect(progressPhotoWeekStartUtc(DateTime.utc(2027, 1, 3, 18, 29)), mon);
      expect(progressPhotoWeekStartUtc(DateTime.utc(2027, 1, 3, 18, 30)),
          DateTime.utc(2027, 1, 3, 18, 30));
    });
  });

  group('parseStorageInstant', () {
    test('Z and an explicit offset are read as given', () {
      expect(parseStorageInstant('2026-11-26T10:00:00.000Z'),
          DateTime.utc(2026, 11, 26, 10));
      expect(parseStorageInstant('2026-11-26T15:30:00+05:30'),
          DateTime.utc(2026, 11, 26, 10));
    });

    test('a value without an offset is read as UTC, never device-local', () {
      expect(parseStorageInstant('2026-11-26T10:00:00.000'),
          DateTime.utc(2026, 11, 26, 10));
    });

    test('null, empty and unreadable values are null', () {
      expect(parseStorageInstant(null), isNull);
      expect(parseStorageInstant(''), isNull);
      expect(parseStorageInstant('yesterday'), isNull);
    });
  });

  group('the free weekly slot (1 per IST week)', () {
    final now = DateTime.utc(2026, 11, 26, 10); // Thu
    test('the cap is 1', () => expect(progressPhotoFreeWeeklyCap, 1));

    test('no object this week: open', () {
      expect(progressPhotoFreeSlotOpen(const [], now), isTrue);
      expect(
          progressPhotoFreeSlotOpen(
              ['2026-11-22T18:29:59.999Z'], now), // Sun 23:59:59.999 IST, last week
          isTrue);
    });

    test('one object this week: used, from the first millisecond of Monday', () {
      expect(progressPhotoFreeSlotOpen(['2026-11-22T18:30:00.000Z'], now),
          isFalse);
      expect(progressPhotosHeldThisWeek(
              ['2026-11-22T18:30:00.000Z', '2026-11-25T01:00:00Z'], now),
          2);
    });

    test('an unreadable created_at is not counted (courtesy check only)', () {
      expect(progressPhotoFreeSlotOpen([null, 'garbage'], now), isTrue);
    });
  });

  group('progressPhotoOrphanCandidates', () {
    FileObject obj(String name, String? createdAt) => FileObject(
        name: name,
        bucketId: 'progress-photos',
        owner: null,
        id: null,
        updatedAt: null,
        createdAt: createdAt,
        lastAccessedAt: null,
        metadata: null,
        buckets: null);
    final now = DateTime.utc(2026, 11, 26, 10);

    test('this week AND at least 60 minutes old', () {
      final c = progressPhotoOrphanCandidates('u', [
        obj('a.jpg', '2026-11-26T08:59:00Z'), // 61 min: candidate
        obj('b.jpg', '2026-11-26T09:01:00Z'), // 59 min: kept
        obj('c.jpg', '2026-11-22T18:00:00Z'), // last week: kept
        obj('d.jpg', null), // unreadable: kept
      ], now);
      expect(c, ['u/a.jpg']);
    });

    test('exactly 60 minutes old is a candidate (the boundary)', () {
      expect(
          progressPhotoOrphanCandidates(
              'u', [obj('a.jpg', '2026-11-26T09:00:00Z')], now),
          ['u/a.jpg']);
    });

    test("this device's own failed cleanup is a candidate after 2 minutes", () {
      final objs = [obj('a.jpg', '2026-11-26T09:57:00Z')]; // 3 min old
      expect(progressPhotoOrphanCandidates('u', objs, now), isEmpty);
      expect(
          progressPhotoOrphanCandidates('u', objs, now,
              ownFailed: {'u/a.jpg'}),
          ['u/a.jpg']);
      expect(
          progressPhotoOrphanCandidates(
              'u', [obj('a.jpg', '2026-11-26T09:59:00Z')], now,
              ownFailed: {'u/a.jpg'}),
          isEmpty,
          reason: 'one minute old is still too young even for its own upload');
    });
  });

  group('progressPhotoContentType', () {
    test('the picker MIME type wins when the bucket accepts it', () {
      expect(progressPhotoContentType('x.bin', 'image/png'),
          (ext: 'png', mime: 'image/png'));
      expect(progressPhotoContentType('x.png', 'image/jpeg'),
          (ext: 'jpg', mime: 'image/jpeg'));
      expect(progressPhotoContentType('x', 'image/webp'),
          (ext: 'webp', mime: 'image/webp'));
    });

    test('else the extension, else JPEG', () {
      expect(progressPhotoContentType('IMG.PNG', null),
          (ext: 'png', mime: 'image/png'));
      expect(progressPhotoContentType('a.webp', 'image/heic'),
          (ext: 'webp', mime: 'image/webp'));
      expect(progressPhotoContentType('a.heic', 'image/heic'),
          (ext: 'jpg', mime: 'image/jpeg'));
    });
  });
}
