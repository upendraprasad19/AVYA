---
bug_id: f2c8d5
date: 2026-09-11
batch: oi162-slice4-windowed-counters
status: fixed_slice_4_of_4
blast_radius: catastrophic
symptom: >
  TWO independent rate limits, plus a privilege gap the fix for both exposes.
  (A) delete-account's 5/60min limit NEVER FUNCTIONED: its fire-and-forget
  insert targeted two columns (prompt_snippet, response_snippet) that do not
  exist on ai_coach_interactions, and left user_message (NOT NULL, no
  default) unset — every insert failed silently into a handler that only
  console.warn'd. attemptCount was structurally always 0, so the >=5 check
  never fired. (B) verify-payment's 20/10min limit destructured only
  { count } from its counter query, never { error } — a counter-query
  failure silently proceeded as if under the limit (fail-open BY OMISSION,
  not by design; its sibling delete-account's comment incorrectly claimed
  verify-payment "fail-closes"). Both also used a non-atomic
  count-then-insert pair. (C) Fixing both by routing through
  consume_quota() surfaced that the function is SECURITY INVOKER with
  EXECUTE granted to PUBLIC/anon/authenticated and does no ownership check
  on p_user_id — un-exploitable today only because usage_counters has RLS
  enabled with ZERO policies, an undocumented invariant this fix now
  deliberately depends on for two security-relevant limits (a DPDP-erasure
  lockout and a payment throttle), so it is hardened in the same batch.
  Direct recurrence of the usage_quota_ledger class (e7c4b2, d3a7f1,
  2026-09-05) applied to instances 4 and 5 of 5; delete-account's original
  rate limit is 7ad009 (2026-05-11).
concept: delete_account_rate_limit, verify_payment_rate_limit
sot_registry_entry: delete_account_rate_limit, verify_payment_rate_limit
writers:
  - { file: supabase/functions/delete-account/index.ts, method: "consume_quota('delete_account', <hourly bucket>) — called at the top of the handler, BEFORE the confirmation-token check; replaces the count-then-insert pair" }
  - { file: supabase/functions/verify-payment/index.ts, method: "consume_quota('verify_payment', <10-minute bucket>) — called at the top of the handler, BEFORE body parsing; replaces the count-then-insert pair" }
  - { file: supabase/migrations/130_consume_quota_revoke_public_execute.sql, line: 42, method: "REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated" }
readers:
  - { file: supabase/functions/delete-account/index.ts, method: "the RPC's own return value — usedCount === -1 refuses with 429; there is no separate advisory read, the check-and-increment IS the enforcement" }
  - { file: supabase/functions/verify-payment/index.ts, method: "same shape — usedCount === -1 refuses with 429; a populated error also refuses (fail-CLOSED, the deliberate change from the pre-fix fail-open-by-omission)" }
hive_key_prefix: "n/a — server-side gates, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: usage_counters
cloud_columns: [user_id, quota_key, window_start, used, updated_at]
contract_test_path: test/contracts/delete_account_rate_limit_writer_to_reader_test.dart, test/contracts/verify_payment_rate_limit_writer_to_reader_test.dart
ist_handling: >
  Deliberately UTC epoch-floor, not IST, and stated rather than deviated
  silently. §4.5 mandates IST for date keys + counter RESETS because those
  are user-visible daily boundaries. These are sub-day rate-limit buckets
  with no user-visible reset moment; only bucket DURATION is observable
  (via Retry-After, itself computed as exact remaining time, not a
  constant), and duration is timezone-invariant. bucketStartMs =
  Math.floor(Date.now() / WINDOW_MS) * WINDOW_MS in both files.
provider_invalidations: "none — no client state changes. One lib/ edit in this batch is a doc-comment fix (dead example-list entry removed from coach_interaction_repository.dart), not a behavior change."
telemetry_op_types: >
  delete-account: console.warn on rateErr (fail-open, unchanged posture) and
  on a -1 refusal (unchanged log shape, now reflects a REAL enforcement
  instead of a permanently-false branch). verify-payment: console.error on
  rateErr (NEW — this path now fails closed and returns 429, so it must be
  loud) where the prior code had no error-path log at all because it never
  read the error.
cross_account_guard: >
  Both call sites pass p_user_id from the caller's OWN verified JWT
  (userClient.auth.getUser(token) / supabase.auth.getUser(token)) — never
  from the request body — so a caller can only ever consume their own
  quota. consume_quota itself has NO ownership check (see symptom C above);
  migration 130 closes the ONLY path that mattered (client-reachable
  EXECUTE), verified by re-deriving the ACL live rather than trusting the
  091 REVOKE-FROM-PUBLIC pattern by analogy — that pattern does NOT close
  this function's grant, because anon/authenticated hold SEPARATE DIRECT
  grants here (migration 128's default-ACL regime), not PUBLIC-inherited
  ones. Caught by an independent review round after the first attempt at
  130 copied the 091 pattern verbatim; re-verified against pg_proc.proacl
  before writing the final migration.
forbidden_patterns_checked: >
  No remaining count(*)/count:"exact" read against ai_coach_interactions in
  either file (mechanically proven — check_usage_counter_source.dart PASS,
  1 known EF counter remaining, the OI-153 dormant one; both this batch's
  entries ratcheted 1 -> 0). No `.single()` on the RPC result (it is a plain
  rpc() call, not a table read — N/A here). No stray reference to either
  retired channel literal in test/ (grep confirmed absent). No client code
  reads Retry-After / retry_after_seconds (grep over lib/ — empty), so
  changing that value from a constant to the bucket's exact remaining time
  is safe. REVOKE targets PUBLIC, anon AND authenticated explicitly — not
  PUBLIC alone (see cross_account_guard).
proposed_fix: >
  Replace each endpoint's count-then-insert pair with one atomic
  consume_quota() call (quota_key `delete_account` / `verify_payment`,
  fixed UTC bucket, existing caps unchanged: 5/hour, 20/10min). Accept the
  fixed-bucket 2x boundary burst — both limits are secondary defense-in-
  depth (delete-account's confirmation token and verify-payment's
  optimistic-Hive-activation + independent webhook are primary), not the
  sole control. delete-account keeps its fail-OPEN posture (a DPDP §17
  erasure must not be blocked by a counter outage); verify-payment
  DELIBERATELY SWITCHES to fail-CLOSED (a background confirmation step
  whose brake must not release during the exact correlated-outage scenario
  it exists to guard against). Retry-After becomes the bucket's true
  remaining time. Migration 130 revokes consume_quota's PUBLIC/anon/
  authenticated EXECUTE (safe: grep -rn consume_quota lib/ is empty; both
  EFs and all three live cap triggers only ever reach it via a service-role
  client). Both retired channel literals removed from
  ai_coach_interactions; four documentation sites corrected
  (payment.md rules 2 and 6, sot_registry.yaml's coach_interactions
  description, supabase/functions/CLAUDE.md's SoT table, and the
  Dart repository's doc-comment).
regression_test_planned: >
  Two writer-to-reader source-grep contracts (one per endpoint, 6+7=13
  assertions, all green) pinning: consume_quota called with the right
  quota_key; the -1 sentinel handled; the retired channel literal absent;
  verify-payment destructures error; delete-account's fail-open /
  verify-payment's fail-closed comments present. Live SQL
  (test/sql/oi162_slice4_quota_boundary_and_acl_live_verify.sql) Part A
  EXECUTED against prod inside BEGIN...ROLLBACK 2026-09-11: 27/27 assertions
  true — drove consume_quota through both new keys across the
  limit-1/limit/limit+1 boundary (delete_account 1..4/5/6, verify_payment
  1..19/20/21) plus one bucket-isolation check; confirmed zero residue in
  usage_counters after (count=0 on the synthetic quota_key prefix). Part B
  (has_function_privilege) EXECUTED live 2026-09-11 AFTER migration 130
  applied: 3/3 assertions true (anon revoked, authenticated revoked,
  service_role retained). Mutation-proven per rule 21, 6/6 planned mutations
  executed — see the doc body below.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "The only lib/ touch in this batch is a doc-comment fix (dead 'verify_payment_attempt' example dropped from coach_interaction_repository.dart's history-replay comment) — no functional or behavioral change to any Dart file." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "Server-side gates; no Hive surface on either endpoint." }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "usage_counters.quota_key is unconstrained text (migration 128) — confirmed live via information_schema, no CHECK/trigger/index/enum on it, so the two new keys need no DDL. Migration 130 IS a schema-level change: it alters consume_quota's EXECUTE grant. Written and reviewed in this batch; APPLIED to prod 2026-09-11T17:32:05+05:30 (founder-approved, founder-run via the Management API after the agent's own raw-curl attempt was correctly classifier-blocked as a live DDL write — see backups/applied_migrations.json)." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live census 2026-09-11: 0 rows in ai_coach_interactions on either retired channel across all 134 rows (7 live channels: in_app_orphan 58, app_event 32, food_text_analysis 25, in_app 7, app 6, promotion_ceremony 5, scan_meal 1). usage_counters holds only quota_key='chat_app' (6 rows, used sums to 44) — the cutover for both new keys starts from a clean slate. consume_quota's live proacl re-confirmed POST-migration-130: {postgres=X/postgres,service_role=X/postgres} — anon and authenticated EXECUTE both confirmed false via has_function_privilege, service_role confirmed true. The privilege gap is CLOSED as of 2026-09-11T17:32:05+05:30." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "Migration 130 written with the full four-tag header (Intent/Destructive/Rollback strategy/Linked diagnose-doc) and an inline commented rollback block. Number re-verified free against local, origin/main, and every other worktree before writing. APPLIED to prod 2026-09-11T17:32:05+05:30 — backups/applied_migrations.json entry added in this same commit per CLAUDE.md §4.5. Live pre/post ACL both captured (see tier 4)." }
  - { tier: 6, name: edge_function_deploy, status: fixed_in_this_batch, evidence: "Both delete-account and verify-payment source fixed in git. NEITHER is deployed. Both are catastrophic-tier per blast_radius.yaml:42-43 by path; each redeploy needs its own explicit authorization, separate from this commit landing and separate from each other." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "Neither function is cron-dispatched — both are client-invoked (delete-account from the profile delete flow, verify-payment from the Razorpay checkout poll)." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "usage_counters has RLS ENABLED with ZERO policies (pg_policies query, live) — the exact fact that made consume_quota's PUBLIC/anon/authenticated EXECUTE grant a latent gap rather than an active one. Unchanged by migration 130, which touches only the function's ACL, not any policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage bucket or object surface touched by either endpoint's rate-limit change." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No new Vault secret read or written." }
  - { tier: 11, name: external_services, status: verified, evidence: "verify-payment's actual Razorpay API calls (order verification, subscription creation) are UNTOUCHED — only the rate-limit gate ahead of them changed. delete-account's Razorpay-cancel step is likewise untouched by this batch (its own doc drift, unrelated to the rate limit, was corrected in payment.md as an adjacent one-line fix, not a functional change)." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Both endpoints' SUCCESS response shapes are byte-identical to before. The 429 error bodies change Retry-After from a fixed constant (3600 / 600) to the bucket's exact remaining seconds — grep -rn 'retry_after_seconds|Retry-After|retryAfter' lib/ returns EMPTY, so no client code reads either field today and this change has no client-visible effect." }
impact_analysis: >
  BEFORE: delete-account's 5/60min DPDP-erasure-endpoint rate limit had NEVER
  fired in production (schema-proven: its insert violated two independent
  constraints on every call). verify-payment's 20/10min limit silently
  proceeded on any counter-query error (fail-open by omission), and its
  count-then-insert pair was non-atomic. AFTER: both limits are enforced
  atomically via the same durable ledger already proven in production for
  three other quota keys since migration 129. verify-payment additionally
  now fails CLOSED on error, trading a near-zero user cost (one of four
  retried confirmation calls, on an already-optimistically-activated
  subscription) for closing the exact failure mode that would otherwise
  release its brake during a correlated-outage retry storm — the scenario
  the limit exists to protect against. SEPARATELY, migration 130 closes a
  privilege gap that predates this batch (consume_quota's client-reachable
  EXECUTE grant) but that this batch is what makes genuinely dangerous, by
  putting a security-relevant lockout and throttle behind the same RLS
  accident every other quota key already relies on advisedly. Live blast
  radius of the CUTOVER itself is zero, measured: no row exists on either
  retired channel and usage_counters starts both new keys from empty.
  Residual, stated rather than engineered around: a 2x burst is possible
  across a fixed-bucket boundary (both limits were previously rolling); no
  cutover backfill exists for either key, which is strictly LOOSENING for
  one window, not a lockout risk; and a pre-existing, unrelated timing
  mismatch in the payment grace window (10min vs a 15min retry tail) is
  filed separately as OI-182 rather than fixed here.
---

# f2c8d5 — two rate limits inert/unsafe, and the ACL gap fixing them exposed

OI-162 slice 4 of 4 — the last engineering slice; what remains on the board
(OI-153, the dormant PRO-image cap) is a product decision, not code.

## Why this is a direct recurrence, not a new bug class

`e7c4b2` and `d3a7f1` (2026-09-05, slice 2) established the pattern: a quota
derived from counting rows in `ai_coach_interactions` is unreliable because
`rolling-context` prunes that table nightly. Slices 3a and 3b applied the same
fix (route through `usage_counters` via `consume_quota()`) to two more
instances. This slice is the SAME fix applied to instances 4 and 5 — except
neither instance was actually broken by pruning; delete-account's insert never
worked at all (a different, independent defect that happened to share a
symptom — "the counter reads 0" — with the pruning class), and verify-payment's
zero could not be distinguished from "never reached" without checking the
schema (it CAN insert successfully; the table's oldest row predates the last
real payment).

## The ACL correction, and how round 2 caught round 1's own mistake

The first draft of migration 130 revoked `consume_quota` EXECUTE `FROM PUBLIC`
only, copying migration 091's pattern by analogy ("revoke from PUBLIC, not the
role" — a rule this repo's own memory already carries from that prior
incident). A second independent review round re-derived the live ACL instead
of trusting the analogy and found it does not apply here: `091`'s functions
predate the schema-wide `ALTER DEFAULT PRIVILEGES` policy migration 128
introduced, so they genuinely had only a PUBLIC-sourced grant.
`consume_quota` was CREATED under that later policy and carries independent
direct grants to `anon` and `authenticated` — `REVOKE ... FROM PUBLIC` would
have been a no-op for both. **A rule learned from one incident does not
transfer by resemblance; it transfers by matching the mechanism, and here the
mechanism differed.** Fixed by revoking from all three explicitly and
re-verifying against `pg_proc.proacl`, not by re-reading the 091 diagnose-doc
harder.

## Why verify-payment flips to fail-closed and delete-account does not

Both endpoints' limits exist to protect a shared resource from a runaway
client. They differ in what a false refusal costs: delete-account is the ONLY
path to a legally-required action with no fallback, so blocking it on a
counter hiccup is a real harm with no compensating safety net — hence fail
OPEN. verify-payment is background confirmation of an action (PRO activation)
that already happened optimistically in Hive and is independently confirmed by
a webhook, with the client retrying three more times regardless — so a false
refusal there costs almost nothing, while a false PASS under a correlated
outage releases exactly the brake the limit exists to be. The two functions
now say this explicitly, including delete-account's comment correcting its own
prior (wrong) claim about its sibling's behavior.

## Mutation proof (rule 21)

All 6 planned mutations EXECUTED against the real files 2026-09-11, one at a
time, each restored (verified via `diff` against a pre-mutation backup)
before the next. Every run reddened EXACTLY the assertion named — no more,
no fewer — confirming each protection is neither too broad (catching
unrelated changes) nor absorbed (per rule 21's "reddens nothing" trap).

| # | mutation | file:line mutated | assertion reddened | result |
|---|---|---|---|---|
| 1 | `delete_account` quota_key retargeted to `verify_payment` | `delete-account/index.ts:80` | `delete_account_rate_limit_..._test.dart:63` (`RATE_LIMIT_QUOTA_KEY = "delete_account"`) | 1/6 red, exactly as predicted |
| 2 | `usedCount === -1` inverted to `!== -1` | `delete-account/index.ts:181` | `..._test.dart:109` (exhaustion sentinel) | 1/6 red, exactly as predicted |
| 3 | verify-payment's `{data: usedCount, error: rateErr}` reverted to `{count: recentAttempts}` | `verify-payment/index.ts:242` | `verify_payment_rate_limit_..._test.dart:90` (destructure shape) | 1/7 red — the sibling "FAILS CLOSED" test at line ~116 stayed green because it only checks the LITERAL string `if (rateErr)` exists later in the file, independent of the destructure; correctly scoped, not a miss |
| 4 | bucket floor reverted to rolling (`Date.now() - WINDOW_MS`) | `delete-account/index.ts:159-160` | `..._test.dart:92` (floor-not-rolling assertion) | 1/6 red, exactly as predicted |
| 5 | migration 130's REVOKE narrowed back to `FROM PUBLIC` only | N/A — proven by live ACL inspection, no DDL run against prod (see below) | — | confirmed: `anon=X/postgres` and `authenticated=X/postgres` are independent ACL entries, unaffected by a PUBLIC-only revoke |
| 6 | `usage_counter_source_lib.dart` allowlist reverted `0`→`1` for delete-account | `usage_counter_source_lib.dart:171` | `..._test.dart:190` (allowlist-ratcheted-to-0) | 1/6 red, exactly as predicted. Note: `check_usage_counter_source.dart` itself stayed PASS under this same mutation — expected, since the gate flags count > allowed, and 0 actual ≤ 1 allowed is compliant; the CONTRACT TEST's exact-value assertion is what catches a ratchet reversion, not the sweep gate. |

Bonus (not on the original 6-item plan, run anyway): inserted a `return` in
delete-account's `if (rateErr)` branch (flipping fail-open to fail-closed) —
reddened exactly `..._test.dart:151` ("fails OPEN... deliberately") and
nothing else. All mutated files restored and re-diffed clean against their
pre-mutation backups before the next mutation and before this commit.

**Mutation 5's evidence, in detail (no DDL run against prod — read-only):**
live query 2026-09-11 against `pg_proc.proacl` for `consume_quota` returned
`{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}`
— FOUR independent grant entries. The bare `=X` (no grantee before `=`) is
the PUBLIC grant; `anon=X` and `authenticated=X` are SEPARATE, not inherited
from PUBLIC. A `REVOKE ... FROM PUBLIC` removes only the first entry, so
`has_function_privilege('anon', 'public.consume_quota(...)', 'EXECUTE')`
would still read `true` afterward — the exact "red" the ledger predicts.
This is why migration 130's real SQL lists PUBLIC, anon AND authenticated.

**Live SQL boundary proof (Part A of
`test/sql/oi162_slice4_quota_boundary_and_acl_live_verify.sql`), executed
2026-09-11 inside `BEGIN...ROLLBACK` against prod:** 27/27 assertions true —
`consume_quota` correctly walked delete_account's shape (limit=5) through
calls 1-4 (succeed, return 1-4), call 5 (succeed, returns exactly 5), call 6
(refuse, returns -1); verify_payment's shape (limit=20) through calls 1-19
(succeed), call 20 (succeed, returns exactly 20), call 21 (refuse, returns
-1); and one bucket-isolation check (the next hour's bucket for the same
user+key starts fresh at 1). Post-run query confirmed zero residual rows in
`usage_counters` under the synthetic `oi162_slice4_test_%` quota_key prefix —
the rollback left no trace.

## What is NOT proven

- **Nothing proves the deployed functions do any of this.** Both
  `delete-account` and `verify-payment` are live with their PRE-fix code;
  deploying either needs its own explicit authorization, separate from this
  commit landing.
- ~~Migration 130 has not been applied.~~ **RESOLVED 2026-09-11T17:32:05+05:30.**
  Founder-approved and founder-applied via the Management API (the agent's
  own raw-curl DDL attempt was correctly classifier-blocked). The privilege
  gap is closed: live post-apply proacl is
  `{postgres=X/postgres,service_role=X/postgres}`; Part B of the live SQL
  file ran 3/3 true. See tiers 3-5 above and `backups/applied_migrations.json`.
- The two contract tests are source greps: they prove the code SAYS the right
  thing; live Deno behavior is CI's `deno-edge-functions` job alone (no Deno
  on this machine). The live SQL boundary proof above covers `consume_quota`
  itself for the two NEW keys — its core check-and-increment logic was
  already proven for three other keys in `e7c4b2` and is unchanged here.

## Known documentation imprecision (not fixed — migration is applied and immutable)

Migration 130's commented rollback block (lines 47-49) says re-granting
EXECUTE to PUBLIC "restores the pre-migration ACL exactly." That is
imprecise: the pre-migration ACL had FIVE entries, two of them (`anon=X`,
`authenticated=X`) separately named, non-PUBLIC-inherited grants; a
`GRANT ... TO PUBLIC` rollback would produce a three-entry ACL
(`postgres=X`, `service_role=X`, PUBLIC) whose EFFECTIVE privilege set is
identical (PUBLIC-inheritance reads the same as a direct grant to
`has_function_privilege`) but whose entry shape differs from the original.
Flagged by the B-pass review (Finding 3 — its hash-named file is pointed
at by `docs/plan-reviews/oi162-slice4-windowed-counters.md`'s
`bpass_review:` field; not named here because that name moved every time
this batch grew). **Not corrected in the migration file** — per
`supabase/migrations/CLAUDE.md`'s immutability rule, migration 130 was
already applied to prod (2026-09-11T17:32:05+05:30) before this review
landed, and editing an applied migration's comments — even to fix a
precision issue — silently falsifies the `backups/applied_migrations.json`
hash. Recorded here instead, per that same file's own guidance ("where a
correction goes instead: the diagnose-doc"). Low priority: the rollback
path is not executed in this batch, and the imprecision does not change
what the rollback actually does.

**Migration 128 (long-applied, also immutable) is now stale in the same
way, on the OPPOSITE claim** (Hermes L35, 2026-09-11). Its
`COMMENT ON FUNCTION` (128:115-119) says `consume_quota` is "SECURITY
INVOKER by design — RLS on usage_counters is the guard, not the EXECUTE
grant," and an inline comment (128:121-128) calls its own
`GRANT ... TO service_role, authenticated` "REDUNDANT" and "harmless…
because the design does not rely on grants." Migration 130 proved the
opposite: revoking that exact grant from `authenticated` was NOT harmless —
it changed which barrier a normal client hits first (see
`test/edge_functions/usage_counters_rls_denies_client_test.dart`'s header,
corrected in this same batch, for the live-verified two-message-text
proof). 128's comments describe the PRE-130 model accurately for the
day they were written; they are not corrected, for the identical
immutability reason as 130's rollback comment above, and are recorded here
instead.

**The "RLS still blocks the internal write if EXECUTE were ever restored"
claim in that same test file's header is a stated COROLLARY, not a
live-re-verified fact.** Live-verified today (Management API, `SET LOCAL
ROLE authenticated` inside `BEGIN…ROLLBACK`, no DDL): a normal client's
call now fails with `permission denied for function consume_quota`
(42501); a direct `INSERT` into `usage_counters` as `authenticated`
(bypassing the function) fails with `new row violates row-level security
policy for table "usage_counters"` (also 42501, different message —
this is the fact that broke the discriminator test's SQLSTATE-only check).
Re-verifying the RESTORED-EXECUTE scenario live would need a transactional
`GRANT EXECUTE ... TO authenticated`, which the live-apply classifier
correctly refused without explicit authorization; that authorization was
not sought for a defense-in-depth check the primary fix does not depend
on. The corollary follows from `consume_quota` being `SECURITY INVOKER`
(runs its internal write AS the calling role) plus the direct-`INSERT`
probe already proving that role's writes are RLS-blocked independent of
any grant — logically sound, not independently re-proven by a live
restored-grant probe in this batch.

## Related

Parent class `d3a7f1`; slice 2 `e7c4b2`; slice 3a `f4a2d8`; slice 3b `c4f9e2`.
delete-account's original rate limit `7ad009` (2026-05-11). OI-162 (parent),
OI-182 (grace-window mismatch, filed not fixed), OI-153 (the one remaining
engineering-adjacent item on the board, blocked on a product decision, not
touched here).
