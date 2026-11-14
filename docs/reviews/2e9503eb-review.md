---
reviewed_at: 2026-08-25T09:30:00+05:30
staged_against: 2e9503eb
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 4
verdict: accepted
---

# Code Review — 2e9503eb

All four findings independently re-verified by the author before action; all four held.
All four are fixed in the follow-up commit on this branch.

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** `docs/plan-reviews/oi60-client-blockers.md:175`, `:252-253`; `docs/audit/oi60-client-blockers.closure.yaml:91`; board `docs/audit/open_issues.md:3404-3409`
- **claim:** The plan-review record and closure YAML both assert, in the PAST TENSE, that the three
  wrong OI-127 line-citations were corrected in this batch. They were corrected in the plan document
  only. The board was never touched.
- **verification:** `git log --oneline bdbeb1a2..HEAD -- docs/audit/open_issues.md` → zero commits.
  `sed -n '3404,3410p' docs/audit/open_issues.md` → still shows `:1446-1458`, `:803`, `:345-350`.
- **suggested-fix:** Correct them on the board in the same batch that claims to have done it.
- **status:** accepted — fixed. All three corrected inline on `open_issues.md` with a stamped
  ⚠ note recording what each used to say and that both were labelled "confirmed by direct read"
  while being wrong. Also added the round-1 refutation of the `existingStart == null` guard so a
  fifth round does not re-attempt a P0.

## Finding 2 — P2 — writer_reader_drift
- **file:line:** `docs/sot_registry.yaml:6712` (`hold_display_read_path`), `:7897-7904`
  (`phase_adherence_rate` writer notes)
- **claim:** `currentPhaseCompletionRate` is a registered SoT writer this commit modifies, but both
  registry entries describing it still state the pre-change behaviour — one says
  `currentPhaseCompletionRate (still clamped)`, the other `totalWeeks MIRRORS the card EXACTLY`.
  The code's own new comment contradicts both.
- **verification:** `grep -n "still clamped" docs/sot_registry.yaml` → `:6712`.
  `git show 2e9503eb -- docs/sot_registry.yaml` shows only 4 `line_range:` corrections, no prose.
- **suggested-fix:** Update both entries in the same commit as the writer, per `lib/CLAUDE.md`.
- **status:** accepted — fixed. `hold_display_read_path` now records that the accumulator excludes
  `is_hold` while the week counter stays clamped; `phase_adherence_rate`'s writer notes drop
  "EXACTLY", explain the deliberate card asymmetry (FOB-6 → OI-125) and why the SCAN loop keeps
  walking the raw week.

## Finding 3 — P2 — guard_without_its_mirror
- **file:line:** `docs/diagnoses/2026-08-25-hold-days-dilute-phase-completion-d3b8f1.md:1`
- **claim:** `bug_id: d3b8f1` collides with the pre-existing, unrelated
  `2026-08-15-cleanup-delete-boundary-keyed-on-uuid-d3b8f1.md`, making the commit trailer
  `closes-diagnose: d3b8f1` ambiguous between two different bugs.
- **verification:** `ls docs/diagnoses/*.md | sed -E 's/.*-([0-9a-f]{6})\.md$/\1/' | sort | uniq -c | awk '$1>1'`
  → `2 d3b8f1`, the only duplicate in the corpus.
- **suggested-fix:** Rename to a fresh id; consider a `check_diagnose_id_unique.dart` gate mirroring
  `check_oi_numbering_unique.dart`.
- **status:** accepted — fixed. Renamed to `b9d4c2`, trailer corrected, cross-references updated,
  and an `id_collision_note:` added recording the miss. **The detector gap is filed as OI-140** —
  `validate_diagnose_doc.dart` takes ONE path and never scans the corpus, so nothing in the repo
  can see this class, even though the OI-number version of the same bug shipped six times and got
  its own dedicated gate.

## Finding 4 — P2 — guard_without_its_mirror
- **file:line:** `docs/plan-reviews/oi60-client-blockers.md:338`;
  `docs/audit/oi60-client-blockers.closure.yaml:96`
- **claim:** The mutation table says restoring the unfiltered accumulator reddens **4 of 7** with 3
  no-op controls. Actual is **5 red / 2 green** — "a hold-only week extends the scan but contributes
  NO days" is not a no-op under that mutation (expected 1.0, got 0.8).
- **verification:** Apply the one-line revert to `workout_schedule_read_service.dart`, run
  `flutter test test/contracts/phase_completion_excludes_holds_behavioral_test.dart`, revert.
- **suggested-fix:** Re-run and correct both tables.
- **status:** accepted — fixed. Author re-ran independently and confirmed `+2 -5`. Root cause named
  in both documents: the count was measured when the file had SIX tests and was never re-measured
  after the seventh was added. The protection is STRONGER than documented, not weaker — but rule 24
  treats mutation counts as evidence, so a stale one devalues every other count beside it.

## Lenses that returned clean

- **writer_reader_drift (runtime field contract)** — writer stamps `is_hold` (bool) + `hold_ordinal`
  (int) at `workout_schedule_write_service.dart:288-289`; every reader agrees on `== true` / `!= true`
  semantics (`:829`, `:854`, `write_service:380`, the `completedWeekNumbers` precedent at `:1032`, and
  the new `_withoutHoldRows`). Checked with `grep -rn "is_hold" lib/` and by reading each site. The
  documentation of that relationship going stale is Finding 2; the field contract itself is intact.
- **function_exception_swallow** — no `.functions.invoke(` in either changed file.
- **blast_radius_mismatch** — commit self-declares `platform`; the path registry computes `account`
  (`lib/core/services/**` catch-all). Self-declaring one tier ABOVE the mechanical floor is the
  conservative direction and matches the ×2 review actually performed.
- **secrets_in_tree** — no credential-shaped literals; only pre-existing Hive key-name constants.
- **unawaited_no_error_sink** — 5 `unawaited(` calls, all pre-existing and outside the diff hunks,
  all with an `ErrorTelemetry.recordNonFatal` sink. None added.
- **guard_without_its_mirror (fix correctness)** — all four mutations run in isolation and reverted:
  accumulator filter removed → 5/7 red (Finding 4); scan re-filtered → 1/7 red; `gatherHoldRows`
  anchor reverted to raw `h.weekStart` → 1/3 red, reproducing the duplicate spilled Monday (14 rows
  instead of 13); `computeTriggers` re-widened → 1/8 red. `computeTriggers`'s record traced to its
  call site: `shouldFetch` gates the fetch+merge, `mayReanchor` independently gates only the
  `plan_start`/`plan_end` writes — disjoint key sets, both bindings read distinctly, not collapsed.
  Regression sweep of 121 tests across the new files plus every neighbouring hold / reanchor /
  restore / adherence suite: all green. `flutter analyze` on the 5 changed Dart files: 0 errors,
  0 warnings, 4 pre-existing-pattern infos.

## Founder triage notes

Not required — all four findings are evidence defects, not code defects, and all four were fixed in
this batch rather than triaged. The verdict moved `pending` → `accepted` only after each fix landed.

**Worth carrying forward:** the ×2 plan review read the DESIGN and found design defects (including a
P0 it prevented). The B-pass read the ARTIFACTS and found that the artifacts lied — a past-tense
claim for work never done, two registry entries describing superseded behaviour, a colliding id, and
a stale measurement. Neither pass would have found the other's findings.
