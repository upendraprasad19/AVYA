---
branch: worktree-enforcement
date: 2026-07-07
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/worktree-enforcement-bpass.md
---

# Plan-review record — worktree-per-session enforcement (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
(the change adds a **commit-blocking** pre-commit gate + a SessionStart hook + a root CLAUDE.md
invariant), so it carries a B-pass. Not catastrophic → no Hermes.

## Scope
Enforce **one git worktree per session** so concurrent Claude sessions can no longer mix each
other's files. Four layers (defense in depth): (1) pre-commit gate
`scripts/check_commit_from_worktree.dart` (+ pure `scripts/worktree_guard_lib.dart`) blocks a
non-integration commit made in the PRIMARY (shared main) worktree; (2) root CLAUDE.md §4.13 + §7
pointer; (3) `scripts/discipline_hook.dart` SessionStart warning in the shared main worktree;
(4) `scripts/new-worktree.sh <slug>` one-command helper. Diagnose-doc `f0c2d5`; contract test
`test/contracts/check_commit_from_worktree_test.dart`; memory `feedback_worktree_per_session.md`.

## Root cause (why this exists)
Two incidents on 2026-07-07 mixed work across concurrent sessions: multiple sessions ran in the
SHARED main folder, which has ONE git index (`.git/index`). A `git add` from either session stages
into that same index, so a commit from one can sweep in the other's staged files. Worktrees (each
with its own index) were the intended isolation and were used for most past work — but nothing
ENFORCED it. This batch makes it structurally enforced. (The change was itself built + committed
from a worktree, dogfooding the rule it establishes.)

## Review arc (2 rounds; §4.12)
Per §4.3, a docs/process-only ≥account change takes a self-consistency review; this batch also ships
real, commit-blocking CODE, so it additionally got a full adversarial B-pass.

- **Round 1 — design + ground-truth self-review (context: this session).** The mechanism was
  verified against LIVE git before/while building, not assumed:
  - The shared-index root cause reproduced (one `.git/index` for the primary; a linked worktree has
    its own index).
  - Primary-vs-linked detection confirmed live: primary → `--git-dir` == `--git-common-dir`; linked
    → they differ (git structural guarantee — a linked worktree can never have them equal).
  - `.claude/worktrees/` is gitignored (`.gitignore:67`) so worktrees don't pollute status.
  - The gate auto-wires via the `for GATE in scripts/check_*.dart` loop and is recognized by Gate 33
    (`check_gate_scripts_wired.dart`); it is fail-open on any git error and carries an
    `ALLOW_MAIN_COMMIT=1` escape hatch. Contract test drives an exhaustive 32-combo truth table (10/10).
  - `new-worktree.sh` resolves the PRIMARY root via `git worktree list --porcelain` (handles the
    space in "Claude Code/Fitness App") so it never nests the new worktree under a linked one.

- **Round 2 — independent context-blind adversarial B-pass (fresh Sonnet).** Told to break the gate,
  not validate it. Verdict SHIP-WITH-FIXES, **no P0**. Found 1 P1 + several P2; **all material
  findings verified by me against live git and folded in this batch:**
  1. **P1-1 (fixed):** cherry-pick/revert in the primary was blocked (only `MERGE_HEAD` was exempt)
     — extended the integration exemption to `CHERRY_PICK_HEAD`/`REVERT_HEAD`.
  2. **P2-1 (fixed):** the SessionStart warning was a false-negative from a primary *subdirectory*
     (relative `--git-common-dir`) — both dirs now resolved with `--path-format=absolute`;
     re-verified live that the warning now fires from `lib/`.
  3. **P2-5 (fixed):** a local `CI=true` silently exempted — narrowed to `GITHUB_ACTIONS` only.
  4. **P2-4/P2-6 (fixed):** doc drift (`SessionStart:compact`, "merges"-only exemption) synced across
     the hook header, §7, §4.13, memory, and the diagnose.
  5. **P2-2 (soak) / P2-3 (hint visibility):** dispositioned with recorded reasons in the B-pass doc
     (deterministic gate + founder-chosen hard block → no §4.11 soak; uniform gate-failure UX +
     proactive SessionStart warning deliver the recovery guidance). Terminal, not deferred.

## Convergence
After folding every B-pass fix: `dart analyze` clean on gate + lib + hook; the 32-combo contract
test 10/10 green; and live re-verification (gate PASS from a linked worktree; SessionStart warning
silent in a worktree, firing in the primary root AND a primary subdirectory). The fixes are small,
mechanical, and each independently re-verified — no new material issue surfaced, so the unit is
converged (not the §4.12 "keeps-finding-new-issues → split" signal).

**Verdict: converged.**
