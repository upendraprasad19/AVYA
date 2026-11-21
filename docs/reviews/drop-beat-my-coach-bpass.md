---
reviewed_at: 2026-10-25T13:00:00+05:30
staged_against: 73d569c0
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 19
verdict: accepted
---

# Code Review (B-pass) - branch drop-beat-my-coach (OI-395, T3 of the exercise-library programme)

Reviewed: the Group A commit (`3dddb4e1`, rebased as `73d569c0` after finding 1), `git diff origin/main...HEAD`: the Edge Function source, the dead widget, two constants, the never-unlockable `challengeWon` badge, their registry/test/doc entries, the new contract test `test/contracts/beat_my_coach_removed_test.dart`, the closure ledger, the plan and the delete recipe in the deploy skill. Four fresh, read-only Sonnet reviewers on four lens slices (A: remnants and blast radius; B: the two tests' mirror cases and fixtures; C: documents, registries and the rollback recipe; D: secrets, the shared Edge Function comment edits and the Dart behaviour), each with an exhaustive command list that banned every `scripts/*` gate, the network, MCP tools and the database. All four complied; the harness refused their `findings.md` writes, so each returned its report as text.

Severity count: P0 0 . P1 1 . P2 4 . P3 13 . 1 informational. No false alarms: every finding was confirmed by the author by reading the file or running the command it names (finding 1 by `git rev-list --left-right --count HEAD...origin/main` = `1 7`, `git ls-tree origin/main docs/audit/OPEN_INDEX.md` = empty, `git check-ignore -v` = `.gitignore:212`). Live-state sentences (function version, row counts, log sweeps) were unverifiable by design and were judged only for internal consistency.

Fixes landed in the commit that carries this file; the plan's "B-pass disposition" table lists them, the ledger row `BPASS` records the evidence.

## Findings

## Finding 1 - P1 - blast_radius_mismatch / writer_reader_drift (reviewers A and C, independently)

- **file:line:** `docs/audit/OPEN_INDEX.md` (OI-395 row); plan unit 10, the Group B and Verification paragraphs; ledger U10B.
- **claim:** the branch was cut from `c0565234` and was 7 commits behind `origin/main`. Landing A2 (`c43abca3`) made `docs/audit/OPEN_INDEX.md` and `docs/diagnoses/INDEX.md` gitignored local build products and added `check_local_indexes_untracked.dart`, which fails if either is tracked. The branch edited the tracked file: a certain modify/delete conflict, invisible to a three-dot diff, and the plan's Group B told the author to regenerate and commit that file.
- **verification:** `git rev-list --left-right --count HEAD...origin/main` = `1 7`; `git ls-tree origin/main docs/audit/OPEN_INDEX.md docs/diagnoses/INDEX.md | wc -l` = 0; `git check-ignore -v docs/audit/OPEN_INDEX.md`.
- **status:** accepted - fixed. The Group A commit was local and unpushed, so it was REBASED onto `origin/main` `b0735bb1` (not merged: a conflicted merge runs the gates written for authoring commits, `feedback_gates_unsatisfiable_at_merge.md`). The one conflict was resolved by dropping this branch's edit to the index; `open_issues.md`, `blast_radius.yaml` and `sot_registry.yaml` auto-merged with disjoint hunks. Plan unit 10, Group B, Verification and ledger U10B no longer commit or regenerate the index (`build_local_indexes.dart --lenient` only to read it). Verification now uses the whole-project `flutter analyze --no-fatal-infos` per section 4.12.8 as amended by main. The dispatch protocol in `.claude/skills/code-review/SKILL.md` gains step 0b (see the tuning entry).

## Finding 2 - P2 - guard_without_its_mirror (reviewer B)

- **file:line:** `test/contracts/beat_my_coach_removed_test.dart:45-47` (`_stripComments`), positive control `:75-83`.
- **claim:** the stripper `//[^\n]*` also deletes everything after `://`, so a removed name placed after a URL on the same line (`"https://x.supabase.co/functions/v1/beat-my-coach"`) is invisible to the absence scan, and a `/*` inside a string (a glob) could swallow the code up to the next `*/`. The control tested only "flags code, ignores comment", the side the code was written for. Reviewer B built both counter-examples in node and found a real file with the shape (`postgrest_fake_fetch.ts:124`); 62 test files already use `(?<!:)//`.
- **verification:** `git grep -l -F '(?<!:)//' -- test | wc -l` = 62; `sed -n 124p supabase/functions/_shared/postgrest_fake_fetch.ts`.
- **status:** accepted - fixed: URL-safe line stripper `(?<!:)//`, block opener not preceded by a word character, quote, backtick, `/` or `*` (fails closed on a comment glued to a word); the positive control gained a token after a URL, after a glob string, in a comment after a URL (still stripped), in other casings and as `challenge_card`. Mutations M10, M11 killed.

## Finding 3 - P2 - guard_without_its_mirror (reviewer B)

- **file:line:** `test/contracts/exercise_library_cloud_seeded_test.dart:228-235` (registry assertion).
- **claim:** `contains('getFormCuesTool,')` over the whole comment-stripped `registry.ts` also matches the import line the day a second exercise tool turns it into a multi-line import with trailing commas (`registry.ts:30` is single-line today, the array entry is at `:67`), so deleting the array entry would stay green. The ledger's mutations never ran that case.
- **verification:** `grep -n getFormCuesTool supabase/functions/_shared/tools/registry.ts` shows `:30` and `:67` only.
- **status:** accepted - fixed: the assertion is scoped to the `ALL_TOOLS` array body (`indexOf('const ALL_TOOLS')` to the next `];`, the idiom of `derive_only_tool_surface_test.dart`). Mutation M19 (multi-line import AND array entry deleted) killed.

## Finding 4 - P2 - asserted_fixture_value / writer_reader_drift (reviewers A, C, D)

- **file:line:** `.claude/skills/edge-function-deploy-rollback/SKILL.md:138` ("first live delete ... 2026-10-25"), `docs/architecture/database.md:41` ("removed 2026-10-25"), `docs/adr/0016-edge-function-user-token-auth-contract.md:129`, `supabase/functions/_shared/notification_prefs.ts:22` ("since removed"), `test/contracts/exercise_library_cloud_seeded_test.dart:7-8,210`, `test/contracts/beat_my_coach_removed_test.dart:71`.
- **claim:** several durable sentences state, with a hard-coded date, that the function was removed or deleted. The live Edge Function still exists at review time (ledger U12 is `blocked_on_user`); the delete day is a separate founder-gated action and not necessarily today; if the go is refused or delayed the pushed Group A state would assert a delete that never happened.
- **verification:** `git diff origin/main...HEAD -U0 | grep -E '^\+' | grep -n -i -E "removed 2026|since removed|first live delete|until its removal|was deleted"`.
- **status:** accepted - fixed: the SKILL heading says "worked example", undated; database.md and the ADR say "dropped under OI-395" (the ADR update line keeps its note date but speaks of the reference EF being dropped); `notification_prefs.ts:22` says "now dropped" (same line count); the test comments say "source was removed"; the test's failure message says "the beat-my-coach source directory".

## Finding 5 - P2 - asserted_fixture_value (reviewers C and D)

- **file:line:** `docs/audit/open_issues.md:6105` (OI-348) and `:3745` (OI-210).
- **claim:** live open-issue prose cites `app_constants.dart:193` (line does not exist now: the file has 190 lines and `razorpayKeyId` is at 189) and `app_constants.dart:26` (now 25). The plan's line-shift sweep covered the doc deletions but not the Dart ones.
- **verification:** `grep -n razorpayKeyId lib/core/constants/app_constants.dart` = 189; `git show c0565234:lib/core/constants/app_constants.dart | sed -n 193p` = the `razorpayKeyId` line.
- **status:** accepted - fixed (OI-348 now names the symbol and `:189`; OI-210 keeps its dated `:26` and adds "now `:25`"). The sweep command is in plan unit 8; the other hits are in frozen records (plans, reviews, diagnoses, plan-reviews, audit reports, a migration header) that already drifted before this change (finding 18).

## Finding 6 - P3 - guard_without_its_mirror (reviewer B)

- **file:line:** `test/contracts/exercise_library_cloud_seeded_test.dart:215-221`.
- **claim:** the tool-file assertion ran on the raw file text: a commented-out read satisfied it, and it is first-of-N (`getFormCues.ts` has the literal twice, `:65` stage 1 and `:92` stage 2; either alone passed).
- **status:** accepted - fixed: comment-stripped, both reads required. Mutations M20 (one read renamed) and M21 (both reads only inside comments) killed.

## Finding 7 - P3 - asserted_fixture_value (reviewer B)

- **file:line:** `exercise_library_cloud_seeded_test.dart:8-10,207`; `beat_my_coach_removed_test.dart:159-160`.
- **claim:** the header called the coach feature "PRO" while `getFormCues` is `tier: "free"` (`getFormCues.ts:124`); the test name "live, reachable cloud reader" proves two literals, not reachability; the reason "must neither unlock nor count as a badge" overclaims (`unlockedCount` would count the stale key; it has no callers).
- **status:** accepted - fixed: header says "the coach's form-cue answers", test renamed "getFormCues is a cloud reader of exercise_library and is listed in the tool registry", reason now says only what is asserted.

## Finding 8 - P3 - guard_without_its_mirror (reviewer B)

- **file:line:** `beat_my_coach_removed_test.dart:36-43` (tokens), `:67-73` (a), `:108-125` (c).
- **claim:** each guard assumed one spelling: tokens were case-sensitive, `challenge_card` (the deleted widget's file name) was not a token, a `beat_my_coach` directory passed (a), (c) checked only the hyphen slug, and (a) had no parent-existence control (a wrong cwd makes every `existsSync` false).
- **status:** accepted - fixed: lower-case tokens compared case-insensitively plus `beatmycoach` and `challenge_card`; (a) checks the underscore directory and a parent control; (c) checks both spellings. Mutations M12, M13, M16, M17, M18 killed.

## Finding 9 - P3 - asserted_fixture_value (reviewer B)

- **file:line:** `beat_my_coach_removed_test.dart:89-94`.
- **claim:** floors of 200 / 30 were 35% and 12% of the measured 570 .dart / 254 .ts files; a half-walked tree stayed green. Recomputed three ways (git ls-files, a node walk, subtree counts): the measured numbers are exact.
- **status:** accepted - fixed: floors 500 / 220 and two canary files (`badge_service.dart`, `ai-proxy/index.ts`) must be in the scanned set. Mutations M14 (subtree walk) and M15 (canary file skipped; the failure message read: "the scan never reached supabase/functions/ai-proxy/index.ts") killed.

## Finding 10 - P3 - writer_reader_drift (reviewers A and C)

- **file:line:** `.claude/memory/feature_decisions.md:94`.
- **claim:** the diff removed the third row of the "Shareable Cards Spec" table but left "All 3 shareable cards include:".
- **status:** accepted - fixed ("Both shareable cards include:").

## Finding 11 - P3 - writer_reader_drift (reviewer A)

- **file:line:** `docs/adr/0016-edge-function-user-token-auth-contract.md:136`.
- **claim:** the See-also bullet still pointed at "the four reference EFs (... / beat-my-coach)", a live pointer, while the sibling handbook page was edited in place. `:57` is founding-incident history and stays.
- **status:** accepted - fixed ("the three reference EFs (...; a fourth, beat-my-coach, was dropped under OI-395)").

## Finding 12 - P3 - writer_reader_drift (reviewer A)

- **file:line:** `docs/audit/library-core-list-pool.closure.yaml:120-123` (row R8).
- **claim:** R8 stays `blocked_on_user` with the reason "Founder picks OI-395 option (a) or (b)"; this batch answers it (a third path: drop). Two ledgers disagree about whether a decision is outstanding. The plan listed it in R5 ("left as historical").
- **status:** accepted - terminal state recorded, not deferred: the plan's R5 no longer lists it, and Group B (the docs-only commit after the founder-gated delete, ledger row U10B `blocked_on_user`) flips R8 together with closing OI-395, because the answer only becomes final when the delete exists.

## Finding 13 - P3 - writer_reader_drift (reviewers A and D; pre-existing, adjacent)

- **file:line:** `docs/sot_registry.yaml:1599-1600` and `:4638-4639` (`badge_service.dart` `line_range: 110-115`, "weight-log counter").
- **claim:** the range never covered its stated subject (the `weight_` loop is `119-122` now, `121-124` at base); the diff re-derived the sibling `checkAll` range but not these two. They "kept passing" only because the parity gate checks range overflow, not content.
- **status:** accepted - fixed (both re-pointed to `119-122`).

## Finding 14 - P3 - missing_input (reviewer C)

- **file:line:** `docs/audit/drop-beat-my-coach.closure.yaml:13,65,82,127,144`.
- **claim:** the header named a plan-review record that does not exist yet and was not marked to-be-created; U11's title promised a "retrospective memory" the row says is written later; REVIEW-ROUNDS was `verified_clean` with a title saying "B-pass pending"; R6 was `closed_in_commit` but its verification described later events. Gate 40 reads only key sets, so none blocked CI.
- **status:** accepted - fixed (header comment, U11 retitled, REVIEW-ROUNDS retitled with the B-pass as its own row `BPASS`, R6 reworded as a ruling whose mechanical facts were read).

## Finding 15 - P3 - asserted_fixture_value (reviewer C)

- **file:line:** plan unit 10 (`open_issues.md:6607`), the Tier paragraph ("27 paths", "other 18 feature"), ledger R5 evidence ("the three comment-only mentions").
- **claim:** the base line is `6606`; the tier counts do not sum (reviewer C ported `blast_radius_from_diff` to node: 19 or 20 `feature` depending on whether the plan itself is counted); only ONE comment-only mention survives.
- **verification:** `git show c0565234:docs/audit/open_issues.md | sed -n 6603,6607p` (the `Blocked on` line is `6606`).
- **status:** accepted - fixed (6606; counts no longer pinned in prose, they change every commit; R5 evidence names the real survivors).

## Finding 16 - P3 - asserted_fixture_value (reviewer C)

- **file:line:** `.claude/skills/edge-function-deploy-rollback/SKILL.md:142-143`.
- **claim:** "retention starts around 2026-08-10" is an absolute date in a reusable recipe (log retention is a rolling window; the plan's own evidence puts the boundary between 07-15 and 08-10); step 2 compares by sha256 after an MCP read that returns chat text, without saying how to hash it (§6.9 says the MCP tool is not mechanical).
- **status:** accepted - fixed (rolling-window wording; write the returned text byte for byte to a scratch file and `sha256sum` it).

## Finding 17 - P3 - asserted_fixture_value (reviewer D)

- **file:line:** `docs/audit/drop-beat-my-coach.closure.yaml:69` (U9).
- **claim:** "None reddened nothing" is a double negative that mutation M7b ("STAYS GREEN by design") makes false.
- **status:** accepted - fixed ("Every mutation reddened at least one test except M7b, which stays green by design").

## Finding 18 - P3 - writer_reader_drift (reviewer D)

- **file:line:** `docs/plans/streak-freeze-restore-ownership.md:162` (`badge_service.dart:115`), and the frozen-record citations of the shifted `app_constants.dart` lines.
- **claim:** dated historical records cite lines the deletions shifted.
- **status:** no change, by the plan's R5 (records are not rewritten) after the sweep `git grep -n -E "(app_constants|badge_service|achievement_badge)\.dart:[0-9]" -- . ':!backups'`: the LIVE citations were fixed (finding 5); the rest are plans, reviews, diagnoses, plan-reviews, audit reports and a migration header whose citations already drifted before this batch (`app_constants.dart:128`, `:120`, `:78`). No gate reads them.

## Finding 19 - informational - (reviewers B and D)

- **file:line:** `lib/shared/models/achievement_badge.dart:11,45` (`BadgeId.nutritionWeek`).
- **claim:** the defect class removed here ("a badge tile that can never unlock") still exists one enum value away; test (d) pins enum vs list, not enum vs unlock rule (13 `tryUnlock` rules for 14 enum values).
- **status:** known to the plan (evidence row, unit 10); terminal state recorded in ledger row U10B (`blocked_on_user`: the OI is minted with `mint_oi.sh` in Group B, after the founder-gated delete, so a refused go cannot orphan an `oi/N` reservation). Not a defect of this change.

## Mutation evidence for the B-pass hardening (rule 21)

Everything was staged first, so each restore came from the index; each mutation was confirmed applied (non-empty unstaged diff, or the created directory) and each restore was confirmed clean (`git diff --quiet`). "RED" means a failed-test `[E]` line plus "Some tests failed" (a load or compile error prints differently); M15 was re-run to read the failing assertion.

| Id | Mutation | Result |
|---|---|---|
| M10 | stripper line pattern back to `//[^\n]*` | RED |
| M11 | block opener loses its string guard | RED |
| M12 | tokens compared case-sensitively | RED |
| M13 | `challenge_card` removed from the token list | RED |
| M14 | scan walks only `lib/features` | RED |
| M15 | scan skips exactly `ai-proxy/index.ts` | RED (canary message read) |
| M16 | empty `supabase/functions/beat_my_coach/` created | RED |
| M17 | `# beat_my_coach` appended to `docs/snapshot_contract.yaml` | RED |
| M18 | parent control points at a missing directory | RED |
| M19 | `registry.ts`: multi-line import with trailing comma AND array entry deleted | RED |
| M20 | `getFormCues.ts`: one of the two reads renamed | RED |
| M21 | `getFormCues.ts`: both reads only inside comments | RED |

## Tuning entry

- **2026-10-25** - blast-radius platform - 19 findings; 0 false_alarm; tuning: (1) dispatch protocol step 0b added to `.claude/skills/code-review/SKILL.md`: before dispatching, `git fetch origin main`, `git rev-list --left-right --count HEAD...origin/main`, and intersect `git diff --name-status <merge-base> origin/main` with the branch's file list, because the reviewers' three-dot diff is a merge-base diff and CANNOT show that main deleted or untracked a file the branch edits (the P1 here was found only because two reviewers happened to compare trees, and the session banner "local main is 7 commit(s) behind origin/main" had been read as background); (2) lens 6 for any NEW absence guard (nothing may name X): the positive control must include the inputs that make the SCANNER blind - a token after `scheme://`, a glob in a string, other casings and the snake_case spelling - not only "flags code, ignores comment" (at review time 62 test files used `(?<!:)//` and 99 call sites the naive stripper; 64 and 97 after this batch switched its own two); (3) briefs with an exhaustive allowed-command list worked: all four reviewers stayed inside it, none ran a live-capable gate (round 1 of the PLAN review had one that did).
