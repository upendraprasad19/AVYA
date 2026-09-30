---
source: CLAUDE.md §19 (subset — class-C survivors)
migrated: 2026-05-18
status: scaffold
---

# Common Pitfalls — Cross-Domain

> §19 entries that don't fit a specific feature CLAUDE.md or architecture doc.
> Class A entries (test-covered) deleted in Milestone 6.
> Class B entries (need tests) get tests in Milestone 4 then deleted.
> Class C entries (non-testable) relocated here OR to feature CLAUDE.md in Milestone 5.
> Class D entries (historical/stale) deleted in Milestone 6.

<!-- POPULATED IN MILESTONE 5 -->

---

## Batch Retrospectives (durable historical record)

### DRIFT-FIX BATCH 2026-05-24 — first writer-reader-drift-detector validation + 10 findings closed + Gate 23

First execution of the ECC adoption B1 agent (`.claude/agents/writer-reader-drift-detector.md` — see "Adopted ECC Patterns" below) against workout + nutrition domains. 9 findings surfaced by initial scan + 1 orphan caught at T16 verification re-run = 10 closed in one mega-commit `14cda1b` (Approach C; founder-locked, waiving `feedback_gates_before_refactor` for this batch — 10 mostly-mechanical findings; pre-commit hook only runs once).

Headline closures:

- **Nutrition F1 P0** — `NutritionWriteService.computeLogKey` + `logMeal` inline + `logWater` (3 sites; scan caught 2, in-batch sweep caught 3rd per `feedback_ist_sweep_gap`) now route through `istDateStr(date)`; behavioral test `nutrition_write_service_ist_anchored_test.dart` pins.
- **Nutrition F2 P1** — Gate 53 (`scripts/check_nlog_key_canonical.dart`) + contract test pin the 3-file `nlog_*` writer allowlist (mirrors Gate 17 for `exlog_*` from APK Test #16.1).
- **Nutrition F4 P2** + **Workout F4 P2** — migration 068 ships `nutrition_log_items.fiber NUMERIC DEFAULT 0` (additive) + atomic rename `workout_logs.exercise_name` → `workout_name` (column was always a session label e.g. "Push A", never per-exercise; founder choice — sole tester, no dual-write phase). UNIQUE INDEX dropped + renamed + recreated; weekly-report Edge Function (sole `workout_logs.exercise_name` reader) redeployed v21. Source-tree file `068b_drift_fix_batch.sql` (renamed from `068_drift_fix_batch.sql` on 2026-05-27 per `050b` precedent — see `README_RECONCILIATION_2026-05-11.md` §E) lives alongside the existing `068_cron_call_log.sql`; `applied_migrations.json` records `"068b_drift_fix_batch"`.
- **Workout F1 P1** — AI snapshot PR read `reps_completed` (SUM across sets per WriteService contract); new `AiCoachRepository.prSetRepsForExlog` walks `sets[]`, surfaces reps at the PR-weight set, falls through to `reps_completed` for legacy rows without `sets[]`.
- **Workout F2 P1** — 6 sites across 5 train/ files silently read `log['duration_seconds']` at top level; WriteService never emits the field there (`sets[].duration_sec` is canonical) → 0 for every modern row. Routed through `WorkoutReadService.bestPerSetDuration`.
- **Workout F5 P2** — deleted `logSetWithPrRescan` + 3 cascading orphan helpers (`_invalidateExlogDateIndex`, `_recomputePrFlagsForExercise`, `_PrScanEntry`) ~277 lines total. Preflight grep confirmed zero active callers; cascading cleanup verified `_exlogDateIndex`/`_ensureExlogDateIndex` still actively called from `getExerciseLogsForDate` legacy fallback (kept).
- **T16 orphan finding** — `train_provider.dart` 4 sites read legacy `sets_completed` while WriteService emits canonical `set_number`; closed via dual-name read pattern (canonical-first fallthrough) mirroring `ExerciseSet.fromMap` `duration_sec`/`duration_seconds`.

**Class lesson — first B1 validation:** the ECC drift-detector caught a real latent P0 (nutrition F1 IST) on its very first run against an audited domain. ROI of B1 adoption proven. In-batch scope expansion pattern reaffirmed across 4 expansions during execution (F1 2→3 sites, F2 2→6 sites, T11 cascading dead code, T16 orphan) all closed in same commit per `feedback_no_deferrals`.

9 new contract/behavioral tests, 1 new build gate (Gate 23 wired into `.claude/commands/build-apk.md`), 1 migration applied live (version `20260525010726`), 1 Edge Function redeploy (weekly-report v20→v21 `ezbr_sha256 ec4c002321e78fdf4d2348f31f3ce2dec0dcd4c9eeb5f3072736ba952d8114df`). closes-diagnose: 524d12.

Sources: spec `docs/superpowers/specs/2026-05-24-drift-fix-batch-design.md`, plan `docs/superpowers/plans/2026-05-24-drift-fix-batch.md`, closure YAML `docs/audit/2026_05_24_drift_fix_closures.yaml`, diagnose `docs/diagnoses/2026-05-24-drift-fix-batch-524d12.md`.

---

## ADOPTED ECC PATTERNS (2026-05-24)

Five tools adopted from [affaan-m/ECC](https://github.com/affaan-m/ECC) on 2026-05-24 to harden the Claude harness workflow against the #1 recurring bug class (writer/reader drift) and the doc drift that hides it. Skipped: PostToolUse hooks (Windows fragility), memory TTL (deferred to separate batch). Adopted ECC's intent + structure; rewrote every prompt for our codebase (SoT registry refs, Hive/Riverpod/Supabase patterns, known drift signatures baked in).

1. **`.claude/settings.json`** (B2) — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55` + `MAX_THINKING_TOKENS=10000`. Compact at 55% not 95%; cap thinking budget. Effect visible from next session.
2. **`.claude/skills/strategic-compact/SKILL.md`** (B5) — surfaces `/compact` suggestions at logical phase boundaries with curated preserve/drop guidance. Founder-approved; never auto-runs.
3. **`.claude/skills/sync-claude-md/SKILL.md`** (B6) — audits CLAUDE.md for drift vs live code/DB state. Extracts paths, line refs, count claims, version claims, memory refs; verifies each. Run at end of every batch before committing CLAUDE.md changes.
4. **`.claude/agents/writer-reader-drift-detector.md`** (B1) — read-only subagent that traces writer→reader paths for a domain or writer file. Targets the writer/reader drift bug class (7+ instances since Test #6). First run surfaced 1 P0 (nutrition IST writer) + 2 P1 (AI PR reps semantic, top-level duration_seconds dead read) + multiple P2 — driving a follow-on drift-fix batch.
5. **`.claude/skills/audit-claude-config/SKILL.md`** (B3) — audits `.claude/settings*.json` for stale Bash allows, orphan permissions, suspected secrets. One-time + quarterly. First run baseline clean (1 P2 stale Bash allow).

Spec: [docs/superpowers/specs/2026-05-24-ecc-adoption-design.md](../superpowers/specs/2026-05-24-ecc-adoption-design.md)
Plan: [docs/superpowers/plans/2026-05-24-ecc-adoption.md](../superpowers/plans/2026-05-24-ecc-adoption.md)
First-run reports: `docs/audit/2026-05-24-{claude-md-drift,drift-scan-workout,drift-scan-nutrition,claude-config-audit}.md`.

Founder gates: T3 first-run surfaced 4 P1 + 2 P2 in CLAUDE.md (count drifts + version-stamp annotation), all closed in same batch (commit `85a47ba`). T4 first-run drift findings escalated to a dedicated drift-fix follow-on batch — shipped 2026-05-24 in commit `14cda1b` (see "DRIFT-FIX BATCH 2026-05-24" entry above); 10/10 findings closed (9 from scan + 1 orphan from T16 verification re-run), migration 068 applied live, Gate 23 added, weekly-report Edge Function v21 deployed.

Explicitly NOT adopted: PostToolUse hooks (Windows fragility), memory TTL (deferred to separate batch), cross-harness adapters (Claude Code only), ECC's 230+ generic skills (only adopted what we'll actually invoke).

---

## Subprocess-spawning tests need a file-level `@Timeout` (2026-08-25)

**Symptom.** A test file passes when run targeted and FAILS in the full suite, with a timeout.

**The class is "spawns a subprocess", not "is an e2e file".** Any test that calls
`Process.run`/`Process.start` — directly, or indirectly via a git hook or script it invokes —
belongs to it. All 20 such files under `test/scripts/` carry the annotation today: 11 named
`*e2e*` and 9 not (`safe_push_test`, `safe_merge_test`, `dart_bin_resolver_test`, …).

**Why the suite is a different input set, not a superset.** Each spawned child pays the
`flutter/bin/dart` wrapper cost — measured at **3.4–10.5 s for a no-op** (root CLAUDE.md §0),
because the wrapper takes the SDK update lock and shells out to git on every invocation, and that
lock SERIALIZES concurrent callers. Two sequential spawns fit inside the default **30 s**
(`package:test_api` `Timeout`) when the file runs alone, and do not when ~40 files run
concurrently. **A targeted run cannot create contention**, which is the condition most likely to
break a subprocess test — so a green targeted run is not evidence.

**The fix.**
```dart
@Timeout(Duration(minutes: 5))
library;
```
before the first `import`. Sibling values: `gate_index_e2e` 3, `retire_worktree_e2e` 4,
`plan_review_record_gate_e2e` 5, `batch_close_hook_e2e` / `skill_tuning_history_e2e` 6.

**Make teardown never throw.** A timed-out child still holds a Windows handle into the temp dir,
so `deleteSync` raises `PathAccessException` and stacks a SECOND failure that HIDES the real one.
Cleanup is hygiene, not an assertion; `%TEMP%` is reaped by the OS regardless.

**⚠ This convention is unenforced, and the class has recurred 4×.** `aac52fb6` records three
consecutive merge attempts failing on it (9 → 3 → 1 failures); it then recurred on 2026-08-25
(`main` red at 4897/-2). A per-file convention held only by memory is the weaker fix. `dart_test.yaml`
exists and currently configures only the `golden` tag — a repo-wide `timeout:` there, or `--timeout`
on the `flutter test` invocations in `scripts/pre-push.sh` and `.github/workflows/test.yml`, would
close the class in one place. A `check_*.dart` gate asserting "spawns a subprocess ⇒ has
`@Timeout`" is the other option. Neither is done; both are the real fix and are tracked as such.

## Riverpod-3 widget-harness pitfalls (2026-09-19)

**Symptom.** A `testWidgets` file that opens Hive and renders Wardroom widgets fails in one of four
unrelated-looking ways: a GoogleFonts network error on whichever test renders a style FIRST; a
`did not complete` hang on a plain `await box.put(...)`; a picker that taps the wrong tile because
the box it reads is empty; or a provider assertion that reads a DIFFERENT container from the one
the widget wrote to. All four have one worked reference implementation:
`test/widgets/compass_redesign_test.dart`. Read the CODE there, not this summary, when in doubt.

**1. GoogleFonts warms up BEFORE any `path_provider` mock exists** (`:14-20` header, `_FontWarmup`
`:40-63`, warmup test `:66-74`). The repo bundles no fonts, so every `AppTypography` style is fetched
at runtime and quietly degrades in the harness — UNTIL a test mocks `path_provider`
(`setUpHiveForTests` does, `test/helpers/hive_test_setup.dart:26-27`), which answers GoogleFonts'
fetch-and-save path and turns the degrade into a loud error on the first style rendered afterwards.
The fix is structural: the FIRST test in the file renders every family+weight the file uses, with no
mock installed, and Hive is opened INSIDE each test body (`await tester.runAsync(setUpHive)`, `:203`),
never in a global `setUp` that would run ahead of the warmup. GoogleFonts caches per family+weight,
so the warmup must enumerate the exact variants (`:42-43` lists why each line is there).

**2. Real I/O inside `testWidgets` goes through `tester.runAsync`** (`:203`, `:205-227`, `:259`). A
`testWidgets` body runs in a fake-async zone; a bare `await HiveService.instance.workoutBox.put(...)`
never completes and the runner reports `did not complete` minutes later. Every Hive open, put and
teardown in that file is wrapped: `await tester.runAsync(() => HiveService.instance.workoutBox.put(...))`.
The same escape hatch is what makes a REAL wall-clock gap possible (`:647-653`: a 5 ms
`Future.delayed` inside `runAsync` so two taps get different `millisecondsSinceEpoch` ids — the
fake clock cannot produce that).

**3. Seed every box the widget reads, or the empty state IS the test's path** (`:299-312`). The
substitute picker reads `exerciseBox`; with it empty the list is empty and the test would tap the
BACK tile and pass for the wrong reason. The comment at `:299-300` says so. Conversely the
empty-box shape is a deliberate assertion in its own test (`:262-275`: `NO WORKOUT SCHEDULED TODAY`
+ `intents` empty, citing §4.4 rule 13) — seed for the path you mean to exercise, assert the empty
state where the empty state is the subject.

**4. `UncontrolledProviderScope(container: container, …)` with a container YOU own** (`:81` creates
`ProviderContainer()` in `setUpHive`; `:229-232` hands it to the widget; `:247` reads
`container.read(pendingToolIntentsProvider)` AFTER the interaction; `:85` disposes it in
`tearDownHive`). A plain `ProviderScope` creates its own container, so a provider the widget wrote
to is unreachable from the test — the assertion would read a fresh, empty instance and pass or fail
for reasons unrelated to the widget. The uncontrolled form is what lets the test observe the exact
container the widget mutated.

**Teardown mirrors setup** (`:84-87`, `:259`): dispose the container, then `tearDownHiveForTests`,
both via `runAsync`, at the END of the test body — not in a `tearDown` hook that would run outside
the widget test's zone.

## The APK toolchain depends on an Android Studio install nothing in this repo records (2026-08-27)

**Symptom.** `flutter build apk` dies in ~2 minutes with
`ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH`, and
`flutter doctor` reports the Android toolchain broken (`cmdline-tools component is missing`).

**Cause.** Every APK from +35 to +38 was built with **Android Studio's bundled JetBrains
Runtime**. The Gradle daemon logs record it verbatim — `~/.gradle/daemon/8.14/daemon-*.out.log`:

    javaHome=C:\Program Files\Android\Android Studio\jbr,javaVersion=21,javaVendor=JetBrains s.r.o.

Android Studio was uninstalled after 2026-08-06, which removed the only JDK on the machine. The
Android **SDK** survives at `%LOCALAPPDATA%\Android\Sdk`; only the JVM went. Nothing in the repo
ever referenced `JAVA_HOME`, so the build silently depended on an external install no gate,
script or doc mentioned.

**Fix.** Install JDK 21 and point `JAVA_HOME` at it:

    winget install --id Microsoft.OpenJDK.21 --silent

**Use 21, not 17.** `android/app/build.gradle.kts` sets `sourceCompatibility`/`targetCompatibility`/
`jvmTarget` to `VERSION_17`, and reading those as the required JDK is the trap — they are the
BYTECODE TARGET, not the JVM Gradle runs on. The daemon logs prove the proven configuration is 21.
Verified 2026-08-27: Microsoft OpenJDK 21.0.12.1 built `+39` clean, Gate 48 and Gate 13 both PASS.

**Diagnosing this again in five minutes rather than an hour:** the JVM that ran any past build is
in `~/.gradle/daemon/<gradle-version>/daemon-*.out.log` — grep for `javaHome=`. Each log's mtime
matches its build date, so you can identify exactly which toolchain produced which shipped APK.

⚠ A Windows env-var change does NOT reach an already-running shell. After installing, `JAVA_HOME`
reads unset in this session even though `[Environment]::GetEnvironmentVariable('JAVA_HOME','Machine')`
returns the right path — export it explicitly for the build rather than concluding the install failed.



## Full incident detail for CLAUDE.md §4.9 rows

> Moved here VERBATIM from root `CLAUDE.md` §4.9 (context-lean batch, 2026-09-29). Root keeps a `symptom | fix | pointer` table; each row below is the original, unabridged row text under its original title, so a grep on a row title still lands here.

### A `postmaster`-context GUC (e.g. `cron.log_run`) cannot be flipped by any SQL migration — requires a full server restart, not a retryable syntax fix

| Pitfall | How to avoid | Source |
|---|---|---|
| A `postmaster`-context GUC (e.g. `cron.log_run`) cannot be flipped by any SQL migration — requires a full server restart, not a retryable syntax fix | Check `select context from pg_settings where name='<setting>'` before authorizing/drafting. Full detail + the incident: `supabase/migrations/CLAUDE.md` Common pitfalls. | 2026-09-22, diagnose e8b4a1 |

### `idx_scan=0` proves an index is unused by QUERIES — it says nothing about FK-constraint-support use, which `get_advisors` will separately flag as `unindexed_foreign_keys` if you drop the wrong one

| Pitfall | How to avoid | Source |
|---|---|---|
| `idx_scan=0` proves an index is unused by QUERIES — it says nothing about FK-constraint-support use, which `get_advisors` will separately flag as `unindexed_foreign_keys` if you drop the wrong one | Check `pg_constraint` for a same-column FK before dropping. Full detail + the incident: `supabase/migrations/CLAUDE.md` Common pitfalls. | 2026-09-22, diagnose e8b4a1 |

### Wrong import path

| Pitfall | How to avoid | Source |
|---|---|---|
| Wrong import path | Use relative within features, `package:` for shared/core. | `docs/playbook/common-pitfalls.md` |

### Gradle build hangs silently

| Pitfall | How to avoid | Source |
|---|---|---|
| Gradle build hangs silently | `-Xmx` must be ≤4G on 16GB system. 8G causes OOM with no terminal output. Check `android/hs_err_*.log`. Remove stale `flutter/bin/cache/lockfile` if Flutter commands hang on lock. | `docs/playbook/common-pitfalls.md` |

### `flutter build apk` dies in ~2 min: `JAVA_HOME is not set and no 'java' command could be found`

| Pitfall | How to avoid | Source |
|---|---|---|
| **`flutter build apk` dies in ~2 min: `JAVA_HOME is not set and no 'java' command could be found`** | Install **JDK 21** (`winget install --id Microsoft.OpenJDK.21`) and export `JAVA_HOME`. **The build has NEVER had an in-repo JDK source** — every APK +35→+38 used Android Studio's bundled JetBrains Runtime, and uninstalling Android Studio (after 2026-08-06) removed the machine's only JVM. The Android SDK survives; the JDK does not. ⚠ **Use 21, not 17** — `build.gradle.kts`'s `sourceCompatibility = VERSION_17` is the BYTECODE TARGET, not the JVM Gradle runs on; reading it as the JDK requirement is the trap. The five-minute diagnostic for "which JVM built any past APK": `grep -o 'javaHome=[^,]*' ~/.gradle/daemon/<ver>/daemon-*.out.log` — each log's mtime matches its build's ship date. ⚠ A Windows env-var change does NOT reach an already-running shell; export it explicitly rather than concluding the install failed. | `docs/playbook/common-pitfalls.md` (2026-08-27, cost ~1h on the +39 build) |

### Worktree APK build fails with "Did not find .env"

| Pitfall | How to avoid | Source |
|---|---|---|
| Worktree APK build fails with "Did not find .env" | `.env` is gitignored. Before `flutter build apk` in a new worktree, copy from main: `cp "C:/Upendra/Claude Code/Fitness App/.env" <worktree>/.env`. | `docs/playbook/common-pitfalls.md` |

### Built APK via `flutter build apk` directly

| Pitfall | How to avoid | Source |
|---|---|---|
| Built APK via `flutter build apk` directly | Always use the `/build-apk` skill. Direct flutter build can hang silently on this machine without the skill's pre-flight cleanup. | `docs/playbook/common-pitfalls.md` |

### Master Audit / multi-agent surveys produce false-positive findings

| Pitfall | How to avoid | Source |
|---|---|---|
| Master Audit / multi-agent surveys produce false-positive findings | Never apply a multi-agent audit finding without first reading the cited file:line AND verifying claimed cloud state via live `information_schema` query. Cite the verification SQL in the audit report. See `feedback_audit_findings_require_live_verification.md`. | `docs/playbook/common-pitfalls.md` |

### `/tmp` means TWO DIFFERENT DIRECTORIES depending on which binary reads it

| Pitfall | How to avoid | Source |
|---|---|---|
| **`/tmp` means TWO DIFFERENT DIRECTORIES depending on which binary reads it** | Git-Bash resolves `/tmp` to `%TEMP%` (`C:\Users\<u>\AppData\Local\Temp`); a **Windows** `python`/`node` resolves it to `C:\tmp` on the current drive. So `cat > /tmp/f` followed by `python -c "open('/tmp/f')"` touches two unrelated files. It fails LOUDLY when the file is absent (`FileNotFoundError`) and **silently when it is not**: on 2026-08-28 a Python edit reported success against `C:\tmp\msg.txt` while `safe_commit.sh "$(cat /tmp/msg.txt)"` read the UNEDITED Git-Bash copy, so a corrected commit subject reverted itself and the commit-msg gate rejected it twice with the identical message — which reads as a broken gate rather than a path bug, and that misreading is the expensive part. **Never use `/tmp` here.** Use the session scratchpad by its absolute Windows path (the harness provides one for exactly this). Same family: a `node` script resolving its own paths from `__dirname` must be run from inside the repo, not copied to a temp dir, or it resolves `assets/` against the wrong root. | 2026-08-28 (OI-89 batch; cost two commit cycles plus one failed generator run) |

### `safe_commit.sh` takes ONE POSITIONAL argument and no flags — a flag becomes the MESSAGE. (`safe_push.sh` is DIFFERENT — its real signature is `[remote] [branch] [extra args...]`, `scripts/safe_push.sh:23`, and it accepts flags like `-u` as trailing extra args; this row does not apply to it. Corrected 2026-09-26 — the row previously lumped both scripts under the same "no flags" claim, which was wrong for `safe_push.sh`.)

| Pitfall | How to avoid | Source |
|---|---|---|
| **`safe_commit.sh` takes ONE POSITIONAL argument and no flags — a flag becomes the MESSAGE.** (`safe_push.sh` is DIFFERENT — its real signature is `[remote] [branch] [extra args...]`, `scripts/safe_push.sh:23`, and it accepts flags like `-u` as trailing extra args; this row does not apply to it. Corrected 2026-09-26 — the row previously lumped both scripts under the same "no flags" claim, which was wrong for `safe_push.sh`.) | `sh scripts/safe_commit.sh -F msg.txt` commits with the subject **`-F`** and drops the file. The wrapper reports `OK -- HEAD advanced` and is *right*: it verifies a commit HAPPENED, never that it says what you meant. Second-order and worse: the `commit-msg` gates key on the SUBJECT, so a `fix:` prefix reduced to `-F` no longer matches and **`closes-diagnose:` is never demanded** — the gate that exists to catch a malformed commit is silent when the message is destroyed. Repair: `git reset --soft HEAD~1` (the safety hook guards `commit`/`push`, not `reset`), then `safe_commit.sh "$(cat msg.txt)"` — command substitution keeps the newlines and `-m` accepts them. General form: a wrapper that reads `"$1"` as data cannot reject a flag. Read the usage line, and `git log -1 --format=%s` after any commit whose message matters. | 2026-08-28 (OI-89 batch; `memory/feedback_git_landing_verification.md`) |

### A widget test that mocks `path_provider` makes GoogleFonts fail LOUDLY instead of degrading

| Pitfall | How to avoid | Source |
|---|---|---|
| **A widget test that mocks `path_provider` makes GoogleFonts fail LOUDLY instead of degrading** | The repo bundles **no fonts** — `pubspec.yaml` has no `fonts:` section and there is no `.ttf` in the tree — so every `AppTypography` style is fetched at runtime and, in the harness, quietly degrades to a fallback. That is fine, and `test/widgets/completion_prompt_card_test.dart` relies on it. **But GoogleFonts SAVES fetched fonts through `path_provider` (`_httpFetchFontAndSaveToDevice`).** A test that mocks that channel so Hive can open a box therefore answers GoogleFonts too, walking it into the fetch-and-save path where the network failure surfaces as a **test error** — landing on whichever test renders an AppTypography style **FIRST**. ⚠ **The failure follows POSITION, not content:** delete the failing test and it moves to the next one, which reads like a different bug each time. Fix: open Hive **lazily** (not in `setUpAll`) so the first tests run before the mock exists, and have that first test render **every** style family the file needs — GoogleFonts caches per family+weight, so priming JetBrains Mono leaves DM Sans to fail later. Tried and rejected, all measured: `allowRuntimeFetching = false` (turns a soft degrade into a hard throw), the wardroom goldens' warmup loop, `takeException()` (the error arrives after the body), `FlutterError.onError` suppression (not routed there), and seeding fewer rows (it is the box open, not the row count). | 2026-08-29 (exercise-plates; `test/contracts/exercise_plate_widgets_test.dart` header carries the long form) |

### `await`-ing real disk I/O inside a `testWidgets` body hangs until the harness gives up

| Pitfall | How to avoid | Source |
|---|---|---|
| **`await`-ing real disk I/O inside a `testWidgets` body hangs until the harness gives up** | A `testWidgets` body runs in a **fake-async zone**; the clock only advances when you `pump`. So `await box.put(...)`, `await someRepo.init()`, or any real file write **never completes** — the runner reports `did not complete` after minutes (measured: **6m35s**, then **4m55s**), which reads as a hang or a timeout rather than the code being wrong. ⚠ The same statement in a plain `test(...)` body is fine, so the identical line passes in one file and hangs in another. Fix: `await tester.runAsync(() async { ... })`, which escapes the fake zone — or do the work in `setUpAll`, which is already outside it. ⚠ Note the collision with `unawaited_futures` (WARNING in `analysis_options.yaml:21`): dropping the `await` to dodge the hang fails the push instead. `runAsync` is the answer that satisfies both. | 2026-08-29 (exercise-plates) |

### Extracting or moving code breaks source-grep contracts in files you never touched

| Pitfall | How to avoid | Source |
|---|---|---|
| **Extracting or moving code breaks source-grep contracts in files you never touched** | Before landing any extraction/move/rename, **grep the test tree for what is moving** — the old symbol, the old literal, the enclosing method name: `grep -rn "<old-literal>" test/`. Source-grep contracts pin code by LOCATION, so relocating it breaks them in files the diff does not open, and a targeted test run cannot see it. Measured 2026-08-30 (`profile-phase-fixes`): extracting an inline ternary into `deploymentEyebrowLabel` and moving a `.from('users')` select into a retry helper broke **4 assertions across 3 files** (`hold_display_read_path_test`, `phase_relative_week_label_test`, `user_full_name_writer_to_reader_test`) — none of them touched by the batch, all invisible until the pre-push full suite, costing a full push cycle. ⚠ **Fix them by REPOINTING at the new location, never by deleting or loosening** — the assertion is still true, it just moved; two of the three came back STRONGER (one now also pins that the delegation is not severed, which the original single-body grep structurally could not catch). Same family as the `@Timeout` row below: a targeted run is a different input set, not a subset. ⚠ **Recurred 3× in ONE batch** (2026-09-16, `cron-ai-removal`): extracting `RANK_LABELS`/`composeCongrats` into `congrats.ts` and a milestone-copy if-chain into `message.ts` each stranded a Flutter contract test reading only the OLD file (`proactive_coach_promotion_test.dart`, `streak_guardian_eligibility_test.dart` — 3 RED assertions + 1 RED group respectively); a third instance was a close cousin, not an extraction but a LINE-COUNT SHIFT — `docs/snapshot_contract.yaml`'s `future_prediction`/`morning_alert` reader citations went stale when code removed ABOVE the cited line shifted it out of the gate's ±15-line slack window. **None were caught by two full context-blind plan-review rounds** — both read source and Deno tests but neither ran `flutter test`, which this repo's own pre-commit hook also skips by design (ADR-0018); only a THIRD round explicitly instructed to run the suite found it. The lesson generalizes past extraction: **any edit that adds/removes lines above a file:line citation is the same hazard**, whether the moved concept is code (repoint the test) or just line count (repoint the citation). **Conversion-on-touch (2026-09-17): any test or file:line citation touched in a batch gets converted to behavioral or wide-window (±40 lines) form in THAT batch. No global gate — a grep-detects-grep gate would be its own brittleness.** ⚠ **A fourth variant (2026-09-28, `single-owner-a2b`): the thing that "moved" was a call site's own NAME, not its file or line.** A test-seam refactor changed `daily-snapshot`'s Gemini call from `geminiChat({...})` to an injectable `geminiChatFn({...})` parameter (defaulting to the real function, for testability) — same runtime call, different literal text. `_shared/gemini_backoff_retry_test.ts`'s `assertSoleCallSiteHasRetries` pinned the LITERAL string `"geminiChat({"`, which is not a substring of `"geminiChatFn({"` ("Fn(" sits between them), so the test went blind with `no geminiChat( call found` — invisible across THREE units and TWO B-pass rounds because the failing file lives in `_shared/` and only a suite-wide `deno test supabase/functions/` exercises it; every targeted per-function run stayed green. Fixed by widening the helper to recognize either spelling. Diagnose `e35936`. ⚠ **A fifth variant (2026-09-29, `oi-245-246-restore-fixes`): ADDING code introduced a SECOND occurrence of an existing marker literal, and `indexOf`-based anchoring silently re-pointed at the wrong one.** `_drainPendingExlogDeletes` (new this batch, `sync_workout.dart:196`) calls `.from('workout_log_exercises').upsert({` — the exact same literal `test/contracts/sync_natural_key_guard_test.dart`'s `windowBefore` helper anchors on via `src.indexOf(marker)` to find the REAL per-row push upsert at `:495`. Because the new call sits EARLIER in the file, `indexOf` (first-match) silently started returning the new call's position instead, and the test failed with `workout_log_exercises summary upsert must be preceded by a 'sync_skipped_null_natural_key' telemetry emission` — a message that reads like the GUARD broke, when actually the guard was untouched and the ANCHOR moved. Invisible to two full context-blind review rounds and every targeted run (`sync_natural_key_guard_test.dart` was never in either diff's own touched-file set); found only by the corrected full-suite re-run (`TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`) this same repo's own memory note (`reference_vps_full_suite_needs_ist_tz.md`) exists to make someone actually do. Fixed by extending the marker with a trailing `\n` — the real call is `.upsert(\n  summaryPayload,` (multi-line, named variable) while the new one is `.upsert({` (inline map, brace on the same line) — a stable structural difference between the two call SHAPES, not a fragile text coincidence. **The generalization**: this pitfall's existing four variants are all about something MOVING or being RENAMED; this one is about something NEW being ADDED that happens to share an existing marker's literal text — check `grep -c "<marker>"` before trusting `indexOf` finds the occurrence you think it does, whenever a batch adds a new call site to a table/function an existing source-grep test already anchors on. | 2026-08-30 (`profile-phase-fixes`; see also §4.4 rule 21's mutate-it-and-run-it clause) |

### `flutter analyze <FILE>` on a library with `part` files reports CLEAN on a tree that does NOT compile

| Pitfall | How to avoid | Source |
|---|---|---|
| **`flutter analyze <FILE>` on a library with `part` files reports CLEAN on a tree that does NOT compile** | A `part of` file has **no imports of its own** — it inherits the parent library's — and is only analysed AS PART OF that library. So `flutter analyze lib/features/train/screens/train/screen.dart` returns "No issues found" while `hero_cards.dart` / `planned_expansion.dart` (both `part of` it) fail to resolve a symbol the deleted import provided. **Per-file analyze is a DIFFERENT input set from `flutter analyze lib/`, not a subset** — the same rule the `@Timeout` row below states for test runs, which is easy to hold for tests and forget for analyze. ⚠ **Before trusting a scoped analyze, ask whether any touched file is a `part` or declares `part`s.** If so the only valid check is `flutter analyze lib/` — cheap, **39.7 s** on the whole tree here vs 295 s for the pre-push run that caught it. Measured 2026-09-02 (`readiness-flip`): a B-pass finding called an import dead on a grep scoped to `screen.dart` alone; it served three files; five per-file analyzes all said clean; the push failed with `error: failed to push some refs` and nothing else, because the local hook aborted. ⚠ Second half: **a finding inherits the input set of whoever found it** — that B-pass had 0 false alarms across 5 findings and still handed over a one-file grep that broke the build. Widen a finding's evidence BEFORE acting on it. ⚠ Third: do **not** pipe `safe_push.sh` / `safe_commit.sh` through `tail`/`head` — they print a temp log and then delete it, so truncating the output destroys the only copy of the diagnostic (cost one extra 5-minute push cycle here). | 2026-09-02 (`readiness-flip`; `feedback_green_check_input_set_width.md` #29) |

### A new test file that spawns subprocesses — or waits on a live service — goes green targeted and RED in the full suite

| Pitfall | How to avoid | Source |
|---|---|---|
| **A new test file that spawns subprocesses — or waits on a live service — goes green targeted and RED in the full suite** | Give it a **file-level `@Timeout(Duration(minutes: N))` + `library;`** annotation. **The class is "bounded by work this process does not CONTROL", NOT "is named `*_e2e_*`"** — it read *"spawns a subprocess"* until 2026-09-07, and that narrower wording is what let a LIVE NETWORK CALL through: `ai_proxy_test.dart` spawns no subprocess at all (`grep -c "Process\.\(run\|start\)"` → 0), waits on a live Gemini generation, had no annotation, and so ran on Dart's 30 s unit-test default and reddened `main` on latency alone (diagnose `a7c3e9`). A subprocess is one instance of the class, not its definition. ⚠ For the network shape the annotation ALONE is not enough — give the CALL its own SHORTER `.timeout()` that throws a message naming the function and the elapsed wait, because if the test budget expires first the HARNESS reports the failure and the harness knows nothing: you get `Test timed out after 30 seconds` and no idea which call was slow — corrected 2026-08-25 by the round-2 review of this very row, which originally said "e2e" and would have let the author of a future `foo_lib_test.dart` reasonably conclude it did not apply to them. The repo already treats it as the wider class: all **20** files under `test/scripts/` that call `Process.run`/`Process.start` carry the annotation — 11 `*e2e*` files AND 9 without `e2e` in the name (`safe_push_test`, `safe_merge_test`, `dart_bin_resolver_test`, …), which is what `aac52fb6` meant by "All 14 test files that spawn Process.run/Process.start now declare @Timeout". A subprocess spawned INDIRECTLY counts: `pre_merge_commit_e2e_test` spawns none itself, but its `git merge` invokes a hook that resolves dart via `_dart_bin.sh`. Every e2e under `test/scripts/` now has one (`gate_index_e2e` 3, `retire_worktree_e2e` 4, the two 2026-08-25 hook/gate files 6) because they spawn real `dart run` children, and each child pays the `flutter/bin/dart` wrapper cost this file measures at **3.4–10.5 s for a no-op** (§0). Two sequential spawns fit inside the default **30 s** when the file runs ALONE and do not when the suite runs ~40 files concurrently. **A targeted run is a DIFFERENT input set from the suite, not a subset** — it cannot create contention, which is the condition most likely to break a subprocess test. Run a new e2e inside the FULL suite once before believing it. Second half, learned the same day: make teardown **never throw** — a timed-out child still holds a Windows handle into the temp dir, so `deleteSync` raises `PathAccessException` and stacks a SECOND failure that HIDES the real one. Cleanup is hygiene, not an assertion; `%TEMP%` is reaped by the OS regardless. | `docs/playbook/common-pitfalls.md` (2026-08-25 — `main` went red at 4897/-2 on the first full-suite run across 9 unpushed commits; both failures were newly-added e2e files that had passed 61/61 targeted minutes earlier). ⚠ **A per-file convention with no gate is the WEAKER fix and this class has now recurred 5×.** **The 5th (2026-09-04) is the one to read, because the file had ALREADY been fixed for this exact class and the fix did not take:** `0a99a0b7` added `@Timeout(Duration(minutes: 6))` to `batch_close_hook_e2e_test.dart`, but one test in it carried its own `timeout: const Timeout(Duration(seconds: 60))`, and **a per-test `timeout:` takes PRECEDENCE over the file annotation** — so the file-level budget never applied to the one test that needed it, and a 25s inner process budget bounded the child. Green targeted (7/7) and green across all of `test/scripts/` (555/555); RED only in the ~5300-test suite. **Adding the file-level annotation is not enough if a per-test override survives it** — grep the file for `timeout:` after adding `@Timeout`. Original note follows:  (`aac52fb6` records three consecutive merge attempts failing on it). `dart_test.yaml` exists and sets only the `golden` tag — a repo-wide `timeout:` there, or `--timeout` on the two `flutter test` invocations, would close the class in one place. Filed rather than done here because changing the global test timeout affects every test and both CI jobs, which is its own change with its own blast radius. |

### `blast_radius_from_diff.dart` FAILS OPEN on a path that does not exist yet — so a tier "verified" before the file is written is the PATH tier, not the real one

| Pitfall | How to avoid | Source |
|---|---|---|
| **`blast_radius_from_diff.dart` FAILS OPEN on a path that does not exist yet — so a tier "verified" before the file is written is the PATH tier, not the real one** | The classifier has a CONTENT rule (`scripts/blast_radius_content_rules_lib.dart`): a `supabase/migrations/*.sql` containing `SECURITY DEFINER` is forced to **catastrophic** regardless of its glob. That rule can only fire on a file it can READ. Classify a not-yet-written path and it silently returns the path-glob tier — which reads exactly like a verified answer and is how a plan claimed `platform` for a migration that classifies `catastrophic`. ⚠ **The consequence is not cosmetic:** catastrophic requires `hermes: accepted` in the plan-review record (`check_plan_review_record_exists.dart:836`), so the wrong tier silently drops a mandatory review. **Write the file (a scratch copy is fine), classify THAT, delete it** — and re-classify after any edit that adds or removes `SECURITY DEFINER`. Same family as the `part`-file analyze row above: the tool was right, the input set was empty. | 2026-09-04 (OI-162 slice 1, review round 1) |

### Repairing a broken ENFORCEMENT breaks every test that was silently relying on it not enforcing

| Pitfall | How to avoid | Source |
|---|---|---|
| **Repairing a broken ENFORCEMENT breaks every test that was silently relying on it not enforcing** | When a fix makes a cap / quota / rate limit / guard actually work, **grep the test tree for anything that exercises the now-enforced path and asserts success.** Those tests were green because the thing was broken, and nothing in the diff touches them, so no targeted run can see it. Measured 2026-09-05 (OI-162 slice 2): migration 129 moved the chat cap onto a durable ledger; three `ai_proxy_test.dart` tests each send ONE live chat as ONE shared QA account and asserted a bare `200`. They passed for months only because the pre-fix trigger counted rows in a table `rolling-context` prunes nightly. Main went red with `Expected: <200> Actual: <429>` and `usage_counters` showed that account at `used=10`. ⚠ **Review round 1 raised this exact shared-account collision — for the NEW test the plan proposed — and neither it nor the five rounds after it asked the mirror question.** The question asked was "does MY test disturb theirs"; the one never asked was "does my CHANGE alter the world their assertions assume". Having identified the shared account as fragile is what makes the miss instructive: the hazard was named, then scoped to the wrong actor. ⚠ Fix the ASSERTION, not the cap: a test that asserts a status code dependent on **shared mutable state it does not control** should accept both outcomes and pin the contract of each (here 200 → response shape, 429 → the `RATE_LIMITED` code the client maps). That is strengthening, not loosening — the refusal path had no assertion at all before. ⚠ And say the arithmetic out loud: 3 live chats per CI run against a 10/day cap means **CI can run 3 times per IST day**. Repairing the test unblocks main; it does not raise that ceiling, and a dedicated or PRO test account is the actual fix. **Expect this again in slices 3-4** — six more quota readers move onto the same ledger. | 2026-09-05 (`e7c4b2`; `test/edge_functions/ai_proxy_test.dart` `chatBodyOrAssertCapped`) |

### A new behavioural test that EXECUTES green tells you nothing until you run it against the code it REPLACES

| Pitfall | How to avoid | Source |
|---|---|---|
| **A new behavioural test that EXECUTES green tells you nothing until you run it against the code it REPLACES** | Green means it ran. It does not mean it can tell the new implementation from the old one, and reading the assertions will not reveal which. **The cheap experiment, for a migration: restore the previous function body inside a `BEGIN … ROLLBACK` and re-run the new assertions.** Anything still green is not measuring your change. Measured 2026-09-05 (OI-162 slice 2): **5 of 7** new live-Postgres assertions PASSED against the pre-migration `count(*)` triggers. Two were VACUOUS — pre-migration no ledger row exists, so `used` before and after were both NULL and `IS NOT DISTINCT FROM` reported ok; one would have passed **if the feature did nothing at all**. Fixed by requiring a real pre-existing row, and by pairing the exempt user against a non-exempt one who DID consume in the same transaction. ⚠ The other three pass by DESIGN and are correct to keep — a cap still firing with the right error identifier must hold under any implementation — but they are **behaviour-invariants, not evidence the migration landed**, and the file now says so at each. Label the two kinds or someone cites the wrong one. ⚠ Second recurrence of this class (the sync T3/T4/T5 assertions carry the same unproven-discrimination note); found only because a B-pass agent died mid-run having proposed exactly this experiment. | 2026-09-05 (`e7c4b2`; `test/sql/oi46_daily_cap_triggers_live_verify.sql` header carries the per-assertion split) |

### Citing a Postgres function's body from the migration that CREATED it — the LAST `CREATE OR REPLACE` wins

| Pitfall | How to avoid | Source |
|---|---|---|
| **Citing a Postgres function's body from the migration that CREATED it — the LAST `CREATE OR REPLACE` wins** | `supabase/migrations/` is append-only, so one function has several definitions and only the highest-numbered one is live. `enforce_food_text_daily_limit` is defined in **026, 113 AND 127**; `enforce_vision_analysis_daily_limit` in **111 AND 114**. Reading an earlier one is stale BY CONSTRUCTION, and it does not merely give you an old number — **migration 111 defines BOTH cap functions, so a first-match there returns the CHAT cap (10) when you asked for the vision cap.** Measured 2026-09-04: 111's vision cap (15) was read from source and reported to the founder as a *correction* to an earlier claim of 20, three weeks after 114 had replaced it with exactly 20. ⚠ **Comment-stripping is mandatory, and not for the reason you expect** — the commented rollback body sits BELOW the live statement so a first-match misses it anyway; the trap is the four-tag HEADER, whose `Rollback strategy:` line quotes the OLD value ABOVE the live one. Documenting the previous value makes the file self-trapping for any naive grep. Resolver + the two cap readers: `test/helpers/migration_cap_reader.dart` (`latestMigrationDefining`), mutation-proven. Verify live state with `pg_get_functiondef` rather than any migration file. ⚠ **And do not compute "the next migration number" with a naive numeric sort** — `ls | grep -oE '^[0-9]+' | sort -n | tail -1` answers **202**, because `20260331000001_add_pgvector_memory.sql` is timestamp-scheme and its first three digits are `202`. Three filename schemes coexist here (see `supabase/migrations/CLAUDE.md`), so match the scheme explicitly: `ls supabase/migrations/ | grep -E '^[0-9]{3}[a-z]?_'`. Sanity-check the answer by asking whether a migration with that number actually exists — one `ls` settles it. ⚠ **Since 2026-09-29 (OI-263) this recipe is for READING only — to ALLOCATE a number never read it off `ls` at all: `sh scripts/mint_migration.sh --next` / `<slug>` (root CLAUDE.md §7 row).** Measured 2026-09-04 while planning OI-162 slice 1. | 2026-09-04 (`b8f4c2`; cost one wrong founder-facing number) |

### A filter you add for READABILITY narrows the verification's input set — and zero results look identical to proof

| Pitfall | How to avoid | Source |
|---|---|---|
| **A filter you add for READABILITY narrows the verification's input set — and zero results look identical to proof** | Every `--include` / `-v` / `^\s+` / directory argument / `\| head` is a CLAIM that what you are looking for cannot appear where you just excluded. State the claim or drop the filter. **Four instances in ONE session** (2026-09-08/09, OI-162 slice 3b): **(a)** a `grep -rn <symbol> lib/ test/` written into a plan but *run* against `lib/` only returned "1 hit, its own definition", and the plan concluded a method was safely deletable — there were **2**, the second a contract-test map asserting that very file still read the old table; **(b)** `grep -cE "^\s+(warning\|error) -"` over analyzer output returned **0 against a REAL warning**. The analyzer **right-aligns the severity column to a FIXED width of 7** (`len("warning")`), so `warning` gets **0** leading spaces, `error` **2**, `info` **3** — fixed, not longest-present, because info-only output still gets 3. That anchor therefore matches `error` and `info` and is structurally blind to exactly ONE severity: **`warning`**, the only one that matters, since `--no-fatal-infos` suppresses infos and an `error` fails the build anyway. It would have failed the push with git's opaque `failed to push some refs`. Positive control on real output: warnings+info → `^\s+` **0** vs `^\s*` **2** with 2 warnings present; and on output that ALSO holds an `error`, `^\s+` returns a **NON-ZERO** count while still missing every warning, so the number reads like a successful find. ⚠ **Two independent runs disagreed (0 vs 1) purely because one sample had an error line, and both were right.** **(c)** a `grep -v "Running build hooks"` **deleted the answer**, because the banner prints on the SAME LINE as the result (`Running build hooks...Blast-radius: platform`) — stacked with omitting `blast_radius_from_diff.dart`'s `-` stdin flag, which silently classifies the EMPTY staged set instead; **(d)** a post-rename sweep scoped `--include=*.md --include=*.yaml` reported "none remaining" while the stale name sat in a **`.sql`**. **Prefer `git grep` for does-this-still-exist** — every tracked file, no extension list to get wrong. ⚠ **The tell: you wrote the filter and the expected answer in the same breath.** Say the input set out loud in its WIDEST form before citing any check, and read the COUNT, not the colour. ⚠ A review round argued this row was wrong by quoting analyzer-looking output from a **prose report** (em-dash separators, issue count printed *above* the issues) — characterising a tool's stdout from a hand-typed summary, which is this row's own error class committed while disputing it. Measure the tool. | 2026-09-10 (OI-172 batch; `feedback_green_check_input_set_width.md` #36–39, and #29's `part`-file row above is the same family) |

### A plan's SoT-registration step gets a new concept's full name right, but earlier steps in the SAME task still reference its test file by a shorthand abbreviation

| Pitfall | How to avoid | Source |
|---|---|---|
| **A plan's SoT-registration step gets a new concept's full name right, but earlier steps in the SAME task still reference its test file by a shorthand abbreviation** | Before dispatching a task whose brief creates a new SoT-registry concept, grep the brief itself for every occurrence of that concept's `_writer_to_reader_test.dart` filename and confirm ALL of them match the exact string the registration step declares — not a Hive-key/variable abbreviation used elsewhere in the same brief for brevity (e.g. `exlog`/`nlog`). Gate 9 (`check_writeservice_contracts.dart`) derives the required filename from the registry's `concept:` field alone, so a plan that is internally consistent everywhere except that one field-derivation rule reads as clean under human review — each citation looks locally plausible on its own — and fails only at commit time. **Recurred identically in 2 consecutive tasks of the same plan** (OI-204's `exlog`→`nlog` extension, mirroring the established `sync_scheduled_payload_hash_index` precedent whose Hive key is abbreviated but whose test file spells out the full concept name): Task 2's implementer discovered it mid-task (first commit attempt failed Gate 9); caught proactively in Task 3's brief before dispatch this time by `sed`-ing the exact suffixed string `_payload_hash_index_writer_to_reader_test` across the brief file and confirming the SHORTER bare Hive-key string (a different thing that correctly stays abbreviated per the plan's own Global Constraints) was untouched by the fix. | 2026-09-19 (OI-204 batch, diagnose `d3f8a6`; Task 2 report + Task 3 pre-dispatch brief fix) |

### A migration's own "Post-apply verification" comment can itself be an unsafe, non-transactional live write

| Pitfall | How to avoid | Source |
|---|---|---|
| **A migration's own "Post-apply verification" comment can itself be an unsafe, non-transactional live write** | A verification snippet inside a migration's comments is prose, not code the migration ever runs — nothing checks whether it is SAFE to actually execute as written. Migration 138's own snippet was a bare `UPDATE ... SET status = 'cancelled' WHERE id IN (SELECT id FROM subscriptions WHERE status = 'active' LIMIT 1) RETURNING ...`, with no `BEGIN`/`ROLLBACK` — run literally, it permanently cancels a REAL, randomly-selected active subscriber, relying on a trailing comment ("then manually revert this test row") for the operator to remember to undo it by hand. Worse, pre-140, a manual revert wouldn't even have restored the correct state — `cancelled_at` had no clear-on-reactivation branch, so "manually reverting" would have left a stale, permanent cancellation stamp corrupting the very digest metric this migration exists to power. Since the migration is IMMUTABLE once applied (`supabase/migrations/CLAUDE.md`), this cannot be fixed in place. **Before running ANY verification snippet copied from a migration's own comments, wrap it in `BEGIN; ... ROLLBACK;` yourself unless the snippet already visibly does so** — never trust the comment's own framing ("run this to verify") to imply it is transaction-safe. | 2026-09-21 (Hermes pass, `docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md`) |

### Appending `&` to a command that the tool ALREADY runs in the background double-backgrounds it — the outer wrapper can exit before the real work finishes, orphaning it and leaving `_git_lock.sh`'s lock stuck with a dead holder pid

| Pitfall | How to avoid | Source |
|---|---|---|
| **Appending `&` to a command that the tool ALREADY runs in the background double-backgrounds it — the outer wrapper can exit before the real work finishes, orphaning it and leaving `_git_lock.sh`'s lock stuck with a dead holder pid** | The harness's own background-execution flag (e.g. a Bash-tool `run_in_background: true`) already forks and tracks the command; adding a trailing `&` inside that command forks it AGAIN into a detached child the harness cannot track. Observed: `safe_commit.sh "$MSG" > log 2>&1 &` under `run_in_background: true` reported "launched pid N" and exited almost instantly (code 0) — the outer wrapper process died right after backgrounding its own child, the child (which had acquired `_git_lock.sh`'s lock) was reaped without running its `trap ... EXIT` cleanup, and the log file was left at 0 bytes. `Get-Process`/`Get-CimInstance` on the reported pid confirmed it was gone — not merely slow — before clearing the lock by hand (`rm -rf .git/worktrees/<name>/.safe_git_op.lock`, the documented manual-clear path for a confirmed-dead holder). **Never add your own `&`/backgrounding syntax inside a command already passed a background-execution flag** — let the tool's own backgrounding do the job, and redirect output with a plain `>` to a real file path (not a shell variable holding a Windows-style path passed through Git Bash, which can also silently misresolve). | 2026-09-22/23 (`next-aab-decision-d1227b` batch, alert_cron_failures fix; see also `feedback_git_landing_verification.md`) |

### A file whose own SUBJECT is invisible/separator characters (U+2028, U+2029, U+0085, ESC, …) is the one file where writing a literal escape-looking sequence in source risks the harness silently converting it to the ACTUAL raw character on disk

| Pitfall | How to avoid | Source |
|---|---|---|
| **A file whose own SUBJECT is invisible/separator characters (U+2028, U+2029, U+0085, ESC, …) is the one file where writing a literal escape-looking sequence in source risks the harness silently converting it to the ACTUAL raw character on disk** | `supabase/functions/_shared/sanitize_for_prompt.ts`'s own header comment records this happening to itself: its first draft wrote the escape examples as literal characters and an actual ESC byte + em-dashes landed in the file instead of the intended ASCII text — caught only by asserting the comment block is pure-ASCII in the test suite, not by eyeballing it. **Recurred twice more in ONE new test file** (2026-09-26, single-owner-a1 B-pass round 2): `test/ai_coach/compact_context_sanitized_length_test.dart`'s first draft embedded a raw U+2028 LINE SEPARATOR once in its own fixture and once inside the COMMENT warning about doing exactly that — found via `xxd`/hex dump (`e2 80 a8`) after a Python string-match unexpectedly failed, not by reading the file. **Fix, both times: build every such character from `String.fromCharCode`/bare hex integer literals (`0x2028`, not `' '` typed as prose), never a literal escape sequence anywhere in source** — including inside a comment that is WARNING about this exact trap, which is the self-referential shape both recurrences took. Verify with `python3 -c "print(sorted(set(hex(ord(c)) for c in open(f).read() if ord(c) > 127)))"` on the finished file. | 2026-07-27 (`f4a9c2`, sanitize_for_prompt.ts's own header) + 2× 2026-09-26 (single-owner-a1, `docs/diagnoses/2026-09-26-ai-proxy-prediction-unmetered-caller-prompt-125b81.md`) |

### After a GitHub-PR merge, PRIMARY's local `main` can lag `origin/main` by exactly the merge commit — and `retire_worktree.dart` reports the just-merged branch as `[branch not merged]`, reading as a real problem

| Pitfall | How to avoid | Source |
|---|---|---|
| **After a GitHub-PR merge, PRIMARY's local `main` can lag `origin/main` by exactly the merge commit — and `retire_worktree.dart` reports the just-merged branch as `[branch not merged]`, reading as a real problem** | Nobody runs `git pull` on primary's own `main` just because a PR merged remotely — the merge landed on `origin/main`, not on primary's LOCAL `main` ref, and the retirement predicate checks the local one. Fix: `git fetch origin main && git merge --ff-only origin/main` while `main` is checked out (safe — refuses outright on any real conflict, so it cannot silently discard anything). Re-run the dry-run; `[branch not merged]` becomes `[merged + clean + pushed]` (or the `no upstream configured, or it was deleted on the remote` form once the remote branch is gone) with no other change. Confirmed twice, not a one-off: `reps-secs-invalidation-fixes` (2026-09-28) and `schedule-status-single-writer` (2026-09-29), both via a GitHub-PR merge (§4.13 point 8's autonomous-retirement flow makes this the FIRST thing to check on any `[branch not merged]` verdict, before assuming the merge itself failed). | 2026-09-29 (`schedule-status-single-writer`; `feedback_autonomous_worktree_retirement_on_batch_close.md` in the harness memory dir) |

### A merge of two long-lived branches into a shared, dated, self-numbered file (a skill's own bug-class index, tuning history, etc.) can silently produce a numbering COLLISION — same slot, two unrelated entries, no content lost

| Pitfall | How to avoid | Source |
|---|---|---|
| **A merge of two long-lived branches into a shared, dated, self-numbered file (a skill's own bug-class index, tuning history, etc.) can silently produce a numbering COLLISION — same slot, two unrelated entries, no content lost** | Unlike OI numbers (`mint_oi.sh`/`check_oi_numbering_unique.dart`, CLAUDE.md §7) or `check_*.dart` gates (filename-keyed, not number-keyed), a file like `.claude/skills/debugging/SKILL.md`'s `### N.M` bug-class index has NO allocator and NO uniqueness gate — nothing in the pre-commit/CI loop greps for `^### [0-9]+\.[0-9]+` duplicates. Two branches independently extending the SAME index while diverged will each correctly compute their own "next free number" from their own tip, and a clean 3-way git merge (no textual conflict, since each side inserted at a different point in the base) lands both bodies intact under the SAME number — a defect invisible to `git diff`, `git log`, and every existing gate, because nothing was lost or marked conflicted. Found 2026-09-29 (`oi-245-246-restore-fixes` merge-reconciliation review, `docs/reviews/07f2a817bbdd-review.md`): this branch's own new entry and `origin/main`'s day-swapper-batch entry both independently claimed `### 2.74`. **Detection: after resolving ANY merge that touches a shared self-numbered file, `grep -oE "^### [0-9]+\.[0-9]+" <file> | sort | uniq -d` (adjust the pattern to the file's own numbering scheme) and diff the result against the SAME check run on each parent alone — a duplicate absent from both parents is a merge-introduced collision, not a pre-existing one.** Fix: renumber the smaller/later-landing side to the file's true next-free number, then re-grep the WHOLE tree (not just the file itself, and not a single literal pattern — use several: `§N.M`, `class N.M`, `bug-class N.M`) for anything citing the old number by value (a plan-review record, a diagnose-doc's `related_bugs:` field), since a stale cross-reference is exactly as easy to miss as the collision itself. ⚠ **Recurred IMMEDIATELY, same file, same batch, hours later:** the very next merge-reconciliation pass on this same branch (a THIRD, unrelated branch landing on `main` in between) produced a SECOND collision at the number this row's own worked example had just renumbered TO (`2.77`) — a different concurrent branch had independently claimed it too. **This is not a one-time fix; re-run the detection grep on EVERY merge that touches the file, not just the first one that surfaces a conflict marker** — a CLEAN auto-merge (no textual conflict at all) is exactly the case this class hides in, since nothing about a clean auto-merge prompts anyone to check. | 2026-09-29 (`oi-245-246-restore-fixes`; `docs/reviews/07f2a817bbdd-review.md`, addendum) |
