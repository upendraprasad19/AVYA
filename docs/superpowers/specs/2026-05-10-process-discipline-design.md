# Process discipline foundation — design

**Date:** 2026-05-10
**Author:** Claude (brainstormed with founder, locked decision-by-decision)
**Status:** spec — pending plan
**Batch:** APK Test #13 / process-discipline-batch
**Branch:** `feat/process-discipline-batch`

---

## Goals

Convert process-discipline rules from read-once memory files into mechanical gates that block commits, builds, and merges. Make it impossible (not "discouraged") to ship the kind of regression that has bitten the founder across APK Tests #12.5 → #12.9 inclusive.

Specifically, prevent these recurring failure modes from reaching `main`:

1. **F1 — class-vs-instance scope error.** I patch ONE reader/writer when the class spans many.
2. **F2 — same-concept SoT mismatch.** Two surfaces read from different sources for the same logical concept.
3. **F3 — cold-start race / provider invalidation gap.** Day rollover, restore ordering, etc.
4. **F4 — sync gap.** Local Hive write that never reaches cloud (or cloud write that never restores).
5. **F5 — telemetry / contract payload-shape drift.** Cross-process boundary contracts silently break.
6. **F6 — "pre-existing test failure" excuse.** Banned in CLAUDE.md rule 20 but kept happening.

## Non-goals

- New feature work.
- Bug fixes outside the 3 Sunday observations (today-card vs calendar mismatch, day rollover, Saturday workout vanished).
- Migration 051 (template_exercises UNIQUE) — still deferred from #12.7.
- Test #4 audit findings (11-P0 list) — separate batch.
- ai_coach_repository profile.full_name probe — deferred from #12.8.

## Locked decisions (Q1–Q9 from brainstorm)

| Q | Topic | Locked answer |
|---|---|---|
| Q1 | Enforcement scope | **A** — enforce all 6 failure modes mechanically (not memory files) |
| Q2 | Spec structure | Single cohesive batch, no incremental APKs, ONE final APK at end |
| Q3 | Discipline checklist content | **L3** — 12 mandatory questions per bug |
| Q4 | Subagent enforcement | **M3** — agent-brief preamble + main-thread validator script + main-thread runs `/diagnose-bug` for bugs it owns directly |
| Q5 | SoT registry completeness | Per-concept schema with hive/cloud/writers/readers/restore_methods/provider_invalidation_set/contract_tests/integration_tests/ist_sites/telemetry/edge_function_payloads/forbidden_legacy_patterns. ~30 concepts target. Plus a registry-completeness test that asserts every `_syncX`/`_restoreX`/`logXxx` method in `lib/core/services/` is registered. |
| Q6 | `/build-apk` gates | All 14 gates. `flutter analyze --fatal-infos`. 8 new `scripts/check_*.dart`. `--emergency-bypass` flag with `+Ne` versionCode suffix. |
| Q7 | Cleanup strategy per drift type | Hive field rename → one-shot migrator with shadow-box backup. Cloud column rename → Postgres migration + alias. Hive key prefix → migrator + sweep. Provider/literal drift → code rename + audit test. Op_type/payload drift → rename in client+server same commit + Gate 12. Pre-cleanup `pg_dump` + ADB Hive pull from founder's device. |
| Q8 | Diagnose-doc format | YAML frontmatter (14 machine-validated fields) + free-form body. Path `docs/diagnoses/YYYY-MM-DD-<slug>-<6-char-id>.md`. Status enum: investigating / proposed / implementing / shipped / regression / deferred. |
| Q9 | Backfill scope | Last 10 batches (#12 onwards). ~50-55 retroactive diagnose-docs. 4 parallel subagents. |

## Architecture

### The discipline checklist (L3, 12 questions)

Every bug fix MUST answer these 12 questions (machine-validated) before any code change:

1. **Symptom** — one observable sentence.
2. **Concept** — name from `sot_registry.yaml` (must resolve).
3. **Writers** — every writer of this concept by `file:line` (run grep, paste output).
4. **Readers** — every reader by `file:line`.
5. **Hive key prefix + formula** — exact Dart expression.
6. **Sync methods** — which `_syncX()` methods touch this.
7. **Restore methods** — which `_restoreX()` methods.
8. **Cloud table + columns** — schema reference.
9. **Existing contract test path** — or "must add new contract test".
10. **IST handling** — every `DateTime.now()` / date-key / time-of-day site.
11. **Provider invalidation set** — Riverpod providers that must be invalidated after a successful write.
12. **Telemetry op_types** — success and failure paths.

Plus 2 boolean checks: cross-account guard (uses `MigratedKey`?), forbidden patterns absent.

### Enforcement layers

**Investigation time:** Main thread invokes `/diagnose-bug` skill (interactive). Subagents receive the agent-brief preamble in their prompts (mandatory).

**Output time:** Both produce a YAML stanza or full diagnose-doc, validated by `scripts/validate_*` Dart CLIs.

**Commit time:** Pre-commit hook rejects bug-fix commits (`fix:` / `bug:` / `regression:`) unless they reference a valid `closes-diagnose: <id>` doc.

**Build time:** `/build-apk` runs all 14 gates including the diagnose-doc audit. Refuses to build if any gate fails.

**Merge time:** Worktree branch only merges to main after all build gates pass on a fresh build.

## Phase plan

### Phase 1 — Foundation

7 artifacts. Ships nothing user-facing.

- **A.** `docs/discipline.md` — canonical L3 doc, single source of truth. Linked from CLAUDE.md, the skill, the agent preamble, every validator.
- **B.** `.claude/commands/diagnose-bug.md` — interactive skill. Walks 12 questions, makes me paste real grep output, validates each answer, writes YAML-frontmatter doc to `docs/diagnoses/<date>-<slug>-<id>.md`.
- **C.** `docs/agent_brief_preamble.md` — copy-pasteable subagent prompt prefix. Mandatory output: YAML `diagnose_stanza` block. Failure to include = main thread rejects agent output.
- **D.** `scripts/validate_diagnose_doc.dart` — parses frontmatter, asserts 14 fields present + non-placeholder + every `<file>:<line>` resolves to real source + paths exist. Used by `/build-apk` Gate 10.
- **E.** `scripts/validate_agent_diagnose_stanza.dart` — same validation against an agent's text output. Used by main thread immediately after every Agent dispatch.
- **F.** `scripts/pre-commit.sh` extension — bug-fix commit gate. If subject matches `^(fix|bug|regression):`, body must contain `closes-diagnose: <bug-id>` AND referenced file exists AND validates via D. Waiver: `regression-test-skipped: <reason>` appends to `docs/skipped-discipline.md`.
- **G.** CLAUDE.md §6.22 — codifies the rules. Subagents must receive the preamble; their output must validate; bug-fix commits must reference a diagnose-doc; waivers logged.

**P1 acceptance:** all 7 artifacts exist; validators exit zero on hand-crafted valid sample, non-zero on samples with placeholder fields; pre-commit hook rejects ungated `fix:` commit, accepts gated one, accepts `regression-test-skipped:` and appends to log.

### Phase 2 — Audits + Cleanups

#### P2.1 — SoT registry completeness audit + fill

Main thread walks every `lib/core/services/*.dart`, identifies every `_syncX` / `_restoreX` / `logXxx` / `upsertX` / `completeX` method via grep, then groups by concept domain (Workout / Nutrition / Health / Auth / Subscription / AI-Coach / Custom / Telemetry — 8 domains).

Subagent fan-out: **8 parallel subagents**, one per domain. Each receives the agent-brief preamble (artifact C) + its concept slate + the current `sot_registry.yaml` + the full schema definition from Q5. Each agent fills its domain's concepts and emits a YAML diff block. Main thread merges all 8 diffs into `sot_registry.yaml` and runs `check_sot_registry_completeness.dart` (P3.3 / Gate 7) to validate.

If a domain's registry entry has any unresolved `<file:line>` reference or any concept missing from the schema, that domain's agent is re-dispatched with the failure reason (matches M3 enforcement). Registry grows from 19 → ~30 concepts. Every concept has a complete entry.

#### P2.2 — Backfill last 10 batches' diagnose-docs (4 parallel subagents)

| Agent | Batches owned | Approx commits |
|---|---|---|
| BF-A | #12 + #12.1–12.4 cascade | ~18 |
| BF-B | #12.5 + #12.6 | ~15 |
| BF-C | #12.7 + #12.8 | ~16 |
| BF-D | #12.9 + cross-cutting | ~3 |

Each agent receives the brief preamble + commit list + the (now-complete) registry. Per commit: produces retroactive diagnose-doc with `status: shipped` (passing) or `status: regression` (validator finds gap). Validated via E. Commits with `status: shipped_without_regression_test` append to `docs/regression-test-debt.md`.

#### P2.3 — Naming-drift audit + cleanup

Per concept in registry, audit 5 surfaces:

| Surface | Cleanup |
|---|---|
| Hive field names | Hard rename + `HiveFieldRenameMigrator` (one-shot, idempotent, shadow-box backup, gated by `migrationBox['field_rename_v1_done']`) |
| Cloud column names | Postgres migration to rename + Flutter call site updates + old column kept as a `GENERATED ALWAYS` alias until the NEXT batch's APK ships (one batch's worth of deprecation, then dropped via a follow-up migration scheduled in the next batch's plan as an explicit task) |
| Hive key prefixes | One-shot `HiveKeyMigrator` with shadow-box backup; post-migration sweep test asserts old prefix has zero keys |
| Provider/literal/widget naming | Code rename + naming-audit test (Gate 8) source-greps for forbidden patterns |
| Op_type / payload-shape | Rename in client + server in same commit + Gate 12 enforcement |

#### P2.4 — Regression-test-debt backlog

`docs/regression-test-debt.md` populated by P2.2. Every entry: `<diagnose-doc-id> · <concept> · <missing test type> · <commit-sha>`. Feeds Phase 3 prioritization.

**Pre-cleanup snapshot rails (REQUIRES FOUNDER ACTION — gating start of P2.3):**
- Main thread runs `pg_dump` of prod Postgres → `backups/cloud_pre_discipline_<timestamp>.sql` (committed to a separate `feat/backups` branch, not pushed to origin). Main thread can do this autonomously via Supabase MCP / direct connection.
- **Founder action**: founder runs `adb pull /data/data/com.icanbefitter/app_flutter/ <local-path>/founder_hive_pre_discipline_<timestamp>/` from their device-attached terminal. This is the ONLY step in P2 that requires founder cooperation — all other P2 work is autonomous. Without this snapshot, P2.3 (cleanup with Hive migrators) cannot start; main thread blocks and asks founder.
- Snapshot rail completeness is verified by `scripts/check_snapshot_rails.dart` (gate added to P2.3 entry): asserts both `backups/cloud_pre_discipline_*.sql` AND `backups/founder_hive_pre_discipline_*/` exist before any cleanup commit.

**P2 acceptance:** registry ≥30 concepts complete; ≥50 retroactive diagnose-docs validated; regression-test-debt populated; all naming-drift cleanup commits land; HiveFieldRenameMigrator + HiveKeyMigrator tested on synthetic boxes; snapshot rails captured.

### Phase 3 — Tests

#### P3.1 — Per-concept WriteService→consumer contract tests

Per concept in registry: `test/contracts/<concept>_writer_to_reader_test.dart`. Source-greps every writer's field set; asserts readers consume the canonical fields. For Hive concepts: write a fake row via writer signature, read it back via every reader, assert byte-for-byte field equivalence. For cloud concepts: payload-shape contract.

#### P3.2 — Integration tests for "exactly the failure we keep missing"

Three new files under `integration_test/`:

- **`cold_start_day_rollover_test.dart`** — boot app on Sat, log a workout, simulate IST clock advance to Sun midnight via mock clock injection, assert today-card refreshes to Sunday content, calendar strip Saturday gets ✓, no stale Saturday workout visible as today's workout.
- **`logout_login_round_trip_test.dart`** — log a workout on day N, sync, sign out, sign back in, assert: cloud has the workout, restore writes it back to Hive at the canonical key, today-card + calendar-strip + workout-receipt all show DONE for day N.
- **`today_card_vs_calendar_strip_same_source_test.dart`** — log a workout, assert today-card status field === calendar-strip status field for the same date (forces both readers through the same provider/helper).

Plus: every entry in `docs/regression-test-debt.md` (output of P2.4) gets a test in P3 OR explicit `permanently-skipped: <reason>`.

#### P3.3 — Auxiliary contract + audit tests

- `test/contracts/sot_registry_completeness_test.dart` — Phase 4 Gate 7 reuses this in CI.
- `test/contracts/naming_audit_test.dart` — Phase 4 Gate 8 reuses.
- `test/contracts/edge_function_payload_match_test.dart` — Phase 4 Gate 12 reuses. Catches Test #12.9 telemetry blackout class.

**P3 acceptance:** all P3 tests green on the worktree branch; regression-test-debt fully resolved (test added or `permanently-skipped` with reason).

### Phase 4 — `/build-apk` gate upgrades

8 new scripts under `scripts/`. Each is a standalone Dart CLI; exits 0 on pass, non-zero on fail; prints a structured JSON report on failure.

| # | Script | Catches |
|---|---|---|
| 1 | `check_sot_registry_completeness.dart` | Methods/key-prefixes not in registry |
| 2 | `check_naming_audit.dart` | Forbidden legacy patterns present |
| 3 | `check_writeservice_contracts.dart` | Hive field has no contract test |
| 4 | `check_bugfix_commits_have_diagnose.dart` | Recent `fix:` commit without `closes-diagnose:` |
| 5 | `check_sync_fanout.dart` | Hive prefix without `_syncX` + `_restoreX` |
| 6 | `check_edge_function_payloads.dart` | Flutter caller body keys ≠ Edge Function validator shape (Test #12.9 class) |
| 7 | `check_apk_size_within_bounds.dart` | APK delta > ±10% from previous shipped |
| 8 | `check_migrations_applied.dart` | Local migration not applied to prod |

### Updated `.claude/commands/build-apk.md` body

**14 enforcement gates** (per Q6). Pre-build housekeeping (JVM cleanup, etc.) is preserved but is not counted as a numbered gate. Numbering matches Q6's table 1-to-1.

```
Pre-build housekeeping (existing, not a numbered gate):
  - Kill stale java.exe / gradle.exe (Windows)
  - Delete <flutter_sdk>/bin/cache/lockfile if stale

Gate 1.  On main, clean tracked tree        (existing pre-flight)
Gate 2.  versionCode bumped vs last shipped (existing pre-flight)
Gate 3.  .env exists                        (existing pre-flight)
Gate 4.  flutter analyze --fatal-infos      (NEW — was --no-fatal-infos)
Gate 5.  flutter test (full suite)          (existing via pre-commit; re-run as gate)
Gate 6.  flutter test integration_test/     (NEW — needs offline emulator)
Gate 7.  scripts/check_sot_registry_completeness.dart      (NEW)
Gate 8.  scripts/check_naming_audit.dart                   (NEW)
Gate 9.  scripts/check_writeservice_contracts.dart         (NEW)
Gate 10. scripts/check_bugfix_commits_have_diagnose.dart   (NEW)
Gate 11. scripts/check_sync_fanout.dart                    (NEW)
Gate 12. scripts/check_edge_function_payloads.dart         (NEW)
Gate 14. scripts/check_migrations_applied.dart             (NEW — pre-build)
   ↓ all green ↓
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart
   ↓
Gate 13. scripts/check_apk_size_within_bounds.dart         (NEW — post-build)

Post-build housekeeping (not a numbered gate):
  - APK exists at expected path
  - No hs_err_*.log dumps
  - Record APK MD5 + size into backups/apk_sizes.json
```

#### `--emergency-bypass` flag

Argument: literal string `emergency-bypass`. When present:

- Gates 4, 6, 7, 8, 9, 10, 11, 12, 13, 14 skipped (Gates 1–3 + Gate 5 still run; pre-build housekeeping still runs; build still runs).
- versionCode in `pubspec.yaml` MUST be temporarily suffixed with `e` (e.g. `1.0.0+18e`); separate `chore: emergency build versionCode` commit required.
- Built APK filename: `app-prod-release-EMERGENCY.apk`.
- Row appended to `docs/emergency-builds.md`: timestamp, user-acknowledged-reason, gates skipped, post-mortem-due-by date.
- Founder sees a banner on app launch: `"EMERGENCY BUILD — discipline gates skipped. See docs/emergency-builds.md."`

**P4 acceptance:** all 8 scripts exit cleanly on green codebase + non-zero on hand-crafted failure; build-apk runs all gates in order; `--emergency-bypass` works end-to-end; `backups/apk_sizes.json` exists with 12.9 (114.2MB) recorded; `flutter analyze --fatal-infos` green on worktree (means we fix the 19 existing infos in P2.3).

### Phase 5 — Apply discipline to Sunday's 3 bugs

For each bug, identical flow:

1. Main thread invokes `/diagnose-bug` interactively.
2. Skill walks 12 questions, writes `docs/diagnoses/2026-05-12-<slug>-<id>.md`.
3. `validate_diagnose_doc.dart` exits zero.
4. Main thread implements fix using existing patterns (deterministic Hive keys, fan-out to sync, IST throughout) — informed by the diagnose-doc's writer/reader enumeration.
5. Each fix commit references `closes-diagnose: <bug-id>` in body.
6. Each fix ships with: contract test (writer-reader pair) + integration test (cold-start / logout-login flow).
7. Pre-commit hook validates the diagnose-doc reference + runs full suite + new tests.

**Bug 5.1 — Today-card vs calendar-strip same-day mismatch**
*Image 1 (Sat 9 May)*: today-card DONE but calendar-strip S9 has no ✓. Two readers on the same Hive key disagree.

**Bug 5.2 — Day rollover Sat→Sun didn't refresh**
*Image 2 (Sun 10 May)*: today-card stuck on Saturday's BACK DAY A. Either `DayRolloverService.runRolloverNow()` didn't fire on cold start, OR fired but didn't invalidate the right providers.

**Bug 5.3 — Saturday workout vanished on logout-login**
*Image 2*: S9 calendar-strip with no ✓ even though founder logged the workout on Sat. Either the local Hive write never reached cloud, OR cloud has it but restore didn't pull it back, OR the data was clobbered by 5.2's rollover regression.

Forensic step before each diagnose: query cloud for founder's data; capture state in the diagnose-doc's body.

**P5 acceptance:** 3 diagnose-docs validate; 3 fix commits with `closes-diagnose:` references; integration tests cover the 3 bugs; full suite green.

### Phase 6 — Final APK + founder verification

#### P6.1 — Merge worktree → main

`feat/process-discipline-batch` → `main` via `--no-ff`. Single merge commit summarizing all 6 phases, listing every diagnose-doc closed, listing every gate added.

Pre-merge: full local CI run (analyze + test + integration + all 8 gate scripts). Pre-merge gate: every gate exit-zero.

#### P6.2 — Build final APK

`/build-apk` from the merge commit on `main`. All 14 gates green. APK 1.0.0+17 (or +18 if any intermediate emergency build happened — defensive).

Output: `app-prod-release.apk`, MD5 recorded, size logged to `backups/apk_sizes.json`.

#### P6.3 — Founder on-device verification

```
1. Install APK 13.0 (versionCode +17)
2. Profile → LOGOUT → SIGN IN
3. Wait on /restoring 10–15s
4. Verify on home (Sun May 12 — present-time):
   - Greeting shows real name
   - PRO pill = PRO
   - Today-card matches today's plan (no stale Saturday state)
   - Calendar-strip Mon/Tue/Wed/Thu/Fri/Sat all reflect cloud truth
   - Saturday May 9 specifically: calendar ✓ if it was completed in cloud
5. Open AI coach → ask "show this week" → assert no fabrication, real data
6. Spot-check templates → 3 cards, no duplicates
7. Force-stop, leave overnight, open at 7am Mon May 13:
   - Today-card refreshes to Monday (day-rollover smoke test)
   - Sunday rest day shows correct status
8. Log a fresh workout → close app → re-open → workout still visible
   on calendar + today-card
```

Post-install founder query (telemetry, with `log-client-error` now unblocked by 12.9):

```sql
SELECT op_type, COUNT(*) AS n, MIN(created_at), MAX(created_at)
FROM public.client_errors
WHERE user_id = '<founder>' AND created_at >= now() - interval '15 min'
GROUP BY op_type ORDER BY MAX(created_at) DESC;
```

Expected: `auth_signed_in`, `hive_session_opened`, `restore_started`, `restore_completed`, `subscription_state_written` — proves telemetry now flows.

**P6 acceptance:** APK 1.0.0+17 (or +18) shipped; founder 8-step verification passes; 48-hour soak shows no new bugs; telemetry shows expected sequence.

## Worktree + rollback safety

**Worktree:** `feat/process-discipline-batch`, created from `main` after the 12.9 merge. Pre-commit hook re-installed via `sh scripts/setup-hooks.sh`.

**Rollback escapes:**

| Phase fails | Recovery |
|---|---|
| P1 (foundation broken) | Worktree branch deleted; nothing on main affected |
| P2 (audit/cleanup error) | Worktree commits revert; pre-cleanup `pg_dump` + Hive snapshots restore data |
| P3 (test won't pass) | Failing test fixed OR explicitly `permanently-skipped` in regression-test-debt with reason |
| P4 (gate script broken) | Hand-crafted failure-case test surfaces it; fix the script, re-run |
| P5 (one of 3 bugs has no clean fix) | Bug's diagnose-doc gets `status: deferred` + fix moves to follow-up batch; other 2 still ship |
| P6 (APK won't pass gates) | Whichever gate fails IS the bug; we don't ship until clean |

**Hard escape — full revert:**
- Worktree branch deletion = full undo before merge.
- After merge, `git revert -m 1 <merge-sha>` reverts all 6 phases atomically.

## Acceptance for the entire batch

- [ ] All 6 phases' acceptance checklists satisfied.
- [ ] Worktree merged to main as a single `--no-ff` commit.
- [ ] APK 1.0.0+17 (or +18) built from merge commit on main, all 14 gates green.
- [ ] Founder installs + 8-step verification passes.
- [ ] 48-hour soak: no new bugs; telemetry shows expected sequence.
- [ ] Retrospective at `memory/project_apk_test_13_process_discipline_batch.md`, links every diagnose-doc closed, lists every gate added.

## Out of scope (explicitly deferred to separate batches)

- Migration 051 (`template_exercises` UNIQUE constraint) — deferred from #12.7.
- Test #4 audit findings (11-P0 list).
- `ai_coach_repository.dart` profile.full_name probe — deferred from #12.8.
- Any new feature work.
- Remaining `permanently-skipped` entries from `regression-test-debt.md` after this batch.

---

## Cost estimate

- Phase 1 (foundation): 4–6 h main-thread.
- Phase 2 (audits + backfill): 3–4 h orchestration + 4 parallel subagents (~3 h each in parallel).
- Phase 3 (tests): 6–8 h main-thread (heavy: lots of new contract + integration tests).
- Phase 4 (gate scripts): 4–6 h main-thread.
- Phase 5 (3 bugs disciplined fix): 3–5 h main-thread.
- Phase 6 (final APK + founder verification): 1 h build + on-device verification window.

Wall-clock with subagent parallelism: **~18–25 h of Claude work**, distributed over 2–3 working sessions if the founder isn't reviewing in real time.
