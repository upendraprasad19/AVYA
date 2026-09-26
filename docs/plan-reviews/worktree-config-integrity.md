---
branch: worktree-config-integrity
date: 2026-08-10
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/worktree-config-integrity-bpass.md
---

# Plan-review record — worktree config integrity + lifecycle retirement (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
because it adds a **commit-blocking** pre-commit gate and amends root CLAUDE.md §4.13, so it
carries a B-pass. Not catastrophic → no Hermes.

## Scope

Two halves of one problem — §4.13's worktree model was unenforced at the bottom and unbounded at
the top.

1. **`scripts/check_worktree_config_integrity.dart`** (+ pure
   `scripts/worktree_config_integrity_lib.dart`) — asserts no `core.worktree` in ANY git scope.
   Diagnose `a4f7c2`. CLAUDE.md §4.13 point 7.
2. **`scripts/retire_worktree.dart`** (+ pure `scripts/retire_worktree_lib.dart`) — the missing
   counterpart to `new-worktree.sh`. CLAUDE.md §4.13 point 6 + a §5 per-batch checklist row.

Tests: `test/scripts/worktree_config_integrity_{lib,e2e}_test.dart`,
`test/scripts/retire_worktree_{lib,e2e}_test.dart`, plus registration in
`test/contracts/gate_e2e_env_hermetic_test.dart`'s `_helpers`.

## Root cause (why this exists)

**Half 1 — the substrate.** `.git/config`, shared by all 102 linked worktrees, carried
`core.worktree = .../worktrees/post38-auth-fixes`. Every git command in the repository resolved
against that one branch's working tree: `git status` in any worktree listed another batch's files
and omitted its own. §4.13's existing gate, `check_commit_from_worktree.dart`, passed cleanly
throughout — it compares `--git-dir` to `--git-common-dir`, and those stay correct. The rule was
never violated; its **precondition** was. §4.13 asserts "a worktree has its OWN index, so mixing
is structurally impossible" — true only while nothing overrides per-worktree resolution.

**Half 2 — the lifecycle.** §4.13 mandated creation and defined no end of life. `new-worktree.sh`
created; nothing retired. 106 directories / 17 GB, reclaimed to 1.4 GB. Not neglect — an unclosed
loop in the rule, so it regrows on its own until the rule closes it.

## Ground truth verified

- `core.worktree` corruption reproduced and repaired live; verified from the main folder AND two
  linked worktrees (the main-folder check alone would have missed the blast radius).
- Post-repair index audit across all worktrees: **no cross-contamination**, no commit corrupted.
- Every review claim re-verified against the actual files by the main thread before acceptance,
  per `feedback_audit_verifier_cannot_trust_own_subagent`. Two subagent claims were corrected:
  OI-93 was reported as a 4th recurrence (it is the 3rd), and a worktree count of 108 (it was 102).

## Review rounds

**Round 1 — two independent context-blind lenses (destructive-safety, doc/consistency): 12
findings, 1 P0.**
- P0: `--execute` destroyed gitignored files. `git status --porcelain` excludes them AND
  `git worktree remove` does not refuse — verified: exit 0, file gone. §4.13 has `new-worktree.sh`
  copy a gitignored `.env` into every worktree, so the blind spot sat on the documented workflow.
- P1: `git log @{u}..` exits 128 with no upstream; reading that as 0 reported a leg as passed that
  was never evaluated.
- P1: the `core.worktree` guard read only the primary's scopes, missing a per-worktree
  `config.worktree` — the a4f7c2 inversion one scope over.
- P1: a slug argument did not scope the orphan sweep; `--execute <unmatched>` still deleted a
  directory and reported success.
- P2 ×2: `_countFiles` measured 0 for a tree of empty subdirectories; `GIT_WORK_TREE` defeated
  primary detection.
- Doc: point 6 had **no trigger** (no checklist row, no cadence, no hook) — the open-issues-board
  failure mode with better prose; the headline dropped the *clean* leg; point 2 did not permit the
  deleting command point 6 requires; the 17 GB figures were uncorroborated.
- **My own arithmetic error:** "five worktrees held 21 uncommitted files" over a list of SIX
  summing to 36. `post38-auth-fixes` is not merged (0 matches in `git branch --merged main`), so
  it was never at risk — including it broke the sum and weakened the claim it was cited for.

**Round 2 — on the HARDENED state, per §4.12.1: 6 findings, 1 P0, and BOTH P0-class findings were
defects introduced by round 1's own corrections.**
- P0: `isRegenerableIgnored` prefix-matched, so `.env` also matched `.envrc` (direnv secrets) and
  the ignored directory `.envs/`. Reproduced end-to-end: both destroyed. Because
  `--ignored=matching` collapses a directory to ONE entry, a single false positive authorises
  deleting an unbounded subtree. Fixed by segment-anchoring file matches.
- P1: the allow-list omitted `android/local.properties` and `GeneratedPluginRegistrant.java` —
  both present in this repo's real ignored set — so every worktree where flutter had run became
  permanently **unretirable**. The round-1 fix over-correcting, the same shape as the no-upstream
  over-correction it followed.
- P1: CLAUDE.md named THREE legs while the code had four, and claimed "pushed" for a branch that
  may never have been pushed.
- P2 ×3: `upstreamConfigured` had no test at all; orphan entries were labelled "files"; a slug
  naming an orphan gave a misleading error.

**Also caught outside the review rounds:** my no-upstream fix over-corrected and reddened 4 tests
before being re-fixed (retire, but say `no upstream configured` rather than claiming `pushed` —
leg 1 already proves the commits reachable from `main`); and `flutter analyze` caught
`retire-worktree.dart` violating Dart's `file_names` lint, a shell convention copied into Dart.

## Convergence

Round 2's findings were materially different in KIND from round 1's — round 1 found gaps in the
original design, round 2 found defects in round 1's repairs. That is the §4.12.1 signal working as
documented. The unit was already split (this is Unit 1+2 of a four-unit plan; the gate-registry and
CI units are explicitly NOT in this branch), and round 2's findings were all local corrections
rather than design reversals, so the unit is converged rather than too large.

## Verification

- 31 retire tests + 22 config-integrity tests green; `flutter analyze` clean for these files.
- **Mutation-proven on all three protective legs** — neutering the dirty check reddens 5 tests, the
  ignored check 4, and reverting the segment-anchored match to prefix matching 4. A gate whose test
  never fails is the Gate-44 lesson this batch exists downstream of.
- Live dry-run against the real repo: all remaining worktrees kept with correct per-leg reasons;
  all orphans reported, none touched.
- The `--execute` sweep was run by the founder (an auto-mode classifier correctly blocked the agent
  from bulk-deleting): 46 → 10 directories, all 8 protected worktrees intact at exactly the
  predicted dirty counts (14/15/3/2/1/1/0/0).

## Residual, stated rather than hidden

- **`GIT_WORK_TREE` is not detected** by the integrity gate, though it causes the same
  misresolution. Deliberate: git exports it into every hook, so flagging it would fail every
  pre-commit run — a self-inflicted ship-stop worse than the gap. The env vector is transient (one
  process tree); the config vector is persistent. Documented in the diagnose-doc.
- **`pr-ag-handoff-gaps`** (thousands of entries, `lib/` + `docs/`, no `.git`) is reported for
  manual review and never auto-removed. git cannot vouch for a directory it has lost track of.
- The 17 GB / 1.4 GB figures are point-in-time measurements, marked as such in CLAUDE.md rather
  than presented as re-derivable.
