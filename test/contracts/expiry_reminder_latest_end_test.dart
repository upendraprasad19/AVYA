// OI-202 / Hermes L1 (2026-09-29) — expiry-reminder must remind a user only when
// their LATEST active subscription ends inside the 3-day window. Selecting every
// active row in the window pushed "PRO plan expiring soon" to users who had
// already renewed (an older row lapsing + a later row). The reduction itself is
// behaviourally tested in supabase/functions/_shared/subscription_test.ts (a
// renewed user is not reported); this file pins that expiry-reminder USES it
// and that a failed read cannot read as "nobody is expiring".
//
// PRESENCE ONLY: index.ts calls serve() at import, so it has no test seam.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  final src =
      _strip(File('supabase/functions/expiry-reminder/index.ts').readAsStringSync());

  test('reads the latest end per user, not every active row in the window', () {
    expect(src.contains('fetchLatestActiveEndByUser('), isTrue);
    expect(src.contains('usersWithLatestEndIn('), isTrue);
    expect(RegExp(r'\.from\(\s*"subscriptions"\s*\)').hasMatch(src), isFalse,
        reason: 'a direct per-row subscriptions select re-opens the renewed-user push');
  });

  test('a null (failed) read throws instead of exiting healthy', () {
    expect(
      RegExp(r'latestEnd === null\)\s*throw new Error').hasMatch(src),
      isTrue,
    );
  });
}
