---
branch: claude/hopeful-allen-pys70q
date: 2026-10-07
blast_radius: account
review_rounds: 3
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
post-fix tree `e1ec97d` (3 findings, one of them a defect in round 1's own fix), round 3 on the
delta of round 2's fixes `fad7232` (4 findings, two P2 defects in round 2's own guard). All thirteen
are closed; see `docs/reviews/weekly-report-issue78-review.md`.

**Caveat on `converged`.** Rounds 2 and 3 each found a P2 defect in the PREVIOUS round's fix, which
is the §4.12.1 signal that the unit is large for its size; it is stated here rather than hidden. Round 3's
fixes (the observable `WeeklyReportCallGate`, the 120s call timeout, the guarded `setState`) were NOT
given a fourth independent review: they are covered by 11 mutants of the new code (all reddened), 24
contract tests of which 5 are behavioral on the gate, and the full suite at pre-push. `converged` is
the author's self-attested call that the finding rate has fallen to what mutation plus the suite can
close; if that is judged wrong, a fourth round on the round-3 delta should run before this lands.
