---
bug_id: 9c4b1e
date: 2026-11-13
batch: oi469-formcues-active
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-438 and OI-469 (the same defect, filed 2026-10-26 and 2026-11-05): the coach tool `getFormCues` read
  `exercise_library` by name with no `is_active` filter on either stage, so a retired row (`is_active = false`) could
  answer. Four names exist as BOTH an active and a retired row on the live project (Ankle Circles, Seated Piriformis
  Stretch, Sissy Squat, Toes to Bar), so the exact stage could return the retired copy (`limit(1)` with no ORDER BY: the
  planner chose). A retired-only name (56 of the 64 retired rows have no live row whose name equals or contains theirs)
  answered with the retired row's own cues. The app is not live; the visible damage today is small because the seed
  copied the kept twin's cues onto the four retired twins, so the cues are identical; `instructions`,
  `primary_muscles`, `difficulty_level` and `logging_type` can differ.
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
contract_test_path: supabase/functions/_shared/tools/__tests__/getFormCues_test.ts
related_bugs: [c2a7f1, c3e8f1, c1d7a4, b7d3e1, f2c7a9]
recurrence: |
  A recurrence of the soft-delete-flag writer / reader drift class (CLAUDE.md section 4.1, the default suspect): a
  WRITER introduced `is_active = false` rows (Batch A merges, C2a / C2b removals, migrations 164, 167, 171, 174-176) and
  one READER never learned to skip them. c2a7f1 (C2a) is the writer batch and noted the gap (it made a retired row that
  shares a name with a kept row copy the kept row's cues "because getFormCues has no is_active filter") and filed OI-438;
  c3e8f1 (S1b-3) hit it again with E053 and recorded it in its B-pass; the OI board carried it twice. No earlier fix of
  this reader exists; the known-good fix of the class is applied: the READER filters, and a test lists the retired row
  FIRST so a missing filter shows as the retired row's cues.
writers:
  - { file: supabase/migrations/171_reseed_exercise_library.sql, method_or_widget: "C2b: deactivates the removed rows, copying the kept twin's cues onto same-name pairs (E084, E111, E169, E179)", line: 1 }
  - { file: supabase/migrations/167_reseed_exercise_library.sql, method_or_widget: "C2a: sets is_active = false on its removed rows, never DELETE (workout_logs / template_exercises hold foreign keys)", line: 1 }
  - { file: scripts/seed_exercise_library.js, method_or_widget: "retireStatements and the removals emitter: UPDATE ... SET is_active = false (+ the kept row's cues on a same-name pair)", line: 261 }
readers:
  - { file: supabase/functions/_shared/tools/exercise/getFormCues.ts, method_or_widget: "stage 1 exact ilike (was unfiltered) and stage 2 partial ilike (was unfiltered), both now .eq is_active true", line: 67 }
  - { file: supabase/functions/_shared/tools/registry.ts, method_or_widget: "import of getFormCuesTool (and its ALL_TOOLS entry), bundled into ai-proxy only", line: 31 }
hive_key_prefix: "none: a server-side read of the cloud exercise_library; the Hive exerciseBox is untouched"
hive_key_formula: "not applicable"
sync_methods:
  - "none: exercise_library is bundle-seeded and written by migrations; no client sync reads or writes it"
restore_methods:
  - "none: the library is not user data"
cloud_table: exercise_library
cloud_columns:
  - is_active
ist_handling:
  - { file: supabase/functions/_shared/ist_date.ts, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: no client provider reads this tool's result except through the coach chat reply"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: the tool reads the shared exercise_library, which has no user scope; RLS is USING (true) and the service-role client reads it."
forbidden_patterns_checked:
  - { pattern: "a getFormCues exercise_library read without .eq is_active true", absent: true }
  - { pattern: "an ordering (.order is_active) used instead of the filter (the prefer-active design the founder rejected 2026-11-13)", absent: true }
  - { pattern: "a retired row deleted instead of hidden (the foreign keys from template_exercises and workout_logs forbid it)", absent: true }
proposed_fix: |
  Add `.eq("is_active", true)` after `.ilike(...)` and before `.limit(1)` on BOTH queries in getFormCues.ts. Design call
  put to the founder 2026-11-13 and answered "strict filter": the alternative (sort active first, let a retired-only name
  still answer) was rejected because both OIs say "add the filter", a row deactivated because its cues were bad (the
  rollbacks of migrations 164 and 174-176) must stop being served, and only about 14 of the 56 retired-only names resolve
  in the Hive client anyway (6 `alias_to` entries plus the 8 merges; 44 are "Sheet drop"), so users cannot reach the rest.
  Cost, accepted: those retired-only names answer `found: false` and the coach uses general knowledge. Rollback: revert
  the commit and redeploy `ai-proxy`; the data is untouched.
regression_test_planned: |
  supabase/functions/_shared/tools/__tests__/getFormCues_test.ts (6 tests: exact twin returns the active row; a
  retired-only name is not found; a retired exact name falls through to the live containing name; the partial stage skips
  a retired match listed first; no match is not found; both queries carry the filter), and a PRESENCE pin in
  test/contracts/exercise_library_cloud_seeded_test.dart (the comment-stripped reader holds `.eq("is_active", true)` at
  least twice; presence only, the Deno test is the behavioural protection).
impact_analysis: |
  Platform tier (`_shared/**`), one reader in one Edge Function bundle (`ai-proxy`). Live behaviour change after the
  deploy: the four same-name pairs answer from the active row (cues identical today), the 56 retired-only names answer
  `found: false`. No schema change, no data change, no client change. Needs the founder's go to deploy `ai-proxy`.
touched_layers_checked:
  - { layer: client_code, status: not_applicable, evidence: "no lib/ file reads exercise_library through Supabase (grep 2026-11-13); the Hive client already skips retired rows (seed prune)" }
  - { layer: postgres_schema, status: verified, evidence: "exercise_library.is_active is bool DEFAULT true (002_create_fitness_tables.sql:30; backups/live_schema_columns.json); foreign keys template_exercises_exercise_id_fkey and workout_logs_exercise_id_fkey to exercise_library(id) read live from pg_constraint 2026-11-13" }
  - { layer: postgres_data, status: verified, evidence: "live read-only 2026-11-13: 934 rows = 870 active + 64 inactive, 0 NULL is_active; 4 same-name active/inactive pairs; 56 of 64 inactive rows have no live equal-or-containing name; 0 template_exercises, workout_logs and workout_log_exercises rows point at an inactive row" }
  - { layer: edge_function_code, status: fixed_in_this_batch, evidence: "getFormCues.ts both queries filter is_active; deno check of the file, the test, ai-proxy/index.ts and the whole supabase/functions tree clean; whole-tree deno test 1687 passed, 2 failed = future-prediction and re-engagement index_test.ts AddrInUse on :8000 (known VPS quirk, files untouched)" }
  - { layer: client_server_contract, status: verified, evidence: "ai-proxy is the only bundler of the tool (ai-proxy/index.ts:55,63 -> tool-loop.ts:58 -> registry.ts:31); the tool result shape (found / exercise_name / matched_via) is unchanged; found:false is already a handled outcome" }
---

## Root cause

Writer: Batch A, C2a and C2b (and migrations 164, 174-176) retire exercises by `is_active = false`, never DELETE, because
`template_exercises.exercise_id` and `workout_logs.exercise_id` are foreign keys to `exercise_library(id)`. Reader:
`getFormCues.ts` was written before any row was inactive and never filtered. Both stages used `.limit(1)` with no ORDER BY,
so with two matching rows the planner chose. The seed worked around it for same-name pairs by copying the kept row's
cues onto the retired row (`scripts/seed_exercise_library.js`, comment reworded in this batch), which is why the visible
damage was small.

## Measured (live, read-only, 2026-11-13, project dedsavbjuwgarrhphgnl)

- 934 rows: 870 active, 64 inactive, 0 NULL `is_active`.
- 4 names with both an active and an inactive row (E084 Ankle Circles, E111 Sissy Squat, E169 Seated Piriformis Stretch,
  E179 Toes to Bar; all `removed_in: c2b`).
- 56 of the 64 inactive rows have no active row whose name equals or contains theirs; 17 (inactive, active) name pairs
  where one name contains the other.
- No rows in `template_exercises`, `workout_logs` or `workout_log_exercises` point at an inactive row.

## Plan review

Two rounds on the plan (`docs/plans/2026-11-13-oi469-formcues-active.md`), both context-blind Sonnet reviewers, both
"not converged" on plan text only (no P0 or P1): round 1 found the retired-name behaviour change, an unobservable live
check (tool results are not logged), a rollback recipe that would have silently set `verify_jwt=true`, and stale registry
claims; round 2 found OI-438 as the same defect, the rollback-by-deactivation case, the exact `--rollback` recipe
(section 6.13) and a nullable-column note. Every finding was checked against the repo or live before use. The one design
call went to the founder (strict filter).

## Mutations (rule 21)

Each applied (the diff against a saved copy counted) and restored (`cmp` against the copy), on `getFormCues_test.ts`
(6 tests, all green on the fixed code):

- stage 1 `.eq` removed: 4 red (exact twin, retired-only, retired-exact-then-live, both-queries-filter); partial test green.
- stage 2 `.eq` removed: 4 red (retired-only, retired-exact-then-live, partial skips retired, both-queries-filter); exact twin green.
- both removed: 5 red (only "no match is not found" stays green).
- stage 1 `true` changed to `false`: 4 red.
- `.order("is_active", { ascending: false })` in place of `.eq` on both (the rejected prefer-active design): 3 red
  (retired-only, retired-exact-then-live, both-queries-filter), proving the tests encode the strict decision.
- `exercise_library_cloud_seeded_test.dart` presence pin: one `.eq` removed reddens exactly 1 test.

## Not fixed here (recorded as findings, none is a new unit)

No tie-break among several ACTIVE matches (stage 2 returns an arbitrary one; `promote-community-item` inserts
`is_active: true` rows with no name dedupe and `exercise_library` has no UNIQUE on `name`); `ilike` with user text does
not escape `%` and `_`; the tool does not read `name_aliases`, so the roughly 14 retired names that resolve in the Hive
client answer `found: false` on the server; `workout_log_sets` was not counted for retired-exercise references.

## Deploy (pending the founder's go; tier 6 evidence follows in a docs PR after the deploy)

`ai-proxy` only, from a throwaway clone with full history, rollback prepared first by the section 6.13 recipe
(`ai-proxy` is `verify_jwt=false`; a bare `--rollback` would set it to true). Proof after deploy: hash of the deployed
`getFormCues.ts` against git, smoke with no credentials expecting the function's own 401, one coach question about a
retired-only name. OI-438 and OI-469 close together after that.
