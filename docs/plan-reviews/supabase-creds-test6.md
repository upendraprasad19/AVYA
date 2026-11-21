---
branch: supabase-creds-test6
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
hermes: accepted
tier: full
blast_radius: catastrophic
reviewed_at: 2026-08-15T17:35:00+05:30
bpass_review: docs/reviews/228af8d27de2-review.md
hermes_report: docs/audit/2026-08-15-hermes-supabase-creds-test6.md
---

# Plan review record — supabase-creds-test6

Greens the `Supabase Integration Tests` job, which has failed on every push to
`main` since `888a3fcd`, and closes the delete-boundary hole that greening it
would otherwise have opened.

Two commits, one push: **`acffbd43`** (uuid delete boundary + free-tier doc
drift) and **`e4121c14`** (credentials from the environment). Split on that seam
deliberately — see below.

## Review rounds — THREE, all context-blind, all before execution

Each round returned **UNSOUND** and each found a *different* class. Per §4.12.1
that is convergence when the classes stop being new, and a split signal when they
do not — both happened here, in that order.

- **Round 1 (Sonnet).** Found the plan duplicated an unmerged branch
  (`supabase-ci-http-mock`) and was about to re-invent a guard that branch already
  had. Also: the two `edge_functions` files carry their own 2-value skip-gates and
  never consult the helper, so widening `hasCredentials` alone fixes one of three.
- **Round 2 (Opus, on the hardened plan).** Found the P0 that would have reddened
  a *different* CI job: `cleanup_target_guard_test.dart` pinned the email constant
  as a literal, and the `Unit Tests` job runs `flutter test test/` with **no**
  `--dart-define`, so an environment-backed constant evaluates to `''` there. Also
  that harvesting `http_override_restored_test.dart` would have REGRESSED `main`
  (the branch's copy is the older one), and that the announce step must widen to
  four inputs or a missing secret is a silent green.
- **Round 3 (Sonnet, on piece 2 alone).** Found that the prior branch converted
  the *password* to an environment read but left the *email* bound to a constant
  still naming the dead account — so a faithful harvest would have wired up both
  secrets and left CI red with the identical error.

**The split came out of round 3.** Three rounds each finding new classes meant the
unit was too large; the root cause was mine — I had bundled a safety-boundary
redesign with a credential switch. They have different surfaces and different
verifiability, so each round pressed on whichever half and found something. Split
on that seam, the boundary landed first and can be verified with no secret at all.

## B-pass — `docs/reviews/228af8d27de2-review.md`, verdict accepted

5 findings, 4 fixed, 1 false alarm. The one worth remembering: `kTestCredentialsPresent`
was **defined with zero call sites** while `DEVICE_TESTING.md` asserted it was the
guard every sign-in flow checks — a documented enforcement claim that was untrue.

## Hermes — `docs/audit/2026-08-15-hermes-supabase-creds-test6.md`, verdict accepted

Required at catastrophic tier. Four parallel Opus lenses, 12 findings. Two lenses
independently found that the B-pass fix for the above was **itself incomplete** —
one test types the credential directly and bypasses the helper. Same guard, second
false enforcement claim. Also surfaced OI-115's unaddressed write-boundary bullet,
a seed warning written as a comment instead of a check, and a silently
non-idempotent insert adding 7 rows per run.

## Ground truth verified

Every live claim checked directly, not taken from a subagent:

| Claim | How verified |
|---|---|
| `qa@icanbefitter.com` does not exist | `select … from auth.users` on `dedsavbjuwgarrhphgnl` → zero rows |
| test6 exists, id `039b8eb3-…` | same query → exactly one row, id ↔ email |
| test6 is FREE tier | `subscriptions` row: `status='active'` but `end_date 2026-07-03`, expired; `checkPro` needs `end_date > now()` |
| Both secrets exist | `gh api repos/:owner/:repo/actions/secrets` → 4 names, `_TEST_EMAIL`/`_TEST_PASSWORD` updated 2026-08-14T17:49Z |
| Free cap is 10/day, no trial | `ai-proxy/index.ts:71` + live `enforce_chat_app_daily_limit` trigger definition |
| Quota does not accumulate | `cleanup()` deletes `ai_coach_interactions`; its step (`test.yml:386`) precedes the edge step (`:396`) |
| Blast radius | `blast_radius_from_diff.dart` on the staged set → `catastrophic` (I had predicted `platform`) |
| RLS bounds the damage | live `pg_policies`: all 12 tables `auth.uid()`-qualified, none granted to `anon` |

## Three claims of mine that were wrong, corrected in-flight

1. **"The 4th CI run of an IST day will 429."** False — `cleanup()` zeroes the
   rows in an earlier workflow step. Round 1 *confirmed* my arithmetic because I
   asked it to verify my computation; both of us traced the counter and the
   inserter and neither asked who **deletes**. Three separate reviewers have now
   asserted this same premise.
2. **"Ordering 2a-before-2b is load-bearing."** Decorative — both land in one
   commit, so there is no intermediate state. The real property is a design
   constraint: *the final state must not compare emails*.
3. **"The guard fails closed, loudly."** It fails closed **silently** —
   `cleanup()` early-returns on a null id before the guard runs. No delete is
   issued, so not a hole, but the description was wrong.

## Convergence

`converged`. Every finding across three rounds, the B-pass and Hermes is terminal:
fixed, or refuted with the refutation recorded, or accepted with its residual
stated in the open. The gates pass; the guard suite is 14/14 green with no
`--dart-define`, matching the `Unit Tests` job exactly; the boundary is
mutation-proven on three separate mutations, each actually run.

**Not claimed:** that CI will go green. I do not have the password and will not
handle it, so the secret's *value* is unverified — a wrong one fails with the
identical string as today's bug. And OI-121 records that zero assertions in these
files have ever executed, so the first honest run is expected to surface real
defects. A red run after this lands is more likely to be the tests working than
this change being wrong.
