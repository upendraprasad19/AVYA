---
name: debugging
description: Apply this skill when a bug is reported or suspected. Enforces diagnose-first, recall-prior-fixes-second, propose-third, fix-fourth. Self-evolving — append learnings on every use.
type: process
priority: high
self-evolving: true
---

# Debugging Skill — ICANBEFITTER

> Tribal knowledge codified. This skill is the canonical methodology for every bug investigation on this codebase. Self-evolving: every session that surfaces a NEW bug class, methodology refinement, or red flag MUST append to this file before the session is marked complete.

---

## 0. When to invoke

- A bug is reported by the founder or surfaces in telemetry (`client_errors`, Crashlytics, cron 401s, etc.).
- An APK observation arrives mentioning UI mismatch, missing data, stale state, "didn't save," "wrong account data."
- A test failure on `main` (per CLAUDE.md rule 20, these are P0).
- Suspected regression of a previously-fixed class.

If the founder asks to "fix everything" or batches multiple observations, run this skill per-observation and aggregate.

---

## 1. Methodology — six-step checklist (DO NOT SKIP STEPS)

### Step 1 — WAIT for all observations / reproduce

- If the founder is mid-flow ("more obs coming"), DO NOT start fixing. Collect the full batch.
  - Source: `feedback_observation_workflow.md`, `feedback_no_deferrals.md`.
- Reproduce locally if possible — Flutter test, integration test, or by reading the exact code path.
- If you cannot reproduce, write down the precise environment (cold-start vs hot, signed-in user identity, IST time-of-day, free vs PRO).

### Step 2 — Identify writer(s) AND reader(s) by file:line

For any "UI says X but data says Y" / "saved but didn't appear" / "wrong value rendered" bug, the FIRST artifact you produce is a writer/reader map:

```
Writer:  lib/path/file.dart:LINE  (function/method name)
Readers: lib/path/file.dart:LINE  (every consumer of the field)
         lib/path/file.dart:LINE
         supabase/functions/<fn>/index.ts:LINE  (cloud consumers count)
```

- Patching only the reader (or only the writer) is the recurring anti-pattern. Source: `feedback_source_of_truth_audit.md`, `feedback_writer_reader_field_drift_recurring.md`.
- Cross-reference `docs/sot_registry.yaml` for known single-source-of-truth concepts; if the bug touches one of them, the registry already enumerates the contract you must honor.

### Step 3 — Recall prior fixes for the same class

Before proposing ANY fix, grep memory + project retrospectives:

```
Grep MEMORY.md (~/.claude/projects/.../memory/) for feedback_* files matching the symptom
Grep memory/ for project_apk_test_*.md retrospectives — same class likely shipped before
Grep CLAUDE.md §19 "COMMON BUGS TO AVOID" table for an exact-match entry
```

- If a prior incident matches: read its diagnose-doc (`docs/diagnoses/`), its regression test (`test/contracts/` or equivalent), and the fix commit. The bug may be a regression of THAT fix.
- If you find a prior fix and propose to "reuse the same pattern," verify the file:line citations still exist (memory is point-in-time per CLAUDE.md user rules).

### Step 4 — Verify schema + code claims with TOOLS, not prose

- Schema claims (column exists, FK direction, UNIQUE constraint, default value): query LIVE via Supabase MCP `execute_sql` against `information_schema.columns`, `pg_indexes`, `pg_constraint`. NEVER trust subagent prose or memory recall alone. Source: `feedback_audit_findings_require_live_verification.md`, `feedback_mistake_restore_window.md`.
- Code claims (line numbers, function bodies, conditional branches): use `Read` or `Grep` directly on the cited file. Subagents hallucinate constants — verify before citing.
- Cite the verification SQL / file:line in the diagnose-doc so the next person can re-run it cheaply.

### Step 5 — Propose plan; founder reviews; then code

- Output: a numbered plan with (a) writer/reader map, (b) prior-fix references, (c) verification queries run + results, (d) proposed code change scoped per file, (e) regression test plan, (f) diagnose-doc id to allocate.
- Wait for explicit approval per `feedback_approval_gate.md` (at least one round of review).
- Only AFTER approval: Edit / Write code. Source: `feedback_observation_workflow.md`.

### Step 6 — Every fix ships with

Per CLAUDE.md rules 21 + 22:
1. **Diagnose-doc** at `docs/diagnoses/<date>-<slug>-<6hex>.md` (validated by `dart run scripts/validate_diagnose_doc.dart`).
2. **Regression test** under `test/contracts/`, `test/<service>/`, or alongside the fix that FAILS on `main` without the fix and PASSES with it.
3. **Memory-file update** if the bug is a NEW class, a NEW methodology refinement, or a NEW recurring mistake. Append to existing `feedback_mistake_*.md` if the class already has one.
4. **CLAUDE.md update** to §19 "COMMON BUGS TO AVOID" only if the bug introduces a new invariant the codebase must enforce forever.
5. **This skill file** updated per §5 self-evolution rule below.

---

## 2. Bug class catalog (seeded — append on each new class)

### 2.1 Writer/reader field drift
- **Telltale:** "Saved but doesn't appear" / "Receipt shows 0 sets" / "AI snapshot misses meals." Hive write path uses field name A; consumer reads field name B (or same name with different semantic — e.g. cumulative-vs-first-set).
- **Root-cause shape:** WriteService rewrite renames field; some consumers updated, others linger on legacy name. OR: field semantics change (per-set → sum) without renaming, so type checks pass but values lie.
- **Fix pattern:** Dual-name reader (`map['new'] ?? map['legacy']`); contract test in `test/contracts/<x>_write_to_read_contract_test.dart` pinning SEMANTICS not just presence; sweep all consumers in same PR.
- **Prior incidents:** Tests #6, #7, #8 (`project_apk_test_8_batch.md`), #12 Theme E (`project_apk_test_12_batch.md`), #15.3 Bugs 1/6/7 (`project_apk_test_15_3_batch.md`). See `feedback_writer_reader_field_drift_recurring.md`.

### 2.2 IST date-key drift
- **Telltale:** Counter resets at midnight UTC instead of midnight IST; receipt for May 5 contains May 4 exercises; row written under "today" appears under "yesterday" between IST 00:00–05:30.
- **Root-cause shape:** Code uses `DateTime.now().toIso8601String().substring(0, 10)` (UTC) or `date.year/.month/.day` (local) instead of `istDateStr(date)`. OR: double-shift by passing `istNow()` into `istDateStr` (which already shifts).
- **Fix pattern:** Route every date-key helper through `lib/core/utils/ist_date.dart` (client) or `supabase/functions/_shared/ist_date.ts` (Edge). Pass raw `DateTime.now()` to `istDateStr` — never `istNow()`. Contract test asserts UTC late-evening input → next-IST-day output.
- **Prior incidents:** Test #11 B1+B2+M3 (`project_apk_test_11_batch.md`), Test #11.1 (istDateStr double-shift), Test #12 Task A-1 `formatDateKey` UTC bug (`project_apk_test_12_batch.md`). See `feedback_use_ist_throughout.md`, `feedback_ist_sweep_gap.md`.

### 2.3 Cross-account Riverpod / Hive cache race
- **Telltale:** After signOut + signUp on same session, Edit Profile shows previous user's data; UI surfaces stale rank/streak/templates from the prior account.
- **Root-cause shape:** Riverpod Notifier `build()` reads Hive once and caches; auth-token re-emits before `HiveUserSession.openForUser(newUid)` awaits complete; provider rebuilds against previous owner's namespaced box.
- **Fix pattern:** Two-layer — (a) `authUserIdTokenProvider` returns `'<anon>'` while authUid disagrees with `HiveUserSession.currentOwnerFullId`; (b) `wrapUserScopedBox` returns `GuardedBox.empty(authUid)` on disagreement. Every user-scoped provider `ref.watch(authUserIdTokenProvider)` as first line of `build()`. Source-grep contract test walks `lib/features/*/providers/` for non-watchers.
- **Prior incidents:** Test #15.3 Bug 5 (`c4055a`), Test #15.4 B1 (`project_apk_test_15_4_batch.md`).

### 2.4 Partial unique index `ON CONFLICT` trap (two failure modes)
- **Telltale (mode A — 23505):** `PostgrestException 23505 unique_violation` on writes that should be idempotent; orphaned child rows (per-set / per-item) without parents.
- **Telltale (mode B — 42P10):** `PostgrestException 42P10 "there is no unique or exclusion constraint matching the ON CONFLICT specification"` on EVERY write that should use a natural-key arbiter. Zero rows reach cloud silently.
- **Root-cause shape (A):** `upsert(..., onConflict: 'id')` translates to `ON CONFLICT (id) DO UPDATE`. PostgreSQL still evaluates EVERY unique constraint; a different partial UNIQUE trips first → 23505 instead of merge.
- **Root-cause shape (B):** `upsert(..., onConflict: '<natural-key columns>')` targets a partial UNIQUE index (`WHERE col IS NOT NULL AND ...`). PostgreSQL requires the partial predicate to be STATICALLY provable from the row's NOT NULL column constraints. If even one arbiter column is NULLABLE, the planner refuses the partial index as arbiter → 42P10. **Source-grep contract tests miss this because they pin the onConflict string, not the runtime arbiter behavior.**
- **Fix pattern (A):** Switch `onConflict` to the natural-key column list.
- **Fix pattern (B):** Two layers — (1) schema migration: backfill NULL columns with writer-contract-aligned defaults → `ALTER COLUMN ... SET NOT NULL` → `DROP INDEX` partial → `CREATE UNIQUE INDEX` non-partial; (2) client guard: skip the upsert + emit `sync_skipped_null_natural_key` telemetry if any natural-key column is null. Pin via `test/contracts/sync_natural_key_guard_test.dart` AND the **live-arbiter scaffold** at `test/sql/onconflict_live_arbiter.sql` + `scripts/check_onconflict_live_arbiter.dart` which runs `INSERT ... ON CONFLICT` in a rollback transaction against the live schema. Wire into `/build-apk` Gate set after one round of CI green.
- **Class rule (NEW 2026-05-15):** any partial UNIQUE index intended to back `ON CONFLICT` MUST have all arbiter columns `NOT NULL`, OR the index MUST be non-partial. Verify via the live-arbiter scaffold before merging the onConflict change.
- **Prior incidents:** Audit 2026-05-12 P0-A/P0-B (mode A — `project_audit_2026_05_12.md`); APK Test #16 (mode B — `project_apk_test_16_batch.md`, diagnose `76c8f4` + `9f4ab2` + `25e91d`). See `feedback_partial_unique_arbiter_trap.md`.

### 2.5 Edge Function cold-start retry budget
- **Telltale:** "AI is temporarily unavailable" / generic 502/503/504 within seconds of an idle period; works on retry.
- **Root-cause shape:** Supabase Edge Function cold-start can exceed any single-attempt timeout (logged 6-7s execution_time on 2026-05-15 ai-proxy 502s). Client retries at undersized backoff → user sees failure. Direct-HTTP fallbacks (`_directHttpCall`, `_directMediaHttpCall`) often bypass the retry helper entirely.
- **Fix pattern:** `retryColdStart` helper in `lib/core/services/supabase_service.dart` with schedule `[2000, 6000, 12000]` ms (3 retries, ~20s window — bumped from `[1500, 4000]` in APK Test #16 after live evidence). Retry-trigger status set: 502 + 503 + 504 (not 500). Wrap BOTH `client.functions.invoke` callsites AND raw `http.post` direct-HTTP fallbacks via `_retryHttpColdStart` helper. Emit `ErrorTelemetry.logEvent('edge_function_cold_start_retry', ...)` per attempt. 401-recursion guard preserved.
- **Prior incidents:** Test #15.3 Bug 2 (`7c4e1a`); APK Test #16 (`c01d57` — schedule bump + ai-media-proxy wiring).

### 2.6 Vault service-role-key for cron auth
- **Telltale:** Cron jobs send `Authorization: Bearer null` → 401 on every tick; `cron.job_run_details` reports "succeeded" (because `net.http_post` dispatched), but Edge Function gateway logs 401.
- **Root-cause shape:** `private.morning_alert_get_service_key()` reads `vault.decrypted_secrets WHERE name='service_role_key'`; Vault row never populated.
- **Fix pattern:** Dashboard → Settings → Vault → add secret named exactly `service_role_key` with the service_role JWT. New cron jobs MUST resolve via `private.morning_alert_get_service_key()` — never hardcode the anon JWT. Verify via test invocation.
- **Prior incidents:** Audit 2026-05-12 Vault fix (`project_audit_2026_05_12.md`).

### 2.7 Android Auto-Backup leak across accounts
- **Telltale:** Fresh sign-up sees previous user's templates / Hive data / PRO status / renewal date on the same Google account's device.
- **Root-cause shape:** Android Auto Backup default-enabled (no `data_extraction_rules.xml`). Hive `.hive` files in `app_flutter/` get backed up to Google Drive and restored on reinstall.
- **Fix pattern:** `android/app/src/main/res/xml/data_extraction_rules.xml` excludes `app_flutter/`. Splash-time guard: if `userBox['profile']['id']` ≠ `currentUser.id`, wipe Hive + signOut. `isPro()` runs Hive-profile.id vs session.id check on every call. `_downgradeLocally` wipes `_expiresAtKey`/`_planKey`/`localActivationAt`/`_lastVerifiedKey` not just `_isProKey`. All 3 layers required.
- **Prior incidents:** `project_2026-04-24_design_bug_batch.md`.

### 2.8 Migration-record pair gap (`applied_migrations.json`)
- **Telltale:** Pre-commit hook fails or `/build-apk` Gate 14 blocks; migration exists in `supabase/migrations/` but `backups/applied_migrations.json` doesn't list it.
- **Root-cause shape:** Supabase MCP `apply_migration` call not paired with a `backups/applied_migrations.json` update in the same commit.
- **Fix pattern:** Every `apply_migration` MCP call → update `backups/applied_migrations.json` in the SAME commit. Codified by `feedback_migration_apply_record_pair.md`.
- **Prior incidents:** Audit 2026-05-12 migration 061.

### 2.9 Subagent numeric-claim hallucination
- **Telltale:** A subagent investigation report cites "30/90-day restore window" / "line 47 has X" / "trigger fires at 23:00 UTC" — but the actual code says otherwise.
- **Root-cause shape:** Subagents trained on prose-summary patterns confabulate numbers (line numbers, day counts, thresholds, constraint names) that LOOK plausible but don't match the file.
- **Fix pattern:** Treat every numeric claim from a subagent as UNVERIFIED. Re-read the cited file with `Read` or `Grep` before citing in your own work or in CLAUDE.md / diagnose-docs. 3 of 21 Master Audit findings on 2026-05-12 were false alarms by this exact mechanism.
- **Prior incidents:** `feedback_mistake_restore_window.md`, `feedback_audit_findings_require_live_verification.md`.

### 2.11 Repository `box.get(key) → Map` drops Hive key as id (Gate 16 class)
- **Telltale:** Edit sheet fields blank; downstream consumers (delete, sync, diff) get `id=null` despite the row existing in Hive; "saved but can't be edited" / "selected exercise has no id."
- **Root-cause shape:** Repository iterates `box.keys` (or reads a single `box.get(key)`) and returns the value Map without injecting the key as `id` on the returned map. The Hive key IS the identity in this codebase (`exlog_<...>`, `custom_exercise_<uuid>`, `wlog_<date>`, etc.). Restored entries from cloud sync writers (e.g. `sync_community._restoreCustomExercises`) carry NO `id` value field — the id field lives in the cloud row but the local writer keys the box by the same value, expecting readers to extract it from the key.
- **Fix pattern:** After every `final raw = box.get(key)` that returns a Map, do `final m = Map<String, dynamic>.from(raw); m['id'] ??= key;` (preserve any existing id; never overwrite). Or annotate `// gate16-exempt: <reason>` within 8 lines above when stripping is intentional.
- **Class enforcement:** `scripts/check_id_injection_on_get.dart` (Gate 16) — runs on `/build-apk`. Baseline at `backups/id_injection_on_get_baseline.txt` for grandfathered violations; NEW occurrences hard-fail.
- **Prior incidents:** APK Test #15.1 Bug F (founding incident; the WriteService rewrite stopped writing id-as-value-field, downstream filters silently stripped every row); APK Test #16 caught a fresh introduction in A5's swap-picker fix via Gate 16 before merge. See `feedback_id_must_be_injected_on_get.md`.

### 2.12 Rogue Hive key formula bypasses canonical writer
- **Telltale:** Same logical entity (exercise on a date, meal on a date) appears as multiple rows in the local Train/Receipt/Edit UI. Hive key derivation looks correct on the surface; the duplicates have identical name/date but different keys.
- **Root-cause shape:** A canonical SoT writer (e.g. `WorkoutWriteService.exlogKey`) uses a deterministic formula (UUID v5 over `lowercase+trim(name)` + IST date). One or more secondary writers in the codebase bypass it — restore paths, AI-tool dispatchers, legacy code — and use a different formula (`name.hashCode`, `ms+hashCode`, or just `cloud_uuid`). Same exercise produces multiple keys. Reader iterates index → renders all → user sees duplicates.
- **Fix pattern:** (1) Replace every rogue formula with a call to the canonical helper. (2) Bump the relevant migrator (`ExlogKeyMigrator._migrationKey` etc.) to re-key existing local data + merge collisions with the writer's idempotency window. (3) New source-grep build gate that fails if any code outside the SoT helper constructs the prefix-shaped key directly.
- **Class enforcement:** APK Test #16.1 / Theme A added Gate 17 `scripts/check_exlog_key_canonical.dart`. Same pattern extensible to `nlog_*`, `wlog_*`, `coach_*`, `custom_exercise_*`.
- **Prior incidents:** Test #12.8 / Bug #1 (founding — restore writing ms+hashCode keys; partially fixed but secondary writer at workout_repository:1133 also rogue); Test #16.1 (closed all 3 rogue paths). See `feedback_writer_reader_field_drift_recurring.md` (7th instance).

### 2.13 Telemetry sink silently drops past rate limit
- **Telltale:** Server logs show hundreds of telemetry POSTs returning 200 but the storage table has zero new rows. Investigators see "telemetry is working" because of the 200s but actually have no signal. Hidden until someone runs both queries side-by-side.
- **Root-cause shape:** Rate-limited telemetry function returns 200 with `{rate_limited: true}` body (or just `{ok: true}`) without inserting. Client doesn't honor the signal — treats 200 as success and keeps spamming. Limit was set too low for noisy bug days.
- **Fix pattern:** (1) Raise limit but keep finite (2000/day per user is a reasonable starting point). (2) Add priority lanes — `HIGH_PRIORITY_OP_TYPES` set bypasses the limit (crashes, auth failures, SQL state codes, gate violations). LOW ops share the budget. (3) Return distinguishable signal (`next_window_at` ISO timestamp + `priority_lane` field). (4) Client honors signal — set in-memory cooldown, short-circuit LOW POSTs during cooldown, HIGH always POSTs. (5) Twin tests on both sides asserting the same op_type allowlist (drift between client + server is the next-most-likely regression).
- **Class rule:** any rate-limited sink MUST be auditable — log/return enough signal that "is this sink eating data" is answerable by a single SQL query (e.g., counting rate_limited responses vs. inserts in the same window).
- **Prior incidents:** APK Test #16.1 / Theme D (`9d12af` — `log-client-error/index.ts:142-147`, founding incident). See `feedback_observability_silent_drop.md`.

### 2.10 Provider-invalidation-after-mutation gaps
- **Telltale:** Write succeeds; UI shows stale value until cold restart; insight card / receipt / calendar week shows pre-mutation state.
- **Root-cause shape:** Hive write path forgets to invalidate one of the canonical provider batch: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`, `aiInsightProvider`, `dietPlanProvider`.
- **Fix pattern:** Pin the batch in `EditWorkoutLogSheet.save` (workout SoT) / equivalent for nutrition. Any new mutation path must invalidate the full canonical set. Source-grep regression test asserts presence.
- **Prior incidents:** Test #2 F5 (`aiInsightProvider`), edit-profile regen, `project_apk_test_2_batch.md`.

---

## 3. Red flags — if you're thinking X, STOP

Borrowing from `superpowers:using-superpowers`, `superpowers:systematic-debugging`, and project-specific patterns:

- **"This looks the same as a prior fix — I'll just copy it."** Verify the cited file:line still exists. Memory is point-in-time.
- **"I'll just patch the reader."** Stop. Step 2 demands writer+reader map. The writer might be the actual bug; patching only the reader hides drift forever.
- **"I'll skip the diagnose doc for this one — it's small."** Rule 22 is non-negotiable; pre-commit hook will block you. Bundle the doc into the same `git add` set per `feedback_diagnose_doc_first_in_batch.md`.
- **"It's just a typo / cosmetic fix — no regression test needed."** Rule 21 applies to every `fix:` commit. Source-grep tests count as regression tests.
- **"The subagent said line 47 — let me just go fix line 47."** Read line 47 first. See §2.9.
- **"Context is at 80% — let me hand off to a fresh session."** Banned per `feedback_no_stop_until_done.md`. Use TodoWrite, dispatch focused subagents, compact — but finish the batch.
- **"I'll defer this to a follow-up batch."** Banned per `feedback_no_deferrals.md` + `feedback_no_deferrals_recurrence.md`. Fix all surfaced bugs in the same batch.
- **"The founder didn't approve explicitly but said 'continue' — let me build the APK."** APK builds require explicit per-build approval per `feedback_apk_build_explicit_approval.md`.
- **"I'll bypass the pre-commit hook with --no-verify."** Banned unless the founder approves per-batch AND a final full-suite gate runs before merge (`feedback_bulk_commit_hook_bypass.md`).
- **"I'm changing onConflict to a new column set — it'll work."** STOP. Verify (a) a UNIQUE index exists on those columns; (b) the index is non-partial OR all arbiter columns are NOT NULL; (c) run a live `INSERT ... ON CONFLICT (...) DO UPDATE` in a rollback transaction and confirm no 42P10. Source-grep contract tests do NOT catch partial-arbiter bugs — see §2.4 mode B.
- **"The subagent's fix introduced a regression but Gate XX caught it — I'll skip the fix-up commit since the gate already passed somehow."** Gate scripts may report FAIL but exit 0 during baselining. Re-run the gate standalone and check `$?`. If `[Gate XX] FAIL` appears in output, ALWAYS fix-up and commit, even if exit code says 0. APK Test #16 caught this nuance via Gate 16.
- **"This bug class is novel — I don't need to update the catalog."** Wrong. §5 self-evolution rule below applies.

---

## 4. Output contract — what this skill emits at session end

Every debugging session that uses this skill produces an artifact summary with these fields (paste into the final PR description and into the diagnose-doc):

```
Bug class:         <existing label from §2, or NEW label proposed>
Writer:            <file:line>
Reader(s):         <file:line list>
Prior fixes:       <memory-file links, prior diagnose-doc ids, commits>
Live verification: <SQL queries run + result row counts, file:line reads confirmed>
Plan approved at:  <timestamp / approval message>
Diagnose-doc:      docs/diagnoses/<date>-<slug>-<6hex>.md
Regression test:   <test path that fails-on-main / passes-with-fix>
Memory deltas:     <new feedback_* files OR updates to existing ones>
CLAUDE.md deltas:  <§19 entry added? new invariant codified?>
Skill deltas:      <new bug class appended to §2? new red flag in §3?>
```

---

## 5. Self-evolution rule (MANDATORY)

When you encounter ANY of the following during a debugging session, append to this file BEFORE marking the session complete:

1. **A new bug class** not in §2 — add a new sub-section with the same shape (telltale, root-cause shape, fix pattern, prior incidents).
2. **A new methodology refinement** — extend §1 step list or add a sub-step. Cite the incident that surfaced the refinement.
3. **A new red flag** — add to §3 with the trigger phrase and the correct response.
4. **A bug class graduates** (3+ recurrences) — link a dedicated `feedback_mistake_*.md` from MEMORY.md and tighten the §2 fix pattern.

If you DO NOT update this file when one of the above applies, the next bug eats the time savings — the whole point of self-evolution is broken. The founder's recurring frustration with writer/reader drift (`feedback_writer_reader_field_drift_recurring.md`) is the canonical example: tribal knowledge that should have been a skill from Test #6 onward but wasn't, costing 6+ batches of re-discovery.

Append-only by default. If you must REWRITE an existing entry (e.g. the fix pattern changed), preserve the prior version in a `### N.X.archived-YYYY-MM-DD` sub-entry with a one-line note on why it was superseded.

---

## 6. Cross-references

- `CLAUDE.md` §19 — COMMON BUGS TO AVOID table (canonical project-side bug list)
- `CLAUDE.md` §22 — Diagnose-doc rule
- `CLAUDE.md` rules 20 / 21 — No deferred test failures / Regression test required
- `docs/discipline.md` — L3 checklist
- `docs/sot_registry.yaml` — Single-source-of-truth registry
- `docs/agent_brief_preamble.md` — Subagent prompt prefix for investigations
- `MEMORY.md` — Memory index (grep here first in Step 3)
- `superpowers:systematic-debugging` — Anthropic's general-purpose debugging skill (this skill is the project-specific extension)

---

## Changelog

- **2026-05-15** — Skill created. Seeded with 10 bug classes from Tests #6 through #15.4 + audit 2026-05-12. Diagnose-doc `2026-05-15-debugging-skill-creation-4e9515.md`.
- **2026-05-15 (evening, post-APK-Test-#16)** — Self-evolution. (a) §2.4 expanded with mode-B 42P10 trap (5th writer/reader drift instance), live-arbiter scaffold reference, NOT-NULL-arbiter class rule. (b) §2.5 retry budget bumped to `[2000, 6000, 12000]` + 504 trigger + direct-HTTP wrapping. (c) §2.11 added — Repository `box.get(key) → Map` id-injection class (Gate 16). (d) Two new red flags in §3: onConflict-change verification + "Gate FAIL output but exit 0" trap. Closes-diagnose: `76c8f4`, `9f4ab2`, `25e91d`, `c01d57`, `a5d29c`.
- **2026-05-16 (post-APK-Test-#16.1)** — Self-evolution. (e) §2.12 NEW — "Rogue Hive key formula bypasses canonical writer" (7th writer/reader drift instance, 3 rogue exlog formulas, Gate 17 new). (f) §2.13 NEW — "Telemetry sink silently drops past rate limit" (log-client-error 100/24h silent drop, found this batch). Closes-diagnose: `a16c1a`, `a17bc3`, `913261`, `9d12af`.
