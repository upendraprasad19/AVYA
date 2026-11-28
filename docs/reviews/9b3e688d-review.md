---
reviewed_at: 2026-09-04T18:52:00+05:30
staged_against: 9b3e688d
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, test_can_actually_fail, asserted_fixture_value, stale_or_wrong_citation, modelled_on_is_a_checkable_claim, missing_input, blast_radius_mismatch, live_state]
findings_count: 8
verdict: accepted
---

# Code Review — 9b3e688d

Commit under review: `fix(limits): free food-text cap said 10 everywhere except the trigger
that enforces it`. Migration 127 lowers `enforce_food_text_daily_limit`'s FREE arm 50 -> 10
(PRO stays 200), applied to prod as cloud version `20260904114820`. Widens
`ai_message_limit_parity_test.dart`, adds `food_text_analysis_daily_cap_writer_to_reader_test.dart`
and a shared `test/helpers/migration_cap_reader.dart`.

All mutation-proof claims in the commit message were independently re-run (see Finding-free
section below) and confirmed exact. The core fix (migration 127, live-verified) is correct. The
findings below are about **incomplete propagation of the fix** — other readers of the same "50"
that this batch's own stated methodology ("every source of truth... one said 50") should have
caught but didn't — plus a few precision/documentation issues.

## Finding 1 — P1 — writer_reader_drift / guard_without_its_mirror
- **file:line:** `supabase/functions/ai-proxy/index.ts:324`
- **claim:** The diagnose-doc's `touched_layers_checked` tier 6 states "the only ai-proxy change
  is a routing-table docstring line; zero runtime effect, so no redeploy is required for
  correctness," and the SoT registry's `readers:` list for `food_text_analysis_daily_cap` names
  only 4 client Dart files. Both are incomplete: `ai-proxy/index.ts` itself is a reader that
  duplicates the FREE cap as a literal, and this batch didn't touch it. Line 324:
  `const cap = isProUser ? 200 : 50;` — still `50` — feeds directly into the HTTP 429 body
  returned when the trigger rejects an insert: `` `Daily food analysis limit reached (${cap}/day).
  Try again tomorrow.` `` (line 327). The literal was `50` before this commit and is `50` after it,
  even though the trigger it's describing now enforces `10`.
- **verification:**
  `grep -n "50/day\|: 50\|50 :\|50;" supabase/functions/ai-proxy/index.ts` →
  ```
  231:    // Free: 50/day  ·  PRO: 200/day. Enforced atomically by Postgres
  324:          const cap = isProUser ? 200 : 50;
  ```
  Only line 14 (the routing-table docstring cited in the commit message) was actually changed by
  this diff; lines 231 and 324 were not. For comparison, the chat-cap analog in the SAME file uses
  a named, tested constant instead of a duplicated literal:
  `grep -n "^const FREE_DAILY_LIMIT\|limit: FREE_DAILY_LIMIT" supabase/functions/ai-proxy/index.ts`
  → `71:const FREE_DAILY_LIMIT = 10;` and `750:          limit: FREE_DAILY_LIMIT,` — that constant
  IS asserted equal to `AppConstants.freeAiMessagesPerDay` by the pre-existing first test in
  `ai_message_limit_parity_test.dart`. The food-text path has no equivalent constant and no
  equivalent test coverage of this specific literal.
  Live impact confirmed low but real: the in-app client does not surface this raw server string —
  it substitutes its own hardcoded generic message (`lib/features/nutrition/providers/nutrition_provider.dart:856`:
  `'Daily food analysis limit reached. Try again tomorrow or upgrade to PRO.'`, no number
  interpolated) — so in-app users never see the wrong number. The caller who DOES see it is
  exactly the population this fix targets: anyone hitting `ai-proxy` directly. Enforcement itself
  is unaffected (still correctly blocks at the 11th call); only the message is wrong.
- **suggested-fix:** Hoist a `FREE_FOOD_TEXT_DAILY_LIMIT = 10` constant next to `FREE_DAILY_LIMIT`
  (line 71), use it at both line 231 (comment) and line 324, and add an assertion to
  `food_text_analysis_daily_cap_writer_to_reader_test.dart` or `ai_message_limit_parity_test.dart`
  pinning it against `AppConstants.freeAiTextLogsPerDay`, mirroring the existing chat-cap pattern.
- **status:** accepted — FIXED. ai-proxy now names FOOD_TEXT_FREE_DAILY_CAP/FOOD_TEXT_PRO_DAILY_CAP (index.ts:84-85) and the 429 body reads them; both pinned to the live trigger arms, and the literal ternary is pinned ABSENT, by food_text_analysis_daily_cap_writer_to_reader_test.dart. Mutation-proven twice (cap 10->50 = 1 red; literal restored = 1 red).

## Finding 2 — P1 — stale_or_wrong_citation
- **file:line:** `supabase/functions/CLAUDE.md:128,168`; `lib/features/nutrition/CLAUDE.md:41`;
  `docs/architecture/ai.md:135`; `docs/architecture/functionality-flow.md:206`
- **claim:** None of these five lines (across four files) were touched by this commit, yet all
  five still state the food-text FREE cap is "50/day" post-fix. Two of the four files —
  `supabase/functions/CLAUDE.md` and `lib/features/nutrition/CLAUDE.md` — are **auto-loaded by
  Claude Code into every future session that touches those subtrees**, per root CLAUDE.md's own
  framing ("Per-feature rules live in nested `lib/.../CLAUDE.md` (auto-loaded...)"). This is not
  a hypothetical propagation risk: both files' stale "50/day free ... migration 024" content was
  injected into THIS review's own context verbatim as system-reminder blocks the moment I read
  files under `supabase/functions/` and `lib/` earlier in this session (visible in the transcript).
  Root CLAUDE.md §5's per-batch checklist explicitly asks "Nested CLAUDE.md updated if feature
  contract changed" — this commit changed the enforced FREE cap (the feature contract) and left
  both nested docs uncorrected, plus two architecture docs.
- **verification:**
  `grep -rn "50/day" docs/architecture/ai.md docs/architecture/functionality-flow.md supabase/functions/CLAUDE.md lib/features/nutrition/CLAUDE.md` →
  ```
  docs/architecture/ai.md:135:- `food_text_analysis`: Text → nutrition JSON. **Rate limited: 50/day free, 200/day PRO** ...
  docs/architecture/functionality-flow.md:206:- **`NUT-05`** ... Server caps 50/day free, 200/day PRO. ...
  supabase/functions/CLAUDE.md:128:| `food_text_analysis` | ... | 50/day free · 200/day PRO — enforced atomically by the `trg_food_text_rate_limit` Postgres trigger (migration 024) ...
  supabase/functions/CLAUDE.md:168:| food_text_analysis 429 ... | Trigger `trg_food_text_rate_limit` ... (migration 024, 2026-04-18) enforces the 50/day free / 200/day PRO cap atomically. ...
  lib/features/nutrition/CLAUDE.md:41:| `food_text_analysis` daily cap | server-side trigger `trg_food_text_rate_limit` (migration 024) — 50/day free, 200/day PRO. ...
  ```
  These were NOT in the commit's diff (`git show --stat 9b3e688d` lists only 10 changed files;
  none of these four are among them). Live pg_proc confirms the true cap is now 10 (Lens 9).
- **suggested-fix:** Update all five "50/day free" occurrences to "10/day free," and correct
  `supabase/functions/CLAUDE.md`'s two "migration 024" enforcement citations to the live
  definition (migration 127 / cloud version `20260904114820`) — "024" (really 026 on disk) is now
  two generations stale as the citation for *current* enforcement, though it remains historically
  accurate as the migration that *first* created the trigger.
- **status:** accepted — FIXED. All four docs updated: supabase/functions/CLAUDE.md (routing table + pitfalls row + SoT contracts row), lib/features/nutrition/CLAUDE.md:41, docs/architecture/ai.md:135, docs/architecture/functionality-flow.md:206. The two nested CLAUDE.md files were the sharp half — they auto-load into every future session in those subtrees.

## Finding 3 — P2 — stale_or_wrong_citation
- **file:line:** `supabase/functions/ai-proxy/index.ts:231`
- **claim:** The commit message frames "the ai-proxy routing docstring is corrected from
  '50/day free' to '10/day free'" as the extent of ai-proxy's involvement in this fix — but that
  correction only touched ONE of two near-identical occurrences in the same file. Ninety lines
  below the routing-table docstring (line 14, which WAS fixed), the `food_text_analysis` handler's
  own header comment still reads: `// Free: 50/day  ·  PRO: 200/day. Enforced atomically by
  Postgres // trigger \`trg_food_text_rate_limit\` (migration 024) on the`.
- **verification:** `sed -n '230,236p' supabase/functions/ai-proxy/index.ts` shows the unedited
  comment; `git show 9b3e688d -- supabase/functions/ai-proxy/index.ts` shows only line 14 in the
  diff hunk.
- **suggested-fix:** Update line 231-233's comment alongside line 14's, in the same commit that
  fixes Finding 1 (both are in the same function).
- **status:** accepted — FIXED. ai-proxy/index.ts:231 header comment now reads 10/day and cites the LIVE migration (127) rather than 024.

## Finding 4 — P2 — stale_or_wrong_citation
- **file:line:** `docs/architecture/business-rules.md:36`
- **claim:** The diagnose-doc, the migration header, and the SoT registry entry all cite
  `docs/architecture/business-rules.md:17,36` together as two independent confirmations that "the
  free cap is documented as 10/day." Line 17 (under `## FREE Forever`) is correct and IS such a
  confirmation. Line 36 is a different thing: it's the FIRST bullet under `## PRO — ₹349/month or
  ₹2,999/year` (header at line 34), and it reads the *identical* text — "AI food text analysis —
  10 text logs/day" — as the FREE row above it. As the PRO row, it's wrong on its own terms: the
  live server cap for PRO is 200/day and the client displays "unlimited"
  (`usage_counter_service.dart:127`: `isPro ? 999999 : AppConstants.freeAiTextLogsPerDay`), not
  10/day — the adjacent PRO rows for scan-meal and cart-auditor correctly show higher PRO numbers
  (10/day vs FREE's 3 and 1), so this one bullet looks like a copy-paste leftover from the FREE
  section rather than an intentional PRO figure. This batch's own stated methodology — "Four
  sources of truth... Three said 10" — treated line 36 as one of the three agreeing sources
  without noticing it's actually a second, unrelated bug in the same file it was reading.
- **verification:** `grep -n "AI food text analysis" docs/architecture/business-rules.md` →
  `17:...` and `36:...`; `sed -n '30,40p' docs/architecture/business-rules.md` confirms line 34
  is the `## PRO` header and line 36 sits directly under it, identical text to line 17.
- **suggested-fix:** Correct business-rules.md:36 to state PRO's actual entitlement (e.g.
  "unlimited — 200/day abuse ceiling"), and in the diagnose-doc/migration-header, cite only line
  17 as the FREE confirmation rather than "17,36" as if both independently confirmed the same
  fact.
- **status:** accepted — FIXED, and wider than reported. business-rules.md:36 is the PRO row, so it was never evidence for the free cap; it was also independently wrong (PRO is unlimited client-side, 200/day server ceiling). Row corrected and the diagnose-doc citation narrowed to :17 only, with the error recorded.

## Finding 5 — P3 — modelled_on_is_a_checkable_claim / stale_or_wrong_citation
- **file:line:** `supabase/migrations/127_food_text_free_cap_parity_10.sql:36`
- **claim:** "⚠ This is the FOURTH definition of enforce_food_text_daily_limit (026 -> 113 ->
  this)." The parenthetical names three anchors, and a repo-wide grep finds exactly three files
  that `CREATE [OR REPLACE] FUNCTION enforce_food_text_daily_limit` — 026, 113, 127. This is the
  THIRD definition, not the fourth (comment-only; zero functional effect).
- **verification:** `grep -rln "FUNCTION enforce_food_text_daily_limit" supabase/migrations/` →
  `026_food_text_rate_limit_trigger.sql`, `113_fix_food_text_trigger_ist_boundary.sql`,
  `127_food_text_free_cap_parity_10.sql` (3 files). A wider grep for any mention at all
  (`grep -rln "enforce_food_text_daily_limit" supabase/migrations/`) also turns up `090_...` (an
  `ALTER FUNCTION ... SET search_path`, not a redefinition — changes no cap logic) and `111_...`
  (a prose comment, "Mirrors migration 026's ... shape," not a definition) — neither is a fourth
  *definition*, and neither is named in the migration's own parenthetical.
- **suggested-fix:** Correct to "THIRD definition," or if 090's `ALTER FUNCTION` is meant to
  count as a touch, say so explicitly instead of leaving the count unexplained.
- **status:** accepted — FIXED. Migration 127 header now says THIRD definition (026 -> 113 -> 127). Verified by grep: exactly three migrations define the function.

## Finding 6 — P3 — asserted_fixture_value
- **file:line:** `test/contracts/ai_message_limit_parity_test.dart:513-558` (new "server vision
  ceiling covers the full PRO per-channel allowance" test);
  `docs/diagnoses/2026-09-04-food-text-free-cap-server-client-drift-b8f4c2.md:208-211`
- **claim:** The diagnose-doc says: "The founder plan of 2026-09-04 was 'we'll increase the max to
  ~30 when we add one' — an intention with nothing to fire it. Now it fires." This overstates what
  the assertion mechanically does. `proTotal` is the sum of exactly two named constants read via
  `clientIntConstant('proScanMealPerDay')` and `clientIntConstant('proCartAuditorPerDay')` — a
  fixed, hardcoded enumeration, not a dynamic scan. Adding a third PRO vision-channel constant to
  `app_constants.dart` (and wiring a new channel into the shared trigger) does **not** by itself
  redden this test; a developer would also have to remember to edit this specific test to add the
  new constant into the sum — the same "remember to update the pinning test" discipline gap this
  whole batch is about, one level up. The assertion IS real and meaningful for the current two
  channels (confirmed via mutation — see Lens 3), just not self-updating for a hypothetical third.
- **verification:** Read of the diff (`test/contracts/ai_message_limit_parity_test.dart` new
  test body) — only two `clientIntConstant(...)` calls feed `proTotal`; no loop/regex over
  `pro.*PerDay` constant names, no reflection.
- **suggested-fix:** Either soften the diagnose-doc's "now it fires" framing to note it requires
  updating this test alongside any new channel, or make the sum genuinely dynamic (e.g. regex-scan
  `app_constants.dart` for a documented `pro*VisionPerDay` naming convention) if "fires
  automatically" is the intended guarantee.
- **status:** accepted — FIXED. The test comment now states its scope exactly: it compares the ceiling against two NAMED constants, and a third channel fires it only once its constant is added to the sum. The overstated automatic-discovery framing is gone.

## Finding 7 — P3 — guard_without_its_mirror (informational, pre-existing, out of scope)
- **file:line:** `supabase/functions/_shared/tools/nutrition/logMealByText.ts:32`;
  `supabase/functions/_shared/food_parser.ts:1-24`
- **claim:** The AI Coach chat's `logMealByText` tool parses free-text meal descriptions via
  `parseFoodText()` → `geminiChat()` directly, and never inserts a row with
  `channel='food_text_analysis'` into `ai_coach_interactions`. It is therefore never counted by
  `enforce_food_text_daily_limit` at all — a free user can log unlimited meals-by-text through AI
  Coach chat, bounded only by the separate, unrelated chat cap (`channel='app'`, 10/day). This is
  a legitimate "EF acting on the user's behalf" path (per the guard_without_its_mirror lens) that
  performs food-text-analysis-equivalent Gemini calls without touching the cap this commit
  hardens. `food_parser.ts`'s own header comment documents this as a deliberate, temporary
  duplication ("left that channel untouched on purpose... A future refactor can collapse both onto
  this helper"), so it predates and is out of scope for this specific commit — but it means the
  `food_text_analysis_daily_cap` SoT concept's enforcement is not comprehensive across every
  food-text-analysis-shaped AI call, which the concept's name and description don't disclose.
- **verification:** `grep -rln "food_text_analysis" supabase/functions/ --include="*.ts"` → only
  `ai-proxy/index.ts`, `_shared/food_parser.ts`, `_shared/gemini.ts` (the latter two only mention
  the channel name in a comment); `grep -n "food_text_analysis\|ai_coach_interactions" logMealByText.ts` → no matches.
- **suggested-fix:** None required for this commit. Worth a one-line note in the SoT registry's
  `description:` field ("does not cover AI-Coach chat's logMealByText path — see food_parser.ts
  header") so a future reader doesn't assume comprehensive coverage, or an OI-board entry if not
  already tracked.
- **status:** false_alarm (informational, correctly flagged) — NOT a defect of this batch. logMealByText is a separate, pre-existing, documented path; it does not read or report the food-text cap, so it cannot drift from it. Recorded here so the next reader does not re-derive it.

## Finding 8 — P3 — blast_radius_mismatch (low confidence)
- **file:line:** `docs/blast_radius.yaml:23-26` (platform tier `requires:`)
- **claim:** Platform tier's `requires:` list is `[regression_test, behavioral_test_path,
  code_review_b_pass, feature_flag]`. This commit satisfies the first three (widened parity test +
  new writer-to-reader test, `presence_only: true` rationale for the behavioral gap, this review)
  but ships no feature flag / kill-switch — the new cap takes effect the instant the migration is
  applied, and the diagnose-doc's `forbidden_patterns_checked` section doesn't mention or waive
  `feature_flag`. `scripts/check_blast_radius_coverage.dart` (read in full) only verifies that
  every directory has SOME tier rule in the registry — it does not check that an individual
  commit's `requires:` list was actually satisfied, so nothing mechanically blocks this.
- **verification:** `sed -n '15,27p' docs/blast_radius.yaml`; full read of
  `scripts/check_blast_radius_coverage.dart` (confirms it's a coverage-only gate, no per-commit
  `requires:` enforcement).
- **suggested-fix:** Low confidence this is a real gap — CLAUDE.md §4.6's feature-flag protocol is
  explicitly scoped to "payment / sync / auth / AI prompt / plan generator," not rate-limit
  constants, and the migration's documented, byte-identical rollback body arguably substitutes for
  a runtime flag on a pure numeric-threshold change. Recommend a one-line explicit waiver in the
  diagnose-doc ("feature_flag N/A — reason") rather than leaving `requires:` silently unaddressed,
  so a future reader doesn't have to re-derive whether it was considered.
- **status:** accepted — ANSWERED, not waived. platform tier lists feature_flag, which no gate enforces. It is inapplicable here for the same reason recorded for Slice A on 2026-09-03: this change tightens a cap that was too loose, so a flag whose OFF state restores 50/day would re-open the exact hole. A flag whose OFF state is the vulnerability is not a safety mechanism. Same disposition, same reasoning, stated rather than inherited.

## Lenses returning clean

**Lens 3 — test_can_actually_fail (mutation re-run, independent).** All four claimed mutation
results were reproduced exactly, one at a time, each confirmed applied via `grep`/`sed -n` before
running `flutter test`, each reverted via `git checkout --` immediately after, `git status`
confirmed clean after every step and at the end:
- (a) Migration 127 `ELSE 10` → `ELSE 50`: **1 red** (`writer FREE arm == reader
  freeAiTextLogsPerDay`, expected 10 got 50). Matches claim.
- (b) `test/helpers/migration_cap_reader.dart` `return defs.last;` → `return defs.first;`:
  **3 red** — the vision-ceiling test failed with `Vision ceiling (10,
  111_chat_vision_daily_cap_triggers.sql)`, reproducing the diagnose-doc's own planning-error
  anecdote verbatim (migration 111 defines both cap functions; a naive first-match returns the
  CHAT cap for a vision query). Matches claim exactly, including the specific wrong value cited.
- (c) `stripSqlComments` removed from `readProFreeCap` + `readSingleCeiling` (both call sites):
  **1 red** — the food-text FREE-arm test failed reading migration 127's own `Rollback strategy:`
  header prose (`ELSE 50` at line 32) instead of the live statement (`ELSE 10` at line 65), exactly
  as described. Matches claim.
- (d) `stripSqlComments` removed from `latestMigrationDefining`'s `contains(...)` check only:
  **0 red** — all 10 tests passed. Matches the negative claim exactly.

**Lens 6 — modelled_on_is_a_checkable_claim (migration 113 vs 127 diff).**
`diff <(sed -n '20,55p' 113_...) <(sed -n '45,83p' 127_...)` shows the only executable-statement
difference is `ELSE 50 END;` → `ELSE 10 END;`; every other diff hunk is comment text. The
IF/SELECT/RAISE EXCEPTION/RETURN statements are byte-identical. Claim confirmed true.
`grep -rln "FUNCTION enforce_food_text_daily_limit"` → {026, 113, 127}; `grep -rln "FUNCTION
enforce_vision_analysis_daily_limit"` → {111, 114}. Both enumeration claims in
`test/helpers/migration_cap_reader.dart`'s header comment confirmed exact.

**Lens 9 — live_state (Supabase MCP, project `dedsavbjuwgarrhphgnl`, confirmed via `get_project`
before querying).**
- `SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='enforce_food_text_daily_limit'` →
  live body contains `daily_cap := CASE WHEN is_pro THEN 200 ELSE 10 END;` and the IST boundary
  expression, byte-identical to migration 127's function body.
- `SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname='trg_food_text_rate_limit'` →
  `BEFORE INSERT ON public.ai_coach_interactions ... EXECUTE FUNCTION
  enforce_food_text_daily_limit()`, `tgenabled='O'` (enabled).
- `list_migrations` → last entry `{"version":"20260904114820","name":"food_text_free_cap_parity_10"}`,
  matching the diagnose-doc's claimed cloud version exactly. Also confirms migration 026's own
  header note that it was applied live as `024_food_text_rate_limit_trigger` on 2026-04-18
  (`{"version":"20260418124721","name":"024_food_text_rate_limit_trigger"}`) — so the "migration
  024" citations in Finding 2 are not fabricated, just stale for *current* enforcement.
- `sha256sum supabase/migrations/127_food_text_free_cap_parity_10.sql` →
  `305622fba7cd22019e3c73810aae952f7446159e1731fca1db94fbc02f7ad0ca`, exact match to
  `backups/applied_migrations.json`'s recorded hash.
- Also checked the "mirror" retroactivity question (Lens 2): a free user with 10-49
  `food_text_analysis` rows already logged today (IST) before the migration applied would be
  immediately blocked from their next legitimate call post-migration, with no warning. Queried
  live data — `SELECT user_id, count(*) FROM ai_coach_interactions WHERE channel='food_text_analysis'
  AND created_at >= <IST day start> GROUP BY user_id HAVING count(*) >= 10` → **0 rows**. Nobody
  was actually affected; the diagnose-doc's "impact_analysis" claim ("No user loses access they
  have today... live prod exposure was low") holds empirically, not just by assertion.
- `enforce_vision_analysis_daily_limit`'s live body confirmed `daily_count >= 20` — matches
  migration 114 exactly, confirming the vision-ceiling test's `20` fixture value is real.

**Lens 4 — asserted_fixture_value (constant values).**
`grep -n "freeAiTextLogsPerDay\|freeScanMealPerDay\|proScanMealPerDay\|freeCartAuditorPerDay\|proCartAuditorPerDay\|freeAiMessagesPerDay" lib/core/constants/app_constants.dart`
confirms: `freeAiMessagesPerDay=10` (L75), `freeAiTextLogsPerDay=10` (L78), `freeScanMealPerDay=3`
(L81), `proScanMealPerDay=10` (L84), `freeCartAuditorPerDay=1` (L87), `proCartAuditorPerDay=10`
(L90). `proScanMealPerDay + proCartAuditorPerDay = 20`, matching the live vision ceiling exactly
(equality, not slack) — confirmed via mutation (b) above that this is a meaningful, non-vacuous
bound (reddens when the ceiling regresses). Free sum (3+1=4) is comfortably under 20, as claimed.

**Lens 1 — writer_reader_drift (client-side enumeration completeness).**
`grep -rn "freeAiTextLogsPerDay" lib/ test/` confirms all four client-side SoT registry entries
(the constant + 3 usage sites: `usage_counter_service.dart:127`, `food_logger_section.dart:107`,
`subscription_section.dart:174`) are complete and accurate — no missed client reader. (The
incomplete side of this lens — `ai-proxy/index.ts` itself as an unlisted reader — is Finding 1.)

**Lens 5 — stale_or_wrong_citation (file:line spot-checks not covered by Findings 2/4/5).**
Every other new file:line citation checked against the actual file: diagnose-doc's writer citation
`113_...sql:38` → exact match (`daily_cap := CASE WHEN is_pro THEN 200 ELSE 50 END;`); `127_...sql:65`
→ exact match (live `ELSE 10` line); `127_...sql:74` (IST handling) → exact match (the boundary
expression line); SoT registry writer `line_range: 45-83` → exact match to the
`CREATE OR REPLACE FUNCTION ... $$ LANGUAGE plpgsql;` span; SoT registry reader `line_range`s for
`usage_counter_service.dart` (124-128), `food_logger_section.dart` (105-109),
`subscription_section.dart` (172-176) → all exact, all correctly scoped to the cited method;
`supabase/migrations/CLAUDE.md:68` → exact match (`ai_coach_interactions | coach_interactions,
food_text_analysis_daily_cap | ...`). Also independently ran the repo's own citation gates:
`dart run scripts/check_sot_registry_parity.dart` → PASS, 0 errors; `dart run
scripts/check_sot_behavioral_test_paths.dart` (Gate 42) → PASS, confirms 7 `presence_only: true`
entries (was 6 before this batch, per CLAUDE.md rule 21 — consistent with this being the 7th);
`dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-09-04-food-text-free-cap-server-client-drift-b8f4c2.md`
→ OK.

**Lens 7 — missing_input (migration_cap_reader.dart robustness).**
`migrationNumber()` returns `-1` for a filename with no numeric prefix, which by design never wins
`defs.last`. Confirmed a real such file exists — `supabase/migrations/all_migrations_combined.sql`
— and it does NOT currently contain `FUNCTION enforce_food_text_daily_limit`
(`grep -c "FUNCTION enforce_food_text_daily_limit" all_migrations_combined.sql` → 0), so it's
correctly excluded from `defs` today; the -1 sentinel design is sound even if it did match.
`Directory(migrationsDir).listSync()` is non-recursive — confirmed the one subdirectory,
`supabase/migrations/041_chunks/`, is correctly excluded by `.whereType<File>()` and (checked)
contains no definition of either function anyway, so non-recursion isn't hiding anything today.
The "future migration that merely references the function in prose" risk that
`stripSqlComments` inside `latestMigrationDefining` guards against is honestly documented as
currently-inert (confirmed by mutation d = 0 red) rather than claimed as active protection.

**Lens 8 — blast_radius_mismatch (glob coverage).**
`grep -n "platform" docs/blast_radius.yaml` confirms `supabase/functions/ai-proxy/**` (L54) and
`supabase/migrations/**` (L62) are both explicitly platform-tier globs — the commit's self-declared
`Blast-radius: platform` is correctly derived from its touched paths. (The one gap found under this
lens — the unaddressed `feature_flag` requirement — is Finding 8, low confidence.)

## Test run

```
flutter test test/contracts/ai_message_limit_parity_test.dart \
  test/contracts/food_text_analysis_daily_cap_writer_to_reader_test.dart \
  test/contracts/food_text_analysis_daily_cap_test.dart \
  test/contracts/applied_migrations_parity_test.dart
```
Result: **10/10 passed** (`00:01 +10: All tests passed!`). Re-run after all four mutation
round-trips to confirm the tree was left exactly as it started — same 10/10 result, `git status`
clean.


## Founder triage notes

Triaged 2026-09-04 by the batch author, immediately after the pass, before the merge.
**7 accepted and fixed in this same batch (no deferrals, CLAUDE.md 4.2); 1 false_alarm**
(Finding 7, correctly self-labelled informational/pre-existing by the reviewer).
False-alarm rate 1/8 = 12.5%, under the 30% tuning threshold.

**The pass earned its cost, and the reason is worth stating.** All four mutation claims
and the live-prod state reproduced exactly, so the fix itself was sound. What the reviewer
found instead was that the fix had been applied where the cap is ENFORCED and nowhere it is
REPORTED: the 429 message told callers 50/day, and two auto-loaded nested CLAUDE.md files
would have kept feeding 50/day to every future session as authoritative context. The
author's own pre-commit grep was scoped to `test/` and `scripts/` for a repo-wide constant,
returned zero hits, and was read as proof of absence -- the same input-set defect that
produced the original bug, committed again inside its fix.
