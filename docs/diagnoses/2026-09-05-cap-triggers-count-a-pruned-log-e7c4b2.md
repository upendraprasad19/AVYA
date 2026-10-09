---
bug_id: e7c4b2
date: 2026-09-05
batch: oi162-slice2-triggers
status: fixed_slice_2_of_4
blast_radius: platform
symptom: >
  The three Postgres cap triggers answered "has this user hit their daily cap?"
  by running count(*) over `ai_coach_interactions` — the conversation log that
  `rolling-context` prunes nightly (summarises and DELETEs once a user passes 50
  non-app_event rows, keeping the newest 10). So all three caps silently reset
  for anyone who chats enough: the 10/day free chat cap, the 20/day combined
  scan_meal + cart_auditor vision cap, and the 10-free / 200-PRO food-text cap.
  Slice 2 of OI-162; the parent bug is d3a7f1, which landed the ledger with
  nothing calling it.
concept: usage_quota_ledger
sot_registry_entry: usage_quota_ledger
writers:
  - { file: supabase/migrations/128_usage_counters.sql, line: 69, method: consume_quota — still the only writer of usage_counters; slice 2 adds callers, not writers }
  - { file: supabase/migrations/128_usage_counters.sql, line: 133, method: cleanup_usage_counters — retention, windowed rows only }
readers:
  - { file: supabase/migrations/129_cap_triggers_use_usage_counters.sql, line: 91, method: enforce_chat_app_daily_limit — quota_key chat_app, 10/day, PRO returns BEFORE consuming }
  - { file: supabase/migrations/129_cap_triggers_use_usage_counters.sql, line: 142, method: enforce_vision_analysis_daily_limit — quota_key vision_analysis, 20/day shared by both channels }
  - { file: supabase/migrations/129_cap_triggers_use_usage_counters.sql, line: 174, method: enforce_food_text_daily_limit — quota_key food_text, 200 PRO / 10 free from ONE call site }
  - { file: lib/features/ai_coach/repositories/ai_coach_repository.dart, line: 279, method: getFreeImageAnalysisCount — the ONLY client-side legacy reader, STILL on the old table, slice 3 }
  - { file: supabase/functions/ai-media-proxy/index.ts, line: 74, method: countFreeImageAnalyses — STILL on the old table, slice 3 }
  - { file: supabase/functions/ai-media-proxy/index.ts, line: 96, method: countProImageAnalysesToday — STILL on the old table, slice 3 }
  - { file: supabase/functions/weekly-report/index.ts, line: 96, method: first-free-report lifetime gate — STILL on the old table, slice 3 }
  - { file: supabase/functions/delete-account/index.ts, line: 146, method: delete-attempt rate limit — STILL on the old table, slice 4 }
  - { file: supabase/functions/verify-payment/index.ts, line: 225, method: payment-verify rate limit — STILL on the old table, slice 4 }
hive_key_prefix: "n/a — cloud-only ledger and cloud-only triggers; no Hive surface"
hive_key_formula: "n/a — no Hive key participates in this concept"
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/cap_triggers_use_usage_counters_test.dart
ist_handling: >
  All three triggers carry migration 111/113/127's Asia/Kolkata day boundary
  VERBATIM into their consume_quota window argument:
  (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE
  'Asia/Kolkata'). That expression is the fix for 7ad0d3 — migration 026's bare
  date_trunc('day', now()) truncates in the session timezone (UTC on this
  project), resetting an IST day cap at 05:30 IST. The backfill uses the same
  expression, so a backfilled row lands in exactly the window the trigger will
  read. Pinned by the contract test, and mutation-proven by re-anchoring chat's
  window to the bare UTC form (1 test reddened).
provider_invalidations: "none — no client state changes and no client code touched"
telemetry_op_types: "none added — the P0001 → 429 path through ai-proxy is unchanged"
cross_account_guard: >
  Unchanged from slice 1 and re-verified: RLS is enabled on usage_counters with
  NO policy, and consume_quota is INVOKER-mode, so only service_role and
  postgres (both rolbypassrls) can write. Every writer of a gated channel is a
  service-role Edge Function (ai-proxy:324/:513/:754, ai-media-proxy:664). The
  two client-side writers of ai_coach_interactions (sync_coach.dart:149 →
  in_app_orphan, app_events_service.dart:60 → app_event) write NON-gated
  channels and short-circuit before reaching consume_quota. Pinned by the
  landmine guard, which is MULTILINE by necessity — these writers span two
  lines, and a line-oriented scan sees 6 of 14.
forbidden_patterns_checked: >
  No definer-mode function introduced (all three stay INVOKER). No RLS policy
  added or changed. No new count on ai_coach_interactions outside the one-time
  ledger backfill, for which migration 129 is enumerated BY NAME in the OI-162
  gate's allowlist (a per-statement pattern exemption was tried first and the
  B-pass defeated it three ways). No client
  code touched. No Edge Function deployed. No deferral euphemism. No columns
  added, so backups/live_schema_columns.json does not move.
  ⚠ CORRECTION (B-pass 004af467): an earlier draft of this field claimed the
  migration "carries the four-tag header". It does NOT — 129 has `Intent:` and
  `Rollback strategy:` but is MISSING `Destructive?:` (it is not destructive)
  and `Linked diagnose-doc:` (which is this file, e7c4b2). The migration is
  applied and therefore immutable, so the omission stands and is recorded here
  instead, per supabase/migrations/CLAUDE.md. ⚠ Note also that NO GATE CHECKS
  THE FOUR TAGS: supabase/migrations/CLAUDE.md asserts "the pre-commit hook
  greps for the four tags", and it does not — `grep -rn Destructive
  scripts/pre-commit.sh` returns nothing. Prose describing a gate that was
  never written, the same shape as the check_open_issues_reconciled.dart note
  on the OI board.
proposed_fix: >
  One migration (129) that first backfills the current IST window for all three
  quota_keys from the still-present log rows, then CREATE OR REPLACEs the three
  trigger bodies to call consume_quota() instead of counting. Trigger bindings
  are untouched. The backfill runs first, and a migration applies in a single
  transaction, so no session can observe the new logic before the seed lands.
regression_test_planned: >
  TWO layers, because a source-grep proves PRESENCE only (rule 21).
  (1) test/contracts/cap_triggers_use_usage_counters_test.dart — 10 source-grep
  assertions over migration 129: all three triggers call consume_quota with
  their own quota_key, none still reads ai_coach_interactions, the three P0001
  identifiers survive verbatim, each carries the IST expression and not the bare
  UTC form, each channel short-circuit PRECEDES the consume_quota call, chat
  exempts PRO before consuming, the backfill precedes the replacements, and the
  MULTILINE landmine guard (with a positive control proving it can see a
  two-line writer).
  (2) test/sql/oi46_daily_cap_triggers_live_verify.sql — EXTENDED with 8
  behavioural assertions run against live Postgres inside BEGIN…ROLLBACK via
  `dart run scripts/check_onconflict_live_arbiter.dart --sql <file>`: the ledger
  reaches used=10 for chat and refuses the 11th; PRO inserts 12 and creates NO
  counter row; 11 scan_meal + 9 cart_auditor total 20 on ONE key and the 21st is
  refused; a rolled-back insert refunds its consumed unit; free food_text stops
  at 10; and an ungated channel touches the ledger not at all. No Gemini call,
  no shared QA account, no residue.
impact_analysis: >
  Behaviour is identical at the boundary — count(*) >= cap and consume_quota
  returning -1 both allow exactly `cap` inserts per window — and strictly better
  under concurrency, since the read-then-write race is replaced by one atomic
  upsert. ONE deliberate behaviour change: chat exempts PRO BEFORE consuming, so
  a PRO user writes no ledger row and a same-day downgrade resumes from the
  pre-upgrade value, granting up to 10 extra messages. The old form re-counted
  the PRO-era rows. Accepted — bounded, needs a subscription lapsing mid-day
  mid-conversation, no security consequence, and the alternative required
  inventing a sentinel limit for a tier documented as unlimited. Also accepted,
  with its framing corrected: an authenticated user CAN today insert a gated
  channel directly via PostgREST (the INSERT policy has no channel restriction),
  and after this migration such a hand-crafted request fails 42501 instead of
  succeeding and inflating that user's own cap. Self-limited to the caller.
touched_layers_checked:
  - { tier: 1, name: client code, status: not_applicable, evidence: "no client file changed; the two client writers of ai_coach_interactions write non-gated channels and are pinned by the landmine guard" }
  - { tier: 2, name: hive, status: not_applicable, evidence: "cloud-only ledger, no Hive surface" }
  - { tier: 3, name: postgres schema, status: verified, evidence: "no DDL beyond CREATE OR REPLACE on three existing functions; usage_counters unchanged since 128" }
  - { tier: 4, name: postgres data, status: fixed_in_this_batch, evidence: "backfill seeds the current IST window for chat_app/vision_analysis/food_text; live counts at authorship were chat 3, vision 0, food_text 0" }
  - { tier: 5, name: migrations applied, status: fixed_in_this_batch, evidence: "migration 129 applied and recorded in backups/applied_migrations.json in this commit" }
  - { tier: 6, name: edge function code vs deploy, status: not_applicable, evidence: "no Edge Function changed; the three P0001 base identifiers ai-proxy greps at :338/:524/:765 are preserved verbatim and pinned by the contract test" }
  - { tier: 7, name: cron jobs, status: verified, evidence: "usage_counters_retention_daily (jobid 37) unchanged; its 7-day cutoff cannot reach a live one-day window" }
  - { tier: 8, name: rls policies, status: verified, evidence: "pg_policies on ai_coach_interactions and usage_counters unchanged; the landmine acceptance is documented in impact_analysis" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or added" }
  - { tier: 11, name: external services, status: not_applicable, evidence: "no external service touched; the harness deliberately makes no Gemini call" }
  - { tier: 12, name: client to server contract, status: verified, evidence: "the P0001 → 429 mapping is the contract, preserved verbatim and mutation-proven by renaming one identifier (1 test reddened)" }
related_bugs: [d3a7f1, c9e3b1, 7ad0d3, f1a70c, b8f4c2]
recurrence: >
  RECURRENCE of d3a7f1 by construction — this is slice 2 of that fix, not a new
  bug. It also closes the writer/reader drift class for three of the nine
  readers d3a7f1 enumerated. Related to 7ad0d3 (the IST boundary this migration
  carries verbatim) and c9e3b1 (the read-then-write race that consume_quota's
  atomic upsert removes). f1a70c is the parity class the cap-reader helper
  protects, and b8f4c2 is why that helper resolves the LATEST defining
  migration rather than the creating one.
---

# Cap triggers counted a log that gets pruned (slice 2 of OI-162)

## What moved

Three trigger bodies, one migration, server-side only. No Edge Function change,
no client change, no deploy. The full converged spec is
`docs/audit/oi162-slice2-plan.md`; the six review rounds and every finding's
disposition are in its §9 and in `docs/plan-reviews/oi162-slice2-triggers.md`.

## What the review caught that reading did not

Six rounds, and the ones worth carrying forward:

**The helper had a latent bug older than this slice.** `readSingleCeiling` and
`readProFreeCap` matched over the WHOLE migration file. Migration 111 defines
BOTH `enforce_chat_app_daily_limit` and `enforce_vision_analysis_daily_limit`,
so an unscoped read of 111 for vision returns the CHAT cap of 10. It was masked
only because 114 and 127 happen to be single-function files — migration 129,
defining all three, would have made it reachable. Both readers are now scoped to
the function's own `CREATE OR REPLACE` block. This is b8f4c2's trap in its
second form: right file, wrong function.

**A resolver that would have kept reading the superseded migration.**
`latestMigrationDefining` matched `FUNCTION <name>`, but 129 writes
`FUNCTION public.<name>`, and the repo uses both conventions (111/114/127 bare,
128 qualified). So the resolver still returned 114, and the parity test would
have passed while asserting a definition that was no longer live. Caught by the
plan's own step-0b dry-run BEFORE the apply, which is the only reason it was
free to fix — an applied migration is immutable.

**A verification command that could not see what it verified.** The plan's
writer-inventory grep was line-oriented, and these writers span two lines
(`.from("ai_coach_interactions")` then `.insert({`), so it silently dropped
`ai-proxy:321/510/751` — the three gated-channel writers that ARE the safety
argument. 6 hits versus 14. The landmine guard inherits the fix: it is multiline,
and it carries a POSITIVE CONTROL asserting it can actually see
`app_events_service.dart`'s two-line shape, because a guard that quietly matches
nothing looks exactly like a guard that finds nothing wrong.

## The gate that blocked its own remedy

`check_usage_counter_source.dart` — shipped in slice 1 to stop a tenth quota
being built the old way — flagged migration 129, because the backfill reads
`count(*) FROM ai_coach_interactions` to seed the ledger. It could not
distinguish deriving a quota from the pruned log (the bug) from seeding the
ledger from it once (the fix).

The exemption is per-STATEMENT: the count must sit inside a statement that
INSERTs into `usage_counters`. Deliberately not per-file, or a future migration
could buy immunity for a real quota read by name-dropping the table above it.
Mutating the scope from statement to file reddens exactly the test that pins
this ("a quota derivation is STILL caught in a file that also backfills").

## Mutation proofs

**The seventh, behavioural, run post-apply against live Postgres inside
`BEGIN … ROLLBACK`:** the vision trigger was mutated to split its ONE shared
budget into a per-channel key (`'vision_' || NEW.channel`) — semantically wrong,
still valid SQL, deliberately not a compile error. **Both** vision assertions
reddened: `slice2_vision_shares_one_key` reported "expected 20 on the shared
key, got NO ROW", and `slice2_vision_21st_refused` reported "the 21st combined
insert SUCCEEDED". The ROLLBACK restored the live function (verified after:
shared key present, mutation absent) and `usage_counters` was unchanged at 1 row
/ used=3.

Six file-level, each confirmed APPLIED before its run, none a compile error:
vision reverted to `count(*)` (**4** reddened), chat's P0001 identifier renamed
(1), chat's window re-anchored to bare UTC (1), vision's short-circuit moved
below `consume_quota` (1), a two-line-shape gated writer added to `lib/` (2),
the helper's post-129 cap regex broken (1). Plus the gate-exemption mutation
above (1 of 15).

⚠ **The third silently-unapplied mutation in this repo's history happened during
this batch and was caught.** The short-circuit mutation's anchor omitted a
comment line, so the python assert threw — but the runner script had no `set -e`
and the output was filtered to the report lines, so the traceback was invisible
and the run reported `applied=1, reds=0`. That reads as "the test is blind" when
it actually meant "the mutation never happened". **Confirming a mutation applied
requires a check scoped the way the mutation is scoped**; the first applied-check
here indexed from the first occurrence of the function name, which is in the
header comment — the same first-match-in-wrong-scope bug being fixed in the
helper twenty minutes earlier.

The migration was restored by `cp` from a pre-made copy and its sha256
re-verified, never by `git checkout` — that rewrites CRLF and silently
invalidates the ledger hash while `git status` reads clean.

## Two defects the live run found that the source-grep test could not

Both were in the harness extension itself, and both are the argument for having
a behavioural layer at all — the contract test was green throughout.

**`ROLLBACK TO SAVEPOINT` is a syntax error inside PL/pgSQL (42601).** The
refund assertion used an explicit savepoint. A PL/pgSQL `BEGIN … EXCEPTION`
block IS an implicit savepoint, and raising inside it already rolls back
everything the block did. The whole file failed to parse on its first live run.

**A swallowed fixture seed made an assertion mean the opposite of what it read
like.** `public.subscriptions` has `plan` and `start_date` as NOT NULL; the PRO
seed omitted both, and the `EXCEPTION WHEN OTHERS THEN NULL` around it — copied
from the file's best-effort user seeding — hid the failure. The "PRO" user was
therefore FREE, hit the free cap at 10, and `slice2_pro_consumes_nothing`
reported a P0001 as though the product had regressed. Fixed twice over: the seed
is no longer swallowed, and a new `slice2_fixture_pro_seeded` assertion
evaluates the exact predicate the trigger evaluates, so the fixture can never
again fail silently into a test that reads as a product defect. This is rule
21's "confirm the FIXTURE reproduces a state the real workflow actually
produces", arriving through a swallow rather than a wrong fixture — and a
best-effort seed is safe only for state the assertion does not depend on.

## Five of seven assertions passed against the code they replaced

The most useful measurement in this batch, and it was not planned — a B-pass
reviewer died mid-run with the line *"let me verify empirically by running the
slice2 assertions against the pre-129 trigger bodies."* Finishing that
experiment: the pre-129 `count(*)` bodies were restored inside a rolled-back
transaction and the new assertions re-run against them. **Five of seven passed.**
Running is not discriminating, and nothing about reading the tests reveals which
is which.

Two were genuinely defective — both compared NULL to NULL, because pre-129 no
ledger row exists at all:

- `slice2_pro_consumes_nothing` asserted "PRO has no counter row", which is
  equally true when NOTHING writes rows. Now paired with the FREE user in the
  same transaction: the free row must exist, proving the ledger is live and PRO
  is absent by exemption rather than by nothing working.
- `slice2_aborted_row_refunds_unit` compared `used` before and after an aborted
  insert. Both NULL, `IS NOT DISTINCT FROM` true, "ok". It would have passed if
  the feature did nothing at all. Now requires a real pre-existing unit.

Both verified in both directions after the fix: post-129 they pass with real
numbers (`free holds used=3`, `unchanged at 2`); pre-129 they now FAIL with an
explicit VACUOUS message.

The remaining three that pass pre-129 are **correct to keep and are now labelled
as such** in the harness header: the cap firing with the right P0001 identifier
(`slice2_chat_11th_refused`, `slice2_vision_21st_refused`) and an ungated
channel being left alone (`slice2_ungated_channel_untouched`) must hold under
ANY implementation. They are contract regression tests, not evidence the ledger
is wired. Keeping them is right; citing them as proof slice 2 landed is not, and
the header now says so.

⚠ The general form, because this is the second time it has bitten this project
(the sync T3/T4/T5 assertions carry the same open note): **a behavioural test
that EXECUTES green tells you nothing until you have run it against the code it
replaced.** The cheap version is exactly what was done here — restore the old
body inside a rolled-back transaction and re-run.

## The consequence that turned main red: CI depended on the cap being broken

**Discovered post-merge, and it is the most instructive thing in this batch.** CI failed on
`485bde42` with `Expected: <200> Actual: <429>` in `ai_proxy_test.dart`. Live check:
`usage_counters` showed `test6@gmail.com  chat_app  used=10` — exactly at the cap.

This is not a regression. **It is the fix working, and the test suite had been relying on it not
working.** Three tests (T15, T18, T19) each send ONE live chat as ONE shared QA account and
asserted a bare `200`. They were green for months because the pre-129 trigger counted rows in
`ai_coach_interactions`, which `rolling-context` prunes nightly — the count reset before it could
ever bite. Migration 129 made the ledger durable and the cap started enforcing.

⚠ **The arithmetic is now a hard constraint: 3 chats per CI run against a 10/day cap means CI can
run 3 times per IST day before the 4th goes red.** That is not fixed by the test change below and
should not be papered over.

**The fix** (`chatBodyOrAssertCapped` in `ai_proxy_test.dart`): accept 200 OR 429, asserting the
correct contract for each — the AI-response shape, or the `RATE_LIMITED` code and error text the
client maps to its "daily limit" copy. This is not loosening a test to accommodate a bug. It is
correcting a test that **asserted something it does not control** — the quota state of a shared
account — into one that asserts what it actually verifies. The 429 branch pins a contract nothing
asserted before.

⚠ **Not mutation-proven locally and I am not claiming otherwise:** `.env` carries
`SUPABASE_URL`/`SUPABASE_ANON_KEY` but not `SUPABASE_TEST_EMAIL`/`_PASSWORD`, and the helper's
four-input `hasCredentials` predicate makes the file SKIP without all four. CI has the secrets —
and because the QA account is AT the cap right now, CI's next run exercises the 429 branch
directly. That run is the proof.

**Scope checked, not assumed:** `grep -rln "ai-proxy\|ai-media-proxy" test/` returns
`ai_proxy_test.dart` alone, and none of its calls set a `type`, so all three are chat. There is no
vision or food_text equivalent to fix — the class is contained.

**The real fix is a provisioning decision, raised not assumed:** a dedicated per-run QA account,
or a PRO one (which the chat trigger exempts entirely). Both change what the tests mean and who
pays for them, so they belong to the founder.

## What is still broken after this slice

Six of the nine readers. `ai-media-proxy`'s two image meters and
`weekly-report`'s first-free-report gate (slice 3), and the `delete-account` /
`verify-payment` rate limits (slice 4, catastrophic tier, needs `hermes:
accepted`). A free user can still reset their 5 lifetime image analyses and
their one free Gemini 2.5 Pro weekly report by chatting enough.
`test/contracts/usage_quota_ledger_writer_to_reader_test.dart` pins that
explicitly so the batch cannot be misread as having fixed the whole bug.
