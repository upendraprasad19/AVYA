---
reviewed_at: 2026-09-28T19:45:00+05:30
staged_against: 330f5d0c27fc
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [merge_resolution, writer_reader_drift, guard_without_its_mirror, asserted_fixture_value, missing_input]
findings_count: 1
verdict: accepted
---

# Code Review — 330f5d0c27fc (third merge of origin/main into day-swapper-sync-load)

PR #47 went CONFLICTING after main merged PR #48 (reps-secs-invalidation-fixes: six
day-rollover provider-invalidation fixes, a foreground midnight Timer in
`day_rollover_service.dart`, and a `logExercise` aggregate fix computing reps/weight/volume from
`cleanedSets`). Main changed no Edge Function, so the five deploys made from this branch today
stay current.

Resolutions: code-review and debugging SKILL.md tuning/bug-class appends and the OI board
(OI-263/264 branch, OI-265/266/267 main) kept both sides; both sides had added a debugging bug
class `2.73` — the branch's keeps 2.73 (cited by number in three `test/widgets/*` comments),
main's became 2.75 (cited nowhere by number); `sot_registry.yaml` line citations into
`workout_write_service.dart` re-derived from the merged file (wlogKey 1465, scheduleKey 1468,
upsertScheduled 602-681, and `_rescanPrFor` 379-400, which auto-merged stale and the parity gate
caught); both generated indexes regenerated.

One context-blind Sonnet reviewer. The lens that mattered — the SILENT overlap, since
`workout_write_service.dart` and `lib/core/services/CLAUDE.md` auto-merged although both sides
edited them — came back clean: main's aggregate fix is the only hunk in its region; the branch's
exlog fingerprint and move/merge helpers read persisted post-fix values rather than recomputing.
The branch's `daySwapWeekProvider` / `daySwapAllowanceProvider` do not compute from
`DateTime.now()` directly and depend on `currentPlanProvider`, already in main's rollover
invalidation list, so main's new "every now()-computing provider" rule is not violated.

## Finding 1 — P2 — writer_reader_drift (free-text line citations no gate reads)
- **file:line:** docs/sot_registry.yaml, prose `method:` strings in three concept entries
  (day_swap_engine, schedule_arrangement_stamp and its sibling)
- **claim:** `confirmed :703` / `:642` / `upsertScheduled at :592` / `:676-690` were stale against
  the merged file; they are free text, not `line:`/`line_range:` keys, so
  `check_sot_registry_parity` cannot see them (the OI-262 gap).
- **verification:** `grep -cE "confirmed :(703|642)|at :592|:676-690" docs/sot_registry.yaml` → 0 after fix
- **status:** fixed — 11 occurrences (the reviewer named 4, in one entry; the coordinator's own
  grep found the same stale text in two more entries) set to the merged locations: :713, :652,
  :602, :686-696, each confirmed by reading that line. They were already ~2 lines off before this
  merge, so they were set to exact positions rather than shifted.

## Founder triage notes
One doc-citation finding, fixed before commit. Tests in the overlap 135/135; whole-project
analyze 0 warnings / 0 errors; parity PASS.
