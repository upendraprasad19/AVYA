---
branch: ops-alerting-b2a
date: 2026-09-26
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/1c2e14c715da-review.md
---

# Plan-review record — batch B2a-1 + B2a-1b: pg_cron SQL-job-failure and
# job-silence alerts (OI-178, migrations 145 + 146)

Keystone record for the §4.12 merge gate. Platform tier (neither migration
carries SECURITY DEFINER, classified on the written files) ⇒ ×2 review + a
B-pass; no Hermes. Plan: `docs/superpowers/plans/2026-09-26-ops-alerting-batch-b2a.md`
(both B2a-1 and its B2a-1b continuation section). Diagnose docs: `b4c8e2`
(145) and `f7a3d2` (146).

Split per §4.12.1 from the original B2a plan-review R1, which found the
client-telemetry half needed redesign; this piece — two new SQL-level pg_cron
alerts — converged independently and ships first. Full round-by-round detail,
including every finding and every mutation count, is in the plan doc itself;
this record summarizes.

## Migration 145 (`alert_sql_job_failures`) — converged after 4 rounds

- **R1 (not converged):** established the design (one aggregated alert per
  run, severity split on capacity-vs-real failure kind) against live
  `cron.job_run_details` (jobid 41 failed 5/5 nights, d6b2f9).
- **R2 (not converged, material):** the window used `start_time` where it
  needed `coalesce(end_time, start_time)`; the idempotency guard's quoted
  unschedule hid the job from Gate 31 (OI-193) — fixed to unschedule by
  jobid; an open critical could mask a genuinely new failing job — fixed to
  job-set containment; 24 h sat on the nightly boundary — narrowed to 23 h.
- **R3 (not converged, material):** job-set containment was too coarse
  (mixed capacity+real sets); narrowed to `sql_jobs` (real-failure jobs
  only); a `closes-oi` overclaim was corrected (OI-178 stays open until 146
  also lands); stale doc counts fixed.
- **R4 (converged):** 0 material findings.
- Regression test: `test/contracts/alert_sql_job_failures_test.dart` (8
  tests), 19 mutations proven, each reddening ≥1 test.

## Migration 146 (`alert_cron_job_silent`) — converged after 3 rounds

- **R1 (not converged, material — P1):** the expected-gap CASE gave a gap
  shorter than reality for month-restricted, dow+month, and dom-29–31
  schedules (a yearly job could false-page at ~39 d under the original
  order). Fixed by reordering the CASE (month → dow → dom → hour → `*/N` →
  else) so every branch gives a gap ≥ reality. Also: `why` now carries the
  last run's status (a hung run reads as `(running)`, not "not launched");
  the shared test helper now throws on any numeric-id `alter_job` or a
  direct `UPDATE cron.job` naming the job; residuals filed as OI-250
  (out-of-band heartbeat — self/correlated silence, `cron.log_run`
  dependency) and OI-251 (retention-effect observability). 18 mutations
  proven, each reddening ≥1 test.
- **R2 (not converged, material — P2):** re-enabling a switched-off job, or
  shortening its schedule, pages ONE false critical (`cron.job` has no
  timestamp columns, so "last launched" still predates the change until the
  next scheduled run) — no safe suppression exists (it would leave a
  re-enabled-but-never-relaunched job permanently unjudged, the exact case
  the alert exists to catch), so this is documented and accepted as one
  expected page. Plus P3s: two schedule shapes with unbounded real gaps
  (both day-fields set with one starting `*`; a set month with dom 29–31)
  needed a NULL (not-judged) arm each; 3 mutations against the round-1 test
  suite survived, including one (`silent_jobs` filtered on the wrong `kind`)
  that would have paged critical every hour with all tests green — all 3
  now pinned; the helper's numeric-id regex widened to catch `job_id => N`
  as well as `:=`; wording/count corrections. 5 further mutations proven.
- **R3 (converged):** independently re-verified all 6 round-2 fixes from
  scratch (including re-running the 3 P3-2 mutations itself with its own
  restore + sha256 cycle, and live-executing the new NULL-arm logic against
  all 26 live active jobs to confirm neither arm swallows a live schedule).
  0 new material findings — one non-blocking note only (the new NULL
  condition is conservative beyond its minimal target case; costs nothing
  today).
- Regression test: `test/contracts/alert_cron_job_silent_test.dart` (7
  tests), 18+5 mutations proven across R1/R2, each reddening ≥1 test.

## B-pass (`docs/reviews/1c2e14c715da-review.md`) — accepted

Dispatched after both migrations independently converged, against the full
staged diff (both migrations, both test files, the shared helper, yaml/
registry/doc updates, OI-250/OI-251). 4 findings, all fixed same batch:

- **P1 (`guard_without_its_mirror`):** 146's dedup `NOT EXISTS` joins its
  critical- and warn-branch with a top-level `OR`; each branch was pinned as
  its own `contains()` substring, so an `OR`→`AND` mutation left both
  substrings intact and the test green (7/7) while dedup became structurally
  disabled for both severities (a page-storm) — three independent prior
  review rounds, one of which mutation-tested three *other* survivors in
  this same block, all missed this one, because each looked at a branch's
  content, never the connective between two already-verified branches.
  Fixed: a new assertion pins the boundary text itself; re-mutated,
  independently, now reddens 1/7.
- **P2 (citation drift):** the f7a3d2 diagnose doc's `writers[1]`/`readers[1]`
  `line:` fields onto 146.sql had drifted 14 lines across the R1–R3 header
  growth (CLAUDE.md §4.9's documented recurring class). Fixed — and the fix
  to Finding 3 (below) then shifted a THIRD citation (145.sql's `readers[0]`,
  90→93), caught and fixed in the same pass rather than left for a future
  review to rediscover.
- **P2 (factual error):** "14 jobs failed within 7 hours" (145's header, the
  b4c8e2 diagnose doc, the plan doc) was wrong — independently re-verified
  live by both the reviewer and the coordinator: the real span is 14h44m
  (01:46–16:30 UTC) across two clusters. Corrected in all three locations
  before 145's apply, while the header is still mutable.
- **P3 (registry formatting):** the new CRON_REGISTRY.md rows showed genuine
  IST-converted times with no qualifier next to older rows that show raw UTC
  mislabeled "UTC" — clarified by suffixing the new rows `IST`; the older
  rows' pre-existing mislabeling is untouched, unrelated scope.

145's structurally analogous dedup OR (embedded in one literal string,
asserted whole) was independently checked by both the reviewer and the
coordinator and confirmed already covered — no fix needed there.

Skill self-evolution: `.claude/skills/code-review/SKILL.md` Tuning history
gets a same-dated entry generalizing the `guard_without_its_mirror` method —
a compound boolean's connective between two individually-pinned sub-clauses
is its own mutation target, invisible to per-clause substring assertions.

## Ground truth

Every fact re-derived live on project `dedsavbjuwgarrhphgnl`, read-only, by
the coordinator and independently by each review round; see both diagnose
docs' `touched_layers_checked`. Neither migration is applied as of this
record — apply requires its own explicit founder authorization per §4.3.
