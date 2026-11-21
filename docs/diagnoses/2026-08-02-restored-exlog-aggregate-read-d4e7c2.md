---
bug_id: d4e7c2
date: 2026-08-02
batch: Unit 7 (OI-25/44/45/46/48/50 batch) — closes OI-50
status: fixed
blast_radius: account
symptom: |
  A cloud-restored workout renders wrong on two surfaces. The receipt shows
  0 duration for a timed/cardio exercise that has a real total, and the Edit
  Workout Log sheet shows a BLANK sets box and a BLANK duration box for the
  same row — after which saving writes the blank back as 0, destroying the
  real total. The two surfaces also disagree with each other on the same row.
concept: workout_receipt_rendering + workout_log_edit_surface (exlog aggregate read)
sot_registry_entry: workout_receipt_rendering, workout_log_edit_surface
writers:
  - { file: lib/core/services/sync/sync_workout.dart, line: 763, method: restore exlog set_number }
  - { file: lib/core/services/sync/sync_workout.dart, line: 766, method: restore exlog top-level duration_seconds }
  - { file: lib/core/services/sync/sync_workout.dart, line: 803, method: restore exlog sets[] (conditional) }
  - { file: lib/core/services/workout_write_service.dart, line: 180, method: logExercise stamps set_number }
readers:
  - { file: lib/features/train/widgets/workout_receipt_card.dart, line: 367, method: fromExerciseLogs set count }
  - { file: lib/features/train/widgets/workout_receipt_card.dart, line: 434, method: fromExerciseLogs effectiveDuration }
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, line: 1033, method: EditLogExerciseRow.fromLog sets }
  - { file: lib/features/train/widgets/edit_workout_log_sheet.dart, line: 1042, method: EditLogExerciseRow.fromLog duration }
  - { file: lib/features/train/widgets/week_selector.dart, line: 830, method: _ExerciseLine duration (round-1 F1) }
  - { file: lib/features/train/screens/train/exercise_preview_sheet.dart, line: 127, method: cumulative fallback label (round-1 F1) }
  - { file: lib/features/train/screens/train/expanded_exercises.dart, line: 70, method: cardio total (round-1 F1) }
  - { file: lib/features/train/repositories/workout_repository.dart, line: 941, method: getExercisePRHistory sets (round-2, the sixth reader) }
  - { file: lib/core/services/workout_read_service.dart, line: 186, method: aggregateSetCount (new shared reader) }
  - { file: lib/core/services/workout_read_service.dart, line: 202, method: hasAggregateSetCount (new shared reader) }
  - { file: lib/core/services/workout_read_service.dart, line: 227, method: aggregateDurationSeconds (new shared reader) }
hive_key_prefix: exlog_
hive_key_formula: WorkoutWriteService.exlogKey(date, name) — UUID v5 over lowercase+trim(name) + IST date
sync_methods: SyncService._syncExerciseLogs (push), sync_workout.dart restore loop (pull)
restore_methods: sync_workout.dart restore exlog loop (the writer that produces the failing shape)
cloud_table: workout_log_exercises + workout_log_sets
cloud_columns: set_number, duration_seconds, reps, weight_kg, distance_km, exercise_name, workout_log_id
contract_test_path: test/contracts/exlog_aggregate_read_behavioral_test.dart
ist_handling: |
  Unchanged. The exlog row's `date` key is IST (WorkoutWriteService.istDateStr);
  this fix touches only aggregate VALUE reads, never a date key or boundary.
provider_invalidations: |
  None added. The two readers are called inside existing render/build paths
  that already run under their current invalidation sets; no new provider and
  no new write path is introduced by this fix.
telemetry_op_types: exlog_no_aggregate_signal (new, receipt-side)
cross_account_guard: |
  Unchanged. Both readers receive rows already fetched through
  wrapUserScopedBox-backed paths (workoutBox via HiveService /
  WorkoutRepository.getExerciseLogsForDate). No raw Hive.box access added.
forbidden_patterns_checked: |
  No raw Hive.box( in the diff; no inline isPro check; no setState for shared
  state; no hardcoded colors; no new unawaited without an error sink (the one
  telemetry call uses the established fire-and-forget
  `// ignore: discarded_futures` + ErrorTelemetry.logEvent idiom, matching
  home_provider.dart and todays_meals_card.dart).
proposed_fix: |
  One shared aggregate reader on WorkoutReadService — aggregateSetCount,
  hasAggregateSetCount, aggregateDurationSeconds — with both surfaces routed
  through it, plus a hasAggregateData flag on EditLogExerciseRow so an absent
  count is distinguishable from a logged zero, plus receipt-side telemetry when
  a row carries no aggregate signal at all.
regression_test_planned: |
  test/contracts/exlog_aggregate_read_behavioral_test.dart — 23 tests.
  Behavioral, driven through the real readers against a Hive row in the exact
  restore shape. Negative controls recorded below. Plus a rewrite of
  test/contracts/no_top_level_duration_seconds_reads_test.dart, whose old
  failure message actively recommended the call that causes this bug.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze reports No issues found across all 7 changed lib files; 63 tests green across the new behavioral file plus 9 adjacent receipt/exlog/PR contract tests" }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "test/contracts/exlog_aggregate_read_behavioral_test.dart groups B and D seed a real restore-shaped exlog row into workoutBox and drive WorkoutReceiptData.fromExerciseLogs" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "no schema change; workout_log_exercises.duration_seconds and .set_number already exist and are already populated by the push path (diagnose a2b3c4)" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "read-side-only client fix; no cloud rows written or migrated" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this batch" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change; no new cloud read" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no Storage object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret referenced" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service touched" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "traced the full loop: cloud workout_log_exercises to sync_workout.dart restore writer to the exlog Hive row to both readers; the failing shape is produced at sync_workout.dart:763-766 with sets[] written only under the :777 guard" }
impact_analysis: |
  Affects any user who has restored from cloud — a reinstall, a new device, or
  a second device — and whose workout_log_sets join came back empty for an
  exercise. Free and PRO alike. No data was lost in the cloud; the loss was
  local and on-screen, except for the edit-sheet save path, which could write
  a blank duration back over a real total (a genuine local data loss). Fixing
  the read also stops that write. Not reproducible on a device that has never
  restored, which is why it survived: every client-side writer produces the
  shape the readers expected.
---

# Restored `exlog_*` rows are mis-read by the receipt and the edit sheet

## What OI-50 actually was

OI-50 was filed (2026-05-17) as "23 risky accesses across 6 files" and corrected
on 2026-07-29 down to **2 confirmed silent-wrong sites**. Both corrections were
right about the count and still understated the defect, because they described
the two sites as independent null-guard nits. They are one bug:

> The cloud-restore writer emits a **different subset of the exlog aggregate
> fields** than the client-side writer, and each of the two readers hand-rolled
> its own reconciliation of that. One reconciliation was incomplete and the
> other was semantically wrong.

## Writers

| writer | `set_number` | `sets_completed` | top-level `duration_seconds` | `sets[]` |
|---|---|---|---|---|
| `workout_write_service.dart:180` (modern) | ✅ | ❌ | ❌ (that field is on the `wlog_` row, `:477`) | ✅ always |
| `sync_workout.dart:733-767` (restore) | ✅ `:763` | ❌ never | ✅ `:766` | **only when the `workout_log_sets` join is non-empty** (`:777`, `:803`) |

The empty-join case is reachable three ways, all in shipped code:
1. the `restore_exercise_log_sets_fetch` fetch fails and is caught (~`:704`) — the
   join map is then empty for **every** exercise in the restore;
2. the `'$workoutLogId|$exerciseId'` group key misses (`:773-776`);
3. genuinely old cloud data with summary rows but no per-set rows.

## Readers, and the two defects

**Defect 1 — receipt renders 0 duration.** `workout_receipt_card.dart` had
`const int duration = 0` and derived the total purely from the per-set sum, so
with no per-set array `effectiveDuration` was 0.

The hardcode came from the 2026-05-24/T6 drift-fix, whose comment reasoned
*"`WorkoutWriteService` does NOT emit a top-level `duration_seconds` on exlog
rows … the pre-fix top-level read was dead — always 0 for modern rows."* That
sentence is **true and insufficient**: it is a statement about the modern writer
only, and the restore writer does emit the field. Removing a read because *one*
of two writers never populates it is the drift.

**Defect 2 — edit sheet shows a blank sets box, and blanks the duration.**
`EditLogExerciseRow.fromLog` read `log['sets_completed']` — the legacy key —
while restore stamps `set_number`. The receipt at `:358-359` had *already*
learned to MAX both keys (APK Test #12.1/#12.2); the edit sheet never got that
treatment, so the two surfaces disagreed on the same row.

Worse, its duration box used `WorkoutReadService.bestPerSetDuration`, a per-set
**MAX**, for a box whose value `save` writes straight to top-level
`duration_seconds` — a **SUM** by the writer contract. `bestPerSetDuration`
gates its top-level fallback on `setCount <= 1`, so on a restored multi-set
timed row it returned 0, the box rendered blank, and saving wrote 0 over the
real total.

## Refuted during investigation

Recorded rather than dropped, per §4.1:

- **"A downward edit can never take."** Hypothesis: the receipt MAXes
  `set_number`/`sets_completed` while the sheet saves only `sets_completed`, so
  editing 5 sets down to 3 would still render 5. **False** —
  `workout_write_service.dart:754-757` normalizes `sets_completed` into
  `set_number` on write, and the sheet routes through
  `WorkoutWriteService.instance.editLog` (`edit_workout_log_sheet.dart:267`).
  The write side was already correct; only the read side had drifted.
- **"A migrator already backfills this."** `hive_field_rename_migrator.dart`
  mentions the `set_number`/`sets_completed` pair only inside a **commented-out
  usage example** (`:25-31`). Nothing self-heals these rows.
- **"`lib/features/train/CLAUDE.md` wrongly lists `duration_seconds` as an exlog
  field."** Initially planned as a doc correction. **False** —
  `workout_read_service.dart:30` documents it as part of the exlog contract
  ("SUM across sets, only timed/cardio") and the restore writer really does
  write it. The doc needed a *clarification of which writer emits it*, not a
  deletion. Had the planned "fix" landed, it would have introduced an error.

## The fix

One shared reader on `WorkoutReadService` (`:186`, `:202`, `:227`):
`aggregateSetCount` (MAX across `set_number`, `sets_completed`, and both array
spellings), `hasAggregateSetCount` (absent vs logged-zero), and
`aggregateDurationSeconds` (per-set SUM canonical, top-level aggregate as the
fallback, `null` when there is no signal at all). Both surfaces now delegate,
so a third reader cannot drift again — the workout-domain equivalent of what
`NutritionReadService.deriveMealDisplayName` did for the identical nutrition bug.

`hasAggregateData` on `EditLogExerciseRow` additionally stops `save` stamping a
fabricated `sets_completed: 0` over a count that was simply absent
(`edit_workout_log_sheet.dart:255`), while preserving a deliberately-typed 0.

Receipt-side telemetry `exlog_no_aggregate_signal` fires when a row carries no
count signal at all, so the next shape regression is visible instead of mute.

**No kill-switch, deliberately** (founder call). There is no correct old
behaviour to preserve — the current output is simply wrong — and a switch whose
only effect is to restore a rendered zero is not a safety valve. Same reasoning
as Unit 3c's monotonic guard.

## Negative controls

Each behavioral assertion was run against readers reverted to their pre-fix
semantics (the shared helper and the `hasAggregateData` API left in place so the
test still compiled). Observed failures:

| assertion | expected | pre-fix actual |
|---|---|---|
| receipt duration, restored row | `300` | **`0`** |
| receipt duration, per-set row | `150` | `0` |
| edit-sheet SETS box | `'3'` | **`''`** |
| edit-sheet DURATION box | `'300'` | **`''`** |
| the two surfaces agree | equal | receipt `'4'` vs sheet `''` |

5 of the 23 fail without the fix; the other 18 exercise the new pure helper and
the new row flags directly (green by construction — the "run against the pre-fix
readers" claim applies to the 5, not to the pure-helper cases).

After restoring the fix, **63 tests pass across 10 files**: this one plus the
rewritten `no_top_level_duration_seconds_reads_test.dart`,
`edit_workout_log_sets_field_contract_test.dart`,
`hive_field_name_exlog_behavioral_test.dart`,
`workout_receipt_rendering_writer_to_reader_test.dart`,
`workout_receipt_rendering_behavioral_test.dart`,
`workout_log_edit_surface_behavioral_test.dart`,
`exercise_personal_records_writer_to_reader_test.dart`,
`receipt_scoping_test.dart` and
`duration_seconds_aggregate_populated_test.dart`.
(An earlier draft said "54 across 7 files" — 54 was measured over a 9-file set
while the list named 7. Both numbers are now measured against the list as
written; round 2 caught the mismatch.)

## Round-1 review — 6 findings, all fixed before the merge

The single most valuable finding was **F1: the scope was wrong**. I had claimed
"two readers"; there were **five** hand-rolled aggregate reads, and the fix as
first written left three of them broken. `lib/features/train/CLAUDE.md` was
edited to assert "two readers each rolled their own" — an overclaim that would
have been committed as documentation.

| # | sev | finding | resolution |
|---|---|---|---|
| F1 | P1 | Three more readers with the same defect: `week_selector.dart` (per-set MAX for a duration shown beside a set count → 0 on restored rows, so the duration vanished from the line), `exercise_preview_sheet.dart` (its own comment calls the value "cumulative" while reading a per-set MAX), `expanded_exercises.dart` (a variable named `totalDuration` holding a MAX, rendered as the cardio total). All three ALSO hand-rolled the 4-source set-count MAX. | All routed through the shared helper. `perSetMaxDur` in `expanded_exercises` deliberately left as `bestPerSetDuration` — that branch labels its output "best". |
| F2 | P1 | `no_top_level_duration_seconds_reads_test.dart` scanned only `lib/features/train/`, so this fix legally reintroduced the banned read one directory away — and its failure message said *"Use `WorkoutReadService.bestPerSetDuration(log) ?? 0` instead"*, which is the call that CAUSES this bug. A gate whose remediation advice reproduces the defect it guards. | Rewritten: scans `lib/features/train/` **and** `lib/core/services/` with two named exemptions (the canonical reader; the `wlog_*` push projection), and the message now picks by semantic. Plus a second test that fails if an exemption goes stale. |
| F3 | P2 | `_perSetList` used `log['sets'] ?? log['sets_detail']` — null-coalescing, so a row with `sets: []` **and** a populated `sets_detail` resolved to the empty list. The receipt's pre-Unit-7 code measured both lengths and MAXed them, so my in-code claim "Semantics unchanged" was false. | Takes the LONGER of the two arrays. Test added. |
| F4 | P2 | The new telemetry sits in a build path (`home_screen` reaches `fromExerciseLogs` from `build`), so it could post once per no-signal row per rebuild. The cited precedent lives in a *provider* — the pattern was not actually mirrored. This repo has a documented free-tier telemetry collapse (c4f8d2 / b4f7e2). | Deduped to once per `(date, exercise)` per process. |
| F5 | P2 | The save guard covered only `sets_completed`. Worse, the **per-set** branch writes `duration_seconds = 0` when the per-set rows carry no durations — so a restored row with `sets[]` but no per-set durations would have its real total wiped on any save. The read fix newly *exposes* that: the receipt now shows the total, so the user would watch it vanish. | `hasAggregateDuration` added; both save branches guarded. `reps_completed`/`weight_kg`/`distance_km` deliberately left unguarded and the reasoning recorded in-code — no other key holds a surviving value for them, so a fabricated 0 destroys nothing. |
| F6 | P3 | Test count stated as 14; actually 19 at the time (22 now). `editLog` cited at `:233`; it was `:243` then and `:267` now. | All corrected against a fresh read. |

Findings the reviewer raised that I checked and did **not** act on:
- The `Map<String, dynamic>.from(log)` cast can in principle throw on a
  non-String Hive key — but identical `.from`/`.cast` conversions already sit on
  the same rows at `workout_read_service.dart:263/275/306` and in `editLog`, and
  every writer builds `Map<String, dynamic>`. No new crash class.
- `expanded_exercises.dart`'s `perSetMaxDur`: the reviewer read it as the same
  defect. It is not — that branch renders `'$sets sets · best $dur'`, so a
  per-set MAX is the correct semantic. Its sibling `totalDuration` WAS wrong,
  and I nearly deleted it as dead code before checking: it is live in the cardio
  branch at `:83`.

## Round-2 review — every finding was a round-1 regression

Exactly the §4.12.1 signature, for the second batch running: round 2 was told its
primary job was to attack round 1's corrections, and **it found nothing wrong
with the original work** — all four material findings trace to the round-1 fixes.

| # | sev | finding | resolution |
|---|---|---|---|
| N1 | P1 | **A sixth reader**, missed by the round-1 sweep: `workout_repository.dart:941` (`getExercisePRHistory`) read only `sets_completed`, so every restored row reported 0 sets — and its consumers are `ai_snapshot_builder` and `pattern_detector`, i.e. a restored user's **AI coach** reasoned over zeroed set history. Made my freshly-written CLAUDE.md "FIVE readers" claim wrong on arrival. | Routed through `aggregateSetCount`. CLAUDE.md corrected to SIX, with an explicit warning that the count has already moved twice. **Not** applied to `:978` — the reviewer recommended it, but that site reads the legacy EMBEDDED `exercise_logs` shape where `sets` is a scalar, so `aggregateSetCount` (which treats `sets` as a List) would have been a new bug. |
| N2 | P2 | My own round-1 fix made `expanded_exercises.dart` render a **total** under the label "best": both arms of `perSetMaxDur > 0 ? perSetMaxDur : totalDuration` used to be the per-set MAX, so the label was always truthful; changing the fallback to the aggregate broke that — precisely for the restored rows this batch targets. | Label now follows the value: `'best'` vs `'total'`. |
| N3 | P2 | My round-1 `hasAggregateDuration` guard made a duration **permanently un-clearable** on any row holding both per-set durations and a top-level total. The user zeroes every box → the guard drops the write → `editLog` MERGES rather than replaces → the stale top-level total is read back forever. | Added `hadPerSetDuration`; the guard now requires that the original row had **no** per-set duration, so it only protects the case where the top-level value is the sole copy. Test added. |
| N4 | P3 | Round 1's own numeric corrections were still wrong: three reader line-refs landed on comment lines, the body contradicted its own frontmatter on the helper line numbers, and "54 tests" was measured over 9 files while the list named 7. | All re-measured and corrected. The lesson is not "count more carefully" — it is that **every line number in this doc moved twice** as the fixes landed, so citations must be re-derived after the LAST edit, never carried forward. |

Sound on review: the widened gate (verified to fail on an injected violation),
the `_perSetList` longer-array change (no writer produces a longer-and-staler
`sets_detail`, so the hypothesised worse case is unreachable), and the telemetry
dedupe.

**A process finding worth more than any of the above:** the round-2 reviewer ran
its own negative control by injecting a violation into `week_selector.dart` and
then "reverting" it — which restored that file to git HEAD and **silently wiped
this batch's edit to it**. Caught only because a later grep for the citation line
returned nothing. A read-only reviewer that writes to the tree can destroy work,
and `git status` still looked plausible. Every subsequent claim was re-verified
against the tree rather than against the review report.

## Recurrence

Writer/reader field drift — this repo's most recurrent class (≥15× since APK
Test #6), and the third instance on this exact surface:

- `e1f8a2` (2026-05-12) — the edit sheet read only `sets_detail` while the
  modern writer wrote `sets`, so the per-set path was bypassed entirely.
- `a2b3c4` (2026-05-12) — `workout_log_exercises.duration_seconds` was 100% NULL
  in the cloud because the push projection read a field the writer never wrote.

All three are the same shape: **a reader keyed to one writer's field spelling
when two writers exist.** The structural answer applied here — one shared reader
rather than a third hand-rolled reconciliation — is the one `lib/CLAUDE.md`
already prescribes for this class.
