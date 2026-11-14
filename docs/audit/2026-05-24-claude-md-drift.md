# CLAUDE.md Drift Audit — 2026-05-24

First-run dry-run output of the `sync-claude-md` skill. Scope-capped to ~35 high-impact verifications per skill bootstrap protocol — exhaustive line-by-line audit of a ~3000-line file deferred to subsequent runs.

## Scope of this run

- **All P0 candidates** searched (broken file paths, broken memory refs) — 35 file paths verified, 12 memory refs verified.
- **Count claims** verified across §2 (tables), §7 (tables explicit), §10 (Wardroom exports), §11 (AI coach tools, Edge Functions), §17 (exercise library), §18 (food database).
- **Edge Function versions** — all 11 versions explicitly named in CLAUDE.md cross-referenced against live `list_edge_functions` MCP output.
- **Memory file refs** — 12 high-frequency `feedback_*.md` / `project_*.md` references verified.

Not in scope this run (deferred): exhaustive line:N references across §15 / §19; per-function migration cross-references; `appVersion` history claims; gates 1-17 vs scripts/ directory enumeration (Gate 18-22 implicitly verified via file existence).

## Summary

- **P0 (broken refs):** 0
- **P1 (count drift):** 4
- **P2 (line/version drift):** 2

CLAUDE.md is structurally healthy — no broken file paths, no missing memory files, no fatally stale version claims. Drift items are all count claims that lagged shipping (tables +1 since §7 last touched, Wardroom exports −2 since §10 last touched, morning-alert deployed 4 versions past the recorded v21).

## P0 findings

None. All 35 file path references and all 12 memory file references resolved to existing files.

## P1 findings

### Finding 1: `46 Tables` claim is now `47`

- **Where:** CLAUDE.md §7 ("DATABASE SCHEMA (46 Tables — Supabase Postgres)") + the per-domain breakdown table that sums to 46.
- **Claim:** `"46 Tables — Supabase Postgres" ... "Count verified live on prod 2026-05-11"`.
- **Reality:** `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'` returns **47** as of 2026-05-24.
- **Suggested fix:** Identify which table was added since 2026-05-11 (likely from migrations 067-071, e.g. `cron_call_log` from migration 068), bump the header to "47 Tables", add the new table to the appropriate domain bucket in the breakdown table, refresh the "Count verified live" date.
- **Related:** `scripts/check_doc_internal_consistency.dart` (Gate 18) is the registered drift-pair gate for this number — confirm it's wired against §2 ("21 tables" was the docstring example before; verify §2 vs §7 stays internally consistent).

### Finding 2: Wardroom barrel claims `36 exports`, file has `34`

- **Where:** CLAUDE.md §10 "Wardroom primitives (36 exports)" + accompanying enumerated table.
- **Claim:** `"Barrel: lib/shared/widgets/wardroom/wardroom.dart — 36 export lines."`
- **Reality:** `grep -c "^export" lib/shared/widgets/wardroom/wardroom.dart` returns **34**.
- **Suggested fix:** Reconcile — either CLAUDE.md was anticipating 2 future exports that didn't land, or 2 entries were deleted post-doc-update. Audit the barrel against the enumerated primitive table; bump the docstring count to match. Likely candidate for removal from the table: legacy `RankChip` + `RankInsignia` (CLAUDE.md notes them as deleted in audit-2026-05-16 / E.11 — table footer says "DELETED" but the "36 exports" header line may be counting from before the delete).

### Finding 3: `258 exercises` ≠ `250` claim ≠ `200+` claim

- **Where:** CLAUDE.md §17 "EXERCISE LIBRARY" says `"250 exercises seeded in bundled JSON"`. §4 / SEED DATA bullet says `"assets/data/exercise_library.json (200+ exercises)"`.
- **Claim:** Two different counts, both stale.
- **Reality:** `assets/data/exercise_library.json` has **258** entries.
- **Suggested fix:** Pick a single accurate number ("258 exercises" or "250+ exercises"). The two-place claim doubles the drift risk — consolidate to one §17 source-of-truth and have §4 link to it.

### Finding 4: AI coach tools enumeration says `workout (8)` — registry has 8 entries but family has 9 files

- **Where:** CLAUDE.md §11 family table: `"Workout (8) | swapExercise, logSet, markWorkoutComplete, shortenWorkout, createCustomExercise, modifyWorkoutForInjury, rescheduleWeek, generateHotelWorkout"`.
- **Claim:** Workout family has 8 tools listed.
- **Reality:** `supabase/functions/_shared/tools/workout/` has 9 `.ts` files. Inspection: 8 tool files + 1 `index.ts` barrel — claim is **accurate at the registry level** but the surrounding "24 AI coach tools" total is consistent with the registry (verified: 8+5+5+5+1=24 entries in `ALL_TOOLS`).
- **Suggested fix:** No action needed — flagging only to document the verification. Adding a comment in §11 like "(file counts include index.ts barrels; registry-level counts are canonical)" would prevent future false-positive drift-flags from this skill.

## P2 findings

### Finding 5: Edge Function `morning-alert` stamped v21 in CLAUDE.md, live is v25

- **Where:** CLAUDE.md §19 entry for APK Test #8 batch: `"morning-alert v21 deployed"`.
- **Claim:** Live deployed version is v21.
- **Reality:** `list_edge_functions` returns morning-alert at **v25** (4 versions past).
- **Suggested fix:** Per skill protocol (±2 tolerance, >2 behind = P2), update CLAUDE.md §19 to note current live is v25, or add a clarifying "(v21 as of that batch; live drifts forward)". Same pattern likely applies to other Edge Function version stamps in batch retrospectives — those are historical anchors not live claims, so a single clarifying sentence per §19 mega-entry is preferable to chasing every version drift.

### Finding 6: `ai-proxy v66` cited in §15 (audit-2026-05-16 batch), live is v67

- **Where:** CLAUDE.md §19 audit-2026-05-16 entry: `"ai-proxy v66 (placeholder resolution + cross-channel dedup)"`. Also referenced in §11 retrieval section: `"since ai-proxy v46"` (historical anchor — not a drift).
- **Claim:** Latest live deploy is v66.
- **Reality:** Live is **v67**.
- **Suggested fix:** Within ±2 tolerance — no action strictly required. Note in the report so the founder can decide if these batch retrospective stamps should be marked as "historical" vs "live" in future doc style.

## Verifications confirmed (no drift) — sample

For founder visibility, these high-traffic claims verified as **accurate**:

- **§18 food_database 1431 items** — `food_database.json` has 1431 entries (exact match).
- **§11 AI coach 24 tools** — `ALL_TOOLS` registry has 24 entries (8 workout + 5 progress + 5 nutrition + 5 plan + 1 exercise).
- **§10 _highValueFeatures set** — `subscription_service.dart` has exactly 3 features (phases_2_to_12, ai_coach_unlimited, progress_photos).
- **Wardroom AppRadius spec** — §10 says `card = 6 dp` and `sharp = 2 dp`; `lib/core/theme/spacing.dart` confirms exact values.
- **Edge Function deploys (current generation):** ai-media-proxy v18 ✓ • delete-account v3 ✓ • clean-orphan-media v6 ✓ • razorpay-webhook v18 ✓ • verify-payment v13 ✓ • log-client-error v7 ✓ • promote-community-item v10 ✓ • evaluate-rank-promotions v6 ✓ • pr-detection v6 ✓.
- **Filesystem aggregate counts:** 71 numeric migrations (highest 071) • 154 contract tests • 26 build gates • 105 memory files • 6 agents • 3 skills (sync-claude-md, debugging, strategic-compact — debugging + strategic-compact landed pre-T2, sync-claude-md from T3 just committed).

## Tooling concerns

- **MCP `execute_sql` requires `project_id`** as a separate parameter — first invocation failed with ZodError. Documented in skill; future runs unaffected.
- **Edge Function version stamps in §19 batch retrospectives** are inherently lossy — they record a point-in-time deploy but the live function keeps moving. Recommend a structural decision: either (a) mark each version stamp with the deploy date in CLAUDE.md so future skill runs treat them as historical, or (b) move version stamps out of §19 entirely into a separate `docs/edge_function_versions.md` that the skill audits separately.
- **AI tool family counts** (24 tools / 5 families) require parsing TypeScript to distinguish tool files from barrel `index.ts`. The skill uses the `ALL_TOOLS` registry as canonical truth — line-counting `ls` of family directories yields off-by-1 false positives.

## Founder action

No fixes have been applied. Review the P1 findings (counts) and P2 findings (versions); instruct the next session which to address. The skill will be re-run end-of-batch.
