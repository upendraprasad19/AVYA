# OI-469 (and OI-438): getFormCues answers from retired exercise rows (rev 3)

Worktree/branch `oi469-formcues-active` from main `c6b1ee48`. Execution mode: inline (one worktree, one writer).
Tier L (Edge Function under `_shared`, deployed through `ai-proxy`). Blast radius `platform` (`docs/blast_radius.yaml:106`, `_shared/**`).
Founder go 2026-11-13 ("Ok") covers writing the fix. The live `ai-proxy` deploy needs its OWN explicit go (CLAUDE.md §4.3).
Rev 3 = rounds 1 and 2 applied (all findings verified against the repo or live first). The one design call, strict filter vs prefer-active, was put to the founder 2026-11-13: **strict filter** (section 1).

## 0. The bug, writer and reader

**Symptom.** The coach tool `getFormCues` can return the form cues of a RETIRED exercise row (`is_active = false`) when an ACTIVE row of the same name exists, and can answer from a retired row at all.

**Reader (the bug).** `supabase/functions/_shared/tools/exercise/getFormCues.ts`
- stage 1, exact: `.from("exercise_library")` at :65, chain `.select(COLUMNS).ilike("name", name).limit(1).maybeSingle()` (:66-69)
- stage 2, partial: `.from` at :92, `.ilike("name", `%${name}%`)` (:93-96)
No `is_active` filter and no ORDER BY: with two matching rows the planner picks.

**Writer (what makes rows inactive).** Batch A merges and Batch C2a/C2b removals set `is_active = false`; nothing DELETEs. Migration 167 is Batch C2a (it deactivates the 50 removed rows, plus 7 Batch A repeats); the four same-name pairs below were deactivated by migration 171 (C2b, 11 `UPDATE ... SET is_active = false, coaching_cues` statements). Migration 164's rollback also deactivates rows (`UPDATE ... SET is_active = false WHERE source = 'exercise-gif-set'`, 629 rows); 175 reactivates E053; 174 and 176 change `suitable_for` / `movement_pattern` only. `template_exercises.exercise_id` and `workout_logs.exercise_id` are foreign keys to `exercise_library(id)` (`002_create_fitness_tables.sql:70`, `:127`; live `pg_constraint` 2026-11-13), which is why rows are hidden, never deleted.

**Same defect on the board twice.** OI-438 (`docs/audit/open_issues.md:6690-6700`, "Blocked on: the Edge Function deploy go", 2026-10-26) and OI-469 (:6914-6916, 2026-11-05) both end with "Done when: both queries add `.eq("is_active", true)`". Both close together after the deploy; both entries are edited in this branch to cross-link and carry the live verification (section 3).

**Live evidence (read-only, project `dedsavbjuwgarrhphgnl`, 2026-11-13).** 934 rows = 870 active + 64 inactive, 0 NULL `is_active` (column is `bool DEFAULT true`, nullable: `002:30`).
- 4 names exist as BOTH an active and an inactive row: Ankle Circles, Seated Piriformis Stretch, Sissy Squat, Toes to Bar (E084, E111, E169, E179; all `removed_in: c2b`, replacements G1368, G1489, G2567, G0474). The seed copied the kept twin's `coaching_cues` and `common_mistakes` onto the retired row, so cues are identical old vs new for these four; they differ in `instructions`, `primary_muscles`, `difficulty_level`, `logging_type`.
- 56 of the 64 retired rows have no live row whose name equals or contains theirs (the other 8: the 4 same-name pairs and 4 retired names that one live name contains). After the strict filter those names answer `found: false` and the coach falls back to general knowledge. Founder weighed this on 2026-11-13 and chose the strict filter. Evidence on both sides, for the record: the seed says a differently named retired row "keeps its own cues, which are right for its own name" (`scripts/seed_exercise_library.js:267-269`), but the same batch's plan treats the filter as the follow-up fix (`docs/plans/2026-10-25-library-batch-c2-removals.md:106`, `:129`: the cue copy exists "because getFormCues has no is_active filter"). In the removals file only 6 entries carry `alias_to` and 44 of the 56 say "Sheet drop", so at most about 14 retired names resolve in the Hive client (`name_aliases`); the other 44 are not offered in the app either.
- Rollback-by-deactivation (migration 164's rollback): a row deactivated because its cues or data were bad stops being served the moment it is hidden. This is the other half of why the strict filter was chosen.
- Rows pointing at a retired exercise: `template_exercises` 0, `workout_logs` 0, `workout_log_exercises` 0 (`workout_log_sets` not counted).

**Other readers of `exercise_library` in Edge Functions** (grep 2026-11-13, two reviewers): `swapExercise.ts:38` comment only, `promote-community-item/index.ts:191` INSERT only (`is_active: true` at :203); `lib/` has no direct Supabase read. getFormCues is the only unfiltered reader. `ai-proxy` is the only bundler (`ai-proxy/index.ts:55,63` -> `tool-loop.ts:58` -> `registry.ts:31` -> `exercise/index.ts:1`).

**Bug history (§4.1.5).** `docs/diagnoses/INDEX.md` is a local build (built in the primary 2026-11-13: no entry for formcues / is_active). Diagnose docs that mention getFormCues (b7d3e1, c3e8f1, e1a7c4, c1d7a4, f2c7a9, c2c e230) report no `is_active`-filter fix. This IS the soft-delete-flag writer/reader drift class (§4.1): a writer introduced `is_active = false` rows, one reader never learned. The diagnose doc says so and cites C2a `c2a7f1` as the writer.

## 1. The change

In `getFormCues.ts`, on BOTH queries add `.eq("is_active", true)` after `.ilike(...)` and before `.limit(1)`. Nothing else in the handler changes. `.eq` drops a NULL `is_active`; live has 0 NULLs and the column defaults to true, so a NULL row would be a data defect, not a case to serve.

Unchanged on purpose, recorded as findings (§5): no tie-break among several ACTIVE matches, no `%`/`_` escaping, no `name_aliases` stage.

`is_active` is a real column (`backups/live_schema_columns.json`; gate `check_schema_column_refs.dart`).

## 2. Tests (§4.4 rule 21)

New `supabase/functions/_shared/tools/__tests__/getFormCues_test.ts`, reusing `fake_sb.ts` (`eq`, `ilike`, `limit`; its `ilike` is an anchored whole-string regex with `%` as `.*`, case-insensitive) plus a LOCAL `withMaybeSingle` wrapper (pattern: `getPromotionStatus_test.ts:12-22`; `fake_sb` has no `maybeSingle`; `handler` is optional in `ToolDefinition`, so the test calls `handler!`). Every fixture lists the RETIRED row FIRST, so an unfiltered `limit(1)` returns it; the two rows' `coaching_cues` differ so the result identifies its source row.
- **A. exact twin:** "Sissy Squat" retired (first) + active; result = active row, `matched_via: "exact"`.
- **B. retired-only name:** "Pigeon Pose" retired only; `found: false` (stage 1 and stage 2 both miss).
- **C. retired exact + live containing name:** query "Lat Stretch": "Lat Stretch" retired (first), "Kneeling Lat Stretch" active; stage 1 misses, stage 2 returns Kneeling, `matched_via: "partial"`.
- **D. partial prefers active:** query "Stretch Test", "Stretch Test Alpha" retired (first), "Stretch Test Beta" active; stage 1 misses, stage 2 returns Beta.
- **E. no match:** `found: false` (GREEN before and after; pins the not-found shape).
- **F. both queries carry the filter:** the recorded `calls` show `["eq","is_active",true]` on each of the two `exercise_library` reads (use a query that reaches stage 2, e.g. D).
Without the fix A, B, C, D, F are RED; E is GREEN.

**Mutations (rule 21), each confirmed applied with `grep -c`, results recorded in the diagnose doc:**
1. remove `.eq` from stage 1 only: A, B, C red; D green (stage 1 misses anyway).
2. remove `.eq` from stage 2 only: B, C, D red (stage 2 then returns the retired row); A green.
3. remove both: A, B, C, D, F red.
4. change `true` to `false` in stage 1: A red.
5. replace `.eq` with `.order("is_active", { ascending: false })` on both (the rejected prefer-active design): B and C red, which proves the tests encode the strict decision.

**Registry, comments, pin (presence only).**
- `docs/sot_registry.yaml:12124-12126` (`exercise_library_schema`, reader `getFormCues.ts`; the Hive-client reader rows are :12120-12123) says "exact-name match with no is_active filter (why 162 copies the kept cues...)": reworded in the same commit ("filters is_active = true on both queries; the seed's cue copy is now defence in depth"), and given a `behavioral_test_path:` for the new Deno test per Gate 42 (pattern `docs/sot_registry.yaml:12023-12030`).
- `scripts/seed_exercise_library.js:253-254`, `:267-268` and `test/contracts/exercise_library_cloud_seeded_test.dart:476-478` comments are reworded ("historical: getFormCues now filters is_active"); two reviewers found no gate or hash covering them (re-grep `scripts/check_*.dart` and `test/` for the exact phrases before editing). The cue-copy SQL statements stay unchanged.
- `exercise_library_cloud_seeded_test.dart:560-605` already counts `.from("exercise_library")` >= 2 after comment strip; add a PRESENCE pin that the stripped source has `.eq("is_active", true)` at least twice (declared presence-only; the Deno test is the behavioural protection). The test header cite `getFormCues.ts:65,92` (:28) is re-pointed to the shifted lines.

## 3. Process steps and commands

- Diagnose doc `docs/diagnoses/2026-11-13-getformcues-inactive-rows-<id>.md` (slim fields + `touched_layers_checked`: tiers 1, 3, 4 verified; tier 6 "deploy pending founder go", filled by a docs PR from a new worktree after the deploy, because this branch will be merged by then). The `fix(...)` commit carries `closes-diagnose: <id>` (rule 22) and NO `closes-oi:` trailer (both OIs stay OPEN until the deploy). OI-438 and OI-469 each get `Verified: 2026-11-13` (live query above), a cross-link, and "Blocked on: the founder's go for the ai-proxy deploy".
- Local, in order, all with `--node-modules-dir=none`: `deno check` on `getFormCues.ts`, on the new test file, on `supabase/functions/ai-proxy/index.ts`, and on the whole tree `supabase/functions/` (CI, `.github/workflows/test.yml:267-275`); then `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/` (`_shared/` changed; `supabase/functions/CLAUDE.md` pitfall 1). `tool-loop_hard_failure_flag_test.ts` and `tool-loop_failure_kind_test.ts` pass `sb: null` and are insensitive to this change (not regression proof).
- §4.12.8 loop BEFORE a review round on the built diff: whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop, commit, open the PR, `sh scripts/land_pr.sh <pr> --ci-only` in the background; dispatch only on `result: ci-green`.
- Plan-review record `docs/plan-reviews/oi469-formcues-active.md`: 2 rounds on the plan (round 1 not converged, round 2 not converged, P2s all plan text), then a round on the built diff; `ground_truth_verified: true`, `bpass: accepted` (platform). B-pass (`/code-review`) before the merge; merge through `land_pr.sh` / `safe_pr_merge.sh`.

## 4. Deploy and live verification (needs its own explicit go)

`getFormCues` ships inside `ai-proxy` only. Per `.claude/skills/edge-function-deploy-rollback/SKILL.md`:
1. **From a throwaway clone with FULL history** at `origin/main` (§6.15 / OI-405; a `--depth 1` clone cannot resolve the live sha, §3.2; a worktree deploy rewrites tracked `backups/edge_function_payloads/ai-proxy/*` and leaves an untracked `.claude/_payload_*` that makes the worktree unretirable). Every API-talking `deploy_via_api.js` call gets `--token-file "<primary>/.supabase/supabase access token.txt"` (`emit_payload.js` takes no such flag) and `--yes` (no TTY).
2. **Pre-deploy diff:** a deploy ships the WHOLE local tree. Read the live artifact's commit (§3.4 step 2) and run a two-dot `git diff --name-only <live-sha> origin/main -- supabase/functions` (two-dot, in case the live sha is not an ancestor). Show the founder what else rides along with the go request (`docs/plans/2026-11-13-coach-late-link-timeout-retry.md` Fix 4 also wants an `ai-proxy` deploy).
3. **Rollback prepared BEFORE the deploy.** `ai-proxy` is `verify_jwt=false` (`ai-proxy/index.ts:28-30`; `test/contracts/runbook_deploy_verify_jwt_test.dart:47`). `--rollback` cannot take a verify_jwt argument and always reads it as true (`.claude/deploy_via_api.js:355`), so a bare `--rollback ... --yes` would 401 every user. The working recipe is §6.13: (a) `--rollback ai-proxy <live-sha> --dry-run` writes `.claude/_payload_ai-proxy_rollback_<sha>.json`; (b) copy that file out of `.claude/`; (c) rolling back = forward-deploy THAT file with the positional `false` and `--yes`. Forward deploy passes `false` explicitly too. Committed docs quote only the `--rollback <fn> <sha>` form (§6.14, scanned by `runbook_deploy_verify_jwt_test`).
4. **Verification.** Tool results are NOT logged (`tool-loop.ts:621-635` records name/status/args/latency), so `function_logs` cannot show the cues. Proof = (a) hash of the deployed `getFormCues.ts` vs git and the function version bump (§6.9/§6.10); (b) smoke with NO credentials expecting the function's own 401 (the smoke map accepts [400, 401] for ai-proxy); (c) a read-only live query before the deploy, `select name, is_active from exercise_library where name ilike 'Toes to Bar' and is_active = true`, shows the row the filtered query reads; (d) one coach question about a retired-only name (e.g. "Pigeon Pose") reading the model's reply, expecting no database cues.

## 5. Out of scope, recorded as findings (go to the next relevant plan; not new units here)

- No tie-break among several ACTIVE matches (stage 2 returns an arbitrary one). The diff makes this visible for ONE name:
  "Quad Stretch" (retired; alias of E216 Standing Quad Stretch) used to answer deterministically from the retired row,
  and now falls to stage 2 where two active rows (Standing Quad Stretch, Banded Quad Stretch) match with `limit(1)` and
  no ORDER BY. The other three retired names a live name contains (Lat Stretch, Prone Lat Pull, Piriformis Stretch) have
  one candidate each. Consequence of the founder's strict-filter decision; test C pins the one-candidate shape. `promote-community-item/index.ts:191-203` inserts `is_active: true` rows with no name dedupe and `exercise_library` has no UNIQUE on `name` (`002:6-38`), so two ACTIVE rows can also tie on an exact name.
- `ilike` with user text does not escape `%` and `_`.
- The tool does not read `name_aliases`, so the roughly 14 retired names that resolve in the Hive client answer `found: false` on the server.
- `workout_log_sets` was not counted for retired-exercise references.
