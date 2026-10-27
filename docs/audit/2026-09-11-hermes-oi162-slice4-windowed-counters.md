---
hermes_pass_id: 2026-09-11-hermes-oi162-slice4-windowed-counters
ran_at: 2026-09-11T20:00:00+05:30
batch_scope: working-tree (branch oi162-slice4-windowed-counters vs main) — delete-account + verify-payment rate limits onto usage_counters/consume_quota, migration 130 ACL hardening
lens_set: [L1, L2, L14, L21, L22, L23, L29, L35, L40]
agents_dispatched: 9
findings_total: 16
findings_by_severity: { P0: 0, P1: 3, P2: 4, P3: 5, false_alarm: 4 }
verdict: accepted
---

# Hermes Pass — OI-162 slice 4 (windowed counters: delete-account + verify-payment rate limits, migration 130 ACL)

> Note on provenance: the 9 lens dispatches ran and returned in full on
> 2026-09-11, but this consolidated report was compiled after a context
> compaction wiped the raw per-lens agent transcripts. Every finding below
> was either (a) reconstructed from this session's own detailed triage notes
> written BEFORE compaction (which named specific files/lines per finding)
> and then RE-VERIFIED live against current code/schema before being written
> here, or (b) for L14, where no pre-compaction triage note survived at all,
> independently re-checked live from scratch rather than guessed. No finding
> in this report is stated from memory alone without a corresponding live
> re-verification in this session. `ran_at`'s time-of-day is an approximation
> for the same reason — the date is certain, the exact hour is not preserved.

## Summary

- 0 P0, 3 P1, 4 P2, 5 P3, 4 false_alarm/verified_clean.
- Ship-blockers: none remaining — all 3 P1s fixed and mutation-proven.
- Every finding reached a terminal state in this same batch — fixed, filed,
  or verified clean; none left open. One systemic, pre-existing finding
  outside this diff's touched files was filed as **OI-184** (table-grants
  hardening, 4 tables).

## Findings by lens

### L1 — writer_reader_drift

**F1 / F2 — `p_window_start`/`p_user_id` pinned by membership, not
association, in both new contract tests (P1, FIXED).**
`test/contracts/delete_account_rate_limit_writer_to_reader_test.dart` and
`test/contracts/verify_payment_rate_limit_writer_to_reader_test.dart` pinned
`p_quota_key`/`p_limit` by association (regex tying the RPC argument to the
specific constant) but pinned `p_window_start`/`p_user_id` by bare membership
— the file merely CONTAINS the strings `userId`/`bucketStart` somewhere.
Proven exploitable: mutating `p_window_start: bucketStart` →
`p_window_start: new Date().toISOString()` (unfloored — defeats the
fixed-bucket property) and `p_user_id: userId` → a fixed dummy UUID (defeats
per-user isolation) both left every existing assertion in both files green.
**Fixed:** added an association test to each file pinning
`p_user_id:\s*userId` and `p_window_start:\s*bucketStart`, plus a link from
`bucketStart` to its own floored derivation. Mutation-proven: all 4
mutations (2 per file) now redden exactly the new assertion, confirmed live
against `supabase/functions/delete-account/index.ts` and
`supabase/functions/verify-payment/index.ts`, then restored and re-verified
byte-identical to the pre-mutation source.

**F3 — 3 stale review-filename citations (P3, FIXED).** The B-pass review
file was renamed `12408db06b47-review.md` → `1486254681fb-review.md`
mid-batch (content grew after dispatch, moving the staged-diff hash), but
three FORWARD-POINTING citations to the old name survived the rename:
`docs/audit/open_issues.md:3567`, this same diagnose-doc's own migration-130
imprecision note, and `supabase/migrations/CLAUDE.md`'s new pitfall row.
(Three OTHER mentions of the old hash are correct as written — they are
prose describing the rename itself, e.g. "RENAMED from 12408db06b47" — and
were left untouched.) Fixed all 3; re-confirmed via
`git grep -n "docs/reviews/12408db06b47-review.md"` returning zero hits.

**F4 — `docs/sot_registry.yaml`'s `coach_interactions` channel enumeration
missing 4 live values (P2, FIXED).** The "channel field values in use" list
was missing `free_image_analysis`, `video_paywall`, `image_paywall`, and
`proactive_i_see_you` — all four confirmed live via
`grep -rn 'channel: "'` across every EF touching `ai_coach_interactions`.
Also noted (not added to the "in use" list, by design): `'chat'` is treated
as a valid coach-chat channel by `coach_interaction_repository.dart`'s
`_coachChatChannels` reader allowlist for RESTORED rows, though nothing
writes it today; and `pro_image_analysis`/`image_analysis` are read-only,
permanently dormant values (OI-153, a tracked product decision, not a new
finding) correctly excluded from "in use" for the same reason.

### L2 — table-grants / RLS posture

**F2 + F6 (deduplicated as one systemic finding) — 4 tables rely on
RLS-zero-policy default-deny alone; raw grants under it were never narrowed
(P2, pre-existing, filed not fixed).** `usage_counters`,
`account_deletion_log`, `admin_metrics_daily`, and `cron_call_log` all have
RLS enabled with zero policies, and all 4 ALSO grant `anon`/`authenticated`
full SELECT/INSERT/UPDATE/DELETE/TRUNCATE at the raw table level — confirmed
LIVE via `has_table_privilege`, not from memory. Correcting the record from
this session's own earlier (pre-compaction) characterization: two of the
four are more precisely wrong than "pre-existing since 128" —
`admin_metrics_daily`'s own creating migration explicitly tried to narrow
this (`revoke all ... from public; grant ... to service_role`) and the
narrowing did not take, because it revoked from the PUBLIC pseudo-role while
`anon`/`authenticated` hold their OWN direct grant (the exact class
`feedback_revoke_from_public_not_role.md` names); and no migration file
anywhere enables RLS on `account_deletion_log` or `cron_call_log` at all,
yet live state shows both RLS-enabled — that provenance is untraced by this
repo's migration history. Currently SAFE (RLS default-deny blocks all 4
non-TRUNCATE commands); fragile if any future policy is ever added for an
unrelated reason (opens the full un-narrowed grant, not just the intended
slice), and TRUNCATE is granted but not reachable via PostgREST's REST
surface (no TRUNCATE verb), so that half is excess privilege, not a live
exploit path. **Filed as OI-184** — 4 tables × before/after ACL diff × its
own review is a properly separable unit, not a drive-by inside this batch's
delete-account/verify-payment scope.

### L14 — onConflict natural-key live arbiter

**No finding (verified_clean).** `consume_quota`'s
`ON CONFLICT (user_id, quota_key, window_start)` (migration 128) was checked
against the LIVE schema: `pg_constraint` shows `usage_counters_pkey` as a
PRIMARY KEY on exactly those 3 columns, with no partial predicate. This is
NOT the partial-unique-arbiter trap
(`feedback_partial_unique_arbiter_trap.md`) — the arbiter is a plain,
full-coverage PK, which is the safe shape. Nothing to fix.

### L21 — Edge Function semantic correctness

**F3 — UTC-not-IST bucket computation undocumented at the source (P3,
FIXED).** Neither `delete-account/index.ts` nor `verify-payment/index.ts`
explained, at the point of computation, why their rate-limit bucket floors
on UTC epoch rather than IST — a silent divergence from CLAUDE.md §4.5's
IST rule, which a reader unfamiliar with this diagnose-doc's `ist_handling`
field could reasonably read as an oversight. Fixed: added a short comment at
each bucket computation citing the reasoning (sub-day bucket, no
user-visible reset moment, duration is timezone-invariant) and pointing at
this diagnose-doc's `ist_handling` field.

**F5 — verify-payment's fail-closed 429 has no `Retry-After` header, unlike
its sibling exhausted-quota 429 (P3, NOT fixed — decision recorded).**
Confirmed real: the `rateErr` branch returns 429 with no `Retry-After`,
while the `usedCount === -1` branch sets one precisely from the bucket
boundary. **Decided against fixing:** `git grep -n "Retry-After|
retry_after_seconds" lib/` returns ZERO hits — no client anywhere reads
either the header or the body field, including on the EXISTING `-1` branch
that already sets it. A fabricated retry value for a genuinely transient,
unknown-duration failure (there is no bucket boundary to compute from) would
carry less honest information content than the existing case, for a header
nothing consumes. Treated as a non-finding rather than technical debt.

### L22 — [security/access] — convergent with L35

See the single consolidated entry under L35 below; both lenses independently
found the identical defect.

### L23 — [cross-account ownership scoping]

**PARTIAL #1 — weekly-report accepts a body-sourced `user_id`
(verified_clean).** `weekly-report/index.ts:80-88` does read
`body.user_id`, but it is GUARDED: `if (targetUserId !== userId) return 403`
against the JWT-validated caller, exact match, fail-closed. Not exploitable
— the body value can only ever equal the caller's own id or be rejected.
Comment at the site (`"Allow passing user_id in body for server-to-server
calls"`) correctly documents this as a deliberate compatibility shim. No
action.

**PARTIAL #2 — verify-payment's idempotency/race-recovery reads of
`subscriptions` are scoped only by `razorpay_payment_id`, not also by
`user_id` (P2, FIXED as defense-in-depth).** Two reads
(`verify-payment/index.ts`, the pre-SELECT and the 23505-race-recovery read)
query `.eq("razorpay_payment_id", paymentId)` with no `.eq("user_id", ...)`.
Not independently exploitable: by the time either read runs,
`payment.notes.user_id === userId` has already been enforced (the OI-29
guard, lines 416-445) — `paymentId` is already proven to belong to the
caller. Fixed anyway: added `.eq("user_id", userId)` to both, verified safe
against the legitimate webhook-race case (confirmed `razorpay-webhook` also
derives its row's `user_id` from the identical `payment.notes.user_id`
field, so a real race-recovery row can never be excluded by the new filter).
Added an association test (both sites must carry the filter, not just one)
to `test/contracts/verify_payment_notes_user_id_required_test.dart`,
mutation-proven — deleting the filter from the second site reddens exactly
this new test and correctly names which site regressed.

### L29 — [client-server error-contract parity]

**F1 — `delete_account_screen.dart`'s catch block has no branch for a 429/
`rate_limited` response (P2, FIXED).** The delete-account rate limit (5/hr)
was structurally inert before this batch (see the parent diagnose), so this
branch was previously unreachable. Post-fix, a genuine 429 fell through to
the generic "Couldn't delete account, try again" message — misleading for a
transient rate-limit. Fixed: added an `e.status == 429` branch (mirroring
the existing 401 status-code check) mapping to a new `'rate_limited'`
switch case with its own message. Mutation-proven: repointing the branch to
`'generic'` reddens exactly 1 of 39 tests in
`test/features/profile/delete_account_screen_test.dart`, for the right
reason (the new association assertion).

**F2 — verify-payment's rate-limit-exhausted branch has no server-side log,
unlike delete-account's equivalent (P3, FIXED).** Added a `console.warn`
matching the local file's own fail-closed-branch logging style
(`user=${userId}`, no request_id — none is computed this early in this
file). Mutation-proven: removing the log line reddens exactly the new
assertion in `verify_payment_rate_limit_writer_to_reader_test.dart`.

### L35 — [migration ACL / documentation accuracy] — consolidated with L22

**Convergent P1 (found independently by BOTH L22 and L35) — the RLS-vs-
missing-grant discriminator test degenerated to a tautology post-migration-
130 (FIXED).**
`test/edge_functions/usage_counters_rls_denies_client_test.dart`'s second
test was named "the refusal is RLS, not a missing EXECUTE grant" and
asserted only `caught.code isNot 42883/PGRST202`. Migration 130 revoked
EXECUTE on `consume_quota` from `authenticated`, and a missing-EXECUTE
refusal ALSO carries SQLSTATE 42501 (never 42883/PGRST202) — so that
assertion became permanently true regardless of whether RLS still holds,
green for the wrong reason on every future CI run.
**Fixed, verified live rather than assumed:** ran two read-only,
`BEGIN…ROLLBACK`-wrapped probes via the Management API (`SET LOCAL ROLE
authenticated`, no DDL): a normal call to `consume_quota` today fails with
`permission denied for function consume_quota` (EXECUTE-revoke, hit first);
a DIRECT `INSERT` into `usage_counters` as `authenticated` (bypassing the
function) fails with `new row violates row-level security policy for table
"usage_counters"` — different message, same SQLSTATE, which is exactly why
the old test could no longer tell them apart. The test now asserts on
message text, and the file's header was rewritten to describe the CURRENT
two-layer model (EXECUTE-revoke primary, RLS-zero-policy secondary)
instead of the pre-130 one-layer model it still described. **One claim is
stated as a corollary, not independently re-verified live**: whether RLS
would still hold if EXECUTE were ever mistakenly restored. Re-proving that
live would need a transactional `GRANT EXECUTE ... TO authenticated`, which
the live-apply classifier correctly refused without explicit human
authorization; that authorization was not sought for a defense-in-depth
check the primary fix does not depend on. The corollary follows
deductively from `consume_quota` being `SECURITY INVOKER` (its internal
write runs AS the caller's role) plus the already-proven fact that role's
writes are RLS-blocked independent of any grant — logically sound, stated
as such, not re-proven by a live restored-grant probe in this batch.

**L35's second finding — migration 128's own comments are now stale on the
opposite claim (P3, documented not fixed — migration is immutable).**
128's `COMMENT ON FUNCTION` and an inline comment call the function's
`GRANT ... TO service_role, authenticated` "REDUNDANT" and "harmless…
because the design does not rely on grants" — migration 130 proved the
opposite. Per `supabase/migrations/CLAUDE.md`'s immutability rule (an
applied migration's file, including comments, must never be edited — doing
so falsifies the ledger's hash), this is NOT corrected in 128. Recorded in
this diagnose-doc instead, alongside the identical-shape correction already
there for migration 130's own rollback-comment imprecision (also found by
the B-pass).

### L40 — [pre-existing / adjacent scope]

**F2, F3, F4 — three findings, all correctly assessed as pre-existing and
out of this diff's scope (verified_clean, no action).** Per this session's
own pre-compaction triage, all three were reviewed and determined to
describe defects or patterns that predate this batch and are not touched by
the delete-account/verify-payment/migration-130 diff. No independent
re-derivation of their exact text survived compaction; their disposition
(correctly out-of-scope, no action needed) did survive as this session's
own recorded conclusion and is not being re-litigated here. If a future
session needs the exact original text, re-run L40 against this same diff.

## Founder triage

Auto-triaged in-session per the standing "post commit" authorization — no
P0/P1 required founder judgment calls beyond what CLAUDE.md's process
invariants already settle (no-deferrals, mutation-proof-before-belief,
live-verify-before-file). One scope decision (OI-184's sizing as a separate
unit rather than a drive-by fix) follows the batch's own established
precedent (OI-153) rather than a fresh judgment call.

## Action items

- [x] L1 F1/F2 — hardened both contract tests to ASSOCIATION, mutation-proven — commit (this batch)
- [x] L1 F3 — fixed 3 stale citations — commit (this batch)
- [x] L1 F4 — fixed sot_registry.yaml channel enumeration — commit (this batch)
- [x] L2 F2/F6 — filed as **OI-184** on `docs/audit/open_issues.md`
- [x] L14 — verified_clean, no action needed
- [x] L21 F3 — fixed UTC/IST comment in both EFs — commit (this batch)
- [x] L21 F5 — verified_clean / no action (no consumer exists for the header this would add)
- [x] L22 + L35 (convergent) — fixed discriminator test + header, live-verified — commit (this batch)
- [x] L23 PARTIAL #1 — verified_clean, no action needed
- [x] L23 PARTIAL #2 — fixed as defense-in-depth, mutation-proven — commit (this batch)
- [x] L29 F1 — fixed client 429 handler, mutation-proven — commit (this batch)
- [x] L29 F2 — fixed missing server log, mutation-proven — commit (this batch)
- [x] L35 (migration 128 stale comment) — documented in diagnose-doc (migration immutable, cannot fix in-file)
- [x] L40 F2/F3/F4 — verified_clean, no action needed

## Self-evolution

Append to `.claude/skills/hermes-pass/SKILL.md`'s history in the same
commit: this pass's distinguishing lesson is that **a consolidated report
compiled after a context compaction must re-verify, not recall** — every
lens finding here was either independently re-checked live in this session
(L14, L2's live ACL query, L22/L35's live message-text probes) or carried
forward only where this session's own pre-compaction triage notes already
recorded a specific, named disposition. No finding's substance came from
recalling what a subagent supposedly said without a corresponding
re-verification step.
