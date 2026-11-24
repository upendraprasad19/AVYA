# OI-507: getFormCues lookup follow-ups (rev 5: simplified after three review rounds; round 4 converged, its P2s applied)

Worktree/branch `oi507-formcues` from main `c8a19ef4`. Execution mode: inline (one worktree, one writer).
Tier L (Edge Function under `_shared`, deployed through `ai-proxy`). Blast radius `platform` (`_shared/**`).
Founder go to write the fix: 2026-11-23. The live `ai-proxy` deploy needs its OWN explicit go (CLAUDE.md section 4.3).
Review history: rounds 1-3 each found 3-4 P1s, nearly all in machinery added to stage 2 (whole-word regex, shortest-name ranking, `ambiguous`, `other_matches`, 200-row caps). Rev 4 REMOVES that machinery (the "remove the mechanism when rounds chase its symptoms" lesson): stage 2 keeps its original substring meaning and only gains determinism. Round 3 also showed a ranking by `is_foundational` is impossible (that column does not exist live, verified 2026-11-23).

## 0. The defects, writer and reader

Reader: `supabase/functions/_shared/tools/exercise/getFormCues.ts` (stage 1 exact `ilike`, stage 2 partial `ilike`, both `.limit(1)`).
Writers of what it reads: migrations/seed write `exercise_library` (incl. `name_aliases`, `is_active`); `promote-community-item/index.ts:191-204` inserts `is_active: true` rows with no name check; a user's own custom exercises live in `user_custom_exercises` / Hive `customBox`, NOT in `exercise_library`.
Prior fix of the same reader: diagnose `9c4b1e` (ai-proxy v104), which recorded these defects as "not fixed here". Cite it in `related_bugs:`; recurrence class = a reader that resolves a name without a deterministic, escaped, alias-aware rule.

1. Stage 2 has no tie-break (`squat` matches 68 active rows; `Quad Stretch` matches two).
2. `ilike` wildcards `%` `_` `\` are unescaped (`%` matches all 870 rows, answers `found: true`, labelled `exact`); PostgREST also treats `*` as `%`.
3. `name_aliases` is never read (14 rows, all active).
4. A name with no row (retired-only, or a user's own custom exercise) answers `found: false` with no instruction, so the reply depends on the model.
5. (Founder-added) a custom exercise whose name is a substring of a library name gets that row's cues with no sign it is a different exercise.
6. Sibling readers `getExerciseHistory.ts:62` and `getPRTimeline.ts:83` pass model text to `ilike` unescaped (own-data scope, `user_id` filtered).
7. The alias data itself: `Forward Lunge -> {Reverse Lunge}` (wrong movement) and `Bodyweight Standing Calf Raise -> {Donkey Calf Raise}` (questionable); see section 6.

## 1. Live evidence (read-only, project `dedsavbjuwgarrhphgnl`, 2026-11-23)

- `name_aliases` is `text[]`; 14 active rows carry a non-empty array. `exercise_library` has NO `is_foundational` column.
- `workout_log_sets.exercise_id` holds the exercise NAME. 10 sets name a retired-only exercise: `Donkey Calf Raise` x4 (covered by the alias on Bodyweight Standing Calf Raise) and `Negative Pull Up` x6 (no alias: stays `found: false`, intended, answered by the hint).
- `Reverse Lunge` is a retired row; no active row has it in its name; the true reverse lunges are `Barbell Rear Lunge` / `Dumbbell Rear Lunge`.

## 2. The change

New `supabase/functions/_shared/like_escape.ts`: `escapeLike(s)` removes every `*`, then escapes `\`, `%`, `_` (backslash first). Used by `getFormCues.ts`, `getExerciseHistory.ts:62`, `getPRTimeline.ts:83`. Verified-separate, listed in the diagnose: `future-prediction/index.ts:82` (`matchSubstring` is an internal literal) and `telegram-admin-bot/index.ts:375` (founder-ops bot, founder-typed input).

`getFormCues.ts`, every stage `is_active = true`, `name` = trimmed and `*`-stripped; empty after that = the existing `exercise_name is required` error:

1. **Stage 1 exact:** `.ilike("name", escapeLike(name)).eq("is_active", true).order("name").limit(1)`; `matched_via: "exact"`.
2. **Stage 1b alias:** `.eq("is_active", true).neq("name_aliases", "{}").order("name").limit(200)` (live: 14 rows; `neq` is valid PostgREST on `text[]` and excludes NULL); JS handles `name_aliases ?? []`, compares `alias.trim().toLowerCase() === name.toLowerCase()`, first by name order. FAIL OPEN: a query error or `rows.length === 200` on this stage is logged with `console.error` and the lookup continues to stage 2 (it must not break every exact-miss query, which succeed through stage 2 today). `matched_via: "alias"`. Not length-gated. Stage names below are "stage 1 / 1b / 2"; the list numbers are items.
3. **Stage 2 partial, original meaning kept:** only when the trimmed, `*`-stripped name has >= 3 characters; `.ilike("name", `%${escapeLike(name)}%`).eq("is_active", true).order("name").limit(1)`. Deterministic (alphabetical among matches), not smarter. `matched_via: "partial"`. NO whole-word rule, NO shortest-name rule, NO `ambiguous`, NO `other_matches`.
4. **Not found:** `{ found: false, exercise_name, hint }`; `hint` (constant) says: no saved cues exist for this exercise (it may be the user's own custom exercise); give 2-4 brief cues and 1-2 common mistakes from general knowledge, in the same short style as the library; say in one short line that these are general cues, not the app's saved ones; do not invent app data.
5. **Tool description gains one sentence:** when `matched_via` is `partial` or `alias`, tell the user which exercise's cues you are giving (`exercise_name` is returned). This is the whole mitigation for defect 5; the residual (a custom name that is a substring of a library name) is accepted and recorded.

Result type: `matched_via: "exact" | "alias" | "partial"`, optional `hint`. Old fields kept; no consumer pins the two-value union (round 2 sweep: only `getFormCues.ts`, its test, `derive_only_tool_surface_test.dart:58`, `captain_manual.ts:406`).

Accepted regressions, recorded in the diagnose: `_` or `*` typed as a wildcard no longer works, and `*` is stripped (a user's custom `Squat*` no longer matches itself in the sibling history readers; the library has no names with `%`, `_`, `*` or `\`); a 1-2 character query no longer partial-matches (it falls to the hint); `Pull-Up` vs `Pull Up` spelling variants do not normalise; stage 2 picks the alphabetically first match (for example "Bench Press" with no exact row picks `Band Bench Press`), which is deterministic where it was arbitrary, not "best".

Unchanged on purpose: no `user_custom_exercises` read (user-scoping risk; the snapshot already carries `custom_exercises`; the hint covers the miss); `captain_manual.ts` untouched.

## 3. Tests (rule 21)

fake_sb (NOT edited) supports `eq neq ilike order limit`, records filters (not `.order`), `neq` is `v !== val`, `ilike` regex-escapes `\` and has no `_` wildcard. A test-local wrapper (pattern `withMaybeSingle`, `getFormCues_test.ts:16`) calls the base `.neq` (so T8 still sees the recorded filter) and post-filters rows in `.then`, so the alias stage sees only aliased rows.

getFormCues (`getFormCues_test.ts`; the existing "both queries carry the is_active filter" test is rewritten to assert every `exercise_library` read carries the filter, 3 reads on the partial path):
- T1 alias beats partial: `Banded Quad Stretch` listed before `Standing Quad Stretch` (alias `Quad Stretch`); query "Quad Stretch" returns Standing, `matched_via: "alias"`.
- T2 partial determinism: `Goblet Squat`, `Squat Jump`, `Front Squat` listed worst-first, query `squat` with no exact row: alphabetical first wins (`Front Squat`), `matched_via: "partial"`.
- T3 escaping, 3+ character queries so stage 2 runs: `50%`, `a_b`, `x\y` and `a*bc`: the recorded stage-1 value holds `50\%` / `a\_b` / `x\\y` / `abc`, the recorded stage-2 value is `%…%` with the same escapes; a 3-character `a*b` (becomes `ab`, 2 characters) is a stage-1-only case with no partial read; a 1-character `%` query returns `found: false` with no partial read; a query of only `*` returns the required-name error.
- T4 alias: `Donkey Calf Raise` returns Bodyweight Standing Calf Raise, case-insensitive; a retired aliased row is skipped; `null` / `[]` `name_aliases` tolerated; an alias with stray spaces matches; a padded query `"  Donkey Calf Raise "` (exact miss, alias hit after the name trim) matches; a whitespace-only query returns the required-name error; 200 aliased rows and an alias-read error are logged and the lookup still reaches stage 2 (fail open, asserted via a recorded third read).
- T5 length guard: a 2-character query reaches no partial read (recorded calls = exact + alias only).
- T6 hint: not-found carries `hint` containing "general" and "same short style"; found results carry no `hint`.
- T7 ordering, behavioural per stage: exact = `Row` / `ROW` listed in the wrong order (pins fake_sb's code-unit order, not Postgres collation; labelled so); alias = two active rows sharing one alias, listed in the wrong order; partial = T2.
- T8 alias read shape: the recorded alias read carries `["neq","name_aliases","{}"]` and `["eq","is_active",true]`.
`getExerciseHistory_test.ts` and `getPRTimeline_test.ts` (exist, use `fakeSb`): one test each that the recorded `ilike` value for `%` is `\%`.
Dart pin `test/contracts/exercise_library_cloud_seeded_test.dart`: raise `>=2` to `>=3` and repoint the stale `getFormCues.ts:67,95` citation; no helper wraps the literal `.eq("is_active", true)`.

Mutations (apply confirmed with `grep -c`, restore with `cmp`, counts in the diagnose): drop `escapeLike` on stage 1, on stage 2, on each sibling (T3 / sibling red); drop the `*` strip (T3 red); drop the alias stage (T1/T4 red); stage order alias-after-partial (T1 red); drop `.order` on exact / alias / partial (T7 / T7 / T2 red); drop `.neq(name_aliases)` (T8 red); drop `.trim()` on aliases or on the name (T4 red); case-sensitive alias compare (T4 red); drop the length guard (T5 red); delete `hint` (T6 red); drop `is_active` on the alias read (T4/T8 red); remove the 200-row guard or the error catch (T4 red); drop the description sentence (a presence pin on the description text).

## 4. Gates and process

- `deno check --node-modules-dir=none` on `getFormCues.ts`, `getExerciseHistory.ts`, `getPRTimeline.ts`, `like_escape.ts`, `ai-proxy/index.ts`; `deno test` the touched tests; whole-tree `deno test` once (known `:8000` AddrInUse quirk on two index tests).
- Before implementing: one read-only live REST check that `neq name_aliases {}` returns exactly the 14 rows.
- Diagnose (full template, `tier: l_fix`, `related_bugs: [9c4b1e]`, recurrence stated, the 14-row alias review, siblings listed, accepted regressions); SoT registry `exercise_library_schema` (`docs/sot_registry.yaml` ~13140): update reader lines, fix the "both stages" comment, add `behavioral_test_path`; say how 9c4b1e's "no reader of `name_aliases`" was re-verified.
- Closure ledger `docs/audit/oi507-formcues.closure.yaml` (Gate 40) and trailers `closes-diagnose:`, `closes-oi: OI-507`: the lunge/donkey alias data (defect 7) lands in unit B FIRST (section 6), so at this unit's merge defects 1-4, 6 and the alias half of 7 are `closed_in_commit`; defect 5 is an accepted residual recorded as `verified_clean` with its evidence (the description sentence and the hint); the donkey alias takes the state unit B's founder decision gives it (`closed_in_commit` if removed or repointed, `verified_clean` with the founder's keep decision if kept). No entry is `upstream_blocked` for work we own.
- Pre-deploy (`supabase/functions/CLAUDE.md`): `git fetch origin main` then `git diff --name-only HEAD...origin/main -- supabase/functions`; non-empty and touching `ai-proxy` or an imported `_shared` file means merge `origin/main`, `deno check`, then deploy.
- Plan-review record `docs/plan-reviews/oi507-formcues.md`, B-pass, `land_pr.sh`. Deploy `ai-proxy` only on the founder's separate explicit go; rollback by the edge-function-deploy-rollback skill's recipe prepared BEFORE the deploy. Post-deploy smoke (B-pass 2026-11-24): `getFormCues` for "Quad Stretch" must answer `matched_via: "alias"` (a `partial` answer means the fail-open alias stage is dead).

## 5. Out of scope (recorded)

`user_custom_exercises` lookup; any `captain_manual.ts` or client change; `future-prediction` and `telegram-admin-bot`.

## 6. Unit B: the alias data (DECIDED 2026-11-23, founder: fix the data)

Founder answer: remove the `Forward Lunge -> {Reverse Lunge}` alias so "Reverse Lunge" answers `found: false` (coach uses general knowledge). The second questionable alias `Bodyweight Standing Calf Raise -> {Donkey Calf Raise}` (a donkey calf raise is bent-over; 4 logged sets resolve through it) is put to the founder at the START of unit B and decided there; this unit does not decide it.

Size: the alias is a recorded library decision (`scripts/library_batch_c2_removals_gen.js:50` E144 `{to: 'G3470', alias: true}`; `scripts/data/library_batch_c2_removals.json:145-154`), pinned by contract tests (at least `library_batch_c2_removals_file_test.dart`, `exercise_library_merge_contract_test.dart`, `library_batch_c2_name_readers_test.dart`, `exercise_alias_lookup_behavioral_test.dart`, `library_batch_c_rows_contract_test.dart:46-52` `_aliasTargets`, `exercise_library_cloud_tuples_match_test.dart`) and bundled in `assets/data/exercise_library.json:32920`. Recipe: change `REPLACEMENT.E144.alias` in the generator, regenerate the removals file, re-run the importer (`scripts/add_library_batch_c_v15.js:297-302` derives `name_aliases` from `alias_to`; a bare JSON edit would drift), bump `_exerciseLibraryVersion` 27 -> 28 (`lib/core/services/seed_service.dart:189`, plus its doc-comment line) with a v28 upgrade behavioural test (pattern `library_seed_v24_upgrade_behavioral_test.dart`), mint the migration with `sh scripts/mint_migration.sh <slug>` (UPSERT of all 870 rows, `Destructive?: yes`, inline rollback restoring the alias), update `backups/applied_migrations.json`, SoT `behavioral_test_path_v28`. Own branch `oi507-lunge-alias`, own plan and review rounds, own live-apply go. Client effect (tester-only, app not live): the Hive name "Reverse Lunge" in an old template/log stops resolving to Forward Lunge (`exercise_repository.dart:45`).

BINDING ORDER (merge order, not only deploy order): unit B merges and its migration is applied live FIRST; only then does this unit (A) merge to main, and only then is the `ai-proxy` deploy go requested. Merging A earlier would arm the alias stage for any later `ai-proxy` deploy.
