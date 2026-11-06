---
bug_id: c4f9e2
date: 2026-09-08
batch: oi162-slice3b-media-meter
status: fixed_slice_3b_of_4
blast_radius: platform
symptom: >
  The free tier's 5 LIFETIME image analyses silently reset. `ai-media-proxy`'s
  gate asked "how many free image analyses has this user spent?" by counting
  rows in `ai_coach_interactions` with channel='free_image_analysis' and NO date
  bound. Those rows are non-`app_event`, so `rolling-context` summarises and
  DELETEs all but the newest 10 once a user passes 50 — and a LIFETIME quota has
  no window to survive deletion on. A free user who chatted enough got another 5
  free Gemini Vision reads, repeatedly. A SECOND, independent defect sat in the
  same function: the reader was fail-OPEN (`if (error) return 0`, `catch (_) {
  return 0 }`) with a docstring arguing fail-open was "safer … because 0 < 5",
  which is precisely when the gate does NOT fire (audit CODE-3). Slice 3b of
  OI-162; parent bug d3a7f1; identical mechanism to f4a2d8 (slice 3a).
concept: media_free_image_lifetime_gate
sot_registry_entry: media_free_image_lifetime_gate
writers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "consume_quota('free_image_analysis', 'epoch') — the QUOTA writer, gated on isFreeImageAnalysis && !interactionLogError, running AFTER the insert" }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "ai_coach_interactions insert — unchanged and unconditional, the SOLE persisted copy of the exchange and the restore source; no longer feeds the gate. Its error is now captured rather than discarded" }
  - { file: supabase/migrations/128_usage_counters.sql, line: 69, method: consume_quota — the ledger's only writer }
readers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "readFreeImageQuota — advisory usage_counters read feeding the 5-lifetime gate" }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "the 'X of 5 free analyses left' display, now derived from consume_quota's RETURN rather than a second full count" }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: countProImageAnalysesToday — STILL on the old table, dormant, OI-153 }
  - { file: supabase/functions/delete-account/index.ts, line: 146, method: delete-attempt rate limit — slice 4 }
  - { file: supabase/functions/verify-payment/index.ts, line: 225, method: payment-verify rate limit — slice 4 }
hive_key_prefix: "n/a — server-side gate, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/media_free_image_lifetime_gate_writer_to_reader_test.dart
ist_handling: >
  Not applicable by design, and that is the point: this is a LIFETIME quota, so
  it uses the timezone-free `'epoch'` sentinel window_start rather than an IST
  day bucket. `cleanup_usage_counters()`'s predicate is two-sided — `window_start
  <> 'epoch' AND window_start < now() - interval '7 days'` — so the epoch row is
  excluded from retention by the FIRST conjunct, permanently. The TS literal
  `1970-01-01T00:00:00+00:00` is asserted equal to `'epoch'::timestamptz`.
  Contrast the SIBLING quota in the same file, countProImageAnalysesToday, which
  IS an IST day bucket — the two must never share a quota_key.
provider_invalidations: "none — no client state changes. The only client edit is the deletion of a zero-caller method plus a copy constant."
telemetry_op_types: >
  Three new server-side log lines, deliberately distinguished. console.error when
  the ledger read fails (the fail-closed refusal, previously a silent grant);
  console.error on a populated consume_quota error (a real under-count — the
  analysis was delivered but the ledger did not move); console.warn on a -1
  return (a concurrent request that won the race past the advisory gate). -1 is
  a SUCCESSFUL return meaning exhausted, so logging it as a failure would fire on
  every ordinary race and drown the real under-counts.
cross_account_guard: >
  Every ledger read and write is scoped by `p_user_id` / `.eq("user_id", userId)`
  where userId comes from the verified JWT, not from the request body. RLS is
  enabled on usage_counters with NO policy and consume_quota is SECURITY INVOKER;
  the EF reaches it with the service-role client, which bypasses RLS by design.
  No cross-user surface is introduced — the quota_key is a constant, not
  user-supplied.
forbidden_patterns_checked: >
  No `.single()` on the ledger read (asserted absent — it throws PGRST116 on the
  absent row every free user has at cutover). No fail-open `return 0` on an error
  path. No second call site for this quota_key. No count(*) over
  ai_coach_interactions for this channel (asserted absent by name AND by query
  shape). Checked `check_usage_counter_source.dart` (PASS, 3 known EF counters
  after the 2 -> 1 ratchet), `check_sot_behavioral_test_paths.dart`,
  `check_sot_registry_parity.dart`, `check_reader_manifest_complete.dart`.
proposed_fix: >
  Replace the row-counting reader with an ADVISORY `.maybeSingle()` read of
  usage_counters (quota_key `free_image_analysis`, `'epoch'` window) that fails
  CLOSED, and make consume_quota the authoritative writer, running AFTER the
  unconditional conversation-log insert and gated on that insert having
  succeeded. Use consume_quota's return value for the "X of 5 left" display,
  deleting the second full count. Give the fail-closed path its own
  `gate_reason: "quota_unavailable"` and its own copy, since reusing the paywall
  would tell a user who spent nothing that they spent 5. Delete the zero-caller
  client twin `getFreeImageAnalysisCount()` rather than repointing it. No
  migration — `quota_key` is unconstrained text.
regression_test_planned: >
  test/contracts/media_free_image_lifetime_gate_writer_to_reader_test.dart — 10 source-grep
  assertions, MUTATION-PROVEN on 6 legs (see below). Plus three `slice3b_*`
  ledger assertions appended to test/sql/oi46_daily_cap_triggers_live_verify.sql,
  and the three ratchets in usage_quota_ledger_writer_to_reader_test.dart updated
  to reflect the new state (allowlists + stillLegacy, 5 -> 3).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Deleted the zero-caller getFreeImageAnalysisCount(); added the imageQuotaUnavailable copy mirror. flutter analyze run over the touched tree." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "Server-side gate; no Hive surface. No box, no key prefix." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "usage_counters.quota_key is unconstrained text (migration 128) — no CHECK constraint, so a new key needs no DDL. Confirmed no migration is required." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live read 2026-09-08: 0 rows in ai_coach_interactions with channel='free_image_analysis' across 0 distinct users, and 0 rows in usage_counters for this quota_key. The bug was LATENT — real mechanism, nobody had hit it — so the cutover regrant affects nobody." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this slice. 130 stays free." }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "ai-media-proxy is LIVE AT v21 (list_edge_functions, 2026-09-08) and this change is NOT deployed. Deploying requires its own explicit founder authorization per CLAUDE.md 4.3 — plan approval is not deploy approval. Until then the fix exists in git only, and the live function still counts the pruned log." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "ai-media-proxy is client-invoked, not cron-dispatched. rolling-context (the pruner) is unchanged — this fix stops depending on it rather than altering it." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "RLS enabled on usage_counters with NO policy; consume_quota is SECURITY INVOKER; the EF uses the service-role client (index.ts constructs with SUPABASE_SERVICE_ROLE_KEY), so both the read and the RPC are reachable. Unchanged by this slice." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage surface touched. The SSRF allowlist and signed-URL paths are untouched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No new secret. No secret read added or changed." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No Razorpay / OneSignal / Firebase surface. The Gemini call itself is unchanged; only whether it is reached." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Response shape preserved for both existing paths; the new quota_unavailable refusal adds a gate_reason and OMITS free_image_used rather than fabricating it. Verified zero client readers of free_image_used / free_image_remaining / free_image_limit / gate_reason (grep over lib/) — the user-visible number reaches the client only through the reply TEXT." }
impact_analysis: >
  BEFORE: any free user whose ai_coach_interactions history passed
  rolling-context's 50-row threshold had their spent free-image analyses pruned
  and regained all 5, repeatedly — unbounded free Gemini Vision. Independently,
  any transient PostgREST error on the counting query granted an analysis,
  because the reader returned 0 and 0 < 5. AFTER: the meter is a durable
  usage_counters row that retention structurally cannot delete, and an
  unreadable ledger refuses instead of granting. Blast radius is platform (Edge
  Function + shared copy + SoT registry). Live blast radius of the CUTOVER is
  zero, measured: no user has ever consumed one of these analyses. Residual
  risks, both bounded and both stated in the plan: two concurrent requests can
  each pass the advisory gate and the second consume returns -1 (at most one
  extra analysis, once); and an insert that succeeds while the consume fails
  under-counts by one, which is the deliberately-chosen recoverable direction.
---

# c4f9e2 — the free tier's 5 LIFETIME image analyses reset themselves

Third instance of the counter-in-a-summarized-table class (after slice 2's three
cap triggers and slice 3a's weekly report), and the second LIFETIME one. Same
shape as `f4a2d8`, different surface.

## Why a trigger was rejected here, when slice 2 used triggers

Unlike 3a, an INSERT *does* exist at the moment this quota is spent, so a trigger
was genuinely possible. It was rejected on two specific grounds rather than by
analogy:

1. A trigger cannot return the new count to the Edge Function, so the
   "X of 5 free analyses left" display would need a THIRD round trip — defeating
   the double-count collapse that is half this slice's value.
2. A trigger RAISES on exhaustion, which would make the conversation-log insert
   throw. That insert is unconditional by design (it is the only persisted copy
   of the exchange), so the refusal path would have to be restructured around an
   exception.

## Ordering, and why the guard is not redundant with it

`consume_quota` runs AFTER the insert and only when `!interactionLogError`.
Ordering alone is insufficient: an insert that FAILED while the consume SUCCEEDED
reaches the same bad end state — a lifetime unit burned, the analysis lost — by a
different route. The conjunct closes it. Skipping the consume under-counts, which
is the recoverable direction.

## Mutation proof (rule 21)

Six mutations, each CONFIRMED APPLIED by a token grep before the run, each
reddening exactly one assertion, all restored:

| # | mutation | result |
|---|---|---|
| 1 | `p_quota_key` retargeted to another key (writer/reader drift) | 1 red |
| 2 | epoch sentinel → a real 2026 timestamp (retention would delete it) | 1 red |
| 3 | fail-CLOSED reverted to `if (error) return 0` (the CODE-3 defect) | 1 red |
| 4 | `!interactionLogError` dropped from the consume guard | 1 red |
| 5 | **decoy guard** — real guard kept, an `if ()` inserted between it and the RPC | 1 red |
| 6 | allowlist left at 2 instead of ratcheting to 1 | 1 red |

None was a compile error (the assertions are source greps over TypeScript, which
`flutter test` does not compile), so every red is an assertion failing for its own
reason. M5 is the one that matters and was checked BY NAME: it reddens
`the consume is CONTAINED BY the insert-succeeded guard` with
`Expected: false / Actual: <true>`. That mutation is exactly what defeated slice
3a's first attempt at this assertion, which checked PROXIMITY (`gap < 200`) — a
decoy guard is adjacent to the real call by construction, so proximity is not
containment.

## What is NOT proven

- **Nothing proves the deployed function does any of this.** ai-media-proxy is
  live at **v21** and this change is not deployed; deploying needs its own
  explicit authorization.
- The `slice3b_*` SQL assertions verify the LEDGER (limit-5 one-through-five then
  refusal, key isolation, two-sided retention). **RUN LIVE 2026-09-09 against
  prod, founder-authorized: 3/3 `ok`**, with the meter reporting the full
  sequence `1 2 3 4 5 | sixth=-1`. Rollback verified afterwards — 0 synthetic
  rows of any kind left behind. ⚠ **They execute no Edge Function and would pass
  unchanged against the pre-slice-3b code.** They are behaviour-invariants of the
  ledger, NOT evidence this slice landed; do not cite them as such.
- The contract test is a source grep: it proves the code SAYS the right thing.
  There is no Deno on this machine; CI's `deno-edge-functions` job is the only
  compile proof.

## Related

Parent `d3a7f1` · slice 2 `e7c4b2` · slice 3a `f4a2d8` · OI-153 (the dormant PRO
image cap in the same file — nothing writes `pro_image_analysis` or
`image_analysis`, confirmed in code and in prod data, so migrating it would
ACTIVATE a cap that has never fired: a product decision, deliberately not made
here) · slice 4 (`delete-account` / `verify-payment`, catastrophic).
