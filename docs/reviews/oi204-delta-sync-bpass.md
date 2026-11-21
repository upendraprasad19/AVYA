---
reviewed_at: 2026-09-19T21:40:00+05:30
staged_against: oi204-delta-sync (whole-branch, three-dot main...HEAD, 23 files)
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh context-blind subagents, lens split 1-5 / 6-8)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
---

# Code Review — `oi204-delta-sync` (whole-branch B-pass)

Dispatched against the three-dot `main...HEAD` diff (23 files; the naive two-dot `main..HEAD`
is a trap on this branch — `main` independently gained 8 unrelated gates from the sibling
`discipline-gates-tier12` branch after this worktree forked, so two-dot would show them as
deleted). Blast radius confirmed **platform** via
`git diff main...HEAD --name-only | dart run scripts/blast_radius_from_diff.dart -`. Two fresh
context-blind reviewers, split across the lens set per this skill's own >15-files default
(2026-09-08 tuning entry): reviewer A lenses 1-5, reviewer B lenses 6-8 (briefed to specifically
mutate-test `check_sync_hash_skip_atomicity.dart`'s detection logic and the hash-store-ordering
atomicity itself).

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** `scripts/sync_hash_skip_atomicity_lib.dart:89-93` (pre-fix), reproduced against
  `lib/core/services/sync/sync_workout.dart:485-487`
- **claim:** The gate's `hasStore` check matches a store statement against the WHOLE file
  (`storeRe.hasMatch(stripped)`), whose `\s*` spans newlines (Dart's `\s` character class always
  matches `\n`, no flag needed). The guard-scan then separately re-ran the SAME regex against
  each individual LINE in isolation to find which line(s) to walk backward from. A store
  statement wrapped across two lines (a plausible `dart format` output for a line past 80
  columns) matches the whole-file check but matches neither half when re-run per line, so
  `storeLineIdxs` comes back empty, the backward-guard-scan loop never runs, and the function
  falls through to PASS — invisible to an UNGUARDED multi-line store, exactly the atomicity
  violation the gate exists to catch.
- **verification:** Reviewer B mutated the real `sync_workout.dart` to `exlogHashIndex[key] =\n
  fp;` with the guard removed, ran `dart run scripts/check_sync_hash_skip_atomicity.dart` — it
  printed `OK` and exited 0. Control (same defect, kept on one line) correctly FAILED, isolating
  the line-split as the defeat mechanism. Independently re-traced the regex logic by hand before
  accepting the finding (confirmed `\s*` spans `\n`, confirmed `storeLineIdxs` would be empty for
  the split case, confirmed the fall-through path).
- **suggested-fix:** Compute `storeLineIdxs` from the whole-text match set (`storeRe.allMatches`)
  mapped to line indices via each match's start offset, instead of re-matching per split line.
- **status:** accepted, fixed. `scripts/sync_hash_skip_atomicity_lib.dart`'s
  `checkDomainAtomicity` now derives `storeLineIdxs` from `storeRe.allMatches(stripped)` +
  `lineIndexForOffset(m.start)`, so both the existence check and the guard-scan agree on what
  counts as a store regardless of line-wrapping. Two new fixtures added to
  `test/scripts/sync_hash_skip_atomicity_lib_test.dart` (split-line unguarded → must FAIL;
  split-line correctly-guarded → must PASS, the fix's own mirror case). Reverted the fix and
  confirmed the new FAIL fixture reddens exactly as reviewer B's live mutation predicted
  (`Expected: not null, Actual: <null>`); restored, re-confirmed 15/15 lib + 3/3 e2e green, and
  the real gate still `OK` against production `sync_workout.dart`/`sync_nutrition.dart` (current
  code was never affected — this closes a future-regression blind spot, not a live defect).
  `docs/audit/gate_test_ledger.yaml` evidence extended. Full trace in
  `docs/diagnoses/2026-09-19-full-rescan-sync-timeout-d3f8a6.md`'s new "B-pass remediation"
  section (third commit on this branch citing `closes-diagnose: d3f8a6`).

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** `scripts/sync_hash_skip_atomicity_lib.dart:119-128` (the swallow-count check),
  reproduced against `lib/core/services/sync/sync_workout.dart:454-457`
- **claim:** The swallow-count half of the gate is a pure occurrence-count comparison — total
  textual occurrences of `<flag> = false;` must equal a hardcoded expected value. A NEW
  swallowing catch added around an unguarded call (e.g. wrapping the currently-bare
  `workout_log_exercises` summary upsert in a try/catch that forgets to set the flag false) is
  invisible: the count stays unchanged, so the gate reports OK — while the resulting bug is a
  genuine FALSE-SKIP (fingerprint stored for content that never actually reached cloud).
- **verification:** Reviewer B mutated `sync_workout.dart` to add exactly this shape (a second
  swallowing catch around the summary upsert, flag untouched); the gate printed OK. Verified this
  is ALREADY explicitly disclosed, accurately, in `docs/architecture/sync.md:147-162` — read the
  full section directly rather than trusting the citation: it names the exact mechanism
  ("changed-COUNT check, not structural... verification") and the exact failure class, and states
  the fix would need real catch-block-boundary analysis, out of scope for this mechanism.
- **suggested-fix:** Reviewer B: "no action strictly required beyond what's already written... flagging for founder triage." Independently judged during triage that the existing wording, while mechanistically accurate, undersold the actual severity (framed as "the gate can't distinguish X from Y" rather than naming the false-skip risk directly).
- **status:** accepted, addressed without a structural fix. `docs/architecture/sync.md`'s
  disclosure strengthened to explicitly name the false-skip direction and cite this finding,
  rather than leaving it as inferrable-but-unstated. The heavier fix (per-catch-block structural
  enumeration) remains a legitimate, larger, separate engineering decision — not undertaken here,
  consistent with the existing text's own scoping and reviewer B's own recommendation not to
  force it into this pass.

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** `docs/sot_registry.yaml:2161-2165` (exlog's `class_constraints:`, has the
  disclosure) vs. `docs/sot_registry.yaml:2259-2283` (nlog's, lacked it); underlying code at
  `lib/core/services/sync_service.dart:1325,1340,1342`
- **claim:** `weeklyFullSync()` calls `_syncExerciseLogs` and `_syncNutritionLogs` symmetrically,
  both outside the per-domain coalescer. The registry documents the resulting overlapping-pass
  lost-update race ONLY for the exlog concept; nlog's `class_constraints:` block has a different,
  unrelated known limitation but no equivalent statement, even though the same race applies
  identically and is safe for the same reason (a losing pass's persisted fingerprint can only ever
  be older-than-or-equal-to what's actually on cloud).
- **verification:** `sed -n '2143,2166p;2259,2283p' docs/sot_registry.yaml` confirmed the
  asymmetry directly; `sed -n '1325,1345p' lib/core/services/sync_service.dart` confirmed both
  calls happen the same way. Reviewer B independently re-traced the race for nlog and confirmed it
  holds (same reasoning as exlog).
- **suggested-fix:** Mirror the sentence into nlog's `class_constraints:` block.
- **status:** accepted, fixed. Sentence added to `docs/sot_registry.yaml`'s
  `sync_nutrition_log_payload_hash_index` concept, citing this finding and the same reasoning.
  `dart run scripts/check_sot_registry_parity.dart` PASS after the edit (0 errors; 1 pre-existing
  unrelated orphan-class warning for `CoachMediaRepository`, not touched by this batch).

## Finding 4 — P3 — writer_reader_drift
- **file:line:** `lib/core/services/sync/sync_workout.dart:532-575` (`_resolveCompletedAt`,
  pre-existing/unmodified by this diff) interacting with the new
  `lib/core/services/sync/sync_workout.dart:313-329` (`summaryPayload` construction) and
  `sync_service.dart:1722-1733` (`exlogPayloadFingerprint`)
- **claim:** `_resolveCompletedAt`'s last-resort fallback
  (`return DateTime.now().toUtc().toIso8601String();`, already telemetry-flagged as
  `sync_completed_at_fallback` when hit) feeds `summaryPayload['completed_at']`, which
  `exlogPayloadFingerprint` hashes. For a row that hits this fallback, `completed_at` — and
  therefore the fingerprint — changes on every pass, so `exlogShouldSkipUpsert` can never return
  true for that key: the OI-204 optimization silently never engages for it, falling back to the
  pre-fix always-push behavior. Fails safe (no data loss, no incorrect skip). Not discussed in the
  diagnose-doc's "Known limitations" (which names a different gap).
- **verification:** Read `sync_workout.dart:539-574` directly — confirmed the fallback is the 7th
  and last resolution tier, past `created_at`/`completed_at`/`logged_at`/`updated_at_ms`/
  `completed_at_ms`/`dateKeyPrefix`. Confirmed `completedAt` (from `_resolveCompletedAt`) flows
  into `summaryPayload['completed_at']` at line 329, and `summaryPayload` is passed directly to
  `exlogPayloadFingerprint` at line 429. Confirmed the diagnose-doc's pre-existing "Known
  limitations" section covers only the `check_schema_column_refs.dart` gate-coverage note, not
  this interaction.
- **suggested-fix:** (a) document as an accepted, self-limiting edge case, or (b) exclude
  `completed_at` from the fingerprint when produced via the fallback path (needs
  `_resolveCompletedAt` to signal provenance, a larger change). Reviewer A recommended (a) as
  proportionate given the existing telemetry.
- **status:** accepted, fixed via (a). New "Fingerprint-determinism note" bullet added to
  `docs/diagnoses/2026-09-19-full-rescan-sync-timeout-d3f8a6.md`'s "Known limitations" section.

## Lens coverage — reviewer A (lenses 1-5), no further findings
Extensively verified clean with evidence, not merely asserted:
- **writer_reader_drift** (remainder): sole-writer/sole-reader for both new Hive indices
  confirmed structurally (`part of '../sync_service.dart'` shared-library privacy) and by
  repo-wide grep (matches ONLY inside the three expected files). Hive-key string literals in
  `simulation_service.dart`'s `resetJourney` byte-match the `sync_service.dart` consts. Cloud
  writer surface matches the SoT registry exactly. "No out-of-band cloud mutator" independently
  re-verified live: `grep -n 'from("workout_log_exercises")\|from("workout_log_sets")\|
  from("nutrition_logs")\|from("nutrition_log_items")' -r supabase/functions/` → 14 call sites,
  all `.select(`, zero writes. Nutrition slot-key trim/liveness computation traced end-to-end and
  confirmed not a drift (both sides consume the same already-trimmed `mergeNutritionLogsBySlot`
  output). `_deterministicId` confirmed a true deterministic hash.
- **function_exception_swallow**: N/A — zero `.functions.invoke(` calls anywhere in the 23-file
  diff.
- **blast_radius_mismatch**: satisfied — `docs/blast_radius.yaml:63` confirms `platform` for the
  touched glob; platform's `requires:` (regression_test, behavioral_test_path, code_review_b_pass,
  feature_flag) all traced end-to-end, including tracing both new kill-switches
  (`disable_exlog_hash_skip`/`disable_nlog_hash_skip`) through to a byte-identical-when-disabled
  guarantee, not just grepped for existence.
- **secrets_in_tree**: N/A — zero credential-shaped literals across all 21 files in the diff.
- **unawaited_no_error_sink**: satisfied — every `unawaited(` added/touched wraps
  `ErrorTelemetry.logEvent`/`recordNonFatal`, this repo's established sink, inside a catch nested
  in an outer per-key catch that cannot let an exception escape the sync loop.

## Lens coverage — reviewer B (lenses 7-8), no further findings
- **missing_input**: every new path/symbol the diff's code and tests read verified to exist with
  the assumed shape — the e2e test's `scrubbedChildEnvironment` import, both `resetJourney`
  literal-string assertions (grepped live, both present, well inside the method body), every new
  `cloud: columns:` list cross-checked against `backups/live_schema_columns.json` for all 4
  tables, all 3 pre-existing contract tests this diff's restructure broke confirmed correctly
  repointed (not loosened) with measured character-distance slack.
- **asserted_fixture_value**: every UUID-shape assertion is structural, not an invented literal;
  every "flips the fingerprint" test compares two computed values; the two exact-store-call-site-
  count tests and the nlog clear-on-revert test independently confirmed NOT vacuous (would fail if
  the feature did nothing); no new assertion depends on shared/live mutable state (every new test
  is pure-static or uses an isolated temp-dir Hive box); the three-state (absent/stale/matching)
  shape traced and confirmed handled, including the cold-start case (no prior index entry at all
  → full push, same as pre-existing behavior, no OI-162-slice-3a-class regression). The
  `weeklyFullSync` race safety claim was RE-DERIVED by hand (not merely read) for exlog, which is
  what surfaced Finding 3 (the same claim, un-mirrored, for nlog).

## Founder triage notes
All 4 findings accepted and closed in this same batch (no deferrals): Findings 1 and 3 fixed in
code/docs; Finding 4 fixed via diagnose-doc documentation; Finding 2 verified already correctly
(if under-emphasized) disclosed, wording strengthened rather than attempting the larger structural
fix reviewer B itself did not recommend forcing into this pass.
