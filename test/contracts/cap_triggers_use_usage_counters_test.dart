// OI-162 slice 2 — the three Postgres cap triggers read `usage_counters` via
// `consume_quota()`, not `count(*)` over `ai_coach_interactions`.
//
// WHY: `ai_coach_interactions` is a conversation LOG that `rolling-context`
// prunes nightly (MESSAGE_THRESHOLD=50, KEEP_RECENT=10). Any quota derived from
// its row count silently resets when a user chats enough. Slice 1 built the
// ledger; this slice makes the triggers its first three callers.
//
// SCOPE OF THIS FILE — presence only, deliberately. These are source greps over
// migration 129. They prove the trigger bodies SAY the right thing; they cannot
// prove live Postgres BEHAVES that way. The behavioural half lives in
// `test/sql/oi46_daily_cap_triggers_live_verify.sql` (the `slice2_*` labels),
// which runs real INSERTs inside a BEGIN/ROLLBACK via
// `dart run scripts/check_onconflict_live_arbiter.dart --sql <file>`.
// Saying so explicitly because rule 21 is emphatic that a source-grep counts
// for PRESENCE only, and this file would otherwise read as more than it is.
//
// OI-153 (2026-09-12) REPOINT: this file used to assert that all three
// triggers resolve to the SAME migration (129) — a proxy for "none was left
// behind on a pre-129 count(*) body". Migration 132 redefines ONLY the vision
// trigger (a NULL-channel guard), so "same file" stopped being true while the
// property it stood for still holds. Each trigger is now resolved to its OWN
// latest definer and required to be ≥ 129; the backfill assertion is pinned
// to 129 BY NAME, because the backfill is a one-time event that lives there
// whatever is redefined later. Review round 2 found this; without it every
// test in this file would have errored in `setUpAll` the moment 132 existed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/migration_cap_reader.dart';

/// The three trigger functions this slice moves, with the quota_key each must
/// consume and the P0001 identifier `ai-proxy` greps to map a refusal to a 429.
const _triggers = <String, ({String quotaKey, String p0001})>{
  'enforce_chat_app_daily_limit': (
    quotaKey: 'chat_app',
    p0001: 'chat_app_daily_limit_reached',
  ),
  'enforce_vision_analysis_daily_limit': (
    quotaKey: 'vision_analysis',
    p0001: 'vision_analysis_daily_limit_reached',
  ),
  'enforce_food_text_daily_limit': (
    quotaKey: 'food_text',
    p0001: 'food_text_daily_limit_reached',
  ),
};

/// Channels the three triggers gate. A `lib/` insert of any of these would be
/// refused `42501` post-slice-2, because `consume_quota` is INVOKER-mode and
/// `usage_counters` is RLS-with-no-policy — only service_role/postgres may
/// write it. Closed set of four; that is what makes the guard below checkable.
const _gatedChannels = <String>[
  'app',
  'scan_meal',
  'cart_auditor',
  'food_text_analysis',
];

void main() {
  group('OI-162 slice 2 — cap triggers consume usage_counters', () {
    /// The migration that carried the one-time backfill of the current IST
    /// window. Pinned by NAME (see the header): later migrations may redefine
    /// a trigger, but the backfill happened exactly once, here.
    final backfillMigration =
        File('supabase/migrations/129_cap_triggers_use_usage_counters.sql');
    late Map<String, File> definerOf;
    late Map<String, String> blocks;

    setUpAll(() {
      definerOf = {};
      for (final name in _triggers.keys) {
        final f = latestMigrationDefining(name);
        expect(f, isNotNull, reason: 'no migration defines $name');
        // Every trigger's LIVE definition must be 129 or LATER — none may be
        // left behind on its old count(*) body. `latestMigrationDefining`
        // returns the highest-numbered definer, so a trigger whose last
        // definition predates 129 is exactly the regression this catches.
        final n = migrationNumber(f!.uri.pathSegments.last);
        expect(n, greaterThanOrEqualTo(129),
            reason: '$name resolves to migration $n — a pre-ledger body');
        definerOf[name] = f;
      }
      blocks = {
        for (final name in _triggers.keys)
          name: functionBlock(definerOf[name]!.readAsStringSync(), name)!,
      };
    });

    test('every trigger calls consume_quota with its own quota_key', () {
      for (final entry in _triggers.entries) {
        final block = blocks[entry.key]!;
        expect(block, contains('consume_quota'),
            reason: '${entry.key} must delegate to the ledger');
        expect(block, contains("'${entry.value.quotaKey}'"),
            reason: '${entry.key} must consume quota_key '
                '${entry.value.quotaKey}');
      }
    });

    test('no trigger still counts ai_coach_interactions rows', () {
      for (final entry in _triggers.entries) {
        final block = blocks[entry.key]!;
        expect(block.contains('ai_coach_interactions'), isFalse,
            reason: '${entry.key} still reads the prunable log — that IS the '
                'bug this slice exists to fix');
        expect(block.contains('count(*)'), isFalse,
            reason: '${entry.key} still uses a count(*) ceiling');
      }
    });

    test('the three P0001 identifiers ai-proxy greps survive verbatim', () {
      // ai-proxy maps a refusal to a 429 with a plain msg.includes() at
      // index.ts:338 / :524 / :765. Change one and every capped request
      // silently becomes a 500 — no test would fail but for this one.
      for (final entry in _triggers.entries) {
        expect(blocks[entry.key]!, contains(entry.value.p0001),
            reason: 'ai-proxy greps ${entry.value.p0001} verbatim');
      }
    });

    test('every trigger anchors its window to the IST day boundary', () {
      // The fix for 7ad0d3. Migration 026's date_trunc('day', now()) truncates
      // in the session timezone (UTC here) and so resets at 05:30 IST.
      const ist =
          "date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'";
      for (final name in _triggers.keys) {
        expect(blocks[name]!, contains(ist),
            reason: '$name must use the IST day boundary');
        expect(blocks[name]!.contains("date_trunc('day', now())"), isFalse,
            reason: '$name must not use the bare UTC-anchored form');
      }
    });

    test('each channel short-circuit precedes the consume_quota call', () {
      // Load-bearing, not stylistic: the short-circuit is what keeps a
      // non-gated writer (including the two client-side ones) from ever
      // reaching consume_quota and being refused 42501.
      for (final name in _triggers.keys) {
        final block = blocks[name]!;
        final guard = block.indexOf('NEW.channel');
        final consume = block.indexOf('consume_quota');
        expect(guard, greaterThanOrEqualTo(0), reason: '$name has no channel guard');
        expect(consume, greaterThan(guard),
            reason: '$name calls consume_quota BEFORE its channel '
                'short-circuit — an ungated insert would consume a unit');
      }
    });

    test('chat exempts PRO before it consumes anything', () {
      final block = blocks['enforce_chat_app_daily_limit']!;
      final proReturn = block.indexOf('IF is_pro THEN');
      final consume = block.indexOf('consume_quota');
      expect(proReturn, greaterThanOrEqualTo(0));
      expect(consume, greaterThan(proReturn),
          reason: 'PRO must return before consuming — a PRO user has no cap '
              'and must not burn a ledger unit');
    });

    test('the current IST window is backfilled before the triggers switch', () {
      // Without this, swapping the source hands every user a fresh allowance
      // for the current window.
      final sql = backfillMigration.readAsStringSync();
      final backfill = sql.indexOf('INSERT INTO public.usage_counters');
      final firstReplace = sql.indexOf('CREATE OR REPLACE FUNCTION');
      expect(backfill, greaterThanOrEqualTo(0), reason: 'no backfill present');
      expect(backfill, lessThan(firstReplace),
          reason: 'the backfill must run BEFORE the trigger bodies switch');
      for (final entry in _triggers.entries) {
        expect(sql, contains("'${entry.value.quotaKey}',"),
            reason: 'no backfill for quota_key ${entry.value.quotaKey}');
      }
    });

    group('the landmine guard', () {
      // consume_quota is INVOKER-mode and usage_counters is RLS-with-no-policy,
      // so an `authenticated` client inserting a GATED channel gets 42501 and
      // its write FAILS — a hard error, not a degraded cap. Every gated writer
      // must therefore be a service-role Edge Function.
      //
      // ⚠ MULTILINE BY NECESSITY. These writers span two lines:
      //     .from("ai_coach_interactions")
      //     .insert({
      // A line-oriented scan cannot see both halves. `app_events_service.dart`
      // uses exactly that shape, so a single-line guard would be blind to the
      // very writer class it exists to catch — and a single-line scan of the
      // Edge Functions misses ai-proxy:321/510/751 too (6 hits vs 14).

      /// Every `.from('ai_coach_interactions') … .insert(/.upsert(` chain in a
      /// tree, with the text of the call that follows, matched ACROSS lines.
      List<String> writerCalls(String dir) {
        final re = RegExp(
          r'''from\(\s*['"]ai_coach_interactions['"]\s*\)[\s\S]{0,80}?\.(?:insert|upsert)\(([\s\S]{0,400})''',
        );
        final out = <String>[];
        for (final f in Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) =>
                f.path.endsWith('.dart') || f.path.endsWith('.ts'))) {
          for (final m in re.allMatches(f.readAsStringSync())) {
            out.add('${f.path}||${m.group(1)}');
          }
        }
        return out;
      }

      test('the multiline matcher actually sees a two-line writer', () {
        // A POSITIVE CONTROL, and the reason this test exists at all: the
        // previous single-line form returned a partial result that read exactly
        // like a complete one. Never publish a verification without one.
        final calls = writerCalls('lib');
        expect(
          calls.any((c) => c.contains('app_events_service.dart')),
          isTrue,
          reason: 'the matcher missed app_events_service.dart, which uses the '
              'two-line .from(...)\\n.insert(...) shape — it is single-line '
              'blind and proves nothing',
        );
        expect(
          calls.any((c) => c.contains('sync_coach.dart')),
          isTrue,
          reason: 'the matcher missed sync_coach.dart',
        );
      });

      test('no lib/ code inserts a GATED channel', () {
        // ⚠ FAIL-CLOSED ON INDIRECTION. The first version matched only a
        // QUOTED LITERAL after `channel:` — and `app_events_service.dart:63`
        // writes `'channel': _channel`, resolved from a `static const` 35
        // lines above. So the guard was structurally blind to a constant, in
        // one of its own positive-control files, live today. A source grep is
        // bounded by what its author pictured someone writing; the fix is not
        // a cleverer regex but to REFUSE to pass on anything it cannot read.
        final offenders = <String>[];
        final unresolved = <String>[];

        for (final call in writerCalls('lib')) {
          final parts = call.split('||');
          final path = parts[0];
          final body = parts[1];
          final m =
              RegExp('''['"]?channel['"]?\\s*:\\s*([^,\\n}]+)''').firstMatch(body);
          if (m == null) continue; // no channel key in this insert at all
          var value = m.group(1)!.trim();

          // Literal? Compare directly.
          final lit = RegExp(r'''^['"]([^'"]*)['"]$''').firstMatch(value);
          if (lit != null) {
            final channel = lit.group(1)!;
            if (_gatedChannels.contains(channel)) {
              offenders.add('$path writes gated channel "$channel"');
            }
            continue;
          }

          // Identifier? Resolve a same-file `const <name> = '<literal>'`.
          final ident = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
          if (ident) {
            final src = File(path).readAsStringSync();
            final decl = RegExp(
              '''const\\s+(?:String\\s+)?$value\\s*=\\s*['"]([^'"]*)['"]''',
            ).firstMatch(src);
            if (decl != null) {
              final channel = decl.group(1)!;
              if (_gatedChannels.contains(channel)) {
                offenders.add(
                    '$path writes gated channel "$channel" via const $value');
              }
              continue;
            }
          }
          unresolved.add('$path -> channel: $value');
        }

        expect(
          offenders,
          isEmpty,
          reason: 'a client-side (authenticated) insert of a gated channel is '
              'refused 42501 by usage_counters RLS and the user\'s write '
              'FAILS. Route it through a service-role Edge Function.\n'
              '${offenders.join('\n')}',
        );
        expect(
          unresolved,
          isEmpty,
          reason: 'this guard could not statically resolve a channel value, so '
              'it cannot prove the write is safe. Resolve it by hand, then '
              'either inline the literal or teach this test the new shape — do '
              'NOT loosen the assertion.\n${unresolved.join('\n')}',
        );
      });

      test('the known client writers are still the ungated two', () {
        // An absence assertion nobody counted is worthless, so name the set.
        // If a third client writer appears, this fails and someone checks its
        // channel deliberately rather than trusting a green "no offenders".
        final files = writerCalls('lib')
            .map((c) => c.split('||')[0].replaceAll(r'\', '/'))
            .map((p) => p.split('/').last)
            .toSet();
        expect(
          files,
          {'sync_coach.dart', 'app_events_service.dart'},
          reason: 'the set of client-side ai_coach_interactions writers '
              'changed. Confirm the new one writes a NON-gated channel, then '
              'update this set.',
        );
      });
    });
  });
}
