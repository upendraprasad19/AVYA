---
branch: cron-log-retention-oi199-oi471
plan: docs/plans/cron-log-retention-oi199-oi471.md
date: 2026-11-06
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/0b477314d248-review.md
hermes: accepted
hermes_report: docs/audit/2026-11-06-hermes-cron-log-retention-oi199-oi471.md
---

# Plan-review record - OI-199 + OI-471 (migration 172, per-function keep-set for cron_call_log, drop of the orphan 7-day pruner)

Plan: `docs/plans/cron-log-retention-oi199-oi471.md` (v5). Execution mode: inline, one worktree. Catastrophic by CONTENT: the migration
restates a `SECURITY DEFINER` function, so the batch carries a B-pass and a Hermes pass.

## Founder decisions
- 2026-11-06: scope call "I'd do only the migration and leave out the Telegram `/cron` window change, since Telegram is deferred",
  answered "Ok": the `/cron` window, the alert's message text and a reader past 14 days are OI-478 (parked).
- 2026-11-06: explicit go for the live apply of migration 172 (function replacement and the DROP, one `execute_sql` request): "Yes,
  apply migration". "That's enough" for the local test scope (analyze, the targeted tests and the gate loop, not the full local suite;
  CI runs it on the PR). Commit, push, merge and any rollback were NOT covered and each needs its own go.

## Rounds
Two context-blind Sonnet rounds on the plan before any code (round 1 ground truth, round 2 design and gates on the revised plan); no
P0. Round 1 re-ran the body on 3000 random fixtures (0 violations of superset and exactness as it defined them) and measured the page
counts. Round 2 found the Hermes requirement (R2-1), the record and hash circularity (two commits in one PR, R2-2), the expected-red
list, the job-41 one-transaction consequence and the `id DESC` tie-break; all folded into plan v3 (plan sections "Review #1 applied
(v2)" and "Review #2 applied (v3)"). The plan was then extended by the B-pass round (v4) and the Hermes round (v5); each is recorded
in its own section and report.

## Behavioural proof
Local docker Postgres only (never production; a first production rehearsal of OI-473 hung). `bash
test/sql/cleanup_cron_call_log_per_function_local.sh` applies the REAL migration files: the 169 body 15 of 35 red, the 172 body 35 of
35, `proacl` identical, 19 SQL mutants killed; step 2b runs the exact live apply request (commit, rollback on a wrong md5, rollback
on a catalog dependent). The Dart contract test (65 tests, 40 fixtures) was proved by a neuter experiment (42 red) and hand mutations.
Live after the apply: `md5(prosrc)` 6597e3e24f91126b6268b3d54aa7ea57 and length 460, orphan gone, ACL identical, `anon` and
`authenticated` cannot execute, job 41 unchanged. The keep-set itself is not observable live until a function is quiet for 10 days.

## B-pass
`docs/reviews/0b477314d248-review.md` (two fresh Sonnet reviewers, reviewed at staged `c49ca9e21907`; the name moved because the Hermes
round and the post-apply ledger, board and apply-state edits changed the staged hash; the function text is unchanged). No P0 or P1.
Verdict accepted.

## Hermes
`docs/audit/2026-11-06-hermes-cron-log-retention-oi199-oi471.md`: four Sonnet seats (runbook, readers, security, remediation code), no
P0 or P1, 7 P2 and 24 P3, every finding fixed or filed (OI-478 part 2 for the alert's message text, OI-481 for `error_summary`).
Verdict accepted.
