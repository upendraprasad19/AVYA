---
bug_id: f4a2d8
date: 2026-09-06
batch: oi162-slice3-lifetime-meters
status: fixed_slice_3a_of_4
blast_radius: platform
symptom: >
  The one free weekly report silently regenerated. `weekly-report`'s first-free
  gate asked "has this user ever generated a report?" by counting rows in
  `ai_coach_interactions` with channel='weekly_report' and NO date bound. Those
  rows are non-`app_event`, so `rolling-context` summarises and DELETEs all but
  the newest 10 once a user passes 50 — and a LIFETIME quota has no window to
  survive deletion on. A free user who chatted enough got another free
  Gemini 2.5 Pro report, repeatedly. Slice 3a of OI-162; parent bug d3a7f1.
concept: weekly_report_pro_gate
sot_registry_entry: weekly_report_pro_gate
writers:
  - { file: supabase/functions/weekly-report/index.ts, method: "consume_quota('weekly_report_free', 'epoch') — the QUOTA writer, gated on !hasPro, running AFTER the insert" }
  - { file: supabase/functions/weekly-report/index.ts, method: "ai_coach_interactions insert — unchanged, the SOLE persisted copy of the report and the restore source; no longer feeds the gate" }
  - { file: supabase/migrations/128_usage_counters.sql, line: 69, method: consume_quota — the ledger's only writer }
readers:
  - { file: supabase/functions/weekly-report/index.ts, method: "advisory usage_counters read feeding isFirstReport, then the 403" }
  - { file: supabase/functions/ai-media-proxy/index.ts, line: 74, method: countFreeImageAnalyses — STILL on the old table, slice 3b }
  - { file: supabase/functions/ai-media-proxy/index.ts, line: 96, method: countProImageAnalysesToday — dormant, OI-153 }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, line: 279, method: getFreeImageAnalysisCount — zero callers, slice 3b }
  - { file: supabase/functions/delete-account/index.ts, line: 146, method: delete-attempt rate limit — slice 4 }
  - { file: supabase/functions/verify-payment/index.ts, line: 225, method: payment-verify rate limit — slice 4 }
hive_key_prefix: "n/a — server-side gate, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/weekly_report_lifetime_meter_test.dart
ist_handling: >
  Not applicable by design, and that is the point: this is a LIFETIME quota, so
  it uses the timezone-free `'epoch'` sentinel window_start rather than an IST
  day bucket. Verified live that the TS literal `1970-01-01T00:00:00+00:00`
  equals `'epoch'::timestamptz`, and that a row written by consume_quota at that
  value is found by a read filtering on the same literal.
provider_invalidations: "none — no client state changes and no client code touched"
telemetry_op_types: >
  Two new server-side log lines, deliberately distinguished: console.error on a
  populated RPC error (a real under-count), console.warn on a -1 return (a
  concurrent first-ever request that won the race past the advisory gate). -1 is
  a SUCCESSFUL return, so logging it as an error would fire on ordinary second
  attempts and drown the real signal.
cross_account_guard: >
  usage_counters' PK is (user_id, quota_key, window_start) and every read and
  write here is scoped to targetUserId, so no cross-user read is expressible.
  The function is service-role and verify_jwt=true; the caller is resolved via
  auth.getUser(token) before any of this runs.
forbidden_patterns_checked: >
  No migration (quota_key is unconstrained text; nothing to backfill — the
  channel has zero rows and `summarized` is 0 repo-wide, so never-used rather
  than pruned). No definer-mode function. No RLS change. No client code touched.
  No new channel value minted, which is why OI-153's channel-enumeration blocker
  does not bind. No deferral euphemism. Migration 130 NOT consumed — it stays
  free for slice 4 or a concurrent session.
proposed_fix: >
  Move the gate's READ onto usage_counters and add consume_quota as its writer,
  leaving the ai_coach_interactions insert untouched. Three properties are
  load-bearing and none is optional: (1) the insert stays verbatim and
  unconditional, because it is the sole persisted copy of the report and the
  restore source; (2) consume_quota runs AFTER it and is gated on !hasPro, since
  the gate never refuses PRO and reports_screen fires on every screen open;
  (3) the advisory read uses .maybeSingle() and treats an ABSENT row as a
  legitimate used=0 that GRANTS — only a populated error fails closed. No
  migration is required: quota_key is unconstrained text and there is nothing to
  backfill.
regression_test_planned: >
  test/contracts/weekly_report_lifetime_meter_test.dart — 9 source-grep
  assertions: consume_quota called with the free-tier key; the epoch sentinel;
  the gate reads usage_counters and no longer counts the channel; .maybeSingle()
  and never .single(); an absent row yields used=0 (GRANT) while only an error
  denies; PRO does not consume; the ai_coach_interactions insert survives
  unconditional; the insert PRECEDES the consume; and the OI-162 gate's
  allowlist is ratcheted to 0 for this file.
  PLUS the repointed test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart.
impact_analysis: >
  A free user gets exactly one weekly report, permanently, instead of one per
  prune cycle. PRO is unaffected — the gate never refused PRO and now never
  consumes for PRO either. ONE deliberate behaviour change beyond the fix: the
  ledger freezes while a user is PRO, so a downgrade resumes from the
  pre-upgrade value; the same asymmetry migration 129 records for chat.
  Bounded residual: two SIMULTANEOUS first-ever requests can both pass the
  advisory gate, so a free user could receive at most ONE extra report, once,
  ever — accepted, because the alternative (consume at the gate) burns a
  LIFETIME unit on a Gemini outage with no refund path.
touched_layers_checked:
  - { tier: 1, name: client code, status: not_applicable, evidence: "no client file changed; reports_screen.dart reads only the response it already receives" }
  - { tier: 2, name: hive, status: not_applicable, evidence: "server-side gate, no Hive surface" }
  - { tier: 3, name: postgres schema, status: verified, evidence: "no DDL — quota_key is text NOT NULL with zero CHECK constraints, verified via information_schema" }
  - { tier: 4, name: postgres data, status: verified, evidence: "zero rows for weekly_report_free at cutover, and summarized=0 on every channel — never used, not pruned; so no backfill" }
  - { tier: 5, name: migrations applied, status: not_applicable, evidence: "no migration; 130 deliberately left free" }
  - { tier: 6, name: edge function code vs deploy, status: fixed_in_this_batch, evidence: "weekly-report changed; deploy is a separate explicitly-authorized step AFTER the B-pass" }
  - { tier: 7, name: cron jobs, status: verified, evidence: "usage_counters_retention_daily unchanged; an 'epoch' row is excluded by the predicate's first conjunct — verified by executing cleanup_usage_counters() against a live epoch row" }
  - { tier: 8, name: rls policies, status: verified, evidence: "unchanged; the EF is service-role so RLS-with-no-policy does not obstruct it" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or added" }
  - { tier: 11, name: external services, status: verified, evidence: "Gemini call path untouched; the gate runs before it exactly as before" }
  - { tier: 12, name: client to server contract, status: verified, evidence: "the 403 NOT_PRO shape is unchanged; only what decides it moved" }
related_bugs: [d3a7f1, e7c4b2, e4d1b7, c9e3b1]
recurrence: >
  RECURRENCE of d3a7f1 by construction — slice 3a of that fix. Same class as
  e7c4b2 (slice 2, the three cap triggers) but on the Edge Function side, which
  is a materially different problem: a trigger runs as postgres inside the
  INSERT's transaction, while an EF makes two independent PostgREST calls with
  no transaction spanning them. e4d1b7 is this gate's own earlier fail-open fix.
---

# The free weekly report regenerated itself (slice 3a of OI-162)

## What moved

One Edge Function. The gate reads `usage_counters` instead of counting a log
`rolling-context` prunes. No migration, no client change, no schema change.

Full spec and seven review rounds: `docs/audit/oi162-slice3-plan.md`.

## The two things that would have shipped

**The `.single()` lockout.** Round 6. Replacing a `count: "exact"` read with a
value-select adds a third outcome that did not exist before — `data: null,
error: null`, the successful read of an absent row. My own round-3 remediation
had hardened *"an unreadable counter refuses"*, written for the error branch,
and it swallows the absent branch. **Every user is in the absent state at
cutover** (zero rows for this key), so that would have refused every first-time
free user permanently. The file offers both `.single()` (throws PGRST116 on zero
rows) and `.maybeSingle()` precedents, so picking wrong was plausible.

⚠ **A guard's mirror can be created by the guard's own fix.** "I already checked
the mirror" was true of the original design and false of the fixed one. Recorded
as instance #24 of that class.

**The silent write.** The `ai_coach_interactions` insert had to stay verbatim —
it is the only persisted copy of the report text (`reports_screen.dart` caches
one, not a list) and the row a reinstall restores (`sync_coach.dart` restores
every channel unfiltered). An early draft said `consume_quota` "replaces" it.

## Verified live, not argued

In one rolled-back transaction: the TS literal equals `'epoch'::timestamptz`;
an absent row reads as NULL (→ GRANT); the first consume returns 1 and **the
reader finds that write** through the same filter the EF uses; the second
returns -1; and the row survives `cleanup_usage_counters()`. Separately, the RPC
signature was checked against `pg_proc` — `p_user_id, p_quota_key,
p_window_start, p_limit` — because a mismatched argument name would be a
**silent** failure: the code logs errors rather than throwing, so a completely
broken consume would look exactly like success while the bug persisted.

## Mutation proofs (rule 21)

Nine, each confirmed APPLIED by an anchor check before its run, baseline and
restored both green:

| Mutation | Tests reddened |
|---|---|
| Remove the `!hasPro` gate | 1 |
| Flip fail-closed to fail-OPEN | 2 |
| Typo the quota_key | 2 |
| `'epoch'` → a real timestamp | 1 |
| Advisory read points back at `ai_coach_interactions` | 2 |
| Absent row conflated with used | 1 |
| Record writer stops stamping the channel | 3 |
| Un-ratchet the allowlist | 1 |
| Swap the insert and consume order | 1 |

## The gate now proves the migration landed

`check_usage_counter_source.dart`'s allowlist for this file dropped 1 → **0**,
and its known-EF-counter total 5 → 4. That is not decoration: `sweep()` only
flags `count > allowed`, so leaving it at 1 would let a revert to the old
`ai_coach_interactions` count pass silently.

## What is still broken

Five of nine readers. `ai-media-proxy`'s free-image lifetime meter and its dead
client twin (slice 3b), the dormant PRO image cap (OI-153, a product decision —
migrating it would ACTIVATE a cap that has never fired), and the two
catastrophic-tier rate limits in `delete-account` and `verify-payment` (slice 4,
`hermes: accepted` required).
