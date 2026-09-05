# Open Issues — class-level audit follow-ups

Evergreen task board. Every gap surfaced by any audit / observation /
diagnose pass that hasn't yet been closed by a shipped commit lives here.

## How this file is used

- **Append-only at the bottom.** Never re-number a closed issue; the OI
  number is its permanent identifier (referenced from diagnose-docs +
  commit messages).
- **Status transitions:**
  - `OPEN` — identified, not started
  - `IN_PROGRESS` — being worked this session
  - `CLOSED` — shipped, with hex diagnose-doc ID + commit SHA
- **One section per issue.** Status line first so a quick scroll surfaces
  open work without reading prose.
- **Cross-reference both directions:** every diagnose-doc that closes an
  commit that closes one cites `closes-oi: OI-NN` in the message body —
  **enforced** since 2026-07-29 by `scripts/check_closes_oi_cited.dart`, wired
  into `scripts/commit-msg.sh`. It fires only when a `**Status**:` line actually
  moves OPEN → CLOSED, so ordinary commits pay nothing.
  (The old companion rule — a `oi_closed: OI-NN` field in diagnose-doc
  frontmatter — is **dropped**. It reached 2 diagnose-docs in 74 issues and no
  script ever read it. The board already records each closing commit's SHA, so
  OI→commit traceability survives; the gate above supplies the commit→OI
  direction. A third documented-but-unenforced convention is worse than none.)

## Why this file exists

5+ APK test iterations have surfaced the same recurring bug class
(writer/reader drift). Memory files capture retrospectives; diagnose-docs
capture forensics; `sot_registry.yaml` captures concept structure. None
of them answer the question "what's still open from prior audits?" This
file does. It's the queryable backlog the user explicitly asked for on
2026-05-17.

---

## Closed (chronological)

- **OI-07** (2026-05-17) — AI snapshot field-name contract manifest
  shipped. `docs/snapshot_contract.yaml` + self-consistency contract
  test. closed_diagnose_id: `93aeac`. commit_sha: pending. Gate
  enforcement (OI-03) remains OPEN as planned.
- **OI-01** (2026-05-17) — Reader-manifest gate now enforces EXHAUSTIVE
  reader completeness (Phase 2 added to
  `scripts/check_reader_manifest_complete.dart`; registry populated
  with 14 new `readers:` entries + 67 `reader_allow_files:` entries
  across 16 concepts; contract test
  `test/contracts/reader_manifest_exhaustiveness_test.dart` pins the
  gate as a subprocess). closed_diagnose_id: `0a1e17`. commit_sha:
  pending.
- **OI-02** + **OI-08** (2026-05-17) — Symmetric ReadServices shipped
  for workout / nutrition / health domains (`workout_read_service.dart`,
  `nutrition_read_service.dart`, `health_read_service.dart`). PR
  per-set MAX semantic (OI-08) centralised in
  `WorkoutReadService.bestPerSetReps` / `.bestPerSetDuration` /
  `.bestPerSetWeight`; `WorkoutRepository.loadAllExercisePRs` collapsed
  ~90 lines of inline switch math to 4 delegating calls;
  `train_screen.dart` file-private helpers DELETED;
  `NutritionRepository.dailyMacros` delegates. 3 new SoT registry
  concepts + 6 existing concept `reader_allow_files:` updates so the
  Phase 2 reader-manifest gate passes. 3 contract tests (30 cases).
  closed_diagnose_id: `8d85c2`. commit_sha: pending.

---

# Second wave (2026-05-17) — surfaces NOT covered by the writer/reader drift sweep

The OI-01 through OI-10 batch closed the writer/reader drift class
exhaustively. Founder's follow-up question on 2026-05-17 ("does our
audit cover everything — UI / backend / APIs?") surfaced 8 additional
audit surfaces never systematically swept. Added below as OI-11..OI-18
with risk ranking. Visual regression harness explicitly NOT added per
founder direction (low priority — no historical pure-visual bug has
shipped).

# Hermes audit 2026-05-17 (evening) — OI-26 through OI-43

External Hermes cross-check on 2026-05-17 evening surfaced 13 REAL findings (3 P0 + 6 P1 + 4 P2) + methodology lens-registry work. Verification report: `~/.claude/plans/i-did-an-audit-glittery-meerkat.md`. Each finding becomes one OI below for tracking.

# OI-43 lens-scan findings (filed 2026-05-17, ready for follow-up batches)

## OI-78 — 3 more public-schema RPCs retain the PUBLIC-default-ACL anon/authenticated EXECUTE gap (P3)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-31 (round-1 review of Unit 5, re-engagement-prefilter) — live
  `has_function_privilege` query against `dedsavbjuwgarrhphgnl` for every non-trigger
  `public`-schema function.
- **Identified**: 2026-07-31 · round-1 review of Unit 5 (OI-48, re-engagement-prefilter), while
  independently re-verifying migration 117's claim that `find_orphan_chat_media` was the only
  instance of the migrations-090/091 gap class still live. The same `has_function_privilege`
  query applied repo-wide surfaced 3 more.
- **What's wrong**: none of these three ever had their PUBLIC-default grant revoked. Migrations
  090/091 (2026-06-11) fixed 9 SECURITY DEFINER functions (live-verified prosecdef=true); migration
  117 fixed the sibling `find_orphan_chat_media` (created by migration 071, 2026-05-17 — ~25 days
  BEFORE 090/091, not after as an earlier draft of this entry said). None of the 4 functions this OI
  and migration 117 cover were missed for timing reasons — 090/091's REVOKE pass specifically
  targeted SECURITY DEFINER functions, and all 4 (these 3 plus `find_orphan_chat_media`) are plain
  SQL/STABLE, categorically outside that scope regardless of creation order:
  - `get_users_with_message_count(int)` — created `010_...sql:76`, never revoked. Sole caller:
    `rolling-context/index.ts:137` (service_role).
  - `match_memories(uuid,vector,int,float8)` — created `20260331000001_...sql:70`, never
    revoked. Sole caller: `_shared/memory_retrieval.ts:114` (service_role).
  - `morning_alert_pick_quarter(...)` — `046_...sql:50` grants `authenticated, service_role`
    explicitly but never revokes the PUBLIC-default grant anon still inherits. Sole caller:
    `morning-alert/index.ts:577` (service_role).
  None are `SECURITY DEFINER` (all run with the caller's own privileges), and each table they
  touch has an RLS backstop consistent with the reasoning migration 117 documents for
  `find_orphan_chat_media` (verify per-function before treating that as established rather than
  assumed) — so this is unwanted attack surface, not a confirmed live data leak. Severity is P3
  for that reason, matching the pre-fix `find_orphan_chat_media` classification.
  **Not in scope, seen and deliberately excluded (round-2 review N7):** `email_is_registered`
  is also anon+authenticated-executable and SECURITY DEFINER, but that is an intentional,
  reviewed exception (migration 106, pre-auth sign-in flow — `revoke all from public; grant
  execute to anon, authenticated;` explicitly) documented as the "15/16" carve-out in the
  2026-06-11 audit closure. Noted here so a future sweep doesn't rediscover it as a "4th
  instance" of this OI's class.
- **Fix shape**: same pattern as migrations 090/091/117 — `REVOKE EXECUTE ... FROM PUBLIC, anon,
  authenticated` + `GRANT EXECUTE ... TO service_role` (or `TO authenticated, service_role` where
  a real authenticated caller exists — confirm per function, don't assume service-role-only).
  Given this is the fourth time this exact gap class has been found by whichever unit happens to
  be using one of these functions as a reference pattern, the more durable fix is a structural
  gate: a live query enumerating every `public`-schema function's `anon`/`authenticated` EXECUTE
  privilege against an explicit allowlist (mirroring how `check_schema_column_refs.dart` already
  does this for column references), run at `/build-apk` or in CI, so a 5th instance can't ship
  silently. Whether to fix the 3 functions one-by-one or build the gate first is a scoping call
  for whoever picks this up — not pre-decided here.
- **Blast radius estimate**: likely `platform` (migration touching 3 existing functions' grants
  only, no DDL/table change) — confirm via `scripts/blast_radius_from_diff.dart` at diff time;
  the `SECURITY DEFINER` content-rule will NOT fire here since none of these are SECURITY
  DEFINER, so don't assume catastrophic without checking.

## OI-80 — check_snapshot_contract silently skips one reader citation while counting it (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred.
- **Identified**: 2026-08-01, while correcting reader citations that OI-79's paging refactor moved.
- **What's wrong**: `scripts/check_snapshot_contract.dart` reports `8 reader citations checked` and
  exits 0, but the `_shared/notification_prefs` entry under `extra_server_written_keys` →
  `notification_preferences` → `readers:` is **never validated**. Setting its `line:` to `700`
  (600+ lines past EOF) still PASSES, while the identical mutation on the `streak-guardian` entry
  *directly below it in the same list* correctly FAILS. So the gate counts a citation it does not
  check — the a9f2c6 "gate exits 0 while doing nothing" class, in miniature.
- **Cause NOT diagnosed.** The obvious theory (comment lines between `readers:` and the first
  `- {` entry breaking the parser) was **tested and refuted** — moving the comments below the
  entries changed nothing. Recorded as unknown rather than guessed.
- **Why it matters**: that citation is the one most likely to drift, since `notification_prefs.ts`
  is the file OI-79 rewrote most heavily (+67 lines, the reader moved 77 → 106). A stale pointer
  sends the next audit to a function parameter and invites the conclusion that the reader is gone.
- **Compounding**: `check_snapshot_contract.dart` is in the skip allowlist of BOTH
  `scripts/pre-commit.sh` and `.github/workflows/test.yml` (both `check_*.dart`
  gate-loop case-skip blocks — cited by anchor, not line: the 2026-08-10 CI
  sharding batch moved both); it runs only via
  `test/contracts/snapshot_contract_consolidated_test.dart`.
- **Interim mitigation (already shipped in `337bf6eb`)**: the YAML carries an inline ⚠ warning at
  that entry, and its `line: 106` was verified BY HAND. Nothing currently depends on the gate
  maintaining it.
- **Fix**: find why that entry is skipped (start by instrumenting `_Key.readers` parsing for the
  `extra_server_written_keys` block), add a negative-control test that a deliberately-wrong
  citation FAILS for every reader entry, and remove the gate from both skip allowlists.

## OI-81 — 10 per-user reads still destructure `data` without `error` in 4 cron functions (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-08-01 (Unit 9) — counted during the OI-79 sweep; NOT re-verified since.
- **Identified**: 2026-08-01, while fixing the same class in `streak-guardian` (F16) and
  `weekly-recalc:326` (F37).
- **What's wrong**: `const { data } = await supabase.from(...)` with no `error` destructure coerces
  a FAILED query to `data ?? []`, which downstream reads as a legitimate empty result. Two live
  instances found in this batch were not theoretical: `streak-guardian` turned a failed
  "who trained today" read into "nobody trained" (⇒ alert everyone), and `weekly-recalc:326` left
  the monotonic guard's comparison map empty, silently re-opening diagnose `3a7b9f` (every user's
  LIFETIME `total_workouts_done` overwritten by a 4-week count).
- **Scope**: ~10 further sites across 4 cron functions this batch did not otherwise touch. The
  count is from a sweep, not a per-site audit — re-derive before fixing rather than trusting it.
- **Why not fixed here**: OI-79's scope was row-count bounding. These sites are correctly bounded;
  the defect is error handling. Fixing them means auditing each caller's intended failure mode
  (abort the tick vs. skip the user), which is a different judgement per site.
- **Fix**: per site, decide abort-vs-skip, then either destructure and handle `error` or route
  through `paged_fetch` (which throws). Gate candidate: extend
  `scripts/check_unbounded_cron_reads.dart` to flag `const { data }` with no `error` in the same
  chain — it already parses these chains.

# Reconciliation 2026-07-26 — board revived after 70 dormant days

This file was last touched `32437ee7` on **2026-05-17** and then went unread while dozens of
batches shipped. Root cause: it had **no mechanism** — no gate, no hook, no CI job referenced it
(`grep open_issues scripts/ .github/ .claude/settings.json` → nothing). Everything in this repo
with a gate holds; everything on intention decays. Same disease §4.12 records for plan quality
("100% honor-system").

> ⚠️ **CORRECTION (2026-07-29).** The line that stood here claimed this was *"Fixed in this
> batch by `scripts/check_open_issues_reconciled.dart` + a SessionStart injection in
> `scripts/discipline_hook.dart`."* **Neither was ever written.** `git log --all --
> scripts/check_open_issues_reconciled.dart` returns nothing, and `discipline_hook.dart`
> contains zero references to `open_issues`. The section diagnosed the disease exactly right
> and then recorded a cure that did not exist — which is the disease, one level up: a claim
> with no mechanism behind it, decaying unread.
>
> The mechanism is real as of **2026-07-29**: `scripts/build_oi_index.dart` regenerates
> [`OPEN_INDEX.md`](OPEN_INDEX.md) from this file, wired into `scripts/pre-commit.sh` beside
> the other index regens, and it **fails closed** if any open entry is missing its
> `Blocked on` / `Verified` fields. `scripts/check_closes_oi_cited.dart` (commit-msg) enforces
> the `closes-oi:` citation. Both are exercised by `test/contracts/`.

**Audit of the 8 still-OPEN OIs against live code (2026-07-26).**

> ⚠️ **An earlier draft of this section claimed "All verified STILL OPEN" and "Every line citation
> had drifted, so they are refreshed here." Both statements were FALSE.** Only 4 of 8 were audited
> and only 3 of ~20 citations were refreshed. Review round 1 caught it. The claim is corrected below
> rather than quietly edited, because a backlog that overstates what is open is only marginally more
> useful than one nobody reads — and this is the third instance today of the
> `feedback_mistake_unverified_done_claims` class.

| OI | Verified 2026-07-26 | Citation |
|---|---|---|
| OI-44 | **STILL OPEN** — `checkAndUnlock` at `badge_service.dart:18` | `getCurrentRank()` 176 → **`rank_service.dart:217`**. NOT refreshed: `isPro` `sub.service.dart:233` → **`subscription_service.dart:320`**; `gate()` 306 → **:420** |
| OI-45 | **STILL OPEN** — `increment()` body is still `final current = read(); await write(current + 1)` **[SUPERSEDED 2026-07-29 by the usage-counter-race batch correction in OI-45's own entry above — this row re-confirmed the CODE SHAPE only; the RUNTIME behavior it implies does not reproduce, downgraded CRITICAL → LOW]** | 74-79 → **`usage_counter_service.dart:100-106`**. NOT refreshed: `UserRepository.updateProgress` 75-84 → **:133**; `HealthSyncService.syncToHive` 190-192 → **:148** |
| OI-46 | **STILL OPEN** — migration 026 explicitly scopes to `food_text_analysis`; no daily-cap trigger on `ai_coach_interactions` | — |
| OI-47 | ~~**STILL OPEN** — `_shared/sanitize_for_prompt.ts` **absent**; raw `User name: ${name}` live~~ **SUPERSEDED — OI-47 CLOSED 2026-07-28** (merge `9d5e9d31`, deployed to all 16 LLM-reaching functions). `sanitize_for_prompt.ts` exists. Row kept as the dated 2026-07-26 snapshot it is; annotated 2026-08-07 because a grep for "OI-47" hits this row before the closed entry, and this board's own index cites OI-47 by name as the item that "read as authoritative for a day while being wrong". | 243 → **`morning-alert/index.ts:278`** |
| OI-48 | **MATERIALLY STALE — the stated harm no longer describes the code.** `e78e2c7e` (2026-07-08, OPT-E) batched the per-user reads via chunked `.in()`. The outer `from("users").select(...)` remains, so the O(all users) *shape* survives, but "~5 Postgres reads × N users" does not. **Needs re-scoping, not carrying forward.** | — |
| OI-51 | ~~**PARTLY CLOSED.** … **Still genuinely open:** Crashlytics `setUserIdentifier('')` and `OneSignal.logout()`~~ **SUPERSEDED — OI-51 CLOSED 2026-07-28** (merge `9d5e9d31`, `ff716e29`; test `signout_unbinds_sdk_identity_test.dart`). Row kept as the dated 2026-07-26 snapshot it is; annotated 2026-08-07 for the same grep-precedence reason as OI-47 above. ⚠ Its closed entry records a residual worth re-checking: the fix is CLIENT-side and was not in APK `1.0.0+37`; whether it has reached users depends on which build shipped after `+38`. | auth_provider 543/760 → **:587/:607**; razorpay 30-32 → **:40-42** |
| OI-25 | Carried forward — **NOT audited this pass.** | — |
| OI-50 | Carried forward — **NOT audited this pass.** Spot-check found `sets.first` moved `train_provider.dart:72` → **:85**, and the cited `mealType[0]` does **not exist** in `todays_meals_card.dart` at all (it is in `nutrition_screen.dart`). Citations unreliable. | — |

**Standing rule this establishes:** an OI carried forward without an audit says so explicitly. "Carried
forward" is a statement about effort spent, not about truth — conflating the two is what let a
70-day-old file read as authoritative.

---

# Pending work as of 2026-07-26 (OI-52 … OI-67)

Everything currently owed, from any source — not only audit findings. `MEMORY.md` remains the
durable *why* (scars, retrospectives) but lives in the harness dir outside git and is invisible to
cloud sessions; **this file is the cross-session backlog.**

## OI-53 — Flip the remaining 10 workout-generator ship-dark flags (was 13; equipment-exclusions flipped 2026-08-05; readiness + triggered-deload flipped 2026-09-01)

- **Status**: OPEN
- **Verified**: 2026-08-05 — flag inventory, dependency order and the data lag all re-derived from
  source this session (`plan_engine_flags.dart`, `deload_evaluator.dart:170,173`,
  `ship_dark_pending_review.yaml:76-101`), not carried from the entry's original text.
- **Identified**: 2026-07-26 · workout-generator overhaul complete `7bb766fa`
- **Blocked on**: FOUNDER — but read the shape below before treating this as one decision.
  ⚠ **DATED FOUNDER DECISION 2026-09-01: readiness + triggered deload were approved and
  flipped together** (branch `readiness-flip`, record `docs/plan-reviews/readiness-flip.md`).
  Recorded here because a repo-only reader cannot otherwise reconcile `Blocked on: FOUNDER`
  with those two flips existing. **10 remain.**
- **What this actually is — 13 product decisions, not one toggle.** The ledger is explicit:
  *"there is no batch discount, and flipping thirteen flags in one commit would be one review
  pretending to be thirteen."* Each flip-on commit needs its own **full ×2 + `bpass: accepted`**
  (§4.12.4 — the lighter `ship_dark_build` tier does NOT apply to a flip). Nothing is broken by
  leaving them OFF: every shipped APK to date has run with all 13 dark, so OFF *is* the current
  product. What is owed is a decision per flag, not a flip.
- ✅ **`enable_readiness` + `enable_triggered_deload` — FLIPPED 2026-09-01.** Together, and the
  coupling was mechanical: `plan_generator.dart` gates `stashWorkingBase` on the deload flag at
  GENERATION time, so a plan generated with it OFF can never be lifted — flipping deload later
  would have helped no existing plan. Sleep is now MEASURED from Health Connect
  (`SLEEP_SESSION`) rather than self-reported, so the check-in is 2 taps when sleep is known.
  Readiness trends are FREE for all (the Reports paywall branch was removed, not gated).
  ⚠ Three Android-side defects were caught in review, each invisible to `flutter test`:
  the wrong data type (`SLEEP_ASLEEP` matches STAGES, not the session), `READ_SLEEP` declared
  in no manifest, and a permission-request function with no caller.
- **The order is forced by code, not preference.** `enable_readiness` had to flip FIRST:
  - `enable_triggered_deload`'s evaluator **early-returns** on readiness
    (`deload_evaluator.dart:56` — `if (!PlanEngineFlags.readinessEnabled) return;`; the
    ledger's `&& readinessEnabled` phrasing describes the effect, not the code shape) —
    so it does literally nothing until readiness is ON.
  - `enable_plateau_escalation` self-gates (`plateauedGroups` checks `readinessEnabled`).
  - `enable_volume_titration`'s **+1** direction needs positive readiness recovery evidence, so
    with readiness OFF it can only ever TRIM. Flipping it alone gives users a one-way volume cut.
- ⚠ **A data lag no review can shortcut.** Even with readiness flipped, `deload_evaluator.dart:173`
  requires **≥3 readiness rows inside a 14-day IST window** (`:170`) before the dependent flags can
  act; below that it returns `good: false` and keeps the deload (safe, but inert). So three of the
  thirteen sit dead for **at least two weeks** after any flip, waiting on check-in data only real
  users generate. "Flip all 13 at once" is therefore not merely risky — it is ineffective, and it
  destroys attribution: 13 simultaneous changes to prescribed load/volume/selection with one
  bug report and no way to isolate the cause. Attribution is the entire point of ship-dark.
- ✅ **`enable_equipment_exclusions` — FLIPPED 2026-08-05 (diagnose `e2d6b8`), so this issue is
  now TWELVE flags, not thirteen.** It was the exception: its *collection* UI shipped lit while
  its *consumption* stayed dark, so the app saved an equipment preference it then ignored — a
  live broken promise rather than a dormant feature. That promise is now kept. The counts and
  quotes above ("13", "thirteen") describe the pre-flip state and are left as the ledger's own
  wording; the live number is **12**. Related: OI-89 (its condition (a) closed with this flip),
  and OI-95 (the flip's kill-switch is reachable only in debug builds).

## OI-54 — Confirm `/admin` access

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · admin dashboard shipped 2026-07-13
- **Blocked on**: FOUNDER (must load `/admin` signed-in)
- **What's missing**: Verify `ADMIN_USER_IDS` actually contains the founder UUID.

## OI-55 — Live `amar` re-verify (Unit 0)

- **Status**: OPEN
- **Verified**: 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Identified**: 2026-07-26 · Unit 0 shipped `34621203`
- **Blocked on**: FOUNDER sign-in. (The "sequenced after OI-52" half is dead — OI-52 closed
  2026-07-27; the founder-sign-in half is real and still blocks.)

## OI-56 — Revert repo to private

- **Status**: OPEN
- **Verified**: 2026-08-05 — visibility read live (`gh repo view` → **PUBLIC**); CI cost measured
  from the Actions API (below). Supersedes the earlier "after billing is fixed" blocker, which
  never said what about billing.
- **Identified**: 2026-07-26 · public since 2026-07-18
- **Blocked on**: FOUNDER — **dated decision 2026-08-05: stay public until September 2026**, then
  flip. Nothing technical blocks it; this is a scheduling call with a measured reason. Public repos
  get unlimited free Actions minutes, private ones are metered, and the measurement below puts the
  current cadence at ~98% of the free private quota. Deliberately kept `OPEN` rather than given
  some "parked" status — it is not done, and it should keep showing up in the open count.
- **What's missing**: flip the repo back to private.
- **The CI-cost measurement that decides this** (taken 2026-08-05 so September does not re-derive
  it): all 6 jobs run on `ubuntu-latest` — the 1× multiplier, cheapest tier. Per-job time on run
  `31006716605`: Analyze & Unit Tests 430 s · Build Check (APK) 192 s · Audit Gates 59 s ·
  Plan-review record 35 s · Supabase Integration 23 s · Deno EF tests 12 s = **751 s of job time**.
  GitHub bills each JOB rounded UP to the whole minute, so that is **16 billed minutes per run**,
  not the 12.5 the raw seconds imply — four sub-minute jobs cost a full minute each. At **123 runs
  per 30 days** that is **~1,968 min/month against GitHub Free's 2,000-minute private quota
  (~98%)**. GitHub Pro (~$4/mo) lifts it to 3,000 and gives real headroom. Wall-clock is a trap
  here: a run takes ~7 min end-to-end but bills 16, because jobs run in parallel and are billed
  individually.
- ⚠ **Two inputs to that number are UNVERIFIED**: the account plan could not be read
  (`gh api user` returned `plan: null` — token scope), so GitHub Free is *assumed*; and the quota
  figures come from model knowledge, not from the billing page. Confirm both at billing before
  flipping, or the headroom calculation is built on a guess.
- **Security consequence while public** — unchanged, and now runs ~4 weeks longer than planned:
  fork-PR branch-name collisions are a live concern for the keystone gate (owner-guard added
  `d947743d`).

## OI-57 — Decide the 7 open Dependabot PRs

- **Status**: OPEN
- **Verified**: 2026-08-05 — every PR's `mergeStateStatus` + check rollup read live from the GitHub
  API this session, and every PR body checked for a security-advisory section.
- **Identified**: 2026-07-26
- **Blocked on**: FOUNDER — **dated decision 2026-08-05: merge #16 only; the other six are
  declined as churn** (see below). #16 was taken in this batch.
- ⚠ **NONE of the 7 is a Dependabot *security* update.** No security labels, no "Vulnerabilities
  fixed" section on any of them — they are ordinary "a newer version exists" PRs. This corrects the
  framing this entry previously invited: OI-57 had been ranked as a *supply-chain* item, and it is
  not one. The single security mention anywhere in the set is inside **#5**'s changelog, where
  `actions/setup-java` upgraded its own bundled `form-data` — the action's supply chain, not ours.
- **Live state (2026-08-05, measured)**: #17 CLEAN · #16 CLEAN · #15 CLEAN · #5 CLEAN ·
  **#14 DIRTY** (conflicted) · **#9 DIRTY** (conflicted — this was the entry's one `UNKNOWN`, now
  resolved) · **#10 UNSTABLE, 3 FAILURE checks**.
- **Declined, with reasons (2026-08-05)** — a recorded decision, not a deferral; re-open any of
  these if its premise changes:
  - **#17** `onesignal_flutter` 5.5.4→5.6.6 — version churn, no fix we need.
  - **#15** `build_runner` 2.13.1→2.15.1 — dev-only, and this repo generates no `.g.dart` today
    (providers are written manually; root CLAUDE.md §0), so it is near-inert either way.
  - **#14** `actions/checkout` 4→7 — **three major versions**, and conflicted. The keystone
    plan-review CI job depends on `fetch-depth: 0` to reach `HEAD^1..HEAD^2`; a major bump here
    can break the gate that enforces every other gate. Not worth it for zero gain.
  - **#10** `flutter_native_splash` 2.4.7→2.4.8 — dev-time generator, and currently failing 3
    checks.
  - **#9** `patrol` + `patrol_finders` — device-test framework churn, conflicted.
  - **#5** `actions/setup-java` 4→5 — the `form-data` fix is internal to the action; also requires
    a plan-review record by design (below).
- **The `github-actions` rule still stands** for #14/#5 whenever they are revisited: `pub` bumps
  merge under the content-verified exemption, but the 2 `github-actions` bumps require a
  plan-review record **by design** — a bot must not rewrite the CI that enforces every other gate.
  Documented in `.github/dependabot.yml`.

## OI-58 — Keystone gate: subject-spoof bypass (single-parent half CLOSED as OI-58a)

- **Status**: OPEN
- **Blocked on**: none — but see the correction below; the OPEN status now covers only the
  subject-spoof residual, not both bypasses this title once bundled.
- **Verified**: never (for the residual below; the single-parent half IS verified — see next)
- **⚠ CORRECTED 2026-08-30 — this entry described BOTH bypasses as unaddressed for 33 days
  after one of them was fixed.** The single-parent half shipped the DAY AFTER the split-out
  below, as `bd91c6eb` (2026-07-28, diagnose `d9b4e7`, `status: fixed`) — exactly the
  `reopen_when` condition the split-out names: direct-to-main commits judged per-commit,
  exemption verifies every changed LINE is a version line. Live today in
  `plan_review_record_lib.dart`; `check_plan_review_record_exists.dart:385` names it
  explicitly as "OI-58a". Re-verified 2026-08-30 by RUNNING the tests, not re-reading docs:
  the 8-test group `OI-58a — direct-to-main landings are judged` in
  `test/scripts/gate_input_family_e2e_test.dart` passes 8/8 against the live gate as a real
  subprocess, including the exact attempt-1 and attempt-2 bypasses described below.
  `docs/audit/gate-input-family.closure.yaml`'s own `OI-58a` entry had the SAME staleness —
  `terminal_state: upstream_blocked` for 34 days while its own file header said "closed in
  code" two lines above it — corrected in the same batch.
  **Why this was found:** `bd91c6eb` cited `closes-oi: OI-58` — this whole ticket — while its
  own commit body correctly scoped itself to only the single-parent half ("OI-58b … remains
  OPEN and is not claimed here"). That is real, verified, tested work, NOT a false citation
  in the OI-150 sense (cited, zero work performed) — but it cites a two-part parent ticket for
  a one-part fix, and this entry's prose never caught up. `scripts/check_closes_oi_performed.dart`
  (new, same batch) would flag this shape going forward — it checks a citation against the
  BOARD's status, and OI-58 (the union) correctly still read OPEN, so a citation against it
  is only satisfied once the whole ticket is. The lesson generalises: cite the SPECIFIC entry
  the fix closes, not a broader parent that bundles other still-open work.
- **Attempted and SPLIT OUT 2026-07-27** (branch `gate-input-family`, founder-approved
  per §4.12.1). The enforcement was built twice and failed review twice, each time in
  the same place, BEFORE the fix above landed the next day. **Read this before touching the
  residual below:**
  - **Attempt 1** judged all direct-to-main commits in a push as ONE union before testing
    the exemption, so a single `feature`-tier commit alongside the version bump killed
    it. That is the standard release flow (`2c4cbddd` bump 05:24 + `6a364656` docs 06:42,
    the two halves of APK +37) and it FAILED — verified by running the gate over
    `3bca83a8..HEAD`.
  - **Attempt 2** fixed that per-commit and introduced a worse bug: the exemption is
    `paths.every(versionBumpAllowedPaths.contains)`, an all-of test over an ALLOW-LIST,
    which accepts every proper subset. **Confirmed by execution**: a direct commit
    rewriting `monthlyPriceInr = 1` and `freeAiMessagesPerDay = 9999` in
    `app_constants.dart` — no version line touched — passed at `account` tier with a
    `NOTE (version-bump exemption)`. `check_app_version_matches_pubspec.dart` only pins
    the `version:` string, so it backs nothing else in either file.
  - **The fix shape for attempt 3**: verify the changed LINES, not the paths — every
    changed line in the diff of those two files must be a version line. That matches the
    standard the Dependabot exemption in the same file already meets ("earned by what the
    diff contains, not by trusting a branch name"). Do NOT simply require both files:
    10+ historical bumps touched `pubspec.yaml` alone.
  - **Do not re-derive the baseline**: 5 of the last 60 first-parent commits are
    single-parent, 3 of those ≥account — `be3b4baf` (account, 11 files, password reset)
    and `8c38c855` (account, 8 files) are real unreviewed auth landings; `2c4cbddd`
    (platform, 2 files) is the bump the exemption exists for. Measure per-COMMIT: the
    per-push figure is different and justifying hard-fail on the wrong one is how
    attempt 1 shipped.
  - **What DID ship**: the pushed-range walk, two-dot diffs and dual-registry tiering
    (OI-70/OI-71) — so the range machinery this needs already exists.
  - Residual first-time merge-subject spoof stays **founder-only**: no in-repo script can
    close it; the control is requiring PRs so GitHub writes the merge subject.
- **Identified**: 2026-07-26 · diagnose `d3f8a2`, ci-governance batch
- **Risk class**: enforcement bypass
- **What's missing** (residual only — the single-parent half above is CLOSED, corrected
  2026-08-30; this used to describe both and was wrong on the first for 33 days): Branch
  identity derives from the merge SUBJECT (author-controlled free text), which
  `git merge --no-ff -m "Merge branch 'other'"` can spoof to resolve to another branch's
  approved record. Disabling GitHub's squash/rebase buttons closed the GitHub-originated path.
  The ACCIDENTAL half (slug + quote truncation) is closed. Residual is the DELIBERATE,
  first-time spoof — founder-only, no in-repo script can close it (a script's every input is
  authored by the person being checked); the control is requiring PRs so GitHub, not the
  committer, writes the merge subject.
- **Fix shape**: stop keying on the subject/`HEAD^2`; evaluate the pushed range via
  `github.event.before..after` (used nowhere in the repo today). Materially different design — own
  reviewed unit.

## OI-60 — Flip `enable_hold_weeks`

- **Status**: OPEN
- **Verified**: 2026-08-20 — the blocker list re-derived from the AUTHORITATIVE ledger
  (`docs/ship_dark_pending_review.yaml:251-382` + `docs/audit/oi60-streak-identity.closure.yaml`),
  not carried from this entry's own text, which was wrong. The three `enable_hold_weeks` rows were
  read directly and all still carry `flip_reviewed: false`. FOB-1's six surfaces were each read in
  source before being fixed — one (`phase_roadmap_screen.dart`) reaches the clamp through
  `getProgramWeek`, so the FOB's own file list understated it rather than overstating it, and one
  (`profile_content.dart`) is a consumer the FOB named only via its provider.
- **Identified**: 2026-07-26
- ⚠ **Corrected 2026-08-20.** This entry read *"7 unstarted flip-on-blocker items (FOB-1…FOB-7)"*
  and `OPEN_INDEX.md` repeated it. That was stale on three counts as of 2026-08-13, and the index
  is generated from this line, so the whole board carried the wrong number: **FOB-2 CLOSED**
  (`docs/audit/oi60-streak-identity.closure.yaml`, diagnose `a3f8d1`), **FOB-7(c) verified clean**
  (the report was stale — ai-media-proxy already carries both the 10K cap and the FC7 nonce fence),
  **FOB-7(d) CLOSED**, and **FOB-6 SPLIT OUT to OI-125** by founder decision as a FEATURE that is
  explicitly *not* a flip blocker. "Unstarted" was also wrong for the two that had already shipped.
- **Blocked on**: **3 remaining flip-on blockers** in `docs/ship_dark_pending_review.yaml` —
  **FOB-3, FOB-4, FOB-7(a)/(b)**. The coach snapshot and the Sunday push / weekly report still tell
  every holder a false week-4 story; `currentPhaseCompletionRate` still folds hold days into the
  PRO-advance gate input and `PlanIntegrityReconciler` still scans weeks 1-4 only. FOB-3/FOB-4
  require ai-proxy + weekly-recap-ready + weekly-report EF redeploys — each its own explicit
  authorization (§4.3), plan approval ≠ deploy approval.
- ✅ **FOB-3 CODE LANDED 2026-08-21** — branch `claude/oi-pending-hold-weeks-1od97o`, diagnose
  `b6e1f4`, closure `docs/audit/fob3-coach-hold-block.closure.yaml`, behavioral test
  `test/contracts/hold_snapshot_block_behavioral_test.dart` (7 cases, mutation-proven on five legs,
  each reddening exactly one test). The snapshot gains a facts-only `hold` block through a new
  `holdSnapshotBlock()` seam, emitted with a null-aware element so a non-holder's snapshot gains no
  key at all, and `hold` joins `trimSnapshotToBudget`'s keep set. The INSTRUCTION half — a HOLD
  WEEKS section in `captain_manual.ts` telling the coach to read `snapshot.hold`, quote
  `hold.label`, IGNORE both projected week fields BY NAME and NEVER say final-week-of-Phase-I —
  is **INERT until ai-proxy is redeployed** (credentials, not permission; see
  `docs/operations/FOUNDER_LAPTOP_HANDOFF.md` §2-4).
  ⚠ Two things nearly shipped broken and are worth carrying forward: 20 **unescaped backticks**
  inside the `CAPTAIN_MANUAL` template literal would have terminated it and boot-failed ai-proxy
  on the next deploy without failing loudly (deploy-skill 6.5); and the first **keep-set test
  proved nothing** — dropping `'hold'` from the keep set left every test green, because the
  trimmer shrinks the LARGEST non-kept field and two giant bloat fields absorbed the whole overage
  before the ~110-char block was ever reached.
  Deliberately NOT done: suppressing the two week fields. They are read by non-hold logic, and
  OI-60's own `do_not` forbids the obvious replacement.

  ⚠ **FOB-4 needs MORE than a redeploy, and the ledger's `why:` does not say so.** Measured
  2026-08-20 against the live schema: `information_schema.columns` in schema `public` contains
  **zero** columns matching `%hold%`, and `user_progress` carries no hold field of any spelling
  (23 columns, listed live). `is_hold` is written by `holdWeek()` onto local schedule rows and
  **never reaches the cloud** — there is no `workout_schedule` table in `public` at all. So
  `weekly-recap-ready` and `weekly-report` cannot branch on a hold no matter what is deployed:
  the signal does not exist on their side of the wire. Whoever takes FOB-4 must decide how hold
  state crosses that boundary FIRST (a `user_progress` column, or a derived RPC), which means a
  MIGRATION and its own live-apply authorization on top of the two redeploys. Do not schedule
  FOB-4 as a redeploy-only unit.
- ✅ **FOB-5 CLOSED 2026-08-20** — diagnose `c7a3b9`, closure `docs/audit/fob5-hold-telemetry.closure.yaml`,
  migration **120 applied live** (founder-authorized). `holdWeek()` now emits `hold_week_started`,
  consumed by three new `hold_*` columns on `founder_metrics_engagement()` that reach the founder
  dashboard with no EF redeploy. ⚠ FOB-5's own prescribed fix (`where channel = 'app'`) was
  **wrong and was not applied** — it matches 7 of 116 rows. The metric now reads **22 instead of
  116**. One self-inflicted regression was caught and closed inside the batch: the required
  `DROP`+`CREATE` reset the function's ACL and briefly made it anon-executable (finding FOB-5-E).
  ⚠ Read `oi60-streak-identity.closure.yaml` before attempting FOB-7(b): widening the 1..4 scan is
  already REFUTED (the scan IS the re-anchor trigger, so widening buys no healing and only makes
  the re-anchor fire more often — the P0-11 concern `d7f3a9` rejected). The shape is *split the
  trigger from the write.* OI-127 is routed to whichever batch takes FOB-7(a)/(b), so one batch
  holds the reconciler context.
- ✅ **FOB-1 CLOSED 2026-08-20** — branch `claude/oi-pending-hold-weeks-1od97o`, diagnose `f4c8e1`,
  behavioral test `test/contracts/hold_week_identity_behavioral_test.dart` (16 cases, mutation-proven
  on both protective legs: neutering the hold arm reddens 3, removing the flag gate reddens 5 across
  this file and `hold_display_read_path_test.dart`). Adopted "a hold suppresses the week number; Hn
  is the identity" on all **six** in-repo surfaces that printed the clamped week 4 to a holder
  (home eyebrow, profile subtitle, journey timeline ×2, phase-roadmap header, share-as-video stamp
  + its Remotion composition), behind a new single-gate seam
  `WorkoutScheduleReadService.weekIdentity()`. Two named residuals, neither deferred:
  `ai_snapshot_builder.dart` is **FOB-3's** by the board's own division (it rewrites the same lines
  to add the `hold` block and needs the ai-proxy redeploy — touching it twice would ship a
  half-changed snapshot contract), and `telegram-bot/bot.py` is **upstream_blocked**, a separate
  repo on the OpenClaw VPS (§2).
- **What's missing**: Own full ×2 per §4.12.4 (flip-on is where real user risk starts) — the four
  remaining FOB items closed first. The flip-on commit must clear **all four** `enable_hold_weeks`
  rows in the ledger (`hold-mechanic`, `hold-display`, `hold-display-fixes`, and
  `claude/oi-pending-hold-weeks-1od97o`) in one commit — corrected from "three" on 2026-08-21 when
  FOB-1+FOB-3 added the fourth.

## OI-61 — Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup

- **Status**: OPEN
- **Verified**: 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Identified**: 2026-07-26 · Units 2+3+FC8 shipped `237c347`, ai-proxy v73
- **Blocked on**: none — its only blocker was OI-52, which closed 2026-07-27. Pickable now.

## OI-62 — Coach-reliability: FC6 + Unit A

- **Status**: OPEN
- **Verified**: 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Blocked on**: FC6 is unblocked — its OI-52 dependency closed 2026-07-27. Unit A: F3 anytime,
  F1 founder-gated.
- **Identified**: 2026-07-26 · Unit B merged `b2ea2e3`, ai-proxy v72

## OI-63 — Restore C2: 137-policy RLS initplan

- **Status**: OPEN
- **Verified**: 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Identified**: 2026-07-26 · restore-perf C3 shipped
- **Blocked on**: none — it was sequenced after OI-52, which closed 2026-07-27. Pickable now.

## OI-64 — Discipline-overhead: the three unbuilt gates

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-26 · discipline-overhead shipped `dd51a40a`
- **What's missing**: Stop-hook completion gate · automatic ship-dark verification gate (proving a
  flag really is default-OFF and byte-identical from a script) · ship-dark ledger-enforcement gate.

## OI-65 — Qualification-Exam feature

- **Status**: OPEN
- **Blocked on**: FOUNDER — **dated decision 2026-08-05: pick this up in January 2027.** Nothing
  technical blocks it and it blocks nothing else; it is a pure enhancement, and the founder scoped
  it out of the current horizon deliberately. Kept `OPEN` rather than given some "parked" status —
  it is not done, and it should keep showing up in the open count. Same shape as OI-56's
  September decision, and for the same stated reason.
- **Verified**: 2026-08-05 — BLOCKER ONLY (the founder decision above was taken in-session). The
  issue's own substance — the 9 locked decisions and the branch state — has NOT been re-checked
  since filing.
- **Identified**: 2026-07-26
- **What's missing**: 9 decisions locked, committed `7328c99` on branch `qualification-exam`,
  **unpushed**. Pre-implementation.
- ⚠ **Not an agent-side deferral under §4.2.** That rule bans an AGENT from re-labelling its own
  unfinished work to avoid completing it. This is the founder making a product-scope call with a
  date attached, which is the one case §4.2 explicitly reserves to them ("an explicit founder
  product-scope decision"). Recorded here so a future session reads it as neither pickable work
  nor a violation.

## OI-66 — Prove or remove the CI gradle cache

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-26 · ci-speed batch `904e6961`
- **Risk class**: unverified optimisation
- **What's missing**: The cache is **3.4 GB**; restore-and-extract cost may exceed the Gradle work it
  saves. First run only populated it, so its value is still unmeasured. Compare a warm-cache run's
  `Build Check (APK)` duration against the 7m41s/7m47s uncached baseline. **If it is not a clear win,
  take it back out** — an unmeasured optimisation is tech debt.

## OI-69 — Nothing detects this backlog going stale AGAIN

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-26 · review round 1, "what this misses"
- **Risk class**: the original failure, recurring
- **What's missing**: even the withdrawn mechanism would not have caught renewed neglect — its gate
  was satisfied by typing `none-affected`, and its digest was passive. The 70-day dormancy would
  recur identically. None of the checks that would actually detect it exist: (a) days-since-this-file
  -last-modified exceeding a threshold, (b) when a record declares specific `OI-NN` ids, requiring the
  merge diff to actually touch this file, (c) verifying an OI declared closed really flipped to
  `CLOSED`.
- **Honest framing**: shipping this file repo-tracked makes the backlog **visible** from any machine,
  any session, and GitHub. That is the durable half and it is real. It does not make neglect
  **detectable**. Recorded rather than papered over.

## OI-73 — ~10 Edge Functions still run the pre-`9ab9f42b` cron auth gate

- **Status**: OPEN — hygiene, **not** an outage
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-27 · after the cron-auth restore
- **Corrected 2026-07-27** (gate-input-family batch), two errors in this entry's own text:
  1. It cited **`a3ff9571`** as the restoring commit. That is not a commit —
     `git log a3ff9571` returns *unknown revision*. It is a **review-file** hash
     (`docs/reviews/a3ff9571fbc9-review.md`). The actual cron-auth restore is `9ab9f42b`,
     merged as `d2b1b74b`. The title above is corrected.
  2. It said the affected functions "carry a live `deno.land/x/jose` remote import". True of the
     **deployed bundles**, not of git — the only tracked hits are a history comment and
     `import_map.json`. Wording corrected below. Same class as
     `feedback_mistake_unverified_done_claims`: an artifact hash read as a commit, and a
     deployed-side fact stated as a source-side one.
- **Count revised ~15 → ~10.** The six notif-prefs deploys on 2026-07-27 shipped from current git,
  so five of them incidentally picked up the clean gate. Verified in the deployed bytes rather than
  by version number: `jwtVerify` = 0 occurrences, `env.get("SUPABASE_JWT_SECRET")` = 0,
  `CRON_SECRET` = 10, and `jose` appearing only inside a comment.
- **What's true**: cron auth is LIVE. Migrations 107-110 plus the dashboard secret restored it with
  no redeploy, because the deployed gate checks a legacy `CRON_SECRET` hatch *before* the
  unreachable `SUPABASE_JWT_SECRET` path. `cron_call_log` shows 15 functions succeeding 2026-07-26.
- **What's left**: the remaining functions still carry the dead `SUPABASE_JWT_SECRET` branch, and
  their **deployed bundles** still resolve a `deno.land/x/jose` remote import. If that pinned URL
  ever 404s upstream, every one of them boot-fails at once
  (`feedback_mistake_remote_dep_rot`). `morning-alert`, `compute-coach-signals`, `weekly-recalc`
  and `compute-admin-metrics-daily` already carry the clean gate, as do the five cleaned on 07-27.
- **How to do it**: one function at a time with verification between — the deploy skill's §6.6
  warns that latent dep-rot boot-fails only on the NEXT redeploy, so a blind batch is the wrong
  shape.

## OI-74 — Notification-prefs helper fetches whole snapshot_json history, unbounded

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-27 · B-pass on notif-prefs Units C..G
- **Risk class**: silent degradation to SEND at scale
- **What's wrong**: `supabase/functions/_shared/notification_prefs.ts` selects the entire
  `snapshot_json` for EVERY historical row of every queried user — no `.limit`, no `.range`, no
  JSON-path projection. `morning-alert` deliberately paginates users at `PAGE_SIZE = 200` "to cap
  memory", and this query re-imports each page's whole snapshot history underneath it.
- **Failure shape**: Edge Function memory/timeout, or PostgREST max-rows truncation silently
  dropping the oldest-latest users from the map. Truncation degrades to SEND, so a user's OFF stops
  being honoured with **no error and no signal** — the same silent-inertness class the batch closed.
- **Fix shape**: `.select("user_id, snapshot_json->notification_preferences")` and/or a
  `DISTINCT ON (user_id)` RPC. Schema-adjacent, so it wants its own review rather than a late edit.
- **Not urgent today**: 17 users, 91 rows. It becomes real with growth, which is exactly when
  nobody is looking.

## OI-77 — AI-coach chat photo references never round-trip through cloud sync/restore

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-30 (B-pass, coach-media-consent / Unit 8) — read the actual push and
  restore payloads directly, not inferred.
- **Identified**: 2026-07-30 · round-1 review of Unit 8 (coach-media-consent, OI-25). A
  `mcp__ccd_session__spawn_task` chip (`task_e8b00d00`) was also raised in that session for
  convenience, but a chip is ephemeral session UI state, not a durable repo artifact — this entry
  is the authoritative, git-tracked record; the chip is not required for this to be actionable.
- **What's wrong**: `lib/core/services/sync/sync_coach.dart`'s push payload
  (`_syncCoachInteractions`, `:149-157`: `id, user_id, channel, user_message, ai_response,
  model_used, created_at`) and restore payload (`_restoreCoachInteractions`, `:204-217`: `id,
  user_message, ai_response, model_used, mode, is_user_message, created_at, channel, source`) have
  never included ANY `media_*` field — not `media_url`/`media_type` (pre-existing, predates OI-25
  entirely), and not the two OI-25/Unit-8 fields (`media_storage_path`, `media_save_state`), which
  simply inherit the same pre-existing gap rather than introduce a new one.
- **Failure shape**: on a cross-device (or post-reinstall) restore, a HISTORICAL AI-coach chat
  message that had a photo degrades to caption-only text — `ChatBubble`'s `hasMediaUrl` gate and
  `chat_area.dart`'s `onSaveMedia` wiring are both null-gated on fields that never survived the
  restore, so neither the image thumbnail nor the save-consent chip render at all. The photo
  itself is NOT lost (it still exists in `chat-media`/`coach-media` Storage, and an
  already-saved copy still renders correctly in `SavedCoachPhotosScreen`, which lists directly
  from Storage, not from restored Hive state) — only its appearance in that one historical chat
  bubble on the second device.
- **Fix shape**: extend both `_syncCoachInteractions`'s push payload and
  `_restoreCoachInteractions`'s restore payload to include `media_url`, `media_type`,
  `media_storage_path`, `media_save_state`. Needs its own scoping pass first: whether this was a
  deliberate scope-limit on what channel gets cloud-synced (vs. an oversight) was not determined —
  distinguishing the two is exactly the judgment call this OI exists to hold, not a guess to bake
  into a fix.
- **Blast radius estimate**: `account` (touches `sync_coach.dart`'s push/restore contract for an
  existing table, no new migration).

## OI-85 — repair the `schedule_*` rows a DECLINED phase advance leaves behind (P2)

- **Status**: OPEN
- **Blocked on**: none — but three mechanisms are already refuted (below). The next attempt needs
  the losing generation's own key set, which nothing currently records.
- **Verified**: 2026-08-05 (telemetry-readiness re-checked against live v11 + `pubspec.yaml`
  `1.0.0+37` — see the measurement note below; the three refutations were reproduced from code
  2026-08-03 in Unit A / diagnose `d1f6b3` and are unchanged)
- **Identified**: 2026-08-03 · split out of OI-83 per §4.12.1 after two context-blind review
  rounds refuted two successive repair designs, the second as a data-loss risk.
- **Risk class**: stale local rows after a lost advance race (not a demotion — the counter is
  correct; the plan content is not)
- **What's wrong**: when `commitPhaseAdvance` DECLINES after `generateAndSchedule` has already
  run, the `schedule_*` rows and plan window written for the phase we did not advance to are
  left in place. Nothing rolls them back, so the user can read a plan for a phase they are not
  on. Instrumented via `phase_advance_declined_rows_stale` — Unit A added the telemetry precisely
  so the frequency can be measured before more repair machinery is built.
- **⚠ THE MEASUREMENT HAS NOT STARTED (verified 2026-08-05).** Both halves were checked directly,
  not assumed. Server: the `log-client-error` HIGH-priority lane went live 2026-08-05 as **v11**
  (it had been v10 since ~2026-06-18, so this op-type was classified LOW — and therefore droppable
  past the 2000/day budget — for the whole time it existed). Client: the emitter at
  `pro_phase_advance.dart:405` landed in `5131244e` (2026-08-03), but the newest shipped APK is
  `1.0.0+37` from `99e145d2` (**2026-07-27**), so **no installed build emits this event at all**.
  The deploy pre-positioned the server; the clock starts at the next APK ship, not before. Reading
  an empty `client_errors` count today as "the condition is rare" would be reading a silent
  pipeline, which is exactly the mistake `feedback_backend_collapse_blinds_telemetry` names.
- **Three refuted mechanisms — do not re-propose without new evidence:**
  1. *Make the restore writers take `withPhaseAdvanceLock`.* It is a TRY-lock
     (`pro_phase_advance.dart` returns `ifBusy` immediately, no queue), so a restore arriving
     mid-generation is turned away and the user's cloud progress never lands. Trades stale rows
     for a DROPPED RESTORE.
  2. *Force `PlanIntegrityReconciler.reconcile` past its `needsHeal` gate.* Inert:
     `mergeScheduleEntry` then applies the same "local already has exercises → keep local"
     predicate per row, and these rows have their exercises. Only rest days would heal.
  3. *Add `preferSnapshot` + delete rows past the re-anchored `plan_end`.* DATA LOSS. Cloud
     `plan_json` is pushed only by the daily full sync (`sync_service.dart` `_fullSyncInterval`),
     so the snapshot can describe the PREVIOUS phase window and the sweep would delete the
     winner's freshly-generated rows. Separately, `_syncWorkoutPlan` snapshots every `schedule_*`
     key box-wide, so `preferSnapshot` would also revert an un-synced local exercise swap on any
     planned day (`swap_service.dart` rejects only `completed`).
- **Fix shape (what a fourth attempt needs)**: the set of keys the LOSING generation wrote.
  `generateAndSchedule`'s caller knows its `startDate` and phase; recording that window (or the
  written key set) and scoping the repair to it removes every dependency on a stale cloud
  snapshot. Measure `phase_advance_declined_rows_stale` first — if the condition is rare enough,
  the honest answer may be to keep reporting and not build the repair at all.
- **Blast radius estimate**: `account` (`lib/shared/services/pro_phase_advance.dart` +
  `graduation_screen.dart`); no migration.

## OI-86 — two concurrent `flutter test` runs on this machine corrupt each other's Hive state (P2)

- **Status**: OPEN
- **Blocked on**: none — the mechanism is understood and was reproduced twice; scheduled work.
- **Verified**: 2026-08-03 (twice in one day, both times the same tests passed standalone
  immediately afterwards on the identical tree)
- **Identified**: 2026-08-03 · Unit B (`b4e9c7`) — once during overlapping `safe_commit` runs,
  once during a `safe_push` whose pre-push suite raced another session's suite.
- **Risk class**: test-harness isolation / false-red on a real gate
- **What's wrong**: Hive test boxes are opened from a **process-shared** location, so two
  `flutter test` runs executing at the same time on this machine collide. The loser sees
  `HiveError: Box not found. Did you forget to call Hive.openBox()?` from
  `HiveService.userBoxGuarded` → `wrapUserScopedBox` (`guarded_box.dart:341`), and whatever
  assertion followed the failed read then reports a *value* mismatch rather than the underlying
  throw — which is what makes it easy to mis-diagnose.
- **Two confirmed occurrences, same day, same test family**:
  1. Two `safe_commit.sh` invocations overlapped (the first had not finished when a second was
     launched after a tool timeout). `subscription_expiry_banner_behavioral_test.dart`
     "a marker stamped under session A is NOT visible to session B" failed, then passed
     standalone seconds later on the identical tree.
  2. `safe_push.sh`'s pre-push full suite ran while another session had ~10 dart/flutter
     processes live. `subscription_cqrs_behavioral_test.dart` "genuine expiry still downgrades
     and still stamps `pro_lapsed_at`" AND the same expiry-banner test failed —
     `Expected: null / Actual: '2026-08-02T20:05:42.435058'`, immediately preceded by
     `[MigratedKey.delete] userBox expiresAt threw: HiveError: Box not found`. The push was
     correctly REJECTED (`git exit 1`, `origin/main` unmoved). A retry with the machine quieter
     passed **4188 tests, 0 failures** on the same commit with no code change.
- **Why it is not "just flaky"**: CI is green on the same commits — an isolated single-runner
  environment never hits it. The failure is deterministic given concurrency, and it produces a
  **false red on a real gate**, which is the dangerous shape: it invites exactly the hook-bypass
  reflex CLAUDE.md bans, and it trains the reader to dismiss genuine failures in that test
  family.
- **Fix shape (not yet attempted)**: give each test process its own Hive directory — a per-run
  temp dir keyed on PID or the runner's shard id, set in the shared test bootstrap rather than
  per-file. The git-index half of this exact "one machine, two sessions" problem was solved
  structurally by §4.13 (one worktree per session → one index per session); this is the Hive
  half.
- **Interim discipline (already in force, and not a fix)**: never launch a second
  `safe_commit.sh` / `safe_push.sh` while one may still be running — a Bash tool timeout does
  NOT kill the process (`feedback_git_landing_verification.md`). Both occurrences today began
  that way.
- **Blast radius estimate**: `feature` (test harness + bootstrap only); no migration, no schema,
  no runtime code.

## OI-87 — one session's non-compliant merge into local `main` blocks every other session's push (P2)

- **Status**: OPEN
- **Blocked on**: none. The concrete instance RESOLVED 2026-08-05 — the session that did the work
  produced `docs/plan-reviews/restore-onboarding-signin-fix.md` (`review_rounds: 2`,
  `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`), so the keystone gate is
  satisfied by a real review rather than by anyone attesting to work they did not do. The
  STRUCTURAL problem below is unfixed and is what this entry now tracks.
- **Verified**: 2026-08-05 — record confirmed present by direct read of its frontmatter, and CI is
  green on the pushed range containing that merge (`9e7d4769`), which is the gate's own verdict.
  The 2026-08-03 reproduction of the blocked push (both worktrees + the then-missing file) stands.
- **Identified**: 2026-08-03 · Unit B (`b4e9c7`) push attempt
- **Risk class**: cross-session shared mutable state / coupled compliance
- **What happened**: with `origin/main` green at `14c7aeed`, another session merged
  `onboarding-oauth-session-fix` into **local** `main` at 20:43 (`f0b98c8b`). That branch is
  `>=account` (it touches `lib/features/onboarding/providers/onboarding_provider.dart`) and has
  **no** `docs/plan-reviews/onboarding-oauth-session-fix.md` — not committed, not drafted; the
  other worktree's tree is clean. This session then tried to push an unrelated docs-only commit
  (OI-86) and `check_plan_review_record_exists.dart`, run over the full prospective push range,
  correctly FAILED on the foreign merge. The push was not attempted.
- **Why this is structural, not just someone forgetting**: §4.12.3 puts the gate at **push time
  in CI** on purpose — a local pre-commit `MERGE_HEAD` check is bypassable and a `--no-ff` merge
  skips the local hook entirely, so CI-at-push is the only point that cannot be evaded. Correct
  for ENFORCEMENT. The unintended consequence is that a non-compliant merge can sit in local
  `main` indefinitely, and because the gate is RANGE-based, it is inherited by whoever pushes
  next. Compliance becomes coupled across otherwise-independent sessions, and the session that
  is blocked is precisely the one that cannot fix it: the only remedy is an attestation that
  must come from whoever actually ran the review.
- **The dangerous incentive it creates**: the blocked session's fastest path to unblocking is to
  author the missing record itself. That would be a FALSE ATTESTATION — a claim that a ×2
  context-blind review and ground-truth audit happened when they did not. This is strictly worse
  than any defect the review would have caught, and worse than the class of false-claim finding
  this very batch fixed (a P1 where three documents said a fix "was restated" when the file had
  not been touched). Any future automation here must not make fabrication the path of least
  resistance.
- **Third instance of one pattern today** — "one machine, N sessions, shared mutable state":
  1. `.git/index` — **solved** by §4.13 (one worktree per session).
  2. Hive test boxes — **OI-86** (concurrent `flutter test` runs corrupt each other's state).
  3. local `main` itself — THIS item. §4.13 explicitly designates the shared main folder as
     "INTEGRATION-ONLY: reads, `git merge <branch>` + `git push`", i.e. multi-session merging
     into one local `main` is by design. §4.13 fixed the index facet and, by encouraging many
     parallel session worktrees, made facets 2 and 3 more likely rather than less.
- **Fix shape (not yet attempted)**: a LOCAL, immediate, advisory warning at merge time — a
  `post-merge` hook (or a check inside the documented merge step) that, when a `--no-ff` merge
  into `main` brings in a branch whose blast-radius is `>=account`, prints loudly if
  `docs/plan-reviews/<branch>.md` is absent or non-converged. It cannot be an enforcement gate
  (post-merge hooks do not fail the merge, and any local check is evadable — which is exactly
  why §4.12.3 chose CI). But it would surface the problem to the session that CAUSED it, at the
  moment it was caused, instead of to an unrelated session minutes-to-hours later. That is the
  whole delta: same enforcement, correct attribution.
- **Interim discipline (already in force)**: always run
  `PUSH_BEFORE=<origin tip> dart run scripts/check_plan_review_record_exists.dart` over the FULL
  prospective push range before pushing — never `HEAD^1..HEAD`. That is what caught this. Failing
  to do so on 2026-08-03 morning is what put `ca4ef2c3` on `origin` red.
- **Blast radius estimate**: `feature` (a hook + docs); no runtime code, no migration, no schema.

## OI-88 — `restoring_screen.dart` split owed (allow-list entry now removed) (P3)

- **Status**: OPEN
- **Blocked on**: nothing external — but the split is now known to be **bigger than "move two
  widgets"**, and the file has **ZERO margin**. See the 2026-08-10 update.
- **Verified**: 2026-08-10 (`wc -l` = **800** on `main` @ `1e981c82`;
  `check_god_screen_max_lines.dart` passes — at exactly the ceiling, so the NEXT change to this
  file fails the gate outright)
- **UPDATE 2026-08-10** · `google-signin-misroute`, merge `1e981c82`, diagnose `c2e9f4`. The
  **extraction half shipped**: `_healAfterRestoreInBackground` → `restoring/heal_after_restore.dart`
  and `_AnimatedDots` → `restoring/animated_dots.dart`, both as `part` files of the same library
  (private names unchanged, no call site moved). That is exactly the two candidates the fix shape
  below names. It did **not** close this OI, because the fix's own new code consumed the headroom
  it bought: 791 → 728 → 800.
  - ⚠ **The remaining work is the STATE-CLASS split, and it was attempted and REVERTED in that
    same batch.** Moving `_RestoringScreenState` into `restoring/state.dart` leaves the head file
    at 63 lines and immediately breaks: **5 `line_range` citations in `docs/sot_registry.yaml`**,
    `check_reader_manifest_complete.dart`, and `restoring_screen_timeout_test.dart` — because a
    dozen registry entries and several source-grep tests point at line numbers INSIDE this file.
    Re-anchoring all of them is the actual owed work, and it is its own batch. Landing a
    half-migrated registry to save one refactor trades contained hygiene debt for live correctness
    risk.
  - One thing that batch DID make safe: `test/helpers/read_screen_source.dart` gained
    `readLibrarySource()` / `readRestoringScreenSource()`, which resolve parts by parsing the head
    file's own `part` directives instead of a hardcoded folder map. **17** test files source-read
    this screen (the figure carried in earlier sessions was "4"); they now follow a split
    automatically rather than silently reading a subset.
- **Prior verification**: 2026-08-05 (`wc -l` = 791 on `repo-gate-pattern-sweep`; allow-list entry
  removed in the same commit; `check_god_screen_max_lines.dart` passes with the file no longer
  exempt)
- **UPDATE 2026-08-05** · `repo-gate-pattern-sweep`, diagnose `e7c3b9`. A comment trim took the
  file 824 → 791, so the allow-list entry was removed — the gate protects this file again on its
  own terms. **This did not do the owed work.** No code moved, no file was created; the trim was
  comments only (proven byte-identical in code by strip-and-compare, twice). The fix shape below
  is untouched and this OI stays OPEN, narrowed to it. Two things to carry forward: (a) that
  batch's plan-review record claimed removing the entry would *close* OI-88 — it was wrong and is
  corrected in the same commit as this update; (b) 791 leaves **nine lines** of margin, which is
  precisely the condition the allow-list's own `graduation_screen` note records as having created
  OI-84 (it sat six under, so a fix could not touch it at all). The next change to this file will
  most likely have to do the split first rather than trim further.
- **Identified**: 2026-08-03 · `restore-onboarding-signin-fix` batch. Diagnose `a3f6d9`'s fix
  (local-onboarded-flag stamp at all three paths to `/home` in `RestoringScreen`) added 24 lines
  net after comment-trimming, pushing the file from 800 to 824 lines — 24 over Gate 43's ceiling.
- **Risk class**: god-screen / tech-debt ladder regression — same class as OI-84
  (`graduation_screen.dart`).
- **What happened**: `restoring_screen.dart` sat exactly at the 800-line ceiling pre-diff (never a
  C3/C4 target). The a3f6d9 fix could not land without tripping Gate 43. Comments were trimmed to
  the minimum non-obvious "why" first (saved ~15 lines); the remainder is irreducible without
  either restructuring the file or resorting to single-line `if` statements inconsistent with the
  rest of the file's style. Added to the gate's transitional allow-list
  (`scripts/check_god_screen_max_lines.dart`) on explicit founder authorization in chat.
- **Why this is tracked rather than closed**: same rationale as OI-84 — the allow-list's own header
  says it "MUST shrink to empty when the audit ladder closes". An eighth entry with no owed-work
  record would quietly reverse that direction. This OI is that record.
- **Fix shape (revised 2026-08-10 — the easy half is DONE)**: the two named extraction candidates
  (`_healAfterRestoreInBackground`, `_AnimatedDots`) shipped in `1e981c82` as `part` files under
  `lib/features/auth/screens/restoring/`. The allow-list entry was already removed on 2026-08-05.
  **What remains is the state-class split, and its cost is the citation re-anchoring, not the
  move:**
  1. Move `_RestoringScreenState` into `restoring/state.dart` as `part of '../restoring_screen.dart'`
     (mechanical; the head file keeps its `*_screen.dart` name so it stays inside Gate 43's
     filename regex — deliberately unlike `active_workout/screen.dart`, which the regex does not
     match at all).
  2. Re-anchor **every** `docs/sot_registry.yaml` entry whose `file:` is `restoring_screen.dart` —
     there are ~5 with `line_range`s plus a dozen `forbidden_patterns` exemption rows.
  3. Fix `check_reader_manifest_complete.dart` and `restoring_screen_timeout_test.dart`, both of
     which key off content that moves.
  4. Verify with `sot_registry_completeness_test.dart` (the Gate-7 mirror that catches
     `line_range` overruns) and `reader_manifest_exhaustiveness_test.dart`.
  Sequence matters: do this BEFORE any other change to the file, because there is no margin left
  to absorb one.
- **Blast radius estimate**: `account` (`restoring_screen.dart` is on the auth post-auth-boot path);
  no migration, no schema.

## OI-90 — `GuardedBox.empty`'s "reads serve empty" is bypassed by the seven plain `Box` getters (P2)

- **Status**: OPEN
- **Blocked on**: nothing — but the reader-vs-writer split below must be measured before a fix is
  scoped, and that measurement is the first unit of work.
- **Verified**: 2026-08-04 (call-site counts below produced by direct grep; the getter bodies and
  the throw site re-read directly)
- **Identified**: 2026-08-04 · the B-pass review of the Unit 1 onboarding session-guard batch
  (diagnose d4e8a2). Deliberately NOT folded into that batch — adding an unrelated
  core-services change to a diff that had just passed ×2 review + B-pass would have invalidated
  the review it just passed.
- **Risk class**: cross-account guard / auth-transition resilience — same family as b8e3f1
- **What's wrong**: b8e3f1 established the contract that during the auth/Hive disagreement window
  (authenticated, Hive owner still null) a user-scoped box **serves empty on reads and throws loud
  on writes** — reads degrade to an empty state, only writes fail. That contract is implemented on
  `GuardedBox`. But all seven plain `Box` getters at
  `lib/core/services/hive_service.dart:225-231` are defined as
  `Box get userBox => userBoxGuarded.rawBox;` (and the same for workout/nutrition/health/custom/
  coach/notifications) — and `GuardedBox.rawBox`
  (`lib/core/services/guarded_box.dart:170-176`) throws
  `StateError('GuardedBox.empty: rawBox unavailable during auth/Hive disagreement')`
  unconditionally when the stub is in play. So any caller on a plain getter gets a **throw on a
  READ**, which is precisely what b8e3f1 exists to prevent.
- **Scope (measured, and deliberately incomplete)**: `HiveService.instance.<box>` plain-getter
  call sites under `lib/` — userBox 38, workoutBox 48, nutritionBox 20, healthBox 26, customBox
  17, coachBox 22, notificationsBox 8 = **179 total**, against **14** uses of the `*Guarded`
  getters. ⚠ That 179 counts reads AND writes together; writes SHOULD throw, so it is an upper
  bound on the affected surface, not the finding's size. Splitting read-vs-write across those 179
  is the first thing the fix needs and has not been done.
- **Why it likely hasn't bitten visibly**: the disagreement window is short (~50-500 ms on
  signOut+signUp transitions), and `app_router._authRedirect` routes an authenticated-owner-null
  session to `/restoring` before most screens mount. So this is a latent resilience gap, not a
  standing breakage — consistent with b8e3f1 having been found via a blank-Home crash rather than
  a broad outage.
- **Fix shape (not yet attempted)**: measure the read/write split across the 179 sites; then
  either migrate read call sites to the `*Guarded` getters, or give `rawBox` a read-safe sibling
  that returns an empty view instead of throwing. Either way it needs the same behavioral
  treatment as b8e3f1 — a test driving a real authenticated-owner-null window and asserting reads
  degrade rather than throw — plus a kill-switch, since this touches the cross-account guard.
- **Blast radius estimate**: `platform` (`lib/core/services/hive_service.dart` +
  `guarded_box.dart` are core session/auth infrastructure); no migration, no schema.

## OI-93 — a deployed Edge Function can lag the repo indefinitely; the parity test that would notice compares repo-to-repo (P2)

- **Status**: OPEN
- **Blocked on**: nothing. The mechanism is understood and was measured, not inferred. Building
  the detection is the work.
- **Verified**: 2026-08-05 (found by measuring the repo-vs-live delta of `log-client-error` during
  its authorized deploy; live source read directly via the management API, both before at v10 and
  after at v11)
- **Identified**: 2026-08-05 · while deploying `log-client-error` under explicit founder
  authorization
- **Risk class**: silent server/client contract drift — observability lane specifically
- **What's wrong**: `test/contracts/high_priority_op_types_parity_test.dart` pins the Dart client
  list (`lib/core/services/error_telemetry.dart:86`) against the Edge Function's
  `HIGH_PRIORITY_OP_TYPES` **as it exists in the repo**. Its own header even documents the missing
  step — "Fix path when this test fails: … 3. Server-side: redeploy `log-client-error` Edge
  Function" — but a repo-to-repo source-grep is green whether or not that redeploy ever happened.
  Nothing anywhere compares repo source to deployed source.
- **The measured instance**: live `log-client-error` sat at **v10 since ~2026-06-18**. Three
  commits landed on `index.ts` after that. At the moment of the 2026-08-05 deploy the live
  allowlist ended at `streak_freeze_lapse_reset` and was missing **7** op-types — 4 from Hermes C8
  (`e33c39e4`, 2026-07-30) and 3 from Unit A / OI-83 (`5131244e`, 2026-08-03). Every one of those
  events was being classified LOW server-side, i.e. droppable once a user passed the 2000/day
  budget, which is the exact silent-drop failure the priority lane was built to prevent.
- **Why it is easy to miss**: the drift is invisible from inside the repo. `flutter test`, the
  pre-commit gates and CI were all green throughout the seven weeks, because every one of them
  reads the repo. The only witness is the live project.
- **Two prior instances of the same class** (this is the third): OI-73 — ~10 Edge Functions still
  running the pre-`9ab9f42b` cron auth gate; and the `restore-user-snapshot` redeploy note at
  `open_issues.md:481`. Both are "deployed artifact lags committed source, noticed by hand."
- **Fix shape (not yet attempted)**: a check that reads deployed Edge Function source via the
  management API (`GET /v1/projects/<id>/functions/<slug>`) and diffs the contract-bearing
  constants against the repo. Two honest constraints to design around: it needs a management-API
  token, so it cannot run in the ordinary pre-commit path and probably belongs in CI with a
  secret, or in `/build-apk`'s gate set; and it must not fail closed on unrelated formatting, so
  the comparison should target named constants rather than whole files. A far cheaper first
  version — a release-checklist line item that lists every Edge Function whose repo source has
  commits newer than its deployed version — would have caught this instance and needs no new
  parsing at all.
- **Blast radius estimate**: the gate itself would be `feature` (a script plus CI wiring). The
  drift it detects is not — this instance sat on the telemetry lane, and OI-73's sits on cron
  auth.

- **FOURTH INSTANCE, 2026-08-08 — same function again, inside a single batch.** During
  `post38-auth-fixes` slice-0 scoping: deployed `log-client-error` **v12** carries a FIVE-entry
  `PRE_AUTH_OP_TYPES`; the repo source carries **six**. Round-1 review of that same batch added
  `auth_send_phone_otp_failed` — the one pre-auth op_type that was already emitted signed-out and
  therefore still 401'd — and the redeploy never happened. Measured by decoding
  `.claude/_payload_log-client-error.json` as UTF-8 and diffing against the worktree source
  (18334 chars deployed vs 19253; the allow-list block is the sole difference). Latent, not
  live-broken: `_kEnablePhoneEnlist = false` (`lib/features/auth/screens/sign_in_screen.dart:27`)
  makes `signInWithPhone` unreachable, so nothing emits that op_type today.
  What this instance adds to the case: the drift opened and went unnoticed **within one batch,
  between a review round and the commit** — not over seven weeks. So the "release-checklist line
  item" cheap version above would NOT have caught it; the window was hours, not weeks. Recorded
  in `docs/diagnoses/2026-08-06-preauth-failures-unloggable-b6e4f2.md` tier 6.
  ⚠ Note on how it was found: the first diff read the payload with Python's `open()`, which
  defaults to cp1252 on Windows, producing mojibake that looked like an `emit_payload.js`
  encoding bug. It is not — that script reads `'utf-8'` at both sites (`:123`, `:188`). Decode
  explicitly before concluding anything about deployed bytes.

## OI-94 — `anonKey` is deprecated; production still passes it to `Supabase.initialize`

- **Status**: OPEN
- **Verified**: 2026-08-05 — surfaced by the analyzer immediately after the supabase_flutter
  2.12.4→2.17.1 bump in this batch; the call site was read directly, not inferred.
- **Identified**: 2026-08-05 · `deps-board-equipment` batch (the OI-57 #16 merge)
- **Blocked on**: nothing technical to *start*, but it needs a founder/dashboard step — see below.
- **What it is**: `supabase_flutter` now deprecates `anonKey` in favour of `publishableKey`
  ("anonKey will be removed in a future major version"). The production call site is
  `lib/core/services/supabase_service.dart:51`. Six test call sites carry the same deprecation
  (`password_reset_redirect_flow_test.dart:334`, `ai_proxy_test.dart:40`, `pgvector_test.dart:51`,
  `lt_journey_plan_export.dart:122` + `:127`, `supabase_test_helper.dart:66`).
- **Severity is genuinely low, and saying so precisely matters**: it is `info`-level, the parameter
  still works on the whole 2.x line, and removal lands in 3.x. Nothing is broken today.
- **Why it was NOT folded into the bump that surfaced it**: the migration is not a rename. It
  needs a *different key* issued from the Supabase dashboard (`sb_publishable_…`, not the legacy
  anon JWT), which means `.env` on every dev machine, the CI secret, and the Vercel web build all
  change together — an auth-configuration change with a founder/dashboard dependency. Bundling
  that into a dependency bump would have put a config change to the auth boot path inside a commit
  whose whole verification story is "the client library moved." Recorded with a reason rather than
  done silently or dropped silently.
- **Fix shape**: issue the publishable key in the dashboard → add it alongside the existing var
  (do not swap in place) → switch `AppConstants` + `supabase_service.dart:51` → verify auth boot on
  device AND on web → then retire the old var from `.env`/CI/Vercel. The test call sites can move
  in the same pass.
- **Blast radius estimate**: `account` — it is the auth client's boot credential. Would want the
  ≥account review and an APK + live-web check, exactly like the bump that surfaced it.

## OI-95 — a kill-switch is only reachable in DEBUG builds, so no flag can be reverted without an APK respin

- **Status**: OPEN
- **Verified**: 2026-08-06 — found by the round-2 reviewer of the `deps-board-equipment` batch and
  re-confirmed by direct read, not accepted on the reviewer's word.
- **Identified**: 2026-08-06 · `deps-board-equipment` (the e2d6b8 equipment-exclusions flip)
- **Blocked on**: nothing technical. It needs a PRODUCT decision on *where* an operator switch
  belongs (see below) before any code.
- **What it is**: every `PlanEngineFlags` kill-switch lives in the local, unsynced `configBox`.
  The only in-app writer of any of them is `DevPanelScreen`, and `app_router.dart:336` registers
  `/dev` behind `if (kDebugMode)` — so the whole panel is compiled out of
  `--flavor prod --release`. `grep -rn "RemoteConfig" lib/` finds nothing but
  `sync_service.dart:254`'s comment confirming none exists.
- **Why it matters**: §4.6's feature-flag protocol requires the old path stay "reachable when the
  gate is closed". In a shipped APK it is not reachable — reverting ANY flag requires a code
  change plus a full APK respin and store round-trip. The protocol's rollback promise is
  therefore satisfied in the repo and not on the device, which is the gap that matters.
- **Surfaced by, but NOT specific to, e2d6b8**: the equipment-exclusions flip wired a dev-panel
  toggle (`_toggleEquipmentExclusions`) and its closure entry initially claimed that made the
  kill-switch operable. Round 2 showed that is true only in debug. The same is true of
  `enable_hold_weeks` and every one of the twelve OI-53 flags — this is architectural.
- **Fix shape (needs the product call first)**: the honest options are (a) an `/admin`-gated
  operator screen — `/admin` IS registered unconditionally (`app_router.dart:344+`) and is
  founder-gated by `ADMIN_USER_IDS`, so a flag panel there would be release-reachable without
  exposing plan-engine internals to users; or (b) a genuine server-side remote config, which is
  a much larger piece and would also give staged rollout. (a) is small and closes the immediate
  gap; (b) is the real capability. Do NOT expose kill-switches on a user-facing settings screen.
  ⚠ (a) depends on OI-54 — whether `/admin` is actually reachable for the founder has never been
  confirmed.
- **Accepted risk in the meantime** (recorded as a judgement, not a fact): the flags gated this
  way change plan CONTENT, not crash-safety or data integrity, so respin latency is tolerable.
  That reasoning would NOT hold for a flag guarding auth, payment or sync.
- **Blast radius estimate**: `feature` for (a); `platform` for (b).

## OI-96 — community promotion has TWO mechanisms and the trigger may starve the cron's copy step (P2)

- **Status**: OPEN
- **Blocked on**: a PRODUCT decision — which mechanism owns promotion. The mechanism is understood
  and read from live state; what to DO about it is not a mechanical call.
- **Verified**: 2026-08-07 — both definitions read directly (the trigger from live `pg_proc`, the
  cron from source), and the live counters queried. See the evidence block below.
- **Identified**: 2026-08-07, while closing OI-82 (diagnose `d5b8c2`). Filed rather than fixed
  inside a vote-tally cleanup, per the round-2 plan-review note that the cron/trigger relationship
  "is not established anywhere".
- **Risk class**: two writers, one concept — the SoT class root `CLAUDE.md` §4.1 names as the
  default suspect.
- **What's wrong (read, NOT observed — see the live-state caveat)**: `community_review_queue`'s own
  registry entry says items auto-promote "via the SECURITY DEFINER trigger
  `trg_auto_approve_community` **and** the `promote-community-item` cron (both BYPASSRLS)". They do
  different things and interact badly:
  - **The trigger** (`public.auto_approve_community_item()`, read live from `pg_proc`) fires on an
    approve vote, counts `community_reviews`, and at `approve_count >= 10` sets
    `user_custom_foods.approved = true` / `user_custom_exercises.approved_for_library = true` on the
    SOURCE row. It does NOT copy anything into the public library and does NOT notify.
  - **The cron** (`promote-community-item`) tallies the same votes with the same threshold of 10,
    then for each item over threshold fetches the source row and **`if (source.approved === true)
    continue; // already promoted`** — before the step that copies into `food_database` /
    `exercise_library` and calls `notifySubmitter`.
  Read literally, the trigger always wins: it flips the flag synchronously on the 10th vote, so by
  the time the daily cron runs, every qualifying row is already `approved = true` and is skipped.
  The copy-into-library and submitter-notification steps would then never execute, and no community
  item would ever reach the public library — while both mechanisms report success.
- **⚠ UNPROVEN, and that is stated deliberately**: with **0 approve votes ever cast** the
  interaction has never been exercised, so this is a reading of two definitions, not an observed
  failure. Do not treat it as confirmed until it is reproduced (cast 10 approve votes against one
  item on a branch, then run the cron and check whether a `food_database` row appears).
- **Live state 2026-08-07** (`dedsavbjuwgarrhphgnl`): `community_reviews WHERE vote='approve'` = 0;
  `user_custom_foods WHERE approved` = 0; `user_custom_exercises WHERE approved_for_library` = 0;
  `food_database WHERE source='community'` = 0; `exercise_library WHERE source='community'` = 0.
  The whole surface is dormant, which is why this is P2 and not P0 — it bites the first time the
  feature is genuinely used.
- **Second, separable finding — a traceability gap**: `auto_approve_community_item()` is defined
  **cloud-only**. No migration in `supabase/migrations/` creates it; the only repo references are
  `053`/`090`/`091` ALTERing or REVOKEing something that must already exist, and `092`. Its body is
  recoverable solely by querying `pg_proc`, so a reviewer reading the repo cannot see the threshold,
  the columns it writes, or that it is SECURITY DEFINER. Whatever is decided about the mechanism,
  the definition should be captured in a migration so the repo stops under-describing live schema.
- **Product question to answer first**: should the trigger own promotion (and then the cron's
  copy/notify steps need to stop keying off `approved`), or should the cron own it (and then the
  trigger should not pre-empt the flag)? One mechanism should own the transition; today two claim it.
- **Blast radius estimate**: `platform` — a fix touches an Edge Function and probably a migration
  defining/altering a SECURITY DEFINER function. Note the `security definer` content rule
  (`blast_radius_content_rules_lib.dart`) escalates any `supabase/migrations/**.sql` whose TEXT
  matches `/security\s+definer/i`, comments included — writing that phrase in the migration, even in
  a comment, self-escalates the change to `catastrophic`. Plan for that or phrase around it
  deliberately; do not discover it at push time.

## OI-97 — five PaywallSheet labels fall through to generic copy (P3)

- **Status**: OPEN
- **Blocked on**: nothing — mechanical, but it is copy work, so it wants the Wardroom brand soul
  loaded (§0.3) rather than a mechanical string drop.
- **Verified**: 2026-08-07 — `_featureSubtitle`'s switch read directly against every
  `showPaywallSheet` call site in `lib/`.
- **Identified**: 2026-08-07, while fixing OI-76's paywall half (diagnose `a7e3d1`). OI-76's own
  call site was the worst instance (it passed a snake_case id and rendered
  "progress_photos is a PRO feature"); these five are the residue on call sites that fix did not
  touch, and are recorded so the class is not mistaken for closed.
- **What's wrong**: `paywall_sheet.dart` `_featureSubtitle` switches on display strings and returns
  a feature-specific benefit line, else the default *"Upgrade to PRO and unlock your full
  potential."*. Five labels reach it with no matching `case` and therefore show generic copy on a
  screen whose entire job is to convert: `'PRO'`, `'PRO Upgrade'`,
  `'AI Body Composition Assessment'`, `'Readiness Trends'`, `'AI Weekly Report'`.
  Note `'AI Weekly Report'` is a near-miss — the switch has `case 'Weekly AI Report'`, a word-order
  difference, which is exactly the kind of drift a `default:` arm hides.
- **Why it is P3 and not lower**: no user sees a wrong claim, only a weak one. But the default arm
  silently absorbs typos, so this is also the mechanism by which a future renamed feature loses its
  copy without anything failing.
- **Fix shape**: add the five cases; consider whether the labels should be constants shared with the
  call sites so a rename cannot silently fall through again (the deeper fix, and the only one that
  stays fixed).
- **Blast radius estimate**: `feature` — one widget, copy only.

## OI-141 — retire the notification-preferences snapshot fallback once APK +39 is adopted (P3)

- **Status**: OPEN
- **Blocked on**: APK +39 adoption — a founder release decision, not a code state. Nothing
  technical blocks the removal itself; the code is written and marked.
- **Verified**: 2026-08-26 — filed as the tracked half of OI-98's fix, per §4.6's provision that
  an old path whose roll the founder schedules later is tracked on the board, never left as an
  intention.
- **What survives, and why**: OI-98 moved notification preferences to
  `user_preferences.notification_preferences`. Two pieces of the old path were deliberately KEPT
  so client and server deploys did not have to be ordered:
  1. **Client** — `compileDailySnapshot` (`sync_service.dart:899`) still emits the key into
     `snapshot_json`, but ONLY when the device has a local record (it omits it entirely
     otherwise, which is what stopped a reinstalled device asserting an all-enabled default).
  2. **Server** — `_shared/notification_prefs.ts` reads the column first and falls back to the
     newest snapshot row **only for users the column does not answer for**.
- **Why they must retire TOGETHER**: removing the server fallback alone would strand every user
  still on APK +38 — they would read ABSENT ⇒ SEND, taking honoured users from 2 of 5 to 0 of 5.
  Removing the client emission alone would strand a +39 user whose column write failed. Both are
  marked in code with the same retirement note so neither can be removed without the other being
  noticed.
- **The trigger, stated so it is checkable**: +39 adoption sufficient that the snapshot path is
  dead weight, AND a re-run of the zero-`false`-values query immediately before the removal:
  ```sql
  select count(*) from user_daily_snapshots d, jsonb_each(d.snapshot_json->'notification_preferences') e
  where d.snapshot_json ? 'notification_preferences' and e.value->>'enabled' = 'false';
  ```
  It was **0** when OI-98 shipped, which is what made the cutover lossless. It stops being 0 the
  moment a user on +38 turns something off, and at that point the fallback is carrying real data
  and must not be dropped without reading it first.
- **What to remove when it fires**: the client emission + `emissionMap()`'s padding + the
  `pushSnapshot()` call in `NotificationPrefsRepository.write` that exists only to feed it; the
  server fallback block; the `legacy_fallback:` stanza in `docs/sot_registry.yaml`; and the
  `notification_preferences` entry under `extra_server_written_keys:` in
  `docs/snapshot_contract.yaml`. ⚠ `emissionMap()`'s removal retires the sole send-side pin on
  **OI-76/a7e3d1** (PRO-locked keys must never be scoped out of what is sent) — re-express that
  against the column writer rather than deleting it.
- **Blast radius estimate**: `platform` — `_shared/**` plus `lib/core/services/sync/**`.

## OI-111 — the stale-`userId` sink guard covers the nutrition fan-out only; ~26 sibling sinks share the shape

- **Status**: OPEN
- **Blocked on**: nothing — this is bounded work, not a decision
- **Verified**: 2026-08-07 (grep below run against `post38-auth-fixes`)
- **Filed by**: round-1 review of `post38-auth-fixes`, which caught that the e5c2d1 diagnose-doc
  claimed this OI had already been filed when it had not. Filing it for real is the fix for that
  claim — a scope statement closed against a tracker entry that does not exist is a deferral to
  nowhere (`feedback_spawn_task_chip_not_durable`).
- **What e5c2d1 actually fixed**: `SyncService.ownerChangedSince(ownerId)` is now checked at the
  WRITE SINK in `sync_nutrition.dart` — all four of that file's sinks (`nutrition_logs`,
  `nutrition_log_items`, `water_logs`, `user_saved_meals`). The RESTORE half is global, because
  its guard lives in the shared between-step check (`restoreAbortedFor`).
- **What remains**: every other sync fan-out method resolves the owner id once — at its own entry
  or in a caller that passes it down — and then carries it across awaits to a cloud write.
  `grep -rn "'user_id': userId" lib/core/services/sync/` finds the sibling sinks across
  `sync_workout`, `sync_health`, `sync_profile`, `sync_coach` and `sync_community`.
- **Why it matters**: the observed incident was caught by RLS (22 × 42501), which is the LAST
  line of defence, not the intended one. The same race with the opposite interleaving — captured
  id equal to the NEW user while the ROWS came from the previous user's Hive box — satisfies
  `auth.uid() = user_id` and is written, and Postgres cannot distinguish that from a legitimate
  write. So the unguarded sinks are a silent cross-account-write risk, not just a noise source.
- **Fix shape**: mechanical sweep — `if (ownerChangedSince(userId)) return;` immediately before
  each cloud write, plus a case in
  `test/contracts/session_owner_inflight_guard_behavioral_test.dart` per domain. Consider a
  `check_*.dart` gate that flags a `'user_id': userId` sink with no preceding guard within N
  lines, so the sweep cannot silently regress (§4.11 gates-before-refactor).
- **Blast radius estimate**: `platform`.

## OI-109 — ForgotPasswordSheet's two-step code flow has no test

- **Status**: OPEN
- **Blocked on**: nothing — bounded work
- **Verified**: 2026-08-07 (`grep -rln "ForgotPasswordSheet" test/` → no matches)
- **Filed by**: round-1 review of `post38-auth-fixes`. The c9e2b7 diagnose-doc originally
  DESCRIBED two sheet test cases that had never been written; correcting the doc without
  tracking the gap would just move the untruth. Filed so the gap is owed, not implied away.
- **What is covered today**: `test/contracts/password_recovery_code_flow_behavioral_test.dart`
  covers the RESET SCREEN's session gate (2 cases, first mutation-proven).
- **What is NOT covered**: the headline Unit-2 change — `ForgotPasswordSheet`'s step machine
  (email → code), its client-side code validation (`length != 6 || int.tryParse == null`
  rejects before any network call), and its `verifyOTP(type: OtpType.recovery)` call plus the
  `AppRouter.isPasswordRecovery = true` + `router.go('/reset')` sequence on success.
- **Fix shape**: a widget test using the same MockClient + inline `Supabase.initialize` harness
  as `password_reset_redirect_flow_test.dart` (note its `:272-279` comment — init must happen
  INSIDE the testWidgets body, not setUpAll, or a GoTrue timer lands outside the zone `pump()`
  advances). Assert: send success advances the step and shows the target address; a bad code is
  rejected with NO request issued; a good code sets the recovery flag and navigates to `/reset`.
- **Why it matters**: this is the flow a locked-out user depends on, and it is the part of the
  batch with the largest behaviour change (link → typed code). The screen it hands off to is
  tested; the handoff itself is not.
- **Blast radius estimate**: `platform`.

## OI-110 — ~90 diagnose-docs cite a `sot_registry_entry:` concept that does not exist

- **Status**: OPEN
- **Blocked on**: nothing — bounded, mechanical work. Gate 44 already prevents new instances.
- **Verified**: 2026-08-08 (`dart run scripts/check_sot_registry_citations.dart` reports the
  count live on every run; it is not a hand-written snapshot)
- **Identified**: 2026-08-08 · while building Gate 44 during `post38-auth-fixes` slice 0
- **Risk class**: documentation integrity — a citation that resolves to nothing
- **What's wrong**: `scripts/validate_diagnose_doc.dart` — the validator every diagnose-doc must
  pass — contains **zero** references to the SoT registry. It checks the `sot_registry_entry:`
  field is present and non-empty; it has never checked the value RESOLVES. Across 370 tracked
  docs that has accumulated **~90 unresolved identifier-shaped citations across 82 distinct
  names** since 2026-05-03, plus **29** citations written as free prose that no tool can
  adjudicate at all.
- **Why a dangling citation is worse than an absent one**: §4.1's writer/reader discipline sends
  you to the registry to find the contract. Finding nothing reads as "this concept was never
  registered" rather than "this doc named something that does not exist" — so the reader
  concludes the CODE lacks a contract when the real defect is in the doc.
- **What is already done**: Gate 44 (`scripts/check_sot_registry_citations.dart`, pure logic in
  `scripts/sot_citation_lib.dart`, test `test/contracts/sot_registry_citations_test.dart`) hard-
  fails any doc dated >= `2026-08-01` whose citation does not resolve, and reports the older
  backlog as a live WARN count. Scoped by date because a repo-wide hard fail would have been
  unsatisfiable on day one, which is how gates end up bypassed
  (`feedback_mistake_claimed_gate_unsatisfiable.md`).
- **Fix shape**: walk the 82 distinct dangling names. Each resolves to one of three: a registry
  concept that was RENAMED (repoint the citation), a concept that genuinely should exist, or a
  doc where no concept applies (use `not_applicable`).
  ⚠ Adding a concept is NOT cheap any more: **Gate 42 flipped STRICT on 2026-08-07**, so a new
  entry needs a real `behavioral_test_path:` or `presence_only: true` with a documented reason.
  The `behavioral_test_required: true` backlog marker was REMOVED and is now itself a hard
  blocker. An earlier draft of this entry said otherwise — written from a CLAUDE.md read that
  was one day stale. Budget a behavioral test per added concept, not a placeholder.
  Then move `citationCutoff` back and delete the backlog branch —
  the gate graduates to `--strict` by default. Normalising the 29 prose citations to a bare
  identifier or a sentinel closes the gate's remaining blind spot.
- **Blast radius estimate**: `feature` (docs + a constant), though it touches many files.

## OI-113 — the anon telemetry lane's daily budget is a non-atomic count-then-insert

- **Status**: OPEN
- **Blocked on**: nothing
- **Verified**: 2026-08-09 (B-pass on `d4a8de00`, reviewer read the deployed function source)
- **Identified**: 2026-08-09 · raised by the B-pass reviewer as an un-filed caveat rather than a
  finding, because it is not a regression from that commit
- **Risk class**: soft rate limit presented as a hard one
- **What's wrong**: `log-client-error`'s anon lane counts existing rows and then inserts, with no
  DB-side reservation or trigger — unlike this codebase's own ai-proxy reservation pattern. Under
  concurrency the effective ceiling exceeds `ANON_DAILY_RATE_LIMIT = 200`. It is now reachable
  with only the public anon key, which is what makes it worth writing down.
- **Why it is not urgent**: the lane is allow-list-only (six op_types, all `_failed`), is forced
  non-high-priority so it cannot bypass the priority budget, and writes `user_id NULL` rows that
  the authenticated RLS policy still refuses. The exposure is noise volume, not authz.
- **Fix shape**: either a Postgres-side reservation (the ai-proxy pattern) or accept the soft cap
  explicitly and say so in the function header, so nobody later reads 200 as a guarantee.
- **Blast radius estimate**: `platform` (Edge Function + possibly a migration).

## OI-114 — `.claude/deploy_via_api.js` cannot be unit-tested, so its logic is only ever proven by hand

- **Status**: OPEN
- **Blocked on**: nothing
- **Verified**: 2026-08-10 (read the file; confirmed the top-level IIFE and CI's node absence)
- **Identified**: 2026-08-10 · while fixing `a7c3f9` (two defects in this same script)
- **Risk class**: untestable tooling on the production-deploy path
- **What's wrong**: the script ends in a bare top-level `async` IIFE with no `require.main === module`
  guard and no `module.exports`, so importing it *attempts a deploy*. Its pure logic —
  `SMOKE_TOLERATED_CODES`, `provenanceSha`, `isHighPriority`-style helpers — therefore cannot be
  exercised by any automated test. Compounding it, `.github/workflows/test.yml` provisions **deno
  only** (lines 108/125), never node, so even a hand-written JS test would not be gated by CI.
- **Evidence it matters**: `a7c3f9` fixed two defects here that had shipped through at least the v11
  and v12 deploys of `log-client-error` unnoticed. Both were proven by *extracting source text and
  eval-ing it* — a technique that works but tests a copy of the parse, not the module. The
  `log-client-error` Edge Function this tool deploys already solves exactly this, with
  `if (import.meta.main) serve(handler)` plus explicit test exports; the deploy tool never adopted
  the same pattern.
- **Fix shape**: wrap the IIFE in `if (require.main === module)`, add `module.exports` for the pure
  helpers, add a node test, and add a `node --test` step to CI (or port the helpers to Dart so the
  existing `flutter test` gate covers them). Deliberately NOT bundled into `a7c3f9`: changing the
  execution model of the script that had just performed a live production deploy, in the same commit
  that fixes the defects that change would test, is the wrong order — the guard lands first and
  standalone, per §4.11.
- **Blast radius estimate**: `feature` (`.claude/` + `.github/workflows/`), but the *consequence* of
  a defect in this file reaches production deploys.
## OI-99 — Gate 26 has no `docs/` zone, and the destination files OI-91 rewrote into are themselves not immune to dead/wrong `CLAUDE.md §N` citations (P3)

- **Status**: OPEN
- **Blocked on**: nothing technical. Needs its own false-positive analysis before a fix, same
  reason OI-91's code zone didn't reuse the markdown zone's bare-section pattern — prose docs
  likely cite external specs/RFCs differently than code comments do, and that has to be measured,
  not assumed.
- **Verified**: 2026-08-08 — B-pass on branch `oi91-claude-md-citations`, dispatched as part of
  landing OI-91. Found by reading `docs/architecture/ai.md` directly, not by extending the gate.
- **Identified**: 2026-08-08 · B-pass review of branch `oi91-claude-md-citations` (diagnose
  `b2f7a4`).
- **Risk class**: docs-rot / broken agent navigation — same class as OI-91, different zone.
- **What's wrong**: `scripts/check_claude_md_citations.dart`'s two zones (markdown contract files;
  code comments under `lib/ test/ scripts/ supabase/ integration_test/`) both stop short of
  `docs/**`. That is a real gap specifically because OI-91 made it one: 96 of the 138 citations
  that batch rewrote now point INTO `docs/architecture/*.md`, and those destination files carry
  their own `CLAUDE.md §N` citations, un-scanned by either zone. A live instance was found by
  reading, not grepping: `docs/architecture/ai.md:40` cited "CLAUDE.md §6 rule 1" — old §6 was the
  coding rules, current §6 is unrelated (MULTI-TIER COVERAGE PROTOCOL) — the exact "wrong-but-live"
  shape OI-91 spent its effort finding and fixing elsewhere. That specific instance (plus two
  softer ones in `docs/reference/food-database.md` and `docs/reference/directory-structure.md`)
  were fixed on the spot in the same commit as this filing; the STRUCTURAL gap — nothing stops the
  next one from appearing — is what stays open.
- **Fix shape (not attempted)**: extend Gate 26 with a third zone over `docs/architecture/**`,
  `docs/reference/**`, `docs/naming_conventions.md`, `docs/playbook/**`, mirroring the code zone's
  anchored-pattern approach (`CLAUDE\.md.{0,3}§N`, not bare `§N`) — but first measure how many bare
  section tokens exist in that zone and what fraction are false positives, the same survey OI-91
  did for code before committing to the anchored shape. Land report-only per §4.11, baseline, then
  flip to hard-fail.
- **Blast radius estimate**: `feature` (docs-only; no migration, no schema, no application code).

## OI-100 — `prior_art_checked:` needs to reference a VERIFIED artifact, not be free text — §4.1.5 has now been skipped twice, the second time inside the batch built to prevent it (P1)

- **Status**: OPEN
- **Blocked on**: nothing technical. The design below is settled; it needs implementation plus the
  fixture updates it forces.
- **Verified**: 2026-08-11 — round-2 context-blind review of branch `safe-push-verifier`, plus
  direct counts by the main thread (110 records, 42 with `date:`).
- **Identified**: 2026-08-11 · ×2 plan review of `safe-push-verifier`.
- **Risk class**: process-discipline decay — the recurrence class `ci-speedup.closure.yaml` CI-10
  already documents.
- **What's wrong**: CI-10 recorded a full plan → ×2 review → B-pass → implement → merge → red CI →
  revert cycle spent re-deriving an option this repo had measured and rejected 15 days earlier,
  because the §4.1.5 bug-history lookup was never run. The remedy proposed at the time was a
  `prior_art_checked:` field on the plan-review record. **It happened again during the very batch
  that proposed that field**: the dispatched §4.1.5 subagent was stopped and never reported, the
  plan proceeded anyway, and then asserted in writing that the lookup "paid for itself". It had not
  run. That is the point: the CI-10 failure was a **false assertion**, and a free-text field
  receives the same false assertion. As designed it would be, in the reviewer's words, "a habit
  with a checkbox" — strictly weaker than every other field on that gate, since `bpass:` and
  `hermes:` already carry anti-fabrication backing.
- **Fix shape (design settled, not attempted)**: require `prior_art_checked:` to NAME a committed
  artifact that EXISTS at the merge rev — reusing the `refs` mechanism verbatim at
  `scripts/check_plan_review_record_exists.dart:842-866`, which already does exactly this for
  `bpass_review`/`hermes_report` (file must exist at `atRev` AND contain a line-anchored marker).
  A diagnose-doc, a closure-YAML entry, or a committed grep transcript all qualify.
  **Do NOT make the requirement date-conditional** — that was tried in review and is worse than the
  hole: only **42 of 110** existing records carry a `date:` field at all, so the rule needs an
  implicit "no date ⇒ exempt" clause, and any future record then opts out by omitting one line.
  Self-attested dates are also trivially back-dated. Gate the requirement on the merge commit's
  reachability from a marker commit if a cutover is needed at all.
- **Also required by this fix**: the e2e fixtures at
  `test/scripts/plan_review_record_gate_e2e_test.dart:136-145` and `:222-231` build records with
  today's exact field set and will redden; `test/scripts/gate_input_family_e2e_test.dart:601-622`
  asserts on WHICH failure fires first and can break even while the exit code stays 1;
  `test/contracts/review_gate_staged_content_not_working_tree_test.dart:278,298,315` writes review
  artifacts for the same gate. Rule 21 needs a test that FAILS without the new field — updating
  fixtures is the opposite direction.
- **Blast radius estimate**: `platform` (`scripts/check_plan_review_record_exists.dart` is the
  keystone merge gate).

## OI-101 — Gate 41 (`check_test_runtime_budget.dart`) is shipped, dormant, and points at a destination it was never wired to (P2)

- **Status**: OPEN
- **Blocked on**: a founder scope decision — re-arm or retire. Two named options is precisely why
  this could not ship inside `safe-push-verifier`.
- **Verified**: 2026-08-11 — prior-art sweep + round-2 review of `safe-push-verifier`; skip entries
  read directly at `scripts/pre-commit.sh:222` and `.github/workflows/test.yml:224`.
- **Identified**: 2026-08-11 · the sweep that found this batch was rebuilding it.
- **Risk class**: dormant-gate / false-assurance — a closure ledger says a finding is closed by an
  artifact that never runs.
- **What's wrong**: `scripts/check_test_runtime_budget.dart` landed 2026-05-21 (commit `4d912d3`)
  closing audit finding T9, and has **zero invocation sites**: every one of its ~10 references is a
  skip list, an allowlist, a ledger, or a generated index. `docs/audit/2026_05_20_audit_closures.yaml:485-496`
  says it was "intended for /build-apk skill + CI artifact runs" — grep of `.claude/commands/build-apk.md`
  for it returns **nothing**. This is why a later batch proposed building it again from scratch:
  a shipped-but-dormant gate is invisible to anyone searching for whether the capability exists.
- **Fix shape (not attempted; ~10 files, 4 platform-tier — this is why it is its own unit)**:
  - **If RETIRED**: delete the script; remove skip entries at `pre-commit.sh:222` and `test.yml:224`
    (both platform); remove the Gate 33 allowlist entry at `check_gate_scripts_wired.dart:72-73`
    (platform); remove the grandfathered name at `check_gate_test_ledger.dart:110`; **remove
    `docs/audit/gate_test_ledger.yaml:251` or the build HARD-FAILS** — `gate_test_ledger_lib.dart:274`
    errors on "has a ledger entry but no scripts/$gate on disk" (verified); regenerate
    `docs/audit/GATE_INDEX.md`; fix the generator line `audit_test_pyramid.dart:338` that still
    emits the dead name. **Blocker**: retiring deletes the artifact that closed audit finding T9,
    silently reopening it — which §4.2 forbids. T9 must be re-closed by something else first.
  - **If RE-ARMED**: standalone mode runs `flutter test --reporter json` over the whole suite, the
    exact reason it was allow-listed. `--analyze` mode needs a JSON artifact **CI does not produce**
    (`test.yml:112,369,377` all use `--reporter expanded`), so this also edits `test.yml` (platform).
    Its default budget is 30s/test against a suite whose measured p95 is 38.4s and max 149.0s per
    file — arming at default plausibly reddens `main` immediately. §4.11 also mandates a 24h
    `--warn-only` baseline, which a single-push batch cannot satisfy.
- **Blast radius estimate**: `platform`.

## OI-103 — `safe_push.sh` reports OK from a detached HEAD when given an explicit branch argument (P3)

- **Status**: OPEN
- **Blocked on**: nothing; needs its own small analysis, deliberately not bundled into
  `safe-push-verifier` because no fix had been designed and the stated mechanism was wrong.
- **Verified**: 2026-08-11 — round-2 review of `safe-push-verifier` corrected the earlier claim.
- **Identified**: 2026-08-11.
- **Risk class**: landing-verification (`feedback_git_landing_verification.md`).
- **What's wrong**: `safe_push.sh:64` resolves `LOCAL_SHA` from a branch **name**, so from a
  detached HEAD with an explicit branch argument it pushes that branch's (possibly stale) sha,
  ls-remotes the same name, matches, and reports OK — while the commits you are actually sitting on
  are not the ones that landed. **Correction to the earlier framing**: the NO-argument case is
  already safe — `BRANCH` becomes the literal `HEAD`, `git push origin HEAD` fails on an unqualified
  destination, `GIT_EXIT != 0`, and the script exits 1 loudly. Only the explicit-branch-arg form
  has the misleading shape, and that form is arguably *correct* ("push the branch you named, verify
  the branch you named").
- **Fix shape (not attempted)**: probably a WARNING when `HEAD` is detached and an explicit branch
  arg is given, not an abort — aborting would break the documented 2-positional-arg form
  (`safe_push.sh:12-17`) that exists precisely so callers don't fall back to raw, unverified git.
- **Blast radius estimate**: `platform` (`docs/blast_radius.yaml:158`).

## OI-104 — `check_hooks_installed.dart` detects hook PRESENCE, not staleness; installed hooks were 12 days behind their sources (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical.
- **Verified**: 2026-08-11 — `.git/hooks/pre-commit` and `pre-push` both dated `Jul 29 10:28`
  against `scripts/pre-commit.sh` `Aug 10 11:30`; the installed copies were missing the `flutter()`
  env-unset wrapper and the entire gate-index regen block. Fixed for this machine by re-running
  `sh scripts/setup-hooks.sh`; the structural gap stays open.
- **Identified**: 2026-08-11 · ×2 plan review of `safe-push-verifier`.
- **Risk class**: silent-inert-gate — the highest-consequence shape, because everything downstream
  looks green.
- **RECURRED 2026-08-20, and this instance is the strongest evidence yet that presence-checking is
  the wrong invariant.** Fixing `b2e9f4` (pre-push ran a bare `flutter test` while CI excludes
  goldens and pins TZ) meant editing `scripts/pre-push.sh`. The edit was correct, its 3-case
  parity test was green, and all three mutation legs reddened — every signal available said the
  gate was fixed. The push then failed with **the exact same 4 failures as before the fix**,
  because `.git/hooks/pre-push` was a stale `cp` dated `Aug 20 06:56` and contained **0**
  occurrences of `exclude-tags golden`. `check_hooks_installed.dart` was green throughout.
  Two things this adds to the entry above:
  1. **The test suite cannot cover this.** `pre_push_matches_ci_invocation_test.dart` reads
     `scripts/pre-push.sh` — the source — and is right to. No test that reads the source can
     observe that a different file is what actually runs. So the hash check is not a nicety that
     duplicates test coverage; it is the ONLY thing that can catch this class.
  2. **The failure mode is a false NEGATIVE on a fix**, not just a stale gate. The operator sees
     their own fix appear not to work, with no indication why. The natural next move is to
     doubt the fix — or to reach for `--no-verify`, which is precisely what `b2e9f4` existed to
     stop needing.
  Fixed for this machine again by re-running `sh scripts/setup-hooks.sh` (second time in 9 days);
  the structural gap stays open, which is the whole point of this entry.
- **What's wrong**: `scripts/setup-hooks.sh:45` installs by `cp`, not symlink, so `.git/hooks/*`
  drifts from `scripts/*.sh` the moment either changes. `scripts/check_hooks_installed.dart:40`
  checks only `if (!content.contains('scripts/pre-commit.sh') && !content.contains('flutter analyze'))`
  — **any** file containing the string `flutter analyze` passes. So an edit to a hook script is inert
  until someone remembers to re-run the installer, and the gate that exists to catch that says green.
  This is a `feedback_green_check_input_set_width` instance sitting under the whole local gate suite.
- **Fix shape (not attempted)**: compare content, not presence — hash `scripts/<hook>.sh` against
  `.git/hooks/<hook>` and fail on mismatch with the exact re-run command; or install a symlink where
  the platform permits and hash-check only where it does not. Prefer the hash check: it is
  platform-independent and states the real invariant ("the hook that runs IS the hook in git").
- **Blast radius estimate**: `platform`.

## OI-106 — local `flutter test` runs ~3.9x slower per file than CI, cause unknown (P3)

- **Status**: OPEN
- **Blocked on**: a contamination-free measurement on a quiet machine. Every candidate so far has
  died to a measurement artifact.
- **Verified**: never — this is OI-102's unanswered half, carried forward unmeasured on 2026-08-11.
- **Identified**: 2026-08-11 (as OI-102; re-scoped to OI-106 when ADR-0018 removed OI-102's symptom).
- **Risk class**: developer-cycle-time. No correctness risk.
- **What's wrong**: CI runs 690 files in 417s while local ran 478 in 1114.6s — roughly 3.9x slower
  per file locally, at ~4x the parallelism. Nobody knows why. This was the open question underneath
  OI-102; ADR-0018 removed the *pain* (the suite no longer runs per-commit) without explaining the
  *gap*, so it survives on its own. It still costs real time at every pre-push and every CI run.
- **What has ALREADY been ruled out — do not re-derive** (inherited verbatim from OI-102, which was
  closed 2026-08-11; read that entry for the full evidence):
  - *Optimising the slow files*: distribution is flat. Top 10 files = 8.4%, top 200 = 59.7%.
  - *`flutter test` -> `dart test`*: measured ~18% against a >=50% bar set in advance.
  - *`--concurrency`*: UNPROVEN and the obvious measurement is a trap — the apparent 2.1x died to
    the reverse-order control. Alternating j8/j16 is perfectly aliased with an observed period-2
    oscillation; identify the oscillator BEFORE assigning a swing to either arm.
  - *A "37% fixed per-file startup" figure*: wrong — inferred from spans measured under 8-way
    contention, which include queueing.
  - *Diff-conditional test selection*: rejected in `docs/adr/0013-blast-radius-tiered-gating.md:52-67`.
- **Fix shape (measurement first, no predetermined outcome)**: counterbalanced blocks
  (`j8x3, j16x3, j16x3, j8x3`) or randomised order, n>=5 per arm, on a machine with no subagents
  running, reporting the paired distribution.
- **Interaction**: OI-86 (concurrent `flutter test` runs corrupt each other's Hive state) is the
  named hazard for any concurrency increase; 112 contract files use Hive. It is intermittent, so
  "twice consecutively green" does NOT clear it.
- **Blast radius estimate**: `platform` (any fix touches `scripts/pre-push.sh` or `test.yml`).
## OI-107 — `build-apk.md`'s two inline `gh run list` copies should move onto `scripts/gh_run_lib.dart` (P3)

- **Status**: OPEN
- **Blocked on**: nothing technical. It is deliberately sequenced AFTER the new helper has proven
  itself on a low-stakes call site, not blocked by a missing capability.
- **Verified**: 2026-08-12 — both call sites read directly while building the reconciler; the
  helper they would move onto (`scripts/gh_run_lib.dart`) shipped in the same batch and is
  test-covered.
- **Identified**: 2026-08-12 (post-push CI reconciler batch, branch `ci-reconciler`).
- **Risk class**: duplication / release-gate correctness. No live user risk.
- **What's wrong**: the `gh run list --json headSha,conclusion,...` idiom exists twice, inline, in
  `.claude/commands/build-apk.md` — Gate 3.5 (~`:92-123`, hard-aborts an APK build on a red or
  mismatched CI conclusion) and the `--from-green` fast path (~`:357-366`). They are near-identical
  but drift in their flags: `--limit 1` + first-entry vs `--limit 20` + `select(.headSha==...)[0]`.
  Neither sorts explicitly, so both depend on `gh run list`'s **undocumented** default ordering —
  checked against `gh run list --help` and the CLI manual on 2026-08-12: no ordering guarantee is
  stated, and `createdAt` is available precisely so callers can sort themselves. On a **re-run**
  (several runs for one SHA) that is the difference between reading the original red result and the
  newer green one. `scripts/gh_run_lib.dart` now does sort explicitly, and its test supplies the
  rows oldest-first so a naive `.first` reddens.
- **Why it was NOT done in the batch that created the helper**: Gate 3.5 gates every APK release.
  Rewriting the highest-stakes `gh` call site in the repo, in service of a session-start warn-only
  tool, is the wrong order of operations — the helper should earn trust on the call site where a
  mistake costs a spurious warning before it is put on the one where a mistake costs a bad release.
  This is an OI with a terminal state, not a prose deferral (§4.2).
- **Fix shape**: a bash block cannot `import` a Dart library, so this needs a thin CLI wrapper
  (e.g. `dart run scripts/gh_run_query.dart --sha <sha> --branch <b> --workflow "<w>"` emitting one
  JSON line) that both markdown blocks call. Land the wrapper + its test FIRST, verify it returns
  byte-equivalent verdicts against several real historical SHAs (green, red, absent, re-run), and
  only then swap the two call sites — each swap verified against a real build.
- **Blast radius estimate**: `platform` (`.claude/commands/build-apk.md` + a new `scripts/*.dart`).
## OI-108 — `safe_commit.sh` silently accepts a git FLAG as the commit message (P2)

- **Status**: OPEN
- **Blocked on**: nothing. The fix is a few lines; it is filed rather than bundled because it
  belongs to the commit wrapper, not to the batch that tripped over it.
- **Verified**: 2026-08-12 — hit live while committing branch `ci-reconciler`. Reproduced, then
  repaired by `git reset --soft HEAD~1` + recommit.
- **Identified**: 2026-08-12 (post-push CI reconciler batch).
- **Risk class**: silent-wrong-result in a platform-tier wrapper. No data loss (the tree committed
  correctly); the damage is a commit whose message is unusable.
- **What's wrong**: `scripts/safe_commit.sh:27` takes the message as `MSG="${1:-}"` and runs
  `git commit -m "$MSG"` (`:47`). It supports NO git-style flags. Invoking it the way one invokes
  `git commit` — `sh scripts/safe_commit.sh -F /tmp/msg.txt` — produces a commit whose **subject is
  the literal string `-F`**, with the message file silently ignored. Every gate passes, the wrapper
  reports `OK -- HEAD advanced ...`, and the only symptom is the echoed subject, which is easy to
  miss in a long gate log. Observed exactly this on `0b3f2125` before it was redone as `32c145b7`.
- **Why it matters more than a typo**: this wrapper exists BECAUSE "it reported success" and "it
  actually did the right thing" must not diverge (`feedback_git_landing_verification.md`). A commit
  that lands with a garbage message while the wrapper prints OK is that same divergence in a
  different field. It is also a foot-gun aimed squarely at muscle memory: `-m`, `-F`, `--amend` and
  `-a` are all things a person types at `git commit` by reflex, and every one of them would be
  swallowed as message text.
- **Fix shape**: reject a first argument that begins with `-` (a message legitimately starting with
  a dash can still be passed after an explicit `--`), and separately consider supporting `-F <file>`
  properly — multi-paragraph messages via `"$(cat file)"` work but are awkward, which is what
  motivated reaching for `-F` in the first place. Same audit applies to `safe_push.sh` and
  `safe_merge.sh`, which take positional args and would mis-handle a leading-dash argument the same
  way — check all three, not just the one that bit.
- **Blast radius estimate**: `platform` (`scripts/safe_commit.sh` is pinned platform; the hook
  scripts are individually pinned per `docs/blast_radius.yaml`).

## OI-122 — `check_regression_catalog.dart` runs `flutter test` with no concurrency bound, on a machine §4.13 guarantees is shared (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. Needs a measurement before a value is picked — see below.
- **Verified**: 2026-08-13 — read directly at `scripts/check_regression_catalog.dart:56-64`:
  `Process.run('flutter', ['test', ...dartPaths], runInShell: true)`. No concurrency argument.
- **Identified**: 2026-08-13, as the root cause behind diagnose `c3f9a7`.
- **Risk class**: gate credibility. Blocks MERGE commits specifically — the one commit type where
  §4.4 rule 20 forbids bypassing the hook and the reader most needs red to mean red.
- **What's wrong**: the runner self-parallelises at `flutter test`'s CPU-count default. §4.13
  simultaneously mandates one worktree per session, and sessions genuinely run concurrently — three
  were committing at once on 2026-08-13. Neither half is wrong alone; together the suite competes
  with itself and its siblings. Measured symptom: five merge attempts returned 11 / 7 / 8 / 4
  failures on an unchanged tree, all `TimeoutException`, zero assertion failures.
- **Why `c3f9a7` did not fix this**: that raised the three affected files' timeouts — the symptom.
  Bounding the runner is the cause, but it slows EVERY merge commit, so the trade needs a number.
- **What a fix needs first**: measure the catalog's wall-clock at the default vs a bound (2, 4) on a
  quiet machine, counterbalanced — per `feedback_green_check_input_set_width`, a cold/warm ordering
  confound has already killed one measurement in this repo. Only then pick a value.
- **Blast-radius estimate**: `feature` (`scripts/**`), though it is gate machinery, so it wants a
  real review despite the tier.

## OI-117 — a SIGKILLed gate and a violated gate print the same `GATE FAIL` line (P2)

- **Status**: OPEN
- **Blocked on**: nothing.
- **Verified**: 2026-08-13 — observed live. The backgrounded gate invocation is
  `scripts/pre-commit.sh:315` (`if ! dart run "$GATE" >/dev/null 2>&1; then`, inside a subshell
  closed by `) &` at `:318`); bash's async job-control notice printed
  `3950 Killed  dart run "$GATE"` — note it appears despite the `>/dev/null 2>&1` redirect, because
  the notice comes from the shell's job control, not the gate. Immediately followed by
  `[pre-commit] GATE FAIL: check_adr_index_fresh.dart`, and the same for
  `check_app_version_matches_pubspec.dart`. Both gates then **PASSED when run individually**
  (exit 0; "OK: docs/adr/INDEX.md is up to date"; "OK — both at 1.0.0+38").
- **Identified**: 2026-08-13.
- **Risk class**: it spends the no-bypass discipline on evidence that does not exist. §4.4 rule 20
  and `feedback_mistake_no_verify_reflex.md` both forbid bypassing a red gate — correctly. A gate
  that reports failure when it was actually KILLED trains the reader to doubt the next real red.
- **What's wrong**: the hook branches on the gate's non-zero exit code without distinguishing a
  normal non-zero (violation found) from death by signal (128+N, e.g. 137 = SIGKILL). Under memory
  pressure the OS kills a `dart run` and the pipeline reports it as a finding.
- **Fix shape**: detect `exit >= 128` and print a distinct line. "Gate could not be RUN" is a
  different sentence from "gate FAILED", and only the second should block. Third instance in three
  days of the bad-news-vs-no-news class (`d4f9b2`, `a7e3c1`, `c3f9a7`).
- **Blast-radius estimate**: `platform` (`scripts/pre-commit.sh` is pinned).

## OI-120 — the c3f9a7 timeout raise leaves the CI `unit-test` job with ~2 min of headroom (P2)

- **Status**: OPEN
- **Blocked on**: nothing; needs the same measurement OI-116 needs, and should probably be picked
  up with it.
- **Verified**: 2026-08-13 — both numbers read directly, not inferred.
  `.github/workflows/test.yml:93` sets `timeout-minutes: 20` on the `unit-test` job, and `:112`
  runs `flutter test test/ --exclude-tags golden --reporter expanded` — the FULL suite, unfiltered.
  `test/contracts/git_safety_hook_integration_test.dart` now declares 9 tests × 2 min. Tests within
  one file run **sequentially** (no `test.parallel` in the file), so that file's worst-case timeout
  exposure went from 8×30s + 1×60s = **5 min** to **18 min**.
- **Identified**: 2026-08-13, by the B-pass on `supabase-test-http`. Missed by the author, who
  checked the local gate (OI-116) and not CI.
- **Risk class**: signal quality, and it is the same trade `c3f9a7` was meant to improve. This does
  NOT invalidate the raise — the historical evidence (≈30 failures, 100% `TimeoutException`, 0
  assertion failures) is solid, and no current test has a code path where waiting longer changes
  the RESULT rather than the duration (all 21 test bodies read; none has retry or fallback logic).
  The exposure is forward-looking: if a FUTURE regression genuinely hangs this file, the signal
  degrades from "9 named TimeoutExceptions in ~5 min, attributable to one file" to "the whole
  `unit-test` job timed out at 20 min", which names nothing. That is strictly worse, and it is
  precisely the conflation OI-117 and `c3f9a7` exist to fight.
- **Why it is separate from OI-116**: OI-116 is scoped to the LOCAL `check_regression_catalog.dart`
  path. This is the CI job budget. Different runner, different limit, different fix.
- **Fix shape**: options are (a) raise `unit-test`'s `timeout-minutes`, (b) bound test concurrency
  so per-file wall-clock stops being the binding constraint, (c) lower the per-test timeout once
  OI-116's root cause is fixed and the generous value is no longer load-bearing. (c) is the honest
  end state — the 2-minute value exists to absorb contention, not because any test needs 2 minutes.
- **Blast-radius estimate**: `platform` (`.github/workflows/test.yml`).

## OI-119 — `git_safety_hook.dart` matches command TEXT, so it blocks commands that merely mention a banned form (P3) — and, newly evidenced, MISSES 13 executable spellings

- **Status**: OPEN
- **Blocked on**: nothing, but it needs a false-positive analysis before a fix — the hook is
  load-bearing and over-narrowing it would reopen the raw-push hole it exists to close.
- **⚠ BOTH DIRECTIONS ARE NOW MEASURED (2026-08-17, review round 2 of `cycle-time-and-board-gaps`).**
  This entry was filed about false POSITIVES. The false-NEGATIVE half was executed against the real
  hook for the first time, and it is the larger number. Each of these is a RAW `git commit` /
  `git push` that the hook ALLOWS (exit 0):
  `(git commit …)` · `{ git commit; }` · `/usr/bin/git …` · `./git …` · `sudo git …` ·
  `nohup git …` · `time git …` · `exec git …` · `eval 'git commit'` · `` OUT=`git commit` `` ·
  `OUT=$(git commit)` · `echo x | xargs git commit` · `git --git-dir=… commit` ·
  `cd /tmp & git commit` (a single `&` is not in the separator set) · a bare `\r` separator.
  The `--no-verify` deny still fires in all of them (its match is unanchored), so the
  skip-hooks control is intact; what leaks is the use-the-wrapper control.
  **NOT introduced by that batch, and NOT made worse by it** — `stripCommandPrefixes`, added there,
  is a net gain in this exact direction (`FOO=1 git commit` and `FOO=1 git push` went ALLOW → BLOCK).
  Recorded here rather than fixed there because closing them means touching the deny path, whose
  one intolerable failure mode is a false BLOCK, and that is precisely the analysis this entry is
  already blocked on. Do the two directions together or not at all.
- **Sibling gap, same review**: `commandUsesWrapper` (`git_safety_lib.dart`) matches a path
  **suffix** and is command-WIDE, so `sh /tmp/evil_safe_commit.sh && git commit -m x`,
  `mysafe_commit.sh && git commit -m x`, and `sh scripts/safe_commit.sh "m" || git commit -m m`
  all read as "went through the wrapper". Also strictly tighter than the pre-batch
  `command.contains(basename)` it replaced, so again not a regression. Fix shape: require an exact
  basename AND pair the allow with the statement that carries the raw git, the same
  same-statement discipline `inlineEnvAssignment` now uses (diagnose `c8b3e6`).
- **Reproduction harness exists** — drive the hook by feeding
  `{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"…"}}` on stdin;
  exit 2 = blocked, 0 = allowed. ⚠ Put the cases in a FILE: the hook matches command TEXT, so a
  matrix written inline on a Bash command line blocks the harness itself. Always include a control
  that must block, or the whole matrix can be measuring nothing.
- **Verified**: 2026-08-13. ⚠ **The two detectors are NOT equally leaky, and the original filing
  conflated them** — corrected by the B-pass, which reproduced the real one involuntarily while
  reviewing this entry:
  1. **CONFIRMED, and it is the leaky one.** `scripts/git_safety_lib.dart:32-33`'s
     `commandHasNoVerifyFlag` is a fully **unanchored** `RegExp(r'--no-verify\b')` over the whole
     command string. So writing this OI entry was blocked (the prose contains the flag name), and
     so was the reviewer's read-only `grep -n -- "--no-verify" docs/audit/open_issues.md` — a grep
     with no `git` in it at all.
  2. **DOES NOT REPRODUCE as originally described.** I filed a claim that a `grep` for the text
     `git`+`commit` tripped the hook. `commandInvokesGitSubcommand` (`:18-27`) splits on statements
     and anchors on `^git`, so a bare `grep "git commit"` does not match it. My original block was
     almost certainly clause 1 firing on a different part of that same command; I attributed it to
     the wrong detector without checking.
- **Identified**: 2026-08-13.
- **Risk class**: friction that manufactures workaround pressure. A hook firing on mentions makes
  routine diagnosis (grepping logs, process lists, writing docs) fail in a way whose obvious escape
  is the documented bypass env var — training the exact reflex the hook exists to prevent.
- **What's wrong**: substring matching cannot distinguish "invoke X" from "mention X". Note the
  second instance defeats the obvious cheap fix of "ignore matches inside a `grep` argument" — that
  one was a heredoc writing a Markdown file.
- **Fix shape**: **split it — the two detectors need different treatment.** `commandHasNoVerifyFlag`
  is the leaky one and is tightenable at low risk (require the flag to be an actual argument token
  rather than any substring); `commandInvokesGitSubcommand` is already anchored per statement and
  should be left alone, since loosening OR tightening it risks reopening the raw-push hole the hook
  exists to close. Parsing shell properly is out of scope. Any change MUST keep the raw-push and
  raw-commit detections intact — verify against
  `test/contracts/git_safety_hook_integration_test.dart`, which covers those paths.
- **Blast-radius estimate**: `platform` (hook script).

## OI-123 — the test-suite UPSERT path is guarded only transitively, by file ordering (P2)

- **Status**: OPEN
- **Blocked on**: nothing — scoped and understood; needs the same treatment the delete
  path got in `acffbd43`, applied to the write path.
- **Verified**: 2026-08-15 — Hermes lens (destructive-op safety) on branch
  `supabase-creds-test6`, reproduced by direct read.
  `grep -rn "\.upsert(" test/supabase/ test/edge_functions/` → 12 hits, **none**
  preceded by a guard call.
- **Identified**: 2026-08-15, during the test6 credential repoint (diagnose `d3b8f1`).
- **Risk class**: production data overwrite. NOT data loss — RLS bounds every write to the
  signed-in user's own rows (live `pg_policies`: all 12 tables `auth.uid()`-qualified, none
  granted to `anon`), so the ceiling is "corrupt the configured test account", not "reach a
  third party".
- **What's wrong**: `acffbd43` put `assertDisposableTarget` in front of all three DELETE
  sites and (in `7d2582f1`) in front of `ai_proxy_test`'s write path. It did **not** guard
  `SupabaseTestHelper.insertRow` / `upsertRow`, nor the direct upserts in
  `test/supabase/auth_restore_test.dart:51` (`from('users').upsert(...)`). Those are safe
  **today** only because `cleanup()` is the first statement of `setUp` in every file that
  upserts, and it throws first. That is a property of the current file ordering, not of the
  write path. A new `test/supabase/` file that upserts without a `cleanup()` in its `setUp`
  has no boundary at all, and nothing would flag it.
  ⚠ `users` is **not** in `cleanupTables`, so `auth_restore_test.dart:51`'s write to the
  account's `email` / `full_name` / `onboarding_completed` is permanent and never cleaned.
- **Fix shape (not attempted)**: route `insertRow` / `upsertRow` through
  `assertDisposableTarget` the way `cleanup()` is, and add the same call to the direct
  upsert sites — OR, better, make the guard structural rather than per-callsite so a new
  file cannot silently opt out. A contract test asserting "every `.upsert(`/`.insert(` in
  `test/supabase/` is preceded by a guard" would catch the class rather than the instances.
- **Blast-radius estimate**: `feature` (test infrastructure only).

## OI-124 — the device delete-account test hard-deletes `auth.users` with NO allow-list (P1)

- **Status**: OPEN
- **Blocked on**: nothing technical. It is currently `skip: true` with its body commented
  out, so there is no live exposure — the decision needed is whether to guard it before it
  is ever un-skipped, or delete it.
- **Verified**: 2026-08-15 — Hermes lens (destructive-op safety), read directly at
  `integration_test/device/delete_account_patrol_test.dart:40-75`.
- **Identified**: 2026-08-15, during the test6 credential repoint (diagnose `f7a2c4`).
- **Risk class**: irreversible account destruction. Strictly worse than the `cleanup()`
  class OI-115 covered: that deletes ROWS for a user, this deletes the USER.
- **What's wrong**: the batch that closed OI-115 established a thesis —
  *"environment-driven credentials are safe because the delete boundary is keyed on a uuid
  allow-list"*. **That thesis does not extend to this file.** It reaches the DPDP
  delete-account flow, which hard-deletes from `auth.users`, and
  `integration_test/helpers/auth_helper.dart` gates on credential **presence**
  (`kTestCredentialsPresent`), never on **identity** — there is no `qaUserIds` equivalent
  anywhere on the device surface. Whoever un-skips this test inherits an unguarded
  irreversible delete against whatever account `SUPABASE_TEST_EMAIL` names.
- **Fix shape (not attempted)**: before un-skipping, assert the signed-in uuid is in
  `SupabaseTestHelper.qaUserIds` (or a device-side equivalent) and fail closed otherwise.
  Deleting the test outright is also a legitimate terminal answer — it has never run.
- **Blast-radius estimate**: `account` if un-skipped as-is; `feature` for adding the guard.

## OI-125 — Selectable past hold weeks (FOB-6) — 6 named lifecycle traps

- **Status**: OPEN
- **Verified**: 2026-08-13 — filed from `docs/ship_dark_pending_review.yaml` FOB-6, whose trap list
  was produced by a live walkthrough plus two independent context-blind reviews on 2026-07-25. The
  traps themselves have NOT been re-verified against current source since then.
- ⚠ **Renumbered 2026-08-16 (was OI-106).** Filed on branch `claude/open-issues-triage-976962` while `main` independently advanced to OI-124, so OI-106 collided with a different, unrelated issue already on the board. Commit `0e4d97cd`'s message still cites the OLD number — it was pushed before the collision was found and is not rewritten. Mapping: 106→125, 107→126, 108→127.
- **Identified**: 2026-08-13 · split out of OI-60 by founder decision when OI-60 was broken into 7
  pieces (round-1 review returned NOT CONVERGED with structural redesigns in four items).
- **Blocked on**: none technically — but it is a NEW FEATURE, not a correctness fix, and it is the
  only FOB item of that kind. Sequence it after the remaining correctness pieces (FOB-1, FOB-3/4,
  FOB-5, FOB-7a/b) so the flip-on is not gated on feature work.
- **What's missing**: during a hold the THIS WEEK rows show the phase's ORIGINAL week 4 while the
  user trains the hold week, and both the W4 chip and the current H chip render gold. Six traps,
  verbatim from the ledger: (a) extracting the row→WorkoutDayData mapping depends on loop var `w`
  for dayNumber, so the refactor runs for EVERY user and is NOT hold-gated — it needs a
  characterization test before extraction; (b) a notifier watching `holdStatusProvider` is reset by
  every `currentPlanProvider` invalidation, clobbering manual selection; (c) needs the
  `authUserIdTokenProvider` cross-account guard every sibling Train provider carries; (d) the hero
  card sources TODAY unconditionally, so selecting a past hold shows today's workout above another
  hold's rows; (e) `expandedDayProvider` must collapse on selection or a stale index carries over;
  (f) terminal states (hold elapses, PRO advance empties holds) are undefined.
- ⚠ **Hold chips must NEVER drive `selectedWeekProvider`** — hold rows are stamped `week = 4 + ordinal`
  but `CurrentPlanData.weeks` stops at the phase's 4, so `getWeek(5)` is empty and selecting it
  renders "Week 5 hasn't started yet" over a week the user is training
  (`lib/features/train/CLAUDE.md`, `hold_display_read_path`).

## OI-126 — The `logged` / `custom_template` training-day predicate split (5 call sites)

- **Status**: OPEN
- **Verified**: 2026-08-13 — the 5 call sites and the two predicate shapes were read directly while
  fixing a3f8d1; `type: 'logged'`'s two writers were confirmed by grep.
- ⚠ **Renumbered 2026-08-16 (was OI-107).** Filed on branch `claude/open-issues-triage-976962` while `main` independently advanced to OI-124, so OI-107 collided with a different, unrelated issue already on the board. Commit `0e4d97cd`'s message still cites the OLD number — it was pushed before the collision was found and is not rewritten. Mapping: 106→125, 107→126, 108→127.
- **Identified**: 2026-08-13 · surfaced by round-1 review of the a3f8d1 batch
- **Blocked on**: none. Pickable, but it is a live behaviour change for all users, so it needs its
  own review — which is exactly why it was not bundled into a3f8d1.
- **What's missing**: the repo holds TWO shapes of one rule. The EXCLUSION shape
  (`type != 'rest' && type != 'off'`) now lives in `isTrainingDayType`
  (`lib/core/utils/phase_completion.dart`) and is used by the weekly-streak reckoning and
  `holdWeekSessionProgress`. The INCLUSION shape (`type != 'workout' && type != 'custom_template'`)
  is inlined at 5 sites: `train_provider.dart:507`, `:683`,
  `workout_schedule_read_service.dart:1016` (`currentPhaseCompletionRate`),
  `home_screen.dart:589`, `:764`. The two DISAGREE about `type: 'logged'` — written by
  `WorkoutWriteService.markCompleted`'s no-prior-schedule branch (AI-coach-only logging) and by the
  restore synthesize path in `sync/sync_workout.dart`, whose own comment states a logged row
  "counts as a workout day in the streak walk". So a coach-logged or cloud-restored day currently
  counts as a training day for the streak but as a REST day for phase completion, the home rest-day
  banner, and the PRO-advance gate input.
- **Why it was not fixed in a3f8d1**: `currentPhaseCompletionRate` feeds the PRO phase-advance gate.
  Widening it changes who can advance, for every user, with no kill-switch — a materially different
  risk class from the flag-dark streak fix, and it deserves its own blast-radius call rather than
  riding along.
- ⚠ Note `phase_completion.dart`'s existing doc comment describing the inclusion rule is CORRECT for
  its own function — do not "fix" it to match the exclusion helper. A round-2 review claimed it was
  wrong; round 3 showed both of `phaseCompletionRate`'s callers really do compute the inclusion form.

## OI-127 — `plan_start` moving under a live hold week: is the streak identity still sound?

- **Status**: OPEN
- **Verified**: 2026-08-13 — the four `plan_start` write sites were enumerated by grep and are fact.
  The BEHAVIOUR when one fires mid-hold is explicitly NOT verified — that is the whole question.
- ⚠ **Renumbered 2026-08-16 (was OI-108).** Filed on branch `claude/open-issues-triage-976962` while `main` independently advanced to OI-124, so OI-108 collided with a different, unrelated issue already on the board. Commit `0e4d97cd`'s message still cites the OLD number — it was pushed before the collision was found and is not rewritten. Mapping: 106→125, 107→126, 108→127.
- **Identified**: 2026-08-13 · §4.12.1 split out of the a3f8d1 batch after three review rounds
- **Blocked on**: none. Route to the piece that already owns `plan_integrity_reconciler.dart`
  (the FOB-7a/7b piece) so one batch holds the reconciler context.
- **What's missing**: the hold-week streak identity is `(normalizeToMonday(workoutDate) − plan_start)`
  in whole weeks + 1, computed at COMPLETION time from the then-current `plan_start`. It is ≥ 5 at
  materialization. Whether that survives `plan_start` moving mid-hold is unresolved. Four write
  sites: `workout_schedule_read_service.dart:188` and `:348`, `sync/sync_workout.dart:1126`,
  `plan_integrity_reconciler.dart:175`. The last two are the concerning pair — both write `reStart`
  from `PlanWindowReanchor.resolve` with **no `existingStart == null` guard**.
- ⚠ **READ THIS BEFORE RE-ANALYSING — three rounds produced three different answers:**
  - R1: "a phase advance sets `plan_start = rollStart + 7`, so the hold drops out of window" —
    right conclusion, wrong mechanism.
  - R2: "false — the advance passes `startDate: DateTime.now()`, the hold survives, identity = 1" —
    **misattributed**: `train_provider.dart:567` is inside `_autoGeneratePlan` (the auto-regenerate
    path), NOT the PRO advance.
  - R3: "the advance passes `nextPhaseStartDate()`, so R1 was right after all" — confirmed by direct
    read: it returns `_normalizeToMonday(max(plan_end + 1, today))`
    (`workout_schedule_read_service.dart:1577`), and during a hold `plan_end` is the hold week's
    Sunday, so `plan_start` becomes `holdMonday + 7` and the hold dates ARE before the window
    (`:833` filters on a strict `isBefore`).
    ⚠ **CITATIONS CORRECTED 2026-08-25** (batch `oi60-client-blockers`, found by that batch's review
    round 1 and re-verified by reading each line). R3's text said `:1446-1458` for
    `nextPhaseStartDate` — that range is `pastPhaseBlocks()`'s legacy 28-day bucketing — and `:803`
    for the `isBefore` filter, which is prose. **Both were labelled "confirmed by direct read" and
    neither was.** They survived three rounds and were copied verbatim into a fourth batch's plan
    before anyone opened the file. `:1577` is the pre-batch line; the `oi60-client-blockers` changes
    push it to `:1615`.
  So the PRO-advance path looks safe. The OPEN question is the two unguarded re-anchor movers, plus
  `_autoGeneratePlan`'s first-generation branch writing `normalizeToMonday(today)` while `is_hold`
  rows survive.
  ⚠ **CITATION CORRECTED 2026-08-25** (same batch): this read `_autoGeneratePlan`'s "first-generation
  branch (`:345-350`)". That range is exercise-category resolution and `_autoGeneratePlan` starts at
  **`train_provider.dart:638`** — a DIFFERENT FILE from the one the surrounding text is citing, which
  is what made the error invisible.
  ⚠ **A fix REFUTED here so it is not re-attempted (round 1, `oi60-client-blockers`, 2026-08-25):**
  guarding the re-anchor with `existingStart == null` would be a P0. `plan_window_reanchor.dart:46-56`
  treats `localStart == null` as the documented FRESH-INSTALL path that seeds a new device's
  `plan_start` at all, so the guard would break every fresh install and first restore. That batch
  instead declined to WIDEN the exposure: `plan_integrity_reconciler.dart`'s re-anchor now fires only
  on `triggers.mayReanchor`, which reduces to exactly the pre-batch condition — identical, NOT
  narrower (an overstated "narrows" claim was struck after review round 2 proved the reduction). Live risk assessed as nil by R3 (the `!=` dedup gate only suppresses a
  second same-week credit, and the pre-fix clamped behaviour was strictly worse), which is why this
  was filed rather than blocking the fix.

## OI-130 — concurrent sessions have no way to see what another is working on, so the same bug gets diagnosed and fixed twice (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical, but the cheap fixes are all partial and the complete ones are
  expensive — see "Why this is hard" before picking one.
- **Verified**: 2026-08-16 — three measured instances, all within ~72 hours, all discovered by
  accident rather than by any mechanism:
  1. **The same bug diagnosed twice, two diagnose-docs.** Subprocess-test timeouts: I filed
     `c3f9a7` (`concept: subprocess_test_timeout_under_suite_parallelism`) while another session
     independently filed `4f2a9e` (`concept: git_hook_env_leak`) for the *same failing files and
     the same symptom*, landing `80abfbd0` + `a90d3732` on main mid-flight. Different root causes,
     same remedy shape (raise the timeouts), colliding edits. I found out at merge time.
  2. **Duplicate OI ids, twice in one day.** `OI-109` and then `OI-115`/`OI-116` were each minted
     on two branches at once. `build_oi_index.dart`'s duplicate detector caught the second pair;
     its own error text already names the pattern — *"the boards MERGED CLEANLY because the
     additions sat in different regions… sweep EVERY branch for the ceiling, not just this one.
     It moves."* This is OI-112's class, recurring.
  3. **A whole investigation duplicated.** 2026-08-16: dispatched a 10-agent workflow to determine
     whether the failing RR-1 test or the redeem-referral EF was wrong. While it ran, another
     session diagnosed it identically and landed the fix (`62b8892c`, branch `rr1-referral-401`).
     Both reached the same conclusion — the test asserted the function's contract against a
     GATEWAY response (`verify_jwt: true` rejects a no-Authorization request before the module
     boots). Cost: ~1.36M subagent tokens for an answer that was already landing.
  Live instance while writing this entry: `git log origin/main..main` showed **2 commits from
  another session, merged into local `main` 55 seconds earlier and not yet pushed**
  (`80d3d4dd` + `147c8ad3`). Nothing surfaced that; it was noticed only because an unrelated
  ahead/behind check was run first.
- **Identified**: 2026-08-16.
- **Risk class**: wasted work, and — more seriously — **divergent records of the same fact**. Two
  diagnose-docs for one bug means a future reader finding one has half the picture. Instance 1 is
  now cross-referenced in both directions by hand, but nothing made that happen except catching it.
- **What's wrong**: `§4.13` mandates one worktree per session and sessions genuinely run in
  parallel (three were committing simultaneously on 2026-08-13). Every coordination signal the repo
  has is **post-hoc**: `git fetch` shows another session's work only once it is pushed, the OI board
  only once an id is committed, `docs/diagnoses/INDEX.md` only after the doc lands. There is no
  *pre*-declaration of intent, so two sessions can spend hours on the same problem and only
  discover it at merge.
- **Why this is hard (read before proposing a fix)**: the obvious remedies are each partial.
  - *A shared "who is working on what" file* — needs writing before the work, which is exactly the
    discipline that decays without a gate (`§4.13` point 6's lesson). And it is itself a
    concurrently-edited file, i.e. the same collision class one level up.
  - *Mint OI ids from `origin/main` after a fetch* — narrows instance 2 only, and does not help at
    all when the other session has not pushed yet (as above, 55 seconds).
  - *A session registry keyed on the worktree name* — `new-worktree.sh` already names every
    session's workspace, and `git worktree list` is readable from any session without a fetch. That
    is the most promising primitive: the data already exists, unpushed, locally. But a worktree slug
    (`supabase-test-http`) says nothing about which *bug* is being worked; instance 1's two sessions
    had unrelated slugs.
  - **No detector was attempted here deliberately.** `docs/audit/oi-mechanism.closure.yaml` D5
    records a staleness detector for a neighbouring problem that was built, ×2-reviewed and
    WITHDRAWN wholesale after three generations of parser scars. Do not re-propose that shape.
- **What a fix must clear to be worth building**: it must (a) surface intent BEFORE the work, not
  after the push, (b) not itself become a concurrently-edited file with the same collision class,
  and (c) not depend on a discipline that decays — i.e. it needs a trigger, not a convention.
- **Blast-radius estimate**: `feature` for a docs/convention change; `platform` if it touches
  `scripts/new-worktree.sh` or a hook.

## OI-131 — the golden tests are excluded from every gate on every platform, so they only ever pass on one machine (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical — but it needs a decision on WHICH of the two real fixes to
  buy, and both cost more than a hook edit. See "The two candidates" below.
- **Verified**: 2026-08-20 — measured while fixing `b2e9f4`, not inferred.
  - CI has always excluded them: `.github/workflows/test.yml:112` runs
    `flutter test test/ --exclude-tags golden`.
  - `scripts/pre-push.sh` used to run them, by accident rather than intent — it ran a bare
    `flutter test`, which includes the tag. On this Linux container that produced 2 hard
    failures (`test/goldens/wardroom/ward_rank_pill_golden_test.dart`, Lt and SD1 collapsed)
    on a commit CI passed cleanly.
  - `b2e9f4` aligned pre-push with CI, which is correct on its own terms and makes the
    exclusion **uniform**: the goldens now run in no automated gate anywhere.
- **What this means concretely**: the wardroom goldens pass only on the machine whose fonts
  rendered the master images — Windows. Every other environment fails them on rasterisation.
  So they are not a regression gate; they are a machine-dependent surprise. A real visual
  regression would reach `main` unnoticed by any gate, and the person who eventually notices
  would be whoever next runs them on the one machine where they work.
- **Why this was filed rather than fixed in `b2e9f4`**: that batch was aligning a hook with CI.
  Making goldens genuinely portable is separate, larger work with its own trade-offs, and
  bundling it would have widened a `platform`-tier hook fix into a test-infrastructure change.
  Stated as a deliberate trade in that diagnose-doc's `impact_analysis`, and tracked here so
  the trade does not decay into an unowned gap — the §4.13-point-6 lesson (a rule with no
  trigger regrows the problem it solved).
- **The two candidates**, neither obviously right:
  1. **Regenerate goldens per platform** and gate them per-runner. Honest, but multiplies the
     master images by the number of platforms and makes every intentional UI change a
     multi-machine chore.
  2. **Run them in ONE pinned container** (a fixed image with fixed fonts) and gate on that,
     ignoring host rendering entirely. One source of truth, but adds a container step to CI
     and makes local golden runs advisory-only by design.
  A third option — delete them — should be considered explicitly rather than by default. They
  are currently paying no rent.
- **What a fix must clear**: whichever candidate wins, the goldens must run in an automated
  gate on every push that can change them, and a failure must be reproducible by anyone
  rather than only by the master image's author.
- **Blast-radius estimate**: `platform` (touches CI config and/or the hooks).

---

## OI-134 — mutation-proving runs in the shared worktree, where §4.13's guarantee does not reach (P2)

- **Status**: OPEN
- **Blocked on**: nothing. Small and self-contained.
- **Verified**: 2026-08-20 — observed live, twice, by two independent reviewers in the same session.

§4.13 makes cross-session file-mixing structurally impossible by giving each session its own
index. Mutation-proving defeats that from a direction the rule does not cover: it deliberately
edits tracked files **in place** and restores them seconds later, so any concurrent reader sees a
tree that matches neither HEAD nor any commit.

Both happened during the FOB-1/FOB-5 Hermes pass:

- The L1 reviewer watched `workout_schedule_write_service.dart:338` change from
  `hold_week_started` to `hold_week_begun`, then saw a second `log()` call appear at `:238`, then
  saw migration `120:101` flip one of its three predicates. It reverted one edit before
  recognising the pattern, then stopped touching the tree and re-verified every finding against
  `git show HEAD:`.
- The L9/L13 reviewer caught the same two mutations and states plainly that had it sampled once
  and reported, it would have filed a **phantom P0 against clean code**.

Both landed on the same framing independently: *a mutation run in the primary worktree while a
reviewer reads it is the §4.13 shared-index problem in a new costume.*

The dispatch was the author's, not the reviewers' — mutation agents and read-only reviewers were
pointed at one tree at the same time.

**Silver lining worth recording:** because the reviewers caught the mutations in flight and
identified them as the author's own, the mutation run was **independently corroborated** rather
than self-attested — a stronger result than rule 24's ledger trust model normally yields. That is
an argument for making this observable on purpose, not for pretending it did not happen.

**Fix shape:** mutation proving runs in a dedicated worktree (`new-worktree.sh mutate-<slug>`),
and the §4.12 review dispatch states which tree it is reading. Cheap. The alternative — a
reviewer that re-verifies every finding against `git show HEAD:` — is what both reviewers were
forced to invent mid-flight, and it should not be an improvisation.



---

## OI-135 — 60 of 125 migration-ledger hashes do not match their files, and nothing recomputes them (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. The fix shape is settled (below); what it needs is a decision on whether to backfill the 60 or grandfather them by name.
- **Verified**: 2026-08-20 — measured, not estimated. Recomputed sha256 for every entry in `backups/applied_migrations.json` against its `supabase/migrations/*.sql` file: **125 entries → 64 match, 60 mismatch, 1 non-hash sentinel (120b, deliberate)**.

`backups/applied_migrations.json` records a `hash` per applied migration. Its documented purpose
is drift auditing — "recompute hashes on drift", per `applied_migrations_parity_test.dart:36`.
**Nothing recomputes them.** `check_applied_migrations_ledger.dart` requires the `hash` KEY to be
present (`_requiredKeys`) and never looks at its value; no other gate reads it. So the field has
been decorative since it was introduced, and has silently drifted on 48% of entries.

**Found by the round-2 review of `claude/oi-pending-hold-weeks-1od97o`**, which correctly flagged
migration 120's hash as stale — I had updated it in one commit and then edited the file again in
the next, invalidating it. That instance is fixed. The finding only became interesting when the
count was checked: 120 was not special, it was the 61st.

**Why it drifts by construction:** the hash tracks the FILE, and migration files legitimately get
edited after they are applied — corrected comments, added rollback blocks, clarified headers. Every
such edit invalidates a hand-maintained hash, and nothing notices. A hash maintained by memory
across a repo this size will always converge on wrong.

**Fix shape:**
1. A gate that recomputes sha256 for every ledger entry naming a real file and fails on mismatch.
   It must skip entries with no file by design (120b's `unverifiable:no-artifact` sentinel) and
   entries hand-applied outside the migration system (119).
2. The 60 existing mismatches get **enumerated by name** as `grandfathered:` in that script — a
   terminal exemption, exactly the precedent `check_gate_test_ledger.dart` set for its 84
   pre-2026-08-10 gates, and explicitly NOT a deferral. Membership by name, not by date.
3. Mutation-prove it per rule 24 and add its `gate_test_ledger.yaml` entry.

**Deliberately NOT bundled into the batch that found it.** Adding a hard-failing gate with 60
pre-existing violations to a merge-blocking step would be a ship-stop for a hygiene problem — the
same error class as the 2026-07-25/26 required-status-checks incident. The one instance that batch
caused is fixed in it; the class is filed here.

---

## OI-136 — Gate 40 validates "closure YAML" without ever parsing it as YAML; 2 files in the repo are invalid and it passes all 32 (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. Needs the same grandfather-or-backfill decision as OI-135 — 2 pre-existing files would redden a strict parse, so a hard flip is a ship-stop until they are fixed or enumerated.
- **Verified**: 2026-08-20 — measured, not inferred. `yaml.safe_load` over every `docs/audit/*closure*.yaml` + `*closures*.yaml`: **2 fail to parse**, while `validate_audit_closure.dart` reports `PASS: 32 closure file(s) validated`.

```
docs/audit/2026_06_11_audit_closures.yaml  -> mapping values are not allowed here
docs/audit/gate-registry.closure.yaml      -> while scanning a double-quoted scalar
```

`scripts/validate_audit_closure.dart` is a **line scanner**. It greps for `terminal_state:` and
the forbidden `deferred:` key and tallies `closed_count:` — all by reading lines, never by loading
the document. So a closure file can be syntactically broken and still be "validated".

**Found twice in two days, both times by accident**, which is the argument for a real parse:
1. The B-pass on `47eaf8318774` found `hermes-fob-remediation.closure.yaml` used `*wip` six times
   with no `&wip` anchor — not valid YAML, Gate 40 green.
2. Writing `oi132-cron-registry.closure.yaml` the very next hour, **the identical anchor mistake
   was made again** and Gate 40 was green again. It was caught only because the author happened to
   run `yaml.safe_load` by hand. Sweeping the rest then turned up the two above.

A gate that cannot detect the mistake its own authors keep making twice in two days is not
enforcing the thing it appears to enforce.

**Why it matters beyond tidiness.** These files are the §4.2 no-deferrals mechanism — the
structural claim is that a non-terminal item BLOCKS the gate. That claim rests on the gate
reading the file correctly. A file that does not parse has never been meaningfully checked, and
its `terminal_state:` values are being counted by string-matching lines that may not mean what
they appear to.

**Fix shape:** load each file with a real YAML parser before the line checks; on a parse error,
fail with the parser's message. The 2 existing failures get fixed (both look mechanical) or
enumerated by name as a terminal exemption, exactly the precedent
`check_gate_test_ledger.dart` set. Then the line checks can keep working on the parsed document
instead of raw text, which also closes the class quietly rather than one anchor at a time.

**Related:** OI-135 (a ledger field nothing recomputes), OI-132 (a gate whose input could not see
the failure it existed to catch). Same family — the check exists, looks green, and is not
checking what its name claims.

---

## OI-137 — the migration-ledger gate checks that `hash:` EXISTS, never that it is a hash; a literal `%s` passed it (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. Same grandfather-or-backfill decision as OI-135 — 60 of 126 entries already carry hashes that match no artifact, so a strict flip is a ship-stop until they are recomputed or enumerated by name.
- **Verified**: 2026-08-20 — reproduced, not inferred. The entry for migration `121` was written with `"hash": "sha256:%s"` — an unsubstituted Python format placeholder. `dart run scripts/check_applied_migrations_ledger.dart` reported PASS. Caught by the B-pass on the same commit, and corrected there to `sha256:ac8c01a26e32…`.

`scripts/check_applied_migrations_ledger.dart:26` is the whole story:

```dart
const _requiredKeys = ['migration', 'applied_at', 'hash', 'applier'];
```

The gate asserts every entry HAS the four keys. It never looks at what is in them. So
`sha256:%s`, `sha256:`, `TODO`, or the empty-ish `sha256:x` all satisfy it identically, and the
field that exists to attest replay fidelity attests nothing.

**Why this one is worth a number rather than a quiet fix.** It is the third instance in two days
of the same shape — a gate green because it checks the presence of a thing rather than the thing
(OI-132: Gate 31's input could not see a fileless migration; OI-136: Gate 40 "validates" YAML it
never parses). And it landed *inside the commit whose own note explains why a meaningless hash on
this entry must not happen*, which is as close to a controlled demonstration as this class gets:
the author knew the failure mode, wrote it down, and still shipped an instance of it past the gate
in the same file.

**Fix shape:** two cheap checks, one strict and one advisory.
1. Shape: `hash:` must match `^sha256:[0-9a-f]{64}$` OR a documented sentinel string (the `120b`
   entry deliberately carries one, because a fileless entry has nothing to hash — see its note).
   That alone would have caught `%s`, and costs nothing.
2. Value: where a `.sql` file exists for the migration, recompute its sha256 and compare. That is
   the OI-135 half and is the one that needs the grandfather decision first, because it reddens 60
   pre-existing entries on day one.

Step 1 is separable and blocks nothing — it is the part worth doing on its own.

**Related:** OI-135 (60 of 126 ledger hashes match nothing, and nothing recomputes them — this is
its mint-time sibling: 135 is about drift, 137 is about a value that was never a hash at all),
OI-136, OI-132.

## OI-138 — `retire_worktree` removes the worktree but leaves the BRANCH, silently burning the slug

- **Status**: OPEN
- **Verified**: 2026-08-25 — read `scripts/retire_worktree.dart:275-282` directly: it calls
  `git worktree remove <path>`, reports RETIRED on exit 0, and never references the branch.
- **Identified**: 2026-08-16, as a "second, smaller gap" inside OI-128. **Split out 2026-08-25**
  when OI-128 closed, rather than being closed with its parent — the parent's fix (the
  regenerable list) does not touch this at all, so closing both on one commit would have recorded
  a fix that was never written.
- **Blocked on**: none. Small, but see the trap below — it is not a one-liner.
- **What's missing**: after a successful `git worktree remove`, delete the branch with
  `git branch -d`. Use `-d`, NEVER `-D`: the safe form refuses an unmerged branch, and that
  refusal is the entire guarantee. The four-leg predicate has already proven the branch merged by
  the time we get here, so `-d` is expected to succeed; if it does not, that is new information
  and the branch must be KEPT and reported, not force-deleted.
- ⚠ **THE TRAP: the worktree slug is NOT the branch name.** Verified live 2026-08-25 —
  `git worktree list` shows `.claude/worktrees/post38-auth-fixes` sitting on branch
  `rescue/post38-auth-inflight`, and three other `rescue/*` branches are in the same shape. A
  delete keyed on the directory slug would either fail to find a ref or, worse, match an
  unrelated branch that happens to share the name. The loop already has the real branch in scope
  (`classifyWorktree` is called with `merged.contains(branch)`), so the fix must use THAT value,
  not `name`.
- **Symptom when it bites**: `sh scripts/new-worktree.sh <same-slug>` fails with "branch already
  exists". The slug is burned and the operator has to `git branch -d <slug>` by hand — which is
  exactly the state OI-128's own workaround note describes.
- **Regression test shape**: extend `test/scripts/retire_worktree_e2e_test.dart` (it already
  builds real linked worktrees). Two cases, and the second is the one that matters: (1) retiring a
  merged worktree deletes its branch and the slug is immediately reusable; (2) a worktree whose
  BRANCH NAME DIFFERS FROM ITS SLUG deletes the branch, not the slug-named ref — construct it the
  way `rescue/*` did, with `git worktree add -b rescue/<x> .claude/worktrees/<x>`.
- **Blast radius estimate**: `platform` — `scripts/retire_worktree*.dart` is individually pinned
  above the `scripts/** → feature` catch-all in `docs/blast_radius.yaml`. Adds a DESTRUCTIVE
  operation (branch deletion) to a tool that currently only removes directories, so it needs the
  mutation-proven treatment its siblings already carry.
- **Related**: OI-128 (parent, CLOSED 2026-08-25 — the regenerable-list half), §4.13 point 6.

## OI-139 — the only tool that DELETES developer work is tiered `feature`; every tool that merely BLOCKS a commit is pinned `platform`

- **Status**: OPEN
- **Verified**: 2026-08-25 — `grep -n retire_worktree docs/blast_radius.yaml` returns NOTHING, and
  `git diff --name-only main...board-hygiene | dart run scripts/blast_radius_from_diff.dart -`
  printed `Blast-radius: feature` for a branch whose only code change is to
  `scripts/retire_worktree_lib.dart`.
- **Identified**: 2026-08-25, while closing OI-128 — surfaced by the tier coming back `feature`
  when both OI-128's own estimate and the closing commit message said `platform`.
- **Blocked on**: FOUNDER. This is a governance decision, not a defect fix: pinning changes the
  REVIEW BURDEN for every future change to these files (≥account ⇒ ×2 plan review + plan-review
  record + B-pass). Deliberately not applied unilaterally inside a hygiene commit, which would
  also have retroactively changed the required review for the very commit adding it.
- **What's missing**: two lines in `docs/blast_radius.yaml`, above the `scripts/** → feature`
  catch-all:
  `- { glob: "scripts/retire_worktree.dart", tier: platform }` and
  `- { glob: "scripts/retire_worktree_lib.dart", tier: platform }`.
- **Why the current tiering is backwards**: `retire_worktree` is the ONLY tool in this repo that
  destroys developer work — it runs `git worktree remove`, and OI-138 proposes adding
  `git branch -d` on top. Its four-leg predicate exists precisely because a wrong answer is
  unrecoverable: on 2026-08-09 five worktrees held 21 uncommitted files while classifying as
  merged, and a merged worktree holding an ignored `secrets/.env` was removed with exit 0 and the
  file was gone. Meanwhile every sibling whose worst failure is a REFUSED COMMIT is pinned
  `platform`: `git_safety_hook.dart`, `git_safety_lib.dart`, `check_commit_from_worktree.dart`,
  `worktree_guard_lib.dart` (`blast_radius.yaml:76-79`). The tiering is inverted with respect to
  blast radius: block-a-commit is recoverable in seconds, delete-a-worktree is not recoverable at
  all.
- **What it cost already**: this exact gap is why the three P0s in `isRegenerableIgnored`
  (none→prefix→basename→exact) each shipped and were caught only by the NEXT round rather than by
  a required review — a `feature`-tier change needs neither a ×2 plan review nor a B-pass.
- **Counter-argument, stated fairly**: §4.13 point 6 makes retirement deliberately NOT a blocking
  gate, and pinning `platform` raises the cost of routine maintenance on a tool that is
  operator-invoked and dry-run by default. The counter to the counter is that tier governs REVIEW
  of changes to the tool, not how often the tool runs.
- **Blast radius estimate**: `platform` — editing `docs/blast_radius.yaml` itself is the
  registry that every other tier decision reads.
- **Related**: OI-128 (CLOSED 2026-08-25, whose own `platform` estimate was wrong and propagated
  into a commit message), OI-138 (adds the branch deletion that makes this sharper), §4.13 point 6.
## OI-140 — nothing detects a duplicate diagnose `bug_id`, though the identical OI-number bug shipped six times and got its own gate

- **Status**: OPEN
- **Verified**: 2026-08-25 — `ls docs/diagnoses/*.md | sed -E 's/.*-([0-9a-f]{6})\.md$/\1/' | sort |
  uniq -c | awk '$1>1'` returned `2 d3b8f1`, a live collision between
  `2026-08-15-cleanup-delete-boundary-keyed-on-uuid-d3b8f1.md` (landed `acffbd43`) and a doc minted
  in the `oi60-client-blockers` batch. Read `scripts/validate_diagnose_doc.dart` directly: it takes
  exactly one path argument and never enumerates the directory, so it cannot see the class at all.
- **Identified**: 2026-08-25, by the B-pass on `2e9503eb`. The colliding doc was renamed to `b9d4c2`
  before merge, so no collision is live — but nothing would have caught it, and nothing would catch
  the next one.
- **Blocked on**: none.
- **What's missing**: `scripts/check_diagnose_id_unique.dart`, mirroring
  `scripts/check_oi_numbering_unique.dart` — wired into `pre-commit.sh` and CI.
- **Why this is worth a gate rather than care**: the repo ALREADY concluded this, for the sibling
  identity space. `check_oi_numbering_unique.dart` exists because OI numbers are minted by
  eyeballing the board's tail and six collisions shipped by 2026-08-16 — one undetected for 3 days
  0h 34m, with its pushed commit message still citing superseded numbers. Diagnose ids are minted
  the same way (a human picks six hex chars), have the same one-number-space-across-two-locations
  problem (`docs/diagnoses/` plus every `closes-diagnose:` trailer in git history), and carry a
  sharper consequence: rule 22 makes `closes-diagnose: <id>` the ONLY machine-readable link between
  a fix commit and its rationale, so a duplicate id makes that link ambiguous **forever**, and git
  history cannot be rewritten to repair it.
- ⚠ **The mint-time half is the tractable half, and the cross-branch half may not be worth it.**
  Within-tree duplicate detection is a directory scan and is trivially correct. Cross-BRANCH
  detection (two sessions minting the same id concurrently) is the part that made
  `check_oi_numbering_unique.dart` hard — it needed a three-point predicate, fails OPEN, and its own
  first live run reported PASS against an empty parse because `Process.runSync` defaults to
  `systemEncoding` and mangled an em-dash. Read that script before writing this one, and consider
  shipping only the within-tree scan rather than re-deriving the three-point machinery.
- **Blast radius estimate**: `platform` — a new `check_*.dart` gate wired into pre-commit and CI.
  Per rule 24 it ships mutation-proven with a `docs/audit/gate_test_ledger.yaml` entry.
- **Related**: OI-112 (the OI-number version, whose mint-time half is closed), rule 22, the
  `id_collision_note:` in `docs/diagnoses/2026-08-25-hold-days-dilute-phase-completion-b9d4c2.md`.

## OI-143 — nothing checks whether a multi-task BATCH is finished; the Stop hook only asks the §5 rows (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. Needs a design call on what "unfinished" means mechanically
  (see "The hard part" below) before a script is worth writing.
- **Verified**: 2026-08-28 — observed live, repeatedly, during the OI-89 equipment-capability batch.
- **Identified**: 2026-08-28 · founder, after the agent ended four consecutive turns mid-batch with
  "continuing with Task N" and then stopping. Founder: *"again you stopped? dont we have a hook or
  something which keeps on checking if work is complete or not?"*
- **Risk class**: process / agent-discipline enforcement
- **What's wrong**: the four wired hook events are `UserPromptSubmit`, `PreToolUse:Skill`,
  `SessionStart` and `Stop`. Three fire BEFORE work. `Stop` fires at turn-end — but
  `scripts/batch_close_hook.dart` only asks the §5 close-out rows (retrospective, skill
  self-evolution, CLAUDE.md, worktree retirement, full-suite scope). **None of them asks the
  question that actually matters mid-batch: "is the work the founder asked for finished?"**
  So the agent can answer all five §5 rows honestly, correctly, and still stop with 6 of 13
  planned tasks unstarted. The hook's own design note says it fires "only when commits have
  landed and are unpushed" — which is exactly the state a HALF-DONE batch is in, and it reads
  that state as an end-of-batch signal rather than a mid-batch one.
- **Why the existing guards do not cover it**: `feedback_autonomous_auto_mode.md` and
  `feedback_no_stop_until_done.md` both cover it in PROSE, and §4.4 rule 23 ("No stopping
  mid-batch") is a stated invariant. This file's own §4.13 point 6 records the governing lesson:
  *"everything with a gate holds, everything on intention decays."* Rule 23 has no gate.
- **The hard part (why this is not a 20-minute script)**: a script would have to know what "the
  work" is. Candidate signals, none free of false positives:
    - an implementation plan under `docs/superpowers/plans/` with unticked `- [ ]` boxes — but
      plans legitimately outlive a single session, and a plan is not always present;
    - a `docs/audit/<batch>.closure.yaml` with non-terminal entries — but Gate 40 already
      hard-fails on those, and the file is written at batch END, not start;
    - TodoWrite state — ephemeral, not readable from a hook.
  A false "you are not done" on a genuinely finished batch is worse than the current silence: it
  would train the agent to dismiss the hook, which is how the §5 rows decayed in the first place.
- **Fix shape (not yet attempted)**: most promising is the plan-file signal, scoped narrowly — if
  a plan file was modified or added in the unpushed range AND still has unticked steps AND the
  session has landed commits against it, emit an advisory (NOT blocking) line naming the next
  unticked step. Advisory because a blocking Stop hook re-triggers Stop, which
  `batch_close_hook.dart` already guards against with `stop_hook_active`.
- **Blast radius estimate**: `platform` (`scripts/**` hook machinery is pinned platform in
  `docs/blast_radius.yaml`); no migration, no schema.

## OI-142 — deploy-artifact commits are unenforced: prod runs Edge Function code whose deploy record exists only in one machine's working tree (P2)

- **Status**: OPEN
- **Verified**: 2026-08-27 — the class was LIVE in the working tree at filing time, not inferred.
  Ten Edge Functions were deployed at `5416431a` (confirmed against prod: `list_edge_functions`
  shows all ten — `streak-guardian` v23, `morning-alert` v32, `expiry-reminder` v19,
  `weekly-recap-ready` v21, `workout-window-closing` v11, `protein-gap-alert` v12, `pr-detection`
  v13, `plateau-alert` v11, `re-engagement` v13, `proactive-coach-promotion` v11 — with
  `updated_at` in that window). Their payload archives were written under
  `backups/edge_function_payloads/`, and the result sat UNCOMMITTED across two subsequent merges
  (`d7930a2a`, `1ea33bb7`) before `300f5563` landed it.
- **Identified**: 2026-08-27, while cross-checking whether OI-98 had actually shipped. Found by
  reading `git status` in the primary worktree, not by any gate.
- **Blocked on**: none.
- **Recurrence — twice in three days**: `6ad1a28e` (2026-08-25) is literally
  *"chore(repo): land the deps-board-equipment close-out that never committed"*. Same class, same
  directory, two days earlier. Neither instance was caught by tooling; both were caught by a human
  reading `git status` for an unrelated reason.
- **What's wrong — and the trap is the near-miss, not the absence**: nothing gates this. The
  obvious candidate is NOT one. `scripts/check_edge_function_payloads.dart` is **Gate 12**, which
  validates that a Flutter caller's payload KEYS are a subset of what the Edge Function reads from
  the request body — a different concern entirely — and it currently returns
  `PASS (no-op) — no edge_function_payloads defined in registry yet`. Its NAME reads as coverage it
  does not provide, which is the more dangerous half: an auditor grepping for a payload gate finds
  one, sees green, and moves on.
- **Why this is more than tidiness**: between deploy and commit, prod runs code whose deploy record
  exists only in one machine's working tree. §6 tier 6 ("Edge Function code vs deploy") is
  unanswerable during that window — the repo cannot say what is live. It also hard-fails
  `/build-apk` **Gate 1** (`git status --porcelain` non-empty, untracked files included), so it
  silently blocks every APK build until somebody notices. That is how this instance surfaced: it
  was standing between the repo and APK +39.
- **What's missing**: an assertion that a deploy's payload archive is committed. The cheapest
  correct place is `deploy_via_api.js` itself — it already writes and prunes the archives at
  `:585-600`, so it is the one process that KNOWS a deploy happened and can refuse to exit clean
  while they are unstaged. A `scripts/check_*.dart` gate is the alternative, but it must answer
  "was there a deploy?" from repo state alone, which is the harder question.
- **Blast radius estimate**: `platform` — `.claude/deploy_via_api.js`, plus (if taken as a gate) a
  new `check_*.dart` shipping mutation-proven with a `docs/audit/gate_test_ledger.yaml` entry per
  rule 24.
- **Related**: OI-140 (same shape — a real class with no detector, filed the same week), §6 tier 6,
  `/build-apk` Gate 1, `GO_LIVE_CHECKLIST.md` row 5.4 (the `+38` size-ledger entry that also sat
  uncommitted — the third instance of this family).

## OI-145 — 34 licence-clean drawings depict bodyweight exercises the library does not have (P3)

- **Status**: OPEN
- **Blocked on**: nothing technical. It needs the per-exercise authoring that OI-89 did for its 33
  rows, and its own spec + review — it must not ride along inside another batch.
- **Verified**: 2026-08-29 — the 302-entry manifest of `github.com/bryllim/workout-guide` was
  matched against all 292 library rows; 68 drawings have no library equivalent, 34 of them in the
  bodyweight family. 30 of the 34 were then probed by name against `exercise_library.json`
  individually and none exists.

- **What it is**: the exercise-plates work (branch `exercise-plates`,
  `docs/plans/exercise-plates-spec.md`) adopts that drawing catalogue under CC BY-SA 4.0. The
  catalogue is larger than our library in exactly the place ours is thinnest. These 34 arrive with
  artwork already licensed and already downloaded — the only cost is authoring the row.
- **Why it matters**: OI-89 established the bodyweight tier as a HARD floor, and its own residual
  records that some bodyweight patterns have a single candidate. Glute isolation at the bodyweight
  tier is the sharpest gap and the catalogue has six for it.
- **The 34, grouped**:
  - glutes, bodyweight: `clamshell`, `fire-hydrant`, `donkey-kick`, `side-lying-hip-abduction`,
    `side-lying-leg-raise`, `hip-airplane`
  - posterior chain: `bird-dog`, `superman`, `superman-hold`, `back-extension`,
    `glute-focused-back-extension`, `lying-hamstring-walkout`
  - knee-dominant: `bodyweight-squat`, `cossack-squat`, `shrimp-squat`, `forward-lunge`,
    `step-down`, `single-leg-calf-raise`
  - core: `hollow-rock`, `heel-tap`, `plank-shoulder-tap`, `seated-knee-tuck`, `squat-thrust`
  - household kit: `chair-dip`, `wall-walk`, `stability-ball-hamstring-curl`
  - conditioning: `skater-hop`, `lateral-shuffle`, `fast-feet`, `sprawl`, `seal-jack`
  - flexibility: `seated-forward-fold-stretch`, `butterfly-stretch`
  - triceps: `weighted-dip`
- **Why it is NOT part of the plates batch**: a new row is not a name and a picture. Each needs
  `coaching_cues`, `common_mistakes`, `breathing_cue`, `movement_pattern`, `equipment_tier`,
  `rep_range`, `priority_tier` and injury tags, or it degrades the generator rather than helping
  it. 34 such rows would make the plates batch un-reviewable. Founder agreed 2026-08-29.
- **Cheap when it happens**: each lands with its `demo_slug` already known, so it gets a plate for
  free on the same `_exerciseLibraryVersion` bump.
- **Related**: OI-89 (the bodyweight floor and its single-candidate residual),
  `docs/plans/exercise-plates-spec.md`.

---

## OI-146 — three duplicate exercise rows, two of them dead, one skewing selection (P2)

- **Status**: OPEN
- **Blocked on**: nothing. Needs a decision on whether the flexibility twins are intentional.
- **Verified**: 2026-08-29 — name-normalised (case, punctuation, word order) across all 292 rows of
  `assets/data/exercise_library.json`, then each name grepped against `lib/` for live references.

- **The three pairs**:

  | dead row | live twin | reference count in `lib/` |
  |---|---|---|
  | E167 `Cross Body Shoulder Stretch` (flexibility) | E219 `Cross-body Shoulder Stretch` (cooldown) | 0 vs **5** |
  | E168 `Doorway Chest Stretch` (flexibility) | E220 `Chest Doorway Stretch` (cooldown) | 0 vs **6** |
  | E016 `Close Grip Bench Press` | E241 `Close-Grip Bench Press` | 0 vs 0 — see below |

- **Why the first two are not symmetric**: `warmup_cooldown.dart` selects cool-downs from
  HARDCODED name lists (`_cooldownStretches`, `warmup_cooldown.dart:142-146`), not from the
  library `category`. Only the `cooldown`-category spelling is named there, so the
  `flexibility`-category twin is unreachable through that path and duplicates a row that is live.
- **Why E016/E241 is the worse one**: both are byte-identical in `category`, `logging_type`,
  `equipment_needed` and `primary_muscles`, and neither is hardcoded anywhere — so BOTH sit in the
  generator's selectable pool. That gives one exercise **double the selection probability** of
  every neighbour in its slot, silently skewing variety. This is a selection-fairness bug, not
  cosmetic.
- **What to check before deleting anything**: whether a plan already generated for a live user
  pins the dead spelling (`schedule_*` rows store the NAME), and whether
  `exlog_*` history keyed on the dead name would orphan. The exlog key is
  `exercise_name.hashCode`, so a rename is NOT free — see `lib/features/train/CLAUDE.md`
  `exercise_logs_read_path`.
- **Found by**: the founder, eyeballing the plate-assignment review — his note on
  Captain's Chair Leg Raise read "this is same as knee raise. duplicate", which prompted the audit.

### WIDENED 2026-08-29 — it is EIGHT pairs, not three

The original audit compared names to names. A second audit, run because the founder said
"there were repetitions again" for the third time, compared them **by the drawing each one
claims** — two library rows fighting over one catalogue drawing is the same duplicate, found
by a different route. That surfaced five more:

| pair | why the name audit missed it |
|---|---|
| E?? `V-Up` / `V-Ups` | plural only — normalised the same, but they are two rows |
| `Hip Abduction Machine` / `Hip Abductor Machine` | one letter |
| `Standing Quad Stretch` / `Quad Stretch` | one is a prefix of the other |
| `Battle Ropes` / `Battle Rope Wave` | different word count |
| `Overhead Tricep Cable Extension` / `Overhead Cable Extension` | one word dropped |

⚠ **The lesson for the next audit is the method, not the count.** Name-normalisation and
drawing-claim-collision find DIFFERENT duplicates, and neither is a superset of the other. Run
both. The claim-collision audit is only possible because the plates work assigns a drawing per
exercise — before that, these five were invisible to any check in the repo.

- **Related**: `docs/plans/exercise-plates-spec.md`, OI-145, and
  `memory/feedback_green_check_input_set_width.md` (the check whose input set was too narrow —
  it compared contested-vs-proposed and never looked at the confirmed tier).

## OI-147 — remove Donkey Calf Raise: a one-row deletion that touches the cloud seed, a live apply, and the frozen generator baseline (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. Needs the plan-generator question answered (below) before the row is removed, and a founder go for the live prod apply.
- **Verified**: 2026-08-29 — every claim below re-derived from the named file in this worktree.

**Founder decision (brainstorm, exercise-plates):** Donkey Calf Raise is *"not feasible generally"*
and should leave the library. It carries no drawing, so it was originally bundled into the
exercise-plates batch, which is where its real cost surfaced.

**Split out of `exercise-plates` on 2026-08-29** after review round 2 returned `not converged`:
three of that round's five blockers came from this one row removal and none of them from the
plates feature. Removing it from that batch dissolved all three. This is a separable unit with its
own blast radius, not a deferral — the plates work never touched any of these surfaces.

**What a one-row deletion actually requires:**

| # | Surface | Why it fires | Evidence |
|---|---|---|---|
| 1 | `test/contracts/exercise_library_schema_contract_test.dart:84-85` | asserts `rows.length == 292` and `ids.toSet().length == 292` | read 2026-08-29; the file has **five** tests, not four |
| 2 | `test/contracts/exercise_library_cloud_seeded_test.dart` | asserts the newest seed migration's tuple count equals the bundled JSON row count | `125_reseed_exercise_library.sql` = **292** tuples, JSON = **292** rows. 291 turns it red |
| 3 | `supabase/migrations/` | that test's own guidance is that a library change **mints the NEXT seed migration** rather than rewriting one | re-mint via `scripts/seed_exercise_library.js` |
| 4 | `backups/applied_migrations.json` | §4.5 — a migration apply pairs with a ledger update in the same commit | |
| 5 | **live prod apply** | §4.3 — needs its own explicit founder go, separate from plan approval | |
| 6 | `test/plan_generator/baseline/baseline_plans.md:235` | the frozen baseline shows the generator **picking this row**: `\| Calves/knee_dominant \| Donkey Calf Raise \| attempt2DropSubFocus \| Calves \| bodyweight \|` | |
| 7 | `test/plan_generator/scorecard_gate_test.dart` | 606-persona matrix with a hard fallback ceiling | |

**⚠ The generator question, which must be answered BEFORE the row goes:**

Donkey Calf Raise is the **only bodyweight-tier calf isolation row in the library**. Verified by
scanning all 292 rows for a calf `primary_muscles` entry:

| row | tiers |
|---|---|
| **Donkey Calf Raise** | `bodyweight`, `home_dumbbells`, `basic_gym`, `full_gym` |
| Standing Calf Raise | `basic_gym`, `full_gym` — **not bodyweight** |
| Seated Calf Raise | `full_gym` only |
| Dumbbell Calf Raise | `home_dumbbells`+ — **not bodyweight** |

The remaining bodyweight `knee_dominant` rows (Baithak, Jump Squat, Broad Jump) are `calisthenics`,
not `isolation`. So removing this row leaves a bodyweight user with **no calf isolation option at
all**, and the `Calves/knee_dominant` slot — already resolving at `attempt2DropSubFocus` — falls
through to `attempt3DropTypeAndTarget`, which the baseline itself flags `⚠`.

`fallback_by_tier.bodyweight` is already 1630 of a 2862 ceiling. One extra fallback pick makes
2863 > 2862 and the suite goes red on `main`.

**This is a prediction from mechanism and citation, NOT a measurement** — the 606-persona matrix
has not been run against a 291-row library. Run it first:
`flutter test test/plan_generator/scorecard_gate_test.dart` against the post-removal JSON.

**Three ways it can end, all terminal:**
1. The matrix does not move → remove the row, fix surfaces 1–5, done.
2. The matrix moves → **add a replacement bodyweight calf isolation row in the same batch**
   (the honest fix — the founder's objection is to this exercise, not to training calves), then
   remove.
3. Re-baseline with the attribution written into the comment, following the precedent at
   `scorecard_gate_test.dart:114-141`. Weakest option; only if 1 and 2 both fail.

**Until then** the row stays in the library and simply shows a monogram in the plates feature
(127 monogram rows instead of 126). Nothing about plates depends on its removal.

## OI-148 — 23 equipment-variant exercises the plate mapping surfaced, blocked on a selection-skew answer (P2)

- **Status**: OPEN
- **Blocked on**: the selection-skew question below. Not on artwork — every one of the 23 already has its drawing identified in `docs/plans/exercise-plates-mapping.json`'s source adjudication.
- **Verified**: 2026-08-29 — each named row checked absent from all 292 rows of `assets/data/exercise_library.json`.

**Split out of `exercise-plates`.** The plate adjudication found the catalogue depicts several
movements we already carry, but **with different equipment** — a dumbbell sumo squat where ours is
bodyweight, a seated dumbbell press where ours is standing. The spec's split rule says: keep our
row exactly as it is (renaming orphans `exlog_*` history, which hashes the exercise NAME) and add a
new row named for the equipment shown, which takes the drawing.

⚠ **The spec attributes these to OI-145. That is the wrong issue.** `open_issues.md` scopes OI-145
to *34 licence-clean drawings depicting bodyweight exercises the library does not have* —
`clamshell`, `fire-hydrant`, `bird-dog` and so on. These 23 are equipment **variants of rows that
already exist**, sharing none of those slugs. Naming a real-but-wrong OI reads as tracked and is
worse than naming none.

Confirmed absent from the library today: `EZ Bar Curl`, `Seated Dumbbell Shoulder Press`,
`Weighted Russian Twist`, `Dumbbell Sumo Squat`.

**⚠ The blocker, which is a product question and not a technical one:** the bodyweight rows are
already tiered into `home_dumbbells` / `basic_gym` / `full_gym`, so a dumbbell user would see
**both** rows of every split pair — the same movement twice in one selection pool, drawing double
the slot probability of its neighbours. That is exactly OI-146's defect, reproduced deliberately 23
times. Answer it before any of these ship.

**Not blocking the plates feature.** `Barbell Curl` keeps its name and its `ez-bar-curl` drawing
(founder, 2026-08-29), so nothing in the shipping 165 depends on this.

## OI-149 — breathing_cue holds a bare number on 136 of 292 rows; the original text is unrecoverable (P2)

- **Status**: OPEN
- **Blocked on**: **the founder** — 136 replacement cues have to be authored, because the original
  text exists nowhere. This is a copy-writing task, not an engineering one.
- **Verified**: 2026-08-29 — counted, and the recovery paths exhausted (below).

**The defect, measured:** exactly **136** of 292 rows match `^\d+(\.\d+)?$` in `breathing_cue`,
and exactly **136** carry a null `met_value`. The intersection is 136 and neither side has a
row the other lacks — a spreadsheet column shift dropped `met_value` into `breathing_cue` and left
its own column empty. `met_value` is read nowhere in `lib/`, so only the breathing copy was lost.

**Both recovery paths were checked and both are dead:**

1. **The cloud seed migrations do not carry the field.** `074_seed_exercise_library.sql` and
   `125_reseed_exercise_library.sql` insert **20 columns**, and `breathing_cue` is not among them —
   `125`'s own header comment lists it under *"JSON-only fields"*.
2. **Git history never had it.** All **19** revisions of `assets/data/exercise_library.json` back to
   2026-04-14 carry `Lateral Raise` with `breathing_cue: "5"`. The shift predates the file's entry
   into the repo, so `git show <rev>:` recovers nothing.

**Shipped state after `exercise-plates`:** BOTH surfaces that render this field now suppress a
numeric value rather than printing "BREATHING / 5" —
`lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart` and
`lib/features/train/screens/active_workout/coaching_content_panel.dart`, pinned together by
`test/contracts/breathing_cue_numeric_suppressed_test.dart`. So the symptom is gone and 136
exercises simply show no BREATHING section.

⚠ **That makes this LESS likely to be noticed, not more** — which is exactly why it is filed rather
than left to the guards. The fix is 136 lines of coaching copy.


## OI-151 — telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and scales to ~240k rows/day at 10k DAU (P3)

- **Status**: OPEN
- **Blocked on**: nothing technical. It is a PRE-LAUNCH tuning decision, not a defect — the
  volume is bounded today and harmless at current scale. It wants a call on what breadcrumb
  granularity is worth paying for once there are real users.
- **Verified**: 2026-08-30 — measured live on `dedsavbjuwgarrhphgnl`, not estimated. Row counts
  are whole-history across all 17 accounts.
- **Identified**: 2026-08-30, during the OI-150 write-durability research (founder asked how many
  cloud writes the app actually makes per day).
- **Risk class**: cost / operational scaling. NOT a correctness issue.

**The measurement.** Every row in the database, all users, ~4 months:

| table | rows | per active day |
|---|---|---|
| `client_errors` | **1905** | **100.3** |
| `scheduled_workouts` | 607 | 28.9 (bursty — 28 rows per plan generation, not a rate) |
| `workout_log_exercises` | 153 | 7.3 |
| `user_daily_snapshots` | 131 | 1.9 |
| `ai_coach_interactions` | 121 | 3.8 |
| `workout_logs` | 41 | 1.5 |
| `weight_logs` | 35 | 1.1 |
| `nutrition_logs` | 32 | 1.5 |
| `water_logs` | 27 | 1.0 |

**1905 telemetry rows vs ~1147 rows of ALL real user data combined.** Actual user-generated
writes are ~5–10 per user per active day — genuinely trivial.

`restore_op_done` alone is **1221 rows = 64% of all telemetry**, at ~24 per user per day
(1221 events / 5 users / 10 active days).

**Why it is bounded today, and where the ceiling actually is.** `restore_op_done` is NOT in
`log-client-error`'s `HIGH_PRIORITY_OP_TYPES` bypass list, so it shares the
`DAILY_RATE_LIMIT = 2000` events/user/24h budget (raised 100 → 2000 in APK Test #16.1 / Theme D).
At 24/user/day we sit at ~1.2% of cap. So this is not a runaway.

⚠ **The scaling arithmetic, which is the actual point:** 24/user/day × 10,000 DAU =
**~240,000 rows/day ≈ 7.2M/month** of observability exhaust. The 2000/user/day cap would permit
20M/day. Neither number is a crisis; both are worth choosing deliberately rather than inheriting.

**Fix shape (not attempted, and deliberately not bundled into the OI-150 batch):** decide a
breadcrumb granularity — e.g. `restore_op_done` becomes one summary row per restore rather than
one per operation, or moves to a sampled lane. Any change must keep the ops that a real incident
needs; `feedback_backend_collapse_blinds_telemetry` records that a telemetry GAP during an
incident is itself a signal, so thinning this is not free.

**Blast-radius estimate**: `account` (touches `log-client-error` + the client emitter).

**Related:** §2.13 (telemetry sink silently drops past rate limit, `9d12af`), diagnose `c4f8d2`
(the un-debounced fan-out that made this lane hot), OI-150 (the batch that surfaced it).

## OI-152 — six-plus call sites fire `syncX()` and `pushSnapshot()` back to back, doubling round-trips per user action (P3)

- **Status**: OPEN
- **Blocked on**: nothing technical. Bounded, mechanical work. Filed rather than bundled into the
  OI-150 batch because that batch is a correctness fix to the sync/restore seam and this is a
  round-trip optimisation — mixing them would widen a `platform`-tier diff for no correctness gain.
- **Verified**: 2026-08-30 — every call site below read directly in the worktree, full grep, not
  sampled.
- **Identified**: 2026-08-30, during the OI-150 write-durability research.
- **Risk class**: efficiency. NOT a correctness issue — both calls succeed today.

**The pattern.** A user action writes to Hive, then fires TWO fire-and-forget cloud calls in
succession, where the second is derived from the same data the first just pushed:

| file:line | the pair |
|---|---|
| `lib/features/train/repositories/workout_repository.dart:1589-1590` | `syncWorkoutData()` + `pushSnapshot()` |
| `lib/features/train/providers/train_provider.dart:2176-2177` | `syncWorkoutData()` + `pushSnapshot()` |
| `lib/features/home/widgets/swap_sheet.dart:143-144` | `syncWorkoutData()` + `pushSnapshot()` |
| `lib/features/train/screens/template_builder_screen.dart:448,460` | `pushSnapshot()` + `syncWorkoutData()` |
| `lib/features/nutrition/providers/nutrition_provider.dart:1313-1314` | `syncCustomItemsNow()` + `pushSnapshot()` |
| `lib/features/profile/screens/edit_profile_screen.dart:1816-1817` | `syncProfileNow()` + `pushSnapshot()` |
| `lib/features/profile/screens/edit_profile_screen.dart:2006-2008` | `syncProfileNow()` + `pushSnapshot()` |
| `lib/features/train/widgets/create_custom_exercise_sheet.dart:92-93` | `syncCustomItemsNow()` + `pushSnapshot()` |

**Why the existing coalescer does not already cover it.** `SyncCoalescer` (Unit H, `c4f8d2`)
de-duplicates repeated calls to the SAME fan-out entry point. These are two DIFFERENT entry
points fired once each, so both pass through. The snapshot debounce (H1b Part B1, `e7c1a9`)
delays the second but does not merge it.

⚠ **Do NOT "fix" this by deleting the `pushSnapshot()` calls.** The snapshot is the AI coach's
context payload and the source for reports/alerts; `sync_service.dart:830` calls the next-login
snapshot push a durability backstop that "MUST be durable". The fix shape is to let the snapshot
be derived from the sync that just ran (one round-trip), not to drop it.

**Blast-radius estimate**: `account` — 8 call sites across train/nutrition/profile, no schema
change.

**Related:** diagnose `c4f8d2` (SyncCoalescer), `e7c1a9` (pushSnapshot debounce), OI-150.

---

## OI-153 — PRO media caps read a `channel` value nothing writes (P1)

- **Status**: OPEN
- **Blocked on**: enumerate every `channel` reader first
- **Verified**: 2026-09-03 — source + live prod
- **What**: tech-debt audit 2026-09-02 findings CODE-1, CODE-2, CODE-3, CODE-4 (Slice B). The PRO
  50/day image cap counts `channel IN ('pro_image_analysis','image_analysis')`
  (`ai-media-proxy/index.ts:98`) but the only insert writes `'free_image_analysis'` or `'app'`
  (`:663-666`). `pro_image_analysis` appears **once** in the repo — that read. Live prod
  `ai_coach_interactions` holds **0** rows on either counted channel, so the cap has never fired.
  CODE-2: PRO+video matches neither `:433` (`isVideo && !isPro`) nor `:504` (`!isVideo && isPro`) —
  the most expensive request type is uncapped.
- **Why it is not a one-line fix**: stamping `pro_image_analysis` drops those rows out of two
  allowlists outside `supabase/functions/` — `coach_interaction_repository.dart:282`
  (`_coachChatChannels`, filters the coach's replayed history) and
  `migrations/120_...sql:125` (`founder_metrics_engagement()`, live). Three review passes each
  found readers the previous one missed, so **the enumeration must be run to empty before design**.
  Changing the read to count `'app'` is REJECTED — `'app'` is shared with ai-proxy text chat.
- **Also**: CODE-1/CODE-2 share one ternary at `:663-665`; `"image_analysis"` is a second dead
  channel with no disposition; updating `founder_metrics_engagement()` needs a migration that may
  collide with the in-flight backend-CPU-starvation batch (migration 120).
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §11 Slice B.

### Folded in 2026-09-03 from OI-162 — the FREE-IMAGE LIFETIME QUOTA resets itself

A third instance of the counter-in-a-summarized-table class, split out of OI-162 because its storage
semantics are the OPPOSITE of a windowed rate limit and it belongs with this entry's channel work.

- **The defect**: `ai-media-proxy/index.ts:62-76` `countFreeImageAnalyses` enforces
  `FREE_IMAGE_ANALYSIS_LIMIT = 5` (`:16`, checked `:466`) by counting **lifetime** rows —
  `.eq("user_id").eq("channel","free_image_analysis")` with **no `created_at` bound** (its own
  docstring says "lifetime"). Those rows are non-`app_event`, so `rolling-context:329-351` selects
  them and `:463-472` deletes all but the newest 10 once `:364` passes `MESSAGE_THRESHOLD = 50`.
  **A lifetime quota has no window to survive deletion on — the 5-image free cap resets toward
  unlimited.** Verified: no guard blocks it.
- ⚠ **Second, independent defect in the same function**: `if (error) return 0` with a docstring
  arguing *"fail-open is safer … because 0 < 5"* — which is precisely when the gate does NOT fire.
  (Audit finding CODE-3.) Both must be fixed together.
- ⚠ **A client-side TWIN exists and is easy to miss**:
  `lib/features/ai_coach/repositories/ai_coach_repository.dart:279-292`
  `getFreeImageAnalysisCount()` reads the same `channel='free_image_analysis'`. Currently **uncalled**
  (`grep -rn getFreeImageAnalysisCount lib/ test/` → 1 hit, its own definition), which makes it cheap
  to fix now and easy to forget later — textbook writer/reader drift (§4.1).
- **LATENT, not live** (verified 2026-09-03): **zero** `free_image_analysis` rows exist, and no user
  is near the 50-row prune threshold (max non-`app_event` = 25). The mechanism is real; nobody has
  hit it. So the "migrate existing consumed quota" question is currently moot — there is nothing to
  migrate.
- **Why NOT in the OI-162 table**: a lifetime quota must never be pruned, while a windowed rate limit
  must be. Fusing them forced a retention exclusion that would have retained a `user_id` forever
  after a DPDP erasure. They are different concepts that share a word.
### ALSO 2026-09-03 — the WEEKLY-REPORT first-free gate is a lifetime count and resets the same way

⚠ **Found in code shipped to prod hours earlier the same day** (`a0e20576`, diagnose `e4d1b7`).
That fix closed the gate's FAIL-OPEN half (a failed count granted a free Gemini 2.5 **Pro** report).
It did not touch — and the diagnose-doc never asked about — what DELETES the rows the gate counts.

- `weekly-report/index.ts:93-98`: `.select("id", { count: "exact", head: true })
  .eq("user_id", …).eq("channel", "weekly_report")` — **no `created_at` bound**, i.e. a LIFETIME
  count, feeding `isFirstReport` at `:113` and the PRO gate at `:116`.
- `weekly_report` is non-`app_event`, so `rolling-context:329-351` summarizes and `:463-472` deletes
  it once the user passes `MESSAGE_THRESHOLD = 50`. Count returns to 0 ⇒ `isFirstReport` true ⇒
  **another free Gemini 2.5 Pro report**, repeatedly.
- Same class as the free-image lifetime quota above; same remedy (a quota ledger that is not pruned).
- **How it was found, worth recording:** a plan reviewer proposed replacing a VOCABULARY-based gate
  matcher (`rate.?limit|attempt|throttle` near the table) with a STRUCTURAL one — `count: "exact"`
  in the same statement as an `.eq/.in("channel")` filter. Run over `supabase/functions/` it returns
  **exactly 5 sites, zero false positives**, and this was site 5. The vocabulary matcher missed it
  and two others, while firing on two `rate_limit` mentions that were COMMENTS. **Match on what the
  code DOES, not on what its prose calls itself.**

### ALSO folded in 2026-09-03 — the nightly summarizer RESETS two paid-tier daily caps

Found while checking a different question; nobody had looked. Same root as the entry above
(a counter whose rows `rolling-context` deletes) but a DIFFERENT mechanism — these caps are
enforced by **Postgres triggers**, not Edge Function code, so an EF-only search misses them.

- `rolling-context/index.ts:27-28` — `MESSAGE_THRESHOLD = 50`, `KEEP_RECENT = 10`; `:369-370`
  summarizes everything except the newest 10 and `:463-472` DELETES it, for any user with >= 50
  non-`app_event` rows.
- The three daily caps count an **IST-day window** over `ai_coach_interactions` (live
  `pg_get_functiondef`): `enforce_chat_app_daily_limit` >= **10**,
  `enforce_food_text_daily_limit` >= **50** free / 200 PRO, `enforce_vision_analysis_daily_limit`
  >= **20**.
- **Where the cap exceeds KEEP_RECENT, the cap is resettable.** A free user who reaches the 50/day
  food-text cap has 50 rows today; the 02:30 IST cron keeps the newest 10 and deletes 40, the
  trigger recounts 10, and **40 more analyses unlock**. Same shape for vision (20/day).
- ✅ **chat (10/day) is SAFE — by coincidence, not design.** The cap blocks the 11th row, so a user
  can hold at most 10 rows for the day, and KEEP_RECENT is also 10, so today's rows are exactly the
  ones kept. ⚠ **That safety evaporates if either constant is changed independently** — they are in
  different files with no comment linking them.
- **LATENT** (verified 2026-09-03): max non-`app_event` rows for any user is **25**, below the 50
  threshold, so this has not fired. Both caps are paid-tier boundaries, so it is a revenue issue
  once usage grows.
- **Design note for whoever takes this**: this is a **quota ledger**, not a rate limiter. It also
  needs `countProImageAnalysesToday` (`:88-99`, IST-day) resolved at the same time — that is CODE-1
  above, the dead `pro_image_analysis` read, so the two are one piece of work.
- **THREE DEFECTS MOVED HERE from the OI-162 review, 2026-09-04** — they were surfaced by review
  round 1 of the usage-counter redesign and, until this edit, lived ONLY in
  `docs/plan-reviews/oi162-round1-findings.md`. A known bug parked in a review-notes file nobody
  has a reason to open is a §4.2 deferral in substance, whatever it is called. They are recorded
  here because this OI already owns `ai-media-proxy` + `weekly-report` quota territory:
  1. **Consumption moves from success-time to request-time** if a counter is naively swapped to an
     increment call. Today the free-image row is written at `ai-media-proxy:669`, AFTER Gemini
     returns; the 502 path returns at `:645` writing nothing. An increment at the pre-flight gate
     means **a free user whose Gemini call fails permanently loses one of five lifetime analyses**,
     and a weekly-report failure burns their single free Gemini 2.5 Pro report — with no report.
     Needs either a read-only pre-flight (`peek`) plus consume-at-the-existing-write-point, or an
     explicit release-on-failure path with every failure path enumerated.
  2. **`ai-media-proxy:687` is a SECOND call to the same counter** — a display re-count after the
     insert, commented at `:680-682` as "re-count AFTER insert so the displayed remaining is
     accurate". Under an increment-based counter it burns a second unit on every success, turning
     the 5-image cap into 2. Any fix must make `:687` read the value the single consume returned,
     not re-query.
  3. **The `rolling-context` prune interaction is not testable in CI.** `rolling-context:117-125` is
     cron-only (`isAuthorizedCronCall`), and CI carries no `CRON_SECRET` — so "the summarizer runs
     and the quota survives", the assertion that most directly pins this whole bug class, has no
     automated home. Either drive the SQL directly in a Deno test under `supabase/functions/`
     (CI's `deno-edge-functions` job runs), or record it as a manual live check in the diagnose-doc.
     Do NOT ship a test that silently skips and reads as green.

## OI-154 — a cleared profile field silently reverts on the next sign-in (P1)

- **Status**: OPEN
- **Blocked on**: needs a design spec (tombstone + migration)
- **Verified**: 2026-09-03 — source, full chain traced
- **What**: audit finding ARCH-1 (Slice C). `_hasValue` returns false for `''`
  (`sync_service.dart:2366-2370`), so `sync_profile.dart:230` omits a cleared field from the upsert
  entirely; the cloud keeps its old value; restore at `:766-767`
  (`for (final e in cloud.entries) if (e.value != null)`) re-hydrates it; and
  `restoreLightweightAlways` runs on **every sign-in** (`sync_service.dart:1326`) — not just reinstall.
- **Blast radius — 33 fields, not 6**: `_hasValue(p[` ×**20** plus `_hasNumber(p[` ×**13**
  (`_hasNumber` at `sync_service.dart:2374-2378` shares the absent/cleared conflation). Two audit
  passes reported 6 then 20; both were too narrow.
- **Two designs already REFUTED — do not re-propose**: (1) "make a server-side null authoritative"
  causes DATA LOSS — `sync_profile.dart:755-757` documents that cloud nulls deliberately do not wipe
  Hive, to preserve local-only edits not yet synced. (2) a per-field sentinel is inexpressible —
  the guarded set spans `date`, `numeric` and `text[]`, and for arrays `[]` already means
  "not answered" (`:216-221`). Only a tombstone (new column + migration + restore-side subtraction)
  survives.
- **Must exclude** `equipment_owned` (`:223`) — its omission is deliberate. **Must converge with**
  diagnose `c3f2d8`, which fixed this for `body_fat_percent` — itself a `_hasNumber` field (`:233`).
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §11 Slice C.

## OI-155 — six gates are wired to no runner, and Gate 33 cannot detect it (P1)

- **Status**: OPEN
- **Blocked on**: re-enumerate the skip block mechanically
- **Verified**: 2026-09-03 — greps with positive control
- **What**: audit findings INFRA-2, INFRA-11 (Slice D). `check_gate_scripts_wired.dart` allow-lists
  gates with a free-text reason such as *"runs in /build-apk skill Gate 14b"*. For six of them
  `.claude/commands/build-apk.md` contains **0** occurrences (control: `check_apk_size_within_bounds`
  → 1), while their only occurrences in `pre-commit.sh:327-341` and `test.yml:236-249` are **skip
  entries**. They execute nowhere. Two are security-relevant
  (`check_two_user_cross_account`, `check_onconflict_live_arbiter`).
- **The audit said five; it is six** — `check_test_runtime_budget.dart` (`pre-commit.sh:338`,
  `test.yml:248`, 0 in `build-apk.md`) has the identical shape. Re-derive with `comm` rather than
  copying a number.
- **INFRA-11 is the mechanism, not a duplicate**: the allowlist reason is prose nobody parses. Fixing
  the six entries without machine-checking the allowlist leaves the class open.
- **Landing hazard**: a hard-fail INFRA-11 landing before INFRA-2 blocks every commit repo-wide.
  Land together, or warn-only first (§4.11 point 2). `check_test_runtime_budget` may need an explicit
  `runner: manual` state since it can name no runner file.
- **Un-dormanting these surfaces pre-existing violations** their allowlist already names
  ("1 unapplied migration", "3 schema-arbiter conflicts", "1 missing test"). ⚠ The
  snapshot-contract one is **stale** — that gate now passes ("57 keys checked").
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §11 Slice D.

## OI-156 — CLAUDE.md numeric claims drift because nothing re-derives them (P2)

- **Status**: OPEN
- **Blocked on**: nothing — mechanical
- **Verified**: 2026-09-03 — each count re-measured
- **What**: audit findings DOC-1..DOC-9, DOC-15..DOC-19, INFRA-3, INFRA-7, TEST-8 (Slice E).
  Measured vs claimed: gates **95** not 90 (`pre-commit.sh` says 89 — three surfaces, three numbers);
  live tables **50** not 47 (`CLAUDE.md:224`, `:819`, `database.md:12`), with `alerts`,
  `readiness_daily`, `admin_metrics_daily` documented nowhere; GATE_INDEX **49 of 96** not "49 of 87";
  `presence_only:` **10** not 6; `docs/reviews/` **87 of 177** not "81 of 164"; committed
  `feedback_*.md` **1** not two; nested `lib/**/CLAUDE.md` **12** vs §7's 10.
- **The control that proves the mechanism**: every GATED numeric held
  (`check_context_artifact_budget` → PASS, 3 within band); nearly every UNGATED one drifted.
- **Fix is a gate, not a sweep**: `check_claude_md_numeric_claims.dart` re-deriving each count from
  its source of truth. ⚠ Two exclusions: the live table count cannot be gated (a pre-commit gate must
  not need DB access), and DOC-15/16/17 are **not** count drift — they are dangling method names
  (`logSteps`/`logMood`/`logEnergy`: 0 hits repo-wide), dangling `test/contracts/` paths (3 missing),
  and a dangling file path (`profile_screen.dart` does not exist). Those need path/symbol resolution,
  which Gate 26 (§N headings only) does not do.
- **DOC-18 is an invariant edit**: rule 14 protects `plan_generator.dart`, now a **5-line re-export
  shim** — repoint it at `plan_engine/plan_generator.dart`.
- **INFRA-7**: the 14 non-root `CLAUDE.md` (207 KB) are auto-loaded agent context and sit outside
  `backups/context_artifact_sizes.json`, which tracks 3 files.
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §11 Slice E.

## OI-157 — no SAST and no SCA run anywhere in CI (P1)

- **Status**: OPEN
- **Blocked on**: founder call on Semgrep scope
- **Verified**: 2026-09-03 — grep, 0 hits
- **What**: audit findings INFRA-1 / DEP-5 (the founder-seeded item) + DEP-9.
  `grep -rniE "semgrep|opengrep|codeql|trivy|gitleaks|snyk|osv-scanner|npm audit|pub audit"
  .github/ scripts/` → **0**. `.github/workflows/` holds one file; its 7 jobs are analyze, unit-test,
  deno-edge-functions, audit-gates, plan-review-record, supabase-tests, build-check.
  `deno check` type-checks but applies no security rules. The ~95 `check_*.dart` gates encode KNOWN
  bug classes, so they are structurally blind to unknown ones.
- **SCA is the wider, unseeded half**: `dependabot.yml` covers `pub` (:13) and `github-actions` (:51)
  only — no npm, no Deno, across ~110 server-side remote imports.
- **Scope recommendation**: Semgrep (Apache-2.0; Opengrep only matters for the paywalled ruleset)
  scoped to `supabase/functions/` — Dart support is thin and `lib/` already has ~95 bespoke gates
  plus `flutter analyze`. **Coupled to DEP-9**: `deno.lock` is gitignored (`.gitignore:140`), so 105
  integrity hashes exist on one machine only; URL pins fix the version, never the bytes. Commit the
  lockfile first, then scanning has something to scan.
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §6.

## OI-158 — tests and gates that cannot fail (P2)

- **Status**: OPEN
- **Blocked on**: TEST-1 needs one device run to establish truth
- **Verified**: 2026-09-03 — source-verified
- **What**: audit findings TEST-1..TEST-7, TEST-9..TEST-13, ARCH-6, CODE-14.
  **TEST-2**: `test('SKIPPED: …', () {});` then `return` renders as a **PASS** in 5 live-cloud files —
  a credential-less run is indistinguishable from success. The sibling `redeem_referral_test.dart:157`
  already diagnoses and fixes this; the lesson reached 1 of 6 files.
  **TEST-3**: `subprocess_test_timeouts_declared_test.dart` asserts `hasLength(3)` on its guarded
  set, so **adding a 4th guarded file fails the test**; `sot_registry_citations_test.dart` spawns 2
  subprocesses with no `@Timeout`. **TEST-4**: `dart_test.yaml` still has no repo-wide `timeout:` —
  the self-documented better fix, still undone; do BOTH (a repo-wide timeout raises the floor for
  genuinely hung tests). **TEST-1**: ~129 non-skipped `integration_test/` tests are run by nothing
  (`pre-push.sh:141` and `test.yml:112` are both `flutter test test/`); they may not even compile.
  **INFRA-4/TEST-5**: Gate 42 `exit(0)`s if `sot_registry.yaml` is absent and never resolves a
  `behavioral_test_path:` to disk. **ARCH-6**: Gate 46 claims to catch an 8th leak-prone singleton
  against a hardcoded const of 7. **CODE-14**: Gate 20 advisory 3.5 months, live **81+** findings,
  and its tracker OI-44 is CLOSED and about a different topic.
- **blocked_on_user**: TEST-12 — all 4 Patrol device flows are `skip: true` and Gate 54 stays green;
  needs a founder run on the Pixel before the gate means anything.
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §4.

## OI-159 — sync and Edge Function correctness residue (P2)

- **Status**: OPEN
- **Blocked on**: nothing — but see OI-154 for the ARCH-1 half
- **Verified**: 2026-09-03 — source-verified
- **What**: audit findings ARCH-2..ARCH-5, ARCH-7..ARCH-10, CODE-5, CODE-9, CODE-10, CODE-11, CODE-12.
  **ARCH-2**: `sync_queue.dart:8-12` documents 4 drain triggers; `connectivity_plus` is **not a
  dependency** (`grep -c connectivity pubspec.yaml` → 0) and no periodic timer exists — a transient
  failure waits for a cold launch or a manual tap. **ARCH-3**: `_backoffSeconds` has 7 entries but
  `_isDue` clamps to `retryCount-1` while dead-lettering at `>= 7`, so the 24h step is
  **unreachable** — real budget ≈ **2h35m**, not ~26h; and the test cited at `:102` to pin it
  (`sync_queue_retry_budget_consistency_test.dart`) **does not exist** — repo-wide grep returns only
  the citation. **ARCH-4**: `_executeUserProfileUpsert` (`sync_service.dart:745-757`) lacks the
  cross-account guard both siblings carry (`:689-693`, `:724-728`). **CODE-10**: a weekly-recalc run
  where 49% of users failed writes `success` to `cron_call_log`, so the health alert can never see it.
  **CODE-11**: an unchecked read feeds a spread-merge that can replace a day's `snapshot_json` with
  three keys. **CODE-5**: fire-and-forget embedding write; `EdgeRuntime.waitUntil` appears **nowhere**
  in the tree. **CODE-9**: IST date concatenated with a `Z` suffix — 5h30m window drift.
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §5.

## OI-160 — dependency + build-toolchain hygiene (P2)

- **Status**: OPEN
- **Blocked on**: DEP-7 needs a founder unpin decision
- **Verified**: 2026-09-03 — versions read from files
- **What**: audit findings DEP-1, DEP-2, DEP-3, DEP-4, DEP-6, DEP-8, DEP-11, DEP-13, CODE-13.
  **DEP-8**: CI builds the APK on **JDK 17** (`test.yml:494`) while the machine and CLAUDE.md require
  **JDK 21** (`openjdk 21.0.12.1`) — CI cannot catch a JDK-21-only Gradle failure.
  **DEP-2/DEP-3**: `@supabase/supabase-js` at 3 versions (37× 2.39.3, 1× 2.42.0, 2× 2.45.4) and
  `deno.land/std` at 3 (9× 0.177.0, 3× 0.208.0, 62× 0.224.0) — the Feb-2023 `std@0.177.0` sits on the
  payment path. **DEP-1**: `import_map.json` is inert — 0 imports resolve through it.
  ⚠ **Do NOT simply delete it**: Gate 27 asserts THREE things, and its floating-pin scan is wrapped in
  `if (importMap.existsSync())` (`check_import_map_present.dart:62`), so deleting the file disables
  the detector during the very work that converges pins (§4.11 inversion). Make the scan
  unconditional FIRST. Note the scan matches **only** `supabase-js` (`:71`), so DEP-3 gets no cover
  from it. **DEP-6**: 84 packages locked below available, 11 constraints below resolvable.
  **DEP-11**: `riverpod_annotation` (a runtime dep with 0 `@riverpod` uses and 0 `.g.dart` files),
  `cupertino_icons`, `pg` all unused.
- **DEP-7 (blocked_on_user)**: pub's solver now shows `share_plus 13.3.0` as *Resolvable*, so the
  block recorded in `project_share_plus_13_blocked.md` may have lifted. Needs a real
  `pub upgrade --dry-run` (runnable without the founder) and then an unpin decision (not).
- **Related**: `docs/audit/2026-09-02/remediation-plan.md` §6.

## OI-161 — two blind spots in our own observability and discipline gates (P3)

- **Status**: OPEN
- **Blocked on**: INFRA-13 is platform-tier, needs its own review
- **Verified**: 2026-09-03 — live query + grep
- **What**: audit findings INFRA-12, INFRA-13.
  **INFRA-12** — telemetry `error_code` values are opaque: one live hour (2026-08-29 18:00) held
  `minified:a0Y` ×47, `String` ×22, `minified:a4d` ×4. `String` is exactly the
  `error.runtimeType.toString()` antipattern lens L32 names, and `minified:*` are unresolved web-build
  symbols. Writer is `lib/core/services/error_telemetry.dart:267,278`. These rows also count toward
  the alert threshold while carrying no diagnostic value.
  **INFRA-13** — `check_gate_scripts_wired.dart:62-77` contains *"tracked separately"* ×4 and
  *"dedicated remediation batches"*, which §4.2 bans. `check_no_deferral_euphemism.dart:15-16` scans
  only staged `*.md` plus a full sweep of CLAUDE.md and `.claude/skills/**/SKILL.md` — it **never
  scans `.dart` source**, so the gate built to catch deferral euphemisms is blind to the ones inside
  gate source.
  ⚠ **INFRA-13's fix is not a one-line widening**: the same banned phrases appear in
  `check_no_deferral_euphemism.dart`'s own header (it quotes the ban), in `discipline_hook.dart`, and
  17× across `lib/`+`test/`+`supabase/`. Markdown has a `deu-quote` escape (`:129-130`); a Dart-comment
  equivalent must be designed, and that script self-declares **platform tier** (`:37-38`), so the
  change needs its own plan-review record + B-pass.
- **THIRD instance, added 2026-09-03 by the Slice A B-pass (`docs/reviews/db5584050b6b-review.md`
  Finding 3): Gate 42 under-reports its own tally.**
  `dart run scripts/check_sot_behavioral_test_paths.dart` prints
  *"…; 7 carry presence_only: true (Deno-EF/static)"* while
  `grep -c "presence_only: true" docs/sot_registry.yaml` → **12**. Cause at
  `scripts/check_sot_behavioral_test_paths.dart:78-86`: the classifier is
  `if (hasBehavioralPath) … else if (hasPresenceOnly) …`, so a concept carrying BOTH fields — the
  CORRECT, documented pattern — is bucketed as behavioral for reporting and never counted.
  ⚠ Does NOT affect the PASS/FAIL verdict (a concept needs only one of the two fields), so this is
  a self-reported-count defect, not a coverage hole. Same class as CLAUDE.md rule 21's own
  *"6 entries carry it today"*, which is likewise wrong — it is 12.
  Fix: count both independently, or test `presence_only` first. Left here rather than folded into
  Slice A because it is a platform-tier gate edit unrelated to that slice's correctness, and the
  slice was deliberately narrowed after two review rounds.
- **NOT a finding — recorded so it is not re-raised**: the 37-day client-error alert silence is
  CORRECT. The detector is alive (670 succeeded / 2 failed in 7 days) and thresholds were tuned
  2026-06-06 to `info_at: 100` REAL errors/hour excluding `event`/`info` breadcrumbs; the worst recent
  hour held 76 real errors. Verified by re-measuring the hour under the actual rule, including the
  failure-shaped op_type re-inclusion (which added ~0).
- **Related**: `docs/audit/2026-09-02/findings-by-lens.md` INFRA-5 resolution.

## OI-162 — the delete-account rate limit is INERT in production; its counter has never written a row (P1)

- **Status**: OPEN
- **Blocked on**: needs OI-153's channel-reader enumeration
- **Verified**: 2026-09-03 — schema + DDL + repo grep + prod
- **PROGRESS 2026-09-05 (does NOT close this)**: the `usage_counters` ledger this issue's fix will
  use is now live AND proven in production with three real readers — migration 129 (`c7b95fe5`)
  moved the chat / vision / food_text cap triggers onto `consume_quota()`. That is slice 2 of 4;
  this issue is slice 4's target and is untouched. What it de-risks: the ledger's atomicity, its
  RLS-with-no-policy guard and its retention are no longer theoretical. ⚠ The trap noted below is
  UNCHANGED and still applies — the fix here still introduces a new channel value, and
  `delete_account_attempt` rows must not become quota state.
- **Security impact**: `7ad009` (2026-05-11) added a rate limit to the delete-account
  confirmation-token check because *"a malicious actor knowing a target's 8-char user_id prefix could
  repeatedly POST attempts."* **That limit has never functioned.** `attemptCount` is structurally
  always 0, so `delete-account/index.ts:159`'s `>= RATE_LIMIT_MAX` can never fire and the
  token-guessing path on the DPDP §17 erasure endpoint is unthrottled.
- **Why the counter always fails** — the insert at `:176-182` is malformed two independent ways:
  1. `prompt_snippet` (`:179`) and `response_snippet` (`:180`) **do not exist** on
     `ai_coach_interactions`. Live snapshot: `[id, user_id, snapshot_id, channel, user_message,
     ai_response, model_used, tokens_used, was_helpful, created_at, summarized, tool_calls]`.
     Repo-wide `prompt_snippet` appears **once** — that line. ⇒ 400 / PGRST204.
  2. `user_message text NOT NULL` (`005_create_ai_tables.sql:32`) is never sent ⇒ 23502.
  **Prod confirms**: the `ai_coach_interactions` channel census lists `in_app_orphan` 57, `app_event`
  30, `food_text_analysis` 25, `app` 8, `in_app` 5, `promotion_ceremony` 5 — `delete_account_attempt`
  is absent at a granularity that shows 5-row channels.
- ⚠ **The obvious fix is a TRAP — do not just correct the columns and ship.** Making the insert
  succeed introduces a NEW channel value, and `rolling-context/index.ts:351` filters by
  `.neq("channel","app_event")` — a **denylist**, deliberately (`:347-350`), so any new channel is
  treated as conversation. Its own header (`:332-344`) records the Hermes P1-E/P1-F incident of
  2026-08-20: such rows *"were being embedded into memory_embeddings as source_type='conversation' —
  92 of 598 rows"* and reached ai-proxy's **SYSTEM prompt**, and the delete at `:466-472` then
  **removed them** — which here would silently reset the very counter the limit reads.
  ⇒ Either add `.neq("channel","delete_account_attempt")` to rolling-context's predicates in the same
  batch (also re-check `restore-user-snapshot:254`, `daily-snapshot:61`, `sync_coach.dart:121`), or
  record the attempt somewhere that is not `ai_coach_interactions`.
- **Paired gate finding (INFRA-14) — why this shipped undetected**:
  `scripts/check_schema_column_refs.dart` validates insert-map keys *"single-line + **first line** of
  multi-line maps"* (its own SCOPE/LIMITS, `:32-34`). `.insert({` puts every key from line 2 onward,
  so most of every multi-line insert map is unchecked; it runs clean today
  (`840 references validated; 0 drift`) while missing both phantom columns. Its header states this
  class *"was invisible BY CONSTRUCTION. Measured: 53% of recent fix-regressions were this
  cloud-contract class"* — it closed the single-line half only.
  ⚠ **A naive balanced-brace extension produces false positives**: a prototype measured 12
  violations of which **10** were keys of nested JSONB value objects (`ai-proxy:1081-1088`
  `metadata: { date, channel, model, is_pro }`, `rolling-context:394-397`, `daily-snapshot:222`,
  `proactive-coach-promotion:154-157`). The fix needs **brace-depth-1-only** key validation, and
  should also add ES6 **shorthand** keys (`.insert({ user_id, embedding, content })` currently
  contributes zero checked refs). ⚠ It can never catch defect #2 — the snapshot stores column
  **names only**, no nullability — so a Deno test asserting `error === null` is the acceptance
  evidence for the NOT NULL half.
- **Provenance**: tech-debt audit 2026-09-02 finding CODE-7, root cause rewritten by Slice A review
  round 1, hazard found by round 2. Split out of Slice A because its blocker is OI-153's enumeration.
- **RESCOPED 2026-09-03 to the WINDOWED counters only** (`delete_account` 5/60min,
  `verify_payment` 20/10min). The free-image LIFETIME quota — a third instance found during this
  plan review — **folded into OI-153**, because a lifetime quota must never be pruned while a
  windowed limit must be, and fusing them forced a retention exclusion that would have retained a
  `user_id` forever after a DPDP erasure.
- ⚠ **verify-payment is instance B and its root cause is NOT deletion** (corrected in review round 2):
  it counts only `>= now()-10min` and `rolling-context` is nightly, so the overlap is narrow. Its
  real defects are the **un-awaited** fire-and-forget `.then()` (`verify-payment/index.ts:258`) and
  inline magic numbers (`>= 20` at `:230`, `600`) instead of named constants.
- ⚠ **DPDP, settled by live query**: `ai_coach_interactions.user_id` is already
  `REFERENCES users(id) ON DELETE CASCADE`, and `users.id` is `REFERENCES auth.users(id) ON DELETE
  CASCADE`. So today's attempt rows ALREADY erase with the user. Any new table must preserve that —
  a no-FK design would be a REGRESSION on the erasure endpoint, not a neutral choice.
- **Related**: OI-153, `docs/audit/2026-09-02/slice-a-plan.md`, `docs/audit/oi162-plan.md`,
  diagnose `7ad009`.

## OI-163 — the four-tag migration header has NO gate, and two places claimed it did (P2)

- **Status**: OPEN
- **Blocked on**: nothing — needs a gate written, mutation-proven, ledger entry
- **Verified**: 2026-09-05 — repo-wide grep + the live cost on migration 129
- **What is true**: `supabase/migrations/CLAUDE.md` mandates a four-line header (`Intent:`,
  `Destructive?:`, `Rollback strategy:`, `Linked diagnose-doc:`). **Nothing enforces any of it.**
  `grep -c Destructive scripts/pre-commit.sh` → 0; no `check_*.dart` reads the tags. The only
  repo-wide hit for `Destructive?:` under `scripts/` is `seed_exercise_library.js:74`, which
  WRITES the tag into a migration it generates.
- **Why it is filed rather than assumed harmless**: that file asserted, in TWO places, that the
  pre-commit hook greps for the tags. Both were false and both were believed. Corrected
  2026-09-05 (`485bde42`) to say self-attested — but a correction is not a gate.
- **It has already cost one migration, permanently**: 129 shipped with `Intent:` and
  `Rollback strategy:` only, while its own diagnose-doc (`e7c4b2`) asserted it "carries the
  four-tag header". Caught by a context-blind B-pass grepping instead of reading. An applied
  migration is IMMUTABLE, so the omission cannot be repaired — only recorded.
- **Shape of the fix**: a `check_*.dart` reading the STAGED blob of any added
  `supabase/migrations/*.sql`, requiring all four tags. Rule 24 applies — mutation proof + a
  `gate_test_ledger.yaml` entry in the same commit. Grandfathering by name is the established
  pattern for the migrations that predate it.
- **Related**: `supabase/migrations/CLAUDE.md` (the correction), diagnose `e7c4b2`, OI-135
  (the sibling class: the ledger `hash` field is present-but-never-compared).

## OI-164 — the shared QA account caps CI at ~3 runs per IST day (P2)

- **Status**: OPEN
- **Blocked on**: a founder decision on test-account provisioning
- **Verified**: 2026-09-05 — live `usage_counters` + the arithmetic + a red CI run
- **What changed**: OI-162 slice 2 (migration 129) made the chat cap actually enforce. It counts
  a durable ledger now instead of a table `rolling-context` prunes nightly.
- **The arithmetic**: `ai_proxy_test.dart` sends THREE live chats per run (T15/T18/T19), all as
  ONE shared QA account, against a 10/day free cap. **Three full CI runs per IST day**; the
  fourth is refused. Observed live: `test6@gmail.com chat_app used=10`, and `485bde42` went red
  with `Expected: <200> Actual: <429>`.
- ⚠ **Main is NOT red today and this is not urgent.** `c46ccd5b` taught those tests to accept
  200 OR 429 and assert the contract of each, so the ceiling no longer reddens the build. **The
  ceiling itself is unchanged** — that fix corrected an assertion, it did not buy quota.
- **Why it will get worse**: slices 3 and 4 move six more quota readers onto the same ledger, and
  any new live-quota test spends the same account.
- **Options, none chosen**: a dedicated per-run QA account; a PRO QA account (the chat trigger
  exempts PRO entirely, so its chats cost nothing); or resetting the counter pre-run — which is a
  CI job mutating prod state and is the worst of the three.
- **Related**: diagnose `e7c4b2`, `test/edge_functions/ai_proxy_test.dart`
  (`chatBodyOrAssertCapped`), root CLAUDE.md §4.9 enforcement-repair row.

## OI-165 — `check_onconflict_live_arbiter.dart` 403s, so every `test/sql/` live harness is un-runnable by its documented command (P2)

- **Status**: OPEN
- **Blocked on**: identifying which token the runner needs (Management API vs service-role)
- **Verified**: 2026-09-05 — ran it; and the harness header records the same failure 2026-07-30
- **Symptom**: `dart run scripts/check_onconflict_live_arbiter.dart --sql <file>` →
  `FATAL — Management API HTTP 403 — "Your account does not have the necessary privileges to
  access this endpoint."` It resolves a token (44 bytes) and warns it is using the
  `SUPABASE_ACCESS_TOKEN` env fallback.
- ⚠ **Not new, and that is the point.** `test/sql/oi46_daily_cap_triggers_live_verify.sql`'s own
  header records the identical 403 on **2026-07-30**, worked around the same way. Five weeks
  un-fixed because the workaround is invisible: whoever hits it hand-pastes the SQL through MCP
  `execute_sql` and moves on, exactly as I did on 2026-09-05 for the slice-2 assertions.
- **Why it matters more than a broken script**: these harnesses are the ONLY behavioural proof
  for Postgres trigger/constraint logic — rule 21 says a source-grep proves presence only. A test
  that cannot be run by its documented command decays; it is not in the gate loop (deliberately,
  `pre-commit.sh` + `test.yml` both case-skip it), so nothing else notices.
- **What is NOT the fix**: deleting the runner and documenting the MCP paste. That makes the
  harness un-runnable by anyone without this MCP, including CI.
- **Related**: `test/sql/onconflict_live_arbiter.sql`, `oi46_daily_cap_triggers_live_verify.sql`,
  rule 21, `docs/operations/SECRET_INVENTORY.md`.
