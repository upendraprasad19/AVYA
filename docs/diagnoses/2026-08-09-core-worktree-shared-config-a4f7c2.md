---
bug_id: a4f7c2
date: 2026-08-09
batch: worktree-config-integrity
status: fixed
blast_radius: account
symptom: |
  `git rev-parse --show-toplevel` returned
  `.../.claude/worktrees/post38-auth-fixes` from EVERY worktree in the repo and
  from the shared main folder. A session working in
  `.claude/worktrees/train-signout-notif-bugs` ran `git status` and got 146 files
  belonging to another batch, while its own 14 modified files were not listed at
  all — git named files that do not physically exist in that directory.

  Root: `.git/config` — the config file SHARED by all 102 linked worktrees —
  carried `[core] worktree = .../worktrees/post38-auth-fixes`. `core.worktree`
  overrides git's per-worktree resolution, so every git command in the
  repository operated against that one branch's working tree.

  The live risk was cross-session file mixing: a `git add` from any worktree
  would stage post38-auth-fixes' content into that worktree's own index, under
  its own branch. This is precisely the incident class CLAUDE.md §4.13 exists to
  prevent, occurring one level BELOW where its gate watches.

  Discovered 2026-08-09 while verifying an unrelated Edge Function change; the
  audit performed after the repair found NO worktree had actually staged foreign
  files, so no commit was corrupted. The exposure was real; the damage was not.
concept: worktree_config_integrity
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is dev-workflow / git
  tooling, same as the sibling entry on f0c2d5 (which established this phrasing
  for the class). The contract: no `core.worktree` key may exist in ANY git
  scope for this repo, because it overrides git's per-worktree working-tree
  resolution and so silently redefines "your own worktree" for every process.
  Enforced deterministically by a pre-commit gate reading
  `git config --show-origin --get-all core.worktree` across all scopes.
  Deliberately NOT added to docs/sot_registry.yaml: that registry tracks
  Hive/Postgres writer-reader contracts, and adding a git-config concept would
  widen its meaning rather than document one.
writers:
  - { file: scripts/new-worktree.sh, method_or_widget: "git worktree add — the ONLY in-repo creator of a worktree; sets no config (ruled out as the source)", line: 48 }
  - { file: scripts/setup-hooks.sh, method_or_widget: "the only in-repo script that writes git config at all (core.sshCommand) — ruled out", line: 63 }
readers:
  - { file: scripts/check_commit_from_worktree.dart, method_or_widget: "primary-vs-linked classification via --git-dir vs --git-common-dir — passed cleanly THROUGHOUT the incident; this is the blind spot", line: 59 }
  - { file: scripts/check_worktree_config_integrity.dart, method_or_widget: "NEW gate — asserts no core.worktree in any scope", line: 44 }
  - { file: scripts/worktree_config_integrity_lib.dart, method_or_widget: "evaluateWorktreeConfig — pure verdict fn over git's exit code + --show-origin output", line: 118 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: test/scripts/worktree_config_integrity_e2e_test.dart
ist_handling:
  - "Not applicable — this is git repository configuration. No date key, no counter reset, no IST-scoped column is involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Not applicable in the user-account sense — this is local developer tooling
  with no user data path. The analogous property (isolation between concurrent
  sessions) is exactly what was broken, and is what the new gate restores.
forbidden_patterns_checked:
  - { pattern: "core\\.worktree", absent: true }
  - { pattern: "git config(?!.*--worktree).*core\\.worktree", absent: true }
proposed_fix: |
  Two parts.

  (1) REPAIR the live corruption:
      git config --file "<repo>/.git/config" --unset-all core.worktree
  Verified afterwards from the main folder AND from two linked worktrees that
  each now resolves to itself. `extensions.worktreeConfig = true` is set but no
  `.git/config.worktree` exists anywhere, so the unset removed nothing else.
  The post38-auth-fixes worktree needed no separate repair — its gitdir,
  commondir and .git pointer were all intact.

  (2) PREVENT recurrence with scripts/check_worktree_config_integrity.dart, a
  pre-commit gate asserting no `core.worktree` in ANY git scope. Checking only
  the shared config file would leave a false-negative class (a global
  ~/.gitconfig or an exported GIT_WORK_TREE produces identical corruption), and
  a false negative here recreates the exact bug the gate exists to catch.

  Root cause is NOT closed and the doc does not pretend otherwise: no in-repo
  script sets this key (grepped — only setup-hooks.sh writes git config at all).
  External tooling (IDE git integration, harness worktree tooling) is not ruled
  out. The most likely mechanism is a `git config core.worktree <path>` run
  without `--worktree` scope, which writes the shared config rather than a
  per-worktree one. The gate is worth having regardless of which wrote it.
regression_test_planned:
  - test/scripts/worktree_config_integrity_e2e_test.dart
  - test/scripts/worktree_config_integrity_lib_test.dart
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "flutter analyze clean; 14 unit tests + 6 e2e tests green. MUTATION-PROVEN: neutering the gate to `exit(0)` turns the e2e suite RED (the injected-corruption assertion catches exit 0 where it demands 1), then green again on restore — the gate discriminates rather than merely existing." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive box, adapter or key is touched; this is git repository configuration." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data path." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage involvement." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The affected contract is developer-tooling-internal (git worktree resolution). Verified end to end post-repair: `git rev-parse --show-toplevel` returns the correct path from the main folder, from train-signout-notif-bugs and from post38-auth-fixes; a full staged-index audit across all worktrees with a non-empty index found only that worktree's OWN files (qualification-exam-plans, 2 files), i.e. no cross-contamination occurred." }
impact_analysis: |
  EXPOSURE: every git operation across 102 worktrees resolved against one
  branch's working tree for an unknown window (the key's write time is not
  recorded by git). Any `git add` during that window could have staged foreign
  files under the wrong branch.

  ACTUAL DAMAGE: none found. The post-repair audit across every worktree with a
  non-empty index found exactly one worktree holding staged files
  (qualification-exam-plans, 2 files), and both were its own. No commit mixed
  files. The 14 uncommitted files in train-signout-notif-bugs are intact.

  WHY THE EXISTING GATE MISSED IT: check_commit_from_worktree.dart classifies
  primary-vs-linked by comparing `--git-dir` to `--git-common-dir`. Those two
  values stay correct while `core.worktree` is set — the key alters where the
  WORKING TREE resolves, not the git-dir topology. So the gate returned an
  accurate answer to the question it asks, while the guarantee it exists to
  enforce ("a worktree has its own index, so mixing is impossible") was false.
  The §4.13 rule text asserts that guarantee as structural; it holds only while
  no core.worktree overrides per-worktree resolution. That assumption is now
  itself gated.
recurrence: |
  First instance of this specific mechanism (core.worktree in shared config).

  It is the THIRD instance of the broader §4.13 cross-session-mixing class: two
  incidents on 2026-07-07 (shared git index in the main folder, diagnose f0c2d5)
  produced the worktree-per-session rule and its gate. This instance defeated
  that rule from underneath rather than violating it — nobody committed from the
  main folder; the isolation itself was undermined.

  Class pattern worth naming: the previous fix gated the RULE (work in a
  worktree) but not the PRECONDITION the rule's guarantee depends on (worktrees
  actually resolve independently). A gate that assumes its own substrate is
  intact will pass while the substrate is corrupt.
related_bugs:
  - f0c2d5
---

# core.worktree in shared config silently redirected all 102 worktrees

## What the operator sees

`git status` in your own worktree lists another batch's files, does not list
your own modified files, and names files that are not physically present in the
directory you are standing in.

## One-line check

```
git config --show-origin --get-all core.worktree
```

Empty (exit 1) is healthy. Any output at all is the bug.

## Repair

```
git config --file "<repo>/.git/config" --unset-all core.worktree
```

Then verify from a LINKED worktree, not just the main folder — the main-folder
check alone will look correct in some configurations and is what would have
hidden the blast radius here:

```
git rev-parse --show-toplevel     # run inside .claude/worktrees/<slug>
```

## Why a new gate rather than a rule

CLAUDE.md §4.13 already says "work in your own worktree", and every session was
obeying it. The rule was not violated; its foundation was. `core.worktree` is a
single line in a file no one reads, written by tooling no one watched, that
silently redefines what "your own worktree" means for every process in the
repository. That is not a discipline problem, so a discipline rule cannot fix
it — hence a gate that asserts the precondition on every commit.
