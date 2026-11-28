---
reviewed_at: 2026-11-12T06:04:00+05:30
staged_against: a138ffb4ec21 (HEAD 9849d606 = origin/main, plus the staged OI-494 diff)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: no P0/P1/P2 in either seat; 4 P3 fixed in the batch, 2 closed with a reason
---

# Code Review (B-pass) - oi494-food-search-date (a138ffb4ec21)

Two context-blind Sonnet seats, each with `docs/agent_brief_preamble.md` prepended and an exhaustive
read-only command list (read-only git, file reads, named `flutter test` files under any `TZ`, `dart analyze`
on staged files, throwaway pure-Dart files in the scratchpad; no `scripts/*`, no network, no SQL). Each seat
ran after the full gate loop: whole-project `flutter analyze --no-fatal-infos` (0 warnings), the full
`TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` (14,122 then 14,123 passed) and the pre-commit
gate loop (OK).

- **Seat 1** reviewed the whole staged diff (hash 477e0445e81a): the three fix sites, the `istNow()` doc
  comment, the regression file (A, B, B2, C, D, D0), the two repointed tests, the docs and the
  `docs/sot_registry.yaml` re-anchors. It re-opened every registry range citing the two shifted files, ran
  the three test files under Asia/Kolkata, UTC, Asia/Tokyo and America/Los_Angeles (23/23 each), and
  recomputed every date literal.
- **Seat 2** reviewed the delta seat 1 caused (hash ca9200d2b503): the profile `updated_at` and snapshot
  photo `taken_at` stamps, the `workout_repository.dart` rename, the `sync_profile.dart` comment, test E and
  the zero-tolerance guard D. It swept `lib/`, `test/`, `supabase/functions/` and `scripts/` for readers of
  either field and ran the new file in the same four zones (9/9 each).

The hash above is the final staged diff after both seats' fixes (a doc comment and a diagnose-doc label) and the OI-494 move from `open_issues.md` to `closed_issues.md` (docs only).

## Finding 1 - P3 - writer_reader_drift (seat 1)
- **file:line:** docs/sot_registry.yaml (`ist_sites`, `line: 412, fn: WaterIntakeNotifier.build`)
- **claim:** line 412 is the `int build()` declaration; the `istDateStr(DateTime.now())` call is at 416.
- **verification:** `git show :lib/features/nutrition/providers/nutrition_provider.dart | sed -n '412p;416p'`
- **suggested-fix:** `line: 416`.
- **status:** false_alarm. The parity gate wants the class name within 5 lines of an `ist_sites` line and
  refuses 416 and 417 (417 was tried first and refused, `[stale-line-range]`). The sibling entry
  (`health_write_service.dart:336`, `setWaterMl`) cites the declaration line too, so 412 follows the
  registry's convention. The old value 409 was a blank line.

## Finding 2 - P3 - guard_without_its_mirror (seat 1)
- **file:line:** test/contracts/ist_now_double_shift_behavioral_test.dart (guard D, `allowed` map)
- **claim:** a per-file token count cannot tell a components-only use from an unsafe one in the same file,
  so a safe use in an allowlisted file could be swapped for an unsafe one unseen; the local variable named
  `istNow` in `workout_repository.dart` muddied the count.
- **verification:** `grep -n "istNow" lib/features/train/repositories/workout_repository.dart lib/features/profile/services/profile_write_service.dart`
- **suggested-fix:** rename the local; note the limit.
- **status:** accepted, fixed. Every remaining use was removed (Finding 3, the local renamed `istWall`), and
  D now fails on any `istNow` token in `lib/` outside `ist_date.dart`, with an empty map and a comment
  saying why it must stay empty. MD2 (old call-only regex) still reddens D0.

## Finding 3 - P3 - missing_input (seat 1)
- **file:line:** lib/features/profile/services/profile_write_service.dart:67,95; lib/core/services/stat_snapshot_service.dart:317
- **claim:** `istNow().toIso8601String()` writes the IST clock reading with a `Z` suffix, 5:30 ahead of the
  real instant: a latent wrong timestamp, harmless only while nothing reads it.
- **verification:** `grep -n "updated_at" lib/core/services/sync/sync_profile.dart`
- **suggested-fix:** `nowWall().toUtc().toIso8601String()`.
- **status:** accepted, fixed. Both stamps now write the UTC instant (the snapshot one matches
  `progressPhotoTakenAtWire`). New test E pins the profile stamp at 22:30 and 23:45 IST with the clock set
  to a LOCAL DateTime, as `DateTime.now()` is in release. Mutants: M5 (`istNow()` back) red E + D, M6 (no
  `.toUtc()`) red E, M7 (snapshot `istNow()` back) red D, all in TZ=Asia/Kolkata and TZ=UTC. M6 first
  survived while E pinned a UTC-flagged clock; the local pin is what made it red. The restore-skip comment
  in `sync_profile.dart` that named `istNow()` was updated (comment only; this makes the diff `platform`
  by path).

## Finding 4 - P3 - writer_reader_drift (seat 2)
- **file:line:** lib/features/profile/services/profile_write_service.dart:29
- **claim:** the class doc still said "Stamps `updated_at` (IST ISO-8601)".
- **verification:** `sed -n 29p lib/features/profile/services/profile_write_service.dart`
- **suggested-fix:** say UTC.
- **status:** accepted, fixed ("the UTC instant, ISO-8601 with Z"). `grep -rn "IST ISO-8601" test/ scripts/`
  returns nothing, so no source pin moved.

## Finding 5 - P3 - asserted_fixture_value (seat 2)
- **file:line:** docs/diagnoses/2026-11-11-ist-now-double-shift-food-search-4f9b2e.md (row M7)
- **claim:** only guard D covers the snapshot `taken_at` stamp; the branch is unreachable, so a
  `DateTime.now()` stamp there would stay green.
- **verification:** `git grep -n "photoUrls" -- lib test`
- **suggested-fix:** label M7 presence only.
- **status:** accepted, fixed (the M7 row says so).

## Finding 6 - P3 - writer_reader_drift (seat 2, predates this diff)
- **file:line:** lib/features/onboarding/providers/onboarding_provider.dart:506
- **claim:** onboarding writes profile `updated_at` as a local ISO string with no `Z`, so the field holds
  more than one format.
- **verification:** `git grep -n "updated_at" -- lib | grep -i profile`
- **suggested-fix:** none.
- **status:** no_change_needed. The field was already mixed before this diff (the IST stamp carried a `Z`,
  cloud restores carry `+00:00`). Nothing reads it: it is not in the profile push payload (`sync_profile.dart`
  builds an explicit field list), the restore skip removes it from both sides, tests assert only
  `isA<String>()`, and `body_fat_default_healer.dart` writes no `updated_at`.

## Lenses checked clean (both seats)
- **writer_reader_drift:** every `docs/sot_registry.yaml` range citing `nutrition_provider.dart` or
  `ai_snapshot_builder.dart` re-opened against the staged blob (each brackets its method); the `nlog_` date
  has one writer (`logMeal`), the other key builders take a formatted string; no `istDateStr(istNow(`,
  `istDateStr(istDateOf(` or nested `istDateOf` in `lib/`; registry entries for the profile and snapshot
  files are unaffected (no line-count change).
- **function_exception_swallow / unawaited_no_error_sink:** no new `functions.invoke`, `catch` or
  `unawaited`; the stamps sit inside the existing try with `recordNonFatal`.
- **blast_radius_mismatch:** fix sites `account`, `sync_profile.dart` `platform` by path (comment only); the
  plan and the plan-review record say `platform`.
- **secrets_in_tree:** none in the staged diff.
- **guard_without_its_mirror:** week arithmetic is instant arithmetic with the IST weekday from
  `istDateOf(wall)`, correct on all 7 IST weekdays, at 00:00-05:30 IST on a UTC host and under host DST;
  the clock seam is reset in `tearDown`; the D scanner counts prefixed calls, tear-offs and
  interpolations and D0 pins its string handling.
- **missing_input:** `logFood` was the only `logMeal` caller passing `istNow()`; the coach
  `tool_dispatcher.dart` local-midnight parse is tracked in OI-493.
- **asserted_fixture_value:** A, B and C fail without the fix (A: 2026-11-12 instead of 11; B: Bench Press
  instead of Squat as today's exercise; C: 2026-11-16 present); B2 is green on main too and pins M4 only, as
  the docs say; E's literals recomputed (22:30 IST = 17:00Z, 23:45 IST = 18:15Z).

## Founder triage notes
Triaged by the coordinating session: 4 P3 fixed in the batch, 1 false alarm (gate convention), 1 no change
needed (predates the diff, no reader).

## Tuning entry
- **2026-11-12** - blast-radius platform - 6 findings; 1 false_alarm; tuning: none. Two notes for the lenses: a seat suggesting a registry line should be run against the parity gate's own window rule before it is offered as a fix, and a timestamp test should pin the clock with a LOCAL DateTime (a UTC-flagged seam value hid a dropped `.toUtc()`).
