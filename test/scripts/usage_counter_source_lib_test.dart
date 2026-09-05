// Tests for scripts/usage_counter_source_lib.dart — the predicate behind
// scripts/check_usage_counter_source.dart (OI-162 slice 1).
//
// Rule 24: a gate ships mutation-proven. Each red-path test below names the
// mutation it defends against, so the ledger's `evidence:` can be checked
// against something concrete rather than taken on trust.
//
// No subprocess is spawned, so no @Timeout is needed (CLAUDE.md §4.9's class is
// "spawns a subprocess", not "is a test under test/scripts/").

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/usage_counter_source_lib.dart';

/// The real quota shape: a `count: "exact"` read pinned to one channel.
const _quotaCounter = '''
    const { count, error } = await client
      .from("ai_coach_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("channel", "free_image_analysis");
''';

/// The real PRUNE shape from rolling-context — same count, `.neq` filter.
/// Legitimate, and must never be flagged.
const _pruneCounter = '''
    const { count } = await supabase
      .from("ai_coach_interactions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .neq("channel", "app_event");
''';

void main() {
  group('check_usage_counter_source — Edge Function detection', () {
    test('flags a quota counter', () {
      final sites = findEdgeFunctionCounterSites('f.ts', _quotaCounter);
      expect(sites, hasLength(1));
    });

    test('does NOT flag rolling-context\'s .neq prune count', () {
      // MUTATION: widen the quota filter to include `neq` and this reddens.
      // The two rolling-context sites are prune-eligibility counts across ALL
      // channels, not quotas. An allowlist that has to excuse legitimate code
      // teaches people to add entries, so the matcher excludes them instead.
      final sites = findEdgeFunctionCounterSites('rolling.ts', _pruneCounter);
      expect(sites, isEmpty);
    });

    test('does NOT flag a commented-out counter', () {
      // MUTATION: drop comment stripping and this reddens.
      final commented =
          _quotaCounter.split('\n').map((l) => '// $l').join('\n');
      final sites = findEdgeFunctionCounterSites('f.ts', commented);
      expect(sites, isEmpty);
    });

    test('reports REAL file line numbers when a block comment precedes', () {
      // MUTATION: make the block-comment strip collapse newlines instead of
      // preserving them, and this reddens.
      //
      // This is not hypothetical: the first derivation of this gate's baseline
      // collapsed block comments and reported stripped-source lines, off by up
      // to 25 and entirely plausible-looking.
      const src = '/*\n\n\n\n\n*/\n$_quotaCounter'; // 6 lines of comment
      final sites = findEdgeFunctionCounterSites('f.ts', src);
      expect(sites, hasLength(1));
      // comment occupies lines 1-6; the query starts at 7, count:"exact" on 9.
      expect(sites.single.line, 9);
    });

    test('a filter further than the window does not match', () {
      final spread = '''
      .select("id", { count: "exact", head: true })
      .eq("a", 1)
      .eq("b", 2)
      .eq("c", 3)
      .eq("d", 4)
      .eq("e", 5)
      .eq("f", 6)
      .eq("channel", "x");
''';
      expect(findEdgeFunctionCounterSites('f.ts', spread), isEmpty);
    });
  });

  group('check_usage_counter_source — allowlist enforcement', () {
    test('a NEW file holding a quota counter is a violation', () {
      // RED PATH. MUTATION: delete the `allowed == null` branch and this reddens.
      final r = sweep(
        efSources: {'supabase/functions/brand-new/index.ts': _quotaCounter},
        migrationSources: const {},
      );
      expect(r.violations, isNotEmpty);
      expect(r.violations.single, contains('brand-new'));
    });

    test('an EXTRA counter inside an allowlisted file is a violation', () {
      // RED PATH. MUTATION: drop the `count > allowed` branch and this reddens.
      // "This file already had one" is exactly how a tenth counter gets added.
      final r = sweep(
        efSources: {
          'supabase/functions/weekly-report/index.ts':
              '$_quotaCounter\n$_quotaCounter',
        },
        migrationSources: const {},
      );
      expect(r.violations, isNotEmpty);
      expect(r.violations.single, contains('holds 2'));
    });

    test('the allowlisted count exactly is clean', () {
      final r = sweep(
        efSources: {
          'supabase/functions/weekly-report/index.ts': _quotaCounter,
        },
        migrationSources: const {},
      );
      expect(r.violations, isEmpty);
      expect(r.isClean, isTrue);
    });
  });

  group('check_usage_counter_source — migrations', () {
    const counting =
        'SELECT count(*) INTO n FROM ai_coach_interactions WHERE user_id = x;';

    test('a NEW migration counting interactions is a violation', () {
      // RED PATH. MUTATION: drop the allowlist membership test and this reddens.
      final r = sweep(
        efSources: const {},
        migrationSources: {'128_usage_counters.sql': counting},
      );
      expect(r.violations, isNotEmpty);
      expect(r.violations.single, contains('128_usage_counters.sql'));
    });

    test('an allowlisted migration is not a violation', () {
      final r = sweep(
        efSources: const {},
        migrationSources: {'127_food_text_free_cap_parity_10.sql': counting},
      );
      expect(r.violations, isEmpty);
      expect(r.offendingMigrations, contains('127_food_text_free_cap_parity_10.sql'));
    });

    test('a commented-out count in a new migration is not a violation', () {
      // MUTATION: drop SQL comment stripping and this reddens.
      final r = sweep(
        efSources: const {},
        migrationSources: {'128_usage_counters.sql': '-- $counting'},
      );
      expect(r.violations, isEmpty);
    });

    test('the real rule: a new migration must target usage_counters instead', () {
      final r = sweep(
        efSources: const {},
        migrationSources: {
          '128_usage_counters.sql':
              'SELECT count(*) INTO n FROM usage_counters WHERE user_id = x;',
        },
      );
      expect(r.violations, isEmpty);
    });
  });
}
