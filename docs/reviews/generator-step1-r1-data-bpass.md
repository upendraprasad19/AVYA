---
reviewed_at: 2026-11-09T02:30:00+05:30
staged_against: generator-step1-r1-data staged tree (29 files) vs origin/main c2841edb
blast_radius: platform
reviewer: fresh-context-blind-sonnet-agent (adversarial B-pass)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value, off_identity]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — Library Batch S1a, core-list levels (`generator-step1-r1-data`)

A fresh, context-blind Sonnet agent reviewed the staged diff (`git diff --cached`, 29 files) with lenses 1, 3, 6, 7 and
8 of the skill plus an OFF-identity check, read-only, allowed the importer and scope `--check` runs and three named test
files. It did not run the gate test (the coordinating session ran it and its two mutations, recorded in diagnose
`e9a4b6`).

**Verdict: no P0, P1 or P2.** Two P3 findings, both wording, both applied.

## Finding 1 — P3 — guard_without_its_mirror (R9 (iv) comment vs condition)
- **file:line:** test/plan_generator/core_list_pool_gate_test.dart:228-242
- **claim:** the comment says the user "always gets" the leg compounds with "no drop, no emergency", while the condition also accepts source `fill` (a same-family row core at a higher level); a reader could take the zero to mean "core only".
- **verification:** read of the `s.source` branches and `core_list_selector.dart` (core / fill / drop sources).
- **suggested-fix:** say in the comment that `fill` is accepted (the plan's wording is "source core or fill").
- **status:** fixed (comment names `core` or `fill`, as the plan specifies).

## Finding 2 — P3 — missing_input (fixture maintenance)
- **file:line:** test/fixtures/library_core_levels_before_s1a.json:1
- **claim:** the "no row outside Table A changed" test depends on the fixture never being re-recorded; its `_note` should say it is frozen.
- **verification:** `node -e` comparison of the fixture with `git show HEAD:assets/data/exercise_library.json`: 862 ids, 0 mismatches.
- **status:** fixed (the `_note` says the fixture is frozen and a later batch adds its own).

## Clean lenses (reviewer's evidence, abridged)
- **Only core_levels changed:** a key-by-key diff of the staged library against HEAD shows exactly 34 changes, all `core_levels`; no row added or removed. Totals 128 / 154 / 128 (HEAD 129 / 138 / 98); source `_meta.derived.core` 56 / 54 / 44, kept rows 72 / 100 / 84, matching the test literals.
- **Importer and scope:** `--check` byte-identical (229 kept + 633 new); scope `--check` OK (C1 to C6, `inputs_sha256` intact).
- **writer_reader_drift:** seed constant 21 at `seed_service.dart:156`; the four registry cites shifted by a uniform +6 (255-296 and three 156-156) and still land on the same statements.
- **blast_radius:** the record's `account` glob sits above `scripts/**`; group 1e checks both engines and a look-alike.
- **importer stage mirrors:** a source id, an unknown id and a duplicate are refused; a row at neither state throws naming the id; `after` is a no-op; an absent record is a printed no-op; the stage runs after retag / E274 and before media, and E274 keeps its Mid Back rewrite (test (a)).
- **asserted values:** Table A literals, the 34-row count and the three re-recorded like-for-like cells match the library.
- **OFF identity:** in `lib/`, `core_levels` is read only in `core_list_selector.dart`; `exercise_selector.dart:590` and `plan_engine_flags.dart:422` mention it in comments; no reader in `supabase/functions`, no cloud column.
- **Tests run by the reviewer:** `library_s1_core_levels_test.dart`, the importer test, `library_seed_v21_upgrade_behavioral_test.dart` (38 tests) passed.

## Founder triage notes
Triaged by the coordinating session: both P3 applied as comment / note edits (no behaviour change). The founder items of
plan Decision 3 are ledgered `blocked_on_user` in `docs/audit/library-batch-s1a.closure.yaml`.

## Tuning entry
- **2026-11-09** - blast-radius platform - 2 findings; 0 false_alarm; tuning: none (both were wording; the batch's real defects, the same-day dedup door and the green-on-old-data gate wording, were found by measuring, which the brief now names as the coordinator's job before dispatch).
