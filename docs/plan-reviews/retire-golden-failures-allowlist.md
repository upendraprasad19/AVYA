---
branch: retire-golden-failures-allowlist
date: 2026-11-07
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/9a9b3c353212-review.md
---

# Plan-review record: the retire tool allowlists the golden comparator's `failures/` directory (platform)

**Tier `platform`, M (operator tooling, no `lib/`, no Hive key, no cloud column, no Edge Function):** one list entry in `scripts/retire_worktree_lib.dart`
(pinned platform at `docs/blast_radius.yaml:375-376`), a one-line `.gitignore` comment, three test files, a diagnose doc, one bug class and its index
row. The matcher `isRegenerableIgnored` is untouched. Execution mode: INLINE (one worktree). Founder go: "instead of filing why dont we fix it right
away?" (2026-11-07). Plan `docs/plans/retire-golden-failures-allowlist.md` (v3), diagnose
`docs/diagnoses/2026-11-07-retire-golden-failures-dir-blocks-worktree-e9b3c7.md`, B-pass `docs/reviews/9a9b3c353212-review.md` (verdict accepted).

## What this branch is

One concrete exact-match entry, `test/goldens/wardroom/failures/`, the single line `git status --porcelain --ignored=matching` prints for the directory the
Flutter test comparator writes on a golden mismatch (`.gitignore:193` ignores it by the glob `test/goldens/**/failures/`). The earlier decision to leave it
out ("it is a pattern", f2a9c7) confused the pattern with what the tool receives; the same move already carries `*.log` and a bare name. Three holds by
this directory were cleaned by hand (2026-09-27, 2026-09-28/29, 2026-11-06). Protection from three sides: a lib test (the string TRUE, eighteen near-misses
FALSE), an e2e in a real git repo with the real glob (one worktree retired, a second fictional suite kept byte-intact, a setUpAll self-check of git's own
output), and a classification test (two `git check-ignore` pins plus a guard that every directory under `test/goldens/` holding a `_test.dart` has its
`failures/` listed).

## Rounds

Two plan-review rounds by fresh context-blind Sonnet readers (each re-measured against the code and scratch repos; neither was told the other's findings),
then a one-reviewer B-pass on the built change.

| Round | Plan | P0/P1 | Outcome |
|---|---|---|---|
| #1 | v1 | 0 P0, 0 P1, 1 P2, 5 P3 | the e2e "other suite kept" case could pass for the wrong reason (without the real glob line the file is `??` and the worktree is kept as dirty): the glob line goes into the fixture, the KEEP reason is anchored, the fixture self-checks the exact `!!` line; entry-scoped mutants; the writer is the SDK comparator, not `golden_toolkit`; an `expectIgnoredByRepo` pin; tier source cited |
| #2 | v2 | 0 P0, 0 P1, 0 P2 | the KEEP assertion anchored to the `goldhome` line, mutants (d) to (h) entry-scoped, a second-suite guard and a fictional suite name, process list completed |
| B-pass | built | 0 P0, 0 P1, 2 P2, 4 P3 | two false history claims in the diagnose doc (an ordinal against its own three dates; three review rounds of one incident counted as three incidents), a header that miscounted, a surviving mutant (six spellings git never prints), a symbol-name filter in the new guard that a helper-driven suite would pass, an unrelated test that would redden when a real suite adds its entry: all six fixed in this branch |

## Ground truth

- The tool's own enumeration was read, not re-derived: `retire_worktree.dart:288` runs `git status --porcelain --ignored=matching`, which prints one `!!` line per ignored directory. A first diagnosis in this session that named two blockers came from a plain `git status --ignored` and was wrong; the registrant file was already allowlisted by exact path.
- The e2e self-check reads that exact line from both fixture worktrees (`!! test/goldens/wardroom/failures/`, `!! test/goldens/zzsuite/failures/`) before any scenario runs.
- Mutation: 15 mutants applied and restored byte-identical, all killed; the one that survived the first matrix (spellings git never prints) was found by the B-pass and is now pinned. Details in the diagnose doc's `mutation_evidence`.
- Whole-project `flutter analyze --no-fatal-infos`: 0 warnings, 0 errors; the three test files 84 / 84; the pre-commit gate loop OK with everything staged.
- Not verified here, said so in the diagnose doc: the recurrence dates (they live in session notes outside the repo), and Windows behaviour of the tool (reasoned from the matcher's backslash normalisation, pinned in the lib test, not run).

## Founder triage notes

Nothing needs a founder decision. The remaining steps are the commit, push and land, which wait for the founder's go.
