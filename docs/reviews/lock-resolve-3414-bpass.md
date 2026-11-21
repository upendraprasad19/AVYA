---
reviewed_at: 2026-11-21T16:30:00+05:30
staged_against: 510a641c0430607ae921da0f179694cbd9a1d004
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input]
findings_count: 15
verdict: accepted
verdict_note: 3 P2 and 12 P3, no P0 or P1; every finding was re-checked against the file by the author and accepted; none was a false alarm (self-attested triage)
---

# Code Review - lock-resolve-3414 (510a641c)

Context-blind adversarial B-pass (CLAUDE.md §4.3, self-initiated) over the committed three-dot diff `origin/main...510a641c` (3 paths: `pubspec.lock`, `docs/plans/2026-11-21-lock-resolve-3414.md`, `docs/audit/open_issues.md`), dispatched only after CI was green on that head and after `origin/main` was confirmed not to have moved (`HEAD..origin/main` empty). Two fresh Sonnet seats, read-only, with an exhaustive allowed-command list (no `dart run scripts/*`, no `scripts/*.sh`, no network tool, no database statement, no write to the repository). Seat A reviewed the lock and could run `flutter pub get` in a scratch folder; seat B reviewed the plan and the board entries by reading the gate sources, and could run no `flutter`. No P0 or P1. The fixes are in the commit that carries this file.

## Finding 1 - P2 - blast_radius_mismatch (BA-1)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md (no mention); docs/blast_radius.yaml:25
- **claim:** `platform` lists `regression_test`, `behavioral_test_path`, `code_review_b_pass`, `feature_flag`; the plan covers only the B-pass and the record.
- **verification:** `grep -nE "feature_flag|regression test|behavioral|rollback" docs/plans/2026-11-21-lock-resolve-3414.md` returned nothing at 510a641c; `docs/blast_radius.yaml:548` says "platform also requires a feature_flag".
- **status:** accepted - fixed (section "Platform-tier requirements": the two acceptance checks are the behavioural evidence, `feature_flag` is not applicable, the rollback is a revert; no script reads the list).

## Finding 2 - P2 - guard_without_its_mirror (BB-1)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:69 (step 6), :47 (C4)
- **claim:** the plan merges with `safe_pr_merge.sh` and says a bad record "reddens main only AFTER the merge", but CLAUDE.md §4.3 lands a branch's PR with `land_pr.sh`, which replays CI's record gate on the merge commit first (`scripts/land_pr.dart:476-566`).
- **verification:** `Select-String scripts/land_pr.dart -Pattern 'replay'`.
- **status:** accepted - fixed. `land_pr.sh` exits 4 on this Windows machine before any step, so step 6 now replays the same sequence by hand (scratch clone, `commit-tree`, the gate script with `PUSH_BEFORE`, `GITHUB_REF=refs/heads/main`, empty `GITHUB_EVENT_PATH`) and requires `replayVerdict`'s PASS line before `safe_pr_merge.sh`. Its output is read before the merge and reported to the founder.

## Finding 3 - P2 - missing_input (BB-9)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:19, :68
- **claim:** CLAUDE.md §4.2 requires `docs/audit/<batch>.closure.yaml` for a batch of four or more findings; this batch has more than thirty (two plan rounds, this B-pass, the units) and step 5 lists none.
- **verification:** `ls docs/audit | grep -c closure.yaml`; `scripts/validate_audit_closure.dart` accepts the file by name, no gate demands its existence.
- **status:** accepted - fixed (`docs/audit/lock-resolve-3414.closure.yaml`, every entry terminal; the two founder decisions are `blocked_on_user`, no `deferred:` key).

## Finding 4 - P3 - writer_reader_drift (BA-2, BB-3)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:34 (F10)
- **claim:** F10 cites `scripts/pre-push.sh:6` and `scripts/run_full_suite.sh:6`, both comment lines; the executing lines are `:139` and `:44`. The writer list omits `dart run scripts/*`, and `.fvmrc` is not covered by `scripts/check_ci_flutter_version.dart`.
- **verification:** `(Get-Content scripts/pre-push.sh)[5,138]`; `git grep -n fvmrc -- scripts .github`.
- **status:** accepted - fixed.

## Finding 5 - P3 - missing_input (BA-3)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:27 (F3)
- **claim:** F3 says which lock the build read is unproven; `.dart_tool/package_config.json` is independent evidence.
- **verification:** `Get-Content "<primary>\.dart_tool\package_config.json"`: generator `pub 3.11.1`, mtime 11:24:16, equal to the saved lock copy and before the AAB (11:34:46), listing the regenerated lock's versions.
- **status:** accepted - fixed (re-measured by the author).

## Finding 6 - P3 - writer_reader_drift (BA-4)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:45 (C2)
- **claim:** "versions the SDK or the dependency set forces" is too broad: the SDK pins `meta`, `vector_math`, `test_api`, `matcher`, `clock`, `stack_trace`; `flutter_riverpod` 3.3.1 and `riverpod` 3.2.1 are resolver choices, and "never buildable or tested" is an absolute no offline check supports.
- **verification:** `Select-String C:\flutter\flutter\packages\flutter\pubspec.yaml -Pattern 'meta|vector_math'`; `flutter_riverpod-3.3.1/pubspec.yaml:30` pins `riverpod: 3.2.1`.
- **status:** accepted - fixed (C2 split into the two groups; the absolute removed).

## Finding 7 - P3 - writer_reader_drift (BA-5)
- **file:line:** pubspec.lock (old, `git show origin/main:pubspec.lock` line 1801); .github/dependabot.yml:33-34
- **claim:** `main`'s lock contradicts itself (`sdks.flutter` `>=3.38.4` with two packages that declare `flutter: ">=3.41.0"`), so it was a partial bot edit, and the `analyzer` ignore did not stop `analyzer` 14.7.0 entering the lock.
- **verification:** `git show origin/main:pubspec.lock | Select-String 'flutter: '`; the two pub-cache pubspecs.
- **status:** accepted - fixed (added to the plan's Problem section and to OI-520; how Dependabot treats `ignore` for transitive entries stays stated as not established).

## Finding 8 - P3 - guard_without_its_mirror (BB-2)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:47 (C4)
- **claim:** the tuning-entry demand is listed among the merge gate's demands, but `check_skill_tuning_history.dart:20-31` runs at the commit that adds the review (CI passes it vacuously); C4 also omits the shape rules (`skill_tuning_lib.dart:430-470`).
- **verification:** read both ranges.
- **status:** accepted - fixed.

## Finding 9 - P3 - writer_reader_drift (BB-4)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:37 (F13), :53 (R3); docs/audit/open_issues.md OI-520 Verified line
- **claim:** "Dependabot also produced PRs on Saturday" is not established: the commits are dated Saturday, but the branch names (`image_picker-1.2.3`, `onesignal_flutter-5.6.7`) carry older versions than the commits, so the PRs existed earlier and were updated.
- **verification:** `git log --format='%h|%ad|%an|%s' --date=iso -6 origin/main -- pubspec.lock`; `git log --merges`.
- **status:** accepted - fixed (dates stated as dates; a rebase also regenerates the lock).

## Finding 10 - P3 - writer_reader_drift (BB-5)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:4
- **claim:** "both are docs-only" while `main`'s range includes `lib/features/train/CLAUDE.md`.
- **verification:** `git diff --stat 0907ee0d 20c0e40b`.
- **status:** accepted - fixed ("change only markdown").

## Finding 11 - P3 - missing_input (BB-6)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:60 (check 2)
- **claim:** `git status --porcelain` cannot be empty in a scratch repo without the repo's `.gitignore`.
- **verification:** measured by the author: the scratch repo listed `?? .dart_tool/` and `?? .flutter-plugins-dependencies`; `git diff --exit-code -- pubspec.lock` exited 0 and `git status --porcelain --untracked-files=no` was empty.
- **status:** accepted - fixed (check 2 rewritten).

## Finding 12 - P3 - writer_reader_drift (BB-7)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:53 (R3); docs/audit/open_issues.md OI-520
- **claim:** "only checks which files changed" understates the Dependabot exemption, which checks the branch prefix, the commit authors and manifest-only paths (`check_plan_review_record_exists.dart:611-621`).
- **verification:** read the range.
- **status:** accepted - fixed.

## Finding 13 - P3 - missing_input (BB-8)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:13; docs/audit/open_issues.md OI-520, OI-521
- **claim:** three inferences read as measurements: "a Dart 3.12 resolver wrote it", "riverpod 3.4.3 depends on `test_api`", "held at 3.2.1 because Flutter bundles Dart 3.11.1". The first two rest on the pub.dev API, which no offline seat could check; the third is wrong in mechanism (`flutter_riverpod` 3.3.1 pins `riverpod` 3.2.1 exactly).
- **verification:** `flutter_riverpod-3.3.1/pubspec.yaml:30`; the committed lock's own `sdks.dart` reads `>=3.11.1 <4.0.0`.
- **status:** accepted - fixed (labelled as pub.dev API facts or inferences; the mechanism corrected).

## Finding 14 - P3 - writer_reader_drift (BB-10)
- **file:line:** docs/plans/2026-11-21-lock-resolve-3414.md:60
- **claim:** "re-run by the B-pass seat" overclaims: seat B could run no `flutter`.
- **verification:** the seat brief's banned list.
- **status:** accepted - fixed (the coordinator and seat A ran them).

## Lenses that returned clean (reviewers' evidence, summarised)

- **secrets_in_tree (seat A):** the lock has 237 package blocks, LF endings, no BOM, only the keys `dependency`, `description`, `source`, `version`, `name`, `sha256`, `url` and the `sdks` section; every url is `https://pub.dev`; a regex scan of all 247 added diff lines for JWT, `rzp_`, `AIza`, `AKIA`, `sk-`, `sbp_`, private keys and e-mail addresses found nothing but pub.dev urls and doc paths.
- **guard_without_its_mirror (seat A):** the version-bump exemption returns false at `plan_review_record_lib.dart:345` (`pubspec.lock` and docs paths are outside `versionBumpPaths`, `:229`); the Dependabot exemption needs a `dependabot/` branch (`:189`), bot-authored commits and manifest-only paths and fails all three; the merge is `gh pr merge --merge` and the gate walks `--first-parent`, so only the PR merge is judged. Residual hazard accepted in R3 and OI-520: the next Dependabot pub PR can regenerate the lock and be waived.
- **blast_radius_mismatch (both seats):** `pubspec.lock` platform (`docs/blast_radius.yaml:678`), `docs/**` feature (`:579`), the first matching glob wins, `docs/blast_radius.yaml` is unchanged by the diff; the plan's "platform maximum, so the record plus `bpass: accepted`" is right.
- **missing_input (seat A):** the saved lock copy exists (56134 bytes, SHA-256 `B990F94F…D7C2`, mtime 11:24:16); the pub cache holds the 230 hosted packages; the repo has one `pubspec.yaml`, no overrides, workspace, path or git dependency, so a scratch resolve sees the repo's inputs. **(seat B):** `oi/520` and `oi/521` exist on the remote (`git ls-remote --heads origin "oi/52*"`), `scripts/check_oi_numbering_unique.dart` checks A, B and C pass by reading, `scripts/build_oi_index.dart` needs nothing the entries lack, the 22 phrases of `docs/deferral_euphemisms.yaml` match nothing in the plan or the 21 added board lines.

## Checks run on the lock (seat A, repeated by the author on the lock that will be merged)

| Check | Result |
|---|---|
| `flutter pub get --enforce-lockfile`, branch pair, scratch folder | exit 0, lock hash `B990F94F1EB4B65BDB392AA659CF6180BC44F1930D4345F8D2669767986AD7C2` before and after (author: same) |
| same, `origin/main` pair | exit 65, "Would change 31 dependencies", lock unchanged (seat A) |
| plain `pub get` in a scratch git repo, branch pair | exit 0; `git diff --exit-code -- pubspec.lock` 0; `status --porcelain --untracked-files=no` empty (author) |
| per package, old lock against new | 19 changed, 11 added, 1 removed; 0 changes of classification, source or url; 7 non-hosted entries are the SDK packages, identical |
| declared against locked | all 43 declared packages present with the matching direct class; versions inside their constraints |
| `sdks` and package minimums | lock `dart >=3.11.1 <4.0.0`, `flutter >=3.41.0`; the highest Dart minimum among the 230 hosted packages is `^3.11.0`, the highest Flutter minimum `>=3.41.0` (`image_picker` 1.2.4, `onesignal_flutter` 5.8.0) |
| integrity digests | the pub cache's `hosted-hashes` match the lock's `sha256` for 230 of 230 hosted entries (seat A; the author re-ran it: 230 of 230, 0 missing) |
| claim C2 | the import counts, the generator facts and the no-plugin statement hold for the 30 present packages; for the removed `listen` the no-plugin statement is UNVERIFIED (`listen-1.0.1` is not in the pub cache) |

UNVERIFIED by anyone offline, and labelled so in the plan and the board: the pub.dev API facts (`sdk: ^3.12.0` of `riverpod` 3.4.3, its dependency on `test_api`), CI's `success` on the earlier `main` commits, and whether Dependabot applies `ignore` to a transitive entry.

## Local contract-sweep warning, itemised (author, not a seat)

The pre-push `scripts/contract_sweep.dart --warn-only` printed `WARN: flutter test exit 1 on 28 selected file(s)` (`+707 ~8 -27`) when this branch's earlier head was pushed. The author re-ran the same 28 files (the list is `dart run scripts/contract_sweep.dart --dry-run`, range `origin/main...HEAD`, three changed paths) with Git's POSIX tools on PATH, as the hook's `sh` has them: `sync_with_main_e2e_test.dart` `+68 -10`, the other 27 files `+639 ~8 -17`, which adds up to the push's `+707 ~8 -27` exactly. The 27 failures sit in four files: `sync_with_main_e2e_test.dart` 10, `sync_with_main_state_e2e_test.dart` 11, `sync_with_main_wrapper_e2e_test.dart` 5, `discipline_hook_local_indexes_e2e_test.dart` 1. Their causes are in the test harness, not in any package: fake `git` / `sh` stub scripts that Windows cannot execute (`Expected: <4> Actual: <0>`, `git could not be started`), `/tmp/...` paths (`sync_with_main.dart is missing`) and, without Git's tools on PATH, `which`, `chmod`, `touch` and `sh` not found (16 failures in the first file instead of 10). None is the `SIGTERM errno 50` class (0 markers). The one in `discipline_hook_local_indexes_e2e_test.dart` is the failure recorded on this machine since 2026-11-03.

**Control:** the same four files on a detached throwaway checkout of clean `origin/main` (`20c0e40b`, `flutter pub get`, same PATH) gave `+114 ~2 -27`, with the same 27 failing test names (0 names differ between the two runs, per-file counts equal). So none of the 27 is introduced by this diff, which touches no script, test or package source. The control does not isolate the lock itself (its own `pub get` produced the regenerated lock), but the failure causes name no package. CI (Linux, four shards, the whole suite including these files) was green on this head. Both facts are about this Windows machine only; the files do not pass here with or without this change.

## Founder triage notes

Triaged by the author under the founder's instruction to commit `main`'s lock as Flutter 3.41.4 resolves it (2026-11-21, "Yes, do it") and the standing pipeline rules of CLAUDE.md §4.3 and §4.12: the 15 reported findings (5 from seat A, 10 from seat B; BA-2 and BB-3 are the same defect, so 14 sections above) are all accepted and fixed in this batch; none false. Self-attested.

## Tuning entry
- **2026-11-21** - blast-radius platform - 15 findings; 0 false_alarm; tuning: none to the lens text. Brief practice kept: the seat that must run a tool gets that tool confined to a scratch folder (seat A `flutter pub get`), the other seat none, and its brief must then not describe checks it cannot run (BB-10).
