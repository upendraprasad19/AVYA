---
branch: speedup-b2-bump-exemption
date: 2026-10-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/speedup-b2-bump-exemption-bpass.md
---

# Plan review — release-cycle speedup B2: merge-commit version-bump exemption (`speedup-b2-bump-exemption`)

The plan is `docs/plans/2026-10-10-release-cycle-speedup.md` (master plan, four batches B1..B4; this record covers B2,
§3 of that plan). Founder directive 2026-10-09: "push and merge and CI is taking a lot of time everyday; plan and
implement all of these." B1 (`speedup-b1-prepush`) merged as PR #98 (`d363553e`); this batch is built on it.

## Why this record exists

B2 edits the keystone gate `scripts/check_plan_review_record_exists.dart` (pinned `platform`), moves its git readers into a new
`scripts/version_bump_git_lib.dart` and CLI `scripts/version_bump_range.dart` (both pinned `platform` by this batch), changes
`scripts/safe_merge.sh`, and rewrites Gate 2 of `.claude/commands/build-apk.md`. The exemption WAIVES the plan-review record and
the B-pass for platform-tier files (`pubspec.yaml`), so a wrong answer from it is a review bypass. Blast radius `platform`, so
CLAUDE.md §4.12 requires two context-blind plan-review rounds plus a B-pass before the merge to `main`.

## Rounds

The two rounds reviewed the master plan; B2 exists as its own batch because of round 1's split. Only what the plan itself records
is attributed to a round.

| Round | Reviewed | Outcome |
|---|---|---|
| 1 | Master plan v1 (one 7-unit batch), fresh Sonnet reviewer with no session context, told to verify every claim against code and live state | **needs-rework.** 0 P0, 11 P1 (plan header: "Round 1 (11 P1) forced the split into four batches"). The version-bump exemption became its own batch (B2) as part of that split; plan §1 runs it in parallel with B3, 'mostly, NOT fully, disjoint' (both touch `docs/blast_radius.yaml`, the glossary and the tuning history). |
| 2 | Master plan v2 (four batches, round 1 applied), a SECOND fresh reviewer, same brief | **needs-rework, localized.** 0 P0, 8 P1, all spec fixes; "a third full round is not warranted unless the edits change a design". The ones that shaped B2 (plan §3): P2-2/P1-6: the content-aware classifier flag for pre-push (U1a) is DROPPED (after B1 a bump PR's branch push is analyze-only; it would only help a direct push to main and would add an env var plus a second classifier path next to the gate), and OI-275 acceptance A is closed `verified_clean` with that evidence; P2-3: the doc ripple (CLAUDE.md §4.3, the code-review skill, `safe_merge_test.dart` advisory tests, the context-artifact budget); the reviewer verified that a change to the tier registry adds `docs/blast_radius.yaml` to the path list, so the exemption fails for it (OI-70 safe). All applied in plan v3. |

## Ground truth (verified against code and live state, 2026-10-11)

- `pubspec.yaml` is `platform` and `lib/core/constants/app_constants.dart` is `account` (`docs/blast_radius.yaml`); the gate walks FIRST-PARENT commits only (`git rev-list --first-parent <base>..HEAD`), so a sync merge made inside a feature branch is never judged on its own.
- The direct-commit exemption (OI-58a, `bd91c6eb`, 2026-07-28) is a pure function over before/after blobs (`isVersionBumpCommit`): every changed path in `versionBumpPaths`, exactly one version token per file normalised, regular-file modes, no create or delete. B2 reuses it unchanged for merges (`<sha>^1..<sha>`), content-keyed: the merge subject is NOT consulted (OI-58b untouched).
- Before B2 the merge loop had no such exemption, so a release bump needed a record and a B-pass for two version lines (and a second PR CI round for the record commit).
- Release flow today: `/build-apk` Gate 2 told the agent to commit the bump on `main`, which since B1 is the only push that still runs the ~39-minute local suite.
- A bypass in the EXISTING predicate was found by the author's own probe before this record: a file named `" pubspec.yaml"` (leading space) rode along on a genuine bump because paths were trimmed. It predates B2 (live for direct pushes since 2026-07-28) and is fixed here with its sibling in the Dependabot predicate (`docs/diagnoses/2026-10-11-version-bump-path-whitespace-34e764.md`).
- Sweeping the gate for the same class found a second, independent hole in the TIER classifier (also predating B2): `_globToRegExp` compiled `**` and `?` to a bare `.`, which does not match a line terminator, so a path whose name holds LF, CR, U+2028 or U+2029 (Linux only) was graded the default tier. Fixed with `dotAll` and tested through the real gate; the two commit-time classifiers that carry their own copy of the glob are outside this diff and are recorded in the closure ledger as a founder scope call (the keystone gate at merge-to-main is the enforcement point).
- Every consumer of the shared helper was followed to its call site: the gate's direct loop, its merge loop, the CLI, and `scripts/safe_merge.sh`'s advisory (NOTE for a bare bump, the original WARNING for anything else or any failure to ask).
- The independent B-pass (`docs/reviews/speedup-b2-bump-exemption-bpass.md`; one fresh context-blind Sonnet reviewer, a first one died on an API rate limit and left no report) returned 7 items: 1 P1, 3 P2, 3 P3, 0 false alarms, all fixed in this batch. The P1 is a FIFTH instance of the path-exactness class (diagnose 34e764), found by asking what ELSE configures the tool that renders the path list: a committed `.gitmodules` with `ignore = all` makes `git diff --name-only` omit a gitlink move (an ADDED gitlink is hidden too, which is wider than the reviewer's note), so a bump plus a hidden gitlink was judged a bare bump and the hidden path never reached the tier computation. Reproduced in a scratch repo before any code changed; fixed with `--ignore-submodules=none` in `diffPathsBetween` and in `scripts/safe_merge.sh`'s advisory diff.
- The P2s were tests that stayed green when the code was wrong, found by mutating the producer: the NULL-versus-empty contract of `diffPathsBetween` (NULL means git could not answer and must fail the landing, an empty list reads as feature tier and PASSES; two gate call sites and a CLI, 0 tests; mutants M3 and M4 survived 57 tests) and a harness-closure import detector that knew one spelling of `import` (mutant H1). All pinned now. The merge-direction pair is pinned too: main moved ahead with a bump while the branch carries real content is NOT exempt, main moved ahead with docs while the branch is a bare bump IS exempt (by the exemption, not by the feature-tier skip).
- The P3s made "byte-identical once the version token is normalised" literally true: `gitBlobAt` keeps a leading BOM (the Dart decoder strips it), the blob modes must be EQUAL on both sides, and `appVersion` must be a `major.minor.patch+build` value; plus a registry `line_range` (127-144) and the NOTE wording of the advisory (it is decided on `merge-base..tip`, the gate on `<merge>^1..<merge>`).

## Execution evidence (post-plan, after the B-pass)

- **Affected files, final tree** (exemption unit, record-lib unit, version_bump_git_lib, gate input-family e2e, plan-review record gate e2e, safe_merge, harness-copies, build_apk_bump_flow): 189 passed, 0 failed (one run, about 2 minutes).
- **Full local suite, final tree** (`TZ=Asia/Kolkata flutter test --exclude-tags golden`, one flutter process): 8,682 passed, 9 skipped, 0 failed in 26.5 minutes (the single-job CI run at the base d363553e had 8,588 passed, so this tree adds 94 tests).
- **Mutation proof, B-pass set** (each mutant confirmed APPLIED, RED, and its source byte-identical after restore): `--ignore-submodules=none` removed from the library 4 red and from the advisory 1 red; a failing diff returned as an empty list 3; lenient path decode 2; the direct-loop and merge-loop `paths == null` guards only printing 2 and 1; an empty diff as NULL 1; BOM dropped 1; mode equality removed 2; appVersion accepts any quoted text 2; merge exempt on EITHER parent 2 and on the second parent 7; import detector 2 / 2 (control) / 1. Earlier sets (gate G1..G18, safe_merge SM1/2/3/5, build-apk BA1..9, harness HC1..4, Dependabot D1/D2, whitespace W1..W3) are in the gate ledger and the diagnose doc.
- **Real files**: a genuine bump of the real `pubspec.yaml` and `lib/core/constants/app_constants.dart` is still accepted by `scripts/version_bump_range.dart`; the pre-commit gate loop passes on the staged tree.

## Convergence

**Converged for B2, B-pass accepted.** Round 2's remaining items were localized spec fixes (no design change), all applied. The B-pass then reviewed the BUILT code independently (1 P1, 3 P2, 3 P3, no false alarms) and every item is closed with a test that fails without the fix and mutation evidence (closure ledger BP-1..BP-7, REG-5). Residual risk, stated plainly: the exemption is only as good as `isVersionBumpCommit` and the path list it is fed. The author's own probing found one real bypass in that chain (a look-alike path name, fixed with its Dependabot sibling) and a second hole in the tier matcher (fixed); the independent B-pass found a fifth member of the class in git configuration the pusher controls (fixed). A sixth cannot be excluded by argument; the defence is that the list is now read byte-exact (NUL-separated, no rename detection, no submodule suppression, strict UTF-8, NULL on any failure) and compared exactly, and each of those properties has a test that goes red without it. The commit-time and push-time readers outside this diff share the old limits (closure PW-5, the founder's scope call); the keystone gate at merge-to-main, which this batch hardens, is the enforcement point. OI-275 stays OPEN: its item D, the allow-rule `Bash(sh scripts/safe_pr_merge.sh:*)`, is a settings change that is the founder's to make.
