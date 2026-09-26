---
bug_id: a7e4c2
date: 2026-08-20
batch: hermes-fob-remediation
blast_radius: catastrophic
status: fixed
symptom: >
  Hermes P1-D + P1-E. FOB-5 existed because five phase_1_day_29_* events had
  ZERO consumers, making the free-tier hold mechanic unobservable. It replaced
  them with hold_week_started plus three SQL columns and declared the consumer
  "REAL, not aspirational". Two independent lenses found that claim false in two
  different directions, and the mechanic remained unobservable.
  (1) The columns reached the Edge Function RESPONSE and stopped there.
  admin-dashboard-data spreads the RPC row wholesale, which is why no redeploy
  was needed — but AdminCurrentMetrics.fromJson is a NAMED-KEY parser and
  engagement_tab renders a FIXED tile list, so a column with no Dart field is
  dropped at parse and painted nowhere. Choosing the existing RPC specifically
  to avoid OI-101's "shipped but nothing calls it" reproduced OI-101 one layer
  up.
  (2) Even counted correctly, the numbers are lossy. rolling-context
  summarize-and-DELETED from ai_coach_interactions with no channel filter, so
  the rows the three metrics count were being pruned nightly — 91 of 92
  comparable rows were already gone when measured. The same unfiltered read also
  embedded 92 analytics rows into memory_embeddings as
  source_type='conversation' (15.4% of all rows), and ai-proxy concatenates
  retrieval into the SYSTEM prompt, so app_event text reached the model as
  though a user had said it.
concept: hold_week_telemetry
sot_registry_entry: hold_week_telemetry
writers:
  - { file: lib/features/admin/models/admin_dashboard_data.dart, line: 126, source: "AdminCurrentMetrics gains holdsStartedToday / holdsStarted7d / holdersTotal — the hop FOB-5 missed. A named-key parser drops what it does not declare" }
  - { file: lib/features/admin/models/admin_dashboard_data.dart, line: 173, source: "fromJson reads the three keys; absent keys degrade to 0 so migration 120's inline rollback (which shrinks the signature back to 5 columns) cannot break the dashboard" }
  - { file: supabase/functions/rolling-context/index.ts, line: 301, source: "the per-user fetch now excludes channel='app_event' — analytics rows are not conversation, so they are neither summarized into memory nor deleted" }
  - { file: supabase/functions/rolling-context/index.ts, line: 181, source: "distinct-user scan, same exclusion — the >=50 threshold must mean the same thing as what is actually summarized" }
  - { file: supabase/functions/rolling-context/index.ts, line: 220, source: "per-user count, same exclusion" }
readers:
  - { file: lib/features/admin/widgets/engagement_tab.dart, line: 74, source: "three new tiles. The holders tile reads 'min, all-time' because the number is a floor, not a census" }
  - { file: supabase/migrations/120_engagement_metric_channel_filter_and_hold_telemetry.sql, line: 99, source: "the three SQL predicates — unchanged; only the header's false 'reach the dashboard' claim and its two stale citations were corrected" }
hive_key_prefix: null
hive_key_formula: null
sync_methods: [AppEventsService.log, AppEventsService._logAsync]
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [channel, user_message, user_id, created_at]
contract_test_path: test/contracts/admin_hold_telemetry_renders_behavioral_test.dart
ist_handling:
  - { file: supabase/migrations/120_engagement_metric_channel_filter_and_hold_telemetry.sql, line: 102, fn: "holds_started_today anchors to IST midnight via the date_trunc/at-time-zone inverse pair, verified live with a boundary table (delta 00:00:00)" }
provider_invalidations: [adminDashboardProvider]
telemetry_op_types:
  success: [hold_week_started]
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "an ai_coach_interactions query in rolling-context without .neq(channel, app_event)", absent: true }
  - { pattern: "a founder_metrics_engagement column with no AdminCurrentMetrics field", absent: true }
proposed_fix: >
  Declare the three columns in the named-key parser and render them, so the
  claim becomes true at the layer a human reads. Exclude channel='app_event'
  from every one of rolling-context's reads on ai_coach_interactions — including
  a re-count of the candidates the get_users_with_message_count RPC returns,
  which is the ONLY one on the live path — so the
  rows survive and stop poisoning retrieval. Label the holders tile as a
  minimum, because a second leak (AppEventsService drops failed inserts with no
  queue, so an offline hold emits nothing) is not closed by either fix.
regression_test_planned:
  - test/contracts/admin_hold_telemetry_renders_behavioral_test.dart
  - test/contracts/rolling_context_excludes_app_event_test.dart
impact_analysis: >
  NO USER-FACING IMPACT, and the reasoning matters because two of the three
  defects touch production behaviour. (1) The unrendered columns were
  founder-only and read 0 regardless, since enable_hold_weeks is default OFF, so
  nothing a user sees changed. (2) The rolling-context filter DOES change
  production behaviour once deployed — analytics rows stop being summarized and
  deleted — but it strictly REDUCES what the summarizer touches, so no
  conversational history that was previously retained can be lost by it. The
  risk direction is unbounded growth of app_event rows in
  ai_coach_interactions, accepted deliberately: they are small, they are the
  only evidence the hold mechanic produces, and a metric that deletes its own
  evidence is worth less than the rows cost. (3) The 92 rows already embedded in
  memory_embeddings are UNCHANGED by this batch and remain retrievable into the
  coach system prompt; that is real, live, and explicitly not closed here
  (OI-133) rather than quietly implied to be fixed.
  Migration 120 was edited but only in comments — every executable statement is
  byte-identical to what was applied, and the live pg_get_functiondef body still
  matches, so no re-apply is needed or implied.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze 0 errors/0 warnings; TZ=Asia/Kolkata flutter test test/ --exclude-tags golden -> 4775 passed, 7 skipped, exit 0" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "no Hive read or write — the admin dashboard is a live cloud read and the telemetry writer is unchanged" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "no schema change. Migration 120's executable statements are byte-identical to what was applied; only comments changed, and the manifest hash was updated with that delta recorded" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "no data written. The 92 already-embedded memory_embeddings rows are NOT removed by this fix — filtering a writer does not unwrite history — and are tracked as OI-133" }
  - { tier: 5, name: migrations_applied, status: verified, evidence: "Gate 39 PASS (125 structured records). 120's hash updated to 6a28578..., 120b's unverifiable orphan hash replaced with an explicit sentinel plus the reason" }
  - { tier: 6, name: edge_function_deploy, status: deferred, evidence: "⚠ THE REPO AND THE RUNNING FUNCTION NOW DISAGREE. The rolling-context fix is INERT until redeployed, and an EF deploy needs its own §4.3 authorization which has NOT been given — the three authorized this session were ai-proxy, weekly-recap-ready and weekly-report. Tracked as OI-133; this is the one tier this batch cannot close itself" }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "rolling-context is cron-dispatched; its schedule and telemetry wrapper are untouched. Separately, two UNREGISTERED destructive cron jobs were found live (jrd_retention_daily, client_errors_retention_daily) — pre-existing, filed as OI-132" }
  - { tier: 8, name: rls_policies, status: verified, evidence: "unchanged. founder_metrics_engagement ACL re-verified {postgres=X/postgres,service_role=X/postgres} by role assumption: anon DENIED, authenticated DENIED, service_role EXECUTED" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service touched" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the contract now terminates at a rendered widget rather than an HTTP body; the render test PUMPS EngagementTab, and a keys-absent case proves a migration rollback degrades to 0 instead of throwing" }
related_bugs:
  - { id: c7a3b9, relation: "the FOB-5 batch this corrects — it verified the columns at the RPC and stopped there" }
  - { id: d5b8f3, relation: "same Hermes pass, same root habit: verifying at the layer being looked at and not one further" }
recurrence: >
  SECOND finding in one pass whose root cause is a claim verified one layer too
  early, and the pair is what makes it a class rather than a slip. In d5b8f3 the
  formatters were behaviourally tested while their ARGUMENTS were not; here the
  columns were confirmed in the RPC response while the PARSER that reads them
  was not. Both times the verification performed was real, careful, and
  insufficient by exactly one hop.
  The tell is a claim phrased in terms of a mechanism ("the EF spreads the row",
  "the ACL is correct") rather than an observer ("the founder sees the number").
  Whenever the deliverable is that a human perceives something, the last
  assertion has to be at the surface a human perceives — a pumped widget, not a
  200.
---

# The hold mechanic stayed unobservable after the batch that made it observable

## Two claims, both false in different directions

FOB-5's own justification names OI-101 — *shipped but nothing calls it* — as the
thing it was avoiding by riding the existing RPC instead of minting
`founder_metrics_holds()`. That reasoning was sound about the RPC and blind
about everything downstream of it. Avoiding a dormant RPC by adding dormant
columns is the same failure with a smaller blast radius.

The second claim is subtler. The metric was not merely unrendered — it was
being actively eaten. `rolling-context` selected every row for a user with no
channel predicate, summarized them, and deleted the originals. The rows the
three new columns count were on that list.

## Why the filter goes on every read, and why "three" was wrong

The first version of this fix filtered three PostgREST chains in the TypeScript
and asserted the job was done. The B-pass falsified it: `rolling-context` calls
the RPC `get_users_with_message_count()` first (`index.ts:143`) and reaches the
manual queries only if that throws. The RPC's own SQL
(`010_add_indexes_idempotency_rpc.sql:76-83`) counts every row for a user with no
channel predicate — and its `where summarized = false` is a permanent no-op,
because nothing in the codebase ever writes `summarized = true`.

So two of the three filters were dead code on the live path. Nothing was
mis-deleted (the per-user FETCH filter runs regardless of which path selected the
user), but the threshold that decides *who gets processed* stayed exactly as
overcounted as before — and, now that app_event rows are never deleted, that
count grows without bound. A user whose analytics volume alone crosses 50 would
be selected nightly, have their entire history paged in, then be skipped.

The candidates are re-counted with the exclusion before the expensive fetch.
Re-validating in the function rather than adding a predicate to the RPC keeps
this a code-only change inside the redeploy already authorized — changing the
RPC is a migration apply and needs its own §4.3 go.

## Why the filter goes on the fallback reads too

The obvious fix is the per-user fetch. But the two candidate-selection queries
decide *whether a user is processed at all*, using a `>= 50 messages` threshold
computed over the same unfiltered table. Filtering only the fetch would leave a
user with 50 analytics events and no conversation selected for summarization,
then fetched with nothing to summarize. The threshold and the work have to mean
the same thing.

Excluded by channel rather than restricted to the three `_coachChatChannels`
deliberately: an allowlist would silently stop summarizing any future
conversational channel, which fails in the direction of losing real history.

## What the tests assert, and why not a grep

`rolling_context_excludes_app_event_test.dart` ENUMERATES every
`.from("ai_coach_interactions")` chain and requires each to carry the exclusion,
rather than grepping for the filter string. The difference is mutation B:

| mutation | grep | enumerate |
|---|---|---|
| remove the filter | red | red |
| **add a NEW unfiltered read beside the filtered ones** | **green** | **red** |
| demote the filter to a comment | green | red |

Mutation B is the shape of the original defect — five consumers read this table
and only one knew the taxonomy. A presence check cannot see a sixth arriving.

## What this does NOT close

- **The deploy.** `rolling-context` is unchanged in production. The repo now
  disagrees with the running function, which is OI-93's class, and an EF deploy
  needs its own authorization.
- **The 92 rows already embedded.** Filtering the writer does not unwrite
  history. They remain retrievable into the coach's system prompt.
- **The offline hold.** `AppEventsService` drops a failed insert with no queue
  and no retry, so a hold taken without connectivity emits nothing, ever. The
  tile says "min" because of this, not only because of the pruning.

All three are on OI-133 with the reasons, not implied by silence.
