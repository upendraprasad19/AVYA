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
Grep docs/playbook/common-pitfalls.md for an exact-match entry
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
4. **`docs/playbook/common-pitfalls.md` update** only if the bug introduces a new invariant the codebase must enforce forever.
5. **This skill file** updated per §5 self-evolution rule below.

---

## 2. Bug class catalog (seeded — append on each new class)

> **Split 2026-09-29 (context-lean):** the full `### 2.N` bodies now live in [`bug-classes.md`](bug-classes.md) (same directory), verbatim and unrenumbered. This file keeps only the index table below. To use a class: find its id/trigger in the table, then `grep -n "^### 2.N " .claude/skills/debugging/bug-classes.md` and read that entry. Do not load `bug-classes.md` whole. **New classes: append the body to `bug-classes.md` and add one index row here, same commit.** The test column shows the first test path the body cites (`-` = none cited; open the body).

> ⚠ **NUMBERS IN THIS SECTION ARE NOT MONOTONIC IN FILE ORDER, and NINE are
> DUPLICATED** — 2.36, 2.37, 2.38, 2.39, 2.40, 2.41, 2.53, 2.54, 2.55 — each
> naming two unrelated classes. Before adding an entry, get the true maximum:
>
> ```sh
> grep -oE '^### 2\.[0-9]+' .claude/skills/debugging/bug-classes.md | grep -oE '[0-9]+$' | sort -n | tail -1
> ```
>
> **`tail -1` on the file itself gives the LAST-POSITIONED entry, not the
> highest-numbered one.** On 2026-09-07 that mistake minted a second 2.61; it
> was caught in review and renumbered, so 2.61 is NOT in the duplicate list
> above — but it is exactly how the other nine got there. Same shape as the
> OI-number collisions `scripts/check_oi_numbering_unique.dart` exists to catch;
> **no equivalent gate covers `.claude/skills/`.**
>
> ⚠ **Do NOT renumber the nine to tidy them.** Every one is cited by number from
> outside this file — `docs/diagnoses/`, `docs/plans/`, `docs/superpowers/`,
> `docs/plan-reviews/` and `memory/` — and because each number names two
> unrelated classes, a citation cannot be resolved to one of them without
> reading it. Tracked as **OI-167**, whose recommendation is to key on the TITLE
> and treat the number as an optional alias, the way CLAUDE.md rule 24 already
> did for gates.

### Bug-class index (bodies live in `bug-classes.md` - open it and grep the id)

| id | title | trigger | regression test |
|---|---|---|---|
| 2.1 | Writer/reader field drift | "Saved but doesn't appear" / "Receipt shows 0 sets" / "AI snapshot misses meals." Hive... | test/contracts/<x>_write_to_read_contract_test.dart |
| 2.2 | IST date-key drift | Counter resets at midnight UTC instead of midnight IST; receipt for May 5 contains May... | - |
| 2.3 | Cross-account Riverpod / Hive cache race | After signOut + signUp on same session, Edit Profile shows previous user's data; UI sur... | - |
| 2.4 | Partial unique index `ON CONFLICT` trap (two failure modes) | PostgrestException 23505 unique_violation on writes that should be idempotent; orphaned... | test/contracts/sync_natural_key_guard_test.dart |
| 2.5 | Edge Function cold-start retry budget | "AI is temporarily unavailable" / generic 502/503/504 within seconds of an idle period;... | - |
| 2.6 | Vault service-role-key for cron auth | Cron jobs send Authorization: Bearer null → 401 on every tick; cron.job_run_details rep... | - |
| 2.7 | Android Auto-Backup leak across accounts | Fresh sign-up sees previous user's templates / Hive data / PRO status / renewal date on... | - |
| 2.8 | Migration-record pair gap (`applied_migrations.json`) | Pre-commit hook fails or /build-apk Gate 14 blocks; migration exists in supabase/migrat... | - |
| 2.9 | Subagent numeric- AND structural-claim hallucination | A subagent investigation report cites "30/90-day restore window" / "line 47 has X" / "t... | - |
| 2.11 | Repository `box.get(key) → Map` drops Hive key as id (Gate 16 class) | Edit sheet fields blank; downstream consumers (delete, sync, diff) get id=null despite... | gate: scripts/check_id_injection_on_get.dart |
| 2.12 | Rogue Hive key formula bypasses canonical writer | Same logical entity (exercise on a date, meal on a date) appears as multiple rows in th... | gate: scripts/check_exlog_key_canonical.dart |
| 2.13 | Telemetry sink silently drops past rate limit | Server logs show hundreds of telemetry POSTs returning 200 but the storage table has ze... | - |
| 2.14 | Plaintext secret in tracked-or-nearly-tracked source | A .gitignore rule for a secret artifact (*.jks, key.properties, *.p12) exists at one le... | gate: scripts/check_secrets_gitignored.dart |
| 2.15 | Stale generated index (INDEX.md, applied_migrations.json, manifest) | An auto-generated file has fewer entries than the filesystem says it should. dart run s... | - |
| 2.16 | Floating dependency pin | grep -rn '@supabase/supabase-js@\d"' supabase/functions/ returns matches. Sibling Edge... | gate: scripts/check_import_map_present.dart |
| 2.17 | Broken intra-doc pointer (§N #M cite to nonexistent section) | Markdown table "Source" column or prose sentence cites CLAUDE.md §N #M where target sec... | gate: scripts/check_claude_md_citations.dart |
| 2.10 | Provider-invalidation-after-mutation gaps | Write succeeds; UI shows stale value until cold restart; insight card / receipt / calen... | - |
| 2.18 | Source-grep contract test stale after refactor — caught only at `fl... | flutter test red after a refactor that preserves behaviour via a shim/forwarder file. F... | gate: scripts/check_sot_behavioral_test_paths.dart |
| 2.36 | A `DROP` + `CREATE` on a SECURITY DEFINER function RESETS its ACL —... | any migration that changes a function's RETURN TYPE. Postgres raises 42P13 on CREATE OR... | test/contracts/admin_metrics_functions_role_revoke_test.dart |
| 2.37 | A positive grep cannot see a defect in an ARGUMENT | any "surface wiring" test that asserts a file CONTAINS someProvider, someFormatter(, or... | test/contracts/hold_week_identity_behavioral_test.dart |
| 2.38 | Verify one layer FURTHER than the layer you are looking at | "the RPC returns it", "the endpoint responds 200", "the EF spreads the row", "the ACL i... | - |
| 2.39 | A mutation set built only from "delete the protection" is half a proof | a mutation_proven: true ledger entry whose evidence is "deleting the check reddens N te... | - |
| 2.41 | The mutation was ABSORBED — the test is green because something els... | you delete a protection, the tests stay green, and the protection looks obviously load-... | - |
| 2.40 | Mutation-proving runs in the SHARED worktree, where §4.13's guarant... | dispatching mutation agents and read-only reviewers at the same time. | - |
| 2.53 | The Nth fix to one file, each a WIDER GUESS at the same heuristic | a test file fails intermittently, you find the previous fix, and your instinct is to ma... | - |
| 2.54 | A mutation test that passes in BOTH arms proved nothing | proving a fix for a RACE by running it N times under synthetic load, then N times with... | - |
| 2.55 | Your own "quick checks" are load, and can cause the failure you the... | a full suite is running (pre-push, CI-locally, a long background job) and you run dart... | - |
| 2.19 | Monotonic-field demoted by recompute | User "loses" an achievement that should be permanent after their current state regresse... | - |
| 2.20 | Query/select references a column on the wrong table (cross-table dr... | PostgREST 42703 column X.Y does not exist in a .from('X').select('..., Y, ...') or .eq/... | gate: scripts/check_schema_column_refs.dart |
| 2.22 | Trigger side-effect exception aborts the triggering write | An INSERT/UPDATE that should always succeed fails with an error that names a DIFFERENT... | test/contracts/dispatch_proactive_coach_promotion_columns_test.dart |
| 2.21 | User-scoped Hive box read during router redirect / before session open | GoException: Exception during redirect: Bad state: HiveUserSession not opened — cannot... | - |
| 2.23 | Realtime `.stream()` channelError = table not in the supabase_realt... | RealtimeSubscribeException(status: channelError, ...) on a _supabase.client.from('<tabl... | - |
| 2.24 | Edge Function / cron SELECTs columns absent from the live schema →... | A server-side cron/EF "runs" (returns 200, pg_cron reports success) but its EFFECT neve... | - |
| 2.25 | Pause/suppression flag checked at async ENTRY, not at the side-effe... | A "pause" flag (set before some operation) fails to actually suppress the operation's e... | test/contracts/subscription_paused_for_simulation_guard_test.dart |
| 2.26 | Remote dependency rot — an exactly-pinned remote URL removed upstream | An Edge Function deploy that worked last week now fails with HTTP 400 — Module not foun... | test/contracts/no_denoland_zod_import_test.dart |
| 2.27 | Missing backoff-retry on a transient upstream call — server gives u... | An AI/coach feature intermittently returns a generic "I had trouble reaching the model"... | - |
| 2.28 | Sheet/dialog renders a captured value snapshot instead of watching... | A bottom sheet / dialog / card shows STALE state after an action that should update it... | test/contracts/biometric_sync_state_test.dart |
| 2.29 | Overloaded field used as a severity/category proxy → aggregate-quer... | An aggregate count / alert / report silently under- or over-counts because its WHERE cl... | test/contracts/alert_thresholds_sync_test.dart |
| 2.30 | Two cloud representations of one concept drift (table vs snapshot b... | A value looks "missing / expired / never set" but it WAS written — just to a DIFFERENT... | test/contracts/plan_expiry_respects_schedule_test.dart |
| 2.31 | Token freshness inconsistent across Edge Function callers | An authed feature intermittently 401s ("Invalid or expired token") while the Edge Funct... | test/contracts/edge_function_token_freshness_test.dart |
| 2.32 | `REVOKE … FROM <role>` is a no-op while PUBLIC still holds the grant | A SECURITY DEFINER function in the public schema is callable over PostgREST by anon/aut... | test/contracts/security_definer_revoke_migration_test.dart |
| 2.33 | A "replaces X" refactor silently drops a field the readers depend on | A count/history/aggregate surface UNDERCOUNTS live data, but the data exists and a rein... | - |
| 2.34 | Commit-gate hash instability — non-deterministic regen + non-byte-f... | The catastrophic-tier review gate can't be satisfied — the docs/reviews/<hash>-review.m... | - |
| 2.35 | Edge Function auth: user JWT passed as the supabaseKey + bare getUs... | an authed verify_jwt=true Edge Function returns its OWN sanitized 401 ("Invalid or expi... | gate: scripts/check_edge_function_auth_pattern.dart |
| 2.36 | PostgREST builder is a thenable with NO .catch() method | a Deno EF .insert()/.update()/.select() chained with .catch(fn) throws a TypeError (.ca... | - |
| 2.37 | Platform-only native init unguarded by kIsWeb → web boot crash | web boot console: "[main] Firebase/Crashlytics init failed: Null check operator used on... | - |
| 2.38 | Cross-user read need vs own-only RLS → must use a scoped service-ro... | a feature that needs to read OTHER users' rows (a community review queue, a referral-co... | - |
| 2.39 | Native-only plugin reachable on web → user-triggered dead-end | a web user taps a control (e.g. Health Sync "CONNECT") and it hangs / dead-ends — the a... | - |
| 2.40 | Fabricated default persisted into a field a DIFFERENT path consumes... | a value the WRITE site fabricates (x ?? 18.0, ?? 0, ?? 'unknown') looks harmless becaus... | - |
| 2.41 | Cross-migration NOT-NULL writer drift (a later migration tightens a... | an INSERT/RPC that worked (or never ran) starts throwing 23502 null value in column "X"... | - |
| 2.42 | A periodic CLEAR of a ledger destroys a PERMANENT-protection invari... | a value that should be remembered for a long horizon is silently forgotten at a periodi... | - |
| 2.43 | Un-debounced fire-and-forget sync fan-out → free-tier backend collapse | a burst of writes (signup onboarding, heavy logging) produces a flood of cloud calls in... | - |
| 2.45 | Supabase dashboard Site URL overrides client `redirectTo` for email... | Forgot-password / magic-link email points to http://127.0.0.1:<port> or a wrong domain.... | - |
| 2.44 | In-flight async op + account swap → cross-account write at the SINK... | after a same-process A→B account swap (sign-out→sign-in, no app restart), user B's loca... | - |
| 2.46 | GoRouter clears URL fragment before any widget can read it | Password-recovery email link lands on the web SPA with a hash (#type=recovery&access_to... | - |
| 2.47 | A fix's write is placed before its own precondition is met, and a b... | a "fix" that adds a Hive/state write inside a try { ... } catch (_) {} block, where the... | test/contracts/terms_acceptance_behavioral_test.dart |
| 2.48 | A "single convergence point" comment is trusted instead of verified... | a fix adds a fallback/heal into a method whose OWN doc comment claims it's "the single... | - |
| 2.49 | An error fallback picks the DESTRUCTIVE default — "we could not det... | a catch block, or a query whose empty result is ambiguous, returns a domain value rathe... | test/contracts/local_onboarding_evidence_behavioral_test.dart |
| 2.50 | A test asserts on a RESPONSE whose author is not the code you are r... | an assertion on an HTTP/RPC response body fails with the field simply absent (Actual: <... | test/edge_functions/redeem_referral_test.dart |
| 2.61 | Prose that DESCRIBES a state, persisted without the state itself, i... | Bug ID: c5a8f3 · Test: test/contracts/deload_reason_staleness_behavioral_test.dart | test/contracts/deload_reason_staleness_behavioral_test.dart |
| 2.62 | A DECISION boolean reused as an EXPLANATION | Bug ID: d9e1b4 · Test: test/contracts/deload_reason_test.dart | test/contracts/deload_reason_test.dart |
| 2.51 | Moving data out of a wholesale-replaced container into another whol... | a setting the user changed on device A is missing after device B syncs — and nothing er... | test/contracts/notification_prefs_round_trip_behavioral_test.dart |
| 2.52 | A call site is deleted for ONE of its consumers while a second cons... | a compile/type error naming an identifier you are certain you removed on purpose — Cann... | - |
| 2.53 | A MIRROR harness stops modelling production, so it is green in ever... | you toggle the input the batch exists to ship, re-run the measurement harness, and the... | - |
| 2.54 | An invariant is GREEN while the thing it protects is broken, becaus... | a freshly-written invariant test passes, and the user-visible failure it was written to... | - |
| 2.55 | A deliberately SCOPED capability, wired to an UNSCOPED surface | a user changes a setting, the app confirms it ("Reschedule Workouts?"), and nothing obs... | - |
| 2.56 | An inherited environment variable INVERTS a test's assertion instea... | a test asserting that a guard REFUSES something starts failing, and the guard is workin... | test/contracts/git_safety_hook_integration_test.dart |
| 2.57 | A citation is checked in ONE direction only — the claim is never ve... | a commit message (or a diagnose-doc, or an agent's own summary) says "closes OI-NN" / "... | test/scripts/oi_closure_lib_test.dart |
| 2.58 | N providers read ONE store independently; the invalidation list for... | two surfaces render the SAME underlying field differently in the same session — Home sh... | test/contracts/profile_provider_single_source_test.dart |
| 2.59 | A gating read discards its `error`, so the FAILURE path grants acce... | a paid-feature gate that "works" in every test and every manual check, because every te... | test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart |
| 2.60 | A validator SKIPS its real check when a field is unparseable, and r... | a citation, path, or symbol is flat wrong, and a gate that exists precisely to verify t... | - |
| 2.63 | A test bounded by something it does not control — no explicit budge... | CI fails with a bare TimeoutException after 0:00:30.000000: Test timed out after 30 sec... | test/edge_functions/ |
| 2.64 | Measuring a failure's frequency against a sink the failure never re... | you are about to answer *"how often does X actually happen?"* with a query — select cou... | - |
| 2.65 | A shared helper's own swallow-without-rethrow defeats EVERY caller'... | three separate call sites all wrap the same shared method (AuthNotifier.signOut()) in a... | - |
| 2.66 | A NEW site reaches for the "more correct" IST helper where it actua... | two call sites are meant to agree on "the same window" (the same now - N days cutoff),... | - |
| 2.67 | A fail-closed capability/policy filter applied to a population that... | after a safety flag flips ON, a whole class of user-authored items (customs, templates)... | - |
| 2.68 | A display classifier GUESSES from a free-text name when the authori... | a category-tagged DISPLAY surface (quote/tagline/color/filter chip) shows a category th... | - |
| 2.69 | A widget-test `pump()` sequence structurally cannot observe the gap... | a real, plausible one-frame flicker/staleness risk exists in a widget whose initState d... | - |
| 2.70 | A new unconditional shared-box read inside a ubiquitous session-ope... | a merge-commit's regression-catalog walk (or any full-suite run) fails a large, seeming... | test/contracts/nutrition_log_retag_writer_to_reader_test.dart |
| 2.71 | A blind wholesale-replace upsert into a shared jsonb blob silently... | a cron/scheduled job reports SUCCESS (HTTP 200, no error anywhere in its own logs) and... | - |
| 2.72 | A test fixture that commits (or runs git) green on every dev machin... | a subprocess/git e2e test passes locally, targeted AND in the full suite, then fails in... | test/scripts/discipline_hook_main_sync_e2e_test.dart |
| 2.73 | A widget test hangs for 20+ minutes straight through `--timeout 90s... | one flutter_tester.exe sits for 18–26 min on a widget-test file; the runner prints noth... | test/widgets/swap_confirm_sheet_test.dart |
| 2.74 | A `getWeek()`-style reader that omits absent keys cannot drive a se... | a repair/heal path (e.g. PlanIntegrityReconciler.needsHeal) that is supposed to catch a... | test/contracts/restore_plan_json_authoritative_test.dart |
| 2.75 | An input controller with no legitimate prefill source gets seeded f... | a value was logged correctly in ONE field, but the persisted record shows a DIFFERENT f... | test/train/duration_controller_seeding_writer_to_reader_test.dart |
| 2.78 | A NEW call site shares an EXISTING source-grep test's marker litera... | a PRE-EXISTING source-grep contract test — one this batch never touched and has no reas... | test/contracts/sync_natural_key_guard_test.dart |
| 2.76 | A real-time test whose synthetic-clock anchor precedes setup that e... | a test that drives a REAL Timer against a synthetic clock ("start N ms before midnight,... | test/contracts/day_rollover_midnight_timer_test.dart |
| 2.77 | A source-grep test survives not just the dead branch it guards, but... | a guard's literal conditional text (if (x == 'completed' && y == 'planned' && z != null... | test/contracts/sync_schedule_completion_payload_hash_index_writer_to_reader_test.dart |
| 2.79 | A denormalized "cache" column outlives the fix that stopped trusting it; its last readers are the founder's dashboards | a docstring says "the column stays as a cache" / "writing it is fine, reading it as truth ... | test/contracts/subscription_columns_dropped_test.dart |

---

## 3. Red flags — if you're thinking X, STOP

(`§2.N` references below resolve in `bug-classes.md`; §2 here is the index.)

Borrowing from `superpowers:using-superpowers`, `superpowers:systematic-debugging`, and project-specific patterns:

- **"This looks the same as a prior fix — I'll just copy it."** Verify the cited file:line still exists. Memory is point-in-time.
- **"I'll just patch the reader."** Stop. Step 2 demands writer+reader map. The writer might be the actual bug; patching only the reader hides drift forever.
- **"I'll skip the diagnose doc for this one — it's small."** Rule 22 is non-negotiable; pre-commit hook will block you. Bundle the doc into the same `git add` set per `feedback_diagnose_doc_first_in_batch.md`.
- **"It's just a typo / cosmetic fix — no regression test needed."** Rule 21 applies to every `fix:` commit. Source-grep tests count as regression tests.
- **"The subagent said line 47 — let me just go fix line 47."** Read line 47 first. See §2.9.
- **"Context is at 80% — let me hand off to a fresh session."** Banned per `feedback_no_stop_until_done.md`. Use TodoWrite, dispatch focused subagents, compact — but finish the batch.
- **"I'll defer this to a follow-up batch."** Banned per `feedback_no_deferrals.md` + `feedback_no_deferrals_recurrence.md`. Fix all surfaced bugs in the same batch. <!-- deu-quote: bug-class entry quoting the banned phrase it forbids -->
- **"The founder didn't approve explicitly but said 'continue' — let me build the APK."** APK builds require explicit per-build approval per `feedback_apk_build_explicit_approval.md`.
- **"I'll bypass the pre-commit hook with --no-verify."** Banned unless the founder approves per-batch AND a final full-suite gate runs before merge (`feedback_bulk_commit_hook_bypass.md`).
- **"I'm changing onConflict to a new column set — it'll work."** STOP. Verify (a) a UNIQUE index exists on those columns; (b) the index is non-partial OR all arbiter columns are NOT NULL; (c) run a live `INSERT ... ON CONFLICT (...) DO UPDATE` in a rollback transaction and confirm no 42P10. Source-grep contract tests do NOT catch partial-arbiter bugs — see §2.4 mode B.
- **"This `.select(...)` column list looks fine — the field exists."** STOP. Existing *somewhere* ≠ existing on THIS table. Live-verify every selected column against `information_schema.columns` for the queried table (`user_profile` vs `users` is the canonical trap). A pure-unit test fed a hand-built row keyed by the column passes green while the real query 42703s. See §2.20.
- **"The redirect/guard just reads `InductionService.x` / a service getter — it's cheap."** If that getter reads a user-scoped Hive box (`coachBox`, `userBox`, …) and the call is reachable from a GoRouter `redirect` or any pre-`/restoring` path, it can throw "HiveUserSession not opened" at cold start → router error page. `HiveService.isInitialized` is NOT enough; guard `HiveUserSession.currentOwnerFullId != null`. See §2.21.
- **"The subagent's fix introduced a regression but Gate XX caught it — I'll skip the fix-up commit since the gate already passed somehow."** Gate scripts may report FAIL but exit 0 during baselining. Re-run the gate standalone and check `$?`. If `[Gate XX] FAIL` appears in output, ALWAYS fix-up and commit, even if exit code says 0. APK Test #16 caught this nuance via Gate 16.
- **"This sheet/card takes the data as a param and renders it — fine."** If a PROVIDER is the source of truth and the surface renders a value captured at open-time, `invalidateSelf()` won't rebuild it → stale until a remount ("works after navigate-away-and-back" is the tell). Wrap in `Consumer` + `ref.watch`; `await` the mutating callback. See §2.28.
- **"The test greps for the provider name, so the wiring is covered."** No. That token survives a call site that passes `null`. See §2.37 — a 4757-test suite stayed green through it.
- **"The RPC returns the column / the endpoint 200s, so the feature works."** That is true at ONE layer. Name the next consumer and check it. See §2.38.
- **"Mutation-proven — I deleted the check and tests went red."** Half a proof. Reorder it, respell it, and add a NEW unguarded instance beside the guarded one. See §2.39.
- **"I deleted the check and tests stayed green, so the mutation must be wrong."** Usually the TEST is: something else absorbed the damage before it reached the assertion. See §2.41.
- **"`CREATE OR REPLACE` keeps the grants, so I can add a return column."** You cannot — 42P13 forces a DROP, and the DROP resets the ACL. See §2.36.
- **"I'll run the mutations here while the reviewers read."** They will see a tree that matches no commit. See §2.40.
- **"The last fix to this file was nearly right — I'll just widen it."** If this is the second or later fix to one file for one class, the heuristic IS the bug. Ask what signal the code already emits. See §2.53.
- **"It passed 5/5 under load, the fix works."** Did you run the NEUTERED arm? If that also passes, your experiment is blind and the 5/5 means nothing. See §2.54.
- **"The suite is running, I'll just check one thing with `dart run`."** That is load — the dart wrapper serializes on the SDK lock. See §2.55.
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
CLAUDE.md deltas:  <docs/playbook/common-pitfalls.md entry added? new §4 invariant codified?>
Skill deltas:      <new bug class appended to §2? new red flag in §3?>
```

---

## 5. Self-evolution rule (MANDATORY)

When you encounter ANY of the following during a debugging session, append to this file BEFORE marking the session complete:

1. **A new bug class** not in §2 — add a new sub-section to `bug-classes.md` (plus one row in the §2 index table here) with the same shape (telltale, root-cause shape, fix pattern, prior incidents).
2. **A new methodology refinement** — extend §1 step list or add a sub-step. Cite the incident that surfaced the refinement.
3. **A new red flag** — add to §3 with the trigger phrase and the correct response.
4. **A bug class graduates** (3+ recurrences) — link a dedicated `feedback_mistake_*.md` from MEMORY.md and tighten the §2 fix pattern.

If you DO NOT update this file when one of the above applies, the next bug eats the time savings — the whole point of self-evolution is broken. The founder's recurring frustration with writer/reader drift (`feedback_writer_reader_field_drift_recurring.md`) is the canonical example: tribal knowledge that should have been a skill from Test #6 onward but wasn't, costing 6+ batches of re-discovery.

Append-only by default. If you must REWRITE an existing entry (e.g. the fix pattern changed), preserve the prior version in a `### N.X.archived-YYYY-MM-DD` sub-entry with a one-line note on why it was superseded.

---

---

---

## 6. Cross-references

- `docs/playbook/common-pitfalls.md` — the canonical project-side bug list (migrated out of the old CLAUDE.md §19, which no longer exists)
- `CLAUDE.md` §4.4 rule 22 — Diagnose-doc rule
- `CLAUDE.md` rules 20 / 21 — No deferred test failures / Regression test required
- `docs/discipline.md` — L3 checklist
- `docs/sot_registry.yaml` — Single-source-of-truth registry
- `docs/agent_brief_preamble.md` — Subagent prompt prefix for investigations
- `MEMORY.md` — Memory index (grep here first in Step 3)
- `superpowers:systematic-debugging` — Anthropic's general-purpose debugging skill (this skill is the project-specific extension)

---

## Changelog

- **2026-09-27 (day-swapper-sync-load)** — Self-evolution. §2.73 NEW — a widget test hanging straight through `--timeout` is unwrapped real I/O in the `testWidgets` body, not a synchronous product loop (3 hangs in one batch; one misdirected product-loop hunt before bisection found the bare `await box.put`).

- **2026-08-28 (OI-144, same branch)** — Self-evolution. §2.55 NEW — a deliberately SCOPED
  capability wired to an UNSCOPED surface (collect-but-ignore). The Profile picker offered
  13 chips at a tier the capability model never reached; ticking one raised the reschedule
  prompt and returned a byte-identical plan. Carries three sub-lessons: check the COMPLEMENT
  of a deliberate scope (both review passes read the scoped tier, where it works); COUNT the
  gates between input and effect (two independent causes, either fix alone a no-op); and ask
  what a guard was STANDING IN FRONT OF before deleting it (removing the tier gate made
  effectiveItems' fail-open branch reachable). Closes-diagnose: `a9e3c7`. Regression test:
  `test/contracts/equipment_owned_widens_test.dart`, mutation-proven on both legs.

- **2026-08-28 (OI-89 equipment capability batch)** — Self-evolution. §2.53 NEW — a MIRROR harness stops modelling production and is green in every world (the 606-persona scorecard reported byte-identical numbers with the capability flag ON and OFF; `CascadeTracer`/`QueryV4Mirror` never modelled capability, and only the pool DATA was pinned, never the BEHAVIOUR). §2.54 NEW — an invariant green while the thing it protects is broken, because it describes ingredients not output ("≥3 baseline rows per pattern" passed while the generator left 331 empty slots; `pickedNames` dedup exhausts a 3-row pool inside one week). Both were found by MEASUREMENT after the ×2 plan review had converged, which is the transferable point: a converged review does not substitute for running the thing. Closes-diagnose: `f7b2c4`. Regression tests: `test/contracts/equipment_tier_consistency_test.dart` (per-pattern floor), `test/plan_generator/scorecard_gate_test.dart` (equipment violations promoted from ≤201 to a hard ==0).

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
- **2026-06-26 (E2E fix-wave Unit F + AI-snapshot self-evolution)** — Self-evolution. §2.9 BROADENED from numeric- to also **structural**-claim hallucination — a subagent's false **absence** claim ("no writer emits X", "this branch is dead / always 0") is the dangerous one: acting on it ships a WRONG fix that breaks the correct path. Founding case: the AI-snapshot fix (`f3c8d1`) nearly shipped a wrong `planned_this_week` fix on a false "no writer emits `type=='workout'`" claim — the writer is `workout_schedule_read_service.dart:160`; the `hive_key_contracts` test + reader-manifest/Gate-19 caught it (3 commit attempts) but those are the LAST line, not the first (one grep for the writer is the first). No new bug fix this entry (the f3c8d1 fix shipped 2026-06-26 `8fe667b`; Unit F `f27ec5f` is the docs/ADR-0016/handbook/charter closure). See `feedback_audit_verifier_cannot_trust_own_subagent.md`.
- **2026-07-23 (password-reset timing hole batch)** — Self-evolution. §2.46 NEW — GoRouter clears URL fragment before any widget can read it (timing-ordering bug: GoRouter's `initialLocation` calls `history.replaceState()` during `runApp()`, stripping the URL hash before `initState` fires). Distinction from §2.45 reinforced: §2.45 is about LINK GENERATION (Supabase dashboard Site URL override); §2.46 is about IN-APP HANDLING of the resulting redirect (fragment consumed by GoRouter before widget code runs). Fix: fragment capture in `main()` before `runApp()`, stash tokens, manually call `auth.setSession()` after `Supabase.initialize()`. Both author and code-review missed it — no timing-ordering lens existed. Closes-diagnose: `9f5c41`. Regression test: `test/contracts/password_reset_redirect_flow_test.dart` (updated, 13/13). Memory: `feedback_mistake_go_router_clears_url_fragment_before_widget.md`.
- **2026-08-02 (terms-accepted-fix batch)** — Self-evolution. §2.47 NEW — A fix's write is placed before its own precondition is met, and a broad `catch(_){}` swallows the resulting throw. Founding case: the 2026-05-16 fix for `users.terms_accepted_at`/`terms_version` wrote to `HiveService.instance.userBox` at CREATE ACCOUNT tap time — before `HiveUserSession.openForUser` had ever run — so the write threw `StateError` on 100% of signups for 2.5 months, silently swallowed. Founder discovered it by manually browsing the live Supabase dashboard; live SQL confirmed the 10 most recent signups (including one from the same day) were all still NULL. The original fix's own regression test was pure source-grep and structurally could not have caught a runtime throw — the founding case for why `presence_only: true` SoT entries need a real behavioral test, not just this class's discovery. Nearest neighbors: §2.21 (read-side sibling — user-scoped box READ before session open) and §2.25 (related but distinct — guard-the-sink-not-the-entry is about a flag not suppressing an in-flight call, this is about a write's precondition never being met at its call site at all). Fix relocated the write into `_ensureLocalUser` post-`openForUser`, added a Google-OAuth/phone-OTP fallback in `AuthSessionBootstrapper.hydrateFromCloud` (neither auth path had ANY consent write), and replaced the source-grep-only test with a real Hive round-trip. Closes-diagnose: `b3f9e7`. Regression test: `test/contracts/terms_acceptance_behavioral_test.dart`. SoT registry `terms_acceptance` flipped `presence_only: true` → `false`.
- **2026-08-02 (terms-accepted-fix batch, plan-review round 1 correction — same day, same diagnose)** — Self-evolution. §2.48 NEW — A "single convergence point" comment is trusted instead of verified; the fallback wired into it silently never runs for the one path that needed it most. The §2.47 fix's own Part B (OAuth/phone-OTP fallback) was wired ONLY into `AuthSessionBootstrapper.hydrateFromCloud`, whose doc comment claims it's "the single place every post-auth path converges on." A dedicated ×2 plan-review round (§4.12) traced the actual call graph and found that claim false for Google OAuth: `signInWithGoogle()` never reaches `hydrateFromCloud` (it only starts the OAuth redirect and returns); the real post-redirect re-entry is `RestoringScreen`, which calls `resolveDestination` + `restoreFromCloudForUser`, neither of which is `hydrateFromCloud`. Net effect: phone OTP was genuinely fixed (it DOES reach `hydrateFromCloud`), but Google OAuth — the plan's own named urgent, live-in-prod-today reason NOT to defer Part B — was left with the exact pre-fix defect. Notably, the batch's own internal B-pass review (5-lens line-level pass, run BEFORE the plan-review round) had already independently found the single-call-site fact while investigating a different question, but characterized it as unrelated stale documentation rather than a correctness gap — one more inferential hop (which callers reach that one call site) was needed and a line-level lens set isn't structured to take it. Fix: extracted `AuthSessionBootstrapper.ensureTermsConsentFallback(userId)` as a standalone method, called from BOTH `hydrateFromCloud` (phone OTP) AND `RestoringScreen`'s returning-user path (Google OAuth's real convergence point, after `HiveUserSession.openForUser`). Closes-diagnose: `b3f9e7` (same bug id — this is a same-day, pre-merge correction of the fix, not a new bug). Regression test added: `terms_acceptance_writer_to_reader_test.dart`'s new "restoring_screen calls ensureTermsConsentFallback" case. Plan-review record: `docs/plan-reviews/terms-accepted-fix.md`.
