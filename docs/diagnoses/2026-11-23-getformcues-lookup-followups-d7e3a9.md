---
bug_id: d7e3a9
date: 2026-11-23
batch: oi507-formcues
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  OI-507 (found while fixing 9c4b1e): the coach tool `getFormCues` resolves an exercise name to a row with three open ends.
  (1) Stage 2 (partial) had `.limit(1)` and no ORDER BY, so a name matching several live rows returned an arbitrary one
  ("squat" matches 68 of 870 active rows; "Quad Stretch" matches Standing and Banded). (2) Both `ilike` stages passed the
  model-supplied name unescaped: `%` matched all 870 rows and answered `found: true` (stage 1 labelled it `exact`), `_`
  matched any one character, and PostgREST reads `*` as `%`. (3) `name_aliases` was never read, so a name the Hive client
  resolves through an alias answered `found: false` on the server. (4) A name with no row (a retired-only name, or a
  user's own custom exercise, which lives in `user_custom_exercises` and not in `exercise_library`) answered a bare
  `found: false` with no instruction, so the reply depended on the model. The two history readers `getExerciseHistory.ts`
  and `getPRTimeline.ts` had the same unescaped `ilike` on model text (own-data scope).
concept: exercise_library_schema
sot_registry_entry: exercise_library_schema
contract_test_path: supabase/functions/_shared/tools/__tests__/getFormCues_test.ts
related_bugs: [9c4b1e]
recurrence: |
  A recurrence of the reader-resolves-a-name-without-a-deterministic-rule class that 9c4b1e left open: that fix added the
  `is_active` filter and RECORDED (its "Not fixed here" section) the missing tie-break, the unescaped `ilike`, the unread
  `name_aliases` and the uncounted `workout_log_sets` references; OI-507 is exactly those four items. No earlier fix of
  these four exists (INDEX grep for getFormCues / name_aliases / ilike: only 9c4b1e and the library batches, which write
  `name_aliases`). 9c4b1e's statement that nothing under `supabase/functions` reads `name_aliases` was re-verified by
  `grep -rn name_aliases supabase/functions` before the change (no reader); the alias stage is the first.
writers:
  - { file: scripts/library_batch_c2_removals_gen.js, method_or_widget: "REPLACEMENT table: an `alias: true` removal (E144) becomes a name_aliases entry on its replacement via the importer", line: 50 }
  - { file: scripts/add_library_batch_c_v15.js, method_or_widget: "appends each removal's alias_to name to its target row's name_aliases", line: 297 }
  - { file: supabase/functions/promote-community-item/index.ts, method_or_widget: "INSERTs exercise_library rows with is_active true and no name check, so an active same-name pair can appear", line: 191 }
readers:
  - { file: supabase/functions/_shared/tools/exercise/getFormCues.ts, method_or_widget: "exact, alias and partial stages, each is_active-filtered, name-ordered, LIKE-escaped; not-found hint", line: 60 }
  - { file: supabase/functions/_shared/tools/progress/getExerciseHistory.ts, method_or_widget: "ilike on exercise_id now through escapeLike", line: 63 }
  - { file: supabase/functions/_shared/tools/progress/getPRTimeline.ts, method_or_widget: "ilike on exercise_id now through escapeLike", line: 84 }
hive_key_prefix: "none: a server-side read of the cloud exercise_library and the caller's own workout_log_exercises; Hive is untouched"
hive_key_formula: "not applicable"
sync_methods:
  - "none: exercise_library is bundle-seeded and written by migrations; no client sync reads or writes it through this path"
restore_methods:
  - "none: the library is not user data"
cloud_table: exercise_library
cloud_columns:
  - name
  - name_aliases
  - is_active
ist_handling:
  - { file: supabase/functions/_shared/ist_date.ts, method_or_widget: "no date key or counter reset is touched by this change", line: 1 }
provider_invalidations:
  - "none: the only client-visible effect is the coach's reply text"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: exercise_library is shared (RLS USING true, service-role client); the two history readers keep their user_id filter, so an escaped wildcard can only reach the caller's own rows."
forbidden_patterns_checked:
  - { pattern: "a getFormCues exercise_library read without .eq is_active true", absent: true }
  - { pattern: "an .order on is_active (the prefer-active design 9c4b1e's founder call rejected)", absent: true }
  - { pattern: "a model-supplied name passed to .ilike without escapeLike in a coach tool", absent: true }
  - { pattern: "a read of user_custom_exercises inside getFormCues (user-scoping risk, out of scope)", absent: true }
proposed_fix: |
  New `_shared/like_escape.ts` `escapeLike` (removes `*`; escapes backslash FIRST, then `%` and `_`), used on both ilike stages
  of getFormCues and on the two history readers. getFormCues: every stage orders by name; a new alias stage (exact miss,
  before partial) matches the name against `name_aliases` of ACTIVE rows in JS (case-insensitive, trimmed; the read is
  `.neq("name_aliases","{}")`, capped at 200 rows, and FAILS OPEN: a read error or a capped read is logged and the lookup
  goes on to stage 2); the partial stage keeps its substring meaning, runs only for names of 3+ characters, and is only made
  deterministic; a not-found result carries a constant `hint` telling the model to give 2-4 brief general cues in the library's
  style and say they are general; the tool description tells the model to name the matched exercise on a partial or alias match.
  Rejected after three plan-review rounds: whole-word matching, shortest-name ranking, an `ambiguous` flag, `other_matches`
  and a 200-row stage-2 fetch (each spawned P1s in the next round; the plan removed them rather than patching), and a ranking
  by `is_foundational` (that column does not exist live).
regression_test_planned: |
  getFormCues_test.ts (T1-T9, plus the six 9c4b1e tests with the 2-read count raised to 3), like_escape_test.ts (3), one test each
  in getExerciseHistory_test.ts and getPRTimeline_test.ts, and the Dart PRESENCE pin in
  test/contracts/exercise_library_cloud_seeded_test.dart raised from 2 to 3 reads and 3 filters.
impact_analysis: |
  Platform tier (`_shared/**`); the tool and both history readers ship in the `ai-proxy` bundle. Live behaviour after the deploy:
  "Quad Stretch" and other alias names resolve through the alias row; `%` and `_` stop matching everything; a name with no row
  carries a hint so the coach answers from general knowledge in the library's style; the partial pick is alphabetical-first.
  Accepted regressions: a 1-2 character query no longer partial-matches; `_` or `*` typed as a wildcard no longer works and `*`
  is stripped (a custom exercise named `Squat*` no longer matches itself in the history readers; the library has no names with
  `%`, `_`, `*` or backslash); "Pull-Up" and "Pull Up" do not normalise; with no exact row the partial pick is the alphabetically
  first match ("Bench Press" picks "Band Bench Press"), deterministic where it was arbitrary, not "best"; a custom exercise whose
  name is a substring of a library name still gets that row's cues (mitigated only by the description sentence that makes the
  coach name the exercise). No schema change, no data change, no client change. Needs the founder's go to deploy `ai-proxy`, and
  ONLY after unit B (the alias data fix, below) is applied live.
alias_audit: |
  The 14 aliased rows (live, read-only 2026-11-23, all active): Chest Dip, Overhead Tricep Cable Extension, Hip Abduction
  Machine, V-Up, Standing Quad Stretch, Cross-body Shoulder Stretch, Chest Doorway Stretch, Ankle Circles, Bodyweight Standing
  Calf Raise, Forward Lunge, Close Grip Bench Press, Standing Lateral Stretch, Seated Piriformis Stretch, Wrist Circles. Spelling
  and hyphen variants are fine. TWO are wrong-movement risks the alias stage would activate: `Forward Lunge -> {Reverse Lunge}`
  (the retired Reverse Lunge was merged by Batch C2a, E144; the true reverse lunges are Barbell/Dumbbell Rear Lunge) and
  `Bodyweight Standing Calf Raise -> {Donkey Calf Raise}` (Library Batch S1b-3 merged E053; a donkey calf raise is bent-over).
  Both are RECORDED library decisions pinned by contract tests, so changing them is a library re-seed (v28): unit B, own branch,
  merged and applied live BEFORE this unit merges or deploys. The founder decided 2026-11-23: remove the lunge alias; the
  donkey alias is put to the founder at the start of unit B.
touched_layers_checked:
  - { layer: client_code, status: not_applicable, evidence: "no lib/ file reads exercise_library through Supabase; the Hive client's own alias fallback (exercise_repository.dart:45) is unchanged by this unit" }
  - { layer: postgres_schema, status: verified, evidence: "live 2026-11-23: exercise_library.name_aliases is text[]; there is NO is_foundational column (a round-3 review's suggested ranking column); is_active bool" }
  - { layer: postgres_data, status: verified, evidence: "live read-only 2026-11-23: 14 active rows carry a non-empty name_aliases, 0 inactive; workout_log_sets.exercise_id holds names: 10 sets name a retired-only exercise (Donkey Calf Raise x4, aliased; Negative Pull Up x6, no alias, answered by the hint); Reverse Lunge is a retired row" }
  - { layer: edge_function_code, status: fixed_in_this_batch, evidence: "getFormCues.ts, getExerciseHistory.ts, getPRTimeline.ts, like_escape.ts; deno check clean on them and ai-proxy/index.ts; whole supabase/functions deno test 1789 passed, 2 failed = future-prediction and re-engagement index_test.ts AddrInUse :8000 (known VPS quirk, files untouched). NOT yet deployed: needs the founder's separate go, after unit B" }
  - { layer: client_server_contract, status: verified, evidence: "ai-proxy is the only bundler of the tools; the tool result is a superset (matched_via gains alias, hint added, all old fields kept); no consumer pins the two-value matched_via union (derive_only_tool_surface_test.dart:58, captain_manual.ts:406 only route to the tool)" }
---

## Root cause

Writer: the library writers (migrations and `scripts/seed_exercise_library.js`, Batches A, C2a, C2b, S1b-3) put names in
`exercise_library.name` and `name_aliases`, and `promote-community-item` inserts rows with no name check; a user's own
exercises are never in that table. Reader: `getFormCues.ts` resolved a name with two bare `ilike` stages and `limit(1)`:
no ORDER BY (arbitrary among several matches), no escaping (wildcards and PostgREST's `*` alias match everything), no read
of `name_aliases`, and no instruction for a miss. The two history readers copied the unescaped `ilike`.

## Plan review

Four rounds (`docs/plan-reviews/oi507-formcues.md`), all context-blind Sonnet reviewers, every finding checked against the repo or
live first. Rounds 1-3 each found 3-4 P1s, nearly all in machinery added to stage 2; per the remove-the-mechanism lesson the plan
deleted it (rev 4) and round 4 converged. One design call went to the founder (the alias data fix, unit B).

## Mutations (rule 21)

(Counts filled from the run; every mutation confirmed applied by a changed file and restored by `cmp`.) 24 mutations over
getFormCues.ts, like_escape.ts, getPRTimeline.ts and getExerciseHistory.ts; first run left 4 survivors (exact `.order` removed:
fixture listed the rows already in order; the 200-row guard removed: the fixture gave the same answer; the alias-error catch
removed: only a log line differs; `*` strip removed inside the helper: the handler strips first), each closed by a fixture
change, a console.error capture, or the direct `like_escape_test.ts`. Second run: all 24 red (1-5 tests each). Equivalent
mutants: none left standing. The Dart PRESENCE pin is mutated separately (one `.eq("is_active", true)` removed).
