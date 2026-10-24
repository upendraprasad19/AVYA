---
branch: speedup-b2-bump-exemption
date: 2026-10-11
reviewed_at: 2026-10-11T12:51:00+05:30
staged_against: d363553e (staged diff at review time: 26 files, platform)
blast_radius: platform
reviewer: claude-sonnet via the code-review brief (fresh, context-blind, read-only except backup/restore mutation of seven named files, exhaustive command list). A first reviewer died on an API rate limit before reporting (no report; the tree was verified intact) and this one was dispatched with a persist-as-you-go rule.
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 7
verdict: accepted
---

# B-pass — release-cycle speedup B2 (`speedup-b2-bump-exemption`): merge-commit version-bump exemption (OI-275)

Reviewed diff: the staged diff against base `d363553e` (26 files, `platform`). **Result: 0 P0, 1 P1, 2 P2, 3 P3, plus 1 unnumbered
observation (a test gap) that the author classified P2.** The reviewer's summary: one bypass of the "bump only" waiver (a path list
that a repo-controlled file can edit), two P2 test gaps proven by surviving mutants, and three P3 nits. 13 mutations: 3 survived
(M3, M4, H1), a fourth direction was undiscriminated (M1). **All 7 items were fixed in this batch** (no deferrals), then re-verified by
mutation (see the author's Round B). Triage is the author's; the founder may re-triage any row. Numeric claims below are the
reviewer's unless marked; the author re-checked each cheap one (marked "re-checked").

## Finding 1 — P1 — missing_input (path-list completeness)
- **file:line:** `scripts/version_bump_git_lib.dart:119-121` (the `git diff --no-renames --name-only -z` arguments in `diffPathsBetween`). Consumers: the gate's direct loop and merge loop, and the CLI behind `safe_merge.sh`.
- **claim:** `git diff` honours `submodule.<name>.ignore = all` from a committed `.gitmodules` and then leaves gitlink pointer moves out of `--name-only`. A commit or merge that is a genuine bump plus a gitlink move was judged a bare bump (the reviewer's probe E2: paths `[app_constants.dart, pubspec.yaml]`, `rangeIsVersionBump == true`; the control without `ignore = all` listed `vendor/x` and was refused), and the same hidden path fed the tier computation. The brief's wording makes it a literal P0; rated P1 because the escaped change is an inert pointer and needs a prior `.gitmodules` landing (`.gitmodules` is `default_tier: feature`; the repo has no `.gitmodules` or gitlink; CI never inits submodules). It predates B2 for direct commits; B2 would have extended it to merges and the CLI.
- **author's re-check:** reproduced in a scratch repo before the fix, and again by the new tests' setup guards. The reviewer's side note that a file turned into a gitlink is not hidden (probe E10) is right, but its inference that "only pointer moves of an already-existing gitlink escape" is too narrow: a newly ADDED gitlink is hidden too (the new tests add `vendor/x` from nothing and their setup guard asserts plain `git diff` omits it).
- **status:** fixed — `diffPathsBetween` passes `--ignore-submodules=none` (git documents it as overriding any `ignore` in git-config or `.gitmodules`), and so does `safe_merge.sh`'s advisory diff. The comment in `plan_review_record_lib.dart` that said a gitlink "fails closed on its own" (true only AT a version path) now says where it does not. Tests: lib CLI attack + control; `diffPathsBetween` driven directly (the hidden gitlink is listed); the gate on a direct landing and on a bump merge (control + attack, with setup guards proving plain git hides the path and the flag shows it); the advisory (a gitlink under `supabase/migrations/**`, `.gitmodules` already on main, still warns). Mutants S1 and A1 below.

## Finding 2 — P2 — guard_without_its_mirror (follow the return value to its call site)
- **file:line:** `scripts/version_bump_git_lib.dart:122` (`if (r.exitCode != 0) return null;`) and `:125` (strict `Utf8Decoder` on the path list); call sites `scripts/check_plan_review_record_exists.dart:477` and `:530` (`if (paths == null) fail(...)`).
- **claim:** both ways `diffPathsBetween` says "git could not answer" were unpinned. M3: `return null` becomes `return <String>[]`; M4: `allowMalformed: false` becomes `true`; 57 tests stayed green under either (`run_M3.txt`, `run_M4.txt`). In the gate M3 turns a failing `git diff` into feature tier and a PASS; the CLI cannot tell null from `[]` because `rangeIsVersionBump` returns false for both. The gate test even said the null-diff `fail()` was "defensive ... not what this test drives". The ledger's "argued equivalent" note covered `_gitOrNull` and the guards inside `rangeIsVersionBump`, not these two.
- **status:** fixed — tests only (the code was right). `diffPathsBetween` is driven DIRECTLY by a throwaway Dart program (the lib has no working-directory parameter and the tests must stay hook-safe): an unresolvable rev is NULL, a MIRROR empty range is an empty list, an invalid-UTF-8 path is NULL, a valid non-ASCII path is verbatim, a leading-space name is untrimmed. The two call-site guards are driven through the real gate with a diff git cannot answer: the parent's root tree object is renamed out of the object store (rename, not delete: loose objects are read-only on Windows), after a control that the same landing passes; exit 1 and "could not diff". An invalid-UTF-8 path name through the gate (and the mirror that a valid non-ASCII name under `docs/` still passes). The shared fixture moved to `test/helpers/git_tree_fixture.dart` with a `rawNames:` option. Mutants M3, M4 and a warn-only guard at each call site below.

## Finding 3 — P2 — guard_without_its_mirror (a defeatable detector)
- **file:line:** `test/contracts/plan_review_gate_harness_copies_imports_test.dart:25` (`^import '([^':]+\.dart)';`).
- **claim:** the header says the closure is "computed from the source ... so the next import the gate grows is caught here", but only the bare `import 'x.dart';` spelling was seen. H1: `import 'version_bump_range.dart' as vbr;` (a script in no copy list) added to the gate left the contract test green (`+6`) while the e2e harnesses would fail to compile in their throwaway repos; the control with the plain spelling (H1b) went red. `show`/`hide`, `export`, `part`, double quotes and conditional-import URIs were invisible too.
- **status:** fixed — the detector finds the statement first (up to its `;`) and takes EVERY quoted `.dart` URI in it, so every spelling (including a conditional import naming three files) is found; `package:`, `dart:`, non-`.dart` URIs and commented-out directives are not. The detector is now a function with its own tests (`relativeImportsOf`), so a regression in a spelling fails by name instead of waiting for a gate to grow one. Mutants H1, H1b, H2 below.

## Finding 4 — P3 — asserted_fixture_value / overstated doc claim ("byte-identical")
- **file:line:** `scripts/version_bump_git_lib.dart:74` (`gitBlobAt`); the claim is repeated at `check_plan_review_record_exists.dart:506-509`, the ledger and the docs.
- **claim:** the predicate was not literally byte-exact in three small ways, none harmful on its own: E1 `Utf8Decoder.convert` discards a leading BOM (author re-check: `EF BB BF 61` and `61` decode to equal strings), so a BOM added or removed beside a bump compared equal; E3 an exec-bit flip (100644 to 100755) passed because both are in `regularFileModes`; E5 the `appVersion` value was any `'[^']*'` string (only commit-time Gate 51 ties it to pubspec, and the keystone gate does not run Gate 51).
- **status:** fixed rather than reworded — the claim is now true: `gitBlobAt` re-prefixes U+FEFF when the bytes start `EF BB BF`; `isVersionBumpCommit` requires `beforeMode == afterMode` (executable on both sides is still accepted); `versionLineConstants` requires `major.minor.patch+build` (the real value is `'1.0.0+48'`, the same shape the pubspec regex already required). Unit, CLI and mirror tests for each. Mutants B1, B2, B3 below.

## Finding 5 — P3 — writer_reader_drift (doc citation)
- **file:line:** `docs/sot_registry.yaml`, `line_range: 119-136` for `_parseRules`; the function is at 127-144 (re-checked). The range had been shifted mechanically by +15 from `104-121`, which did not match HEAD (`_parseRules` at 112); it still contained the declaration, so no gate tripped.
- **status:** fixed — `127-144`; `check_sot_registry_parity` passes.

## Finding 6 — P3 — misleading advisory wording
- **file:line:** `scripts/safe_merge.sh:309` (the NOTE). It is decided on `merge-base..tip` before the merge exists, but the gate decides on `M^1..M`. They agree for a clean merge; if the merge commit itself writes content resolving a conflict, the gate refuses while the advisory said "no record needed".
- **status:** fixed — the NOTE says "unless the merge itself writes content (a conflict resolution): the gate judges the merge commit's net change against main", with a comment naming the difference. No test pins the old sentence; the existing tests match `is a bare version bump`.

## Observation O1 — P2 (severity assigned by the author) — guard_without_its_mirror (merge direction)
- **claim:** "The merge-parent reverse direction (main moved ahead with a bump, branch carries non-bump content) has no discriminating fixture. M1 is still caught, because the wrong parent rejects genuine bumps." M1 (the exemption reads `$sha^2..$sha`) was killed by 4 pass-direction tests only. **Author's re-check:** the EITHER-parent variant (R1 below) was in fact killed by exactly one existing test, and only incidentally (`a push carrying a bump merge AND an unreviewed auth merge`: its second merge happens to have the first merge's bump on its other side); no test stated the single-merge reverse case.
- **status:** fixed — a REVERSE test (main gets a perfect bump after the branch was cut, the branch carries an auth change: not exempt, "no plan-review record") and its FORWARD MIRROR (main gets a docs commit after the cut, the branch is a bare bump: exempt, by the exemption and not by the feature-tier skip). Mutants R1 (either parent) and R2 (second parent) below.

## Lenses that returned clean (reviewer's evidence, condensed)
- **writer_reader_drift:** no Hive or Supabase access in the diff (0 hits); the moved reader code sits in `version_bump_git_lib.dart`, pinned `platform` at `docs/blast_radius.yaml:113-114` ahead of the `scripts/**` catch-all; old line citations in `safe_merge.sh` comments were replaced by symbol names.
- **function_exception_swallow, secrets_in_tree, unawaited_no_error_sink:** 0 `functions.invoke(`, 0 credential-shaped strings, 0 `unawaited(`. Refactor sub-check, diffing `git show HEAD:` against the staged gate: the old direct loop's `blobReadFailed` plus `isVersionBumpCommit` equals the new `before==null||after==null → return false`; `-c core.quotePath=false` is replaced by `-z` with no per-site extras lost; `_maxTierAcross` and `_checkOneRecordOneLanding` use `gitBlobAt`, whose body equals the deleted `_gitBlob`.
- **blast_radius_mismatch:** the record says `platform` and the diff touches platform files plus docs and tests; `.claude/commands/build-apk.md` has no registry rule (not a finding).
- **guard_without_its_mirror (beyond findings 2 and 3):** symlink mode checked on the head and the base side; the duplicate-token fixtures carry the duplicate on BOTH sides; the wrong parent `$sha^2` is caught by 4 tests; both trim-back mutants (the version-bump predicate, the Dependabot predicate) are caught.
- **missing_input:** the real files at `d363553e` (mode 100644, LF, no BOM, one `^version:`, one `appVersion`): a genuine +48 to +49 bump is exempt and the same bump plus `monthlyPriceInr = 349 → 1` is not; every script named in the Gate 2 text exists.
- **asserted_fixture_value:** the U+2028 and U+2029 fixture entries are real code points (`od -c` showed bytes 342 200 250 and 342 200 251; the author later found the SOURCE held them as literal characters and replaced them with escapes, see REG-5); the fixture helper asserts the commit changes exactly the intended path; removing `dotAll` reddens exactly the four terminator tests and the MIRROR stays green.
- **Specific questions answered by the reviewer:** a merge that is more than a bump (rename/copy, mode, CRLF, BOM, second token, case and non-ASCII look-alike paths, delete, create, binary, placeholder collision: no escape beyond findings 1 and 4); the null/empty/mode return values (only finding 2 unpinned); placement and first-parent (swapping the exemption and the `tier < account` skip is an equivalent mutant because `pubspec.yaml` is platform; a conscious design decision that an unrecognised-subject or foreign-owner PR whose whole net change is a bump now passes); `safe_merge.sh` (`set -u` only, everything quoted, merge-base failure falls to the warning, the NOTE prints only on CLI exit 0); `build-apk.md` Gate 2 (`new-worktree.sh <slug>` makes branch = slug, `safe_pr_merge.dart` merges with a merge commit so step 6 relies on exactly the new exemption, `--from-green` requires `HEAD == origin/main`); docs numbers match its reruns; tier matcher: a sweep over 684 files and 3,415 line-terminator variants against the real 166-rule registry graded 0 variants lower and 309 higher.
- **Not verified (reviewer):** the closure ledger beyond its first 60 lines and the plan-review record body; the sync-merge shapes inside a feature branch (reasoning only: they sit on the second-parent side and telescope into `M^1..M`).

## Mutation log
### Reviewer (against the staged blobs; backups verified byte-identical before and after)
| # | File | Mutation | Test file(s) | Red |
|---|---|---|---|---|
| FIX | version_bump_git_lib.dart | proposed fix applied (`--ignore-submodules=none`) | probe E2 | flips true to false, `vendor/x` appears |
| G1 | check_plan_review_record_exists.dart | remove `dotAll: true` | e2e, `line terminator` (5) | 4 (LF, CR, U+2028, U+2029); MIRROR green |
| A1 | plan_review_record_lib.dart | re-add `.trim()` in `isVersionBumpCommit` | exemption + lib unit (52) | 1 |
| A2 | plan_review_record_lib.dart | re-add `.trim()` in `dependabotDiffIsManifestOnly` | same two files | 1 |
| M1 | check_plan_review_record_exists.dart | merge exemption reads `$sha^2..$sha` | e2e, U1b (13) | 4 (pass-direction only; finding O1) |
| M3 | version_bump_git_lib.dart | non-zero git exit returns `[]` instead of null | lib test + e2e (57) | 0 — SURVIVED (finding 2) |
| M4 | version_bump_git_lib.dart | path list decoded with `allowMalformed: true` | same (57) | 0 — SURVIVED (finding 2) |
| M5 | version_bump_range.dart | CLI always returns 0 | lib test + safe_merge (39) | 16 |
| M6 | safe_merge.sh | CLI exit swallowed (`\|\| true`) | safe_merge (19) | 3 |
| H1 | check_plan_review_record_exists.dart | `import 'version_bump_range.dart' as vbr;` | harness-copies test (6) | 0 — SURVIVED (finding 3) |
| H1b | same | control: plain spelling | same | 2 |
| H2/H3 | build-apk.md (.opencode copy / .claude step 4) | 'ONE push' to 'TWO pushes'; `origin bump-<N+1>` to `origin main` | build_apk_bump_flow_test (8) | 2 |

Surviving non-equivalent: M3, M4, H1 (and the undiscriminated reverse direction, O1). Equivalent, argued and not run: swapping the exemption with the `tier < account` skip; a null blob treated as equal (caught later by `isVersionBumpCommit`); `$sha^` for `$sha^1`.

### Author, Round B (after fixing every item; each mutation confirmed APPLIED — exact single match, changed bytes — and the file restored and compared byte-identical)
| Mutation | Finding | Test file(s) run | Red (failing tests) |
|---|---|---|---|
| S1 `diffPathsBetween` loses `--ignore-submodules=none` | F1 | lib test + gate e2e | 4 |
| A1 `safe_merge.sh` advisory diff loses `--ignore-submodules=none` | F1 | safe_merge_test | 1 |
| N1 a failing git diff returns `[]` instead of NULL (the reviewer's M3) | F2 | lib test + gate e2e | 3 |
| N2 the path list is decoded with `allowMalformed: true` (the reviewer's M4) | F2 | lib test + gate e2e | 2 |
| N3 the direct-loop `paths == null` guard only prints (exit stays 0) | F2 | gate e2e | 2 |
| N4 the merge-loop `paths == null` guard only prints (exit stays 0) | F2 | gate e2e | 1 |
| N5 an EMPTY diff becomes NULL (the mirror of N1) | F2 | lib test + gate e2e | 1 |
| H1 the gate grows `import 'version_bump_range.dart' as vbr;` (the reviewer's H1) | F3 | harness-copies test | 2 |
| H1b CONTROL: the same import spelled plainly | F3 | harness-copies test | 2 (control: red with either detector) |
| H2 the detector goes back to the old `^import 'x.dart';` shape | F3 | harness-copies test | 1 |
| B1 `gitBlobAt` drops the leading BOM again | F4 | lib test | 1 |
| B2 mode equality removed (regular-file check only) | F4 | exemption unit + lib test | 2 |
| B3 `appVersion` accepts any quoted text again | F4 | exemption unit + lib test | 2 |
| R1 a merge is exempt when EITHER parent's diff is a bump | O1 | gate e2e | 2 |
| R2 the merge exemption reads `$sha^2..$sha` (the reviewer's M1) | O1 | gate e2e | 7 |

Every survivor of the reviewer's table is now killed (M3 = N1, M4 = N2, H1 = H1), and the direction its M1 left undiscriminated is pinned by R1 and R2. Rows B1 and N5 ran after the literal U+FEFF in the BOM line was replaced by its escape (the mutation could not match the literal form); the other rows ran on the tree that held it, whose behaviour is identical. The equivalent mutants the reviewer argued are left as they are. R2 was re-run once more (R2b) with the red tests listed: the same seven, namely four pass-direction tests, the merge-F2 test, REVERSE and FORWARD MIRROR, so both new direction tests discriminate the wrong parent. R1's two reds are the new REVERSE test and, incidentally, the existing two-merge push test.


## Process notes
- **Reviewer's protocol slips:** it ran `python3 --version` once (forbidden by the brief; it printed a version and touched nothing) and wrote one throwaway `sort -u > /tmp/__x` (deleted). Neither touched the repository: the tree was `cmp`-identical for all 7 mutated files and `git status` was unchanged (26 staged entries plus the two untracked docs).
- **First attempt:** the first reviewer died on an API rate limit with no report; its partial outputs were archived and the tree verified intact before the retry.
- **Author's own test bugs found by the first run of the new tests** (fixed, none reached the reviewer): the e2e helper that hides a root tree went through the shell helper (`_run`, `runInShell: true`), where `cmd.exe` on Windows eats the `^` in `<sha>^{tree}`; a BOM test committed a seed identical to the repository's own seed ("nothing to commit"). A literal U+FEFF in `version_bump_git_lib.dart` (the edit tool decoded the escape `\uFEFF` into the character) was found by the author's own invisible-character scan and replaced by the escape; the scan also found literal U+2028, U+2029 and U+00A0 in test sources (REG-5).
- **origin/main moved** to `273d2c1b` (7 commits past the base); overlap with this batch: `docs/diagnoses/INDEX.md`, `docs/naming_conventions.md`, `docs/sot_registry.yaml`, `.claude/skills/code-review/tuning-history.md`. Expect a merge and a regeneration after the founder's go.

## Founder triage notes
Triaged by the author on 2026-10-11: 7 accepted-and-fixed (finding 5 and 6 are doc/wording, finding 2's fix is tests only), 0 false alarms. The founder may re-triage any row.
