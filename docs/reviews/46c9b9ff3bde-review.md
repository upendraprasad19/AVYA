---
reviewed_at: 2026-09-27T12:01:59+05:30
staged_against: 46c9b9ff3bde
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 1
verdict: accepted
---

# Code Review — 46c9b9ff3bde

## Finding 1 — P1 — guard_without_its_mirror

- **file:line:** `supabase/migrations/147_alert_client_errors_spike_breadth.sql` (the `raw` subquery, `cnt` column vs. the `users`/`server_events` columns); comment block lines ~30-34 explicitly names the scope of the fix.
- **claim:** The migration's own header states its purpose is to fix "the count does not mean what the threshold assumes it means" (raw-row-vs-distinct-event, breadcrumb noise). It then adds an `error_code NOT IN ('event', 'info')` guard to the **`users`** and **`server_events`** FILTER clauses specifically to exclude the routine `event`-coded `subscription_refresh_query_returned_null` breadcrumb (`lib/core/services/subscription_service.dart:911-912`) from those two arms — but the **primary `cnt` column** (the metric the whole migration is about, threshold 40/100/200) has no equivalent guard. `cnt` is computed straight from the outer-WHERE-filtered rowset, and the outer WHERE's op_type re-inclusion regex `(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)` matches `subscription_refresh_query_returned_null` on the `_null` alternative even though `error_code='event'` — so this exact breadcrumb (and any other benign `event`/`info`-coded op_type that happens to contain one of those substrings) still counts toward `cnt` unconditionally. The diagnose doc's `forbidden_patterns_checked` list documents the fix for the `users` arm ("would otherwise inflate this arm on its own") but says nothing about `cnt` sharing the identical exposure, even though `cnt` is the metric most central to this migration's stated purpose.
- **verification:**
  1. Confirmed the write site and exact `error_code`/`op_type`: `lib/core/services/subscription_service.dart:911-912` calls `ErrorTelemetry.logEvent('subscription_refresh_query_returned_null')` with no `message`; `error_telemetry.dart:346-348` stamps `error_code: 'event'`.
  2. Confirmed live via `mcp__claude_ai_Supabase__execute_sql` (read-only) that this exact breadcrumb already appears in `client_errors` and matches the outer WHERE's re-inclusion regex:
     ```sql
     select op_type, error_code, count(*) as n
     from public.client_errors
     where created_at > now() - interval '36 days'
       and coalesce(error_code,'') in ('event','info')
       and op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)'
     group by op_type;
     ```
     Result: `subscription_refresh_query_returned_null` × 28 (plus 4 other event/info-coded op_types matching the same regex, 41 total over 36 days) — all of which pass the outer WHERE and are counted in `cnt`/`rows`, but are excluded from `users`/`server_events` by the new guard.
  3. Confirmed via a 36-day rolling-window replay (own independent SQL, not the migration's own test) that `max(cnt)` never exceeded 24 in this window (floor is 40), so this specific dataset does not currently trip the alert via this path — but the asymmetry is unaddressed by design, not merely untriggered by luck, and any future op_type matching the same regex substrings inflates `cnt` with zero protection, while an identical row would be excluded from the two breadth arms this same migration just hardened.
- **suggested-fix:** Either (a) apply the same `error_code NOT IN ('event','info')` restriction to `cnt` (changing its semantics to match the breadth arms — verify this doesn't regress the deliberate op_type reinclusion design from f0b9d3, which exists precisely to catch genuine failures mislabeled as `event`), or (b) narrow the op_type reinclusion regex's `_null` alternative so it does not match `*_returned_null`-shaped benign breadcrumbs (e.g. require `_failed` instead of bare `_null`, or an explicit deny-list of known-benign op_types), or (c) if the asymmetry is intentional (e.g., `cnt`'s op_type reinclusion is deliberately broader as a low floor while breadth arms are deliberately narrower/stricter), say so explicitly in the migration comment and the diagnose doc's `forbidden_patterns_checked` list, and add a contract-test assertion pinning that `cnt` does NOT get the `error_code NOT IN` guard (so a future accidental "fix" doesn't silently narrow it without discussion). Whichever is chosen, add one assertion to `ops_alerts_spike_breadth_test.dart` that states the decision explicitly — right now the test suite is silent on this axis entirely.
- **status:** accepted — option (c) from the suggested-fix chosen: the
  asymmetry is documented as deliberate (narrowing `cnt` would undo migration
  087/f0b9d3's own P0 fix; a name-based denylist for this one op_type is the
  exact "transient denylist" f0b9d3 already rejected). Filed as **OI-254**
  (root cause is client-side — `subscription_refresh_query_returned_null`'s
  op_type collides with the failure-reinclusion regex's `_null` alternative
  — naturally in scope for B2a-2b, not this pure-SQL migration). Documented
  in the migration's own header comment, the diagnose doc
  (`forbidden_patterns_checked`, `impact_analysis`, and a new "B-pass caught
  a real, tracked asymmetry" section), and pinned by a new test in
  `ops_alerts_spike_breadth_test.dart` ("cnt is DELIBERATELY NOT scoped...")
  asserting `cnt`'s column definition carries no `FILTER` clause — mutated
  (added the guard to `cnt`) and confirmed it reddens exactly that 1 new
  test, none other, before being restored (sha256-verified).

## Lens-by-lens notes (including where no finding was raised)

### 1. writer_reader_drift
Traced every reader of `public.alerts` and its new `context_json` keys (`distinct_events`, `distinct_users`, `server_events`, `rows`):
- `scripts/check_alerts.dart` (SessionStart hook) — fetches the full row via PostgREST but only ever renders `id/detected_at/source/severity/summary/suggested_action`; never parses `context_json`. Grep confirmed zero references to `context_json` in this file.
- `supabase/functions/founder-digest/index.ts` — confirmed via `index_test.ts:601` that its `alerts` select list is `"detected_at, source, severity, summary"` — no `context_json` column at all.
- `supabase/functions/_shared/gemini_failure_alert.ts` — writes its own, unrelated `context_json` shape (`status/message/endpoint`) for a different `source` value; not a reader of this migration's keys.
No reader anywhere assumes the OLD `context_json.count` key shape. Clean.

### 2. function_exception_swallow
No `.functions.invoke(` in this diff. Checked the SQL itself for a silently-swallowed Postgres exception path: none of the new expressions can throw (regex ops on a possibly-NULL `error_message` evaluate to NULL, which FILTER/WHERE treat as "not matched" rather than erroring; `left()`/`coalesce()`/`date_trunc()` are all null-safe here). Note: `error_message ~* '...'` in the `server_events` FILTER clause is not `coalesce()`-wrapped (unlike the offline-exclusion clause), but this is a NULL-safety inconsistency, not a crash — a NULL `error_message` simply fails to match the FILTER, correctly excluding the row. Not raised as a separate finding since no error path exists.

### 3. blast_radius_mismatch
Recomputed independently: `dart run scripts/blast_radius_from_diff.dart -` on the exact staged file list returned `platform`, matching the given classification. Clean.

### 4. secrets_in_tree
`git diff --cached | grep -iE "api[_-]?key|secret|token|password|bearer|service_role"` returns one hit — a pre-existing, unrelated `CRON_REGISTRY.md` row (the `founder_digest_daily` entry) that only names a secret KEY (`cron_secret`), never a value, and is not part of this migration's own diff hunk. No credential-shaped literal anywhere in the actual diff. Clean.

### 5. unawaited_no_error_sink
No silently-dropped error path found in the new SQL logic. Noted (not raised as a finding, since it predates this migration and is not made materially worse by it): the whole `ops_alerts_30min` job body runs as ONE pg_cron command / one implicit transaction (per this repo's own documented VACUUM-in-one-transaction pitfall), so if the new, more complex `alert_client_errors_spike` regex logic ever throws at runtime, the entire job — including the untouched `alert_edge_function_health` and `alert_cron_failures` sub-blocks — fails atomically for that cycle. This is inherited from migration 143's design (which already combined all three blocks), not introduced by 147, and no concrete throw path was found in 147's added SQL (see lens 2), so not raised as a standalone finding.

### 6. guard_without_its_mirror
This is Finding 1 above. Checked all four named guards:
- **Offline-exclusion `NOT(signature AND NOT override)`:** mirror case (a genuinely offline-shaped message that also matches the override) checked live — 0 of 770 offline-shaped rows over 36 days are overridden, and the override patterns are independently non-vacuous (8 status-pattern, 66 type-pattern matches). No false-negative found.
- **Exception-shaped FILTER on both `users` and `server_events`:** present on both (confirmed by reading the SQL and by the passing test `per-user breadth arm counts EXCEPTION-SHAPED rows only` / `server-error-class arm ... among exception-shaped rows only`). Mutated the `server_events` arm's copy of this guard alone (removed `coalesce(error_code, '') NOT IN ('event', 'info') AND` from only that FILTER, leaving the `users` arm's copy untouched) and re-ran the suite: **exactly 1 of 10** tests in `ops_alerts_spike_breadth_test.dart` reddened (the server-error-class-arm test using the whole-literal match) — confirms the round-3 fix (windowed-substring → whole-literal) actually works, and that no other test would have silently absorbed this specific regression. File restored via `cp` from a pre-mutation backup; `sha256sum` confirmed exact match to `89dd1588276a84fb91cf2d53555636d7cbf12455acb81b04d77f48939d51bf2d` afterward, and `git status --porcelain` on the file showed clean `A ` staged state (no diff introduced by the restore).
- **Parenthesized fire condition:** mutated (removed the two parens around `(c.cnt >= 40 OR c.users >= 3 OR c.server_events >= 3)`), re-ran the suite: **exactly 1 of 10** tests reddened (the parenthesization test itself). File restored and sha256-verified identical to the pre-mutation copy.
- **Rank-based dedup:** not independently re-mutated (the diagnose doc's own mutation record for this one — degrading `>= c.severity_rank` to `>= 1`, reddening exactly 1/10 — was accepted on the strength of the other two independently-reproduced mutations behaving exactly as documented, i.e. the documented methodology is trustworthy here).
- **The one gap actually found** is Finding 1 above — the `cnt`/`error_code` asymmetry, which none of `ops_alerts_spike_breadth_test.dart`'s 10 tests assert either way (a plausible regression a test author would not think to write, precisely because the fix's own narrative frames the breadcrumb-exclusion problem as solved once the `users` arm is protected).

### 7. missing_input
Checked `test/helpers/cron_job_body_reader.dart`'s documented limits against what migration 147 actually writes:
- 147 calls `cron.alter_job(job_id := (SELECT jobid FROM cron.job WHERE jobname = 'ops_alerts_30min'), command := $$ ... $$)` — the `jobname = 'ops_alerts_30min'` text sits inside a nested subquery for `job_id`, not as a direct `jobname :=` parameter to `alter_job` itself. The reader's `alter` regex (`cron\.alter_job\([^;]*?jobname\s*=\s*'$job'[^;]*?command\s*:=\s*...`) is a "text anywhere between `alter_job(` and `command :=`, no semicolon crossed" match, not a strict parameter-position match, so it correctly finds this subquery form. Confirmed empirically: `flutter test test/contracts/ops_alerts_spike_breadth_test.dart` passes all 10 tests including the cadence test, which depends on `latestCronJobBody` correctly threading `job_id`'s nested `jobname` reference.
- The reader's `numericAlter` guard (`alter_job\(\s*(job_id\s*(:=|=>)\s*)?[0-9]`) does not false-positive on 147, since `job_id := (SELECT ...` is followed by `(`, not a digit.
- The reader's documented "0 such migrations exist" claim about a numeric-id `alter_job` still holds after this diff (confirmed by the full suite passing, which would throw a `TestFailure` loudly if any migration tripped it).
No gap found between the helper's documented limits and what 147 actually does. Clean.

### 8. asserted_fixture_value
Independently re-derived, via fresh read-only SQL against the live project (`dedsavbjuwgarrhphgnl`), every cited number rather than trusting the diagnose doc or the two prior reviews:
- **Offline-signature sanity** (own query, not copied from the doc):
  `total_rows=6199, offline_shaped_rows=770, overridden_rows=0, status_pattern_matches=8, type_pattern_matches=66` — **exact match** to the diagnose doc's claims (770/6199, 0 overridden, 8 status, 66 type).
- **36-day replay** (own rolling 30-minute-tick simulation using `generate_series`, reproducing the migration's exact `raw` subquery logic including the offline exclusion, NOT copied from the doc's SQL):
  `firing_ticks=8, max_users=2, max_cnt=24, max_server_events=9` — **exact match** to the doc's "8 firing ticks, all warn (max server_events=9 < 10 critical floor), max users=2, cnt never reaches 40 (max 24)".
  Listing the individual firing ticks reproduced the doc's claimed 4 clusters exactly: 2026-08-29 (2 ticks), 2026-09-15 (2 ticks), 2026-09-17 (2 ticks), 2026-09-19 (2 ticks) — each pair of consecutive 30-min ticks fires via `server_events >= 3` alone, consistent with the doc's "every one firing via the server_events>=3 arm — none via cnt or users alone" and with the rank-based dedup design (each pair would collapse to 1 alert, giving the doc's "4 real incidents").
- **Test counts**: ran the actual suite (`flutter test`) rather than trusting the doc's "10/10", "4/4", "8/8" claims: got exactly 10 / 4 / 8 passing (22 total). Matches.
All independently-checkable numeric claims in the diagnose doc reproduced exactly. No discrepancy found.

## Founder triage notes
<!-- left blank per template — filled in later -->
