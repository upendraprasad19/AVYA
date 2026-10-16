// Contract for diagnose e3b9d7 — the PRO-only Sunday Brief shipped to everyone.
//
// THE BUG: `weekly-recap-ready` is the Sunday Brief cron, a PRO deliverable. It
// had NO subscription check of ANY kind. `last_active_at >= cutoff` was its
// only eligibility filter, so every active free or lapsed user received a paid
// -tier push. Confirmed live 2026-08-07 on the founder's own account — PRO
// ended 2026-07-05 and it was still arriving.
//
// THE FIX: the same shared `fetchProUserIds` helper morning-alert /
// plateau-alert / protein-gap-alert already use. Three properties matter, and
// each has its own failure mode:
//
//   1. THE PREDICATE. `status='active' AND end_date > now()` — NOT the stale
//      denormalized `users.subscription_status`, and not `status` alone. A
//      lapsed row keeps `status='active'` until something rewrites it; that is
//      why the founder still qualified 33 days after expiry.
//   2. FETCHED ONCE, OUTSIDE the page loop. It is a full-table set, not a
//      per-page one. Inside the loop it would re-query per page for identical
//      data.
//   3. FILTERED BEFORE the concurrency loop, while pagination bookkeeping stays
//      on the RAW page. `.range()` walked the raw page — advancing the offset
//      by the filtered count would skip users.
//
// Deno source, not runnable under `flutter test` — source-grep contract
// (presence + ORDERING). Its SoT entry carries `presence_only: true` for that
// reason rather than a fabricated behavioral_test_path. Comments stripped first
// per feedback_source_grep_strip_comments_first.md: the fix's own comment names
// `users.subscription_status` as the thing NOT to use, and an un-stripped grep
// would match that explanation.
//
// Run: flutter test test/contracts/weekly_recap_pro_filter_test.dart

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//[^\n]*'), '');

void main() {
  late String src;
  late String raw;
  late String shared; // _shared/subscription.ts — the predicate itself

  setUpAll(() {
    raw = File('supabase/functions/weekly-recap-ready/index.ts')
        .readAsStringSync();
    src = _strip(raw);
    shared =
        _strip(File('supabase/functions/_shared/subscription.ts').readAsStringSync());
  });

  group('the gate exists at all', () {
    test('fetchProUserIds is imported from the SHARED helper', () {
      expect(
        RegExp(r'''import\s*\{[^}]*fetchProUserIds[^}]*\}\s*from\s*['"]\.\./_shared/subscription\.ts['"]''')
            .hasMatch(src),
        isTrue,
        reason: 'a locally re-implemented predicate is how these drift apart; '
            'use the one morning-alert/plateau-alert already share.',
      );
    });

    test('THE BUG: a PRO set is actually computed and consulted', () {
      expect(src.contains('fetchProUserIds('), isTrue);
      expect(
        RegExp(r'proUserIds\.has\(').hasMatch(src),
        isTrue,
        reason: 'importing it without filtering on it would still send to '
            'everybody — the founder\'s exact symptom.',
      );
    });
  });

  group('the predicate is the CANONICAL one', () {
    test('shared helper checks BOTH status active AND end_date > now', () {
      // Verified in the helper, not here, because that is where the predicate
      // actually lives — asserting it in this file would pin a copy.
      expect(shared.contains("'active'") || shared.contains('"active"'), isTrue);
      expect(
        RegExp(r'end_date').hasMatch(shared),
        isTrue,
        reason: "status='active' alone is NOT PRO — a lapsed row keeps it. "
            'That is why the founder still qualified 33 days after expiry.',
      );
    });

    test('this function does not read the stale denormalized column', () {
      expect(
        src.contains('subscription_status'),
        isFalse,
        reason: 'users.subscription_status is a denormalized mirror and goes '
            'stale; the subscriptions table is the source of truth.',
      );
    });
  });

  group('ordering — where the filter sits is the contract', () {
    // These are the assertions that would catch a "fix" that imports the
    // helper but wires it in the wrong place.

    test('fetched ONCE before the page loop, not per page', () {
      final fetchIdx = src.indexOf('await fetchProUserIds(');
      final loopIdx = src.indexOf('while (');
      expect(fetchIdx, greaterThan(-1));
      expect(loopIdx, greaterThan(-1));
      expect(
        fetchIdx < loopIdx,
        isTrue,
        reason: 'it is a full-table set, not a per-page one — inside the loop '
            'it re-queries identical data every page.',
      );
    });

    test('the concurrency loop iterates proUsers, NOT the raw page', () {
      expect(
        RegExp(r'for\s*\(\s*let\s+i\s*=\s*0;\s*i\s*<\s*proUsers\.length')
            .hasMatch(src),
        isTrue,
        reason: 'the send loop is the last place the filter can be lost.',
      );
      expect(
        RegExp(r'for\s*\(\s*let\s+i\s*=\s*0;\s*i\s*<\s*users\.length')
            .hasMatch(src),
        isFalse,
        reason: 'iterating the raw page here re-sends to free users.',
      );
      expect(src.contains('proUsers.slice(i, i + CONCURRENCY)'), isTrue);
    });

    test('pagination bookkeeping stays on the RAW page count', () {
      // The subtle one. `.range()` walked the raw page; advancing `offset` by
      // the FILTERED count would skip users on every page with a non-PRO in it.
      expect(
        RegExp(r'totalUsers\s*\+=\s*users\.length').hasMatch(src),
        isTrue,
        reason: 'offset arithmetic must track what .range() actually walked.',
      );
      expect(
        RegExp(r'totalUsers\s*\+=\s*proUsers\.length').hasMatch(src),
        isFalse,
      );
      expect(src.contains('offset += PAGE_SIZE'), isTrue);
    });

    test('an all-free page advances the offset instead of stalling', () {
      expect(
        RegExp(r'if\s*\(\s*proUsers\.length\s*===\s*0\s*\)\s*\{\s*'
                r'offset\s*\+=\s*PAGE_SIZE;\s*continue;')
            .hasMatch(src),
        isTrue,
        reason: 'skipping the page without advancing would loop forever.',
      );
    });

    test('filtered-out users are counted, and NOT as a preference opt-out', () {
      // B-pass finding 4: entitlement misses and preference opt-outs must not
      // share a counter. `skipped` feeds the response field
      // `skipped_by_preference`; folding non-PRO users into it would make that
      // number read as "N people disabled this" when most of N were never PRO.
      expect(
        RegExp(r'skippedNotPro\s*\+=\s*users\.length\s*-\s*proUsers\.length')
            .hasMatch(src),
        isTrue,
        reason: 'a cron that silently drops recipients reports a clean run '
            'while doing nothing — count them.',
      );
      expect(
        RegExp(r'skipped\s*\+=\s*users\.length\s*-\s*proUsers\.length')
            .hasMatch(src),
        isFalse,
        reason: 'entitlement misses must NOT land in the preference counter.',
      );
      expect(
        src.contains('skipped_not_pro:'),
        isTrue,
        reason: 'and the split must actually reach the response body.',
      );
    });
  });

  test('fail-safe direction: empty set sends to NOBODY, never everybody', () {
    // Asserted where the behaviour lives. fetchProUserIds returns an empty set
    // on error and never throws, so a lookup failure withholds a paid-tier
    // push rather than blasting it to the whole free base.
    expect(
      RegExp(r'catch').hasMatch(shared),
      isTrue,
      reason: 'the helper must swallow its own failure and return empty.',
    );
    expect(
      RegExp(r'if\s*\(\s*proUsers\.length\s*===\s*0\s*\)').hasMatch(src),
      isTrue,
      reason: 'and the caller must treat empty as "send none".',
    );
  });

  test('the fix is attributed in-source for the next reader', () {
    expect(raw.contains('e3b9d7'), isTrue);
  });
}
