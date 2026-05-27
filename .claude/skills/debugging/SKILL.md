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

### 2.19 Monotonic-field demoted by recompute (NEW 2026-05-27)
- **Telltale:** User "loses" an achievement that should be permanent after their current state regresses — rank reverts to floor after streak loss; lifetime workout count drops after weekly cron runs; longest-streak number gets smaller; "personal record" badge disappears. Field names match perfectly across writer + reader (so writer/reader drift §2.1 doesn't apply), but two cloud columns disagree on semantics: one is an append-only event log, the other is a denormalization that gets recomputed and unconditionally overwritten.
- **Root-cause shape:** A field that semantically should only-increase (rank ordinal, lifetime workout count, longest streak, peak weight, badge unlock state, deployment count) has a writer that recomputes from CURRENT state every eval (cron, splash, post-workout fire-and-forget) and `.update()` unconditionally. When current state drops below a previously-passed threshold, the recompute returns a lower value → field gets clobbered → user-visible regression of an earned achievement. The "history" survives only when there's a separate append-only event log table — but the rendered UI typically reads the denorm, not the log.
- **Why it's not §2.1 (writer/reader drift):** Field names + types match exactly. Source-grep contract tests pass. The bug is between TWO writers / sources of truth, not between writer + reader.
- **Fix pattern:** Three layers. (1) Data heal migration — recompute the denorm from the append-only event log (`UPDATE denorm SET col = (SELECT MAX(...) FROM event_log)` with the historical achieved-at timestamp when applicable, not `now()`). (2) Writer guard — read existing value, compare by canonical ordering (ladder ordinal for ranks, numeric `>` for counters), only `.update()` when new > existing. Extract as a pure helper (`shouldPromote(currentCode, qualified)`) so a behavioral test can exercise the guard without a live Supabase round-trip. (3) Mirror to every parallel writer (client + every server cron). Sweep with a c2-style audit subagent — the same anti-pattern often hides in 2-3 sibling functions.
- **Class rule:** Any cloud column whose semantic is "lifetime / peak / highest-ever / longest" MUST be only-increment. Writers MUST guard `if (new > existing)` (or SQL `GREATEST(new, existing)`) — never unconditional `.update()`. Denormalizations of append-only event-log tables MUST also be only-increment; if the event log is the truth, the denorm should reconcile UP toward it, never reset to a recomputed current-state ceiling.
- **Prior incidents:** 2026-05-27 diagnose `3a7b9f` — `user_profile.current_rank_code` demoted SD1 → SD2 on Upendra after streak loss; `rank_promotions` event log row for SD1 survived (UNIQUE arbiter), but the denorm was clobbered. Same batch fast-follow (c2 audit) — `user_progress.total_workouts_done` was recomputed by `weekly-recalc/index.ts` from the last 4 WEEKS of workout_log_exercises and overwritten lifetime — silent decrease every Sunday for users training longer than 4 weeks. Both closed via `shouldPromote`-style guards + heal migration 075. `badge_service.dart:32` verified clean during the c2 sweep (`tryUnlock` already guards `!unlocked.containsKey(id.name)` — correctly monotonic by design).

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
