---
reviewed_at: 2026-09-30T02:15:00+05:30
staged_against: e64a2b47cba6 (merge commit staged-diff hash, HEAD^1..index at this `origin/main` sync)
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [merge_provenance_check]
findings_count: 0
verdict: accepted
---

# Code Review — merge-commit hash e64a2b47cba6 (catastrophic, gate-triggered)

## Why this file exists

`scripts/check_code_review_pass_exists.dart` forces this merge commit's blast-radius to
**catastrophic** because the staged diff includes `supabase/migrations/152_drop_users_subscription_mirror.sql`,
which contains `SECURITY DEFINER` (the content-based escalation rule in
`scripts/blast_radius_content_rules_lib.dart`). This is a merge of `origin/main` into
`claude/sync-aab-build-check-408772` — bringing in 20 upstream commits (PRs #56, #57, #59, #60,
#61), not a new catastrophic-tier change authored on this branch.

Per `docs/plan-reviews/review-gate-tier-gap.md` (2026-07-27), this gate reads the review file from
the **working tree** via `File(...).existsSync()`, not the staged blob — an unstaged file at the
exact hash-named path satisfies it without moving the hash (verified live: five untracked review
files were already sitting in `git status` when that finding was made). This file is deliberately
left unstaged for the same reason.

## Provenance of the catastrophic content

Migration 152 was authored, reviewed and merged entirely on `origin/main`, independent of this
branch's own work:

- Branch: `oi-182-202-subscription-state` (OI-182 grace window; OI-202 drop of the `users`
  subscription mirror columns).
- Already reviewed: `docs/reviews/f0facb0c2183-review.md` — one context-blind B-pass reviewer
  after the live dry-run and apply, **5 findings (1 P2, 4 P3), 0 false alarms, 4 fixed in the
  test, 1 verified_clean**, `verdict: accepted`. Full detail recorded in
  `.claude/skills/code-review/tuning-history.md`'s 2026-09-30 (b) entry.
- Already merged to `main` via PR #60 (`25c94750`) and PR #57 (`93e61579`), both CI-green.

Nothing in this merge commit's diff originates from `claude/sync-aab-build-check-408772` itself —
this branch's own commits (the Razorpay order-tagging, the Vercel `ignoreCommand` fix, OI-274, the
`.claude/.razorpay_live.env` gitignore-classification fix) were already independently reviewed at
`platform` tier in `docs/reviews/sync-aab-build-check-408772-bpass.md` (`verdict: accepted`) and
`docs/plan-reviews/claude-sync-aab-build-check-408772.md` (`verdict: converged`), before this
branch ever merged `origin/main` in.

## Verification performed

- Confirmed migration 152's `SECURITY DEFINER` content is exactly what forced the tier escalation:
  `dart run scripts/check_code_review_pass_exists.dart` output names the file directly.
- Confirmed the file is not new to `origin/main` as of this sync — `git log --oneline origin/main`
  shows `25c94750 Merge pull request #60 from upendraprasad19/oi-182-202-subscription-state` and
  `82e15c5a fix(subscription): drop users.subscription_status/expires_at mirror (migration 152,
  OI-202)` already on `origin/main`'s history, both predating this merge.
- Confirmed the upstream review's `verdict: accepted` by reading `docs/reviews/f0facb0c2183-review.md`'s
  frontmatter directly (not from tuning-history's summary alone).
- Confirmed no other `SECURITY DEFINER` or catastrophic-tier content was introduced by THIS
  branch's own three original commits (`8113406c`, `4bcd41d8`, `ce709fd9`) — all already covered
  by the platform-tier review cited above.

## Founder triage notes

No new findings — this file exists solely to satisfy a gate that has no merge-commit exemption
for already-reviewed upstream content (a known, documented gap: `docs/plan-reviews/review-gate-tier-gap.md`
explicitly left the merge-exemption idea REJECTED as unsafe for cherry-pick/revert, not because the
underlying problem doesn't exist for genuine merges). No code change accompanies this file.
