import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Locks the contract that `evaluateAndPromote` uses an UPSERT
/// (with onConflict on the (user_id, rank_code) UNIQUE constraint),
/// not a plain INSERT. A regression here means duplicate rows or
/// 23505 errors flooding logs the moment the cron + client both
/// fire on the same day.
void main() {
  test('evaluateAndPromote uses upsert with onConflict', () {
    final src =
        File('lib/core/services/rank_service.dart').readAsStringSync();

    // Find the method body.
    final start = src.indexOf('Future<void> evaluateAndPromote()');
    expect(start, isNot(-1), reason: 'evaluateAndPromote must exist');

    // Take a generous body slice (4000 chars covers the method).
    final body = src.substring(start, start + 4000);

    expect(
      body.contains('rank_promotions'),
      isTrue,
      reason: 'method must reference rank_promotions table',
    );
    expect(
      body.contains('.upsert('),
      isTrue,
      reason: 'must use upsert, not insert (idempotency)',
    );
    expect(
      body.contains("onConflict: 'user_id,rank_code'"),
      isTrue,
      reason: "upsert must specify onConflict: 'user_id,rank_code' "
          'matching the UNIQUE constraint from migration 039.',
    );
  });
}
