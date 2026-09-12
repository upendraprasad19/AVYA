---
branch: oi162-slice4-windowed-counters
date: 2026-09-10
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/3cd1891ee7eb-review.md
hermes: accepted
hermes_report: docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md
recorded_at: 2026-09-12T00:00:00+05:30
---

# Plan-review record — OI-162 slice 4, windowed rate-limit counters (delete-account + verify-payment onto `usage_counters`)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `catastrophic`, COMPUTED** — `docs/blast_radius.yaml:42-43` pins both
`supabase/functions/verify-payment/**` and `supabase/functions/delete-account/**`
catastrophic by path; re-confirmed fresh on 2026-09-12 by classifying the
FULL changed-path set (branch history + staged + unstaged, piped via stdin
with the trailing `-`, not the positional-args trap) — still `catastrophic`.
Catastrophic requires `bpass: accepted` AND `hermes: accepted`, both satisfied
below.

## What shipped

Two structurally-inert rate limiters repaired and moved onto the atomic
`consume_quota()`/`usage_counters` ledger (the same primitive migrations
128/129 already use for the chat/food/vision caps):

- **`delete_account`** (5/hour): the prior mechanism inserted into two
  columns (`prompt_snippet`/`response_snippet`) that do not exist on
  `ai_coach_interactions`, into a handler that only `console.warn`'d the
  failure — schema-proven to have NEVER worked, not merely suspected.
- **`verify_payment`** (20/10min): the prior mechanism destructured only
  `{ count }` from its query, never `{ error }`, so a counter-query failure
  silently proceeded as under-limit (fail-open by omission, not design).
  Switched to fail-CLOSED on error (round 1 finding 1) — deliberately the
  OPPOSITE posture from delete-account, which stays fail-OPEN (a DPDP §17
  erasure is a legal right and must not be blocked by a counter outage).
- **Migration 130** (added by round 1, hardened by round 2): revoked
  `consume_quota`'s EXECUTE from `PUBLIC, anon, authenticated`, leaving only
  `service_role`. The function is `SECURITY INVOKER` with no ownership check
  on `p_user_id`, and was un-exploitable before this migration only because
  `usage_counters` has RLS enabled with ZERO policies and neither `anon` nor
  `authenticated` bypasses RLS — an undocumented invariant that this slice's
  own DPDP-erasure lockout and payment throttle now sit directly behind.
  **Applied to prod** 2026-09-11T17:32:05+05:30 (the user ran the apply
  themselves after explicit "migration 130: approved" authorization, once
  blocked twice on other paths — a raw-curl DDL classifier block, then an
  expired MCP token — rather than any workaround).

Full commit-by-commit detail, ground truth, and the design rationale
(fixed UTC epoch-floor buckets, exact-remaining-time `Retry-After`, the
deliberate fail-open/fail-closed asymmetry) live in
`docs/audit/oi162-slice4-plan.md` — not repeated here.

## Rounds

**Round 1 — 8 findings, 0 false alarms, all adopted.** Changed the plan's
SHAPE, not just its wording: added unit C (migration 130, not originally
planned) after finding `consume_quota` INVOKER + PUBLIC EXECUTE + no
ownership check; flipped verify-payment from fail-open to fail-closed;
corrected an overclaimed "zero live rows proves instance B never worked"
(instance A's inertness is schema-proven; instance B's absence-of-evidence
is NOT proof of absence, and the plan stopped claiming otherwise); named
three doc-drift sites (unit D) the plan had left implicit; fixed the
`Retry-After` computation from a constant to exact remaining bucket time.

**Round 2, on the hardened plan — found a P0 INSIDE unit C, the unit round 1
itself had just added.** `REVOKE ... FROM PUBLIC` alone does not close the
hole: the live ACL carries `anon=X/postgres` and `authenticated=X/postgres`
as SEPARATE DIRECT grants (not PUBLIC-inherited), because `consume_quota`
was created under this project's schema-wide `ALTER DEFAULT PRIVILEGES`
regime — the exact opposite of migrations 090/091, whose functions predate
that regime and so genuinely were fixed by a PUBLIC-only revoke. Applying
the 091 pattern by analogy, without reading THIS function's actual ACL
first, was the process failure — corrected by re-deriving the REVOKE
statement from the live `pg_proc.proacl` directly. Round 2 also surfaced:
the verify-payment grace-window/retry-schedule mismatch (P1, filed **OI-182**
— pre-existing, unrelated coupling, not fixed here); three doc-drift sites
named exactly rather than left as a vague "unit D exists"; the diagnose-doc
requirement settled (single doc `f2c8d5` covers all three code units).

**Split decision: no split** (`docs/audit/oi162-slice4-review-continuity.md`).
§4.12.1's split trigger is successive rounds surfacing *new material
classes* of problem — that is not what round 2 found. Round 2's P0 was a bug
INSIDE the one new unit round 1 had just added, not a new category of defect
in units A, B, D, or a new gap elsewhere; units A/B/D carried zero P0/P1
across both rounds. The fix was independently re-derived (not merely
accepted on the reviewer's word) and separately re-checked on a WIDER input
set than round 2 used — round 2 checked Edge-Function writers only for
whether revoking `authenticated`'s EXECUTE could break a live cap trigger;
this session additionally checked the Dart client's cloud writes and found
exactly two channel values, both excluded by all three triggers' early-return
guards, confirming `consume_quota` is never reached from an authenticated-
role insert in production.

## B-pass (`docs/reviews/3cd1891ee7eb-review.md`) — 4 findings + 1 addendum, 0 false alarms

All fixed in-batch. Renamed four times from its dispatch-time
`12408db06b47-review.md` as the batch grew (each remediation round moved
the staged-diff hash the file is named after; `docs/reviews/**` is excluded
from that hash by design, precisely so staging the review itself never
renames it, but staging its OWN required Tuning-history entry did, because
that entry lives in `.claude/skills/code-review/SKILL.md`, which the hash
did NOT yet exclude — fixed in-batch). **This record lands in its own
docs-tier commit, after the code commit, for the same structural reason:
it must name the review file, and it is itself inside the hash the review
file is named for — six of the seven prior catastrophic records did the
same.** The full rename chain is in the review's own `staged_against:`
comment. Findings 1-4 covered: the migration-130 rollback comment's
"restores exactly" overclaim (imprecise — pre-migration ACL had 5 entries
across 2 grantors, a bare `GRANT TO PUBLIC` rollback would produce 3
entries with an identical EFFECTIVE privilege set but different ENTRY
shape — documented in the diagnose-doc, migration file itself immutable and
unedited); the dormant NULL-unsafe channel guard on
`enforce_vision_analysis_daily_limit` (filed **OI-183**, matching the
codebase's own established `guard_without_its_mirror` class); the
`CREATE OR REPLACE` vs `DROP`+`CREATE` ACL-preservation distinction (added
as a new pitfall row to `supabase/migrations/CLAUDE.md`); and the self-
reference gate loop this same B-pass dispatch discovered live (fixed by
adding a second hash-exclusion pathspec to `check_code_review_pass_exists.dart`,
mirroring OI-72's own fix for the identical class, mutation-proven).

## Hermes pass (`docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md`) — 16 findings across 9 lenses, 0 P0, 3 P1, 0 false-alarm-only escapes

Full per-lens detail in the report; summarized here for the record:

- **3 P1s, all fixed and mutation-proven**: both new rate-limit contract
  tests pinned `p_quota_key`/`p_limit` by ASSOCIATION but `p_window_start`/
  `p_user_id` by bare MEMBERSHIP (proven exploitable by two live mutations
  per file, all now closed); and — independently found by two separate
  lenses (L22, L35) — migration 130's own live-prod CI discriminator test
  (`usage_counters_rls_denies_client_test.dart`) degenerated to a tautology,
  because a missing-EXECUTE refusal and an RLS refusal now share SQLSTATE
  42501, which the test's original design (correct BEFORE migration 130,
  when EXECUTE was still granted and RLS was the only guard) never
  anticipated needing to distinguish. Fixed by asserting message text,
  live-verified via two read-only `BEGIN…ROLLBACK` probes (`SET LOCAL ROLE
  authenticated`, no DDL) rather than guessed.
- **4 P2s**: a systemic, PRE-EXISTING, out-of-scope finding (4 tables —
  `usage_counters` included — rely on RLS-zero-policy default-deny alone,
  with their raw `anon`/`authenticated` grants never narrowed) filed as
  **OI-184** rather than fixed here, sized as its own reviewed unit per the
  same precedent OI-153 already set; a `docs/sot_registry.yaml` channel
  enumeration missing 4 live values; a client-side 429 handler gap
  (newly reachable because this batch is what makes the limit fire for the
  first time); and a non-local `subscriptions` read in verify-payment
  (not independently exploitable — already foreclosed by the existing
  Razorpay-notes ownership check upstream — fixed anyway as cheap
  defense-in-depth, mutation-proven).
- **5 P3s**: 3 stale review-filename citations; an undocumented UTC-vs-IST
  divergence at the point of computation (substance was already correct,
  just unexplained at the source); a missing server-side log on
  verify-payment's rate-limit-exhausted branch; and migration 128's own
  now-stale comments on the opposite claim from what migration 130 proved
  (documented in the diagnose-doc — migration is immutable, applied long
  before this review, cannot be edited without falsifying its ledger hash).
- **4 verified_clean / false_alarm**: an `ON CONFLICT` arbiter check (live-
  verified: full non-partial PK, not the partial-unique trap); a
  body-sourced `user_id` in weekly-report (verified: correctly guarded,
  exact-match fail-closed); and 3 pre-existing findings from L40 correctly
  assessed as out of this diff's scope.

One corollary is stated, not independently re-proven live: whether RLS would
still block `consume_quota`'s internal write if EXECUTE were ever mistakenly
restored to `authenticated`. Re-proving it live needs a transactional
`GRANT`, which the live-apply classifier correctly refused without explicit
authorization not sought for a defense-in-depth check the primary fix does
not depend on; the corollary follows deductively from `SECURITY INVOKER`
plus an already-proven fact (that role's writes are RLS-blocked
independent of any grant) and is stated as a corollary, not dressed up as
an independent proof.

## Mutation proof (§4.4 rule 21)

Every NEW or EXTENDED test in this batch was mutated once and confirmed to
redden exactly the assertion it exists to prove, then restored and
re-verified byte-identical to the pre-mutation source:

- 6 mutations against the live rolled-back SQL boundary test (limit-1/
  limit/limit+1 sequencing, bucket isolation) — 27/27 assertions, run live.
- 4 mutations proving the L1 association fix (`p_window_start`/`p_user_id`
  in both `delete_account_rate_limit_writer_to_reader_test.dart` and
  `verify_payment_rate_limit_writer_to_reader_test.dart`) — each reddens
  exactly 1 of 8, restored.
- 1 mutation on the new client-side 429 handler
  (`delete_account_screen_test.dart`) — reddens exactly 1 of 39, restored.
- 1 mutation on the new verify-payment ownership-association test
  (`verify_payment_notes_user_id_required_test.dart`) — reddens exactly 1
  of 4 and correctly names which of the 2 read sites regressed, restored.
- 1 mutation on the new verify-payment server-log test — reddens exactly 1
  of 9, restored.
- 1 mutation on the `check_code_review_pass_exists.dart` gate exclusion
  (removing the second pathspec) reproduces the exact self-reference loop
  the B-pass discovered live.

## Ground truth verified (read-only, live — this session, dated)

- **2026-09-10/11 (plan rounds):** `consume_quota`'s pre-migration ACL had
  5 entries across 2 grantors; `pg_proc.proacl` re-derived directly rather
  than trusted from a remembered pattern. `ai_coach_interactions`' oldest
  row predates the last payment by ~2 months, ruling out a schema-level
  explanation for instance B's zero rows. `grep -rn consume_quota lib/` is
  empty — no client caller.
- **2026-09-11 (post-apply):** migration 130's before/after ACL diff —
  `anon`/`authenticated` EXECUTE both confirmed `false` post-apply,
  `service_role` `true`. `has_function_privilege` checked directly, not
  inferred from the migration's own SQL text.
- **2026-09-11/12 (Hermes remediation):** `pg_constraint` on
  `usage_counters` shows `usage_counters_pkey` as a full, non-partial
  PRIMARY KEY on exactly `(user_id, quota_key, window_start)` — matches the
  `ON CONFLICT` arbiter exactly (L14, clean). Two `BEGIN…ROLLBACK` probes
  (`SET LOCAL ROLE authenticated`, no DDL) got the ACTUAL current error
  message text for both the EXECUTE-revoke and the RLS-zero-policy
  refusals, rather than assumed wording (L22/L35 fix). A live
  `has_table_privilege`/`pg_class.relrowsecurity`/`pg_policies` query
  across 4 tables, re-derived rather than trusted from this session's own
  earlier (pre-compaction) summary, which turned out to need correcting on
  two specific points before OI-184 was filed.

## Gates

Full local gate loop run repeatedly through this batch per §4.12.5, before
each review round that had a diff to gate. Final run pending as the next
step after this record lands (per the standing "post commit" authorization
already given).

## Not done, and why — carried openly rather than silently

- **OI-182** (verify-payment grace-window/retry-schedule mismatch) — filed,
  not fixed. Pre-existing, unrelated coupling; bundling it in would widen a
  catastrophic-tier change's blast radius for no coupling reason.
- **OI-184** (4-table grants hardening) — filed, not fixed. Systemic,
  pre-existing since well before this slice, touches zero files this diff
  touches, and needs its own before/after ACL diff across 4 tables — sized
  as its own reviewed unit per the OI-153 precedent, not a drive-by.
- **The RLS-second-layer corollary** (see Hermes summary above) — stated as
  a deductive corollary from already-proven facts, not independently
  re-verified via a live restored-EXECUTE probe, because doing so needs a
  transactional `GRANT` that the live-apply classifier correctly gates
  behind explicit authorization not sought for a defense-in-depth check.
- **Device/patrol flows not run** (plan round 1 finding 8, carried as
  residue there): `delete_account_patrol_test` and
  `razorpay_payment_patrol_test` are device-gated. The corresponding
  non-device e2e tests were read and found to contain no repeated-invocation
  loops a now-live cap would trip; measured client volume (~4 verify-payment
  calls per payment over 15 min) sits well under the 20/10min cap.
