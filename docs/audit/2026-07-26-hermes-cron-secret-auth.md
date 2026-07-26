---
hermes_pass_id: 2026-07-26-hermes-cron-secret-auth
ran_at: 2026-07-26T12:40:00+05:30
batch_scope: branch cron-secret-auth (working tree, pre-commit)
lens_set: [L21, L23, L24, L28, L31]
agents_dispatched: 5
findings_total: 22
findings_by_severity: { P0: 1, P1: 8, P2: 12, false_alarm: 1 }
verdict: accepted
---

# Hermes Pass — cron-secret-auth (catastrophic)

Mandatory per §4.12.3: blast-radius is catastrophic (`_shared/cron_auth.ts` is catastrophic by path
in `docs/blast_radius.yaml`; migrations 107/109/110 are escalated by the SECURITY DEFINER content
rule). Five Opus lenses dispatched in parallel, each context-blind.

## Summary

The batch's core change — moving the cron fleet from an unsatisfiable JWT gate to a shared secret —
was independently re-verified as correct and working by three separate lenses against live state.
The findings are almost entirely about **what the batch did not cover** rather than what it broke.

**One finding was a genuine near-miss ship-blocker (L21-F1): none of the B-pass fixes were staged.**
The working tree had them; the index did not. Committing would have shipped the original code while
the plan-review record, the B-pass review and this report all attested otherwise.

## Findings

### L21 — Edge Function semantic correctness

| # | Sev | Finding | Status |
|---|---|---|---|
| F1 | **P1** | `timingSafeEqual` and the other two B-pass fixes existed only in the working tree — `git show :…/cron_auth.ts` contained none of them. The commit would have silently dropped all three. | **fixed** — re-staged; `git diff --name-only` now empty, staged blob verified to contain the helper |
| F2 | P2 | Migration 108's operator checklist step 2 said "logCronStart moved ABOVE it" — the exact reorder `cron_auth.ts` and 109 reject as unsafe. 108 is applied, so the wrong instruction would persist as a replayable contract. | **fixed** — corrected in-file with an explicit ⚠ note explaining why |
| F3 | P2 | `errorSummary: String(err)` yields `"[object Object]"` for a supabase-js `PostgrestError` (plain object, not an `Error`), so failure telemetry carried no diagnostic content for the dominant failure path. | **fixed** — `(err as {message?:string})?.message ?? String(err)` |

Cleared explicitly: `timingSafeEqual` is sound (both digests awaited, XOR walks full 32 bytes
unconditionally, digest equality is a valid equality test, `crypto.subtle` rejection propagates to
the outer catch → **fail-closed**); `isAuthorizedCronCall` remains non-throwing on every path;
telemetry lifecycle balanced with no orphaned `started` rows; gate precedes all resource allocation;
no missing `await`.

### L23 — Authorization defense-in-depth

| # | Sev | Finding | Status |
|---|---|---|---|
| F1 | P1 | Compensating observability is one-directional. A caller **with** the secret writes `success`/200 rows, satisfying the silence alert and driving the error-rate alert toward zero. No volume or anomaly alert exists on any of the 17 endpoints. | **open** — recorded below |
| F2 | **P1** | `weekly-recalc` was `verify_jwt=false`, ACTIVE, service-role, with **no auth gate at all**. Any unauthenticated POST drove a full-fleet recalculation. | **fixed** — gate added, deployed v20, added to the auth adoption contract |
| F3 | P2 | Migration 108 contradiction (same as L21-F2). | **fixed** |
| F4 | P2 | Secret-strength framing overstated: 20 chars letters-only is ≤114 bits; even a pessimistic dictionary model is years at 10k req/s. Online brute force is **not** the material risk — rotation, expiry and plaintext reachability are. | **accepted correction** — my own framing to the founder was wrong and was corrected |
| F5 | P2 | `verify_jwt=false` moves rejection from the free gateway into billed compute. Same delta already borne by the other 16. | **accepted trade-off** |

Cleared: `private` schema genuinely unreachable (`has_schema_privilege` false for anon/authenticated/
service_role/authenticator — verified, not assumed); both accessors `postgres=X/postgres` with pinned
search_path; the trigger function unreachable via PostgREST (returns `trigger`); no legitimate access
lost; gate fails **closed** on all five return paths.

### L24 — Gate strictness

| # | Sev | Finding | Status |
|---|---|---|---|
| F1 | P1 | The ordering assertion silently skips 2 of 17 functions (`i-see-you-callout`, `proactive-coach-promotion`) because they read the service key into a module const, so the regex finds no match and the `if (svcClientMatch != null)` guard skips. `proactive-coach-promotion` is the F44 function whose whole reason for being listed is that it once shipped unguarded. | **open** — recorded below |
| F2 | P1 | The hardcoded slug lists have no derivation; nothing forces a new cron function in. A derivable source exists and is unused (`CRON_REGISTRY.md` carries a function-slug column). | **open** — recorded below |
| F3 | P2 | The new regression test had **no positive control** — all three assertions are absence-only, so a dead regex would pass all of them. | **fixed** — positive-control test added asserting the detector flags the exact pre-fix line, that `SUPABASE_JWT_SECRET` is never allowlisted, and that >10 real reads are found in-tree |
| F4 | P2 | 4 of 7 allowlist entries have no corroboration anywhere in the repo. | **open** — recorded below |
| F5 | P2 | The batch's new ordering invariant (logCronStart after the gate) is asserted only by a `contains('logCronStart(')` presence check — moving it above the gate would pass every test. | **open** — recorded below |

Cleared: the new test is **not** vacuous (77 real matches; genuinely fails on reconstructed pre-fix
source); missing-dir is a hard fail not a skip; the regex change introduces no false positive in the
current tree (old and new match indices byte-identical for all 13 previously-matching functions).

### L28 — Service-level invariants

| # | Sev | Finding | Status |
|---|---|---|---|
| F1 | P1 | The absence alert aggregates the **whole fleet**, and `pr-detection` runs every 15 min — so `hours_silent` can never reach 2 while that one job is healthy, and single-function death is invisible. | **fixed** — migration 110 adds `alert_cron_function_dead` (per-function, 8-day window sized to clear the weekly job) |
| F2 | P1 | The only automated reader of `public.alerts` is `check_alerts.dart`, which resolves `.claude/.alerts.env` **relative to cwd** — absent in worktrees, which §4.13 makes mandatory. 26 unacknowledged alerts incl. 12 critical, none acknowledged. | **open** — recorded below |
| F3 | P2 | Migration 108 contradiction (dedup of L21-F2 / L23-F3). | **fixed** |
| F4 | P2 | `admin-dashboard-data` treats a service-role caller as an authorized admin, bypassing `ADMIN_USER_IDS`; only `verify_jwt=true` stops a cron-secret bearer, and nothing pins that flag. | **open** — recorded below |
| F5 | P2 | `cleanup_cron_call_log()` wipes the table when no `success` row exists (scalar subquery → NULL → `IS DISTINCT FROM NULL` true for every row), then the alert reports the precise falsehood 109 was written to prevent. | **fixed** — migration 110 spares the newest success row **and** the newest row of any status |

Cleared: exhaustive `pg_proc` + `pg_trigger` sweep found no dispatch path beyond the one trigger the
batch already handles; no `supabase_functions` schema, so no Database Webhooks; all 17 cron-targeted
slugs are `verify_jwt=false` **and** import the gate; the spare-row subquery is concurrency-safe
(uncorrelated InitPlan, single snapshot).

### L31 — Cron efficiency and scheduling

| # | Sev | Finding | Status |
|---|---|---|---|
| F1 | P1 | The registry row I edited in this very diff still had the wrong cadence (hourly vs the live daily `30 3 * * *`) and the wrong job name. | **fixed** — table regenerated from live `cron.job` |
| F2 | P1 | 11 of 20 registry rows had wrong IST↔UTC conversions, two named jobs that do not exist, and five live jobs missing entirely. Gate 31 checks presence only, so all of it was structurally ungated. | **fixed** — full table regenerated with both UTC and IST columns plus an explicit warning that accuracy is unenforced |
| F3 | P1 | Sunday 14:30 UTC: four Gemini-calling per-user jobs co-execute for the first time in 8 weeks. While 401ing they overlapped harmlessly at ~400ms. | **open** — recorded below, time-boxed |
| F4 | P2 | `compute-coach-signals` recomputes every active user nightly with no change predicate; live, 14 of 15 users in scope have no workout in 7 days, so ~93% of round-trips recompute unchanged inputs. | **open** — recorded below |

Cleared: the `id IS DISTINCT FROM (subquery)` plan concern is a **false alarm** (uncorrelated →
InitPlan, evaluated once); retention sizing is fine (~1,020 rows steady state, growth is O(jobs) not
O(users)); index coverage immaterial at this size; no alert storm or self-trigger possible.

## Open items — explicitly NOT closed in this batch

Founder decision 2026-07-26: gate `weekly-recalc` (done) and fix the defects this batch introduced
(done); the remainder are pre-existing conditions surfaced by the audit and are recorded here with
severity rather than silently dropped. They are not deferrals of this batch's own work — every
defect introduced by this batch is fixed in it.

| Ref | Sev | Item |
|---|---|---|
| L31-F3 | P1 | **Time-boxed.** Four Gemini jobs converge at 14:30 UTC Sundays; first live convergence is the day this shipped. Consider staggering `proactive_protein_gap_alert` / `streak-guardian-daily` / `weekly_recap_ready_sunday`. |
| L28-F2 | P1 | `check_alerts.dart` cannot find `.claude/.alerts.env` from a worktree, so the alerts hook reports zero in the mandated environment. 26 unacknowledged alerts, 12 critical. The alerting added by this batch lands in a table nothing reads. |
| L24-F1 | P1 | Ordering assertion silently skips functions using module-const service keys, including the F44 function. |
| L24-F2 | P1 | Adoption lists have no derivation; `CRON_REGISTRY.md`'s slug column is an unused derivable source. |
| L23-F1 | P1 | No volume/anomaly alert — an attacker holding the secret is invisible to both existing alerts. |
| L28-F4 | P2 | `admin-dashboard-data` accepts a service-role caller as admin; enforcement rests only on an unpinned `verify_jwt` flag. |
| L31-F4 | P2 | `compute-coach-signals` has no skip-if-unchanged predicate; ~93% waste today, O(users) at scale. |
| L24-F4 | P2 | Allowlist entries uncorroborated in-repo. |
| L24-F5 | P2 | logCronStart-after-gate invariant is presence-checked, not semantically enforced. |

## Verdict: accepted

Every defect this batch introduced is fixed in it. The one near-ship-blocker (unstaged fixes) was
caught and corrected. Remaining items are pre-existing and recorded above with severity and evidence.

## Self-evolution

- **Lens signal-to-noise:** L21 3/3 real, L23 4/5 real (one framing correction), L24 5/5 real,
  L28 5/5 real, L31 3/4 real (one explicit false alarm). Very high — no lens tuning warranted.
- **New lens candidate — "index vs working tree parity".** L21-F1 was found only because that lens
  happened to run `git show :<path>` rather than reading the file. Nothing in the existing 53 lenses
  charters checking that what is STAGED equals what was reviewed. Every review in this repo reads
  working-tree files while the gates hash the index. Proposed charter: *for every file a review
  claims to have checked, diff the staged blob against the working tree and fail on divergence.*
  This is the review-layer analogue of `feedback_git_landing_verification`.
- **Cost/latency:** 5 Opus lenses, ~745k subagent tokens, ~6 min wall-clock parallel.
