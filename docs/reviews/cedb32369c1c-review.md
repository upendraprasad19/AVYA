---
reviewed_at: 2026-10-24T08:28:00+05:30
staged_against: cedb32369c1c (named by the staged-diff hash of the final state; round 1 reviewed the first staged version, the delta round the version after the round-1 fixes; that final state hashed df17bd0d780e before the branch was rebuilt on origin/main 1f1ea306 on 2026-10-24, which re-keyed it because docs/blast_radius.yaml and docs/diagnoses/INDEX.md moved on main; every added and removed line of the 13 hashed files is unchanged, only hunk offsets and the context rows of INDEX.md differ)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 32
verdict: accepted
---

# Code Review — merge-conflict-treadmill A0 (atomic read-only hook install; `git add -u -- <index>`)

Two fresh read-only Sonnet seats, each given an exhaustive command list (read-only git, file reads, scratch repos and
script copies in a scratch directory; mutation of the scripts under review only in round 1, with a recorded sha256
before and after). Round 1 reviewed the whole diff (13 staged files): 0 P0, 0 P1, 6 P2, 12 P3. The delta round reviewed
only what was new since round 1 (the stale-tree refusal, the linked-worktree note, the cmp classification, the chmod
handling, the new tests, the docs): 0 P0, 0 P1, 2 P2, 12 P3. All 32 findings are closed in this batch; none is
deferred. After the delta round the author re-ran the complete mutant list (53 mutants, 46 on scripts/setup-hooks.sh
and 7 on scripts/pre-commit.sh; each applied with a match count of 1, run, restored; sha256 of both scripts equal
afterwards): every one reddened at least one case. Round 1 had found 12 of 14 reviewer mutants alive against the first
version of the tests.

## Round 1 findings (18)

### R1 Finding 1 - P2 - guard_without_its_mirror
- **file:line:** scripts/setup-hooks.sh:207-212 (the behind-main check) and :147-151 (the install loop)
- **claim:** The stale-tree guard runs AFTER all five hooks are replaced and never changes the exit code.
  - A stale tree still downgrades the shared hooks. The WARNING says "Update first", but the install has already happened. Then `exit 0` and the "verify:" line follow.
  - Repro: newer tree installs `v2-newer`; a stale tree (origin/main ahead of HEAD) then runs the installer and the hooks become `v1-stale`, rc=0.
  - The diagnose doc lists "installer run from a STALE tree silently downgraded the hooks" as hazard #2 of the bug. Only the read-only bit protects against OLD installers.
  - The check is also one-directional: it only tests "origin/main is an ancestor of HEAD". It stays silent in two cases.
    - A linked worktree. Nothing compares `git rev-parse --git-dir` with `--git-common-dir`.
    - A branch AHEAD of main with unmerged hook edits. This very branch would install unmerged hooks for every worktree with no warning.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pstale && env PATH=/usr/bin:/bin sh scripts/setup-hooks.sh | grep -v "installed|configured"; echo rc=$?; tail -1 .git/hooks/pre-push` (prints the WARNING, rc 0, then `echo pre-push v1-stale`)
- **suggested-fix:** Run the behind check BEFORE the loop and `exit 1` unless an explicit argument overrides it (an argument, not an env var, so the env scanner does not see a new input). Add a "linked worktree" check that warns or refuses. Pin both with a test asserting that the hooks stay unchanged.
- **status:** fixed — the stale-tree check now runs BEFORE the install loop and refuses (exit 1, nothing replaced); `--allow-stale` overrides; tests: group 15

### R1 Finding 2 - P2 - guard_without_its_mirror
- **file:line:** scripts/setup-hooks.sh:164 (`git -C "$REPO_ROOT" config core.sshCommand ...`, under `set -e`), which sits between the loop and the README/behind/FAILURES block (:200-223)
- **claim:** The record-and-continue promise ends at the `git config` line.
  - If `git config` fails (a stale `.git/config.lock`, a read-only config, or a concurrent `git config` in a repo shared by many worktrees), the installer exits 255 BEFORE the README write, the behind line and the FAILURES list.
  - Hooks that failed are therefore never named.
  - Repro: a missing `commit-msg.sh` plus an existing `.git/config.lock` gives rc=255, no "FAILED" list, no README.
  - Seen without contrivance: 1 of 12 parallel installs died with "could not lock config file .git/config".
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pcl && rm -f .git/config.lock; : > .git/config.lock; env PATH=/usr/bin:/bin sh scripts/setup-hooks.sh; echo rc=$?; ls .git/hooks | grep -c README`
- **suggested-fix:** Append `|| record_failure "core.sshCommand" "could not write .git/config" transient`, or move the config step after the summary logic. Add a case with a pre-created `.git/config.lock`.
- **status:** fixed — a failed `git config core.sshCommand` is a recorded transient failure, not an abort before the summary; case 18

### R1 Finding 3 - P2 - guard_without_its_mirror
- **file:line:** scripts/setup-hooks.sh:125-126 (`chmod +x "$tmp" || true`, `chmod a-w "$tmp" || true`)
- **claim:**
  - (a) The installer verifies bytes (:120, :140) but never verifies the mode. A failing `chmod` (a filesystem without POSIX modes such as exFAT/DrvFs/SMB, or any EPERM) installs five non-executable, writable hooks and prints "installed ... rc=0".
    - Git then silently ignores non-executable hooks.
    - Gate 32 does not check the exec bit either, so it still passes.
    - Repro with a stub `chmod` that exits 1: five `-rw-rw-r--` hooks, rc=0.
  - (b) Dropping either `|| true` (mutants M1 and M2) is not caught by any test; the 17/17 stay green. The mutant is worse than the original. With M1 and the same stub, the installer exits 1 with NO output at all and zero hooks installed. That is exactly the "chmod aborts before record-and-continue" failure the plan warns about.
    - Case 8's fresh-dir trick only covers the two `chmod ... "$dst"` lines.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pm1 && env PATH=$S/pm1/stubbin:/usr/bin:/bin sh scripts/setup-hooks.sh; echo rc=$?` (the pm1 copy has M1 applied, the stub chmod exits 1; prints nothing, rc=1)
- **suggested-fix:** On a chmod failure, `record_failure` it (transient or persistent). Add a post-swap `[ -x "$dst" ] && [ ! -w "$dst" ]` check, and add a case with a stub `chmod` that exits 1, expecting exit 1 and all five hooks named.
- **status:** fixed — a failed `chmod +x` is a recorded persistent failure, a failed `chmod a-w` a warning; case 19

### R1 Finding 4 - P2 - guard_without_its_mirror (mutants M5)
- **file:line:** scripts/setup-hooks.sh:125-127 (chmod before `mv`)
- **claim:** The order "chmod the temp, THEN rename" is what keeps the live hook from ever being non-executable. No test pins it.
  - Mutant M5 moves both chmods to `"$dst"` after the post-swap cmp. It is exactly the old `cp; chmod +x` shape, and it opens a window where `$dst` is mode 0644.
  - A commit starting in that window makes git skip the hook ("hook was ignored because it's not set as executable").
  - Result: 17/17 green.
  - Cases 4 and 10 only check the end state.
- **verification:** apply M5 in scripts/setup-hooks.sh (delete :125-126 and add `chmod +x "$dst" || true; chmod a-w "$dst" || true` before the `echo installed`), then `TZ=Asia/Kolkata flutter test test/scripts/setup_hooks_atomic_install_e2e_test.dart` (green)
- **suggested-fix:** A stub `mv` that records `[ -x "$src_arg" ] && [ ! -w "$src_arg" ]` into a file before delegating, and a case asserting the file says OK.
- **status:** fixed — a recording `mv` stub pins chmod-before-rename; case 20

### R1 Finding 5 - P2 - guard_without_its_mirror and asserted_fixture_value (mutants M10, M29)
- **file:line:** scripts/pre-commit.sh:194 and :211; test/scripts/pre_commit_index_add_e2e_test.dart:115-157 (fixture)
- **claim:**
  - Replacing `git add -u -- <index>` by a bare `git add -u` survives at BOTH sites. All 6 cases are green, in two separate runs.
  - Bare `git add -u` stages every tracked modification, so unrelated unstaged WIP rides into the commit.
    - Verified: a staged board plus an unstaged `other.txt` gives `git diff --cached --name-only` = OPEN_INDEX.md, open_issues.md, other.txt.
  - The fixture has no unrelated unstaged tracked edit, so the `-- <path>` half of the guard is untested.
  - Mirror of the other `-u` case: `git add -u -- <path>` exits 128 ("pathspec did not match") when the path is untracked AND absent. That is theoretical today because both builders always write the file. It is untested.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pau && git diff --cached --name-only` (shows other.txt staged by a bare `git add -u`)
- **suggested-fix:** In the fixture add a tracked file with an unstaged edit and assert it is NOT in `git diff --cached --name-only` after the hook (tracked and ignored variants).
- **status:** fixed — the pre-commit fixture keeps an unrelated unstaged tracked edit; the bare `git add -u` mutants now go red

### R1 Finding 6 - P2 - asserted_fixture_value (mutant M23)
- **file:line:** test/scripts/setup_hooks_atomic_install_e2e_test.dart:319
- **claim:** `isNot(contains('installed ${hooksOf(r)}/$h'))` can never fail.
  - `hooksOf(r)` is the ABSOLUTE `$root/.git/hooks`, but the installer prints `$HOOKS_DIR` as given by git. That is the RELATIVE `.git/hooks/...` at the top of a primary worktree.
  - Mutant M23 (print "installed" before the post-swap cmp) therefore stays green (17/17). With it, a lying `mv` prints "installed .git/hooks/pre-commit" five times for hooks that do not exist.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pm23 && env PATH=$S/pm23/stubbin:/usr/bin:/bin sh scripts/setup-hooks.sh 2>&1 | head -6` (prints installed lines for a lying mv)
- **suggested-fix:** Assert `isNot(contains('installed ')) ` on the `.git/hooks/$h` relative form, or on the basename (`installed` + any path ending in `/$h`).
- **status:** fixed — the installed-line assertion compares a relative path to the relative output; it can fail now

### R1 Finding 7 - P2 - guard_without_its_mirror and asserted_fixture_value (mutants M15, M24)
- **file:line:** test/scripts/setup_hooks_atomic_install_e2e_test.dart:90-94 (`_tmpFiles` filters on `contains('.tmp.')`); scripts/setup-hooks.sh:104 and :172
- **claim:** The leftover scanner cannot see a temp name with no trailing dot-and-pid.
  - M15 (`local tmp="$dst.tmp"`) leaves the pid out of the hook temp. It survives all 17 cases, including case 13 (SIGTERM) and case 12. The trap glob `*.tmp."$$"` then stops matching, but the filter is blind to `pre-commit.tmp`.
  - M24 (README temp `AVYA-HOOKS-README.txt.tmp`) survives case 16 for the same reason.
  - The two safeguards cancel each other out. Two concurrent installers would share one temp file, and a signal death would leave temps behind, with a green suite.
- **verification:** apply `local tmp="$dst.tmp"` at scripts/setup-hooks.sh:104 and run `TZ=Asia/Kolkata flutter test test/scripts/setup_hooks_atomic_install_e2e_test.dart` (17/17 green)
- **suggested-fix:** Make `_tmpFiles` match `.tmp` anywhere in the basename (or list every entry that is not one of the five hooks plus the README). Also assert the pid component, e.g. that a leftover name ends in `.tmp.<digits>`.
- **status:** fixed — `_tmpFiles` matches `.tmp` anywhere in a name (pid-less temp names are seen)

### R1 Finding 8 - P3 - guard_without_its_mirror (mutant M6)
- **file:line:** scripts/setup-hooks.sh:79; test/scripts/setup_hooks_atomic_install_e2e_test.dart:324-332
- **claim:** The invariant in the code comment is that the glob matches only this process's temps, "never a concurrent installer's". It is pinned only against the non-numeric name `pre-commit.tmp.foreign`.
  - M6 (`"$HOOKS_DIR"/*.tmp.[0-9]*`) deletes another installer's live temp and survives 17/17. Effect: the concurrent installer reports a rename failure, not corruption.
- **verification:** apply M6 and run the atomic test (green)
- **suggested-fix:** Use a numeric foreign name such as `pre-commit.tmp.1`. It is never this process's pid and it matches the mutant's glob.
- **status:** fixed — a numeric foreign temp survives the installer's own cleanup (trap glob is exact-pid)

### R1 Finding 9 - P3 - guard_without_its_mirror (mutant M16)
- **file:line:** scripts/setup-hooks.sh:104
- **claim:** "Temp file next to the hook" is the atomicity property, and nothing pins its location.
  - M16 (`local tmp="/dev/shm/$name.tmp.$$"`, so `mv` is cross-device copy+delete) passes 17/17. Even case 6 stays green because GNU `mv` unlinks the destination first. `_tmpFiles` only looks inside the hooks dir.
  - The mutant left 6 read-only temps in `/dev/shm`.
  - A future "use mktemp" change would pass.
- **verification:** apply M16 and run the atomic test (17/17 green); `ls /dev/shm` shows `*.tmp.<pid>` leftovers
- **suggested-fix:** A stub `mv` that asserts `dirname "$src_arg" = dirname "$dst_arg"`.
- **status:** fixed — the recording `mv` stub asserts the temp sits beside the hook

### R1 Finding 10 - P3 - missing_input (the Windows retry is simulable on Linux)
- **file:line:** scripts/setup-hooks.sh:131-133
- **claim:** Mutant M30 (delete `chmod u+w "$dst"` from the retry) survives. The retry is documented as unverifiable, but a stub `mv` that refuses a non-writable target simulates Git Bash.
  - With that stub the original reinstalls fine (rc=0, v2, mode 555).
  - The mutant fails (rc=1, hook stays v1).
  - So the retry path and the "restore a-w on second failure" path can both be covered on Linux.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cat $S/winmv.sh; cd $S/pw_orig && tail -1 .git/hooks/pre-push; cd $S/pw_mnoretry && tail -1 .git/hooks/pre-push` (v2 versus v1)
- **suggested-fix:** Add that stub `mv` as a case: reinstall succeeds and ends read-only.
- **status:** fixed — a Git-Bash-like `mv` that refuses a read-only target pins the `u+w` retry; case 21

### R1 Finding 11 - P3 - guard_without_its_mirror (mutant M20)
- **file:line:** scripts/setup-hooks.sh:121 and :141
- **claim:** The persistent/transient classification is pinned only for the "source not found", "could not rename" and "directory" failures.
  - Re-labelling "temp copy differs" and "differs after the rename" as persistent changes the advice to "retrying will not help" instead of "retry when no commit is running". It survives 17/17 because cases 11 and 14 do not assert the hint.
- **verification:** `sed -i` on a scratch copy of :121 and :141 to `persistent` and run the atomic test (green)
- **suggested-fix:** Assert the `retry when no commit is running` line in cases 11 and 14.
- **status:** fixed — the retry hints (persistent vs transient) are asserted for every recorded failure class

### R1 Finding 12 - P3 - unawaited_no_error_sink
- **file:line:** test/scripts/setup_hooks_atomic_install_e2e_test.dart:222-233
- **claim:** Case 6 starts a hook that spins in `while [ ! -f "$1/go" ]; do sleep 0.05; done`.
  - If anything fails between `startSpawn` (:222) and writing `go` (:233), the process is never killed.
  - Examples: the 10 s `started` wait expiring under load (:226-229), or an exception from `install`.
  - There is no `p.kill()`, `addTearDown` or `finally`. The orphan then loops forever even after tearDown deletes the marks dir.
- **verification:** `grep -n "kill\|addTearDown\|finally" test/scripts/setup_hooks_atomic_install_e2e_test.dart` (no hits)
- **suggested-fix:** `addTearDown(p.kill)` right after `startSpawn`, and write `go` in a `finally`.
- **status:** fixed — case 6 kills the spawned hook in a teardown

### R1 Finding 13 - P3 - asserted_fixture_value
- **file:line:** test/scripts/setup_hooks_atomic_install_e2e_test.dart:86 (`_xBits = 0x49`, asserted at :190 and :305)
- **claim:** The assertion requires exec for owner, group and other, but `chmod +x` honours the umask.
  - Under `umask 077` the installed hook is `500`. It works for the owner, but cases 4 and 10 would fail.
  - The VPS umask is 002 and CI is 022, which hides it.
  - Mask checks are otherwise correct: `0x92 = 0o222` and `0x49 = 0o111`.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pum && stat -c '%a' .git/hooks/pre-commit` (500)
- **suggested-fix:** Assert only the owner bit (`0x40`), or `umask 022` in the child (`sh -c 'umask 022; ...'`).
- **status:** fixed — only the OWNER exec bit is asserted (umask-proof)

### R1 Finding 14 - P3 - missing_input
- **file:line:** scripts/setup-hooks.sh:103 and :120; test/scripts/setup_hooks_atomic_install_e2e_test.dart:358-359
- **claim:**
  - (a) With `cmp` absent from PATH, all five hooks are reported "temp copy differs from its source" with the hint "retry when no commit is running", which is the wrong cause and wrong advice (the only clue is a "cmp: not found" line). With `basename` absent the script dies with rc=127 and one line.
  - (b) `twoCommits` runs `git commit` with no `commit.gpgsign=false`. The sibling pre_commit test sets it (:121). A machine with global signing breaks case 15.
- **verification:** `S=/tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0; cd $S/pnocmp && env PATH=$S/nocmpbin sh scripts/setup-hooks.sh 2>&1 | tail -9`
- **suggested-fix:** Treat a `cmp` exit of 2 or 127 as a persistent "cannot verify" failure. In the test use `git -c commit.gpgsign=false` or plumbing.
- **status:** fixed — `cmp` exit codes are classified (1/2 transient, else persistent; case 22); the fixture sets `commit.gpgsign=false`

### R1 Finding 15 - P3 - mutant M-f (no `-f`, and stderr hidden) and the retry chmod following symlinks
- **file:line:** scripts/setup-hooks.sh:127
- **claim:** `mv -f` versus `mv` is unpinned (no tty in the harness). The first attempt's stderr is `/dev/null`, so on a tty a prompt for a non-writable target is invisible. A scratch pty run of a no-`-f` copy hung silently until the timeout.
  - The retry's `chmod u+w/a-w "$dst"` follows a symlink and would flip the mode of a repo script. I did NOT reproduce this, because it needs two failing `mv`s on a symlink destination, so treat it as a note only.
- **verification:** none beyond the scratch pty run above (`$S/mf_setup-hooks.sh`)
- **suggested-fix:** A stub `mv` that fails when called without `-f`.
- **status:** fixed — `mv -f` is pinned by the recording stub

### R1 Finding 16 - P3 - writer_reader_drift (docs and A2 hand-off)
- **file:line:** docs/diagnoses/2026-10-24-hook-install-in-place-and-ignored-index-add-c5e1a8.md (forbidden_patterns_checked); scripts/check_diagnose_index_fresh.dart:75; scripts/pre-commit.sh:221, :231, :255, :265
- **claim:** "git add docs/diagnoses/INDEX.md absent: true" holds only for `scripts/pre-commit.sh`.
  - `check_diagnose_index_fresh.dart:75` still prints "then `git add docs/diagnoses/INDEX.md`" as the fix. After A2 untracks and ignores the index, that hint exits 1.
  - The ADR, incidents, GATE_INDEX and handbook regen blocks keep plain `git add`. That is harmless while those indexes stay tracked.
- **verification:** `git grep -nE 'git add docs/(diagnoses|audit)/(OPEN_)?INDEX\.md' -- scripts`
- **suggested-fix:** Scope the claim to pre-commit.sh and carry the :75 hint into A2.
- **status:** fixed — the diagnose doc scopes the pattern claim to scripts/pre-commit.sh

### R1 Finding 17 - P3 - doc defect
- **file:line:** docs/onboarding/FRESH_CLONE.md:41-43
- **claim:** The splice leaves a dangling sentence. "A Permission denied ... instead of using chmod. It installs into `git rev-parse --git-common-dir`/hooks, which every worktree shares." now has "It" refer to the chmod sentence, and the line is not wrapped.
- **verification:** `sed -n 38,43p docs/onboarding/FRESH_CLONE.md`
- **suggested-fix:** Start a new sentence with "The installer writes into".
- **status:** fixed — the FRESH_CLONE sentence reads whole

### R1 Finding 18 - P3 - informational
- **file:line:** docs/plan-reviews/ (no `merge-conflict-treadmill.md`)
- **claim:** Blast radius is platform. The merge-seam gate needs a plan-review record plus an accepted B-pass at merge. Neither is in the staged set, which is fine for a commit but is a pre-merge item.
- **verification:** `git ls-files docs/plan-reviews | grep -i merge-conflict`
- **suggested-fix:** Write the record after this pass.
- **status:** fixed — docs/plan-reviews/merge-conflict-treadmill.md is written in a LATER commit than this review (its `bpass_review:` must name the accepted review)

## Delta round findings (14)

### Delta Finding 1 - P2 - Q4 / Q1 (the stale linked worktree is not tested)
- **file:line:** scripts/setup-hooks.sh:102; test/scripts/setup_hooks_atomic_install_e2e_test.dart:380-493 (group 15)
- **claim:** Every group-15 fixture has HEAD on the branch `main`, and `origin/main` is moved by `update-ref`. The linked-worktree case only runs with no `origin/main` (exit 128) and only checks the note. So the one-line mutant `--is-ancestor origin/main HEAD` to `--is-ancestor origin/main main` survives all 26 cases. The same goes for `refs/heads/main`. That mutant compares the primary's local main instead of the tree being installed from, and the stale linked worktree is the scenario that actually hurt (18 of 21 trees were stale).
- **verification:**
  - Setup: in `$S/t2`, main and origin/main are both at C; linked worktree `$S/t2-wt` is on branch `wt` at the older commit A.
  - `cd $S/t2-wt && sh ../setup-hooks.sh 2>&1 | head -1` prints REFUSING (exit 1).
  - `cd $S/t2-wt && sh ../mut_head_main.sh 2>&1 | head -2` prints the linked-worktree note, then `installed .../t2/.git/hooks/pre-commit`. The stale tree installs into the shared dir.
  - `grep -c -- '--is-ancestor origin/main main' $S/mut_head_main.sh` is 1, so the mutation applied.
- **suggested-fix:**
  - In group 15, build a primary with main == origin/main and several commits.
  - Run `git worktree add -b stale <wt> <older>` and run the installer from the worktree.
  - Expect exit 1, REFUSING, an untouched hooks dir and no README.
  - Add the converse: a worktree branched from the current main installs.
- **status:** fixed — the stale check compares HEAD (not the primary's main); a stale linked worktree is refused while the primary is current, the converse installs

### Delta Finding 2 - P2 - Q6 (an AHEAD tree that changes hook sources installs them for everyone)
- **file:line:** scripts/setup-hooks.sh:99-100 (design) and :204-208 (the `cp` is from the working tree)
- **claim:**
  - Only "behind" is refused.
  - A linked worktree on a feature branch that edits `pre-commit.sh` and similar files is "ahead", so it gets only the note at :117 and installs its unmerged hooks into the dir shared by every worktree. That is the hazard the batch exists to remove.
  - The installer also copies working-tree bytes, so a dirty file on an up-to-date tree installs too.
  - `git diff --quiet origin/main -- <sources>` covers committed and uncommitted differences.
  - A flat refusal would wedge the legitimate case (primary main merged locally but not pushed), so the guard should be a loud note, or a refusal only when the current branch is not `main`.
- **verification:** `cd $S/q6 && git diff --quiet origin/main -- scripts/pre-commit.sh; echo $?` prints 1. `sh scripts/setup-hooks.sh >/dev/null; cat .git/hooks/pre-commit` prints the uncommitted `EXPERIMENTAL-UNREVIEWED` body, with install exit 0.
- **suggested-fix:**
  - Before the loop, run `git -C "$REPO_ROOT" diff --quiet origin/main -- scripts/pre-commit.sh scripts/pre-push.sh scripts/commit-msg.sh scripts/prepare-commit-msg.sh scripts/pre-merge-commit.sh scripts/setup-hooks.sh`, and only when `origin/main` exists.
  - On a difference, print a WARNING line naming the files. Refuse unless `--allow-stale` or `--allow-unmerged` is passed whenever `git symbolic-ref -q --short HEAD` is not `main`.
  - Add a test for each side.
- **status:** fixed — a tree off main whose hook sources differ from origin/main is refused (`--allow-unmerged`; warning on main; uncommitted edits seen)

### Delta Finding 3 - P3 - Q4 (the chmod +x failure class is not pinned)
- **file:line:** scripts/setup-hooks.sh:177; test case 19, lines 530-549
- **claim:** Case 19 asserts the exit code, that each hook is named, that no file is installed, that `executable` appears, and that no temp is left. It never asserts the persistent trailer ("fix the tree") or the absence of the transient one ("retry when no commit is running"). The mutant `persistent` to `transient` on line 177 survives, so the user is told to retry a chmod failure that retrying cannot fix.
- **verification:** `cd $S/m_mut && PATH=$S/stub_chmod:/usr/bin:/bin sh scripts/setup-hooks.sh 2>&1 | tail -1` prints "retry when no commit is running". `cd $S/m_orig && PATH=$S/stub_chmod:/usr/bin:/bin sh scripts/setup-hooks.sh 2>&1 | tail -1` prints "fix the tree". Both exit 1, install nothing, and satisfy every case-19 assertion.
- **suggested-fix:** In case 19 add `expect(res.err, contains('fix the tree'))` and `isNot(contains('retry when no commit is running'))`.
- **status:** fixed — chmod +x failure on an already-executable copy is accepted; persistent/transient trailers asserted

### Delta Finding 4 - P3 - Q4 (the "silent" tests assert too little, so a stderr leak survives)
- **file:line:** scripts/setup-hooks.sh:102; test lines 445-472
- **claim:** The "no origin/main ref (exit 128) -> silent", "up to date" and "ahead" cases only assert `isNot(contains('behind origin/main'))`. Dropping `2>&1` from line 102 survives. On a fresh clone with no `origin/main`, the installer would then print `fatal: Not a valid object name origin/main`, which does not contain "behind origin/main", and still exit 0.
- **verification:** `cd $S/m3 && sh scripts/setup-hooks.sh 2>&1 | head -1` prints `fatal: Not a valid object name origin/main` (m3 holds the mutant).
- **suggested-fix:** In the three silent cases assert that `res.err` has no `fatal:` and no `[setup-hooks] WARNING`, or that `res.err` is empty.
- **status:** fixed — the silent cases assert an empty stderr

### Delta Finding 5 - P3 - Q4 / Q2 (argument handling)
- **file:line:** scripts/setup-hooks.sh:89-91
- **claim:**
  - Any argument other than a literal `--allow-stale` as `$1` is ignored, so `sh scripts/setup-hooks.sh --help` runs a full install. It also fails closed for a typo on a behind tree, because the refusal still fires.
  - The mutant `[ "$1" = "--allow-stale" ]` to `[ -n "$1" ]` survives, because the only argument any test passes is the literal one. With the mutant, `--typo` overrides the refusal and prints "because --allow-stale was given".
- **verification:** `cd $S/bx && sh scripts/setup-hooks.sh --help 2>&1 | head -1` prints `installed .git/hooks/pre-commit`. `cd $S/m2 && sh scripts/setup-hooks.sh --typo 2>&1 | head -1` prints the WARNING line (mutant installed on a behind tree).
- **suggested-fix:** Reject unknown arguments with usage and exit 2 (`--allow-stale` and `-h/--help` only). Add a test that a stray argument on a behind tree still refuses.
- **status:** fixed — unknown argument exits 2, `--help` exits 0, both before anything runs

### Delta Finding 6 - P3 - Q4 / Q5 (a bogus linked-worktree note from a subdirectory is not pinned)
- **file:line:** scripts/setup-hooks.sh:116; test lines 474-492
- **claim:**
  - The `-C "$REPO_ROOT"` on both `rev-parse` calls is load-bearing. From a subdirectory without it, `--git-dir` prints an absolute path and `--git-common-dir` prints `../.git`, so the strings differ.
  - Every test runs the installer from the repo root, so dropping `-C` survives and the primary would print "this is a linked worktree".
  - The code is correct today.
- **verification:** `cd $S/m4/scripts && sh setup-hooks.sh 2>&1 | head -1` prints the linked-worktree note from the primary (m4 holds the mutant).
- **suggested-fix:** Add a case that runs `sh ../scripts/setup-hooks.sh` with cwd set to a subdirectory of the primary, and asserts exit 0 and no "linked worktree".
- **status:** fixed — both rev-parse calls take `-C <toplevel>`; a subdirectory run prints no linked-worktree note

### Delta Finding 7 - P3 - Q1 (a diverged primary gets advice that cannot work)
- **file:line:** scripts/setup-hooks.sh:107-109
- **claim:**
  - A primary with a merged-but-unpushed local main, while origin/main advanced, is neither ahead nor behind, so `--is-ancestor` returns 1.
  - The message says "behind origin/main... git merge --ff-only origin/main". That fails with "Not possible to fast-forward".
  - CLAUDE.md 4.13.1 names this divergence as a real state.
- **verification:** `cd $S/t1` has main = X, origin/main = Y, both children of P. `git merge-base --is-ancestor origin/main HEAD; echo $?` prints 1, and the installer prints REFUSING with the ff-only advice (exit 1).
- **suggested-fix:** Distinguish "origin/main is a descendant of HEAD" (behind, ff-only is right) from "diverged" with `git merge-base --is-ancestor HEAD origin/main`. For diverged, say "merge origin/main (or push) first".
- **status:** fixed — diverged trees are told to merge or push (no `--ff-only`)

### Delta Finding 8 - P3 - Q1 (a damaged object store is reported as "behind", with the reason swallowed)
- **file:line:** scripts/setup-hooks.sh:102
- **claim:** When a commit in HEAD's ancestry is unreadable (partial or corrupt clone), `merge-base --is-ancestor` prints `error: Could not read <sha>` and exits 1, not 128. The installer then prints "this tree is behind origin/main" with the real error hidden by `2>&1`. It fails closed and `--allow-stale` overrides it, but the advice (ff-merge) cannot help.
- **verification:** `cd $S/r4 && git merge-base --is-ancestor origin/main HEAD; echo $?` prints `error: Could not read 63b173a3...` and then 1. origin/main is a true ancestor there, and the intact repo returned 0.
- **suggested-fix:** Capture stderr; if it is non-empty with rc 1, print it with the REFUSING message (or treat it as undetermined).
- **status:** fixed — an unreadable history shows git's own error

### Delta Finding 9 - P3 - Q7 ("Permission denied means the installer is old" is false for the new installer)
- **file:line:** scripts/setup-hooks.sh:247-248 (README text), CLAUDE.md section 0 hooks line, docs/architecture/hooks.md "Install mechanics"
- **claim:** The README and the CLAUDE.md line say that any Permission denied means the tree's installer is old, so update and never chmod. The new installer also gets Permission denied when the hooks directory itself is not writable (a root-owned hooks dir after a past `sudo` install is plausible). It then prints `cp: cannot create ... Permission denied`, and the README misdirects. The README warning also says "hooks are unaffected" in that run.
- **verification:** `cd $S/pd && chmod a-w .git/hooks && sh scripts/setup-hooks.sh 2>&1 | head -3` prints three `cp: cannot create regular file '.git/hooks/....tmp.N': Permission denied` lines. Run `chmod u+w .git/hooks` afterwards. FRESH_CLONE.md's wording ("from a plain cp") is accurate.
- **suggested-fix:** Reword to "a plain cp or an OLD installer says Permission denied on a hook FILE". Add "if the hooks DIRECTORY is not writable, fix its owner/mode".
- **status:** fixed — Permission denied is split into hook FILE vs hooks DIRECTORY (CLAUDE.md, hooks.md, FRESH_CLONE.md, README)

### Delta Finding 10 - P3 - Q7 (the staged plan still describes the old loud-line design)
- **file:line:** docs/plans/merge-conflict-treadmill.md:115, 120, 158, 383, 402
- **claim:**
  - :120 and :158 say a stale tree gets "a loud line" and "the install still succeeds"; :383 says "A0 prints a loud line but cannot prevent it".
  - :402 still reads "R5B-5 | loud behind-main line (test 15)".
  - :115 specifies `chmod +x "$tmp" || true`.
  - The shipped behaviour is a refusal, and a chmod +x failure is a recorded persistent failure.
  - The plan is the document later landings (A1, A2) are executed and reviewed against.
- **verification:** `git grep -n -E "loud|chmod \+x \"\\\$tmp\" \|\| true" -- docs/plans/merge-conflict-treadmill.md`.
- **suggested-fix:** Rewrite those five lines to the shipped behaviour (refuse; `--allow-stale`; chmod +x failure recorded), and drop the "cannot prevent it" residual or restate it as the stale local `origin/main` residual.
- **status:** fixed — the plan text describes the shipped refusal

### Delta Finding 11 - P3 - Q4 (cosmetic and classification mutants survive)
- **file:line:** scripts/setup-hooks.sh:148 and :227; test cases 18 and 7
- **claim:**
  - `local name="${dst##*/}"` to `local name="$dst"` survives. Every assertion is `contains('commit-msg')` or `contains(h)`, which a full path also satisfies, so the list would show absolute paths.
  - `transient` to `persistent` on the core.sshCommand record (line 227) survives. Case 18 also has a persistent failure (deleted commit-msg), so the "fix the tree" trailer is always present and "retry when..." is never asserted.
- **verification:** Reasoned from the assertions at test lines 265-267 and 519-528. I did not run these two mutants.
- **suggested-fix:** Assert the exact bullet `'  - commit-msg: source '`. In case 18 use a fixture with all five sources present, so the only failure is the config lock, and assert the "retry" trailer.
- **status:** fixed — exact bullet asserted; case 18 isolates the config lock

### Delta Finding 12 - P3 - Q4 (pre-commit test: a widened pathspec survives)
- **file:line:** scripts/pre-commit.sh:194 and :211; test/scripts/pre_commit_index_add_e2e_test.dart:159
- **claim:** The unstaged WIP (`other.txt`) sits at the repo root, so it catches a bare `git add -u`. The mutant `git add -u -- docs/audit/OPEN_INDEX.md` to `git add -u -- docs/audit` stays green, because no other tracked file under `docs/audit` or `docs/diagnoses` is dirty in any fixture. Same for `docs/diagnoses`.
- **verification:** Reasoned from the fixture (lines 145-160). I did not run it, because that needs the dart stub harness.
- **suggested-fix:** Commit `docs/audit/other_audit.md` and `docs/diagnoses/2026-10-01-wip-cccccc.md` in the fixture. Modify both unstaged after the seed commit and assert neither is staged.
- **status:** fixed — the pre-commit fixture keeps unstaged WIP in docs/audit and docs/diagnoses

### Delta Finding 13 - P3 - Q5 (chmod +x became a hard failure where it used to be `|| true`)
- **file:line:** scripts/setup-hooks.sh:176-180; old version `git show HEAD:scripts/setup-hooks.sh` line 70 (`chmod +x "$dst" || true`)
- **claim:**
  - On a filesystem where chmod fails but files already appear executable (vfat or exFAT mounted with default masks), the new installer now refuses to install anything.
  - On NTFS under Git Bash, chmod returns 0, so the main Windows path is fine.
  - I have no repro for the exotic filesystem, which is why this is P3 and not higher.
- **verification:** Compare the old line above with the new line 176.
- **suggested-fix:** After a failed `chmod +x "$tmp"`, accept the temp if `[ -x "$tmp" ]` is true, and only then record a persistent failure.
- **status:** fixed — covered by the chmod-accept-if-executable test (F3)

### Delta Finding 14 - P3 - Q7 (observation: the F18 plan-review record is not on disk)
- **file:line:** docs/diagnoses/2026-10-24-hook-install-in-place-and-ignored-index-add-c5e1a8.md:161 ("F18 the plan-review record" is listed as closed)
- **claim:** `docs/plan-reviews/` has no `merge-conflict-treadmill.md`, staged or untracked. setup-hooks.sh is now platform tier and CLAUDE.md is platform, so the CI-only merge gate (`check_plan_review_record_exists.dart`) will demand it. This is not a defect if the record is written after this B-pass, but the diagnose doc says the finding is closed.
- **verification:** `ls docs/plan-reviews | grep -i -E "treadmill|merge-conflict"` prints nothing.
- **suggested-fix:** Write the record (`verdict: accepted` lines on the cited files) before the merge, and say in the diagnose doc that it is written after the B-pass.
- **status:** fixed — the plan-review record is written in a later commit; the diagnose doc wording says so

## Lenses checked clean (condensed from both reports)
- writer_reader_drift: Gate 32's `parseInstalledHooks`, its invocation-count regex, the blast-radius content-rule test and `dart_bin_resolver_test` all parse the five quoted `install_hook "..."` calls; no comment or echo introduces another quoted call shape; `install_hook() {` is not counted. The env scanner (`test/helpers/spawn_env_scan.dart` `_scanShell`) finds no read-before-assign in the script (`ALLOW_STALE`, `ALLOW_UNMERGED`, `BEHIND_RC`, `MB_ERR`, `rc`, `name` are all assigned first; no `${X:-` idiom).
- function_exception_swallow: no `.invoke(` in the staged additions; n/a.
- blast_radius_mismatch: scripts/setup-hooks.sh, scripts/pre-commit.sh, scripts/check_hooks_installed.dart, CLAUDE.md and the docs/blast_radius.yaml edit are platform; the batch is platform, as declared.
- secrets_in_tree: regex scan of the staged additions and file names, 0 hits.
- unawaited_no_error_sink: only the case-6 teardown (fixed, R1 Finding 12).
- missing_input: `readlink -f`, `which`, `id -u`, the dart locator and a missing `origin/main` ref (exit 128 installs silently) were probed; Windows Git Bash behaviour of the `u+w` retry, `cmp` and `chmod` is stated as unverified, not claimed.
- asserted_fixture_value: every mode and message literal was recomputed against the script text; weak absence assertions became Findings above.

## Mutants run by the reviewers
Round 1: 14 reviewer mutants; 2 red, 12 survived; every survivor became a test or installer behaviour (see the R1 findings). Delta round: no tests were run by the reviewer (the worktree was in use); the findings are reasoned from the code and from scratch-copy runs with stubs. Restore proofs recorded by both seats: sha256 of the scripts equal to the staged blobs, `git status --porcelain` showing no MM/AM line.

## Founder triage notes
All 32 findings accepted and fixed in this batch (statuses above). Open for the founder after merge, not part of this review's verdict: run `git fetch origin main && git merge --ff-only origin/main && sh scripts/setup-hooks.sh` on the primary and on the Windows clone (A2 requires that confirmation before it merges).
