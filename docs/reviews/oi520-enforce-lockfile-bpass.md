---
reviewed_at: 2026-11-22T14:30:00+05:30
staged_against: ffd2906ca56f1810ada92722d6b2ee98c1f9cf4a
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: 2 P2 and 4 P3, no P0 or P1; every finding was re-checked against the file by the author and accepted; none was a false alarm (self-attested triage)
---

# Code Review - oi520-enforce-lockfile (ffd2906c)

Context-blind adversarial B-pass (CLAUDE.md §4.3, self-initiated, platform tier) over the committed three-dot diff `origin/main...ffd2906c` of branch `oi520-enforce-lockfile` (PR 317; CI green on that head, run 44998296576). One fresh read-only Sonnet seat, lenses 1, 3, 4, 6, 7, 8 of the code-review skill and L1, L3, L54 of `docs/audit/LENS_REGISTRY.md`; lenses 2 and 5 not applicable, lens 4 found no secret-shaped literal. The seat worked in its own detached worktree and scratch repositories under the scratchpad (it mutated COPIES of the test and ran them), and removed the worktree without `--force`; the main worktree stayed clean. The change: a CI check in the required `Analyze` job (`flutter pub get`, then `git ls-files --error-unmatch -- pubspec.lock && git diff --exit-code -- pubspec.lock`), the contract test that pins its shape, and a comment and a documentation section. The plan is `docs/plans/2026-11-22-oi520-enforce-lockfile.md`; a narrow plan-review round 3 ran on the same head in parallel and converged with 4 P3 (its findings overlap BP-1, BP-3, BP-4 and BP-6 and are in the plan's Dispositions).

## Finding 1 - P2 - guard_without_its_mirror (BP-1)
- **file:line:** test/contracts/ci_lockfile_enforced_test.dart:116-146 (`_steps`), :228-238 (the pre-step check), at ffd2906c
- **claim:** a flow-style step (`- {name: X, run: '...'}`) or a step written `-  name:` (two spaces after the dash) was invisible to `_steps`: its dash regex needs `- key:` with one space, so the line was merged into the previous step's last key (the `with:` of `flutter-action`), and a neutering step before `Install dependencies` was not flagged. The header and claim C2 said any `run:` step before the resolving step is pinned, which was false for these spellings. Every mutant in the file was block-style, the silent assumption.
- **verification:** MEASURED by the seat: it inserted `      - {name: Neuter, run: 'git update-index --assume-unchanged pubspec.lock'}` after `cache: true` in the real `test.yml` and ran the real test: all 35 cases passed; the `-  name:` spelling gave the same; the block-style twin gave `[pre-step]`. MEASURED by the author (plan F16): in a scratch repo with a drifted lock, the verify command returns 1 without the neutering step and 0 with `git update-index --assume-unchanged pubspec.lock` run before `pub get`, although `pub get` rewrote the file.
- **suggested-fix:** make the reader fail closed on any line it does not parse, and add mutants for the flow-style step and the `-  name:` step.
- **status:** accepted - fixed in 7c9a5ebe and 63fcbf35: `[unparsed]` (guarded job) and `[unparsed-jobs]` (jobs section) reject every line the reader cannot interpret; mutants for a flow-style step, `-  name:`, an anchor, a bare `-`, `<<:` at job level and inside a step, an odd indent and a tab; real mutations M17 and M18 of the final run (plan F14) are red.

## Finding 2 - P2 - asserted_fixture_value (BP-2)
- **file:line:** test/contracts/ci_lockfile_enforced_test.dart:451,456 at ffd2906c
- **claim:** two mutants hard-coded `flutter-version: '3.41.4'`; a legitimate all-jobs Flutter bump (route 2 in `docs/architecture/hooks.md` and in the `test.yml` comment) turned the test red with "the mutant would be vacuous", and neither document mentioned this test.
- **verification:** MEASURED by the seat: all six pins changed to `3.42.0` in the sandbox gave `+33 -2`.
- **suggested-fix:** read the pin from the real workflow and build the mutants from it.
- **status:** accepted - fixed in 7c9a5ebe: the pin and the checkout line are read from the real job; the final real-mutation run includes G01 (all six pins bumped to `3.42.0`), which must stay GREEN and did.

## Finding 3 - P3 - guard_without_its_mirror (BP-3)
- **file:line:** test/contracts/ci_lockfile_enforced_test.dart:168-174 (`_namesTheCheck`), :202-205 (`sameName`) at ffd2906c
- **claim:** uniqueness of the check name read only an explicit `name:`. A job without `name:` produces a check-run named by its id; such a twin (in this file or in another) would mask the guard, because the wrapper takes the latest run per name (`scripts/safe_pr_merge_lib.dart:225`).
- **verification:** MEASURED by the seat, with the test's own helpers: an id-only `Analyze:` job gave GUARD-GREEN in `test.yml` and in another file; a named twin gave `[other-workflow]`. Whether GitHub treats `analyze` and `Analyze` as distinct ids is UNVERIFIED, so the comparison is case-insensitive.
- **suggested-fix:** treat a job without `name:` as named by its id.
- **status:** accepted - fixed in 7c9a5ebe: the effective check name is the `name:` or, when absent, the id (case-insensitive); a `name:` the reader cannot read as text counts as the check name; mutants for an id-only twin (`Analyze`, `ANALYZE`), a folded-scalar twin, a flow-style twin, a quoted-id twin and the same shapes in another workflow file.

## Finding 4 - P3 - guard_without_its_mirror (BP-4)
- **file:line:** test/contracts/ci_lockfile_enforced_test.dart:51-52, :149-151, :105-112, :65-67, :168-171, :501-507 at ffd2906c
- **claim:** the reader's tolerances (comments, quotes, `key :` spacing, the column-0 stop) had no killing mutant, and the "comment that quotes the command" test was vacuous for the comment stripping.
- **verification:** MEASURED by the seat on sandbox copies: `_strip` made a no-op, the `//` stripping removed, `_jobKeys` without quote tolerance, `_jobRange` without quote tolerance, `_namesTheCheck` without quote tolerance: each 35 of 35 cases still passed; `_clean` without trailing-comment removal was killed. Plan round 3 measured 13 such regressions, 11 survived.
- **suggested-fix:** a mutant or a control for each tolerance; put a `# flutter-version: 9` comment inside the `with:` block.
- **status:** accepted - fixed in 7c9a5ebe and 63fcbf35: mutants and 7 controls pin each tolerance; the harness `scratchpad\run_mutants4.js` removes each tolerance and guard branch of the reader in turn (32 mutations of the test file). Its first run had 4 survivors (the column-0 stop of the jobs-section reader, a non-key line at indent 8, the odd-indent branch, the repeated-action rule), closed by five more cases; the re-run on 63fcbf35 is 55 of 55 as intended, 0 survived (plan F14).

## Finding 5 - P3 - guard_without_its_mirror (BP-5)
- **file:line:** test/contracts/ci_lockfile_enforced_test.dart:149-155 at ffd2906c
- **claim:** `[required-job]` read `scripts/safe_pr_merge_lib.dart` as source text with a regex, which a multi-line `/* 'Analyze', */` comment defeats (the anchor line survives while Dart no longer requires `Analyze`); the skill's rule for a source grep is to prefer a value-level test, and one is cheap because `test/scripts/safe_pr_merge_lib_test.dart` already imports the library.
- **verification:** MEASURED by the seat through the harness: the multi-line comment form gave GUARD-GREEN; neighbouring tests (`safe_pr_merge_lib_test` 3 failures, `land_pr_lib_test` 2) did go red, so the suite as a whole caught it.
- **suggested-fix:** import `requiredSuccessJobs` and assert `contains('Analyze')`.
- **status:** accepted - fixed in 7c9a5ebe: the test imports `requiredSuccessJobs`; the regex and its comment stripping are gone; the in-memory mutant filters the imported list and real mutation M10 (the entry removed from the library) is red.

## Finding 6 - P3 - writer_reader_drift / blast_radius_mismatch (BP-6)
- **file:line:** docs/architecture/hooks.md:383, .github/dependabot.yml:50-53, plan line 6 at ffd2906c
- **claim:** `hooks.md` said the test "pins the shape of the two steps and of the job around them", which Finding 1 made an overclaim, and its "does not stop" row omitted unparsed spellings; the `dependabot.yml` sentence "exempt from the record ONLY while their pubspec.lock is left unchanged" was wrong (the exemption looks at the branch, the authors and the paths, `scripts/check_plan_review_record_exists.dart:611-619`, never at the lock; what is conditional is the red `Analyze`); the plan called `hooks.md` `feature` tier while `docs/blast_radius.yaml:124` makes it `platform`.
- **verification:** READ: the cited lines and `docs/blast_radius.yaml:124`.
- **suggested-fix:** reword the three.
- **status:** accepted - fixed in 7c9a5ebe: `hooks.md` states the fail-closed reader and what is not pinned (and cites the feedback memory as agent memory, not tracked in this repo), the `dependabot.yml` comment says the exemption never looks at the lock and the red `Analyze` is what blocks, the plan names `hooks.md` as `platform`.

## Verified clean (the seat, re-checked where noted)

| Check | Result |
|---|---|
| PRs 319, 320, 321 | CLOSED unmerged; 314 MERGED |
| `gh run view` on the proof runs 44987608180, 44990440321, 44994297459 | `Analyze` failed at the install step (319, the flag) or at the Verify step (320, 321); those heads carry the older step names but the command is unchanged since 9c489a33 |
| F14 counts | reproduced: verify step deleted 12 red, `\|\| true` 8, job id renamed 35, job `continue-on-error` 2 (the counts of the v2.2 head) |
| `--enforce-lockfile` | exits 0 on an `sdks` floor edit and on an added `collection: any`; a following plain `pub get` dirties the lock (same Flutter 3.41.4) |
| `.gitattributes` (`-diff`, `binary`, `diff=x`, `-text`, `eol=crlf`) | does not blind `git diff --exit-code`: each case returned 1 |
| mutants | all 29 then-existing in-memory mutants die with exactly their own token (the one with two tokens is "job renamed", `job-name` plus `job-name-unique`); none vacuous |
| readers of the changed step text | none beyond `hooks.md`; CI run 44998296576 green |
| counts | "five other install steps" and the mutant count correct; no lens-4 literal |

## Local contract-sweep warning, itemised (author, not a seat)

Every push of this branch printed `[contract-sweep] WARN: flutter test exit 1 on 17 to 19 selected file(s)` (`+325 -81` on ffd2906c's predecessor, `+327 -81`, `+378 -81` on the heads that followed). On each push the author extracted the failing test names from the push output, normalised them (path and file prefix stripped, non-ASCII removed) and diffed them against the failing names of the same sweep on a detached checkout of clean `origin/main` (`c8a19ef4`, saved as `sweep17_control.txt`): 81 failures in `test/scripts/land_pr_e2e_test.dart` each time, all carrying `SignalException: Failed to listen for SIGTERM ... errno = 50` (143 marker lines), 0 names only in the push, 0 only in the control. That is the known Windows harness class of `reference_windows_full_suite_two_known_failures.md`, not this branch. CI (Linux, four shards) is the full-suite gate and was green on ffd2906c.

## Founder triage notes

Triaged by the author under the founder's instruction of 2026-11-22 ("Yes, add CI check") and the standing pipeline rules of CLAUDE.md §4.2, §4.3 and §4.12 (the founder was not asked to ratify individual findings): 6 findings from 1 seat, each re-checked against the file (BP-1 and BP-2 also by the author's own measurement, plan F16), all accepted and fixed in this branch, none rejected, none a false alarm. The P3 findings were folded rather than left optional (§4.2). The B-pass's own method (mutate copies of the helpers and run them) was re-run by the author as a full harness on the fixed head and found four more gaps in the new cases, closed in the same batch.

## Tuning entry
- **2026-11-22** - blast-radius platform - 6 findings; 0 false_alarm; tuning: lens 6 gained a "hand-rolled parser" sub-check in `.claude/skills/code-review/SKILL.md` (a source-reading test with a hand-written YAML or text reader must FAIL CLOSED on any line it cannot interpret, and each tolerance it grants needs a mutant or a control; mutate the reader's own helpers and run). Brief practice kept: the seat may mutate COPIES in a detached worktree inside the scratchpad and must remove it without `--force`.
