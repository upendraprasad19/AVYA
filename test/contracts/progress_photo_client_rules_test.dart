// Pure, behavioural pins for unit B2 of the progress-photo PRO batch (OI-314,
// OI-322): the repository's refusal classifier, the `taken_at` wire value and the
// daily-cap window. `capture` itself needs ImagePicker and Supabase and is not
// executed here; its wiring is pinned in progress_photo_capture_wiring_test.dart
// (presence only).
//
// WHAT EACH GROUP CAN FAIL ON
//  - classifier: every branch of the conservative rule, including the cases that
//    must be FALSE (a bare 403 with another message; an offline failure whose
//    statusCode is a Dart type name; the in-flight leg at the INSERT stage).
//  - wire value: ends in Z and is the same instant for a local and a UTC input.
//  - cap window: IST midnight, fed local and UTC inputs and the 23:59:59.999 /
//    00:00:00.000 IST boundary, independent of the machine's zone.
//  - cap boundary: 4 may add one, 5 and 6 may not.
// ZONE MATRIX, stated honestly: this file does not vary the machine's zone. CI and
// pre-push pin Asia/Kolkata, where a device-local midnight EQUALS IST midnight, so a
// "device-local window" regression passes HERE under IST (it fails under UTC and
// America/Los_Angeles, run by hand: ledger row C2, self-attested). What guards it in
// CI is the source pin in progress_photo_capture_wiring_test.dart (the window
// function must call istMidnightUtc and never build a DateTime from local parts).
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/repositories/progress_photo_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, StorageException;

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

  group('exceptions', () {
    test('PhotoQuotaException carries the cap and the message only', () {
      const e = PhotoQuotaException(dailyCap: 5, message: 'm');
      expect(e.dailyCap, 5);
      expect(e.toString(), 'm');
    });

    test('ProgressPhotoProRequiredException has a stable default message', () {
      expect(const ProgressPhotoProRequiredException().toString(),
          'progress_photo_pro_required');
    });
  });

  group('progressPhotoCapReached', () {
    test('the cap is 5 per IST day: 4 photos may add one more, 5 and 6 may not',
        () {
      expect(progressPhotoDailyCap, 5);
      expect(progressPhotoCapReached(0), isFalse);
      expect(progressPhotoCapReached(4), isFalse);
      expect(progressPhotoCapReached(5), isTrue,
          reason: 'the sixth photo of the day must be refused');
      expect(progressPhotoCapReached(6), isTrue);
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

  group('progressPhotoCapWindowStartUtc (OI-322)', () {
    // IST midnight 2026-10-08 00:00 == 2026-10-07 18:30:00Z
    const start8 = '2026-10-07T18:30:00.000Z';
    const start9 = '2026-10-08T18:30:00.000Z';

    test('just before IST midnight is still the previous IST day', () {
      // 2026-10-08 23:59:59.999 IST == 2026-10-08 18:29:59.999 UTC
      expect(progressPhotoCapWindowStartUtc(DateTime.utc(2026, 10, 8, 18, 29, 59, 999)),
          start8);
    });

    test('exactly IST midnight starts the new IST day', () {
      expect(progressPhotoCapWindowStartUtc(DateTime.utc(2026, 10, 8, 18, 30)),
          start9);
    });

    test('mid-day IST', () {
      expect(progressPhotoCapWindowStartUtc(DateTime.utc(2026, 10, 8, 6, 0)),
          start8);
    });

    test('a UTC input and the same instant as a local input agree', () {
      final utc = DateTime.utc(2026, 10, 8, 20, 0);
      final local = utc.toLocal();
      expect(progressPhotoCapWindowStartUtc(local),
          progressPhotoCapWindowStartUtc(utc));
      expect(progressPhotoCapWindowStartUtc(utc), start9);
    });

    test('the result is a UTC ISO string', () {
      expect(progressPhotoCapWindowStartUtc(DateTime.utc(2026, 1, 1, 12)).endsWith('Z'),
          isTrue);
    });
  });
}
