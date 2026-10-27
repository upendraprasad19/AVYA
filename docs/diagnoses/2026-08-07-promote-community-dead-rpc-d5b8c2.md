---
bug_id: d5b8c2
date: 2026-08-07
batch: oi-unit1
status: fixed
blast_radius: feature
symptom: |
  `promote-community-item` (daily cron, job `promote_community_item_daily`)
  opened both of its promotion paths with a call to the Postgres RPC
  `community_votes_summary`. That function does not exist — in any schema, on
  this project. PostgREST reports a missing function as an `error` object rather
  than throwing, so the call returned `{data: null, error}` and the
  `candidates ?? (await fallbackCount(...))` fell through to the local tally on
  every single tick. The "primary" ranking path had never executed in
  production.

  The failure was also unreportable. It was guarded by
  `if (countErr && !list) console.warn(...)`, but `fallbackCount` returns `[]`
  on failure and `![]` is `false` in JavaScript, so the condition could not be
  true even when `countErr` was set. A dead guard wrapped a dead call, and the
  pair read as working error handling.
concept: community_review_queue
sot_registry_entry: community_review_queue
writers:
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: "promoteFoods — copies an approved user_custom_foods row into food_database", line: 118 }
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: "promoteExercises — copies an approved user_custom_exercises row into exercise_library", line: 174 }
readers:
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: "countApproveVotes (was fallbackCount) — THE approve-vote tally, paged via fetchAllPages", line: 248 }
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: "promoteFoods call site — now calls the tally directly", line: 122 }
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: "promoteExercises call site — now calls the tally directly", line: 177 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: community_reviews
cloud_columns: [item_type, item_id, vote, reviewer_id]
contract_test_path: test/contracts/promote_community_vote_tally_test.dart
ist_handling:
  - "Not applicable — this function tallies votes by item, with no date key, no counter reset and no IST-scoped column. Its cron schedule is unchanged."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Not applicable in the client sense — this is a service-role cron with
  BYPASSRLS. The relevant guard is the DPDP pseudonymization one and it is
  UNCHANGED by this fix: migration 049 set ON DELETE SET NULL on
  user_custom_foods / user_custom_exercises, so a hard-deleted account leaves
  rows with `user_id = NULL`, and the existing `if (source.user_id)` check
  before `notifySubmitter` still guards that. This fix touches only the vote
  tally, never the row-copy or the notify path.
forbidden_patterns_checked:
  - { pattern: "live .rpc( call in promote-community-item (comment-stripped source)", absent: true }
  - { pattern: "community_votes_summary in live code (comment-stripped source)", absent: true }
  - { pattern: "countErr identifier anywhere in live code", absent: true }
  - { pattern: "oi79-ok waiver comment in this file (raw source — a waiver IS a comment)", absent: true }
  - { pattern: "fetchAllPages + orderBy retained on the tally (OI-79 must not regress)", absent: false }
proposed_fix: |
  Delete both `.rpc("community_votes_summary")` calls, both `oi79-ok` waiver
  comments, and both dead `if (countErr && !list)` guards. Rename
  `fallbackCount` -> `countApproveVotes` and call it directly, since it is not a
  fallback to anything and never was. Rewrite its doc comment, which described
  itself as a "fallback count query if the RPC helper doesn't exist yet" — the
  helper was never written.

  DECISION RECORD. OI-82 explicitly reserved create-the-RPC vs. delete-the-call
  as a product decision rather than a mechanical fix. The founder took it on
  2026-08-07: delete. The evidence behind it:
    - No migration in the repo has ever defined the function. The single textual
      match in supabase/migrations is a PROSE COMMENT in
      101_admin_dashboard_metrics_functions.sql:16, which cites
      `community_votes_summary` as an example of an existing public function the
      repo already calls. It is not one, and never was — so migration 101's
      stated rationale for choosing the `public` schema rests partly on a
      function that does not exist. NOT corrected in this commit, deliberately:
      migration 101's body already contains the literal phrase "SECURITY
      DEFINER" (line 33, plus the `security definer` clauses on the three
      functions it defines), and `blast_radius_content_rules_lib.dart` escalates
      any `supabase/migrations/**.sql` whose WHOLE-FILE content matches
      `/security\s+definer/i` — so touching that file at all, even for a
      comment, moves this batch from platform to catastrophic tier and pulls in
      a hermes pass. Measured, not assumed: with the file staged
      `blast_radius_from_diff.dart` reports `catastrophic`; without it,
      `platform`. Tracked as its own ledger entry (MIG-101-COMMENT) to ride with
      the OI-78 unit, which has to touch migrations at that tier regardless.
    - There was therefore no unapplied migration to restore. This was
      speculative code whose helper was never authored.
    - `countApproveVotes` already computes exactly what the RPC's name promises:
      approve votes grouped per item_id, same `{item_id, approves}` shape, and
      both paths apply `APPROVAL_THRESHOLD` identically in TypeScript. Creating
      the RPC would have meant inventing ranking behaviour nobody specified, to
      replace a path that already works.
  The waiver comments had to go WITH the calls, not after them:
  `check_unbounded_cron_reads.dart` matches `oi79-ok` waivers by line proximity,
  so a waiver whose target is deleted can drift onto a neighbouring read and
  silently bless it — a failure mode that gate's own comments name.
regression_test_planned:
  - test/contracts/promote_community_vote_tally_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No Flutter client code touched. The client's role in this concept is casting votes via SubmissionsRepository.castCommunityVote, which is unchanged." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Promotion is entirely server-side; no Hive key participates." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "LIVE 2026-08-07 against dedsavbjuwgarrhphgnl: `SELECT n.nspname, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proname='community_votes_summary'` returned ZERO ROWS — re-confirming the premise TODAY rather than inheriting the OI's 2026-08-01 claim. No schema change made by this fix." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "LIVE 2026-08-07: approve_votes_total=0, custom_foods_approved=0, custom_ex_approved=0, food_database source='community'=0, exercise_library source='community'=0. The entire community-promotion surface is dormant — nothing has ever been promoted, so this change cannot alter any existing outcome." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration authored or applied. backups/applied_migrations.json untouched, correctly." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "Source fixed and pinned by test/contracts/promote_community_vote_tally_test.dart (5 assertions, negative-controlled by reinstating the defect: 2 fail, then pass again on restore). NOT YET DEPLOYED — see impact_analysis. The deployed bundle still contains the dead RPC call until a redeploy, which is a separate explicit-go action per §4.3 and is recorded as such in the closure ledger rather than left implicit." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Schedule and dispatch untouched — job `promote_community_item_daily` still calls the same function slug. This fix changes only what the function does after it boots." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched. The function runs service-role/BYPASSRLS exactly as before." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved in vote tallying." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read, added or rotated." }
  - { tier: 11, name: external_services, status: verified, evidence: "OneSignal is reached only via notifySubmitter, which sits after the row-copy and is untouched, including its existing `if (source.user_id)` null-guard for DPDP-pseudonymized rows." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The client writes community_reviews rows (SubmissionsRepository.castCommunityVote); the cron reads them. That contract is unchanged — this fix removes a call that never returned data and promotes the tally that always did. Column refs (item_type, item_id, vote) are unchanged and still resolve against backups/live_schema_columns.json." }
impact_analysis: |
  NO BEHAVIOUR CHANGE IN PRODUCTION, and that is provable rather than asserted:
  the deleted path never once returned a row (the function it called does not
  exist), so removing it cannot change any outcome. Tier-4 evidence shows the
  whole surface is dormant besides — 0 approve votes, 0 promotions, ever.

  What DOES change is diagnosability. The function no longer issues a request
  that fails on every tick, and no longer carries a warning branch that cannot
  execute. If vote tallying fails in future, `countApproveVotes`'s own catch
  logs it and returns `[]`.

  NOT YET LIVE. This is a source fix only. The deployed bundle still contains
  the dead call, and per §4.3 an Edge Function deploy is a separate explicit
  authorization — plan approval is not deploy approval. This container also has
  no `supabase/.supabase/` access token, so the host-shell deploy path is not
  available from here regardless. Recorded as `blocked_on_user` in the closure
  ledger rather than silently omitted, because conflating "committed" with
  "live" is exactly what OI-47 got caught doing.

  LATENT ISSUE FOUND, NOT FIXED HERE, FILED SEPARATELY. Promotion has TWO
  independent mechanisms: this cron, and the SECURITY DEFINER trigger
  `auto_approve_community_item` (read live from pg_proc — it is defined
  cloud-only and appears in NO repo migration, which is its own traceability
  gap). Both use a threshold of 10. The trigger fires on the 10th approve vote
  and sets `approved = true` / `approved_for_library = true` on the SOURCE row.
  The cron then skips any row where `source.approved === true` before copying it
  into `food_database` / `exercise_library`. Read literally, the trigger always
  wins the race, so the cron's copy-and-notify step would never run and no
  community item would ever reach the public library. This is stated as a
  READING, not an observation: with 0 approve votes ever cast, the interaction
  has never been exercised, so it is unproven. Filed as a new board entry with
  this evidence rather than fixed inside a vote-tally cleanup, because deciding
  which of the two mechanisms owns promotion is a product question.
related_bugs: []
recurrence: |
  Not a recurrence of a prior diagnose-doc, stated explicitly so a future audit
  can verify rather than assume.

  It IS a second instance of the source-grep-false-confidence class, in its most
  literal form: a `console.warn` that reads as error
  handling, wired to a condition (`countErr && !list`) that is unsatisfiable
  because `![]` is false. Source-grepping this file for "does it handle RPC
  errors?" returns yes. Executing it returns never. The OI-79 paging audit
  waived these two reads as "cannot truncate" — true, and irrelevant: they could
  not return rows at all.
---

# d5b8c2 — promote-community-item called an RPC that has never existed

## The three-line mechanism

```js
const { data: candidates, error: countErr } = await admin.rpc("community_votes_summary", …);
const list = candidates ?? (await fallbackCount(admin, …));   // candidates is ALWAYS null
if (countErr && !list) console.warn(…);                        // ![] === false, so NEVER
```

`.rpc()` on a missing function resolves with an error object rather than
rejecting (supabase-js only rejects under `.throwOnError()`, which is not used
here), so `candidates` is `null`, the `??` always evaluates the tally, and the
error is dropped by a guard that cannot fire.

## Live verification (§4.9 — never act on a claimed cloud state without checking)

Run 2026-08-07 against `dedsavbjuwgarrhphgnl`:

| Query | Result |
|---|---|
| `pg_proc` ∀ schema for `community_votes_summary` | **0 rows** |
| `community_reviews WHERE vote='approve'` | **0** |
| `user_custom_foods WHERE approved` | **0** |
| `food_database WHERE source='community'` | **0** |
| `exercise_library WHERE source='community'` | **0** |

The first row re-establishes the fix's premise today. The rest establish that
the surface is dormant, which is why this closure claims a diagnosability
improvement and explicitly does NOT claim a user-visible fix.

## Negative control (executed, then reverted)

Reinstating the exact original shape — the `.rpc` call plus the
`if (countErr && !list)` guard — fails
`promote_community_vote_tally_test.dart` on 2 of 5 assertions ("the RPC is
absent from pg_proc…", "the guard could never fire…"). Restoring the fix returns
5/5. The test asserts over COMMENT-STRIPPED source so that the doc comment can
keep the historical record without satisfying its own prohibition.
