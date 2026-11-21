---
reviewed_at: 2026-11-12T16:20:00+05:30
staged_against: generator-step1-1bf2 c19e5792 (batch commit 1fe05fba, origin/main sync 7ca1233b, round-4 fixes c19e5792), diff origin/main...HEAD minus the OI-493 nutrition files, CI green on the head
blast_radius: platform
reviewer: one fresh context-blind Sonnet seat (adversarial B-pass)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — Unit 1B-F2, the core-list overlay copy (`generator-step1-1bf2`)

One fresh, context-blind Sonnet seat reviewed `git show 1fe05fba` and `git show c19e5792` at `c19e5792` (CI green)
read-only, with an exhaustive command list (read-only git, file reads, read-only `python3` / `node -e`, `sha256sum`,
`dart analyze` on changed files, five named test files; no `dart run`, no scripts, no network, no database statement,
no file writes). It ran the five test files (108 green) and recomputed every asserted literal from the data. Migration
176 was already applied live, so a finding about its content would have needed a new migration; none was found
(176 vs 175: exactly the 12 movement_pattern values differ).

## Finding 1 — P3 — writer_reader_drift (inserted-lines sub-check)
- **file:line:** docs/sot_registry.yaml:12555 (`docs/blast_radius.yaml` `line_range: 39-634`)
- **claim:** the diff inserted 5 lines into blast_radius.yaml inside the cited range; the end was not shifted (and was
  already short of the last rule on main).
- **verification:** `sed -n` on both trees; the singleton rule moved 634 -> 639; the last rule is at 663.
- **suggested-fix:** shift the end.
- **status:** accepted — fixed: `39-663` (the whole paths list, first rule 41, last 663); parity gate PASS.

## Finding 2 — P3 — writer_reader_drift (ledger record)
- **file:line:** backups/applied_migrations.json, entry 176 `applied_at`
- **claim:** `2026-11-12T16:30:00+05:30` is later than the commit that carries it (09:20:55 UTC = 14:50 IST).
- **verification:** `git log --format=%ad`; the hash matches the file.
- **suggested-fix:** the real apply time.
- **status:** accepted — fixed: `14:45:00+05:30` (the apply preceded the post-apply snapshot written 09:17:55 UTC);
  Gate 39 PASS.

## Finding 3 — P3 — guard_without_its_mirror (rollback emitter)
- **file:line:** scripts/seed_exercise_library.js `TEXT_FROM_ARRAY` / `restoreValue`
- **claim:** the fix covered movement_pattern / exercise_type only; the rollback still used a generic coercion that
  differs from the INSERT's for `name_aliases` ([] -> ARRAY[] where the INSERT writes NULL) and the defaulted columns
  (logging_type, source, is_active, is_indian_context: NULL where the INSERT writes the default). The tuple guard cannot
  see it (tupleOf applies the INSERT coercion). No current record hits it.
- **verification:** read 151-182 and 370-377.
- **suggested-fix:** reuse the INSERT's per-column coercion.
- **status:** accepted — fixed: one `COLUMN_SQL` map is the INSERT's coercion; `tupleOf` and `restoreValue` both use it
  and `CLOUD_COLUMNS` is its key set. Migration 176 regenerates byte-identical. New test in the S1b-3 merge-branch
  sandbox: a name_aliases record whose before is [] restores `SET name_aliases = NULL`, never `ARRAY[]` (mutant: the
  generic coercion for name_aliases reddens it); the F2 sandbox mutation now swaps `restoreValue` for the generic form.

## Finding 4 — P3 — hygiene (stale comment)
- **file:line:** test/scripts/library_media_importer_test.dart:662-664
- **claim:** the injury-tag group's header comment sat above the new overlay-copy group (the group was inserted between
  the comment and its group).
- **verification:** read 660-666.
- **suggested-fix:** the overlay group's own mutation list.
- **status:** accepted — fixed: the overlay group has its own header; the injury-tag header is back above its group
  (`git diff 67b536e4` shows that comment unchanged from main).

## Lenses checked clean (seat's report, condensed)
- writer_reader_drift: no live reader of an overlay key (`git grep` lib, supabase/functions, scripts, test); the 27 rows
  equal `slot_* ?? own` on main; the 12-row cloud record exact, E064 out; 228 frozen hashes recomputed; the v26 sha pin
  equals main's asset; every other registry range on a changed file correct.
- function_exception_swallow, secrets_in_tree, unawaited_no_error_sink: nothing in the diff.
- blast_radius_mismatch: both new records at account above scripts/**, pinned; the selector platform.
- guard_without_its_mirror: every row-state combination of the overlay-copy stage handled or refused naming the id and
  key; self-inclusion clean (the importer is a no-op at the committed state; the generator reads 175, not 176).
- missing_input: every path read exists with the assumed shape.
- asserted_fixture_value: the 26 / 27 / 13 / 19 / 12 counts, E048, E064, the copied tables, N20 and the v26 sha.

## Founder triage notes
All four findings accepted and fixed in this batch (no false alarm).

## Tuning entry
- **2026-11-12** - blast-radius platform - 4 findings; 0 false_alarm; tuning: finding 3 is the mirror of the author's own fix (one column class fixed, the sibling columns of the same emitter left on the old path, invisible to the tuple guard because the guard used the right coercion). For a fix to an emitter, brief the seat to list every input class the emitter takes and compare it with the path the guard checks; the fix that converges is one coercion shared by both, not a per-column exception list.
