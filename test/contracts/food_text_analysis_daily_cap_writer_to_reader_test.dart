// Writer -> reader contract for the SoT concept `food_text_analysis_daily_cap`
// (diagnose b8f4c2, 2026-09-04).
//
// WRITER: the Postgres trigger `enforce_food_text_daily_limit` — the only thing
//   that actually enforces the cap. Raises P0001 on the INSERT that would
//   exceed it.
// READERS: the Dart constant `AppConstants.freeAiTextLogsPerDay` and the three
//   client sites that meter against it.
//
// THE CONTRACT: writer and readers must agree on the FREE number. When they
// drift, the looser side wins silently and the tighter side becomes decorative
// — a caller reaching ai-proxy directly gets the server's number, not the one
// the app displays. That is exactly what happened: client 10, server 50, for
// four months, invisible in-app because the client blocks first.
//
// Third instance of this class. f1a70c (2026-06-07) was client 15 vs server 10
// on the CHAT cap; its fix shipped ai_message_limit_parity_test.dart to pin
// that ONE pair, and food text drifted the other way unpinned. The lesson is
// not "pin this number" — it is that a parity fix must pin every pair of the
// class. See also test/contracts/ai_message_limit_parity_test.dart, which holds
// the chat pair and the vision ceiling.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

void main() {
  group('food_text_analysis_daily_cap writer -> reader', () {
    late File migration;

    setUpAll(() {
      final m = latestMigrationDefining('enforce_food_text_daily_limit');
      expect(m, isNotNull,
          reason: 'No migration defines enforce_food_text_daily_limit. The '
              'trigger IS the writer for this concept — if it is gone, this '
              'contract has no enforcement at all.');
      migration = m!;
    });

    test('writer FREE arm == reader freeAiTextLogsPerDay', () {
      final caps = readProFreeCap(migration);
      expect(caps, isNotNull,
          reason: 'daily_cap CASE expression not found in '
              '${migration.uri.pathSegments.last}. If the trigger changed '
              'shape, update the matcher in test/helpers/migration_cap_reader '
              '— do NOT delete this assertion.');

      final clientFree = clientIntConstant('freeAiTextLogsPerDay');
      expect(clientFree, isNotNull,
          reason: 'freeAiTextLogsPerDay missing from app_constants.dart');

      expect(caps!.free, clientFree,
          reason: 'Server FREE food_text cap (${caps.free}, '
              '${migration.uri.pathSegments.last}) must equal '
              'AppConstants.freeAiTextLogsPerDay ($clientFree). They drifted '
              '50-vs-10 until b8f4c2 — a 5x server-side bypass reachable by '
              'calling ai-proxy directly. docs/architecture/business-rules.md:17 '
              '(the FREE-tier row) also says 10 — :36 is the PRO row and reads '
              'unlimited, so it was never evidence for this value.');
      expect(clientFree, 10,
          reason: 'Founder decision 2026-09-04: free food text = 10/day.');
    });

    test('writer PRO arm stays 200 — a decision, not drift', () {
      // The client reports 999999 ("unlimited") for PRO at
      // usage_counter_service.dart _limit(). That divergence is deliberate:
      // 200 food logs in one IST day is an abuse ceiling, not a product limit.
      // Pinned so nobody "fixes" it into agreement, and so nobody lowers it
      // without a decision.
      final caps = readProFreeCap(migration);
      expect(caps, isNotNull);
      expect(caps!.pro, 200,
          reason: 'PRO food_text ceiling is 200/day (founder decision '
              '2026-09-04). The client advertises unlimited; this is the '
              'abuse backstop behind that promise.');
    });

    test('ai-proxy 429 body reports the SAME caps the trigger enforces', () {
      // Added by the B-pass on b8f4c2's own commit. ai-proxy renders the 429
      // message from its own numbers, and they were an inline
      // `isProUser ? 200 : 50` literal — so after migration 127 lowered the
      // real free cap to 10, the error text kept telling users "50/day",
      // misinforming precisely the direct-API population the cap targets.
      // The first fix corrected the trigger and left this reader stale: the
      // instance fixed, the class open.
      final caps = readProFreeCap(migration);
      expect(caps, isNotNull);

      final src = stripDartComments(
          File('supabase/functions/ai-proxy/index.ts').readAsStringSync());

      final free =
          RegExp(r'FOOD_TEXT_FREE_DAILY_CAP\s*=\s*(\d+)').firstMatch(src);
      final pro =
          RegExp(r'FOOD_TEXT_PRO_DAILY_CAP\s*=\s*(\d+)').firstMatch(src);
      expect(free, isNotNull,
          reason: 'ai-proxy must name its food-text free cap as '
              'FOOD_TEXT_FREE_DAILY_CAP, not inline it — an unnamed literal is '
              'what drifted.');
      expect(pro, isNotNull,
          reason: 'ai-proxy must name its food-text PRO cap as '
              'FOOD_TEXT_PRO_DAILY_CAP.');

      expect(int.parse(free!.group(1)!), caps!.free,
          reason: 'ai-proxy FOOD_TEXT_FREE_DAILY_CAP must equal the live '
              'trigger FREE arm (${caps.free}, '
              '${migration.uri.pathSegments.last}). The 429 body is the only '
              'thing that tells a caller what the limit is.');
      expect(int.parse(pro!.group(1)!), caps.pro,
          reason: 'ai-proxy FOOD_TEXT_PRO_DAILY_CAP must equal the live '
              'trigger PRO arm (${caps.pro}).');

      // ASSOCIATION, not just membership. Round 2 of the ×2 review proved the
      // two assertions above are not enough: swapping the ternary's branches
      // (telling PRO users "10/day" and free users "200/day") left all 5 tests
      // GREEN, because both arms are still named constants holding the right
      // values — they are simply on the wrong sides. Checking that the right
      // numbers EXIST says nothing about which branch reads which.
      final ternary = RegExp(
        r'const cap = isProUser\s*\?\s*([A-Za-z0-9_]+)\s*:\s*([A-Za-z0-9_]+)\s*;',
      ).firstMatch(src);
      expect(ternary, isNotNull,
          reason: 'Could not find the `const cap = isProUser ? … : …;` ternary '
              'in ai-proxy. If it was restructured, re-point this assertion — '
              'do NOT delete it; without it a branch swap ships silently.');
      expect(ternary!.group(1), 'FOOD_TEXT_PRO_DAILY_CAP',
          reason: 'The TRUE branch of `isProUser ? … : …` must be the PRO cap. '
              'Found "${ternary.group(1)}". A swap tells paying users the free '
              'limit and free users the PRO limit.');
      expect(ternary.group(2), 'FOOD_TEXT_FREE_DAILY_CAP',
          reason: 'The FALSE branch must be the FREE cap. '
              'Found "${ternary.group(2)}".');

      // The exact pre-fix shape, kept as a redundant tripwire documenting the
      // historical defect. The association check above strictly subsumes it (a
      // numeric literal fails group-name equality), but this one names the
      // specific regression in its failure message.
      expect(RegExp(r'isProUser\s*\?\s*\d+\s*:\s*\d+').hasMatch(src), isFalse,
          reason: 'The food-text 429 cap must not be an inline numeric ternary '
              '— that literal is what went stale for four months.');
    });

    test('every client reader routes through the one constant', () {
      // Writer/reader drift is cheapest to prevent by keeping ONE reader
      // symbol. If a screen ever hardcodes 10, this contract stops covering it.
      const readers = [
        'lib/core/services/usage_counter_service.dart',
        'lib/features/nutrition/widgets/food_logger_section.dart',
        'lib/features/profile/screens/profile/subscription_section.dart',
      ];
      for (final path in readers) {
        final src = stripDartComments(File(path).readAsStringSync());
        expect(src.contains('freeAiTextLogsPerDay'), isTrue,
            reason: '$path must read the cap from '
                'AppConstants.freeAiTextLogsPerDay, never a literal.');
      }
    });

    test('the IST day boundary survives in the live definition', () {
      // Carried verbatim from migration 113; it is the fix for 7ad0d3 (UTC
      // midnight resets the cap at 05:30 IST, not midnight IST). A rewrite of
      // this trigger that drops it silently re-opens that bug.
      final body = stripSqlComments(migration.readAsStringSync());
      expect(body.contains("AT TIME ZONE 'Asia/Kolkata'"), isTrue,
          reason: 'The live ${migration.uri.pathSegments.last} must compute its '
              'day boundary in IST (7ad0d3). date_trunc in the session default '
              'timezone (UTC here) resets the cap at 05:30 IST.');
    });
  });
}
