---
bug_id: d5b8e3
date: 2026-10-25
batch: merge-conflict-treadmill-b
status: fixed
blast_radius: platform
symptom: >-
  Nine bug-class numbers in the debugging skill (2.36, 2.37, 2.38, 2.39, 2.40, 2.41, 2.53, 2.54,
  2.55) each named TWO unrelated classes, in both .claude/skills/debugging/bug-classes.md (the
  bodies) and the SKILL.md index table, so a citation such as "debugging skill 2.38" did not
  resolve to one class (OI-167). The cause is how a new number is chosen: "max + 1" read by eye,
  and `tail -1` on bug-classes.md answers "the last-positioned entry", not "the highest number"
  (2.61 was minted twice on 2026-09-07 for exactly that reason, caught in review). Nothing gated
  either file; scripts/check_oi_numbering_unique.dart does this for OI numbers only. The skill's
  own red-flag table (SKILL.md section 3) and two Changelog lines cite classes by number too, so
  a renumber that only reads outside documents would have left four red flags pointing at the
  wrong class.
concept: debugging_bug_class_ids
sot_registry_entry: not_applicable
writers:
  - file: .claude/skills/debugging/SKILL.md
    method: section 5 rule 1 (a new class appends a body and an index row) and the index table rows
    line: 299
  - file: .claude/skills/debugging/bug-classes.md
    method: the `### 2.N` headings and the Numbering header with the legacy map
    line: 8
readers:
  - file: scripts/check_bug_class_numbers_unique.dart
    method_or_widget: main (reads both files, prints findings to stderr, exit 1; --next prints the next free id)
    line: 57
  - file: scripts/bug_class_ids_lib.dart
    method_or_widget: checkBugClassNumbers (duplicates, set difference, major pin, lookalikes, title pairing) and nextFreeId (numeric maximum)
    line: 300
  - file: .claude/skills/debugging/SKILL.md
    method_or_widget: the nine red flags of section 3 that cite a class as "See §2.N"
    line: 255
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/bug_class_numbers_gate_e2e_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: 'File\(.*\)\.existsSync\(', absent: true }   # in scripts/check_bug_class_numbers_unique.dart and scripts/bug_class_ids_lib.dart only: they read inside try/catch instead (the added-line gate check_gate_existssync_file_vs_dir.dart blocks the call there); the e2e test file uses File(...).existsSync() on purpose
  - { pattern: 'Platform\.environment', absent: true }   # the gate and its tests read no environment variable (the spawn env manifest test)
proposed_fix: >-
  A strict uniqueness gate, scripts/check_bug_class_numbers_unique.dart over the pure parser
  scripts/bug_class_ids_lib.dart, run by the pre-commit loop and the CI Audit Gates job (both run every
  scripts/check_*.dart, so no hook or workflow edit). It fails on an id used twice in either file, an
  id in one file and not the other, a major other than 2, a numeric `### 2.N` heading in SKILL.md,
  a line that looks like a heading (even one indented up to three spaces) or a row but does not
  parse, an unclosed code fence, an id whose title differs between the files (the first 16 letters
  and digits, any script), a missing file or index section, and a parse that finds nothing. `--next` prints the next free id as the numeric maximum over both files. The nine
  duplicated ids are split once: the class with more citation lines keeps the number (a tie goes to
  the class introduced earlier in git), the other moves to 2.125-2.133 in old-id order with a
  `(was 2.N; renumbered 2026-10-25)` marker on its heading and index row; 18 citation lines in 9
  files follow their class (8 outside documents, 6 in SKILL.md, 4 in bug-classes.md); the legacy map
  with a date rule for records this change did not rewrite sits in the bug-classes.md header.
  The gate and the clearing renumber land in one commit because a gate-first commit cannot pass its
  own pre-commit.
regression_test_planned:
  - test/scripts/bug_class_ids_lib_test.dart
  - test/scripts/bug_class_numbers_gate_e2e_test.dart
  - test/scripts/bug_class_renumber_pins_test.dart
related_bugs:
  - b7e3d1  # the OI-number collision invariant (check_oi_numbering_unique.dart): the same mechanism, six live instances by 2026-08-16
  - c5e1a8  # A0 of this plan: a shared-state installer that overwrote in place (class 2.118 cites the same family of shared writers)
  - eeca32  # A2 of this plan: generated indexes that every branch rewrote
recurrence: |
  Recurrence of the OI-number collision class (b7e3d1) in a second self-numbered catalog: 2.61 was
  minted twice on 2026-09-07 and nine numbers carried two classes each by then. The OI board got an
  allocator and a gate; the bug-class catalog got only a warning comment, which stopped a tenth
  collision on the day it was written and nothing after. This instance adds the gate (not an
  allocator: CI runs the gate on the PR's merge result and every commit's pre-commit loop runs it)
  and clears the nine. Residual, by design: two PRs that mint the same next id and are both green
  before either merges turn the main push CI red; the session that merged second renumbers
  (landing D of the plan narrows the window).
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ code changed (two Dart scripts, three test files, markdown, one yaml registry)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive key or box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration; supabase/migrations/158_referral_referrer_cap.sql cites 2.36 (the ACL class, which keeps the number) and is not edited." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service; GitHub Actions runs the new gate through the existing Audit Gates loop (verified at PR time)." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "End to end on the real tree: on the base files (b0735bb1) the real gate reported exactly the nine duplicate ids (18 lines) plus the 2.93 title mismatch and next free id 2.123; on the renumbered tree it prints PASS with headings=131 rows=131. 72 mutants (parser, gate wiring, root resolution, renumber outcome, citations) all reddened at least one test." }
impact_analysis: >-
  Platform (the gate and its lib are registered platform in docs/blast_radius.yaml beside the OI
  twin). Every commit now runs one more gate, which reads two markdown files and has no environmental
  input. A tree that gains a duplicate through a merge is blocked until one commit renumbers it; the
  output names the ids and the next free id. No hook, workflow or token-scope change, so nothing to
  reinstall on the VPS or the Windows clone. Other sessions: a branch that appends a bug class at the
  end of both files merges cleanly with this change (the renumber edits headings and rows in place in
  the middle); the live session sync-storm-first-sweep holds 2.123 and 2.124, and the moved classes
  start at 2.125 so neither side renumbers.
---

# Bug-class numbers: nine ids named two classes each, and nothing checked the numbers

## What was wrong

The debugging skill keeps its bug classes in two files that must agree: one `### 2.N Title` heading
per class in `bug-classes.md` and one row per class in the SKILL.md index table. The next number was
chosen by looking at the file. Because the entries are not in numeric order (2.61 and 2.62 sit above
2.53-2.60; 2.41 precedes 2.40), `tail -1` returns the last-positioned entry, which is not the highest
number, and two classes ended up on one id. OI-167 recorded nine such ids on 2026-09-07 and warned
against a renumber because every one is cited by number. That warning was right about the cost and
wrong about the conclusion: all citations of the nine could be read (about 100 lines in total once the
version-string noise is excluded) and the citing lines of the moved classes number 18.

Writer: whoever appends a class (`SKILL.md` section 5 rule 1). Readers: every document that cites a
class by number, and, now, the gate. The drift was writer to reader: a number written twice resolves to
whichever occurrence a reader finds first.

## What the fix does

See `proposed_fix`. Points worth stating:

- **The first census missed the skill's own files.** The plan's first draft counted 8 citation lines in
  7 files; three independent reviewers found 10 more lines inside SKILL.md and bug-classes.md (four red
  flags, two Changelog lines, four cross-references). The red flags are the dangerous ones: they are what
  an agent reads at the start of a debugging session. A pin test now resolves each of the nine red flags
  to the class it names.
- **Counting lines, with a stated tie-break.** The number stays with the class that has more citation
  lines; a tie goes to the class introduced earlier in git, because a record written before the later
  class existed can only mean the earlier one. 2.37 and 2.40 are ties; the rule keeps the June 2026
  classes. A citation whose class cannot be told (`bug-classes.md:274`, a "(§2.40 family)" that matches
  neither class) loses its number rather than guess; two family citations name both classes.
- **Why not an allocator.** An allocator reserves numbers over the network (the OI allocator is
  `scripts/mint_oi.sh` with a ref namespace and an offline failure mode). Here the gate runs on the PR's
  merge result, so a collision between two open PRs is caught before the second merges, at the price of
  one renumber when two PRs are both green before either merges.
- **Why not key on the title.** OI-167 recommended it. More than 100 documents cite by number and a title
  is a sentence that gets reworded; the numbers stay the key and the legacy map bridges the old records.
- **Titles are compared, with a 16-character rule.** Without it, an id attached to a different class in
  the two files (a renumber that edited one side) passes every other check. Measured on the base: one of
  131 heading and row pairs differs under the rule (2.93), aligned in this commit. A comparison of whole
  titles would have flagged 15 or more.
- **Streams and codes are pinned.** PASS goes to stdout, findings to stderr as `path:line: message`, exit 1
  for a finding or an unreadable input, exit 2 for a bad argument; a parse that finds no headings or no
  rows fails instead of passing.

## Tests and mutation proof (rule 21)

Three test files, 108 tests: `bug_class_ids_lib_test.dart` (68, the parser and checker, fixtures built to
reach one branch each), `bug_class_numbers_gate_e2e_test.dart` (33, the REAL script spawned on temp
catalogs: every finding kind, the input guards, `--next`, the three root shapes and the real tree) and
`bug_class_renumber_pins_test.dart` (7, the exact old-to-new mapping in both files and the red flags and
repointed lines on the real documents). 72 mutants were applied one at a time, each confirmed by an
exact-one-match assertion before the write, the three files run, the sources restored and their sha256
re-checked: 72 of 72 reddened (the table is in the gate ledger entry). Two of them did not prove anything
on the first run against the final code and were fixed rather than argued: the harness anchor for "drop
fence handling" no longer compiled after the fence scan began returning a record, and "drop the CR strip"
survived because a CRLF heading that carries a title still parses without the strip (the strip only
matters for a heading with no title, which now has its own assertion). The real-document mutants (swap two
moved ids in one file, in both files, move the wrong class of a pair, leave a red flag or an outside
citation on the old id) are killed by the pin file, which is the only thing that can see a CONSISTENT
mistake the gate itself cannot.
