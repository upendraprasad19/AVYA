# Plan — L1b "coach history tools and server readers" (OI-296, OI-308, OI-269, OI-307 reader side)

**Version:** v12 (2026-10-06), after plan-review round 11 (R11T: one P2, no manual pr-detection invoke; wording, §7h); v11 was after round 10 (R10T: one P2, the pr-detection window is now tick-aligned, §7g); v10 was after round 9 (R9T); v9 was after round 8 (R8T) and L1a-2 v6 withdrawing the server day clamp: `completed_at` stays the write time, so day-window readers select rows BY `workout_log_id` instead of by `completed_at`. Round-10 dispositions §7g, round-9 §7f, round-8 §7e, round-7 §7d, round-6 §7c, round-5 §7b, round-4 §7a, round-3 §7, round-2 §8, round-1 §9.
**Umbrella:** `docs/superpowers/specs/2026-10-03-progress-review-design.md` v3.1, landing L1. Siblings: L1a-1 `docs/plans/coach-history-correctness-sync.md` (server migration; its §0 V-rows are cited here) and L1a-2 `docs/plans/coach-history-correctness-client.md` (client restore/delete; no server clamp since its v6) — L1a was split after round 3.
**Execution branch / worktree:** `coach-history-correctness-tools`. **Mode:** inline, one coordinator.
**Blast radius:** `platform` (`_shared/**`, `ai-proxy/**`, `weekly-recalc/**`; `weekly-report`, `i-see-you-callout`, `pr-detection`, `future-prediction` via the catch-all `blast_radius.yaml:421`).
**Order with L1a:** independent code (L1a-1 touches no Edge Function; L1b touches no `lib/`). Before L1a-1's apply, readers dedupe on their own (B1); after it, there is one live row per key. Known gap until L1a-1 applies: a delete that hits OI-312 leaves its live row, which readers still count (undetectable — identical to a re-log); L1a-1's precondition requires 0 such pairs.
**Status:** v12 — CONVERGED (round 11 P2 was a post-deploy check step only, applied). No code.

**Live facts (coordinator, read-only, 2026-10-06):** rows whose `workout_log_id` is the shared missing-date bucket `v5('workout_')`: 0 in `workout_log_exercises` (of 226), 0 in `workout_log_sets` (R4T-4). `proactive_pr_detection` runs hourly (`0 * * * *`, migration `141_disk_io_audit_cleanup_batch.sql:154-165`, `docs/operations/CRON_REGISTRY.md:28`) while `pr-detection/index.ts:72-78` reads only the last 20 minutes (R4T-1).

---

## 1. Defects

| # | Defect | Readers (file:line) | Prior / class |
|---|---|---|---|
| T1 | Duplicate live summary rows summed/counted (OI-307 reader side) | `progress/getProgressSummary.ts:60-64,85-90,108-124`; `getExerciseHistory.ts:48-56,79-125`; `getPRTimeline.ts:66-75,113,157`; `weekly-report/index.ts:216-224,322-326`; `future-prediction/index.ts:67-74`; `i-see-you-callout/index.ts:229-236`; **`pr-detection/index.ts:85-100`** (filters `is_pr` server-side before any dedupe, so a superseded row's stale PR is celebrated — R3TB); **`weekly-recalc/index.ts:236-264`** (progression grouping uses every live row — R3TB) | OI-307 |
| T2 | Volume = weight × reps × sets (OI-308); model- and user-facing text treats cumulative `reps` as per-set reps | `getExerciseHistory.ts:88,95,101,145`; `getPRTimeline.ts:113-117,172` (description); `i-see-you-callout/index.ts:265-267` ("`${reps} reps`" next to a weight); `pr-detection/message.ts:18` | **Recurrence** of APK #12.6 (`5c61edc6`) |
| T3 | Tombstoned rows read as live (OI-269) | `progress/getProgressSummary.ts:60-64,85-90`; `weekly-report/index.ts:216-224`; `i-see-you-callout/index.ts:229-236`; `future-prediction/index.ts:67-74` | **Recurrence** of the OI-246 follow-up |
| T4 | UTC day boundaries and edit-day bucketing | `progress/getProgressSummary.ts:29,37-38,113`; `getExerciseHistory.ts:42,90`; `getPRTimeline.ts:77-78,114`; `weekly-report/index.ts:170-174,222-223,247,417`; `weekly-recalc/index.ts:242,264` | **Recurrence** of 7ad0d3 |
| T5 | Unpaged long reads (OI-296) | `progress/getProgressSummary.ts:60-90` (incl. `scheduled_workouts` `:67-70`); `getNutritionHistory.ts:106-114`; `getPromotionStatus.ts:160-168`; `getExerciseHistory.ts:48-56`; `future-prediction/index.ts:67-74` | **Recurrence** of `docs/diagnoses/2026-08-01-unbounded-cron-reads-d3f7b2.md` |
| T6 | `getNutritionHistory` items: unchunked `.in()`, read for `total` | `getNutritionHistory.ts:117-126` | same file |
| T7 | `getPRTimeline` `.limit(50)` presented as all-time | `getPRTimeline.ts:20,75,128,157` | new |
| T8 | Adherence counts future days; misses `moved`/`dropped` | `progress/getProgressSummary.ts:66-70,134-141`; set inline at `rank_engine.ts:188-200` | APK #12.6 class |
| T9 | pr-detection reads a 20-minute window but its cron has run hourly since migration 141 ⇒ PRs completed ~20–60 min before each tick are never read and never celebrated (R4T-1) | `pr-detection/index.ts:72-78` (comment "15min cron + 5min buffer") vs `141_…sql:154-165` | Writer/reader drift between a cron schedule and its function's window (class 2.1); 141 changed the schedule without the window |

**Reader dispositions:** `getPromotionStatus.ts:136` rolling window — `verified_clean`; `restore-user-snapshot:197` ships rows to the client restore — owned by L1a-2 U2. `pr-detection` and `weekly-recalc` are no longer `verified_clean` (R3TB): both are fixed by B1 (T1) and both are deployed (§5).

## 2. Units

**B1 · shared pure helper `_shared/live_exercise_rows.ts`.** `liveSummaryRows(rows)`: drop rows with `deleted_at`; keep one row per **`(user_id, workout_log_id, exercise_id)`** (`workout_log_id` is date-only and not user-scoped, `sync_workout.dart:279,327-330`, so `user_id` is required for multi-user readers); rows whose `workout_log_id` does not resolve in the B3 day map (e.g. the missing-date bucket `v5('workout_')`, 0 rows today but producible by installed APKs) are keyed by `(user_id, IST(completed_at) date, exercise_id)` instead, so they never collapse across days (R4T-4); winner = the highest `set_number`, then highest `id` — the last push in 44 of 44 live groups (L1a-1 V11); after L1a-1 there is one row; the winner's OWN `is_pr` is used (last write wins, founder decision). Every reader selects `user_id, workout_log_id, exercise_id, set_number, is_pr, completed_at, deleted_at`, queries with `.is("deleted_at", null)` on the server as well, and applies **dedupe BEFORE any `is_pr` filter or cap**:
- `getProgressSummary` derives `pr_count` from query 1's deduped rows (query 1 now selects `is_pr`; query 5 removed — the parallel-queries pin is repointed from 5 to **4** `.from(` calls);
- `getPRTimeline` reads the exercise's rows (paged, B4), dedupes, filters `is_pr`, then caps (B6);
- `i-see-you-callout` reads the user's last-24 h rows (all, not only `is_pr`) with `.limit(1000)` in the same statement (one user's day is far below it — R3TA bound), dedupes, filters `is_pr`, takes the newest;
- `pr-detection` drops `.eq("is_pr", true)` from its paged read (`fetchAllPages`, unchanged paging), dedupes per user, then filters `is_pr` (R3TB); **T9 (R5T-1):** in the same commit the window moves into a pure module `pr-detection/window.ts` as `prWindow(now) = {since: floorToPeriod(now) − period, until: floorToPeriod(now)}` (tick-aligned, `PR_PERIOD_MINUTES = 60`; the read filters `completed_at >= since AND completed_at < until`, so each row present at its tick is read by exactly one tick (a row pushed after its tick passed — `completed_at` is the device's write time — is read by none; today's 20-minute window loses those too, plus every row 20–60 min old; named as a residual in the T9 diagnose-doc, R11T-1) and a few minutes of cron start drift neither drops nor repeats a row — R10T-1) (`index.ts` calls `Deno.serve` at import, so it cannot be tested directly); the header comment (`:2-6`, still "every 15 min") and the `:72` comment cite migration 141 and the registry row. The test finds the cadence from the WRITER — the last `cron.schedule('proactive_pr_detection', '<cron>'` or `cron.alter_job(… schedule := '<cron>')` for that job across `supabase/migrations/` in migration order (today `141_…sql:162-165`; creator `031_…sql:27-29`, multi-line). The parser strips `--` and `/* */` comments first (141 ends with a commented rollback to `*/15`, `:188`), matches across whitespace/newlines, orders files by the `NNN[a-z]?_` scheme (`050b_`, `068b_` exist), and ignores the timestamp-prefixed files and `all_migrations_combined.sql` (R7T-1) — asserts the `docs/operations/CRON_REGISTRY.md:28` cell equals it (`check_cron_registry.dart` checks names only, `:82-83`), converts it to minutes, asserts `PR_PERIOD_MINUTES` equals it, and asserts two consecutive ticks (`T`, `T+60 min`, each with a few seconds of start drift) give adjacent, disjoint windows; a PR at `T−3 min` is read by exactly one of the two ticks (R6T-2/3, R10T-1); mutations: a fixture migration altering the job to `0 */2 * * *` ⇒ red; the registry cell edited alone ⇒ red; a fixture shaped like 141 — a live alter to `0 */2 * * *` followed by a commented rollback to `0 * * * *` — ⇒ red. A shared TS constant would be true by construction and is not used. There is no overlap to absorb: `shouldSendProactive` (`_shared/proactive_dedup.ts:52-70`) only blocks the same type on the same IST date and other senders overwrite its single slot between ticks, so an overlapping window would push a PR twice (R10T-1). Deploy check (tier 7): live `cron.job` schedule for `proactive_pr_detection` = `0 * * * *`;
- `weekly-recalc` runs `liveSummaryRows` after `excludeDeletedLogs` (`:251`) so the progression score and variety see one row per key (R3TB);
- `future-prediction` likewise.
Behavioural Deno tests on the helper (two users same day; three rows A→B→A documented as "highest count wins" — the known limit of any server rule before L1a-1; a stale PR on a superseded row is dropped) plus one per reader above (pr-detection: a superseded `is_pr` row is not celebrated, and a PR 50 minutes before the tick is read; weekly-recalc: the progression input has one row per key). SoT concept **`wle_live_summary_read_contract`** (`exercise_logs_read_path` already exists, `docs/sot_registry.yaml:341`) with `behavioral_test_path` = the helper test.

**B2 · T2.** Volume = weight × cumulative reps. Model- and user-facing text fixed at the source:
- `getExerciseHistory` description becomes "… each session's best weight, total reps across all sets and set count …"; the response field `reps` is renamed `total_reps` (also in `getPRTimeline`'s `PREntry`), and `total_volume_kg` is documented as best weight × total reps;
- `getPRTimeline` description (`:172`) says "total reps" (R3TB);
- `i-see-you-callout` (`:265-267`) and `pr-detection/message.ts:18` stop rendering `weight × N reps` from the cumulative field: with a weight they show the weight only; without a weight, "`N total reps`" (R3TB).
These are AI-prompt / notification-copy changes (§6). The diagnose-doc discloses that best weight × total reps still overstates pyramid sets (`ai.md:198`). Tests: math test mirroring `get_progress_summary_math_test.dart`; declaration tests pinning both descriptions; message tests for the two notification strings.

**B3 · T4.** Windows are half-open IST ranges `[d T00:00:00+05:30, next day T00:00:00+05:30)` (`_shared/ist_date.ts`, the `istYesterdayWindow` pattern), each tool's window defined as exactly N IST dates ending today (`getProgressSummary` `periodDays` dates; `getExerciseHistory` `weeks × 7`; `getPRTimeline` `from`/`to` as IST dates (R3TA); `weekly-report` 7 dates, from 8 today at `:170-174` — for ALL three of its reads (summary rows, `nutrition_logs` `:183-184`, `workout_logs` `:235-236`) so the report's days line up (R9T-4); `weekly-recalc` 28).
- **Day of a summary row = the date whose UUID v5 equals `workout_log_id`.** The map covers **2020-01-01 to today + 400 days** (~2,870 entries; not just the window — an edited old log carries a recent `completed_at` and an old `workout_log_id` (R3TA), and a coach reschedule moves logs to FUTURE days (R4T-3)), fallback IST(`completed_at`). Rows whose resolved day falls **outside** the window (before its start or after its end) are dropped after the read. **Selecting the window (v9, replaces the R5T-3 widening, the R6T backfill dependency and the R7T bounds):** `completed_at` is the write time — an edited old log carries a recent one, a forward-moved log keeps an earlier one — so no `completed_at` range selects a day window correctly. Every **day-window reader** (`getProgressSummary` q1, `getExerciseHistory`, `weekly-report`, `weekly-recalc`) therefore selects summary rows with `.eq("user_id", …)` (or the all-user cron equivalent) and `.in("workout_log_id", ids)` where `ids` = the UUID v5 of each IST date in its window PLUS the missing-date bucket `v5('workout_')` (installed APKs can still write it, `sync_workout.dart:278-279`; its rows are attributed by IST(`completed_at`) and window-filtered in memory — R9T-1; live today: 0 null and 0 unresolvable ids of 226, coordinator read-only 2026-10-06), in chunks of ≤ 100 ids fetched concurrently and paged (B4/B5 termination); per-user reads use `uniq_wle_user_wlog_ex_set` (`082_…sql:34`, leads with `user_id, workout_log_id`); `weekly-recalc`'s all-user read uses `idx_wle_workout_log_id` (`009_…sql:42`). After dedupe every reader sorts by (resolved day asc, `completed_at` asc) before computing anything order-dependent — `getExerciseHistory`'s `current_weight_kg`/`weight_change_kg` (`:102-104`, "chronological, oldest first" `:33`) and `weekly-report`'s PR order (`:535`) — because pages are keyed by the random `id` and chunks arrive concurrently (R9T-2); test: two in-window days whose ids sort in reverse ⇒ `current_weight_kg` is the later day's. Exact for edited-old and forward-moved rows alike, no widening, no upper bound. `getPRTimeline` (all-time per exercise) keeps no `completed_at` bound and filters on the resolved day (R4T-2); `future-prediction` has no lower bound. **Recency readers** (`pr-detection`, `i-see-you-callout`) keep their `completed_at` recency bound (a fresh write) AND require the row's resolved day to be IST yesterday or today — this excludes an old log edited today (a new improvement: today such an edit re-announces an old PR) and a forward-moved row (its day is later), while a workout logged today for yesterday (the coach's past-date log, `tool_dispatcher.dart:370-389`) is still celebrated as it is today (R9T-3); no `created_at` or upper bound is needed because `completed_at` is never future-dated. Re-announcement edge (narrower than today, R11T-1, R11C-1): editing yesterday's PR today, editing today's PR in a later hour, or moving an old PR row into today/yesterday can push again when the dedup slot is free (new IST date or another type overwrote it) — founder ACCEPTED 2026-10-06 (L1a-2 U3); ledger row `verified_clean`. Tests: an edited old PR (resolved day 3+ days back) is not celebrated; a forward-moved PR is not celebrated; a fresh PR is; a PR logged today for yesterday is. This closes OI-296's edited-old-log fixture on the reader side for every APK. 
- **UUID v5 via `crypto.subtle` (R3TA):** `_shared/uuid_v5.ts`, SHA-1 over namespace bytes + name, version nibble 5, RFC 4122 variant, lowercase hex — no npm dependency, no import-map change. Pinned by a parity fixture: one real live `workout_log_id` and its date (read-only `SELECT`, recorded in the test), plus the Dart `_deterministicId` output for the same name.
- **Module placement (R4T-5):** the day map, window helpers and `uuid_v5` live in NEW modules (`_shared/uuid_v5.ts`, `_shared/exercise_day.ts`); `_shared/ist_date.ts` and `_shared/paged_fetch.ts` stay byte-identical (checked by `git diff --stat` in the plan-review record), so no other function's bundle changes.
- `weekly-report:247` and `:417` use the same day function so the `rpeByDate` join (`:258-268`) lines up.
- Tests: a future-dated `workout_log_id` (rescheduled) dropped from a window ending today; `getPRTimeline` with a past `to` returns an edited-old-log PR dated to its own day; 00:15-IST, 23:50-IST, an edited-old-log row (old `workout_log_id`, in-window `completed_at`) excluded from the window and attributed to its own day; window edges; `weekly-report` and `weekly-recalc` through extracted pure helpers (both call `serve()` at import).

**B4 · T5 paging.** In a NEW module `_shared/paged_fetch_bounded.ts` with its own count-bearing builder type (R4T-5; `paged_fetch.ts`, imported by ~20 functions, is not edited): `fetchPagesBounded<T>(makeQuery: (withCount: boolean) => builder, {orderBy, maxPages, label}) → {rows, truncated}`: page 0 requests `count: 'exact'` (only page 0 — a count on a later page past the total returns PGRST103); stop when `rows.length >= count`, or on an empty page, or when `count` is null (falls back to the empty-page rule); `truncated` = `maxPages` reached with a full last page. The count-bearing builder type is declared in the new module (R3TA; `paged_fetch.ts:93-96` `RangeableBuilder` stays as is). Order keys: `id` for wle; `[date, id]` for `weight_logs` and `nutrition_logs`; `[date desc, id]` for `getPromotionStatus` dates; **`[scheduled_date, id]` for `scheduled_workouts` in `getProgressSummary` (`:67-70`, R3TA)**. `Promise.all` in `getProgressSummary` preserved. Tests: the three stop paths; 2,350 rows in 1,000-row pages; count shrinking between pages ends on the empty page without a false `truncated`. Latency measured per tool and recorded; `maxLatencyMs` adjusted with a test if needed.

**B5 · T6.** Items skipped for `aggregation: "total"`. For `per_day`: ranges ≤ 31 days attach items (chunks of 100 ids fetched concurrently, B4 termination); longer ranges return per-day totals **without items** plus a note "items omitted for ranges over 31 days" — no rejection, so the default call (`aggregation` defaults to `per_day`, `:25-26`) never fails. The `.describe()` text gains that sentence (AI-prompt change, §6). Test: 60-day `per_day` call ⇒ totals, no items, note.

**B6 · T7.** Read the exercise's PR-candidate rows fully (paged, `.limit` removed), dedupe (B1), filter `is_pr`, **sort by (resolved day desc, `completed_at` desc)** before the cap and before computing `first_pr_date` / `latest_pr_date` and the progression note (`:113-150` assumed `completed_at DESC` order; an edited old row would otherwise sort as latest — R4T-2), return the 50 most recent with `truncated: true` and a note when more exist; `pr_count` / `first_pr_date` computed over all live PRs.

**B7 · T8.** `.lte("scheduled_date", istDateStr())`; excluded statuses `paused`, `skipped`, `rest`, `moved`, `dropped`, null — a mirrored constant. The parity test asserts the relation **tool set ⊇ `rank_engine.ts:188-200` set ⊇ client `invisibleScheduleStatuses`** (`workout_schedule_read_service.dart:889-891`), with `skipped` and null listed as deliberate tool-only additions (R3TA; an equality test would fail today on true data).

**B8 · gate — two commits, §4.11 order (R4T-6, R5T-2).** The gate has only a whole-gate `--warn-only` flag (`check_unbounded_cron_reads.dart:115,208,228`), its `_shared` scan is not recursive (`:174-183`), and pre-commit runs every gate with no arguments and discards the output (`scripts/pre-commit.sh:372`), as does CI (`.github/workflows/test.yml:270`). So the **FIRST commit** builds a scoped mode: a recursive scan of `_shared/tools/**` (keeping the `_test` exclusion), a single named constant listing the WARN scope, tools-scope violations print `WARN` and are left out of the exit code while every other violation still exits 1; a test asserts both in one run (tools-path violation ⇒ exit 0 + `WARN`; non-tools violation ⇒ exit 1) and is mutation-proven by treating every path as tools-scope (the second assertion reddens); the ledger moves `grandfathered → mutation_proven` in this commit (rule 24). The **LAST commit**, after B4, B5, B6 and the `suggestMeal` rewrite and at least 24 h after the first, deletes the scoped-WARN branch (no dead flag) and flips the test to expect exit 1; mutation re-run. If the branch is ready sooner, the flip waits — no waiver is assumed. Baseline: the coordinator runs the gate by hand at both commits and pastes the output into the plan-review record (pre-commit shows nothing). `scripts/check_unbounded_cron_reads.dart` gains `_shared/tools/**` and recognises `fetchPagesBounded` (`_pagedHelper`, `:77`); the header's "client-invoked out of scope" sentence is narrowed to say coach tools are in scope. The reads it would flag today (R3TA, each site read) and their fix: `progress/getProgressSummary.ts` ×5 (B4), `getExerciseHistory.ts:49` (B4), `getNutritionHistory.ts:107,124` (B4/B5), `getPromotionStatus.ts:164` (B4), `suggestMeal.ts:102` (rewritten as one statement with its `.limit(500)` from `:118`), and `getPRTimeline` once its `.limit(50)` is removed (B6). Before the flip commit the WARN list must be **zero**. Ledger: `check_unbounded_cron_reads.dart` moves from `grandfathered` (`gate_test_ledger.yaml:695`) to `mutation_proven` with its new test (one state per gate). `weekly-report`, `future-prediction` and `pr-detection` are not cron-auth files or are already paged, so their conversions are covered by named behavioural tests.

**Test fakes:** `unit_c_read_hardening_test.ts` fakes gain `is` and `range`; assertions become `assertRejects(fn, Error, "query failed")`. `future-prediction/index_test.ts:110-117` stub gains `is`/`range`.

## 3. Ripple set (repoint, never loosen)
`test/contracts/get_progress_summary_parallel_queries_test.dart` (`.from(` count 5 → 4; keep `await Promise.all(` and `maxLatencyMs`), `test/contracts/get_progress_summary_math_test.dart`, `supabase/functions/_shared/tools/__tests__/{getProgressSummary,getExerciseHistory,unit_c_read_hardening}_test.ts`, `test/ai_coach/get_nutrition_history_tool_test.dart:33-37`, `supabase/functions/_shared/paged_fetch_test.ts`, `supabase/functions/future-prediction/index_test.ts:110-117`, `test/contracts/audit_2026_06_07_batch6_server_test.dart:117` (greps i-see-you-callout), `pr-detection`, `weekly-recalc` and `weekly-report` tests, `docs/architecture/ai.md` tool sections (descriptions + `total_reps`), `docs/sot_registry.yaml`.

## 4. Expected live effect (measured before deploy)
A read-only query records, for the duplicate account, the before/after of volume, sessions and PR counts per tool (24 groups carry a PR row) in the diagnose-docs.

## 5. Process
- Diagnose-docs T1–T9 (FULL template with `related_bugs`/`recurrence` for T2–T5 and T9); one `fix(...)` commit per defect; B8's WARN commit first and its flip commit last.
- **Deploys, each its own founder go, from post-merge `main`:** `ai-proxy`, `weekly-report`, `weekly-recalc`, `i-see-you-callout`, **`pr-detection`** (R3TB). Pre-deploy check per function: fetch the decoded live files (`Accept: multipart/form-data`, deploy-rollback skill §6.9) and diff every module including `_shared/**` against post-merge `main`; any unrelated difference (e.g. the Gemini-3 changes from `beecc799` / `ca2f6f46`) is listed and needs its own founder go. Rollback SHA recorded; an authenticated smoke per function (`verify_jwt=true` ⇒ real user token).
- **Rollback (R3TB wording):** a defect is rolled back by reverting the offending commit on `main` and redeploying the affected functions from the result — never by redeploying an old payload over a newer `_shared/**`.
- **Closure ledger** `docs/audit/coach-history-correctness-tools.closure.yaml`: T1–T9 + B8 `closed_in_commit`; `getPromotionStatus` rolling window `verified_clean`; **per function, one `blocked_on_user` deploy row and one post-deploy check row** (ai-proxy: a tool response showing `total_reps`; weekly-report: a new row with a 7-date window; weekly-recalc: a run whose progression input is deduped (function log); i-see-you-callout and pr-detection: NO manual invoke — it has no dry-run or single-user path (`index.ts:55-187`) and a manual call re-reads the last tick's window and sends real pushes (R11T-1); the check is the first cron tick's function log (`pr_rows/users/sent`) and its `cron_call_log` row, plus a read-only query of the rows `[floor − 60 min, floor)` selected for the duplicate account; the Deno behavioural test is the proof for superseded rows); **`future-prediction` deploy decision `blocked_on_user`** — it has no caller (OI-210); its source is fixed for parity, deploying it is the founder's call.
- **future-prediction and the flips (R4T-7):** its decision row closes either as "deployed" (with its check) or as "declined — no caller (OI-210)"; either closure satisfies every flip rule below, and OI-269/OI-296 then record which.
- **Board:** OI-296 and OI-308 flip after their deploy + check rows close. OI-269 gets the note "source-fixed, not deployed" at merge and flips after the deploys (R3TB). **OI-307 flips only when L1a-1's apply row AND every L1b deploy row are closed** — whichever closes last flips it (stated in L1a-1 §7 and OI-307; R3TB).
- `deno check --node-modules-dir=none` per function; `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/` before push; B-pass before merge.

## 6. §4.6 decisions
Model-facing text changes (B2 descriptions and `total_reps`, B5 `.describe()` and note, B6 note) are AI-prompt changes; the two notification strings (B2) are user-facing copy. Decision: no flag — each corrects a statement that is false today; reverting is a one-commit revert + redeploy; precedent `docs/plans/auth-recovery-code-length.md:11`; recorded in the plan-review record for the founder to overrule. `weekly-recalc`: no gate — its outputs (`detected_experience_level`, `total_workouts_done` under GREATEST) are read by the AI snapshot, onboarding seed and beat-my-coach, not the plan engine (round 2 verified). Tool outputs otherwise only gain fields (`truncated`, notes).

## 7f. Round-9 dispositions
| Finding | Disposition |
|---|---|
| R9T-1 (unresolvable ids dropped) | `v5('workout_')` bucket added to every id list, attributed by `completed_at`; live count 0/0 cited. |
| R9T-2 (`getExerciseHistory` order lost) | Sort by (resolved day, `completed_at`) after dedupe; test. |
| R9T-3 (past-date coach logs no longer celebrated) | Recency readers accept resolved day = yesterday or today; test. |
| R9T-4 (weekly-report window size) | 7 dates for all three reads. |
| R9T minor (select list; index) | `completed_at` selected; `idx_wle_workout_log_id` cited for the all-user read. |

## 7e. Round-8 dispositions
| Finding | Disposition |
|---|---|
| R8T-1 (U1.5 apply before the bounded readers deploy) | Moot: U1.5 withdrawn (L1a-2 v6); `completed_at` is never future-dated. |
| R8T-2 (`created_at` bound misses next-day / same-day moves) | Bounds withdrawn; recency readers filter on the resolved day; tests. |
| R8T-3 (transitional row never closes) | Withdrawn with U1.5: day-window readers select by `workout_log_id`, so no transitional population exists. |

## 7d. Round-7 dispositions
| Finding | Disposition |
|---|---|
| R7T-1 (comment-blind cron parser) | Comment stripping, multi-line match, scheme ordering, exclusions; third mutation fixture. |
| R7T-2 (future-dated `completed_at` reaches recency readers) | `lte(now)` + `created_at` window on both readers; three tests. |
| R7T-3 (transitional row not terminal) | One `upstream_blocked` row closed by the L1a-2 U1.5 apply. |

## 7c. Round-6 dispositions
| Finding | Disposition |
|---|---|
| R6T-1 (widened weekly-report read truncates at 1,000) | Widening removed (its window is 7 dates per B3; "8-date" here was a slip, corrected by R9T-4). |
| R6T-2 (recency readers widened) | Widening removed; recency bounds stated unchanged; `prWindowSince` asserted. |
| R6T-3 (test parses a doc cell) | Test reads the migrations' cron writer, checks the registry against it; two mutations. |
| R6T-4 (permanent 428-day weekly-recalc scan) | Widening removed; L1a-2 U1.5 backfill closes the transitional rows. |

## 7b. Round-5 dispositions
| Finding | Disposition |
|---|---|
| R5T-1 (T9 test true by construction; untestable at `index.ts`) | `window.ts` pure module; test parses the registry row; mutation; header fix; tier-7 deploy check. |
| R5T-2 (no per-scope WARN mode; pre-commit discards output) | Scoped mode built + tested + mutation-proven in the first commit; branch deleted at the flip; manual baselines. |
| R5T-3 (lower-bound widening too small) | Widen by 400 days; deploy-time measurement. |

## 7a. Round-4 dispositions
| Finding | Disposition |
|---|---|
| R4T-1 (pr-detection 20-min window vs hourly cron) | New defect T9, fixed in the B1 pr-detection commit; live fact cited in the header. |
| R4T-2 (getPRTimeline upper bound; B6 order) | B3 no past upper bound; B6 sort by resolved day; test. |
| R4T-3 (future days) | Map to today + 400; after-window drop; test. |
| R4T-4 (missing-date bucket) | Measured 0/0; unresolved ids keyed by IST(`completed_at`) date; helper test. |
| R4T-5 (shared-module blast) | New modules; `paged_fetch.ts` and `ist_date.ts` byte-identical. |
| R4T-6 (B8 vs §4.11) | WARN commit first, flip last, ≥ 24 h apart. |
| R4T-7 (future-prediction vs flips) | Either closure of the decision row satisfies the flips. |

## 7. Round-3 dispositions
| Finding | Disposition |
|---|---|
| R3TB (pr-detection, weekly-recalc not clean) | T1 rows; B1 reader list; both deployed. |
| R3TB (cumulative reps wording ×3) | B2 bullets; message tests. |
| R3TB (OI-307 flipped before deploys) | §5 board rule; L1a-1 §7 and OI-307 match. |
| R3TB (ledger rows; future-prediction; OI-269; rollback) | §5. |
| R3TA (edited old log counted in-window) | B3 2020 map + out-of-window drop + test. |
| R3TA (unbounded `scheduled_workouts`) | B4 order key `[scheduled_date, id]`. |
| R3TA (B8 order; list of flagged reads) | B8 lands last; the reads listed with their fixes; warn-only must list zero. |
| R3TA (i-see-you bound) | B1 `.limit(1000)` in the same statement. |
| R3TA (npm uuid unresolvable) | `crypto.subtle` v5 + parity fixture. |
| R3TA (B7 equality false) | Superset relation. |
| R3TA (`RangeableBuilder` count; query 1 `is_pr`; pin count) | B4; B1; §3 (5 → 4). |

## 8. Round-2 dispositions (still valid)
R2TA-1 → key with `user_id`; R2TA-2/R2TB-1 → highest `set_number`; R2TA-3 → dedupe before `is_pr`; R2TA-4 → server `.is` + paged-then-capped; R2TA-5 → `makeQuery(withCount)`; R2TA-6/R2TB-11 → suggestMeal rewrite + ledger; R2TA-7 → named tests; R2TA-8 → N-date windows + id day; R2TA-9 → mirror + parity; R2TB-2 → B3; R2TB-3 → descriptions + `total_reps`; R2TB-4 → no rejection; R2TB-5 → multipart diff; R2TB-6 → concept name; R2TB-7 → §1 dispositions (revised in round 3); R2TB-8/9 → §5; R2TB-10 → §3; R2TB-12 → header gap.

## 9. Round-1 dispositions (from v2)
L1C-1 → B1; L1C-2/L1A-5/L1B-9/L1D-7 → future-prediction and the extra UTC sites in §1; L1C-3 → B4; L1C-4 → B5; L1C-5 → pure helper; L1C-6 → fakes; L1C-7 → B7; L1C-8 → B6; L1C-9 → B2; L1C-10 → B3; L1C-11 → B4/B8; L1C-12 → §4; L1D-6 → §5.

## 7g. Round-10 dispositions
| Finding | Disposition |
|---|---|
| R10T-1 (65-min window overlaps on an hourly cron; `shouldSendProactive` does not absorb it — other types overwrite the slot, and the IST-midnight tick is a new date) | T9 window is tick-aligned `[floor(now) − 60 min, floor(now))`; test asserts adjacent disjoint windows and single read of a `T−3 min` PR; the "absorbed" sentence replaced. |

Round 10 otherwise verified R9T-1..4 landed and §1–§7f consistent (no other material finding).

## 7h. Round-11 dispositions
| Finding | Disposition |
|---|---|
| R11T-1 (post-deploy "dry trigger" of pr-detection would send real duplicate pushes and could never fail) | Ledger check replaced by the first cron tick's log + `cron_call_log` + a read-only window query; pr-detection is never invoked by hand. Wording: "exactly one tick" limited to rows present at the tick (late arrival named as a residual); the edit-after-celebration residual stated next to B3's recency rule. |

Round 11 verified the tick-aligned window (disjoint `[since, until)`, drift-safe), the cron writer and registry cites, and that U3's latest-write `completed_at` adds no new defect (device rows already resolve to `updated_at_ms`; B3's yesterday/today rule narrows re-announcement).
