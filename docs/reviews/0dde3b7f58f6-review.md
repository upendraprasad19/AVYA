---
reviewed_at: 2026-10-25
staged_against: b0735bb1 (origin/main 38f8a064 differs only in docs/audit/open_issues.md)
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh context-blind seats, read-only; S1 gate/parser/tests, S2 renumber/citations/docs/registries)
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 17
verdict: accepted
---

# Code Review - landing B: bug-class uniqueness gate + renumber (OI-167, diagnose d5b8e3)

Diff reviewed: the 23 staged files of branch `bug-class-uniqueness` (the gate
`scripts/check_bug_class_numbers_unique.dart`, its parser `scripts/bug_class_ids_lib.dart`, three test files, the
renumber of nine bug-class ids in `bug-classes.md` and the SKILL.md index, 18 repointed citation lines in 9 files,
registries and docs). Both seats were dispatched context-blind with an exhaustive command list (read-only git,
reading tools, `python3 -I` on scratch copies, the named test files, `dart analyze`, and exactly one script run:
the new gate with `--root=` on catalogs they built in their own scratch dir). Neither seat touched a tracked file.
Every finding below is closed in the same batch; the staged hash above is of the tree AFTER those fixes.

## Seat S1 - the gate, the parser and the tests (0 P0, 0 P1, 2 P2, 9 P3)

### S1-1 - P2 - asserted_fixture_value
- **claim:** the 16-character title rule had no boundary pin: comparing 15 or 17 characters instead of 16 left every test green.
- **status:** accepted - fixed: two lib tests pin a title that differs only at character 16 and only at character 17; mutants N01 (15) and N02 (17) are red (2 and 3 tests).

### S1-2 - P2 - guard_without_its_mirror
- **claim:** a heading indented one to three spaces (`   ### 2.9 X`) was ignored, so a real duplicate hid behind an indent and the gate passed.
- **status:** accepted - fixed: the lookalike rule now matches up to three leading spaces (`^ {0,3}#{1,6}\s*\d+\.\d+`) and reports an indented heading as unparseable; mutants N03 to N05 (no indent, narrowed levels) are red.

### S1-3 - P3 - guard_without_its_mirror
- **claim:** an unclosed code fence silently swallowed every later heading and row, so the tail of a catalog could vanish from the check without a finding.
- **status:** accepted - fixed: `_scanFences` returns the unclosed opener and the checker reports it with its line; mutants N17, N24, N25 are red.

### S1-4 - P3 - guard_without_its_mirror
- **claim:** when the parse found zero headings or zero rows the gate printed only the zero-guard message, hiding the findings that explained why.
- **status:** accepted - fixed: findings print first, the guard message after; N22 is red.

### S1-5 - P3 - missing_input
- **claim:** a missing input file named only the repo-relative path, so a run with `--root=` against the wrong directory did not say which root it looked in.
- **status:** accepted - fixed: the message names the root; N23 is red.

### S1-6 - P3 - guard_without_its_mirror
- **claim:** `next free id: null` was printed when the catalog had no ids.
- **status:** accepted - fixed: the clause is omitted when there is no next id; N21 is red.

### S1-7 - P3 - guard_without_its_mirror
- **claim:** the table separator test accepted only `---`; `:--`, `--:` and a two-dash cell are legal separators.
- **status:** accepted - fixed: separator regex `^:?-+:?$` on all cells; N18 is red.

### S1-8 - P3 - guard_without_its_mirror
- **claim:** prose such as `#2.9` or a numeric heading in SKILL.md of another major was not reported.
- **status:** accepted - fixed: the numeric-heading rule is major-2 only by design and pinned both ways (N19 red); a prose line that starts with `#N.M` is read as a heading that did not parse, by design, and a lib test says so.

### S1-9 - P3 - guard_without_its_mirror
- **claim:** `--next` printed a bare id with no banner while the header documents it, and the docs did not say which file to read the id from.
- **status:** accepted - fixed: bug-classes.md header and SKILL.md section 5 rule 1 name `--next`.

### S1-10 - P3 - asserted_fixture_value
- **claim:** a lib test asserted the exact UTF-8 error text of the Dart runtime.
- **status:** accepted - fixed: asserts the finding kind, not the runtime's message.

### S1-11 - P3 - asserted_fixture_value
- **claim:** surviving mutants of the first 47: lookalike indent, fence indent, closer with text, normalisation of digits and underscores, sort by file only, the three index terminators without trim.
- **status:** accepted - fixed: 25 more mutants (N01 to N25) written and reddened; see the mutation section.

## Seat S2 - the renumber, citations, docs and registries (0 P0, 0 P1, 0 P2, 6 P3)

### S2-1 - P3 - writer_reader_drift
- **file:line:** docs/plans/spawn-tests-env-and-stderr.md:12
- **claim:** the repointed line still said the number was duplicated and cited by title, which this change makes false, and kept a `:254` anchor.
- **status:** accepted - fixed: clause and anchor dropped.

### S2-2 - P3 - writer_reader_drift
- **file:line:** docs/superpowers/plans/2026-09-24-oi126-training-day-predicate-unification.md:26
- **claim:** a plan-review line cites the old id and was missing from the legacy map.
- **status:** accepted - fixed: listed in the legacy map (historical record, not rewritten).

### S2-3 - P3 - writer_reader_drift
- **file:line:** .claude/skills/debugging/SKILL.md Changelog
- **claim:** "second class" and "fewer citations" wording did not say which class of a pair kept the number.
- **status:** accepted - fixed: "fewer citation lines", "tie kept the earlier class", "the other class of each pair".

### S2-4 - P3 - writer_reader_drift
- **claim:** the two family citations (bare "2.54" in `spawn-tests-pr2-migrate-remaining.md:135`, the `(§2.40 family)` line in bug-classes.md) were described as repointed without saying they name both classes or neither.
- **status:** accepted - fixed in the legacy map notes.

### S2-5 - P3 - asserted_fixture_value
- **claim:** the diagnose doc's forbidden-pattern scope for `existsSync` was unstated (the e2e test file uses it on purpose).
- **status:** accepted - fixed: the pattern comment says which two files it covers.

### S2-6 - P3 - asserted_fixture_value
- **claim:** the grep example in the bug-classes.md header matched a trailing-space heading differently from the gate.
- **status:** accepted - fixed: the example carries the trailing space and says why.

S2 confirmed with commands: no citation of a moved class by its old id remains outside the dated historical carve-outs; the
legacy map matches `git log -S` introduction dates; the two new `docs/blast_radius.yaml` globs sit above `scripts/**`
(first match wins) and every changed path classifies platform; the OI-167 closure has the shape the `closes-oi` gates read;
`docs/naming_conventions.md` rows are inside the glossary table; no hook, workflow or script `.sh` is touched; no scratch,
`.env`, log or `*.orig` file is staged; no credential-shaped literal in the diff.

## Mutation evidence (rule 21, run by the author, not by the seats)

72 mutants, each applied with an exact-one-match assertion before the write, the three test files run, the sources restored
and their sha256 re-checked. Run 1 (47 mutants) ran before the fixes above and was all red. Run 2 on the final code added
N01 to N25 and left two not proving: M06 (a compile error in the harness anchor, counted red by a failed-count heuristic) and
M09 (a CRLF heading with a title parses without the carriage-return strip, so the strip was unproven). M09 now has a
title-less CRLF heading assertion; both are red on the rerun (10 and 1 failed tests). The table is in the gate ledger entry.

## Tuning entry

- **2026-10-25** - blast-radius platform - 17 findings; 0 false_alarm; tuning: lens 6 (guard_without_its_mirror) gains one question for any parser guard: "give the guard's input a TITLE-LESS, an INDENTED and a CRLF variant - which of them does the guard still see?" - two of S1's P2/P3 findings (an indented heading, a heading with no title) and the author's own M09 were the same blind spot: every fixture carried a title and no indent, so deleting the strip or the indent allowance changed nothing a test could see. Lens 8 gains: a mutation harness that counts a COMPILE ERROR as red (failed tests = everything) proves nothing - read the status word, not the failed count.
