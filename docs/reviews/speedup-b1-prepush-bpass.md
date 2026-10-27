---
branch: speedup-b1-prepush
date: 2026-10-10
reviewed_at: 2026-10-10T02:09:00+05:30
staged_against: ab1fe0223e86
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind, read-only except backup/restore mutation of three files)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 12
verdict: accepted
---

# B-pass — release-cycle speedup B1 (`speedup-b1-prepush`): pre-push branch-push skip + `safe_pr_merge.sh` (OI-275)

Reviewed diff: the staged diff at staging hash `ab1fe0223e86` (25 files, platform). **Result: 0 P0, 0 P1, 12 P2.**
The reviewer's summary: the production code held up against every hostile input it could build (33 stdin shapes through the real
classifier under dash and gawk; none lets a push to main/develop classify BRANCH_ONLY or DELETE_ONLY; the evaluator fails closed on
every unreadable-input case). The 12 findings are mutation survivors (test gaps), one asymmetry in the lib's "floor" rule, two
residual-risk gaps in the wrapper, and doc drift. **All 12 were fixed in this batch** (no deferrals); the fixes were then
re-verified by mutation (see "Triage / fix verification" and the author's Round B mutation log). Triage is the author's; the
founder may re-triage any row.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** scripts/pre-push.sh:184 (`$2 ~ /^0+$/ { del++; next }`), test/scripts/pre_push_branch_push_skip_e2e_test.dart (`_sha = 'a' * 40`)
- **claim:** The anchor on the delete detector is pinned by no test. Mutant `/^0+$/` -> `/^0+/` left all 32 tests green: every `_update` fixture uses sha `aaaa...`. Any real sha beginning with `0` (about 1 in 16 commits) would count as a delete; an all-such push becomes DELETE_ONLY and skips the suite at any tier, including unknown or empty-range, where the fail-safe must run it.
- **verification:** `sed -n 184p scripts/pre-push.sh`; apply the mutant; run the e2e file.
- **status:** fixed — added cases with local shas `0aaa...` and `000...1` (unknown tier + empty range, expect the suite) and a 64-zero delete. Mutant now RED (1).

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** scripts/pre-push.sh:188 (`if (upd == 0 && del > 0)`)
- **claim:** "Every line deletes" is unpinned: mutant `if (del > 0)` (a mixed update+delete push counted DELETE_ONLY) kept all 24 tests green because the only mixed-push test ran at platform tier where both classes skip.
- **status:** fixed — mixed update+delete push at an unknown tier and with an empty range now expects the suite. Mutant now RED (1).

## Finding 3 — P2 — guard_without_its_mirror
- **file:line:** scripts/pre-push.sh:199-211 (DELETE_ONLY block before the `origin/main` fail-safe)
- **claim:** The comment says the DELETE_ONLY skip sits before the origin/main AND empty-range guards on purpose, but tests covered only the empty-range half (every fixture repo had `refs/remotes/origin/main`). Moving the block below the origin/main guard kept 32 tests green.
- **status:** fixed — a third fixture repo with NO origin/main plus a delete-only case. Mutant (block moved below the guard) now RED (1).

## Finding 4 — P2 — guard_without_its_mirror
- **file:line:** scripts/safe_pr_merge_lib.dart:165 (`!_completed(r) || _conclusion(r) != 'success'`)
- **claim:** The fail-closed core predicate was tested only against failure/skipped/in_progress/missing. Mutant `== 'failure' || == 'skipped'` kept 60/60 green and would accept a required job that is `timed_out`, `action_required`, `startup_failure`, `stale` or `neutral`.
- **status:** fixed — the per-required-job loop now also iterates those five conclusions and expects a refusal naming the conclusion. Mutant now RED (5, one per required job).

## Finding 5 — P2 — guard_without_its_mirror
- **file:line:** scripts/safe_pr_merge_lib.dart (the "other checks" loop)
- **claim:** Asymmetric floor rule: a REQUIRED job with only cancelled runs is refused, but an UNLISTED job whose only runs are cancelled is never reported (the "other" loop iterates `latest`, which excludes cancelled runs). A timed-out job is reported as cancelled (test.yml's own 2026-07-01 note), so B3's `Unit Tests shard n/4` jobs would be silently ignored on timeout.
- **status:** fixed — the lib now reports every unlisted cancelled-only job; tests: cancelled-only unlisted job refuses, cancelled-then-rerun-to-success is fine. Mutant now RED (1).

## Finding 6 — P2 — blast_radius_mismatch
- **file:line:** scripts/safe_pr_merge.dart (`prFields` omitted `files`; `baseRefName` fetched but never judged)
- **claim:** A `pull_request` run uses the PR's OWN `.github/workflows/test.yml`, so a PR that edits it can make a required job green vacuously — weaker than the old local suite, which was independent of test.yml; B3/B4 rewrite exactly those jobs next. `baseRefName` was unused: a PR into another base gets no CI and was refused only by the zero-check-runs path.
- **status:** fixed — changed files are read through the paginated `pulls/N/files` endpoint (the `--json files` field is capped at 100; a rename's previous path counts too); any `.github/` path refuses unless the caller passes the deliberate `--allow-workflow-change` (the sh wrapper forwards that one literal flag only); an unreadable file list fails closed; a base other than main/develop refuses. Mutants (CI-config check off, base check off) now RED (3, 2).

## Finding 7 — P2 — guard_without_its_mirror
- **file:line:** scripts/safe_pr_merge.dart (after `gh pr merge`)
- **claim:** After `gh pr merge` exits 0 the wrapper reported "merged" without re-reading the PR (the repo's "git said OK but it didn't land" class); a merge-queue or auto-merge enqueue would be reported as merged.
- **status:** fixed — the PR state is read back; anything but `MERGED` exits 2 UNVERIFIED (as `safe_push.sh` does). Mutant (read-back off) now RED (1).

## Finding 8 — P2 — guard_without_its_mirror
- **file:line:** scripts/pre-push.sh:244-252; .github/workflows/test.yml:6-7
- **claim:** The skip message said CI on the open PR is the gate, but CI runs only for a PR into main/develop; for a PR-less branch (about 20 of 29 remote branches per the hook's own header) no suite runs anywhere, and the old hook ran the suite locally.
- **status:** fixed — the message now states "NO test suite has run anywhere for this branch until a PR into main/develop exists — only analyze", and a test asserts it.

## Finding 9 — P2 — missing_input
- **file:line:** scripts/safe_pr_merge.sh; test/scripts/safe_pr_merge_e2e_test.dart
- **claim:** The only test of the sh wrapper exited at its own argument-count check; the `_dart_bin.sh` sourcing and the `exec ... "$1"` hand-off were unexercised, so a typo there passed every test.
- **status:** fixed — (a) `sh scripts/safe_pr_merge.sh abc` must reach the Dart program (`unexpected argument "abc"`); (b) a verbatim copy of the wrapper in a scratch git repo with a stub `dart` records exactly what is forwarded (`96`, and `96 --allow-workflow-change`); (c) arbitrary second arguments are rejected. Three wrapper mutants (drop the PR argument, drop the flag forward, accept a different flag literal) now RED (2, 1, 1).

## Finding 10 — P2 — writer_reader_drift (moved-prose and stale claims left behind)
- **claim:** Several places still described the pre-change behaviour or cited drifting pre-push line numbers: scripts/pre-commit.sh:116, docs/onboarding/FRESH_CLONE.md, .github/workflows/test.yml:110 (false golden claim), test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart:82 (same false golden claim), scripts/contract_sweep_lib.dart:27 and its test:40; line-number citations in scripts/blast_radius_stdin_usage_lib.dart:74 and its test:87, analyze_narrower_than_lib_lib_test.dart:81, scripts/safe_merge.sh:270.
- **status:** fixed — every one reworded; line numbers replaced by symbols. (The test.yml edit is comment-only, so this branch's PR touches `.github/` and is merged with `--allow-workflow-change` after reading that one-comment diff.)

## Finding 11 — P2 — asserted_fixture_value
- **file:line:** docs/diagnoses/2026-10-10-release-cycle-wallclock-c7a3e9.md (`regression_test_planned`)
- **claim:** Quoted counts were off (49 vs the measured 50) and the first mutation record did not say which mutant form produced "4 failures" (the reviewer got 5 reds counting the presence pin).
- **status:** fixed — the doc now quotes the measured counts after the fixes (23 pre-push e2e, 65 lib, 17 wrapper e2e, 6 contract) and states the mutant forms.

## Finding 12 — P2 — writer_reader_drift (docs)
- **file:line:** docs/naming_conventions.md:332-333
- **claim:** The new `push class` and `safe_pr_merge` glossary rows had 2 cells; the table has 3 (`Term | Meaning | What it is NOT`).
- **status:** fixed — third cell added to both.

## Lenses that returned clean (reviewer's evidence, condensed)
- **writer_reader_drift (beyond 10-12):** job names byte-equal to the seven `name:` fields of test.yml (only the two push-only jobs carry a job-level `if:`); pre-push echo text matches the tests' `contains` strings; no test pins the reworded CLAUDE.md/hooks.md/process-invariants-detail/build-apk/batch_close_lib text; none of the 279 added `.md` lines hits the 22 deferral-euphemism phrases; context-budget bands: CLAUDE.md +1.4%, open_issues.md +5.25%, both inside the soft band.
- **function_exception_swallow:** 0 `functions.invoke` hits; the CLI catches only `ProcessException` / `FormatException`, both failing closed; `parseCheckRuns` can only throw `FormatException`.
- **blast_radius_mismatch:** the three new platform pins sit before the `scripts/**` catch-all (first match wins); nothing in the diff is above platform.
- **secrets_in_tree:** 0 hits for the credential-shape patterns over the added lines; the fixture holds only check-run ids, a commit sha and two app slugs.
- **unawaited_no_error_sink:** 0 `unawaited`/`Future`/`async` additions; no `&` background in the staged shell scripts.
- **guard_without_its_mirror (areas probed, no finding):** 33 stdin shapes (new branch, main, develop, delete of main, CRLF main -> OTHER, CRLF branch, 40- and 64-zero deletes, tag, notes, remotes, mixed, empty, blank lines, lone CR, 3- and 5-field, tabs, trailing spaces, regex metacharacters, `refs/heads/mainX`, `refs/heads/main/x`, `refs/heads/Main`); git never lists a rejected or up-to-date ref on stdin; `PUSH_REFS=$(cat)` on closed stdin dies exactly as the old `cat > /dev/null` did; a failed `awk` blocks the push (never skips); an empty or unknown TIER falls through to the suite; the PR number is `^[0-9]+$`, the repo `^[\w.-]+/[\w.-]+$`, the sha `^[0-9a-f]{40}$`, with no shell (`runInShell: false`) so there is no injection into the `gh api` path; check-run ordering is by max id independent of list order; a required name under a non-github-actions app is ignored; truncated/unbalanced JSON, an empty body or a page without `check_runs` refuse. Not validated by the reviewer: `total_count` vs parsed length (now enforced — see the author's follow-up below).
- **missing_input:** test.yml job names, the fixture (staged, 8 runs, `total_count` 8), `_dart_bin.sh`, `spawn.dart`/`dartBin()` all exist; staged blobs are LF; `git diff --cached --check` is clean. Not verifiable offline by the reviewer: the fixture's live-capture provenance, branch protection and the 39/13-minute figures (the author re-verified these with `gh` before the review: protection read live, the fixture captured from PR #96's head, the full suite measured at 38 min on 2026-10-10).
- **asserted_fixture_value (beyond 11):** the red-fixture regex flips exactly `Unit Tests`; every SKIP-half test has a paired RUN-half case, so none would pass if the feature did nothing; the diagnose-doc line cites 108/244/123 are correct; `spawn_env_manifest` and `spawn_sites_guard` pass with the new e2e file in the recursion allow-list.

## Mutation log
### Reviewer (against the staged blobs; backups verified byte-identical before and after; no compile-error mutants)
| # | File and change | Result |
|---|---|---|
| M1 | pre-push.sh `/^0+$/` -> `/^0+/` | 0 red of 32 — SURVIVED (finding 1) |
| M2 | pre-push.sh `upd == 0 && del > 0` -> `del > 0` | 0 red of 24 — SURVIVED (finding 2) |
| M3 | pre-push.sh DELETE_ONLY block moved below the origin/main guard | 0 red of 32 — SURVIVED (finding 3) |
| M4 | pre-push.sh `$3 !~` -> `$1 !~` (local ref instead of remote ref) | 2 red — KILLED (incidentally) |
| M5 | pre-push.sh main clause removed | 5 red — KILLED |
| M6 | safe_pr_merge_lib `!= 'success'` -> `== 'failure' \|\| == 'skipped'` | 0 red of 60 — SURVIVED (finding 4) |
| M7 | safe_pr_merge_lib unreadable `false` -> `true` | 2 red — KILLED |

### Author, Round B (after fixing every finding; the 110-test set of four files, plus the 17-case wrapper e2e file for the sh mutants; each mutation confirmed APPLIED by `cmp`, every file restored and `cmp`-verified)
| Mutation | Red |
|---|---|
| M1 unanchored `/^0+/` | 1 |
| M2 mixed push counted DELETE_ONLY | 1 |
| M3 DELETE_ONLY block below the origin/main guard | 1 |
| M6 weakened success predicate | 5 |
| M8 unlisted cancelled-only jobs ignored | 1 |
| M9 CI-config paths never flagged | 3 |
| M10 base-branch check off | 2 |
| M11 post-merge MERGED read-back off | 1 |
| M12 `total_count` check off | 1 |
| sh wrapper drops the PR argument / drops the flag forward / accepts a different flag literal | 2 / 1 / 1 |

All four reviewer survivors (M1, M2, M3, M6) are now killed.

## Author's follow-ups found while fixing (not separate findings)
- The full-suite run before this review had one failure, in `test/contracts/spawn_env_manifest_test.dart` (the recursion pin enumerates every test that runs the real hook; the new e2e test had to be added). The reviewer saw the fix already in place.
- While fixing finding 6 the new wrapper tripped the same manifest test a second time: `${ALLOW:+...}` in the sh wrapper reads as an environment-variable read. Rewritten as a plain `if`.
- The reviewer noted `total_count` vs the parsed length was not validated; it is now (a dropped or duplicated page makes the parse fail closed), with a test and a mutation.

## Founder triage notes
Triaged by the author on 2026-10-10: 12 accepted-and-fixed, 0 false alarms. The founder may re-triage any row.
