# Open Issues — class-level audit follow-ups

Evergreen task board. Every gap surfaced by any audit / observation /
diagnose pass that hasn't yet been closed by a shipped commit lives here.

## How this file is used

- **Append-only at the bottom.** Never re-number a closed issue; the OI
  number is its permanent identifier (referenced from diagnose-docs +
  commit messages).
- **Numbers are ALLOCATED, never eyeballed (2026-09-12).** File a new issue with
  `sh scripts/mint_oi.sh "<title>"` — it reserves the next free number as the
  remote branch `oi/N` (an atomic create on GitHub, so two sessions cannot both
  get N, laptop or cloud) and appends the stub. An UNRESERVED number FAILS the
  commit (`check_oi_numbering_unique.dart`, Check C) at pre-commit and at
  pre-merge-commit — adopting an orphan reservation by hand is fine. Run it in
  YOUR worktree (§4.13) — it edits this file. A number filed before the
  allocator existed: `sh scripts/mint_oi.sh --reserve N "<title>"`. Never mint
  offline — the script refuses, by design. The cloud never prunes (no `gh`);
  the next laptop mint prunes for it. Spec:
  `docs/superpowers/specs/2026-09-12-oi-allocator-design.md`.
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
- **Verified**: 2026-09-26 — ROOT CAUSE FOUND: the reader regex at `scripts/check_snapshot_contract.dart:252` captures `fn:\s*([\w-]+),`, which rejects the `/` in `fn: _shared/notification_prefs` (`docs/snapshot_contract.yaml:578`), so that reader line never matches and is never checked. The skip-list half of this OI is already done (OI-155).
  PRIOR (kept verbatim): 2026-08-01 (Unit 9, `oi79-paged-cron-reads`) — measured, not inferred.
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

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** Fix is one capture, `[\w-]+` → `[^,]+`; the one affected citation (`notification_prefs.ts:231`) is currently correct, so it surfaces 0 new violations and can hard-fail on day one. Add a negative-control test that mutates every reader entry's line. Pairs with OI-216 (per-entry slack, same script).

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

## OI-53 — Flip the remaining 2 workout-generator ship-dark flags (was 13; equipment-exclusions flipped 2026-08-05; readiness + triggered-deload flipped 2026-09-01; phase-arc flipped 2026-09-05; deload-reason-line flipped 2026-09-06; exercise_id_history + injury_substitute_pref + cross_phase_variety flipped 2026-09-16 batch 1; graded_progression + session_detraining_cut + physique_focus_bringup + adherence_gate flipped 2026-09-16 batch 2)

- **Status**: OPEN
- **Verified**: 2026-08-05 — flag inventory, dependency order and the data lag all re-derived from
  source this session (`plan_engine_flags.dart`, `deload_evaluator.dart:170,173`,
  `ship_dark_pending_review.yaml:76-101`), not carried from the entry's original text.
- **Identified**: 2026-07-26 · workout-generator overhaul complete `7bb766fa`
- **Blocked on**: FOUNDER — but read the shape below before treating this as one decision.
  ⚠ **DATED FOUNDER DECISION 2026-09-01: readiness + triggered deload were approved and
  flipped together** (branch `readiness-flip`, record `docs/plan-reviews/readiness-flip.md`).
  Recorded here because a repo-only reader cannot otherwise reconcile `Blocked on: FOUNDER`
  with those two flips existing. ⚠ **DATED FOUNDER DECISION 2026-09-05: `enable_phase_arc`
  approved and flipped** (branch `phase-arc-flip`, record `docs/plan-reviews/phase-arc-flip.md`).
  ⚠ **DATED FOUNDER DECISION 2026-09-06: `enable_deload_reason_line` approved and flipped** as Unit B (branch
  `unitb-deload-reason`, record `docs/plan-reviews/unitb-deload-reason.md`) — the piece split
  out of the phase-arc flip the day before, once its stale-reason defect was fixed (diagnose
  `c5a8f3`).
  ⚠ **DATED FOUNDER DECISION 2026-09-16: `exerciseIdHistoryEnabled` + `injurySubstitutePreferenceEnabled`
  + `crossPhaseVarietyEnabled` approved and flipped together** as Batch 1 of a founder-directed
  release-blocker triage (branch `oi53-batch1-flip`, record `docs/plan-reviews/oi53-batch1-flip.md`)
  — the three lowest-risk of the remaining flags (bounded/preference-only re-ranks with no ability
  to widen a slot's candidate pool beyond what queryV4's injury/equipment filters already permit).
  ⚠ **DATED FOUNDER DECISION 2026-09-16: `gradedProgressionEnabled` + `sessionDetrainingCutEnabled`
  + `physiqueFocusBringupEnabled` + `adherenceGateEnabled` approved and flipped together** as
  Batch 2 of the same triage (branch `oi53-batch2-flip`) — the founder's own scoping question
  ("all 6 remaining, or the 4 clean ones") surfaced that `volumeTitrationEnabled`'s readiness
  dependency is, unlike its siblings `triggeredDeloadEnabled`/`plateauEscalationEnabled`, NOT
  enforced in code (`volume_titration.dart:116-136`'s `_recovered()` has no readiness gate at
  all — it is inert today only because the flag itself short-circuits first); that flag and
  `plateauEscalationEnabled` (which depends on it) were deliberately excluded from this batch.
  **2 remain.**
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
- ✅ **`enable_phase_arc` — FLIPPED 2026-09-05.** Display-only, no engine coupling. Taken
  first deliberately: it changes nothing about prescribed training, so it was the cheapest
  ×2 and it put `week_character` on screen before anything that alters load.
  ⚠ **It did NOT ship alone — the batch was SPLIT.** The week-4 deload-"why" line lives
  INSIDE the same widget, so the flip would have lit it too. Plan-review round 2 found the
  stamped `deload_reason_phase_<P>` is never deleted anywhere in `lib/` while a mid-phase
  regen re-stamps week 4 as `deload`, so the strip would render DELOAD above "Working week
  — you've recovered", permanently. That line now sits behind its own ship-dark
  `enable_deload_reason_line` and is Unit B, with its own ×2.
  ⚠ Three defects were fixed in the flip itself, none of them the flag: the fifth wave token
  `working` was unmapped; the label lookup trimmed while its fallback did not; and the
  `length < 2` guard let a 2-3 week blob render a strip whose clamped-to-4 highlight could
  mark no node at all. Also raised FOB-8 against OI-60 — the strip reads
  `getCurrentWeekNumber()` directly, so it is a seventh week-identity surface.

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
- ✅ **`exerciseIdHistoryEnabled` + `injurySubstitutePreferenceEnabled` + `crossPhaseVarietyEnabled`
  — FLIPPED 2026-09-16 (branch `oi53-batch1-flip`, record `docs/plan-reviews/oi53-batch1-flip.md`,
  ×2 review converged).** All three are bounded re-ranks of an already-safe candidate list (the
  injury/equipment filters run first and are unaffected by any of these three) — none can widen
  what a user is prescribed beyond what the pre-flip cascade could already produce, only change
  which already-eligible pick wins. `exerciseIdHistoryEnabled` is forward-only (new `exlog_*` rows
  start carrying a matchable `exercise_id`; a later kill-switch reverts the CODE path verbatim but
  does not retro-strip already-stamped ids — harmless, since an OFF resolver never reads them).
  Review found zero code-correctness issues across two independent rounds; both rounds' documentation
  findings (a stale flag-name cross-reference in `plan_engine/CLAUDE.md`, three untouched
  `docs/sot_registry.yaml` concept entries, and this board entry itself) are fixed in the same
  branch. `ship_dark_pending_review.yaml`'s three `pending:` entries move to `resolved:` in this
  branch's follow-up records commit, per this repo's established split-commit convention for that
  file. **6 remained at the time this bullet was written; superseded by Batch 2 below — 2 remain now.**
- ✅ **`gradedProgressionEnabled` + `sessionDetrainingCutEnabled` + `physiqueFocusBringupEnabled` +
  `adherenceGateEnabled` — FLIPPED 2026-09-16 (branch `oi53-batch2-flip`, ×2 review converged).**
  All four INCREASE prescribed load/volume or change the interactive UI (unlike Batch 1's bounded
  re-ranks), matching the founder's original "not the safe direction" ship-dark framing for each.
  `adherenceGateEnabled` is the most architecturally involved: it gates a `last_phase_profile`
  Hive write, a G5 faithfulness re-ranking gate, AND the actual `repeatContent`/`repeat` trigger
  computation at TWO independent call sites (`pro_phase_advance.dart`'s automatic low-adherence
  repeat, `graduation_screen.dart`'s explicit choice sheet). The automatic path re-checks the flag
  a SECOND, redundant time immediately before `_buildRepeatPins` (confirmed by mutation — neutering
  either check alone left the relevant test green; only neutering both reddened it). That trigger
  computation had NO behavioral test coverage before this batch — the pre-existing
  `repeat_phase_pinned_selection_behavioral_test.dart` tests the pinning MECHANISM directly
  (`pinnedExercisesByDay`) and never touches the flag; `repeat_content_scheduling_test.dart`
  covers the `last_phase_profile` write half only. Closed by a new
  `pro_phase_advance_behavioral_test.dart` group driving the actual gating decision end-to-end
  (real expired phase, real completion rate, real G5-matching baseline), mutation-proven. A
  second, unrelated stale comment was found and fixed in the same investigation:
  `workout_schedule_read_service.dart`'s `autoGenerateNextPhaseIfNeeded` doc called the
  `repeatContent` trigger "not yet wired" — it had been wired by Units 3-a2/3-b for weeks; the
  prose was never updated when they landed.
  **B-pass finding (2026-09-16), fixed same batch:** unlike the automatic path, the choice-sheet
  path had NO re-check at all — `runGraduationPhaseAdvance` took the user's already-made
  `repeat: true` choice and called through to `_buildRepeatPins` unconditionally, so a kill-switch
  flip during the human-time gap between the choice sheet opening and the tap was silently not
  honored, contradicting the flag's own "byte-identical when killed" guarantee. Fixed by moving the
  check into `_buildRepeatPins` itself — the ONE method both callers funnel through — so it is now
  genuinely universal rather than caller-dependent; mutation-confirmed (reverting the check reddened
  exactly the new graduation-path kill-switch test, nothing else). `ship_dark_pending_review.yaml`'s
  four `pending:` entries move to `resolved:` in this branch's follow-up records commit. **2 remain**
  (`volumeTitrationEnabled`, `plateauEscalationEnabled` — see the DATED FOUNDER DECISION above for
  why they were excluded).

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
- **Verified**: 2026-09-26 — blocker list re-derived: FOB-7(a)/(b) are CLOSED (`d8b90e86`, merged `280fd810`, `docs/audit/oi60-client-blockers.closure.yaml`); FOB-8 is open and was missing from this list (`train_provider.dart:959` `phaseArcProvider` still reads `getCurrentWeekNumber()` directly).
  PRIOR (kept verbatim): 2026-08-20 — the blocker list re-derived from the AUTHORITATIVE ledger
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

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** The `Blocked on` line below predates this and still lists FOB-7(a)/(b) — they are CLOSED (`d8b90e86`, merged `280fd810`, diagnoses `b9d4c2` / `e7c4a2`). What really remains: **FOB-4** (how the Sunday push + weekly report learn a user is on hold — founder design choice: (a) a `user_progress` hold column/RPC + 2 EF redeploys, or (b) drop the week number from those two EFs' copy for everyone, no migration) and **FOB-8** (`train_provider.dart:959`, `phaseArcProvider` reads `getCurrentWeekNumber()` directly — NOT previously on this list). FOB-3's code is on main; archived ai-proxy payload `backups/edge_function_payloads/ai-proxy/v3_57b0b07.json` (2026-09-24) contains 'HOLD WEEKS', so it is probably deployed — confirm with `get_edge_function` before relying on it.

## OI-61 — Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup

- **Status**: OPEN
- **Verified**: 2026-09-26 — narrowed. v74: H2 is in source (`ai-proxy/index.ts:1075-1092`), H1/H3 already founder-decided (`docs/plan-reviews/v74-coach-telemetry.md:19-21`); the Units 2+3+FC8 live-verify was superseded by later live-tested batches. LIVE: test7 still has 2 `referral_trial` subscription rows `status=active` past end_date (latest 2026-07-13).
  PRIOR (kept verbatim): 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Identified**: 2026-07-26 · Units 2+3+FC8 shipped `237c347`, ai-proxy v73
- **Blocked on**: none — its only blocker was OI-52, which closed 2026-07-27. Pickable now.

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** Narrowed to the ONE remaining item: test7's 2 expired `referral_trial` rows still read `status=active` (live 2026-09-26). Needs a founder yes for a prod data UPDATE marking them expired; then close.

## OI-62 — Coach-reliability: FC6 + Unit A

- **Status**: OPEN
- **Verified**: 2026-09-26 — FC6 SHIPPED (`_clampMealPayload` on all write paths, `nutrition_write_service.dart:117,270`, plus restore; APK now +47). Unit A (F1 restore EF cold-start, F3) has NO content anywhere in the repo — its only record was a harness-local memory file not present on this machine.
  PRIOR (kept verbatim): 2026-08-05 — BLOCKER ONLY (OI-52 confirmed CLOSED at `closed_issues.md:1048`,
  2026-07-27). This issue's own substance has NOT been re-checked since filing.
- **Blocked on**: FC6 is unblocked — its OI-52 dependency closed 2026-07-27. Unit A: F3 anytime,
  F1 founder-gated.
- **Identified**: 2026-07-26 · Unit B merged `b2ea2e3`, ai-proxy v72

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** FC6 is done. Unit A exists only as a name here. Founder question: close OI-62, or re-file Unit A with its substance?

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
- **Blocked on**: founder scheduling of U2b (its own plan + ×2 review) — not technical.
- **Verified**: 2026-09-26 — NARROWED. The "Box not found" in the expiry-banner and
  realtime files was at least partly a SINGLE-process race, not only cross-process
  contention: tests waited for an unawaited `_downgradeLocally()` with a proxy, and
  tearDown closed Hive under the running chain (OI-242, diagnose `b3f8e5`). Those
  files plus the paused-guard file now use `ProDowngradeWaiter`. REMAINING scope is
  exactly two files, split out of `ci-green-batch-a` per §4.12.1 after review round 3
  kept surfacing new issues in the machinery proposed for them:
  (1) `test/contracts/subscription_cqrs_behavioral_test.dart` — 12 `_settle` sites
  still on the a3e9b7 onStateChanged-chained sampler; R3 found the proposed tripwire
  unsound (F1) and a downgrade started in setUp that no per-test wait drains (F4);
  (2) `test/contracts/subscription_payment_grace_window_behavioral_test.dart` (its
  `:79-81` 12×5 ms tearDown drain) — R3 F2: every site there must `wait()`, a teardown
  drain alone is not loud. The per-process Hive directory fix below still stands for
  the cross-process half.
  PRIOR (kept verbatim): 2026-08-03 (twice in one day, both times the same tests passed standalone
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
- **Verified**: 2026-09-26 — mostly fixed by OI-181 (`safe_merge.sh:235-290` warns at merge time when a ≥account branch has NO record). Residual: a record that EXISTS but is not converged gets no warning, and a raw `git merge` bypasses `safe_merge.sh` (`git_safety_hook.dart` has no merge clause).
  PRIOR (kept verbatim): 2026-08-05 — record confirmed present by direct read of its frontmatter, and CI is
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

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** Narrowed to the residual in the Verified line.

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
- **Verified**: 2026-09-26 — 2 live mismatches, not 5: `'AI Weekly Report'` (`reports_screen.dart:1011`) vs `case 'Weekly AI Report'` (`paywall_sheet.dart:151`); `'AI Body Composition Assessment'` (`edit_profile_screen.dart:1657,1700`). `'PRO'`/`'PRO Upgrade'` are deliberate generic sentinels; `'Readiness Trends'` has no call site (readiness went free).
  PRIOR (kept verbatim): 2026-08-07 — `_featureSubtitle`'s switch read directly against every
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

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** Scope is now the two labels above plus shared label constants (the entry's deeper fix). Copy must follow the Wardroom brand soul (`lib/shared/widgets/wardroom/CLAUDE.md`).

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

- **Status**: OPEN — wrapper shipped ship-dark 2026-09-25 (`fc797551`), kill-switch OFF; the
  flip-on decision is the remaining open item, tracked here per §4.6 step 4 rather than as an
  unstated intention.
- **Verified**: 2026-08-13 — the 5 call sites and the two predicate shapes were read directly while
  fixing a3f8d1; `type: 'logged'`'s two writers were confirmed by grep.
- **Shipped 2026-09-25** (`fc797551`, branch `oi126-training-day-predicate`, diagnose `b7e3a1`,
  ×2 plan review + self-triggered B-pass both accepted): a live re-grep at implementation time
  found the split was actually **12** call sites, not 5 — 6 more found by the original Task 3/4
  grep, plus a 12th (`weekly_calendar.dart`) found only by the final whole-branch review because
  its predicate was split across two booleans instead of one joined expression. All 12 now
  delegate to `PlanEngineFlags.isRestDayConsideringLogged(type)`
  (`lib/shared/repositories/plan_engine/plan_engine_flags.dart:499-504`), which reads
  `configBox['enable_logged_counts_as_phase_training_day']` (default OFF — every site is
  byte-identical to the pre-fix inline ternary until the flag flips) and, when ON, delegates to
  the new `isPhaseCompletionTrainingType` (`lib/core/utils/phase_completion.dart:80-81`).
  **Remaining**: flipping the flag to ON is explicitly out of scope for this batch and needs its
  own full ×2 review per CLAUDE.md §4.12.4 (this was the ship-dark BUILD tier, 1 review round
  covering the wiring; the FLIP tier requires 2). Only 3 of 12 sites have real call-through test
  coverage under flag-ON (`currentPhaseCompletionRate`, `PlanIntegrityReconciler.needsHeal`,
  `StreakWarningEligibilityNotifier.isWorkoutDayToday`) — a disclosed, deliberate gap for this
  batch; the flip-on batch's own plan should budget closing it (4 UI-layer widget-pump tests for
  `home_screen.dart`/`day_detail_sheet.dart`/`weekly_calendar.dart`).
- ⚠ **Renumbered 2026-08-16 (was OI-107).** Filed on branch `claude/open-issues-triage-976962` while `main` independently advanced to OI-124, so OI-107 collided with a different, unrelated issue already on the board. Commit `0e4d97cd`'s message still cites the OLD number — it was pushed before the collision was found and is not rewritten. Mapping: 106→125, 107→126, 108→127.
- **Identified**: 2026-08-13 · surfaced by round-1 review of the a3f8d1 batch
- **Blocked on**: none. The flip-on commit needs its own full ×2 review (see above); the wiring
  itself is shipped.
- **What's missing**: the repo holds TWO shapes of one rule. The EXCLUSION shape
  (`type != 'rest' && type != 'off'`) now lives in `isTrainingDayType`
  (`lib/core/utils/phase_completion.dart:59`) and is used by the weekly-streak reckoning and
  `holdWeekSessionProgress`. The INCLUSION shape (`type != 'workout' && type != 'custom_template'`)
  is now unified behind `PlanEngineFlags.isRestDayConsideringLogged` at all 12 sites (see above).
  The two shapes still DISAGREE about `type: 'logged'` at flag OFF (unchanged pre-fix behavior) —
  written by `WorkoutWriteService.markCompleted`'s no-prior-schedule branch (AI-coach-only
  logging, `workout_write_service.dart:510`) and by the restore synthesize path in
  `sync/sync_workout.dart:985`, whose own comment states a logged row "counts as a workout day in
  the streak walk". So a coach-logged or cloud-restored day still counts as a training day for
  the streak but as a REST day for phase completion, the home rest-day banner, and the PRO-advance
  gate input — until the flip-on commit lands.
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
- **Verified**: 2026-09-26 — LIVE, worse than filed: 3 current `bug_id` collisions in `docs/diagnoses/` — `d3f7b2`, `e8a3b1`, `f7a2c9` (`grep -h '^bug_id:' docs/diagnoses/*.md | sort | uniq -d`).
  PRIOR (kept verbatim): 2026-08-25 — `ls docs/diagnoses/*.md | sed -E 's/.*-([0-9a-f]{6})\.md$/\1/' | sort |
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

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** Three live collisions now exist (listed above); any `closes-diagnose:` trailer citing one of them is ambiguous. Pairs with OI-167 (skill bug-class number collisions) as one 'hand-minted id collision' batch.

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

## OI-154 — a cleared profile field silently reverts on the next sign-in (P3, was P1)

- **Status**: OPEN
- **Blocked on**: FOUNDER — product choice (below). Deferred 2026-09-29 as non-critical; nothing technical blocks it.
- **Verified**: 2026-09-29 — re-traced against `main` @ 628798ec; citations below are corrected, the chain is unchanged. See "2026-09-29 re-scoping". Not reproduced on a device.

### 2026-09-29 re-scoping (supersedes the P1 framing and the "only a tombstone survives" conclusion below)

**Reachable blast radius is ONE field, `city` — not 33.** Only fields a user can empty through the UI
can hit this: `phone` has no client writer to `users.phone` and is not in the `user_profile` payload;
`avatar_url`/`banner_url` are set-only (`profile_provider.dart:136-140, 214-218`);
`date_of_birth`/`wake_up_time`/`preferred_workout_time` use `?iso` and omit the key when unset
(`edit_profile_screen.dart:1866-1868`); `injuries`/`equipment_*` use `[]` as "not answered".
`body_fat_percent` never reaches sync when cleared, so it is a separate defect: **OI-271**. The other
~27 guarded fields have no clear affordance, so they are LATENT, not user-visible. Only readers of
`city`: `ai_snapshot_builder.dart:107` (already skips empty) and the Edit Profile seed `:214` — hence P3.

**Corrected citations** (the code moved): payload builder `lib/core/services/sync/sync_profile.dart:197-255`
(`city` at `:230`); restore merge `sync_profile.dart:764-771` (a second cloud-over-Hive merge sits at
`auth_session_bootstrapper.dart:525-532`); `_hasValue`/`_hasNumber` at `sync_service.dart:2718`/`:2726`;
`restoreLightweightAlways` defined `:1520`, called `:1478`. Counts still hold: `_hasValue(p[` ×20, `_hasNumber(p[` ×13.

**A design was drafted and REJECTED on cost (2 plan-review rounds, both NOT CONVERGED)** —
`docs/superpowers/specs/2026-09-29-oi-154-profile-city-clear-design.md` (kept as the record). v1 "send `''`
when Hive holds `''`" is WRONG: `edit_profile_screen.dart:1864` writes `'city': _cityController.text.trim()`
on EVERY save, so anyone who ever saved without a city already holds `city: ''`, and an unrelated save from a
stale device would wipe a real cloud city. v2 (a local clear-intent marker) needs, per round 2: success
detection on `Result.isOk` (the failed-push path enqueues a marker then `return;`s normally —
`sync_profile.dart:258-296`), a generation stamp with compare-and-clear, the second merge site, and the marker
written inside the `ProfileWriteService` lock before the profile write. Judged disproportionate for one P3 field.
Do NOT re-propose v1. Verified clean by round 2: sending `''` to `user_profile.city` is safe at the DB
(nullable text, no CHECK/trigger/RLS obstacle, nothing in `supabase/functions/` reads it).

**Options when picked up (founder to choose):**
1. **A — UI guard (recommended)**: if a city is already stored and the box is emptied, block Save with
   "City can't be removed. Change it to another city instead."; a user with no stored city can still save empty.
   One file (`edit_profile_screen.dart` ~`:1864`), S-tier, no sync/migration. Cost: a user can never remove a
   stored city (privacy question for the founder; delete-account is the only erasure).
2. **B — empty means unchanged**: omit `city` from the save map when the box is empty. Simpler, but silently ignores the user.
3. **v2 marker design** from the spec, if removal must work — L-tier, needs the round-2 amendments and a third review round.

### Original entry (2026-09-03, kept for history; its P1 rating and tombstone-only conclusion are superseded above)
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

## OI-166 — regeneration RESTARTS the periodization wave instead of continuing it, so the wave index and the week counter disagree (P2)

- **Status**: OPEN
- **Blocked on**: OI-175 (the window-alignment half — `redoWeek4`/`holdWeek` + the strip's `isCurrent` clamp). Unit 1 (`7f6cf74b`) and Unit 2 (`de52f1e8`) have both SHIPPED; what is left of this issue lives in OI-175 and OI-190 (OI-189 CLOSED 2026-09-13, `b9e4d1`). Stays OPEN until OI-175 lands, because the filed symptom's "now" highlight still points at `week_plans[3]` past real week 4.
- ⚠ **Blast radius is `account`, NOT `≥platform`** — corrected 2026-09-07 by running the classifier over the actual de-duplication file set (`lib/core/services/**` → `docs/blast_radius.yaml:326`; `lib/features/ai_coach/**` → `:235`; positive control `sync_workout.dart` → `platform`, so the classifier discriminates). `bpass: accepted` is still required and still planned — `account` mandates the ×2 review and a self-initiated B-pass (§4.3). This line previously asserted `≥platform` on no measurement
- ⚠ **SPLIT 2026-09-07 after FIVE non-converging review rounds** (§4.12.1: *"successive reviews keep surfacing new material issues ⇒ the unit is too large"*). Round 5 found 7 P1s, **four of them inside round 4's own remediations**, and independently recommended the same split point. **Unit 1 (converged, ships)**: the `check_single_schedule_row_builder.dart` gate scoped to `lib/` and defaulting to warn · `rawWeekNumber()` extracted from `getCurrentWeekNumber()` · implementation D's (`hotel_workout_planner.dart`) three wrong stamps corrected per-row-date. **Unit 2 (re-planned from scratch)**: the pure `buildScheduleRows`, callers A/B/C, the deload dual write, the coach's `current_plan` write, and the preview-cache staleness rule. Plan + all five rounds' findings of record: `docs/audit/oi166-regen-wave-alignment-plan.md`
- ⚠ **OPEN DESIGN QUESTION owned by the Unit 2 re-plan — Q7, the `switch_goal` refresh regression** (raised round 3, unclosed through rounds 4 and 5): bounding a regen's writes at `plan_end` means a `switch_goal` no longer refreshes orphan rows past it, so those keep **old-goal** workouts where today they are rewritten. Options: (a) accept until OI-174's prune, leaving stale forward workouts after an explicit goal change; (b) extend the regen's delete range past `plan_end` to cover existing forward rows — OI-174's prune scoped to a single regen. Lean is (b): a regeneration leaving stale forward workouts contradicts what the user asked for, and "rows this regen is replacing" is a smaller claim than a global prune. **Recorded here rather than in the plan doc because that doc is being rewritten and an open question inside a document under rewrite has no owner**
- **Verified**: 2026-09-06 — every citation below re-read in-session against source
- **Identified**: 2026-09-06 · filed as "the AI-coach regen writes ROWS but never `current_plan`", then WIDENED the same day: a founder-led brainstorm found the same defect class on the **shipped Edit-Profile path**, which DOES write the blob and is still wrong
- **The defect, one sentence**: a regeneration lays out a **fresh 4-week wave anchored at the current week's Monday**, while `getCurrentWeekNumber()` keeps counting from `plan_start` — so the wave index and the week counter disagree by `(currentWeek − 1)` for the rest of the phase
- **Two entry points, one cause**:

  | | AI coach (`RegeneratePlanPlanner`) | Edit Profile (`generateAndScheduleFromDate`) |
  |---|---|---|
  | Writes `current_plan`? | **No** — `grep -c` for `current_plan`/`_planKey`/`week_plans` on `regenerate_plan_planner.dart` + `workout_write_service.dart` → **0 and 0** | Yes, `workout_schedule_read_service.dart:388` |
  | Moves `plan_start`? | No | No — `:382-386`, written only `if (isFirstGeneration)` |
  | Symptom | the strip shows the OLD phase's wave, indefinitely | the strip highlights the WRONG NODE, by one per elapsed week |

- **Worked example (Edit-Profile path, real dates)**: joins Tue 1 Sep 2026 ⇒ `plan_start` normalizes to **Mon 31 Aug**, `plan_end` 27 Sep. Weeks: W1 31 Aug–6 Sep · W2 7–13 · W3 14–20 · W4 21–27. He regenerates Wed 9 Sep. `_normalizeToMonday(9 Sep)` = **Mon 7 Sep** — exactly W2's own boundary, so the DATES align and only the INDEX is wrong. The new wave's `week_plans[0]` now covers 7–13 Sep, but `getCurrentWeekNumber()` = (9 Sep − 31 Aug) = 9 days ⇒ `9~/7+1` = **2**, and `phase_arc_strip.dart:102` renders `isCurrent: (i + 1) == arc.currentWeek` ⇒ it highlights `week_plans[1]`:

  | dates | counter says | strip highlights | he actually trains |
  |---|---|---|---|
  | 9–13 Sep | 2 | overreach | baseline |
  | 14–20 Sep | 3 | peak | overreach |
  | 21–27 Sep | 4 | **deload + the reason line** | **peak** |
  | 28 Sep–4 Oct | 5 → clamped 4 | deload | deload (right by accident) |

- ⚠ **The week-4 row is the sharpest symptom and it lands on a feature shipped 2026-09-06.** The deload reason line gates on `arc.currentWeek == 4` (`phase_arc_strip.dart:74-75`), so it explains a deload during the user's PEAK week. **Unit B's guard cannot catch this by construction**: `validatedDeloadReason` compares the stamp against week 4 of the blob, and week 4 of the blob genuinely IS a deload. Both halves are self-consistent; both point at the wrong week
- ⚠ **A defensive workaround for this already exists inside another feature.** `deload_evaluator.dart` guard 5 bails on any week-4 row whose `generated_via` starts `ai_coach`, because "their own week-numbering + unconditional wave + never-persisted base make an arithmetic un-deload unsafe". The fix below removes the reason that guard has to exist
- **Corroboration**: `workout_schedule_read_service.dart:1182`'s own comment predicts "a `current_phase==1` plan with **week-5/6 rows**" — exactly what a week-2 (→ week 5) or week-3 (→ week 6) regen produces under the current fresh-4-weeks layout
- **Locked design (founder, 2026-09-06)**:
  1. **Base week is the join date, always.** `plan_start` never moves on a regen (already true in code; now an affirmed invariant, not an accident). Founder's reason includes future billing alignment
  2. **A regen writes rows only up to the current phase's end** (`plan_end`) — never beyond; later weeks are the next phase's business. Kills the week-5/6 orphans
  3. **A regen CONTINUES the wave (weeks N..4); it never restarts it at 1.** Wave index and `getCurrentWeekNumber()` then agree by construction, so the arc defect goes away structurally rather than by a display patch
  4. **Regen in week 4 ⇒ that ONE week only**, carrying whatever character week 4 currently holds
  5. **A goal/equipment change mid-phase does NOT move the deload** — week 4 stays the deload of the original base (founder: simpler to maintain)
  6. **One rule for every regeneration entry point** — AI coach, Edit Profile, anywhere else
  7. **The cold-start weight estimate is free for all tiers** → split out as **OI-173**
  8. **A regen READS the deload decision; it never re-runs it.** The week-3→4 rollover has already decided by then, so the regen preserves week 4's current `week_character` (`deload` stays deload; an already-lifted `working` stays working). Chosen over clearing `deload_evaluated_for_phase_<N>`: no "regenerate repeatedly until the deload lifts" exploit, and one decision per phase as designed. ⚠ Implementation: a LIFTED week 4 must regenerate as the WORKING variant — the `working_sets`/`working_reps` stash (SoT `deload_working_base_stash`) already exists for exactly this
  9. **Coach truncation is STATED, not silent.** A request longer than the phase's remaining weeks is truncated to them and the coach says so, naming the phase end (enforcement is the SILENT clamp at `regenerate_plan_planner.dart:143`, `final n = weeks.clamp(1, 12);` — `:61` is only a doc comment; and `RegeneratePlanResult` returns just `totalWeeks` (`:305-312`), so stating the truncation needs a NEW requested-vs-granted field out of `plan()`, i.e. a signature change, not copy alone). Proposed copy — card context line `Rest of phase rebuilt — 3 weeks`; coach reply "Rebuilt the rest of this phase — 3 weeks, through 27 Sep. Weeks beyond that come with your next phase." The coach reply is model-generated, so this lands as a prompt / tool-result instruction, not a literal string
- ⚠ **Round 1 of the plan review (2026-09-06) found a P0 in the first draft's rule, and it constrains any fix here**: `getCurrentWeekNumber()` CLAMPS to 1..4 (`:1263`), so `4` means week 4 AND weeks 5, 6, 7… identically. `redoWeek4()` (`workout_schedule_write_service.dart:178-215`) extends `plan_end` by 7 days WITHOUT moving `plan_start` and is the live free-tier “keep training Phase 1” write (`keep_training_phase1_action.dart:29-36`, since `enable_hold_weeks` is OFF). In that state `isPhaseExpired()` is FALSE (`:1360`), the delete loop (`:362-372`) runs FIRST, and a rule keyed on the clamped week would **delete the remaining days and write nothing**. Any fix must key on the UNCLAMPED week and refuse BEFORE deleting. Invariant: **a regeneration never deletes a row it does not replace.**
- ⚠ **A fourth disagreeing number, not in the table above**: rows carry `'week'`, stamped from the LOOP INDEX (`:271, :303, :473, :502`; `regenerate_plan_planner.dart:278, :352`) and rendered as “Week N” on the Home today-card (`hold_week_labels.dart:133` ← `home_screen.dart:798`) and the day-detail sheet (`:146` ← `day_detail_sheet.dart:108`). A fix that aligns only `week_character` leaves both Home surfaces wrong.
- **Follow-on filed**: **OI-174** — this unit stops NEW past-`plan_end` rows; it does not prune existing ones, which are sync-durable and delay the PRO phase advance.
- ⚠ **A SECOND live bug the same fix cures, found 2026-09-06 while resolving plan-review Q3: the AI coach schedules workouts on the WRONG WEEKDAYS.** `_getDayPattern` returns Monday-indexed values and says so inline — `regenerate_plan_planner.dart:118-131`, `case 3: return [0, 2, 4]; // Mon, Wed, Fri`, documented at `:116` as *"Returns 0-indexed weekdays (0=Mon, 6=Sun)"*. `generateAndScheduleFromDate` honours that by laying each week out from a Monday (`:435-439`, `weekStart = monday.add(week*7)`). **The coach does not**: `start` defaults to TODAY (`:144-146`, `startDate != null ? DateTime.parse(startDate) : _today()`), `weekStart = start.add(weekIdx*7)` (`:224`), and the Monday-indexed pattern is then applied as an OFFSET FROM START (`dayPattern.contains(dayOfWeek)`). So a 3-day user who asks the coach to regenerate on a Wednesday is scheduled **Wed/Fri/Sun instead of Mon/Wed/Fri**. It fires on every coach regen not initiated on a Monday. The planner's own header claims the opposite (`:99-101`: *"Day-of-week pattern matches [WorkoutScheduleService._getDayPattern] exactly so the rest-day distribution stays consistent with manual plan generation"*) — a comment asserting an invariant the code does not hold. Anchoring the coach to plan-week Mondays, which decision 3 already requires, fixes it. ⚠ Rows ALREADY written with skewed weekdays are not repaired by the fix; they are corrected the next time anything regenerates that window, and rewriting them proactively would be a destructive migration over a user's live forward plan — tracked here, not silently assumed away.
- **One unit closes four things**: this OI · the (previously unfiled) Edit-Profile off-by-N · the week-5/6 orphan rows · and it retires the reason `deload_evaluator` guard 5 exists
- ✅ **UNIT 2 SHIPPED 2026-09-12** — `cecda187` on `regen-wave-unit2`, merge `de52f1e8`, CI run 34678095394 green (7/7 jobs). Diagnose `d7f3b2`; record `docs/plan-reviews/regen-wave-unit2.md` (9 rounds, converged, `bpass: accepted`); ledger `docs/audit/regen-wave-unit2.closure.yaml`. Closes the CONTENT half: `contentFlavorIndex((w-1)%4)` cycles the wave past week 4 for both writers, B's loop is anchored to the stored `plan_start` and bounded at the stored `plan_end`, and the AI-coach path (writer C) now writes `current_plan` (a spliced 4-node window preserving completed weeks) — so the phase-arc strip no longer renders a stale wave after a coach regen. **What this did NOT close, each now with its own number:** the window-alignment half and the strip's `isCurrent` clamp (OI-175, pre-existing); **Q7 below — dropped by the re-plan, never decided** (OI-189, filed 2026-09-12 when a post-ship audit found zero mentions of it across v4→v10, nine rounds and the B-pass); and the founder's 2026-09-07 "one implementation" de-duplication, which Unit 2 deliberately did not do — B and C were fixed in place — leaving Unit 1's §4.11 gate WARN-only with no flip owner (OI-190).

## OI-173 — no cold-start weight estimate: a brand-new user, every free user, and any newly-introduced exercise get NO weight guidance at all (P2)

- **Status**: OPEN
- **Blocked on**: none — founder approved 2026-09-06 as free for all tiers. Needs its own small design decision (what seeds the first estimate) before speccing
- **Verified**: 2026-09-06 — `plan_generator.dart:234` (`if (weights == null && phase >= 2)`); `progression_resolver.dart:169` (`if (top == null) continue;`); `periodization_engine.dart:112-117` (`suggestedWeight`/`weightCue` set ONLY when `previousWeights` holds the key); `exercise_card.dart:91` (the active-workout prefill needs `lastPerf.lastWeight`)
- **Identified**: 2026-09-06 · split out of OI-166's brainstorm at founder's direction. It is a NEW FEATURE, never shipped — not a bug — so scoping it separately is a product-scope split, **not** a §4.2 deferral. OI-166 must not depend on it
- **Symptom — three faces, one cause**:
  1. **A brand-new user** has no `exlog_*` history, so every exercise is skipped by `progression_resolver.dart:169` and the weight field is blank
  2. **Every free user, forever** — not because his logs are missing but because the whole progression stage is gated `phase >= 2` and a free user is phase 1 only. His logs are never consulted at plan time at all
  3. **Any newly-introduced exercise, for any tier** — e.g. a PRO user switching goal in week 4 gets new movements with no history, so they are skipped exactly like a new user's
- **Today's actual behaviour, for the record**: sets/reps come from the periodization wave for everyone; `suggested_weight` is PRO-and-phase≥2 only; the active-workout card prefills `lastWeight × effectiveLoadFactor` for everyone **but only once history exists**. So the gap is precisely the FIRST session of any exercise — where a beginner is least equipped to guess and most at risk
- **Founder decision**: free for all tiers. Reason: zero infrastructure cost — no AI, no Edge Function, no API; pure local Dart over Hive (coding rule 8). In practice this means lifting the `phase >= 2` gate at `plan_generator.dart:234` so phase 1 gets plan-time weights too
- **Two candidate designs (founder offered both; not yet chosen)**:
  1. Recommend from day 1, seeded from onboarding (experience level / bodyweight / goal). Covers all three faces above
  2. Leave week 1 blank and calibrate from week-1 logs. ⚠ This is roughly today's behaviour already (the prefill does it at training time), and it structurally **cannot** cover face 3 — an exercise introduced in week 4 has no week-1 history to calibrate from
- **Open before speccing**: what the exercise library actually carries (load metadata? archetype tagging?) versus deriving purely from onboarding fields — **not yet investigated, do not assume**
- ⚠ **Safety**: recommending a load to someone who has never lifted carries real injury risk. A cold-start estimate must be deliberately conservative and framed as a starting point, not a prescription

## OI-174 — schedule rows written past `plan_end` are never pruned, and they delay the PRO phase advance (P2)

- **Status**: OPEN
- **Blocked on**: none — NARROWED 2026-09-13 by OI-189 (see the last bullet): the local half is closed; what remains is the cloud `scheduled_workouts` prune + a freshness guard on `PlanWindowReanchor`, platform tier, needs its own plan
- **Verified**: 2026-09-13 — re-derived while closing OI-189: `_syncScheduledWorkouts` is upsert-only (never deletes a cloud row); `_restoreWorkoutPlan` (`sync/sync_workout.dart:1131`, every returning launch), `_restoreScheduledWorkouts` (since 2020-01-01) and `plan_integrity_reconciler.dart:288-306` are all unbounded by `plan_end`; `PlanWindowReanchor.resolve` (`plan_window_reanchor.dart:45-60`) treats a differing cloud window as authoritative. Both prod censuses 2026-09-13 → 0 rows past `plan_end` (10 users, 369 rows each copy)
- **Identified**: 2026-09-06 · surfaced by round 1 of the OI-166 plan review (finding P1-3), which caught the OI-166 plan claiming these rows were "fixed" when the fix only stops NEW ones being created
- **How they get there**: a mid-phase regen lays out 4 fresh weeks from the current week's Monday, so a week-2 regen writes through `plan_start+34` and a week-3 regen through `plan_start+41` — i.e. week 5 and week 6 rows inside a 4-week phase. `workout_schedule_read_service.dart:1182`'s own comment already warns about "a `current_phase==1` plan with week-5/6 rows". **OI-166 stops the creation; it does not clean what is already there**
- **They are durable, not transient**: `sync/sync_workout.dart:1036-1043` snapshots **every** `schedule_*` key with no date filter into `plan_json.schedules`, and `_restoreWorkoutPlan` (`:1131+`) / `plan_integrity_reconciler.dart:290-300` re-apply them across reinstall and across devices. `test/contracts/phase_adherence_rate_test.dart:191-208` already encodes the week-5/6 state as live reality
- **Consequence beyond tidiness**: `isPhaseExpiredFrom` returns false while any workout row exists on-or-after today (`:1376-1379`), so orphan rows keep a finished phase looking un-expired for up to 7 days. `autoGenerateNextPhaseIfNeeded` early-returns on `!isPhaseExpired()` (`:546`) and `deload_evaluator.dart:61,63` read the same pair — so **the PRO phase advance is delayed** for exactly the users who regenerated mid-phase
- **Why it is NOT folded into OI-166**: pruning is a destructive one-time migration over user data with its own blast radius, and cleaning it CHANGES phase-advance timing (it starts firing on schedule) — a real behaviour change on a PRO path needing its own test. OI-166 is a layout fix. Keeping them separate is a scope split, **not** a §4.2 deferral: OI-166 ships complete and correct without this, and this is filed with a terminal owner rather than left as an intention
- ⚠ **The design question that must be answered first**: what happens to a **`completed`** orphan — a workout the user genuinely performed, logged, and earned a streak for, that happens to sit past `plan_end`? Deleting it destroys real history and could move streaks/PRs/adherence. A prune almost certainly must keep `completed` rows and remove only `planned`/`rest` ones, but that needs stating and testing, not assuming
- **NARROWED 2026-09-13 by OI-189 (`b9e4d1`, branch `oi189-plan-end-bound`)** — what is now TRUE on the device: (i) no phase-layout writer creates a row past `plan_end` any more (A by construction, B since `d7f3b2`, C since `b9e4d1`); (ii) every regen — Edit Profile, coach `regeneratePlanBlock`, coach `switchGoal` — sweeps non-completed rows past `plan_end` locally (`sweepNonCompletedRowsPastPlanEnd`) and pushes `plan_json` right after, so the `plan_json` cloud copy no longer resurrects them; (iii) the `completed`-orphan question above is ANSWERED: completed rows are history and are KEPT by the sweep (the same rule the in-window delete loop applies); (iv) founder decision D2: user-placed rows past `plan_end` (assignTemplateToDate, coach hotel workout, coach reschedule destination) are swept too. **What remains, owned here**: (a) the cloud `scheduled_workouts` table is never pruned — `_syncScheduledWorkouts` is upsert-only — and the three restore writers are unbounded, so a row swept locally can RETURN on a restore (reinstall / new device) until the next regen sweeps it again; (b) an OFFLINE phase advance (writer A with `pushPlanWindow: true`, or `redoWeek4`) cannot push, so `PlanWindowReanchor` can mirror the STALE cloud window back on the next launch and the sweep would then delete the live phase's rows — mitigated by the immediate pushes (online case closed), not eliminated. **Fix design**: a cloud delete issued by the sweep for the same keys (check the RLS delete policy on `scheduled_workouts` first) + a freshness guard on the reanchor (a cloud window older than the local one is not authoritative). Platform tier. A restore-side date filter was REJECTED (hides the stale rows, does not remove them).
- ⚠ **A FOURTH residual, found 2026-09-13 by OI-189's own B-pass (finding B-3), distinct from all
  three above:** `isPhaseExpiredFrom`'s own predicate `_scheduledWorkoutDays()`
  (`workout_schedule_read_service.dart:1642`, pre-existing, untouched by OI-189) filters rows by
  `type` only, never by `status` — so a FUTURE-dated `completed` row past `plan_end` (correctly
  preserved by OI-189's sweep as history) still keeps `isPhaseExpired()` false, reproducing this
  entry's own "orphan rows delay the PRO phase advance" symptom for that one row shape. Verified
  by a probe test (seed a future-dated completed row 3 days out, plan_end 5 days past: sweep
  removes 0 as it should, `isPhaseExpired()` stays false before AND after). Not fixed by OI-189 —
  scoped out as touching a different, pre-existing function with its own blast radius. Fix design:
  `_scheduledWorkoutDays()` (or `isPhaseExpiredFrom` itself) needs a "not completed" filter to
  match the sweep's own rule, symmetric with how the sweep already treats completed rows as
  history that should not block anything.

## OI-175 — a regeneration past the phase's 4th week (`rawWeek > 4`) has no well-defined behaviour (P2)

- **Status**: OPEN
- **Blocked on**: FOUNDER — what a regeneration should DO for a user in the extended "keep training Phase 1" state. AND sequenced after **OI-174**: round 2 of the OI-166 plan review proved the two are not separable
- **Verified**: 2026-09-06 — `getCurrentWeekNumber()` clamps to 1..4 (`workout_schedule_read_service.dart:1263`); `redoWeek4()` extends `plan_end` without moving `plan_start` (`workout_schedule_write_service.dart:178-215`, esp. `:213-214`) and is the live free-tier write while `enable_hold_weeks` is OFF (`keep_training_phase1_action.dart:29-36`, `plan_engine_flags.dart:63-69`); `isPhaseExpired()` gates the Home expired card (`home_screen.dart:771`), the Train surface (`train/screen.dart:169`) and both PRO advance paths (`pro_phase_advance.dart:144`, `workout_schedule_read_service.dart:546`)
- **Identified**: 2026-09-06 · split out of OI-166 under §4.12.1 (successive reviews surfacing new material issues ⇒ split and ship the smallest converged piece). Round 1 produced 11 findings; round 2 produced 5 NEW P1s **inside round 1's own corrections**, and three of them (P1-A, P2-F, P2-H) were all this one branch
- **The state**: two routes put a user past their 4th plan week without `plan_start` moving. (1) `redoWeek4()` — the free-tier "keep training Phase 1" tap — extends `plan_end` by 7 days. (2) A mid-phase regen writes 4 fresh weeks from the current Monday, so rows reach `plan_start+34` (week-2 regen) or `+41` (week-3) while `plan_end` stays `+27`
- **Why OI-166 does not fix it**: OI-166 makes a regen lay `weekPlans[rawWeek-1 .. 3]` on plan weeks `rawWeek..4`. That is well-defined only for `1 ≤ rawWeek ≤ 4`. **For `rawWeek > 4` OI-166 deliberately falls back to today's behaviour verbatim** — no data loss, no regression, and no new claim about a state that is not well-defined until OI-174 prunes. This issue owns the improvement
- ⚠ **Three candidate behaviours, none yet chosen — this is the founder question**:
  1. Regenerate the current extended window (`today..plan_end`) carrying week 4's character, since `redoWeek4` is by construction a week-4 repeat. ⚠ Round 2 found this is NOT week-aligned in the normal case: `rollStart = todayMidnight` when today is past `plan_end` (`workout_schedule_write_service.dart:186-188`), which is the gated-on case, so the window starts on an arbitrary weekday and `dayPattern.contains(dayOfWeek)` would place sessions on the wrong days
  2. Refuse outright. ⚠ Round 2 (P1-A) showed a plain refusal REGRESSES route (2): `plan_end (+27) < today (+30)` makes the window empty, so the goal change is silently discarded, and the orphan rows keep `isPhaseExpired()` false so no recovery surface is reachable for 7 days. Today's code at least honours the goal change
  3. Treat it as a phase boundary — hand off to phase advance / the paywall
- ⚠ **Whatever is chosen must not stamp `'week': 5`**: `hold_week_labels.dart:133` renders `row['week']` straight to the Home card, and that file's own header (`:93`) calls `copy['week'] = 4 + n` "the dishonest number, persisted" — it exists to suppress exactly that string
- **Invariant that holds regardless**: a regeneration never deletes a row it does not replace. ⚠ Note this is already violated in a narrow way — `workout_schedule_read_service.dart:373-376` deletes `displaced_*` keys unconditionally with no `completed` check and no replacement (pre-existing, round 2 P3-N)
- **PARTIALLY RESOLVED 2026-09-11 — a FOURTH candidate behaviour was chosen and shipped, none of the three above**: OI-166 Unit 2 (`docs/audit/oi166-unit2-plan-v10.md`, diagnose `d7f3b2`) implements CYCLING — `contentFlavorIndex((w-1)%4)` repeats the baseline→overreach→peak→deload wave past week 4 rather than freezing on week 4's character (candidate 1), refusing (candidate 2), or handing off to phase advance (candidate 3). This closes the "no well-defined behaviour" complaint for the CONTENT/LABELING half: `rawWeek > 4` now stamps its real week number and picks well-defined content, verbatim, for any `rawWeek`. It does NOT close the WINDOW-ALIGNMENT half this entry also raises — whether `redoWeek4`'s own extension window is week-grid-aligned is untouched (`redoWeek4`/`holdWeek` themselves were explicit out-of-scope for Unit 2). Leaving this OPEN rather than closing it: the founder-blocked question above was "what should a regen DO", and cycling answers it for content but the sequencing-after-OI-174 note and the `redoWeek4` non-alignment concern (candidate 1's own rejection reason) still stand.
- ⚠ **A THIRD residual surfaced the same day by the Unit 2 B-pass (Finding 2, P1), distinct from window-alignment: the phase-arc strip's "NOW" highlight does not cycle even though content now does.** `getCurrentWeekNumber()` (`workout_schedule_read_service.dart:1334`, unchanged by Unit 2) clamps to `[1,4]`, so past real week 4 the strip permanently highlights index 3 — "deload" per Unit 2's own splice — regardless of which of baseline/overreach/peak/deload the real current week actually cycles to. Reachable TODAY via the live `redoWeek4`, no flag required. Not strictly a NEW regression (pre-fix, `current_plan` was also unconditionally rewritten to the same canonical order every regen, so the clamp already existed against different, frozen content) — but Unit 2 makes the mismatch visible and variable for the first time. A real fix means routing the highlight through a cycle-aware index or otherwise making `hold_week_identity`'s clamp itself past-week-4-aware, which is a redesign of a DIFFERENT SoT concept (`hold_week_identity`, own tests, own explicit "do NOT branch inputs where the clamped 4 is HONEST" warning for its other consumers) — correctly out of scope for the already-9-round-converged Unit 2, tracked here instead of left implied-fixed.

## OI-167 — the debugging skill's bug-class numbers collide 9×, every one is cited by number from elsewhere, and nothing gates them (P3)

- **Status**: OPEN
- **Blocked on**: nothing technical — needs a per-citation reading, or a decision to stop numbering
- **Verified**: 2026-09-07 — `grep -oE '^### 2\.[0-9]+' .claude/skills/debugging/SKILL.md | grep -oE '[0-9]+$' | sort -n | uniq -d` → **2.36, 2.37, 2.38, 2.39, 2.40, 2.41, 2.53, 2.54, 2.55** (NINE numbers, each naming TWO unrelated classes). True max is **2.63**. The pairs are genuinely distinct content — `2.36` is both *"a DROP + CREATE on a SECURITY DEFINER function RESETS its ACL"* and *"PostgREST builder is a thenable with NO .catch()"*
- **Identified**: 2026-09-07 · found by nearly minting a tenth — this session added a `2.61` that already existed, caught it in review, and renumbered to 2.63. **2.61 is therefore NOT in the duplicate list**; it is only how the mechanism was discovered
- **Symptom**: two unrelated bug classes answer to the same number, so a citation like "debugging skill bug-class 2.38" does not resolve to one entry. A reader following it lands on whichever occurrence they find first, which may be the wrong class entirely.

- **Root cause, worth stating precisely because it will recur**: the numbers are **not monotonic in file order** — 2.61 and 2.62 sit ABOVE 2.53–2.60 in the file. So the natural survey, `grep -nE '^### 2\.[0-9]+' | tail -1`, answers *"the last-positioned entry"* when the question was *"the highest number"*, and returns a number that is already taken. Correct form, now in the section-2 header as a guard:

      grep -oE '^### 2\.[0-9]+' .claude/skills/debugging/SKILL.md | grep -oE '[0-9]+$' | sort -n | tail -1

- **Same class as the OI-number collisions** `scripts/check_oi_numbering_unique.dart` exists to catch (six had shipped by 2026-08-16; `build_oi_index.dart:110-111` records *"OI numbers are minted by eyeballing the board's tail"*). Identical mechanism, identical cause, **no equivalent gate covers `.claude/skills/`**.

- ⚠ **RENUMBERING IS NOT SAFE FOR ANY OF THE NINE.** A first pass at this entry claimed six of them were uncited and "mechanically safe"; a context-blind review disproved it, and the census below is the corrected result. Every one of the nine is cited by number from outside the skill:

      for n in 36 37 38 39 40 41 53 54 55; do echo -n "2.$n -> "; grep -rn "2[.]$n" --include=*.md . | grep -v skills/debugging/SKILL.md | grep -vE 'docs/(audit|reviews|plan-reviews)/' | wc -l; done
      # every one NON-ZERO. Citing docs span docs/diagnoses/, docs/plans/,
      # docs/superpowers/, docs/handbook/, docs/adr/ and memory/.

  Deliberately ONE line with no backslash continuations and `2[.]N` rather than `2\.N`: three
  separate attempts to publish the multi-line form had their escapes eaten in transit, shipping a
  command with a literal newline inside `printf` and no continuations at all. A guard that
  prescribes a broken command is worse than no guard, so the form that survives copying wins over
  the form that reads more nicely.

  ⚠ **The claim is "all nine are non-zero", NOT any particular count** — and the distinction is
  not pedantry, it is the second defect this entry had to fix. The exact totals are UNSTABLE:
  2.53 reads 8, 10 or 5 depending purely on which directories the command excludes, and a bare
  `2.39` also matches version strings and decimals. Worse, the exclusions have to grow as this
  issue accumulates meta-documentation — the review and plan-review files written FOR this entry
  quote the same numbers, so the first published command started counting them within minutes
  (2.36 went 1 → 6). **A count over a corpus that includes the discussion of the count is not a
  measurement.** Non-zero-ness is the property that survives every exclusion choice, so it is the
  only thing asserted here.

- ⚠ **Two ways the first pass got this wrong, both worth keeping**:
  1. Its census filtered to lines also containing `bug.?class|debugging skill`. The real citations mostly do not say that — `docs/diagnoses/2026-06-13-referral-rls-context-d2b9e6.md:80` reads `2.36 (FunctionException not unpacked → masked errors)` and matches no keyword. **A filter narrower than the thing you are counting reports zero and looks like proof.**
  2. It attributed the citations to "CLAUDE.md, ADRs and diagnose-docs". **No CLAUDE.md cites any of these numbers** — `find . -iname CLAUDE.md -exec grep -Hn "2\.3[789]\|2\.40" {} \;` returns nothing. CLAUDE.md rule 9 cites only 2.35 / 2.31, neither of which is duplicated, so that citation is unaffected.

- ⚠ **The prescribed census must EXCLUDE this board.** This entry names the very numbers it counts, so a naive `grep -rn` scores its own text as citations — the self-matching shape `check_no_deferral_euphemism.dart` handles with a visible `deu-quote` marker. The `grep -v` exclusions above are load-bearing, not decoration.

- **Options**:
  1. ~~Renumber the uncited duplicates~~ — **there are none**; every one is cited. Any renumber requires reading all citations first, so this is not the cheap option it appears to be.
  2. Stop numbering new entries and key on the TITLE, the way `GATE_INDEX.md` keys gates on filename with the number as an optional alias — the move CLAUDE.md rule 24 already made, for this exact reason. Existing numbers stay as aliases; the collisions become harmless.
  3. Gate only, renumber nothing — blocks new collisions, leaves the nine ambiguous.

- **Recommendation**: **option 2 plus a gate.** Rule 24's precedent already exists in this repo — *"the filename is the identity; a number is an optional alias"* — and it is why `GATE_INDEX.md` stopped having this problem. Titles are what readers search for, existing numbers keep resolving as aliases, and no archaeology is needed to stop the bleeding.

- **Not urgent**: this misdirects a reader; it breaks no build and no runtime path. Filed at P3 so it is not lost — the guard now in the section-2 header stops a tenth collision, but a comment is an intention, and this repo's own §4.13 point 6 says intentions decay.

## OI-169 — a local run of `test/edge_functions/` reports "All tests passed" having executed nothing (P2)

- **Status**: OPEN
- **Blocked on**: nothing — needs a decision on which signal to use
- **Verified**: 2026-09-07 — `flutter test test/edge_functions/ai_proxy_test.dart` → `00:00 +1: All tests passed!` on a file containing ~24 tests. `--dart-define-from-file=.env` changes nothing, because the missing keys are not in `.env`
- **Identified**: 2026-09-07 · while verifying the fix for diagnose `a7c3e9`
- **Symptom**: every file under `test/edge_functions/` opens with a credential gate — `if (!SupabaseTestHelper.hasCredentials) { test('SKIPPED: …', () {}); return; }`. `SUPABASE_TEST_EMAIL` / `SUPABASE_TEST_PASSWORD` are **CI-only secrets**, absent from the local `.env`, so the whole file collapses to that one placeholder and reports GREEN.

- **Why this is worse than an ordinary skip**: the placeholder is a PASSING test, so the runner's colour, exit code and summary line are all indistinguishable from a real pass. The only tell is the COUNT — `+1` where two dozen were expected — and a count is exactly what a human skims past. It cost a false "the fix is verified" claim during a red-`main` repair, which is the worst possible moment to be wrong about whether a test ran.
- ⚠ **The skip itself is correct** — a dev machine has no business holding CI secrets. The defect is that the skip is INVISIBLE, not that it happens.

- **Options**:
  1. Make the placeholder a real `skip:` (`test('…', () {}, skip: 'CI-only secrets')`) so the runner prints `~1` instead of `+1`. One-line change per file, and `~` is visually distinct.
  2. Have the placeholder PRINT a loud banner naming the missing variables.
  3. A gate asserting every `test/edge_functions/**` file uses the `skip:` form, so a new file cannot reintroduce the silent shape.
- **Recommendation**: option 1 + option 3. `skip:` is the mechanism Dart already has for exactly this, and it changes the summary line, which is the thing that lied.

## OI-177 — the live-cron snapshot that gives Gate 31 its only fileless-migration coverage has no regeneration trigger, and is already stale (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-10 — `backups/live_cron_jobs.json` holds **28** jobs; `select jobname from cron.job` returns **29**. The absentee is `usage_counters_retention_daily` (jobid 37), scheduled by `128_usage_counters.sql`. The snapshot has not been regenerated since `887fbd82`, the commit that created it.
- ⚠ **NOT a live coverage gap today, and the entry says so up front so nobody fixes the wrong thing**: that job IS in `128_usage_counters.sql` and IS in `CRON_REGISTRY.md`, so Gate 31's input A (the migration scan) sees it and the gate legitimately passes — `PASS: 6 job(s) from migrations and 28 from the live snapshot`.
- **The actual risk, which is narrow and specific**: the snapshot exists *only* to catch jobs input A cannot see — a migration applied to prod leaving no `.sql` file, which is exactly what happened on 2026-08-15 and went unseen for five days (OI-132). **A stale snapshot is dangerous for precisely the one class it was built to cover, and harmless for everything else.** It went stale within three weeks of being created.
- **Why it went stale**: regeneration is "a documented step on any migration that schedules or unschedules a job" — i.e. an intention. `scripts/check_cron_registry.dart:42-43` states the limitation honestly ("proves registry-vs-snapshot parity, not snapshot-vs-live freshness"), so this is a known, disclosed hole rather than a surprise. CLAUDE.md §4.13 point 6 already names the pattern: everything with a gate holds, everything on intention decays.
- **Proposed repair**: give it a trigger rather than a reminder — either a §5 close-out row (the mechanism that carries worktree retirement and the context budget, both ungateable for the same reason), or a gate comparing the snapshot's last-touched commit against the newest migration containing `cron.schedule`. The latter is checkable offline and needs no credentials, which matters because CI holds zero Actions secrets (OI-105).
- **Reduced-severity residue from the 2026-08-16 Hermes pass (L24-F1…F5)**: input A's parser still misses `cron.schedule_in_database` (the only form that can set `active=false`), the `cron.unschedule(bigint)` overload, the 2-arg `cron.schedule` form, `$$`-quoting, `EXECUTE '...'`, and direct `INSERT INTO cron.job`. **These are no longer the headline** — input B now covers what input A misses, which is why the architectural fix Hermes asked for was the right call and was made. They matter only in combination with the staleness above.
- **Blast radius**: `scripts/**` is individually pinned `platform`; a new gate needs its own test plus a `mutation_proven:` ledger entry per rule 24.
- **Class**: `feedback_green_check_input_set_width` — a second input was added precisely because the first had the wrong corpus; the second now has a freshness problem the first did not.

## OI-179 — `alert_cron_function_dead` cannot fire across 100% of its range, and never has (P1)

- **Status**: OPEN
- **Blocked on**: none — one-line predicate fix; the value is in the test that would have caught it
- **Verified**: 2026-09-26 — the R2-11 PRECONDITION is now met: migration 144 (diagnose `d6b2f9`) excludes `alert-critical-notify` inside the alert's `cron_call_log` subquery (live jobid 32 verified), pinned by `test/contracts/cron_vacuum_single_statement_test.dart`, which also requires every function on `cron_auth_adoption_test.dart`'s `_triggerDispatchedFunctions` roster that calls `logCronStart` to be excluded. The `>= 8` vs 7-day-prune defect itself is UNCHANGED (batch B2). Latent, recorded: `weekly-recalc` calls `logCronStart` (`weekly-recalc/index.ts:208`) but has no cron job and is not on the roster — a manual run would put it in the same silence-is-healthy class once the threshold is fixed. Also: with retention broken (09-22 → 09-26) this alert became reachable BY ACCIDENT, and a weekly function with one lost success row (`weekly-recap-ready`, OI-194 class) could have false-fired from 2026-09-29; 144's restored prune closes that.
  PRIOR (kept verbatim): 2026-09-10 — `min(started_at)` across `cron_call_log` is **2026-09-03**, so the maximum achievable `days_silent` is **7.46**. The alert's predicate is `days_silent >= 8`. Hermes measured **7.21** on 2026-08-16; three weeks later the ceiling is unchanged because it is set by the pruner, not by traffic.
- **Identified**: 2026-08-16 · Hermes L1-F3. **Pre-existing — not introduced by the log-retention batch.**
- **The mechanism**: `cleanup_cron_call_log` prunes `cron_call_log` at 7 days, sparing only the single *globally* newest success. The alert asks whether any function has been silent for **8** days. The table cannot hold evidence that old, so the predicate is unsatisfiable by construction. It has fired **0 times, ever**.
- ⚠ **The prior diagnose-doc records this as "cannot fire past day 7", which reads like a partial blind spot.** It is not partial: the alert is inert across its entire range. A threshold above its own data-retention ceiling is not a tuning problem, it is a dead alert that reads as coverage — which is worse than having no alert, because it occupies the slot.
- **Proposed repair**: set the threshold below the retention ceiling (or lengthen retention for the alert's own read), **and** add a test asserting `threshold < retention_window` for every alert that reads a pruned table — the class, not the instance. A one-line fix with no such test leaves the next alert free to repeat it.
- **Blast radius**: `alerts/_thresholds.yaml` + the alert's SQL; classify the written file.
- **Cited as a live backstop while inert (2026-09-13, Hermes L31 on OI-153)**: migration 131's header (immutable) and the first version of `founder-digest/index.ts`'s header both named `alert_cron_function_dead` as the fallback that "would otherwise take a week to notice" a dead digest. It would notice nothing. The digest header was corrected (v2); the registry row 131 says so; the migration comment cannot be.
- **Class**: `feedback_green_check_input_set_width` — the alert's input set is bounded by a pruner it does not know about. Also `feedback_bad_news_vs_no_news`: zero firings had two explanations (all healthy / cannot fire) and nobody asked which.
- ⚠ **Precondition on this alert's own repair (R2-11, review round 2, 2026-09-14):
  before lowering this threshold (or lengthening retention for it), the fix
  MUST exclude non-scheduled, trigger-dispatched functions — today just
  `alert-critical-notify` — from `alert_cron_function_dead`'s scope,** via
  an allowlist of real `cron.job` slugs or an explicit denylist of
  trigger-dispatched function names. Reason: `alert-critical-notify` is
  event-driven (not `cron.schedule`-dispatched), so it can legitimately go
  long stretches without running; if this alert's own OPEN threshold-below-
  retention fix (above) ever makes it fire for `alert-critical-notify`, that
  CRITICAL alert triggers `alert-critical-notify` itself to run, which
  writes a fresh success row, which resets its own death-clock — a
  self-sustaining false-critical loop. Today this is INERT only because
  this OI's own bug (the threshold sitting above the retention ceiling)
  keeps the alert from ever firing at all — fixing THIS OI without the
  exclusion would arm the loop for the first time. Cross-referenced from
  OI-199, whose fix shape (widening retention to per-function) would
  independently arm the same loop from the other side.

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** OI-224 closed as a duplicate of this entry (same `alert_cron_function_dead` `days_silent >= 8` predicate vs the 7-day `cron_call_log` prune). ⚠ LIVE 2026-09-26: the prune is currently NOT running (`db_maintenance_nightly` has failed every night since 2026-09-22, filed separately), so retained rows reach back to 09-14 and the predicate has become reachable BY ACCIDENT — a false critical for `alert-critical-notify` is armed for ~2026-10-01 06:47Z if retention is not restored first.

## OI-180 — `check_sot_registry_parity` silently skips every single-number `line_range:`, so 30 citations are validated by nothing (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-10 — `scripts/check_sot_registry_parity.dart:141` matches `line_range:\s*(\d+)-(\d+)` only. Counted in `docs/sot_registry.yaml`: **30** entries use the single-number form and **640** use the dash form. The 30 get no file-exists check, no range check, and no method-appears check — they are not validated at all.
- **Identified**: 2026-09-10 · B-pass finding 3 on `4f6eb6532418` (the realtime PRO-gate rebase).
- **How it surfaced, which is the useful part**: the `sync_realtime_subscription` concept cited `sync_service.dart:808 method: checkAndSync`. That was correct when authored and pointed at a bare `}` 167 lines from the real call site after the rebase. **The gate never noticed, because 808 is single-number.** Converting that one citation to the dash form during the fix made the gate check it — and it immediately FAILED, because the range named a call site rather than the declaration. The same gate went from silent to blocking on the same citation purely because of its punctuation.
- ⚠ **A second, different false negative sits next to it**: the dash-form check asks only whether the method NAME appears anywhere inside the range. `_onUserChanged` cited `158-195`, and line 158 is `SingletonLifecycleRegistry.register('SyncService', _onUserChanged);` — a *reference*, not the definition (which is at 166). The gate was satisfied by the mention. So even the checked form can be green while pointing at the wrong place.
- **Proposed repair**: validate the single-number form too (at minimum file-exists plus method-appears-near-N), and for the dash form prefer matching a DECLARATION (`method_name(` preceded by a type or `Future<`) over a bare substring. Both are offline checks needing no credentials.
- **Blast radius**: `scripts/**` is individually pinned `platform`; needs its own gate test + `mutation_proven:` ledger entry per rule 24.
- **Class**: `feedback_green_check_input_set_width` — the gate's input set silently excluded 4.5% of the citations it exists to police. Also `feedback_bad_news_vs_no_news`: an unchecked citation and a valid one both report nothing.

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** OI-209 closed as a duplicate of this entry. Its census, re-measured 2026-09-26 by simulating the gate regex: **39** bare single-number `line_range` entries (was 30); of the 28 that name a symbol, **21** would go stale if bare-N were parsed (OI-209 said 15); 11 are prose. Related blind spot found the same day — see OI-207's UPDATE: `method: a / b / c` fails `_bareSymbolRe` and is prose-skipped entirely (417 of 663 dash-form entries).
## OI-184 — 4 tables rely on RLS-zero-policy default-deny alone; the raw grants under it were never narrowed (P2, systemic, pre-existing)

- **Status**: OPEN
- **Blocked on**: none — mechanically straightforward (a `REVOKE` batch), but
  sized as its own reviewed unit (4 live tables, needs the same live
  before/after ACL diff discipline this batch used for migration 130), not a
  drive-by edit inside slice 4.
- **Verified**: 2026-09-11 — LIVE, via the Management API (read-only queries,
  no DDL): for all 4 tables, `pg_class.relrowsecurity = true`,
  `count(*) from pg_policies = 0`, and `has_table_privilege('anon'|
  'authenticated', <table>, 'SELECT'|'INSERT'|'UPDATE'|'DELETE'|'TRUNCATE')`
  all return `true`. Re-derive with the query in "Proposed repair" below
  rather than trusting this snapshot.
- **What**: `usage_counters`, `account_deletion_log`, `admin_metrics_daily`,
  and `cron_call_log` each have RLS ENABLED with ZERO policies — Postgres's
  implicit default-deny is CURRENTLY the only thing stopping `anon`/
  `authenticated` from reading/writing them, because all 4 ALSO hold full
  raw table-level grants (SELECT/INSERT/UPDATE/DELETE/TRUNCATE) for both
  roles. Two of the four are more precisely wrong than "pre-existing since
  128": `admin_metrics_daily`'s OWN creating migration
  (`102_admin_metrics_daily_snapshot.sql:54-55`) explicitly ran
  `revoke all on public.admin_metrics_daily from public; grant select,
  insert, update on public.admin_metrics_daily to service_role;` — but live
  state shows the narrowing did not take: `anon`/`authenticated` hold full
  CRUD anyway. This is the exact class `feedback_revoke_from_public_not_role.md`
  names: revoking from the PUBLIC pseudo-role does not touch a privilege a
  named role (`anon`/`authenticated`) holds directly (Supabase's platform
  provisioning grants broadly to those roles at schema level, not through
  PUBLIC) — the same trap diagnose a9d3f1 documents for function EXECUTE,
  here on tables. That same migration's comment (`102:45-48`) also called
  `account_deletion_log` "the documented exception" with RLS NOT enabled —
  but live state shows RLS IS enabled on it. No migration file anywhere runs
  `ENABLE ROW LEVEL SECURITY` on either `account_deletion_log` or
  `cron_call_log` (checked: `grep -rin "row level security"
  supabase/migrations/*.sql` returns zero hits naming either) — RLS on both
  was turned on by an action this repo's migration history does not trace,
  which is itself worth noting independent of the grants question.
- **Consequence**: SAFE TODAY (RLS's default-deny blocks SELECT/INSERT/
  UPDATE/DELETE for any non-`rolbypassrls` role) but fragile on two axes:
  (1) it would weaken the instant any future policy is added to any of
  these 4 tables for an unrelated reason — a narrow, well-intentioned
  own-row policy for one command opens exactly that command up to the FULL
  breadth the un-narrowed grant allows, with no narrower backstop behind it,
  because the raw grant was never reduced to match the intended access
  pattern; (2) RLS does not cover `TRUNCATE` at all in Postgres, and all 4
  tables grant it to `anon`/`authenticated` directly. (2) is NOT reachable
  through the app's actual client surface today — PostgREST's REST API
  exposes only SELECT/INSERT/UPDATE/DELETE verbs, never TRUNCATE — so this
  requires a direct Postgres wire-protocol connection under one of these
  roles, which the app's clients do not have; noted as excess privilege
  worth closing, not as a live exploit path.
- **Surfaced by**: Hermes L2 (findings 2 + 6), OI-162 slice 4 hermes-pass,
  2026-09-11 — while investigating `usage_counters`' own RLS-zero-policy
  posture for migration 130's B-pass. The compacted summary this session
  inherited named these same 4 tables and this same shape from EARLIER
  session work; re-verified live rather than trusted, because the earlier
  claim turned out to need correction on exactly the two points above
  (migration 102's own narrowing attempt, and account_deletion_log's RLS
  provenance) that a memory-only citation would have missed.
- **Proposed repair**: mirror migration 130's own pattern — for each table,
  `REVOKE ALL ON <table> FROM anon, authenticated;` (naming the ROLES
  directly, not `PUBLIC` — the exact fix `feedback_revoke_from_public_not_role.md`
  prescribes), keeping `service_role`'s grant. Re-verify live before/after
  via the query in "Verified" above (same discipline as this batch's
  `test/sql/oi162_slice4_quota_boundary_and_acl_live_verify.sql` Part B).
  Not done here: 4 tables × before/after ACL diff × its own B-pass is a
  properly separable unit, not a drive-by inside slice 4's delete-account/
  verify-payment scope.
- **Blast radius**: `supabase/migrations/**` — platform tier (live grants on
  4 tables, one of them, `usage_counters`, load-bearing for two rate limits
  this batch just shipped).
- **Related**: OI-162 (parent), diagnose a9d3f1 (the function-EXECUTE
  sibling of this same class), `feedback_revoke_from_public_not_role.md`.

## OI-185 — `check_schema_column_refs.dart` validates only the FIRST line of a multi-line insert/update map (P2, gate gap, pre-existing)

- **Status**: OPEN
- **Blocked on**: none — carried out of OI-162 (closed 2026-09-12), where it rode as the
  "paired gate finding INFRA-14" of the 2026-09-02 tech-debt audit and was never in any slice's scope.
- **Verified**: 2026-09-03 — by the audit (a prototype run) and by the gate's own header; NOT re-run
  since. Re-measure before designing.
- **What**: the gate's SCOPE/LIMITS header says it validates insert()/update()/upsert() map-literal keys
  for "single-line + first line of multi-line maps". `.insert({` puts every key from line 2 onward, so
  most of every multi-line insert map is unchecked. It ran clean (`840 references validated; 0 drift`)
  while `delete-account` inserted two columns that do not exist (`prompt_snippet`, `response_snippet`,
  OI-162) — the gate's own header calls this class "invisible BY CONSTRUCTION" and it closed only the
  single-line half.
- **Why not a one-liner**: a naive balanced-brace extension measured **12** violations of which **10**
  were keys of nested JSONB value objects (`ai-proxy` `metadata: { date, channel, model, is_pro }`,
  `rolling-context`, `daily-snapshot`, `proactive-coach-promotion`). The fix needs brace-depth-1-only key
  validation, plus ES6 **shorthand** keys (`.insert({ user_id, embedding, content })` currently
  contributes zero checked refs). It can never see the NOT NULL half (the snapshot stores column
  names only) — a Deno test asserting `error === null` is the acceptance evidence for that half.
- **Proposed repair**: extend `scripts/check_schema_column_refs.dart` key extraction to depth-1 keys of
  multi-line maps + shorthand keys; ship `--warn-only` first per §4.11, baseline, then hard-fail;
  mutation-proven per rule 24 (a planted phantom key on line 3 of a multi-line insert must redden).
- **Blast radius**: `scripts/check_*.dart` — platform tier (an enforcement script); no runtime code.
- **Related**: OI-162 (parent, closed), audit `docs/audit/2026-09-02/slice-a-plan.md` §0,
  `backups/live_schema_columns.json` (the snapshot), diagnose `f2c8d5`.

## OI-186 — the AI coach cannot replace ONE day with a different workout: the only route is a 2-step template chain that pollutes the saved-templates library, and it cannot name an exercise outside today's snapshot (P2)

- **Status**: OPEN
- ⚠ **Provenance — renumbered TWICE.** Minted as OI-177 in this branch's working tree (2026-09-10) while `origin/main` independently minted OI-177 for the live-cron/Gate-31 snapshot trigger → renumbered to OI-182; then, before this branch merged, `origin/main` independently minted OI-182 again ("the payment grace window closes before the last verify-payment retry fires", OI-162 slice 4, `0c13a144` in merge `f95cae45`) → renumbered to **OI-186** (2026-09-12). Renumbered per `check_oi_numbering_unique.dart` (gate precedent `0cb4120a`). Mapping: 177→182→186, 178→183→187, 179→184→188 — **OI-185 deliberately skipped**: the unmerged branch `oi162-close` (`3267b992`, checked out in another worktree) had already minted OI-185 for a different issue (`check_schema_column_refs.dart` multi-line map gap), so taking 185 here would have forced a third collision at THAT branch's merge; the board already tolerates gaps (OI-19/20/22). Neither renumber rewrites a pushed commit message: `20302f30` (pushed 2026-09-10, on `origin/regen-wave-unit2`) files this entry as **OI-177** — an earlier version of this bullet claimed "no pushed commit cites the old number", which was wrong for 177 and 178 (`git ls-remote --heads origin regen-wave-unit2` = `8e343151`; verified 2026-09-12) and is corrected here rather than deleted.
- **Blocked on**: founder product decision on tier (see the FREE-tier note below) — the engineering is unblocked
- **Verified**: 2026-09-10 — full census of `supabase/functions/_shared/tools/registry.ts:32-65`, **20 registered tools**, read individually. No tool takes "a date + a desired focus" and rewrites that one day. Denominator stated deliberately: an earlier pass in the same session claimed the only route was `regeneratePlanBlock(weeks:1)` and that was WRONG — it had read two of the five tool directories
- **Identified**: 2026-09-10 · founder scenario: *"today, when he woke up, he asks the coach — I'm not in the mood, so let's do a rest workout today"*, one day only, without touching a completed workout

### What DOES exist for a single day (all verified against the tool files)

| User intent | Tool | Tier | Confirmation |
|---|---|---|---|
| rest / skip today | `pausePlan(startDate, days:1)` → `status='paused'`, row preserved | **PRO** | destructive |
| shorten today | `shortenWorkout(minutes)` — keeps compounds, drops accessories | **FREE** | trivial |
| move today elsewhere | `rescheduleWeek(daysAvailable)` — non-fitting workouts DROPPED | PRO | destructive |
| bodyweight/no-gym today | `generateHotelWorkout(days:1)` | PRO | destructive |
| put a SAVED template on today | `scheduleTemplate(templateId, dates:[today])` | PRO | destructive |

All honour the completed guard already — `pausePlan` *"Already-completed workouts are NOT paused (skipped silently)"*; `scheduleTemplate` *"Already-completed dates are silently skipped — history is never overwritten"*; `generateHotelWorkout` *"completed workouts are preserved"*.

### The actual gap, precisely

"Do legs instead of push today" has exactly one route: `createCustomTemplate` → `scheduleTemplate(dates:[today])`. Three problems with it, none cosmetic:

1. **It permanently pollutes the user's library.** `createCustomTemplate` saves to `snapshot.saved_templates[]` with no ephemeral mode — a one-off mood change leaves "Legs Day" in their saved templates forever.
2. **Two `destructive` confirmation cards** for a one-day change, versus `shortenWorkout`'s single `trivial` one.
3. ⚠ **The coach cannot name an exercise it cannot already see.** `createCustomTemplate`'s `exerciseId` says *"Use the exact `exercise_id` from `snapshot.today_workout.exercises[]` OR `snapshot.custom_exercises[]`. Never invent IDs."* — and `swapExercise.ts:8-10` carries the identical constraint for `newExerciseId`. **There is no tool that searches the exercise library.** So when today is a push day, the coach structurally cannot compose a leg session: the leg exercise IDs are not in its context.

Point 3 is the load-bearing one — it means this is not merely an ergonomics gap that a new tool closes on its own. Any `replaceWorkoutDay` tool needs an ID source, so either a `searchExercises` read tool ships with it, or the replacement is generated app-side by `PlanGenerator` from a focus string (`'legs'`) rather than composed by the model. **That half is now tracked as OI-187** (which also found the write path already accepts any library ID — this is a missing READ tool, not a missing capability). **OI-186 cannot be closed without OI-187 or its option 3.**

### Tier question for the founder

`pausePlan` is **PRO**. So a FREE user saying *"I'm not in the mood, rest today"* is refused by the tier gate, while *"I only have 20 minutes"* (`shortenWorkout`, FREE) is honoured. Rule 6 says Phase 1 is always free; whether a free user may take a rest day through the coach is a product call, not a bug. Surfaced, not decided.

### Sequencing note

This gets MORE visible once OI-166 Unit 2 caps `regeneratePlanBlock` at the 4-week phase block (founder locked 2026-09-10). Today a user can abuse `regeneratePlanBlock(weeks:1)` — 7 days from today — as a blunt substitute. After the cap it is still 7 days and still wrong, so the workaround does not improve; it just stops being reachable for longer horizons.

- **Blast radius**: `supabase/functions/**` is `account`; a new tool also touches `registry.ts`, the coach prompt, and `tool_dispatcher.dart`. Needs its own live-deploy authorization per §4.3
- **Class**: not a writer/reader drift — a genuine capability gap. Related: OI-166 (regen scope), OI-175 (`rawWeek > 4` semantics)

## OI-187 — the AI coach has no read path to the 292-exercise library: the WRITE path already accepts any library ID, the model can never learn one (P2)

- **Status**: OPEN
- ⚠ **Provenance — renumbered TWICE.** Minted as OI-178 in this branch's working tree (2026-09-10) while `origin/main` independently minted OI-178 for pg_cron/alerting visibility → renumbered to OI-183; then, before this branch merged, `origin/main` independently minted OI-183 again ("`enforce_vision_analysis_daily_limit`'s channel guard is NULL-unsafe", OI-162 slice 4, `0c13a144` in merge `f95cae45`) → renumbered to **OI-187** (2026-09-12). Renumbered per `check_oi_numbering_unique.dart` (gate precedent `0cb4120a`). Mapping: 177→182→186, 178→183→187, 179→184→188 — **OI-185 deliberately skipped**: the unmerged branch `oi162-close` (`3267b992`, checked out in another worktree) had already minted OI-185 for a different issue (`check_schema_column_refs.dart` multi-line map gap), so taking 185 here would have forced a third collision at THAT branch's merge; the board already tolerates gaps (OI-19/20/22). Neither renumber rewrites a pushed commit message: `20302f30` (pushed 2026-09-10, on `origin/regen-wave-unit2`) files this entry as **OI-178**, and `5f8d6930` / `8e343151` correct it under that number — an earlier version of this bullet claimed "no pushed commit cites the old number", which was wrong for 177 and 178 (`git ls-remote --heads origin regen-wave-unit2` = `8e343151`; verified 2026-09-12) and is corrected here rather than deleted.
- **Blocked on**: nothing technical — needs a design choice between a `searchExercises` read tool and a snapshot digest (options below). Founder directed 2026-09-10: *"ai coach should have the tools whatever necessary"*
- **Verified**: 2026-09-10 — every claim below re-read against source in-session
- **Identified**: 2026-09-10 · surfaced while filing OI-186; it is the reason OI-186 cannot be closed by a `replaceWorkoutDay` tool alone

### The asymmetry, which is the whole issue

**The write path is ALREADY fully capable.** `swap_service.dart:221` — `_hive.exerciseBox.get(toExerciseId)` is a direct key lookup into the **complete** library; any of the 292 exercises resolves. (`:225-236` then falls back to `customBox`, matching on id **or name**.)

**The model can never produce a valid ID.** Verified chain:
- `assets/data/exercise_library.json` holds **292** exercises, keyed by opaque IDs — `E001` = "Barbell Bench Press"
- `seed_service.dart:185-192` — *"writes every exercise into exerciseBox keyed by its `id`"*. So the Hive key IS `E001`; a NAME does not resolve on the library branch (only on the custom branch)
- `ai_snapshot_builder.dart` — `grep -c "exercise_library"` → **0**. No library key in the snapshot at all
- its `custom_exercises` key reads `_hive.customBox` (`_readCustomExercises`) — **user-created only**, not the built-in 292
- `getFormCues` (the only library-touching read tool) resolves a NAME → cues/mistakes/muscles/difficulty/logging_type and **returns no `id`** (`getFormCues.ts:74-86`, `:101-113`). So there is no name→id recovery hop either

⇒ The tool descriptions are honest about the cage: `createCustomTemplate.ts:5-6` *"Use the exact `exercise_id` from `snapshot.today_workout.exercises[]` OR `snapshot.custom_exercises[]`. **Never invent IDs.**"*; `swapExercise.ts:8-10` identical for `newExerciseId`.

**This is a missing READ tool, not a missing capability.** Nothing in the write path needs to change.

### What it silently costs today, in production

- **`swapExercise` (live, PRO)** — its entire purpose is "swap X for something else", yet the model's only legal `newExerciseId` values are exercises **already in today's workout** (a no-op or a duplicate) or the user's own customs. For a user with no custom exercises the tool cannot make a single meaningful swap the model chose. Its `reason` field advertises *"Equipment substitute for home"*, *"Easier on the shoulder"* — neither is reachable
- **`createCustomTemplate` (live, PRO)** — can only compose from exercises visible in today's snapshot, so "build me a leg day" on a push day is structurally impossible
- **OI-186's `replaceWorkoutDay`** — blocked on this for the same reason

⚠ **UNMEASURABLE TODAY — corrected 2026-09-10, same day this entry was filed.** This row first said *"check `ai_coach_interactions` for `exercise_not_found` before designing the fix"*. **That query returns zero for a reason that has nothing to do with how often it happens**, so acting on it would have been the `bad_news_vs_no_news` collapse:
  - `tool_dispatcher.dart:281-282` catches `SwapExerciseException` and returns `ToolExecutionResult.failure(_swapExerciseErrorMessage(e))` — **no `logEvent`, no `recordNonFatal`**. The multi-swap site `:598-599` likewise only appends to a local `errors` list.
  - The generic `logEvent('tool_dispatch_..._unexpected_failure')` at `:227-235` lives in `dispatch()`'s defensive catch and fires ONLY for errors no handler caught — a HANDLED `SwapExerciseException` never reaches it.
  - `ai_coach_interactions` is chat history + `channel='app_event'` rows (`app_events_service.dart:60`), not tool outcomes.
  ⇒ `exercise_not_found` reaches **no telemetry sink at all**. Its frequency is currently unknowable, and **"no reports" must not be read as "not happening"**. Any fix for this OI should add telemetry to the swap failure path in the same commit, or the prevalence question stays permanently unanswerable. Related class: `feedback_observability_silent_drop`.

### Options

1. **`searchExercises` read tool** — `(query|muscle_group|equipment) → [{id, name, equipment, muscles}]`, capped ~20 rows. Mirrors `getFormCues`'s existing `exercise_library` Postgres query, so the seam is proven. FREE tier (a read). Composes with every write tool above, including OI-186's.
2. **Library digest in the snapshot** — all 292 as `id|name|equipment` costs real tokens on EVERY message, for a need that arises rarely. Rejected on cost unless filtered by the user's equipment.
3. **App-side generation from a focus string** — `replaceWorkoutDay(date, focus:'legs')` hands off to `PlanGenerator`, which already queries the library (rule 8). Solves OI-186 without giving the model IDs, but does NOT fix `swapExercise` or `createCustomTemplate`.

**Recommendation: option 1**, because it is the only one that fixes all three call sites. Option 3 remains worth doing for OI-186's generate-a-day case — they are complementary, not alternatives.

- **Blast radius**: `supabase/functions/**` = `account`. New tool = `registry.ts` + the tool file + coach prompt + `zodToGemini` shape; a read tool needs no `tool_dispatcher.dart` write branch. Live deploy needs its own authorization per §4.3
- **Class**: capability gap + **`feedback_bad_news_vs_no_news`** — a tool that cannot express the request and one that expresses it badly are indistinguishable from the transcript, which is why this survived 20 shipped tools unnoticed
- **Related**: OI-186 (blocked on this), OI-166 (regen scope)

## OI-188 — no re-entry path for a returning user: the free path hands them a DELOAD at their full pre-absence load, and the PRO ramp-back is an order of magnitude too slow (P1)

- **Status**: OPEN
- ⚠ **Provenance — renumbered TWICE.** Minted as OI-179 in this branch's working tree (2026-09-10) while `origin/main` independently minted OI-179 for the `alert_cron_function_dead` coverage gap → renumbered to OI-184; then, before this branch merged, `origin/main` independently minted OI-184 again ("4 tables rely on RLS-zero-policy default-deny alone", OI-162 slice 4, `0c13a144` in merge `f95cae45`) → renumbered to **OI-188** (2026-09-12). Renumbered per `check_oi_numbering_unique.dart` (gate precedent `0cb4120a`). Mapping: 177→182→186, 178→183→187, 179→184→188 — **OI-185 deliberately skipped**: the unmerged branch `oi162-close` (`3267b992`, checked out in another worktree) had already minted OI-185 for a different issue (`check_schema_column_refs.dart` multi-line map gap), so taking 185 here would have forced a third collision at THAT branch's merge; the board already tolerates gaps (OI-19/20/22). Unlike its two siblings, no commit message on this branch ever cited OI-179 — it was filed in the working tree only (`git log main..HEAD` grep, verified 2026-09-12).
- **Blocked on**: founder product decision on the absence-length branch table (§ "Recommended shape" in the research doc). The engineering is unblocked once that is picked
- **Verified**: 2026-09-10 — app behaviour read from source by the main thread; external research graded and recorded at `docs/research/returning-user-reentry.md`. ⚠️ Defects 2, 3 and 4 were **corrected the same day** by plan-review round 3 (F4): defect 3 cited default-OFF code and pointed the wrong way, and the decay turns out to be unreachable for free users. Read the per-defect correction notes, not the original wording
- **Identified**: 2026-09-10 · founder brainstorm: *"a pro user completes phase one, then he's missing for six weeks, then he comes back"*

### Why this is P1 and not a nice-to-have

The evidence-backed risk on return is **injury, not lost gains** — CSCCa/NSCA cite NCCSIR data that *"almost 60% of non-contact injuries occur during these periods in which the athlete is transitioning back into training following a period of inactivity."* We currently have no re-entry concept at all.

**And the market is empty.** Of 21 apps checked, exactly ONE (StrongLifts) has a documented automatic return-after-absence adjustment; two ask the user; the rest do nothing. This is an open goal, not catch-up.

### Four defects in what ships today (all main-thread verified)

1. ⚠️ **The LIVE free-user return path prescribes a DELOAD — but the fix is already WRITTEN and sitting behind a flag.** *(Corrected 2026-09-10 after founder caught the original wording: "we were repeating week 3 and not week 4, check". They were right.)*
   - **LIVE:** `holdWeeksEnabled` defaults **false** (`plan_engine_flags.dart:63-69`), so a returning free user gets **`redoWeek4`**, which sources `week4Start = planEnd - 6d` (`workout_schedule_write_service.dart:183`) — the TRAILING week of the window, i.e. the deload week on a clean 28-day phase. Coleman et al. 2024: an *unnecessary* deload in trained lifters *"appears to negatively influence measures of lower body muscle strength."* They have already had a forced deload; we give them another.
   - **ALREADY BUILT, ship-dark:** `holdWeek` (`:266-270`) sources `planStart + 14..20` = **week 3 (PEAK)**, dropping to `+21..27` (deload) only on **every 4th hold** — so a long-term holder keeps the wave rhythm peak/peak/peak/deload instead of deloading forever. Its own comment names the live behaviour as the defect: *"NEVER plan_end-derived (redoWeek4's bug was copying the trailing deload week every time)"*.
   - ⇒ **This defect's remedy is OI-60's flag flip, NOT new engineering.** Scope this OI to the three defects below, and treat item 1 as one more argument for OI-60. Anyone planning work here should read `holdWeek` before designing anything — the smarter rule already exists.
2. **The decay cuts the quality they RETAINED — and for a FREE user it never fires at all.** `lib/core/utils/detraining.dart` scales **weight** (≤7d 1.0 · 8-21d 0.925 · 22-35d 0.825 · >35d **0.50**). But Bosquet 2013 (103 studies) puts work capacity worst (SMD −0.62) and peak power best-retained (−0.20); Bjørnsen 2019 finds ~60% of strength gain retained at 20 weeks. **What they lost is volume tolerance, not load.** Points at cutting sets/frequency rather than weight.
   - ⚠️ **Scope, corrected 2026-09-10 (round 3):** `detrainingDecayEnabled` is default ON, but **both** call sites are closed to a free user. ⑦(a) lives inside `ProgressionResolver.resolve()`, which returns `{}` for `phase <= 1` (`progression_resolver.dart:55`); ⑦(b) (`train_provider.dart:1312`) is behind `sessionDetrainingCutEnabled`, default OFF. A free user is on phase 1 by definition (rule 6 / rule 19 gate `phases_2_to_12`).
   - ⇒ **The returning FREE user is prescribed their exact pre-absence load, undecayed** — on top of the deload-week copy `redoWeek4` hands them (defect 1). Two independently wrong things in the one path most returning users are on. The decay debate above is a **PRO-only** question until ⑦(b) flips.
3. ⚠️ **The ramp-back is far too SLOW, and the plan-suggested weight is constant within a phase.** *(Corrected 2026-09-10 by plan-review round 3 finding F4. The original entry claimed the ramp was performance-gated and returned users to full load in 3-4 weeks, citing `progression_resolver.dart:307`/`:318`. **Both citations are inside `_gradedSuggestion`, called only under `gradedProgressionEnabled` (`:61`, `:189`), which is default FALSE** — so "beginners are on the unconditional ramp" was false in production, and the arithmetic assumed a per-session ramp that does not exist. The hazard is the opposite of the one filed.)*
   - **What ships** is the fixed rule at `progression_resolver.dart:203-215`: reps ≥10 → `base + 5.0` (lower) / `+2.5` (upper); ≥5 → hold; <5 → back off.
   - **It runs once per PHASE, not per session.** `resolve()` has exactly one caller (`plan_generator.dart:235`) and returns `{}` for `phase <= 1`. Its output becomes `suggestedWeight`, applied **identically to every week** of the phase (`periodization_engine.dart:112-115`); the wave varies sets and reps, never weight (`_waveReps`, `:262`).
   - ⇒ From a −50% cut, the plan's suggested weight recovers at **+2.5–5 kg per 4-week phase** — roughly **10 phases** to undo a 100 kg → 50 kg cut. A returning user is left with a suggestion far below what they can lift, for months, so they override it manually and the prescription becomes noise.
   - The time-gating argument still holds on the evidence (Kubo 2012: tendon stiffness ~3 months to build, **1 month to lose**, so a strong first session is not readiness — ⚠️ n=9, one tendon, isometric, the only direct human time-course data found). But it argues for a **deliberate, bounded re-entry ramp**, not for slowing down a ramp that is already an order of magnitude too slow.
4. **Half the feature is switched off, so for a PRO user the two halves disagree in production.** `sessionDetrainingCutEnabled` defaults **false** (`plan_engine_flags.dart:110-120`). On phase ≥2 generation prescribes −50%; the active-workout screen then prefills the **old undecayed** last-logged weight, with no welcome-back banner and no explanation. The user sees two different numbers and no reason for either. ⚠️ Per defect 2's scope correction this disagreement is **PRO-only** — on phase 1 neither half decays, so they agree, wrongly.

⚠️ **CORRECTED 2026-09-16 (OI-53 batch 2) — the premises of defects 2, 3 and 4 above all changed under this OI**, discovered while flipping four unrelated flags and re-grepping every live reference to their old key names before landing. `sessionDetrainingCutEnabled` and `gradedProgressionEnabled` both flipped from default-OFF to default-ON (kill-switches `disable_session_detraining_cut` / `disable_graded_progression`). Read each correction below against the CURRENT code, not the defect text above it, which now describes the PRE-flip state:
- **Defect 2's "for a FREE user it never fires at all" is now FALSE.** `ActiveWorkoutNotifier.startWorkout` (`train_provider.dart:1320-1334`) applies ⑦(b) unconditionally on the flag — there is no phase or tier check anywhere near it — so a free (phase-1) user now gets the session-prefill cut too. This does not touch ⑦(a) (`ProgressionResolver.resolve()` still returns `{}` for `phase<=1`), so it does not "fix" the free-user decay gap this defect was filed against; it changes WHICH half a free user gets.
- **Defect 3's "beginners are on the unconditional ramp is false … `gradedProgressionEnabled` … is default FALSE" is now FALSE.** The flag is default TRUE, so the ORIGINAL claim round 3 was correcting — "beginners are on the unconditional ramp" — is TRUE again in production (`ProgressionResolver`'s beginner auto-linear window, `training-age < 120d`, always progresses regardless of rep-range). **This needs its own re-verification, not an inference from this note** — round 3's correction may have found other reasons the original hazard was overstated beyond the flag's default; nobody has re-checked those since. Flagged here so the next reader does not carry forward a "corrected" verdict whose load-bearing premise no longer holds.
- **Defect 4's "the two halves disagree… PRO-only… on phase 1 neither half decays, so they agree, wrongly" is now FALSE in the OPPOSITE direction.** For phase ≥2 the two halves now AGREE (both decay) — the defect as originally filed is resolved there. But phase 1 flips from "neither decays" to "⑦(b) decays, ⑦(a) doesn't" (⑦(a) is phase-gated at `phase<=1`; ⑦(b) is not) — a NEW disagreement, inverted, and still live. Nothing in OI-53 batch 2 touched ⑦(a)'s phase gate; this is a byproduct of ⑦(b) alone moving.
This is reported as-is, not resolved — the underlying re-entry/detraining PRODUCT design is explicitly `Blocked on: founder product decision` above, and a 4-flag ship-dark batch is not the place to redesign it.

### The unsettled part, stated so nobody re-litigates it

**Do NOT pick a load-reduction percentage.** Published guidance spans **10% to 60%** for overlapping scenarios with no experiment adjudicating — the single most confident "not settled" finding in the research. The recommendation is to **re-baseline from what the user actually logs** in the first sessions back. Our flat −50% sits at the aggressive end of a range nobody has validated.

### Constraints to honour

- **Never gate the re-entry ramp behind PRO.** It is a safety feature; no app was found paywalling one. Gate depth (AI re-planning, analytics), never the lighter first week.
- **Forgive, don't reset, and say so BEFORE they lapse.** Silverman & Barasch 2023 (*JCR* 49(6), seven studies): a broken streak's demotivating effect is **amplified when users blame themselves** and **attenuated when the streak can be repaired**.
- **Calibrate the ceremony down.** ~5% of lapsed users resurrect after 30+ days and retain ~20% worse than new users (Duolingo, published). A warm card and a good first session beats an elaborate re-onboarding flow.
- **Copy should name work capacity, not strength** — it is what they will actually feel, and it pre-empts the "I lost everything" misread that causes the second quit.
- **Never diagnose without prescribing** (Garmin's anti-pattern: labels *"your fitness level is decreasing"*, offers no action).
- ⚠️ **Do not cite the "88% of lapsed users feel shame — UCL 2025" statistic.** The press release was read directly; **the figure is not in the study**.

### Relationship to OI-166 Unit 2

Unit 2's blocked question — what a regeneration does when the plan window is EXTENDED (`redoWeek4`/hold) or EXPIRED — is really this issue wearing a different hat. Unit 2 now bounds its writes at `plan_start + 27d` and **leaves out-of-phase state on its current behaviour**, so it introduces no regression and this OI owns the improvement. Neither blocks the other.

- **Blast radius**: `lib/shared/repositories/plan_engine/**` is `platform` (`docs/blast_radius.yaml:67`); touching `progression_resolver.dart` or the decay bands lands there ⇒ `feature_flag` + `bpass: accepted`
- **Full research record**: `docs/research/returning-user-reentry.md` — 21-app table with per-row evidence grading, detraining timelines, UX patterns with verbatim copy, and an explicit list of what the evidence does NOT settle
- **Related**: OI-166 (regen scope), OI-60 (hold-weeks flip — hold weeks are the *other* answer to the same moment and are still OFF), OI-53 (ship-dark flag flips, incl. `sessionDetrainingCutEnabled`)
## OI-190 — Unit 1's §4.11 gate `check_single_schedule_row_builder.dart` is WARN-only past its window because the shared builder it guards was never built: the 2026-09-07 "one implementation" decision has no owner (P2, process/gate)

- **Status**: OPEN
- **Blocked on**: none — needs a plan. Input is already written: `docs/audit/oi166-regen-implementation-inventory.md` (the B-vs-C divergence table, with a 2026-09-11 note that its B citations shifted +42..+49 after Unit 2 — re-grep symbols, do not cite its numbers).
- **Verified**: 2026-09-12 — `dart run scripts/check_single_schedule_row_builder.dart` on `main` @ `de52f1e8` prints `PASS: 479 lib/ file(s) scanned … (2 pending OI-166 Unit 2 migration)`; `_hardFail = false` at `:39`; `lib/core/services/schedule_row_builder.dart` (allowlisted as "created by OI-166 Unit 2") does not exist; the two `pendingUnit2` exemptions are `workout_schedule_read_service.dart` (A+B) and `regenerate_plan_planner.dart` (C).
- **Identified**: 2026-09-12 · post-ship audit of Unit 2, by the founder's question *"did we face any discipline gaps?"*
- **What happened**: Unit 1 (`4282a4e8`, 2026-09-08) shipped this gate per §4.11 ("gate lives BEFORE the first refactor commit; WARN-only to baseline; then flips to hard-fail"), with its header asserting *"OI-166 Unit 2's final commit flips it to `true`, at which point every `pendingUnit2` allowlist entry must already be gone."* Unit 2's round-1 review then found the shared builder as specified could not express what caller C already does; the re-plan (v4→v10) fixed B and C **in place, deliberately unconverged** — and nobody carried the consequence back to the gate or to the board. The 24-hour baseline window §4.11 names has been open since 2026-09-08. The de-duplication survived only as a prose banner in the inventory doc: *"still owed"*. Prose is where owed work goes to decay (§4.13 point 6: *"everything with a gate holds, everything on intention decays"*).
- **What the gate is doing today**: it still guards against a THIRD implementation of a schedule-row constructor appearing in `lib/` (its allowlist is pinned by `schedule_row_builder_gate_lib_test.dart`), which is real value — but in WARN mode inside `pre-commit.sh` (every gate runs `>/dev/null 2>&1`) a violation prints nothing locally; only CI would show it. Its header and the allowlist comment describe a Unit 2 that did not happen.
- **Fix, in order**: (1) this batch corrects the gate's header + allowlist comment to say the truth and point here (`docs`-tier edit, no logic change); (2) a planned unit builds `schedule_row_builder.dart` from the inventory, migrates A/B/C onto it, removes both `pendingUnit2` entries, flips `_hardFail = true` in the SAME commit (the gate's own header describes this sequence), and decides OI-189's horizon once for both writers; (3) that unit's ×2 review must re-read THIS entry and OI-189 as inputs — the way Q7 was lost is the way this would be lost.
- **Rule this should leave behind** (proposed for §4.11, not yet written into CLAUDE.md): a WARN-only gate is born with an OI naming its flip condition and owner, so the flip cannot be dropped by a re-plan that changes scope.
- **Blast radius**: the de-dup touches `lib/core/services/**` (account) and `lib/features/ai_coach/**` (account); the gate script is feature-tier by path.
- **Related**: OI-166 (parent), OI-189 (CLOSED 2026-09-13 — the horizon rule is decided: every writer stops at the stored `plan_end` and every regen sweeps past it; the unified builder must carry the same bound AND the same sweep), OI-174, OI-176 (the other OI-166-batch gate with a known blind spot).
- **Input added 2026-09-13 by OI-189's review (round 2 F12 + round 4 F7)** — the coach card's copy for the BOUNDED regen case is authored outside the diff preview and is wrong in two places, to be decided ONCE here: (1) the confirm card's summary line is EF-authored — `supabase/functions/_shared/tools/plan/regeneratePlanBlock.ts:54` `previewSummary` says "Regenerate next N weeks" and `:5-6,42` tells the model "1-12 weeks … start a new phase", both contradicting a block the client bounds at `plan_end` (catastrophic-tier deploy; a client-side substitution would not rebuild when the planner cache fills, because `tool_confirm_card.dart:307` renders before the diff widget's async `plan()`); (2) `tool_confirm_card.dart:409-410` `_executedMessage` says "Plan regenerated" for a sweep-only success (`count: 0, cleared: N`) — it keys on the intent TYPE and never sees `data`; carrying the result to the card needs a `ToolIntent` field.

## OI-191 — target_weight_kg can contradict the chosen goal's direction, making the reach-your-goal projection false (P2)

- **Status**: OPEN
- **Blocked on**: none — bounded, no schema/migration/payment/auth involvement
- **Verified**: 2026-09-13 — reproduced live on the newly-created Play Store review account
  (`googleplay-review@icanbefitter.com`, `public.user_profile`: `current_weight_kg=75`,
  `target_weight_kg=71`, `primary_goal='build_muscle'`) and confirmed by reading all 4 files
  below directly, not from a subagent summary.
- **Identified**: 2026-09-13 · founder noticed the account's own goal/target combo looked
  backwards while spot-checking the onboarding flow, asked "goal is also to reduce weight
  right? check."
- **What**: two writers save `target_weight_kg` with zero cross-field validation against
  `primary_goal`:
  - `lib/features/onboarding/screens/stats_screen.dart` `_onCalibrate` (~line 387-424) —
    seeds the field goal-aware (`build_muscle` → current+3kg, `lose_fat` → current-5kg,
    `recomp` → current-2kg; the comment at line 42-46 spells this out), but it's a free
    `TextEditingController` and the submit handler validates only that weight/height parse
    as numbers. A user can overwrite the sensible seed with anything.
  - `lib/features/profile/screens/edit_profile_screen.dart` (`target_weight_kg` write at
    line 1825) — same gap, second door: a user can set a sensible target during onboarding,
    then contradict it later via Edit Profile with no warning either.

  Three independent render sites then trust the raw, unvalidated pair and produce an actively
  false projection when goal-direction and target-direction disagree:
  `lib/features/profile/screens/profile/nutrition_targets.dart:15-31`,
  `lib/features/nutrition/screens/nutrition_screen.dart:520-548` (`_projectionLine`),
  `lib/features/profile/screens/profile/pace_detail_sheet.dart:5-13` — all three gate on
  `goal ∈ {lose_fat, build_muscle}` + both weights present + gap > 0.1kg, then call
  `BmrCalculator.projectGoalDate` (`lib/core/utils/bmr_calculator.dart:258-288`), which computes
  `gap = (currentKg - targetKg).abs()` — an **unsigned magnitude**, blind to which direction the
  diet is actually pushing the user.
- **What this does NOT affect**: the calorie/macro numbers themselves. Checked
  `BmrCalculator.calculateTargets` specifically — for `goal == 'build_muscle'`,
  `target_weight_kg` is never read at all; it's consulted only inside the `goal == 'lose_fat'`
  branch, to pick the protein baseline. So a contradictory target doesn't corrupt the diet
  prescription, only the projection text describing it.
- **Consequence**: a user on a `build_muscle` surplus (weight trending up) with a target below
  current sees "At this pace, you'll reach 71 kg on \<date\>" — a promise the prescribed diet
  cannot keep, since the diet is moving them the opposite direction. Symmetric failure exists
  for `lose_fat` + a target set above current. Not hypothetical to this one test account: any
  real user who mistypes or misunderstands the target-weight field the same way hits the
  identical wrong message.
- **Bug-history check**: grepped `docs/diagnoses/INDEX.md` + `open_issues.md` +
  `closed_issues.md` for `projectGoalDate` / target-goal direction conflicts — no hits. Not a
  recurrence of the existing onboarding-calc-drift class (c3f2d8/f1b6d4/f19a7c/c7a1f5), which are
  all preview-vs-commit or missing-input bugs, not a direction contradiction.
- **Fix shape (not decided, sketched for whoever picks it up)**: (a) validate at both writers —
  block or auto-correct a contradictory target before save; needs enforcing at TWO sites, and a
  third if any other writer of this field is found; or (b) make `projectGoalDate` (or its 3
  call sites) direction-aware — suppress or reword the projection when direction disagrees with
  goal, so a bad input degrades gracefully instead of lying. (b) is a single-point fix versus
  (a)'s multi-writer enforcement, but is a genuine design call, not decided here.
- **Blast radius**: `feature` — UI/calc-only, no schema/migration/payment/auth/sync path
  touched (per `docs/blast_radius.yaml`'s account-tier trigger list, none apply).
- **Related**: none of the existing calorie-drift diagnoses; found while investigating a
  founder observation on the same test account that also produced
  [[feedback_mistake_subscription_status_vs_subscriptions_table]] (unrelated mechanism, same
  investigation session).

## OI-192 — the orphan-sync dedupe can never match a photo turn: client writes `[Photo] …`, server writes `[Photo: image] …`, so every media exchange upserts a phantom `in_app_orphan` duplicate (P2)

- **Status**: OPEN
- **Blocked on**: none — pick ONE placeholder shape (or skip `mode == 'media'` rows in the orphan path, which is what `recentHistoryExchanges` already does for replay)
- **Verified**: 2026-09-13 — source only: `lib/features/ai_coach/providers/ai_coach_provider.dart` `sendWithMedia` writes `userMessage: '[Photo] $captionForLog'` (`:625`) with a `coach_<ms>` id (NOT a uuid — `coach_interaction_repository.dart` `saveUserMessagePending`, `'id': id` where `id = mintCoachKey()`); `supabase/functions/ai-media-proxy/index.ts` writes the server row as `` `[Photo: ${media_type ?? "image"}] ${message}` `` (`:598`, `:868`). The live count of `in_app_orphan` rows starting `[Photo` was measured 2026-09-13 (after the 06:54–07:10 IST DB-starvation episode that had timed out the first three attempts): **0** orphan photo rows AND **0** server-authored `[Photo:` rows exist in `ai_coach_interactions` — and 0 rows of ANY `[Photo`-prefixed shape, in a table whose oldest retained row is 2026-05-11 — so the defect is LATENT: no photo turn has left a row in this table's retained history (`rolling-context` prunes it nightly, so absence is not proof none was ever made), and the phantom appears on the first PRO photo turn that survives to a sync. Re-run `select count(*) from ai_coach_interactions where channel = 'in_app_orphan' and user_message like '[Photo%'` before fixing; a non-zero count means the double-count is already in `founder_metrics_engagement()`.
- **Mechanism**: `lib/core/services/sync/sync_coach.dart` `_syncCoachInteractions` skips a row only when its `id` looks like a uuid (the server-authored case) or when a server row with the SAME `user_message` exists within 5 minutes (`.eq('user_message', userMsg)`, the audit-2026-05-16 F6-4 cross-channel dedupe). A media row fails both: its id is `coach_<ms>`, and its `user_message` differs from the server's by the `: image` infix — so the dedupe SELECT returns nothing and the row is upserted under `channel: 'in_app_orphan'` with the analysis as `ai_response`. That is the P2-B "phantom duplicate" class (audit 2026-05-12, 81 phantom rows) re-opened for exactly one message shape. Consequence: interaction analytics (`founder_metrics_engagement()`, migration 120, counts `in_app_orphan` as chat) double-count every photo turn; `recentHistoryExchanges` is NOT affected (it drops `mode == 'media'` rows locally, and the restored orphan carries channel `in_app_orphan`, which is in `_coachChatChannels`, so a RESTORED phantom WOULD be replayed as a prior chat turn — a second-order effect worth checking on a fresh install).
- **Repair options**: (a) make the client write the server's exact shape (`[Photo: image] …`) — one literal, but couples two writers on a format string; (b) skip `mode == 'media'` rows in `_syncCoachInteractions` outright — the server row already exists for every media turn (the media proxy inserts BEFORE Gemini), so the orphan path has nothing to add; **lean (b)**, mirroring the replay filter. Regression test: extend `test/contracts/` sync-coach coverage with a media row fixture asserting no upsert.
- **Blast radius**: `lib/core/services/sync/**` — account (sync); no schema, no EF.
- **Related**: OI-153 (found while tracing every writer of `[Photo`-shaped rows for the PRO cap work), the audit-2026-05-12 P2-B entry (same class).

## OI-193 — Gate 31 treats a COMMENTED `cron.unschedule('X')` as a real unschedule, so nine migrations' rollback blocks silently drop their own job from the registry check (P2, gate gap)

- **Status**: OPEN
- **Blocked on**: none — strip `--` comments before the unschedule scan (the same `stripSqlComments` `test/helpers/migration_cap_reader.dart` already has), then re-baseline
- **Verified**: 2026-09-12 — `scripts/check_cron_registry.dart` `unschedulePattern` (`cron\.unschedule\s*\(\s*['"]([^'"]+)['"]`) runs over the RAW file content with no comment stripping; `grep -ln "^--.*cron\.unschedule('" supabase/migrations/*.sql` → **9** files whose inline-rollback comment names a job (076, 077, 086, 087, 102, 109, 110, 121, 128 — the OI-153 plan's "ten" was a miscount, corrected here by re-running the grep); and the SECOND shape, measured the same way: **16** migrations mention `cron.unschedule('…')` at all, **11** of them UNCOMMENTED (015, 028, 031, 040, 046, 061, 069, 077, 086, 087, 102) — genuine unschedule-then-re-schedule sequences (102's `perform cron.unschedule(...)` DO-block guard before its `cron.schedule` is the clearest). The gate computes `scheduled − unscheduled` as SETS with no ordering, so every job that was ever re-scheduled under its own name (`morning_alert_generate`, `compute_coach_signals`, the alert crons, …) is ALSO absent from input A today. Comment-stripping closes the 9-file shape; "last-wins by POSITION" (a `cron.schedule` after a `cron.unschedule` of the same name, in file order across the numbered sequence, re-activates the job) closes the 11-file shape. Input B is the only thing covering either right now
- **What**: input A of Gate 31 is "scheduled − unscheduled (last-wins)". A migration that schedules `X` and, per the migration-header convention, carries `-- SELECT cron.unschedule('X');` in its commented rollback block therefore contributes `X` to BOTH sets, and `X` drops out of `activeJobs`. The registry row for `X` is then never demanded by input A. Input B (the live-cron snapshot, `backups/live_cron_jobs.json`) still catches it — as long as the snapshot is fresh, which OI-177 says it is not guaranteed to be. So the two inputs currently cover each other's blind spot by accident: A is blind to every job whose migration documents its own rollback, B is blind to everything scheduled since the last regeneration.
- **Why it matters now**: the convention that CAUSES it is the one every migration is told to follow (`supabase/migrations/CLAUDE.md`: inline rollback = commented reverse DDL). Migration 131 (OI-153) deliberately writes its rollback as `cron.unschedule(<the job name scheduled above>)` — an unquoted placeholder — to stay visible to input A, and says so in a comment. That is a workaround, not a fix; the gate should strip comments.
- **Repair**: comment-strip before both patterns (schedule AND unschedule), add a red-path test to the gate's test file (a fixture migration with a commented unschedule must still demand a registry row), ledger entry per rule 24. Then 131's placeholder comment can become a normal quoted rollback line.
- **Blast radius**: `scripts/**` pinned platform (gate script).
- **Related**: OI-177 (input B freshness — the other half of the same coverage story), OI-132 (why input B exists).

## OI-194 — `compute_admin_metrics_daily` (jobid 30) skipped its 2026-09-11 18:15Z tick with no `cron_call_log` row while 27 other cron calls logged that day — a silent-skip class no alert covers (P2, observability)

- **Status**: OPEN
- **Blocked on**: none for the code (repair (d) below is a `_shared/cron_telemetry.ts` unit); the FLEET redeploy that makes it live in every cron function needs the founder's per-deploy go (§4.3)
- **Verified**: 2026-09-12 — `select function_name, started_at from cron_call_log where started_at >= '2026-09-11'` returned 27 rows across the other cron functions and none for `compute-admin-metrics-daily`; `cron.job_run_details` had no retained row for jobid 30 at 18:15Z and `net._http_response` retention was too short to recover the request (measured during the OI-153 plan's ground-truth pass)
- **What**: a cron tick that never reaches the Edge Function leaves no `cron_call_log` row — `logCronStart` runs INSIDE the function. `alert_edge_function_health` and `alert_cron_function_dead` (8-day window) read that table, so a job that fails to dispatch (pg_net failure, gateway timeout before the module boots, a 401 at the gateway) is invisible to both until 8 days pass. One tick was observed missing; whether it recurs is unknown because nothing records the absence.
- **SECOND INSTANCE, MECHANISM NOW MEASURED (2026-09-13, `founder_digest_daily`'s first natural
  fire)**: at 02:30:00Z three cron EFs booted together (morning-alert, pr-detection,
  founder-digest). The Supabase logs show three `POST /rest/v1/cron_call_log?select=id` at
  02:30:01 — two `201`, ONE **`504`** — and the digest's own log line at 02:30:08:
  `[cron_telemetry] start insert failed for founder-digest { message: "Gateway Timeout" }`. The
  function then ran to completion: `POST | 200 | …/founder-digest` at 02:30:20 (the message was
  delivered), yet `cron_call_log` holds NO row for that run, because `logCronStart` returned
  `null` and `logCronEnd(null, …)` is a no-op by design (`_shared/cron_telemetry.ts`: "Failures
  inside the telemetry call itself are SWALLOWED"). So the class is wider than "a tick that never
  reaches the function": **a tick whose START insert loses a race with the rest of the 02:30Z
  burst is invisible too, and the function may have succeeded.** `cron.job_run_details` for
  jobid 38 says `succeeded / 1 row` (pg_cron's view of the enqueue), `net._http_response` says
  `timed_out` at 5000 ms (pg_net's view), the function said 200 (the truth) — three records, and
  the one every alert reads is the one that is empty. The 2026-09-11 18:15Z compute-admin-metrics
  miss has the same shape available to it (18:15Z is a `*/15` slot shared with pr-detection and
  alert_edge_function_health).
- **Repair candidate (d), now the strongest**: make `logCronEnd(null, …)` INSERT a terminal row
  (`function_name, status, http_status, error_summary: 'start insert failed'`) instead of
  returning, and/or retry the start insert once after a short backoff — a run must never be
  erased by its own telemetry losing a race. `_shared/cron_telemetry.ts` is bundled into every
  cron function, so the fix reaches each one only on its next redeploy; state that in the unit.
- **Repair candidates (a)–(c), now SECONDARY** — every one of them reads `cron_call_log`, which (d) shows is lossy at the very ticks that matter: (a) the founder digest reads `cron_call_log` for yesterday and lists functions with ZERO rows against `CRON_REGISTRY.md`'s expected daily set — the digest already exists and is the cheapest place; (b) a `pg_cron`-side check joining `cron.job_run_details` (status/return_message) per job per day — needs longer `job_run_details` retention than `jrd_retention_daily` (jobid 33) keeps today; (c) the pg_net response table with a longer retention. Decide, then file the chosen one as a unit.
- **Blast radius**: `supabase/functions/founder-digest/**` (platform) for (a); `supabase/migrations/**` (platform) for (b)/(c).
- **Related**: OI-153 (the digest), OI-177 (cron snapshot freshness), the backend-CPU-starvation in-flight batch (a starved DB is one plausible cause of a missed dispatch).

## OI-196 — `morning-alert`'s Telegram sender logs the raw fetch error, whose message embeds the bot token (P2, latent)

- **Status**: OPEN
- **Blocked on**: none — one-line change in one function; ships with the next `morning-alert` redeploy
- **Verified**: 2026-09-13 — read `supabase/functions/morning-alert/index.ts` `sendTelegramMessage` (the `catch (err) { console.error(\`Telegram error for ${chatId}:\`, err); }` arm); confirmed the URL shape at the `fetch(\`https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage\`` call two lines above it
- **What**: Deno's `fetch` rejects a network-level failure with `TypeError: error sending request for url (https://api.telegram.org/bot<TOKEN>/sendMessage): …` — the request URL, token included, is INSIDE `.message`. `sendTelegramMessage` logs the error object whole, so on any DNS/TLS/connection failure the bot token lands in the Edge Function logs (retained by the platform, visible to anyone with dashboard access). A `console.error(err)` is not a leak on a 4xx/5xx (`response.ok` false takes the OTHER branch and logs Telegram's body, which never echoes the token) — only the thrown path leaks, which is why it has stayed invisible: it fires only when Telegram is unreachable.
- **Why P2 and not P0**: the token has not been observed in a log (no unreachable-Telegram incident is recorded); the audience of function logs is the founder's dashboard; and the fix is trivial. It is filed rather than fixed in OI-153 because `morning-alert` is a different function with a different blast radius (per-user PRO delivery) and OI-153 did not touch it.
- **Widened 2026-09-13 (Hermes L40)**: the SAME two lines (`:382` `console.error(\`Telegram send failed for ${chatId}:\`, errorBody)` and `:388`) also print a USER's Telegram `chatId` — a persistent identifier from `telegram_connections` — on every failure, and `:382`'s `errorBody` is unbounded. The repair must cover all three: token (never log `err`), chat id (log a user-id prefix or nothing), body (slice to 200 chars as the digest does). Fixing only the `err.name` line would fix the instance, not the class (`feedback_mistake_guard_without_its_mirror`).
- **Repair**: log `err instanceof Error ? err.name : typeof err` only — `founder-digest/index.ts` `telegramErrorSummary` is the working twin (`supabase/functions/founder-digest/index.ts`, pinned by its `index_test.ts` "carries the error NAME only" test). Redeploy `morning-alert`. Consider hoisting the guarded sender into `_shared/telegram.ts` so a third Telegram caller cannot re-introduce the shape; `supabase/functions/CLAUDE.md` carries the pitfall row.
- **Blast radius**: `supabase/functions/morning-alert/**` — platform (cron EF; PRO push + Telegram delivery).
- **Related**: OI-153 (where the class was found while writing the digest's sender).

## OI-197 — Founder observability gaps: payment-flow alerting dormant, EF auth-outage blind spot, no native-crash summary, no server-side error-rate view

- **Status**: OPEN
- **Blocked on**: none — no schema/migration/payment/auth path touched by the filing itself;
  each of the 4 items below needs its own scoped design before any code lands
- **Verified**: never — this is a gap analysis surfaced while brainstorming the Telegram
  admin-bot design (`docs/superpowers/specs/2026-09-13-telegram-admin-bot-design.md`), not a
  live-reproduced bug. Each sub-item cites where the gap lives; none has been fixed or tested.
- **Identified**: 2026-09-13 · filed via mint_oi.sh from branch `telegram-admin-bot`, per
  founder request during that brainstorm ("what are we not logging that we should be")
- **What**: four separate detection/observability gaps, each requiring new logic (not just a
  new report surface) to close:
  1. **Payment-flow alerting is effectively dormant.** The only existing check
     (`alert_payment_flow_health`, `docs/operations/CRON_REGISTRY.md` row 076) fires on "fewer
     than 3 new subscriptions in 24h" — a weak proxy for "payments are broken," not a check on
     actual Razorpay webhook/signature failures — and the registry itself already notes it is
     "effectively dormant at current scale." No alert exists for a failed/rejected webhook call.
  2. **A total Edge-Function auth outage is invisible.** `alert_edge_function_health`
     (CRON_REGISTRY row 076) computes an error RATE from `cron_call_log`, but a 401 (e.g. the
     Vault service-role-key drift class this repo has hit before) writes no row to that log at
     all — so the check's own `total >= 5` guard never matches during exactly the outage it
     exists to catch. Registry note: "Never fired once."
  3. **Native crashes (Firebase Crashlytics) aren't summarized anywhere day-to-day.** Crashlytics
     is wired client-side (with a `kIsWeb` guard, per the debugging skill's §2.37) but nothing
     pulls a daily/weekly crash count into `founder-digest` or any other founder-facing surface —
     it's fire-and-forget to Firebase's own console, which nobody routinely opens.
  4. **No server-side error-rate view.** `public.client_errors` covers client-side telemetry
     well (op_type/error_code breakdown, per the debugging skill's bug-class catalog), but there
     is no equivalent aggregated "which Edge Function is erroring most, and at what rate" view —
     only the coarse pass/fail signal `alert_edge_function_health` computes (and gap #2 shows
     that signal has its own blind spot).
- **Fix shape (not decided, sketched for whoever picks this up)**: each item needs its own
  scoped design, likely as 4 independent small batches rather than one — they don't share a
  root cause. (1) needs a real Razorpay-webhook-failure signal, not a subscription-count proxy.
  (2) needs `alert_edge_function_health`'s data source widened to see 401s specifically (or a
  parallel check keyed on gateway-level rejection, not `cron_call_log`). (3) needs a scheduled
  pull from Crashlytics (via its API, or a summary written by the client on next launch) into
  the existing digest/alerts pipeline. (4) needs either a `client_errors`-shaped server-side
  telemetry sink, or extending the alert crons' aggregate queries to break down by function.
- **Related**: found during — and referenced in — §8 ("Deferred") of
  `docs/superpowers/specs/2026-09-13-telegram-admin-bot-design.md`. The Telegram admin bot
  reports on top of what these checks already produce; it does not close any of these 4 gaps
  itself.

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** OI-234 closed as a duplicate of item 2 here (401s write no `cron_call_log` row, so `alert_edge_function_health`'s `total >= 5` guard never sees them; 0 alerts ever). Live 2026-09-26: `alert_edge_function_health`, `alert_payment_flow_health`, `alert_cron_silence` and `alert_cron_function_dead` have fired 0 alerts between them.

## OI-199 — cleanup_cron_call_log() spares only TWO global rows, not each function's latest — true >7d cron silence still goes invisible to /cron

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-14, live read of the function body — corrected same
  day (R2-06/R2-07, review round 2) to cite migration **110**
  (`110_cron_silence_per_function_and_cleanup_null_guard.sql:30-47`), the
  LAST `CREATE OR REPLACE` and therefore the LIVE definition — the original
  filing below quoted the SUPERSEDED migration 109 body (one spared row);
  110 already widened that to two, and this OI's core finding (still not
  PER-FUNCTION) survives the correction unchanged.
- **Identified**: 2026-09-14 · filed via mint_oi.sh from branch `telegram-admin-bot`
- **How found**: B-pass review of telegram-admin-bot's F4 fix (`/cron`'s
  `.limit(200)` row-window → `.gte()` 7-day time-window). The fix's own
  code comment claimed `cleanup_cron_call_log()` "always spares each
  function's most recent row" — the B-pass read the live function body and
  found this false. The LIVE (migration 110) definition:
  ```sql
  CREATE OR REPLACE FUNCTION public.cleanup_cron_call_log()
  RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
  AS $fn$
    DELETE FROM public.cron_call_log
    WHERE started_at < now() - interval '7 days'
      AND id NOT IN (
        SELECT id FROM (
          (SELECT id FROM public.cron_call_log
            WHERE status = 'success' ORDER BY started_at DESC LIMIT 1)
          UNION
          (SELECT id FROM public.cron_call_log
            ORDER BY started_at DESC LIMIT 1)
        ) AS keep_rows
      );
  $fn$;
  ```
  This spares exactly TWO rows globally (the single most-recent
  `status='success'` row table-wide, AND the single most-recent row of any
  status table-wide), not one per function. (109's ORIGINAL one-row body,
  for the record, was `id IS DISTINCT FROM (SELECT id ... WHERE
  status='success' ORDER BY started_at DESC LIMIT 1)`.)
- **Consequence**: a cron-dispatched function silent for longer than 7 days
  has ALL its `cron_call_log` rows purged by the next nightly
  `cron_call_log_cleanup_daily` run and becomes invisible to
  `/status`/`/cron`'s 7-day `.gte()` window — the same class of blind spot
  F4 fixed (a genuinely-stale function silently missing), re-manifesting
  past 7 days instead of past 200 rows. `alert_cron_silence` (also
  migration 109) is a real absence-backstop for total-fleet silence, but
  doesn't cover a single function going silent while others keep running.
- **Fix shape (not decided)**: widen `cleanup_cron_call_log()`'s exemption
  from two global rows to a per-`function_name` `DISTINCT ON` — e.g. spare
  the latest row for EVERY `function_name` present, not just the two
  fleet-wide ones. Needs a new migration (110 is applied and immutable) and
  its own live-verify pass (confirm the DISTINCT ON exemption doesn't
  defeat the 7-day retention's original storage-growth purpose for
  functions that run frequently). **Precondition (R2-11, review round 2):
  before this fix ships, it MUST exclude non-scheduled, trigger-dispatched
  functions (`alert-critical-notify` today) from
  `alert_cron_function_dead`'s scope** — see the cross-reference in that
  alert's own OI (OI-179) for why: a per-function retention exemption would
  arm the exact false-critical-alert loop that OI-179's own threshold
  currently keeps inert by accident.
- **Scope note**: pre-existing production infrastructure (migration 110
  predates this branch), out of scope for the telegram-admin-bot batch's
  own fix diff — the comment claiming this behavior was corrected in that
  same commit (`diagnose 82b018`), and this OI tracks the deeper fix.

## OI-200 — founder_metrics_ops().client_errors_today counts benign event-coded breadcrumbs, no 087-style reinclusion filter

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-14, B-pass on migration 135 (`docs/reviews/5eb09cde42a2-review.md`
  Finding 1) — live query against `dedsavbjuwgarrhphgnl` showed
  `founder_metrics_ops().client_errors_today = 4` on a day with zero real
  errors, all four rows `error_code='event'` (benign `ErrorTelemetry`
  breadcrumbs). `client_errors_today` has counted every `event`-coded row
  since the function was first created (migration 093/101), regardless of
  whether the row is a genuine failure — `ErrorTelemetry.logEvent`
  (`lib/core/services/error_telemetry.dart:332`) hardcodes
  `error_code:'event'` for both benign breadcrumbs and real failures
  (`*_failed`, `widget_error_fallback`, `*_returned_null`,
  `*_unknown_error`), the exact same ambiguity migrations 086/087 resolved
  on the ALERT-SPIKE side (`alert_client_errors_spike`) by re-including any
  `event`-coded row whose `op_type` is failure-shaped
  (`~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)'`).
  `founder_metrics_ops()` has never had the equivalent reinclusion filter —
  it either counts all `event` rows (pre-135) or, after 135, still counts
  all `event` rows (135 only excludes `info`; it does NOT touch `event`).
- **Scope note**: pre-existing since `founder_metrics_ops()`'s creation,
  predates the telegram-admin-bot branch entirely — out of scope for
  migration 135's own fix (R2-10, diagnose `82b018`), which targeted only
  the NEW regression migration 134 introduced (`info`-coded telemetry
  inflating the count). Migration 135's own header comment overclaims
  "mirrors the exclusion pattern migrations 086/087 already established"
  when it only excludes `info`, not `event` — flagged by the B-pass
  (`docs/reviews/5eb09cde42a2-review.md` Finding 1). **The migration file
  itself is NOT corrected**: it was already applied live before the B-pass
  ran, and `supabase/migrations/CLAUDE.md` ("An APPLIED migration is
  IMMUTABLE — including its comments") is explicit that editing an applied
  file's comment silently falsifies its ledger hash with no gate catching
  it. The correction lives here and in diagnose-doc `82b018` instead, per
  that same section's guidance. The eventual fix mirrors 087's exact regex
  reinclusion pattern, applied to `client_errors_today`'s subquery, in a
  NEW migration (136+).

## OI-201 — alert_cron_function_dead can burst-dispatch many critical alerts at once; Telegram send failures are silently dropped with no retry

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-14, Hermes lens L31 (`docs/audit/2026-09-14-hermes-telegram-admin-bot.md`).
  Two compounding gaps, both pre-existing infrastructure (migration 110,
  predates this branch), materially amplified by this branch's own
  deliverable (`alert-critical-notify` is what turns a Postgres `alerts`
  row into an actual Telegram push):
  1. **Burst dispatch**: `alert_cron_function_dead`'s query
     (`110_cron_silence_per_function_and_cleanup_null_guard.sql:82-119`) is
     a SET-RETURNING `INSERT ... SELECT` — one `critical`-severity row PER
     dead function, in one statement. `133`'s trigger is `FOR EACH ROW`, so
     a single statement that flags N dead functions fires N separate
     `net.http_post` dispatches to `alert-critical-notify`, each sending
     its own Telegram message. This repo's own history has a precedent for
     "many cron jobs dead simultaneously" (the Vault `service_role_key`
     drift killed 12+ jobs at once) — that exact shape would now burst
     ~12-20 Telegram sends in one statement, against Telegram's roughly
     1 msg/sec per-chat rate limit. The other `alerts` writers
     (`076_alert_detection_crons.sql`, `086`, `087`, `109`) each carry a
     single-open-alert `NOT EXISTS` dedup guard scoped per-alert; this one
     is scoped per-`function_name` (`110:112-119`), so it does not bound a
     fleet-wide event.
  2. **No retry on Telegram send failure**: `_shared/telegram.ts:63-66`
     handles a non-2xx Telegram response gracefully (no throw, no token
     leak — `telegramErrorSummary` returns `err.name` only) but a `429`
     (rate-limited) is indistinguishable from any other failure, `Retry-
     After` is ignored, and `pg_net.http_post` is fire-and-forget with no
     retry at the Postgres layer either. A dropped send during exactly the
     burst scenario above is lost from the Telegram channel permanently —
     the founder never sees it, with no compensating signal beyond a
     `cron_call_log` `failed` row and a `client_errors` `warn` row that
     nothing surfaces proactively.
- **Scope note**: out of scope for the telegram-admin-bot batch's own fix
  diff — fixing requires either batching `alert_cron_function_dead`'s
  dispatch (one summary alert instead of N) or adding retry/backoff to
  `alert-critical-notify`'s Telegram send path (with `Retry-After`
  honored), both separate infrastructure work with their own blast radius
  and test surface. Filed here rather than fixed in-batch per the same
  reasoning as OI-199/OI-179 above.

## OI-205 — Already-authenticated user opening a valid /reset link is silently switched to a different account with no consent prompt (/confirm partially guarded — no same-vs-different-account distinction yet)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-16, B-pass on the email-confirm-ux batch
  (`docs/reviews/email-confirm-ux-bpass.md` Finding 4). `_authRedirect`
  (`lib/core/router/app_router.dart`) makes both `/reset` (`isOnReset`) and
  `/confirm` (`isOnConfirm`) unconditional passthroughs, returned BEFORE
  `isAuthenticated` is even read. So an already-signed-in user who opens
  EITHER a stale/re-clicked link of their own, or a forwarded/shared link on
  a device someone else is using, gets `verifyOTP`'d against whatever account
  the token resolves to, with the resulting session silently replacing the
  one already active — no prompt, no signal that a switch is about to happen.
  `_ensureLocalUser`'s cross-account guard (`auth_provider.dart:894-951`) is
  correctly reused by both flows, so there is no cross-account Hive DATA
  LEAK — the gap is consent/signal, not data safety.
- **Scope note**: `/reset` has carried this ROUTER-GUARD shape since it
  shipped, and `/confirm` deliberately mirrors it (`app_router.dart`'s own
  comment: "same shape as /reset") rather than introducing a new
  inconsistency — that much is a pre-existing characteristic being
  consistently extended, not a new regression, and remains correct.
  ⚠ **Corrected 2026-09-16, plan-review round 1
  (`docs/plan-reviews/round-reports/email-confirm-ux-round1.md` Finding 1):
  the two are NOT reachability-symmetric in practice, and this note
  previously implied they were.** `/reset` has ZERO Android App Link
  registered anywhere (`AndroidManifest.xml` grepped in full for
  `intent-filter`/`android:host`/`android:path`/`autoVerify` — the only
  `app.icanbefitter.com` App Link in the file is the brand-new one this
  batch adds, scoped to `/confirm` exactly); per diagnose `c9e2b7`, password
  reset was redesigned in 2026-08 to an in-app emailed code, so a `/reset`
  LINK, on the rare occasion one exists at all, only ever opens in a
  **browser** on Android — a separate Flutter-web instance, structurally
  unable to touch the native app's live session. `/confirm`, by contrast,
  is now `autoVerify="true"`: tapping the link from ANY app on a phone with
  AVYA installed hands control DIRECTLY to the already-running Activity via
  `onNewIntent`/`singleTop`, with no "happens to already be in the same
  browser tab" precondition. `/confirm`'s silent-account-switch exposure is
  therefore materially broader and more automatic than `/reset`'s — not
  merely "the same shape, extended to a second entry point." The actual
  remedy is still real UX design (an interstitial, or equivalent) applying
  to both routes, and is still out of scope for a bug-fix batch to design
  unilaterally — but whoever prioritizes this OI should do so from this
  corrected risk picture, not the original symmetric one. Documented as a
  known, corrected-in-place decision (not a silent gap) in
  `lib/features/auth/CLAUDE.md`'s pitfalls table alongside the existing
  `/reset` note.
- **Interim guard SHIPPED 2026-09-16** (same batch, founder-approved via
  AskUserQuestion after the round-1 correction above): `confirmEmail` now
  refuses outright — via the pure, mutation-tested
  `AuthNotifier.confirmEmailAuthGuardState` — and never calls `verifyOTP` at
  all when `SupabaseService.instance.isAuthenticated`, showing "You're
  already signed in. Sign out first to confirm a different account." instead
  of silently switching. This closes the SILENT part of the exposure for
  `/confirm` specifically (no consent-to-switch flow, no same-vs-different-
  account distinction — those still need the real UX decision below).
  `/reset` is UNCHANGED — it was not touched by this batch and its exposure
  is already much lower per the corrected risk picture above.
- **Fix shape (not decided) — the REMAINING gap**: a same-vs-different-
  account distinction (harmlessly re-confirming your OWN already-used link
  should not need a sign-out) needs comparing the verified token's resolved
  user id against the currently-authenticated one — not feasible without
  first calling `verifyOTP`, which itself already mutates the client's
  active session as a side effect, so a clean "reject and restore the prior
  session" implementation needs real session-capture/restore design, not a
  quick guard. Deliberately NOT attempted in this batch (real edge cases:
  restore failure, token expiry mid-round-trip) — tracked here rather than
  rushed under review-response pressure. Also still open: the actual
  confirm-before-switch UX (interstitial or equivalent) for the DIFFERENT-
  account case, applying to both `/reset` and `/confirm`.
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch `email-confirm-ux`

## OI-207 — sot_registry.yaml: hold-weeks line_range citations (762-847, 890-915) stale, pre-dates OI-53 batch 1/2

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-26 — real cause is NOT an incidental mention in a wide window: `method: a / b / c` fails `_bareSymbolRe` (`check_sot_registry_parity.dart:70`), `_extractSymbol` returns null, and the entry is treated as PROSE and never symbol-checked. 417 of 663 dash-form entries are prose-skipped this way. The two hold-weeks methods are now at `workout_schedule_read_service.dart:986-1104`.
  PRIOR (kept verbatim): 2026-09-16, live `Read` of `lib/core/services/workout_schedule_read_service.dart`
  vs `git show HEAD:<path>` at the same lines, cross-checked against `docs/sot_registry.yaml`
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch `oi53-batch2-flip`
- **How found**: opportunistically, by the OI-53 batch 2 plan-review round-1 subagent, while
  independently re-deriving OTHER `workout_schedule_read_service.dart` citations this batch's own
  comment-only edits had shifted (see the batch's flip commit — 5 more stale citations in the SAME
  file were found and fixed there: `pastPhaseBlocks`, `_scheduleRowsBefore`, `pastPhaseBlocksForDisplay`,
  `holdSnapshotBlock`, `currentWeekColumnProjection`; a B-pass/round-2 follow-up sweep then found and
  fixed 3 more of the same class — a class-level range, a `tool_dispatcher.dart` sibling citation,
  and two inline `file:line` comments in the new test file). These two are DIFFERENT — confirmed
  already wrong at `HEAD`, i.e. before OI-53 batch 1 or batch 2 touched anything, so filed separately
  rather than folded into that batch's diff.
- **Root cause**: `docs/sot_registry.yaml` has two `line_range:` citations against this file for
  hold-weeks (FOB-3 / OI-60) concepts that no longer bound their methods:
  - Line ~6830: `line_range: 890-915`, method `activeHoldWeeks / activeHoldOrdinalFor / weekIdentity
    — the seam + the single flag gate`. Actual: `activeHoldWeeks` at line 1000, `activeHoldOrdinalFor`
    at 1005, `weekIdentity` at 1019-1024. Off by ~110 lines.
  - Line ~6946: `line_range: 762-847`, method `isDeloadHold / _holdDatesByOrdinal / holdOrdinalForDate
    / holdWeeks / holdWeekSessionProgress`. Actual: `isDeloadHold` at line 901, `holdWeekSessionProgress`
    starting at 1092 (body continues past 1103). Off by ~140 lines at the start.
  `check_sot_registry_parity.dart`'s stale-line-range check is a substring search for the method
  name anywhere inside the cited window — both citations are wide enough (25 and 85 lines) that
  they may still coincidentally contain an incidental mention of one of the several method names
  in their multi-method group, which is plausibly why the gate has stayed green through whatever
  intervening edits caused this drift. Not re-derived here: exactly which past commit(s) moved
  these methods without updating the citation.
- **Consequence**: doc-accuracy only — nobody has reported acting on a wrong line number from this
  citation. The registry entries' `notes:`/`semantic:` prose is unaffected; only the `line_range:`
  pointer is stale.
- **Fix shape**: re-derive each method's real current span (multi-method groups may need splitting
  into per-method ranges rather than one shared range, since the two groups' real spans now
  interleave — `activeHoldWeeks`/`activeHoldOrdinalFor`/`weekIdentity` at 1000-1024 sits INSIDE the
  810-line-off `762-847`→real-901+ group's likely corrected span, which needs care, not a
  mechanical shift). Small, isolated YAML-only fix; does not need its own plan-review round.
- **Scope note**: deliberately excluded from OI-53 batch 2 (branch `oi53-batch2-flip`) — unrelated
  SoT concept (hold-weeks/OI-60, not any of the 4 flags that batch flips), pre-dates that batch,
  and the two groups' overlapping real spans need a judgment call this batch's reviewers should not
  have to spend attention on. Fix as part of whatever batch next touches hold-weeks, or as a
  standalone doc-only fix.

**UPDATE 2026-09-26 (backlog triage + `ci-green-batch-a`):** This is a third parity-gate blind spot beside OI-180 (bare single-number ranges). Fix shape: a slash/comma-list extractor checking each identifier, landed `--warn-only` first (§4.11) because the gate hard-fails every commit.

## OI-208 — AuthNotifier._teardown() swallows internal failures with no signal to callers -- a timeout leaves all 3 signOut() call sites unable to react (OI-51 residual)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-16, B-pass on the confirm_email_screen OI-51 fix
  (Finding 2). `_teardown()`'s three
  steps (`auth_provider.dart:891-905`) each swallow their own throw in their
  own try/catch, and `_performSignOut`'s own try/catch around
  `_teardown().timeout(signOutTimeout)` (`:871-884`) ALSO does not rethrow —
  it logs + records telemetry and falls through. So a genuine TIMEOUT (not a
  throw) during teardown means `signOut()` returns NORMALLY to every caller.
  All three sites that wrap `AuthNotifier.signOut()` in try/catch specifically
  for OI-51 (`confirm_email_screen.dart`, `settings_screen.dart`,
  `perform_sign_out.dart`) exist to catch a throw and defensively call
  `releaseDeviceSessionIdentity()` on it — none of their catches can fire in
  the timeout case, because nothing throws. If the timeout lands after step 3
  (the real Supabase `signOut()`) but before `unbindSessionIdentity()`
  completes at the end of `_teardown()` (`:907`), the user's cloud session is
  already gone but the device's OneSignal `external_id` / Crashlytics
  `userIdentifier` binding is left stale — the exact OI-51 exposure, reached
  via a fourth path (timeout) that no per-call-site catch can guard against,
  because there is nothing to catch.
- **Scope note**: Identical across all 3 call sites and pre-dates every one
  of them — not introduced or worsened by any of the try/catch guards those
  sites carry (this OI-51 fix included). The actual fix needs `_teardown()`
  itself to expose whether it genuinely completed (not just whether an
  exception escaped it), which changes the shared sign-out contract every
  caller relies on — real design work, not a single call site's guard, and
  deliberately not attempted inline under review-response pressure for a
  12-line diagnose-doc-driven fix.
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch
  `email-confirm-ux`, during the B-pass on diagnose `d4a8f6`.

## OI-210 — future-prediction Edge Function has no live caller anywhere in the shipped app -- decide: wire it up to replace ai-proxy's predict path, or delete it

- **Status**: OPEN
- **Blocked on**: founder decision (see below — surfaced and answered once
  already, but the answer was "leave as-is for now", not a final call on
  wire-up-vs-delete)
- **Verified**: 2026-09-16, B-pass on the cron-ai-removal batch
  (`docs/reviews/247d945d1ba0-review.md` Finding 1), independently
  re-verified before acting: `grep -rn "futurePredictionFunction" lib/`
  → only the declaration at `app_constants.dart:26`, never called again
  anywhere in `lib/`; `grep -n "future-prediction"
  docs/operations/CRON_REGISTRY.md` → no match; `grep -rln
  "future-prediction" supabase/migrations/*.sql` → no match (not
  `pg_cron`-scheduled). The prediction card users actually see comes from
  a DIFFERENT, entirely untouched path: `lib/core/services/
  prediction_service.dart`'s `regeneratePrediction()` (manual/PRO-monthly
  refresh) and `lib/features/onboarding/providers/
  onboarding_provider.dart`'s onboarding-completion prediction (fires on
  EVERY new signup) both call `AiService.instance.predict()` →
  `ai-proxy` with `type: 'prediction'` — a separate, still-Gemini-calling
  path this batch never touched (`ai-proxy`'s own prompt: "Be specific
  with numbers but realistic").
- **Why this matters**: this batch's stated motivation was reducing
  Gemini quota pressure after a production 429 exhaustion incident. This
  batch spent ~3 commits + 3 diagnose-docs (`9c3d7a`, `e5c9b2`, `b2f7c4`)
  hardening `future-prediction` — real trend math, a streak-forecast
  fix, a timezone fix, a sanity-clamp fix — none of which currently
  reduces any live Gemini call, because nothing calls this function. The
  highest-frequency actual prediction call in the app (every onboarding
  completion) is on the untouched `ai-proxy` path and remains uncapped.
- **Founder decision so far (2026-09-16)**: presented 4 options (leave
  as-is + file this OI / wire future-prediction in now, expanding this
  batch's scope / delete future-prediction as dead code / investigate
  first). Founder chose "leave as-is, file a follow-up decision" —
  this batch's future-prediction work ships as a real, harmless
  improvement to currently-unreachable code; this OI carries the actual
  wire-up-vs-delete decision for a future batch, not resolved now.
- **Suggested fix (either direction, not both)**: (1) WIRE UP — redirect
  `prediction_service.dart`'s `regeneratePrediction()` and
  `onboarding_provider.dart`'s onboarding-completion prediction call to
  invoke `future-prediction` instead of `ai-proxy` `type='prediction'`.
  Real scope: two client call sites, a new `functions.invoke('future-
  prediction', ...)` call each, response-shape reconciliation (
  `future-prediction`'s response schema vs `AiChatResponse`'s), and its
  own plan-review round given it changes a live, PRO-relevant user flow.
  Actually closes the 429-mitigation goal for predictions. OR (2) DELETE
  — remove `future-prediction/` (index.ts, trend.ts, index_test.ts,
  `AppConstants.futurePredictionFunction`) entirely; the app keeps using
  `ai-proxy`'s predict path as it does today, unaffected either way.
- **Identified**: 2026-09-16 · filed via mint_oi.sh from branch
  `cron-ai-removal`, during the self-triggered `/code-review` B-pass
  required before merge (CLAUDE.md §4.3).

## OI-211 — Custom exercise equipment field + [] to ['none'] backfill of existing rows (Option B from custom-picker-fix)

- **Status**: OPEN
- **Blocked on**: founder batch scheduling
- **Verified**: never
- **Identified**: 2026-09-17 · filed via mint_oi.sh from branch `custom-picker-fix`
- **Detail** (diagnose `e7b2d4`): the picker-visibility bug was fixed reader-side (canOfferInPicker — customs with unverifiable equipment always offered) because it needs no data migration. The DATA half remains: the creation sheet still stores `equipment_needed: []`, which only works because the picker exempts empty-requirement customs. Root-cause completion: (1) add an equipment multi-select to CreateCustomExerciseSheet writing normalized `EquipmentVocab` tokens; (2) one-time idempotent repair of existing custom_exercise_ rows `[] → ['none']` in Hive AND cloud `user_custom_exercises` (restore path included); (3) then the L2 append's exclusion-only guard becomes capability-checked for customs too. Needs a live cloud apply authorization (§4.3).

## OI-212 — Custom foods unsearchable from the main food search bar (search never reads customBox)

- **Status**: OPEN
- **Blocked on**: founder product decision (separate Your Foods section vs unified search)
- **Verified**: never
- **Identified**: 2026-09-17 · filed via mint_oi.sh from branch `custom-picker-fix`
- **Detail**: `FoodRepository.search` (food_repository.dart:37-43) queries only the seeded ~5K foodBox, never customBox — a custom food is unreachable from the main search box and only surfaces via the dedicated "Your Foods" section. No filter-drop bug (no analogous equipment-style regression found in custom-food or saved-meal readers), but the same "I can't find it when I search" confusion as the exercise picker bug. Decide: fold customBox into search results with a custom badge, or keep the section split deliberately.

## OI-213 — Razorpay auto-renew subscriptions (web): mandates, subscription.charged webhooks, cancel-at-period-end — one-time orders shipped 2026-09-17, renewals deliberately deferred

- **Status**: OPEN
- **Blocked on**: founder product decision on timing (revenue tradeoff: auto-renew reduces lapse churn; requires the revoke path design first — nothing in the codebase takes entitlement away today, and a renewal charge without a revoke path makes refunds unenforceable)
- **Verified**: 2026-09-17 — claims traced from the web-launch batch (spec 2026-09-17-web-razorpay-checkout-design.md, decisions section) and the multi-source billing brainstorm memory
- **Identified**: 2026-09-17 · filed via mint_oi.sh from branch `main`

The web launch (merged `02a7eba8`) ships ONE-TIME orders on the existing
`create-razorpay-order` / `razorpay-webhook` / `verify-payment` pipeline.
Auto-renew needs: Razorpay Subscriptions (plans + mandates), a
`create-razorpay-subscription` EF, new webhook events (`subscription.charged`
etc. — the current webhook's idempotency is keyed on `razorpay_payment_id`
pre-SELECT + 23505, which does not cover subscription cycle events), a
cancel path (note: `delete-account`'s Razorpay-cancel step reads
`razorpay_subscription_id`, which has readers and ZERO writers today — a
live-money no-op the day this ships), and the revoke/entitlement-takedown
design (billing brainstorm "not yet designed" item). The
`update_user_subscription_status()` trigger widening (brainstorm decision 5)
also lands with this work, not before.


## OI-214 — Diet plan Option A: curated Indian meal-template layer (recipe-first selection + portion scaling)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-17 · filed via mint_oi.sh from branch `diet-plan-quality`

## OI-215 — Device verification expansion: Patrol flows for the UI-bug cluster, screenshot tests, canary APK

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `discipline-v2`

Follow-up from the discipline-overhead-v2 design (spec:
`docs/superpowers/specs/2026-09-17-discipline-overhead-v2-design.md` §4, "design C"). Evidence:
of 65 fix commits Sept 2026, ~60% are product bugs and the biggest cluster is founder-visible
UI/UX defects (the 5-observation batch of 2026-09-16: toast color, text wrap, double-pop, empty
states, spinner) — every pre-merge review stage is a code reader and CANNOT see these; the
founder is the QA loop. Scope: expand `docs/operations/DEVICE_TESTING.md`'s 4 Patrol flows to
cover the recurring UI-bug classes (toast/error states, text overflow, empty states,
double-pop/navigation), per-screen screenshot comparisons, and a canary APK flow so S-class UI
fixes get device verification before the founder reports them. Real engineering — own batch,
not bundled into discipline-v2.

## OI-216 — snapshot-contract gate: per-entry slack mechanism for shift-sensitive citations

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `discipline-v2`

`scripts/check_snapshot_contract.dart:118-119` hardcodes a fixed ±15-line window for every
`file:line` citation in `docs/snapshot_contract.yaml` — no per-entry slack exists. The
`future_prediction`/`morning_alert` reader citations drifted twice (2026-07-26, 2026-09-16) when
code removal ABOVE the cited line pushed them out of the window; the discipline-v2 sweep
(1664b475) added SHIFT-SENSITIVE notes but could not convert the mechanism without globally
weakening every other entry. Fix: per-entry optional `slack: N` field (default 15), consumed by
the gate; entries that have drifted twice get 40.

## OI-217 — telemetry v2: aggregate plan-review findings by class (compile/logic/citation) + explicit M/L counts

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `discipline-v2`

Follow-up from discipline-overhead-v2 telemetry (spec §2.8 scope correction). The shipped reader
covers convergence stats, gate failures, escape ledger, and the `tier: s_fix` share; it cannot
aggregate review findings by class because plan-review records carry no structured finding-class
field. Fix: records gain an optional `findings_by_class:` frontmatter map (compile/logic/citation/
material), the telemetry reader sums it across recent records, and M/L counts derive from diagnose
  docs stamped `tier: m_fix`/`tier: l_fix` (extending the `tier: s_fix` stamp from CLAUDE.md
  §4.12.6/rule 22).


## OI-220 — Contract-sweep gate: pre-push targeted SoT contract testing

- **Status**: OPEN — narrowed to the `--warn-only` → hard-fail FLIP; the build shipped 2026-09-19
- **Blocked on**: one clean batch under `--warn-only` (batch B, OI-204, is the baseline batch); the flip removes BOTH tokens of `--warn-only || true` at the `scripts/pre-push.sh` wiring line and takes the full ×2 review (§4.12.4's flip-on rule)
- **Verified**: 2026-09-19 — shipped on `gate-integrity` (`scripts/contract_sweep.dart` + pure `scripts/contract_sweep_lib.dart`; wired in `pre-push.sh` for every tier above `run_full_suite()`; guards `CONTRACT_SWEEP_SKIP=1` / `CONTRACT_SWEEP_NESTED=1`). Real-tree measurement for the flip decision: selection 1.9 s / 17 tests on a 15-file range; 18.5 s / 505 tests on a 366-file range (`origin/main~40...HEAD`) — near full-suite size, so on a ≥account push the sweep is ADDITIVE to the full suite until the flip and can never short-circuit under `|| true`; after the flip a red sweep saves the full run on exactly the pushes that would have failed it. The baseline batch records real seconds per push. **Trust model (replaces this entry's original "rule-24 mutation-proven ledger entry" obligation, which is unsatisfiable by construction):** the sweep is deliberately NOT a `check_*` gate — `pre-commit.sh` and `test.yml` enumerate every `check_*.dart`, and `gate_test_ledger_lib.dart` rejects a ledger key with no `check_*` script on disk — so it carries NO ledger entry; its wiring is pinned by `test/contracts/contract_sweep_wired_test.dart` (+ a behavioural assertion in `pre_push_analyze_always_e2e_test.dart` that the real hook reaches the line) and its proof is rule 21: 6 mutations, 9 reds (+2 for un-wiring the line), one leg re-run by the coordinator. Tests: `test/scripts/contract_sweep_lib_test.dart` (10), `contract_sweep_e2e_test.dart` (7), `contract_sweep_wired_test.dart` (1). Riders (1) and (2) below landed as CLAUDE.md §4.1.5 item 6 and §4.12.7; the riverpod-3 playbook section landed in `docs/playbook/common-pitfalls.md`.
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `main`
- **Detail**: From the ai-coach-ux-tool-integrity retro (memory
  `project_ai_coach_ux_tool_integrity_2026_09_18.md`): ~2h of that batch went
  to full-suite runs because a contract regression
  (`phase_adherence_rate_test.dart` — "paused counts to total but is not
  done") was first seen at pre-push, twice. The sweep would have caught it in
  ~2 min. DESIGN (founder-approved):
  `scripts/contract_sweep.dart` selects contract tests from the push range's
  changed-file list (reuse `blast_radius_from_diff.dart`'s input) via THREE
  unioned arms — (a) registry: changed path → `docs/sot_registry.yaml`
  writers/readers → `behavioral_test_path:`; (b) content-reference:
  `git grep` test/ for each changed lib/ file's basename (catches
  cross-contract pins matching no concept); (c) changed test files
  themselves. Wired into `scripts/pre-push.sh` ABOVE the full suite, all
  tiers. Collection error → fall back to running the full `test/contracts/`
  subset (fail-safe to MORE testing, never none — the #47 lesson: uncertainty
  must not look like a clean sweep). `--warn-only` for the first batch to
  baseline mapping recall, then hard-fail (§4.11 baseline-first pattern).
  Rule-24 obligations: mutation-proven ledger entry; fake-runner tests (no
  real flutter spawn — the `safe_push_test` injection pattern); file-level
  `@Timeout` + `library;`. pre-push.sh is pinned `platform` in
  `docs/blast_radius.yaml` → ×2 plan review + B-pass apply.
- **Rides on the same landing** (from the same retro, founder-approved):
  (1) value-semantics grep as a PRE-WORK step — a batch changing a stored
  value's MEANING sweeps `test/` AND `supabase/functions/` for that value
  before coding (codified reactively in code-review SKILL tuning
  2026-09-18; becomes a §4.1.5 sibling); (2) execution-mode decision
  (subagent vs inline) made at batch START, not mid-batch — both land as
  CLAUDE.md §4 amendments in the gate batch. Rider: riverpod-3
  widget-harness pitfalls (GoogleFonts warmup + `runAsync` fake-async +
  `UncontrolledProviderScope` + empty-box seeding) codified into
  `docs/playbook/common-pitfalls.md` — currently living only in
  `test/widgets/compass_redesign_test.dart`'s header.
- **Escalation criterion** (explicit, so the flip is not a judgment call):
  the `--warn-only` → hard-fail flip happens after ONE clean batch; a
  mis-selection during baseline is a mapping bug fixed before the flip,
  never a reason to stay warn-only.

## OI-218 — Cloud exlog tombstone residual — moved-out-date rows never tombstoned, restore can resurrect + double-count volume

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `oi-filing-reschedule-followups`

From the `ai-coach-ux-tool-integrity` B-pass (`docs/reviews/2026-09-18-ai-coach-ux-tool-integrity-bpass.md`
finding 3), accepted as a documented-not-fixed residual in
`docs/diagnoses/2026-09-18-reschedule-terminal-rows-e8f4a3.md` (BP-P2b, finding 9 folds in here).
`moveExerciseLogs` (`lib/core/services/workout_write_service.dart`) does not tombstone the
cloud `workout_log_exercises` rows for the moved-OUT date. `_restoreExerciseLogs`
(`lib/core/services/sync_workout.dart` ~666+) re-creates `exlog_<fromDate>_<hash>` rows from
those never-tombstoned cloud rows and calls the union-only `addToExlogIndex` on the from-date
index — so after any move, a restore resurrects the from-date logs while the moved copies live
at `toDate`, double-counting volume across two dates in the AI snapshot's `recent_logs`.
Separately, restore-recreated terminal (`moved`/`dropped`) rows on a fresh device lose their
`moved_to`/`moved_via`/`moved_at`/`dropped_*` audit metadata, because the push payload
(`sync_workout.dart:1634`) sends `status` but not those fields, and a cloud-only row has no local
`existingMap` to inherit them from.

**Fix direction (not designed yet):** either tombstone from-date cloud exlogs on move, or extend
the push payload with the terminal audit fields so a cloud-only restore keeps them.

## OI-219 — is_pr not rescanned across moveExerciseLogs — collision merge can drop a true PR flag

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `oi-filing-reschedule-followups`

From the `ai-coach-ux-tool-integrity` B-pass (finding 6), accepted as a documented-not-fixed
residual in `docs/diagnoses/2026-09-18-reschedule-terminal-rows-e8f4a3.md` (reviewer-scoped:
readers are display-only and the flag self-heals on the next edit-sheet save). `moveExerciseLogs`
(`lib/core/services/workout_write_service.dart`) — a collision merge keeps the EXISTING row's
`is_pr` (the moved row's is dropped); the non-collision path keeps the moved row's from-date
`is_pr` semantics with no rescan pass. A moved row carrying the TRUE PR merged into an
`is_pr:false` existing row loses the PR from PR surfaces until the next edit-sheet save rescans.
(Double-PR display is NOT reachable — a same-exercise collision always merges into one row.)

**Fix direction:** after the move loop, run the same chronological rescan
`logExercise`/edit-sheet already use for the affected exercise names on `toDate`.

## OI-221 — tool_dispatcher defensive date-parse fallbacks can clobber the wrong date on a malformed schedule key

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-18 · filed via mint_oi.sh from branch `oi-filing-reschedule-followups`

From the `ai-coach-ux-tool-integrity` B-pass (finding 8), accepted as a documented-not-fixed
residual in `docs/diagnoses/2026-09-18-reschedule-terminal-rows-e8f4a3.md` (degenerate/defensive
path, reviewer-scoped as a bounded follow-up). `lib/features/ai_coach/services/tool_dispatcher.dart`
has two silent-redirect fallbacks: `:761` (`?? destDate` — a failed from-date parse writes the
TERMINAL row onto the DESTINATION date, clobbering the workout just written there) and `:800`
(`?? DateTime.now()` — could stamp `'dropped'` over today). Currently unreachable while schedule
keys are well-formed (the row was just read from `schedule_<fromDate>`), but a parse fallback that
silently redirects a write is worse than failing the move.

**Fix direction:** the drop path's fallback should be a refusal, not a silent redirect.

## OI-222 — Document versionCode-bump-via-merge CI gap in CLAUDE.md §4.9

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-19 · filed via mint_oi.sh from branch `plan-review-record-versionbump44`

`check_plan_review_record_exists.dart`'s version-bump exemption (`isVersionBumpCommit`) only
applies to single-parent direct-to-main commits — every prior versionCode bump
(`1e0f91ce`, `64fc2893`) landed that way. Bumping via the standard §4.13 worktree +
`safe_merge.sh` flow instead produces a `--no-ff` merge commit, which gets NO exemption
("every merge in the range needs a valid record for its own tier") and fails CI's
"Plan-review record" job. Hit live 2026-09-19: merge `0768a0ce` (branch
`aab-versioncode-bump-44`) failed CI on exactly this; fixed by authoring
`docs/plan-reviews/aab-versioncode-bump-44.md` after the fact rather than avoiding the
gap. Also confirmed: `mechanical_only: true` (CLAUDE.md §4.12.6) has ZERO hits in the
gate script — it is not implemented, so declaring it does not reduce the
`review_rounds >= 2` / `bpass: accepted` requirement for a merge that needs one.

**Fix scope:** add a row to CLAUDE.md §4.9 (Common process pitfalls) documenting that a
versionCode bump must be committed DIRECTLY to `main` (single-parent, `ALLOW_MAIN_COMMIT=1`
or equivalent), never via worktree+merge, unless the author is prepared to also author a
plan-review record for the merge. Out of scope for the fix that discovered this (kept
feature-tier deliberately, to avoid the exact recursion this OI describes) — CLAUDE.md is
pinned `platform` tier, so this edit needs its own appropriately-reviewed commit.

## OI-227 — Telegram coach connect is broken (no linking token, bot says no user found) — remove UI entry points, revisit phase 2

- **Status**: OPEN
- **Blocked on**: none — UI removal is self-contained; the real fix needs the separate bot project
- **Verified**: 2026-09-21 — founder tapped "Connect @AVYACoachBot" live, bot replied "no user found"
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3`

Founder tapped "Connect @AVYACoachBot" from the AI Coach tab and Telegram
replied "no user found" — the account-linking handshake between the app and
the bot doesn't work end to end.

Root cause on the app side: `_openTelegramBot()`
(`lib/features/ai_coach/screens/ai_coach/recording_body.dart:13`) opens a bare
`https://t.me/AVYACoachBot` deep link with **no linking token** — no `?start=`
param identifying the app user. Without one, the bot (a separate project on
OpenClaw VPS, NOT in this repo — root `CLAUDE.md:269`) has no way to associate
the incoming Telegram chat with an `icanbefitter` account. This repo cannot fix
the bot-side half of that handshake; it needs access to the bot project.

Confirmed while investigating: this is a **different bot** from the founder's
admin console. `@AVYACoachBot` (user-facing, meant to carry coach
conversations + proactive nudges via `telegram_connections`, referenced in
`morning-alert/index.ts:456-464` as a push fallback) is separate from
`@ICanbeFitterBot` / `@IcanbefitterBot` (root `CLAUDE.md:269`,
`supabase/functions/CLAUDE.md:55` — the `telegram-admin-bot` Edge Function,
read-only, founder-only, allowlisted to a single chat id, powers `/digest`
etc.). No relation between the two; fixing one says nothing about the other.

Live in-app entry points that let a user reach the broken flow:
- `lib/features/ai_coach/screens/ai_coach/compact_header.dart` — popup menu
  item `telegram` ("Connect @AVYACoachBot").
- `lib/features/ai_coach/screens/ai_coach/telegram_view.dart` — the
  "CONNECT @AVYACOACHBOT" CTA on the in-app Telegram card.

Founder decision 2026-09-21: full fix (proper linking token + bot-side
handling) is phase 2. **Done in this session, uncommitted:** removed the
"Connect @AVYACoachBot" menu item (`compact_header.dart`) and the matching CTA
in `telegram_view.dart` (its not-connected copy now reads "Telegram — Coming
Soon" with no button). Deliberately **kept** the `switch_channel` toggle
("Switch to Telegram" / "Switch to In-App Chat") — `channelProvider`
(`ai_coach_provider.dart:1075-1086`) persists `coach_channel` to Hive, so any
user already on `channel == 'telegram'` needs that toggle to get back to chat;
removing it too would trade this bug for a worse one (a stranded user with no
UI path back). Verified with `flutter analyze lib/` (both touched files are
`part of 'screen.dart'`, so only a whole-tree analyze is valid per this
board's own common-pitfalls note) — 0 errors/warnings, 45 pre-existing infos
unrelated to these files. `telegram_view.dart` / `channelProvider` /
`_openTelegramBot()` left in place (dead but harmless) for phase 2.

**Phase 2 must not reuse the email flow (2026-09-29, Hermes L22/L35 on `oi-182-202-subscription-state`).**
`telegram-bot/bot.py` `receive_email` (`:281-332`) links a Telegram chat to whichever `users` row
matches a typed email, with no proof of ownership: no code, no link, no token. Anyone who knows or
guesses a victim's email can link their own chat to that account, chat as that user (the coach
context is built from the victim's data via `get_user_context`), and probably replace the real
owner's `chat_id` in `telegram_connections`, which `morning-alert` uses as a push fallback. It is
dormant only because the feature is hidden and the bot is not deployed (founder, 2026-09-29). The
phase-2 linking-token handshake above (the app mints a one-time token, opened as
`t.me/AVYACoachBot?start=<token>`) removes the flaw; the email prompt must be deleted, not kept as
a fallback.

Two related items surfaced, deliberately NOT resolved by this OI:
- `lib/shared/widgets/paywall_sheet.dart:120` markets "Weekly AI nutrition
  report + Telegram push" as a PRO perk bullet. With the connect entry points
  gone, no new user can ever receive that. Founder to decide whether to reword
  it now or leave it for the phase-2 fix.
- `lib/features/ai_coach/widgets/telegram_card.dart` (`TelegramCard`) appears
  unreferenced anywhere else in `lib/` — looks like dead code predating
  `telegram_view.dart`. Not touched here; separate small cleanup if confirmed.

**Recommendation**: Phase 2 — design a real linking handshake (token minted
app-side, passed via the deep link's `start` param, exchanged by the bot for
the user's id) with whoever owns the bot project, then re-add the UI entry
points. Until then, this OI stays open as the pointer for "why is Telegram
missing from the Coach menu."

## OI-228 — AI coach shortenWorkout tool calls get stuck at status:queued with no resolution; log_workout_sheet shows wrong copy for a completed day

- **Status**: OPEN
- **Blocked on**: none — Bug A is CLOSED; Bug B's "stuck at queued" premise is REFUTED (Batch B, see below) — the real remaining gap is missing client-side confirm/dispatch telemetry, needed before a fix can be proposed with confidence
- **Verified**: 2026-09-22 (Batch B) — live-traced the exact incident row; the cloud `tool_calls` field is a write-once snapshot that never transitions for ANY write tool, so it cannot itself evidence a stuck dispatch (see Update below)
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3` (**Bug A is CLOSED by batch `oi-batching-strategy-e5e359`**, see the update at the bottom — Bug B remains open)

Two related but distinct AI-coach tool-dispatch bugs surfaced from founder
screenshots of a completed workout day.

**Bug A — log_workout_sheet shows wrong "no workout" copy for a completed day.**
`lib/features/ai_coach/widgets/log_workout_sheet.dart:99-115` (`_load()`)
treats any `schedule_<date>.status` other than `'planned'`/`'paused'` —
including `'completed'` — as "not loggable" and renders the generic empty
state `'NO WORKOUT SCHEDULED TODAY'` (`:208`). For a day the user actually
completed, this is misleading: the workout WAS scheduled and IS done, not
absent. Needs a distinct completed-state copy branch (e.g. "Today's workout
is already logged.").

**Bug B — shortenWorkout tool call sat at `status: "queued"` and never
resolved, while the model narrated success anyway.**
This is NOT a missing-guard bug — verified live in this session:
`WorkoutScheduleService.shortenDay` (`lib/core/services/swap_service.dart:350-354`)
correctly throws `ShortenDayException('workout_completed', 'Cannot shorten a
completed workout')` for a completed day, and the swap tool's own inline
check (`tool_dispatcher.dart:283-286`, `_executeSwapExercise`) is symmetric
and correct. `_executeShortenWorkout` (`tool_dispatcher.dart:577-595`) has no
inline check of its own but correctly delegates to `shortenDay`, which DOES
guard. **The observed tool call never reached this code at all** — the
founder's `ai_coach_interactions.tool_calls[]` entry for the shorten intent
sat at `status: "queued"` indefinitely, and the model's text reply
prematurely narrated "I have queued... you will see the revised plan
shortly" — directly violating `captain_manual.ts:435`'s hard rule: "Never
narrate what you are about to do. Do it, then report the result in one
line."

**Not yet isolated:** why the tool call got stuck at `queued` and never
actually dispatched. Needs tracing the tool-call lifecycle between the
model's `tool_call` emission (ai-proxy `tool-loop.ts`) and the client's
`ToolDispatcher` intent processing — worth checking live `ai_coach_interactions`
rows for other stuck-`queued` instances to see if this is rare or systemic
before assuming a specific mechanism.

**Recommendation**: (1) Fix log_workout_sheet's copy for the completed-day
case — small, isolated, no root-cause investigation needed first. (2)
Investigate live why the shorten intent stalled at `queued` — reproduce with
a fresh shorten-on-completed-day request, inspect `tool-loop.ts`'s
round-trip and the client dispatch path, before proposing a fix. (3)
Separately: the premature "queued... shortly" narration is a
captain_manual.ts instruction-adherence gap the model should be tightened
against regardless of Bug B's root cause.

**Update 2026-09-22 (Batch A, branch `claude/oi-batching-strategy-e5e359`):**
Bug A CLOSED — `log_workout_sheet.dart` now distinguishes a `'completed'`
schedule row (new `_alreadyCompleted` flag) and shows "WORKOUT ALREADY
LOGGED" / "Today's workout is already logged." instead of the generic empty
state. Behavioral widget-pump test + mutation-proof in
`test/widgets/log_workout_sheet_completed_day_test.dart`. Bug B is
UNCHANGED and still needs the live tracing this entry's own recommendation
(2) describes — not attempted in this batch (investigation-first work,
outside a ready-to-fix batch's scope).

**Update 2026-09-22 (Batch B investigation, branch
`worktree-agent-a8d2441cb81c6553b`):** Bug B's root cause is now
REFRAMED, not fully closed — the "stuck at queued" premise itself does not
describe a broken lifecycle.

**Code-level finding.** `ai_coach_interactions.tool_calls` is written
EXACTLY ONCE, at request-resolve time
(`supabase/functions/ai-proxy/index.ts:1155`), from `loop.toolCallsLog` —
which `tool-loop.ts:505-509` sets to `status: "queued"` the instant a
write-tool's `intentBuilder` succeeds, and never mutates afterward.
Exhaustive grep of `supabase/functions/**` and `lib/**` found no other
write site touching this column (client-side `ai_service.dart:295-297`
only READS the per-request `tool_calls_log` field from the response —
"Server-only diagnostics; never surfaced to the user" — and never writes
it back). So `status: "queued"` is the PERMANENT, by-design value for
every successfully-queued write-tool call, forever — regardless of whether
the client ever renders the confirm card, the user taps APPLY, execution
succeeds, a guard rejects it, or the card is dismissed. This field cannot
itself distinguish "resolved" from "never even seen" and was never meant
to transition; the OI's own title is a misreading of it.

**Live data for the exact incident**
(`ai_coach_interactions.id = 4b2c3bfc-f2af-4395-8f56-32200d890757`,
2026-09-21 12:07:10 UTC, `user_message = "Cut today's workout to 30 min"`,
`user_id = d7a67a37-0b05-4f0a-b13c-388bff3cb59b`):
- This is the ONLY `shortenWorkout` tool call ever recorded, and the only
  successfully-queued write-tool-call entry in the table's entire history
  (16 of 271 interactions carry non-null `tool_calls`; only 2 are real
  tool-loop arrays — this one, and an unrelated `getNutritionHistory`
  `invalid_args` from 2026-08-01). **Rare, not systemic** — settles the
  OI's own open question.
- `public.scheduled_workouts` for this user/date
  (`id = e919fd76-42ff-4f75-9bbe-86284c82e4b1`) shows
  `status: "completed"`, `completed_at: 2026-09-21 04:14:46 UTC` —
  completed ~8h before the shorten request, and UNCHANGED afterward (no
  shortened-workout side effect ever landed, consistent with either "guard
  correctly rejected it" or "it never dispatched at all").
- `_executeShortenWorkout` (`tool_dispatcher.dart:585-604`) logs
  `ErrorTelemetry.logEvent('tool_dispatch_shorten_workout_failed', …)`
  (`:601-602`) whenever `WorkoutScheduleService.shortenDay` throws
  `ShortenDayException` — exactly the completed-day guard case this OI
  already confirmed works correctly. `client_errors` has ZERO rows with
  that op_type for this user, ever. So the guard path was never even
  exercised: the client-side dispatcher branch for this intent never ran
  at all, success or rejection.
- The ONLY `client_errors` activity for this user in the 22 minutes
  spanning the request (12:07:00–12:29:00 UTC) is **54 `restore_op_done`
  events** — the same ~8 sync tables (water_logs, workout_templates,
  streaks, schedule_completions, scheduled_workouts, workout_logs,
  saved_meals, nutrition_logs) completing in repeating waves roughly every
  3 minutes, several taking 10–42s each. The device was in the middle of a
  heavy, repeating background/restore-sync storm exactly when the chat was
  sent and for the following ~20+ minutes.

**Conclusion.** No dispatch-code bug was found — the guard, the
`intentBuilder`, and the queue-for-confirmation architecture all behave as
designed. The best-supported (not proven) explanation for "nothing
visibly happened" is that the user never tapped APPLY on the resulting
confirm card — there is no telemetry either way, because
`ToolConfirmCard`'s confirm/dismiss actions (`tool_confirm_card.dart:39-64`)
leave no cloud trace at all (Hive-only, no cloud write-back). The
concurrent restore storm is circumstantial, not proven causal, but is
itself anomalous (54 restore ops for one user in 22 minutes) and worth its
own look — not attempted here, out of this batch's 3-item scope.

**Batch B2 fix plan (not implemented here):** (1) Add a client-side
lifecycle event — write to `client_errors` (or a new light column) on
confirm-card render, APPLY tap, and dispatch outcome — so a future
incident is diagnosable from data instead of inference. (2) Once that
telemetry exists, reproduce a shorten-on-completed-day request and confirm
whether the card renders/behaves correctly under normal load, then
separately under a concurrent restore storm, to test the sync-storm
correlation directly. (3) Separately (already flagged in this OI):
tighten `captain_manual.ts`'s no-narration instruction so the model stops
describing queued-for-confirmation write tools as already-in-progress
background jobs ("you will see the revised plan shortly") — this is a
real prompt-adherence gap independent of Bug B's root cause. (4) Consider
whether the restore-storm frequency (54 events/22min for one user) is
itself a distinct issue worth its own OI — flagged, not filed, in this
batch (out of scope).

## OI-229 — AI coach chat replies violate captain_manual.ts hard rules: 100-word cap breached, fabricated free-tier message count shown to a PRO user

- **Status**: OPEN
- **Blocked on**: none — both are prompt-adherence gaps in `captain_manual.ts`'s
  existing rules, not missing code; needs a prompt-engineering iteration + live
  re-testing, not a one-line code fix
- **Verified**: 2026-09-21 — both cited captain_manual.ts lines re-read live
  this session and match the founder's observed reply exactly
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3`

Founder (confirmed PRO) sent "Hi" to the AI coach. The reply violated two of
`captain_manual.ts`'s own hard rules for the `chat` channel.

**Violation 1 — reply length.** `captain_manual.ts:432-433`: "REPLY LENGTH
(chat) — HARD RULES: Default reply: 100 words or fewer." The actual reply
ran to roughly 230 words — more than double the cap, with no photo attached
(the 60-word photo case doesn't apply).

**Violation 2 — fabricated free-tier cap shown to a PRO user.** The reply
included "You have 10 messages remaining today on the free tier."
`captain_manual.ts:122-124` is the only place in the system prompt resembling
this text: "When free user approaches/hits the 10/day cap: ... 'Free tier —
10 messages today, you're at 8. Want unlimited? PRO is ₹349...'" — an
ILLUSTRATIVE EXAMPLE scoped explicitly to a free user near the cap. No field
in the snapshot sent to the model carries a literal "messages remaining"
count (PRO is unlimited server-side — no counter is even meaningful). The
model appears to have pattern-matched this example phrasing into a reply for
a user its own snapshot should have shown as PRO — i.e. it did not correctly
gate this instruction block on `snapshot.subscription`/PRO status before
using it.

**Not yet investigated:** whether `snapshot.subscription` (or whatever field
carries PRO status) was correctly populated in the actual request that
produced this reply — if the snapshot itself was wrong, this is a data bug,
not a pure model-adherence gap. Needs a live snapshot inspection on a repro.

**Recommendation**: (1) Verify live that the snapshot sent for this request
correctly marked the user PRO — rule out a data bug before assuming pure
prompt drift. (2) If the snapshot was correct, tighten
`captain_manual.ts:122-124`'s instruction to be more explicitly conditional
("ONLY if snapshot.subscription is NOT pro") and/or move the illustrative
example further from ambiguous phrasing a model could echo verbatim
regardless of gating. (3) Consider a server-side deterministic safety net for
both violations — e.g. truncate/warn on replies exceeding the word cap, and
strip/refuse any reply containing free-tier cap language when
`snapshot.subscription == 'pro'` — since prompt-only fixes are probabilistic
and this is exactly the kind of hard, checkable rule a deterministic
post-check can backstop.
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3`

**Update 2026-09-22 (Batch B investigation, branch
`worktree-agent-a8d2441cb81c6553b`):** Recommendation (1) — live snapshot
verification — is now DONE. Confirmed: the snapshot WAS correctly PRO at
generation time. **Both violations are pure prompt drift, not a data bug.**

Incident row: `ai_coach_interactions.id =
f6208401-acae-424b-90d5-fd57268d086f` (2026-09-21 11:57:08 UTC,
`user_message = "hi"`, `user_id = d7a67a37-0b05-4f0a-b13c-388bff3cb59b`) —
this is the exact reply text the OI describes (matches both violations
verbatim, including the closing "You have 10 messages remaining today on
the free tier."). Note: `ai_coach_interactions` has no stored
snapshot/context column (confirmed via `information_schema.columns` — only
`id, user_id, snapshot_id, channel, user_message, ai_response, model_used,
tokens_used, was_helpful, created_at, summarized, tool_calls`), so the raw
snapshot payload itself isn't recoverable after the fact; PRO status was
instead cross-checked against the two live sources that feed it:

- `public.subscriptions`: an `active` `yearly` row for this user
  (`id = 448b08ee-c23d-4770-8104-cf0b5da4bc4c`,
  `start_date: 2026-09-14 17:37:49 UTC`,
  `end_date: 2027-09-14 17:37:49 UTC`) — active and unexpired at message
  time.
- `client_errors`: `op_type = "subscription_state_written"`,
  `error_message = "isPro=true plan=yearly"`,
  `created_at: 2026-09-21 11:56:06 UTC` — **62 seconds before** the "hi"
  request — confirms the LOCAL Hive cache that
  `ai_snapshot_builder.dart`'s `_getSubscriptionState()` (`:1367-1378`,
  reading `SubscriptionService.instance.isPro()` at `:1368`) builds
  `snapshot.subscription` from was already `true` at generation time.

Both the server (Postgres) and client (Hive, via telemetry) sources
independently confirm PRO status was correctly known. The model echoed
`captain_manual.ts:122-124`'s illustrative free-tier example verbatim
despite having the correct PRO signal available — this is Violation 2
settled as pure prompt-adherence drift, matching OI-231's parallel finding
for the rank-address violation from the SAME reply (see that OI's Batch B
update — both violations in this single "hi" reply are now confirmed
prompt drift, not data bugs).

**Word count** (Violation 1): the actual reply is ~190 words by a plain
whitespace count (vs. the OI's original "roughly 230" estimate) — either
way, well over double the `captain_manual.ts:432-433` 100-word cap. No
data-bug angle applies here; it is the same class of length/gating
adherence gap as Violation 2.

**Batch B2 fix plan (not implemented here):** (1) Tighten
`captain_manual.ts:122-124`'s free-tier-cap instruction to be explicitly
conditional ("ONLY if snapshot.subscription.tier !== 'pro'") and move the
illustrative example phrasing further from something a model could echo
verbatim regardless of gating — per this OI's own Recommendation (2). (2)
Add a deterministic server-side post-check in `ai-proxy`/`tool-loop.ts`
that strips or refuses any reply containing free-tier-cap language when
`snapshot.subscription.tier === 'pro'` — per Recommendation (3); this is a
hard, checkable rule that shouldn't rely on prompt adherence alone. (3)
Separately, add a reply-length enforcement backstop (truncate/regenerate)
for the 100-word chat cap, since this is the second confirmed instance of
the model ignoring an explicit hard-rule instruction in the same manual —
worth treating length + subscription-gating as one "deterministic
post-check" work item in Batch B2 rather than two.

## OI-231 — AI coach addressed a promoted user by their OLD rank term (Recruit instead of Sailor) — current_rank_code read directly from Hive, bypassing rank_service's canonical reader

- **Status**: OPEN
- **Blocked on**: none — live verification DONE (Batch B, see update below):
  hypothesis 2 (pure model miss) CONFIRMED, hypothesis 1 (stale data)
  REFUTED. Remaining work is a `captain_manual.ts` prompt-tightening pass
  (Batch B2), not more investigation
- **Verified**: 2026-09-22 (Batch B) — settled via the same reply's own
  internal inconsistency (correct SD1 rank name later in the identical
  output that opened with the SD2 address term) — see update below
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3` (see the update at the bottom for batch `oi-batching-strategy-e5e359`'s partial progress)

Founder is confirmed rank SD1 (per this session's earlier investigation) but
was addressed "Recruit" — the term for rank SD2 — in the "hi" reply.

**How rank-address is supposed to work:** `captain_manual.ts:27-28`
instructs the model: "RANK-AWARE ADDRESS (use snapshot.current_rank.code):
SD2 → 'Recruit'" (with the SD1 term "Sailor" listed alongside it,
`captain_manual.ts:214-215`). The model is told to derive the address
directly from `snapshot.current_rank.code`, which `ai_snapshot_builder.dart`
builds via `_getCurrentRankFromLadder()` (`:1384-1398`).

**This OI's own title names a mechanism that was checked and ruled out.**
`_getCurrentRankFromLadder()` (`:1386`) and `_getNextRankFromLadder()`
(`:1402`) both read `profile['current_rank_code']` directly off
`_hive.userBox.get('profile')` rather than calling
`rank_service.dart`'s canonical `getCurrentRank()` (`:217-229`, the reader
named in the `rank_monotonic_current_code` SoT registry entry,
`lib/core/services/CLAUDE.md`) — a real code-hygiene violation of this
repo's "always read through the canonical SoT reader" rule, worth fixing
regardless. **But `getCurrentRank()` itself does the exact same read**
(`profile['current_rank_code'] as String? ?? 'SD2'`, `rank_service.dart:220`)
— identical key, identical default. So the duplicate-reader pattern reads
the SAME value either way; it cannot by itself explain a stale rank shown to
the user, and is not confirmed as this bug's cause.

**Not yet isolated — two remaining hypotheses, not distinguished:**
1. **Stale data.** `profile['current_rank_code']` in Hive genuinely still
   held `'SD2'` at the moment this snapshot was built, even though the app's
   own Profile screen (which also ultimately reads this field) showed SD1 —
   meaning the promotion write (`rank_service.dart:140-174`,
   `evaluateAndPromote`) either hadn't run yet, or ran but didn't reach this
   Hive key in time, for this specific request.
2. **Pure model miss.** The snapshot's `current_rank.code` was already
   correctly `'SD1'` and the model simply didn't use it — echoing "Recruit"
   from conversational habit/training bias rather than reading
   `snapshot.current_rank.code` as instructed.

These have different fixes (a data/sync bug vs a prompt-engineering
tightening) and need to be told apart before proposing one.

**Recommendation**: (1) On a repro, inspect the live snapshot payload
actually sent to the model for that request (or the `ai_coach_interactions`
row's stored context, if captured) to see what `current_rank.code` literally
said — this alone settles hypothesis 1 vs 2. (2) Independently of the root
cause: fix `ai_snapshot_builder.dart:1386` and `:1402` to call
`RankService.instance.getCurrentRank()` instead of duplicating its read —
even though it isn't this bug's cause, it's a live SoT-reader duplication
this repo's own conventions forbid, and duplicated reads are exactly the
pattern that silently drifts later (`feedback_writer_reader_field_drift_recurring.md`).

**Update 2026-09-22 (Batch A, branch `claude/oi-batching-strategy-e5e359`):**
Recommendation (2) DONE — both call sites now route through
`RankService.instance.getCurrentRank()`. As this entry's own text already
anticipated, this does NOT close the OI: the live-verification half
(recommendation 1, hypothesis 1 vs 2) is still unresolved and needs a repro
with live snapshot/interaction inspection, which is investigation-first work
outside a ready-to-fix batch's scope. Stays OPEN, blocked on the same live
verification as before. (Side benefit of the hygiene fix, found while
implementing it: `_getCurrentRankFromLadder()` was ALSO reading a second,
dead Hive key — `current_rank_earned_at`, which nothing writes; the real
writer uses `current_rank_achieved_at`. Fixed as part of the same change;
see OI-230's closure note in `docs/audit/closed_issues.md`.)

**Update 2026-09-22 (Batch B investigation, branch
`worktree-agent-a8d2441cb81c6553b`):** Hypothesis 1 vs 2 is now SETTLED —
**confirmed hypothesis 2 (pure model miss). Hypothesis 1 (stale data) is
REFUTED.**

`ai_coach_interactions` has no stored snapshot/context column (confirmed
via `information_schema.columns` — only `id, user_id, snapshot_id, channel,
user_message, ai_response, model_used, tokens_used, was_helpful,
created_at, summarized, tool_calls`), so the raw snapshot payload sent to
the model for this request is not recoverable directly. The stored
`ai_response` TEXT itself settles the question instead, without needing it.

Incident row: `ai_coach_interactions.id =
f6208401-acae-424b-90d5-fd57268d086f` (2026-09-21 11:57:08 UTC,
`user_message = "hi"`, same founder-test user). The SAME reply:
- Opens: "Recruit, stand by for the brief."
- Later, in the identical reply, states: "Your current rank is Seaman 1st
  Class."

Per `captain_manual.ts:162-163`, "Seaman 1st Class" is SD1's RANK NAME
("Seaman 2nd Class" is SD2's). Per `captain_manual.ts:28-29`, "Recruit" is
SD2's ADDRESS TERM and "Sailor" is SD1's. Both values came from ONE
request/generation. Since the rank NAME stated in the body is objectively
correct for SD1, the underlying `current_rank` data available to the model
WAS correct (SD1) at generation time — this directly refutes hypothesis 1
(a stale `profile['current_rank_code']` still holding `'SD2'`). The model
used the wrong (SD2) address term at the greeting while correctly stating
the SD1 rank name moments later in the SAME output — an internal
self-contradiction only explainable as the model not consistently applying
the rank-aware-address instruction (`captain_manual.ts:27-29`, `:214-215`),
i.e. pure prompt-adherence drift. This is the identical incident and root
cause as OI-229's Violation 2 (also settled prompt drift, see that OI's
Batch B update) — both violations came from this one "hi" reply.

**Batch B2 fix plan (not implemented here):** (1) Tighten
`captain_manual.ts:27-29`/`:214-215`'s rank-aware-address instruction to
explicitly require internal consistency within a single reply — e.g. "if
you state the rank NAME anywhere in this reply, the greeting ADDRESS TERM
must match the same rank" — since the failure mode here is specifically
the model using two different rank vocabularies in one output, not simply
picking a wrong rank. (2) Consider a deterministic post-check
cross-referencing the address term actually used against
`snapshot.current_rank.code` server-side, similar to OI-229's proposed
subscription-gating backstop — both are the same class of "hard, checkable
rule the model drifted on despite correct underlying data."

## OI-233 — user_daily_snapshots' 4 cron/client writers are not atomic against each other — residual race left open by the d8a2f6 merge-safe fix

- **Status**: OPEN
- **Blocked on**: none — scope and fix shape are already known, just not
  proportionate to bundle into the fix that surfaced it
- **Verified**: 2026-09-21 — explicitly scoped out in
  `docs/diagnoses/2026-09-21-morning-alert-snapshot-clobber-d8a2f6.md`'s own
  `impact_analysis`, filed here per that doc's own note ("worth its own OI
  if the founder wants the race closed too")
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/food-logging-observations-126ab3`

`docs/diagnoses/2026-09-21-morning-alert-snapshot-clobber-d8a2f6.md` fixed
`daily-snapshot/index.ts`'s blind wholesale-replace upsert into
`user_daily_snapshots.snapshot_json` — it now reads the existing row,
merges via `mergeSnapshotJson` (`_shared/snapshot_merge.ts`), and upserts
the merged result. This makes the CLIENT writer safe against a cron having
written earlier.

**What it does NOT do:** make the 4 writers (`daily-snapshot`,
`morning-alert`, `rolling-context`, `future-prediction`, `beat-my-coach`)
atomic against EACH OTHER. Each still does its own application-level
read-modify-write (SELECT, merge in application code, then UPSERT) — so two
of them racing the exact same row at the exact same instant could still
lose an update to each other: both read the same pre-race row, both merge
their own key in locally, and whichever UPSERT lands second overwrites the
first's change (the first's key survives only if the second writer's merge
happened to include it too, which it won't for a key it doesn't own).

This is a narrower, lower-probability window than the bug d8a2f6 fixed (that
one was a GUARANTEED clobber on every client sync after any cron write, not
a race requiring near-simultaneous writes) — which is why d8a2f6 deliberately
did not bundle this fix in: the diagnose-doc's own `impact_analysis` names
the proportionate fix (a Postgres RPC doing an atomic `snapshot_json ||
$delta`, the same approach `e4a1b7`/OI-98's final fix used for
`notification_preferences`) but notes it requires a migration touching a
table 4 live Edge Functions read/write — disproportionate to the actual
reported symptom, which the read-modify-write fix already closes completely.

**Recommendation**: if the founder wants this residual race closed too,
follow `e4a1b7`/OI-98's precedent: a SECURITY DEFINER (or INVOKER, per that
migration's own later correction) Postgres RPC that does the merge
atomically inside a single statement (`snapshot_json = snapshot_json ||
$delta`), called by all 5 writers instead of each doing its own
SELECT-then-UPSERT. Needs its own migration + live verification pass per
this repo's migration protocol, not a quick follow-on to d8a2f6.

## OI-236 — 12 of 14 Supabase advisor-flagged unused indexes (idx_scan=0) left unreviewed — idx_users_email_lower and idx_subscriptions_razorpay_payment_id are auth/payment-adjacent, may be low-frequency not dead

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/next-aab-decision-d1227b`

## OI-237 — Extreme update:insert ratios on scheduled_workouts (34:1) and template_exercises (39:1) — possible sync write-amplification rewriting full rows instead of deltas, needs docs/architecture/sync.md + WriteServices code review

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-21 · filed via mint_oi.sh from branch `claude/next-aab-decision-d1227b`

## OI-239 — Acknowledging an alert re-arms its dedup window instead of waiting out the original interval — a systemic property shared by all 6 alert_* cron jobs

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-22 · filed via mint_oi.sh from branch `claude/strange-merkle-c2d0b9`

Surfaced while fixing migration 140's `alert_cron_failures` stuck-window bug
(`docs/diagnoses/2026-09-21-hermes-pass-migration-138-139-fixes-h1a2b3.md`): every `alert_*` cron
job (`alert_cron_failures`, `alert_client_errors_spike`, `alert_cron_silence`,
`alert_cron_function_dead`, `alert_edge_function_health`, and any future sibling following the
same convention) dedups on `NOT EXISTS (SELECT 1 FROM public.alerts WHERE source = '<job>' AND
acknowledged = false AND detected_at > now() - interval '<window>')`. Acknowledging the alert
(the founder's own normal triage action) sets `acknowledged = true`, which makes that
`NOT EXISTS` check true again on the VERY NEXT cron tick (as soon as 15 minutes later) rather
than waiting out the original dedup window from `detected_at`. So the founder's own act of
reading and dismissing a page can cause a near-immediate re-page for the same underlying,
still-ongoing condition — the opposite of what acknowledging is supposed to signal. Not unique to
`alert_cron_failures`; every job sharing this INSERT-with-`NOT EXISTS`-dedup idiom has the same
property.

**Fix direction:** either dedup on `detected_at` alone regardless of `acknowledged` (so
acknowledging never shortens the window), or add a separate `snoozed_until` concept distinct
from `acknowledged` so triage and re-page timing are decoupled. Needs a design decision, not a
one-line fix, since it touches the shared convention all 6 jobs rely on — a design change here
should update all 6 in the same batch, not just the one that surfaced it.

## OI-240 — _getNextRankFromLadder's remaining/binding_constraint is inaccurate for 3 of 4 constraint types: officer/MCPO completionRateMinimum gate not modeled at all, deployments 'current' hardcoded 0 (intentional, matches RankService)

- **Status**: OPEN
- **Blocked on**: none — bounded work, but a genuinely different/larger unit than OI-230's fix (new requirement type + a fundamentally different, adherence-dependent ETA semantic)
- **Verified**: 2026-09-22 — every claim below re-read live this session (`kRankGates` full literal, `rank_service.dart:439-444`)
- **Identified**: 2026-09-22 · surfaced while fixing OI-230 (`ai_snapshot_builder.dart` `_getNextRankFromLadder`/`_getEtaNextPromotion`) · filed via mint_oi.sh from branch `claude/oi-batching-strategy-e5e359`

Found while making OI-230's ETA fix binding-constraint-aware: the `remaining`
map `_getNextRankFromLadder()` (`lib/features/ai_coach/services/ai_snapshot_builder.dart:1400-1465`)
computes for the AI snapshot is accurate for exactly ONE of the four
constraint types it can select as `binding_constraint`, and the OI-230 fix
had to work around the other three rather than trust them:

**1. Officer/MCPO ranks (`completionRateMinimum` gate) — not modeled at all.**
`kRankGates` (`lib/core/services/rank_ladder_data.dart:196-249`) gates MCPO,
SubLt, Lt, LtCdr, Cdr and Capt primarily by `completionRateMinimum` +
`completionRateWindowWeeks`. `_getNextRankFromLadder`'s `reqs` map
(`:1419-1431`) never reads either field — only `totalWorkoutsAtLeast`,
`streakAtLeast`, `minWeeksSinceSignup`, `deploymentsCompleteAtLeast`. For
these ranks, `binding_constraint` can only ever resolve to `'weeks'` (the
only other requirement most of them carry), even when completion rate is
the REAL blocker — a user could be weeks-eligible and still nowhere near
promotion, with the snapshot claiming weeks is the only gap. OI-230's fix
guards against this specific case (any rank with `completionRateMinimum`
set gets an honest "cannot estimate" ETA regardless of what
`binding_constraint` says), but the `next_rank.remaining`/`binding_constraint`
FIELDS THEMSELVES — read directly by the model, separate from
`eta_next_promotion` — are still silently wrong for these ranks.

**2. `deployments` — `current` hardcoded 0 (NOT fixed by OI-230, and correctly so).**
The `reqs.forEach` loop (`:1437-1456`) never computes `current` for the
`'deployments'` key — it stays 0 regardless of the user's actual deployment
count, so `remaining['deployments']` always shows the FULL requirement.
This is left as-is deliberately: `RankService.getNextRank()`
(`rank_service.dart:439-444`) documents the identical tradeoff for its own,
separate implementation — an accurate deployments-complete count requires a
network call (counting `rank_promotions` rows with
`trigger_type='deployment_complete'`), which a synchronous snapshot-builder
call can't cheaply do, and the comment there explicitly notes staying at 0
avoids flipping the PO/CPO gate prematurely on a stale/wrong signal. Worth
fixing PROPERLY (e.g. a cached/synced local count, or accepting the network
call) but not as a quick mechanical add — same shape of work as item 1.

**3. `streak_days` — FIXED by OI-230's batch, noted here for completeness.**
Same missing-`current` pattern as `deployments`, but `WorkoutRepository.currentStreak()`
is a cheap, synchronous, already-used-in-this-file local reader (no network
call needed) — fixed directly as part of OI-230's fix rather than filed
here. See OI-230's closure note.

**4. `workouts` — dead by construction, not a modeling gap.** No `kRankGate`
entry ever sets `totalWorkoutsAtLeast` (F18, `rank_service.dart:18-19`), so
this key never enters `reqs` at all. Not a bug to fix — see OI-230.

**Why filed separately rather than fixed alongside OI-230:** item 1 needs a
NEW requirement type (`completion_rate`) threaded through `reqs`/`remaining`/
`binding_constraint`, PLUS a materially different ETA semantic for it — you
cannot estimate "N days until your completion rate is 80%" from a count the
way you can for streak/weeks/workouts, since it depends on the user's own
future adherence over a rolling window, not a monotonic count ticking down.
Item 2 needs either new sync plumbing or an accepted network call inside a
snapshot builder that is otherwise entirely synchronous/local. Both are
genuinely larger, riskier units of work than OI-230's binding-constraint
generalization — bundling them would have meant either a much bigger,
harder-to-review diff, or shipping OI-230's real fix later than necessary.

**Recommendation**: (1) For officer/MCPO ranks, thread `completionRateMinimum`/
`completionRateWindowWeeks` into `reqs` as a `'completion_rate'` requirement
type, with its `remaining` value expressed as a rate GAP (e.g. `0.80 -
actualRate`) rather than a count, and design an ETA response that's honest
about being adherence-dependent (likely still "cannot estimate a date," but
at least surfacing the current rate + target so the coach can reference
concrete progress). (2) For deployments, evaluate whether a client-side
cached count (synced periodically, accepting some staleness) is safer than
either the current always-0 or a live network call on every snapshot build.

## OI-241 — Cross-worktree concurrency: no lock prevents multiple sessions running full flutter test simultaneously, causing 3x+ slowdowns

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-22 · filed via mint_oi.sh from branch `claude/next-aab-decision-d1227b`

Investigated during this session after the founder asked why a routine commit was taking over an
hour: comparing `Get-Process`/`Get-CimInstance` CPU-time deltas across the machine's active Claude
Code worktrees showed genuine, growing CPU usage in OTHER sessions' `dart`/`flutter test`
processes running concurrently — one command line explicitly referenced a different worktree
(`supabase-outage-check-e79200`). `scripts/_git_lock.sh`'s mutex is keyed on
`$(git rev-parse --git-dir)/.safe_git_op.lock`, which for a linked worktree resolves to that
worktree's own private `.git/worktrees/<name>/` admin directory — structurally per-worktree, so it
cannot and does not prevent two DIFFERENT worktrees from running the full CPU-bound gate loop
(`flutter analyze` + `flutter test`) at the same time. On this 16-core machine with 3 sessions'
worth of contention, a normally ~2-minute `safe_commit.sh`/`safe_push.sh` run measured well over an
hour.

**Fix direction:** a cross-worktree lock (e.g. keyed on the shared `.git/` common dir rather than
the per-worktree admin dir) that limits how many `safe_commit.sh`/`safe_push.sh`/pre-push gate
loops run concurrently across ALL worktrees sharing one repo — the founder's own suggestion was
"at most one or two pushes at a time." Needs its own design pass (queueing vs. hard refusal,
timeout/staleness handling matching `_git_lock.sh`'s existing "no automatic reclaim" philosophy)
before implementation — not a one-line change, since it changes the concurrency model for every
session working in this repo simultaneously.

## OI-244 — Confirm-link tap left auth.one_time_tokens unconsumed — unexplained low email confirmation completion rate

- **Status**: OPEN — both web-path root causes now found + fixed, pending deploy; Android App Links piece still genuinely open
- **Blocked on**: (1) Vercel deploy authorization for BOTH f92d17 and 42a98d (2) founder Play Console check (Android App Links, unaffected by either code fix)
- **Verified**: 2026-09-23 — reproduced live on 2 real devices (see f92d17), then reproduced a SECOND, distinct failure live twice more post-deploy (see 42a98d)
- **Identified**: 2026-09-23 · filed via mint_oi.sh from branch `claude/oi-242-flaky-test-filing`

Founder forwarded a screenshot of `sumitk142003@gmail.com` hitting
"Email not confirmed" on sign-in, and reported having observed Sumit tap
the confirmation link and be shown what looked like a success/confirmed
state. Live SQL against `auth.users` (project `dedsavbjuwgarrhphgnl`)
confirmed `email_confirmed_at` is genuinely NULL, and `auth.one_time_tokens`
still holds the ORIGINAL, unconsumed `confirmation_token` row for this user
— a successful `verifyOTP` deletes/consumes that row, so whatever was shown
on screen, the confirmation call had not actually succeeded against
Supabase. `client_errors` telemetry has zero rows for this user's confirm
attempt (no success AND no failure event), so `AuthNotifier.confirmEmail`
was never observed completing either way.

Widening the query: of the last 9 real external signups (10-day window)
that ever had a confirmation email sent, only 1 (`chintamani78987@gmail.com`,
15 min) ever completed confirmation via email. 6 never confirmed at all,
some over a week old. No hour in the sample exceeded 2 signups (rules out
built-in-mailer burst rate limiting). Founder confirmed custom SMTP (Brevo)
is already configured, ruling out this repo's own documented "no custom
SMTP" cause (`lib/features/auth/CLAUDE.md`'s pitfall table) as the
explanation.

**Candidate causes, not yet distinguished — `auth.audit_log_entries` is
empty project-wide (0 rows), so there is no server-side trail to tell
these apart:**
1. Android App Link auto-verification failing open to a browser instead of
   handing control to the app (`autoVerify` intent-filter / `assetlinks.json`
   — see the existing `web_confirm_link_routing` class, diagnose 9c4e1a,
   which covers the WEB-side redirect once reached, but not why the call
   would fail to complete even there).
2. The founder glimpsing `ConfirmEmailScreen`'s loading state
   ("Confirming your account...") and reading the "CONFIRM ACCOUNT" header
   as a completed confirmation rather than an in-progress one.
3. A second signup/resend attempt invalidating the original link's token
   before it was tapped.

**UPDATE 2026-09-23 — root cause #1 (of two) found and fixed in code, not
yet deployed.** Reproduced live with the founder: signed up a fresh account
(avyaanshfit@gmail.com), tapped the real confirmation email link on an
iPhone (Safari) AND on the Android device with the app installed. BOTH
landed on `ConfirmEmailScreen`'s "This confirmation link is missing its
token" error — including on Android, where the tap opened a browser
instead of the app (App Links did not claim it — see candidate #1 below,
still unresolved). Isolated via direct `curl -D-` against the LIVE
production deployment: `vercel.json`'s `/confirm` redirect issues
`Location: /?token_hash=X&type=signup#/confirm` — the forwarded query lands
BEFORE the `#`, not inside it, so it's invisible to GoRouter's
HashUrlStrategy on every request, unconditionally, regardless of device.
This is the direct, concrete explanation for the 6-of-9 non-confirmation
finding above. Full writeup + fix:
`docs/diagnoses/2026-09-23-confirm-link-token-hash-lost-in-vercel-redirect-f92d17.md`.
Fix is a client-side `ConfirmLinkDetector` (mirrors the existing
`PasswordRecoveryDetector` pattern) — written, mutation-proven,
**NOT YET DEPLOYED** (needs explicit founder go-ahead for the Vercel prod
deploy per CLAUDE.md §4.3).

Candidate #1 above (Android App Links not claiming the URL) is now
CONFIRMED as real and STILL UNRESOLVED — reproduced on Android with the app
installed, link opened a browser. `AndroidManifest.xml`'s intent-filter and
`web/.well-known/assetlinks.json` (live-verified served correctly, 200,
correct fingerprints) both look correctly configured; likely explanation is
Google Play App Signing (this app ships via Play Console internal testing —
`memory/project_launch_blockers_1_inflight.md`) re-signing the APK with a
certificate not present in `assetlinks.json`'s two listed fingerprints —
**needs the founder to check Play Console → Setup → App integrity → App
signing key certificate → SHA-256** against `assetlinks.json`; not
checkable from this session. Candidates #2/#3 are superseded — the web
path failing unconditionally for everyone is sufficient explanation on its
own, so there's no need to separately adjudicate the founder's brief
glimpse or a resend-invalidation race.

A self-service "resend confirmation email" affordance shipped separately
(diagnose f6c2a9) as a mitigation regardless of this root cause — genuinely
useful once (1) is deployed, since a resent link would then actually work.

**UPDATE 2026-09-23 — root cause #2 (of two) found and fixed in code, not
yet deployed.** f92d17's fix went live; the founder immediately
re-tested by tapping a fresh, real confirmation email link — and hit a
DIFFERENT error ("This confirmation link is invalid or has expired."),
reproduced identically a second time from a fresh incognito window
(ruling out stale-cache/service-worker theories). Live `auth_logs` queries
across both reproductions showed the same account's `/resend` calls
succeeding (200) from the founder's device while **zero `/verify` requests
ever reached Supabase's Auth server** in either window — proving the
failure was generated client-side, without the link ever actually being
checked. Root cause: `AuthNotifier.confirmEmail` never called
`ensureSupabaseReady()` before touching Supabase, unlike its sibling
methods (`signInWithEmail`/`checkEmailRegistered`), which have used that
guard since 2026-04-04 — `confirmEmail` was written 2026-09-16, five months
later, and simply never got the same guard. `/confirm` is a top-level route
exempted from `_authRedirect` and NOT nested under `/splash` — the only
place `Supabase.initialize()` runs — so a cold tap on a confirmation link
(the normal case for a real user, not an edge case) races an uninitialized
`Supabase.instance`, whose not-ready guard is a bare `assert()` stripped in
release builds; the underlying `late SupabaseClient client` field then
throws `LateInitializationError`, landing in the generic catch-all and
showing "invalid or has expired" before any network request is attempted.
Full writeup + fix:
`docs/diagnoses/2026-09-23-confirm-email-supabase-not-ready-race-42a98d.md`.
Fix is one guarded line reusing the existing `ensureSupabaseReady()` helper
— written, mutation-proven (the mutated test reproduced the exact live
error string), **NOT YET DEPLOYED**.

Between f92d17 and 42a98d, both identified causes of confirmation calls
silently failing on the WEB path are now fixed in code. Once both are
deployed, the web fallback path (which is what any Android tap ALSO lands
on for as long as App Links fails to claim the URL — see below) should
work end-to-end for every real user, not just the founder's test accounts.
OI-244 stays OPEN because the Android App Links sub-issue is independent
of both fixes and still requires the founder's own Play Console check —
not something resolvable from this session.

## OI-247 — db_maintenance_nightly (jobid 41) fails every run: VACUUM cannot run inside a transaction block

- **Status**: OPEN
- **Blocked on**: the first nightly run after the fix (2026-09-27 03:30/03:40/03:43 UTC) — closes only on observed `succeeded`, never on the apply.
- **Verified**: 2026-09-26 — FIX APPLIED: migration 144 (`ops-alerting-batch-b`, diagnose `d6b2f9`) live at 20260926065733; `cron.job` 41 now holds the 4 cleanups and no VACUUM, new single-statement jobs 44 `jrd_vacuum_daily` (03:40) / 45 `client_errors_vacuum_daily` (03:43). Pending: the next runs' `cron.job_run_details` status.
  PRIOR (kept verbatim): 2026-09-26 — LIVE `cron.job_run_details`: jobid 41 `db_maintenance_nightly` failed every run 2026-09-22 → 09-26 with `VACUUM cannot run inside a transaction block` (pg_cron wraps a multi-statement command in one transaction).
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ci-green-batch-a` (backlog triage)

Fix shape: split the VACUUM into its own single-statement job. Also motivates OI-178 (SQL-job failures raise no alert).

## OI-248 — client_errors_spike trips on one device's offline telemetry-queue replay (alert counts rows, not users)

- **Status**: OPEN
- **Blocked on**: none — scheduled: batch B.
- **Verified**: 2026-09-26 — LIVE: the spike rows came from ONE device replaying its offline telemetry queue on reconnect; the alert threshold counts rows, not distinct users, so one device's backlog reads as an incident.
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ci-green-batch-a` (backlog triage)

Fix shape: count distinct users and/or exclude network-class errors; client side, classify offline errors before they are queued.

## OI-249 — 45 s restore-op timeouts on tiny tables on builds +45 to +47

- **Status**: OPEN
- **Blocked on**: none — P2, unscheduled.
- **Verified**: 2026-09-26 — LIVE client telemetry: restore ops on tiny tables hit the 45 s timeout on builds +45 to +47. Cause not yet investigated.
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ci-green-batch-a` (backlog triage)

Tables are small, so the timeout is not payload size; suspect connection/auth warm-up or serialised awaits.

## OI-250 — pg_cron self/correlated silence has no out-of-band watcher (146 cannot see itself or a whole-scheduler stop; cron.log_run dependency)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ops-alerting-b2a`
- **Problem**: OI-178's two alerts (145 `alert_sql_job_failures`, 146
  `alert_cron_job_silent`) both run INSIDE pg_cron. They cover each other only
  partly: 146 sees 145's job go silent, and 145 sees 146's job fail. Nothing
  sees 146 itself go silent, and nothing sees the case where pg_cron stops
  launching jobs at all (scheduler down, DB saturated as on 2026-09-21 e8b4a1,
  or all jobs stop together). Both alerts also read `cron.job_run_details`,
  which is written only while `cron.log_run = on`, a postmaster-context GUC.
  If it is ever switched off, 145 goes blind, and 146 pages every job, then
  re-pages every 23 h and again at the next :33 after each acknowledgement.
- **Fix shape**: a heartbeat checked from OUTSIDE pg_cron. For example, the
  SessionStart alert hook or an external uptime check reads
  `max(cron.job_run_details.start_time)` plus `cron.log_run` and complains if
  either is stale or wrong.
- **Class**: absence of a row reads as health (same family as OI-178, OI-179).
- **Source**: diagnose `f7a3d2` residual (2); 146 header residuals.

## OI-251 — Retention/vacuum effect is unobserved: return_message '1 row' hides DELETE counts; no retention/disk threshold in alerts/_thresholds.yaml

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `ops-alerting-b2a`
- **Problem**: the retention jobs (`db_maintenance_nightly` after 144 B1,
  `cleanup_cron_job_run_details`, and the others) report
  `return_message = '1 row'` whatever they deleted, because the command is one
  SELECT that wraps the DELETEs. So a job that deletes nothing, or everything,
  looks identical. 145 catches a retention job that FAILS, and 146 one that
  stops being LAUNCHED. Nothing catches one that runs "successfully" and deletes
  nothing (the 141→144 shape, where retention was dead for weeks). There is also
  no table-size or disk threshold in `alerts/_thresholds.yaml`.
- **Fix shape**: have each retention job return or log its per-table deleted
  counts (for example into `cron_call_log` or a `retention_runs` table), and
  add a threshold entry that alerts on zero deletions over N days where rows
  older than the retention window exist, plus a table-size growth alert.
- **Source**: OI-178's third aggravation; diagnose `f7a3d2` residual (4) and
  `b4c8e2`.

## OI-252 — Workout templates: one stable identity (delete/rename propagation, unit 2a)

- **Status**: OPEN
- **Blocked on**: founder on-device verification only. Everything else this entry previously
  listed as blocking (B-pass self-review, the merge to `main`) is done — see Verified below. This
  field went stale the same way OI-258's did (board not re-read after the work that closed it);
  corrected 2026-09-29 rather than left for a future session to re-discover.
- **Verified**: 2026-09-28 (superseding the 2026-09-27 note below) — merged to `main` in two
  waves (`82844bfd`, `43b89035`, final `d8832af8`), both self-triggered B-pass reviews on the
  reconciliation merges accepted (`docs/reviews/merge-reconciliation-82844bfd-review.md`: 3
  findings, 2 fixed + 1 false_alarm; `merge-reconciliation-43b89035-review.md`: 0 findings).
  Migration 145 confirmed live via `list_migrations` + `backups/applied_migrations.json`
  (`20260927011446`); migration 146 (same-unit B-pass Finding 1 fix, BEFORE INSERT OR UPDATE)
  also live (`20260927045029`). `restore-user-snapshot` (v7) and `workout-window-closing` (v15)
  confirmed deployed via `list_edge_functions` (`updated_at` matching the local payload-backup
  timestamps) AND a live `get_edge_function` source fetch matching the committed code
  byte-for-byte at the OI-252 markers. Full local suite green (6589 tests) at push time.
  PRIOR (2026-09-27, kept for record): implementation complete and gate-green: client restore
  rework across all three template_id-carrying restore paths, migration 145 applied live to
  dedsavbjuwgarrhphgnl (pg_trigger + information_schema.columns confirmed),
  `restore-user-snapshot` (v7) and `workout-window-closing` (v15) deployed and Deno-tested
  pre-deploy, `backups/applied_migrations.json` + `backups/live_schema_columns.json` updated,
  full `sh scripts/pre-commit.sh` reports OK. 10 new behavioral tests, mutation-proven on 3 legs.
  Diagnose-doc `docs/diagnoses/2026-09-27-deleted-workout-template-resurrects-via-restore-f4a8c2.md`.
- **Identified**: 2026-09-26 · filed via mint_oi.sh from branch `template-stable-identity`

Fix shape: migration 145 (add `deleted_at`, keep `UNIQUE(user_id,name)`, BEFORE UPDATE trigger renames on delete-transition + no-ops any write to an already-deleted row) + `restore-user-snapshot`/`workout-window-closing` EF updates + client rework of template create/push/restore/delete across `sync_workout.dart`, `template_service.dart`, `train_provider.dart`, `workout_write_service.dart`, plus a one-time legacy-key migrator. Saved meals (unit 2b, `reuse-audit-fixes` batch) reuse whatever this proves. Full design + 3 converged review rounds: `docs/superpowers/plans/2026-09-26-template-stable-identity.md`.

## OI-253 — PendingTemplateDeletes queued delete lost on logout/offline sign-out before it drains

- **Status**: OPEN
- **Blocked on**: a durable, cross-session delete queue design (own-scope unit, not part of OI-252)
- **Verified**: never
- **Identified**: 2026-09-27 · filed via mint_oi.sh from branch `template-stable-identity`

Symptom: `PendingTemplateDeletes` (`lib/core/services/pending_template_deletes.dart`) lives in
`userBox`, which is cleared on logout. A template deleted locally but not yet drained to a cloud
tombstone (offline, or the app closed/signed out before the next sync tick) loses its queued
delete entry — the local Hive row is already gone (deleted eagerly in
`WorkoutWriteService.deleteTemplate`), but the cloud row survives untouched and can resurrect on
a later restore, same class of bug OI-252 fixes for the identity-collision case. Fix shape
(not designed): either persist the queue somewhere that survives logout (a small dedicated table
keyed by user id, drained on next login for that user) or drain synchronously/best-effort on
sign-out before `userBox` clears. Surfaced during OI-252's B-pass (finding 7,
`docs/reviews/template-stable-identity-bpass.md`); documented as a known limit in
`pending_template_deletes.dart`'s class doc and the OI-252 diagnose-doc's `cross_account_guard`
field rather than fixed in that batch (narrow, pre-existing gap; not a regression from OI-252's
change, and no evidence it's hit in production yet).

## OI-256 — Profile field-level conflict resolution: per-field merge instead of whole-object overwrite (user_profile sync)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-27 · filed via mint_oi.sh from branch `single-owner-a2b`
- **Problem**: `_syncUserProfile` (`sync_profile.dart:226-229`) pushes the user's
  WHOLE Hive `user_profile` record to the cloud on every save, from FOUR call
  sites (`profile_write_service.dart:125`, `auth_session_bootstrapper.dart:685,807`,
  `restoring_screen.dart:584`, `induction_service.dart:121,221`). This is a blind
  whole-object overwrite with no per-field timestamp or version, so two writers
  touching the SAME record — two devices editing offline, a background job, a
  restore racing a live edit — can silently clobber each other with no conflict
  detection at all. Found while designing a2b-2 (coach chat extraction writing
  `diet_preference`/`lifestyle_activity`/`injuries`), but the bug is NOT specific
  to that feature — it already existed for plain two-device editing before any AI
  wrote to this table, and will recur for every future writer to `user_profile`
  (a2b-2 is being shipped on a narrower field-specific lock instead of waiting on
  this, per founder decision 2026-09-27).
- **Fix shape**: per-field (or per-row) timestamp/version metadata on
  `user_profile`, and a merge RPC (mirroring migration 123's
  `merge_notification_preferences` — `INSERT ... ON CONFLICT DO UPDATE` keyed on
  `auth.uid()`) that only touches fields that actually changed, instead of the
  current blind whole-object push. This is a genuine architecture change to core
  profile sync (bigger blast radius than any single feature), not a small patch —
  scope it as its own dedicated unit with its own ×2 plan review, not bundled into
  a feature batch.
- **Source**: found during a2b-2 design (single-owner batch, 2026-09-27); the
  underlying whole-object-overwrite pattern is `sync_profile.dart`'s existing,
  pre-AI design, not something a2b-2 introduced.

## OI-257 — Onboarding diet_preference default 'veg' doesn't match Edit Profile's chip vocabulary (non_veg/vegetarian/vegan/pescatarian/keto)

- **Status**: OPEN
- **Blocked on**: a product decision — change onboarding's default, or leave it and keep isVeg accepting both 'veg' and 'vegetarian' forever
- **Verified**: `lib/features/onboarding/screens/plan_screen.dart:520` writes the literal `'veg'` (documented product decision, `lib/features/onboarding/CLAUDE.md`: "diet_preference defaults to 'veg' (Indian-first default)"); `lib/features/profile/screens/edit_profile_screen.dart:1253-1259`'s `_buildDietPreferenceChips` options map is `{non_veg, vegetarian, vegan, pescatarian, keto}` — 'veg' matches NONE of them. A user who never visits Edit Profile carries `diet_preference: 'veg'` forever; the first time they DO open Edit Profile, `_dietPreference` loads as `'veg'` (line 225) and every chip renders unselected (`isSelected` false for all 5), which reads as a UI bug even though the underlying value is fine.
- **Discovered**: 2026-09-27, single-owner a2b-2 batch, while fixing the protein-gap-alert `isVeg` vocabulary bug (which checked only `"veg"`/`"vegan"`, never the REAL `"vegetarian"` value Edit Profile writes). Out of scope for that fix (isVeg now correctly accepts BOTH `'veg'` and `'vegetarian'`, so this is no longer a live correctness bug for that alert) — filed because the underlying vocabulary mismatch is real and independent of it.
- **Impact**: cosmetic (no chip highlighted) for any user who hasn't yet visited Edit Profile since onboarding, plus latent risk that a FUTURE reader of `diet_preference` assumes the 5-value Edit Profile vocabulary and mishandles `'veg'` the way `isVeg` used to. Not a data-loss or crash bug.
- **Reopen when**: a founder product decision is made — either change `plan_screen.dart:520`'s default to `'vegetarian'` (closing the vocabulary gap at the source) or explicitly accept `'veg'` as a permanent third vegetarian-family value everywhere `diet_preference` is read.
- **Identified**: 2026-09-27 · filed via mint_oi.sh from branch `single-owner-a2b`

## OI-259 — check_plan_review_record_exists.dart cannot parse hand-authored reconciliation-merge subjects

- **Status**: OPEN
- **Blocked on**: none (false-positive class, not a missing-review class — see Impact)
- **Verified**: 2026-09-28 — confirmed live on GitHub Actions, both failing commits, both
  underlying plan-review records
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `oi-reconciliation-merge-gap`,
  found while verifying CI for an unrelated push (`gate14-migration-collision`)

Symptom: CI run 36339457678 (push of commit `d8832af8` to `main`, 2026-09-27T18:07) FAILED its
"Plan-review record (>=account merge-to-main)" job with:
```
[plan-review-record] FAIL: 43b89035: could not recover merged branch from subject: 'Merge origin/main (ops-alerting-b2a2b) into local main -- second reconciliation, OI-254 client-side fix landed concurrently' (expected "Merge branch 'X'" or "Merge pull request #N from owner/X").
[plan-review-record] FAIL: 82844bfd: could not recover merged branch from subject: 'Merge origin/main (ops-alerting-b2a2a) into local main -- reconciles after template-stable-identity merge' (expected "Merge branch 'X'" or "Merge pull request #N from owner/X").
```
Both commits are hand-authored **reconciliation merges** — `git merge origin/main` run from local
`main` with a custom `-m` message, to fold in commits another concurrent session had pushed to
`origin/main` while this session's `main` had diverged (the exact §4.13/multi-session shape this
repo runs under routinely). `classifyMergeSubject()`'s three recognized shapes
(`scripts/plan_review_record_lib.dart:61,87,92`) all expect a GIT-GENERATED subject —
`Merge branch 'X'`, `Merge branch 'X' of <url>`, or `Merge pull request #N from owner/X` — none of
which match a hand-written "Merge origin/main (X) into local main -- ..." subject, so both fall
through to `MergeSubjectKind.unrecognized` and hard-fail, even though the diff range for each
merge IS correctly classified >= account tier (the gate reaches the parse step at all only after
that check passes).

Impact, checked rather than assumed: **this is a false positive, not a missing review** — both
merged branches, `ops-alerting-b2a2a` and `ops-alerting-b2a2b`, have real, converged plan-review
records (`docs/plan-reviews/ops-alerting-b2a2a.md`: `review_rounds: 3`, `verdict: converged`,
`bpass: accepted`; `docs/plan-reviews/ops-alerting-b2a2b.md`: `review_rounds: 2`,
`verdict: converged`, `bpass: accepted`) — the gate simply cannot recover either branch NAME from
the reconciliation commit's custom subject to go look for them. The existing
`MergeSubjectKind.remoteSyncMerge` case (`check_plan_review_record_exists.dart:606`) already
special-cases exactly this shape for the OTHER direction — "a `git pull` on main with divergent
local history" — but only when `ms.branch == 'main'` (i.e., the STANDARD git-generated
"Merge branch 'main' of <url>" subject from pulling main-into-main); a reconciliation merge that
NAMES the *other* branch it was folding in (as both of these do, in parentheses) does not match
that regex either, so it falls through past the exemption into `unrecognized`.

Practical consequence, checked: because CI evaluates only the PUSHED RANGE (`PUSH_BEFORE..HEAD`)
on each push, a subsequent clean push (this OI's own filing branch, and the preceding
`gate14-migration-collision` push, `70895e15`) does NOT re-encounter these two already-landed
commits and passes independently — so `main`'s LATEST push is not blocked by this. The residue is
narrower but real: (1) that specific historical CI run (`36339457678`) sits permanently red in
Actions history for a review that in fact happened; (2) the NEXT reconciliation merge with a
similarly-shaped hand-written subject will hard-fail its own push's CI the same way, and — unlike
this instance — a future reconciliation might not have every merged branch's plan-review record
already sitting on disk to fall back on if someone tries to work around it by hand.

Fix shape (not designed): widen `classifyMergeSubject()` with a new pattern recognizing
"Merge origin/main ([branch]) into local main" (and close variants of the reconciliation-merge
phrasing this repo's own sessions have now used at least twice) as a `remoteSyncMerge`-like kind
that extracts `[branch]` as the branch to look up, rather than requiring `ms.branch == 'main'`.
Needs care: the extracted name must still go through the same `recordSlug()` normalisation and
Dependabot/foreign-PR checks as `branchMerge`, since a hand-written subject is exactly the kind of
free-text a malicious or careless commit could use to smuggle an arbitrary string past the "branch
merge" trust model this gate is built on (see the gate's own `foreignPullRequest` handling for the
threat model it already defends against).
- **Class**: a keystone gate's merge-subject classifier enumerates GIT-GENERATED subject shapes
  only, and a legitimate, repo-sanctioned hand-authored merge shape (reconciling a diverged `main`
  across concurrent sessions, §4.13) falls outside all of them — the same "enumerated allowlist
  meets a real but unanticipated shape" class as `check_hive_first_pattern.dart`'s alias-set gap
  and `mint_oi.sh`'s original three-shape-only design, just for merge subjects instead of function
  calls or OI reservations.
- **Source**: GitHub Actions run 36339457678 (job 108676553930), discovered while confirming CI
  green for the unrelated `gate14-migration-collision` push (diagnose `d5f1b8`).

## OI-261 — displaced_<date> swap backups are local-only: never in plan_json or any cloud table, so swap-back on a new device silently loses the displaced template link

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-28 — `git grep displaced -- lib/core/services/sync/` returns nothing
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `day-swapper-sync-load`

Symptom: `displaced_<date>` is the backup `TemplateService.assignTemplateToDate` writes when a
template is assigned over a date that already held a workout, so removing the template later
brings that workout back. It has existed since 2026-04-10 (`708d2910`) and has only ever lived in
local Hive. `git grep -n displaced -- lib/core/services/sync/` finds nothing, no cloud table or
column holds it, and `_syncWorkoutPlan`'s bundle loop collects `schedule_` keys only. On a new
device or a reinstall, the template day restores through `plan_json`, but its backup does not, so
removing the template there brings back nothing. No error is shown. The day-swapper batch
(spec §5.1 row 4, §5.5) made the backup TRAVEL with the template when a day is swapped, which
makes the backup matter more, but did not create the local-only gap.
- **Class**: restore-completeness. A Hive key that carries user-meaningful state but belongs to
  no sync domain, the same class as the historical `_restoreXxx` gaps in
  `test/sync/restore_completeness_test.dart`.
- **Fix shape (not designed)**: carry `displaced_<date>` inside the `plan_json` bundle next to its
  `schedule_<date>` row (the only schedule vehicle that round-trips content), with the same L1/L3
  merge rules as the row it belongs to; or fold it into the row itself as a nested field so it can
  never be separated from it. Either way it needs a restore test in
  `restore_completeness_test.dart`.
- **Source**: Hermes E-pass, day-swapper-sync-load, findings h2F2 and h4F2
  (`docs/audit/2026-09-28-hermes-day-swapper-sync-load.md`).

## OI-262 — check_sot_registry_parity only checks N-M line_ranges: bare :NNNN citations and (push)/(pull)-suffixed ranges are never validated, and a wide range passes while pointing at the wrong span

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-28 — measured against the gate's own regexes (below)
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `day-swapper-sync-load`

Symptom, measured 2026-09-28 against `scripts/check_sot_registry_parity.dart`:
1. **Single-number ranges are never parsed.** The block regex at `:141` requires
   `line_range:\s*(\d+)-(\d+)`, so a `line_range: 137` entry matches nothing and gets neither the
   bounds check nor the method-location check. `grep -c "line_range: [0-9]\+ *$"
   docs/sot_registry.yaml` → **34** such entries.
2. **A method value with trailing text gets no symbol check.** `_extractSymbol` (`:79-97`)
   accepts only a backticked name or a bare/dotted identifier. `_syncStreaks (push) + restore
   merge`, `_syncSleepLogs (push)` and every `"X (confirmed :NNN; ...)"` prose value fall to
   case 3 ("prose — skip"), so a stale range on those entries is invisible.
3. **Bare `:NNNN` citations inside prose are never checked.** For example, the `sync_epoch`
   entry's "confirmed :1485" and "at :1532 and :1553". The day-swapper-sync-load batch re-derived
   these by hand three times in one day as edits above them shifted the file.
4. **A wide range passes while pointing at the wrong span.** The check only asks whether the
   method's signature falls inside `[start, end]`. On 2026-09-28, `mergeScheduleEntry` was cited
   `72-115` while it sat at `100-143`, and `_restoreScheduledWorkouts` was cited `2000-2296` while
   it sat at `2185-2524`. Both passed.
- **Class**: a green check is only as wide as its input set
  (`feedback_green_check_input_set_width`). The gate reports PASS over the subset it can parse,
  and that looks identical to a PASS over the whole registry.
- **Fix shape (not designed)**: accept `N` as `N-N`; extract the leading identifier from a method
  value before any `(` or space instead of skipping it as prose; add a `:NNNN`-in-prose resolver
  that at least checks bounds and names the nearest symbol; tighten (4) by requiring the cited
  start to be within a small window of the method's doc-comment or signature line. Each leg needs
  a mutation-proven test (the gate already has a rule-24 ledger entry).
- **Source**: founder-queued during the day-swapper-sync-load batch after repeated hand
  re-derivation of shifted citations.

## OI-260 — 4 sibling reportGeminiExhaustion-wiring tests (weekly-report/assess-body-composition/ai-media-proxy/rolling-context) share e35936's exact literal-string blind spot if any adopts an injectable geminiChatFn seam

- **Status**: OPEN
- **Blocked on**: none — fixable any time by whoever's own batch next touches one of these 4 files, or as a small standalone follow-up
- **Verified**: never
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `single-owner-a2b`, surfaced by the B-pass on diagnose `e35936`'s fix (`docs/reviews` — subagent finding, not yet written to a file; see that diagnose-doc's "B-pass findings" section for the exact verification)

**Not a live bug today** — all 4 functions currently call `geminiChat({...})` directly, confirmed via `grep -rn "geminiChat({\|geminiChatFn(" supabase/functions/{weekly-report,assess-body-composition,ai-media-proxy,rolling-context}/index.ts`. This is a latent-recurrence risk, the exact same shape diagnose `e35936` just fixed for `daily-snapshot`'s retry-pinning test, but on the OI-238 `reportGeminiExhaustion`-wiring tests instead:

- `supabase/functions/weekly-report/index_test.ts:44` — `source.indexOf("await geminiChat({")`
- `supabase/functions/assess-body-composition/index_test.ts:39` — `source.indexOf("await geminiChat({")`
- `supabase/functions/ai-media-proxy/index_test.ts:430` — `rawIndexSource.indexOf("await geminiChat({")`
- `supabase/functions/rolling-context/index_test.ts:69` — `source.indexOf("await geminiChat({")`

If ANY of these 4 functions is ever refactored to call Gemini through an injectable `geminiChatFn` parameter (the exact testability seam `daily-snapshot` adopted in unit a2a, `docs/plan-reviews/single-owner-a2.md`), that function's own test above goes blind with `callIdx not found` — but **fails LOUD**, not silently: `assertEquals(callIdx >= 0, ...)` throws, so CI/the full suite catches it immediately. This is why it's `OPEN`/not urgent rather than a P0/P1 — no silent coverage loss is possible, only a noisy, easily-diagnosed failure at the moment the hazard actually fires (which may be never).

**Fix, when picked up:** apply the exact same widening `e35936` did to `_shared/gemini_backoff_retry_test.ts`'s `assertSoleCallSiteHasRetries` — recognize either `geminiChat({` or `geminiChatFn({`, sum occurrences of both — to each of these 4 files' own call-site-finding logic. Four small, independent, mechanical edits; no shared helper currently links them (each function's `index_test.ts` has its own copy of this check, unlike the retries-pinning tests which share `assertSoleCallSiteHasRetries`).

**Reopen when:** one of the 4 functions actually adopts a `geminiChatFn`-style seam (its own test will fail loud at that point regardless of whether this OI was ever picked up first) — or on general principle at the next quarterly tech-debt audit (§4.10).

## OI-264 — docs/sot_registry.yaml is not valid YAML (35 parse errors); every gate reads it line-wise, so a real YAML consumer would fail

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-28 — PyYAML safe_load, iterated to 35 errors
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `day-swapper-sync-load`; found by the merge-resolution B-pass (`docs/reviews/6e4819de87d7-review.md`)

Measured 2026-09-28: `yaml.safe_load(open('docs/sot_registry.yaml'))` fails; commenting out each
failing line and re-parsing finds **35** errors before the file loads. They are already present at
merge base `7cb4eb78` (the first, a flow sequence `fields_read: [via … at :351, :357, …]`, dates to
`c854332b`). Three shapes account for the samples read:
1. **Double-quoted regex `pattern:` values** with backslash escapes YAML rejects
   (`"workoutBox\.put\('schedule_"` → "unknown escape character").
2. **Flow sequences holding prose** with `[`, `?` or ` :NNN` inside
   (`fields_read: [meals[], meals[].name, …]`).
3. **Unquoted `:` after a space** inside a flow item.

- **Why it has not bitten**: no consumer uses a YAML parser. `grep -l sot_registry` over
  `scripts/` and `test/` finds no file that also imports `package:yaml` or calls `loadYaml`; every
  gate (`check_sot_registry_parity`, `check_writeservice_contracts`, `check_sot_behavioral_test_paths`,
  …) reads it with line regexes.
- **Why it is not a quick quote-everything fix**: shape 1 strings are consumed VERBATIM by
  line-reading gates as regexes. Re-quoting them (single quotes, or doubled backslashes) changes the
  bytes those gates extract, so each gate reading `pattern:` must be checked or updated in the same
  change. That is a gate-semantics change and needs its own mutation-proven tests.
- **Fix shape (not designed)**: either (a) make the file valid YAML and move every gate onto one
  shared parser (removes the line-regex fragility OI-262 also records), or (b) rename it off `.yaml`
  and document it as a line-oriented format, so nobody reaches for a YAML parser. Add a gate that
  parses it, whichever is chosen.
- **Source**: day-swapper-sync-load, second merge of origin/main (2026-09-28).

## OI-265 — Boot-time healer needed for pre-existing exlog rows corrupted by the duration-controller-seeding leak (e8f95e) — reps_completed/duration_seconds duplication predates this fix and is not retroactively healed

- **Status**: OPEN
- **Blocked on**: none — needs its own writer/reader-chain analysis + regression test before pickup
- **Verified**: never
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `reps-secs-invalidation-fixes`, surfaced by the B-pass on diagnose `e8f95e`'s fix (`docs/reviews/b6f1837bf486-review.md` P1 — the diagnose-doc had claimed this was already "tracked via mint_oi.sh" when no such entry existed anywhere on either board; this OI is that missing filing, done for real)

Bug `e8f95e` (`docs/diagnoses/2026-09-28-duration-controller-seeding-leak-e8f95e.md`) stopped a
leak that fed a phantom duration into `_resolveLoggingType`'s data-shape fallback, mis-resolving
certain custom bodyweight exercises to `'timed'` and — via the separate pre-normalization-aggregate
bug fixed in the same batch — writing `reps_completed`/`duration_seconds` values that disagree with
the exercise's own `sets[]`. The fix is forward-only: any `exlog_*` row already written before this
fix landed keeps its corrupted aggregate fields.

**Fix, when picked up:** mirror bug `a4c7d1`'s Part 2 pattern (a boot-time or on-read healer) —
detect "this row's top-level `reps_completed`/`duration_seconds` disagrees with what `sets[]`
itself would fold to" and rewrite the aggregate fields to match `sets[]`. Needs its own
false-positive analysis first: a genuinely `'timed'`-resolved exercise SHOULD have
`duration_seconds` populated and `reps_completed` at 0, so the healer must distinguish "aggregate
disagrees with sets[] because of this bug" from "aggregate correctly reflects a timed exercise" —
likely by recomputing the aggregate from `sets[]` directly and comparing, not by pattern-matching
on which fields are non-zero.

**Reopen when:** picked up as a dedicated fix, or resurfaced by a live query on
`workout_log_exercises` showing the same `reps_completed == duration_seconds` duplication shape for
an account that logged before 2026-09-28.

## OI-266 — _resolveLoggingType never consults customBox/user_custom_exercises for a custom exercise's own logging_type — data-shape fallback can misclassify e.g. a custom weighted_bodyweight exercise as weight_reps

- **Status**: OPEN
- **Blocked on**: none — fixable any time by whoever's own batch next touches `_resolveLoggingType` or the custom-exercise creation path
- **Verified**: never
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `reps-secs-invalidation-fixes`, surfaced by the B-pass on diagnose `e8f95e`'s fix (`docs/reviews/b6f1837bf486-review.md` P1 — same missing-filing gap as OI-265; see that OI's note)

`WorkoutWriteService._resolveLoggingType` (`workout_write_service.dart`) resolves a custom
exercise's `logging_type` purely from data-shape inference (`hasDur`/`hasWeight` on the logged
sets) — it never consults `HiveService.instance.customBox`/`user_custom_exercises`, where the
exercise's OWN `logging_type` was already stamped at creation time (confirmed live during the
e8f95e investigation: `user_custom_exercises.logging_type = "bodyweight_reps"` for the founder's
"Single Leg Front Lever" exercise, never read here). For bug e8f95e itself this didn't matter — once
the duration-controller leak stops, the data-shape fallback resolves correctly on its own
(`hasDur` becomes `false`). But data-shape inference is structurally unable to distinguish some
type pairs: a custom `weighted_bodyweight` exercise (added weight + reps) has `hasWeight=true` just
like `weight_reps`, so it would resolve to the wrong type even with a perfectly clean input — no
duration-controller leak required.

**Fix, when picked up:** in `_resolveLoggingType`, look up the exercise's own `logging_type` from
`customBox`/`user_custom_exercises` FIRST (mirroring how the seeded library lookup already takes
priority over data-shape inference), falling back to data-shape inference only when the exercise is
in neither the seeded library nor `customBox` (a shape that should be rare/impossible in practice,
but the fallback should stay as the safety net it already is).

**Reopen when:** picked up as a dedicated fix, or resurfaced by a founder report of a custom
`weighted_bodyweight` (or similarly data-shape-ambiguous) exercise logging with the wrong type.

## OI-267 — weeklyReportDataProvider has no write-time invalidation across weight/meal/workout logs (3 domains, 15+ raw call sites) — only day-rollover invalidation was added; the sparkline can still show a just-logged entry's absence until the next unrelated rebuild

- **Status**: OPEN
- **Blocked on**: none — fixable any time; needs a per-domain call-site audit before pickup
- **Verified**: never
- **Identified**: 2026-09-28 · filed via mint_oi.sh from branch `reps-secs-invalidation-fixes`, found during plan-review round 1 of the day-rollover invalidation batch (`docs/plan-reviews/reps-secs-invalidation-fixes.md`) while independently verifying a different (false-positive) finding about `UserStatsNotifier`

`WeeklyReportDataNotifier.build()` (`lib/features/profile/providers/weekly_report_data_provider.dart`)
computes a rolling 7-day window from `DateTime.now()` directly and watches nothing except
`authUserIdTokenProvider` — confirmed via `grep -rn weeklyReportDataProvider lib/ test/` that it has
ZERO `ref.invalidate(weeklyReportDataProvider)` call sites anywhere in `lib/` (the day-rollover leg
added in the same batch that filed this OI is the FIRST invalidation this provider has ever had).
Its own doc comment already names the gap: "invalidate when the user logs a workout or meal if you
want the sparkline to refresh without an app restart" — aspirational, never wired. Since Profile
lives under `StatefulShellRoute.indexedStack` (never disposed on tab switch), once built this
provider can show a stale weight/calorie/protein/workout window for the rest of the app session,
even across new logs in all three domains it aggregates.

Unlike `weeklyNutritionProvider` (bug bae4dd, same batch) — which already had write-time
invalidation via `nutrition_provider.dart`'s `logFood` and was only missing the rollover leg — this
provider had NO invalidation at all until this OI's sibling fix added the rollover leg. The
write-time leg is a materially larger fix than the rollover leg: `HealthWriteService.logWeight`,
`NutritionWriteService.logMeal` and `WorkoutWriteService.markCompleted` are plain service methods
with no `WidgetRef`, so invalidation can't be added inside them — it has to be added at each
Riverpod-layer CALL SITE instead, and there are many: `logWeight` alone has 5 raw call sites
(`weight_log_sheet.dart` → `weightLogNotifierProvider.notifier.logWeight`,
`conversational_log_handler.dart`, `onboarding_provider.dart`, `home_provider.dart`,
`simulation_service.dart`); `logMeal` has 7 (`nutrition_provider.dart` ×2, `search_mode_body.dart`,
`barcode_scan_sheet.dart`, `scan_meal_section.dart`, `tool_dispatcher.dart`,
`simulation_service.dart`); `markCompleted` has 7 more. A fix needs to find EVERY Riverpod-layer
wrapper around each (mirroring how `nutrition_provider.dart:1081` wraps `logMeal` for
`weeklyNutritionProvider`) and add the invalidation there — or, better, audit whether a SINGLE
lower-fan-in wrapper already exists for each domain that all UI paths route through, to avoid
repeating the invalidation call at every one of the 15+ sites (which is itself the kind of
easy-to-miss-one pattern this whole batch's day-rollover 27-provider list already demonstrates).

**Fix, when picked up:** for each domain (weight/meal/workout), find the Riverpod-layer call site(s)
that wrap the raw WriteService call and add `ref.invalidate(weeklyReportDataProvider)` there —
verify with a live grep whether one narrow chokepoint exists per domain before assuming all 5-7
raw call sites need their own edit.

**Reopen when:** picked up as a dedicated fix, or resurfaced by a founder report of the Weekly
Report sparkline not reflecting a just-logged weight/meal/workout entry.

## OI-268 — contract_sweep sets TZ=Asia/Kolkata for its flutter child; on Windows the CRT reads that IANA name as UTC, so date contracts fail falsely

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-29 — same test, TZ unset PASS vs TZ=Asia/Kolkata FAIL
- **Identified**: 2026-09-29 · filed via mint_oi.sh from branch `day-swapper-sync-load`

Measured 2026-09-29 on the Windows dev machine (system timezone IST):
`flutter test test/contracts/logout_login_round_trip_test.dart --plain-name "Local ISO string"`
passes with `TZ` unset and FAILS with `$env:TZ='Asia/Kolkata'` (`Expected: '2026-05-09'
Actual: '2026-05-10'` — the fixed local input `2026-05-09T21:00:00.000` was read as UTC and
shifted into the next IST day). The Windows C runtime parses `TZ` as a POSIX `tzn[+|-]hh[:mm]`
string; an IANA name like `Asia/Kolkata` is not one, and the process silently runs as UTC.

- **Where it bites**: `scripts/contract_sweep.dart:30` passes `..['TZ'] = 'Asia/Kolkata'` in
  the Dart `Process` environment for its `flutter test` child. In the day-swapper-sync-load
  pre-push runs, the sweep reported failures in `logout_login_round_trip_test.dart` T1,
  `ai_snapshot_building_behavioral_test.dart`, `coaching_notes_behavioral_test.dart` (2),
  `coach_interaction_repository_only_test.dart` and `coach_memory_service_only_test.dart` —
  all of which passed in the same hook's full suite minutes later.
- **Why the full suite is unaffected here**: `scripts/pre-push.sh:151` sets
  `TZ=Asia/Kolkata flutter test …` from Git's `sh`, and those same tests pass there; the
  MSYS layer evidently does not hand the literal IANA string to the native process. Not proven
  beyond that observation.
- **Why it matters now**: the sweep is `--warn-only || true` today, so these are noise. OI-220's
  planned flip to hard-fail would turn them into a push-blocker on every Windows push.
- **CI is unaffected**: Linux glibc understands `Asia/Kolkata` (`test.yml:28`).
- **Fix shape (not designed)**: on Windows, do not set `TZ` in `contract_sweep.dart`'s child
  env (the system zone is already IST on the dev box), or set a POSIX form the CRT accepts
  (`IST-5:30`), and add a test that runs one IST-sensitive contract through the sweep's own
  spawn path on Windows. Check `pre-push.sh:151` with the same experiment before relying on it.
- **Source**: day-swapper-sync-load pre-push run, 2026-09-29.

## OI-269 — workout_log_exercises readers don't filter deleted_at (weekly-recalc + pr-detection fixed; 4 remain)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-29 · filed via mint_oi.sh from branch `oi-245-246-restore-fixes`

From the `oi-245-246-restore-fixes` batch's own adversarial review rounds 2 and 3 (B-pass).
Migration 150/151 (OI-246) added `workout_log_exercises.deleted_at` so a deleted exercise log
can be told apart from a live one. Two readers were fixed IN THIS SAME BATCH because the
delete-transition trigger's `exercise_id` suffix genuinely NEWLY broke them (not merely a
pre-existing gap):
- `weekly-recalc/index.ts` grouped by `exercise_id ?? exercise_name` for experience-level
  scoring — a deleted log fragmented into its own bogus single-entry "exercise" (inflating
  variety score). Fixed via `supabase/functions/weekly-recalc/live_log_filter.ts`'s
  `excludeDeletedLogs` (round 2 finding).
- `pr-detection/index.ts` (`composeMessage` in `message.ts`) interpolates `exercise_id`
  DIRECTLY into a push-notification body with **no `exercise_name` fallback** (unlike
  `i-see-you-callout`'s `exercise_name ?? exercise_id`), and the query had no `deleted_at`
  filter — so a PR logged and deleted inside the same ~20-min cron window would send a real
  push reading e.g. `"new Bench Press ‹del:a1b2c3d4› 100kg PR"`, leaking an internal id
  fragment + non-ASCII delimiter into user-facing copy. Fixed via
  `supabase/functions/pr-detection/live_pr_filter.ts`'s `excludeDeletedPrs` (round 3 / B-pass
  review A finding 1).

Four OTHER readers of this table still do not filter `deleted_at` at all. Verified
individually (not assumed): none of them render `exercise_id` raw to a user, so none share
pr-detection's display-corruption defect — these are correctness-only gaps (a deleted PR/log
still counted), unchanged by 150/151 relative to their pre-migration behavior:
- `supabase/functions/i-see-you-callout/index.ts:230` (`checkPRAfterBadSleep`) — safe:
  `exName = pr.exercise_name ?? pr.exercise_id ?? "that lift"` (`:264`) prefers the name.
- `supabase/functions/future-prediction/index.ts:68` (`liftPrediction`; uses
  `ilike("exercise_id", "%squat%")` wildcard substring match — a suffixed row's `exercise_id`
  still CONTAINS the searched substring, so this one would match a deleted row both before and
  after 150/151, unchanged either way, but is still worth fixing for correctness)
- `supabase/functions/weekly-report/index.ts:215` (7-day PRO AI report) — safe: selects/renders
  `exercise_name` only (`:246`, `:533`), never `exercise_id`.
- `supabase/functions/_shared/tools/progress/getProgressSummary.ts` (AI coach tool — volume +
  PR count) — safe: aggregates numeric counts, does not read or render `exercise_id`/
  `exercise_name` at all.

Two readers checked and found naturally immune (exact-ish `ilike` match against a known clean
name that a suffixed row can't match): `getPRTimeline.ts`, `getExerciseHistory.ts`.

**Reopen when:** picked up as a dedicated fix, or resurfaced by a founder report of a deleted
exercise log still influencing a PR alert, prediction, or the weekly AI report.

## OI-270 — PendingTemplateDeletes shares PendingExlogDeletes' fixed const-list mutation crash

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-09-29 · filed via mint_oi.sh from branch `oi-245-246-restore-fixes`

From the `oi-245-246-restore-fixes` batch (OI-246). `PendingExlogDeletes.add`/`.remove`
(`lib/core/services/pending_exlog_deletes.dart`, new this batch) initially called `.add()` /
`.removeWhere()` directly on `read()`'s return value, which is the `const []` literal
(immutable) on a fresh box — the very first exercise-log delete for any user would have thrown
`UnsupportedError` and failed the whole `deleteLog` call. Caught by this batch's own new test
on its first run, fixed by copying to a growable list first
(`List<Map<String, dynamic>>.of(read())`) before mutating.

The pre-existing sibling `PendingTemplateDeletes` (`lib/core/services/pending_template_deletes.dart`)
shares the IDENTICAL `return const []` shape in its own `read()`, and its `add`/`remove` still
mutate that return value directly — the same latent crash, unfixed, deliberately left out of
this batch's approved OI-245/OI-246 scope. Confirmed still present as of this filing (round-2
review re-checked and confirmed unchanged).

**Reopen when:** picked up as a dedicated fix — the repair is a one-line copy-to-growable-list
change, identical to `pending_exlog_deletes.dart`'s own fix, in each of `add`/`remove`.

## OI-271 — Edit Profile: emptying the Body fat % box does not clear the stored value (P3)

- **Status**: OPEN
- **Blocked on**: none — nothing external; founder deferred 2026-09-29 as non-critical (P3)
- **Verified**: 2026-09-29 — read `edit_profile_screen.dart:1869-1870` and `ProfileWriteService.patchProfile` (`profile_write_service.dart:86`); NOT reproduced on a device
- **Identified**: 2026-09-29 · filed via mint_oi.sh from branch `oi-154-profile-clear-tombstone` · found while scoping OI-154

**What**: Edit Profile builds its save map with `if (_bodyFatController.text.isNotEmpty) 'body_fat_percent': double.tryParse(...)`
(`edit_profile_screen.dart:1869-1870`). When the user empties the box, the key is simply
absent from the map. `patchProfile` is a MERGE (`profile_write_service.dart:86-96`), so the old
value survives in Hive. The clear never reaches local storage, let alone sync — a different
defect from OI-154, which is about a clear that DOES reach Hive and is lost in the cloud round trip.
`body_fat_assessed_at` has the same `!= null` guard (`:1871`), so the "last assessed" date also stays.

**Not the sync bug**: do not fix this by changing `sync_profile.dart:233` (`_hasNumber`). Nothing
reaches that line for a cleared box.

**Decision needed before coding (product)**: should emptying the box REMOVE the stored body fat
(and its assessed-at date), or keep it? If it removes it, the derived calorie targets
(`recalculateTargets`, Katch-McArdle vs Mifflin fallback — see `lib/features/profile/CLAUDE.md`
"Edit Profile silently recomputes calories" row and diagnose `c3f2d8`) must fall back to Mifflin
for that user, and a cleared `null` must then also reach the cloud, which lands on OI-154's sync
conflation (`_hasNumber(null)` is false, so the cloud keeps the old number and restore
re-hydrates it). So a real fix is either UI-only (keep-on-empty, with a message) or is
coupled to OI-154's design. Pick the first unless the founder wants removal.

**Reopen when**: picked up. Needs a diagnose-doc, a behavioral test on the save map, and a mutation run.

## OI-272 — Reconcile live prod migrations against the applied-migrations ledger (apply-time check; a live apply nobody recorded is invisible to every gate)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-09-29 — data below re-derived by plan-review round 3 and by a live `list_migrations` read; the design is NOT settled (three review rounds each broke the previous round's rules)
- **Identified**: 2026-09-29 · filed via mint_oi.sh from branch `migration-ledger-integrity`; carved out of OI-263 at founder direction

**What is missing.** Every gate goes file → ledger (`check_migration_ledger_paired.dart`, Gate 14).
Nothing goes live prod → `backups/applied_migrations.json`. The ledger is a per-branch copy of a
global fact, so a migration applied live from an unmerged branch (the 148/149 case, 2026-09-28)
is invisible to every other branch until merge. The one gate that compared live to the ledger
(`check_migrations_live.dart`) was retired under OI-223 because it could not pass: 125 of 139
migrations had been applied raw and never registered live.

**Why the first design (an apply-time preflight script, plan
`docs/plan-reviews/migration-ledger-integrity.md` D8) was cut** — three plan-review rounds, each
finding new defects introduced by the previous round's fixes:
- Live names are NOT reliably number-prefixed: 76 of 145 rows are prefixed, 69 are not
  (`alert_sql_job_failures`, `log_table_retention`, `usage_counters`), and prefixed numbers repeat
  (`050_` x2, `068_` x2). "Is N taken live?" cannot be answered from live names alone.
- The ledger is a thin bridge: 65 of 159 entries carry `slug`, 24 carry `cloud_version` and only 21
  of those are 14-digit (3 are prose such as `live-apply-2026-09-29`).
- Raw applies (`.claude/apply_migration_via_api.js`) never register a `schema_migrations` row, so
  a live list is structurally blind to that class.
- The `--live` snapshot is agent-supplied and no hook runs the script, so it is self-attested.
- Round-3 defects: the 145/146 exemption must cover the live-name leg too; a sibling branch that
  applied but has not merged serialises every other branch; "N" is undefined for letter-suffix
  files (`151b_`) across the legs.
- Round-3 measured a rule that IS neither always-red nor always-green on today's data: consider
  only live versions >= the ledger's earliest 14-digit `cloud_version` (20260905071759);
  accounted = version in the `cloud_version` set, OR name (`N_slug` / bare `slug`) equals a ledger
  `slug`, OR its N equals a ledger id. Result: 0 unaccounted rows today, and a live apply with no
  ledger entry still refuses. Starting point, not a decision.

**Framing for the redesign.** Treat this as reconciliation (detect an unrecorded live apply after
the fact, from somewhere the database is reachable) rather than a gate an agent must remember to
run first. A git hook cannot query prod. Needs its own plan and its own x2 review.

## OI-273 — Branch sweep for merged branches that never had a worktree here (retire_worktree --sweep-branches)

- **Status**: OPEN
- **Blocked on**: none — this unit's exclusion from its batch is a REVIEW OUTCOME, not a schedule: plan-review round 1 of the `branch-lifecycle-cleanup` batch (2026-09-29) returned two P0s against this unit and §4.12.1 says split and ship the converged piece. Once GitHub auto-delete is on and `retire_worktree` deletes its own local branch (OI-138), this unit covers only branches that never had a worktree here (cloud `claude/*`), so its value is lower.
- **Verified**: 2026-09-29 — every constraint below was reproduced by the round-1 reviewer in throwaway repos or read from the cited file; not re-run after filing
- **Identified**: 2026-09-29 · filed via mint_oi.sh from branch `branch-lifecycle-cleanup`

**What**: a `--sweep-branches` mode (dry-run default) that repeats the by-hand cleanup done 2026-09-29 (17 local + 55 remote merged branches, name→sha saved, every tip an ancestor of `main`). Outline: `docs/superpowers/specs/2026-09-29-branch-lifecycle-cleanup-design.md` §8 (the original v1 Unit 2 text was replaced by that section; this entry is the authoritative record of its constraints).

**Constraints found by round 1 — a design that ignores any of these is unsound:**
1. **Remote transport must be `gh api -X DELETE repos/<owner>/<repo>/git/refs/heads/<b>`, never `git push --delete` inside the tool.** `scripts/pre-push.sh:39-42` states analyze runs on `git push --delete` "deliberately"; `scripts/mint_oi.sh:316` already refuses git transport for `--prune` for this reason (analyze once PER ref, ~212 s each, and an untracked primary draft fails it). `gh api` has no compare-and-swap: re-read `ls-remote` immediately before each delete.
2. **A "merged + last commit older than 3 days" recency guard is WRONG.** `%(committerdate)` of a branch cut fresh with zero own commits is the date of the main commit it was cut from, and `ls-remote` gives no push time. After a quiet weekend a live cloud branch qualifies. Require positive proof for the exact tip: e.g. `gh pr list --state merged --head <b> --json headRefOid` equals the current remote tip sha, or the tip is the second parent of a merge on `origin/main`. This also covers "merged, then re-used".
3. **`gh pr list` needs `--state open --limit 1000 --json headRefName,headRefOid,headRepositoryOwner`** (default limit 30 truncates and fails open; compare owner, forks collide by name). Follow `scripts/reconcile_ci.dart:216-232`: return null, not an empty list, on missing `gh` / non-zero exit / unparseable output, and skip the remote half loudly.
4. **The e2e harness leaks the real `gh`**: `test/scripts/retire_worktree_e2e_test.dart:34-38` strips `GIT_*`, `GITHUB_*`, `PUSH_BEFORE` but not `GH_TOKEN` / `GH_REPO`, and keeps `HOME` and `PATH`. Tests need a stub `gh` first on `PATH`, `GH_*` stripped, and a private `HOME`. Never let a test reach real GitHub.
5. **`git branch -d` is not the safety guarantee.** It tests "merged into HEAD or upstream": with an upstream that contains the tip it deletes an UNMERGED branch (reproduced). The candidate list is the only guard for the sweep's local half, so it must be derived from `--merged main`, fully-qualified (`refs/heads/`), never `%(refname:short)` (a tag and branch of one name print `heads/T`), and passed after `--`. Protected-prefix matching must be case-insensitive.
6. **Multi-machine gap**: "not held by a worktree" sees only this clone's worktrees, not a laptop's.
7. Protected forever: `main`, `oi/*` (OI reservation refs, CLAUDE.md §7), `rescue/*` (unmerged unique work), `dependabot/*` (open PRs), any open-PR head.

**Reopen when**: picked up as its own plan with its own ×2 review. Needs a diagnose-doc, a bare-origin + stub-`gh` e2e, and a mutation run per guard.

## OI-274 — Vercel Flutter SDK re-clone on every build wastes ~1/3 of build time (no persistent flutter/ cache)

- **Status**: OPEN
- **Blocked on**: none — fixable any time; needs `scripts/vercel_build.sh` migrated to
  emit Build Output API v3 (`.vercel/output/config.json` with `"cache": ["flutter/**"]`)
  instead of the current simple `outputDirectory` config, built and tested against a
  non-`main` deploy before it touches `app.icanbefitter.com`
- **Verified**: 2026-09-30 — confirmed live via Vercel's `list_deployment_events` on two
  consecutive `avya` deployments (`dpl_HD8uzw6u...` main, `dpl_9qgumkdU...` preview)
- **Identified**: 2026-09-30 · filed via mint_oi.sh from branch
  `claude/sync-aab-build-check-408772`, found during a Vercel Pro billing-usage
  investigation (same investigation that shipped the `vercel.json` ignoreCommand fix,
  commit `8113406c`)

`scripts/vercel_build.sh:75-81`'s `if [ -d flutter ]` branch was written to reuse a cached
Flutter SDK checkout across builds "when Vercel's cache persists" — that condition was never
verified until now. Build logs for two back-to-back `avya` deployments both show the FULL
cold-start sequence on every single build: `Cloning into 'flutter'...`, a fresh 218.7 MB
Linux Dart SDK download, `Building flutter tool...`, `Resolving dependencies...`. Each
build's own upload afterward is `Uploading build cache [136.00 kB]` — nowhere near large
enough to hold a Flutter checkout, so whatever Vercel's default cache mechanism persists for
a `"framework": null` project, it is not the `flutter/` directory. The `if [ -d flutter ]`
reuse branch has therefore never fired in production.

Cost, measured directly from the two builds' timestamps: cloning + bootstrapping the Flutter
tool takes ~57-70s of each ~180s (3 min) build — roughly **a third of every single build**,
on top of the compile step (`flutter build web`, ~107-127s) which is inherent to the app's
size and not addressed by this fix.

Corrected the stale assumption in
`docs/superpowers/specs/2026-06-05-vercel-flutter-web-build-fix-design.md:147` (§8, "Out of
scope") in the same investigation — it had claimed the reuse path "already helps when
Vercel's cache persists" with no verification; that doc now records the confirmed finding.

**Fix, when picked up:** switch `scripts/vercel_build.sh` from relying on `vercel.json`'s
`outputDirectory` field to writing the Build Output API v3 format directly — build
`flutter build web --release` into a working dir, copy its output into
`.vercel/output/static`, and write `.vercel/output/config.json` with an explicit
`"cache": ["flutter/**"]` entry so Vercel actually persists the SDK checkout between builds.
This is a real change to how the deploy pipeline produces its output (not a config toggle),
so it needs its own test cycle against a non-`main` branch deploy before landing on `main`.

**Reopen when:** picked up as a dedicated fix, or Vercel build-minute spend becomes a
recurring concern again before this lands.

## OI-275 — Cut release-cycle wall-clock: a version-only bump runs the full suite 3x (pre-push x2 + CI) plus branch/PR/record; and the agent stops for petty approvals

- **Status**: OPEN
- **Blocked on**: none — founder directive 2026-10-01 is "cut the timing wherever possible, max autonomy"; this entry is the work item, not a question.
- **Verified**: 2026-10-01 — timings below are from the AAB +48 session (pre-push log `38:56` full-suite runtime, CI run `36772623448` Unit Tests 11m48s, jobs listed by `gh pr checks 63`); the exemption behavior is read from `scripts/check_plan_review_record_exists.dart` header (OI-58a) and not re-run.
- **Identified**: 2026-10-01 · filed via mint_oi.sh from branch `oi-fast-version-bump`

**What (measured, AAB 1.0.0+48 bump, 2 lines in 2 files):**
1. `pre-push` ran the full ~7,300-test suite (~40 min) on the bump push, then AGAIN (~40 min) on the review-record commit pushed afterwards — `blast_radius_from_diff.dart` classes the branch diff `platform` because `pubspec.yaml` / `app_constants.dart` are in the registry. CI then ran the same suite a third time (Unit Tests 11m48s). ~92 min of suite time for a 2-line diff.
2. The branch+PR path needed a `docs/plan-reviews/<slug>.md` record + a B-pass report, because `check_plan_review_record_exists.dart`'s version-bump exemption (`isVersionBumpCommit`) covers only single-parent direct-to-main commits, not a PR merge commit.
3. The run sat for hours because the agent ASKED the founder for a PR-merge yes at the end (auto-mode classifier "Merge Without Review" block) instead of surfacing every known gate up front. Founder: "ask me for permissions in the beginning; give max autonomy; no petty approvals."

**Acceptance (each is a deliverable, none optional):**
- A: a version-only diff (exactly `pubspec.yaml` `version:` + `app_constants.dart` `appVersion`, nothing else — verified by content, not by commit subject) classifies BELOW `account` in `docs/blast_radius.yaml` / `blast_radius_from_diff.dart`, so pre-push skips the full suite for it. Mutation-proven per §4.4 r24: a diff adding ANY other line must still classify `platform`.
- B: a documented one-push sequence for a bump (bump + record in ONE push) in `.claude/skills/build-apk/SKILL.md` Gate 2, so the suite never runs twice for one batch.
- C: `/build-apk` Gate 2 gains a "versionCode bump" fast path that names the exemption route and the classifier-blocked steps (PR merge) so the agent lists them in its first reply.
- D: a durable allowlist rule (settings.json) for `gh pr merge` on this repo's own branches once CI is green, if the founder grants it — otherwise the agent must request the go-ahead in its FIRST reply, never at the end. (Settings changes are the founder's; this item records the ask.)

**Constraints:** do not weaken the full-suite gate for any diff that touches code; the exemption must key on diff CONTENT (OI-58 subject-spoof history). Needs a diagnose-doc and a bare-repo e2e per §4.4.

**Reopen when**: n/a — open until A–D are each closed with a commit.

## OI-276 — Chat video analysis feature: nothing in the client uploads video (no picker, no compression package); design it (on-device key-frame extraction first, then re-encode or Files API) and align the PRO video cap/docs

- **Status**: OPEN
- **Blocked on**: founder prioritisation (`blocked_on_user`) — founder decision 2026-10-01 scheduled video analysis after the limits batch. **reopen_when**: the founder picks it up (no data dependency). This entry is the work item.
- **Verified**: 2026-10-01 — `grep -rn pickVideo lib/` is empty; `lib/features/ai_coach/screens/ai_coach/media_picker.dart` only calls `pickImage` (maxWidth 1920, imageQuality 85, `flutter_image_compress`); `pubspec.yaml` has no video/ffmpeg/compress-video package; the server path `supabase/functions/ai-media-proxy/index.ts` accepts video but applies the shared 5 MB `MAX_IMAGE_BYTES` (a 15 s iPhone 1080p clip is ~15 MB, 4K ~40 MB) so no real video could pass. The stale "client cap pickVideo maxDuration 30s" comment (F15 TODO, index.ts ~672) described a client that does not exist.
- **Identified**: 2026-10-01 · filed via mint_oi.sh from branch `gemini3-limits-caching`

**What:** video analysis is advertised only in internal docs (`business-rules.md` "photo / video analysis"); no client can produce it. Design it as a real feature. Options in order of recommendation: (1) on-device key-frame extraction (6–8 frames sent as compressed photos through the existing image path — no new infra, enough for exercise-form checks); (2) on-device re-encode to ~720p / 1–2 Mbps (new package, APK size gate L19); (3) server-side Gemini Files API upload (large files, Edge memory risk, 48 h retention).

**Acceptance:** a chosen design + plan-review record; the client path exists end to end (pick → reduce → upload → analyse → show); the PRO video cap (5/day after the limits batch) and the 5 MB byte rule are re-derived from the real payload; docs/paywall copy claim video only once it ships.

## OI-277 — Free-tier chat cost exposure after the Gemini 3.1 Flash-Lite move: re-measure real per-message cost and free 7/day worst case once cached-token data exists; revisit the free cap and prompt size

- **Status**: OPEN
- **Blocked on**: no real PRO/volume data yet — PRO only starts consuming `chat_app` ledger units when the gemini3-limits-caching migration is applied. **reopen_when**: 14 days after that migration apply (PRO ledger rows exist) OR sustained > 46 chat messages/day (the measured always-on explicit-cache break-even), whichever comes first. (Cached-token telemetry will read ≈0: the 5.8K prompt is below 3.1-flash-lite's implicit-cache minimum.)
- **Verified**: 2026-10-01 — inputs: measured avg chat `tokens_used` 13,610 over 12 rows (small sample, ~30% of Gemini rows log tokens, mixes primary + Lite-fallback rows); live `system_prompt_size` 24,338–24,420 chars in 13 of 14 recent log lines (~20.3K chars is the static Captain manual); 3.1 Flash-Lite paid price $0.25 in / $1.50 out per 1M (cached $0.025) from Google's pricing page via a summarizing fetch — re-verify. Coordinator arithmetic at ₹86/USD, 13.3K in / 300 out per message: ₹0.325/msg uncached, free 7/day worst case ₹68/user/month, PRO 20/day worst case ₹195.
- **Identified**: 2026-10-01 · filed via mint_oi.sh from branch `gemini3-limits-caching`

**What:** the founder's out-of-scope item (2): free-tier chat cost exposure. Once the free 7/day cap of the gemini3-limits-caching batch is live (Part B), it is bounded (≈₹2,200/month if all 33 free users maxed), but the per-message figure rests on a 12-row sample and an unmeasured cache hit-rate.

**Acceptance:** re-measure per-message cost from ≥ 2 weeks of logged cached/total tokens; state free worst case with a denominator; decide keep/lower the free cap and whether a prompt-size cut is warranted; close with the numbers.

## OI-278 — Telegram bot chat cap parity: bot is disabled; when re-enabled its cap (business-rules says 10/day) must follow the new free 7 / PRO 20 chat caps

- **Status**: OPEN
- **Blocked on**: the Telegram bot (separate OpenClaw VPS project, not in this repo) is DISABLED as of 2026-10-01 per the founder; this is `upstream_blocked` until it is re-enabled. **reopen_when**: the founder re-enables the bot.
- **Verified**: 2026-10-01 — `docs/architecture/business-rules.md:26` says the bot has "the same 10/day forever cap"; `enforce_chat_app_daily_limit` (live) counts only `channel='app'`, so a Telegram cap, if any, lives outside this repo.
- **Identified**: 2026-10-01 · filed via mint_oi.sh from branch `gemini3-limits-caching`

**What:** when the bot is re-enabled, its chat cap and its model path must match the app's (free 7 / PRO 20, 3.1 Flash-Lite, shared `usage_counters` key or an explicit separate budget).

**Acceptance:** re-enable checklist run (cap source located, model constants, quota key, copy); business-rules line corrected; reopen_when: the founder re-enables the bot.

## OI-279 — Phase 1b: pull-on-resume - a backgrounded device refreshes itself (7-day window, pull-before-reckon ordering, pending-delete-aware exercise-log restore, per-set fetch must fail the pull, own refresh signal) - split out of resilient-client Phase 1 by 4.12.1

- **Status**: OPEN
- **Blocked on**: Phase 1 (e5b2a9) merged to `main`; needs its own plan and two context-blind review rounds before any code (CLAUDE.md 4.12.1: Unit C failed two plan-review rounds on DESIGN, so it was split out instead of patched a third time).
- **Verified**: 2026-10-02 - read on the branch: the draft `docs/superpowers/plans/2026-10-01-resilient-client-phase1b-resume-pull-DRAFT.md`; `day_rollover_service.dart:174-177` (the streak-decay reckon runs on local data; gated on `restoreCompletedTick > 0` when this was written, since 2026-10-06 (b4e7a1) on the per-account `SyncService.restoreSettledForCurrentUser`); `sync_workout.dart:861` (`_restoreExerciseLogs`) with the per-set fetch failure swallowed at `:890-895`; `pending_exlog_deletes.dart:22`; `sync_service.dart:1838-1841` (`restoreCompletedTick`, `bumpRestoreCompleted`). Not run on a device.
- **Identified**: 2026-10-02 · filed via mint_oi.sh from branch `claude/resilient-client-phase1`

After Phase 1 a failed push reaches the cloud on its own, but a SECOND device (an Android phone that is backgrounded, not closed) still only picks up another device's changes at its next cold start. Phase 1b is the resume-time pull that closes that gap.

Requirements the Phase 1 plan reviews established (all carried in the draft file):
1. Pull BEFORE the streak-decay reckon: `reckonStreakDecayAndPersist` (`workout_repository.dart`, called from `DayRolloverObserver._doRolloverWithRef` in `day_rollover_service.dart`) runs on stale local data today; a pull started after it does not help.
2. Skip rows whose delete is still queued in `PendingExlogDeletes`: a local-wins pull otherwise RESURRECTS an exercise log the user deleted while the backend was down.
3. A failed per-set fetch must FAIL the pull, not write a set-less exercise log that local-wins then never heals (`sync_workout.dart:890-895` swallows it today).
4. Its own refresh signal: `restoreCompletedTick` is bumped only by the background-restore heal (LAST, through `DayRolloverObserver.reckonAndNotifyAfterRestore`, since b4e7a1) so it cannot double as "the pull wrote something". UPDATED 2026-10-06 (b4e7a1): it no longer gates the streak-decay reckon (the per-account marker `restoreSettledForCurrentUser` does). That marker is process-lifetime and NOT freshness-bounded, so a pull-on-resume must call `reckonStreakDecayAndPersist` only AFTER the pull settles (closure ledger `docs/audit/streak-freeze-restore-ownership.closure.yaml`, RESIDUAL-FRESHNESS names this OI as its reopen condition).
5. A failure counter so a failed op aborts the pull, sharing the Phase 1 backoff / paused state.
6. Scope: a recent window (7 days in the draft) via direct RLS queries, no migration, no edit to the catastrophic-tier `restore-user-snapshot` EF; never meals (OI-281) and never the scheduled-workout overlay (it can wipe an unpushed swap).

7. (added 2026-10-04 by swap-title-and-launch-refresh, OI-284) After the pull restores any workout log, call `CompletedTitleHealer.run()` (local-only, no network; makes a completed non-template row's title follow its own `wlog_<date>`) - the heal is hooked into the full-restore entry points, NOT the resume path, so the pull must call it itself. It must NOT bump `restoreCompletedTick` (item 4); the pull's own tick is what refreshes the UI. The restore wrapper in that plan also adds a separate `restoreRefreshTick` for failed/cancelled full restores; the mixin listens to both, so rebase the listener list together.

Items 2 and 3 live in the SHARED writer `_restoreExerciseLogs`, so the cold-start restore has the same exposure: Phase 1b VERIFIES that and fixes it at the writer, not only in the pull. Water and a stale device's overwrite stay with OI-280.

## OI-280 — Phase 2 multi-device delta sync: updated_at+deleted_at on every synced table, per-table cursor, conditional push, water as per-drink entries, cold-start restore replaced by a cursor delta (the since=2020-01-01 full-history restore re-runs on every swipe-away); also the fixed 3 s splash floor

- **Status**: OPEN
- **Blocked on**: Phase 1b (OI-279) merged; needs the founder's go on the delta-sync design and per-action authorization for each live migration apply (the `updated_at` / `deleted_at` columns).
- **Verified**: 2026-10-02 - read `backups/live_schema_columns.json` (live-schema snapshot): `water_logs` has `created_at` + `updated_at`; `weight_logs`, `scheduled_workouts`, `streaks`, `nutrition_logs` and `workout_logs` have only `created_at`; none has `deleted_at`. `sync_service.dart:1776` and `:1902` hard-code `since = '2020-01-01T00:00:00Z'` for the cold-start restore; `splash_screen.dart:111-112` waits a fixed 3000 ms. Not measured on a device.
- **Identified**: 2026-10-02 · filed via mint_oi.sh from branch `claude/resilient-client-phase1`

Design (founder-locked 2026-10-01): a server-set `updated_at` + `deleted_at` (tombstones) on every synced table; a per-table cursor and per-row base version on the client; a CONDITIONAL push (`where updated_at = base`) so a stale device's later write cannot silently win - a timestamp alone does NOT fix that; on conflict pull + merge + retry. Water becomes per-drink ENTRIES (summed), not a per-day `total_ml` (an increment cannot be told from an absolute set). Merge rules: add-only entries = union; a per-key value = newer wins; forward-only state (schedule status, rank, phase) keeps its existing field rules; settings = field-level newer wins.

Also owned here, found while building Phase 1 and NOT changed by it:
- The cold-start restore is a full-history restore (`since = '2020-01-01T00:00:00Z'`, `sync_service.dart:1776` and `:1902`) and re-runs on EVERY swipe-away (a swipe-away is a cold start). The fix is a per-table cursor delta; a cold-start cooldown is only safe once Phase 1b's resume-pull exists, otherwise a cooled-down device would never refresh.
- The fixed 3 s splash floor (`splash_screen.dart:112`): Phase 1 evidence-first routing skips the routing-read wait but not this floor.

Out of scope by founder decision: a standby database; backups wait for the Supabase Pro upgrade.

## OI-281 — Meal deletes never reach the cloud: NutritionWriteService.deleteLog is local-only, so _restoreNutritionLogs resurrects deleted meals at cold start

- **Status**: OPEN
- **Blocked on**: needs a cloud tombstone (`deleted_at`) on `nutrition_logs`, or a cloud delete from `deleteLog`, plus a reader filter - a migration, which needs the founder's per-action apply authorization.
- **Verified**: 2026-10-02 - code read, NOT reproduced on a device: `NutritionWriteService.deleteLog` (`nutrition_write_service.dart:493`) removes the Hive key and fires `syncNutritionData()` / `pushSnapshot()`; the only cloud `.delete()` in `sync_nutrition.dart` is the `nutrition_log_items` vacuum for item indexes past a log's current count (`:403-406`), so a deleted LOG never leaves the cloud; `_restoreNutritionLogs` (`:609`) writes back a cloud row whose local key is absent (legacy path `:768-771`).
- **Identified**: 2026-10-02 · filed via mint_oi.sh from branch `claude/resilient-client-phase1`

A meal the user deleted can come back at the next cold start, because the delete is local-only and the full-history restore re-adds every cloud row it does not find locally. Same restore-completeness class as the exercise-log delete. Phase 1b deliberately does NOT pull meals for this reason (a resume pull would resurrect them faster).

Fix shape: a cloud tombstone (or a cloud delete) written by `deleteLog`, and `_restoreNutritionLogs` skipping tombstoned rows. Needs a migration, so it is also part of the OI-280 tombstone work if that lands first.

## OI-283 — Live-DB SQL harness runners (check_onconflict_live_arbiter, check_two_user_cross_account) have no automated runner: CI holds no Management API token

- **Status**: OPEN
- **Blocked on**: founder decision: provision a CI secret holding a Management API token for the fitness project (OI-165, now closed, fixed the LOCAL token resolution; CI is a separate matter)
- **Verified**: 2026-10-02: both runners work by hand (probe via `check_onconflict_live_arbiter.dart` returned OK from a linked worktree); neither has a runner in `pre-commit.sh` or `test.yml`
- **Identified**: 2026-10-02 · filed via mint_oi.sh from branch `deploy-token-path`
- **Why**: `scripts/check_gate_scripts_wired.dart` allowlists both scripts as `manual:` runners; the allowlist needs an OPEN OI. They are the only behavioural proof for Postgres trigger logic (rule 21), and run only when a human remembers.
- **Options**: (a) a CI job with a read-only-scoped Management API secret running the rollback-only SQL files; (b) keep them manual and document the runbook line. Either way this OI names which.

## OI-284 — Completed day-swap row keeps its pre-swap title after a cross-device restore: completed-row merge freeze (FIX IMPLEMENTED on branch swap-title-and-launch-refresh 2026-10-04 - stays OPEN until the founder's device check)

- **Status**: OPEN
- **Blocked on**: the founder's on-device check (an APK built from `main` after the merge). Implemented: `CompletedTitleHealer` (plan `docs/plans/swap-title-and-launch-refresh.md` v3, diagnose `d4a7e1`) heals a completed non-template row's title from its own `wlog_<date>` after a succeeded full restore. UNPROVEN: which `source` the phone's `wlog_2026-10-01` carries - if it is the synthetic `cloud_restore_completion` (copied from the stale completions name) the heal will not fire there and the optional live repair of the Oct 1/2 `plan_json` rows is the fallback. Close this OI only after the check.
- **Verified**: 2026-10-03 - live rows (user d7a67a37): phone row 2026-10-01 completed 'Push + Core' while `wlog_2026-10-01` = 'PULL + CORE'; writer `PlanIntegrityReconciler.mergeScheduleEntry` completed-row early return (`plan_integrity_reconciler.dart:104-106`). How the phone reached completed-before-merge order is unproven; capturing it needs OI-293 (restore outcomes observable on a release device).
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-285 — mergeScheduleBundleIntoHive decides snapshot winners once before the loop and puts with no per-date lock: a swap or completion committed mid-restore can be overwritten by an older snapshot row

- **Status**: OPEN
- **Blocked on**: its own plan + review; touches the restore merge (platform tier).
- **Verified**: 2026-10-03 - code read: `mergeScheduleBundleIntoHive` (`plan_integrity_reconciler.dart:~243-300`) computes `snapshotArrangementWinsKeys` once before the loop and awaits a `put` per key with no `_acquireLock(date)`; not reproduced on a device.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-286 — Replaced-swap notice: a device whose local swap loses to a newer cross-device arrangement gets no notice (Wardroom copy; dedupe per week+stamp)

- **Status**: OPEN
- **Blocked on**: OI-285 (the notice needs the per-week re-decide); Wardroom copy review.
- **Verified**: 2026-10-03 - code read: L3 arrangement-wins replaces a local swap silently; no user-visible signal exists.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-287 — Day-swap allowance is per-device: a swap on web leaves the phone showing the full weekly allowance; usage_counters has no client read path (needs EF read mode or RLS policy)

- **Status**: OPEN
- **Blocked on**: founder go on the read path: `usage_counters` has no RLS policy, so the read needs a `consume-day-swap` read-only mode (EF deploy = its own prod go) or a migration adding an owner-SELECT policy (apply = its own go).
- **Verified**: 2026-10-03 - live: phone daily snapshot `swaps_left`=3 after a web swap while `usage_counters` day_swap used=1; `DaySwapAllowance` (`day_swap_allowance.dart:47-62`) reads only the per-device userBox copy, corrected only by its own `consume-day-swap` reply.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-288 — Discipline: accepted-residual wording in tests pinned a defect as correct (restore_merge_invariants R2); narrow residual-text gate + lens L55 + two-device walk row in §5

- **Status**: OPEN
- **Blocked on**: its own L-tier branch (root CLAUDE.md + LENS_REGISTRY count spots); grandfather list decided in its plan.
- **Verified**: 2026-10-03 - `test/sync/restore_merge_invariants_test.dart:539` pins the completed-row freeze as an accepted residual; spec day-swapper-design §5.7 calls it correct; the founder observed it as a bug 2026-10-01.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-289 — Nutrition cross-device probe: verify meal add/edit/delete converge web<->phone after restore (deletes tracked in OI-281); probe only

- **Status**: OPEN
- **Blocked on**: the founder running the two-device walk (web + phone, same account: add / edit / delete a meal on one, then launch the other) - the probe needs the founder's real devices; findings are filed as their own OIs; delete resurrection is already OI-281.
- **Verified**: never - asked by the founder 2026-10-01 ('check nutrition from this perspective'); not yet probed.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-290 — DaySwapRules leaves week_number unclassified (travels as content); hygiene - no observed symptom, week is already identity

- **Status**: OPEN
- **Blocked on**: founder call - close as no-symptom hygiene, or fix with a non-vacuous test; low value: no reader of `week_number` in lib, push reads `entry['week'] ?? entry['week_number']` (`sync_workout.dart:2093`), restore mirrors it from `week` (`:2567-2568`).
- **Verified**: 2026-10-03 - `day_swap_rules.dart:17-28` identity set contains 'week' but not 'week_number'; two round-4 plan reviewers found no observable symptom. A test must use DIFFERENT week/week_number values on the two rows or it passes vacuously.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-292 — morning-alert push names a workout from YESTERDAY's snapshot: the 02:00 IST generate reads user_daily_snapshots for yesterdayIST, whose today_workout_name was built on the upload day; today it is masked by the generic 'workout' fallback, a real name needs a date-correct source (week_lookahead[1] or a dated key)

- **Status**: OPEN
- **Blocked on**: a design decision on the date-correct source (client-side dated key vs `week_lookahead[1]` read in the EF); an EF change ⇒ deno check + its own prod deploy go.
- **Verified**: 2026-10-03 - `supabase/functions/morning-alert/index.ts:236-243` selects `snapshot_date = yesterdayIST`; generate runs 02:00 IST (`docs/operations/CRON_REGISTRY.md` row 015); `supabase/functions/daily-snapshot/index.ts:631` stores under `getTodayIST()`; `ai_snapshot_builder.dart:1103-1114` builds `today_workout_name` for the upload day; `message.ts:19,31-74` interpolates it unsanitised. Coach is NOT affected: it reads `week_lookahead[0].name` (`ai_snapshot_builder.dart:~1307`, `DaySwapCopy.titleOf`). Any push-facing name must also filter status (travel/paused/moved rows keep a workout type, `swap_service.dart:697-698`) and match TS `sanitizeIdentifier` (`_shared/sanitize_for_prompt.ts:156-175`).
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-293 — Restore outcomes are unobservable on a release Android device: _restoreWorkoutPlan returns void and swallows errors, a failed launch-path fetch returns [] (same as no data), and any local breadcrumb needs a reader (allowBackup=false, no diagnostics surface)

- **Status**: OPEN
- **Blocked on**: its own plan: the outcome must distinguish fetch failure (`_fetchUserProgressRowForRestore` returns `const []`, `sync_service.dart:1661-1677`) and the record must have a READER the founder can reach on a release build.
- **Verified**: 2026-10-03 - `android/app/src/main/AndroidManifest.xml:25` allowBackup=false; `userBox` exports only `profile` (`export_data.dart:11`); `_deletedTemplateCloudIds` swallows to `const {}` (`sync_workout.dart:1785-1793`) so a template-lookup outcome is unreachable (UPDATED 2026-10-06, b4e7a1: that catch now also notes `RestoreFailureCollector`, an in-memory per-call sink of the streak-critical op failures that drives ONLY the streak-decay marker; it is NOT the plan-level outcome record or the reader this OI asks for); a slow restore outlives `_safeRestoreOp`'s timeout (`sync_service.dart:~2648`) so any per-user write needs a userId guard. Round-5 review of swap-cross-device-reconcile v5 (U6 split out).
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-294 — A cold-start restore that never returns (killed or hung mid-restore) leaves the UI on pre-restore rows: the only tick bump is the success-only heal_after_restore (CORRECTED TWICE 2026-10-04: a normal cold start already refreshes on success, and a failed/cancelled RESULT after partial writes is almost unreachable)

- **Status**: OPEN
- **Blocked on**: its own plan (split out of swap-title-and-launch-refresh by plan round 2, CLAUDE.md 4.12.1). Design must: (1) refresh at a step boundary or in a `finally`, not on a returned `RestoreResult` (a wrapper that acts on `!result.succeeded` almost never fires - see Verified); (2) use a SEPARATE tick (UPDATED 2026-10-06, b4e7a1: `restoreCompletedTick` NO LONGER gates streak decay, the per-account `SyncService.restoreSettledForCurrentUser` does, and the tick is bumped last by `DayRolloverObserver.reckonAndNotifyAfterRestore`; a separate tick is now cleaner, not a correctness requirement); (3) skip when the owner changed (a refresh during an account-switch cancel invalidates providers while boxes swap); (4) share ONE generic data-refresh listenable with Phase 1b/OI-279 (its draft wants `resumePullTick`; D7 bumps `restoreCompletedTick`, contradicting its own requirement 4); (5) add a real test seam - `restoreFromCloudForUser` in `SyncHarness` always returns `failed('No authenticated user')` at `sync_service.dart:1886` because `SupabaseClient(url,key)` has no session.
- **Verified**: 2026-10-04 - code read, NOT reproduced on a device. Premise 1 (cold start): `splash_screen.dart:312` routes every authenticated cold start to `/restoring`, which starts a FULL `restoreFromCloudForUser()` and, only `if (result.succeeded)`, runs `_healAfterRestoreInBackground` -> `bumpRestoreCompleted()` (`restoring_screen.dart:327-334`, `heal_after_restore.dart:74`). Premise 2: `_safeRestoreOp` (`sync_service.dart:2681-2714`) swallows every per-op error AND timeout, so a failing step never makes the restore `failed`; single-call faults fall back to the legacy fan-out; the other `failed` returns (`:1886` no user, `:1911` openForUser) are zero-write; `cancelInflightRestore` has two callers, both in `restoring_screen.dart:143,223` for new/mid-onboarding users (nothing to refresh). So the founder's outage mornings (`restore_started` 05:48Z and 06:24Z with no `restore_completed`) were a restore that never RETURNED (process kill or a hang - un-ceilinged candidates: `ensureFreshToken` at `:1925` outside the try, `SubscriptionService.refreshFromSupabase` at `:2052`). Unreproduced; needs OI-293-style evidence.
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`; corrected twice 2026-10-04 from branch `swap-title-and-launch-refresh`

## OI-295 — Schedule writers that pass no WidgetRef (deload_evaluator lift via upsertScheduled; lazy writes in workout_schedule_read_service) can change today's row without invalidating todayWorkoutProvider, leaving Home's Today card and insight stale until another invalidation

- **Status**: OPEN
- **Blocked on**: an audit of every ref-less schedule writer (which can touch TODAY's row, and when they run) and a choice of signal (a ref-free invalidation hook vs `restoreCompletedTick`-style notifier); overlaps OI-294.
- **Verified**: 2026-10-03 - code read, not reproduced: `lib/core/services/deload_evaluator.dart:223` calls `WorkoutWriteService.instance.upsertScheduled(...)` with no `ref`; `upsertScheduled` invalidates only `if (ref != null && onInvalidate != null)` (`lib/core/services/workout_write_service.dart:661`); lazy writes in `lib/core/services/workout_schedule_read_service.dart:~278-577` (round-6 review of swap-cross-device-reconcile v6). The Home insight is now exactly as stale as the Today card in these cases (it watches `todayWorkoutProvider`).
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `swap-cross-device-reconcile`

## OI-301 — No gate stops a stray file at the repo root: existsSync (14 bytes of junk) and build_log.txt (a Gradle console capture) were both committed and sat on main

- **Status**: OPEN
- **Blocked on**: its own plan + review (a new `scripts/check_*.dart` gate is platform tier: two plan-review rounds, and CLAUDE.md §4.4 rule 24's mutation-proven test, `docs/audit/gate_test_ledger.yaml` entry and wiring); the plan must first settle what is legitimate at the root, see below. Kept out of the OI-282 batch because adding it there would restart that batch's review (§4.12.1).
- **Verified**: 2026-10-03 - `git ls-files` at the repo root listed both: `existsSync` (14 bytes, content `M1 js isFile-`, added by `987ce09b` / PR #68; the content matches a mutation-log line in `docs/reviews/deploy-token-path-bpass.md`, so most likely an unquoted `->` in an echo) and `build_log.txt` (143 bytes, a `flutter build apk` console capture added by `0b609654` on 2026-03-31, referenced nowhere). A search of `scripts/check_*.dart`, `scripts/pre-commit.sh`, `scripts/pre-push.sh` and `.github/workflows/test.yml` for any root-file check found none (a grep, not an exhaustive proof). Both files are removed by the OI-282 batch (branch `oi282-blast-radius-globs`).
- **Identified**: 2026-10-03 · filed via mint_oi.sh from branch `oi282-blast-radius-globs`

The repo root has no allowlist, so a command that writes a file there (a stray shell redirect, a build log) is committed by the next `git add -A` and nothing objects. Fix shape: a `check_repo_root_allowlist.dart` pre-commit and CI gate that fails when a tracked root-level path is not in a short allowlist, run warn-only first (§4.11). The root FILES are easy (21 today: everything `git ls-files | grep -v /` lists except those two). The open question is the root DIRECTORIES: HEAD tracks 21 (`.claude`, `.github`, `.opencode`, `.preview`, `alerts`, `android`, `assets`, `backups`, `docs`, `integration_test`, `lib`, `memory`, `node_modules` (142 tracked files), `remotion`, `screenshots`, `scripts`, `supabase`, `telegram-bot`, `test`, `testing`, `web`), and whether `node_modules/`, `remotion/`, `screenshots/`, `testing/`, `.preview/` and `.opencode/` belong at the root is a repo-policy question the plan has to answer before an allowlist can name them or exclude them.
## OI-302 — Restore keeps the OLDEST cloud workout_logs row for a date completed twice under different names (orderBy created_at, additive local-wins), so the completed card, receipt and now the heal-aligned row show the older session's name

- **Status**: OPEN
- **Blocked on**: a decision: pick the NEWEST row per date (`logged_at`) or keep the oldest; changes which name/duration the completed card and receipt show for double-completed dates, so it needs its own plan. Not blocking OI-284 (the heal follows the card).
- **Verified**: 2026-10-04 - code read: `_restoreWorkoutLogs` (`lib/core/services/sync/sync_workout.dart:790-841`) fetches `orderBy: 'created_at'` ascending and skips any date whose `wlog_<date>` already exists locally, so the FIRST (oldest) cloud row for a date wins; the push upserts on (user_id, date, workout_name) (`:157-195`) so a re-finish under a new name leaves two cloud rows. Found by round-1 review of swap-title-and-launch-refresh v1.
- **Identified**: 2026-10-04 · filed via mint_oi.sh from branch `swap-title-and-launch-refresh`

## OI-303 — Delete the disable_completed_title_heal kill switch and its closed-path after the founder's on-device check of OI-284 (Section 4.6.4: old path removed in the batch that rolls the gate)

- **Status**: OPEN
- **Blocked on**: the founder's on-device check of OI-284 (APK from main, observe the Oct 1 row title on the Android phone after a restore). Ratified in chat 2026-10-04 ("ok proceed") as the schedule for CLAUDE.md 4.6.4: the opt-out kill switch stays until that check, then the old (heal-off) path is deleted in the batch that rolls the gate.
- **Verified**: 2026-10-04 - code read: the kill switch is `SyncFlags.completedTitleHealEnabled` (`lib/core/services/sync_flags.dart`, configBox `disable_completed_title_heal`), read in `SyncService.shouldHealAfterRestore` and `SyncService.healCompletedTitlesAfterRestore`. The batch that closes OI-284 must delete: the flag getter, both reads, the kill-switch and flag-closed tests in `test/contracts/completed_title_follows_log_test.dart`, the mutation-proof M8/M9 rows, and the flag mentions in the diagnose-doc d4a7e1, `lib/core/services/CLAUDE.md` and the SoT registry notes. If the device check shows the heal did not fire (wlog source `cloud_restore_completion`), do NOT delete: re-plan OI-284 first.
- **Identified**: 2026-10-04 · filed via mint_oi.sh from branch `swap-title-and-launch-refresh`

## OI-318 — A 127 s cold-start restore on 2026-10-06 (per-op 9-41 s, two 45 s ceilings) was never diagnosed: no query_logs or get_advisors evidence was taken inside that window; reopen if a restore over 60 s recurs

- **Status**: OPEN
- **Blocked on**: a recurrence: a restore over 60 s on any device AND `query_logs` / `get_advisors` evidence taken inside that window (the phone's network and Supabase cannot be told apart afterwards). Not a defect with a known cause; the ledger entry F6 in `docs/audit/streak-freeze-restore-ownership.closure.yaml` is `upstream_blocked` on this.
- **Verified**: 2026-10-06 - `client_errors` for the founder's cold start at 06:45 IST: `restore_completed total_ms=127281`, per-op `restore_op_done` 9-41 s with two 45 s ceilings; the same restore's single-call data ops took 0-355 ms, so the time was spent on the legacy per-op reads, not the single-call bundle. `get_advisors` shows current state only. No IO-budget exhaustion was established (see `feedback_mistake_get_project_status_blind_to_io_throttle.md` before reading `get_project` status as health).
- **Identified**: 2026-10-06 · filed via mint_oi.sh from branch `claude/avya-streak-data-check-b506de`

## OI-319 — current_streak_weeks is a lifetime counter that never resets when the daily streak breaks (founder decision A, 2026-10-06): a reset-on-break rule is a new product feature and would have to remove the field from monotonicProgressFields

- **Status**: OPEN
- **Blocked on**: a founder product decision (not scheduled): today `current_streak_weeks` only ever goes up (`completeWorkout`, `lib/features/train/providers/train_provider.dart`, is its only runtime writer; a restore never lowers it since 2026-10-06, `monotonicProgressFields` in `lib/shared/repositories/user_repository.dart`). If a break in the daily streak should reset the weeks, that is a new rule with its own plan, and it must remove the field from `monotonicProgressFields` again.
- **Verified**: 2026-10-06 - code read: no code path resets the field except the debug-only `simulation_service.dart` reset; badge readers (`badge_service.dart` 4/8/12-week badges) and the AI snapshot (`ai_snapshot_builder.dart`) read it as a lifetime count. Founder decision A, 2026-10-06 ("lifetime counter, restore never lowers it").
- **Identified**: 2026-10-06 · filed via mint_oi.sh from branch `claude/avya-streak-data-check-b506de`

## OI-309 — Merge-conflict treadmill: every >=account PR conflicts with main again and again (shared append-only + generated docs, max+1 numbering) while the 25-minute pre-push full suite re-runs on each docs-only merge; PR #73 needed 4 merge rounds in ~1 day, and its merge then turned main red on a stale plan-review tier

- **Status**: OPEN
- **Blocked on**: a plan (it changes hooks and the generated-file policy, so CLAUDE.md 4.12 plan review x2 applies) and a founder call on the options below. Interim, in force now: for a push whose new commits are only a merge of `origin/main` with docs-only conflict edits, the founder approved `FOUNDER_APPROVED_NO_VERIFY=1` (chat 2026-10-05, "Approved no verify if that helps"); CI still runs the full suite on the PR. Whether that approval is standing or per-push is the founder's to state.
- **Verified**: 2026-10-05 - measured on PR #73 (OI-284): 4 merge-of-main rounds in about a day (plus a red main: the plan-review record's tier was measured before main's PR #70 promoted two files it touches to platform, so the merge-to-main gate wanted `bpass: accepted`; fixed by the record-correction PR); each round = hand-resolve + gate loop + a ~25-minute pre-push full suite, during which main moved again. Commits touching each file on `origin/main` in 3 days: `OPEN_INDEX.md` 8, `bug-classes.md` 8, `open_issues.md` 8, `sot_registry.yaml` 9, `diagnoses/INDEX.md` 6, `debugging/SKILL.md` 4, `naming_conventions.md` 3. Conflicts seen: bug-class number taken twice by max+1 (2.85 then 2.87), glossary rows appended at the same spot, two generated indexes, the OI board tail, plus one non-textual interaction (PR #70's new engine-completeness test flagged the new file).
- **Root causes**: (1) every batch is REQUIRED to edit the same shared files, mostly by appending at one spot (bug classes, naming glossary, OI board, SoT registry, diagnose docs); (2) generated files (`OPEN_INDEX.md`, `diagnoses/INDEX.md`, `GATE_INDEX.md`) are committed and regenerated per commit, so they conflict on any overlap although they rebuild in seconds; (3) bug-class numbers are claimed by "max + 1" (OI numbers are not: `mint_oi.sh` reserves atomically; OI-167 already recommends keying classes on the title); (4) the pre-push full suite takes ~25 minutes and re-runs on a docs-only merge, a window in which another PR merges.
- **Options to plan** (each independent): (a) stop tracking generated indexes (build in CI / on demand) or give them a regenerate merge driver installed by `setup-hooks.sh`; (b) one file per entry for bug classes, glossary terms and diagnose entries with a generated index, so two branches never edit the same lines; (c) an allocator or title-keyed ids for bug classes; (d) pre-push policy: when the new commits are a pure merge of `origin/main` (CI-green) the delta since the last green push is docs-only, verify the delta (gates + analyze) instead of the whole suite, CI stays the full-suite source of truth; (e) a GitHub merge queue (or auto-merge) so each PR is tested on top of current main serially; (f) `git rerere` and `merge=union` for pure-append files.
- **Industry norm** (to cite in the plan): merge queues that test the merge RESULT (GitHub merge queue, Mergify, Graphite, bors in Rust, Kubernetes Tide, Zuul speculative merging, Chromium CQ); per-change fragment files with the aggregate generated at release (Changesets, Towncrier); generated artifacts not committed or rebuilt in CI; trunk-based, short-lived branches.
- **Identified**: 2026-10-05 · filed via mint_oi.sh from branch `swap-title-and-launch-refresh`

## OI-311 — A spawned `dart run` exited 254 in CI with no stderr in the log (run 37203140849, 2026-10-04; second sighting after a7f3d1): cause not established, not reproducible locally

- **Status**: OPEN
- **Blocked on**: a second sighting with output. Not reproducible (200 of 200 concurrent local spawns exit 0; the file passes under `CI=true`; the re-run was green; the last 30 failed CI runs hold no unit-test failure and no `Actual: <254>`). Reopen when ANY test whose spawned `dart` exits 254 fails again: `test/contracts/sot_registry_citations_test.dart` now prints the child's stderr under the failing test (PR #79) and, once this batch lands, so does every test that spawns through `test/helpers/spawn.dart` (PR 2 migrates the rest); read whatever that log offers and, if it offers nothing, say so before reasoning about the cause. Do NOT add a retry first: it would hide the evidence.
- **Verified**: 2026-10-06 - read from `docs/audit/sot-gate-test-stderr.closure.yaml` row C3 and the 2026-10-04 CI log (run 37203140849, attempt 1: `Expected: <0> Actual: <254>` from the `dart run` of `scripts/check_sot_registry_citations.dart`, then green on re-run). `dart run` exits 254 when the Dart VM cannot compile or load the script (255 = an uncaught exception); the reason is on stderr, which that test did not print. Neighbouring causes excluded by reading: `4f2a9e` (a `GIT_*` leak), `c3f8e1` (the CI environment), `c3f9a7` (a timeout). Untested hypotheses: a concurrent implicit `pub get` / `.dart_tool` rewrite, and launcher races under load.
- **Identified**: 2026-10-06 · filed via mint_oi.sh from branch `spawn-tests-env-and-stderr` (founder decision 2026-10-06, item 2: "Put the 254 on the issue board: yes"; the first sighting was `a7f3d1`, July 2026)

The one failure was a single run on `main`; the cause is UNESTABLISHED. This entry exists so the board, not only a closure ledger, tracks it (answers row C4 of the `sot-gate-test-stderr` ledger).

## OI-315 — ProgressPhotoRepository.cleanupOrphanedStorage has zero callers, and the 5/day progress-photo cap is client-side only: a PRO caller can upload unlimited 8 MiB objects

- **Status**: OPEN
- **Blocked on**: a plan: a server-side per-day cap is a schema change (a BEFORE INSERT trigger like the AI-coach caps, or a Storage-side limit), and wiring or deleting the sweeper needs a decision on when it may run.
- **Verified**: 2026-10-06 - `git grep -n cleanupOrphanedStorage -- lib test supabase` finds no caller in `lib/` or `supabase/` (the definition is `progress_photo_repository.dart:240`; the only other hits are source-grep assertions in `test/sync/closeout_maintenance_test.dart`); `capture()` uploads first (`:128`) and inserts the row second (`:137`), so an object whose row insert fails is an orphan that nothing removes. The 5/day cap is a client-side count before the pick (`:85-99`); no trigger or policy enforces it.
- **Identified**: 2026-10-06 · filed via mint_oi.sh from branch `progress-photos-b0`

Residuals (i) and (iii) of the B1 plan's D1: a PRO caller can upload an unbounded number of objects of up to 8 MiB each, and failed captures leave orphan objects. Found by the B1 plan review round 1 (finding 12).

## OI-316 — The progress-photos bucket and its SELECT/DELETE/INSERT policies have no repo migration, and no recurring live check detects a dashboard edit of them (the OI-283 class)

- **Status**: OPEN
- **Blocked on**: a plan for a recurring catalog check (a catalog-snapshot test in CI or a nightly cron) and the founder's call on where it runs.
- **Verified**: 2026-10-06 - the B1 live evidence (E10) lists nine INSERT policies on `storage.objects`, three of them duplicates per bucket, none created by a repo migration; the avatars, banners, chat-media and coach-media policies were also made in the dashboard. B1's live-verify file catches a wrong policy once, at apply time; nothing recurring does.
- **Identified**: 2026-10-06 · filed via mint_oi.sh from branch `progress-photos-b0`

Residual (iv) of the B1 plan's D1, the OI-283 class: a dashboard edit of the progress-photos policies (a new permissive INSERT policy, a widened UPDATE policy) would silently reopen the door B1 closes. Propose a scheduled catalog snapshot compared with a committed expectation.

## OI-320 — redeem-referral has no per-referrer cap: each new referee (idempotent per referee only, index.ts:105-117) adds 7 days to the referrer's PRO, so throwaway accounts extend it without limit - product decision needed on a cap

- **Status**: OPEN
- **Blocked on**: a founder product decision: whether to cap referral credit per referrer (and at what number), or accept it; then a server-side check in `redeem_referral_atomic`.
- **Verified**: 2026-10-07 - read `supabase/functions/redeem-referral/index.ts:105-117` (idempotency is per referee only) and found by the B1 Hermes pass (L2 F2, `docs/audit/2026-10-06-hermes-progress-photos-pro-server-rule.md`); the B1 rule inherits it, it does not create it.
- **Identified**: 2026-10-07 · filed via mint_oi.sh from branch `pp-preexisting-ois`

Pre-existing; surfaced while reviewing the progress-photo PRO rule. Throwaway accounts can chain 7-day credits onto a referrer's PRO, which the progress-photo rule then honours like a paid subscription.

## OI-321 — clean-orphan-media rechecksIsPro uses .maybeSingle() (index.ts:120-129): a user with two unexpired active subscription rows gets an error, data null, and is treated as free - chat-media cleanup only

- **Status**: OPEN
- **Blocked on**: nothing: a small fix (read the active rows with a limit and test for any, instead of `.maybeSingle()`), with a regression test.
- **Verified**: 2026-10-07 - read `supabase/functions/clean-orphan-media/index.ts:120-129`: `.maybeSingle()` errors on two matching rows, `data` is null, `!!data` is false, so the user is treated as free. Found by the B1 Hermes pass (L1 note).
- **Identified**: 2026-10-07 · filed via mint_oi.sh from branch `pp-preexisting-ois`

Impact is limited to chat-media orphan cleanup (a user with two unexpired active rows is cleaned as if free); no PRO gate depends on this function.

## OI-323 — weekly-report has no server-side per-day cap for PRO: consume_quota runs only for non-PRO (weekly-report/index.ts:716), so the client once-per-IST-day cap is bypassed by a direct API call or a second device and each call is a thinking-on Gemini call - product decision needed on a PRO cap

- **Status**: OPEN
- **Blocked on**: a FOUNDER product decision: cap PRO weekly reports per IST day (and at what number) or accept the client-only cap; PRO is "20 AI messages a day, NOT unlimited" elsewhere, so a server rule is consistent. Then a `consume_quota` call for PRO in `weekly-report/index.ts`.
- **Verified**: 2026-10-08 - read `supabase/functions/weekly-report/index.ts`: the free gate (`!hasPro && !isFirstReport` -> 403) runs before Gemini and `consume_quota('weekly_report_free', 'epoch')` runs only for `!hasPro` (:716); a PRO caller has no ledger row at all. Found by the issue #78 batch (diagnose `d7b2e5`, review `docs/reviews/weekly-report-issue78-review.md`).
- **Identified**: 2026-10-08 · filed via mint_oi.sh from branch `issue78-closeout`

Issue #78 capped the SCREEN (PRO-only silent refresh, at most once per IST day, one call at a time), which is a client rule only: a direct `functions.invoke('weekly-report')`, a second device, or a reinstall each makes another `MODEL_PRO` thinking-on call with `maxTokens: 4096` and `retries: 2` (up to 3 Gemini attempts). Nothing server-side bounds a PRO user. Shape of a fix: `consume_quota('weekly_report_pro', <IST day window>, cap)` for `hasPro`, fail closed on a ledger error like the free meter, 429 with a coach-voice message, plus the client mapping; same pattern as `pro_media_daily_caps` in `supabase/functions/CLAUDE.md`. Owner decision first: the number.

## OI-324 — SupabaseService.callFunction has no timeout of its own (supabase_service.dart:395-441; _invokeRaw is a bare functions.invoke and retryColdStart retries 502/503/504 three times): every Edge Function caller can hang for minutes, only the Weekly Report screen now bounds its call (120s)

- **Status**: OPEN
- **Blocked on**: none - an engineering choice (a default timeout inside `callFunction` / `_invokeRaw`, with a per-call override for the slow AI endpoints), then a behavioral test with a never-completing invoker.
- **Verified**: 2026-10-08 - read `lib/core/services/supabase_service.dart:395-441` (`callFunction`), `:453-458` (`_invokeRaw`, a bare `client.functions.invoke`), `:507-560` (`retryColdStart`: 502/503/504 retried 3 times, 2s/6s/12s) and `functions_client-2.7.1/lib/src/functions_client.dart:118-270`; `grep -n timeout supabase_service.dart` shows timeouts only on the token refresh (20s). Found by the round-3 review of issue #78.
- **Identified**: 2026-10-08 · filed via mint_oi.sh from branch `issue78-closeout`

Every Edge Function call from the client can wait on a stalled socket or a gateway 504 for minutes (an estimate, assuming ~150s per attempt, was NOT measured). Issue #78 bounded only the Weekly Report call (`.timeout(WeeklyReportCallGate.callTimeout)`, 120s); the other callers (ai-proxy chat, food/scan, restore, payments) are unbounded and several hold a spinner or an in-flight flag while they wait. Fix shape: a default timeout in `callFunction` that the slow AI endpoints override, mapped to a friendly error, with the retry loop counted inside the bound. Care: `ai-proxy` has its own retry budget `[2000, 6000, 12000]` (diagnose `c01d57`) and a restore may legitimately run long, so the number is per endpoint, not global.

## OI-325 — Profile weekly-report card still says 'Weekly AI Report' (profile_content.dart:322) and the Profile row title says 'Weekly Report' (wardroom_copy.dart:271) while the screen is now Coach's Weekly Dispatch - one agreed name needed across the Profile entry points, the paywall feature string and notification/inbox text

- **Status**: OPEN
- **Blocked on**: a FOUNDER copy decision: the one name for this feature across Profile, the paywall and notifications (the screen is now "Coach's Weekly Dispatch"; the Profile row says "Weekly Report"; the Profile card says "Weekly AI Report"). Then a `WardroomCopy` constant and a source-grep test.
- **Verified**: 2026-10-08 - `grep -rn "Weekly AI Report\|Weekly Report" lib/` after the issue #78 merge: `profile_content.dart:322` ('Weekly AI Report'), `wardroom_copy.dart:271` (`profileReportsTitle = 'Weekly Report'`), `paywall_sheet.dart:151` (`case 'Weekly AI Report'` subtitle map, which the screen's old and new feature strings never matched). Not re-checked against notification/inbox copy.
- **Identified**: 2026-10-08 · filed via mint_oi.sh from branch `issue78-closeout`

Left out of issue #78 on purpose and then not surfaced: the batch renamed the SCREEN's card title and paywall feature string and I judged the Profile row a navigation label to leave alone; the round-2 reviewer found `profile_content.dart:322` separately and I classed it as "a separate feature label" without asking you. Under CLAUDE.md section 4.2 that should have been fixed in the batch or put to you at the time; it is filed now. Also check `lib/features/profile/screens/profile/profile_content.dart` for the card's tap target and `paywall_sheet.dart:151` so the paywall subtitle matches the renamed feature string (today it matches neither the old nor the new one).

## OI-326 — Restore-after-sign-in cost with the paged Edge Function (v10) is unmeasured: about 13 sequential requests and no client timeout of its own - needs one phone restore, then compare per-request rows with live count(*)

- **Status**: OPEN
- **Blocked on**: the founder: one sign-out/in on the upend account (a fresh restore against Edge Function v10) - I cannot trigger a phone restore. Then read the per-request `rows` log line from the function logs and compare each count with a live `count(*)` for that user, and read `restore_step_done` / `restore_completed` from `client_errors` against the baseline.
- **Verified**: 2026-10-09 - read the closure ledger entry `RESTORE-TRANSPORT-NO-TIMEOUT` in `docs/audit/streak-freeze-restore-ownership.closure.yaml` (baseline read-only 2026-10-06: the last 8 single-call restores took 15,034 to 127,281 ms; the paged function went live 2026-10-07 as v10). NOT re-measured since.
- **Identified**: 2026-10-09 · filed via mint_oi.sh from branch `claude/avya-streak-data-check-b506de`

Priority: MEDIUM, not a go-live blocker. Today the restore is bounded only by the restoring screen's 15 s / 30 s hint and its CONTINUE escape. The paged Edge Function makes about 13 more sequential requests and the client call has no timeout of its own (the general gap is OI-324). This item closes as `verified_clean` with the measured cost once one restore has run against v10; if the numbers are bad, the fix is a timeout plus fewer sequential requests. Moved here from the streak closure ledger so the board shows it.
## OI-327 — Weekly streak never resets when the daily streak breaks: current_streak_weeks only goes up (server GREATEST since migration 156) - product decision whether a broken daily streak should reset the weeks, then a migration plus a monotonicProgressFields change

- **Status**: OPEN
- **Blocked on**: a founder product decision: should a broken daily streak reset `current_streak_weeks`? Today it never goes down.
- **Verified**: 2026-10-09 - read `docs/plans/streak-freeze-restore-ownership-addendum-a.md` ("Not in this addendum": ledger `WEEKS-RESET-FEATURE`, `blocked_on_user`). The server rule is GREATEST since migration 156, merged in PR #90.
- **Identified**: 2026-10-09 · filed via mint_oi.sh from branch `claude/avya-streak-data-check-b506de`

Priority: LOW, not a go-live blocker. Since slice C1 neither the server nor restore can lower `current_streak_weeks`, so a user whose daily streak breaks keeps their weeks. If the product wants a reset, it needs a new migration (the RPC is GREATEST today) AND removing the field from `UserRepository.monotonicProgressFields`, and the dev simulation reset (`simulation_service.dart:134-136`) then works as intended. Until decided, the behaviour is "weeks only go up".
## OI-328 — One-off production credit of the 2026-09-14 week for user d7a67a37 (counted week lost to the first-session marker bug fixed in slice D) - a data correction needing its own explicit go

- **Status**: OPEN
- **Blocked on**: an explicit founder go: it is a live production write to one account. Not a code change.
- **Verified**: 2026-10-09 - read the plan (`docs/plans/streak-freeze-restore-ownership-addendum-a.md` slice D defect: the first session of a week stamps the marker so the qualifying session never counts). NOT re-queried: whether the 2026-09-14 week is actually missing for user d7a67a37-0b05-4f0a-b13c-388bff3cb59b must be read from the live `user_progress` row before any write.
- **Identified**: 2026-10-09 · filed via mint_oi.sh from branch `claude/avya-streak-data-check-b506de`

Priority: LOW, no go-live impact (one account). Slice D fixed the counting rule going forward; it does not back-fill weeks already lost. If the founder wants this week credited, the steps are: read the live row, state the exact UPDATE, run it in a transaction that returns the before/after, and get a separate go (CLAUDE.md section 4.3, live prod needs its own authorization). The value to correct is `user_progress.current_streak_weeks` (with `last_counted_week_key` left alone).
