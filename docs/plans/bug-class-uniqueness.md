---
plan: bug-class-uniqueness
revision: 3
date: 2026-10-25
base: b0735bb1
blast_radius: platform   # decided in section 7: the gate and its lib get two platform globs, like the OI twin (blast_radius.yaml:294-295)
tier: M
execution_mode: inline   # one worktree, one branch (bug-class-uniqueness)
closes_oi: [OI-167]
parent_plan: docs/plans/merge-conflict-treadmill.md   # landing B of A0, A1, A2, B, C, D; OI-309 stays OPEN until D
commit_type: feat(gates)   # NOT fix(...): no diagnose-doc is owed (rule 22 keys on the fix/bug/regression prefix)
---

# Landing B: bug-class numbers become unique, and a gate keeps them so

## Revision history
- **build notes (2026-10-25, after rev 3):** the B-pass (two fresh seats, 17 findings, no P0 or P1) changed the built gate beyond the rev 3 text,
  all fixed in the batch and pinned by tests and mutants (docs/reviews, the review file that lands with the commit):
  - a heading indented one to three spaces is a lookalike finding (it was invisible: a false pass);
  - an unclosed code fence is a finding in either file; HTML comments are NOT modelled (a heading inside one counts, which fails closed);
  - the numeric-heading-in-SKILL.md rule applies to major 2 only (a `### 5.1` sub-section is not a bug class);
  - titles are compared by their letters and digits of any script, not `[a-z0-9]`; a line separator inside a title no longer stops the parse;
  - a separator row may use one or two dashes; a row needs four cells, with or without the trailing bar;
  - a parse that finds nothing prints the findings that explain it first; a missing file names the root; no `next free id: null`;
  - the boundary of the 16-character rule is pinned (the 16th character is compared, the 17th is not);
  - docs: `--next` prints after a build banner on some toolchains (the id is the last line of stdout); the legacy map names the oi126
    plan-review line; the family citation reads clearly; one false clause in `spawn-tests-env-and-stderr.md` was dropped.
- **rev 2 → rev 3 (round 2, two reviewers: R2-A ground truth and completeness, R2-B design by simulation; both CONVERGED with no P0/P1; 4 + 18 P2 and 11 + several P3 items folded).** R2-A's items:
  - **Pairing (R2A-1):** check 6 pairs only ids that occur exactly once in each file (duplicates are check 1's job; a map keyed by id
    would otherwise collapse them); the baseline expectation is "nine duplicate ids plus the 2.93 pairing finding".
  - **Stale text (R2A-2, R2A-10):** no "test 18" remains in the body (the "Test 18 / M12" in the entry below is rev 1's numbering); the skill
    files hold 18 citation lines of which 10 are repointed; only the "UNRENUMBERED / duplicated on purpose" statement of the
    bug-classes.md header goes false, the `tail -1` recipe is superseded, not false.
  - **Live conflict (R2A-3):** `sync-storm-first-sweep` has staged +5 rows at the END of the naming-conventions glossary table, and
    both batches add a SKILL.md index row at the end of the TABLE (not EOF) and a Changelog entry at EOF. The two glossary rows go
    mid-table, and the rebuild rule covers textual conflicts at the shared append points (section 7).
  - **Recipe (R2A-4):** the renumber script and the rebuild steps are written inline (sections 6 and 7).
  - **Table and wording (R2A-5, R2A-6, R2A-7, R2A-13, R2A-14, R2A-15):** 53B is 7 lines; d2b9e6:80 is assigned by the dated rule; the
    sentence at `spawn-tests-pr2-migrate-remaining.md:135` cites BOTH 2.54 classes; the noise explanation is exact; the two blast-radius
    globs go above `scripts/**`; "1 of 131" is "1 of the 131 heading/row pairs (122 distinct ids)".
  - **IO, ledger, residuals (R2A-8, R2A-9, R2A-11, R2A-12):** `FormatException` is caught beside `FileSystemException`; the ledger evidence is a
    single-line quoted string; the working-tree-versus-staged residual is listed; the plan-review record carries the commit-type, closure
    ledger and no-soak rationales.
  R2-B's items:
  - **Default root untested (B1):** three spawn shapes (cwd only, `--root` only, `--root` pointing at an empty dir) and two mutants.
  - **Wiring (B2, B6):** `check(bugClassesText, skillText)` returns findings with file and line, so lookalike detection covers both
    files; every rule has an e2e fixture per file.
  - **Title pairing (B3, B5, B10, B13):** the row title is cell 2 of the `|` split; an EMPTY normalized title is a finding; the strip
    clause and the build-time fallback are deleted (both were dead); the marker sits at the end of the title cell.
  - **Fixtures that reach the mutants (B7, B8, B9, B15):** fence fixtures with a column-0 heading inside an indented fence and a wrong
    closer; the zero guard is ONE combined guard with a both-empty fixture; `--next` fixtures with the max only in rows / only in
    headings; literal 1-based line numbers; `2.05` vs `2.5`.
  - **Cut (B14, unit size):** the BOM clause and its mutant (both files start with `#` / `---`, a BOM can never change a result),
    mutant M27 (union of two others).
  - **Mutants (B12):** the consistent swap in both files (only the pair pin in test 16 kills it) and "wrong class of a pair moved"
    (only the red-flag keyword in test 17 kills it).
  - **Baseline proof (B4):** the base reports nine duplicate ids (18 lines) PLUS the 2.93 title mismatch, which the same commit aligns.
  - **Rebuild and pins (B11):** one table constant drives the throwaway rebuild script, tests 16 and 17, the legacy map and the ledger
    evidence; the tests say that retiring or rewording a pinned class means editing the table.
  - **Process (B16, B17, B18):** the glossary section is decided; the §4.11 deviation (no 24 h `--warn-only` soak, because pre-commit
    runs every gate with no arguments and a gate-first commit could not pass its own pre-commit) is stated for the founder; a full-template
    diagnose doc is written because OI-167 is a recurrence-class defect.
- **rev 1 → rev 2 (round 1, three reviewers: ground truth, citation completeness, design attack; all three HARDEN, none REWORK).** Folded:
  - **Census scope (R1A-F1, R1B-F1, R1C-1, P1):** rev 1 never searched the skill's own two files. They hold 18 citation lines (SKILL.md
    270-278, 353, 363; bug-classes.md 274, 452, 455, 1181, 1636, 1749, 1858), 10 of which follow a moved class. The repoint set is now
    **18 lines in 9 files** (section 0).
  - **Decision rule (R1A-F2, P1):** counted per LINE with the in-skill citations, 2.37 and 2.40 are TIES. The tie goes to the class
    introduced EARLIER in git (the June 2026 classes), because an older record can only mean it. The moved set does not change.
  - **Collision (R1B-F4):** the live session `sync-storm-first-sweep` has STAGED `### 2.123` and `### 2.124` in both files. Moved
    classes start at **2.125** (section 1).
  - **Test 18 / M12 of rev 1 (R1B-F3, R1A-F4, R1C-2):** keyed on the legacy marker with the exact old→new mapping pinned in BOTH files; M12
    split in three. A permanent cross-file title-prefix check enters the gate (section 3).
  - **Parser and `--next` (R1C-5):** lookalike lines are findings, major 2 is pinned, `--next` has defined failure behaviour.
  - **Test adequacy (R1C-4):** 14 mutants added, tests 14 and 17 made observable, fixtures in the real disorder, exact streams and
    exit codes pinned.
  - **Docs (R1B-F5, R1A-F3, R1C-6):** the bug-classes.md header (lines 3-9) and SKILL.md:87 go stale and are rewritten; the legacy map
    moves to the bug-classes.md header with one pointer in SKILL.md; one marker template for all nine.
  - **Repo seams (R1A-F5, R1C-7):** `runSpawn`, `@Timeout` + `library;`, no `existsSync`, no `Platform.environment`, root = cwd with
    `--root=<dir>`.
  - **Process (R1A-F6, R1C-9, R1B-F10):** blast radius decided (platform); closure ledger, commit type, naming glossary, worktree
    retirement, the §4.11 baseline statement and the OI-167 deviation are stated.
  - **Wording (R1A-F7/F8/F9, R1B-F7/F8/F9, R1C-3/8):** the §4.9 row is CLAUDE.md:262 and "second to last"; the title-mismatch count is
    method-dependent; the CI claim is narrowed; the parent plan's "from 2.114" is superseded.

## 0. Evidence (measured 2026-10-25 on base b0735bb1)

- The bug-class bodies live in `.claude/skills/debugging/bug-classes.md` (`### 2.N Title`, 131 headings, max **2.122**, all major 2).
  The index is one table in `.claude/skills/debugging/SKILL.md` under `### Bug-class index` (line 112; rows 116-246, 131 rows; a blank
  line at 247, a `---` rule at 248, `## 3.` at 250). The id SETS are equal. **Nine ids are used twice in BOTH files:** 2.36, 2.37, 2.38,
  2.39, 2.40, 2.41, 2.53, 2.54, 2.55 (the duplicate rows are SKILL.md 134-142, 160-165 and 179-181).
  Reproduce: `grep -oE '^### 2\.[0-9]+' .claude/skills/debugging/bug-classes.md | grep -oE '[0-9]+$' | sort -n | uniq -d`.
- Nothing gates their NUMBERS (the size budget and the euphemism sweep read SKILL.md, nothing reads the ids).
  `scripts/check_oi_numbering_unique.dart` does the job for OI numbers. CLAUDE.md:262 (the §4.9 row about shared self-numbered files)
  names the manual recipe. The pre-commit loop (`for GATE in scripts/check_*.dart`, no staged-file filter) and the CI `audit-gates` job
  (`.github/workflows/test.yml:326-331`) run EVERY `scripts/check_*.dart`; neither case-skip list names the new file;
  `check_gate_scripts_wired.dart` infers it from the loop. No workflow, hook or allow-list edit.
- Root cause 3 of OI-309: the next number is "max + 1" read by eye. The recorded failure: `tail -1` returns the last-POSITIONED entry
  (2.61 minted twice on 2026-09-07).
- **Citations of the nine, read one by one** (counted as distinct LINES in non-historical tracked files: md, dart, ts, yaml, sh, sql,
  including BOTH skill files; `assets/` hits are SVG path coordinates, `backups/` hits are the "multiply by 2.54" prompt text, version strings such as
  `supabase-js 2.39.3` and `git 2.53` sit in docs/ and scripts/, JSON and txt hits are the same; all were checked for real citations: none). Excluded as HISTORICAL records this batch must not rewrite: `docs/reviews/`,
  `docs/plan-reviews/`, `docs/audit/*closure*`, `.claude/skills/code-review/tuning-history.md` (frozen), the OI-167 entry,
  `docs/plans/auth-recovery-code-length.md:221` (a statement about the SET).

| id | class A (earlier position) | class B (later position) | citation lines A | citation lines B | decision |
|---|---|---|---|---|---|
| 2.36 | `DROP`+`CREATE` resets a SECURITY DEFINER ACL (bug-classes.md:151; git 2026-08-21) | PostgREST builder is a thenable, no `.catch()` (:433; 2026-06-13) | 47de4f diagnose:45, `sot_registry.yaml:5336`, `158_referral_referrer_cap.sql:71`, `oi320-referrer-cap.md:40`, bug-classes.md:1858, SKILL.md:274 (6) | none (0) | keep A, **move B** |
| 2.37 | a positive grep cannot see a defect in an ARGUMENT (:176; 2026-08-21) | platform-only native init unguarded by `kIsWeb` (:439; 2026-06-13) | `oi150-phase-delta.md:308`, `oi126-...unification.md:23`, SKILL.md:270, bug-classes.md:1636, :1749 (5) | `open_issues.md:3416`, d8f3a2 diagnose:83, `unit3-web-ux.md:87`, bug-classes.md:452, :455 (5) | TIE → earlier in git: keep B, **move A** |
| 2.38 | verify one layer FURTHER (:193; 2026-08-21) | cross-user read vs own-only RLS (:445; 2026-06-13) | SKILL.md:271 (1) | ADR 0016:137, handbook `edge-function-user-token-auth.md:97` (2) | keep B, **move A** |
| 2.39 | a mutation set of only "delete the protection" is half a proof (:208; 2026-08-21) | native-only plugin reachable on web (:451; 2026-06-14) | `oi150-phase-delta.md:313`, write-durability spec:258, SKILL.md:272, bug-classes.md:1636 (4) | d8f3a2:83 (1) | keep A, **move B** |
| 2.40 | mutation-proving in the SHARED worktree (:243; 2026-08-21) | fabricated default persisted into a field a different path consumes (:457; 2026-06-14) | `oi150-phase-delta.md:330`, SKILL.md:275 (2) | c3f2d8 diagnose:107,163 (2) | TIE → earlier in git: keep B, **move A** |
| 2.41 | the mutation was ABSORBED (:223; 2026-08-21) | cross-migration NOT-NULL writer drift (:463; 2026-06-16) | 321062 diagnose:147, `profile_target_recompute_test.dart:212`, `progress_restore_monotonic_behavioral_test.dart:588,751`, write-durability plan:1347, `memory/project_fob3_coach_hold_block_2026_08_21.md:32`, SKILL.md:273 (7) | none (0) | keep A, **move B** |
| 2.53 | the Nth fix to one file, each a WIDER GUESS (:255; 2026-08-27) | a MIRROR harness stops modelling production (:627; 2026-08-28) | `spawn-tests-env-and-stderr.md:12`, `progress-photos-pro-server-rule.md:52`, e6c4a9 diagnose:40, SKILL.md:276 (4) | capability plan:19,84, capability spec:104, `profile_target_recompute.dart:69`, `query_v4_mirror.dart:99`, write-durability plan:653, SKILL.md:363 (7) | keep B, **move A** |
| 2.54 | a mutation test that passes in BOTH arms proved nothing (:277; 2026-08-27) | an invariant GREEN while the thing it protects is broken (:652; 2026-08-28) | `oi150-phase-delta.md:313`, write-durability spec:258, write-durability plan:1404, `spawn-tests-pr2-migrate-remaining.md:89`, SKILL.md:277 (5) | SKILL.md:363 (1); `spawn-tests-pr2-migrate-remaining.md:135` ("a guard satisfied by a mention") fits both and is rewritten to cite both | keep A, **move B** |
| 2.55 | your own "quick checks" are load (:294; 2026-08-27) | a deliberately SCOPED capability wired to an UNSCOPED surface (:673; 2026-08-28) | write-durability plan:23, `spawn-tests-pr2-migrate-remaining.md:58,125`, SKILL.md:278 (4) | SKILL.md:353 (1) | keep A, **move B** |

Rule used, stated so it can be checked: the number stays with the class that has MORE citation lines; a tie keeps the class
introduced EARLIER in git (`git log -S '<heading>'`), because a record written before the later class existed can only mean the
earlier one. **Moved: 36B, 37A, 38A, 39B, 40A, 41B, 53A, 54B, 55B.**

Citation lines that follow a MOVED class and are repointed (**18 lines in 9 files**):
- external, 8 lines in 7 files (`pr2:135` cites BOTH 2.54 classes after the edit; the other seven follow one class): `oi150-phase-delta.md:308` (37A) and `:330` (40A); the oi126 plan `:23` (37A); d8f3a2 diagnose `:83` (39B; its
  "§2.37" is B and stays); `spawn-tests-env-and-stderr.md:12`, `progress-photos-pro-server-rule.md:52`, e6c4a9 diagnose `:40` (53A);
  `spawn-tests-pr2-migrate-remaining.md:135` (54B);
- SKILL.md, 6 lines: `:270` (37A), `:271` (38A), `:275` (40A), `:276` (53A), and the Changelog lines `:353` (55B) and `:363` (54B; its 53B part stays);
- bug-classes.md, 4 lines: `:1636` (37A), `:1749` (37A), and two lines with a family citation of unresolvable class:
  `:1181` ("§2.53/§2.54/§2.63/§2.65 (bad-news-vs-no-news family)": cite BOTH classes of 2.53 and of 2.54) and `:274`
  ("reach for the behavioural test FIRST (§2.40 family)": neither 2.40 class says that; the parenthetical is DELETED, which also keeps
  the 2.40 decision independent of that line). `:1749`'s bare "2.54" cites both 2.54 classes.

Cited but NOT repointed: `docs/diagnoses/2026-06-13-referral-rls-context-d2b9e6.md:80` ("2.36 (FunctionException not unpacked ->
masked errors)": its parenthetical matches neither class title, so no repoint can be verified; the dated rule assigns it to the June
class, now 2.125, and the legacy map says so), the OI-89 records dated 2026-08-28
(`docs/plan-reviews/oi89-bodyweight-floor.md:113`, `docs/audit/oi89-bodyweight-floor.closure.yaml:145-146`, which mean the 53B/54B pair) and
every other review, plan-review, closure ledger and tuning-archive line.

## 1. Decision

A strict uniqueness gate over the two files, a one-time renumber of the nine moved classes, and a legacy map. Not chosen:

- **An allocator (`mint_bug_class.sh`) or title-keyed ids** (OI-167's recorded recommendation: key on the title, the number an optional alias).
  Over 100 documents cite classes by NUMBER and the title is a sentence that gets reworded; rewriting the citations to titles is the
  larger edit and the less stable key. The renumber keeps numbers as the key and the map bridges the old citations. An allocator is a
  network-reserving script with a new offline failure mode; revisit only if the gate fires more than once.
- **A grandfather list for the nine.** It would leave 18 classes answering to 9 numbers, which is the defect OI-167 records.
- **Rewriting historical records.** Reviews, plan reviews, closure ledgers and the frozen tuning archive keep their text.

**New ids.** Moved classes take the ids above the highest id found on `origin/main` AND in every local worktree's skill files, in
old-id order, recomputed at the final rebuild. At this base `origin/main` holds 2.122, and the live session `sync-storm-first-sweep`
has staged 2.123 and 2.124, so the targets are **2.125 to 2.133**: 36B→2.125, 37A→2.126, 38A→2.127, 39B→2.128, 40A→2.129,
41B→2.130, 53A→2.131, 54B→2.132, 55B→2.133. Whichever of the two batches merges first, the other needs no renumber: this batch edits
headings and rows IN PLACE (middle of both files), the other appends at the end. If more ids appear before the push, shift by the same
rule and say so in the commit.

**Marker.** Every moved heading, and the END OF THE TITLE CELL of every moved index row, carries `(was 2.N; renumbered 2026-10-25)`
(headings that already end in `(NEW date)` keep it first). The parser reads only the leading id and a 16-character title prefix, so the
marker is inert.

## 2. Writers and readers (§4.1)

- **Writers:** a human or agent appends a `### 2.N` heading to `bug-classes.md` and one row to the SKILL.md index (SKILL.md section 5,
  rule 1, `SKILL.md:314`; the warning block `SKILL.md:89-110`; the header `bug-classes.md:3-9`).
- **Readers:** (a) every document that cites a class by number (section 0); (b) the new gate; (c) the pre-commit loop and the CI
  `audit-gates` job. Other readers of the two files by path: `check_context_artifact_budget.dart:55` (SKILL.md only; baseline 71,782 B,
  now 72,142 B, soft band 15%), `check_no_deferral_euphemism.dart:145-160` (sweeps both in full; the plan and the new prose carry
  none of the 22 phrases), `check_analyze_narrower_than_lib_in_tooling.dart` (scans `.claude/skills/**/*.md`). None parses headings,
  counts rows or pins an id (re-verified by two reviewers).
- **Drift seen:** the same number twice (the nine); in-skill citations that follow a class when it moves (section 0).

## 3. The gate

Files: `scripts/bug_class_ids_lib.dart` (pure, no IO) and `scripts/check_bug_class_numbers_unique.dart` (IO and exit codes). No
`// Gate: N` line (rule 24). No `File(...).existsSync()` (the added-line gate `check_gate_existssync_file_vs_dir.dart` would block it):
read with `readAsStringSync` inside `try`, catching `FileSystemException` AND `FormatException` (invalid UTF-8). No `Platform.environment` read (the spawn env manifest test).

**Lib (pure):**
- `parseHeadings(text)`: lines matching `^### (\d+)\.(\d+)(?: (.*))?$` after stripping a trailing `\r` (CR handling is live on a Windows
  checkout; there is NO BOM clause: line 1 of both files is `# Debugging...` / `---`, never a heading or row, so a BOM could not change a
  result); fence-aware (a line with up to three spaces of indent then at least three backticks or tildes opens; the closer must use the
  same character and at least the opener's length; four spaces of indent is not a fence; an unclosed fence runs to EOF). Numbers are
  read with `int.tryParse`; an id that does not parse is a finding, never an exception. Returns id, title, 1-based line.
  `### 2.5.archived-2026-01-01` is NOT an id (SKILL.md section 5 shape); `#### 2.7` is not an id.
- `lookalikes(text)`: any line outside a fence matching `^#{1,6}\s*\d+\.\d+` that `parseHeadings` does not accept and that is not the
  `.archived-` shape (for example `### 2.124: Title`, `###2.124`, `##### 2.124`, `### 2.7x`) is a finding, so an unparsed class cannot
  hide. A numbered sub-heading inside a class body (`#### 2.4 ...`) is therefore a finding BY DESIGN (there are none today).
- `parseIndexRows(text)`: the rows of the table under the line that starts `### Bug-class index`, up to the next line starting `## ` or
  `### ` or a `---` rule. A row line is split on `|`; cell 1 must match `^\s*(\d+)\.(\d+)\s*$`, **cell 2 (trimmed) is the title**; a row line
  with fewer than four cells is a finding. Same fence handling. Returns null when the `### Bug-class index` line is absent.
- `check(bugClassesText, skillText)` returns findings, each with a file, a 1-based line and a message:
  1. an id used more than once in headings (every line), or more than once in rows (every line); ids compare as integer pairs, so
     `2.05` and `2.5` are the same id;
  2. a heading id with no row, a row id with no heading;
  3. an id whose major is not 2 (headings or rows);
  4. a numeric `### N.M` heading found in SKILL.md (a body appended to the wrong file);
  5. lookalike lines, run on BOTH texts;
  6. **title pairing:** only an id that occurs exactly ONCE in each file is paired (a duplicated id is check 1's finding and is not
     paired, so a map keyed by id cannot collapse it into spurious findings). Both titles are normalized (lowercase, keep only `[a-z0-9]`); an EMPTY normalized title on either side is a finding; otherwise the first
     `min(16, shorter length)` characters must be equal, a difference is a finding (an id attached to a different class in the two
     files). Measured on the base: 1 of the 131 heading/row pairs (122 distinct ids) differs under this rule (2.93), 3 under a 30-character case-insensitive prefix without
     alphanumeric normalization (2.93, 2.102, 2.118); the build aligns the 2.93 index row in the same commit.
- `compareIds` / `nextFreeId`: numeric on both parts (`2.9 < 2.10 < 2.100`), never lexical, never positional; leading zeros parse to the
  same pair; next free = `2.<highest minor over the UNION of both files' ids + 1>`.

**Gate:**
- Root: `--root=<dir>` if given (the test seam; equals form like `check_cqrs_query_naming.dart`), else `Directory.current` (the repo idiom
  of 25 gates; run from the repo root by the hook and CI). The PASS line prints the resolved absolute root so a run against the wrong
  tree is visible.
- Reads `<root>/.claude/skills/debugging/bug-classes.md` and `<root>/.claude/skills/debugging/SKILL.md` as UTF-8 (`readAsStringSync`);
  invalid UTF-8 (`FormatException`) is a failure with the reason, exit 1, never an uncaught exception.
- **Streams and exit codes (pinned):** PASS prints one line to stdout `PASS bug-class numbers unique (headings=<n> rows=<n>, root=<abs>)`
  and exits 0. Findings go to stderr, one per line, as `<repo-relative path>:<line>: <message>`, ending with
  `next free id: 2.<N>`; exit 1. A missing/unreadable file, a missing index section, or **no headings or no rows (ONE combined guard)** →
  exit 1 with the reason (a vacuous parse must not PASS). Unknown arguments → exit 2. A failure never prints `PASS`.
- `--next`: prints only `2.<N>` to stdout and exits 0 when both files are readable and the union is non-empty; findings, if any, are
  still printed to stderr in the normal format and do NOT change the exit code; exits 1 on missing input, a missing index section or an
  empty union.
- No git access, no network, so no fail-open case. Cuts both ways: a duplicate that reaches a tree through a merge blocks every commit
  in that tree for a defect the committer did not cause; the finding text names the ids and `next free id`, so the repair is one commit.

**Where it runs:** pre-commit (loop; `pre-commit.sh:392` discards the output, only the exit code matters locally) and CI `audit-gates`
(loop; on the PR merge ref and on `main` pushes; the output is in the job log). A clean auto-merge runs only `pre-merge-commit.sh`, not
the loop: the first local run after such a merge is the next commit (in practice bug-classes.md gains headings at EOF and SKILL.md gains a row at the end of the TABLE, so two new classes usually
conflict textually and are resolved in a manual commit, which does run the loop) or CI. No hook, no workflow change: no hook reinstall on
either machine, no `workflow` token scope.

## 4. Docs edits

- `bug-classes.md` header (lines 3-9; "UNRENUMBERED, nine numbers are duplicated on purpose" is false after the landing and the `tail -1`
  recipe is superseded): rewritten to "ids are unique and gated; get the
  next with `dart run scripts/check_bug_class_numbers_unique.dart --next`; no-Dart fallback `grep ... | sort -n | tail -1`", and it now
  carries the **legacy map**: the nine pairs (old id → kept class / moved class and new id), the dated rule ("a record before
  2026-08-21 citing 2.36-2.41 means the June class; for 2.53-2.55 a record before 2026-08-28 can only mean the 2026-08-27 class; after
  that, read the sentence"), and the unresolved citations of section 0.
- `SKILL.md`: the warning block (89-110) is replaced by a short statement and a pointer to that header; line 87 ("verbatim and
  unrenumbered") is corrected; the 4 red-flag citations and 2 Changelog citations of section 0 are repointed; section 5 rule 1 gains
  "run the gate before the commit"; a Changelog entry for this batch is added (every prior self-evolution batch has one).
- Nine moved headings and nine moved rows are renumbered in place (position unchanged) with the marker; the 18 citation lines are repointed.
- **Index row for 2.93** is aligned with its heading (the one title pairing difference on the base, section 3).
- OI-167: closed by `closes-oi: OI-167` and archived to `docs/audit/closed_issues.md` (convention of commit 2b88e7c2). OI-309 stays OPEN;
  its Blocked-on line gets one progress sentence ("A0, A1, A2 merged; B is in this PR; C and D remain"). The parent plan's
  lines 82 and 389 ("from 2.114") get a "superseded by docs/plans/bug-class-uniqueness.md" note.
- No CLAUDE.md edit (L tier avoided; CLAUDE.md:262 stays true and now has a gate behind it).
- `docs/naming_conventions.md` section 8 (Reserved domain glossary, a table with `gate` and `site guard` rows) gets two rows: "bug-class
  id" and "legacy map" (§4.7), inserted MID-table next to the `gate` rows, not at the table end where `sync-storm-first-sweep` has
  staged five rows.
- `docs/diagnoses/2026-10-25-bug-class-number-collisions-<id>.md`: the FULL template, because OI-167 is a recurrence-class defect (2.61 minted
  twice on 2026-09-07, six OI-number collisions by 2026-08-16); the `feat(gates)` prefix does not require it, the §4.1/§4.1.5 discipline does.
- `docs/audit/gate_test_ledger.yaml` gets the `mutation_proven: true` entry. Its `evidence:` is ONE single-line quoted string (the parser
  reads every continuation line as `key: value`; a line starting with `- ` becomes a `test_path`, and a `test_path` / `evidence` /
  `mutation_proven` key inside the text re-keys the entry); `docs/audit/GATE_INDEX.md` is regenerated by pre-commit.

## 5. Tests and mutation plan (CLAUDE.md rules 21 and 24)

All spawns go through `test/helpers/spawn.dart` (`runSpawn(..., why:)`; `spawn_sites_guard_test.dart` bans raw `Process.run` in tests);
each file has `@Timeout` and `library;`. Expectations are exact literals (`expect(r.exitCode, 1)`: the ledger gate's red-path regex is
`exitCode,\s*(1|2|isNot\(0\)|...)`). Line numbers in findings are asserted as literal 1-based numbers.

`test/scripts/bug_class_ids_lib_test.dart` (pure):
1. heading shapes: with/without title; `### 2.5.archived-...` is neither an id nor a lookalike; `#### 2.7`, `### 2.7x`, `### 2.124: T`,
   `###2.124` are not ids (the last three are lookalike findings); `2.05` and `2.5` are one id (a duplicate); a 40-digit number is a
   finding, not an exception;
2. fences: backtick and tilde; opener indented two spaces with a COLUMN-0 `### 2.9` inside (kills "column-0 fences only"); the wrong
   closer: `` ```\n~~~\n### 2.9\n```\n### 2.1 `` yields only 2.1 (kills "any closer closes"); a shorter closer does not close; an
   unclosed fence swallows the rest; four spaces of indent is not a fence; a lookalike inside a fence is ignored;
3. CRLF equals LF;
4. duplicates: two, three, rows only, both files; every duplicate line is reported (literal numbers), not only the first;
5. set difference in BOTH directions;
6. ordering in the real disorder (2.61 at line 548 and 2.62 at 578 above 2.56-2.60 at 700-987; the A copies of 2.53-2.55 before the B
   copies): a fixture that ENDS on a lower id than its maximum (kills positional "last"); `[2.9, 2.10, 2.100]` (kills lexical);
7. index section bounds: a stray row after the `---` rule, after a `## ` heading and after a `### ` heading is NOT read (one fixture per
   terminator); a missing section returns null; `|2.5|` without spaces parses; a row with fewer than four cells is a finding;
8. next free id: with a gap, with the max only in rows, with the max only in headings;
9. lookalikes per file; a non-2 major (`### 3.1`, `| 3.1 |`) is a finding; a numeric `### 2.5 X` heading in SKILL.md text is a finding;
10. title pairing: equal; case-only and punctuation-only differences pass; a different class under the same id is a finding; an empty
    title on either side is a finding; a title shorter than 16 characters that is a prefix of the other side passes; two different
    short titles are a finding; an id duplicated in either file is not paired.

`test/scripts/bug_class_numbers_gate_e2e_test.dart` (real gate; fixtures in a temp dir):
11. clean fixture: exit 0, stdout is the `PASS` line with `headings=` and `rows=`, stderr is empty;
12. one fixture per finding kind, PER FILE where the rule applies: duplicate heading; duplicate row; heading without row; row without
    heading; major 3 (heading and row); lookalike (in bug-classes.md and in SKILL.md); numeric `### N.M` heading in SKILL.md; title
    pairing mismatch; each exits 1, names the id and `path:line`, ends with `next free id:`, and stdout does NOT contain `PASS`;
13. input guards: either file missing → exit 1; the index section absent (zero headings) → exit 1 with the "index section" reason, a
    different message from "heading has no row"; **both-empty with the index section present and a header-only table** → exit 1 with
    the no-headings-or-rows reason (the only fixture that reaches the combined guard);
14. `--next`: prints the number, exit 0; max only in rows; max only in headings; with findings present stdout holds only the number and
    stderr holds the findings; exit 1 on missing input and on an empty union; a bad argument exits 2;
15. root resolution, three shapes: (a) cwd = fixture, no `--root` → PASS; (b) cwd = an empty dir, `--root=<fixture>` → PASS; (c) cwd =
    fixture, `--root=<empty dir>` → exit 1. Plus the REAL tree (cwd = repo root): exit 0, the PASS line's counts are equal and above 100;
16. **renumber outcome pins** (real files, parse-based, keyed on the marker): ONE table constant `kRenumberTable` (old id, keyword,
    new id) at the top of the file, shared with test 17; exactly nine parsed headings and nine parsed rows carry the marker; each
    (old N, new id) pair equals the table in BOTH files; each old N is held by exactly one other heading and one other row; new ids
    strictly increase in old-id order; the normalized 16-character title prefix of each moved heading equals that of its row. A header
    comment says: retiring or rewording a pinned class means editing the table;
17. **citation pins** (real files): for ONLY the nine `See §2.N` red flags in SKILL.md section 3, N resolves to a heading whose title
    contains the table's keyword (`positive grep`, `FURTHER`, `half a proof`, `ABSORBED`, `DROP`, `SHARED worktree`, `Nth fix`,
    `BOTH arms`, `quick checks`) AND the keyword is absent from the pair's other class title; the 18 repointed lines contain the new ids
    (anchor strings, not line numbers) and no longer contain the old pointer.

Mutants (each applied and confirmed with `grep -c`, run, restored; for the real docs restore on EXIT with a trap and `git diff --stat`
empty after each, bug class 2.40): M1 dedupe headings through a `Set`; M2 lexical max; M3 positional last; M4 skip heading-without-row;
M5 skip row-without-heading; M6 drop fence handling; M7 fences recognised at column 0 only; M8 any closer closes; M9 drop CR strip; M10
parse rows from the whole file; M11 drop the `---` terminator; M12 drop the `## ` terminator; M13 drop the `### ` terminator; M14 null index
section treated as an empty set; M15 missing file returns PASS; M16 exit 0 on findings; M17 print `PASS` on failure; M18 swap
stdout/stderr; M19 `.archived-` parsed as an id; M20 `--next` from headings only; M21 `--next` from rows only; M22 drop the combined
zero guard; M23 drop lookalike reporting for one file; M24 drop the major-2 pin; M25 drop the title pairing; M26 `min(16, x)` replaced by
16; M27 row title always empty; M28 report only the first duplicate line, or 0-based lines; M29 ignore `--root`; M30 ignore the cwd
default; M31 swap two moved ids in headings only; M32 in rows only; M33 swap them consistently in BOTH files (only the pair pin in
test 16 kills it); M34 move the wrong class of a pair (36: A instead of B; only the red-flag keyword in test 17 kills it); M35 leave one
red-flag citation unrepointed; M36 drop the empty-title finding; M37 let a huge number throw. Evidence goes in the ledger entry.

## 6. Verification before review dispatch (§4.12.8)

`flutter analyze --no-fatal-infos` (whole project), `TZ=Asia/Kolkata flutter test --exclude-tags golden` (full), `sh scripts/pre-commit.sh`
or the commit attempt; also `dart run scripts/check_gate_scripts_wired.dart`, `check_gate_test_ledger.dart`,
`check_context_artifact_budget.dart`, `check_gate_existssync_file_vs_dir.dart`, and a hand grep: after the edits, grep BOTH skill files and
every file of section 0 for each of the nine OLD ids and read every hit.

**Baseline proof (§4.11).** The gate is run on the base files (`git show b0735bb1:<path>` into a temp root). It must report the nine
duplicate ids (18 lines: 9 headings, 9 rows) plus the 2.93 title mismatch, which the same commit aligns; the output goes in the ledger
evidence. **Deviation, stated for the founder:** §4.11 asks for a 24 h `--warn-only` soak before a gate hard-fails. A gate-first commit
cannot pass its own pre-commit (the loop runs every gate with no arguments and the nine duplicates exist), so the gate and the clearing
renumber land in ONE commit; the gate reads two files and has no environmental input, so the soak would measure nothing.

**Rebuild script.** The renumber is applied by a throwaway python script in the scratchpad (not committed), driven by ONE table (old id,
class, new id, keyword). It starts from the BASE copies of the two skill files and the 7 external files (`git show b0735bb1:<path>`),
renames the 9 headings and 9 rows by anchored replacement, rewrites the 18 citation lines, and ASSERTS exactly one match per
replacement (an anchor miss aborts before any write; compute first, then write). The hand-written parts (header, legacy map, SKILL.md
prose, Changelog) are separate hunks the script does not touch. The same table is the constant in tests 16 and 17, the legacy map and the ledger evidence; the final-rebuild shift
edits the table and re-runs the script.

## 7. Landing

- Branch `bug-class-uniqueness`; commit type `feat(gates)` (a new gate plus a doc renumber, not an app bug fix; the full-template diagnose
  doc of section 4 is written anyway); one operation (one mapping, one recipe), so no §4.2 closure ledger.
- **Blast radius: platform.** `docs/blast_radius.yaml` gets two globs (`scripts/check_bug_class_numbers_unique.dart`,
  `scripts/bug_class_ids_lib.dart`) in the platform block ABOVE `scripts/**` (first match wins; a glob below it stays `feature`), mirroring the OI twin at `blast_radius.yaml:294-295` and A2's gate globs, so a later edit that
  loosens the gate cannot clear review. Hence: `docs/plan-reviews/bug-class-uniqueness.md` (two plan rounds, last converged,
  `bpass: accepted`; the record states three self-attested rationales: `feat(gates)` instead of `fix(...)` with a full diagnose doc written
  anyway, no §4.2 closure ledger, no §4.11 soak), a B-pass on the built diff, PR through `sh scripts/safe_pr_merge.sh <pr>`.
- **Commit, push, PR and merge each need the founder's explicit go**; build, reviews and the local gate loop do not.
- **Immediately before the merge:** `git fetch origin main`; list the bug-class ids on `origin/main` (any id at or above 2.125 or a new
  id in the skill files → shift by the section 1 rule and rebuild WITHOUT a merge commit: (1) `git commit-tree <index tree> -p <old base>` makes a synthetic commit of the branch state; (2) `git merge-tree --write-tree
  --name-only --merge-base <old base> origin/main <synthetic>` gives the merged tree and the conflict list; (3) `git update-ref
  refs/heads/bug-class-uniqueness origin/main <old tip>` then `git read-tree --reset -u <tree>`; (4) resolve conflicts, all at shared
  append points (the glossary table end, the SKILL.md index-table end, the SKILL.md Changelog tail, the bug-classes.md tail): keep BOTH
  sides, with a script that asserts exactly one conflict region per file; then re-run the section 6 script); replay the gate on the
  merge-tree result: `git archive <merged tree> .claude/skills/debugging | tar -x -C <scratch>` then
  `dart run scripts/check_bug_class_numbers_unique.dart --root=<scratch>` must PASS. `safe_pr_merge.sh` requires Audit Gates green on the HEAD sha and only WARNS
  when the branch is BEHIND (`safe_pr_merge_lib.dart:22-28, 284-287`), so this step is the guard.
- After the merge: retire this session's worktree (§4.13.8). No live DB, no Edge Function, no workflow, no hook, no APK.

## 8. Residuals

- Two PRs mint the same next id and both are green before either merges: the CI `pull_request` run uses the merge ref computed at
  trigger time and does not re-run when main moves, so the second merge turns the `main` push CI red and, until fixed, blocks every
  commit in any tree that syncs `main` (the gate is in the pre-commit loop). The owner of the fix is the session that merged second:
  one commit renumbering its class and citations; `--next` gives the number. Landing D (merge train) may narrow the window.
- The gate reads the WORKING TREE, not the staged index: a duplicate staged beside a fixed unstaged copy passes pre-commit locally and
  CI (which checks out the commit) catches it (the staged-versus-working-tree class of `review_gate_staged_content_not_working_tree_test.dart`).
- About a dozen local worktrees have `.git` pointers the VPS cannot read (Windows paths); their staged skill-file ids are not
  visible here, so the final rebuild re-checks `origin/main` and every readable worktree and the PR CI is the backstop.
- Frozen records keep their ambiguous citations; the legacy map is the resolution.
- Two index titles may differ in wording beyond the 16-character prefix; that is by design.
