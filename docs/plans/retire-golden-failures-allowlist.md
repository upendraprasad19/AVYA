# Plan (v3, after plan reviews 1 and 2): let `retire_worktree.dart` retire a worktree that holds the golden `failures/` output (exact path, one entry)

Branch `retire-golden-failures-allowlist`. Tier: platform (explicit pins `docs/blast_radius.yaml:375-376`; the `scripts/**` default is feature, `test/**` and `docs/**` are feature, so the max is platform); sizing M (CLAUDE.md 4.12.6: not S, not L). Execution mode (4.12.7): inline, one
worktree, one unit; no subagent implementation. Founder ask: 2026-11-07, "instead of filing why dont we fix it right away?" after the
retirement of `cron-log-retention-oi199-oi471` was held by this directory.

## Problem (verified 2026-11-07)

A worktree that ran the full local suite on this VPS WITHOUT `--exclude-tags golden` (CI passes it) has `test/goldens/wardroom/failures/` (8 PNGs
from golden comparisons that mismatch because the baselines are Windows-rendered). `scripts/retire_worktree.dart:285-298` counts every `!!` line of
`git status --porcelain --ignored=matching` that `isRegenerableIgnored` (`scripts/retire_worktree_lib.dart:335`, exact match against the list at `:238`)
does not accept, so the dry run reports `KEEP ... [1 non-regenerable ignored file(s)]` and the session has to ask a human. Recurrences: 2026-09-27
(ops-alerting-b2a2b), 2026-09-28/29 (reps-secs), 2026-11-06 (cron-log-retention-oi199-oi471) = three. Autonomous retirement (4.13 point 8) says never ask.

## Facts checked, with the command

1. The tool's enumeration is `git status --porcelain --ignored=matching` (`retire_worktree.dart:288`). Measured in a worktree with the directory
   present: it prints ONE line per ignored directory, `!! test/goldens/wardroom/failures/` (and `!! test/goldens/home/failures/` for a second
   suite), however many files are inside (review 1 re-measured: one line also for an empty `failures/`, and for a tree with nested subdirectories). Plain `--ignored`
   can collapse a parent instead (`!! test/goldens/home/` when only `failures/` is ignored there); the tool does not use it. Consequence stated: the single
   line authorises deleting the WHOLE subtree under it, nested subdirectories included.
2. `.gitignore:193` is `test/goldens/**/failures/` (comment `:190-192`: "diff artifacts ... per-run output of a failing test, never source").
   The writer is the Flutter SDK's `LocalFileComparator.generateFailureOutput` (`flutter_test/lib/src/_goldens_io.dart`, SDK 3.41.4 per `.fvmrc`: `generateFailureOutput` at `:141`, `createSync(recursive: true)` at `:158`, `getFailureFile` at `:167-172`): flat files
   `failures/<name>_{masterImage,testImage,isolatedDiff,maskedDiff}.png` next to the test file, only on a mismatch, `createSync(recursive: true)`,
   never deletes. `golden_toolkit` is not in `pubspec.yaml`, so the `.gitignore:190` comment names the wrong tool (fixed in this change, comment text only).
3. The tracked baselines are in a DIFFERENT directory, `test/goldens/wardroom/goldens/` (`git ls-files test/goldens` lists them), so the entry never
   touches a tracked or baseline file; a tracked file is never an `!!` line anyway.
4. `test/goldens/` today holds ONLY `wardroom/` (one suite). `test/goldens/home/failures/` appears in the tests only as a hypothetical sibling.
5. Precedent for listing the CONCRETE path a pattern produces, in `retire_worktree_lib.dart`: `.claude/.gate_failures.log` (`:322`, produced by the
   glob `*.log`, `.gitignore:3`) and `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` (`:274`, produced by the bare name
   in `android/.gitignore:7`). `test/scripts/gitignore_classification_test.dart:28-35` says glob entries (`:28-31`, which names this very glob) are out of
   THAT test's scope because `isRegenerableIgnored` is exact-match, and that the real deep path of a bare name "is classified in the lib list
   instead" (`:34-35`). Said precisely: the PATTERN stays unclassifiable; this change classifies one concrete path it produces, as the two entries above do.
6. The existing refusal to list this directory (`retire_worktree_lib.dart:323-327`, diagnose f2a9c7 of 2026-08-25) rests on one reason: it is a
   PATTERN and the list's rule is exact-match-only after three P0s from looser matching (prefix `.envrc`, basename `supabase/.env`). The concern
   is matching, not the directory. One literal path is exact: no prefix, no basename, no `contains`, no glob.
7. `test/scripts/retire_worktree_lib_test.dart:333-337` pins `isRegenerableIgnored('test/goldens/home/failures/')` FALSE ("so a later 'just add a
   glob' change reddens here"). That sibling stays FALSE after this change (it is a different literal).

8. Review 1 verified (read-only, scratch repos and a sibling real worktree): no script, hook, CI file, test or doc writes into `test/goldens/**/failures/`
   but the Flutter comparator; no doc tells anyone to keep something there; `git log --all` shows nothing ever added under a `failures/`; no existing
   test goes red when the entry is added (`gitignore_classification_test.dart` iterates `.gitignore` LITERALS against the two lists; the new entry is
   neither a literal nor in the precious list).

## Change

1. `scripts/retire_worktree_lib.dart`: add `'test/goldens/wardroom/failures/', // .gitignore:193` to `regenerableIgnoredPaths`, with the evidence in
   a comment; replace the "DELIBERATELY ABSENT" block with an accurate one: the PATTERN `test/goldens/**/failures/` stays out; the one concrete
   directory the tool emits for the one existing suite is listed; a second golden suite directory would keep its worktree until it is listed too.
   The new comment cites `.gitignore:193` (the old one said `:183`, wrong). No change to `isRegenerableIgnored` (still exact match) or the header rule.
2. `test/scripts/retire_worktree_lib_test.dart`: TRUE for `test/goldens/wardroom/failures/` and its Windows spelling
   `test\goldens\wardroom\failures\`. FALSE for: a file inside it (both spellings); the same path without the trailing slash (a pure exactness assertion: git cannot print that form for this
   dir-only pattern, a symlink named `failures` prints as `?? test/`, counts as dirty and keeps the worktree); the parents `test/goldens/wardroom/`, `test/goldens/`, `test/`; the tracked baselines directory `test/goldens/wardroom/goldens/`;
   the sibling suite `test/goldens/home/failures/` (existing assertion, comment updated); a path-prefixed form
   `backup/test/goldens/wardroom/failures/`; a name-extended form `test/goldens/wardroom/failures-old/`; a different-case form
   `Test/Goldens/Wardroom/Failures/`; a `.bak` form `test/goldens/wardroom/failures.bak/`. New near-misses use the fictional suite name `zzsuite` (a real future suite such as `home` must
   be able to add its own entry without tripping them); the existing `home` assertion at `:337` keeps its meaning today.
3. `test/scripts/retire_worktree_e2e_test.dart`, in the SHARED `setUpAll` repo (no extra `dart run` spawn; its `--execute --all` test covers the
   removal): add the real glob line `test/goldens/**/failures/` to the fixture `.gitignore` and two worktrees, `goldwardroom` holding
   `test/goldens/wardroom/failures/x.png` (must print `RETIRE  goldwardroom` and be removed) and `goldhome` holding
   `test/goldens/home/failures/x.png` (must print the line matching `KEEP    goldhome  \[1 non-regenerable ignored file\(s\)`, which anchors the reason to THIS worktree (a global
   `contains('non-regenerable ignored')` is already true from `ignored`, `envrc`, `nestedenv`) and whose `1` proves the whole directory counted as
   one `!!` line; it survives `--execute --all` byte-intact). Its suite name is `zzsuite`, not `home`.
   Without the real glob line the file would be `??` untracked, count as dirty, and a bare "is kept" would pass for the wrong reason, so the
   fixture self-checks, in a NEW block next to the existing existence and merged-branch checks (`e2e:152-166`, which check only that directories
   exist and two branches are merged), that `git status --porcelain --ignored=matching` in each of the two worktrees contains the exact
   `!! test/goldens/<suite>/failures/` line. The new names are not prefixed by an existing name
   (`ignored`, `envrc`, `envonly`, `wip`), so the file's `contains('KEEP    <name>')` style cannot match them by accident.
3b. `test/scripts/gitignore_classification_test.dart`: add `expectIgnoredByRepo` pins for BOTH `test/goldens/wardroom/failures/x.png` and the exact
   list string `test/goldens/wardroom/failures/` (`git check-ignore -v --no-index` gives `.gitignore:193` for both; the no-slash form exits 1) to the
   existing "must be ignored by the REPO .gitignore itself" group (the helper `expectIgnoredByRepo(String path, String consequence)` is declared inside that
   group at `:268`; its message reads `'$path is NOT ignored — $consequence.'`, so the third argument continues that sentence; the group title at
   `:248` is widened), so the new list entry is tied to `.gitignore:193` (failure direction without it is safe:
   the directory would show as `??`, count as dirty, and the worktree would be kept); and reword its header (`:27-31`) so it does not say the golden
   glob can never be classified in the lib list.
3c. **Second-suite guard (review 2 F7, the `guard_without_its_mirror` case):** in the same file, derive every directory under `test/goldens/` whose
   `.dart` files use `matchesGoldenFile` and require `<dir>/failures/` to be in `regenerableIgnoredPaths`. A second golden suite then fails HERE, at
   the moment it lands, instead of causing a seventh silent KEEP. Today the derived set is exactly `{test/goldens/wardroom}`.
4. `.gitignore:190`: `golden_toolkit` -> the Flutter test comparator (comment text only, SAME LINE COUNT so the glob stays at `:193`, which the
   new comment, the pins and the diagnose doc cite).
5. Docs: a diagnose doc (full template, recurrence class: d7b3e9, f2a9c7, b4d7e9, a9c4f2, b7d4c8, 8f3e35) naming the superseded sentences (lib
   comment, the `gitignore_classification_test.dart` header, f2a9c7 `proposed_fix`, a9c4f2 `:73` ("remain unclassifiable"), the OI-128 close
   text in `docs/audit/closed_issues.md:1329-1331`, the `reference_vps_quirks.md` "real fix still unapplied" line, and the two plans that
   describe the `rm -r` workaround). Records stay as history; the live statements are the two code comments above.

## Residual risk, stated

A file a human saves by hand into `test/goldens/wardroom/failures/` is deleted when its worktree is retired, where before the worktree was kept.
The directory's contract is "per-run output of a failing test, never source" (`.gitignore:190-192`) and the comparator rewrites it; the tracked
baselines are elsewhere. Because the one `!!` line authorises the whole subtree, anything nested under it goes too (measured by review 1). The destroyable-versus-recoverable asymmetry the header cites is real but the directory has no reason to hold anything
else. If a reviewer disagrees, the alternative is to leave the entry out and keep the documented workaround (`rm -r` the directory); the cost of
that alternative is one human round trip per full-suite session on this VPS.

## Tests and mutation proof (4.4 rules 21 and 24)

- New tests as above, then MUTATE, ENTRY-SCOPED so that only the NEW assertions can be what reddens (a whole-matcher widening also reddens the
  existing near-miss tests and would prove nothing about the new ones): (a) delete the new list entry (the real regression); (b1) add
  `|| p.startsWith('test/goldens/wardroom/failures/')` to the matcher; (b2) `|| p.contains('test/goldens/wardroom/failures/')`; (b3)
  `|| p.endsWith('wardroom/failures/')`; (b4) `|| 'test/goldens/wardroom/failures/'.startsWith(p)` (parents); (c) replace the entry by the glob string
  `test/goldens/**/failures/`; (d) `|| p.toLowerCase() == 'test/goldens/wardroom/failures/'` (entry-scoped, because lowercasing the whole path would also redden the existing
  `GeneratedPluginRegistrant.java` assertion); (e) `|| p.startsWith('test/goldens/wardroom/failures')` (no slash: name-extended, no-slash, inside);
  (f) `|| p.startsWith('test/goldens/wardroom/')` (baselines, parents, inside); (g) a glob-regex matcher `RegExp(r'^test/goldens/[^/]+/failures/$')`
  (killed by the existing `home` pin AND by the new e2e `zzsuite` case, which shows the e2e case is independent); (h) the entry spelled without its
  trailing slash. And a mutant on the second-suite guard: remove the list entry (it must redden the guard as well as the TRUE assertion). Confirm each mutation APPLIED (`grep -c`, and the diff of the file), run
  the three test files, and record which test names reddened and how many, measured and not predicted, in the diagnose doc; a mutant that reddens
  nothing is reported as such.
- Run: `retire_worktree_lib_test.dart`, `retire_worktree_e2e_test.dart`, `gitignore_classification_test.dart` (its literal-entry buckets must
  stay green: the new list entry is a concrete path, not a literal `.gitignore` line), whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop. No Edge Function, schema, or `lib/` change.

## Process

Commit type `fix(retire): ...` (CLAUDE.md 4.4 rule 22): body trailer `closes-diagnose: <id>`, a diagnose doc that passes
`dart run scripts/validate_diagnose_doc.dart`, full template (recurrence class). Platform record `docs/plan-reviews/retire-golden-failures-allowlist.md`
(`scripts/check_plan_review_record_exists.dart:795-827`): `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`,
`bpass: accepted`, `bpass_review: docs/reviews/<hash>-review.md` whose line-anchored `verdict: accepted` and `## Tuning entry` section exist; a Hermes
pass is NOT required (catastrophic tier only). Skill self-evolution (5.1): add the sixth instance to `.claude/skills/debugging/bug-classes.md`
(`:1836-1841`, the unretirable-worktree class) in the same commit. Memory outside the repo: `reference_vps_quirks.md` item 4 is rewritten after the
fix lands.

Plan review twice (context-blind Sonnet, ground truth against the files), B-pass on the staged diff (platform tier needs `bpass: accepted`),
plan-review record in a second commit, then commit, push and merge only on the founder's go (4.3). Blast radius to confirm with
`dart run scripts/blast_radius_from_diff.dart <paths>`: expected platform.

## Review 1 applied (v2)

Reviewer 1 (context-blind Sonnet, read-only, scratch repos and a sibling worktree): SOUND WITH FIXES, no P0 or P1; verified facts 1 to 7 and the absence of
any other producer or reader. Applied: **F1 (P2)** the e2e "home kept" case could pass for the wrong reason (without the real glob line the file is
`??` and the worktree is kept as dirty): the glob line is added to the fixture, the KEEP reason must contain `non-regenerable ignored`, the fixture
self-checks the exact `!!` line, and the cases go in the shared `setUpAll` repo with names not prefixed by existing ones; **F2 (P3)** entry-scoped
mutants instead of a whole-matcher widening, and a spelled-out near-miss list (path-prefixed, name-extended, inside, parents, no slash, Windows,
case); **F3 (P3)** the `gitignore_classification_test.dart` header and `.gitignore:190` are edited, a9c4f2 `:73` and the OI-128 close text are named
in the diagnose doc, the new comment cites `.gitignore:193`; **F4 (P3)** an `expectIgnoredByRepo` pin ties the entry to the `.gitignore` rule;
**F5 (P3)** the writer is the Flutter SDK comparator not `golden_toolkit`, the closer precedent is `.claude/.gate_failures.log`, the plain-`--ignored`
remark is corrected; **F6 (P3)** the tier source is the explicit pins at `docs/blast_radius.yaml:375-376`, `safe_push_test.dart` dropped from the run
list (it names the list only in a test title). Unverifiable by the reviewer and left to the author: the recurrence dates (they live in memory notes
outside the repo; the repo corroborates two sibling worktrees holding `failures/` dirs dated 2026-09-26 and 2026-09-27), Windows behaviour of the
tool, and that the planned mutants redden (measured when run).

## Review 2 applied (v3)

Reviewer 2 (context-blind Sonnet, read-only, scratch worktrees): SOUND WITH FIXES, no P0, P1 or P2; confirmed every citation and that the new e2e
worktrees fit the shared `setUpAll` repo with no change to any existing scenario or count. Applied: **F1** anchored the KEEP assertion to the
`goldhome` line; **F2** mutant (d) made entry-scoped; **F3** mutants (e) to (h) and the spelled-out `.bak` form; **F4** the false "symlink" reason replaced
by the measured behaviour; **F5** the overstated "already does" reworded; **F6** commit type, trailer, record fields, tuning entry, the
`bug-classes.md` instance and the memory note listed; **F7** the second-suite guard (3c) and a fictional suite name in the new near-misses; **F8**
one-line `.gitignore` comment edit; **F9** SDK line range. Process note: the reviewer ran `git worktree add --orphan` in the REVIEWED worktree by
mistake (a failed `cd` joined with `;`); the stray worktree, its admin entry and its directory were removed and verified gone before any edit.
