# CLAUDE.md Drift Audit — 2026-05-27

> Run via `/sync-claude-md`. Scope: root CLAUDE.md + cross-checked against live Supabase, filesystem, and Edge Function state.
> All findings are claims founder reviews — DO NOT auto-edit CLAUDE.md.

## Summary

- **P0 (broken refs / sequence violations):** 1
- **P1 (count drift):** 3 (was 4 — P1-4 reclassified as informational on 2026-05-27 plan-mode investigation)
- **P1.5 (cloud-state bug):** 1 (was P2-2 — exercise_library empty broke `beat-my-coach`)
- **P2 (line/version drift / observations):** 3

All file paths in §7 pointer table verified present. All non-numeric file path claims in §0 (e.g. `lib/core/utils/ist_date.dart`, `supabase/functions/_shared/cron_telemetry.ts`, `scripts/validate_diagnose_doc.dart`) resolve cleanly. No broken `feedback_*.md` / `project_*.md` references in the body of CLAUDE.md (memory index has separate warning — see P2-3).

---

## P0 findings

### P0-1: Duplicate migration number `068` (sequence violation)

- **Where:** `supabase/migrations/`
- **Claim:** CLAUDE.md §0 says "Migration apply paired with `backups/applied_migrations.json` update in same commit" (§4.5) — implicitly assumes monotonic numbering scheme per `supabase/migrations/CLAUDE.md`.
- **Reality:** Two files share number 068:
  - `068_cron_call_log.sql` (applied in cloud as version `20260516121348` → name `068_cron_call_log_audit_2026_05_16`)
  - `068_drift_fix_batch.sql` (applied in cloud as version `20260525010726` → name `068_drift_fix_batch`)
- **Why it matters:** Two migrations with the same local number means `ls supabase/migrations/068_*` ambiguates, and any tool that keys on the prefix (e.g. naming/apply scripts) will mis-pair file → applied row.
- **Suggested fix:** Rename `068_drift_fix_batch.sql` → `068b_drift_fix_batch.sql` locally per the established `050b` precedent in `README_RECONCILIATION_2026-05-11.md` §E (cloud has already absorbed both — no apply re-run needed). Ledger entry already records `068b_drift_fix_batch`, so only the source-tree filename + the 4 doc references need updating. Document in next batch's commit. **[CLOSED 2026-05-27 in delightful-cascade batch.]**

---

## P1 findings

### P1-1: "46 tables" → live count is 47

- **Where:** CLAUDE.md §2 (line 129) **and** §7 pointer table (line 407)
- **Claim:**
  - L129: `| Database | Supabase Postgres (46 tables — backup + AI + community) |`
  - L407: `| Database schema (46 tables) | docs/architecture/database.md |`
- **Reality:** `SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'` → **47**.
- **Confirmation:** Memory entry `project_ecc_adoption_2026_05_24.md` already records the 47-table state. Drift originates in CLAUDE.md not being bumped alongside.
- **Suggested fix:** Change both occurrences from "46 tables" → "47 tables". Founder should also confirm `docs/architecture/database.md` lists all 47.

### P1-2: "5K DB" food_database claim vs 1,431 rows live

- **Where:** CLAUDE.md §3 (line 200) — Nutrition tab row.
- **Claim:** `food search (5K DB)`
- **Reality:** `SELECT count(*) FROM food_database` → **1,431** rows.
- **Why it matters:** This is the headline marketing/UX figure for the nutrition feature. Either the seed is undershipped (real bug) or the claim is stale aspirational copy (just docs). Both are P1.
- **Suggested fix:**
  1. Confirm with founder what the intended seeded size is.
  2. If 5K is intentional and 1,431 is a missing-seed bug, this becomes a real diagnose-doc (`030_seed_food_database` + `041_food_database_seed_v2_alter` migrations are applied, so seeding ran — count mismatch is suspicious).
  3. If 1,431 is the intended current state, update §3 to `food search (~1.4K DB)` or similar.

### P1-3: "41 canonical lenses" → registry has L1-L53

- **Where:** CLAUDE.md §4.8 + §7 pointer table (`docs/audit/LENS_REGISTRY.md (41 lenses)`).
- **Claim:** "41 canonical lenses" (referenced twice).
- **Reality:** `docs/audit/LENS_REGISTRY.md` contains numbered sections:
  - `L21-L25 — Surfaced by Hermes audit 2026-05-17`
  - `L26-L33 — From feedback_audit_methodology_lenses.md R1/R2 + this report`
  - `L34-L41 — New for next audit`
  - `L42-L53 — Added by tech-debt audit 2026-05-20 / Batch 1`
  - Total: **53 lenses** (L1-L53). L42-L53 were added during the 2026-05-20 B5 batch.
- **Suggested fix:** Change both occurrences from "41 canonical lenses" → "53 canonical lenses". Bonus: confirm L42-L53 are actually adopted (not just "added by") and not still in the "considered + rejected" bucket.

### P1-4 [DOWNGRADED → INFORMATIONAL]: `backups/applied_migrations.json` ledger has 77 entries — cloud has 67

> **Updated 2026-05-27 (plan-mode investigation):** Not actually drift. `supabase/migrations/README_RECONCILIATION_2026-05-11.md` already documents the delta as expected bookkeeping — Supabase Dashboard SQL editor renamed 13 migrations during apply (lost source-filename mapping in cloud), one early migration `add_gdpr_referral_community_tables` bundled what later became three split source files, and several seed migrations were applied as chunked deploys under a single prod row. Gate 39 (`check_applied_migrations_ledger.dart`) validates ledger SHAPE only, not parity — there is no silent failure. Leaving entry here for future-reader context.

- **Where:** CLAUDE.md §4.5 ("Migration apply paired with `backups/applied_migrations.json` update in same commit").
- **Claim:** Ledger ↔ cloud kept in lock-step.
- **Reality:**
  - `backups/applied_migrations.json` → 77 entries
  - `mcp__list_migrations` → 67 entries
  - Local migration files → 78 `.sql` files (plus README + CLAUDE.md + `all_migrations_combined.sql`)
- **Resolution:** No action. See `README_RECONCILIATION_2026-05-11.md` for the full table of expected mismatches.

---

## P2 findings (line / version drift / observations)

### P2-1: Ledger filename scheme split (legacy date-prefix vs sequential `0NN_`)

- **Where:** `supabase/migrations/`
- **Reality:** Mix of two schemes — `001_…` … `073_…` sequential, plus `20260328000001_video_renders.sql`, `20260330_create_promo_codes.sql`, `20260331000001_add_pgvector_memory.sql`, `all_migrations_combined.sql`. The MCP `list_migrations` output uses a *third* scheme: 14-digit timestamps that don't directly map to either filename style.
- **Suggested fix:** Document the three coexisting schemes in `supabase/migrations/CLAUDE.md` so future migrations don't drift further. Long-term: pick one. Not P1 because nothing's broken — just opaque.

### P2-2: `exercise_library` cloud table has 0 rows

- **Where:** Not a direct CLAUDE.md claim, but the table is named in §2a "Confirmed by" list. Memory (`project_data_architecture.md`) implies a populated exercise library.
- **Reality:** `SELECT count(*) FROM exercise_library` → **0**.
- **Why this might be intentional:** App is Hive-first; exercise library could live entirely in seed bundle + Hive. But §2 lists `exercise_library` among the 46 (now 47) cloud tables and §2a says it's "present" as proof of project identity. "Present" ≠ populated; if intentional, harmless.
- **Suggested fix:** Founder confirm: is cloud `exercise_library` deliberately empty (seed lives client-side only), or is this an undiscovered seed-pipeline bug? If intentional, add a `-- intentionally empty (seed is bundled in Hive)` note in `docs/architecture/database.md`.

### P2-3: MEMORY.md is 29.8KB — exceeds 24.4KB system limit

- **Where:** `C:\Users\upend\.claude\projects\C--Upendra-Claude-Code-Fitness-App\memory\MEMORY.md` (107 files indexed).
- **Reality:** System reminder at session start warned: "MEMORY.md is 29.8KB (limit: 24.4KB) — index entries are too long. Only part of it was loaded."
- **Why it matters:** Global rule: "If `MEMORY.md` exceeds ~200 lines, run `/consolidate-memory` or manually merge overlapping files before adding more." Currently silently truncated — recent index entries (project memories below the cutoff) won't be loaded in fresh sessions, defeating their purpose.
- **Suggested fix:** Run `/consolidate-memory` (skill `anthropic-skills:consolidate-memory` listed), OR shorten the per-line descriptions in the `## Project — recent batches` section (some entries are 6-line paragraphs disguised as one-liners).

### P2-4: ai-proxy live v67; latest memory entry references v66

- **Where:** Memory `project_apk_test_16_1_batch.md` references ai-proxy v65. `project_audit_2026_05_16_batch.md` references v66. CLAUDE.md itself does not pin a version (only historical v43 in §0).
- **Reality:** `list_edge_functions` → ai-proxy version **67**, ezbr_sha256 `9ac11175e54643d986aab37dd8ece1323dd005b81863a3dc2ee37b23d7d25491`, last updated 1779089011201 (2026-05-23).
- **Why it matters:** Within ±2 tolerance per skill rules — informational only. The v67 deploy isn't recorded in any visible memory file. If v67 was a side-effect deploy (e.g. Phase E rolls in #16.2 audit batch), that batch's retrospective should cite it.
- **Suggested fix:** Optional — if v67 isn't covered by an existing batch retro, add a one-line note when the next retrospective is written.

---

## Verified clean (no drift)

- All 28 file paths in §7 pointer table exist (sampled above).
- All `scripts/check_*.dart` paths referenced in §4 — Gate 18, 22, 23, 31, 40, 42, 47 — match present scripts.
- `lib/core/utils/ist_date.dart`, `supabase/functions/_shared/ist_date.ts`, `_shared/cron_telemetry.ts`, `docs/agent_brief_preamble.md`, `docs/naming_conventions.md`, `docs/sot_registry.yaml`, `docs/diagnoses/INDEX.md` all present.
- Project ID `dedsavbjuwgarrhphgnl` and OneSignal App ID `fd37a411-121e-4022-9929-2af68c2371f5` confirmed correct (queried tables match listed schema).
- 23 numbered coding rules in §4.4 — count matches (1-23).
- 12-tier multi-tier coverage protocol — count matches (§6 table has 12 rows).
- 8 skills present in `.claude/skills/`; 7 agents in `.claude/agents/`. CLAUDE.md does not pin counts, so no drift.
- 216 contract tests in `test/contracts/`. CLAUDE.md does not pin a count.

---

## Recommended next steps (founder approves)

1. **P0-1**: Renamed duplicate `068_drift_fix_batch.sql` → `068b_…` per the `050b` precedent. ✅ closed in delightful-cascade batch.
2. **P1-1**: Bump "46 tables" → "47 tables" in CLAUDE.md (two spots).
3. **P1-2**: Resolve "5K DB" vs 1,431-row reality — is it a bug or a docs lag?
4. **P1-3**: Bump "41 canonical lenses" → "53 canonical lenses" in §4.8 + §7.
5. **P1-4**: Reconcile `backups/applied_migrations.json` against cloud (77 vs 67) — Gate `check_applied_migrations_ledger.dart` may be reporting WARN.
6. **P2-3**: Run `/consolidate-memory` — MEMORY.md is past the loadable size.

Items P2-1, P2-2, P2-4 are informational; no immediate action required.
