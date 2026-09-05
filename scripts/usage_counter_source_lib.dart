// scripts/usage_counter_source_lib.dart
//
// Pure detection logic for the usage-counter source gate (OI-162 slice 1).
// The CLI entry point (check_usage_counter_source.dart) delegates to this so the
// predicate is testable without spawning a subprocess.
//
// WHAT IT GUARDS
// --------------
// `ai_coach_interactions` is a conversation LOG that also serves as a usage
// LEDGER: nine sites derive a quota from a row count on it. `rolling-context`
// prunes that table nightly (keeps the newest 10 once a user passes 50), so
// every one of those quotas is resettable — which is the whole of OI-162.
//
// Slice 1 introduces `usage_counters` + `consume_quota()` as the replacement.
// This gate exists so that while the nine call sites are migrated one slice at a
// time, NOBODY ADDS A TENTH. Per CLAUDE.md §4.11 it ships in an earlier commit
// than the refactor it protects.
//
// THE MATCHER IS STRUCTURAL, NOT VOCABULARY
// -----------------------------------------
// An earlier draft matched words like `rate_limit` / `quota`. Measured against
// the real tree that fired on two COMMENTS (`ai-proxy:266`, `:729`) and missed
// three real counters. The shape below — a `count: "exact"` read whose filter
// pins a specific `channel` — returns exactly the real quota sites and nothing
// else.
//
// ⚠ `.neq("channel", …)` is DELIBERATELY NOT a match. `rolling-context:218,254`
// use that shape to count prune-eligible rows across all channels; they are not
// quotas and must not be allowlisted as though they were. Matching `.eq`/`.in`
// only is what keeps the allowlist honest — an allowlist that has to excuse
// legitimate code teaches people to add entries.
//
// ⚠ COMMENTS ARE STRIPPED LINE-PRESERVINGLY. Block comments are replaced by the
// same number of newlines rather than removed, so reported line numbers are REAL
// file lines. The first version of this derivation collapsed them and reported
// stripped-source lines — off by up to 25 and silently plausible.

/// One flagged site.
class CounterSite {
  final String path;
  final int line;
  final String detail;
  const CounterSite(this.path, this.line, this.detail);

  @override
  String toString() => '$path:$line — $detail';
}

/// Replaces block comments with an equal number of newlines and blanks out
/// `//` line comments, so line numbers are preserved exactly.
String stripDartLikeCommentsPreservingLines(String src) {
  final noBlock = src.replaceAllMapped(
    RegExp(r'/\*.*?\*/', dotAll: true),
    (m) => '\n' * '\n'.allMatches(m.group(0)!).length,
  );
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('//');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

/// Blanks out SQL comments, preserving line count.
///
/// ⚠ Handles BOTH `--` and `/* … */`. The block form was missing until
/// 2026-09-05 (B-pass on `004af467`), so a count sitting inside a block comment
/// was read as live code and reported as a violation — a false positive, and
/// the kind that trains people to distrust the gate. Newlines inside a block
/// comment are preserved so every other line number stays correct.
String stripSqlCommentsPreservingLines(String src) {
  final noBlock = src.replaceAllMapped(
    RegExp(r'/\*[\s\S]*?\*/'),
    (m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
  );
  return noBlock
      .split('\n')
      .map((l) {
        final i = l.indexOf('--');
        return i >= 0 ? l.substring(0, i) : l;
      })
      .join('\n');
}

/// How many lines after a `count: "exact"` to look for the channel filter.
/// 6 covers every real site (the filters are chained immediately after) without
/// reaching into an unrelated adjacent query.
const int channelFilterWindow = 6;

/// Edge Function quota-counter sites in [source] (already a whole file body).
///
/// Matches a `count: "exact"` read whose next few lines pin a channel with
/// `.eq(` or `.in(` — the quota shape. `.neq(` is excluded by design.
List<CounterSite> findEdgeFunctionCounterSites(String path, String source) {
  final src = stripDartLikeCommentsPreservingLines(source);
  final lines = src.split('\n');
  final out = <CounterSite>[];
  final quotaFilter = RegExp(r'''\.(eq|in)\(\s*["']channel''');
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains('count: "exact"')) continue;
    final end = (i + channelFilterWindow) < lines.length
        ? i + channelFilterWindow
        : lines.length;
    final window = lines.sublist(i, end).join('\n');
    if (quotaFilter.hasMatch(window)) {
      out.add(CounterSite(path, i + 1,
          'count:"exact" read filtered to a specific channel — a quota derived '
          'from ai_coach_interactions rows'));
    }
  }
  return out;
}

/// True if [source] (a migration body) derives a count from
/// `ai_coach_interactions`.
///
/// ⚠ **A one-time ledger BACKFILL is handled by the allowlist below, NOT by a
/// pattern exemption here — and that is a deliberate reversal.** Migration 129
/// legitimately reads `count(*) FROM ai_coach_interactions` three times, once
/// per quota_key, to seed `usage_counters` for the current window; without it,
/// swapping the source hands every user a fresh allowance.
///
/// The first attempt at this exempted any count sitting inside a statement that
/// INSERTs into `usage_counters`. The B-pass defeated it three ways in one
/// sitting: a real quota read hidden behind a no-op `INSERT INTO
/// usage_counters` in a data-modifying CTE; a `/* */` block comment (which the
/// stripper did not remove); and a legitimate CTE-first backfill that the
/// heuristic wrongly FLAGGED, because the count precedes the INSERT in the
/// statement text.
///
/// The lesson is the one the code-review skill already states: **when a guard
/// is a source grep, tightening the pattern never converges.** An enumerated,
/// grep-auditable allowlist does converge — a future backfill has to be added
/// BY NAME, which forces a human to look at it exactly once. That is the same
/// trade `check_no_deferral_euphemism.dart` makes with its visible `deu-quote`
/// marker, and the same one rule 24 makes with `grandfathered:`.
bool migrationCountsInteractions(String source) {
  final src = stripSqlCommentsPreservingLines(source);
  return RegExp(
    r'count\(\s*\*\s*\)[\s\S]{0,120}?from\s+(public\.)?ai_coach_interactions',
    caseSensitive: false,
  ).hasMatch(src);
}

/// Edge Function files permitted to hold quota counters today, with the exact
/// number each may hold. A count INCREASE inside an allowed file is still a
/// violation — the allowlist is per-site, not per-file, because "this file
/// already had one" is how a tenth gets added.
///
/// Re-derive rather than trusting these numbers:
///   dart run scripts/check_usage_counter_source.dart --list
const Map<String, int> allowedEdgeFunctionSites = {
  'supabase/functions/ai-media-proxy/index.ts': 2, // free-image lifetime + pro-image IST day
  'supabase/functions/delete-account/index.ts': 1, // 5 attempts / 60 min
  'supabase/functions/verify-payment/index.ts': 1, // 20 attempts / 10 min
  'supabase/functions/weekly-report/index.ts': 1, // first-free-report lifetime
};

/// Migrations that already contain a `count(*) FROM ai_coach_interactions`.
///
/// ENUMERATED BY NAME AND PERMANENT — an applied migration is immutable
/// (`supabase/migrations/CLAUDE.md`), including its comments, so these can never
/// be edited to satisfy the gate. That makes an enumerated exemption terminal
/// rather than a deferral (§4.2), exactly like rule 24's `grandfathered:` list.
///
/// The real rule this encodes: **no NEW migration above 127 may derive a quota
/// from `ai_coach_interactions`** — it must use `usage_counters` instead.
const Set<String> allowedMigrations = {
  '010_add_indexes_idempotency_rpc.sql',
  '026_food_text_rate_limit_trigger.sql',
  '028_compute_coach_signals_cron.sql',
  '101_admin_dashboard_metrics_functions.sql',
  '111_chat_vision_daily_cap_triggers.sql',
  '113_fix_food_text_trigger_ist_boundary.sql',
  '114_raise_vision_analysis_cap_to_20.sql',
  '120_engagement_metric_channel_filter_and_hold_telemetry.sql',
  '127_food_text_free_cap_parity_10.sql',
  // ⚠ 129 is the OPPOSITE of a violation and is listed for the opposite
  // reason to the rest: its three counts are the one-time BACKFILL that seeds
  // `usage_counters` from the log before the triggers stop reading it. It is
  // the migration that FIXES this bug class for the three cap triggers. Listed
  // by name rather than pattern-exempted — see migrationCountsInteractions.
  '129_cap_triggers_use_usage_counters.sql',
};

/// Result of a full sweep.
class SweepResult {
  final List<CounterSite> edgeFunctionSites;
  final List<String> offendingMigrations;
  final List<String> violations;
  const SweepResult(
      this.edgeFunctionSites, this.offendingMigrations, this.violations);

  bool get isClean => violations.isEmpty;
}

/// Compares observed sites against the allowlists.
///
/// [efSources] maps a repo-relative POSIX path to file contents.
/// [migrationSources] maps a BASENAME to file contents.
SweepResult sweep({
  required Map<String, String> efSources,
  required Map<String, String> migrationSources,
  Map<String, int>? allowedEf,
  Set<String>? allowedMigs,
}) {
  final allowEf = allowedEf ?? allowedEdgeFunctionSites;
  final allowMig = allowedMigs ?? allowedMigrations;

  final sites = <CounterSite>[];
  efSources.forEach((path, src) {
    sites.addAll(findEdgeFunctionCounterSites(path, src));
  });

  final perFile = <String, int>{};
  for (final s in sites) {
    perFile[s.path] = (perFile[s.path] ?? 0) + 1;
  }

  final violations = <String>[];
  perFile.forEach((path, count) {
    final allowed = allowEf[path];
    if (allowed == null) {
      violations.add(
          'NEW quota counter in $path ($count site(s)) — this file is not on the '
          'allowlist. Use consume_quota() against usage_counters instead of '
          'counting ai_coach_interactions rows (OI-162).');
    } else if (count > allowed) {
      violations.add(
          '$path holds $count quota counters, allowlisted for $allowed — a NEW '
          'one was added. Use consume_quota() instead (OI-162).');
    }
  });

  final offending = <String>[];
  migrationSources.forEach((basename, src) {
    if (!migrationCountsInteractions(src)) return;
    offending.add(basename);
    if (!allowMig.contains(basename)) {
      violations.add(
          'NEW migration $basename derives a count from ai_coach_interactions. '
          'Applied migrations are immutable so the allowlist is permanent; a new '
          'quota must target usage_counters (OI-162).');
    }
  });

  return SweepResult(sites, offending, violations);
}
