---
reviewed_at: 2026-11-12T22:40:00+05:30
staged_against: generator-step1-1bf f86dce17 (the batch commit e93d7278 merged with origin/main 9849d606), diff origin/main...HEAD, 125 files
blast_radius: platform
reviewer: four fresh context-blind Sonnet seats (adversarial B-pass; A production code, B the library data path, C the test harnesses, D deletions and documents)
lens_set: [writer_reader_drift, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, blast_radius_mismatch]
findings_count: 20
verdict: accepted
---

# Code Review (B-pass) — Unit 1B-F, the core-list pool becomes the only picker (`generator-step1-1bf`)

Four fresh, context-blind Sonnet seats reviewed `git diff origin/main...HEAD` at `f86dce17` read-only. Their commands
were listed exhaustively (read-only git, file reads, read-only `python3` / `node -e`, `dart analyze` on one file, and at
most three named light test files each); `dart run scripts/*`, `scripts/*.sh`, the heavy generator tests, network tools
and database statements were forbidden. Seat B ran the v25 seed, warm-up and importer tests (all green); seat C ran the
queryV4 rules, audit lib and env manifest tests (all green); seats A and D ran nothing.

**Verdict: accepted.** No P0 or P1. Nine P2 and eleven P3 / residual observations, every one fixed in this batch or
answered below with its evidence. Mutations for each code or test fix are in the diagnose doc (`39eb2a`).

## Seat A — production code

### Finding A1 — P2 — guard_without_its_mirror / writer_reader_drift
- **file:line:** lib/shared/repositories/plan_engine/session_set_allocator.dart (evictFor's decision and final check; pass A's re-check)
- **claim:** Ruling 5 guard (c) promised a 1e-6 tolerance in the decision and the final check; the code compared
  exactly. The decision sums the freed seconds in its own order and the ledger subtracts each hold's cost one at a
  time, so at an exact boundary an ulp could make the decision say "fits" and pass A's re-check say "no": holds
  evicted for nothing.
- **status:** fixed. One helper, `SessionSetAllocator.fitsAfterEviction(need, left)` (`need <= left + 1e-6`), serves the
  decision, its final check and pass A's re-check. Tests: the group "guard (c): one comparison, with a 1e-6
  tolerance" in `allocator_timed_hold_eviction_behavioral_test.dart` (the boundary semantics; a pin on the three call
  sites, since no allocator fixture reaches an ulp). Mutants: tolerance removed (red); pass A's re-check back to an
  exact `<=` (red). No plan output changes: golden and audit re-run on the fixed tree (see the closure).

### Finding A2 — P3 → fixed as a defect — writer_reader_drift (stats on a copied day)
- **claim:** on a day variant B copies from A, A's evicted holds never entered B's `nonBudgeted`, so B's `rowsSeen`
  was post-eviction, while the plan says `rowsSeen` is the selector's rows before eviction in both variants
  (`plateau_rotation_behavioral_test.dart` reads it for B).
- **status:** fixed: `copiedEvicted[d]` counts them into `rowsSeen`. The copied-day test now asserts `rowsSeen` [5] for
  A and B; mutant (the counter not incremented) red.

### Finding A3 — P2 — a data change in a file labelled comment-only
- **claim:** the warm-up table's Jumping Jacks / Jump Rope gain `hip` (data, not a comment); is it pinned?
- **status:** fixed (coverage). `warmup_library_injury_mirror_test` pins the table against the library rows; the new
  test "hip injury DROPS Jumping Jacks and Jump Rope (Ruling 12)" in `warmup_injury_filter_behavioral_test.dart` checks
  the behaviour (non-vacuous baseline, the floor holds); mutant (Jumping Jacks without `hip`) red.

### Finding A4 — P3 — the v12 guard is gone
- **claim:** a box with no `core_levels` yields empty days for uninjured users.
- **status:** answered. Every generation path awaits `SeedService.instance.seedIfNeeded()` first
  (`onboarding_provider.dart:563`, `regenerate_plan_planner.dart:212`, `train_provider.dart:787`,
  `workout_schedule_read_service.dart:217`, `:385`); only a failed seed reaches it, the closure's `STALE_LIBRARY`
  entry (upstream_blocked, store launch).

## Seat B — the library data path (Ruling 12, seed v25)

No P0 to P2. Seat B recomputed: exactly 14 rows differ from origin/main, only in `injury_contraindications`, each
gaining only `hip`; every `before` of the v25 record equals origin/main and every `after` HEAD; the 14 fixture tag lists
equal origin/main; the pinned v24 digest; all 228 frozen row hashes (0 mismatches); the warm-up table equals the
library tags; the stage's refusals each have a red test; the importer is idempotent.

### Finding B1 — P3 — mirror test strength
- **claim:** the v25 MIRROR (a box already at v25 is not rewritten) asserted one row.
- **status:** fixed: it loops all 14 ids.

### Finding B2 — P3 (residual) — scope
- **claim:** E067 Mountain Climber and E201 Spot Jogging carry no `hip`.
- **status:** answered: Ruling 12's scope check (18 candidates by `high_impact` and name) left the rows that do not land
  from flight, d19's criterion; Mountain Climber keeps a foot on the floor. No change.

## Seat C — the test harnesses

### Finding C1 — P2 — guard_without_its_mirror
- **claim:** `injury_sweep_b_singles_test`'s block-file guard read five files; the new `f_repeat_pairs30` file's tier
  loop or `minutes: 30` could change silently.
- **status:** fixed: the sixth file is in the map; the "five files" wording in both files is updated. Mutant
  (`minutes: 45`) red.

### Finding C2 — P2 — guard_without_its_mirror
- **claim:** `scan` checked performability against the full tier, ignoring the run's exclusions, so an excluded item in
  a `pairs9_exclall` pick would pass.
- **status:** fixed: `scan(..., exclusions:)` computes the run's own capability; the R6 lib passes the exclusions.
  Clean run green; mutant (the generator not given the exclusions while the scan is) red: "unperformable ...
  pairs9_exclall: Nordic Curl needs [foot anchor]".

### Finding C3 — P3 — a counted tier that never runs
- **status:** fixed: the fixture-count test asserts every `runCounts` tier is in `kSweepTiers`.

### Finding C4 — P3 — fixture header
- **status:** fixed: the header names the fourth extension block (`pairs_anh_eq`, 9,072 runs) and that R6 fired in 0
  of them (plan Ruling 3).

### Finding C5 — P3 — the ratchet is a net count
- **status:** fixed (documented): the lib header says the per-tier ratchet is net and the per-run zeros are exact.

## Seat D — deletions and documents

Every deleted file and test maps to a Ruling 7 row and its replacement exists (seat D opened each).

### Finding D1 — P2 — the closure said tables were on OI-452 before they were
- **status:** fixed: the 15-pair grid tables at 30 / 45 / 60 minutes are appended to OI-452 from the final-tree runs.

### Finding D2 — P2 — stale "998 golden personas"
- **status:** fixed in `lib/shared/repositories/plan_engine/CLAUDE.md` (three places plus the pitfall line),
  `docs/architecture/functionality-flow.md` (TRAIN-22), `docs/reference/directory-structure.md`,
  `integration_test/flows/plan_generator_to_first_workout_test.dart`, `docs/architecture/plan-engine-detail.md` (the
  OFF-identity line now says the golden holds the one world, re-recorded at the flip).

### Finding D3 — P2 — "20 sweep blocks"
- **status:** fixed: 24 `kThinCeilings` entries since `f_repeat_pairs30`.

### Finding D4 — P2 — "nine G rows"
- **status:** fixed: eight G rows take `hip` from the table (G3582's row was rebuilt too, it already carried hip),
  G3656 by hand in the table: the v25 record's note, the registry and the seed comment.

### Finding D5 — P2 — records cited before they exist
- **status:** by design: `docs/plan-reviews/generator-step1-1bf.md` lands in this batch before the merge (the merge
  seam requires it) and `flip_commit` is stamped with the batch commit's SHA.

### Finding D6 — P3 — the diagnose cited the wrong line for the hard filter
- **status:** fixed: `core_list_selector.dart:265` (`isContraindicated`) for the hard filter, `:322` for the jump-only
  pool.

### Finding D7 — P3 — the plan's section 8 test name; Ruling 7's line numbers
- **status:** fixed: the real file name; Ruling 7 states its line numbers are the pre-flip tree's (`ea37ed59`).

### Finding D8 — P3 — bug class 2.53 still describes the mirrors as live
- **status:** fixed: a status line in `.claude/skills/debugging/bug-classes.md` 2.53.

### Finding D9 — P3 — the seam count 8 vs the plan's 7
- **status:** no change: the plan said the final tree's count is recorded; 8 sites verified by the seat.

## Founder triage notes
None needed: no finding asks for a product decision.

## Tuning entry
- **2026-11-12** - blast-radius platform - 20 findings; 0 false_alarm; tuning: four seats by area (code, data path, harnesses, documents) on a 125-file flip worked; the harness seat found two real gaps that every earlier review round missed because they live in test helpers no round was briefed on (a guard map that predates the new file; a scan oracle ignoring the run's exclusions). For a batch whose protection is mostly new test harnesses, brief one seat on the harnesses alone.
