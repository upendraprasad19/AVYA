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
    method: diagnose-index regen block (tracked-only guard, then git add -u -- docs/diagnoses/INDEX.md)
    line: 196
  - file: scripts/pre-commit.sh
    method: open-issues-index regen block (tracked-only guard, then git add -u -- docs/audit/OPEN_INDEX.md)
    line: 216
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
  - { pattern: 'git add docs/(diagnoses|audit)/(OPEN_)?INDEX\.md', absent: true }   # in scripts/pre-commit.sh: both regen blocks guard with git ls-files --error-unmatch and then use git add -u -- <path>. check_diagnose_index_fresh.dart:75 still prints the plain hint; it dies with Gate 25 in the A2 landing, which deletes that gate
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
  instead of silent or aborting ones. pre-commit.sh stages each regenerated index
  only when it is TRACKED (a git ls-files --error-unmatch guard, then
  git add -u -- <path>): a plain git add of an ignored untracked path exits 1 and,
  on the CI runner's git 2.55.0, so does git add -u -- <path> (exit 128; this VPS's
  git 2.43.0 accepts it; found by CI on PR #159, see "CI finding" below). Gate 32's fix text and CLAUDE.md, hooks.md and FRESH_CLONE.md now
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
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "setup-hooks.sh rewritten (stale-tree refusal, install_hook, record_failure, record_cmp_failure, write_readme, traps); pre-commit.sh tracked-only guard plus git add -u -- at the two regen blocks. Tests: setup_hooks_atomic_install_e2e_test.dart 38/38 and pre_commit_index_add_e2e_test.dart 20/20. Mutation runs (each applied with a match count of 1, run, restored byte-identical; sha256 of both scripts verified equal afterwards): 53 mutants on the state BEFORE the CI finding (46 on setup-hooks.sh, 7 on pre-commit.sh), every one reddened at least one case. The first B-pass (Sonnet, fresh, 110 tool calls) ran 14 more mutants against the FIRST version of these tests and 12 survived; each survivor became a test (chmod before the rename, temp beside the hook, mv -f, numeric foreign temp, pid-less temp names, a Git-Bash-like mv for the u+w retry, a bare git add -u with unrelated unstaged WIP, an installed-line assertion that could not fail because it compared an absolute path to a relative one) and three became installer behaviour (the stale-tree refusal runs BEFORE anything is replaced, a failed git config no longer aborts the summary, a failed chmod +x or an unusable cmp is a recorded failure). Case 13 (SIGTERM) runs only where sh is dash (it is on this VPS); on another sh only case 16 kills the EXIT-trap mutant. After CI found the git 2.55.0 behaviour (section CI finding) and the delta B-pass of the fix, 26 mutants on the guard and the 20-case test (the 16 of the first round, the reviewer's survivors SA swallow-the-add, SB HEAD-keyed guard, SC ignore-keyed guard and SD diagnose-builder-not-fatal at each site, the stub dropped from the hook's PATH, and two spellings of add the stub does not model): every one reddened at least one case. M13/M14 (git add -- <path> without -u inside the guard) are equivalent in behaviour for a tracked file and are red only because the stub refuses any spelling of add it does not model; both files were restored byte-identical (sha256 equal)." }
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

## CI finding on PR #159: `git add -u -- <untracked path>` is an error on newer git

The first pushed version of this fix passed everything locally and failed two cases (2a, 2b) in CI
shard 2/4. The runner has git 2.55.0; this VPS has 2.43.0. Writer: `scripts/pre-commit.sh:196` and
`:216` (the regen blocks). Reader: git itself.

- **Symptom (CI log):** `error: pathspec 'docs/audit/OPEN_INDEX.md' did not match any file(s) known to git`,
  hook exit 128, with the index already built and ignored. Cases 2a and 2b (index ignored and untracked).
- **Cause:** on git 2.43.0 `git add -u -- <path>` is a silent no-op for an existing ignored, untracked
  path; the plan's "(executed)" measurement and both B-pass seats ran only that git. Git 2.55.0 rejects that
  shape (the one CI exercised; other versions and other shapes are not measured). The design claim "a no-op
  for an untracked one" was true on one git version.
- **Fix:** stage an index only when it is tracked: `git ls-files --error-unmatch -- <index> >/dev/null 2>&1`,
  then `git add -u -- <index>`. The question asked of git is the same on every version.
- **Why the local tests could not see it, and what changed:** the e2e hook ran the machine's git. It now runs
  with a PATH-stub `git` that exits 128 for `add -u -- <path>` on an untracked path, refuses (exit 99) every
  spelling of `add` it does not model, passes the rest to the real git and LOGS every call; each case asserts
  from the log that the hook really asked the stub whether the index is tracked and called `add -u` exactly
  when it is (so dropping the stub from the hook's PATH reddens 15 cases). Case 0 proves the stub.
  Mixed fixtures (4a-4d: one index tracked, the other ignored) tell the two sites apart; 2a/2b assert that no
  git noise leaks from the guard (the hook runs with `LC_ALL=C`).
- **Delta B-pass of the fix** (one fresh Sonnet seat, 0 P0, 0 P1, 3 P2, 3 P3; every finding closed in this
  batch): the guard is correct in every index state the reviewer built (tracked clean, modified, deleted,
  intent-to-add, tracked and ignored, merge in progress, linked worktree, bash, bash --posix, busybox); the
  gaps were in the tests. P2: no case for the UNTRACKING commit (staged deletion, ignored path; a guard keyed
  on HEAD survived) or for an index untracked and NOT ignored (a guard keyed on `git check-ignore`
  survived) -> cases 5a/5b/5c; nothing pinned that a failing `git add` inside the guard stays fatal
  (`|| true` survived) -> cases 6a/6b with a held `.git/index.lock`; case 0 ran the stub by absolute path and
  nothing proved the hook used it, and the stub matched only the literal `add -u --` -> the call log and the
  99 tripwire. P3: the version claims were extrapolations ("git >= 2.5x", "any untracked path") -> scoped to
  2.55.0 versus 2.43.0 in the hook, the test, this doc, the plan and bug class 2.118; a diagnose-builder
  failure was untested (`exit 1` -> `:` survived) and no case had a tracked index that rebuilds IDENTICAL
  -> cases 3b and 7a/7b; `--skip-worktree` / `--assume-unchanged` -> Residuals.
- **Recurrence:** the "green local = this machine's layout" class (memory
  feedback_green_local_is_this_machines_layout), here a tool VERSION instead of a path layout. CI was the
  second environment; a reviewer's mutants on the same machine could not have found it.

## Residuals (stated, not hidden)

- The installer's own git calls (`merge-base --is-ancestor`, `config`, `rev-parse`, `diff`) are not
  version-specific as far as CI shows: `setup_hooks_atomic_install_e2e_test.dart` ran in shard 3 of the first
  CI run of PR #159 (git 2.55.0, the log's own `git version`), and that shard passed.
- `git update-index --skip-worktree` on a regenerated index makes the hook exit 1 with sparse-checkout advice,
  and `--assume-unchanged` makes it exit 0 without staging a TRACKED regenerated index. Both behave the same
  under origin/main's plain `git add` and the first A0 hook, so this is not a regression of the fix; no
  repo doc or workflow sets either flag. Measured on git 2.43.0 only.
- Once landing A2 untracks the indexes, two printed hints tell the user to `git add` an ignored path
  (`scripts/check_diagnose_index_fresh.dart:75` and `scripts/pre-merge-commit.sh:183`); both are covered by
  landing A2 as planned (it deletes Gate 25, which owns the first hint, and suppresses the merge hook's NOTE,
  which holds the second, when the index is ignored).
- The cases that touch intent-to-add, unmerged and skip-worktree states delegate to the real git, so how git
  2.55.0 treats those is not measured here.
- The Windows retry (`chmod u+w`, `mv` again) cannot be exercised on Linux.
- A machine whose installed hook is still the OLD one is only fixed when someone
  runs the installer from a current primary. The next landing (A2) therefore
  requires that run, on the VPS primary and the founder's Windows clone, before it
  merges.
- On a non-dash `sh`, case 13 is skipped; case 16 alone kills the EXIT-trap mutant
  there.
