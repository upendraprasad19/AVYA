---
bug_id: c4e8b2
date: 2026-09-08
batch: regen-wave-alignment
status: fixed
blast_radius: platform
related_bugs: [a9f3c7]
recurrence: >
  Writer/reader drift across the cloud seam — the repo's most-recurrent class (15+). The specific
  shape here is one the class file had not recorded: not a renamed field, but the SAME field
  carrying two different ENCODINGS on either side of a round-trip, with the restore ordered so the
  wrong one wins.
symptom: >
  After any cloud restore — reinstall, new device, or the background restore most returning users
  get on cold start — every Train-screen day badge read one too high. Monday of week 1 rendered
  `D2`; Sunday of week 1 rendered `D8`, a day number that cannot exist in a seven-day week.
  `preview_plan_provider.dart:117` also MATCHES on that number, so a shifted value silently fell
  through to its positional fallback at `:122`.
concept: >
  `day_of_week` has one meaning in the app — 0=Mon..6=Sun — asserted at
  `tool_dispatcher.dart:695` in a comment and relied on by every reader
  (`train_provider.dart:619` and `:816` compute `(week - 1) * 7 + day_of_week + 1`). Dart's
  `DateTime.weekday` is 1..7, so every writer has to remember to subtract one. Most did. The sync
  push did not: it discarded the correct stored value and re-derived `parsedDate.weekday`.

  What made it durable rather than transient is the ORDER of the restore's merge. The cloud value
  was written AFTER the `...existingMap` spread, so it overwrote a correct local 0..6 with a wrong
  1..7 on every restore. A field that is a pure function of the row's own date was being
  round-tripped through the network and coming back worse.

  The fix therefore belongs on the READ side even though the WRITE side is what was wrong: the
  restore now derives the value from `scheduled_date` and ignores the wire entirely, which
  self-heals every already-corrupted cloud row with no migration. A push-only fix could not do
  that, because a row nobody edits is never re-pushed.
sot_registry_entry: workout_schedule_read_path
sot_registry_note: >
  No new concept, and the citation was corrected before landing: an earlier draft named
  `workout_schedule_restore`, which does not exist in the registry —
  `check_sot_registry_citations.dart` caught it at commit time. `day_of_week` is read by the
  schedule read path (`train_provider` → `dayNumber` → the `D<n>` badge), which is exactly where
  the corruption surfaced, so that is the concept this fix belongs to. This batch makes the
  restore DERIVE rather than trust, narrowing the contract rather than widening it, and gives the
  0..6 canon ONE definition (`dayOfWeekFromDate`) instead of a re-implementation at each writer —
  which is what let two of them disagree in the first place.
writers:
  - { file: lib/core/utils/date_utils.dart, method: "dayOfWeekFromDate — NEW; the single definition of the 0=Mon..6=Sun canon", line: 50 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "push payload — sends the stored value, falling back to the derived one; previously sent raw weekday (1..7)", line: 1633 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "_restoreScheduledWorkouts — derives day_of_week from scheduled_date instead of trusting the wire", line: 1975 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "restore merged map — the key that used to overwrite a correct local value", line: 2012 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "dayNumber = (week-1)*7 + day_of_week + 1", line: 619 }
  - { file: lib/features/train/screens/train/week_rows.dart, method_or_widget: "renders D<n> from dayNumber", line: 54 }
hive_key_prefix: schedule_
hive_key_formula: "workoutBox['schedule_<yyyy-MM-dd>']['day_of_week'] — 0=Mon..6=Sun, now derived from the row's own date on restore."
sync_methods: >
  `_syncScheduledWorkouts` builds the push payload (`sync_workout.dart:1633`). It now sends the
  stored 0..6 value and only derives when that is absent, rather than preferring a re-derivation
  and getting it wrong.
restore_methods: >
  `_restoreScheduledWorkouts` (`sync_workout.dart:1975`, applied at `:2012`) computes
  `dayOfWeekFromDate(date)` from `scheduled_date` and falls back to the transmitted value only
  when the date will not parse. Because the derivation ignores the wire, rows already corrupted in
  the cloud heal on the next restore with no migration.
cloud_table: scheduled_workouts
cloud_columns: [day_of_week, scheduled_date, week_number]
contract_test_path: test/contracts/day_of_week_canon_writer_to_reader_test.dart
ist_handling:
  - { file: lib/core/utils/date_utils.dart, line: 50, fn: "dayOfWeekFromDate parses the already-IST 'yyyy-MM-dd' key that formatDateKey/istDateStr produced. It derives a weekday from a date STRING and builds no new key, so no timezone conversion is introduced or needed." }
provider_invalidations: >
  None added. The restore already invalidates the workout providers on completion; this changes
  only the value one key carries.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — the restore path already runs under the user-scoped box guard; this batch
  changes a derived value inside it, not the scoping.
forbidden_patterns_checked: >
  - The absent-pattern assertions in the contract test STRIP COMMENTS FIRST, using the same
    stripper the new gate uses. This is not decorative: the fix's own comments quote the old
    literal (`'day_of_week': parsedDate?.weekday`) to explain what went wrong, so a raw grep for
    that literal's absence fails on the documentation of the fix. Same self-trapping shape as a
    migration header quoting the value it replaced.
  - `parsedDate` was DELETED rather than left unused — an unused local is a WARNING, and
    `flutter analyze --no-fatal-infos` at pre-push fails on warnings, not just errors.
proposed_fix: >
  Add `dayOfWeekFromDate(String date)` to `date_utils.dart` as the single definition of the canon.
  Restore derives from `scheduled_date`; push sends the stored value and only derives as a
  fallback. Delete the now-dead `parsedDate` local.
regression_test_planned: >
  `test/contracts/day_of_week_canon_writer_to_reader_test.dart` — 13 assertions: the canon
  (Mon=0, Sun=6), a full-week sweep, an explicit "never returns 1..7" guard, unparseable input,
  and the READER's own arithmetic reproduced so the test fails if `D1` ever becomes `D2` again.
  Plus source pins on both sync seams and the hotel planner, and 5 on the kill-switch below.
  MUTATION-PROVEN, three legs, each leaving the file compiling:
  (A) restore the defect (`parsed.weekday` instead of `parsed.weekday - 1`) → 4 of 13 red.
  (B) invert the kill-switch polarity (`!=` → `==`, i.e. opt-out becomes opt-in so the DEFAULT
  becomes the broken path) → 4 red. This is the regression that would ship the bug silently.
  (C) delete the gate from the restore wiring so the legacy arm is unreachable → 1 red.
feature_flag: >
  `SyncFlags.deriveDayOfWeekOnRestore` — `configBox['disable_day_of_week_derive']`.
  Required by the `platform` tier's `requires:` list (`docs/blast_radius.yaml:25`) and by §4.6
  (this touches `sync`). ⚠ Added only after the B-pass flagged its absence: nothing ENFORCES that
  `requires:` list — `check_blast_radius_coverage.dart` never reads it — so the full 78-gate loop
  passed green on a platform-tier sync change with no flag at all. It is a review-read
  requirement, and review is the only thing that caught it.

  POLARITY IS OPT-OUT, deliberately, and this is the one judgement call worth arguing with.
  §4.6 step 1 reads as "default the NEW path behind a gate", which would mean default-OFF. Here
  default-OFF preserves a path that is KNOWN BROKEN — every restored row's badge one too high —
  so a flag whose safe-looking default is the bug is not a safety mechanism. §4.6's actual
  requirement, step 2, is *"old path preserved verbatim, reachable when the gate is closed"*, and
  that is satisfied exactly as written. The repo already ships `disable_phase_arc` and
  `disable_triggered_deload` in this polarity.

  The PUSH side is deliberately NOT gated: reverting it would re-introduce writing 1..7 to the
  cloud, which is the defect itself, and with the restore deriving, the transmitted value is never
  read — so a push kill-switch would protect nothing while adding a branch to a sync path.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ — 0 errors, 0 warnings. The dead `parsedDate` local surfaced as a warning and was removed." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "day_of_week_canon_writer_to_reader_test.dart 8/8; 71/71 across the eight sync + schedule contract suites re-run for collateral damage." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "scheduled_workouts.day_of_week is a bare int with no CHECK and no comment (002_create_fitness_tables.sql:104) — no server-side contract to honour." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Existing rows hold 1..7 and are NOT migrated, deliberately: the restore now ignores the transmitted value, so they heal on next restore." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, name: edge_function_deploy, status: verified, evidence: "grep -rn 'day_of_week' supabase/functions/ returns 0; positive control 'scheduled_workouts' returns 5 files. No Edge Function reads this column, so no redeploy is implied." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads day_of_week." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object touched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "The round-trip is the bug. Push and restore now agree on 0..6, and the restore no longer depends on the push being right." }
impact_analysis: >
  Affects every user whose schedule rows have round-tripped through the cloud — which is most
  returning users, since the background restore runs on cold start. Display-only: no workout, log,
  streak or PR is altered, and no row is deleted or moved. The visible change is that day badges
  become correct on the next restore.

  Not migrated on purpose. Deriving on read means the corrupt cloud values simply stop being read;
  a migration would touch every user's rows to fix something the client can now recompute for free.

  ⚠ Scope boundary worth stating: this closes the CLOUD half of the off-by-one. The local half in
  `hotel_workout_planner.dart` is fixed in the same batch under bug a9f3c7. Both were the same
  mistake made independently, which is precisely why the canon now has one definition.
---

# `day_of_week` round-tripped as 1..7 and overwrote the correct local 0..6

See the frontmatter. Two things worth keeping.

First, the ordering is what made it durable. The restore wrote the cloud value after the
`...existingMap` spread, so a correct local value was overwritten every time. Had the key been
placed above the spread, the same wrong push would have been harmless.

Second, the fix direction was not obvious from the symptom. The push is what was wrong, but fixing
only the push would have left every already-stored row corrupt until something happened to
re-push it. Deriving on restore — from a value that was always a pure function of the row's own
date — makes the wire value irrelevant and heals the existing data as a side effect.
