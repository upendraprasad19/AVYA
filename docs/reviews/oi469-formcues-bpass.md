---
reviewed_at: 2026-11-14T08:50:00+05:30
staged_against: oi469-formcues-active 2b5e3dea (code commit 291ccba1, skill-doc commit 2b5e3dea), diff origin/main...HEAD (9 files), CI green on 291ccba1
blast_radius: platform
reviewer: one fresh context-blind Sonnet seat (adversarial B-pass)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — getFormCues skips retired exercise rows (`oi469-formcues-active`, OI-438 / OI-469)

One fresh, context-blind Sonnet seat reviewed `git diff origin/main...HEAD` at `2b5e3dea` with an exhaustive command
list (read-only git, file reads, `grep`/`sed`/`cmp`/`sha256sum`, the one named Deno test file, `deno check` on one
file; no `dart run`, no scripts, no network, no database statement) and the recorded decisions quoted in the brief (the
founder's strict-filter choice; the out-of-scope list). It was allowed to mutate exactly one file
(`getFormCues.ts`) under a backup / `cmp` / `sha256` protocol: nine mutations, file byte-identical afterwards (sha256
`c51a6aae...ddecb9`, checked by the author too). Result: **no P0, P1 or P2; four P3, all documentation.** The code and
the test do what the plan says, and every documented mutation count reproduced (4, 4, 5, 4, 3).

## Finding 1 — P3 — missing_input / asserted_fixture_value
- **file:line:** `docs/diagnoses/2026-11-13-getformcues-inactive-rows-9c4b1e.md` `recurrence:` (echoed in the plan section 0)
- **claim:** it said c2a7f1 "noted the gap ... and filed OI-438". c2a7f1 never mentions getFormCues, OI-438 or OI-469; OI-438 was filed by Batch C1 (c1d7a4, tier-6 evidence), and the quoted sentence is the C2 plan's R12 (`docs/plans/2026-10-25-library-batch-c2-removals.md:129`).
- **verification:** `grep -c -i "getFormCues\|OI-438" docs/diagnoses/2026-11-04-library-batch-c2a-removals-c2a7f1.md` returned 0 (author re-ran it).
- **status:** accepted, fixed (provenance reworded: c1d7a4 filed OI-438, C2 plan R12 carries the sentence, c2a7f1 is only the writer batch).

## Finding 2 — P3 — guard_without_its_mirror
- **file:line:** diagnose `impact_analysis:`; plan sections 0 and 5
- **claim:** the impact statement named two outcome classes (4 same-name pairs, 56 retired-only) and missed a third: 4 retired names that one live name contains (Lat Stretch, Prone Lat Pull, Piriformis Stretch, Quad Stretch) now fall through to stage 2. Three have one candidate. "Quad Stretch" has two (Standing Quad Stretch, Banded Quad Stretch) and stage 2 has no tie-break, so its answer is now arbitrary where it used to be deterministic. Not a reversal of the strict-filter decision; the record must say it.
- **verification:** the author listed the library names containing "quad stretch" from `assets/data/exercise_library.json` (two rows); the reviewer's shell loop over the removals file and the 14 aliases reproduced 4 + 4 = 8 of 64.
- **status:** accepted, fixed (third class written into `impact_analysis` and plan section 5, with the Quad Stretch consequence).

## Finding 3 — P3 — writer_reader_drift (inserted-lines sub-check)
- **claim:** this diff moved lines in `getFormCues.ts` (+4, +3 before stage 1), `seed_exercise_library.js` (+2) and `exercise_library_cloud_seeded_test.dart`. No live registry range is stale (the registry's `(:60-61)` is the `COLUMNS` constant and still right; the Dart header cite was re-pointed to `:67,95`). One ungated stale cite: OI-187 (`docs/audit/open_issues.md`) cited `getFormCues.ts:74-86, :101-113`, off by 1-2 already on main and now off by more.
- **verification:** `grep -n "getFormCues.ts:74-86" docs/audit/open_issues.md`; a repo-wide grep for "no is_active filter" finds only historical diagnoses, reviews, plans and the migration-162 ledger note.
- **status:** accepted, fixed for OI-187 (re-pointed to "the exact and the partial return blocks"); the other hits are dated historical records (a plan, a prior review, the merged #258 plan) and are left as written.

## Finding 4 — P3 — documentation tense and overclaims
- (a) comments and the registry said "now skips retired rows" while production still runs the old reader until the `ai-proxy` deploy. **accepted, fixed** in the registry `semantic:` ("in code; live after the ai-proxy deploy"); the OIs already say it.
- (b) rollback overclaim: only migration 164's rollback deactivates rows; 175 reactivates E053; 174 and 176 change `suitable_for` and `movement_pattern`. **accepted, fixed** in the diagnose and the plan.
- (c) wrong cite: `verify_jwt` disabled is at `ai-proxy/index.ts:28-30`, not `:26-27`. **accepted, fixed** in plan section 4.
- (d) "Migration 167 ... 7 statements" was ambiguous (it deactivates the 50 removed rows plus 7 Batch A repeats). **accepted, fixed** in the plan.

## What came back clean (the seat's own account, spot-checked by the author)
- Lens 2, 4, 5: no `catch` in the reader or the test, both `exactErr` / `partialErr` still throw; no credential-shaped literal (one `deno.land/std@0.224.0` import, the version 25 sibling tests use); every promise in the test is awaited.
- Lens 3: `docs/blast_radius.yaml:106` (`supabase/functions/_shared/**`, platform) first-matches `getFormCues.ts`; trailers and the diagnose agree.
- Lens 6, nine mutations (each applied, confirmed with `diff`, restored with `cp`, `cmp` identical): stage 1 `.eq` removed 4 red (A, B, C, F); stage 2 removed 4 red (B, C, D, F); both removed 5 red; string `"true"` 4 red; `.neq("is_active", false)` 1 red (F); `.eq` after `.limit(1)` 0 red; stage 2 column typo 3 red; stage 1 `true`->`false` 4 red; `.order(...)` in place of `.eq` (the rejected design) 3 red. The two survivors are equivalent mutants (PostgREST filters are order-independent; `neq false` has the same effect as `eq true` and drops NULL the same way), recorded in the diagnose. No test passes for the wrong reason: every behavioural case is red under at least one single-stage mutation.
- Lens 7, 8: every cited path, line and number the seat could reach from the repo held (E084/E111/E169/E179 and their replacements, 56 `remove` + 10 `keep`, 6 `alias_to`, 44 "Sheet drop", 870 bundled rows, 14 `name_aliases`). Not reproducible from the repo, and not marked wrong for that: the live database counts (934 / 870 / 64 / 0 NULL / 17 / 0 referencing rows), taken read-only by the author on 2026-11-13, and the whole-tree Deno result.

## Founder triage notes
Four P3, none needing a code change; all four fixed in the follow-up commit on this branch. The strict-filter decision (founder, 2026-11-13) is untouched. No finding re-opens a recorded decision. Equivalent survivors M5 and M6 are not tests to add.

## Tuning entry
- **2026-11-14** - blast-radius platform - 4 findings; 0 false_alarm; tuning: none (every finding was a doc fact the author could re-run in one command; finding 1, a provenance claim copied from a plan into a diagnose without opening the cited doc, is the instance to watch: when a diagnose cites "batch X noted Y", grep batch X's own doc for Y).
