# Tech-debt audit 2026-09-02 — findings by lens

Baseline: `a2a7694c` (main). Trigger: CLAUDE.md §4.10 "after any 3+-batch landing".
Dispatch: 6 parallel Opus subagents (Infrastructure → Architecture → Test → Code → Dependency → Documentation),
per `.claude/skills/tech-debt-audit/SKILL.md` step 2.

Baseline gate state: `bash scripts/pre-commit.sh` → **PASS** ("All decluttering gates passed", exit 0),
run in this worktree at `a2a7694c`. An earlier run reporting 29 gate failures was an ARTIFACT — the
harness auto-cleaned the (unchanged) worktree mid-run and the gate loop was reading deleted files.
Mitigation applied: this worktree was dirtied immediately after creation. See §4.13 point 6.

Priority formula (skill step 3): `(Impact + Risk) × (6 − Effort)`.

Verification policy: every number below marked **[verified]** was measured by the MAIN THREAD, not
taken from the subagent. Per `feedback_audit_verifier_cannot_trust_own_subagent.md` + CLAUDE.md §4.9,
subagent numerics are unverified until re-derived.

---

## Seeded findings (founder-declared, then independently confirmed)

### INFRA-SEED-1 — no generic SAST scanner in CI — **[verified]**
- **Evidence:** `grep -rniE "npm audit|osv-scanner|snyk|trivy|grype|dependency-check|pub audit|semgrep|opengrep|codeql|gitleaks" .github/ scripts/` → **0 hits**.
- The ~95 `scripts/check_*.dart` gates are bespoke bug-class detectors, not a general security ruleset.
- Confirmed independently by the Dependency agent as DEP-5. Terminal state required per §4.2.

---

## DEPENDENCY (agent returned 13; priority-ranked)

| ID | Title | I | R | E | Priority | Verdict |
|---|---|---|---|---|---|---|
| DEP-5 | No vulnerability scanning of any kind; Dependabot covers 2 of 4 ecosystems | 4 | 4 | 2 | **32** | REAL **[verified]** |
| DEP-8 | CI builds APK on JDK 17; dev machine + CLAUDE.md require JDK 21 | 3 | 3 | 1 | **30** | REAL **[verified]** |
| DEP-2 | `@supabase/supabase-js` at 3 versions across live EFs | 3 | 3 | 2 | 24 | REAL **[verified]** |
| DEP-3 | 3 `deno.land/std` versions, oldest on the payment path | 3 | 3 | 2 | 24 | REAL **[verified]** |
| DEP-9 | `deno.lock` untracked — 105 integrity hashes exist only on one machine | 3 | 3 | 2 | 24 | REAL **[verified]** |
| DEP-1 | `import_map.json` is inert — nothing resolves through it | 4 | 3 | 3 | 21 | REAL **[verified]** |
| DEP-6 | 84 packages locked below available; 11 direct constraints below resolvable | 3 | 2 | 2 | 20 | REAL |
| DEP-4 | L47 (`jose` ≥5.9) vacuously satisfied — jose imported nowhere | 2 | 1 | 1 | 15 | PARTIAL |
| DEP-7 | `share_plus ^13` block appears to have LIFTED | 2 | 1 | 1 | 15 | REAL (state change) |
| DEP-11 | 3 unused direct deps (`riverpod_annotation`, `cupertino_icons`, `pg`) | 2 | 1 | 1 | 15 | REAL |
| DEP-10 | Flutter 3.41.4 pinned consistently but ~6 months old | 2 | 2 | 3 | 12 | PARTIAL |
| DEP-13 | `cached_network_image` + `go_router` need major migrations | 2 | 2 | 3 | 12 | REAL |
| DEP-12 | GPL/AGPL exposure — 4 matches all MPL-2.0 false positives | 1 | 1 | 1 | 5 | FALSE_ALARM |

### Main-thread verification log (commands + real output)

- **DEP-5 [verified]** — SAST/SCA grep → `0`. `.github/dependabot.yml` ecosystems: `pub` (line 13),
  `github-actions` (line 51). No `npm`, no Deno. **Both the SAST and SCA gaps are real.**
- **DEP-8 [verified]** — `.github/workflows/test.yml:494` → `java-version: '17'`.
  Local `java -version` → `openjdk version "21.0.12.1" 2026-08-18 LTS`. Divergence confirmed.
- **DEP-2 [verified]** — measured spread: **37×** `supabase-js@2.39.3`, **1×** `@2.42.0`, **2×** `@2.45.4`.
  (Agent said "35 others"; real count is 37. Direction correct, count drifted.)
- **DEP-3 [verified]** — measured spread: **9×** `std@0.177.0`, **3×** `std@0.208.0`, **62×** `std@0.224.0`.
  (Agent said 60 for 0.224.0; real is 62.)
- **DEP-1 [verified]** — `grep -rnE 'from "(jose|zod|std/|@supabase/supabase-js)' supabase/functions` → **0**.
  Nothing imports via an alias, so the map resolves nothing. Gate 27 asserts the file exists, not that it is used.
- **DEP-9 [verified]** — `git ls-files deno.lock` → `0`; `git check-ignore -v deno.lock` → `.gitignore:140`.

### Not yet main-thread verified
DEP-4, DEP-6, DEP-7, DEP-10, DEP-11, DEP-12, DEP-13 — agent-cited only. Verify before any lands
a terminal state. DEP-7 in particular CONTRADICTS `project_share_plus_13_blocked.md` and needs a
real resolve, not the solver's `Resolvable` column.

---

## INFRASTRUCTURE (agent returned 11; ×1.2 weight per feedback_operational_observability_first.md)

| ID | Title | I | R | E | Priority | Verdict |
|---|---|---|---|---|---|---|
| INFRA-2 | 5 gates allow-listed as "runs in /build-apk" — `build-apk.md` invokes none; they run NOWHERE | 5 | 4 | 2 | **36** | REAL **[verified]** |
| INFRA-1 | No SAST/security scanner anywhere in CI, Dart or Deno | 4 | 4 | 2 | **32** | REAL **[verified]** |
| INFRA-4 | Gate 42 silently passes if `sot_registry.yaml` is renamed/moved | 3 | 2 | 1 | 25 | REAL |
| INFRA-5 | 20 unacked client-error alerts, newest 37 days old; no ack path | 3 | 3 | 2 | 24 | PARTIAL |
| INFRA-11 | Gate 33's allowlist is unverified free-text prose — the MECHANISM behind INFRA-2 | 4 | 3 | 3 | 21 | REAL **[verified]** |
| INFRA-7 | 14 nested `CLAUDE.md` (207 KB) outside the context-artifact budget guarding the root one | 3 | 2 | 2 | 20 | REAL |
| INFRA-3 | Gate counts stale in 3 places; real = 95 | 2 | 1 | 1 | 15 | REAL **[verified]** |
| INFRA-6 | Crashlytics gate checks a JSON file's key names, not live delivery | 2 | 3 | 3 | 15 | PARTIAL |
| INFRA-8 | Cron registry parity — all 28 jobs documented | 1 | 1 | 1 | — | FALSE_ALARM (Gate 31 holding) |
| INFRA-9 | Cron telemetry adoption effectively complete | 1 | 1 | 1 | — | FALSE_ALARM (allowlist unverified) |
| INFRA-10 | No secrets tracked in working tree | 1 | 1 | 1 | — | FALSE_ALARM (verified clean) |

### INFRA-2 main-thread verification (decisive — priority 36)

Claim chain verified end to end:
1. `scripts/check_gate_scripts_wired.dart:70-71` → `'check_two_user_cross_account.dart': 'Requires live DB
   rollback-txn — runs in /build-apk skill alongside check_onconflict_live_arbiter.dart …'`
2. `.claude/commands/build-apk.md` is the ONLY build-apk surface — `.claude/skills/build-apk/SKILL.md`
   does **not exist** (checked, because a wrong-file grep would have made this a false alarm).
3. All five gates → **0** occurrences in `build-apk.md`.
   **Positive control:** `check_apk_size_within_bounds` → 1, `check_apk_release_signed` → 1. The file
   does name gates; these five are genuinely absent.
4. Their only occurrences in the runners are SKIP entries, not invocations:
   `scripts/pre-commit.sh:331-335` and `.github/workflows/test.yml:242-245`, inside the `|\` skip alternation.

**Conclusion: `check_migrations_live`, `check_onconflict_live_arbiter`, `check_two_user_cross_account`,
`check_snapshot_contract`, `check_unawaited_has_error_sink` execute in NO runner.** Two are
security-relevant (cross-account isolation; onConflict live arbiter). Same class as the precedent
that file documents for `check_telemetry_pii_classification` ("Advisory described how it reports, not
where it runs, and nothing ran it").

**INFRA-11 is the mechanism, not a duplicate:** Gate 33's allowlist maps filename → free-text reason,
and nothing parses "runs in /build-apk skill Gate 14b" to verify that runner exists. Fixing INFRA-2's
five entries without INFRA-11 leaves the class open. Same shape as OI-100.

### INFRA-5 RESOLVED by live investigation — silence is CORRECT, not a defect

The agent could not distinguish "client errors stopped" from "the detection cron stopped" and said so.
The main thread settled it live, and the answer overturned an escalation I was about to make:

1. **The detector is alive** — `cron.job_run_details`: `alert_client_errors_spike` = **670 succeeded /
   2 failed** in 7 days, last run 2026-09-03 04:45 UTC.
2. **Errors did NOT stop** — `client_errors` daily counts since the silence: 369 (08-06), 366 (08-05),
   208 (08-29), 129 (08-19), 77 (08-31), 57 (09-02).
3. **12 hours since 07-27 exceeded 40 errors/hr**, peaking at **289** — and historical alerts fired as
   low as 42. At this point the reading was "alerting is silently dead" — a P0.
4. **Falsified against the config.** `alerts/_thresholds.yaml` (Phase 2, tuned 2026-06-06 to the
   founder-chosen "Tolerant" tier): `info_at: 100` per hour of REAL errors, with `error_code`
   `event`/`info` EXCLUDED as benign breadcrumbs (~81.5% of rows).
5. **Worst hour re-measured under the real rule** (2026-08-29 18:00, 203 rows):
   `event` 127 · `minified:a0Y` 47 · `String` 22 · `minified:a4d` 4 · `aQx` 2 · `ae1` 1
   ⇒ real (non-breadcrumb) = **76**, below the 100 threshold.
6. **Re-inclusion checked too** — failure-shaped op_types are re-included even when stamped `event`.
   The 127 breadcrumbs that hour: `restore_op_done` 81, `hive_session_reopen_noop` 16,
   `hive_session_opened` 5, `restore_started` 4, `restore_step_done` 3, … **none** matches
   `*_failed` / `widget_error_fallback` / `*_returned_null`. Re-inclusion adds ~0.

**⇒ No alert should have fired. The pipeline is behaving as designed.** INFRA-5's severity drops to
its residual only: 20 unacknowledged `info` alerts predating the tuning, with the ack path documented
in `_thresholds.yaml` but never exercised. **Terminal state: `verified_clean` for the silence;
the ack-loop residual folds into Unit 2.**

⚠ **Methodological note worth keeping:** three separate live queries pointed at "alerting is dead"
and the fourth — reading the threshold config — reversed it. A dramatic finding that confirms a
suspicion is exactly when to check the configuration that would refute it.

### INFRA-12 (NEW — main-thread discovered during the INFRA-5 investigation)
- **Title:** Telemetry `error_code` values are opaque — minified web symbols and bare type names
- **Lens:** L32 (telemetry data quality)
- **Evidence:** live `client_errors` for 2026-08-29 18:00-19:00 →
  `minified:a0Y` ×47, `String` ×22, `minified:a4d` ×4, `minified:aQx` ×2, `minified:ae1` ×1.
- **Impact:** 3 | **Risk:** 3 | **Effort:** 2 | **Priority: 24**
- **Why it matters:** L32's charter is literally *"if client sends `error.runtimeType.toString()`, the
  DB fills with `String`, `_Map<String, dynamic>`, `TypeError`"* — `String` as an error_code is that
  exact antipattern, and `minified:*` are unresolved web-build symbols. 47 occurrences of an
  unidentifiable error in ONE hour is real signal being discarded. These rows also count toward the
  alert threshold while carrying no diagnostic value.
- **Verdict:** REAL **[verified: LIVE]**

### Other INFRA verification
- **INFRA-1 [verified]** — same grep as INFRA-SEED-1/DEP-5 → 0 hits. **Triple-confirmed** by three
  independent agents plus the main thread.
- **INFRA-3 [verified]** — `ls scripts/check_*.dart | wc -l` → **95**. `pre-commit.sh:134,310` say 89/75;
  CLAUDE.md §0 says 90/76. Three sources, none generated, all wrong.

## ARCHITECTURE (agent returned 10 + a cleared-FALSE_ALARM block)

| ID | Title | I | R | E | Priority | Verdict |
|---|---|---|---|---|---|---|
| ARCH-3 | 24h backoff step unreachable; the test cited to pin it does not exist | 3 | 3 | 1 | **30** | REAL **[verified]** |
| ARCH-4 | `_executeUserProfileUpsert` lacks the cross-account guard both siblings carry | 3 | 3 | 1 | **30** | REAL |
| ARCH-2 | Retry queue drains on 2 of its 4 documented triggers; `connectivity_plus` is not a dependency | 4 | 3 | 2 | **28** | REAL **[verified]** |
| ARCH-1 | **A cleared profile field never round-trips — stale cloud value re-hydrates on every sign-in** | 4 | 4 | 3 | 24 | REAL **[verified]** |
| ARCH-6 | Gate 46 claims to catch an 8th leak-prone singleton; its list is a hardcoded const of 7 | 3 | 2 | 2 | 20 | REAL |
| ARCH-5 | 6 AI-coach planner singletons cache plan data with no lifecycle reset | 2 | 3 | 2 | 20 | REAL |
| ARCH-9 | 3-consecutive-rest rule implemented twice, once inside a widget | 2 | 2 | 1 | 20 | PARTIAL (service copy authoritative — L28 burn CLOSED) |
| ARCH-7 | `SyncQueue.drain()` documented idempotent, no re-entrancy guard | 2 | 2 | 2 | 16 | PARTIAL |
| ARCH-10 | Mandatory migration header enforced only for the seed migration | 2 | 2 | 2 | 16 | PARTIAL |
| ARCH-8 | `swapDays` quota check and increment separated by 3 awaits | 2 | 1 | 2 | 12 | PARTIAL (call site guarded) |

### ARCH-1 main-thread verification — **the audit's most severe user-facing finding**

⚠ **The priority formula UNDER-RANKS this at 24 because effort=3.** In user terms it is the top
finding: silent reversion of user-entered data. Ranking it by formula alone would be a mistake.

Full chain verified by the main thread:
1. **Writer** — user clears City; `edit_profile_screen.dart` writes `'city': ''` into the Hive profile map.
2. **Guard** — `lib/core/services/sync_service.dart:2366-2370`:
   `static bool _hasValue(dynamic v) { if (v == null) return false; if (v is String && v.trim().isEmpty) return false; return true; }`
3. **Push drops it** — `lib/core/services/sync/sync_profile.dart:230`:
   `if (SyncService._hasValue(p['city'])) 'city': p['city'],` → an empty string is **omitted from the
   upsert payload entirely**, so the cloud row keeps its OLD value. The clear is never transmitted.
4. **Restore re-hydrates it** — `sync_profile.dart:766-767`:
   `for (final e in cloud.entries) if (e.value != null) e.key: e.value` → the stale non-null cloud
   value overwrites the cleared local value.
5. **Trigger is every sign-in, not reinstall** — `sync_service.dart:1326` `await restoreLightweightAlways(userId);`

**Blast radius:** every `_hasValue`-guarded field on that payload — verified present at `:226-234`:
`lifestyle_activity`, `pace_preference`, `diet_preference`, `injuries`, `city`, `body_fat_assessed_at`.

**Recurrence, not a new class:** diagnose `c3f2d8` fixed exactly this for `body_fat_percent` (which is
why line `:233` uses `_hasNumber`). The instance was fixed; the mechanism was not generalised — the
`feedback_mistake_guard_without_its_mirror.md` class (20 instances / 9 sessions).

### Other ARCH verification
- **ARCH-2 [verified]** — `sync_queue.dart:8-12` documents four drain triggers including
  *"Connectivity restore (via `connectivity_plus`)"* and *"Periodic timer (every 5 min while app
  foregrounded)"*. `grep -c connectivity pubspec.yaml` → **0**. The package is not a dependency, so
  that trigger cannot exist. A transient failure waits for a cold launch or a manual banner tap.
- **ARCH-3 [verified]** — `_backoffSeconds = [1, 5, 30, 300, 1800, 7200, _oneDaySeconds]` (7 entries),
  `maxRetries = 7`, dead-letter at `retryCount >= 7`, and `_isDue` uses
  `backoffIdx = (op.retryCount - 1).clamp(0, 6)`. retryCount reaches 7 → dead-lettered BEFORE index 6
  is ever used, so the 24h step is **unreachable**. Real budget = 1+5+30+300+1800+7200 ≈ **2h35m**, not ~26h.
  The test cited at `:102` to "pin them together at runtime" —
  `test/contracts/sync_queue_retry_budget_consistency_test.dart` — **does not exist**; repo-wide grep
  returns exactly one hit, the citation itself. Its parenthetical reads "(lands in B2 continuation)" —
  a deferral that never landed, now reading as coverage.
- **Path correction:** `sync_queue.dart` is at `lib/core/services/`, NOT `lib/core/services/sync/`.

**Agent-cleared FALSE_ALARMs (recorded so consolidation does not re-open them):** CQRS
side-effect-on-read (Gate live, 3 exemptions) · restore `syncX`→`_restoreX` pairing (Gate 21) · SDK
identity unbind (7 real call sites) · usage-counter + `progress` map races (closed by OI-45) ·
`equipment_owned` restore · promo `used_count` (atomic RPC) · redeem-referral replay (23505 fallback).
**Already-tracked, skipped:** OI-90, OI-113, OI-152.

## TEST (agent returned 13 + a negatives block)

| ID | Title | I | R | E | Priority | Verdict |
|---|---|---|---|---|---|---|
| TEST-2 | Credential guard in 5 live-cloud test files renders as a PASSING test | 3 | 3 | 1 | **30** | REAL **[verified]** |
| TEST-3 | Subprocess-timeout guard is a hardcoded 3-file allowlist that *punishes* extension; 1 live escapee | 3 | 4 | 2 | **28** | REAL **[verified]** |
| TEST-4 | `dart_test.yaml` still has no repo-wide `timeout:` — the self-documented better fix | 2 | 3 | 1 | 25 | REAL (untracked) |
| TEST-1 | ~129 non-skipped `integration_test/` tests are executed by no gate anywhere | 4 | 4 | 3 | 24 | REAL **[verified]** |
| TEST-5 | Gate 42 never resolves `behavioral_test_path:` to disk | 3 | 2 | 2 | 20 | REAL (latent) |
| TEST-6 | Contract test named for delegation asserts `expect(true, isTrue)` | 2 | 3 | 2 | 20 | PARTIAL **[verified]** |
| TEST-8 | CLAUDE.md says 6 `presence_only:` entries; there are 10 | 2 | 2 | 1 | 20 | REAL **[verified]** |
| TEST-9 | 3 `presence_only:` entries are Hive-backed — hatch used for convenience, not infeasibility | 3 | 3 | 3 | 18 | REAL |
| TEST-11 | `auth_flow` T5 early-returns on a tautology before its real assertion | 2 | 2 | 2 | 16 | PARTIAL |
| TEST-10 | Registry-cited test documents a mechanism CLAUDE.md says was removed | 1 | 2 | 1 | 15 | REAL (stale doc) |
| TEST-12 | All 4 Patrol device flows `skip: true`, Gate 54 green over never-executed flows | 3 | 2 | 4 | 10 | PARTIAL |
| TEST-7 | Flutter scaffold placeholder `expect(true, true)` survives in CI | 1 | 1 | 1 | 5 | REAL (trivial) |
| TEST-13 | L18 healthy — 83 of 88 skips carry reason + reopen criterion; 1 undocumented | 1 | 1 | 1 | 5 | PARTIAL |
| TEST-14 | Honest negatives: `test/scripts/` 22/22 annotated; `deno check` live; 126/126 registry paths resolve | — | — | — | — | FALSE_ALARM ×4 |

### TEST main-thread verification
- **TEST-8 [verified]** — `grep -c 'presence_only: true' docs/sot_registry.yaml` → **10**. CLAUDE.md:402
  says "(6 entries carry it today)". The escape hatch grew 67% while the rule bounding it says otherwise.
- **TEST-3 [verified]** — `subprocess_test_timeouts_declared_test.dart` `_guardedFiles` holds exactly 3
  entries, and the file asserts `hasLength(3)` with reason *"the c3f9a7 fix covered exactly three files;
  if that set changed, update this list deliberately"*. **The assertion makes adding a 4th guarded file
  FAIL the test** — a guard that punishes its own extension. `sot_registry_citations_test.dart` spawns
  2 subprocesses and declares no `@Timeout`.
- **TEST-2 [verified]** — `test/edge_functions/webhook_test.dart:21` → `test('SKIPPED: SUPABASE_URL /
  SUPABASE_ANON_KEY not set', () {});` then `return;`. An empty test body PASSES, so a credential-less
  run is indistinguishable from "the endpoint behaved correctly" — the OI-105 class. The sibling
  `redeem_referral_test.dart:157-161` already names and fixes this; the lesson reached 1 of 6 files.
- **TEST-1 [verified]** — `scripts/pre-push.sh:141` → `TZ=Asia/Kolkata flutter test test/ --exclude-tags
  golden`. Scoped to `test/` only; `integration_test/` is run by nothing.
- **TEST-6 [verified, downgraded to PARTIAL]** — the `expect(true, isTrue)` is real, BUT the agent
  omitted the adjacent comment: *"This is a 'skipped if Hive not bootable' smoke check — the
  source-grep tests above are the load-bearing invariants."* It is an honestly-labelled placeholder,
  not a disguised tautology. The residual issue is only that the test NAME claims delegation is pinned.
  Recorded as the agent's one over-claim.

## CODE (agent returned 14 + a cleared-FALSE_ALARM block)

⚠ **The severity cluster of this audit.** CODE-1/2/3/8 are all paid-feature gates that FAIL OPEN —
every one errs toward giving away expensive AI inference. Treat as a single security/cost unit.

| ID | Title | I | R | E | Priority | Verdict |
|---|---|---|---|---|---|---|
| CODE-1 | **PRO 50/day image cap unreachable — counts a channel nothing writes** | 4 | 4 | 1 | **40** | REAL **[verified: source + PROD]** |
| CODE-3 | Free-image paywall fails OPEN; its docstring inverts the reasoning | 3 | 3 | 1 | **30** | REAL **[verified]** |
| CODE-6 | `checkPro` swallows errors unlogged — paying user silently loses PRO tools | 3 | 3 | 1 | **30** | REAL |
| CODE-7 | delete-account rate-limit counter is a floating `.then()` | 3 | 3 | 1 | **30** | REAL |
| CODE-8 | weekly-report PRO gate falls open → free user gets a Gemini 2.5 Pro report | 3 | 3 | 1 | **30** | REAL **[verified]** |
| CODE-4 | The counter insert enforcing CODE-3's limit discards its result | 3 | 3 | 1 | **30** | REAL |
| CODE-2 | **PRO video chat has no rate limit on any path** | 4 | 3 | 2 | **28** | REAL **[verified]** |
| CODE-10 | Partial cron runs logged as `success` — health alert can never see them | 3 | 2 | 1 | 25 | REAL |
| CODE-11 | Unchecked read feeds a spread-merge that can wipe a day's snapshot | 4 | 2 | 2 | 24 | PARTIAL (class = OI-81; destructive consequence unrecorded) |
| CODE-5 | Fire-and-forget embedding write; `EdgeRuntime.waitUntil` used nowhere in tree | 3 | 3 | 2 | 24 | REAL |
| CODE-9 | IST date concatenated with `Z` suffix — 5h30m window drift | 2 | 3 | 2 | 20 | REAL |
| CODE-12 | morning-alert's documented idempotency contract is inverted in code | 2 | 2 | 2 | 16 | REAL |
| CODE-14 | Gate 20 advisory 3.5 months, 99 open findings, tracker OI-44 is CLOSED and unrelated | 2 | 3 | 3 | 15 | REAL |
| CODE-13 | 13 dead constants in `app_constants.dart` + 1 dead local | 1 | 1 | 1 | 10 | REAL |

### CODE-1 main-thread verification — **top finding of the audit (40), verified against PROD**

1. **The read** — `supabase/functions/ai-media-proxy/index.ts:98`:
   `.in("channel", ["pro_image_analysis", "image_analysis"])`
2. **The only write** — `:663-666`:
   `const isFreeImageAnalysis = !isVideo && !isPro;`
   `const interactionChannel = isFreeImageAnalysis ? "free_image_analysis" : "app";`
   A PRO image analysis is therefore logged as `"app"`, never as `"pro_image_analysis"`.
3. **Repo-wide** — `grep -rn "pro_image_analysis" lib supabase test scripts` → **1 hit**, which is line 98
   itself. The string is READ in one place and WRITTEN nowhere.
4. **LIVE PROD CONFIRMATION** (`ai_coach_interactions`, project `dedsavbjuwgarrhphgnl`):
   `in_app_orphan` 57 · `app_event` 30 · `food_text_analysis` 25 · `app` 8 · `in_app` 5 ·
   `promotion_ceremony` 5. **Neither `pro_image_analysis` nor `image_analysis` exists — 0 rows.**

⇒ `countProImageAnalysesToday()` returns 0 unconditionally; `proUsedToday >= PRO_IMAGE_DAILY_CAP`
at `:509` can never fire. **The H-23 abuse cap does not exist in production.** The same dead read is
present in the deployed payload archive, so this is live, not a working-tree-only defect.

⚠ **Second-order, found by the main thread:** prod also holds **zero** `free_image_analysis` rows —
the channel CODE-3's free counter reads. Either no free image analysis has ever run, or those rows
are not landing either. Not resolved here; must be settled before CODE-3's fix is designed.

### Other CODE verification
- **CODE-2 [verified]** — `:433` `if (isVideo && !isPro) {` (free-video paywall) and `:504`
  `if (!isVideo && isPro) {` (PRO rate limit). **PRO + video matches neither branch.** The most
  expensive request type is the uncapped one.
- **CODE-3 [verified]** — `:64-65` docstring: *"fail-open is safer than fail-closed for counts — the
  LIMIT comparison still gates correctly because 0 < 5"*. That reasoning is **backwards**: `0 < 5` is
  precisely the condition under which the gate does NOT fire. `:77` `if (error) return 0;` → a broken
  count query grants unlimited free analyses, unlogged.
- **CODE-8 [verified]** — `weekly-report/index.ts:86` destructures `{ count }` with **no `error`**;
  `:92` `isFirstReport = (previousReportCount ?? 0) === 0`; `:95` `if (!hasPro && !isFirstReport)`.
  Query failure ⇒ `null` ⇒ `isFirstReport = true` ⇒ gate passes ⇒ free user receives an unbounded
  Gemini 2.5 **Pro** report.

**Agent-cleared FALSE_ALARMs:** L17 EF auth (gate targets the signature precisely) · L30 prompt
injection (`_shared/prompt_sites_sanitized.test.ts` gates every assignment site) · L21 TDZ (25,317
lines scanned, 55 candidates all false positives; OI-26 class closed) · L33 cold start (already
`await Future.wait(...)`) · L40 PII (Gate 22 clean; a `weight_kg`/`full_name` lead was chased and
proved to be GoRouter `extra:` route args, not telemetry).
**Residual the agent flagged honestly:** `error_telemetry.dart:251-253` ships `error.toString()`
truncated to 500 chars, `auth_session_bootstrapper.dart:497-498` 1000 chars — free-text passthroughs
Gate 22's literal-key matcher is structurally blind to.

## DOCUMENTATION (agent returned 18 across two transmissions; + 1 main-thread finding)

> ⚠ **Process note:** this agent's first report was never delivered to the main thread; only its
> addendum (DOC-15..18) arrived. It was re-requested and re-sent in full. **A subagent's report can
> be silently lost** — if an agent references "my first report" and you do not have one, ask for it
> rather than proceeding on the partial set.

**Central pattern (the agent's own headline, and it holds up):**
**every GATED numeric claim held; nearly every UNGATED one drifted.** DOC-12 is the control —
`check_context_artifact_budget` keeps three file sizes honest and all three are within band, while
DOC-1/3/4/5/6/9 (no gate) are all wrong.

| ID | Title | I | R | E | Priority | Verdict |
|---|---|---|---|---|---|---|
| DOC-3 | "47 tables" wrong in 3 surfaces; live = **50**; 3 tables undocumented | 4 | 3 | 2 | **28** | REAL **[verified: LIVE SQL]** |
| DOC-15 | `lib/core/services/CLAUDE.md` names 3 methods that do not exist, omits 4 that do | 4 | 3 | 2 | **28** | REAL **[verified]** |
| DOC-16 | 3 nested CLAUDE.md cite `test/contracts/` paths that do not exist | 4 | 3 | 2 | **28** | REAL **[verified]** |
| DOC-1 | CLAUDE.md §0 gate counts stale: claimed 90/76/78-of-90 → real **95/81/83-of-95** | 3 | 2 | 1 | 25 | REAL **[verified]** |
| DOC-17 | `profile/CLAUDE.md:19` opens on `profile_screen.dart`, which does not exist | 3 | 2 | 1 | 25 | REAL **[verified]** |
| DOC-7 | 3 of 4 `memory/`-prefixed citations in CLAUDE.md are dangling repo paths | 3 | 2 | 2 | 20 | REAL **[verified]** |
| DOC-2 | `pre-commit.sh` comment disagrees with CLAUDE.md *and* reality (89/75/77) | 2 | 2 | 1 | 20 | REAL |
| DOC-8 | 2 auto-loaded nested CLAUDE.md absent from the §7 pointer table (12 exist, 10 listed) | 2 | 2 | 1 | 20 | REAL **[verified]** |
| DOC-18 | `plan_engine/CLAUDE.md` points "File:" at a 5-line shim; 6 anchors hang off it | 3 | 3 | 3 | 18 | REAL **[shim verified; anchors PARTIAL]** |
| DOC-19 | Closure validator allows 4 terminal states; SKILL.md + §4.10 document only 3 | 2 | 2 | 1 | 20 | REAL **[verified, main-thread]** |
| DOC-4 | GATE_INDEX denominator stale — "49 of 87" vs generated **96** | 2 | 1 | 1 | 15 | REAL **[verified]** |
| DOC-5 | Five §7 test-count claims understate actual counts | 2 | 1 | 1 | 15 | REAL (drift is in the safe direction) |
| DOC-9 | `docs/reviews/` convention counts stale (81/164 → **87/177**) | 1 | 1 | 1 | 10 | PARTIAL |
| DOC-6 | Rule 21 says "only two `feedback_*.md` committed" — there is **1** | 1 | 1 | 1 | 10 | REAL **[verified]** |
| DOC-10 | Line-anchor rot in ROOT CLAUDE.md — searched, 10/10 intact | — | — | — | — | FALSE_ALARM |
| DOC-11 | §N citations + lens count accurate (Gate 26 PASS; 54 lenses) | — | — | — | — | FALSE_ALARM |
| DOC-12 | Context-artifact budget within band — **the gated-vs-ungated control** | — | — | — | — | FALSE_ALARM |
| DOC-13 | `check_open_issues_reconciled.dart` absent — but CLAUDE.md already says so | — | — | — | — | FALSE_ALARM |
| DOC-14 | §2 model matrix + product-data counts accurate (live: food 1431, ranks 11) | — | — | — | — | FALSE_ALARM |

### DOC main-thread verification log
- **DOC-3 [verified — LIVE]** — `select count(*) … table_type='BASE TABLE'` on `dedsavbjuwgarrhphgnl`
  → **50**. Claimed 47 at `CLAUDE.md:224`, `CLAUDE.md:819`, `docs/architecture/database.md:12`
  (the last carrying *"Count verified live on prod 2026-05-27"*). Live query for the three named
  tables returns **all three present**: `admin_metrics_daily`, `alerts`, `readiness_daily` — and
  `grep -c` each against `database.md` → **0, 0, 0**. `alerts` is cited by §7's incident-playbook row;
  `readiness_daily` backs the feature merged at this very baseline.
  ⚠ **The contrast is the finding:** `backups/live_schema_columns.json` — which IS gated — already
  carries all of them. The machine artifact stayed honest; three prose surfaces rotted.
- **DOC-15 [verified]** — `lib/core/services/CLAUDE.md:56` claims *"(6 methods — water / weight /
  sleep / steps / mood / energy)"*. Real methods: `logSleep:67`, `logReadiness:116`, `logWeight:163`,
  `logMeasurement:209`, `setWaterMl:261`, `logUrine:302`, `logHydration:353` (**7**).
  `grep -rn "logSteps\|logMood\|logEnergy" lib/` → **0**. Half the documented surface is fictional and
  four real methods are invisible — in a file auto-loaded when working in that subtree.
- **DOC-16 [verified]** — all three MISSING: `usage_weeks_signup_date_test.dart`,
  `progress_photo_quota_test.dart`, `plan_generator_inputs_test.dart`. Rule 21 makes a cited test the
  evidence a contract is protected; two of these name no file at all.
- **DOC-17 [verified]** — `find lib -name 'profile_screen.dart'` → **0**. Real path is
  `lib/features/profile/screens/profile/screen.dart`.
- **DOC-18 [verified, partially]** — `wc -l lib/shared/repositories/plan_generator.dart` → **5**; the
  file is three `export` lines and a comment. ⚠ **Coding rule 14 says "Never modify
  `plan_generator.dart` without explicit instruction" — and the file that rule names is now an empty
  re-export shim.** The rule's protective scope points at the wrong artifact. The six line-anchors
  hanging off it are structurally unresolvable; I did NOT re-read each anchor target individually.
- **DOC-4/6/7/8 [verified]** — GATE_INDEX header reads *"Total gates: **96** (49 numbered, 47 by
  filename only)"* vs `CLAUDE.md:852` "49 of 87" · `ls memory/feedback_*.md | wc -l` → **1**, not two ·
  3 of 4 `memory/` paths MISSING (`feedback_git_landing_verification.md`,
  `project_discipline_harness_hooks_2026_06_27.md`, `project_memory_consolidation_2026_07_04.md`) ·
  `find lib -name CLAUDE.md | wc -l` → **12**, §7 lists 10.
