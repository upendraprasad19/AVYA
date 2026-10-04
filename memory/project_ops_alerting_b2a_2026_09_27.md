# pg_cron SQL-job-failure + job-silence alerts (OI-178) · 2026-09-27

Branch `ops-alerting-b2a` · commit `8b6ceb04` · merged `main` at `3b68140d`
Diagnoses `b4c8e2` (145) + `f7a3d2` (146) · B-pass
`docs/reviews/1c2e14c715da-review.md` (accepted) · plan-review
`docs/plan-reviews/ops-alerting-b2a.md` (4 rounds, converged)

## What this batch was

OI-178: the alerting stack read only `public.cron_call_log`, which only Edge
Functions write, so a pure-SQL pg_cron job could fail every night (or be
switched off entirely) and nothing would ever report it. Two new hourly
alerts, both reading `cron.job`/`cron.job_run_details` directly: 145 for a
job that ran and FAILED, 146 for one that stopped being LAUNCHED or was
deactivated (145 is structurally blind to the second case — no run row at
all is written). Both applied live, jobid 46 and 47.

## Worth carrying forward

**1. A compound boolean's CONNECTIVE is an independent mutation target, not
covered by testing each operand.** The B-pass found a real P1 that three
prior independent review rounds — one of which explicitly mutation-tested
three *other* survivors in the exact same SQL block — all missed: 146's
dedup `NOT EXISTS` joined its critical/warn branches with a top-level `OR`,
and each branch was pinned as its OWN `contains()` substring assertion. An
`OR`→`AND` mutation left BOTH substrings intact (neither branch's own text
changed) and both assertions green, while the combined predicate became
unsatisfiable for any single row — disabling dedup for BOTH severities (a
page-storm) with the test suite reporting 7/7 pass. The one-`contains()`-
per-block pattern reads as *more* thorough than a single sprawling
assertion; it is the opposite here. 145's sibling dedup embeds its OR
*inside one literal string*, asserted whole — and that one IS caught by the
equivalent mutation. **When a compound boolean has each sub-clause pinned by
a separate substring assertion, deliberately mutate the token connecting
them, not just each clause's content.** Recorded in the code-review skill's
own tuning history (§7 entry, 2026-09-26) since that's this pattern's actual
home; no repo `feedback_*.md` exists for `guard_without_its_mirror`'s cited
source (it's one of the harness-local-only files CLAUDE.md already flags as
missing from the repo).

**2. Editing an about-to-be-immutable migration's header for one fix can
silently drift a citation to a DIFFERENT file.** Correcting 145's header
("14 jobs failed within 7 hours" → the real ~14h44m span, live-reverified
independently by both the B-pass reviewer and the coordinator) added one
line, which shifted a line-number citation in `test/helpers` territory —
no, in the diagnose doc's `readers[0]` pointer onto 145.sql itself (90→93).
Caught in the same pass as the original citation-drift fix (146's own
14-line drift across 3 review rounds) rather than left for a future review
to rediscover. Same CLAUDE.md §4.9 class, but the trigger this time was a
fix landing INSIDE the batch's own review cycle, not an unrelated later
edit — the hazard applies to your own remediation commits, not just future
ones.

**3. Applying two migrations, then discovering mid-ledger-update that the
snapshot regen script's JSON formatting convention was single-line-per-job
while my first regen pretty-printed each job multi-line** cost nothing here
(caught before commit) but is worth a beat: when regenerating a committed
JSON snapshot by hand (`backups/live_cron_jobs.json`), diff the OUTPUT
STYLE against the file's current git history, not just its schema — a
`json.dump(indent=2)` default silently reformats every existing entry, which
would have made an otherwise-2-line diff into a 100+-line one.

**4. A session-context reset mid-batch (worktree fell out of context, then
was restored) did not lose any staged/uncommitted work** — everything
survives on disk in the linked worktree regardless of which directory the
harness currently points the agent at. The one thing that DID need
re-verification after the reset: whether the two live-applied migrations
were still actually live (yes — that's a database-side fact, orthogonal to
session state) and whether local `main` had drifted against `origin/main`
in the interim (it had, by 3 commits, from an unrelated concurrent PR) —
worth an explicit fetch+compare rather than assuming the pre-reset state
still holds.

**5. Merging two same-day platform-tier batches lands overlapping
conflicts by construction, not by mistake.** Both `ops-alerting-b2a` and
the already-merged `reuse-audit-fixes` added same-dated Tuning History
entries to `.claude/skills/code-review/SKILL.md` and new diagnose docs to
the auto-generated `docs/diagnoses/INDEX.md` on the same day. Resolution:
keep BOTH tuning-history entries (they're independent, non-conflicting
prose) rather than picking a side; regenerate the auto-generated INDEX.md
from scratch after resolving the real conflict, rather than hand-merging
conflict markers inside a generated file.
