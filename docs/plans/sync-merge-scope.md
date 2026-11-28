---
plan: sync-merge-scope
revision: 4
date: 2026-10-25
base: d1292a79
blast_radius: platform
tier: M
execution_mode: inline   # one worktree, one session
parent_plan: docs/plans/merge-conflict-treadmill.md (section 7, landing C, unit U3)
closes_oi: [OI-413]      # OI-309 stays open for C2 (the resolver) and D; OI-337 stays OPEN and is amended (D6)
landings: [C1]
---

# Landing C1: a branch sync is graded by what the merge adds beyond main (U3)

Landing C of the parent plan is split in two, as A was: **C1 (this plan)** is U3, the catastrophic review gate's
input on one narrow merge shape; **C2** is U5, the record-aware resolver `scripts/sync_with_main.sh`. They share no
file. C1 has standalone value (it removes the forced merge-only reviews), so it ships first.

## Revision history
- **rev 3 -> rev 4 (delta round on rev 3, two seats; seat A CONVERGED on the rule, seat B HARDEN on the test plan only: 1 P1, 10 P2,
  no design defect; every item folded in):**
  - Gate-level coverage of the fail-closed path (seat B, P1): G11-G14 and G1b added; every test that expects `Fallback` asserts the
    exact reason, and a shared helper fails any scenario that returns `Fallback('internal error')` by accident (the lib's catch-all
    would otherwise hide a throwing mutant).
  - Sets are intersected as BYTE strings and only the survivors are decoded (seats A, B): an undecodable name outside the commit no
    longer disables scoping, and the order-dependent two-pointer merge (UTF-8 byte order is not UTF-16 order) is gone.
  - S18-S20 added (old MERGE_HEAD with the human restoring the tip's version; an mtime rewrite that kills a dropped `--cached`; a
    hostile repo-local config), S16b, oracle 3 (exact equality with an independent reimplementation), full-set assertions for S6 and
    S10; the mutation table is expanded to one mutant per row with corrected killers; the argv lives in two exported constants.
  - D4 lists the flows where scoping is unavailable; D5 lists the two losses reviewers named; the NOTE prints the short tip and
    MERGE_HEAD ids; `escapeForNote` covers C1, U+2028/2029 and the bidi overrides and escapes the backslash; consistency fixes.
- **rev 2 -> rev 3 (round 2, two seats, both HARDEN, no P0/P1; every finding mechanical except the first):**
  - **The rule compares against the TIP of `origin/main`, not against MERGE_HEAD** (seat A, P2). The rev-2 spine test accepted
    fast-forwarded and rebase-merged interior commits and the head of a PR that main later reverted. A path is now exempt when its
    index entry equals HEAD's (nothing new) or equals what `origin/main` holds at that path today (already on main); an old,
    interior or reverted MERGE_HEAD can no longer exempt anything main does not hold now. The spine call is gone; MERGE_HEAD only
    has to be an ancestor of the tip (so a merge of another feature branch keeps today's rule). For a sync of the tip, the verdict
    table is unchanged.
  - **The staged list and the scope list are cross-checked** (seat A, P2): the gate's staged list must equal the `diff-index` list
    against HEAD, otherwise the scope is refused; this turns "neither is a subset of the staged diff" from a claim into a runtime
    check and removes the fail-open `Scoped(empty)` shape (intent-to-add, `diff.relative`, an environment mismatch).
  - `dotAll: true` for the glob engine of this gate (seat A, P2: a path with a line terminator matched no catastrophic glob; the
    keystone already has it). The test oracle gains the new-bytes check (seat A, P2). `--` after every revision argument (seats A, B).
  - Test and mutation table rebuilt row by row (seat B, P2 x5): `--no-renames` is inert on `diff-index`, so it is dropped from the lib
    and kept on the porcelain staged reader; the gitlink case is buildable with plumbing; the exception-to-fallback conversion lives
    inside the lib so a unit test can kill its removal; false killers corrected; mutants added for the literal `.git/MERGE_HEAD`
    read (a linked worktree), null runner results, ignored exit codes, hex-validation shapes, other ref names, the loop variable and
    NOTE silence; G8 is a pending merge in a linked worktree; the S13 fuzz is chunked with a file-level timeout and Windows guards.
  - Registry and process lines added (seat B, P3): `GATE_INDEX.md`, the diagnose `sot_registry_entry`, the one parser shared by the
    gate and the lib, the amended failure message, NOTE escaping, the front matter wording.
- **rev 1 -> rev 2 (round 1, three seats, all HARDEN):** the name-keyed `remerge UNION overlap` rule missed content that git
  relocates by rename (seat A P0, seat B P1) and was replaced by an entry comparison; `git write-tree` (takes `index.lock`) and
  `git merge-tree` (git 2.38) were dropped; `-s ours` corrected; OI-413 and the rejected unconditional stand-down cited; the
  existing fixtures re-pointed; OI-337 decided; naming, registry and feature-flag points added.

## 1. What goes wrong today

A branch that is behind `origin/main` is synced with `git merge origin/main`. A clean automatic merge committed by git itself
runs only the `pre-merge-commit` hook (a clean `git merge --no-commit` concluded with `git merge --continue` runs `pre-commit`).
A merge with a conflict is concluded by `git commit`, which runs `pre-commit`, and `scripts/check_code_review_pass_exists.dart`
classifies `git diff --cached --name-only`, which at that moment is EVERYTHING main brought in (index vs the branch tip), not what
the human changed. If main gained a catastrophic path (an Edge Function for payments, a `SECURITY DEFINER` migration, anything the
registry grades catastrophic) since the branch base, the gate demands `docs/reviews/<hash>-review.md` for a diff that was already
on main. A new review would be a fabricated attestation; the working answer so far is to rebuild the branch's own commit on top of
`origin/main` by hand. Five recorded trips (four in memory `reference_merge_commit_trips_catastrophic_review_gate_2026_10_12.md`, and
the B2 branch of 2026-10-25, OI-413) and one rebuild that turned out not to be needed; the parent plan counts 7 forced merge-only
review entries and 3 rebuilds.

**Measured (2026-10-25, method in section 7).** Main-sync merges inside PR branches reachable from `origin/main`, graded with the
current registry and the current `SECURITY DEFINER` content rule. The "rule" rows use the main side of the merge at sync time as the
tip, which is the tip for a current sync (a stale tip only grades more paths: with the tip five commits ahead the mean graded paths
rise from 5.2 to 24.4 and 1 of 5 measured syncs grades a catastrophic path). Four independent re-runs agree:

| Population | Input | feature | account | platform | catastrophic | avg paths |
|---|---|---|---|---|---|---|
| 46 syncs with a "Merge branch 'main'" subject | full staged diff (today) | 11 | 3 | 24 | **8** | 38.0 |
| | entry differs from HEAD and from the main side | 33 | 1 | 12 | **0** | 5.3 |
| 124 syncs (every merge inside a PR whose second parent is a main state) | full staged diff | 24 | 17 | 60 | **23** | 45.1 |
| | the rule | 95 | 7 | 22 | **0** | 5.2 |

Every catastrophic full diff has no catastrophic path under the rule, and no sync in either population does.

## 2. Writers and readers (section 4.1)

| Artifact | Writer | Reader |
|---|---|---|
| the staged path list | git (the index of the commit in progress) | `check_code_review_pass_exists.dart` `stagedPaths()` (:103) then the loop at :207 |
| the review file name | the author; named for `stagedDiffHash()` (:113) | the same gate, `$_reviewsDir/$hash-review.md` (:249, existence :250) |
| the registry tier rules | `docs/blast_radius.yaml` | `parseRules` (:28-45) and `globToRegExp` (:47-72) in this gate, `blast_radius_from_diff.dart` and `check_plan_review_record_exists.dart` (three copies of the glob engine by design, test `blast_radius_content_rule_wired_all_scripts_test.dart`) |

This landing changes the READER side of the first and third rows. The hash and the review file path do not change.

## 3. Decisions

- **D1. The graded set for a branch sync** is
  `graded = { staged paths p : index[p] differs from HEAD[p] AND index[p] differs from TIP[p] }`, where `TIP` is the commit that
  `refs/remotes/origin/main` names, "differs" is the git tree comparison (mode, object id, or present-versus-absent), and the set is
  the intersection of `git diff-index --cached --name-only -z --ignore-submodules=none HEAD --` and the same call with the TIP object
  name. `git diff-index` is plumbing: no rename detection unless `-M` is given, no `diff.*` porcelain configuration, no `index.lock`.
  - Why this is complete: every path of the commit is in one of three cases. Its entry equals HEAD's: nothing new reaches the
    branch (and the path is not in the staged diff). It equals what `origin/main` holds at that path today: already on main (D5). It
    equals neither: git or the human produced something no reviewed state holds at that path, so the gate grades the path. Because
    the comparison is on ENTRIES at the committed path, it does not matter how git got there (rename, directory rename, add/add,
    conflict resolution, a clean combination of two edits), and a MERGE_HEAD that is old, interior to a PR, or the head of a PR
    main later reverted exempts nothing main does not hold now.
  - `graded` is intersected with the gate's staged list in code, and the two reads must agree (D2.5).
- **D2. Conditions** (any failure falls back to today's behavior, the full staged list, and says why when a merge is in progress; fail
  closed; the lib never throws, an exception becomes `Fallback('internal error')`). The probe order is cheapest first:
  1. `git rev-parse --git-path MERGE_HEAD` (one spawn, so an ordinary commit costs one spawn and one file read) gives a path.
     The injected reader returns null for an ABSENT file (not a merge: `NotAMerge`, no NOTE) and throws for an unreadable one
     (`Fallback('MERGE_HEAD unreadable')`). The file must hold exactly one non-empty line that is a full hex object name of 40 or 64
     lowercase digits (an octopus merge has several lines);
  2. `git rev-parse --verify --quiet refs/remotes/origin/main^{commit}` (the FULL ref name, so a local branch or tag called
     `origin/main` cannot shadow it) gives the TIP; the output must be a full hex object name;
  3. `git merge-base --is-ancestor <MERGE_HEAD> <TIP>` exits 0: the merge is a sync of main. A merge of another feature branch, or a
     shallow history where the answer is unavailable, keeps today's rule;
  4. both `git diff-index` calls exit 0 and their output is strict UTF-8 (a path that is not valid UTF-8 returns "git could not
     answer"; Windows would otherwise decode it leniently);
  5. the set of paths of the `HEAD` call equals the set of the gate's staged list (the same read, the porcelain `git diff --cached
     --no-renames --ignore-submodules=none --name-only -z`); otherwise `Fallback('index reads disagree')` (intent-to-add entries,
     `diff.relative`, a different environment).
- **D3. Unchanged:** the hash (of the full staged diff), the review path, the verdict check, `--warn-only` and its four existing exit
  sites, the `SECURITY DEFINER` content rule (it reads the STAGED blob of each graded path), and the "no staged changes" skip, which is
  decided on the full staged list first. An empty graded set is tier `feature` and passes. When the scoped gate does demand a review,
  the file is still named for the hash of the full staged diff and the reviewer scopes the review to the graded paths (the NOTE lists
  them).
- **D4. Non-goals, stated:** the advisory `NOTE: blast-radius=` line of `pre-commit.sh`, the `Blast-radius:` line that
  `prepare-commit-msg.sh` writes and the pre-push / `safe_merge.sh` classification keep reading the full staged diff or the branch
  range (none of them blocks, or they read `merge-base..branch`, not the merge). The CI plan review record gate is not changed: it
  judges the PR's landing against the range base and stays the server-side check. A merge that is not a sync of main keeps today's
  full-diff rule. `-s ours` leaves the index equal to HEAD, so the staged diff is empty and the gate skips, exactly as today. A
  cherry-pick or revert has no MERGE_HEAD and is unchanged (the reason the earlier unconditional stand-down in OI-413 was rejected,
  `docs/plan-reviews/review-gate-tier-gap.md`: single-parent commits skip the CI keystone, so they must keep the commit-time review).
  A clean automatic merge never reaches this gate (only `pre-merge-commit` runs, `scripts/pre-merge-commit.sh:14-21`). Scoping is
  also unavailable, and the old rule applies, when local `main` is ahead of `origin/main` and is the merged side (the CLAUDE.md
  section 4.13.1 "merged-but-unpushed" base is not an ancestor of the tip), when the remote is not called `origin` or the clone is
  single-branch (no `refs/remotes/origin/main`), and on a shallow history whose boundary hides the answer. Because the tip is re-read
  at every attempt, the same index can pass once and demand a review after `origin/main` moves; the NOTE prints the short tip and
  MERGE_HEAD ids so the reason is readable, and `docs/architecture/hooks.md` says to merge the current tip.
- **D5. Trust argument and the list of what changes.** The rule trusts exactly one thing: what `refs/remotes/origin/main` holds at a
  path is content that landed on main (through `safe_pr_merge.sh` and the CI record gate; `main` has no required status checks,
  CLAUDE.md section 4.3, so content that bypassed those gates on main is not seen again by this gate: the CI keystone on main's own
  pushes is the remaining check for it). It
  removes no protection from the branch's own content (it is already in `HEAD`). It does not trust the human, git or MERGE_HEAD:
  every path whose final entry matches neither HEAD nor main's current entry is graded. What the old rule caught and the new one
  does not, with the judgement for each:
  1. main-only edits, adds and deletes in catastrophic paths, as main holds them now (the intent);
  2. paths relocated by rename, directory rename, rename/rename or directory-versus-file conflicts: covered, the destination entry
     matches neither unless it is main's own; the mirror case, content relocated OUT of a catastrophic path by the branch's rename,
     is graded by its new NAME (feature), exactly as the old gate graded it: the grading is by path name (residual);
  3. an interior commit, a stale commit or the head of a reverted PR as MERGE_HEAD: covered, anything main does not hold now is graded;
  4. main content whose path became catastrophic only after it landed, or that landed before the `SECURITY DEFINER` content rule
     existed: accepted (it was graded by the rules of its day);
  5. a cross-file combination, for example catastrophic X from main plus the branch's Y that X depends on: accepted (the old gate
     forced a review of the whole combined diff; CI and the plan record judge the combination now);
  6. a human who takes main's whole version of a catastrophic file over the branch's own reviewed edit drops that work without
     any prompt (no unreviewed bytes get in, but the old rule graded the path and so surfaced the choice);
  7. main content that bypassed the record gate (a force-push, a direct push) was re-graded incidentally at the next sync by the old
     rule; the new rule trusts it, and detection moves to main's own CI keystone (`check_plan_review_record_exists.dart:505-523`).
  Out of scope: someone who rewrites their own `refs/remotes/origin/main`; that person can use `--no-verify` as well, which needs
  the founder's approval (CLAUDE.md section 4.3), and CI still enforces the record at the merge to main.
- **D6. OI-337 for this gate.** `stagedPaths()` reads `git diff --cached --name-only` without `-z`, `--no-renames` or
  `--ignore-submodules=none` and decodes leniently: a rename out of a catastrophic path is graded by its destination, a non-ASCII
  name by its C-quoted form, a gitlink hidden by `diff.ignoreSubmodules=all` or `.gitmodules ignore = all` is skipped, and a path
  with a line terminator escapes every glob (`.` does not match it; the keystone has `dotAll: true`, this gate does not). The graded
  list is read the hardened way, so the staged list must not be weaker. This landing changes `stagedPaths()` to
  `git diff --cached --no-renames --ignore-submodules=none --name-only -z` (porcelain, so it also works with an unborn HEAD),
  parsed by the lib's one `parseNulPaths` (NUL split, no trimming, strict UTF-8, null on a malformed path, which the existing null
  branch turns into a FAIL; the failure message stops naming the old command), and adds `dotAll: true` to this gate's
  `globToRegExp`. `blast_radius_from_diff.dart` (the advisory trailer and the pre-push suite choice; its `stagedPaths()` also fails
  open, returning an empty list on a git error, and its glob engine has no `dotAll`; about 28 tracked files outside docs mention it) keeps its reader; OI-337 is
  AMENDED on the board to name that single remaining script, the new shared `parseNulPaths` it can adopt, the fail-open and the
  missing `dotAll`. The stale comment at `test/contracts/blast_radius_data_deleting_paths_catastrophic_test.dart:34-39` ("the
  difference is theoretical today") is updated in this landing.
- **D7. No runtime switch.** The platform tier lists `feature_flag` among its `requires` and CLAUDE.md section 4.6 asks for a gate
  for payment, sync (the Hive-to-cloud direction), auth, AI prompt and plan generator changes; this is none of those, and a runtime
  switch that turns a blocking security gate off is itself a bypass. The old behavior is preserved verbatim as the fallback on every
  failed condition; rollback is a revert of the landing.

## 4. Design

- **New lib `scripts/merge_scope_lib.dart`** (the word "sync" is a reserved glossary term for the Hive-to-cloud direction, so the code
  says "merge scope"; the glossary gains "branch sync" with a pointer to the `sync` row). Pure parts: `parseNulPaths`
  (strict UTF-8 for the gate's staged list), `splitNulBytes` (raw NUL split into latin1 "byte strings"), `isFullHexObjectName`
  (anchored, 40 or 64 lowercase hex), `escapeForNote` (C0, DEL, C1, U+2028, U+2029, U+202A-U+202E and the backslash become `\xNN` or
  `\uNNNN` forms), `formatScopeNote` (the NOTE text, so a unit test reaches it), the two argv builders `diffIndexArgv(String
  treeish)` and the constant `stagedPathsArgv` (the gate, the S/G helpers and the argv pins all use them, so a test cannot drift from
  the gate), and `computeMergeScope`. The sets are compared as byte strings (a `Set` intersection, sorted for display only: git
  orders names by UTF-8 bytes and Dart's `String.compareTo` by UTF-16 code units); only the graded survivors are decoded, strictly, so
  an undecodable name outside the commit cannot disable scoping. `typedef GitRun = ({int exitCode, List<int> stdout})? Function(List<String> args)` (null: the process could not
  run) and a REQUIRED `String? Function(String path) readMergeHead` (null: absent; throws: unreadable). The lib imports only
  `dart:convert`. Result type: `NotAMerge`, `Scoped(paths, counts)`, `Fallback(reason)`. `computeMergeScope(git, readMergeHead,
  staged)` stops at the first failed condition, issues no further git call, and wraps its whole body in try/catch.
- **Gate wiring (`check_code_review_pass_exists.dart`):** the production runner spawns `git` with the gate's own environment (the
  hook's `GIT_INDEX_FILE` and, in a linked worktree, `GIT_DIR` are wanted) and `stdoutEncoding: null`; the production
  `readMergeHead` reads the path with a try/catch that maps "file not found" to null and rethrows anything else (a `File(...).existsSync()`
  line would need the `// file-only:` marker of `check_gate_existssync_file_vs_dir.dart`). In `main`, after `stagedPaths()` succeeds and is
  non-empty, the scope call runs and the loop at :207 iterates the graded list or the staged list. NOTE lines are printed only when a
  merge is in progress: scoped (`branch sync of origin/main (tip <short>, MERGE_HEAD <short>): grading N path(s) whose entry matches neither HEAD nor
  origin/main, of S staged: <escaped list>`) or fallback (`branch-sync scoping not applied (<reason>): grading all S staged path(s)`). Unresolved
  conflicts (a manual re-run mid-merge) show their paths in both lists and are graded; the NOTE says "unmerged paths are graded". The new
  import line shifts `parseRules` by one line; the SoT reader `line_range` is recomputed from the anchor after the last edit.
- **Visibility.** `pre-commit.sh:392` runs every gate with `>/dev/null 2>&1` and prints only `GATE FAIL: <name> - re-run for details`,
  so the NOTE is for the manual re-run (`dart run scripts/check_code_review_pass_exists.dart` while the merge is pending) and for the
  tests; `docs/architecture/hooks.md` says so, and says the advisory `NOTE: blast-radius=` line can still read catastrophic after a
  scoped pass.
- **Registry and docs:** `docs/blast_radius.yaml` gains `scripts/merge_scope_lib.dart` as platform above `scripts/**` (first match
  wins), beside the gate's own entry in the same commit (the registry rot test lists every exact-path rule); the new tests stay
  `feature` under `test/**`. `docs/architecture/hooks.md` gets a row for the gate; `.claude/skills/code-review/SKILL.md` section 0
  gets the branch-sync qualifier; the parent plan section 7 records the C1/C2 split; `docs/naming_conventions.md` gains "branch sync",
  "merge scope" and "graded set"; the SoT concept `blast_radius_registry_coverage` gains `behavioral_test_path_merge_scope` (and the
  diagnose doc names that concept in `sot_registry_entry`); the gate moves from `grandfathered` to `mutation_proven` in
  `docs/audit/gate_test_ledger.yaml` (precedent `check_ai_tool_dispatcher_coverage.dart`), which regenerates the tracked
  `docs/audit/GATE_INDEX.md` row in pre-commit; OI-413 is archived to `closed_issues.md` with a CLOSED paragraph that says how this
  design differs from the rejected unconditional stand-down; OI-337 and OI-309 are amended; memory
  `reference_merge_commit_trips_catastrophic_review_gate_2026_10_12.md` is rewritten when the landing merges. A debugging-skill bug
  class is added for the "gate grades the whole incoming diff at a merge" family if no existing class covers it (five trips; id from
  `check_bug_class_numbers_unique.dart --next`). No new `Platform.environment` read.

## 5. Tests

Fixture rules for every new test file: file-level `@Timeout` and `library;`, no per-test `timeout:` override, no `Platform.environment`
read in the test (the spawn env manifest scans tests too); `runSpawn` with the hermetic environment; EVERY git command, setup and code
under test, runs with `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL` pointing at an empty file (through `allowControl`) so a developer's
global `diff.*`, `merge.*`, `core.autocrlf`, `core.hooksPath` or `init.templateDir` cannot reach a fixture or mask a mutant; setup commands
carry their own `-c` pins (`commit.gpgsign=false`, `merge.directoryRenames=conflict`), a repo-local `user.*` and `diff.renames=true`; a
two-parent merge is made with `merge --no-commit --no-ff` (a branch that is an ancestor would fast-forward) and `-s ort`, an octopus with
git's default strategy (ort handles two heads only); every scenario asserts the intended index shape before its verdict, by
`ls-files -s` stage numbers for the named paths, never by porcelain status letters (git-version fragile); modes and symlinks are made
with `update-index --cacheinfo`, and a gitlink is built with `update-index` + `write-tree` + `commit-tree` only (`git add -A` would
stage its deletion). Every test that expects `Fallback` asserts the EXACT reason string, and a shared helper fails any scenario that
returns `Fallback('internal error')` unless that is the scenario's point (the lib's catch-all would otherwise turn a throwing mutant
into a passing test; the diagnose doc records which mutants were first caught only after the helper existed).

1. **`test/scripts/merge_scope_lib_test.dart`** (fake runner, no process): the happy path; NUL splitting with a LEADING and a TRAILING
   space, an embedded newline, a name starting with U+FEFF and a final empty element; the byte-string intersection with the pair `docs/～.md`
   and `docs/<U+10000>.md` (UTF-8 order differs from UTF-16 order) and an undecodable name present only in the TIP diff (still `Scoped`);
   strict UTF-8 on the survivors (an undecodable graded name gives `Fallback` with its reason); every D2 condition returns `Fallback` with
   its own reason; a 64-digit name accepted, 41 and 39 digits, uppercase, a leading `-`, trailing junk rejected, for MERGE_HEAD AND for the
   TIP output (a runner answering `--foo` gives `Fallback` and no further call); a runner returning null for each call; a non-zero exit of
   each call; a throwing `readMergeHead` (`Fallback('MERGE_HEAD unreadable')`) and a throwing runner (`Fallback('internal error')`);
   absent file gives `NotAMerge` after exactly ONE call; the equality check in both directions and with an empty HEAD diff and a
   non-empty staged list, before and not after the intersection; the TIP resolved once and passed as hex (a stateful fake whose second
   `rev-parse` answer differs); the sequence and argv of every call are `diffIndexArgv`/`stagedPathsArgv` plus the `rev-parse`,
   `merge-base` arguments of D2, pinned as presence only; an empty graded set is `Scoped` with no paths; `escapeForNote` and
   `formatScopeNote` for backslash, DEL, C0, C1, U+2028, U+2029, U+202E and the literal text `\x0a` (inputs built with
   `String.fromCharCode`).
2. **`test/scripts/merge_scope_git_test.dart` and `test/scripts/merge_scope_git_fuzz_test.dart`** (the same lib against REAL git in temp
   repos; the result is the returned set, asserted as full-set equality). S1 a conflicted docs file resolved by hand while main brought
   a catastrophic-path file and a `SECURITY DEFINER` migration: graded = {the docs file}; S2 the human edits main's catastrophic file:
   graded; S3 both sides edit different regions of one catastrophic file and git merges it cleanly (`--no-commit`): graded; S4 the human
   takes main's whole version of a conflicted file with `git checkout <TIP> -- path`: not graded, and `-X theirs` on a file the branch
   also edited elsewhere: graded (it matches neither); S5 the human restores HEAD's version of a file main changed: not graded, and the
   set is a subset of staged; S6 main renames a catastrophic file, the branch edited the old path: graded = {the NEW path} exactly (main's
   deleted old path is not graded); S7 the branch renames into a catastrophic directory and main edits the old path: graded; S8 main
   renames a directory into a catastrophic one and the branch added a file under the old directory, accepted unchanged (setup guard: the
   stage-2 entry): graded; S9 rename/rename and file-versus-directory conflicts: every path matching neither is graded; S10 MERGE_HEAD is
   an INTERIOR commit of a `--no-ff` PR that adds a catastrophic file a later commit removes, a fast-forwarded interior commit and the
   head of a PR that main reverted: those paths are graded; a PR head and a main tip whose content main still holds: graded = {}; S11 a
   tag `origin/main`, a branch `refs/heads/origin/main` and a local `main`, each pointing at a different commit, do not shadow the ref;
   S12 no `origin/main` ref, an octopus merge, a MERGE_HEAD that is not an ancestor of the tip, a shallow cut (expect the reason "not an
   ancestor"): `Fallback`; S13 the chunked seeded fuzz (edit, delete, rename, rename+edit, add, mode change, symlink, directory rename on
   both sides, random resolution, `-X ours/theirs`; each chunk names its seed) with three oracles: every staged path outside the set has
   an entry equal to HEAD's or the tip's at that path; every index blob whose object id exists at no path of HEAD's or the tip's tree is
   in the set (the new-bytes oracle that catches a rename-aware rule); and the set EQUALS an independent reimplementation from
   `ls-files -s` and `ls-tree -r` (the over-grading oracle); S14 a gitlink moved under `.gitmodules ignore = all` is graded; S15 a
   conflict-resolved `docs/résumé.md` is graded by its real name and an emoji-named file is graded; S16 a file named `HEAD` in the worktree
   root still returns `Scoped`, and S16b the same with a root file named by the TIP hex and by the MERGE_HEAD hex; S17 an intent-to-add
   entry gives `Fallback('index reads disagree')`; S18 MERGE_HEAD is an old main commit, main has changed a catastrophic file since, and the
   human runs `git checkout <TIP> -- file`: graded = {} (the direction revision 3 added); S19 the mtime of a main-brought file is rewritten
   after the merge: not graded (kills a dropped `--cached` on the TIP call); S20 a hostile repo-local config (`diff.orderFile`,
   `diff.ignoreSubmodules=all`): still `Scoped` with the same set (set equality, not list equality).
3. **`test/contracts/merge_scope_gate_e2e_test.dart`** (the REAL gate spawned in a temp repo; the closure copied with
   `copyScriptClosure`, plus `docs/blast_radius.yaml`; `dartBin()`). Scoped: G1 a sync that brought a `SECURITY DEFINER` migration and a
   catastrophic-path file, human-resolved docs conflict: exit 0 and the scoped NOTE with the exact N; G1b a clean `--no-commit` merge that
   brought catastrophic files and was not touched: exit 0 and "grading 0 path(s)"; G2 the control: MERGE_HEAD is an OLD main commit whose
   catastrophic file main has changed since, so the result holds a version main no longer holds: exit 1 with "requires a STAGED review
   file"; G3 the human edits a catastrophic file: exit 1; G3b the same with an accepted review named for the hash of the FULL staged diff and
   at least one staged non-graded path: exit 0; G4 the human adds `SECURITY DEFINER` content to a migration with
   an innocuous name: exit 1; G5 `--warn-only` on G3: exit 0; G6 `-s ours`: exit 0, "SKIP: no staged changes" and NO branch-sync NOTE; G8
   a pending merge in a LINKED worktree with `GIT_DIR` and an absolute `GIT_INDEX_FILE` exported as a hook sees them: the exact scoped
   NOTE and no "scoping not applied" line, and in the primary worktree with the relative `GIT_INDEX_FILE=.git/index`; an alternate
   `GIT_INDEX_FILE` whose graded result differs from the default index's follows the alternate; G14 an unresolved conflict in a catastrophic
   file is graded and the NOTE says "unmerged paths are graded". Fail closed: G11 a pending merge of ANOTHER feature branch that carries a
   catastrophic path: exit 1, the NOTE "branch-sync scoping not applied (<exact reason>): grading all S staged path(s)" and no "branch
   sync of origin/main: grading" line; G12 no `origin/main` ref; G13 an unreadable MERGE_HEAD (a directory): `MERGE_HEAD unreadable`.
   Not merges: G7 a non-merge commit staging a rename out of a catastrophic directory, a non-ASCII name and a name with a line
   terminator under a catastrophic glob, each exit 1; a name that is not valid UTF-8 (built with `commitFileNamed(..., rawNames: true)`)
   as the ONLY staged path under a feature-tier directory: exit 1, the new "not valid UTF-8" stderr text and no "requires a STAGED review
   file" (a second case under a catastrophic directory); G9 a staged gitlink under a catastrophic glob with `.gitmodules ignore = all`
   demands the review; G10 an ordinary commit prints no branch-sync NOTE.
4. **Updated, not new:** `test/contracts/review_gate_staged_content_not_working_tree_test.dart` copies a literal two-file closure at
   `:255-258` and `:419-422`; both loops become `copyScriptClosure(..., ['scripts/check_code_review_pass_exists.dart'])`; its assertions
   stay unchanged and green (9 tests spawn the gate). `blast_radius_content_rule_wired_all_scripts_test.dart` gains the lib in
   `enforcementPaths`; the stale comment in `blast_radius_data_deleting_paths_catastrophic_test.dart:34-39` is rewritten; the new e2e
   file is added to the guarded list of `subprocess_test_timeouts_declared_test.dart` if that test pins its membership.
5. **Mutation proof (rule 21)** - one mutant per row, each applied with an exact-one-match assertion before the write (a sentinel line
   for the structural ones), the new test files and the updated fixture file run, the source restored and byte-compared; the number of
   red tests is recorded and a compile error is kept apart from red. The `*` marks a row that needs a helper or sentinel edit.

| # | Mutant | Killer |
|---|---|---|
| 1 | graded = UNION of the two diffs * | S4 (restore a file), S18, lib intersection test |
| 2a | graded = the HEAD diff only | S4 (a file taken from main is wrongly graded), S18 |
| 2b | graded = the TIP diff without intersecting the HEAD diff | S1, S5 (the branch's own file appears) |
| 3 | exemption compares MERGE_HEAD instead of the tip | S10, S18, G2 |
| 4a | lib `diff-index` calls without `-z` | lib newline test, S15 |
| 4b | `stagedPaths()` without `-z` | G7 non-ASCII and line-terminator names |
| 5a | lib calls without `--ignore-submodules=none` | S14 |
| 5b | `stagedPaths()` without `--ignore-submodules=none` | G9 |
| 6a | tolerant UTF-8 decode of the survivors | lib invalid-byte test |
| 6b | tolerant decode in `parseNulPaths` for the staged list | G7 raw name under a feature-tier directory |
| 6c | `parseNulPaths` returns [] or skips the malformed entry | G7 raw name as the only staged path |
| 7a | trim a path | lib leading/trailing-space test |
| 7b | keep the final empty element | lib exact-list test, G6 |
| 8a | short ref `origin/main` | S11 tag variant |
| 8b | `refs/heads/main` / `refs/heads/origin/main` | S11 branch variants, S12 |
| 9a | drop `--` on the HEAD `diff-index` call | S16 |
| 9b | drop `--` on the TIP `diff-index` call | S16b |
| 10 | ancestor test operands swapped | S12 (MERGE_HEAD beyond the tip), S10/S18 (old main commit) |
| 11 | drop the ancestor condition | S12 (another branch), G11 |
| 12a | drop the octopus condition (several lines) | S12, lib two-line file |
| 12b | hex check unanchored, `{40,64}`, 41/39 digits, uppercase, a leading `-` | lib hex tests |
| 12c | hex check skipped for the TIP output or MERGE_HEAD content (the validator still exists) | lib `--foo`/`-x` tests |
| 13 | MERGE_HEAD read from the literal `.git/MERGE_HEAD` | G8 (linked worktree) |
| 14a | a null runner result read as empty stdout | lib null-runner tests |
| 14b | a non-zero exit ignored | lib non-zero tests |
| 15a | `Fallback` returned as an empty list inside the lib | lib, S12 |
| 15b | the gate treats `Fallback` as an empty graded list * | G11, G12, G13 |
| 15c | the gate crashes or prints no NOTE on `Fallback` | G11, G12, G13 |
| 16 | no try/catch in `computeMergeScope` | lib throwing runner (reason 'internal error' asserted) |
| 17a | staged list not cross-checked | S17, lib mismatch tests |
| 17b | equality one-directional, list instead of set, or after the intersection | lib both-direction tests, S20 |
| 18 | the gate hashes the graded paths * | G3b |
| 19 | skip the content rule in scoped mode | G4 |
| 20 | the loop at :207 iterates the staged list | G1 |
| 21 | `stagedPaths()` without `--no-renames` | G7 rename |
| 22 | `globToRegExp` without `dotAll` | G7 line-terminator name |
| 23a | Scoped NOTE missing | G1, G14 |
| 23b | `Fallback` NOTE missing | G11, G12, G13 |
| 23c | NOTE printed for a non-merge commit | G10 |
| 23d | the gate prints a path raw instead of `escapeForNote` | `formatScopeNote` unit test |
| 24 | scope computed before the "no staged changes" skip * | G6 (no NOTE) |
| 25 | the gate scrubs its environment before spawning git | G8 (exact scoped NOTE) |
| 26 | an empty graded set treated as `Fallback` | lib empty-set test, G1b |
| 27 | drop `--cached` on the TIP call | S19 |
| 28 | the TIP passed by ref name instead of the resolved hex | the stateful-fake lib test |

Pre-declared equivalent or presence-only: `--no-renames` on `diff-index` is NOT in the lib's argv (plumbing never detects renames
without `-M` and ignores `diff.renames`; the porcelain staged reader keeps it, killed by #21); swapping `diff-index` for `diff` with
the same explicit flags and dropping the intersection with the staged list are verdict-neutral given the equality check (the argv pin
and the lib test are the only evidence); the order of the two `diff-index` calls and the display sort are verdict-neutral.
`--warn-only` adds no exit site in the new code, so G5 covers the unchanged site at :261; the other three sites are pre-existing and
untouched.

## 6. Process

Tier M, platform (a gate that classifies a blocking decision; the diff is `scripts/` + tests + docs, not payment/auth/sync/schema).
Three plan-review rounds are done (round 1: three seats; round 2: two seats; a delta round on revision 3, which had changed the
exemption comparison: two seats, one CONVERGED on the rule and one HARDEN on test-plan details only). Revision 4 folds the delta
round in; no design decision changed, and the implementation's own mutation runs verify the rewritten table row by row (the landing A0
precedent: no further review round for mechanical text). The full gate loop (whole-project `flutter analyze --no-fatal-infos`, `flutter test`, `sh scripts/pre-commit.sh`) runs
before the B-pass; the B-pass has two fresh seats and its file `docs/reviews/<hash>-review.md` carries its `## Tuning entry`; the
plan-review record cites that one file with `verdict: accepted`; the diagnose doc uses the FULL template (recurrence class: five
trips), cites the memory reference, the rejected earlier design and the test paths, and sets `sot_registry_entry:
blast_radius_registry_coverage`; the record is a second commit; one founder go covers commit, push, PR and merge, then
`safe_pr_merge.sh` (never raw `gh pr merge`; a classifier block routes through the GitHub PR). Commit type `feat(gates)` with
`closes-oi: OI-413` and `closes-diagnose:` (rule 22 binds only `fix|bug|regression` subjects; the message cites the regression-test
paths per rule 21). No section 4.2 closure ledger (one defect, every finding fixed in the batch). No hook, workflow or installer change,
so nothing to reinstall and no workflow scope. The VPS runs git 2.43.0 and CI 2.55.0; the plan uses only `rev-parse`, `merge-base`,
`diff-index` and `diff`, all available on both runners (VPS 2.43.0, CI 2.55.0) and none of them the 2.38 `merge-tree --write-tree`.

## 7. Measurement method (so the tables can be reproduced)

For each merge commit `M` with parents `P1 P2` reachable from `origin/main`: population 1 requires the subject to match
`Merge (remote-tracking )?branch '(origin/)?main'` and `git merge-base --all P1 P2` to have exactly one line; population 2 requires `M`
off the first-parent spine and `P2` on it. The full diff is `git diff --no-renames --name-only P1 M`; the rule's set is
`diff(P1,M) ∩ diff(P2,M)` (with `P2` standing for the main side at sync time, which is the tip when the sync is current); each path
is graded by the first matching `docs/blast_radius.yaml` glob (declaration order), then escalated to catastrophic when a
`supabase/migrations/**.sql` file at `M` contains `SECURITY DEFINER`.

## 8. Residuals

- A branch that merges an OLD main commit gets graded for every path main has changed since (over-blocking, never under-blocking);
  merging the current tip is the normal case.
- Over-blocking is real: in two independent randomised fuzzes between 25% and 45% of graded paths were byte-identical to a blob that
  exists at another path in a parent (relocations and git's own `~HEAD` leftovers; the figure depends on the shapes used), and a
  branch's own renumbered `SECURITY DEFINER` migration is graded again. The first forced review after this landing should read the NOTE list, not the full diff.
- Grading is by path NAME: content moved out of a catastrophic path by the branch's rename is graded by its new name, as before.
- A resolution identical to one parent for a path both sides changed is not graded (its content is one parent's).
- Two features that are individually fine and jointly wrong are judged by CI and the plan record, not by any commit-time gate (D5.5).
- The `Blast-radius:` trailer written for a branch-sync merge can still say catastrophic (D4); it is advisory.

## 9. As built (2026-10-25)

- **Files.** `scripts/merge_scope_lib.dart` (new, platform in `docs/blast_radius.yaml` beside the gate), the gate edit, the fixtures
  `test/helpers/merge_scope_repo.dart`, and four test files: `test/scripts/merge_scope_lib_test.dart` (32 tests), `merge_scope_git_test.dart`
  (23 real-git scenarios S1-S12, S14-S21), `merge_scope_git_fuzz_test.dart` (S13: 4 chunks of 20 seeds, three oracles) and
  `test/contracts/merge_scope_gate_e2e_test.dart` (29 tests: G1, G1b, G2, G3, G3b, G3c, G4, G5, G6, G7a-e plus the mirror, G8a-c, G9-G18). The
  staged-content fixture `review_gate_staged_content_not_working_tree_test.dart` (10 tests, green) now copies the gate's import closure.
  Line numbers quoted in sections 2 and 5 are those of the base file (`d1292a79`); the gate's `stagedPaths` is now `:116` and its tier loop `:250`.
- **Mutation proof (rule 21).** 79 mutants run on the FINAL tree (after the last edit of code and tests), all red: one per row of section 5
  except 6a, with the sub-variants 08b1/b2, 12b1-b6, 12c1/c2, 14a1-a4, 14b1-b5, 15a1/a2, 17b1-b4 and 06c1/c2, plus the B-pass additions
  (29 a failing git read as "no staged changes", 30 the review hash without `--ignore-submodules=none`, 31/31b two stand-down shapes (13 and 10
  tests red), 32-32d the FAIL listing, 33 the NOTE cut, 34a-e the escape boundaries, 35 the scoped PASS wording, 36 the tip reason). An earlier
  run had one survivor (12b6: a hex check that accepts a leading dash, which `-` plus 40 digits would pass to git as an option); three cases
  were added to the lib tests. Every killer named in the table was seen among the failing tests (05a: S14; 05b: S14 and G9; 13: S21 and G8a;
  21: G7a; 22: G7c; 25: G8c; 19: G4; 24: G6). Row 6a has no code to mutate. The harness is `c1_mutants.py` in the session scratchpad
  (not in the repository); the per-mutant counts are in `docs/audit/gate_test_ledger.yaml`.
- **Deviations from revision 4.**
  (1) The NOTE for an empty graded set reads `of N staged. Unmerged paths are graded.` (no dangling colon), and the suffix `Unmerged paths are
  graded.` is constant, not conditional.
  (2) Every non-ASCII file name in the gate test is built with `String.fromCharCode(s)`, and the line-terminator case builds U+2028 the same way
  (the Write tool turns a `\uNNNN` escape in written text into the real character).
  (3) `test/contracts/subprocess_test_timeouts_declared_test.dart` pins its guarded list at three files, so the new e2e file declares its own
  file-level `@Timeout(Duration(minutes: 10))` and is not added to that list.
  (4) Graded paths are the gate's own staged strings: nothing decodes a `diff-index` answer, so "only the graded survivors are decoded,
  strictly" (D2.4, section 4) and the test-list item "an undecodable graded name gives `Fallback`" did not apply; an invalid staged name fails the
  GATE with its own message (G7d, G7e) and `parseNulPaths` is strict (lib test 9). `Scoped` carries `(paths, tip, mergeHead)`, not counts.
  (5) The B-pass (two seats, 16 findings, all fixed in the batch) changed the code: the review hash carries `--ignore-submodules=none` (a gitlink
  hidden by `.gitmodules ignore = all` was graded while the hash was that of an empty diff), a scoped PASS reads `max blast-radius of the graded
  set`, a FAIL in a branch sync lists every graded path on stderr (the NOTE cuts at 20), and the tip reason reads `refs/remotes/origin/main is
  missing or not a commit` (git exits 1 for an absent ref, a ref at a missing object and a ref at a blob). New tests: G3c, G15 (the negative
  control for the stand-down: the same staged paths with no merge pending are refused), G16, G17 (a corrupt index), G18.
  (6) The fuzz floors are 1 conflicted merge, 5 scenarios with graded paths and 20 staged paths per chunk (measured 3-5, 10-13 and 56-79 on
  git 2.43.0), so a different git version that resolves one more seed cleanly does not turn the suite red.
  (7) Section 5's "mutants, one per row" read as 63 on the first run and 79 with the B-pass additions; the table above is the final one.
