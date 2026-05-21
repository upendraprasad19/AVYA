# Audit Lens Registry

> **Sibling to `AUDIT_PLAYBOOK.md`.** Playbook is process discipline (two passes, dedup, live verification). This file is the **what-to-look-for checklist** — every comprehensive audit dispatches at least one subagent per lens.
>
> **History:** lenses L1-L13 were inferred from default 5-domain audits + 2026-05-12 Master+Codex dual-pass. L14-L26 were surfaced by external "Hermes" cross-check on 2026-05-11 (`feedback_audit_methodology_lenses.md` R1+R2). L27-L34 were surfaced by Hermes audit on 2026-05-17 + reasoning over Tests #11-#16 bug patterns. Memory file is authoritative; this file is the dispatch checklist.

---

## How to use

1. Pick the lens set: `--all` (33 lenses) for quarterly comprehensive; `--security` (L2/L21/L23/L29) for pre-launch; `--p0-blockers` (L1/L21/L22/L23) for emergency triage.
2. For each selected lens, dispatch one subagent with the **charter template** below.
3. Aggregate findings in `docs/audit/<date>/findings-by-lens.md` keyed by lens number.
4. Apply `AUDIT_PLAYBOOK.md` verification + dedup discipline before acting.
5. Update the **last-run** column at the bottom after each audit.

**Charter template:**

```
You are running lens L<N>: <name>. Scope: <charter>.
Trigger condition: <when this lens is checked>.
Output format: list every finding with file:line + verbatim quote + REAL/FALSE_ALARM/PARTIAL
verdict. Cite the precedent below if your finding matches a known bug class.
Cap report at 800 words. Do NOT propose fixes — that's the consolidation phase.
```

---

## L1-L20 — Default + already-in-charter

| # | Lens | Charter | Last burned |
|---|---|---|---|
| L1 | Writer/reader drift | Every WriteService output field → every consumer reads it. Source-grep + contract test must pin SEMANTICS not just presence. | Tests #6 → #15.3 → #16.1 (7 instances; see `feedback_writer_reader_field_drift_recurring.md`) |
| L2 | RLS table-level | Every public table has a policy; no `USING (true)` on user-tagged tables. | OI-12 (2026-05-17): 0 P0 leaks; 2 P1 functional gaps closed via migration 069. |
| L3 | Edge Function input validation parity | Each function validates length, MIME, JWT, rate limit. | OI-14 (2026-05-17): 1 false alarm; verified per `feedback_audit_findings_require_live_verification.md`. |
| L4 | Cron auth + telemetry | Every cron-triggered function gates `isAuthorizedCronCall(req)` + logs start/end. | OI-11 + OI-15 (2026-05-17): 4 functions retrofitted; 8+ remain (tracked as OI-21). |
| L5 | Storage cost + bucket hygiene | Bucket count, object count, orphans, cost per user. | OI-18 (2026-05-17): 4 buckets / 20 objects / 4.01 MB / $0; coach-media bucket missing (OI-23). |
| L6 | Hive compaction coverage | Every mutation-heavy box runs `compact()` on lifecycle hook. | OI-17 (2026-05-17): 8 boxes GREEN. |
| L7 | Dead-code / dead-column purge | Constants/methods/columns with 0 readers → delete. | E.12 (2026-05-16): 17 columns dropped via migration 067; 3 constants + 1 method + 1 route deleted. |
| L8 | Contract test coverage gap | Every SoT registry entry has a round-trip test. | Test #16.2 (2026-05-16): SoT registry 36 → 41. |
| L9 | IST-throughout | Every date key + cloud `date` column + counter reset uses IST helpers. | Test #15.4 / B1, Test #12 / Task A-1. See `feedback_use_ist_throughout.md`. |
| L10 | SoT registry completeness | Every "single reader" concept in `docs/sot_registry.yaml`. | Test #16.2: 41 entries. |
| L11 | Restore-completeness sync | Every Hive surface paying users lose on reinstall has cloud table + sync write + restore method + contract test. | Test #11 / Theme A (3 surfaces); Test #15.3 / Bug 4a (template restore). |
| L12 | Subscription server-verification | High-value features call `verifyFromServer()`. | Test #12 / Themes C-1..C-4. See CLAUDE.md §10. |
| L13 | Migration apply pair-update | Every `apply_migration` MCP call paired with `backups/applied_migrations.json` update. | See `feedback_migration_apply_record_pair.md`. |
| L14 | onConflict natural-key live arbiter | Every `ON CONFLICT` shape resolves against live schema in rollback txn. | Test #16 / migration 064. See `feedback_partial_unique_arbiter_trap.md`. |
| L15 | Cross-account session ownership (Hive) | Every user-scoped Hive read goes through `wrapUserScopedBox`; writers respect `HiveUserSession`. | Test #15.4 / B1 (two-layer fix). |
| L16 | Riverpod auth-token watch | Every user-scoped provider `build()` watches `authUserIdTokenProvider`. | Test #15.3 / Bug 5 (`c4055a`): 56 providers retrofitted. |
| L17 | Subagent-finding live verification | No multi-agent finding actioned without file:line read + live SQL. | See `feedback_audit_findings_require_live_verification.md`. |
| L18 | Skipped test classification | Every `skip:` directive has documented reason + reopening criterion. | OI-13 (2026-05-17): 74 skips verified intentional Phase 7 scaffolds. |
| L19 | APK size delta gate | Build size within ±10% of last shipped. | Gate 13 (`scripts/check_apk_size_within_bounds.dart`). Note: silent-skip when APK missing — see L24. |
| L20 | Diagnose-doc + memory pair | Every `fix:` commit pairs with `docs/diagnoses/...` + memory update for new patterns. | CLAUDE.md rule 22. |

---

## L21-L25 — Surfaced by Hermes audit 2026-05-17 (this report)

| # | Lens | Charter | Trigger | Precedent |
|---|---|---|---|---|
| **L21** | **Edge Function semantic correctness** | Read each Edge Function top-to-bottom. Catch: variable hoisting / TDZ, unreachable branches, missing `await`, exception swallowing, dead `if` arms, async returning before mutation completes. | One subagent per function-group (3-5 functions each). | F1 (razorpay-webhook line 301 uses `supabaseClient` before line 431 const declaration → `ReferenceError` on every webhook invocation). My first verification subagent missed this by conflating source order with execution order. |
| **L22** | **Schema-vs-payload parity** | For each NOT NULL column added by any migration, grep every `.from('<table>').insert\|upsert\|update` callsite and assert the column is present in the payload (not just typed in the API). | After every migration that touches column nullability. Permanent gate: `scripts/check_schema_payload_parity.dart`. | F2 (migration 052 made `razorpay_signature` NOT NULL; verify-payment upsert at lines 410-439 never sends it → 23502 on every fallback path). |
| **L23** | **Authorization defense-in-depth on service-role paths** | For each Edge Function that uses `SUPABASE_SERVICE_ROLE_KEY`, grep every privileged read/write and assert user-scope check immediately precedes it. RLS does NOT apply to service role; the application code is the only guard. | One subagent per function using service role. | F3 (ai-media-proxy only checks URL prefix, not user-scope on path → user A can fetch user B's Storage object). F4 (verify-payment fail-open when `notes.user_id` absent). |
| **L24** | **Gate-strictness** | For each `scripts/check_*.dart`, audit every `exit(0)` to assert it's a legitimate skip with documented condition. `exit(0)` on "file not found" or "snapshot not present" is almost always wrong in CI. | Before any release / build. Manual once per quarter; permanent meta-script idea: `scripts/audit_all_gates.dart`. | F8 (`check_apk_size_within_bounds.dart` exits 0 when APK missing). F9 (`check_migrations_applied.dart` compares snapshot file, not live DB — self-documented TODO). |
| **L25** | **Intra-document drift** | Grep CLAUDE.md / AGENTS.md for known-drift pairs (table count, migration count, edge function count, rank count, tier feature lists). Fail if any two surfaces disagree. | Permanent gate: `scripts/check_doc_internal_consistency.dart`. | F10 (CLAUDE.md §2:130 says "21 tables", §7:380 says "46 tables" — §7 bumped 2026-05-11 didn't propagate to §2 quick-summary). |

---

## L26-L33 — From `feedback_audit_methodology_lenses.md` R1/R2 (2026-05-11) + this report

These came in via 2026-05-11 Hermes Round 1/2 and were documented in memory but never collated into a canonical playbook checklist. Adding them now.

| # | Lens | Charter | Precedent |
|---|---|---|---|
| **L26** | **CQRS / pure-function discipline** | For every method whose name reads like a query (`get*`, `calculate*`, `read*`, `is*`, `has*`), trace whether it actually mutates state. Side-effect-on-read produces unreproducible bugs because the path is through provider rebuilds, not user actions. | `calculateCurrentStreak()` at `workout_repository.dart:157-246` consumed streak freezes from 4 read-only call sites (UI rebuilds + rank evaluation). Per `feedback_audit_methodology_lenses.md` R2#1. |
| **L27** | **Concurrency on shared state** | For every `getX() → modify → setX()` pattern on shared Hive/Postgres state, identify ALL writers. If ≥2 writers with no atomicity (compareAndSet, version field, RPC, mutex), it's a lost-update race. | Streak freezes refill ↔ consume race per memory R2#2. |
| **L28** | **Service-level invariants** | For every business rule (e.g. "no 3+ consecutive rest days", "max 1 freeze per missed day"), identify whether the rule is enforced at the service layer or only at the UI. UI-only enforcement = backdoor via any new entry point (AI tool, migrator, restore, deep link). | `swapDays()` consecutive-rest guard was UI-only per memory R2#5. |
| **L29** | **Endpoint rate-limit matrix** | Build a table: rows = endpoints, columns = (server limit, client limit, response when over, telemetry on over). Audit annually. | Test #12 audit found drift between client `food_text_analysis` advisory limit and Postgres `trg_food_text_rate_limit`. Test #16.1 D fixed `log-client-error` silent-drop. Per memory R2#3 + this report's gap analysis. |
| **L30** | **Prompt input sanitization** | Every `'$userField'` or `${userField}` interpolation into an LLM prompt is a potential injection vector. Strip control chars, allowlist chars, cap length. | `PredictionService` interpolates user `name` into AI prompt without sanitization (memory R2#7). |
| **L31** | **Cron job efficiency** | Every cron should have a "skip if no change" predicate, not "recompute everything every run". Growing user base flips "acceptable today" to "billing alert" silently. | Per memory R2#11. |
| **L32** | **Telemetry data quality** | Accepting telemetry isn't the same as receiving useful telemetry. If client sends `error.runtimeType.toString()`, the DB fills with `String`, `_Map<String, dynamic>`, `TypeError`. Audit whether stored data is queryable. | `log-client-error` accepted any error code (memory R2#4). Audit P2-G (2026-05-12) added stack to telemetry. |
| **L33** | **Cold-start perf** | Sequential awaits in `init()` before `runApp()`. Each ms costs time-to-first-frame. | Hive boxes opened sequentially at `hive_service.dart:74-76` (memory R1#1; 150-300 ms cold-start win). |

---

## L34-L41 — New for next audit (from this report's "additional gaps" section)

These don't yet have a precedent in our bug history but match patterns that *will* burn us — adding them prophylactically.

| # | Lens | Charter | Precedent (anticipated) |
|---|---|---|---|
| **L34** | **Telemetry coverage on async failure legs** | Grep `unawaited(` across `lib/`. For each callsite, the awaited future must have an error sink in either the function or a `.catchError(...)` decorator. | Test #16.1 D was a silent drop on the telemetry sink itself. Test #12.6 was 30+ silent restore failures. Worst class = silent loss of observability. |
| **L35** | **Migration reversibility / forward-compat** | For each migration touching column nullability / type / drop, list every callsite that writes/reads that column AND confirm at least one prior app version remains compatible (or document the breaking window). | Migration 064 worked because of 0 actual nulls; next migration might not. Migration 067 dropped 17 dead columns — fine but contract test coverage was post-hoc. |
| **L36** | **Idempotency replay completeness** | For each replay-able write (webhook, cron, retry), simulate 3 replays in test and assert end-state byte-equal. | razorpay-webhook hardened in Test #11 / Theme I1. verify-payment + redeem-referral never explicitly pinned. |
| **L37** | **Empty-state / null-shape readers** | For every consumer of a writer's output, contract test must include `empty | malformed | missing-key | wrong-type` cases. | Test #15.3 Bug 1 / Bug 4c / Bug 6 were all reader assumptions about writer shape. |
| **L38** | **Cross-account state leak beyond Hive** | Enumerate every in-memory singleton (NavigatorObserver state, ValueNotifiers, static Maps) + every 3rd-party SDK's user-tagged state (Crashlytics user_id, OneSignal external_id, Razorpay session cookies, WebView cookies). For each, assert signOut clears it. | Test #15.4 / B1 closed Riverpod cache + Hive box scope. SDK state never swept. |
| **L39** | **Backup/restore round-trip completeness** | Assert every `syncX` in `sync_service.dart` part files has paired `_restoreX` + that `test/contracts/restore_completeness_writes_test.dart` covers it. Source-grep gate idea: `scripts/check_restore_round_trip_coverage.dart`. | Test #12.8 found 6 of 16 `_restoreXxx` methods keyed wrong fields. |
| **L40** | **PII / privacy in telemetry payloads** | Grep every `logEvent` / `recordNonFatal` callsite; classify each as `NoPII | UserText | UserMedia | UserHealth`. Reject UserHealth/UserMedia unless explicitly allowlisted. Permanent gate idea: `scripts/check_telemetry_pii_classification.dart`. | DPDP / GDPR risk; not yet burned but high-blast-radius. |
| **L41** | **Cross-document semantic consistency** (cleanup-cron vs migration intent) | For every cleanup cron, cross-reference the migration that defines the bucket/table purpose. Cleanup targeting "long-term consented" bucket = silent data loss. | F5 in this report (`clean-orphan-media` scans `coach-media`; migration 070 designates it long-term). |

---

## Lenses considered + rejected (re-evaluate quarterly)

| # | Lens | Why deferred |
|---|---|---|
| L42? | Hot-path perf budget (cold-start, restore-screen, splash) | We have correctness tests; no perf budget. Adding instrumentation needs Firebase Performance Monitoring wiring first. |
| L43? | Dependency vulnerability scan (`flutter pub outdated`, `npm audit`) | Quarterly cadence, not per-audit. |
| L44? | A11y semantic audit | Not prioritized until first paying user requests / Play Store warning. |
| L45? | Documentation rot — "Closed in Test #N" claims still true | Needs tooling to repro the fix's absence; defer until tool exists. |

---

## L42-L53 — Added by tech-debt audit 2026-05-20 / Batch 1

These lenses correspond to the 10 new gate scripts created during B1 of the 2026-05-20 tech-debt remediation. Each has a permanent `scripts/check_*.dart` enforcer wired into pre-commit + CI.

| # | Lens | Charter | Gate script | Regression test | Precedent |
|---|---|---|---|---|---|
| **L42** | **Secrets in tree (defense-in-depth)** | Sensitive files (keystores, `key.properties`, `*.p12`) are matched by SOME `.gitignore` at SOME level (verified via `git check-ignore -v`); credential-shaped literals absent from tracked source. | `scripts/check_secrets_gitignored.dart` (Gate 23) | `test/contracts/secrets_not_tracked_test.dart` (lands later in B1) | I1 (audit 2026-05-20) — initial P0 flag was a false alarm; root-level `.gitignore` added as defense-in-depth. See `feedback_secrets_pattern_audit_before_first_push.md`. |
| **L43** | **Razorpay key matches flavor** | `.env.prod` carries `rzp_live_*` only; `.env.dev` carries `rzp_test_*`. | `scripts/check_razorpay_key_flavor.dart` (Gate 24) | (gate is the test) | I14 (audit 2026-05-20) — `.env.prod` currently carries `rzp_test_` prefix; user-only blocker. |
| **L44** | **Generated-index staleness** | `docs/diagnoses/INDEX.md` enumerates every diagnose-doc on disk by bug ID. | `scripts/check_diagnose_index_fresh.dart` (Gate 25) | (gate is the test) | Doc2 (audit 2026-05-20) — 152 diagnose-docs vs ~40 in stale INDEX; closed B1. |
| **L45** | **Doc-citation rot** | Every `§N #M` cite across CLAUDE.md / AGENTS.md / nested CLAUDE.md resolves to a heading that exists. | `scripts/check_claude_md_citations.dart` (Gate 26) | (gate is the test) | Doc6 (audit 2026-05-20) — 44 broken `§19` cites across 12 files; swept B1. |
| **L46** | **Import-map pinned** | `supabase/functions/import_map.json` exists + every shared dep pinned to exact version; no floating `@N` pins in any function source. | `scripts/check_import_map_present.dart` (Gate 27) | (gate is the test) | D2/D3 (audit 2026-05-20) — 4 floating `@2` pins + no import_map; created + pinned B1. |
| **L47** | **Crypto-lib minimum version** | `jose` ≥ 5.9 across every Edge Function. | `scripts/check_jose_version.dart` (Gate 28) | (gate is the test) | D12 (audit 2026-05-20) — `jose@5.6.3` in `cron_auth.ts:54`; bumped to 5.9.6 in B1. |
| **L48** | **Client-error spike alert** | `supabase/alerts/client_errors.yaml` declares threshold + notify channel. | `scripts/check_client_errors_alert.dart` (Gate 29) | (gate is the test) | I4 (audit 2026-05-20) — no alert; created scaffold in B1; pg_cron alerting job lands B3. |
| **L49** | **Crashlytics alert routing** | `android/app/firebase-alerts.json` documents velocity + ANR thresholds + notify channel. | `scripts/check_crashlytics_alert_routing.dart` (Gate 30) | (gate is the test) | I9 (audit 2026-05-20) — scaffold created B1; console config TODO. |
| **L50** | **Cron-registry parity** | Every `cron.schedule('NAME',...)` in `supabase/migrations/*.sql` listed in `docs/operations/CRON_REGISTRY.md`. | `scripts/check_cron_registry.dart` (Gate 31) | `test/contracts/cron_registry_parity_test.dart` (lands later in B1) | I5 (audit 2026-05-20) — registry created + populated B1; 6 active jobs registered. |
| **L51** | **Pre-commit hook installed** | `.git/hooks/pre-commit` is installed and invokes `scripts/pre-commit.sh`. | `scripts/check_hooks_installed.dart` (Gate 32) | (gate is the test) | I8 (audit 2026-05-20) — opt-in install never verified; gated B1. |
| **L52** | **Gate scripts wired** | Every `scripts/check_*.dart` is invoked from BOTH `scripts/pre-commit.sh` AND `.github/workflows/test.yml` (or appears in the allow-list for build-only / advisory gates). | `scripts/check_gate_scripts_wired.dart` (Gate 33) | (gate is the test) | I2 (audit 2026-05-20) — 25 of 27 gates were dormant; dynamic-loop wired B1. |
| **L53** | **Edge Function deploy reversibility** | Every Edge Function deploy is reversible in one command (no `git checkout` under pressure). Deployer supports `--rollback <fn> <sha-or-previous>`, archives last 3 payloads under `backups/edge_function_payloads/<fn>/`, runs a post-deploy smoke check against the live function URL. | `scripts/check_edge_function_rollback_script.dart` (Gate 38) | `docs/runbooks/edge-function-rollback.md` | I3 (audit 2026-05-20) — deploys were forward-only; MTTR for a bad deploy was unbounded (`git checkout <SHA>` + re-emit + redeploy under pressure). Closed B3 with git-SHA rollback path, post-deploy smoke step, and 3-deep payload archive. |

---

## Last-run tracker

| Date | Lenses run | Findings | Notes |
|------|-----------|----------|-------|
| 2026-05-11 | L1-L13 (default 5 + R1+R2 partial) | 11 + 12 from Hermes cross-check | First time cross-check used. |
| 2026-05-12 | L1-L13 (Master + Codex dual-pass) | 25 — 3 false alarms | Vault root cause caught by Master only. |
| 2026-05-16 | L1, L7, L8, L10, L14 (Test #16.2 batch lens-set) | 22 findings; 11 diagnose-docs | First full E.* audit. |
| 2026-05-17 | L2, L4, L5, L6, L18, L19 (OI closures) | 8 closures + 3 deferred (OI-21/23/24) | Operational hardening. |
| 2026-05-17 (Hermes verification) | L21-L25 + L41 (NEW) | 13 REAL, 4 FALSE_ALARM, 3 PARTIAL | Drove this registry's creation. |
| 2026-05-20–21 | L1–L52 (6-category tech-debt audit + B1 ship) | 81 findings; 0 deferrals; 10 new gates (L42–L52) | First explicit zero-deferral audit; closure YAML format introduced. |
| **Next audit** | **L1-L53 (all 53)** | TBD | Quarterly cadence per CLAUDE.md §4.10; first scheduled 2026-08-03. |
