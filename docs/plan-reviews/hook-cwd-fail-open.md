---
branch: hook-cwd-fail-open
plan: docs/plans/hook-cwd-fail-open.md
date: 2026-10-22
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/hook-cwd-fail-open-bpass.md
---

# Plan review - OI-384, Claude Code hooks run from the checkout root

Founder decisions: 2026-10-21 "ok" to fix the retirement block with a tool fix, then "ok" to the widened scope (the hook
commands, the git-safety precheck, the retirement entry, a test that runs every hook command from a subdirectory, a
diagnose-doc with a transcript audit), delivered as ONE PR with three separate commits in that order. Commit, push and
merge are each a separate go. NOT covered: the post-merge live probe (plan 3.5), which needs no founder go (read-only,
`--dry-run`), and the Windows check, OI-348 W1 (founder-owned).

## Tier (CLAUDE.md 4.12.4)

Platform (`.claude/settings.json`, `scripts/git_safety_hook.dart`, `scripts/git_safety_lib.dart`; and, since this
batch's B-pass, `scripts/retire_worktree*.dart`). No kill switch, so the full x2 review applies; no hermes (below
catastrophic).

## Rounds

Four rounds of context-blind review, each verifying claims against the code and the harness docs; dispositions are in
the plan, sections 5-8.

- Round 1 (v1 -> v2): 1 P1 (the git-safety precheck had the same defect against the payload cwd), plus P2/P3s.
- Round 2 (v2 -> v3, on the post-round-1 plan): 1 P1 (the precheck fix was unprovable through a helper-only test; a
  real-hook integration case was added).
- Round 3 (v3 -> v4): 1 P1 (a shape pin in `setUpAll` stopped the file before any behavioural assertion could be shown
  to kill a mutant; `setUpAll` now checks safety only).
- Round 4 (v4 -> v4.1): no P0/P1; verdict converged. Its P2/P3s were folded into v4.1 (section 8). Its "split the
  unit" P2 was put to the founder, who chose one PR with three separate commits.

## Ground truth

Harness behaviour from code.claude.com/docs/en/hooks (read 2026-10-21) and measured on the VPS: the mtime test
(2026-10-21 17:09 UTC), exit 255 by hand from `supabase/functions`, dash's failed `cd` exiting 2, the 2.3 ms prefix
cost. Transcript audit: 19 transcripts, 253 Bash calls from a subdirectory, no raw git landed.

## Build evidence

Full gate loop before the B-pass: `flutter analyze lib/` (0 warnings or errors), full `flutter test` in IST with
`--exclude-tags golden` (10149 passed, 9 skipped), pre-commit gate loop with `PRE_COMMIT_GATE_JOBS=1` (OK). Mutation:
18/18 author mutants red, plus N1-N3 and the mid-merge C11 proof for the B-pass fixes (diagnose `8f3e35`).

## B-pass

`docs/reviews/hook-cwd-fail-open-bpass.md`: two fresh read-only Sonnet seats; 1 P1 (found by both) + 8 P3, all fixed,
`verdict: accepted`.
