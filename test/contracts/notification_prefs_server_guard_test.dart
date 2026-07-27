// test/contracts/notification_prefs_server_guard_test.dart
//
// Unit E — every user-controllable notification has a SERVER-side guard, and
// every guard reads preferences the way that actually works.
//
// WHY THE "WORKS" QUALIFIER IS THE POINT
// --------------------------------------
// A guard that reads preferences from a DATE-PINNED snapshot compiles, passes
// review, and does nothing. Measured live: 91 snapshot rows across 17 users,
// exactly ONE row dated today, only 3 users fresh within three days, stalest
// newest row two months old. A `.eq("snapshot_date", todayIST)` preference
// lookup therefore finds nothing for ~16 of 17 users and falls through to
// SEND — the toggle is inert while looking implemented.
//
// Two shipped functions had exactly that shape (`protein-gap-alert` pinned
// today, `morning-alert` pinned yesterday) and were counted as "already
// working" until round 3 measured them. This test exists so that cannot recur:
// preference reads go through the shared helper, which is latest-desc.
//
// Source-grep, deliberately: these are Deno/TypeScript Edge Functions with no
// Dart harness, so this follows the established `cron_auth_adoption_test.dart`
// convention. Comments are stripped first, per
// feedback_source_grep_strip_comments_first — every file here DISCUSSES the
// date-pinning trap in prose, and unstripped matching would flag the
// explanation as the defect.
//
// Run: flutter test test/contracts/notification_prefs_server_guard_test.dart

import 'dart:io';

import 'package:test/test.dart';

const _fnDir = 'supabase/functions';
const _helper = '$_fnDir/_shared/notification_prefs.ts';

/// notification key -> the Edge Function that must honour it.
const _guardOwner = <String, String>{
  'morning_checkin': 'morning-alert',
  'workout_reminders': 'workout-window-closing',
  'streak_alerts': 'streak-guardian',
  'weekly_recap': 'weekly-recap-ready',
  'subscription_reminders': 'expiry-reminder',
  'protein_alerts': 'protein-gap-alert',
  'plateau_alert': 'plateau-alert',
  'pr_celebration': 'pr-detection',
  'rank_promotion': 'proactive-coach-promotion',
  're_engagement': 're-engagement',
};

/// The six functions moved onto the shared helper by Unit E.
const _sharedHelperAdopters = <String>[
  'plateau-alert',
  'pr-detection',
  're-engagement',
  'proactive-coach-promotion',
  'protein-gap-alert',
  'morning-alert',
];

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

String _code(String fn) =>
    _strip(File('$_fnDir/$fn/index.ts').readAsStringSync());

void main() {
  group('Unit E — every notification key has a server-side guard', () {
    test('the shared helper exists and exports both entry points', () {
      final f = File(_helper);
      expect(f.existsSync(), isTrue, reason: '$_helper must exist');
      final src = f.readAsStringSync();
      expect(src, contains('export async function fetchNotificationPrefs'));
      expect(src, contains('export function isNotificationEnabled'));
    });

    test('the helper reads LATEST-desc, never a pinned snapshot_date', () {
      final src = _strip(File(_helper).readAsStringSync());
      expect(src, contains('.order("snapshot_date", { ascending: false })'),
          reason: 'the whole point — most-recent-known preferences, however '
              'old. Live, only 1 of 91 rows is dated today.');
      expect(src.contains('.eq("snapshot_date"'), isFalse,
          reason: 'a date pin here makes every guard in the app inert for the '
              'overwhelming majority of users.');
      expect(src, contains('.in("user_id"'),
          reason: 'batched — re-engagement already runs several queries per '
              'candidate; a per-user lookup would multiply round-trips.');
    });

    test('absent means SEND — only an explicit false silences a push', () {
      final src = _strip(File(_helper).readAsStringSync());
      expect(src, contains('.enabled !== false'),
          reason: 'decision N2. Any other comparison (=== true, truthiness) '
              'turns a sync gap, a fresh install or a malformed value into a '
              'silently disabled notification.');
    });

    test('each key is honoured by its owning function', () {
      // Two legitimate shapes, both in the tree today:
      //   helper-based   isNotificationEnabled(prefs, id, "streak_alerts")
      //   hand-rolled    prefs?.streak_alerts?.enabled === false
      // Matching only the quoted form flags the dot-access functions as
      // missing a guard they demonstrably have — checked before believing it.
      final missing = <String>[];
      _guardOwner.forEach((key, fn) {
        final src = _code(fn);
        final quoted = src.contains('"$key"') || src.contains("'$key'");
        final dotted = RegExp('[.?]\\s*$key\\b').hasMatch(src);
        if (!quoted && !dotted) missing.add('$key -> $fn');
      });
      expect(missing, isEmpty,
          reason: 'a key with no server guard is a decorative toggle: the UI '
              'says it is off, the push still arrives, and the user has no '
              'way to tell.\nMissing:\n  ${missing.join("\n  ")}');
    });

    test('the six Unit-E functions use the shared helper', () {
      final notAdopted = _sharedHelperAdopters
          .where((fn) => !_code(fn).contains('isNotificationEnabled('))
          .toList();
      expect(notAdopted, isEmpty,
          reason: 'hand-rolled preference reads are how the two date-pinned '
              'guards drifted in the first place. Adopt the helper.\n'
              'Not adopted: $notAdopted');
    });

    test('NO function reads notification_preferences off a date-pinned row',
        () {
      // The regression that made two shipped guards inert. A function may
      // still pin a date for CONTENT — that is correct, a protein-gap alert
      // needs today's intake — but it must not read PREFERENCES from that row.
      final offenders = <String>[];
      for (final fn in _guardOwner.values.toSet()) {
        final src = _code(fn);
        if (!src.contains('notification_preferences')) continue;
        // Reading the key straight off a snapshot object, rather than through
        // the helper, is the shape that used to be date-pinned.
        final handRolled =
            RegExp(r'\.notification_preferences').hasMatch(src) ||
                RegExp('\\[\\s*[\'"]notification_preferences[\'"]\\s*\\]')
                    .hasMatch(src);
        if (handRolled && !src.contains('isNotificationEnabled(')) {
          // Allowed only when the function's own snapshot read is latest-desc.
          final latestDesc =
              src.contains('.order("snapshot_date", { ascending: false })');
          if (!latestDesc) offenders.add(fn);
        }
      }
      expect(offenders, isEmpty,
          reason: 'these functions read preferences from a date-pinned '
              'snapshot, so their guard is inert for any user without a row '
              'for that exact date — most users.\nOffenders: $offenders');
    });
  });
}
