---
bug_id: c5e1a8
date: 2026-10-24
batch: merge-conflict-treadmill-a0
status: fixed
blast_radius: platform
symptom: >-
  Two latent hazards in the git-hook install path, found while planning the
  merge-conflict-treadmill fix. (1) scripts/setup-hooks.sh overwrote the
  installed hooks IN PLACE with a plain cp, into one hooks dir shared by every
  worktree: a git process mid-way through running the old hook had the script
  rewritten under it (sh reads a script in blocks), and an installer run from a
  STALE tree silently downgraded the hooks for every concurrent session (18 of 21
  worktrees were based on a stale main when measured; the installer had no
  check). It also stopped at the first failing hook, leaving the later ones
  stale with no list. (2) scripts/pre-commit.sh staged the regenerated indexes
  with a plain git add; git add of a path that is ignored AND untracked exits 1,
  and under set -e the hook kills the commit. Harmless while both indexes are
  tracked, but the next landing (A2) untracks them, and hooks are COPIES, so a
  machine whose installed hook still says plain git add would block every commit
  that touches a board or a diagnose doc.
concept: git_hook_install_atomicity
sot_registry_entry: not_applicable — process/tooling; no Hive or cloud writer/reader contract
writers:
  - file: scripts/setup-hooks.sh
    method: install_hook (temp file, cmp, chmod +x / a-w, mv -f, cmp), record_failure, write_readme, EXIT/HUP/INT/TERM traps
    line: 99
  - file: scripts/pre-commit.sh
    method: diagnose-index regen block (git add -u -- docs/diagnoses/INDEX.md)
    line: 194
  - file: scripts/pre-commit.sh
    method: open-issues-index regen block (git add -u -- docs/audit/OPEN_INDEX.md)
    line: 211
readers:
  - file: scripts/check_hooks_installed.dart
    method_or_widget: Gate 32 per-hook loop (presence, byte comparison against scripts/<hook>.sh, STALE warning text)
    line: 186
  - file: scripts/check_regression_catalog.dart
    method_or_widget: main (reads docs/diagnoses/INDEX.md on merge commits; a missing file exits 2)
    line: 16
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/setup_hooks_atomic_install_e2e_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'install_hook\s+"', absent: false }   # exactly the five canonical calls; Gate 32 and two tests parse that shape (asserted by case 10)
  - { pattern: '\$\{[A-Za-z_]+:-', absent: true }   # no default-idiom read: test/helpers/spawn_env_scan.dart reads it as an env input
  - { pattern: 'git add docs/(diagnoses|audit)/(OPEN_)?INDEX\.md', absent: true }   # in scripts/pre-commit.sh: both regen blocks use git add -u -- <path>. check_diagnose_index_fresh.dart:75 still prints the plain hint; it dies with Gate 25 in the A2 landing, which deletes that gate
proposed_fix: >-
  setup-hooks.sh installs each hook atomically and read-only: copy to a temp
  file next to the hook, cmp it against the source, chmod +x and a-w, rename it
  over the old hook (a rename swaps the directory entry, so a running hook keeps
  its inode), then cmp again. A step that fails is recorded and the loop carries
  on; the installer ends with the list and exit 1. Temp files carry the process
  id and an EXIT trap (plus HUP/INT/TERM traps that turn a signal into an exit,
  because dash skips the EXIT trap on signal death) removes only this process's
  own. Because the installed hooks are non-writable, an OLD tree's installer
  (plain cp) fails with Permission denied instead of downgrading them. The
  installer REFUSES to run (exit 1, nothing replaced) when origin/main is not an
  ancestor of HEAD, because a current installer run from a stale checkout would
  otherwise downgrade the shared hooks (--allow-stale overrides; the cause is told
  apart, so a behind tree is told to fast-forward, a diverged one to merge or push,
  and an unreadable history shows git's own error; a clone with no origin/main ref
  installs). It also REFUSES a tree that is not on main whose hook sources differ from
  origin/main (--allow-unmerged overrides; on main that difference is only a WARNING,
  because the primary's local main may be merged but unpushed), notes when it runs from
  a linked worktree, exits 2 on an unknown argument before touching anything, and writes
  AVYA-HOOKS-README.txt beside the hooks (the one channel that reaches an agent standing
  in a stale tree). A failed chmod +x (unless the temp copy is already executable), a
  failed git config core.sshCommand and a cmp that cannot run are recorded failures
  instead of silent or aborting ones. pre-commit.sh stages the indexes with
  git add -u -- <path>, which stages a tracked index and is a no-op for an
  untracked one. Gate 32's fix text and CLAUDE.md, hooks.md and FRESH_CLONE.md now
  say "install from the primary after git fetch origin main && git merge
  --ff-only origin/main". setup-hooks.sh moves to platform tier in
  docs/blast_radius.yaml (it was DECLINED as fresh-clone-only; it is the only
  writer of the hooks every worktree runs).
regression_test_planned:
  - test/scripts/setup_hooks_atomic_install_e2e_test.dart
  - test/scripts/pre_commit_index_add_e2e_test.dart
  - test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart
related_bugs:
  - a3d7b1  # ten enforcement scripts, incl. two installed hooks, sat at feature tier (setup-hooks.sh was still declined; this batch promotes it)
  - f2a8c6  # Gate 32 unguarded reads (the gate that reads what this installer writes)
recurrence: |
  Recurrence of the "installed hooks are COPIES" class: OI-104 recorded two
  incidents (2026-08-11, 2026-08-20) where a fix looked broken because the
  installed copy was stale, and memory reference_installed_hooks_are_copies_
  stale_prepush_2026_10_11 recorded a third (a stale pre-push that still ran the
  full suite on branch pushes). Gate 32 detects drift AFTER the fact and only
  warns; none of those fixes touched how the hooks are written. This instance
  changes the writer: atomic, read-only, one place that says who may run it.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "setup-hooks.sh rewritten (stale-tree refusal, install_hook, record_failure, record_cmp_failure, write_readme, traps); pre-commit.sh git add -u -- at the two regen blocks. Tests: setup_hooks_atomic_install_e2e_test.dart 38/38 and pre_commit_index_add_e2e_test.dart 6/6. Mutation runs (each applied with a match count of 1, run, restored byte-identical; sha256 of both scripts verified equal afterwards): 53 mutants on the final state (46 on setup-hooks.sh, 7 on pre-commit.sh), every one reddened at least one case. The first B-pass (Sonnet, fresh, 110 tool calls) ran 14 more mutants against the FIRST version of these tests and 12 survived; each survivor became a test (chmod before the rename, temp beside the hook, mv -f, numeric foreign temp, pid-less temp names, a Git-Bash-like mv for the u+w retry, a bare git add -u with unrelated unstaged WIP, an installed-line assertion that could not fail because it compared an absolute path to a relative one) and three became installer behaviour (the stale-tree refusal runs BEFORE anything is replaced, a failed git config no longer aborts the summary, a failed chmod +x or an unusable cmp is a recorded failure). Case 13 (SIGTERM) runs only where sh is dash (it is on this VPS); on another sh only case 16 kills the EXIT-trap mutant." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive key or box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "End to end on this VPS: the real installer installs the real five hook sources, and Gate 32 run against that install prints PASS: all 5 hook(s) with no WARN (case 10). Not verifiable from the VPS: Windows Git Bash behaviour of the u+w retry, cmp and chmod. Roll-out is the founder's: one run of the installer on the Windows clone." }
impact_analysis: >-
  Platform. The hooks are the enforcement path for every commit, push and merge
  in every worktree. The in-place cp could corrupt a hook that git was running at
  the moment another session installed (a window of seconds on a hook that takes
  minutes), and a stale-tree install replaced newer hooks silently; both fail
  closed in the sense that the damage was a wrong or missing check, not data
  loss. The change makes installing stricter: a tree whose installer is old now
  gets Permission denied, which is the intended signal, and the README names the
  recipe. Nothing runs differently for a commit unless the installer is re-run.
---

# Hook install: in place, shared, and silent when stale

## What was wrong

`scripts/setup-hooks.sh` installed with `cp "$src" "$dst"` straight over the
hook. `$dst` is in `git rev-parse --git-common-dir`/hooks, which every worktree of
the clone shares, so:

1. **In-place rewrite.** `sh` reads a script in blocks. A hook that is running
   when another session installs can read the tail of the NEW file at the OLD
   offset. A rename instead swaps the directory entry and leaves the running
   process on the old inode (case 6 proves it with a 20 KiB hook whose last line is
   its end marker).
2. **No ownership of who may install.** Nothing stopped a stale tree from
   installing. Measured: 18 of 21 worktrees were based on a stale main. Gate 32
   only warns about drift afterwards.
3. **Stop at the first failure.** A missing source or a failing copy exited
   immediately, leaving the later hooks stale with no list.

`pre-commit.sh` staged its regenerated indexes with `git add <index>`. For an
ignored, untracked path that exits 1, so once an index is untracked a stale
installed hook blocks every commit that touches the board or a diagnose doc.

## What the fix does

See `proposed_fix`. The one design choice worth stating: the installed hooks are
READ-ONLY on purpose. An old installer's plain `cp` then fails loudly (case 5),
and the README beside the hooks tells an agent that "Permission denied" means
"update this tree", not "chmod it". The sanctioned exception is a rollback
(`chmod u+w <hooks>/*`, then the installer), recorded in the README, hooks.md and
the installer header.

## B-pass round 1 (docs/reviews, 18 findings: 0 P0, 0 P1, 6 P2, 12 P3)

All eighteen are closed in this batch (none deferred): F1 stale-tree refusal before the loop;
F2 `git config` failure recorded; F3 chmod failures recorded and tested; F4/F9/F15 the recording
`mv` stub pins chmod-before-rename, temp-beside-hook and `mv -f`; F5 unrelated unstaged WIP in the
pre-commit fixture; F6 the absolute-vs-relative assertion; F7/F8 pid-less and numeric foreign temp
names; F10 the Git-Bash-like `mv`; F11 retry hints asserted; F12 the spawned hook is killed in a
teardown; F13 only the owner exec bit is asserted (umask); F14 `cmp` exit codes classified and the
fixture sets `commit.gpgsign=false`; F16 the pattern claim is scoped to pre-commit.sh; F17 the
FRESH_CLONE sentence; F18 the plan-review record. The linked-worktree comparison in F1 became a
note (not a refusal): sessions legitimately run it there today and the README says "primary".
One residual from F15 is NOT reproduced and not fixed: the retry's `chmod u+w` follows a symlink at
the destination; it needs two failing `mv` calls on a symlinked hook, which no workflow produces.
F18's plan-review record is written in a LATER commit than the review file it cites (its
`bpass_review:` must name the accepted review), after the final B-pass.

## Delta B-pass (docs/reviews, 14 findings: 0 P0, 0 P1, 2 P2, 12 P3)

A second fresh Sonnet seat reviewed only what was new since round 1. All fourteen are closed in
this batch: F1 the stale check compares HEAD, not the primary's `main` (a stale linked worktree is
refused while the primary is current; the converse installs); F2 a tree off `main` whose hook
sources differ from `origin/main` is refused, with `--allow-unmerged` (a warning on `main`, an
uncommitted edit is seen too); F3 a failed `chmod +x` on an already-executable copy is accepted,
the persistent/transient trailers are asserted; F4 the "silent" cases assert an EMPTY stderr; F5
an unknown argument exits 2 and `--help` exits 0, both before anything is touched; F6 both
`rev-parse` calls take `-C <toplevel>` and a subdirectory run prints no linked-worktree note; F7
a diverged tree is told to merge or push, not to fast-forward; F8 an unreadable history shows
git's own error; F9 the Permission-denied sentence now separates a hook FILE from the hooks
DIRECTORY (CLAUDE.md, hooks.md, FRESH_CLONE.md, the README); F10 the plan text describes the
shipped refusal; F11 the exact bullet and the lock-only case are asserted; F12 the pre-commit
fixture keeps unstaged WIP in `docs/audit/` and `docs/diagnoses/` too (kills a widened pathspec);
F13 `git -C` on the sources diff; F14 this section. Two tests were added after the review for the
independence of the two overrides. The surviving-mutant measure: round 1 found 12 of 14 mutants
alive, the delta round's own 53-mutant run left none.

## Residuals (stated, not hidden)

- The Windows retry (`chmod u+w`, `mv` again) cannot be exercised on Linux.
- A machine whose installed hook is still the OLD one is only fixed when someone
  runs the installer from a current primary. The next landing (A2) therefore
  requires that run, on the VPS primary and the founder's Windows clone, before it
  merges.
- On a non-dash `sh`, case 13 is skipped; case 16 alone kills the EXIT-trap mutant
  there.
