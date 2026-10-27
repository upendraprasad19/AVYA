# Drift-fix batch preflight — 2026-05-24

Captured by T0 implementer subagent before migration 068 + code changes.
Branch: `claude/frosty-bardeen-cce54b` HEAD `8f6a007`.
Project: `dedsavbjuwgarrhphgnl` (myfitnessjourney1988@gmail.com).

---

## 1. UNIQUE constraint name on workout_logs

Live `pg_constraint` query returned **0 UNIQUE constraints** on `public.workout_logs`. The natural-key uniqueness is enforced by a stand-alone UNIQUE INDEX (not a table-level constraint).

### All `pg_constraint` rows on `public.workout_logs`
| conname | contype | def |
|---|---|---|
| `workout_logs_pkey` | p (primary) | `PRIMARY KEY (id)` |
| `workout_logs_exercise_id_fkey` | f | `FOREIGN KEY (exercise_id) REFERENCES exercise_library(id)` |
| `workout_logs_scheduled_workout_id_fkey` | f | `FOREIGN KEY (scheduled_workout_id) REFERENCES scheduled_workouts(id)` |
| `workout_logs_template_id_fkey` | f | `FOREIGN KEY (template_id) REFERENCES workout_templates(id)` |
| `workout_logs_user_id_fkey` | f | `FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE` |

### All UNIQUE indexes on `public.workout_logs` (via `pg_indexes`)
| indexname | indexdef |
|---|---|
| `workout_logs_pkey` | `CREATE UNIQUE INDEX workout_logs_pkey ON public.workout_logs USING btree (id)` |
| **`uniq_workout_logs_user_date_name`** | **`CREATE UNIQUE INDEX uniq_workout_logs_user_date_name ON public.workout_logs USING btree (user_id, date, exercise_name)`** |

### DROP TARGET

`uniq_workout_logs_user_date_name` — UNIQUE INDEX (not constraint).

Migration 068 must use **`DROP INDEX IF EXISTS public.uniq_workout_logs_user_date_name;`** NOT `ALTER TABLE ... DROP CONSTRAINT ...`. The latter will fail because the index is not a table constraint.

After dropping, a new UNIQUE INDEX on `(user_id, date, workout_name)` should be created in the same migration:

```sql
DROP INDEX IF EXISTS public.uniq_workout_logs_user_date_name;
-- (column rename happens here: exercise_name → workout_name)
CREATE UNIQUE INDEX uniq_workout_logs_user_date_workout_name
  ON public.workout_logs (user_id, date, workout_name);
```

---

## 2. Column existence confirmation

- `workout_logs.exercise_name`: **PRESENT** (data_type: `text`)
- `workout_logs.workout_name`: **ABSENT** (correct pre-migration state — to be created by migration 068 as part of the rename)
- `workout_log_exercises.exercise_name`: **PRESENT** (correct — intentionally retained per CLAUDE.md §11 "exercise_id is the stable identity (= exercise_name)" rule for per-exercise rows)

The rename only affects the `workout_logs` (summary) table. The `workout_log_exercises` (per-exercise) table column stays.

---

## 3. Edge Function readers of workout_logs.exercise_name

### AFFECTED (reads `workout_logs.exercise_name` — must update + redeploy)

**1 file / 1 callsite** — verified by combining `.from("workout_logs")` grep (11 files matched) with `.select(...)` containing `exercise_name`:

- **`supabase/functions/weekly-report/index.ts:166-167`** —
  ```ts
  const { data: workoutSummaries, error: summaryError } = await supabase
    .from("workout_logs")
    .select("date, exercise_name, duration_seconds, rpe")
  ```
  Then at line 434 the prompt-builder uses `prs.map((p) => p.exercise_name)` — but that field comes from the SEPARATE `exerciseLogs` array (from `workout_log_exercises` at line 151), not from `workoutSummaries`. The `workoutSummaries` rows currently carry `exercise_name` purely because of the workout_logs read; downstream code at lines 178-188 maps them by `date` only and doesn't actually consume the `exercise_name` field from this read. **Still classified as AFFECTED** — the literal SELECT names a column that will not exist post-migration, so the query will 400 if not updated.

  **Fix:** change line 167 to `.select("date, workout_name, duration_seconds, rpe")` (or drop the field entirely if downstream code doesn't use it — verify via local read).

### NOT AFFECTED (reads workout_log_exercises or tool-argument schemas — column intentionally retained)

10 files / many callsites read `workout_logs` for OTHER columns (count, `logged_at`, `user_id`, `date`) without selecting `exercise_name`:

- `supabase/functions/evaluate-rank-promotions/index.ts:100` — `.select("*", { count: "exact", head: true })` — count-only, no column projection (PostgREST `head: true` returns no rows). Will continue to work after the column rename.
- `supabase/functions/i-see-you-callout/index.ts:170,256,294,308` — all select `logged_at` or count-only.
- `supabase/functions/streak-guardian/index.ts:90` — selects `user_id` only.
- `supabase/functions/re-engagement/index.ts:152` — selects `date` only.
- `supabase/functions/workout-window-closing/index.ts:115` — selects `user_id` only.
- `supabase/functions/_shared/tools/progress/getPromotionStatus.ts:117,126,154` — count-only / `.select("date")`.
- `supabase/functions/delete-account/index.ts:409` — comment-only mention (CASCADE chain description).
- `supabase/functions/_shared/captain_manual.ts:80` — comment-only mention (system-prompt copy referring to "workout_logs_count" snapshot field).

Reads of `workout_log_exercises.exercise_name` (column intentionally retained — NOT affected):
- `supabase/functions/i-see-you-callout/index.ts:203` — selects `exercise_id, exercise_name, weight_kg, reps, completed_at` from `workout_log_exercises`. Safe.
- `supabase/functions/weekly-report/index.ts:153,182` — selects `exercise_name, set_number, reps, weight_kg, duration_seconds, is_pr, completed_at` from `workout_log_exercises`. Safe.
- `supabase/functions/weekly-recalc/index.ts:18,54,87,182,185` — interface type + reads from `workout_log_exercises` table. Safe.
- `supabase/functions/_shared/tools/progress/getPRTimeline.ts:62` — comment-only ("exercise_id is the stable identity (= exercise_name)") + select on `workout_log_exercises`. Safe.
- `supabase/functions/_shared/tools/exercise/getFormCues.ts:18,30,54,57,78,105,117` — Zod tool-argument schema field name. Unrelated to the cloud column. Safe.
- `supabase/functions/_shared/tools/progress/getProgressSummary.ts` — uses `workout_log_exercises` via comments only.

**Summary:** ONE Edge Function (`weekly-report`) needs the SELECT updated + redeployed.

---

## 4. F5 method line range in workout_repository.dart

File: `lib/features/train/repositories/workout_repository.dart`

- Section header (line 1080): `// ── Single-exercise logging (shared by completeWorkout + AI coach) ──`
- Method docstring `///` lines: **1082–1113** (32-line docstring exclusively describing this method — no other method shares it)
- Method declaration: **line 1114** `Future<String> logSetWithPrRescan({`
- Method body closes at **line 1241** (the lone `}` before the next `// ── Deprecated delegation shims (Theme D1 — Test #11) ──` section header at line 1243)

**Delete range: lines 1080 through 1241 inclusive** (162 lines) — includes the section header at 1080, the blank line at 1081, the 32-line docstring at 1082–1113, and the method body at 1114–1241.

If preserving the section header is preferred (other "single-exercise logging" methods may be added in future), the **minimal delete range is 1082 through 1241 inclusive** (160 lines) — docstring + method only.

Recommended: **lines 1080–1241 inclusive** — the section header is method-specific too ("shared by completeWorkout + AI coach") and stale after deletion. Use the plan's Task 11 helper-text guidance.

---

## 5. F5 active caller count

**ZERO active callers in production code** — confirmed via grep `logSetWithPrRescan\(` and broader grep `logSetWithPrRescan`:

### Production code (lib/)
- `lib/features/train/repositories/workout_repository.dart:1114` — **the declaration itself** (sole production occurrence with paren-pattern matching `logSetWithPrRescan\(`).
- `lib/features/ai_coach/services/tool_dispatcher.dart:296` — **comment-only**: `// old per-set logSetWithPrRescan loop that produced N duplicate rows` (no paren).
- `lib/features/ai_coach/services/tool_dispatcher.dart:330` — **comment-only**: `/// `WorkoutRepository.logSetWithPrRescan` directly, which was ONE OF THE 3` (inside docstring, no paren).
- `lib/core/services/write_result.dart:51` — **comment-only**: `/// Calls routed through the legacy WorkoutRepository.logSetWithPrRescan` (inside docstring, no paren).
- `lib/core/services/exlog_key_migrator.dart:22` — **comment-only**: identifier appears inside `///` docstring (no paren).

### Tests (test/)
- `test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart` — assertion test that the dispatcher does NOT call the legacy method. References the name in test names + a `.contains('WorkoutRepository.instance.logSetWithPrRescan(')` source-grep assertion at line 56. **Will pass before AND after deletion** — assertion is "code must not contain this string" which becomes vacuously true once the declaration is gone.
- `test/contracts/exlog_key_canonical_test.dart:16` — comment-only reference.
- `test/contracts/exlog_migrator_handles_rogue_shapes_test.dart:6` — comment-only reference.

### Docs (docs/, scripts/)
- 18+ matches across `docs/audit/`, `docs/diagnoses/`, `docs/superpowers/`, `docs/sot_registry.yaml`, `scripts/check_exlog_key_canonical.dart` — all historical references describing the migration story or source-grep gates. None invoke the method.

**Verification:** The paren-pattern grep `logSetWithPrRescan\(` returned exactly **one** match across all `lib/**/*.dart`: the declaration at `workout_repository.dart:1114`. Zero active callers confirmed.

**Tests that must be updated post-deletion:** `test/contracts/tool_dispatcher_log_pr_uses_writeservice_test.dart` line 56 source-grep is forward-compatible (asserts absence) — no change needed. The new test `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart` (per plan Task 11) becomes the authoritative regression gate.

---

## Sign-off

All 5 preflight steps green. Migration 068 should:

1. `DROP INDEX IF EXISTS public.uniq_workout_logs_user_date_name;`
2. `ALTER TABLE public.workout_logs RENAME COLUMN exercise_name TO workout_name;`
3. `CREATE UNIQUE INDEX uniq_workout_logs_user_date_workout_name ON public.workout_logs (user_id, date, workout_name);`

Single Edge Function (`weekly-report`) needs SELECT updated + redeployed. F5 deletion is safe — zero active callers across all production code.

Captured: 2026-05-25 (T0 preflight subagent).
