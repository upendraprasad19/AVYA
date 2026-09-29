# CLAUDE.md

Guidance for Claude Code (claude.ai/code) in this repository.

> **Scope:** thin invariants index — loads every session, so it stays small. Per-feature rules: nested `lib/.../CLAUDE.md`; cross-cutting: `docs/architecture/<topic>.md`. Long narratives were moved out VERBATIM (context-lean batch, 2026-09-29) to `docs/architecture/process-invariants-detail.md` (§4.3/4.4/4.10/4.12/4.13), `docs/architecture/hooks.md` (§0 hooks/CI, pre-shortening root text, §7 long rows) and `docs/playbook/common-pitfalls.md` (§4.9 rows). Gate/test counts are NOT kept here — derive them (`ls scripts/check_*.dart | wc -l`). See §7.

---

## ⚠️ DISCIPLINE-FIRST (before ANY investigation, fix, or skill)

**Before investigating a bug, proposing a fix, OR invoking any skill:** load and apply the governing invariants first.

1. **Debugging a bug?** Load the six-step methodology (`docs/playbook/common-pitfalls.md` + `.claude/skills/debugging/SKILL.md`) AND the §4.1 observation→propose workflow. Never hypothesise a root cause without naming writers + readers by file:line first.
2. **Proposing a fix?** Apply §4 (no-deferrals §4.2, build/commit gates §4.3, coding rules §4.4, discipline gates §4.5) before writing a line.
3. **Invoking a skill?** Read its SKILL.md, apply the relevant §4 invariants, AND (copy/UI work) load the Wardroom brand soul (`lib/shared/widgets/wardroom/CLAUDE.md`). Never fire a skill blind.
4. This EXTENDS §4.12 (discipline-before-skill, 2026-06-13) to investigation. **No exceptions** — required pre-conditions for ANY code-touching action.
5. **Harness-injected:** `scripts/discipline_hook.dart` surfaces the hot-set at prompt / skill / compaction time. **A reminder, NOT a substitute** — still load the rules (§7).

---

## 0. DEVELOPMENT COMMANDS

### Environment, run, build, test
Copy `.env.example` → `.env` (Supabase URL, anon key, Razorpay key ID). Variables are injected at BUILD time via `--dart-define-from-file=.env` (flutter_dotenv was removed): **every `flutter run` / `flutter build` MUST include it** or auth crashes ("No host specified in URI"). Flavors: `dev`, `prod`.

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart     # prod: --flavor prod
flutter run --dart-define-from-file=.env -d chrome                          # web, no flavor
flutter test                          # unit tests; VPS is UTC → prefix TZ=Asia/Kolkata (CI pins IST)
flutter test test/bmr_calculator_test.dart                                  # single file
flutter test --dart-define-from-file=.env integration_test/app_test.dart --flavor dev   # device + .env
flutter analyze
```
`SUPABASE_URL=https://dedsavbjuwgarrhphgnl.supabase.co`; `RAZORPAY_KEY_ID=rzp_test_…` in dev. Release APK/AAB only via `/build-apk` (§4.3). Gradle `-Xmx4G` in `android/gradle.properties` (NOT 8G — silent OOM; see `android/hs_err_*.log`). Integration tests: `integration_test/flows/`. Providers are hand-written (no `.g.dart`); if you add `@riverpod`: `dart run build_runner build --delete-conflicting-outputs`.

### Git hooks (FIVE) + CI — summary (full text: `docs/architecture/hooks.md`)
Install once per clone: `sh scripts/setup-hooks.sh`. All hooks resolve Dart via `scripts/_dart_bin.sh`, never a bare `dart`. `--no-verify` needs explicit founder approval in chat (§4.3).
- **pre-commit**: every `scripts/check_*.dart` gate + index regens. Does NOT run analyze/test (ADR-0018); `PRE_COMMIT_FULL=1` adds analyze + full suite (`PRE_COMMIT_LEGACY=1` = analyze + `test/contracts/`; FULL wins).
- **pre-push**: `flutter analyze --no-fatal-infos` ALWAYS (a `warning -` line aborts the push and git prints only `failed to push some refs` — on a clean fast-forward that means the LOCAL hook failed); then `scripts/contract_sweep.dart` (warn-only); the full `flutter test` only at blast-radius ≥`account` (`PRE_PUSH_FULL=1` forces).
- **commit-msg** / **prepare-commit-msg**: enforce `closes-diagnose:` / `closes-oi:` trailers and prepend the `Blast-radius:` line.
- **pre-merge-commit**: OI board integrity at an auto-created merge. **CI** (`.github/workflows/test.yml`) is the full-suite source of truth for `main`, but only on `main`/`develop` pushes and PRs — not every push.
- **Deno habit (no hook runs it):** `deno check --node-modules-dir=none supabase/functions/<fn>/index.ts` on every Edge Function you touch BEFORE the commit (`--node-modules-dir=none` is load-bearing; recovery recipe: hooks.md).

### Edge Functions — host-shell deploy (nested `_shared/tools/...` or payloads >100KB)
```bash
node .claude/emit_payload.js <fn> --auto --functions-dir <worktree>/supabase/functions
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> .claude/_payload_<fn>.json <verify_jwt>
```
Token auto-resolves from `supabase/.supabase/supabase access token.txt` (gitignored). Shared imports MUST be `from "../_shared/..."`, NOT `./_shared/`. Legacy MCP `deploy_edge_function` is unsafe for the AI coach bundle; never use the `supabase` CLI (wrong account, §2a). Protocol: `.claude/skills/edge-function-deploy-rollback/SKILL.md`.

---

## 1. PROJECT IDENTITY

**App:** ICANBEFITTER — fitness & nutrition platform for young professionals (22-35) in India. **Model:** Freemium, ₹349/month or ₹2,999/year PRO. **Architecture:** Offline-first — Hive primary; Supabase = backup + AI + community.

---

## 2. TECH STACK

| Layer | Technology |
|---|---|
| Frontend | Flutter (Android + Web → iOS later) |
| State Management | Riverpod |
| Local Storage | Hive (offline-first, primary for all reads/writes) |
| Auth | Supabase Auth (Email + Google OAuth + Phone OTP) |
| Database | Supabase Postgres (47 tables — backup + AI + community) |
| Storage | Supabase Storage (exercise images, progress photos PRO) |
| AI Coach (all tiers) | Edge Function `ai-proxy` → Gemini 2.5 Flash. Free: 10 msg/day FOREVER (OQ-1). PRO: unlimited. Server-side gate. |
| Food AI / Weekly report | Gemini 2.5 Flash (text) + Flash Lite (scan meal, cart auditor) / Gemini 2.5 Pro (PRO-only weekly report) |
| Plan Generator | Dart (local, queries Hive exercise_library, zero API cost) |
| Payments | Razorpay (WebView checkout → webhook → Supabase → poll → Hive) |
| Telegram Bot | Separate project (OpenClaw VPS, @ICanbeFitterBot) — NOT in this repo |
| Health | Google Fit / Health Connect / Samsung Health |

---

## 2a. SUPABASE PROJECT — CONFIRMED IDENTITY

> ⚠️ TWO Supabase projects exist on this account. ALWAYS use `dedsavbjuwgarrhphgnl` (myfitnessjourney1988@gmail.com's Project, ap-southeast-1, host `db.dedsavbjuwgarrhphgnl.supabase.co`). **Before ANY Supabase operation, confirm project_id.** NEVER touch `krcrkntuwutvnmdnkfqf` ("icanbefitter") — the icanbefitter.com blog, a different app.

### Supabase Access — TWO SEPARATE ACCOUNTS
- **myfitnessjourney1988@gmail.com** (org `hwwukmntixflgbxkwavm`): fitness app + blog. **MCP only** (auto-authenticated).
- **Upendra's personal account** (org `dsvxqvpitnpumftnsnwe`): `tjjmtscmwzvlzpbvgtbv`, `zvwepplqqflhgubwalee`. **CLI only** — the `supabase` CLI is logged into THIS account, so `supabase secrets set` will NOT reach the fitness project. Use MCP or the Dashboard for Edge Function secrets/admin.

### Credentials and Firebase / OneSignal
Secrets set in the dashboard, never committed: `ONESIGNAL_REST_API_KEY`, `GEMINI_API_KEY`, `CEREBRAS_API_KEY_1..3`, `RAZORPAY_KEY_SECRET`. `ONESIGNAL_APP_ID=fd37a411-121e-4022-9929-2af68c2371f5`. Firebase project AVYA (Sender ID `194342788570`); `android/app/google-services.json` present.

---

## 3. SCREENS (5 Tabs)

| Tab | Screen | Key Features |
|-----|--------|-------------|
| 🏠 Home | Dashboard | Streak, weekly calendar, today's workout, nutrition snapshot, weight sparkline, PRs |
| 🏋️ Train | Workouts | Phase plan, active workout mode, exercise swap, templates, copy week |
| 🥗 Nutrition | Food Logging | BMR/TDEE, Log Food (AI + Scan), food search, saved meals, water, diet plan + PDF |
| 💬 AI Coach | Chat | Chat, Telegram toggle, reasoning tab + media upload (PRO) |
| 👤 Profile | Settings | Bio stats, goal, health sync, reports, subscription |

---

## 4. PROCESS INVARIANTS (NON-NEGOTIABLE)

> These rules apply EVERY interaction. Subagent dispatches inherit them. Pre-commit hooks gate them. Violations are P0.

### 4.1 Observation / bugfix workflow

- APK observations: WAIT for all → brainstorm → propose → user reviews → plan → execute. Never reflexively fix.
- Every fix must NAME writer(s) + reader(s) by file:line BEFORE proposing the fix. Writer/reader drift is the default suspect class.
- Every fix lands with a regression test in `test/contracts/` + a diagnose-doc (Ref: `feedback_observation_workflow.md`).

### 4.1.5 Bug-history lookup (BEFORE proposing root cause)

1. Grep `docs/diagnoses/INDEX.md` for the symptom / concept / file paths; read every matching diagnose-doc; check `feedback_*.md` for the recurrence class.
2. Recurrence: cite prior instances in the new diagnose-doc's `related_bugs:` + `recurrence:` and apply the known-good fix. Not recurrence: say so explicitly.
3. **Value-semantics grep:** a batch that changes a stored value's MEANING sweeps `test/` AND `supabase/functions/` for it BEFORE coding, not just `lib/`.

### 4.2 No-deferrals

- Multi-bug batches: fix ALL in same batch. No "lower priority" tagging.
- No "context tight" / "responsible handoff" as a stopping excuse — context management is the agent's job (use TodoWrite, dispatch focused subagents, compact when needed). <!-- deu-quote: enumerates the banned phrases -->

- **The ban is on the SEMANTIC, not the literal string.** Re-wrapping a deferral as `dedicated batch` / `test-maintenance batch` / `cleanup batch` / `next-batch baseline` / `documented baseline for next batch` is the SAME violation as `defer` / `follow-up batch`. When the menu you write would force founder to ratify a deferral to pick any option, the menu is malformed — re-design it. Codified 2026-05-24 (7th instance, `feedback_mistake_dedicated_batch_is_defer.md`). <!-- deu-quote: §4.2 enumerating the banned re-wraps it forbids -->
- **Structural closed==N invariant:** every multi-item batch (≥4 findings/units) or audit MUST produce `docs/audit/<batch>.closure.yaml` with per-entry `terminal_state:` ∈ {`closed_in_commit`, `upstream_blocked`, `blocked_on_user`, `verified_clean`} and no `deferred:` key; Gate 40 (`scripts/validate_audit_closure.dart`) fails if any item is non-terminal. Small 2–3 item bugfix batches keep per-fix diagnose-docs + TodoWrite.
- Refs: `feedback_no_deferrals.md`, `feedback_mistake_dedicated_batch_is_defer.md`.

### 4.3 Build / commit / push gates

Full wording and measurements: `docs/architecture/process-invariants-detail.md` (§4.3).

- Never commit or push unless explicitly asked ("commit", "push", "ship" count; "continue" does NOT).
- Never build an APK unless asked; use `/build-apk` (never raw `flutter build`), from `main` ONLY (`--from-green` on a CI-green pushed `main`). New worktrees: copy `.env` from main first.
- **Batch commits; push once per logical batch** (each push re-runs pre-push + CI). Sequential slices of ONE feature with no standalone value share ONE push/CI/APK cycle; split only for a separable defect or an explicit founder scope call.
- **Commit/push only via `scripts/safe_commit.sh "<msg>"` (ONE positional arg, no flags — a flag becomes the message) / `scripts/safe_push.sh [remote] [branch] [extra]`**; a PreToolUse hook (`scripts/git_safety_hook.dart`) blocks raw `git commit`/`git push` (escape: `ALLOW_RAW_GIT=1`). `--no-verify` needs founder approval in chat first, then `FOUNDER_APPROVED_NO_VERIFY=1`. Never pipe either script through `head`/`tail`. Sole exemptions: the ref-create pushes of `scripts/mint_oi.sh` and its sibling `scripts/mint_migration.sh`.
- `safe_push.sh` exits `0` LANDED / `1` FAILED / `2` UNVERIFIED; landing ≠ CI green (SessionStart `scripts/reconcile_ci.dart` warns on a failing run). Read its `.safe_push_result` record ONLY via `scripts/push_result_lib.dart` (absent/unparseable ⇒ UNVERIFIED, never failed).
- Don't manually re-run the full `flutter test` (pre-push ≥account + CI do); run targeted tests in dev.
- **≥account code-review is SELF-INITIATED, before the merge:** any batch at ≥`account` touching code / schema / Edge Functions runs `/code-review` (B-pass) BEFORE the `--no-ff` merge to `main`; never wait to be asked. Docs/process-only changes (e.g. CLAUDE.md) take a self-consistency review instead.
- **Live prod apply needs its own explicit go:** `apply_migration` / EF deploy to prod needs per-action authorization even when the plan was approved. A classifier block on a live apply is CORRECT — get the ok, never work around it.
- Refs: `feedback_apk_build_explicit_approval.md`, `feedback_use_build_apk_skill.md`, `feedback_mistake_review_not_self_triggered.md`, `feedback_git_landing_verification.md`.

### 4.4 The coding rules (24 — NON-NEGOTIABLE)

1. **Hive-first for ALL reads/writes.** Never block UI on Supabase response. Supabase writes are background/async.
2. **Riverpod only** for state management. No `setState` for shared state.
3. **Hive boxes:** Register ALL adapters in `main.dart`. Open ALL boxes before `runApp()`.
4. **Repository pattern** for all data access. Never call Supabase or Hive directly from widgets.
5. **subscription.gate()** for ALL PRO features. Never use inline `isPro` checks in widgets.
6. **Phase 1 is ALWAYS free.** Never gate it.
7. **PaywallSheet** is the ONLY paywall UI.
8. **Plan generator = local Dart.** Queries Hive exerciseBox. Never calls any API.
9. **Never expose API keys client-side.** All AI calls go through Supabase Edge Functions. **EF auth contract (e8a1c3):** an EF authenticates the caller via `createClient(SUPABASE_URL, SERVICE_ROLE).auth.getUser(token)` — NEVER pass the user JWT as the supabaseKey (401s every valid token). Verify a `verify_jwt=true` EF with a REAL user token (deploy-rollback skill, bug-class 6.7). Client authed `functions.invoke` calls go through `SupabaseService.callFunction` / `ensureFreshToken()` (gates `check_edge_function_auth_pattern.dart`, `check_authed_invoke_fresh_token.dart`).
10. **DM Sans font everywhere.** No system fonts. `GoogleFonts.getFont('DM Sans', ...)`.
11. **Wardroom palette** (Campaign Gold `#D4B270`) — not Electric Cyan, not old green `#00e5a0`. Source of truth: `lib/shared/widgets/wardroom/CLAUDE.md`.
12. **Dark theme only.** Backgrounds `#02070F` (bg) > `#06101F` (card) > `#0E1E30` (input).
13. **All screens handle:** loading (skeleton), error (retry), empty states.
14. **Never modify `plan_generator.dart`** without explicit instruction.
15. **Import paths:** relative within features; `package:` for shared/ and core/.
16. **EF SSRF:** never fetch arbitrary user-supplied URLs server-side; allowlist the Supabase Storage prefix + user-scope assertion on path (OI-28).
17. **Release error handling:** `kDebugMode` guard — detailed errors only in debug, generic in release.
18. **EF input limits:** enforce message (5K) + snapshot (10K) limits server-side on ALL AI endpoints.
19. **Server-side subscription verification:** `phases_2_to_12`, `ai_coach_unlimited`, `progress_photos` MUST call `verifyFromServer()` in `gate()`.
20. **No deferred test failures.** Failing tests on `main` are P0; "pre-existing failure" is banned. Pre-commit no longer runs `flutter test` (§0), so the blocking gate is the push (pre-push at ≥`account`, CI on `main`). Never `--no-verify` around either.
21. **Regression test required for every fix** — it FAILS without the fix and PASSES with it; cite its path in the commit. Source-grep tests count for PRESENCE only: every SoT registry entry MUST also carry a `behavioral_test_path:` (Hive-write→read, fakeAsync race, or end-to-end) or `presence_only: true` with a reason (Gate 42 `check_sot_behavioral_test_paths.dart`: strict, blocks, resolves cited paths on disk; `--warn-only` never reaches main; no `behavioral_test_required` backlog). **MUTATE IT AND RUN IT:** a fix whose only NEW protection is a test written/extended by this batch (source-grep, behavioral or e2e) is mutated once before the test is believed; the diagnose-doc says what was mutated and how many tests reddened. Confirm the mutation APPLIED (`grep -c`); a compile error is NOT a proof; a mutation reddening NOTHING is not proof of coverage (a `catch` may have absorbed it — extract guards into a pure function); check the FIXTURE against real workflow history. Self-attested.
22. **Bug fixes require a diagnose-doc.** Every commit on `main` matching `^(fix|bug|regression)(\([^)]*\))?:` MUST cite `docs/diagnoses/<date>-<slug>-<id>.md` via `closes-diagnose: <bug-id>` in the body; it must pass `dart run scripts/validate_diagnose_doc.dart <path>`. Investigation subagents get `docs/agent_brief_preamble.md`. **S-tier fixes (§4.12.6)** use the slim template (symptom, writer+reader file:line, fix, test path; `tier: s_fix`); recurrence-class bugs take the FULL template at ANY tier.
23. **No stopping mid-batch.** Multi-task instructions ("fix everything", "address each and everything") run through to completion. Valid stops only on: whole batch done / BLOCKED on user-only action / new interrupting instruction. Banned: "context tight", "responsible handoff", "fresh session pickup". Documentation per rule 22 + memory file update for any NEW pattern + CLAUDE.md update for any NEW invariant — always. <!-- deu-quote: rule 23 enumerating the banned stopping excuses -->
24. **Every NEW `check_*.dart` gate ships mutation-proven:** the same commit adds a test that FAILS when the gate's protection is neutered plus a `mutation_proven: true` entry in `docs/audit/gate_test_ledger.yaml` (`test_path:` list + `evidence:`); `scripts/check_gate_test_ledger.dart` requires exactly one ledger state per gate. Predating gates are `grandfathered:` by NAME; a new gate takes NO number (filename is identity). Self-attested residue is read by the §4.12 ×2 review. Full text of rules 20/21/24: `docs/architecture/process-invariants-detail.md` (§4.4).

### 4.5 Discipline gates per fix

- Diagnose-doc REQUIRED with `touched_layers_checked` YAML field (per §6).
- Migration apply paired with `backups/applied_migrations.json` update in same commit.
- IST throughout for date keys + cloud `date` columns + counter resets (`lib/core/utils/ist_date.dart`, `supabase/functions/_shared/ist_date.ts`).
- SoT registry update for new writer/reader contracts: `docs/sot_registry.yaml`.
- Pre-commit hook MUST pass — no `--no-verify`.
- Cron-dispatched Edge Functions MUST use `_shared/cron_telemetry.ts`.

### 4.6 Feature-flag protocol for risky changes

When touching payment / sync / auth / AI prompt / plan generator:
1. Default new code path behind `kDebugMode` gate OR Hive flag OR RemoteConfig.
2. Old path preserved verbatim, reachable when gate closed.
3. Roll the gate after manual verification.
4. Delete the old path in the SAME batch that rolls the gate (it is already re-testing that code). If the founder schedules the roll for later, track the old path on the OI board or in `docs/ship_dark_pending_review.yaml` (§4.12.4), never as an intention. (This step once read *"Once verified, delete old path in follow-up batch"* — a §4.2 violation.) <!-- deu-quote: records what the step said before it was fixed -->

### 4.7 Naming conventions

Before introducing any new file / symbol / Hive key / cloud column / Edge Function name: read `docs/naming_conventions.md`, check the reserved-domain glossary, and append any new domain term to it.

### 4.8 Subagent brief preamble + audit lens registry

- Every subagent investigation dispatch MUST prepend `docs/agent_brief_preamble.md` to the brief.
- Review / audit work names which lenses from `docs/audit/LENS_REGISTRY.md` (L1–L54) are in scope.

### 4.10 Tech-debt audit cadence (NEW — tech-debt audit 2026-05-20)

- Run the 6-category tech-debt audit (Code / Architecture / Test / Dependency / Documentation / Infrastructure) each quarter (`/schedule`) AND after any 3+-batch landing.
- Output `docs/audit/<YYYY_MM_DD>_audit_closures.yaml`; every finding carries `terminal_state:` on the entry: `closed_in_commit` → `commit:` + (`verification:`|`notes:`) · `upstream_blocked` → `blocker:` + `reopen_when:` · **`blocked_on_user`** → `reason:` (founder action needed) · `verified_clean` → `evidence:`|`notes:`. NO `deferred:` key. Validator `scripts/validate_audit_closure.dart` (Gate 40) runs on EVERY commit — create the ledger only once every finding is terminal; recompute `closed_count:` from entries.

### 4.11 Gates before refactor (NEW — extends §4.6 feature-flag protocol)

When a refactor touches a known bug class (writer/reader drift, restore completeness, telemetry, secret exposure…): (1) the detection gate `scripts/check_*.dart` is wired into pre-commit + CI BEFORE the first refactor commit; (2) it runs `--warn-only` for 24h to baseline, then flips to hard-fail; (3) no commit lands without the gate green. See `feedback_gates_before_refactor.md`.

### 4.12 Plan review ×2 + discipline-before-skill (NEW — founder directive 2026-06-13)

Full text, measured batches and rationale: `docs/architecture/process-invariants-detail.md` (§4.12).

1. **Every implementation plan is independently reviewed TWICE before execution** by context-blind reviewers who verify every claim against code + live state. **Review #2 runs on the POST-review-#1 plan.** If reviews keep surfacing new material issues the unit is too large — split it and ship the smallest converged piece.
2. **Discipline is enforced BEFORE every skill invocation** (§4; Wardroom soul for copy; bugfix workflow for fixes).
3. **A plan-review RECORD makes #1+#2 a forcing function:** `docs/plan-reviews/<branch>.md` (`review_rounds: ≥2`, `ground_truth_verified: true`, `verdict: converged`; `bpass: accepted` ≥platform; `hermes: accepted` catastrophic), enforced at the merge-to-main commit in CI by `scripts/check_plan_review_record_exists.dart`.
4. **Ship-dark tiering:** a platform/account change behind a kill-switch, default OFF, with a behavioral test proving byte-identical output when OFF gets 1 review round at build time (`tier: ship_dark_build` + `review_rounds: 1` — the gate accepts 1 ONLY with that tier; `bpass: accepted` still required ≥platform). The full ×2 review is REQUIRED again on the commit that flips the default or removes the kill-switch. Log each flag in `docs/ship_dark_pending_review.yaml`; remove it only once its flip-on record shows full ×2 + `bpass: accepted`.
5. **Run the local gate loop BEFORE dispatching any review round that has a draft diff** — reviewer attention is for mechanism, not stale line ranges or counts. (Not for a prose plan with no code yet.)
6. **S/M/L fix tiering.** **S** = diff touches ONLY `lib/features/{home,train,nutrition,profile}/**` (literal hard filter; auth/ai_coach UI ⇒ M), ≤2 PRODUCT-code files (tests + diagnose doc excluded), whole diff <100 lines, not a recurrence-class bug ⇒ no ×2 plan review, B-pass skipped; analyze `lib/` + targeted tests + slim diagnose doc (`tier: s_fix`). **M** = else ⇒ full pipeline + `flutter analyze lib/` before every reviewer dispatch. **L** = payment/auth/sync/schema/EF/plan-engine/CLAUDE.md ⇒ unchanged. SELF-ATTESTED; the merge seam still demands the record at ≥account, and any gate failure, seam symbol or diff growth escalates to M (M briefs declare compile-class findings out of scope; a P0/P2 escaping an S-fix triggers ONE evidence-based tightening). Escapes: `docs/audit/s_tier_escapes.yaml`; an all-mechanical review round closes with `mechanical_only: true`. The founder initiates APK builds.
7. **Execution mode is decided at batch START and written into the plan:** subagent-driven (one worktree per unit; the coordinator integrates by cherry-pick and is the single writer of shared files) or inline — never switched mid-batch. The coordinator re-verifies one mutation per unit (§4.4 rule 21).
8. **Full gate loop before review dispatch (NON-NEGOTIABLE, 2026-09-23):** run the COMPLETE suite — `flutter analyze lib/`, `flutter test` (VPS: `TZ=Asia/Kolkata`), the pre-commit gate loop (`sh scripts/pre-commit.sh` or attempt the commit) — never a hand-picked subset; the loop removes the judgment about which gates are relevant.

These bind the planning / `/code-review` / `/hermes-pass` / brainstorming flows.

### 4.13 One worktree per session (NON-NEGOTIABLE — codified 2026-07-07 after 2 cross-session mixing incidents)

Sessions in the SHARED main folder share ONE git index (commits silently mix in another's staged files); a **worktree** has its OWN. Full text: `docs/architecture/process-invariants-detail.md` (§4.13).

1. **EVERY session that will edit/stage/commit works in its OWN worktree:** `sh scripts/new-worktree.sh <slug>` (copies `.env`), then `cd .claude/worktrees/<slug>`. The base is whichever of local `main` / `origin/main` is ahead (LOCAL `main` when merged-but-unpushed), warning on divergence.
2. **The shared main folder is INTEGRATION-ONLY:** reads, merging, `git push`, `/build-apk`, worktree retirement; never feature commits. Prefer `sh scripts/safe_merge.sh <branch>` over raw `git merge --no-ff` (refuses a local `main` behind `origin/main`).
3. **Enforced** by `scripts/check_commit_from_worktree.dart`: a non-integration commit in the PRIMARY worktree is BLOCKED (exempt: merge/cherry-pick/revert, linked worktrees, CI, `ALLOW_MAIN_COMMIT=1`).
4. SessionStart (`scripts/discipline_hook.dart`) warns when a session starts in the shared main worktree.
5. Even a solo session uses a worktree. Ref: `memory/feedback_worktree_per_session.md`, diagnose `f0c2d5`.
6. **RETIREMENT.** Retire a worktree once its branch is merged, clean (tracked AND ignored) and nothing unpushed: `dart run scripts/retire_worktree.dart --execute [<slug>]` from the PRIMARY (dry-run is the DEFAULT). Trigger = the §5 checklist row; deliberately NOT a blocking gate. FOUR legs, all load-bearing: (1) merged into `main`, (2) no tracked changes, (3) no NON-REGENERABLE ignored files (`git status --porcelain` hides them), (4) nothing unpushed. A failing leg ⇒ report and LEAVE ALONE, never `--force`. Orphaned dirs: only empty ones auto-remove.
7. **`core.worktree` must never be set** (redirects every worktree at one branch; diagnose `a4f7c2`) — gated by `scripts/check_worktree_config_integrity.dart`.
8. **Retirement is AUTONOMOUS once the pipeline lands (founder directive 2026-09-29).** Once THIS session's own branch is committed, pushed, merged to `main` and CI-green, retire its worktree immediately and report it DONE — never ask the founder. Scope: only the worktree this session just finished (other sessions' `KEEP`/`ORPHAN` entries are LEFT ALONE); a failing predicate is still a stop-and-report. Sequence: `ExitWorktree({action: "keep"})` (never `"remove"`) → from primary `dart run scripts/retire_worktree.dart <slug>` (dry-run) → on `[branch not merged]` despite a confirmed merge, first `git fetch origin main && git merge --ff-only origin/main` (§4.9) → `--execute` once it shows `[merged + clean + pushed]`.

### 4.9 Common process pitfalls

Titles below are condensed. Full original rows (incident, measurements, second-order traps): `docs/playbook/common-pitfalls.md` → "Full incident detail for CLAUDE.md §4.9 rows" — grep a key phrase or the pointer id.

| Pitfall | How to avoid | Pointer |
|---|---|---|
| A `postmaster`-context GUC (e.g. `cron.log_run`) cannot be flipped by a SQL migration | `select context from pg_settings where name=…` first; needs a restart. | e8b4a1 |
| `idx_scan=0` says nothing about FK-support use | Check `pg_constraint` for a same-column FK before dropping. | e8b4a1 |
| Wrong import path / Gradle build hangs silently | Relative in features, `package:` for shared/core; `-Xmx` ≤4G. | — |
| **`flutter build apk` dies in ~2 min: `JAVA_HOME is not set and no 'java' command could be found`** | Install JDK 21 (not 17); export `JAVA_HOME`. | 2026-08-27 |
| Worktree APK build: "Did not find .env" / APK built via raw `flutter build` | Copy `.env` from main; always `/build-apk`. | — |
| Master Audit / multi-agent surveys produce false-positive findings | Read the cited file:line AND verify cloud state via live `information_schema` first. | `feedback_audit_findings_require_live_verification.md` |
| **`/tmp` means TWO DIFFERENT DIRECTORIES depending on which binary reads it** | Never use `/tmp` on Windows here; use the session scratchpad by absolute path. | 2026-08-28 |
| **`safe_commit.sh` takes ONE POSITIONAL argument and no flags — a flag becomes the MESSAGE.** | Pass `"$(cat msg.txt)"`; check `git log -1 --format=%s`; repair `git reset --soft HEAD~1`. (`safe_push.sh` DOES take extra args.) | `feedback_git_landing_verification.md` |
| **A widget test that mocks `path_provider` makes GoogleFonts fail LOUDLY instead of degrading** | Open Hive lazily (not `setUpAll`); first test renders every font family the file needs. | `exercise_plate_widgets_test.dart` |
| **`await`-ing real disk I/O inside a `testWidgets` body hangs until the harness gives up** | `await tester.runAsync(...)` or use `setUpAll`. | 2026-08-29 |
| **Extracting or moving code breaks source-grep contracts in files you never touched** | `grep -rn "<old-literal>" test/` before any move/rename/line shift (docs too — nested CLAUDE.md, skill and board files are source-grepped); REPOINT, never loosen; `grep -c "<marker>"` when adding a call site. | common-pitfalls.md |
| **`flutter analyze <FILE>` on a library with `part` files reports CLEAN on a tree that does NOT compile** | Use `flutter analyze lib/` when a touched file is/has a `part`. | 2026-09-02 |
| **A new test file that spawns subprocesses — or waits on a live service — goes green targeted and RED in the full suite** | File-level `@Timeout` + `library;`, shorter per-CALL `.timeout()`, no per-test `timeout:` override, one full-suite run. | common-pitfalls.md |
| **`blast_radius_from_diff.dart` FAILS OPEN on a path that does not exist yet** | Write the file (scratch is fine), classify THAT, delete it. | 2026-09-04 |
| **Repairing a broken ENFORCEMENT breaks every test that was silently relying on it not enforcing** | Grep tests exercising the now-enforced path; fix the ASSERTION (accept both outcomes), not the cap. | e7c4b2 |
| **A new behavioural test that EXECUTES green tells you nothing until you run it against the code it REPLACES** | Restore the old body in `BEGIN … ROLLBACK` and re-run the new assertions. | `oi46_daily_cap_triggers_live_verify.sql` |
| **Citing a Postgres function's body from the migration that CREATED it — the LAST `CREATE OR REPLACE` wins** | Use `test/helpers/migration_cap_reader.dart` or `pg_get_functiondef`; strip comments. Next migration number: to READ it match the scheme (`ls supabase/migrations/ \| grep -E '^[0-9]{3}[a-z]?_'`), never a naive numeric sort; to ALLOCATE one never read `ls` at all — `sh scripts/mint_migration.sh --next` / `<slug>` (§7). | b8f4c2 |
| **A filter you add for READABILITY narrows the verification's input set** | State the widest input set; use `git grep`; read the COUNT, not the colour. | `feedback_green_check_input_set_width.md` |
| **A plan's SoT-registration step names a concept fully, but earlier steps cite its test file by a shorthand** | Grep the brief for every `_writer_to_reader_test.dart` name; all must equal the registry `concept:`. | d3f8a6 |
| **A migration's own "Post-apply verification" comment can itself be an unsafe live write** | Wrap it in `BEGIN; … ROLLBACK;` yourself first. | h1a2b3 |
| **Appending `&` to a command the tool ALREADY runs in the background double-backgrounds it** | Never add your own `&` under a background flag; plain `>` to a real path. | 2026-09-22 |
| **A file whose own SUBJECT is invisible/separator characters (U+2028, U+2029, U+0085, ESC, …)** | Build them from `String.fromCharCode`/hex literals, even in comments; scan for non-ASCII after. | f4a9c2, 125b81 |
| **After a GitHub-PR merge, PRIMARY's local `main` lags `origin/main` — `retire_worktree.dart` reports `[branch not merged]`** | `git fetch origin main && git merge --ff-only origin/main`, re-run the dry-run. | 2026-09-29 |
| **A merge of two long-lived branches into a shared self-numbered file (bug-class index, tuning history) can silently produce a numbering COLLISION** | After ANY merge touching such a file: `grep -oE "^### [0-9]+\.[0-9]+" <file> \| sort \| uniq -d` vs each parent. | 2026-09-29 |

---

## 5. PER-BATCH MAINTENANCE PROTOCOL

> At the end of any batch that lands a commit, walk this checklist ("No update needed" is valid; each row MUST be considered). `/update-docs` walks it. **ENFORCED by a `Stop` hook** (`scripts/batch_close_hook.dart`, once per HEAD with unpushed commits): rows come back `[x]` / `[ ]` / `[?]` — **`[?]` means undetermined, NOT fine.** Content is self-attested. Kill switch `.claude/.batch_close.disabled`; its gitignored `.claude/.batch_close_state` is in `retire_worktree_lib.dart`'s `regenerableIgnoredPaths` (any tool writing a gitignored file into a worktree owes that list an entry). Detail: `docs/architecture/hooks.md`.

```
[ ] Diagnose-doc written + validated (every bug fix; rule §4.5)
[ ] Contract test added + green (every bug fix; rule §4.5)
[ ] SoT registry updated if writer/reader file:line changed
[ ] backups/applied_migrations.json updated if migration applied
[ ] Root CLAUDE.md: new non-negotiable invariant emerged? (rare)
[ ] Nested CLAUDE.md updated if feature contract changed
[ ] docs/architecture/<topic>.md updated if cross-cutting concept changed
[ ] feedback_*.md added/updated if user corrected a claim OR recurring class
[ ] project_*.md retrospective written (every shipped batch)
[ ] Agent memory index (the HARNESS `~/.claude/projects/<mangled>/memory/MEMORY.md`, NOT repo
    `memory/MEMORY.md`): a shipped batch goes to `MEMORY_ARCHIVED.md`, not the index.
[ ] Worktree retired if merged + clean (incl. ignored) + nothing unpushed (§4.13 point 6):
      dart run scripts/retire_worktree.dart          # dry-run first, ALWAYS
    This row IS the trigger — point 6 is deliberately ungated.
[ ] Context-artifact budget re-baselined if a tracked doc drifted (§7 row):
      dart run scripts/check_context_artifact_budget.dart        # then --record if intended
    THIS ROW IS THE TRIGGER (the SOFT band is silent locally; the first sign would be the HARD band
    blocking every commit). `--record` refuses over a hard breach without `--force-record`.
[ ] docs/audit/open_issues.md has 0 CLOSED entries (archive to closed_issues.md; self-attested, no gate)
[ ] Skill self-evolution: does any .claude/skills/<topic>/SKILL.md need a new bug-class entry, red flag, or trigger phrase?
[ ] Runtime verified on device — app launched, went through core flow, observed expected state (NON-NEGOTIABLE).
[ ] After the merge: `dart run scripts/retire_worktree.dart --execute` in the primary (§4.13.6).
```

### 5.1 Skill self-evolution

**GATED for the code-review skill** by `scripts/check_skill_tuning_history.dart`: a commit that ADDS `docs/reviews/<x>-review.md` must also append a same-dated entry to the code-review Tuning history in `.claude/skills/code-review/tuning-history.md` (`SKILL.md` keeps its `## 7` heading and a pointer), or the commit is blocked. Scope: code-review only (`/hermes-pass` keeps its own tuning section); a new bug-class in ANY skill is unenforceable by script and prompted by the §5 Stop hook.

After a batch that surfaced a new bug-class, red flag, or anti-pattern: (1) check whether a skill's "Bug classes"/"Red flags" table covers it, else add an entry; (2) cite bug ID + one-line trigger + regression test path; (3) commit skill edits in the SAME commit as the discovering fix; (4) add a new `.claude/skills/<topic>/SKILL.md` when 3+ batches share a pattern.

---

## 6. MULTI-TIER COVERAGE PROTOCOL

> Every bug fix verifies state across every system tier it touches. Validator: `scripts/validate_diagnose_doc.dart` requires the `touched_layers_checked` YAML field.

### The 12 tiers

| # | Tier | How to verify |
|---|---|---|
| 1 | Client code | Read code, run tests, `flutter analyze` |
| 2 | Hive (local state) | Contract test in `test/contracts/`, manual Hive inspection |
| 3 | Postgres schema | `information_schema.columns`, `pg_constraint`, `pg_indexes` |
| 4 | Postgres data | Audit query on affected table |
| 5 | Migrations applied | MCP `list_migrations` vs `backups/applied_migrations.json` |
| 6 | Edge Function code vs deploy | API `GET /functions/<slug>` returns version |
| 7 | Cron jobs | `cron.job_run_details` last 24h for non-2xx |
| 8 | RLS policies | `pg_policies` for affected table |
| 9 | Storage buckets + objects | `storage.buckets` + `storage.objects` queries |
| 10 | Secrets / API keys | Smoke test Edge Function; check Vault `service_role_key` |
| 11 | External services | Razorpay / OneSignal / Firebase dashboard check |
| 12 | Client → server contract | Trace one full user flow end-to-end |

### touched_layers_checked YAML field

Every diagnose-doc lists tiers with status `verified` / `fixed_in_this_batch` / `not_applicable` / `deferred` + evidence (non-empty, at least one `verified` or `fixed_in_this_batch`). Subagent briefs prepend the checklist via `docs/agent_brief_preamble.md` (§4.8).

---

## 7. WHERE TO FIND DETAILED RULES

| Topic | Path |
|---|---|
| Train / nutrition / home / ai_coach / onboarding / auth / profile | `lib/features/<feature>/CLAUDE.md` |
| WriteServices, sync fan-out, Hive contracts | `lib/core/services/CLAUDE.md` |
| Plan generator V4 | `lib/shared/repositories/plan_engine/CLAUDE.md` |
| Wardroom design system | `lib/shared/widgets/wardroom/CLAUDE.md` |
| Edge Function deploy + AI architecture | `supabase/functions/CLAUDE.md` |
| Migration apply protocol | `supabase/migrations/CLAUDE.md` |
| AI / sync / database / subscription / payment / business rules | `docs/architecture/{ai,sync,database,subscription,payment,business-rules}.md` |
| Functionality flow (test charter) | `docs/architecture/functionality-flow.md` |
| Full text of §4.3/4.4/4.10/4.12/4.13; hooks/gates/harness internals; nested-CLAUDE.md overflow | `docs/architecture/{process-invariants-detail,hooks,functions-detail,train-detail,auth-detail,services-detail,ai-coach-detail,plan-engine-detail}.md` |
| Directory tree; exercise library; food database | `docs/reference/{directory-structure,exercise-library,food-database}.md` |
| Common pitfalls (+ full §4.9 rows); bug history (generated); SoT registry | `docs/playbook/common-pitfalls.md`; `docs/diagnoses/INDEX.md`; `docs/sot_registry.yaml` |
| Live schema column snapshot | `backups/live_schema_columns.json` — regenerate in the SAME commit as any column-changing migration (`check_schema_column_refs.dart`) |
| Naming conventions | `docs/naming_conventions.md` |
| Audit lens registry / closure ledgers | `docs/audit/LENS_REGISTRY.md`, `docs/audit/<YYYY_MM_DD>_audit_closures.yaml` |
| **Open-issues backlog — READ THE INDEX FIRST** | `docs/audit/OPEN_INDEX.md` (generated; `wc -c` it) → `docs/audit/open_issues.md` at the cited line; closed history `docs/audit/closed_issues.md`; numbers minted ONLY by `scripts/mint_oi.sh` |
| Blast-radius registry; ADRs; handbook; incidents | `docs/blast_radius.yaml`, `docs/adr/`, `docs/handbook/`, `docs/incidents/` |
| Review / debug / e2e skills (long history on demand) | `.claude/skills/{code-review,hermes-pass,debugging,e2e-sim-testing}/SKILL.md`; `code-review/tuning-history.md`, `debugging/bug-classes.md`; `docs/reviews/` |
| Device-CI, cron registry, secrets, fresh clone | `docs/operations/{DEVICE_TESTING,CRON_REGISTRY,SECRET_INVENTORY}.md`, `docs/onboarding/FRESH_CLONE.md` |
| Subagent brief preamble; end-of-batch skill | `docs/agent_brief_preamble.md`; `/update-docs` |
| Discipline / `Stop` (§5) / memory write-guard hooks | `scripts/discipline_hook.dart`, `scripts/batch_close_hook.dart`, `scripts/memory_write_guard_hook.dart` |
| Skill self-evolution gate (§5.1) | `scripts/check_skill_tuning_history.dart`; entries in `.claude/skills/code-review/tuning-history.md` |
| Worktree enforcement / retirement / config integrity (§4.13) | `scripts/check_commit_from_worktree.dart`, `scripts/retire_worktree.dart`, `scripts/check_worktree_config_integrity.dart` |
| Gate registry + rule-24 ledger | `docs/audit/GATE_INDEX.md` (generated), `docs/audit/gate_test_ledger.yaml` |
| OI allocator; Dart resolution; merge prechecks; contract sweep; AST debt gates | `scripts/mint_oi.sh`, `scripts/_dart_bin.sh`, `scripts/safe_merge.sh`, `scripts/contract_sweep.dart`, `scripts/check_hive_first_pattern.dart` |
| Migration-number allocation + ledger hash integrity (OI-263/135/137) | `scripts/mint_migration.sh`, `scripts/check_migration_number_reserved.dart`, Gate 39 `scripts/check_applied_migrations_ledger.dart` + `scripts/migration_ledger_hash_lib.dart`, `scripts/migration_ledger_hash.dart`; rules `supabase/migrations/CLAUDE.md`, detail `docs/architecture/migrations-detail.md` |
| Context-artifact budget (L54) | `scripts/check_context_artifact_budget.dart`, `backups/context_artifact_sizes.json` |
