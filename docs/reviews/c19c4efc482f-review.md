---
reviewed_at: 2026-09-23T00:00:00+05:30
staged_against: c19c4efc482f
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 1
verdict: accepted
---

# Code Review — c19c4efc482f

Discipline v3 Phase 3 round-1/round-2 hardening: widened `check_hive_first_pattern.dart`'s
Supabase-call alias set from 2 to 3 (`supa.from(` was a live, unmatched alias in
`rank_service.dart`); fixed a `MEMORY_ARCHIVED.md` false-positive in the memory write-guard;
added 4 platform-tier `blast_radius.yaml` entries for the new/changed scripts; documented the
memory write-guard hook's measured per-call cost; and — the substantive finding of this whole
round — closed the LAST of three unguarded file-read call sites in `check_hooks_installed.dart`
(Gate 32), a gate whose entire contract is "never hard-fail unexpectedly."

## Finding 1 — P3 — cosmetic (found + fixed during this B-pass)
- **file:line:** scripts/check_hooks_installed.dart:104-121 (pre-fix)
- **claim:** An 8-line explanatory comment above the installer-read try/catch was duplicated
  verbatim, back-to-back — a copy/paste artifact from an earlier mutation-revert edit cycle.
- **verification:** `grep -c "Round-2 review (2026-09-23): the try/catch added around the two hook-" scripts/check_hooks_installed.dart` returned `2` before the fix, `1` after.
- **status:** fixed in this same batch (duplicate block removed); re-verified `flutter analyze`
  clean and all 7 `test/scripts/check_hooks_installed_e2e_test.dart` tests still green.

## Lenses checked with no finding
- **writer_reader_drift** — N/A, no Hive/cloud data touched by this diff.
- **function_exception_swallow** — N/A, no `.functions.invoke(` in this diff.
- **unawaited_no_error_sink** — N/A, no `unawaited(` in this diff.
- **blast_radius_mismatch** — the 4 new `platform`-tier entries sit above the generic
  `scripts/**` → `feature` catch-all, so first-match-wins correctly promotes them (`grep -n
  'scripts/\*\*' docs/blast_radius.yaml` confirms the catch-all is well after the new entries).
- **secrets_in_tree** — none; diff is prose/gate-logic/tests only.
- **guard_without_its_mirror** — `check_hooks_installed.dart` now has exactly 3 file-read sites
  (installer, per-hook installed content, per-hook source content), all 3 wrapped in try/catch
  degrading to WARN/UNDETERMINED + exit(0); confirmed via `grep -n "readAsStringSync"` no
  4th unguarded site exists. `memory_write_guard_lib.dart`'s dispatch
  (`isMemoryFilePath` → `isMemoryArchivePath` → `isMemoryIndexPath` → default `validateTopicFile`)
  is exhaustive; archive and index paths are mutually exclusive by suffix so no path shape falls
  through incorrectly.
- **missing_input** — every new read path now has an explicit existence+readability check; none
  assume an unverified file.
- **asserted_fixture_value** — the new `supa.from(` test cases traced against the real regex
  `\b(?:supabase|supa|client)\.from\(`; the "unreadable installer" e2e fixture
  (`[0xFF, 0xFE, 0x00, 0xD8, 0x00, 0x00]`) confirmed to keep `existsSync()` true while making
  `readAsStringSync()` throw `FormatException`, correctly reaching the new try/catch. Test-count
  claims cross-checked against real files: `check_hive_first_pattern_lib_test.dart` has 21
  `test(` calls, `memory_write_guard_lib_test.dart` has 31 — both match CLAUDE.md/ledger prose
  exactly.

## Founder triage notes
Accepted — the one finding was cosmetic and fixed inline during the review itself; no residual
action needed.
