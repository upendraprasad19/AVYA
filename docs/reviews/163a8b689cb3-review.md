---
reviewed_at: 2026-10-24T14:12:00+05:30
staged_against: 163a8b689cb3 (named by the staged-diff hash of the final state; the reviewer read the state that hashed 9355eeaf31fe, and the fixes below, which add test cases and change wording and two comment lines in scripts/pre-commit.sh, changed the hash)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, asserted_fixture_value, missing_input, function_exception_swallow, blast_radius_mismatch]
findings_count: 6
verdict: accepted
---

# Code Review - merge-conflict-treadmill A0, delta for the CI finding (tracked-only guard around `git add -u -- <index>`)

One fresh read-only Sonnet seat with an exhaustive command list (read-only git, file reads, scratch repos and script
copies in a scratch directory, no `flutter test`, no `dart run scripts/*`, no network). It reviewed only what the fix for
the CI finding added on top of the already-accepted review `docs/reviews/cedb32369c1c-review.md`: the two guards in
`scripts/pre-commit.sh` (`if git ls-files --error-unmatch -- <index> ...; then git add -u -- <index>; fi`), the rewritten
`test/scripts/pre_commit_index_add_e2e_test.dart` (then 11 cases) and the doc text that describes them.

**The CI finding behind this delta.** PR #159 head 222fc264, shard 2: cases 2a and 2b of that test file failed on the CI
runner's git 2.55.0, where `git add -u -- <path>` exits 128 ("pathspec ... did not match any file(s) known to git") for a
path that is ignored, untracked and present on disk. This machine's git 2.43.0 exits 0 for the same command, so every
earlier local check, review and mutant run had been blind to it. The fix is the guard; the test now runs the hook through
a PATH-stub `git` that reproduces the 2.55.0 answer.

Result: 0 P0, 0 P1, 3 P2, 3 P3. The reviewer found the guard correct in every index state it built (tracked clean,
modified, deleted from the worktree, intent-to-add, tracked and ignored, ignored and untracked, untracked and not ignored,
the untracking commit, a merge in progress, a linked worktree, exported `GIT_DIR` / `GIT_INDEX_FILE`, dash, bash,
bash --posix, busybox). The gaps were test strength and stale text. All six findings are closed in this batch; none is
deferred. Afterwards the author re-ran the complete mutant list (26 mutants, below): every one reddened at least one case.

## Findings

### Finding 1 - P2 - guard_without_its_mirror
- **file:line:** scripts/pre-commit.sh:196,216; test/scripts/pre_commit_index_add_e2e_test.dart (then lines 138-220)
- **claim:** The fixtures covered 2 of the 4 (tracked x ignored) cells. They never covered the commit that UNTRACKS the files
  (index lacks the path, HEAD has it, the path is ignored, the deletion is staged), which is the next landing's own commit.
  - SB: a guard `git cat-file -e HEAD:<path>` passed all 11 cases, then exits 128 in the untracking commit.
  - SC: a guard `! git check-ignore -q -- <path>` passed all 11 cases, then exits 128 for an untracked, not-ignored path.
  - The shipped guard exits 0 in both states.
- **verification:** `sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/cases.sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/muts/SB_diag_guard_head.sh | tail -1` prints `RED=0`; the same for `muts/SC_diag_guard_notignored.sh` with the `untracked_not_ignored` filter (rc 128)
- **suggested-fix:** Add two cases: stage `git rm --cached` of both indexes plus the `.gitignore` lines (expect rc 0, deletions still staged, file built); untracked and not ignored (expect rc 0, nothing staged).
- **status:** fixed - cases 5a/5b (the untracking commit, board and diagnose doc) and 5c (untracked, not ignored: exit 0, built, never staged). Author mutants SB1/SB2 (HEAD-keyed guard) and SC1/SC2 (ignore-keyed guard) now redden 7 to 8 cases each (SB1 8, SB2 8, SC1 7, SC2 8).

### Finding 2 - P2 - guard_without_its_mirror
- **file:line:** scripts/pre-commit.sh:197,217
- **claim:** Nothing pinned that a failing `git add` inside the guard stays fatal. `git add -u -- <index> || true` at either site passed all 11 cases. With a held `.git/index.lock` the shipped hook exits 128; the mutant exits 0 and the commit carries a stale index.
- **verification:** `sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/q2.sh` prints `h_orig ... rc=128` and `h_swallow ... rc=0`; `cases.sh` on `muts/SA_board_add_swallow.sh` prints `RED=0`
- **suggested-fix:** One case per site: tracked index plus `.git/index.lock`, expect non-zero.
- **status:** fixed - cases 6a/6b (a tracked index, `.git/index.lock` held, the hook must exit non-zero). Author mutants SA1/SA2 (`|| true` at the diagnose site and at the board site) each redden exactly that case.

### Finding 3 - P2 - asserted_fixture_value
- **file:line:** test/scripts/pre_commit_index_add_e2e_test.dart:174-187, 222-227, 263-277
- **claim:** Case 0 ran the stub by absolute path, and nothing proved the hook runs through it. With the stub off the hook's PATH (a one-line regression of `hook()`), the guard-less first A0 hook passed 11/11, case 0 included: the CI emulation could vanish silently. The stub matched only the literal prefix `add -u --`; `add --update --`, `add -u X`, `add -uv --` and `-C . add -u --` all returned 0 untouched.
- **verification:** `MODE=real sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/cases.sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/hook_head.sh | tail -1` prints `RED=0`; `sh .../bpass_a0_fix/q3.sh` lists the pass-through spellings
- **suggested-fix:** Have the stub append its argv to a log in the fixture; 1a/1b assert the log holds `add -u -- <index>`; 2a/2b assert it holds the `ls-files --error-unmatch` call and no `add`; match `-u|--update` anywhere in the options.
- **status:** fixed - the stub logs every call to `.git/stub-git.log` and the cases assert on it: 1a/1b require `add -u -- <index>` in the log, 2a/2b require the guard's `ls-files --error-unmatch` call and no `add` of the index. The stub now REFUSES (exit 99) every `add` spelling it does not model and any global option before `add`, so a hook spelling `--update` or `-C . add -u` fails loudly instead of passing through; case 0 pins the stub itself. Author mutants T1 (the stub dropped from the hook's PATH: 15 cases red), S1 (`add --update --`) and S2 (`git -C . add -u --`) redden (4 cases each).

### Finding 4 - P3 - stale or overclaimed text
- **file:line:** scripts/pre-commit.sh:194; test header :18 and :29-31; docs/plans/merge-conflict-treadmill.md:73,110,143-147,163,286,300; the c5e1a8 tier-1 evidence
- **claim:**
  - (a) "git >= 2.5x" and "any untracked path" are extrapolations. The evidence is 2.43.0 versus 2.55.0, for one shape (ignored, untracked, existing file).
  - (b) The header and the plan still listed `git add -u` -> `git add` as killed by 2a/2b. Behind the guard that mutant (M13/M14) is behaviourally equivalent: 0 differing outcomes over 11 index states (`muts/M13r.sh`, `muts/M14r.sh`). The "53 mutants ... every one reddened" sentence includes that pair.
  - (c) Plan :286 said "A0's `git add -u` makes it a no-op for an untracked file", which is false on 2.55. Plan :110 and :163 (`:192/:209`) still described the pre-guard design.
- **verification:** `grep -n "no-op for an untracked" docs/plans/merge-conflict-treadmill.md` showed line 286
- **suggested-fix:** Say "tracked-only guard" in those sentences and qualify the version claim as 2.55.0.
- **status:** fixed - the hook comment (the only change to `scripts/pre-commit.sh` since the reviewed state: two comment lines), the test header, the diagnose doc (writers, proposed_fix, evidence), plan lines 73/110/163/286/300 and bug class 2.118 say "tracked-only guard" and scope the claim to the observed 2.55.0 versus 2.43.0; `git add --` without `-u` (M13/M14) is stated as equivalent and killed only by the stub's refusal of spellings it does not model. The "38 installer cases passed on CI" sentence was re-based: shard 2 of the supplied log has no line from `setup_hooks_atomic_install_e2e_test.dart`; that file sorts into shard 3 by the partition rule, and the same run's shard 3 log shows it passing.

### Finding 5 - P3 - missing_input
- **file:line:** scripts/pre-commit.sh:196-197, 216-217
- **claim:** `--skip-worktree` on an index makes the hook exit 1 with sparse-checkout advice. `--assume-unchanged` gives rc 0, but the TRACKED regenerated index is silently not staged. Both behave the same under origin/main's plain `git add` and under the first A0 hook, so this is not a regression of the delta. No repo doc recommends either flag. Tested on git 2.43 only.
- **verification:** `sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/q1.sh | grep -E 'skip_worktree|assume_unchanged'`
- **suggested-fix:** None required; list it under Residuals.
- **status:** documented - no code change. Listed in the diagnose doc's Residuals with both behaviours, the statement that origin/main and the first A0 hook behave identically, and the git version it was measured on. The reviewer's other unmeasured states (intent-to-add, unmerged) are listed there too: they delegate to real git, so their behaviour on 2.55 is unverified.

### Finding 6 - P3 - guard_without_its_mirror (pre-existing, same test file)
- **file:line:** scripts/pre-commit.sh:190; test header :32
- **claim:** `exit 1` -> `:` at the diagnose-builder failure survived 11/11 (case 3 covered only the OI builder). No fixture had a tracked index whose rebuilt content equals the committed one, the commonest real case: rc 0 on 2.43 and unverified on 2.55. The `expectNoGitNoise` strings are English-only (not reproducible here: no git translations installed).
- **verification:** `sh /tmp/claude-1001/-home-ubuntu-projects-avya/2215b5ae-c31c-413d-bc3b-b65f5fb4e3a8/scratchpad/bpass_a0_fix/q4sd.sh` prints rc=1 for the original and rc=0 for the mutant
- **suggested-fix:** One case with an unparseable diagnose doc and one with identical rebuilt content.
- **status:** fixed - case 3b (twice: tracked and ignored index) with a `breakBugBuilder` fixture pins the diagnose-builder failure as fatal; cases 7a/7b pin a tracked index whose rebuilt content is unchanged (exit 0, nothing staged for it); the hook now runs under `LC_ALL=C` so the noise assertions do not depend on a localised git. Author mutant SD (`exit 1` -> `:`) reddens both 3b cases.

## Q1..Q6 answers (the six questions of the brief)

**Q1 - is the guard right for every index state?** Yes, in every state the reviewer built (listed above). Exceptions are Finding 5. Intent-to-add, skip-worktree and unmerged states delegate to real git, so their 2.55 behaviour is unverified.

**Q2 - does the `if <cmd>; then git add ...; fi` form keep the add fatal and the condition non-fatal?** Yes under dash, bash and bash --posix; with a held `.git/index.lock` the add stays fatal at rc 128. The condition maps every `ls-files` failure (rc 128 as well as rc 1) to "untracked", which fails open; that is practically unreachable because the trigger `git diff --cached | grep -q` already fails open on an unreadable index.

**Q3 - stub fidelity.** The CI log (lines 4698-4790) shows git 2.55.0 and hook exit 128 with exactly one stderr line, `error: pathspec 'docs/audit/OPEN_INDEX.md' did not match any file(s) known to git`; cases 1a/1b passed there. The stub reproduces that message and exit code and execs real git for everything else. It cannot say what 2.55 does for intent-to-add, skip-worktree, unmerged or unchanged tracked paths (Finding 3 covers the proof gap).

**Q4 - mutants that survived.** SA (`|| true`), SB (HEAD-keyed guard), SC (ignore-keyed guard) and, pre-existing, SD (Findings 1, 2, 6). All proved on script copies with stub executables, none with `flutter test`.

**Q5 - doc claims against the code.** 11 cases, 16 mutants (14 red, 2 equivalent), line numbers 196/216 for the guards and 197/217 for the adds, and the shard-2 failures being exactly 2a and 2b all checked out. The "38 installer cases" claim and the version wording did not (Finding 4).

**Q6 - other `git add` lines.** None would fail today: all six regenerated indexes are tracked and none is ignored; `git grep` over `scripts/`, `.claude/` and `.github/` finds no other `git add -u`. After the next landing untracks the two indexes only printed hints go wrong: `scripts/check_diagnose_index_fresh.dart:75` and `scripts/pre-merge-commit.sh:183` tell the user to `git add` an ignored path, which exits 1. Recorded in the diagnose doc's Residuals as hints for A2.

## Checked and clean

- Syntax: `sh -n` is ok in dash, bash --posix and busybox.
- No non-ASCII added; `git diff --cached --check` is clean.
- The reviewer's worktree was byte-identical afterwards (0 unstaged changes, 0 untracked files, the primary repo clean).

## Author follow-up after the findings

- **Tests:** `test/scripts/pre_commit_index_add_e2e_test.dart` went from 11 to 20 cases (0, 1a, 1b, 2a, 2b, 3 x2, 3b x2, 4a-4d, 5a, 5b, 5c, 6a, 6b, 7a, 7b); all pass. The twelve test files that reference the hook or the touched docs by name (`scripts/pre-commit.sh`, `bug-classes.md`) pass together: 182 tests.
- **Mutation proof (rule 21), round 2:** 26 mutants - M01-M16 (the round-1 set, re-run against the 20-case file), SA1/SA2, SB1/SB2, SC1/SC2, SD, T1, S1, S2. Each was applied with an anchor counted exactly once, confirmed changed, run against the one test file, and restored; the sha256 of the hook and of the test file were equal before and after, and `git diff` hashed equal before and after. Every mutant reddened at least one case. M13/M14 (`git add --`, without `-u`) are behaviourally equivalent to the original in every index state (reviewer's replicas); they redden (4 cases each) only through the stub's refusal of an `add` spelling it does not model.
- **Gate loop on the final staged tree:** `sh scripts/pre-commit.sh` rc 0 with the staged-diff hash unchanged (163a8b689cb3). The earlier complete loop ran on the first fix state: `flutter analyze lib/` 0 warnings and 0 errors, full suite 10643 passed (`TZ=Asia/Kolkata`); the only change to `scripts/pre-commit.sh` since then is two comment lines. The full suite on the final tree is CI's job on the PR (CLAUDE.md section 4.3 forbids a manual full re-run).
