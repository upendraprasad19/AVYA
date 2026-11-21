# CLAUDE.md Decluttering — Design Spec

**Date:** 2026-05-18
**Branch (planned):** `feat/claude-md-declutter`
**Status:** awaiting user review of this spec before implementation plan

## Goal

CLAUDE.md has grown to 1,481 lines / 220 KB / ~55K tokens, of which §19 "Common Bugs to Avoid" alone is 171 lines of historical narrative. The size now:

- Inflates every subagent dispatch's input by ~55K tokens (~$1/batch in pure context overhead).
- Dilutes signal-to-noise — agents miss rules that exist in the file (evidence: IST violations swept in Test #12 / Theme A despite the rule being codified).
- Causes maintenance friction — editing a 1,481-line file, frequent cache invalidations, entropy accretion (§19 grew from ~30 entries 12 months ago to ~100).
- Risks knowledge decay — stale entries reduce trust in the whole document.

Goal: restructure into a hybrid system where root CLAUDE.md is a thin invariants-only reference (~5K tokens) and detailed knowledge lives in per-feature nested CLAUDE.md files or in `docs/architecture/<topic>.md` files, fetched only when relevant.

## Non-goals

- No new automation gates beyond extending the existing `scripts/validate_diagnose_doc.dart`.
- No end-to-end smoke testing infrastructure (separate future spec).
- No memory linter / CI gate for memory files.
- No collapsing of `~/.claude/CLAUDE.md` (global rules) — out of scope.

## Approach: Test-as-doc + skeleton root (Approach B)

Lean on the existing `test/contracts/` corpus + `docs/sot_registry.yaml` + `docs/diagnoses/` as the actual rule-enforcement layer. CLAUDE.md becomes a thin pointer + invariants index; redundant prose that duplicates what tests already enforce gets deleted.

Trade-off accepted: small number of non-testable rules (process discipline, preferences) stay in root CLAUDE.md but go in a dedicated §3 "Process invariants" section that is first-class, not buried inside §19.

## Section 1: Target file map

### Root `CLAUDE.md` (target: ~280 lines, ~7K tokens)

```
## 0. Development commands           keep — load-bearing daily workflow
## 1. Project identity               keep — 6 lines
## 2. Tech stack                     keep, condensed — 12 lines
## 2a. Supabase project identity     KEEP VERBATIM — every byte critical
## 3. Process invariants             NEW — observation workflow, no-deferrals,
                                     build/commit/push gates, 23 coding rules,
                                     per-fix discipline gates
## 4. Per-batch maintenance protocol NEW — 10-node knowledge graph checklist
                                     (Section 3 of this spec)
## 5. Multi-tier coverage protocol   NEW — 12 tiers + touched_layers_checked
                                     YAML field (Section 4 of this spec)
## 6. Where to find detailed rules   NEW — pointer table to nested CLAUDE.md
                                     and docs/architecture topic files
```

§3 of new root makes discipline first-class. Subsections:

- 3.1 Observation / bugfix workflow (refs: `feedback_observation_workflow.md`, `feedback_source_of_truth_audit.md`, `feedback_writer_reader_field_drift_recurring.md`)
- 3.2 No-deferrals (refs: `feedback_no_deferrals.md`, `feedback_no_deferrals_recurrence.md`, `feedback_no_stop_until_done.md`)
- 3.3 Build / commit / push gates (refs: `feedback_apk_build_explicit_approval.md`, `feedback_main_is_source_of_truth.md`, `feedback_use_build_apk_skill.md`)
- 3.4 The 23 coding rules (condensed list, dropping items now redundant with 3.1-3.3)
- 3.5 Discipline gates per fix (diagnose-doc validator, migration apply pairing, IST throughout, SoT registry, pre-commit hook)

### Nested CLAUDE.md files (auto-loaded by Claude Code in subtree)

| Path | Source content (from current CLAUDE.md) |
|---|---|
| `lib/CLAUDE.md` | Cross-feature coding patterns: Hive-first, Riverpod-only, repository pattern, subscription.gate(), DM Sans, dark theme tokens |
| `lib/features/train/CLAUDE.md` | Active workout, swap, edit log, receipt rules + train-domain §19 entries |
| `lib/features/nutrition/CLAUDE.md` | Food logging, water, scan meal, AI breakdown rules + nutrition-domain §19 entries |
| `lib/features/home/CLAUDE.md` | Home cards, weight log, streak, freeze rules + home-domain §19 entries |
| `lib/features/ai_coach/CLAUDE.md` | AI coach chat, tool dispatcher, conversational log handler + ai-coach §19 entries |
| `lib/features/onboarding/CLAUDE.md` | Stepped onboarding flow (current §13a) + onboarding-domain §19 entries |
| `lib/features/auth/CLAUDE.md` | Auth, session, cross-account guard, RestoringScreen + auth §19 entries |
| `lib/core/services/CLAUDE.md` | WriteService rules, sync fan-out, restore-completeness (current §15) + service-domain §19 entries |
| `lib/shared/repositories/plan_engine/CLAUDE.md` | Plan generator V4 (current §12) + plan-domain §19 entries |
| `lib/shared/widgets/wardroom/CLAUDE.md` | Design system (current §9) + Wardroom primitive §19 entries |
| `supabase/functions/CLAUDE.md` | Edge Function deploy protocol, ai-proxy/ai-media-proxy rules + Edge-Function §19 entries |
| `supabase/migrations/CLAUDE.md` | Migration apply protocol + applied_migrations.json discipline + migration-domain §19 entries |

### `docs/architecture/` (cross-cutting concerns, explicit Read)

| Path | Source content |
|---|---|
| `docs/architecture/ai.md` | Current §11 in full (model matrix, 20 tools, proactive triggers, semantic retrieval, Captain manual) |
| `docs/architecture/sync.md` | Current §15 in full (SoT rules, Hive contracts, sync fan-out, restore-completeness) |
| `docs/architecture/database.md` | Current §7 expanded (46 tables, FK quirks, UNIQUE/CHECK constraints) |
| `docs/architecture/subscription.md` | Current §10 in full (PRO features, gate pattern, server verification, _highValueFeatures) |
| `docs/architecture/payment.md` | Current §16 in full (Razorpay flow + DPDP delete-account) |
| `docs/architecture/business-rules.md` | Current §14 (free/PRO matrix, calorie calculation) |

### `docs/playbook/`

| Path | Content |
|---|---|
| `docs/playbook/common-pitfalls.md` | §19 survivors that don't fit a specific feature or architecture topic (rare architectural lessons, cross-domain pitfalls) |

### Full section disposition table

Every current CLAUDE.md section's destination:

| Current section | Lines | Disposition |
|---|---|---|
| §0 Development commands | 100 | Stay in root (load-bearing daily workflow) |
| §1 Project identity | 6 | Stay in root |
| §2 Tech stack | 18 | Stay in root, condensed |
| §2a Supabase identity | 51 | Stay in root (verbatim, critical) |
| §3 Screens (5 tabs) | 10 | Stay in root (small + load-bearing for orientation) |
| §4 Data architecture | 55 | Move to `docs/architecture/sync.md` (intro/overview section) |
| §5 Directory structure | 85 | Move to `docs/reference/directory-structure.md` (already partially there) |
| §6 Coding rules (23) | 27 | Restructure into root §3 "Process invariants" — condense items now redundant with §3.1-§3.3 |
| §7 Database schema | 45 | Move to `docs/architecture/database.md` |
| §8 Logging types | 11 | Move to `lib/features/train/CLAUDE.md` (drives active workout UI) |
| §9 Design system | 122 | Move to `lib/shared/widgets/wardroom/CLAUDE.md` |
| §10 Subscription gate | 81 | Move to `docs/architecture/subscription.md` |
| §11 AI architecture | 166 | Move to `docs/architecture/ai.md` |
| §12 Plan generator | 81 | Move to `lib/shared/repositories/plan_engine/CLAUDE.md` |
| §13 Home screen layout | 20 | Move to `lib/features/home/CLAUDE.md` |
| §13a Onboarding | 121 | Move to `lib/features/onboarding/CLAUDE.md` |
| §14 Business rules | 45 | Move to `docs/architecture/business-rules.md` |
| §15 Sync schedule | 134 | Move to `docs/architecture/sync.md` (main body) |
| §16 Payment flow | 48 | Move to `docs/architecture/payment.md` |
| §17 Exercise library | 18 | Move to `docs/reference/exercise-library.md` |
| §18 Food database | 12 | Move to `docs/reference/food-database.md` |
| §19 Common bugs to avoid | 171 | Distributed via §19 prune protocol (Section 2 of this spec) |
| (new) §3 Process invariants | 0 | New — built from §6 + selected §19 class-C entries + memory feedback refs |
| (new) §4 Per-batch maintenance protocol | 0 | New — Section 3 of this spec |
| (new) §5 Multi-tier coverage protocol | 0 | New — Section 4 of this spec |
| (new) §6 Pointer index | 0 | New — table of contents pointing to nested CLAUDE.md and docs/architecture |

### Always-loaded context size estimate

| State | Always-loaded tokens |
|---|---|
| Current | ~55K (entire CLAUDE.md every session/dispatch) |
| Post-migration, no nested CLAUDE.md active | ~7K (root only) |
| Post-migration, 1 nested active (working in 1 feature) | ~7K + ~5K = ~12K |
| Post-migration, 3 nested active (cross-cutting fix) | ~7K + ~15K = ~22K |
| Post-migration, all 12 nested active (hypothetical worst case) | ~7K + ~60K = ~67K (slightly worse than current — but agents are normally not editing all 12 areas at once) |

Median expected reduction: ~4-5×.

## Section 2: §19 prune protocol

§19 has ~100 entries. Each gets one of 4 classifications.

### Classification matrix

| Class | Definition | Action |
|---|---|---|
| **A** | A test in `test/contracts/` enforces the rule AND the test pattern clearly maps to the entry | Delete entry. Test is the documentation. |
| **B** | Rule IS encodeable as a test but no test exists | Write the test first, then delete entry. |
| **C** | Process/preference or non-deterministic (not test-encodable) | Relocate to root §3, per-feature CLAUDE.md, or `docs/playbook/common-pitfalls.md`. |
| **D** | Historical / fixed long ago / regression impossible given current architecture | Delete outright. Useful for git blame but no future utility. |

### Audit + execution flow

Two-phase to keep rollback safe:

**Phase 1 (relocate-only):** classify every entry into `docs/superpowers/specs/2026-05-18-claude-md-declutter-audit.md`. Move class C content to its target file. §19 keeps `[MOVED to <path>]` markers — bigger file but no deletions. Commit at end.

**Phase 2 (test + destructive delete):** write tests for class B entries. Delete class A + class B + class D entries. Delete the `[MOVED to ...]` stubs. Delete the §19 section header entirely. Commit at end.

### Expected entry distribution

| Class | Estimated count | Disposition |
|---|---|---|
| A — test-covered | ~50-60 | Deleted |
| B — testable, no test | ~10-15 | Test written, deleted |
| C — non-testable | ~15-20 | Relocated |
| D — historical / stale | ~10-15 | Deleted |
| **Total §19** | ~100 | **§19 vanishes; knowledge preserved across tests + relocated docs** |

### Rollback plan

- Phase 1 is pure-add (relocations duplicate content; no deletions). `git revert` puts everything back.
- Phase 2 is destructive. Before merging Phase 2, the audit doc lists every deleted entry with its disposition (test path OR rationale). Anyone can audit the doc to verify nothing was silently lost.

## Section 3: Per-batch knowledge maintenance protocol

The user's knowledge graph has 11 substantive nodes (TodoWrite is in-session ephemeral; not counted). Every meaningful batch (bug fix, feature, audit) must consider each. "No update needed" is a valid answer — but the agent MUST consider each row.

### Node inventory

| # | Node | Location | Purpose | Update frequency |
|---|---|---|---|---|
| 1 | Diagnose-docs | `docs/diagnoses/<date>-<slug>-<id>.md` | One per bug fix; validated by `scripts/validate_diagnose_doc.dart` | Every bug fix. Rule §6 22 |
| 2 | Contract tests | `test/contracts/<topic>_test.dart` | Regression enforcement | Every bug fix. Rule §6 21 |
| 3 | SoT registry | `docs/sot_registry.yaml` | Canonical writer/reader concept registry | When a new SoT concept emerges or writer/reader file:line moves |
| 4 | Applied migrations record | `backups/applied_migrations.json` | Pair with every `apply_migration` MCP call | When a migration is applied. Rule `feedback_migration_apply_record_pair.md` |
| 5 | Root CLAUDE.md | `CLAUDE.md` | Non-negotiable rules + process invariants + pointer map | Only when a NEW non-negotiable invariant emerges. Most batches do not touch |
| 6 | Nested CLAUDE.md | `lib/<path>/CLAUDE.md` | Per-feature SoT writer/reader contracts + feature-specific invariants | When a feature's writer/reader contract changes |
| 7 | Architecture docs | `docs/architecture/<topic>.md` | Cross-cutting deep dives | When the cross-cutting topic itself changes (rare) |
| 8 | Memory feedback_*.md | `~/.claude/projects/<project>/memory/feedback_<topic>.md` | "Rules I learned the hard way." | When user CORRECTS a factual claim, OR same correction recurs 3× (consolidate) |
| 9 | Memory project_*.md | `~/.claude/projects/<project>/memory/project_<batch>.md` | End-of-significant-work retrospective | Every shipped batch |
| 10 | MEMORY.md index | `~/.claude/projects/<project>/memory/MEMORY.md` | Scannable index, ≤200 lines | Every memory file add. Consolidate when 3+ files overlap |
| 11 | Skills | `.claude/skills/<topic>/SKILL.md` | Project-local skills (debugging, custom protocols) | When a new bug class extends a skill's scope — skill self-evolution rule |

### Protocol codified in new root CLAUDE.md §4

```
## 4. Per-batch maintenance protocol

At the end of any batch that lands a commit, walk this checklist.
"No update needed" is a valid answer — the agent MUST consider each row.

[ ] Diagnose-doc written + validated (every bug fix; rule §3.5)
[ ] Contract test added + green (every bug fix; rule §3.5)
[ ] SoT registry updated if writer/reader file:line changed
[ ] applied_migrations.json updated if migration applied
[ ] Root CLAUDE.md: new non-negotiable invariant emerged? (rare)
[ ] Nested CLAUDE.md updated if feature contract changed
[ ] docs/architecture/<topic>.md updated if cross-cutting concept changed
[ ] feedback_*.md added/updated if user corrected a claim OR recurring class
[ ] project_*.md retrospective written (every shipped batch)
[ ] MEMORY.md index updated
[ ] Skill self-evolution: does any .claude/skills/<topic>/SKILL.md need
    a new bug-class entry, red flag, or trigger phrase?
```

### Skill self-evolution sub-rule

```
### 4.1 Skill self-evolution
After a batch that surfaced a new bug-class, red flag, or anti-pattern:
1. Check whether an existing skill's "Bug classes" or "Red flags"
   table covers it. If not, add an entry.
2. New entry cites: bug ID (from diagnose-doc) + one-line trigger
   description + regression test path.
3. Skill edits are committed in the SAME commit as the fix that
   discovered them — skill growth is traceable to its source.
4. New skills added under .claude/skills/<topic>/SKILL.md when 3+
   batches surface related patterns that don't fit an existing skill.
```

### Retrospective template extension

Every `project_*.md` retrospective gets a mandatory section:

```
## Knowledge nodes updated this batch:

| Node | Status |
|---|---|
| 1 Diagnose-docs | <count + paths>, or n/a |
| 2 Contract tests | <count + paths>, or n/a |
| 3 SoT registry | <updated entries>, or n/a |
| 4 Applied migrations | <migration number>, or n/a |
| 5 Root CLAUDE.md | <changed sections>, or no |
| 6 Nested CLAUDE.md | <paths>, or no |
| 7 Architecture docs | <paths>, or no |
| 8 feedback_*.md | <files>, or no |
| 9 project_*.md | <this file>, always yes |
| 10 MEMORY.md | yes/no |
| 11 Skills | <evolved skills>, or no |
```

## Section 4: Multi-tier coverage protocol

Today's batches tend to focus on the code tier and miss server-side / DB / Edge Function / cron / RLS / Storage / secrets tiers. Examples from recent memory:

- Today T4b (chat-media bucket privacy): would have surfaced via tier 9 (storage buckets) check before manual test if the protocol existed.
- Test #15.3 Bug 4a (template restore): tier 3 (schema) + tier 12 (client-server contract) — surfaced during fix, not before.
- Test #16.1 Vault drift on `morning_alert_deliver_early`: tier 7 (cron) + tier 10 (Vault secret) — known but deferred.
- `feedback_partial_unique_arbiter_trap.md`: tier 3 (partial UNIQUE arbiter) + tier 12 (PostgREST onConflict shape) — took 5 iterations to surface.

### The 12 tiers

| # | Tier | Examples of what breaks | How to check |
|---|---|---|---|
| 1 | Client code | Logic bug, render mismatch, state race | Read code, run tests, `flutter analyze` |
| 2 | Hive (local state) | Field rename drift, key collision, IST drift | Contract test, manual Hive inspection |
| 3 | Postgres schema | NULL vs NOT NULL, FK direction, missing UNIQUE/CHECK | `information_schema.columns`, `pg_constraint`, `pg_indexes` |
| 4 | Postgres data | Corrupted rows, stale defaults, migration backfill incomplete | Audit query on affected table |
| 5 | Migrations applied | Written but not applied; applied but not recorded in applied_migrations.json | MCP `list_migrations` vs `backups/applied_migrations.json` |
| 6 | Edge Function code vs deploy | Code edits committed but deployment forgotten; deployed version mismatched | API call: GET /functions/`slug` returns version field |
| 7 | Cron jobs | Vault secret drift, schedule misfire, body parameters wrong | Query `cron.job_run_details` last 24h for non-2xx |
| 8 | RLS policies | New column needs INSERT/SELECT policy update; service-role assumed | `pg_policies` query for affected table |
| 9 | Storage buckets + objects | Public vs private mismatch, MIME whitelist, size cap | `storage.buckets` + `storage.objects` queries |
| 10 | Secrets / API keys | Service role expired, Gemini key revoked, OneSignal rotated | Smoke test affected Edge Function; check Vault for `service_role_key` |
| 11 | External services | Razorpay webhook URL wrong, OneSignal app config, Firebase config | Manual dashboard check or status-page lookup |
| 12 | Client → server contract | Client sends shape X, server expects Y | Trace one full user flow end-to-end |

### The protocol — codified in new root CLAUDE.md §5

Every diagnose-doc adds a new YAML field:

```yaml
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "test/contracts/foo_test.dart passes" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "SELECT ... live audit 2026-05-18 confirmed CHECK constraint present" }
  - { tier: 9, name: storage_buckets, status: verified, evidence: "storage.buckets public=false; client uses createSignedUrl" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no edge function code changed" }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "parseStorageUrl accepts /sign/<bucket>/<path>?token=... (line 178)" }
```

Status values:
- `verified` — checked, confirmed correct.
- `fixed_in_this_batch` — was broken, fixed as part of this batch.
- `not_applicable` — tier isn't touched.
- `deferred` — known to need attention, explicitly out of scope (must cite follow-up bug ID or memory file).

### Validator rule

`scripts/validate_diagnose_doc.dart` extends to:

- Require `touched_layers_checked` field present in YAML frontmatter.
- Require at least 1 entry with status `verified` or `fixed_in_this_batch`.
- Reject if any entry has `status: deferred` without a corresponding follow-up reference (memory file or bug ID).

### Investigation subagent brief template

When dispatching a subagent to investigate a bug, the brief MUST include the 12-tier checklist verbatim:

```
Multi-tier investigation checklist — for each tier, confirm state OR
mark not-applicable:

1. Client code — file/line of writer/reader
2. Hive — field/key shape vs writer
3. Postgres schema — information_schema for affected columns/constraints
4. Postgres data — sample row to confirm shape
5. Migrations — applied_migrations.json vs supabase/migrations/*.sql
6. Edge Function deploy version vs git
7. Cron jobs — cron.job_run_details last 24h
8. RLS — pg_policies for affected table
9. Storage — buckets, objects for affected user
10. Secrets — does the Edge Function have the keys it needs?
11. External services — dashboard config matches expectation?
12. End-to-end contract — client shape vs server shape vs storage shape

Report findings as a YAML touched_layers_checked block (see
diagnose-doc validator format).
```

This roughly doubles investigation prompt size but eliminates the most-painful regression class.

## Section 5: Migration mechanics

### Branch + commit strategy

Single feature branch `feat/claude-md-declutter` off main-tip. 6 commits, each independently revertable.

| # | Commit name | Scope |
|---|---|---|
| 1 | `scaffold` | Create empty target files (12 nested CLAUDE.md + 6 docs/architecture + playbook). Each contains frontmatter only. Root untouched. |
| 2 | `relocate sections` | Move §§4-18 content to target files per the Section 1 disposition table (copy + breadcrumb in root). Root keeps `[MIGRATED to <path>]` stubs for the migrated sections; §6 (coding rules) and §0/§1/§2/§2a/§3 stay in place. |
| 3 | `§19 audit` | Classify every §19 entry into `docs/superpowers/specs/2026-05-18-claude-md-declutter-audit.md`. No code changes. |
| 4 | `§19 class B tests` | Write missing tests for testable §19 entries. Each test cites the audit doc row. |
| 5 | `§19 class C relocate` | Move non-testable entries to root §3 / nested CLAUDE.md / playbook. §19 keeps `[MOVED]` markers. |
| 6 | `root rewrite + cleanup + skill + bug-index + foolproofing` | Final destructive pass. Root rewritten into new structure (§3 discipline + §4 per-batch maintenance + §5 12-tier coverage + §6 pointer index). All `[MIGRATED]` / `[MOVED]` stubs deleted. §19 deleted entirely. Validator extension for `touched_layers_checked` + `recurrence` + `related_bugs` + `impact_analysis` lands here. `.claude/skills/update-docs/SKILL.md` + supporting `references/` files created per Section 6. `scripts/build_bug_index.dart` + initial `docs/diagnoses/INDEX.md` regen + pre-commit-hook lines for INDEX regen + naming-convention grep per Section 8 + Section 9. `scripts/check_regression_catalog.dart` + `scripts/capture_baseline.dart` + `scripts/compare_baseline.dart` per Section 9. |

### What's safe between commits

Between commits 1-5, root CLAUDE.md is BIGGER than it started (original content + breadcrumbs). An agent reading mid-migration sees the original rule PLUS the new location — zero risk of missing a rule. Only commit 6 makes destructive deletions.

### Validation gates per commit

| Commit | Gate |
|---|---|
| 1 | All new files exist, valid markdown |
| 2 | Every relocated section's target file passes `scripts/validate_markdown_links.dart` (new script — checks markdown link refs resolve) |
| 3 | Audit doc covers 100% of §19 entries (no `unknown` class) |
| 4 | New tests green; `flutter test test/contracts/` passes |
| 5 | Every `[MOVED]` marker resolves to a target path |
| 6 | `validate_diagnose_doc.dart` validates with new `touched_layers_checked` field on at least one existing doc (smoke test); `flutter analyze --no-fatal-infos` clean; full `flutter test` green |

### Rollback plan

- Commits 1-5 are pure additions / moves. Revert reverts cleanly.
- Commit 6 is destructive. If post-merge regression surfaces, the pre-commit-6 state is valid (just less polished). Revert commit 6 only.

### Pacing

Single session (4-6 hours), all 6 commits on the same day on feature branch. Merge to main after final review.

### Subagent dispatch strategy

- Commit 2: dispatch 1 subagent per section-to-relocate (parallel content moves). ~8 parallel agents.
- Commit 4: dispatch 1 subagent per class-B test to write. ~10 parallel agents.
- Otherwise: main thread executes.

Subagent briefs include the 12-tier checklist by default.

### Cross-reference update sweep

Root CLAUDE.md `§<N>` references appear in:

- `docs/diagnoses/*.md`
- `docs/sot_registry.yaml`
- `~/.claude/projects/<project>/memory/*.md`
- `scripts/*.dart` inline comments
- `lib/**` inline comments (rare)

One-shot grep + bulk-replace where the new path is unambiguous. Where ambiguous, leave the original `§<N>` reference (still works — root keeps the section heading with a pointer).

## Section 6: "Update-docs" workflow + project-local skill

In the new distributed system, "update docs" is no longer "append to CLAUDE.md §19". It's an 11-node knowledge-graph maintenance task. To prevent the agent from forgetting nodes (as today's batch demonstrated: SoT registry, feedback_*.md, skill self-evolution all missed), codify a one-command workflow.

### The /update-docs skill

**Location:** `.claude/skills/update-docs/SKILL.md`

**Trigger:** invoked manually by user at end of any meaningful batch via `/update-docs`. Also triggered by phrases "update docs", "wrap up docs", "finalize this batch's docs".

**Description (for skill frontmatter):**

```
---
name: update-docs
description: Walk the 11-node knowledge-graph maintenance protocol at end
  of a bug-fix or feature batch. Reads git diff main, populates the
  checklist with file-path → destination mappings, prompts per-node,
  writes the project_*.md retrospective.
---
```

### Mechanical flow

When invoked, the skill executes:

1. **Capture batch scope.** Run `git log main..HEAD --name-only` to list every file touched since branching from main. Also `git diff main --stat`.
2. **Read all diagnose-docs added this batch.** Glob `docs/diagnoses/<today>-*.md`. Extract `writers:` and `readers:` file paths from each YAML frontmatter.
3. **Compute file-path → destination mappings.** Using the table from Section 1 of this spec:
   - `lib/features/<x>/**` → `lib/features/<x>/CLAUDE.md`
   - `lib/core/services/**` → `lib/core/services/CLAUDE.md`
   - `supabase/functions/**` → `supabase/functions/CLAUDE.md`
   - etc.
   Plus cross-cutting detection: if 2+ feature areas touched, suggest `docs/architecture/<topic>.md` as additional target.
4. **Render the 11-node checklist** with pre-populated suggestions:

   ```
   Node 1 — Diagnose-docs:
     Found 4 new docs added this batch:
       - docs/diagnoses/2026-05-18-swap-snackbar-modal-stack-s1n4c0.md
       - docs/diagnoses/2026-05-18-weight-history-invalidate-race-w7r4c3.md
       - ...
     Validator status: all 4 pass scripts/validate_diagnose_doc.dart ✓
     [No action needed]

   Node 6 — Nested CLAUDE.md:
     Files touched in this batch suggest updates to:
       - lib/features/train/CLAUDE.md (swap snackbar pattern)
       - lib/features/home/CLAUDE.md (weight log awaitable, freeze clamp)
       - lib/features/ai_coach/CLAUDE.md (chat-media signed URL)
       - supabase/functions/CLAUDE.md (getProgressSummary Promise.all)
     [Per-file y/n prompt] — for each, ask: update? what to add?

   Node 8 — feedback_*.md:
     Detected pattern: TIMING drift sub-class of writer/reader drift
     (Bug w7r4c3 was the first instance).
     Existing memory: feedback_writer_reader_field_drift_recurring.md
     [Prompt] — append a paragraph about TIMING drift? y/n
   ```

5. **For each `[Prompt]` line:** ask user y/n + content. Apply the update or skip.

6. **Write the project_*.md retrospective.** Template:

   ```markdown
   # project_<batch_name>.md

   ## Summary

   <what shipped, branch, commit SHAs>

   ## Knowledge nodes updated this batch

   | Node | Status | Details |
   |---|---|---|
   | 1 Diagnose-docs | ✅ | 4 docs added (s1n4c0, w7r4c3, f8c1a5, t1m5b0) |
   | 2 Contract tests | ✅ | 8 tests under test/contracts/ |
   | 3 SoT registry | ✅ | weight_logs concept updated with awaitable pattern |
   | 4 applied_migrations.json | ✅ | "072" appended |
   | 5 Root CLAUDE.md | ❌ no change needed | |
   | 6 Nested CLAUDE.md | ✅ | 4 files updated (paths listed) |
   | 7 Architecture docs | ✅ | docs/architecture/ai.md (getProgressSummary), docs/architecture/sync.md (timing drift entry) |
   | 8 feedback_*.md | ✅ | feedback_writer_reader_field_drift_recurring.md extended |
   | 9 project_*.md | ✅ | this file |
   | 10 MEMORY.md | ✅ | index appended |
   | 11 Skills | ✅ | .claude/skills/debugging/SKILL.md §X added (timing drift) |

   ## Non-obvious decisions

   <bullets>

   ## Tried-and-rejected

   <bullets>

   ## Follow-ups deferred

   <bullets>
   ```

7. **Update MEMORY.md index.** Append a line under the appropriate section pointing to the new project_*.md.

8. **Print a summary** of all files touched + skipped nodes (so user can audit at a glance).

### Skill file structure (sketch — full implementation lands in commit 6 of the migration plan)

```
.claude/skills/update-docs/
├── SKILL.md                  ← main protocol document
├── references/
│   ├── path-mappings.md      ← file-path → CLAUDE.md destination table
│   ├── retrospective-template.md   ← project_*.md template
│   └── eleven-node-checklist.md    ← canonical 11-node list
```

The skill itself is just a markdown document with sections that the agent reads top-to-bottom and executes. No code; just structured instructions for the agent to follow.

### Why a skill rather than just a section in CLAUDE.md

- **Discoverability**: `/update-docs` is one keystroke for the user. The protocol auto-loads.
- **Self-evolution**: when a new node gets added to the knowledge graph (e.g., a future migration adds a 12th node), update the skill — every future invocation picks it up immediately.
- **Composability**: the skill can invoke other skills (e.g., `superpowers:consolidate-memory` when MEMORY.md exceeds 200 lines).
- **Versioning**: skill changes are visible in `.claude/skills/` commits — easy to audit how the protocol evolved.

### Cost

- Skill creation: ~2 hours (part of commit 6 of the migration plan).
- Per-invocation cost: ~3-5 min of dialog at end of session. Trades for: zero missed nodes, zero memory entropy.
- Today's batch demonstrates the cost of NOT having it: 5 of 11 nodes silently missed.

### Risk

- The skill's path-mapping table can go stale if new feature directories are added. Mitigation: include the path-mapping table in Section 1 of this spec as the canonical reference, and have the skill reference it.

## Section 7: Validation + measurement

### How we know it worked

1. **Token count**: `wc -c CLAUDE.md` before vs after. Target: ~30 KB / ~7K tokens.
2. **Rule discoverability**: spot-check 5 critical rules from each of §3.1-3.5 — can a fresh agent find them via root + pointers? Yes/no.
3. **Subagent dispatch latency**: time a representative subagent dispatch before vs after. Target: noticeable improvement on cold cache.
4. **Knowledge integrity**: every pre-migration rule has either (a) a passing contract test, (b) a memory feedback file, (c) a nested CLAUDE.md entry, or (d) an architecture doc entry. Tracked via the audit doc.

### Post-migration smoke test

Pick the next batch you actually do (any feature or bug fix). Walk the per-batch maintenance protocol (Section 3) end-to-end. If any node is unclear which file to update, the spec needs refinement.

### Maintenance going forward

The decluttering is one-shot; the per-batch maintenance protocol (Section 3) is forever. The audit doc from commit 3 stays in `docs/superpowers/specs/` as a permanent record of what was relocated where.

## Section 8: Bug-history index + recurrence-lookup workflow

You already have the raw data (every diagnose-doc has YAML frontmatter with `concept`, `symptom`, `sot_registry_entry`, `writers`, `readers`, `contract_test_path`). What's missing is (a) a searchable index over that corpus, and (b) a workflow step that forces a "did we fix this before?" lookup at the start of every investigation.

### Auto-generated `docs/diagnoses/INDEX.md`

Built by new `scripts/build_bug_index.dart`. Walks every `docs/diagnoses/*.md`, extracts YAML frontmatter, emits a multi-cut index:

- **By recurrence class** — bugs grouped under the matching `feedback_*.md` memory file (writer/reader drift, IST sweep gap, etc.). Each class includes the instance count. When count reaches 3, the script prompts: "consider creating a feedback_*.md if one doesn't exist."
- **By concept** (`sot_registry_entry` field) — bugs grouped by the canonical concept they touched.
- **By feature directory** — derived from `writers:` / `readers:` file paths (e.g., `lib/features/train/**` → "train" bucket).
- **Chronological** — flat table latest-first with one-line symptom + test path.

The file is regenerated, never hand-edited. Tracked in git so `git log docs/diagnoses/INDEX.md` shows how the bug corpus has grown over time.

### Diagnose-doc YAML extensions

```yaml
related_bugs:
  - { bug_id: a8f1c2, relation: same_class, note: "Both writer/reader drift, but a8f1c2 was field-rename, this is timing" }
  - { bug_id: w7r4c3, relation: same_concept, note: "Both touch weight_logs" }
recurrence:
  class: writer_reader_drift
  instance_number: 8
  prior_instance_lessons: |
    Past instances were all field-rename fixes. This timing sub-class
    needs a different fix shape — async signature change, not field
    rename. See feedback_writer_reader_field_drift_recurring.md.
```

- `related_bugs:` is optional (use when there's a meaningful cross-reference).
- `recurrence:` is REQUIRED if `concept:` or `class` matches an existing `feedback_*.md` file. The validator enforces this — see below.

### Validator extension

`scripts/validate_diagnose_doc.dart` adds:

- For every `concept:` value, look up the corresponding entries in `docs/sot_registry.yaml`. Warn if concept isn't in registry (catches typos that fracture the index).
- If a `feedback_<class>_recurring.md` memory file exists matching the diagnose-doc's class, require the `recurrence:` field with `instance_number` ≥ 1 and `prior_instance_lessons` non-empty.
- For each `related_bugs[].bug_id`, verify the referenced diagnose-doc exists.

### Investigation-workflow extension (new step in root CLAUDE.md §3.1)

```
3.1.5 Bug-history lookup (BEFORE proposing root cause)
  After observations are captured and BEFORE brainstorming root causes:

  1. Grep docs/diagnoses/INDEX.md for matching:
     - symptom keywords
     - concept (if known from initial triage)
     - file paths (if the bug is in a specific module)

  2. Read every matching diagnose-doc — what was the root cause, what fixed it.

  3. Check feedback_*.md files matching the recurrence class.

  4. If this looks like a recurrence:
     - Note instance number in the new diagnose-doc's `recurrence:` block.
     - Cite prior instances in `related_bugs:`.
     - Apply the class's known-good fix pattern.
     - If the class has a known-failed pattern, mark it explicitly:
       "tried in instance N — failed because Y."

  5. If this DOESN'T look like a recurrence: note that in the diagnose-doc
     so future audits can verify (and create a new feedback_*.md if a
     3rd instance ever appears).
```

### Pre-commit hook integration

`scripts/pre-commit.sh` extends with:

```bash
# Regen bug index if any diagnose-doc was modified
if git diff --cached --name-only | grep -q '^docs/diagnoses/'; then
  dart run scripts/build_bug_index.dart
  git add docs/diagnoses/INDEX.md
fi
```

Pre-commit always sees a fresh INDEX.md when the underlying docs change. Zero manual regen burden.

### Integration with /update-docs skill (Section 6)

The `/update-docs` skill (Section 6 of this spec) invokes `build_bug_index.dart` as part of its workflow. Same regen, same output. The pre-commit hook is the defense-in-depth — catches anyone who skips `/update-docs`.

### Cost

- `build_bug_index.dart`: ~2 hours one-shot to write.
- Validator extension: ~30 minutes.
- Pre-commit hook addition: ~10 minutes.
- INDEX.md regen per batch: ~5 seconds.
- New investigation-workflow step (3.1.5): ~5-10 min added per bug investigation. Trades for avoiding repeat-fix-attempts and surfacing recurrence patterns earlier.

### What this prevents (concrete recent examples)

| Past batch | What we did | What lookup would have shown |
|---|---|---|
| Today's T2 (weight count race) | 2 subagent dispatches before identifying the timing race | Prior writer/reader drift instances in INDEX would have surfaced the class; `feedback_writer_reader_field_drift_recurring.md` would have shown the diagnostic pattern. Investigation time: ~5 min instead of ~30 min. |
| Test #16.1 Theme A | 4 parallel agents to find 3 rogue exlog_* key formulas | The 7th writer/reader drift instance — the feedback file already had the audit pattern; just needed to consult it before dispatching subagents. |
| `feedback_partial_unique_arbiter_trap.md` | 5 iterations to discover writer→DB-target sub-class | A "writer_reader_drift" search in INDEX would have shown the prior 4 instances; the 5th could have applied known patterns sooner. |
| Future "AI photo failed" (T4b style) | Today: required deep investigation across client + Edge Function + Storage | Tomorrow: INDEX lookup for "storage" or "photo" surfaces today's t1m5b0 + the `feedback_*.md` if we create one for "bucket privacy mismatch" class. |

### Risk

- Concept-name drift: if `concept:` values vary slightly between diagnose-docs (e.g., `weight_logs` vs `weight_logging`), the index groups them separately. Mitigation: validator warns when concept isn't in `docs/sot_registry.yaml`'s concept list.
- Build-script staleness: if a diagnose-doc's frontmatter changes after INDEX is built, INDEX is wrong until next regen. Mitigation: pre-commit hook + `/update-docs` skill both regen.

## Section 9: Regression + foolproofing protocols

Section 4 (12-tier coverage) prevents the "code-only" blind spot. Section 9 prevents the **regression blind spot** — i.e. "I changed function X to fix bug Y, but function X had 3 other callers that broke silently." Plus, surfaces existing protocols that are currently buried in the codebase.

### 9.1 Impact-analysis protocol (NEW)

Before changing a load-bearing function or public contract:

1. List every caller via `Grep`. Cite file:line for each.
2. For each caller, identify the behavior it depends on (return-value semantics, sync/async timing, side effects).
3. Verify the change preserves that behavior OR explicitly note "caller N needs updating in same batch."

New diagnose-doc YAML field:

```yaml
impact_analysis:
  callers_audited:
    - { file: lib/features/X/foo.dart, line: 123, depends_on: "non-null return when condition Y" }
    - { file: lib/features/Y/bar.dart, line: 456, depends_on: "synchronous completion before next call" }
  callers_updated_in_this_batch: [<file:line list>]
  callers_unchanged: [<file:line list>]
```

`scripts/validate_diagnose_doc.dart` extension: if the diagnose-doc's `writers:` field references a function with >1 caller (detected via grep across `lib/`), require `impact_analysis:` field with non-empty `callers_audited:`.

### 9.2 Pre-merge regression catalog walk (NEW)

Before merging any batch to main, automated check verifies:

- Every bug class from the last 30 days (per `docs/diagnoses/INDEX.md`) still has its regression test green.
- No regression test was deleted in this batch.
- No test was newly-skipped in this batch (or skip has explicit justification in commit message).

New script: `scripts/check_regression_catalog.dart`. Invoked from `scripts/pre-commit.sh` when the commit is a merge to main OR via `--pre-merge` flag.

### 9.3 Pre-batch baseline capture (NEW)

At start of any batch:

1. `flutter test --reporter json` → `baseline.json`.
2. `flutter analyze --no-fatal-infos` lint count → `baseline-lints.json`.

At end of batch, compare:

- Newly-failing tests → blocker (must fix or explicitly document).
- Newly-skipped tests → require justification in batch commit message.
- Lint count increased → require justification.

New scripts: `scripts/capture_baseline.dart` (start-of-batch) + `scripts/compare_baseline.dart` (end-of-batch). Invoked manually OR via `/update-docs` skill (Section 6).

Baseline files are git-ignored (in `.gitignore`) — they're per-session ephemera, not part of the repo.

### 9.4 Feature-flag protocol for risky changes (NEW)

When introducing a change to a production-critical path (payment, sync, auth, AI prompt, plan generator):

1. Default the new code path behind a `kDebugMode` gate OR a Hive flag (`configBox['feature_<name>_enabled']`) OR a per-user RemoteConfig flag.
2. New path is exercised only when the gate is open. Old path preserved verbatim, reachable when gate is closed.
3. Roll the gate to "on" only after manual verification.
4. Once rolled to on and verified, the old path can be deleted in a follow-up batch.

Codified in root CLAUDE.md §3.6.

### 9.5 Naming-convention protocol (SURFACING EXISTING)

Before introducing any new file, symbol, Hive key, cloud column, or Edge Function name:

1. Read `docs/naming_conventions.md` (already in codebase).
2. Check the reserved-domain glossary.
3. If introducing a new domain term, append it to the glossary.

Pre-commit hook extension: greps changed files for new symbols matching the anti-patterns enumerated in `naming_conventions.md`. Today this protocol exists but is only referenced from old §5 directory-structure — promoting to root §3 makes it discoverable.

### 9.6 Subagent brief preamble (SURFACING EXISTING)

`docs/agent_brief_preamble.md` is the canonical prefix for every subagent investigation brief, per CLAUDE.md rule §6 22. The preamble includes:

- The 12-tier checklist (Section 4 of this spec).
- The bug-history lookup step (Section 8).
- References to relevant `feedback_*.md` memory files.

Every subagent dispatch MUST prepend this preamble to the task-specific brief. Promoted from rule §6 22 to root §3 of new CLAUDE.md for discoverability.

### 9.7 Audit lens registry (SURFACING EXISTING)

`docs/audit/LENS_REGISTRY.md` (added during Hermes audit) lists 41 canonical audit lenses. When invoking review or audit work (Master audit, Hermes-style pass, multi-agent review), specify which lenses are in scope. Prevents the "we just look at code" audit blind spot.

Today this exists but isn't surfaced in CLAUDE.md. Promoted to root §3.

### 9.8 Cron telemetry helper (SURFACING EXISTING)

Every cron-dispatched Edge Function MUST use `_shared/cron_telemetry.ts` (added Test #16.1) per the adoption gate test `test/contracts/cron_telemetry_adoption_test.dart`. Without this, cron-job failures are invisible in `client_errors` (no telemetry surface).

Today this exists but isn't surfaced in CLAUDE.md. Promoted to root §3 (specifically the §3.5 discipline gates subsection).

### Cost summary

| Sub-protocol | One-shot cost | Per-batch cost |
|---|---|---|
| 9.1 Impact analysis | ~30 min (validator extension) | ~5-10 min per fix |
| 9.2 Regression catalog walk | ~2 hours (script) | ~1 min on merge |
| 9.3 Baseline capture | ~2 hours (scripts) | ~2 min start + 30s end |
| 9.4 Feature-flag | 0 (protocol only) | varies by change |
| 9.5 Naming check | ~30 min (pre-commit grep) | trivial |
| 9.6 Agent brief preamble | 0 (existing) | 0 |
| 9.7 Audit lens registry | 0 (existing) | applies only during audits |
| 9.8 Cron telemetry | 0 (existing) | applies only when adding cron functions |

Total one-shot: ~5 hours. Per-batch: ~10-15 minutes added discipline overhead.

### What this prevents (worked examples)

| Past regression | Protocol that would have caught it |
|---|---|
| Test #8 Theme D AI snapshot drift (~10 days unnoticed) | 9.1 — `ai_coach_repository` writers changed; snapshot readers were callers that depended on field names. Impact analysis flags the 4 readers. |
| Today's T2 weight race | 9.1 — when `WeightLogNotifier.logWeight` became `unawaited()`-fire-and-forget, WeightLogSheet caller depended on synchronous completion. Impact analysis catches the caller. |
| Test #11 L1 AI breakdown card "disappears on save" | 9.3 — pre-batch baseline shows save-action test passed; post-batch no test exercises the "card visible after save" UI path. Surfaces the coverage gap. |
| Hypothetical future cron with no telemetry | 9.8 — cron telemetry adoption test fails at pre-commit; agent forced to use `_shared/cron_telemetry.ts`. |
| Hypothetical "we forgot we already have docs/naming_conventions.md" | 9.5 — promotion to root §3 makes it impossible to miss. |

### Risk

- Adds friction to every bug fix (~10-15 min overhead). Mitigation: invoked via `/update-docs` skill (Section 6) so most of the discipline runs automated.
- 9.1 impact-analysis can produce false-positive flags if a function has many trivial callers. Mitigation: validator extension warns rather than blocks — agent can mark callers as "trivial passthrough, no behavior dependency."

## Open questions before implementation

None — all eight sections + supporting scaffolding approved during brainstorm.

## Approval

Awaiting user review of this spec file. After approval, the `superpowers:writing-plans` skill builds the implementation plan.
