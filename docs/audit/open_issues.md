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

## OI-25 — Coach-media consent UI flow (client follow-up)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-26
- **Identified**: 2026-05-17 · OI-23 closure spawned this follow-up
- **Risk class**: feature work
- **Estimated effort**: TBD (~3-4 hours estimate)
- **What's missing**: Founder direction was "We ask user does he
  want to store the pic for future reference and on consent we save
  it." The bucket + policies now exist (OI-23 closed) but the UI
  flow does NOT:
  - After AI analysis returns in chat (ai-media-proxy success path),
    show inline "Save this photo for future reference?" prompt.
  - On user tap → copy blob from `chat-media/<uid>/<filename>` to
    `coach-media/<uid>/<filename>` (atomic — keep source until
    target write succeeds; then optionally delete source if free
    user, retain if PRO).
  - Persist consent decision so it doesn't re-prompt for the same
    photo on a re-render.
  - Surface "Saved photos" in a profile sub-screen so users can
    review / delete their long-term collection.
- **Why class-killing**: Without this UI, the bucket sits empty +
  founder's product intent is unimplemented. The infra is now
  ready; needs Flutter work to plumb the consent + copy flow.
- **Plan**: (1) brainstorm the UX (single confirmation chip vs
  modal). (2) add `coachMediaRepository` with `saveForLater(chatMediaPath)`
  method. (3) wire into `ChatBubble.onMediaSaved` callback after
  ai-media-proxy success. (4) profile sub-screen at
  `/profile/saved-coach-photos`. (5) RLS already correct so no
  server-side work beyond ensuring `delete-account` Edge Function's
  Storage purge step lists `coach-media/<uid>/` (already does per
  CLAUDE.md §16).

---

# Hermes audit 2026-05-17 (evening) — OI-26 through OI-43

External Hermes cross-check on 2026-05-17 evening surfaced 13 REAL findings (3 P0 + 6 P1 + 4 P2) + methodology lens-registry work. Verification report: `~/.claude/plans/i-did-an-audit-glittery-meerkat.md`. Each finding becomes one OI below for tracking.

# OI-43 lens-scan findings (filed 2026-05-17, ready for follow-up batches)

## OI-44 — L26 CQRS violations: 10 query-named methods with side effects (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-29
- **Identified**: 2026-05-17 · OI-43 / L26 lens scan
- **Risk class**: CQRS / pure-function discipline
- **Effort**: ~6-8 hours (10 methods × ~30-45 min each for migration + tests)
- **Findings (top 5 by blast radius):**
  - `SubscriptionService.isPro()` (sub.service.dart:233) — 28+ callsites; downgrades + invalidates on expiry check + cross-account guard during reads
  - `SubscriptionService.gate()` (sub.service.dart:306) — 15+ callsites; async `verifyFromServer()` mutation buried in callback
  - `BadgeService.checkAndUnlock()` (badge.service.dart:18) — Hive write hidden behind "check*" name
  - `RankService.getCurrentRank()` (rank.service.dart:176) — fires telemetry on read
  - `SubscriptionService.verifyFromServer()` — writes Hive subscription state from a verify-named method
- **Fix shape**: rename to verb-form (`refreshIsPro`, `evaluateAndDowngrade`, `checkAndPersistBadges`) OR move mutation into a separately-named method. Test pattern: source-grep that names starting `get*`/`is*`/`has*`/`calculate*` don't contain `box.put` / `instance.update` / `recordNonFatal` in their body.
- **Why not fixed now**: 10 methods × multi-callsite renames is a separate scoped batch.
- **CORRECTED 2026-07-29** (oi-board-corrections batch), re-verified against live code, not
  re-asserted from this entry's own 2026-05-17 text:
  1. **`RankService.getCurrentRank()` is NOT a violation** — `rank_service.dart:217`. Telemetry
     (`ErrorTelemetry.recordNonFatal`) fires ONLY in the exception catch block, never on the
     success path; zero Hive writes in any branch. Removed from the finding list.
  2. **`checkAndUnlock()`'s own name already signals its write** (doesn't match the
     `get*/is*/has*/calculate*` prefix set the fix-shape test targets) — the board's own test
     pattern would already pass this one. Kept as a real but milder finding than the other two.
  3. **`isPro()` → `subscription_service.dart:320`, `gate()` → `:420`** (both files renamed
     since this OI was filed; citations refreshed).
  4. **New finding**: `WorkoutRepository.calculateCurrentStreak()`
     (`workout_repository.dart:275`) — already `@Deprecated` since the 2026-05-11 streak CQRS
     split, **zero live callers** (grep confirms only doc-comment mentions). Fix shape is
     **delete**, not rename.
  5. **New finding, low severity**: `SupabaseService.getOrCreateReferralCode()`
     (`supabase_service.dart:103`) — genuine hidden write (falls through to a live Postgres
     upsert), but "get-or-create" is a defensible naming idiom. Optional rename.
  6. **Revised total: ~4 real items** (isPro split, gate split, calculateCurrentStreak
     deletion, optional getOrCreateReferralCode rename) — not 10 methods. A sweep across
     `nutrition_repository.dart`, `ai_coach_repository.dart`, `coach_interaction_repository.dart`,
     `water_target_service.dart`, `sync_service.dart` found no further live instances.

## OI-45 — L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-29
- **Identified**: 2026-05-17 · OI-43 / L27 lens scan
- **Risk class**: lost-update race on shared state
- **Effort**: ~1-2 days (each needs a mutex / RPC / version field)
- **Top findings:**
  - **CRITICAL** `UsageCounterService.increment()` (line 74-79) — cross-device race could let users bypass daily caps. Two simultaneous scan-meal requests → only 1 counted. Pattern: `final c = read(); write(c+1)` with no atomicity. Fix: Postgres RPC with FOR UPDATE row lock (mirror `update_streak_progress`).
  - **HIGH** `UserRepository.updateProgress()` (line 75-84) — 4 writers (updateProgress, updateProfileFields, StreakProgressService.commitRefill, commitConsume) all do read-modify-write on the same `progress` map. Lost updates likely.
  - **HIGH** `BadgeService.checkAndUnlock()` — 2 writers (checkAndUnlock + checkAll). Rapid-fire achievement triggers can lose newly-unlocked badges.
  - **MEDIUM** `HealthSyncService.syncToHive()` line 190-192 — TOCTOU between `existing == null` check and `put()`.
- **Already mitigated**: StreakProgressService uses migration 056 `update_streak_progress` RPC (the canonical pattern). WorkoutWriteService uses per-(date,exerciseName) `synchronized` mutex.
- **CORRECTED 2026-07-29** (oi-board-corrections batch), re-verified against live code:
  1. **`increment()` CONFIRMED exactly as described** — `usage_counter_service.dart:100-106`,
     still a raw `read; write(current+1)` with zero atomicity. CRITICAL rating stands.
  2. **`UserRepository.updateProgress()` race is real but 3x UNDER-counted.** Real writer set
     is **12+ callsites across 9 files**: `user_repository.dart` `updateProgress:133` +
     `saveProgress:89`; `streak_progress_service.dart` `commitRefill:61`, `commitConsume:126`,
     `grantFirstProFreezes:213`, `resetToFreeCapOnLapse:245`; `workout_repository.dart:247`
     (`_persistCurrentStreakDays`); plus callers in `simulation_service.dart`,
     `pro_phase_advance.dart`, `phase_progress_reconciler.dart`, `graduation_screen.dart`,
     `restoring_screen.dart`, `train_provider.dart`, `home_screen.dart`,
     `onboarding_provider.dart`. **`updateProfileFields` does NOT belong on this list** — it
     writes the separate `profile` Hive key via `ProfileWriteService.patchProfile`, which is
     already `Completer`-mutex-protected (`profile_write_service.dart:46,128`) — a genuine
     canonical pattern already in the repo, cite it alongside migration 056.
  3. **`checkAndUnlock`/`checkAll` DOWNGRADED from HIGH.** Both bodies are fully synchronous —
     no `await` between the `_box.get` read and the `_box.put` write — so there is no live
     interleaving window today under Dart's single-isolate model. Worth a defensive mutex
     anyway (a future edit could add an `await` mid-body), but it is not an active race.
  4. **"WorkoutWriteService uses a `synchronized` mutex" is WRONG.** It's a hand-rolled
     `Map<String, Completer<void>>` (`workout_write_service.dart:41,1083-1092`), not the
     `synchronized` Dart package (that package IS used elsewhere — `hive_user_session.dart` —
     which is likely the source of the mix-up).
  5. **`HealthSyncService.syncToHive()` CONFIRMED**, citation refreshed to `:148` (check at
     `:197`, put at `:199`).

## OI-46 — L28 service-invariant gaps: 3 client-side-only rules (P1)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-29
- **Identified**: 2026-05-17 · OI-43 / L28 lens scan
- **Risk class**: rule bypass via new entry point
- **Effort**: ~1 day
- **Findings (UI-only — new caller would bypass):**
  - Daily AI text log limit (50 free / 200 PRO) — only `UsageCounterService` in-memory counter; NO Postgres trigger on `ai_coach_interactions` for `channel='in_app'`. Compare to `enforce_food_text_daily_limit` precedent (migration 026).
  - Scan meal daily limit + cart auditor daily limit — same in-memory-only pattern; nutrition API batch endpoint lacks gates.
  - Onboarding fields required — only `OnboardingNotifier` route sequence enforces; no `users.*` NOT NULL constraints.
- **Already mitigated**: swapDays consecutive-rest + source≠target guards moved into `WorkoutScheduleService.swapDays()` per audit-2026-05-11 H-6 (precedent pattern).
- **Fix shape**: add Postgres `BEFORE INSERT` triggers + 23P01 raise on cap exceeded; let Edge Function catch + return 429.
- **CORRECTED 2026-07-29** (oi-board-corrections batch) — **the first named finding above is
  WRONG, not just stale.** `channel='in_app'` does not exist as an `ai_coach_interactions`
  value anywhere in the codebase (it's an unrelated client-only coach-delivery-mode string).
  The actual 50/200 food-text cap is `channel='food_text_analysis'`, and it **already has**
  atomic trigger protection — `trg_food_text_rate_limit`, migration 026 — the exact precedent
  this entry cites as what to imitate is already applied to the feature this entry describes as
  unprotected. `tool_dispatcher.dart:1225-1227` and diagnose-docs `0f8d54`/`7ad0d8` corroborate
  this predates the 2026-07-26 "Verified" stamp by months.
  **Two REAL, different gaps found in its place:**
  1. Free-tier chat (`channel='app'`, 10/day cap) is check-then-insert —
     `ai-proxy/index.ts:607` (gate check), `:942` (insert) — no trigger.
  2. Vision cap (`scan_meal`+`cart_auditor` combined, 15/day) is check-then-insert —
     `ai-proxy/index.ts:438` (cap check), `:475`/`:519` (inserts) — no trigger.
  **`swapDays` "already mitigated" claim is misleading, not true.** Verified
  `swap_service.dart:111-167` — the guards are real but 100% client-side Dart against local
  Hive state; there is **no Postgres constraint/trigger** on `scheduled_workouts` backing them.
  This entry's own risk model says client-only rules are exactly what's insufficient —
  reclassified as a 4th instance of the same gap (client-only, accepted lower-severity risk
  given the blast radius is a malformed schedule, not a quota/money bypass), not a fix
  precedent.

## OI-48 — L31 cron efficiency: 3 functions are O(all users), recompute-everything (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-29
- **Identified**: 2026-05-17 · OI-43 / L31 lens scan
- **Risk class**: cost scaling (billing alert at 10K users)
- **Effort**: ~1-2 days (per-function pre-filter design)
- **RE-SCOPED 2026-07-27** (gate-input-family batch). The 2026-07-26 pass flagged this entry as
  *"MATERIALLY STALE — needs re-scoping, not carrying forward"* and then carried it forward
  unchanged. Re-read all three functions rather than re-asserting the 2026-05-17 text; **one of the
  three is genuinely fixed and two are not**:
  - **evaluate-rank-promotions — NO LONGER MATCHES THE FINDING.** `e78e2c7e` (2026-07-08, OPT-E)
    replaced the per-user reads with chunked `.in("user_id", chunk)` batch pre-fetches
    (`index.ts:47-53` chunk-size comment + BATCH_SIZE, `:81` the batched `.in(`, `:136`
    — *"Reduces N*3 queries/tick to 3"*). The outer
    `.from("users")` scan at `:118` survives, so the O(all users) *shape* is intact, but
    "~5 Postgres reads × N users / 50K reads a day" is simply no longer true of this code.
  - **i-see-you-callout — STILL OPEN.** `.from("users")` at `:98` with per-user `.limit(...)`
    queries at `:202`, `:236`, `:289`.
  - **re-engagement — STILL OPEN.** `.from("users")` at `:131` with three per-user `.limit(1)`
    verification queries at `:164`, `:173`, `:182`.
- **Revised scope**: two functions, not three, and the remaining work is the pre-filter SELECT —
  `evaluate-rank-promotions` is now the in-repo example of the fix rather than an instance of the bug.
- **Already efficient (pattern to copy):**
  - `clean-orphan-media` — RPC pre-filter → small working set
  - `pr-detection` — 20-min time window filter
  - `expiry-reminder` — single indexed SELECT with date range
- **Fix shape**: add pre-filter SELECT (last_active_at, signals_computed_at, or other "interesting users today" predicate). Compare to plateau-alert/protein-gap-alert which already use coach_memory scores.
- **CORRECTED 2026-07-29** (oi-board-corrections batch) — **the 2026-07-27 re-scope pass's
  "i-see-you-callout — STILL OPEN" is ITSELF wrong, the second stale miss on this same
  function.** Verified live: `i-see-you-callout/index.ts:26-100` carries an
  `F45 (2026-06-07 audit)` active-user pre-filter (`ACTIVE_WINDOW_DAYS=28`,
  `.gte("last_active_at", activeCutoffIso)` at `:100`) plus `PAGE_SIZE=1000` pagination —
  landed over 7 weeks before this "STILL OPEN" line was written and over a month before the
  2026-07-26 pass that also missed it. **Move it to the "already efficient" list below;** only
  `re-engagement` remains a real, open instance now.
  `re-engagement`'s citation is off by one — `.from("users")` is actually at `:132`, not `:131`
  (region otherwise correct). Its Path B scan carries only an `is_deleted` filter, genuinely
  O(all non-deleted users), then a per-user 3-table (`workout_logs`/`nutrition_logs`/
  `weight_logs`) sequential-query loop at `:140-185` checking for the *absence* of recent
  activity (an anti-join, not a batchable positive-filter check).
  **"plateau-alert/protein-gap-alert already use coach_memory scores" is only half true.**
  `plateau-alert` does (`index.ts:96`, `plateau_risk_score >= 0.7`). `protein-gap-alert` does
  NOT — it pre-filters on `subscriptions.status='active'` then issues already-batched `.in()`
  queries (`index.ts:94-99,123-150`), no score involved. This is actually the **better**
  structural precedent for `re-engagement`'s fix (batched positive-filter pattern), though the
  anti-join shape of `re-engagement`'s actual check fits `clean-orphan-media`'s RPC pattern
  more directly.

## OI-50 — L37 empty/null-shape readers: 23 risky accesses across 6 files (P2)

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-07-29
- **Identified**: 2026-05-17 · OI-43 / L37 lens scan
- **Risk class**: runtime crash OR silent-wrong on malformed/empty Hive shapes
- **Effort**: ~1-2 days (8 contract tests + null-guard refactors)
- **Top findings (6 crashes + 17 silent-wrong):**
  - **CRASH** `train_provider.dart:72` — `sets.first` on empty List throws RangeError.
  - **CRASH** `todays_meals_card.dart:340` — `mealType[0]` indexes potentially-null string.
  - **CRASH** `workout_receipt_card.dart:450` — null deref if `box.get(k)` returns null then `val['type']` access.
  - **SILENT-WRONG** `workout_receipt_card.dart:380` — `log['sets'] ?? log['sets_detail']` both missing → empty path taken → zero reps rendered.
  - **SILENT-WRONG** `edit_workout_log_sheet.dart:938` — fallback to `sets_completed` key without existence check.
- **Already clean** (canonical pattern): `workout_read_service.dart`, `profile_provider.dart` — both use `if (X is List && X.isNotEmpty)` then `for (final s in X) if (s is Map)` guards consistently.
- **Fix shape**: per-file null-guard refactor + contract tests with `empty | malformed | missing-key | wrong-type` cases (the L37 charter pattern).
- **CORRECTED 2026-07-29** (oi-board-corrections batch) — **3 of the 5 named "CRASH" findings
  are WRONG; all already guarded.** Verified live, plus a broad `.first`/`.last`/bracket-index
  sweep across all of `lib/` found no further live instances:
  1. `train_provider.dart` `sets.first` (now at `:85`, moved from `:72`) — guarded, `if (sets
     is List && sets.isNotEmpty)` immediately precedes it at `:84`. No crash reachable.
  2. `todays_meals_card.dart:340` `mealType[0]` — **the citation doesn't exist**; that line is
     a section-divider comment (`// ── Empty slot ──...`), confirmed by direct read, not just
     stale. Both real `mealType[0]` sites — `nutrition_read_service.dart:70-72` and
     `nutrition_screen.dart:1258-1260` — are null/empty-guarded.
  3. `workout_receipt_card.dart:450` null-deref — guarded by `if (val is Map && ...)` at the
     real location, `:454-455`. No crash reachable.
  The 2 SILENT-WRONG findings are real but narrower than described: `:387` (was `:380`) — the
  `sets`/`sets_detail` fallback only produces an empty *per-set breakdown*, not "zero reps
  rendered" (aggregate reps/set-count are read from separate top-level fields); `:939`
  (was `:938`) — confirmed as described, no crash, silent `?? 0` fallback.
  **"23 risky accesses across 6 files" does not hold up.** Confirmed real: 2. A broad sweep of
  every `.first`/`.last`/bracket-index pattern in `lib/` found no further live crash-shaped
  risk. This OI (filed 2026-05-17) very likely predates or was never reconciled against
  PR-FIX-2 (2026-04-24, `lib/CLAUDE.md` common-pitfalls table), which already swept 6 instances
  of exactly this `.first`-on-empty-list bug class 3 weeks earlier.
  **`profile_provider.dart` is NOT a canonical-pattern example** — the `is List &&
  isNotEmpty`/`for (s) if (s is Map)` idiom does not appear anywhere in that file (it only
  reads scalar profile fields). The sole verified canonical example is
  `workout_read_service.dart` (`bestPerSetReps:64-83`, `bestPerSetDuration:91-112`,
  `bestPerSetWeight:118-131`, all three using the idiom).

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
| OI-45 | **STILL OPEN** — `increment()` body is still `final current = read(); await write(current + 1)` | 74-79 → **`usage_counter_service.dart:100-106`**. NOT refreshed: `UserRepository.updateProgress` 75-84 → **:133**; `HealthSyncService.syncToHive` 190-192 → **:148** |
| OI-46 | **STILL OPEN** — migration 026 explicitly scopes to `food_text_analysis`; no daily-cap trigger on `ai_coach_interactions` | — |
| OI-47 | **STILL OPEN** — `_shared/sanitize_for_prompt.ts` **absent**; raw `User name: ${name}` live | 243 → **`morning-alert/index.ts:278`** |
| OI-48 | **MATERIALLY STALE — the stated harm no longer describes the code.** `e78e2c7e` (2026-07-08, OPT-E) batched the per-user reads via chunked `.in()`. The outer `from("users").select(...)` remains, so the O(all users) *shape* survives, but "~5 Postgres reads × N users" does not. **Needs re-scoping, not carrying forward.** | — |
| OI-51 | **PARTLY CLOSED.** `razorpay_service.dart:_onUserChanged()` nulls `_onSuccess`/`_onFailure`/`_pendingPlan` via `SingletonLifecycleRegistry`, added by the 2026-05-20 tech-debt audit (A7) — *after* this OI was filed, so its "No reset path" text is now false. **Still genuinely open:** Crashlytics `setUserIdentifier('')` and `OneSignal.logout()` — neither appears anywhere in `lib/`. | auth_provider 543/760 → **:587/:607**; razorpay 30-32 → **:40-42** |
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

## OI-53 — Flip the 13 workout-generator ship-dark flags

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · workout-generator overhaul complete `7bb766fa`
- **Blocked on**: FOUNDER
- **What's missing**: Test account first — plateau presupposes `enable_readiness` ON. Each flip needs
  its own full ×2 review per §4.12.4; logged in `docs/ship_dark_pending_review.yaml`.

## OI-54 — Confirm `/admin` access

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · admin dashboard shipped 2026-07-13
- **Blocked on**: FOUNDER (must load `/admin` signed-in)
- **What's missing**: Verify `ADMIN_USER_IDS` actually contains the founder UUID.

## OI-55 — Live `amar` re-verify (Unit 0)

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · Unit 0 shipped `34621203`
- **Blocked on**: FOUNDER sign-in; sequenced after OI-52

## OI-56 — Revert repo to private

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26
- **Blocked on**: FOUNDER (after billing is fixed)
- **What's missing**: Public since 2026-07-18. Note the security consequence while public: fork-PR
  branch-name collisions are a live concern for the keystone gate (owner-guard added `d947743d`).

## OI-57 — Decide the 7 open Dependabot PRs

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26
- **Blocked on**: FOUNDER
- **Live state**: #17/#16/#15/#5 CLEAN · #14 DIRTY (conflicted) · #10 three FAILURE checks · #9 UNKNOWN
- **What's missing**: `pub` bumps merge freely under the content-verified exemption; the 2
  `github-actions` bumps require a plan-review record **by design** (a bot must not rewrite the CI
  that enforces every other gate). Documented in `.github/dependabot.yml`.

## OI-58 — Keystone gate: single-parent + subject-spoof bypass

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Attempted and SPLIT OUT 2026-07-27** (branch `gate-input-family`, founder-approved
  per §4.12.1). The enforcement was built twice and failed review twice, each time in
  the same place. **Read this before re-attempting:**
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
- **What's missing**: Branch identity derives from the merge SUBJECT (author-controlled free text)
  and `HEAD^2`. Two faces: a local `git merge` that fast-forwards or `--squash` lands single-parent
  commits the gate never inspects; and `git merge --no-ff -m "Merge branch 'other'"` resolves to
  another branch's approved record. Disabling GitHub's squash/rebase buttons closed only the GitHub
  path. The ACCIDENTAL half (slug + quote truncation) is closed.
- **Fix shape**: stop keying on the subject/`HEAD^2`; evaluate the pushed range via
  `github.event.before..after` (used nowhere in the repo today). Materially different design — own
  reviewed unit.

## OI-60 — Flip `enable_hold_weeks`

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26
- **Blocked on**: 7 unstarted flip-on-blocker items (FOB-1…FOB-7) in
  `docs/ship_dark_pending_review.yaml` — coach/push/weekly-report tell every holder a false
  week-4 story, weekly streak is dead during a hold, hold telemetry has zero consumers, selectable
  past-hold-weeks has 6 named lifecycle traps, and 4 residual scan gaps. None were touched by the
  OI-59 display batch (that work is additive and inert while the flag is OFF). FOB-3/FOB-4 also
  require ai-proxy + weekly-recap-ready/weekly-report EF redeploys (own explicit go, §4.3).
- **What's missing**: Own full ×2 per §4.12.4 (flip-on is where real user risk starts) — all 7 FOB
  items closed first.

## OI-61 — Coach-UX: live-verify test7, v74 hardening, temp-PRO cleanup

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · Units 2+3+FC8 shipped `237c347`, ai-proxy v73
- **Blocked on**: OI-52

## OI-62 — Coach-reliability: FC6 + Unit A

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · Unit B merged `b2ea2e3`, ai-proxy v72
- **Blocked on**: FC6 waits on OI-52. Unit A: F3 anytime, F1 founder-gated.

## OI-63 — Restore C2: 137-policy RLS initplan

- **Status**: OPEN
- **Verified**: never
- **Identified**: 2026-07-26 · restore-perf C3 shipped
- **Blocked on**: sequenced after OI-52

## OI-64 — Discipline-overhead: the three unbuilt gates

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-26 · discipline-overhead shipped `dd51a40a`
- **What's missing**: Stop-hook completion gate · automatic ship-dark verification gate (proving a
  flag really is default-OFF and byte-identical from a script) · ship-dark ledger-enforcement gate.

## OI-65 — Qualification-Exam feature

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-26
- **What's missing**: 9 decisions locked, committed `7328c99` on branch `qualification-exam`,
  **unpushed**. Pre-implementation.

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

## OI-67 — `MEMORY.md` over its soft cap

- **Status**: CLOSED · 2026-07-29 · commit `<pending>`
- **Identified**: 2026-07-26 · consolidation pass
- **What's missing**: 20,316 bytes vs the 17,510 soft target (hard read cap 24,400). Genuinely gated
  on closing items above rather than on more compression — every surviving In-flight entry carries a
  live obligation. Closing OI-52…OI-56 removes most of it.
- **How closed**: NOT via closing OI-52…OI-56 as anticipated above — those remain OPEN (verified).
  A `/consolidate-memory` pass ran in a separate session (2026-07-29), trimming dual-tracked
  In-flight lines that already had their own OI number. Measured directly (`wc -c`), not taken from
  MEMORY.md's own retrospective entry (which claims 16,866 bytes): actual current size is
  **17,227 bytes**, under the 17,510-byte soft target by a 283-byte margin — real, but thin.

## OI-68 — Build the backlog MECHANISM (attempted 2026-07-26, withdrawn after 2 review rounds)

- **Status**: CLOSED · 2026-07-29 · diagnose `a9f2c6` · commit `<pending>`
- **Identified**: 2026-07-26
- **Risk class**: the backlog stays passive — visible only to whoever opens the file
- **What's missing**: a SessionStart digest surfacing OPEN items, a merge-to-main gate forcing an
  `open_issues:` declaration, and a format gate. All three were **built and then withdrawn** — two
  independent review rounds found 5 P1s and the unit was split per §4.12.1, shipping only the data
  half (this file + the `memory/MEMORY.md` stub), which carries no code risk.
- **How closed**: NOT the withdrawn design above (SessionStart digest + blanket merge-gate
  `open_issues:` declaration + format gate) — a narrower, different mechanism shipped instead:
  `e4bc9040` built `docs/audit/OPEN_INDEX.md` (generated, one line per open issue, fails closed on
  a missing field or an empty index) and `scripts/check_closes_oi_cited.dart` (citation required
  only on an actual OPEN→CLOSED transition, not on every merge — strictly narrower than the
  original blanket-declaration idea). Scar #3 below — "the format gate validated shape but not
  vocabulary" — reproduced live a 4th time during `build_oi_index.dart`'s own build (a
  `startsWith('OPEN')` skip silently dropped a `BLOCKED` entry); caught by the B-pass and fixed in
  `f78d721c` (diagnose `a9f2c6`) with explicit negative controls for all four words this entry
  names (PENDING, BLOCKED, REOPENED, the IN-PROGRESS typo) — `unrecognisedStatuses()` /
  `unreadableStatuses()` now classify every status line and exit 1 naming the offending entry
  rather than silently dropping it.
  **Residual, not silently dropped:** no SessionStart digest exists. Both prior attempts were
  withdrawn as buggy (2026-07-26); not re-attempted here. Distinct from OI-69 (staleness
  *detection*) — this is per-session proactive surfacing, and stays unbuilt.
- **Closes**: diagnose-doc
  `docs/diagnoses/2026-07-29-gates-silently-skip-what-they-cannot-parse-a9f2c6.md`.

- **SCARS — read before re-attempting. Three generations of the SAME bug in one component:**
  1. **v1 parser** used an exact-string match `line.trim() == '- **Status**: OPEN'`. It missed 7
     realistic shapes — worst of all this file's OWN house style, since every CLOSED entry here is
     written `- **Status**: CLOSED · <date> · <diagnose>` with a trailing qualifier
     (`grep -cE '^- \*\*Status\*\*: CLOSED ·'` → 39; one reviewer counted 40, the discrepancy was
     never settled and does not change the point). An author following the established convention
     would have been silently dropped from the digest.
  2. **v2 parser** loosened the regex to fix that — and made the colon optional and `*` a valid
     bullet, so a prose line like `- Status quo is unchanged since May` **captures "quo", locks the
     entry, and silently drops it**. Verified: 3 new drop modes, all invisible to the format gate
     shipped alongside. Requiring the colon kills two of them.
  3. **The format gate validated shape but not vocabulary**, though its own error message claimed
     otherwise — `PENDING`, `BLOCKED`, `REOPENED` and a one-character `IN-PROGRESS` typo all passed
     the gate and vanished from the digest.
- **Other findings to carry forward:**
  - The digest's cap (18) hid this very OI. Any accountability item filed against the mechanism must
    be reachable *by* the mechanism, or the tracking is theatre.
  - `open_issues:` was matched against the whole record, accepting a hit in prose or a fenced code
    block — the class `recordBranchFieldMatches` was hardened against a week earlier, reintroduced.
  - The gate reached its checks without computing blast-radius, so it could fail where the keystone
    gate passes. **0 of 70 existing records carry `open_issues:`**, so switching it to hard-fail
    without a migration would redden main immediately.
  - Promoting **this data file** to `platform` tier was self-defeating (ticking one OI to CLOSED
    would then demand a ×2 review + B-pass) and was reverted. Promoting the *enforcement scripts* is
    still right.
  - A brand-new gate on the merge path must ship `--warn-only` per §4.11 — and something must flip
    it. Live precedent for the decay: `check_skipped_discipline_budget.dart` has been `--warn-only`
    since `ae6146eb` (2026-06-18) against a documented *"24h smoke window"* — 38 days.

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

## OI-75 — notification_preferences has no SoT registry entry

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-27 · B-pass
- **What's missing**: §4.5 requires a `docs/sot_registry.yaml` entry for a new writer/reader
  contract. The arc created one (repository → compileDailySnapshot → 6 Edge Function readers) and
  did not register it. `docs/snapshot_contract.yaml` WAS updated, so the drift gate covers the
  snapshot seam; the SoT registry entry is the missing half.

## OI-76 — Notification count includes PRO-locked rows a free user cannot disable

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: never
- **Identified**: 2026-07-27 · B-pass
- **What's wrong**: `profile_content.dart` counts all 10 registry keys, including Protein Alerts and
  Plateau Check. A free user cannot turn those off, and their server functions PRO-gate anyway, so
  the subtitle permanently reads at least 2/10 "enabled" for notifications that will never fire.
- **Related**: the paywall callback passes `AppConstants.featureProgressPhotos` for notification
  rows — wrong copy, and §4.4 r19 keys server-side verification off that id.
