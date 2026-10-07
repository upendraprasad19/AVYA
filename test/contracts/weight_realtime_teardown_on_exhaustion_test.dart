// Regression contract for bug a3d7e2 (Obs#8, 2026-06-13 live web E2E): the PRO
// weight_logs realtime channel spammed channelError on a backgrounded web tab —
// the bounded reconnect (attempt < 2) gave up but left the dead channel attached,
// so the Supabase client kept auto-reconnecting + re-firing the error. The
// onError path now tears the channel down (unsubscribeRealtime) on exhaustion.
// Source-grep, comment-stripped. (Cloud publication + RLS are live-verified
// correct — see the diagnose-doc — so this is NOT a §2.23 missing-publication case.)

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
  test('a3d7e2 — realtime onError tears the channel down on reconnect exhaustion',
      () {
    final src = _strip(
        File('lib/core/services/sync/sync_realtime.dart').readAsStringSync());

    // The bounded reconnect guard must still exist...
    final guardIdx = src.indexOf('attempt < 2');
    expect(guardIdx, isNot(-1), reason: 'the bounded reconnect guard must remain');

    // ...and within the same onError block (proximity), the exhausted path must
    // call unsubscribeRealtime() to stop the Supabase client auto-reconnecting.
    final window = src.substring(
        guardIdx, guardIdx + 500 > src.length ? src.length : guardIdx + 500);
    expect(window.contains('unsubscribeRealtime()'), isTrue,
        reason:
            'on reconnect-budget exhaustion the channel must be torn down '
            '(unsubscribeRealtime) so the WS stops auto-reconnecting + spamming '
            'channelError — Obs#8');
  });
}
