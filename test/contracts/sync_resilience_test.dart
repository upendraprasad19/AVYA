// Regression contract for diagnose a7f2e9 (BUG-G + BUG-H, APK +34 batch):
//  - realtime weight_logs stream must recover from a transient channelError
//    (RealtimeSubscribeException channelError / WS close 1002), not only from a
//    "token expired" error. Pre-fix only token-expiry reconnected, so a
//    channelError left the stream permanently dead (113x in client_errors; PRO
//    Telegram->app instant-sync silently never delivered).
//  - restore must refresh the session before the long multi-step pull so a
//    token expiring mid-restore doesn't 401 (heavy accounts span the TTL).
//
// Source-grep (presence). The reconnect mechanism + ensureFreshToken primitive
// are exercised by realtime/supabase_service tests; this guards the callers.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  test('realtime recovers from a transient channelError (not only token-expiry)',
      () {
    final src = _strip(
        File('lib/core/services/sync/sync_realtime.dart').readAsStringSync());
    expect(src.contains('isChannelError'), isTrue);
    expect(src.contains('channelerror'), isTrue,
        reason: 'a channelError must trigger a bounded reconnect, not stay dead');
  });

  test('restore refreshes the session before the long pull', () {
    final src =
        _strip(File('lib/core/services/sync_service.dart').readAsStringSync());
    // 3 EF invokes (BUG-C d3a1c7) + both restore entrypoints (BUG-G) = >= 5.
    expect('ensureFreshToken'.allMatches(src).length, greaterThanOrEqualTo(5),
        reason: 'restoreFromCloud + restoreFromCloudForUser must refresh up front');
  });
}
