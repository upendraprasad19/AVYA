---
reviewed_at: 2026-07-30T03:46:42Z
staged_against: 9d758b27ab29
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 4
verdict: accepted
---

# Code Review — 9d758b27ab29

Dispatched against an earlier staging hash (`809e33dfc740`, the diff at that
point already carried rounds 1-2's fixes). All 4 findings below were
independently re-verified by me before triage, not accepted on the reviewing
agent's word — verification commands are cited per finding. Fixing findings
1-3 (all inline) added `docs/blast_radius.yaml` + a new test file to the
diff, which moved the diff's own blast-radius tier from `account` to
`platform` (`blast_radius.yaml` is platform-tier by its own registry) —
recorded honestly in the diagnose-doc's frontmatter rather than left at the
bug's own lower tier. The staging hash itself then moved twice more as this
review file's own filename was finalized (each edit to the diagnose-doc's
citation of this file's name is itself a diff change, so the hash chases its
own tail until the diagnose-doc stops naming this file's exact hash — which
it now does, referencing this directory generically instead). See
`docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`'s "B-pass
review" section for the full narrative; this file is the structured record
the gate reads.

## Finding 1 — P2 — blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml:213-216` (pre-fix)
- **claim:** The catch-all comment said "lib/shared/repositories ... is
  account," but no rule implemented it — `lib/shared/repositories/**` fell
  through the `lib/shared/** -> feature` catch-all (first-match-wins), so a
  diff touching only `user_repository.dart` would clear zero review gate.
  Same mechanism hit `lib/features/train/screens/graduation_screen.dart`
  (Unit 3c's target, a confirmed direct progress-map writer) via the
  `lib/features/train/** -> feature` catch-all. Both Units 3b and 3c —
  already queued as this batch's own follow-ups — would silently skip
  `code_review_b_pass` if they didn't also touch a `lib/core/services/**`
  file.
- **verification:** `printf 'lib/shared/repositories/user_repository.dart\n'
  | dart run scripts/blast_radius_from_diff.dart -` → `feature` (pre-fix).
  Independently reproduced before fixing, and re-verified post-fix: same
  command now returns `account`; `printf
  'lib/shared/repositories/plan_engine/plan_generator_v4.dart\n' | dart run
  scripts/blast_radius_from_diff.dart -` still returns `platform`
  (unaffected, more-specific rule); `printf
  'lib/features/train/screens/train_screen.dart\n' | dart run
  scripts/blast_radius_from_diff.dart -` still returns `feature` (unaffected
  — fix is scoped to the single file, not the whole tree).
- **suggested-fix:** Add explicit `lib/shared/repositories/**` and
  `lib/features/train/screens/graduation_screen.dart` rules at `account`,
  declared before the `feature` catch-alls.
- **status:** accepted — fixed inline. New rules added to
  `docs/blast_radius.yaml`; pinned by a new behavioral test,
  `test/contracts/blast_radius_progress_map_writer_paths_test.dart` (4
  assertions: the 2 fixed paths + 2 unaffected controls, via the real
  classifier subprocess, not a yaml text grep).

## Finding 2 — P2 — vacuous_test_claim
- **file:line:** `test/contracts/user_repository_progress_stale_snapshot_test.dart:127-147` (pre-fix)
- **claim:** The `'saveProgress() and updateProgress() do not corrupt each
  other under concurrent dispatch'` test only asserted 2 of the 3 fields
  genuinely in play. The field the concurrent `updateProgress` call set
  (`total_workouts_done`) came back `null` — `saveProgress`'s real REPLACE
  (not merge) contract dropping it when dispatched second — but the test
  never checked, so its name overclaimed "do not corrupt" for a field it
  silently let go.
- **verification:** Temporarily inserted `print(result['total_workouts_done']);`
  after the existing assertions, ran `flutter test
  test/contracts/user_repository_progress_stale_snapshot_test.dart
  --plain-name "do not corrupt each other"` → printed `null`. Reverted the
  insertion immediately after confirming; `git diff` showed the file back to
  its pre-debug staged state before the real fix was made.
- **suggested-fix:** Assert the real outcome explicitly (documenting the
  REPLACE contract, not pretending it's a bug), or reword the test so it
  doesn't imply a broader guarantee than it checks.
- **status:** accepted — fixed inline. Test renamed to state what it proves;
  added an explicit `isNull` assertion with a `reason:` documenting this is
  `saveProgress`'s real, intentional contract (not exploitable today — the
  only 2 real `saveProgress` callers never run concurrently with
  `updateProgress` on the same session); added a warning paragraph to
  `UserRepository.saveProgress`'s own doc comment telling future callers to
  prefer `updateProgress(delta)` unless they hold complete authoritative
  state.

## Finding 3 — P3 — doc_accuracy
- **file:line:** `lib/shared/repositories/user_repository.dart:168` (pre-fix,
  in `updateProgress`'s doc comment)
- **claim:** Cited `user_repository_progress_lock_behavioral_test.dart` (a
  leftover from before the Completer-mutex design was tried and removed) as
  proof of the fix; that file was never committed under that name. The real
  file is `user_repository_progress_stale_snapshot_test.dart`.
- **verification:** `grep -rn "user_repository_progress_lock_behavioral_test"
  --include="*.dart" .` → exactly one hit (the citation itself) pre-fix; zero
  hits repo-wide post-fix.
- **suggested-fix:** Correct the filename in the doc comment.
- **status:** accepted — fixed inline.

## Finding 4 — P2 — test_coverage_gap
- **file:line:** `lib/shared/services/pro_phase_advance.dart:103-121`,
  `lib/features/dev/simulation_service.dart:560-573`
- **claim:** The only regression test for this diagnose-doc's central bug
  (`user_repository_progress_stale_snapshot_test.dart`) proves the bug
  PATTERN using `UserRepository`'s own primitives directly — its own header
  comment already discloses this — but never calls the actual production
  functions that had the confirmed bug (`advanceProPhaseIfExpired`/
  `_advanceProPhaseIfExpired`, `_maybeAdvancePhase`). No test anywhere in the
  suite behaviorally exercises either function's write path; the only
  existing tests referencing them are source-grep/`.contains()` style. A
  future revert of either fixed callsite back to
  `saveProgress(Map.from(staleSnapshot))` would pass the full suite.
- **verification:** `grep -rln "pro_phase_advance\.dart\|simulation_service\.dart"
  test/` → `phase_repeat_nudge_test.dart`, `pro_phase_expiry_surface_test.dart`,
  `splash_post_auth_session_gate_test.dart`,
  `sync_scheduled_payload_hash_index_writer_to_reader_test.dart` (plus the
  stale-snapshot test itself); every one of the first four uses
  `File(...).readAsStringSync()` (confirmed by direct read of each), none
  invoke the real functions.
- **suggested-fix:** Add a widget/provider-level test that drives
  `advanceProPhaseIfExpired(ref)` through the `WidgetRef`-capture bridge
  pattern already established in
  `test/contracts/day_rollover_provider_invalidation_behavioral_test.dart`,
  with a real (not mocked) `WorkoutScheduleService.autoGenerateNextPhaseIfNeeded`
  run against minimal exercise-library/profile/subscription Hive fixtures,
  injecting a concurrent `updateProgress` write during the await window.
- **status:** spawned — NOT fixed inline. Not a live correctness gap (the
  fix itself is already proven by direct reproduction of the bug pattern,
  see the diagnose-doc's writers/readers fields); a rule-21 coverage gap.
  Confirmed via grep that no `workoutScheduleServiceProvider` override or
  fake exists anywhere in the suite today — genuinely novel test
  infrastructure (real exercise-library/profile/subscription fixtures, not
  a quick extension of an existing pattern), disproportionate to build
  under this same B-pass remediation pass per this repo's own "when it
  balloons, split it" precedent (§4.12), already applied twice in this same
  diagnose-doc for Units 3b/3c. Tracked as live task #41, cited in the
  diagnose-doc's "B-pass review" and "Residuals" sections — not silently
  dropped.

## Lenses checked clean (from the original B-pass dispatch, independently
## re-verified where re-verification was possible post-fix)

- **writer_reader_drift:** `pro_phase_advance.dart`/`simulation_service.dart`
  OLD vs NEW conversions use byte-identical field-key strings; `updateProgress`'s
  merge (`current.addAll(fields)`) has no interposed `await` between its own
  read and write. The "15 write callsites across 11 files" recount (round-2
  finding, re-confirmed here) is exact.
- **function_exception_swallow:** 0 `.functions.invoke(`/Edge-Function calls
  anywhere in the diff.
- **secrets_in_tree:** 0 hits for credential-shaped literals across the full
  diff.
- **unawaited_no_error_sink:** the one new `unawaited(` in the diff
  (`health_sync_service.dart`'s `unawaited(completer.future.catchError((_)
  {}));`) is a correct, narrowly-scoped silencing listener — verified via a
  standalone `runZonedGuarded` repro (see the diagnose-doc's "Round-2
  review" section) that it suppresses only the phantom duplicate
  unhandled-Future report, not real follower observability.

## Founder triage notes

Self-triaged under autonomous-mode convention (no per-finding founder
check-in required for a batch already operating under an approved plan).
Findings 1-3 fixed inline and re-verified (tests green, `flutter analyze`
clean, `validate_diagnose_doc.dart` passes, classifier re-run against both
fixed and control paths). Finding 4 spawned as task #41 per the skill's own
`spawn_followup_task` triage option — not a rejection, a scoping decision
consistent with this same diagnose-doc's Unit 3b/3c precedent.
