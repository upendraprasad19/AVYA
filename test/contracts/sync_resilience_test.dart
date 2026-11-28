// Regression contract for diagnose a7f2e9 (BUG-G, APK +34 batch):
//  - restore must refresh the session before the long multi-step pull so a
//    token expiring mid-restore doesn't 401 (heavy accounts span the TTL).
//
// Source-grep (presence). The ensureFreshToken primitive is exercised by
// supabase_service tests; this guards the callers. (The realtime half of this
// file was removed with the Realtime subscription, batch realtime-weight-off.)

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
  test('restore refreshes the session before the long pull', () {
    final src =
        _strip(File('lib/core/services/sync_service.dart').readAsStringSync());
    // 3 EF invokes (BUG-C d3a1c7) + both restore entrypoints (BUG-G) = >= 5.
    expect('ensureFreshToken'.allMatches(src).length, greaterThanOrEqualTo(5),
        reason: 'restoreFromCloud + restoreFromCloudForUser must refresh up front');
  });
}
