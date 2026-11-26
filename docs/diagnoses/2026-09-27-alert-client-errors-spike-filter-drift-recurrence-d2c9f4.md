---
bug_id: d2c9f4
date: 2026-09-27
batch: ops-alerting-b2a2a
status: fixed
blast_radius: platform
symptom: >
  The live alert_client_errors_spike sub-block of ops_alerts_30min (jobid 43)
  counted RAW client_errors rows over a 1-hour window, with no offline-noise
  exclusion, no per-user breadth signal, and no server-error-class signal. A
  single client's retry storm could inflate the count as easily as a genuine
  fleet-wide regression, and a phone losing signal on a train could write
  dozens of connectivity-exception rows in one minute with nothing to tell
  that apart from a real incident. This is a recurrence of the 2026-06-06
  spike-filter-drift class (diagnose f0b9d3): that fix addressed the
  breadcrumb-vs-failure classification but never revisited row-count vs
  distinct-event semantics or offline noise, which is a separate axis of the
  same underlying defect ("the count does not mean what the threshold assumes
  it means").
concept: alert_threshold_tuning
sot_registry_entry: n/a (observability cron consuming a client_errors aggregate — adds no new writer/reader field contract)
writers: >
  The pg_cron job ops_alerts_30min (jobid 43, unchanged) — was defined by
  supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql, now
  re-defined by supabase/migrations/147_alert_client_errors_spike_breadth.sql
  via cron.alter_job (keeps jobid + run history; does NOT unschedule +
  reschedule). It runs every 30 minutes and INSERTs a row into public.alerts
  when the hourly client_errors distinct-event count, per-user breadth, or
  server-error-class breadth crosses a threshold. The documented thresholds
  live in alerts/_thresholds.yaml but are NOT the runtime source of truth; the
  runtime values are embedded in the cron SQL and must be hand-mirrored via a
  paired migration.
readers: >
  The SessionStart hook (scripts/check_alerts.dart, wired in .claude/settings.json)
  reads unacknowledged alerts and surfaces them to the founder at session
  start; the founder triages them in natural language. No client app code
  reads the alerts table — it is RLS service-role only.
hive_key_prefix: not_applicable (server-side pg_cron alert; nothing written to Hive)
hive_key_formula: not_applicable (alert rows live in the Postgres alerts table)
sync_methods: not_applicable (no client sync path; cron writes alerts directly)
restore_methods: not_applicable (no restore path involved)
cloud_table: alerts (written by the cron) / client_errors (the aggregate read source)
cloud_columns: alerts.severity, alerts.summary, alerts.context_json.distinct_events, alerts.context_json.distinct_users, alerts.context_json.server_events, alerts.context_json.rows
contract_test_path: test/contracts/ops_alerts_spike_breadth_test.dart
ist_handling: not_applicable (the cron window is a rolling now()-1 hour interval; no IST date-keying or counter reset)
provider_invalidations: not_applicable (no Riverpod providers; server-side cron)
telemetry_op_types: alert_client_errors_spike (alerts.source); excluded breadcrumb codes = event, info (unchanged from f0b9d3/087); offline-shaped error_message excluded unless a real HTTP status or a server-answered exception type overrides it
cross_account_guard: not_applicable (alerts is service-role-only RLS; the count is an intentional all-user aggregate)
forbidden_patterns_checked:
  - "raw COUNT(*)/COUNT(DISTINCT user_id) over client_errors — replaced with COUNT(DISTINCT (user, message-prefix, second)) so one client's retry storm cannot inflate the count, and the contract test asserts the exact DISTINCT tuple."
  - "an offline-shaped error_message counted as a real error — a regex signature now excludes it, WITH an explicit never-offline override for real HTTP status codes and PostgrestException/FunctionsHttpException/FunctionsRelayException/AuthApiException (these types mean a server answered, so they are never network-loss noise). Verified live: 770 of 6199 rows over 36 days are offline-shaped and 0 were overridden by a real status/type match; the override regexes themselves independently match 8 and 66 live rows respectively (not vacuous)."
  - "the users breadth arm counting ALL real rows (including event-coded breadcrumbs) — would trip routinely on the ordinary subscription_refresh_query_returned_null breadcrumb (lib/core/services/subscription_service.dart:911-912, error_code='event'); the arm now FILTERs to error_code NOT IN ('event','info'). Live 36-day replay with this filter never exceeded 2 distinct users/hour."
  - "the compound-boolean-connective mutation-target class this same batch's B-pass found in migration 146 (an unparenthesized OR-chain ANDed with NOT EXISTS silently disables dedup) — the fire condition here is explicitly parenthesized `(c.cnt >= 40 OR c.users >= 3 OR c.server_events >= 3) AND NOT EXISTS (...)`, and the contract test's assertion string pins the parenthesized form specifically; mutation-tested by deleting the parens locally, which reddened exactly that one test (see Verification)."
  - "dedup as a bare source+ack check, which lets a quiet pre-existing info-level open alert suppress a genuine critical firing later in the same hour — dedup is now RANK-BASED (an open alert of EQUAL-OR-HIGHER severity suppresses), with severity_rank computed once in the subquery and reused for both the emitted severity and the dedup comparison so the two can never independently drift; mutation-tested by degrading the rank comparison to `>= 1` (always-suppress), which reddened exactly the rank-based-dedup test."
  - "NOT fixed in this migration, tracked as OI-254: cnt does not get the users/server_events arms' error_code NOT IN ('event','info') guard, so it still inherits the 087/f0b9d3 breadcrumb-reinclusion regex's match on subscription_refresh_query_returned_null (28x/36d, non-material — max(cnt)=24 vs the 40 floor). Evaluated and rejected: narrowing cnt to match would undo 087's own P0 fix (catching genuine failures the client mislabels error_code='event'); a name-based exclusion for this one op_type is the exact transient-denylist f0b9d3 already rejected (same client-side mislabeling recurs under ~25 other op_types). Real fix is a client-side op_type rename, naturally in scope for B2a-2b, not this pure-SQL migration. Pinned by a new test asserting cnt does NOT carry the guard, so a future silent narrowing or widening is caught either way."
proposed_fix: >
  Migration 147 re-defines ops_alerts_30min's alert_client_errors_spike
  sub-block via cron.alter_job (jobid 43 unchanged): (1) counts DISTINCT
  (user, message-prefix, second) moments instead of raw rows; (2) excludes
  offline-noise via a regex signature, with an explicit never-offline
  override for real HTTP status codes and four server-answered exception
  types; offline-caused client TIMEOUTS are deliberately still counted as
  real (undercounting is the worse failure mode); (3) adds a per-user breadth
  arm over exception-shaped rows only (>=3 users -> warn, >=5 -> critical);
  (4) adds a server-error-class arm matching PGRST00x / 57014
  statement-timeout / WORKER_RESOURCE_LIMIT / bare 5xx (>=3 events -> warn,
  >=10 -> critical); (5) unifies all three arms (cnt/users/server_events)
  into one parenthesized fire condition and one severity_rank computed once
  and reused for both the emitted severity and a new rank-based dedup
  (equal-or-higher severity suppresses, never a lower one masking a higher
  one). The other two sub-blocks (alert_edge_function_health,
  alert_cron_failures) are reproduced byte-identical from migration 143.
  alerts/_thresholds.yaml updated in the same commit: renamed/new keys
  (counts_distinct_events, excludes_offline_noise, breadth_warn_users,
  breadth_critical_users, server_warn_events, server_critical_events),
  info/warn/critical re-based to distinct-event counts (40/100/200), cadence
  corrected */15->*/30 on all three ops_alerts_30min entries (stale since the
  141 consolidation), and defined_in_migration advanced to 147 for both
  client_errors_spike and cron_failures (147 is now the LAST migration
  emitting the alert_cron_failures literal too, since it reproduces that
  block verbatim — alert_cron_failures_sync_test.dart's own
  "defined_in_migration names the LATEST migration" test enforces this).
regression_test_planned: >
  test/contracts/ops_alerts_spike_breadth_test.dart (new) — reads the
  live-authoritative ops_alerts_30min body via the shared
  latestCronJobBody helper and asserts: distinct-event counting, the
  offline-exclusion signature + override, the exception-shaped users filter,
  the server-error regex (itself also requiring exception-shaped rows), the
  PARENTHESIZED fire condition, RANK-based dedup, and byte-identity of the
  two untouched sub-blocks against migration 143. Mutation-tested: removing
  the fire-condition parens reddens exactly 1 of 10 tests (the
  parenthesization test); degrading the dedup rank comparison to `>= 1`
  reddens exactly 1 of 10 (the rank-based-dedup test) — see Verification.
  test/contracts/alert_thresholds_sync_test.dart (rewritten) — yaml<->
  migration numeric-drift contract for all three arms' thresholds, updated
  for the new `raw.cnt`/`raw.users`/`raw.server_events` SQL shape (a stale
  bare-`cnt` anchor from before the severity_rank subquery would have gone
  silently, permanently green — feedback_green_check_input_set_width class).
  test/contracts/alert_cron_failures_sync_test.dart (one assertion widened)
  — accepts cron.alter_job( as well as cron.schedule( for the "scheduled via
  cron, not an Edge Function" check, since 147 re-defines the job via
  alter_job.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: verified, evidence: "lib/core/services/subscription_service.dart:911-912 read directly to confirm the exact file:line and error_code the users-arm exclusion rationale depends on — the migration's OWN header previously cited a stale path (lib/features/profile/services/subscription_service.dart:905-914) that no longer exists on disk; caught and corrected before this doc was written" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "read-only 36-day replay of the new filter (BEGIN-free SELECT, no writes): 8 firing ticks, all severity warn, clustered into 4 real incidents (2026-08-29, 09-15, 09-17, 09-19), all firing via the server_events>=3 arm — matches the plan's own R2 replay claim. Offline-signature check: 770/6199 rows over 36d are offline-shaped, 0 overridden (regex not vacuous — status/type patterns independently matched 8/66 live rows). max_users over 36d with the exception-shaped filter = 2 (never reaches 3)." }
  - { tier: 5, layer: migrations_applied, status: not_applicable, evidence: "migration drafted and tested in this diagnose-doc's batch; NOT YET applied live — pending explicit founder authorization per CLAUDE.md 4.3 (plan approval != deploy approval)" }
  - { tier: 1, layer: contract_tests, status: fixed_in_this_batch, evidence: "test/contracts/ops_alerts_spike_breadth_test.dart 11/11 green; test/contracts/alert_thresholds_sync_test.dart 4/4 green (rewritten); test/contracts/alert_cron_failures_sync_test.dart 8/8 green (one assertion widened). Mutation-proven: parenthesization removal -> 1 test reddens (the parenthesization test, none other); dedup rank degraded to >=1 -> 1 test reddens (the rank-based-dedup test, none other); adding the users/server_events guard to cnt -> 1 test reddens (the OI-254 pinning test, none other) — all three mutations confirmed applied via grep before running, and the file restored to its verified sha256 (7a3c7feafdf1fb9380bb4b641a11094401f9c972fe392b2bb95200f594497025) after each. Round-3 review (context-blind) found a distinct test-robustness gap in the server-error-class arm's own assertion (a fixed-400-char lookback window bled into the adjacent users-arm clause, so it could not detect the server_events arm losing its own exception-shaped-rows guard) — fixed by replacing the windowed substring with an exact whole-literal match; verified by the same window-bleed mutation the reviewer used, which now correctly reddens. B-pass (docs/reviews/46c9b9ff3bde-review.md) found a real, tracked asymmetry (cnt vs the two new breadth arms) — filed as OI-254, documented in the migration header, pinned by a new test (see Mutation 3)." }
impact_analysis: >
  Platform / observability blast radius — no user-facing change, and NOT YET
  live (pending founder go). Before: a single noisy client (retry storm or
  connectivity loss) could trip or dodge the alert purely by chance, and a
  quiet info-level open alert could mask a later genuine critical for up to
  an hour. After: the alert distinguishes distinct incidents from raw noise,
  excludes offline-caused noise while still catching offline-caused
  timeouts, adds two new breadth signals (per-user, server-error-class) that
  a raw count structurally cannot see, and dedup can never let a lower
  severity hide a higher one. Live 36-day replay shows the new design would
  have produced exactly 4 real alerts (all warn, all genuine server-side
  incidents) rather than 0 or an unpredictable number under the old raw-row
  design. Coupling: B2a-2b (client-side telemetry) must define its own
  offlineSignature to match this migration's regex exactly, or the two sides
  of the same signal will classify differently. Residual, tracked as
  OI-254: cnt (unlike the two new breadth arms) still counts the benign
  event-coded subscription_refresh_query_returned_null breadcrumb via the
  inherited 087 op_type-reinclusion regex — currently non-material
  (max(cnt)=24 vs the 40 floor over 36 days) and the real fix is a
  client-side op_type rename, naturally in scope for B2a-2b.
---

# alert_client_errors_spike counted raw rows with no offline/breadth signal (recurrence of f0b9d3)

## What happened

Live investigation of the `ops_alerts_30min` job (jobid 43, currently defined by
migration 143) found that its `alert_client_errors_spike` sub-block, unchanged
in substance since migration 087, still counts **raw `client_errors` rows**
over a rolling 1-hour window. This means:

- A single client retrying a failing call repeatedly inflates the count as
  much as ten different users each failing once.
- A phone losing signal on a train can write dozens of connectivity-exception
  rows in one minute — nothing distinguishes that from a genuine regression.
- There is no signal for "how many distinct users are affected" or "is this a
  server-side incident" — both of which matter more than raw volume for
  deciding whether to page.

This is a **recurrence** of the 2026-06-06 spike-filter-drift class (diagnose
`f0b9d3`): that fix solved breadcrumb-vs-failure classification (`error_code`
'event'/'info' exclusion + failure-shaped `op_type` re-inclusion) but never
touched row-count-vs-distinct-event semantics or offline noise, which is a
separate axis of the same underlying defect — "the count does not mean what
the threshold assumes it means."

## Root cause

`supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql`
(lines 51-65, the `alert_client_errors_spike` sub-block, inherited verbatim
from migration 141) runs:

```sql
SELECT COUNT(*) AS cnt FROM public.client_errors
WHERE created_at > now() - interval '1 hour'
  AND ((error_code IS DISTINCT FROM 'event' AND error_code IS DISTINCT FROM 'info')
       OR op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)')
```

No `DISTINCT`, no offline exclusion, no per-user or server-class signal. The
threshold gates (info 100 / warn 250 / critical 500 rows) were tuned against
this raw-row baseline in 087 and have never been revisited for what the
number actually measures.

## Fix

`supabase/migrations/147_alert_client_errors_spike_breadth.sql` re-defines the
job via `cron.alter_job` (jobid 43 unchanged, run history preserved — see line
47 of the migration) with:

1. **Distinct-event counting** (line 100): `COUNT(DISTINCT (coalesce(user_id::text,'anon'), left(coalesce(error_message,''),200), date_trunc('second', created_at)))`.
2. **Offline-noise exclusion** (lines 113-119): a regex signature for
   connectivity-loss messages, wrapped `NOT (signature AND NOT override)` so a
   real HTTP status code or one of `PostgrestException` /
   `FunctionsHttpException` / `FunctionsRelayException` / `AuthApiException`
   always overrides the exclusion. Offline-caused client **timeouts** are
   deliberately NOT excluded (residual, matches the client-side
   `offlineSignature` contract B2a-2b will add — undercounting real incidents
   is worse than occasionally counting a stalled request).
3. **Per-user breadth arm** (lines 101-103): distinct users among
   exception-shaped rows only (`error_code NOT IN ('event','info')`) —
   excludes the routine `subscription_refresh_query_returned_null` breadcrumb
   (`lib/core/services/subscription_service.dart:911-912`).
4. **Server-error-class arm** (lines 104-107): distinct events among
   exception-shaped rows matching `(PGRST00[0-9]|57014|canceling statement due
   to statement timeout|WORKER_RESOURCE_LIMIT|status(Code)?: ?5[0-9]{2})`.
5. **Unified severity** (lines 95-97): one `severity_rank` computed from all
   three arms, reused for both the emitted severity and a new **rank-based**
   dedup (lines 122-129) — an open alert of equal-or-higher severity
   suppresses, never a lower one masking a higher one.

The `alert_edge_function_health` and `alert_cron_failures` sub-blocks are
reproduced byte-identical from 143 (verified by
`ops_alerts_spike_breadth_test.dart`).

`alerts/_thresholds.yaml` is updated in the same commit: renamed/new keys,
info/warn/critical re-based to distinct-event counts, cadence corrected
`*/15`->`*/30` on all three `ops_alerts_30min` entries (stale since the 141
consolidation — none of the three actually run at `*/15` anymore), and
`defined_in_migration` advanced to 147 for both `client_errors_spike` and
`cron_failures` (147 now carries the LAST occurrence of the
`alert_cron_failures` emitter literal too, by virtue of the verbatim copy).

## Verification

- Live read-only 36-day replay of the new filter (no writes): **8 firing
  ticks**, all severity `warn`, clustered into **4 real incidents**
  (2026-08-29, 2026-09-15, 2026-09-17, 2026-09-19), every one firing via the
  `server_events >= 3` arm — none via `cnt` or `users` alone.
- Offline-signature sanity: 770 of 6,199 `client_errors` rows over 36 days
  are offline-shaped; 0 were overridden. The override regexes are not
  vacuous — independently, 8 rows match the status pattern and 66 match the
  exact-type pattern on live data.
- `max(users)` over 36 days with the exception-shaped filter is 2 — the arm
  never reaches its 3-user warn floor on this dataset, consistent with the
  plan's own claim.
- `test/contracts/ops_alerts_spike_breadth_test.dart`: 11/11 green (10 from
  the original design + 1 OI-254 pinning test added after the B-pass).
- **Mutation 1** (compound-boolean-connective class, this batch's own B-pass
  P1 in migration 146): removed the parens around the fire condition
  (`(c.cnt >= 40 OR c.users >= 3 OR c.server_events >= 3)` ->
  unparenthesized). Re-ran the suite: **exactly 1 of 10** tests reddened (the
  parenthesization test), all others stayed green. File restored from a
  pre-mutation copy; sha256 confirmed to match
  `7a3c7feafdf1fb9380bb4b641a11094401f9c972fe392b2bb95200f594497025`
  afterward.
- **Mutation 2** (dedup discrimination): degraded the rank comparison from
  `>= c.severity_rank` to `>= 1` (always-suppress, i.e. a bare source+ack
  check). Confirmed the mutation applied via `grep -c 'c.severity_rank'`
  (2 -> 1). Re-ran the suite: **exactly 1 of 10** tests reddened (the
  rank-based-dedup test). File restored and sha256 re-verified.
- **Mutation 3** (OI-254 pinning test): added the `error_code NOT IN
  ('event','info')` FILTER to `cnt` (the exact "someone silently narrows cnt
  without discussion" regression the new pinning test exists to catch).
  Confirmed applied via `grep -c "FILTER (WHERE coalesce(error_code, '') NOT
  IN ('event', 'info')) AS cnt"` (0 -> 1). Re-ran the suite (now 11 tests):
  **exactly 1 of 11** reddened (the new "cnt is DELIBERATELY NOT scoped"
  test). File restored; sha256 re-verified against
  `7a3c7feafdf1fb9380bb4b641a11094401f9c972fe392b2bb95200f594497025` (the
  file's hash AFTER the B-pass-triggered header addition documenting OI-254 —
  this superseded the earlier `89dd1588...` hash cited by Mutations 1-2,
  which was correct for the file version those two mutations were run
  against, before the header note was added).
- `test/contracts/alert_thresholds_sync_test.dart`: rewritten for the new SQL
  shape (`raw.cnt`/`raw.users`/`raw.server_events`, not bare `cnt`); 4/4
  green.
- Round-3 (drafted-diff) context-blind review found one P1 (a fixed-size
  400-char lookback window in `ops_alerts_spike_breadth_test.dart`'s
  server_events-guard assertion bled into the adjacent `users` arm's
  identical clause, so it could not detect that specific arm losing its own
  guard — the `feedback_green_check_input_set_width` class, and this file's
  own §4.4 rule 21 "a mutation that reddens nothing is not proof the case is
  covered") and one P2 (this doc's own stale "8/8" count for
  `alert_thresholds_sync_test.dart`, which actually has 4 tests — a
  copy-paste from the neighboring `alert_cron_failures_sync_test.dart` line,
  which correctly says 8/8). Both fixed in this same commit; the P1's fix
  (windowed substring -> exact whole-literal match) was itself verified
  against the reviewer's own window-bleed mutation, which now correctly
  reddens.
- `test/contracts/alert_cron_failures_sync_test.dart`: one assertion widened
  to accept `cron.alter_job(` alongside `cron.schedule(`; 8/8 green.
- **Not yet applied live** — pending explicit founder authorization (plan
  approval != deploy approval, CLAUDE.md §4.3).

## B-pass caught a real, tracked asymmetry — OI-254 (fixed by documentation + pinning test, not by SQL)

The self-triggered B-pass (`docs/reviews/46c9b9ff3bde-review.md`, finding 1,
`guard_without_its_mirror`) found that `cnt` — the primary metric this
migration's threshold gates on — does NOT get the `error_code NOT IN
('event','info')` guard the new `users`/`server_events` arms get, even
though the same migration's own header names the exact breadcrumb
(`subscription_refresh_query_returned_null`) that motivated adding that
guard to the other two arms. Verified live: this breadcrumb fires 28 times
over 36 days (41 total across every event/info-coded op_type matching the
outer breadcrumb-reinclusion regex); currently non-material (`max(cnt)=24`
vs the 40 floor).

Two SQL-only fixes were considered and rejected: narrowing `cnt` to match
would undo migration 087/f0b9d3's own P0 fix (catching genuine failures the
client mislabels `error_code='event'`); a name-based exclusion for this one
op_type is exactly the "transient denylist" f0b9d3's own diagnose doc already
evaluated and rejected, since the same client-side mislabeling recurs under
~25 other op_types. The real fix — renaming this call site's op_type on the
client so it stops matching the failure-reinclusion regex — is a `lib/`
change naturally in scope for **B2a-2b** (client telemetry, the next unit in
this batch), not this pure-SQL migration.

Filed as **OI-254**. Documented in this migration's own header comment and
pinned by a new test
(`ops_alerts_spike_breadth_test.dart`: "cnt is DELIBERATELY NOT scoped...")
asserting `cnt`'s column definition carries no `FILTER` clause, so a future
change to either side of this asymmetry is caught rather than silently
shipped.

## See also

- `supabase/migrations/147_alert_client_errors_spike_breadth.sql`
- `supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql` (the untouched sub-blocks' source)
- `docs/diagnoses/2026-06-06-alert-spike-counts-breadcrumbs-f0b9d3.md` (the first instance of this class)
- `alerts/_thresholds.yaml`
- `test/contracts/ops_alerts_spike_breadth_test.dart`
- `/home/ubuntu/.claude/projects/-home-ubuntu-projects-avya/memory/feedback_compound_boolean_connective_mutation_target.md` (the mutation-target lesson this doc's Mutation 1 applies)
