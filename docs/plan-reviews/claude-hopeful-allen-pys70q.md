---
branch: claude/hopeful-allen-pys70q
date: 2026-10-07
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/weekly-report-issue78-review.md
---

# Plan-review record — GitHub #78: Weekly Report video removal, capped refresh, coach copy (account)

**What this branch is.** Client-only change to the Weekly Report screen
(`lib/features/profile/screens/reports_screen.dart`) plus a pure policy file
(`weekly_report_refresh_policy.dart`) and copy constants (`WardroomCopy.reportCard*`):
the Share-as-Video row is removed (its backend `video-status` is a 410 stub), Regenerate is
replaced by a back button, the open-time refresh is PRO-only and at most once per IST day with a
one-call-at-a-time guard, a spent free report (403 NOT_PRO) opens the paywall, and the card is
renamed "Coach's Weekly Dispatch". No Edge Function, schema or deploy change. Diagnose `d7b2e5`.

**How the plan was reviewed — stated plainly.** The plan (root cause, writer/reader map, the
refresh-cap trade-off, the free-user rule, the title and blurb) was proposed in chat and approved by
the founder item by item before any code was written (§4.1); it was NOT put through two
context-blind PLAN reviews before execution. The two rounds counted here are two fresh,
context-blind, read-only reviews of the implemented diff, each verifying every claim against the
code (hence `ground_truth_verified: true`): round 1 on `88ce1db` (6 findings), round 2 on the
post-fix tree `e1ec97d` (3 findings, one of them a defect in round 1's own fix). All nine are
closed; see `docs/reviews/weekly-report-issue78-review.md`.

**Caveat on `converged`.** Round 2's fixes (`fad7232`) were verified by 9 mutants (all reddened),
the 19-test contract file in three time zones and the full suite at pre-push, not by a third
independent review. If round 2 is judged to have surfaced material new issues, the §4.12.1 rule
applies and a third round should run before this lands on `main`.
