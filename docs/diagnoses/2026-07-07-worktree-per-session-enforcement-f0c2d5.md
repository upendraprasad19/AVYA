---
bug_id: f0c2d5
date: 2026-07-07
batch: worktree-per-session-enforcement
status: fixed
blast_radius: platform
symptom: >
  Two incidents on 2026-07-07 mixed work across concurrent Claude sessions.
  Multiple sessions were running in the SHARED main folder
  (`C:/Upendra/Claude Code/Fitness App`), which has ONE git index
  (`.git/index`). A `git add` from either session stages into that same index,
  so a commit from one session can silently sweep in the OTHER session's staged
  files. During the OPT-A batch, my `git checkout -b` + staged commits in the
  main folder collided with a concurrent session's staged coach-completion work
  in the same index (only escaped by finishing in an isolated worktree).
concept: worktree_per_session_isolation
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is dev-workflow / git
  tooling. The contract: EVERY session that will edit/stage/commit works in its
  OWN git worktree (its own index); the shared main folder is integration-only
  (merge + push + /build-apk). Enforced deterministically by a pre-commit gate
  that blocks a non-merge commit made in the primary worktree.
writers:
  - "{ file: scripts/check_commit_from_worktree.dart, method: main, line: 47 } — the pre-commit gate: gathers git/env facts, calls the pure lib, blocks a non-merge primary-worktree commit."
  - "{ file: scripts/worktree_guard_lib.dart, method: evaluateWorktreeGuard, line: 34 } — pure decision fn (CI / override / no-staged / merge / linked-worktree exemptions; else block)."
  - "{ file: scripts/new-worktree.sh, method: shell, line: 1 } — one-command helper: git worktree add .claude/worktrees/<slug> off main + copy .env."
  - "{ file: scripts/discipline_hook.dart, method: _worktreeWarning, line: 169 } — SessionStart warning when running in the primary/shared main worktree."
readers:
  - "{ file: scripts/pre-commit.sh, method: gate-loop, line: 138 } — the `for GATE in scripts/check_*.dart` loop auto-runs the new gate at pre-commit."
  - "{ file: .claude/settings.json, method: SessionStart, line: 7 } — SessionStart fires discipline_hook.dart (matcher broadened from compact-only)."
  - "{ file: CLAUDE.md, method: section-4.13, line: 1 } — the §4.13 invariant documenting the rule + enforcement."
hive_key_prefix: n/a (git-workflow tooling; no keyed Hive concept)
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a
contract_test_path: test/contracts/check_commit_from_worktree_test.dart
ist_handling: n/a (no date logic)
provider_invalidations: n/a
telemetry_op_types: >
  No runtime telemetry. The gate emits a `[worktree-guard]` PASS/FAIL line at
  pre-commit; the hook emits a SessionStart `⚠️ WORKTREE:` warning.
cross_account_guard: >
  n/a (this is a dev-workflow isolation guard, not a runtime user-scope guard).
  It prevents CROSS-SESSION file mixing at the git-index level, which is the
  developer-workflow analogue.
forbidden_patterns_checked: >
  The gate must FAIL OPEN on any git-introspection hiccup (never wedge a commit
  on a git error); the hook must NEVER break the session (swallow all errors →
  emit nothing). Merges into main (MERGE_HEAD present) are EXEMPT so integration
  still works. CI is exempt (no staged diff there anyway). Escape hatch
  ALLOW_MAIN_COMMIT=1 for a deliberate solo commit — NOT `--no-verify`.
proposed_fix: >
  Four layers: (1) pre-commit gate `check_commit_from_worktree.dart` (+ pure
  `worktree_guard_lib.dart`) blocks a non-merge commit in the primary worktree,
  detecting primary via `git rev-parse --git-dir` == `--git-common-dir`;
  (2) root CLAUDE.md §4.13 invariant + §7 pointer; (3) SessionStart warning in
  `discipline_hook.dart` (matcher broadened off compact-only in settings.json);
  (4) `new-worktree.sh <slug>` helper so the safe path is one command.
regression_test_planned: >
  test/contracts/check_commit_from_worktree_test.dart — an exhaustive 32-combo
  truth table over evaluateWorktreeGuard: blocked IFF (not CI) & (not override)
  & staged & (not merge) & (not linked). All 10 tests pass. Live-verified: the
  gate PASSES from a linked worktree, and the SessionStart warning fires only in
  the primary worktree (git-dir == git-common-dir).
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: new scripts/check_commit_from_worktree.dart + scripts/worktree_guard_lib.dart + scripts/new-worktree.sh; discipline_hook.dart _worktreeWarning; CLAUDE.md §4.13 + §7; settings.json SessionStart matcher broadened. Contract test 10/10 green; hook warning verified in primary + silent in linked. }"
  - "{ layer: client_to_server_contract, status: not_applicable, evidence: no runtime/server behavior changes — this is git-workflow tooling only. }"
impact_analysis: >
  Removes an entire class of cross-session data-loss/mixing incidents by making
  worktree-per-session structurally enforced instead of a convention. The
  pre-commit gate blocks a non-merge commit in the shared main worktree (the
  exact failure mode), the SessionStart hook warns at session start, and the
  helper makes the safe path trivial. Fail-open + escape hatch ensure it never
  wedges a legitimate commit. No runtime/user-facing behavior changes; it is
  developer-workflow hardening. This change was itself implemented + committed
  FROM a worktree (dogfooding the rule it establishes).
closes-diagnose: f0c2d5
---

# f0c2d5 — Worktree-per-session enforcement (stop cross-session file mixing)

## What happened
Two incidents on 2026-07-07 mixed work across concurrent Claude sessions. The
root cause: multiple sessions running in the SHARED main folder
(`C:/Upendra/Claude Code/Fitness App`) share ONE git index. A `git add` from
either session stages into that same index, so a commit from one can sweep in
the other's staged files. Worktrees (each with its own index) were the intended
isolation and were used for most past work — but nothing ENFORCED it, so a
session could (and did) work directly in the shared folder and collide.

## Fix (4 layers, defense in depth)
1. **Pre-commit gate** `scripts/check_commit_from_worktree.dart` (+ pure
   `scripts/worktree_guard_lib.dart`) — BLOCKS a non-merge commit made in the
   PRIMARY worktree (detected via `git rev-parse --git-dir` == `--git-common-dir`).
   Exempt: merges, linked worktrees, CI, nothing-staged, `ALLOW_MAIN_COMMIT=1`.
   Fail-open on git errors. Auto-wired via the `check_*.dart` pre-commit loop.
2. **CLAUDE.md §4.13** invariant + §7 pointer row.
3. **SessionStart warning** in `scripts/discipline_hook.dart` (the settings.json
   SessionStart matcher was broadened off compact-only so it fires at startup).
4. **`scripts/new-worktree.sh <slug>`** — one command to create a worktree +
   copy `.env`, so the easy path is the safe path.

## Verification
- `test/contracts/check_commit_from_worktree_test.dart` — 32-combo truth table,
  10/10 green.
- Gate PASSES from a linked worktree (this change was built + committed from
  `.claude/worktrees/worktree-enforcement`); the SessionStart warning fires only
  in the primary worktree.

## Recurrence
First codification of the cross-session mixing class. Related: the
`using-git-worktrees` skill + the `.claude/worktrees/` convention already existed
— the gap was enforcement, now closed. See `memory/feedback_worktree_per_session.md`.
