---
reviewed_at: 2026-11-13T10:40:00+05:30
staged_against: e0944a4b (origin/main...HEAD, merge base 9fc3b043; CI green on e0944a4b)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh seats: A client + sync, B server + migration + OI-502 + records)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 7
verdict: accepted
verdict_note: no P0 or P1; one P2 and three P3 fixed in the B-pass commit, three answered without a change
---

# Code Review — coach-chat-time-dup (PR #260)

Both seats read `git diff origin/main...HEAD` at e0944a4b with the agent brief preamble, the founder decisions and
rejected alternatives quoted, and an exhaustive read-only command list. Seat A ran 7 test files (75 tests), seat B 7
(124 tests), all green. Neither seat mutated anything; the coordinator mutated each fix below.

## Finding A1 — P2 — guard_without_its_mirror
- **file:line:** lib/core/services/sync/sync_coach.dart, the push's text lookup after a key-lookup miss
- **claim:** the fallback text lookup can hit ANOTHER turn's row that carries a different `client_key` (a failed K1,
  then the same words re-sent as K2, which succeeded) and stamp K2's cloud id onto K1, marking K1 synced. The old code
  did the same; the new column lets the push tell the turns apart.
- **verification:** `sed -n 360,400p lib/core/services/sync/sync_coach.dart`
- **fix:** the text lookup reads `client_key` (only when the key lookup did not throw, so a database without the column
  never fails it), and a hit whose key is set and differs is not stamped: K1 goes up as its own keyed orphan. Test p10
  (+ the request shape: the lookup names `client_key`); p5 now asserts it does NOT when the key lookup failed. Mutants
  P9 (stamp any hit), P10 (never read the key), P11 (always name the column) all red.
- **status:** accepted

## Finding A2 — P3 — writer_reader_drift (registry)
- **file:line:** docs/sot_registry.yaml, two `_restoreCoachMemory` entries citing `sync_coach.dart` 413-421
- **claim:** already stale on main (250-260 against the real 364-410); this batch's mapping carried the error along.
- **verification:** `grep -n "Future<void> _restoreCoachMemory" lib/core/services/sync/sync_coach.dart` (656; closing
  brace 712)
- **fix:** both re-derived from the declaration to 656-712.
- **status:** accepted

## Finding A3 — P3 — missing_input
- **file:line:** sync_coach.dart `_applyKeyedCoachRows`, `keyedFingerprints` and the echo skip
- **claim:** a keyed row and an unkeyed row that both lack a parseable `created_at` fingerprint as `text|null` and the
  unkeyed one is dropped as an echo.
- **fix:** the echo skip requires the unkeyed row to have an instant (one guard; a second, keyed-side guard was tried
  and removed because the two were mutually redundant, each surviving its own mutant). Test k24; mutant R17 red.
- **status:** accepted

## Finding A4 — P3 — blast_radius_mismatch (deploy order)
- **claim:** until ai-proxy / ai-media-proxy are deployed, a new-build turn makes an unkeyed server row, and a push more
  than 5 minutes later can upload a keyed orphan next to it (the original double).
- **status:** no_change_needed: already plan C7 ("step 2 is a HARD prerequisite of shipping any client build"), the PR
  body and OI-503's entry; the deploy precedes the merge.

## Finding B1 — P3 — blast_radius_mismatch
- **file:line:** test/contracts/blast_radius_sync_engine_platform_test.dart, the new `_declined` entry for
  `coach_interaction_repository.dart`
- **claim:** the decline reason did not name the in-flight counter as a correctness input to the restore and push.
- **fix:** the reason now says so and names the tests an edit of the counter must keep green (k3, k19, the request test).
- **status:** accepted

## Finding B2 — P3 — guard_without_its_mirror (gate anchor)
- **claim:** with the telemetry gate anchored at `_sendKeyed(`, a new unguarded catch in `send` / `_sendBody` is invisible.
- **status:** no_change_needed: neither holds a catch or a Gemini call (`_sendBody` has none), so registering it would
  only add a "no catch block" failure; the real failure path stays covered (coordinator mutant: removing both
  telemetry calls in `_sendKeyed` fails the gate).

## Finding B3 — P3 — writer_reader_drift
- **claim:** `coach_memory_service.dart` range 80-148 may be stale after a +1 line edit.
- **status:** false_alarm: `extractAndAppendCoachingNotes` is at line 80 and its closing brace at 148 (measured).

## Founder triage notes
Coordinator triage (platform tier: the verdict is advisory; the merge still needs the founder's go).

## Tuning entry
- **2026-11-13** - blast-radius platform - 7 findings; 1 false_alarm; tuning: none to the lenses. Process note: a seat
  that cannot mutate should say which of its "clean" verdicts rest on reading alone (seat A did); the coordinator's
  mutants then found that a stub which ignores `select` hides a projection change (P10 survived until the test asserted
  the request), and that two guards for one case each survive their own mutant.
