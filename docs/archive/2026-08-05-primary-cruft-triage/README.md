# Archive — primary-folder cruft triage, 2026-08-05

13 files that had been sitting **untracked** in the shared main folder
(`C:/Upendra/Claude Code/Fitness App`), some for weeks. They are archived here
rather than committed to their original paths, because each is a point-in-time
artifact of work that has already landed — keeping them live would imply they
are current guidance, which they are not.

Original paths are preserved under this directory, so
`docs/reviews/unit3-web-ux-bpass.md` is at
`docs/archive/2026-08-05-primary-cruft-triage/docs/reviews/unit3-web-ux-bpass.md`.

## What is here

| Original path | Count | What it is |
|---|---|---|
| `docs/audit/_quarterly_20260610/delta-L*.md` | 7 | Per-lens deltas from the 2026-06-10 quarterly audit. The audit's own closure ledger is the durable record; these are its working notes. |
| `docs/plan-reviews/opt-a-rls-initplan.md` | 1 | Plan-review record for the `opt-a-rls-initplan` branch. |
| `docs/reviews/*-review.md`, `*-bpass.md` | 5 | Review outputs for work that has already merged. |

## Why archiving `opt-a-rls-initplan.md` is safe

It lives under `docs/plan-reviews/`, which `scripts/check_plan_review_record_exists.dart`
reads — so moving it deserves a check rather than an assumption. Verified before
the move:

- The `opt-a-rls-initplan` branch **is already merged into `main`**, so its
  landing is long since pushed. The gate only evaluates landings inside the
  *pushed range*, and it reads records via `git show <merge>:<path>` — from the
  merge commit's own tree, not the working tree. This file was **never
  committed**, so no merge commit's tree ever contained it, and nothing that
  already passed can retroactively fail.
- The other two candidate branch names (`community-review-fix`, `unit3-web-ux`)
  do not exist as branches at all.

If any of these branches is ever re-landed at ≥account, it needs a **fresh**
record describing the new diff — reusing one of these would be exactly the
stale-record reuse that `_checkOneRecordOneLanding` (diagnose `a7f3c2`, landed
2026-08-05) now emits an advisory NOTE for.

## What was deliberately NOT archived

- `docs/audit/2026-06-29-hermes-opt-h-restore-marker.md` — a genuine decision
  record, committed to its normal location instead.
- `docs/superpowers/plans/2026-06-0{4,6}-qualification-exam-*.md` — **never
  committed anywhere in git history**, so these were at real risk of loss.
  Committed to their normal location, not archived.
