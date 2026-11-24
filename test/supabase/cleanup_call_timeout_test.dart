// test/supabase/cleanup_call_timeout_test.dart
//
// Regression for diagnose 5c8e2f: one stuck DELETE inside
// SupabaseTestHelper.cleanup() ate the whole 30 s test budget (T1/T2 of
// sync_service_test.dart, main pushes of PR #260 and PR #264). Credential-free:
// drives cleanup() through the `deleteRows` seam, so it runs in the plain
// Unit Tests job too.
@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'supabase_test_helper.dart';

const _qaId = '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4';

void main() {
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    SupabaseTestHelper.deleteCallTimeout = const Duration(milliseconds: 50);
    SupabaseTestHelper.debugSetSignedInIdForTests(_qaId);
  });
  tearDown(SupabaseTestHelper.resetSeams);

  test('a delete that hangs once is abandoned and retried; cleanup completes',
      () async {
    var first = true;
    SupabaseTestHelper.deleteRows = (table, uid) {
      calls.add(table);
      if (first) {
        first = false;
        return Completer<void>().future; // never completes: the stuck socket
      }
      return Future<void>.value();
    };

    await SupabaseTestHelper.cleanup();

    // 13 tables (nutrition_slot_tombstones added, diagnose c7f4e2) + exactly
    // one retry of the first.
    expect(calls.length, 14);
    expect(calls.first, calls[1], reason: 'the stuck table is retried at once');
  });

  test('a delete that hangs twice fails LOUDLY instead of being swallowed',
      () async {
    SupabaseTestHelper.deleteRows =
        (table, uid) {
      calls.add(table);
      return Completer<void>().future;
    };

    await expectLater(
        SupabaseTestHelper.cleanup(), throwsA(isA<TimeoutException>()));
    expect(calls.length, 2, reason: 'one attempt + one retry, then give up');
  });

  test('an ordinary delete error (missing table) is still skipped', () async {
    SupabaseTestHelper.deleteRows = (table, uid) async {
      calls.add(table);
      throw StateError('relation does not exist');
    };

    await SupabaseTestHelper.cleanup();

    expect(calls.length, 13, reason: 'no retry, no abort on a non-timeout');
  });

  // Diagnose c7f4e2: deleting a nutrition_logs row writes a tombstone
  // (migration 181), so the tombstones must be deleted AFTER it, or the
  // cleanup leaves one behind that wins the next run's re-baseline.
  test('the slot tombstones are deleted after nutrition_logs', () async {
    SupabaseTestHelper.deleteRows = (table, uid) async {
      calls.add(table);
    };

    await SupabaseTestHelper.cleanup();

    final logs = calls.indexOf('nutrition_logs');
    final tombs = calls.indexOf('nutrition_slot_tombstones');
    expect(logs, greaterThanOrEqualTo(0));
    expect(tombs, greaterThan(logs));
  });
}
