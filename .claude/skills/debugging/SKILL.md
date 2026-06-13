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
- **Prior incidents:** Tests #6, #7, #8 (`project_apk_test_8_batch.md`), #12 Theme E (`project_apk_test_12_batch.md`), #15.3 Bugs 1/6/7 (`project_apk_test_15_3_batch.md`). 10th instance landed 2026-05-22 (`project_apk_test_16_2_batch.md`) — graduation `totalSets=0` reader filtered by `log['type'] == 'exercise_log'` (writer never sets `type`) AND read `log['sets_completed']` (canonical writer field is `set_number`). Closes-diagnose 89d56c. See `feedback_writer_reader_field_drift_recurring.md`.
- **Durable mitigation landed in 10th instance batch:** Gate 19 (`scripts/check_hive_map_field_drift.dart`) — for each canonical Hive prefix (`exlog_`, `nlog_`, `schedule_`, `wlog_`), maintains an expected EMIT field set and scans all readers for `['field']` accesses that walk the prefix. Drift candidates not in the EMIT set hard-fail the gate (with `backups/gate19_drift_baseline.txt` grandfathering existing patterns). NEW occurrences caught at pre-commit. The 11th instance — if it happens — will fail the gate before merge.

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

### 2.14 Plaintext secret in tracked-or-nearly-tracked source
- **Telltale:** A `.gitignore` rule for a secret artifact (`*.jks`, `key.properties`, `*.p12`) exists at one level of the repo but not at root — OR the file is "merely untracked" rather than "actively ignored." `git ls-files` returns empty but `git add -A` from a parent dir would include it. Also: credential-shaped literals (`password: 'XYZ'`, `apiKey: 'sk_test_...'`, project-specific marker like `Avya2026`) in tracked source.
- **Root-cause shape:** Defense-in-depth gap. Either `.gitignore` was scoped narrowly (nested only) OR a credential was inlined "temporarily" and never extracted.
- **Fix pattern:** Add the pattern at every level it could be reached (root + nested). Don't remove the nested rule — defense in depth. Verify via `git check-ignore -v <path>` (authoritative, beats grepping `.gitignore` manually). Rotate any inlined credential AND extract to env. Gate: `scripts/check_secrets_gitignored.dart` (Gate 23).
- **Class rule:** "I didn't `git add` it" is not the same as "it's ignored." Always use `git check-ignore -v`.
- **Prior incidents:** Tech-debt audit 2026-05-20 finding I1 — audit subagent flagged as P0 thinking `key.properties` was unprotected; `git check-ignore -v` showed `android/.gitignore:12-14` already covered it. Root-level defense-in-depth added 2026-05-21. **This is also a methodology lesson** — `feedback_audit_findings_require_live_verification.md` applies; the verification subagent should run `git check-ignore -v`, not just `cat .gitignore`.

### 2.15 Stale generated index (INDEX.md, applied_migrations.json, manifest)
- **Telltale:** An auto-generated file has fewer entries than the filesystem says it should. `dart run scripts/build_bug_index.dart` regenerates correctly when invoked manually but the regen-on-commit hook isn't preserving the change. Bug-history grep starts returning false-negatives — "first-instance" claims silently codified.
- **Root-cause shape:** Three sub-classes, decreasing likelihood:
  1. Pre-commit `git add` was bypassed via `--no-verify` reflex (see `feedback_mistake_no_verify_reflex.md`).
  2. One source file has malformed YAML frontmatter and the generator silently skips it (warns to stderr; no failure exit).
  3. A new file doesn't follow the generator's naming convention (e.g. lacks `-<6char-id>.md` suffix).
- **Fix pattern:** Run the regen. If count still mismatches, read stderr for "no parseable frontmatter" warnings; fix missing closing `---`. Then add Gate 25 `check_diagnose_index_fresh.dart` to pre-commit so future drift fails the commit.
- **Prior incidents:** Tech-debt audit 2026-05-20 finding Doc2 — INDEX had 40 entries while filesystem had 152. Fixed `2026-05-15-swap-picker-custom-miss-a5d29c.md` (missing closing `---`) + renamed `2026-05-16-health-write-service.md` → `...-e7a516.md`. Closes-diagnose: audit closure YAML.

### 2.16 Floating dependency pin
- **Telltale:** `grep -rn '@supabase/supabase-js@\d"' supabase/functions/` returns matches. Sibling Edge Functions resolve the same import to different builds depending on CDN cache state. Cold-starts pick up new minor releases without a code change → silent behavior drift.
- **Root-cause shape:** Dependency pinned at import site instead of central `import_map.json`. Different functions added at different times pick latest-stable-at-the-time. Floating `@N` shapes (no minor/patch) are the worst — any npm/esm push slides resolved version.
- **Fix pattern:** Centralize via `supabase/functions/import_map.json` with bare-specifier aliases. Update import sites to use alias (`from "@supabase/supabase-js"`). Pin to exact `@major.minor.patch`. Gate: `scripts/check_import_map_present.dart` (Gate 27).
- **Prior incidents:** Tech-debt audit 2026-05-20 findings D2/D3 — 4 floating `@2` pins; pinned to `@2.45.4` + introduced `import_map.json` in B1.

### 2.17 Broken intra-doc pointer (§N #M cite to nonexistent section)
- **Telltale:** Markdown table "Source" column or prose sentence cites `CLAUDE.md §N #M` where target section was renumbered, relocated, or deleted in a prior refactor. Agents chase the pointer to a dead end and either re-discover from scratch, ignore the row, or silently mis-apply the rule.
- **Root-cause shape:** Doc-structure refactor (relocation/renumbering/decluttering — e.g. CLAUDE.md Milestone 6 commit `bab14f8`) didn't sweep the citation graph. Refactor was correct at destination; back-pointers got orphaned.
- **Fix pattern:** Build citation index + heading set; assert every cite resolves. Gate: `scripts/check_claude_md_citations.dart` (Gate 26). For relocated entries without a clean target heading, convention is to cite `docs/diagnoses/INDEX.md` or `docs/architecture/<topic>.md` or `docs/playbook/common-pitfalls.md`.
- **Class rule:** Any doc refactor that moves headings MUST be paired with a citation sweep + Gate 26 run.
- **Prior incidents:** Tech-debt audit 2026-05-20 finding Doc6 — 44 broken `§19 #N` cites across 12 nested files + root CLAUDE.md:301-305. Swept to `(relocated 2026-05-18 — see docs/diagnoses/INDEX.md)` or `docs/playbook/common-pitfalls.md` in B1.

### 2.10 Provider-invalidation-after-mutation gaps
- **Telltale:** Write succeeds; UI shows stale value until cold restart; insight card / receipt / calendar week shows pre-mutation state.
- **Root-cause shape:** Hive write path forgets to invalidate one of the canonical provider batch: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`, `aiInsightProvider`, `dietPlanProvider`.
- **Fix pattern:** Pin the batch in `EditWorkoutLogSheet.save` (workout SoT) / equivalent for nutrition. Any new mutation path must invalidate the full canonical set. Source-grep regression test asserts presence.
- **Prior incidents:** Test #2 F5 (`aiInsightProvider`), edit-profile regen, `project_apk_test_2_batch.md`.

### 2.18 Source-grep contract test stale after refactor — caught only at `flutter test`
- **Telltale:** `flutter test` red after a refactor that preserves behaviour via a shim/forwarder file. Failures cluster on test files reading the now-thin-shim via `File('lib/.../<old_filename>.dart').readAsStringSync()` or `firstWhere((e) => e.key.contains('<old_filename>.dart'))`. The matched substring lands on the shim's "THIN SHIM" comment, not on the assertion's target pattern. Behaviour is preserved by the shim's forwarders; the test is just looking in the wrong place. Failures grow proportional to how many tests pinned the old file path (53 of 2354 in the canonical incident).
- **Root-cause shape:** A B5-style multi-file split refactor moves a class body into N split files + leaves an old-name shim that re-exports + forwards. Tests written when the file was a monofile grep that file path by literal string. The grep still succeeds at finding A file; it lands on the shim's documentation block instead of the code that used to live there.
- **Fix pattern:** Each affected test's `setUpAll` concatenates the shim + the N new home files. Existing `contains(...)` / `firstMatch(...)` assertions pass without changing what they test for. Example:
  ```dart
  // Tech-debt audit 2026-05-20 / A10 split ai_coach_repository.dart
  // (2127 LOC) into a thin shim that forwards to AiSnapshotBuilder /
  // CoachInteractionRepository / CoachMemoryService. Concat shim +
  // new homes so source-grep contract still resolves.
  final paths = const [
    'lib/features/ai_coach/repositories/ai_coach_repository.dart',
    'lib/features/ai_coach/services/ai_snapshot_builder.dart',
    'lib/features/ai_coach/services/coach_memory_service.dart',
    'lib/features/ai_coach/repositories/coach_interaction_repository.dart',
  ];
  aiRepoSrc = paths
      .map((p) => File(p).existsSync() ? File(p).readAsStringSync() : '')
      .join('\n\n');
  ```
- **Class enforcement:** Gate 42 (`scripts/check_sot_behavioral_test_paths.dart`) — WARN-only until the 48-of-54 SoT-concept backlog of missing `behavioral_test_path:` lands. Flipping to FAIL closes this class permanently — a behavioural test reads via the canonical surface, not by file path, so refactor-driven moves don't affect it.
- **Class rule (NEW 2026-05-24):** Any source-grep contract test added today MUST also have a paired `behavioral_test_path:` in `docs/sot_registry.yaml`. Adding 1 source-grep test creates 1 future post-refactor recovery touch-point. The discipline asymmetry favours behavioural tests.
- **Prior incidents:** APK Test #16.2 +31 / 2026-05-24 / closes-diagnose `2b705b` — 53 stale source-grep tests caught zero actual bugs (all false positives), blocked pre-commit hook for hours; recovery cost ~3 hours of mechanical setUpAll re-pointing across 21 test files + `docs/sot_registry.yaml` bulk fix (49 stale `file:line_range` entries). One real Edge Function bug (proactive-coach-promotion `user_profile.full_name` query) surfaced as a side-effect of Gate 18 firing during the recovery — validating the gate-as-continuous-audit model. See `project_apk_test_16_2_recovery_2b705b.md` + `feedback_source_grep_false_confidence.md`.

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
- **"This `.select(...)` column list looks fine — the field exists."** STOP. Existing *somewhere* ≠ existing on THIS table. Live-verify every selected column against `information_schema.columns` for the queried table (`user_profile` vs `users` is the canonical trap). A pure-unit test fed a hand-built row keyed by the column passes green while the real query 42703s. See §2.20.
- **"The redirect/guard just reads `InductionService.x` / a service getter — it's cheap."** If that getter reads a user-scoped Hive box (`coachBox`, `userBox`, …) and the call is reachable from a GoRouter `redirect` or any pre-`/restoring` path, it can throw "HiveUserSession not opened" at cold start → router error page. `HiveService.isInitialized` is NOT enough; guard `HiveUserSession.currentOwnerFullId != null`. See §2.21.
- **"The subagent's fix introduced a regression but Gate XX caught it — I'll skip the fix-up commit since the gate already passed somehow."** Gate scripts may report FAIL but exit 0 during baselining. Re-run the gate standalone and check `$?`. If `[Gate XX] FAIL` appears in output, ALWAYS fix-up and commit, even if exit code says 0. APK Test #16 caught this nuance via Gate 16.
- **"This sheet/card takes the data as a param and renders it — fine."** If a PROVIDER is the source of truth and the surface renders a value captured at open-time, `invalidateSelf()` won't rebuild it → stale until a remount ("works after navigate-away-and-back" is the tell). Wrap in `Consumer` + `ref.watch`; `await` the mutating callback. See §2.28.
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

### 2.19 Monotonic-field demoted by recompute (NEW 2026-05-27)
- **Telltale:** User "loses" an achievement that should be permanent after their current state regresses — rank reverts to floor after streak loss; lifetime workout count drops after weekly cron runs; longest-streak number gets smaller; "personal record" badge disappears. Field names match perfectly across writer + reader (so writer/reader drift §2.1 doesn't apply), but two cloud columns disagree on semantics: one is an append-only event log, the other is a denormalization that gets recomputed and unconditionally overwritten.
- **Root-cause shape:** A field that semantically should only-increase (rank ordinal, lifetime workout count, longest streak, peak weight, badge unlock state, deployment count) has a writer that recomputes from CURRENT state every eval (cron, splash, post-workout fire-and-forget) and `.update()` unconditionally. When current state drops below a previously-passed threshold, the recompute returns a lower value → field gets clobbered → user-visible regression of an earned achievement. The "history" survives only when there's a separate append-only event log table — but the rendered UI typically reads the denorm, not the log.
- **Why it's not §2.1 (writer/reader drift):** Field names + types match exactly. Source-grep contract tests pass. The bug is between TWO writers / sources of truth, not between writer + reader.
- **Fix pattern:** Three layers. (1) Data heal migration — recompute the denorm from the append-only event log (`UPDATE denorm SET col = (SELECT MAX(...) FROM event_log)` with the historical achieved-at timestamp when applicable, not `now()`). (2) Writer guard — read existing value, compare by canonical ordering (ladder ordinal for ranks, numeric `>` for counters), only `.update()` when new > existing. Extract as a pure helper (`shouldPromote(currentCode, qualified)`) so a behavioral test can exercise the guard without a live Supabase round-trip. (3) Mirror to every parallel writer (client + every server cron). Sweep with a c2-style audit subagent — the same anti-pattern often hides in 2-3 sibling functions.
- **Class rule:** Any cloud column whose semantic is "lifetime / peak / highest-ever / longest" MUST be only-increment. Writers MUST guard `if (new > existing)` (or SQL `GREATEST(new, existing)`) — never unconditional `.update()`. Denormalizations of append-only event-log tables MUST also be only-increment; if the event log is the truth, the denorm should reconcile UP toward it, never reset to a recomputed current-state ceiling.
- **Prior incidents:** 2026-05-27 diagnose `3a7b9f` — `user_profile.current_rank_code` demoted SD1 → SD2 on Upendra after streak loss; `rank_promotions` event log row for SD1 survived (UNIQUE arbiter), but the denorm was clobbered. Same batch fast-follow (c2 audit) — `user_progress.total_workouts_done` was recomputed by `weekly-recalc/index.ts` from the last 4 WEEKS of workout_log_exercises and overwritten lifetime — silent decrease every Sunday for users training longer than 4 weeks. Both closed via `shouldPromote`-style guards + heal migration 075. `badge_service.dart:32` verified clean during the c2 sweep (`tryUnlock` already guards `!unlocked.containsKey(id.name)` — correctly monotonic by design).

---

### 2.20 Query/select references a column on the wrong table (cross-table drift) (NEW 2026-05-30)
- **Telltale:** PostgREST `42703 column X.Y does not exist` in a `.from('X').select('..., Y, ...')` or `.eq`/`.order` on Y. The field Y genuinely exists — but on a DIFFERENT, adjacent table (e.g. `users.full_name` vs `user_profile`). The catch around the query swallows the error and returns a conservative fallback, so the symptom is a silent behavioral degradation (wrong routing / empty result / "always new user"), not a visible crash. Often the SoT registry's `fields_read:` list for the reader ALSO names Y under table X — the registry encoded the same drift.
- **Why it's a §2.1 sibling:** classic writer/reader drift, but across TWO tables. The reader selects from the wrong table for a field that's legitimately a column elsewhere. Source-grep / pure-unit tests that feed a mock row keyed by Y pass green — the row is hand-built, never round-tripped against the real schema.
- **Root-cause shape:** A refactor that consolidates/moves a query (god-provider extract, widget→service hoist) copies a column list without re-checking which table now backs each column. The destination table is correct for most columns; one or two belong to a sibling (auth-adjacent `users`, a `*_progress`, a `*_preferences` table).
- **Fix pattern:** (1) Live-verify EVERY selected column against `information_schema.columns` for THAT table. (2) Replace the misplaced column with the correct sibling-table column that carries the same semantic on the target table (here: identity-step completion detected via `user_profile.date_of_birth`, not `users.full_name`). (3) Update the SoT `fields_read:` list — the registry was wrong too. (4) Regression test: source-grep the reader's select region asserting the bad column ABSENT + the correct column PRESENT, PLUS update the behavioral classify/decision test to key off the real column (the pure test row must use the real column name so it fails-on-main).
- **Class rule:** Any `.select('col1, col2, ...')` added or refactored MUST have every column live-verified against `information_schema.columns` for the queried table. A field existing *somewhere* in the schema is not proof it exists on THIS table (cross-table drift); a field reading like the right concept is not proof it exists AT ALL (plain wrong-name drift). Cross-check the reader's SoT `fields_read:` against the table's real column set.
- **DURABLE GATE (NEW 2026-05-30, a7c3e1):** `scripts/check_schema_column_refs.dart` now mechanically validates EVERY `.from('<table>').select/eq/gte/lte/gt/lt/neq/like/ilike/order('<col>')` reference in `lib/` against a committed snapshot of the live catalog (`backups/live_schema_columns.json`). Wired into the pre-commit gate loop (auto-discovered by the `scripts/check_*.dart` glob). The wrong-column class — which THREE separate bugs in the 2026-05-30 batch belonged to — can no longer reach `main` silently for the select/filter/order surface. **Regenerate the snapshot in the SAME commit as any migration that adds/drops/renames a column** (regen SQL is in the script header). Known limit: insert()/update()/upsert() map-literal keys are NOT yet validated (multi-line maps / spreads / computed keys) — those stay covered by sync round-trip contract tests; future extension.
- **Meta-lesson — why audits kept missing this class:** every prior "complete audit" was STATIC (code-read + mock-data unit/source-grep tests + targeted one-off schema queries). None cross-checked the column *string literals* in client queries against the real catalog, so a plausible-but-wrong name (`total_steps`, `hours`, `full_name`) sailed through. Mock rows are hand-built with the wrong key, so the test agrees with the bug. The fix for a recurring silent class is a deterministic GATE over the whole surface, not another hand-written test. Also: a defensively-caught query (try/catch returning zeros/fallback) makes a 42703 indistinguishable from "no data" — these are the *highest-value* targets for a schema gate because runtime never complains.
- **Prior incidents:** 2026-05-30 diagnose `e2a4f7` — `AuthSessionBootstrapper.resolveDestination` selected `full_name` from `user_profile` (lives on `users`) → 42703 → catch returned `StartMissionBrief` for every user → fresh-install returning users forced to re-onboard. Masked by the router's local-flag redirect. Regression since `ec01b469` (2026-05-21 A1/A9 extract). **2nd instance of the exact `user_profile.full_name` wrong-table mistake** — 1st was `proactive-coach-promotion` (diagnose 9e1d4c, surfaced 2026-05-24 via Gate 18). The `user_full_name` SoT concept ALREADY documented "user_profile has no full_name column" — but nothing cross-validated other readers' `fields_read:` lists against that constraint. **3rd instance 2026-05-30 diagnose `f4b2c9`** (see §2.22) — the `private.dispatch_proactive_coach_promotion` Postgres trigger referenced `NEW.created_at` (no such column on rank_promotions) AND wrote `client_errors(message, severity)` (real: error_message/error_code). 9e1d4c fixed the Edge Function but missed the trigger function — **when you fix a wrong-column class, grep EVERY surface (client Dart + Edge TS + Postgres trigger/RPC functions) for the same column, not just the one that surfaced.** **4th instance 2026-05-30 diagnose `a7c3e1`** — `StatSnapshotService._compute7dAverages` selected `daily_steps.total_steps` (real: `steps`) AND `sleep_logs.hours` (real: `duration_hrs`); both 42703 → defensive catch → every 7d-average field persisted as 0 on promotion + manual snapshots. Found ONLY by the deterministic schema-ref audit (the live web walk couldn't reach it — promotion snapshots were themselves blocked by f4b2c9). This is the founding case for the durable gate above.

### 2.22 Trigger side-effect exception aborts the triggering write (NEW 2026-05-30)
- **Telltale:** An INSERT/UPDATE that should always succeed fails with an error that names a DIFFERENT table than the one being written (e.g. inserting into `rank_promotions` fails with `column "message" of relation "client_errors" does not exist`). A row the user clearly earned never appears (amar onboarded with ZERO rank_promotions). The error's `CONTEXT:` line names a `PL/pgSQL function ... line N` — that's the trigger, not your statement.
- **Root-cause shape:** A `BEFORE/AFTER INSERT` trigger performs a SIDE EFFECT (telemetry insert, dispatch log, denorm write). The side effect raises (wrong column, NOT NULL violation, FK miss). If the trigger has no handler — or its `WHEN OTHERS` handler RE-RAISES (e.g. the handler's own telemetry insert is equally broken) — the exception propagates out of the trigger and **rolls back the originating statement**. The core write is held hostage by its own best-effort side effect.
- **Fix pattern:** (1) Fix the side-effect's actual defect (correct columns / provide NOT NULL values). (2) Make the side effect UNCONDITIONALLY non-fatal: wrap it in a nested `BEGIN ... EXCEPTION WHEN OTHERS THEN NULL; END;` so even a future breakage of the telemetry can never abort the core write. The invariant: **recording the fact must always win over its notification/telemetry side effect.** (3) Verify with a live rollback-transaction: run the triggering INSERT under the OLD function (expect the abort error) and the NEW function (expect success), both `BEGIN ... ROLLBACK` for zero pollution.
- **Class rule:** Any trigger that does a side-effect write MUST wrap that write so it cannot abort the triggering statement. A `WHEN OTHERS` handler that itself can raise is worse than no handler. AFTER-INSERT triggers are not "fire and forget" — their exceptions are synchronous and transactional.
- **Prior incidents:** 2026-05-30 diagnose `f4b2c9` — `private.dispatch_proactive_coach_promotion` (AFTER INSERT on rank_promotions) failed on `NEW.created_at` then re-failed in its `WHEN OTHERS` handler on `client_errors(message,...)` → every rank_promotions INSERT rolled back → core "Become a Lt" ladder silently broken. Migration 078: correct columns + nested-swallow handler. Live rollback-txn proof. Regression test: `test/contracts/dispatch_proactive_coach_promotion_columns_test.dart`.

### 2.21 User-scoped Hive box read during router redirect / before session open (NEW 2026-05-30)
- **Telltale:** `GoException: Exception during redirect: Bad state: HiveUserSession not opened — cannot wrap user-scoped box "<box>"` → GoRouter renders its error page ("Page Not Found"). Trigger is cold-start / web reload / deep-link / process-death restore onto a route whose `redirect` logic reads a user-scoped box (`coachBox`, `userBox`, …) before `HiveUserSession.openForUser` has run.
- **Why it's a §2.3 sibling:** §2.3 / dc52a4 covered the WRITE/splash side (touching `userBox` pre-`openForUser`). This is the READ side, performed inside a GoRouter `redirect` callback — which runs on the VERY FIRST route resolution, long before `restoring_screen` opens the session. The cross-account `wrapUserScopedBox` guard correctly throws; the caller failed to anticipate the not-open state. A `HiveService.isInitialized` guard is NOT sufficient — initialized ≠ session-open.
- **Root-cause shape:** A redirect/idempotency branch calls a service getter (`InductionService.inductionCompleted`, etc.) that reads a user-scoped box, guarded only by `HiveService.isInitialized`. At cold start the box exists but no user owns it yet → throw escapes the redirect → router error page.
- **Fix pattern:** Short-circuit the user-scoped getter to a safe default (`false` for "completed?"-style guards) when `HiveUserSession.currentOwnerFullId == null`, BEFORE touching the box. Guard at the service getter (defends every caller), not just the one redirect. Behavioral test: with no `openForUser` called, the getter returns the safe default instead of throwing — fails-on-main (throws), passes-with-fix.
- **Class rule:** Any code reachable from a GoRouter `redirect` (or any pre-`/restoring` path) MUST NOT read a user-scoped box without a `HiveUserSession.currentOwnerFullId != null` guard. `isInitialized` is necessary but not sufficient.
- **Prior incidents:** 2026-05-30 diagnose `d5c1b8` — `_authRedirect`'s `isOnCoachInduction` branch read `coachBox` via `InductionService.inductionCompleted`; web reload onto `/#/coach/induction` crashed to GoRouter error page. Same not-open root as dc52a4 (write side). Fixed by guarding `inductionCompleted` + `hasCommitted` on `currentOwnerFullId == null`.

### 2.23 Realtime `.stream()` channelError = table not in the supabase_realtime publication (NEW 2026-05-30)
- **Telltale:** `RealtimeSubscribeException(status: channelError, ...)` on a `_supabase.client.from('<table>').stream(...)` subscription, recurring (not a one-off), with NO "token expired" in the message. A "live cross-device / instant sync" feature silently never delivers and the app falls back to its batch-pull path; nobody notices because the error is caught + logged as a non-fatal.
- **Root-cause shape:** Supabase Realtime "Postgres Changes" only delivers for tables that are MEMBERS of the `supabase_realtime` publication. If the table was never added (publication empty, or table dropped from it), every subscribe channelErrors. Reconnect/retry logic that only special-cases "token expired" never recovers, so it recurs forever. RLS still applies on top (delivery is gated by the table's SELECT policy for `auth.uid()`), and `REPLICA IDENTITY` governs whether OLD values arrive on UPDATE/DELETE (default/PK is enough for INSERT-only consumers).
- **Fix pattern:** `ALTER PUBLICATION supabase_realtime ADD TABLE public.<table>` (migration, with the 4 header tags + applied_migrations.json pairing). Verify `pg_publication_tables` lists it AND that the table has a SELECT RLS policy for the subscribing user. Live-verify by reloading and confirming the recurring `realtime_stream_*` client_errors STOP (compare max(created_at) before/after the migration timestamp — that is the zero-pollution behavioral proof).
- **Class rule:** Any client `.from(X).stream(...)` REQUIRES X ∈ supabase_realtime. Adding a realtime subscription in client code without the matching publication migration is dead config. (Candidate future gate: cross-check every `.stream()` table against `pg_publication_tables`.)
- **Prior incidents:** 2026-05-30 diagnose `e3f1a7` — `supabase_realtime` was EMPTY; `sync_realtime.dart` `.from('weight_logs').stream()` channelError'd 156 times → PRO Telegram→app instant-sync silently dead. Migration 079 added weight_logs; live-verified the errors stopped. Found by AUDIT-2 live web re-drive (console + client_errors), not by any static test.

### 2.24 Edge Function / cron SELECTs columns absent from the live schema → silently inert (NEW 2026-05-31)
- **Telltale:** A server-side cron/EF "runs" (returns 200, pg_cron reports success) but its EFFECT never lands — e.g. a rank cron that never promotes anyone past the floor, a recompute that always writes 0. No error in logs.
- **Root-cause shape:** `const { data } = await supabase.from('t').select('a,b,c')...` where one of a/b/c does NOT exist on the live table → PostgREST 400 → the ignored `error` means `data` is null → every field defaults (`?? 0`) → wrong-but-silent output. The code being deployed + returning 200 is NOT evidence it works; a swallowed 400 is indistinguishable from success.
- **Fix pattern:** verify every server `.select()` column against live `information_schema.columns` / `backups/live_schema_columns.json` before trusting it; never ignore `error` on a server read that feeds logic; ship the column migration in the SAME batch as (or before) the function that reads it. Backfill so existing rows are correct on day one.
- **Class rule:** `check_schema_column_refs.dart` validates CLIENT (`lib/`) column refs but NOT `supabase/functions/`. EF column refs are currently unguarded — candidate gate extension (scan `supabase/functions/**/*.ts` `.from().select()`).
- **Prior incidents:** 2026-05-31 diagnose `b9f4d2` — `evaluate-rank-promotions` SELECTed `current_streak_days, deployments_complete, longest_gap_days, last_workout_date` from `user_progress` (none existed) → server rank cron inert (only ever SD2) for weeks; masked because the client path carried promotions. Migration 081 added + backfilled the columns; client now syncs them. See `feedback_edge_function_selects_nonexistent_columns.md`.

### 2.25 Pause/suppression flag checked at async ENTRY, not at the side-effect SINK (NEW 2026-05-31)
- **Telltale:** A "pause" flag (set before some operation) fails to actually suppress the operation's effect — the effect still happens once, right after the flag was set. E.g. the dev year-sim's PRO grant wiped ~1s after granting despite `pausedForSimulation=true` being set before the grant.
- **Root-cause shape:** The guard sits at the TOP of an async function (`if (paused) return;` in `refreshFromSupabase`). But a call that passed that check BEFORE the flag flipped is still in flight (awaiting a network round-trip); when it resolves, it runs its side effect (`_downgradeLocally`) regardless of the now-true flag. Entry-guards are blind to already-in-flight calls. Boot fired several `unawaited(refreshFromSupabase())` during the ~100s restore (paused=false); one resolved after the sim set paused=true + granted PRO, and wiped it.
- **Fix pattern:** Move the guard to the **side-effect SINK** that every path funnels through (here `_downgradeLocally()` → early-return no-op while paused). A sink-guard is timing-independent (covers in-flight callers) AND covers callers you didn't enumerate (the in-`isPro()` expiry/cross-account downgrade was a third path the entry-guard never touched). Keep the cheap entry-guard too as belt-and-braces.
- **Class rule:** when a mutable flag must suppress a side effect, ask "could a call have passed my guard before the flag was set and still be awaiting its result?" If yes, guard the mutation, not the entry.
- **Prior incidents:** 2026-05-31 diagnose `c7e1a4` — sim PRO grant wiped by an in-flight `refreshFromSupabase`. Fix guards `_downgradeLocally` at `subscription_service.dart:762`. Test `test/contracts/subscription_paused_for_simulation_guard_test.dart`. See `feedback_pause_flag_guard_the_sink.md`.

### 2.26 Remote dependency rot — an exactly-pinned remote URL removed upstream (NEW 2026-05-31)
- **Telltale:** An Edge Function deploy that worked last week now fails with `HTTP 400 — Module not found "https://deno.land/x/<pkg>@<ver>/..."` even though NOTHING local changed. Already-deployed functions keep running (cached bundle) so dashboards stay green — the break only shows on the NEXT deploy of any importer.
- **Root-cause shape:** Distinct from §2.16 (floating pin / version drift). Here the version is pinned *exactly* (`@v3.25.76`), but the third-party registry (`deno.land/x`, raw GitHub, an esm.sh path) **removed or relocated the module**. The pin is honored; the target is gone. `curl` the exact URL → 404. The Supabase Edge bundler resolves the full import graph at deploy time, so one 404 on any transitive remote import aborts the whole deploy with an opaque 400.
- **Fix pattern:** Migrate the importer(s) to a registry-backed, immutable-per-version specifier — `npm:<pkg>@x.y.z` or `jsr:<scope>/<pkg>@x.y.z` — which Supabase Edge (Deno) resolves natively. Fix BOTH layers: every inline `from "https://deno.land/x/..."` AND the canonical `import_map.json` alias (a dead alias is a latent landmine that any future bare-specifier import re-triggers). Verify live: `curl -s -o /dev/null -w "%{http_code}"` the old URL (expect 404) and the new specifier's mirror (e.g. `esm.sh/<pkg>@<ver>` → 200). Redeploy + smoke.
- **Class rule:** prefer `npm:`/`jsr:` over remote URLs for all NEW Edge Function deps. Grep-guard the dead source. When stripping comments in a guard test that scans for URLs, use a colon-lookbehind line-strip (`(?<!:)//`) so it does not eat the `//` inside `https://`.
- **Prior incidents:** 2026-05-31 diagnose `f2d8ae` — `https://deno.land/x/zod@v3.25.76/mod.ts` removed upstream (404); 24 inline `_shared/tools/**` imports + `import_map.json` migrated to `npm:zod@3.25.76`; `ai-proxy` redeploy unblocked (v68). Regression pin `test/contracts/no_denoland_zod_import_test.dart`. See `feedback_mistake_remote_dep_rot.md`.

### 2.27 Missing backoff-retry on a transient upstream call — server gives up on the first blip (NEW 2026-06-01)
- **Telltale:** An AI/coach feature intermittently returns a generic "I had trouble reaching the model" / "temporarily unavailable" — and the SAME request succeeds on a manual retry seconds later. The Edge Function gateway log shows **HTTP 200** (the function returned the apology as a normal body), NOT a timeout. The user (or you) may MIS-FRAME it as a "client timeout."
- **Root-cause shape:** The server→upstream call (Gemini, etc.) tries primary then fallback model **back-to-back with no time spacing**, both on the **same shared API key / project quota**, then throws on total failure; the caller catches and surfaces a generic apology — with **zero backoff-retry**. A single transient 429 / 5xx / empty-candidate that hits the shared quota trips BOTH attempts in ~1-2s. A two-model fallback firing back-to-back is NOT a retry. The apology is generated **server-side** — verify via the gateway 200 + the interactions row (apology text + `tool_calls=null`), which REFUTES a "client timeout" premise.
- **Fix pattern:** Classify each failure `retriable` (429 / 5xx / empty-candidate) vs not (a 25s timeout already spent the budget; a non-429 4xx a retry can't fix; deterministic SAFETY/RECITATION content blocks). Add a **bounded, time-spaced** retry over the attempt list for the retriable bucket ONLY, capped by max-passes + a wall-clock deadline. Happy path stays 1 call. Never retry forever — under a SUSTAINED shared-quota outage extra retries burn quota + degrade real users (so the bound is the safety valve, not the recovery).
- **Class rule:** any server→upstream hop that can return a transient 429/5xx needs a time-spaced, bounded retry for the retriable bucket (pair with the client-side §2.5 `retryColdStart`). And — when a user FRAMES a bug ("it's a client timeout"), verify the premise with tools BEFORE fixing; here the gateway 200 + the interactions row proved server-side give-up, redirecting the fix from the client to `geminiChatWithTools`.
- **Prior incidents:** 2026-06-01 diagnose `d4f1c2` — coach "I had trouble reaching the model" was server-side give-up: `tool-loop.ts` caught a `geminiChatWithTools` throw with zero retry, and `geminiChatWithTools` fired Flash→Flash-Lite back-to-back on the shared `GEMINI_API_KEY`. Fix: bounded backoff-retry (2 passes, 700ms spacing, 20s deadline; `retriable` classification) in `geminiChatWithTools`; `tool-loop.ts` catch unchanged (now the final apology after bounded retries fail). Test `supabase/functions/_shared/gemini_backoff_retry_test.ts` (5 cases). Client analog: §2.5. E2E-pacing caveat in `.claude/skills/e2e-sim-testing/SKILL.md` §5.

### 2.28 Sheet/dialog renders a captured value snapshot instead of watching the provider (NEW 2026-06-05)
- **Telltale:** A bottom sheet / dialog / card shows STALE state after an action that should update it — e.g. the Health Connect card shows "Connect" right after connecting, and only navigating away + back shows "Connected". The provider DID update (the write + `invalidateSelf()` ran); the open surface just never re-read it. "Works after navigate-away-and-back" is the signature tell.
- **Root-cause shape:** The widget received a value snapshot as a constructor param (`SomeCard(data: capturedData)`) computed ONCE when the sheet opened, instead of `ref.watch(someProvider)` inside its build. `invalidateSelf()` rebuilds the provider, but the already-mounted sheet still holds the old immutable snapshot → no rebuild. A fresh mount re-reads, masking it as "works on second look". Often paired with an `unawaited(toggle())` callback so a denied-permission path still flips the UI optimistically.
- **Fix pattern:** Wrap the stale surface in a `Consumer` (or make it a `ConsumerWidget`) and `ref.watch(theProvider)` so `invalidateSelf()` rebuilds it in place. `await` the mutating callback (never `unawaited` it) so a failed/denied write doesn't leave the UI ahead of the truth. Add a widget test that toggles + asserts the new label WITHOUT remounting.
- **Class rule:** if a provider is the source of truth for a surface, the surface MUST `ref.watch` it — never render a value captured at open-time.
- **Prior incidents:** 2026-06-05 diagnose `9a5c3f` — Health-sync sheet rendered a captured `BiometricData` snapshot; `toggleSync` correctly wrote + `invalidateSelf()` but the open sheet never re-read. Fix wraps `BiometricSyncCard` in `Consumer(ref.watch(biometricProvider))` + awaits `toggleSync`. Test `test/contracts/biometric_sync_state_test.dart`. SoT concept `biometric_sync_state`.

### 2.29 Overloaded field used as a severity/category proxy → aggregate-query blind spot (NEW 2026-06-07)
- **Telltale:** An aggregate count / alert / report silently under- or over-counts because its WHERE clause filters on a column that is OVERLOADED — one field carrying two meanings (a type AND a severity). The alert looks tuned and fires plausibly, but a whole sub-class is invisible (or inflated). Found by tracing EVERY writer of the filtered column, not by reading the query.
- **Root-cause shape:** A column means different things from different writers. `client_errors.error_code` = the Dart exception class from `ErrorTelemetry.recordNonFatal`, but the literal string `'event'` from `ErrorTelemetry.logEvent` — for EVERY structured event, benign breadcrumb or genuine failure alike (`widget_error_fallback`, `*_failed`, `*_returned_null` all post `error_code='event'`). An alert that excluded `error_code IN ('event','info')` to drop breadcrumb noise therefore also went blind to ~25 call-sites of real `logEvent`-coded failures. Severity actually lived in `op_type` (the naming convention `*_failed` / `*_fallback`), not `error_code`.
- **Fix pattern:** Don't filter an aggregate on an overloaded field as if it were single-purpose. Either (a) re-include the wanted sub-class by the field that DOES carry the real signal (here `OR op_type ~* '(fail|error|crash|fallback|unknown|...|_null)'`), or (b) split the overload at the writer (give the failure path its own code). Validate the predicate against LIVE data — group the excluded bucket by the discriminator and confirm zero misclassification — before trusting it. NAME every writer of the column first (§4.1); the missed writer IS the blind spot.
- **Class rule:** before excluding/including rows by a field in any alert / report / cron aggregate, enumerate ALL writers of that field and confirm it is single-purpose. If two writers assign different meanings, the field is a severity/category PROXY and must not be used as a filter without the real discriminator.
- **Prior incidents:** 2026-06-06 diagnose `f0b9d3` — `alert_client_errors_spike` (migration 086) excluded all `error_code IN ('event','info')` to drop the 81.5% breadcrumb inflation, but `logEvent` stamps `'event'` on genuine failures too → the alert went blind to a crash-storm class. Caught in a founder-prompted pre-push review (NOT my own first sweep). Migration 087 re-includes failure-shaped `op_type`s by regex (validated zero-misclassification on live data); thresholds unchanged. Test `test/contracts/alert_thresholds_sync_test.dart` asserts the `op_type ~*` re-inclusion is present. See `project_alert_threshold_tuning_2026_06_06.md`.

### 2.30 Two cloud representations of one concept drift (table vs snapshot blob) (NEW 2026-06-09)
- **Telltale:** A value looks "missing / expired / never set" but it WAS written — just to a DIFFERENT cloud representation of the same concept than the one the client reads. The client trusts a denormalized SNAPSHOT BLOB while the live per-row TABLE holds the truth (or vice-versa). Symptom: "plan expired" though future workouts exist; the founder says "I DID regenerate" and is right.
- **Root-cause shape:** One concept has two cloud homes that can drift: a live table (`scheduled_workouts`) and a snapshot blob (`user_progress.plan_json` = {plan_start_date, plan_end_date, schedules}). A writer advanced the table (regeneration → 07-05) but the snapshot blob didn't re-persist (its push was 401ing — §2.31), so `plan_end_date` lagged. The client reads the WINDOW from the stale blob (authoritative-by-design via diagnose a7d3f1) → false "expired". A SoT sibling of §2.1 but between two REPRESENTATIONS, not writer↔reader.
- **Fix pattern:** Make the LIVE/materialized representation authoritative for the derived decision, or heal the blob from the table when they disagree. Here `isPhaseExpired()` now consults the materialized `schedule_<date>` rows (pure `isPhaseExpiredFrom`) instead of trusting the stale `plan_end_date` constant. Pair with fixing the blob's persistence (§2.31). NAME every cloud representation of the concept and query EACH before concluding "never written".
- **Class rule:** before asserting a value is missing / expired / never-regenerated, enumerate EVERY cloud representation (live table AND any snapshot blob AND scalar columns) and query each; disagreement = a SoT split, not an absence.
- **Prior incidents:** 2026-06-09 diagnose `a1d4f9` (BUG-A) — `scheduled_workouts`→07-05 vs `plan_json.plan_end_date`→05-24 → false "expired / wrong week / not scheduled" (APK +34 obs 1/5.1/6). Test `test/contracts/plan_expiry_respects_schedule_test.dart`. Memory `feedback_mistake_plan_regen_partial_save.md`. Adjacent same-batch "trust the live/stored thing not the stale derivation" lessons: cache-buster-on-read (BUG-E `b1f3a7`) and orphan-completion-restore (BUG-F `e9b4a2`).

### 2.31 Token freshness inconsistent across Edge Function callers (NEW 2026-06-09)
- **Telltale:** An authed feature intermittently 401s ("Invalid or expired token") while the Edge Function is provably UP (ACTIVE, still logging rows). Some callers work, others 401 — the difference is whether THAT caller refreshed the JWT before invoking.
- **Root-cause shape:** Multiple EF call paths with inconsistent token handling. The canonical helper (`SupabaseService.callFunction`) proactively refreshes (`ensureFreshToken` + hard refresh). Non-canonical paths drift: a web/CORS fallback degrades the Bearer to the ANON key (`... ?? AppConstants.supabaseAnonKey`) → ai-proxy 401; a `sync_service` path calls `functions.invoke` DIRECTLY without refreshing → stale-token 401. A stale token after a long backgrounded period / long restore is the trigger.
- **Fix pattern:** Route EVERY authed EF call through a fresh user token: never anon-fallback an authed endpoint (force-refresh-or-throw-clearly); `await ensureFreshToken()` before any direct `functions.invoke`; refresh before long operations (restore) too. Grep ALL `functions.invoke` + direct-HTTP EF callsites, not just the one that surfaced.
- **Class rule:** any authed Edge Function call MUST send a freshly-refreshed USER token; the anon key is only ever the `apikey` header, NEVER the Bearer for an authed endpoint.
- **Prior incidents:** 2026-06-09 diagnose `d3a1c7` (BUG-C) — ai_service `_directHttpCall`/`_directMediaHttpCall` anon-fallback + `sync_service` daily-snapshot/log-client-error direct invokes → AI "down" (obs 3) + the `push_snapshot` 401 that ENABLED the §2.30 plan_json SoT split. Test `test/contracts/edge_function_token_freshness_test.dart`. BUG-G (`a7f2e9`) extended the refresh to the restore entrypoints. **RECURRED 2026-06-13 (diagnose `c4f1a7`, Obs#9):** the §2.31 prose rule ("grep ALL invoke sites") + that one test STILL missed delete_account_screen (the DPDP delete button "did nothing" on an aged web token) + assess-body-composition + redeem-referral + the video endpoints. Prose did not prevent recurrence → this batch ships the MECHANICAL backstop `scripts/check_authed_invoke_fresh_token.dart` (every raw `functions.invoke` in lib/ must be preceded by `ensureFreshToken`, or route through `callFunction`). Lesson: codifying a class in prose is insufficient — a recurrence-prone class needs a gate.

### 2.32 `REVOKE … FROM <role>` is a no-op while PUBLIC still holds the grant (NEW 2026-06-11)
- **Telltale:** A `SECURITY DEFINER` function in the `public` schema is callable over PostgREST by `anon`/`authenticated` (a privilege-escalation / free-PRO hole). You `REVOKE EXECUTE … FROM anon, authenticated`, `apply_migration` returns success — and the function is STILL anon-executable.
- **Root-cause shape:** PostgreSQL grants `EXECUTE` on every new function to the built-in `PUBLIC` pseudo-role by default; `anon`/`authenticated` INHERIT from PUBLIC. Revoking from the inheriting roles does nothing while PUBLIC still holds the grant — the inherited privilege remains. `apply_migration` success ≠ the privilege actually changed.
- **Fix pattern:** `REVOKE EXECUTE ON FUNCTION … FROM PUBLIC;` then `GRANT EXECUTE … TO <trusted role>` (e.g. `service_role`, or `authenticated` for a guarded client-RPC). VERIFY THE DDL EFFECT LIVE with `has_function_privilege('anon', 'fn(argtypes)', 'EXECUTE')` (and `authenticated`) AFTER apply — never trust the migration's success code. For a SECURITY DEFINER fn that MUST stay client-callable, keep `authenticated` EXECUTE but add an `IF p_user_id <> auth.uid() THEN RAISE` cross-account guard inside.
- **Class rule:** revoking a privilege from a role that INHERITS it (anon/authenticated ⊂ PUBLIC) is a no-op; revoke from PUBLIC + grant to the trusted role, then assert with `has_function_privilege`. Also harden `search_path` (`ALTER FUNCTION … SET search_path = public`) on every SECURITY DEFINER fn.
- **Prior incidents:** 2026-06-11 diagnose `c9b3e2` — migration 090's `REVOKE FROM anon, authenticated` on extend_subscription / redeem_referral_atomic / increment_promo_used_count / trigger fns was a NO-OP (caught by my own `has_function_privilege` check); migration 091 `REVOKE FROM PUBLIC` + `GRANT TO service_role` was the effective fix. Advisor cleared 15/16 anon-exec + all 9 search_path findings. Test `test/contracts/security_definer_revoke_migration_test.dart` + live `test/sql/security_definer_anon_revoke.sql`.

### 2.33 A "replaces X" refactor silently drops a field the readers depend on (NEW 2026-06-12)
- **Telltale:** A count/history/aggregate surface UNDERCOUNTS live data, but the data exists and a reinstall+restore "fixes" it temporarily before it drifts down again. The writer was consolidated ("method B replaces method A") and the new writer omits a field the readers filter on.
- **Root-cause shape:** A refactor routes a write through a different method whose output is *almost* equivalent — but the replaced method stamped a discriminator/identity field (`type`, an ISO timestamp) that the new one doesn't, and NO test pinned that field on the row. Readers filter `type=='workout_log'` (or parse `completed_at`); the new rows lack it → invisible. The RESTORE path still stamps the field, so cloud-round-tripped rows count while live rows don't — masking the bug after a reinstall. This is §2.1 writer/reader drift via *consolidation* rather than rename.
- **Fix pattern:** When a refactor says "replaces method A", DIFF A's emit-field set against the new writer's — every field A stamped that any reader filters/parses MUST survive. Add a behavioral test that drives the new writer and asserts the reader counts it (not just a source-grep). Add a one-shot boot migrator to heal rows already written by the lossy writer. Register a `hive_field_name_*` SoT concept pinning the discriminator field as REQUIRED + extend the field-drift gate's emit set.
- **Class rule:** a writer-consolidation refactor is a writer/reader-drift hazard — pin the discriminator field (the thing readers filter on) with a behavioral test, and verify the live path, not just the restore path (which can mask the drop).
- **Prior incidents:** 2026-06-12 diagnose `f1c8e4` — markCompleted ("replaces saveWorkoutLog") dropped `type:'workout_log'` + `completed_at` from the wlog row → This-Week tile / frequency chart / history / badge total / AI snapshot all undercounted live completions; only the restore path re-tagged them. Sibling `b3f9d1` (the orphan-completion RESTORE synthesize path had the same gap). Tests `markcompleted_wlog_counted_test.dart` + `wlog_type_backfill_migrator_test.dart`. 11th+ instance of the §2.1 class — see `feedback_writer_reader_field_drift_recurring.md`.

### 2.34 Commit-gate hash instability — non-deterministic regen + non-byte-faithful hashing (NEW 2026-06-12)
- **Telltale:** The catastrophic-tier review gate can't be satisfied — the `docs/reviews/<hash>-review.md` file you create with the gate's printed hash still fails to match; or a pre-commit INDEX regen produces a fresh no-op diff every run.
- **Root-cause shape:** (a) An auto-generated artifact embeds a wall-clock timestamp (`Generated: ${DateTime.now()}`) or sorts non-deterministically (unstable sort over a filesystem-ordered list) → its content shifts every run → the staged-diff hash shifts. (b) A "hash the staged diff" helper decodes git's bytes to a String (SystemEncoding/cp1252 on Windows) then hashes `String.codeUnits` (UTF-16) → non-byte-faithful for any non-ASCII (an emoji in a comment) → diverges from `git diff --cached | git hash-object --stdin`.
- **Fix pattern:** (a) Make generated artifacts a PURE FUNCTION of inputs — no timestamps, stable total-order sort (tiebreak by a unique key). (b) Hash RAW BYTES: `Process.run(..., stdoutEncoding: null)` → `List<int>` → feed verbatim to `git hash-object --stdin`. Never round-trip bytes through a String for hashing.
- **Class rule:** anything that feeds a content hash must be byte-deterministic AND byte-faithful; verify by running the generator twice (diff must be empty) and comparing the helper's hash to git's own.
- **Prior incidents:** 2026-06-12 diagnose `f4d1b7` — build_bug_index.dart `Generated:` timestamp (shifted the INDEX hash) + check_code_review_pass_exists.dart `.codeUnits` hash (the ⚠️ emoji in migration 090 broke the gate during the 2026-06-11 security commit, forcing a docs:-split workaround). Test `review_gate_hash_raw_bytes_test.dart`.

### 2.35 Edge Function auth: user JWT passed as the supabaseKey + bare getUser() (NEW 2026-06-13)
- **Telltale:** an authed `verify_jwt=true` Edge Function returns its OWN sanitized 401 ("Invalid or expired token") for a token that is PROVABLY valid in the same instant (the same token returns 200 from `/auth/v1/user` and from other EFs). NOT token expiry — the EF's own auth check rejects every valid token, so the feature is 100% broken for ALL users, silently (looks like "auth required").
- **Root-cause shape:** `createClient(SUPABASE_URL, authHeader.replace("Bearer ", "")).auth.getUser()` — the USER JWT is passed in the `supabaseKey` (apikey) slot, so GoTrue rejects the apikey; AND `getUser()` is called with no token arg. Both wrong. The working EFs use `createClient(URL, SERVICE_ROLE).auth.getUser(token)` (or `createClient(URL, KEY, {global:{headers:{Authorization}}})` + bare `getUser()`).
- **Fix pattern:** `const userClient = createClient(URL, SERVICE_ROLE); const {data} = await userClient.auth.getUser(token);` — userId from `data.user.id` only. Gate `scripts/check_edge_function_auth_pattern.dart` flags `createClient(url, <authHeader/jwt>)`.
- **CRITICAL detection lesson:** the anon-Bearer BOOT-verify (deploy-rollback §6.5) CANNOT catch this — a broken-auth module returns its own 401 to the anon AND to every valid user token, indistinguishable from a correct anon rejection. Verify a `verify_jwt=true` EF with a REAL user token (deploy-rollback §6.7).
- **Prior incidents:** 2026-06-13 diagnose `e8a1c3` — delete-account v1→v4 shipped this; the DPDP §17 erasure was unreachable for ALL users; caught only by the live real-token E2E. Tests `delete_account_auth_pattern_test.dart` + the gate. See `feedback_edge_function_auth_jwt_as_apikey.md`.

### 2.36 PostgREST builder is a thenable with NO .catch() method (NEW 2026-06-13)
- **Telltale:** a Deno EF `.insert()/.update()/.select()` chained with `.catch(fn)` throws a `TypeError` (`.catch is not a function`) → the catch never runs AND the query may never execute. Often masked behind an earlier bug (delete-account's auth always 401'd, so the audit-insert `.catch` never ran until the auth fix revealed it → 500 AFTER a successful irreversible delete).
- **Root-cause shape:** supabase-js PostgREST filter builders are *thenables* (await-able) but do NOT implement `Promise.catch`. `builder.catch` is `undefined`; `undefined(fn)` throws synchronously.
- **Fix pattern:** `const {error} = await admin.from(...).insert(...); if (error) throw error;` wrapped in a real try/catch. Never `.catch()` on a builder; `.catch()` is valid ONLY on a real Promise (a native `fetch()`).
- **Prior incidents:** 2026-06-13 diagnose `d5b2f8` — delete-account audit insert. Test `delete_account_auth_pattern_test.dart` (d5b2f8 group). See `feedback_postgrest_builder_no_catch.md`.

### 2.37 Platform-only native init unguarded by kIsWeb → web boot crash (NEW 2026-06-13)
- **Telltale:** web boot console: "[main] Firebase/Crashlytics init failed: Null check operator used on a null value" (or similar null-check from a plugin with no web binding). Caught by a try/catch so boot doesn't hard-fail, but the feature's fatal-error routing is left half-wired + the error spams boot telemetry on every web load.
- **Root-cause shape:** `FirebaseCrashlytics.instance.*` (and other mobile-only plugins) have no web platform binding; calling them on web hits a null-check inside the plugin. The init was not gated by `if (!kIsWeb)`.
- **Fix pattern:** wrap the native-only init block in `if (!kIsWeb) { ... }`. Preserves Android/iOS exactly; web cleanly skips a binding it doesn't have.
- **Prior incidents:** 2026-06-13 diagnose `b2e9d3` — main.dart Firebase/Crashlytics. Test `crashlytics_web_guard_test.dart`.

### 2.38 Cross-user read need vs own-only RLS → must use a scoped service-role EF (NEW 2026-06-13)
- **Telltale:** a feature that needs to read OTHER users' rows (a community review queue, a referral-code lookup, a leaderboard) returns 0 rows / empty / "not recognized" for EVERY user, silently. The table has own-only SELECT RLS (`auth.uid() = user_id`); the read either filters `.neq('user_id', me)` or looks up another user's row.
- **Root-cause shape:** the cross-user read runs under the caller's `authenticated` context — either a client direct `.from()` (no EF at all), OR an EF that baked the user JWT into `global.headers` so PostgREST derives the role from the JWT and runs as `authenticated`. Own-only RLS returns 0 rows → the feature is inert. Auth itself SUCCEEDS; it's the DATA-read role that's wrong (distinct from §2.35 jwt-as-apikey, which is a 401-for-everyone auth break).
- **Fix pattern:** route the cross-user read through a SCOPED service-role Edge Function — pure `createClient(URL, SERVICE_ROLE)` (BYPASSRLS, no global headers) + `getUser(token)` to authenticate the caller — that returns ONLY the needful rows (e.g. `submitted && !approved`), narrow projection, and STRIPS other users' identifiers it doesn't need (anonymize). NEVER relax the table RLS to world-read — that exposes every user's full catalog incl. private rows. If you also tighten a related world-read policy, verify EVERY reader first; server tallies that are SECURITY DEFINER or service-role are BYPASSRLS and unaffected (verify `prosecdef`/the client builder live before asserting "breaks no reader").
- **Prior incidents:** 2026-06-13 `d2b9e6` (referral — EF read the referrer's code under the referee's RLS context via JWT-in-`global.headers`; the alternative client-direct read was equally blocked); 2026-06-13 `c7d4f1` (community-review queue — client read `user_custom_*` cross-user directly; fixed with the new `get-community-review-items` EF + `community_reviews` SELECT world→own tighten, both BYPASSRLS tally readers verified). Tests: `referral_redeem_success_contract_test.dart`, `community_review_rls_context_c7d4f1_test.dart`. See `feedback_edge_function_auth_jwt_as_apikey.md` (sibling class).

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
- **2026-05-21 (Tech-debt audit 2026-05-20 / Batch 1)** — Self-evolution. §2.14 NEW — Plaintext secret in tracked-or-nearly-tracked source (I1; defense-in-depth `.gitignore` + Gate 23). §2.15 NEW — Stale generated index (Doc2; INDEX.md regen + Gate 25). §2.16 NEW — Floating dependency pin (D2/D3; `import_map.json` + Gate 27). §2.17 NEW — Broken intra-doc pointer (Doc6; citation sweep + Gate 26). Each entry cites the discovering finding ID + the new gate that prevents recurrence. Closes-diagnose: tech-debt audit closure YAML (B1).
- **2026-05-27 (Rank-permanence batch)** — Self-evolution. §2.19 NEW — Monotonic-field demoted by recompute. Founded by `user_profile.current_rank_code` SD1 → SD2 demotion after streak loss; c2 audit fast-follow caught identical class in `weekly-recalc` `total_workouts_done` overwrite. Three-layer fix pattern codified: heal migration from append-only log + writer guard (extract pure `shouldPromote`-style helper for behavioral coverage) + mirror to every parallel writer (client + server crons). Closes-diagnose: `3a7b9f`. Regression test: `test/contracts/rank_no_demotion_behavioral_test.dart` (9/9 passing — exhaustive 11×11 ladder coverage + edge cases). SoT registry entry: `rank_monotonic_current_code`.
- **2026-05-30 (live web E2E bug batch)** — Self-evolution. §2.20 NEW — Query/select references a column on the wrong table (cross-table writer/reader drift). §2.21 NEW — User-scoped Hive box read during router redirect / before session open (read-side sibling of dc52a4 §2.3). §2.22 NEW — Trigger side-effect exception aborts the triggering write (AFTER INSERT trigger whose telemetry insert + re-raising WHEN OTHERS handler rolled back the core write). Two new §3 red flags (live-verify every select column vs information_schema; guard user-scoped getters reachable from redirects on `currentOwnerFullId != null`). All three surfaced by driving the live web app via Claude-in-Chrome (real CanvasKit pixels) — the live console exposed the trigger P0 that no test caught. Bug 1 (`e2a4f7`) + Bug 3 (`f4b2c9`) are the 2nd + 3rd instances of the `user_profile.full_name` / wrong-column class (1st = `9e1d4c`); **lesson: when fixing a wrong-column class, grep EVERY surface (client Dart + Edge TS + Postgres trigger/RPC functions), not just the one that surfaced.** Closes-diagnose: `e2a4f7`, `d5c1b8`, `f4b2c9`. Migration 078 (catastrophic-tier, CREATE OR REPLACE trigger fn). Regression tests: `auth_session_bootstrapper_test.dart` + `induction_service_session_guard_test.dart` (behavioral, reproduces the exact StateError) + `dispatch_proactive_coach_promotion_columns_test.dart`. Live rollback-txn proofs for the trigger fix. SoT registry updated: `onboarding_completed_at` resolveDestination `fields_read` full_name → date_of_birth.
- **2026-06-01 (derive-only AI-coach cross-surface matrix batch)** — Self-evolution. §2.27 NEW — Missing backoff-retry on a transient upstream call (server gives up on the first blip). Surfaced live driving the coach as amar: "I had trouble reaching the model" was server-side give-up (`tool-loop.ts` zero-retry catch + `geminiChatWithTools` back-to-back Flash→Flash-Lite on the shared `GEMINI_API_KEY`), NOT a client timeout (gateway 200 + `tool_calls=null` proved it). Fix: bounded backoff-retry in `geminiChatWithTools` (2 passes / 700ms / 20s deadline, `retriable` classification), `ai-proxy` v69. Also surfaced diagnose `c9f2a7` (nutrition FK-on-PK 23503, 3rd instance of §2.4-adjacent natural-key-upsert-rewrites-FK-referenced-PK class). Closes-diagnose: `d4f1c2`, `c9f2a7`. Tests: `gemini_backoff_retry_test.ts`, `sync_nutrition_log_id_resolved_before_upsert_test.dart`. New project skill `e2e-sim-testing` (live-web cross-surface verification). Premise-correction lesson: verify a user's bug FRAMING with tools before fixing.
- **2026-05-31 (derive-only AI-coach tool-surface batch)** — Self-evolution. §2.26 NEW — Remote dependency rot (an exactly-pinned remote URL removed upstream). Distinct from §2.16 floating-pin: the version was pinned correctly but `deno.land/x/zod@v3.25.76` was deleted from the registry (live `curl` → 404), aborting every Edge Function deploy whose graph imported it. Surfaced while redeploying `ai-proxy` for the derive-only prune (ADR-0012). Fix migrated 24 inline imports + the `import_map.json` alias to `npm:zod@3.25.76`. New §3 red flag implied: a deploy that worked last week failing with "Module not found <remote-url>" + nothing local changed = suspect upstream rot, `curl` the exact URL. Closes-diagnose: `f2d8ae`. Regression test: `test/contracts/no_denoland_zod_import_test.dart` (colon-lookbehind comment-strip so it doesn't eat `https://` URLs). Memory: `feedback_mistake_remote_dep_rot.md`.
- **2026-06-05 (APK obs batch — ship)** — Self-evolution. §2.28 NEW — Sheet/dialog renders a captured value snapshot instead of watching the provider (Obs 5 / `9a5c3f`: Health-sync card showed "Connect" after connecting; only a remount showed "Connected"). New §3 red flag (a provider-driven surface MUST `ref.watch`, never render an open-time snapshot; "works after navigate-away-and-back" is the tell). Fix wraps `BiometricSyncCard` in `Consumer` + awaits `toggleSync`. Test `biometric_sync_state_test.dart`; SoT concept `biometric_sync_state`. Surfaced by the batch's Hermes E-pass as the discovering fix's self-evolution item (completed post-ship).
- **2026-06-07 (process-discipline remediation)** — Self-evolution. §2.29 NEW — Overloaded field used as a severity/category proxy → aggregate-query blind spot (founded by `f0b9d3`: `alert_client_errors_spike` excluded all `error_code='event'` but `logEvent` codes failures as `'event'` too → alert blind to a failure class; migration 087 re-includes failure-shaped `op_type`s). Caught by a founder-prompted pre-push review, not my own sweep — which also drove the CLAUDE.md §4.3 "≥account code-review is self-initiated before merge" invariant + `feedback_mistake_review_not_self_triggered.md`. No diagnose-doc (process codification, not a bug fix).
- **2026-06-09 (APK +34 recurring-observations batch)** — Self-evolution. §2.30 NEW — Two cloud representations of one concept drift (table vs snapshot blob): live `scheduled_workouts`→07-05 vs stale `plan_json.plan_end_date`→05-24 made the app report "expired" though the plan regenerated (BUG-A `a1d4f9`; `isPhaseExpired` now honors the materialized schedule via pure `isPhaseExpiredFrom`). §2.31 NEW — Token freshness inconsistent across EF callers (BUG-C `d3a1c7`: ai_service anon-Bearer fallback + sync_service direct invokes → 401 while ai-proxy was UP; the `push_snapshot` 401 was the §2.30 enabler). Batch also shipped BUG-B (Train expired-state `b6e1c3`), BUG-D (reports lifetime-as-weekly `c2e8b4`), BUG-E (profile cache-buster-on-read `b1f3a7`), BUG-F (out-of-window completion not restored → streak 0 `e9b4a2`), BUG-G+H (realtime channelError recovery + restore token refresh `a7f2e9`). Correction lesson: I wrongly asserted the plan "never regenerated" — `feedback_mistake_plan_regen_partial_save.md` (query EVERY cloud representation before asserting absence). Closes-diagnose: a1d4f9, d3a1c7, b6e1c3, c2e8b4, b1f3a7, e9b4a2, a7f2e9.
