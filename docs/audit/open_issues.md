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

- **Status**: CLOSED
- **Blocked on**: none
- **Verified**: 2026-07-26
- **Closed**: 2026-07-30 — Unit 8 of the OI-25/44/45/46/48/50 batch
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

**CLOSED 2026-07-30** (coach-media-consent batch, Unit 8 — diagnose
`f4a7c2`). All four missing pieces shipped, matching this plan closely with
one mechanism deviation: consent persists as two new fields
(`media_storage_path`, `media_save_state`) written in place on the same
`coach_<ms>` interaction row that already carries `media_url`, rather than
a separate coachBox key hashed on the chat-media path — same outcome (no
re-prompt on rebuild, no new metadata table), one fewer bookkeeping
mechanism, reusing this row's own established UPDATE-not-INSERT idiom.
Investigation before implementation found and fixed a genuine prerequisite
bug this feature depended on: the success-path user photo bubble never
carried `coachKey` (only the AI/error bubble did, for Retry) — without it
nothing could key the consent write back to the right row. Also folded in
the one-line doc fix the plan flagged: `supabase/functions/CLAUDE.md`'s
SSRF-allowlist bucket names were stale (said `progress-photos` +
`chat-attachments`; live code has always been `chat-media`, `coach-media`,
`progress-photos`) — fixed, plus a new test assertion pinning the real set
so this can't drift stale again unnoticed. `scripts/blast_radius_from_diff.dart`
classified the shipped diff `platform` (higher than this batch's own
`account` pre-diff estimate). Round-1 review found the media reference on
a chat photo message (mediaUrl/mediaStoragePath, and now also
mediaSaveState) has never round-tripped through cloud sync/restore, before
or after this batch — a pre-existing, not newly-introduced, gap. Practical
effect: a historical photo message degrades to caption-only text after a
restore on a second device (no image, no consent chip render at all — not
"the chip re-offers"). The photo itself is never lost (still in Storage;
an already-saved copy still lists correctly in Saved Photos, which reads
Storage directly). Out of scope for this unit (would need to extend both
the push and restore payloads in sync_coach.dart). **B-pass correction**: this
paragraph's own first draft said the gap was "flagged as a separate follow-up
task" without a durable, independently-verifiable citation — a
`mcp__ccd_session__spawn_task` chip was raised, but a chip is ephemeral
session UI state, not a git-tracked artifact, so once this OI closed there
was nothing left in the repo pointing at the gap. Filed as **OI-77** instead,
which is the actual, durable record. Full account:
`docs/diagnoses/2026-07-30-coach-media-consent-f4a7c2.md`.

---

# Hermes audit 2026-05-17 (evening) — OI-26 through OI-43

External Hermes cross-check on 2026-05-17 evening surfaced 13 REAL findings (3 P0 + 6 P1 + 4 P2) + methodology lens-registry work. Verification report: `~/.claude/plans/i-did-an-audit-glittery-meerkat.md`. Each finding becomes one OI below for tracking.

# OI-43 lens-scan findings (filed 2026-05-17, ready for follow-up batches)

## OI-44 — L26 CQRS violations: 3 real query-named mutators, one causing a provider self-invalidation (P2)

- **Status**: CLOSED
- **Blocked on**: none — Unit 6 landed the split, the deletion, and the gate that makes the
  shape unconstructible. See the closure block at the end of this entry.
- **Verified**: 2026-08-02
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

- **CLOSED 2026-08-02 — Unit 6.** Diagnose `a9c4e1`. Blast radius `platform`.

  **The finding that justified the work was not the naming.** Traced end to end:
  `profile_provider.dart:380` `SubscriptionInfoNotifier.build()` → `isPro()` →
  `subscription_service.dart:1048` `_downgradeLocally()` → `:1072` `onStateChanged` →
  `app.dart:47` `ref.invalidate(subscriptionInfoProvider)` — **a provider build invalidating
  itself.** Precision matters: it terminated (the second pass returns before mutating) and the
  invalidation landed a microtask after `build()` returned, so it cost one wasted rebuild rather
  than crashing. It was fixed because a build method must not mutate, not because it was on fire.

  **Fix.** `_enforceEntitlementInvariants()` (`:414`) holds the cross-account + expiry branches
  verbatim; `proStateSnapshot()` (`:367`) is a genuinely pure read; `isPro()` (`:338`) keeps its
  name and behaviour (enforce, then report) so all 32 decision callsites are byte-identical.
  Only build methods and the 8 re-entrant reads inside `verifyFromServer()` use the pure read.
  `evaluateEntitlement()` (`:481`) is called explicitly at boot (`splash_screen.dart:220`) and on
  account swap (`:56`). §4.6 kill-switch `disable_cqrs_pure_pro_read`.

  **Three of this entry's own claims were wrong** and are corrected here rather than closed over:
  - `gate()` is **10** callsites, not "15+".
  - `calculateCurrentStreak()` did **not** have "zero live callers" — `lib/` yes, but
    `test/train/streak_anchor_test.dart:42,73` called it and
    `test/contracts/streaks_writer_to_reader_test.dart:59` *source-grepped that the symbol
    exists*. That test demanded the presence of the defect; it now pins the split pair.
  - A fourth item, found while building the gate: `lib/CLAUDE.md` cited
    `check_writer_reader_drift.dart` and `check_subscription_gate.dart` as live pre-commit
    gates. **Neither has ever existed** — same class as this board's own
    `check_open_issues_reconciled.dart` note. Corrected.

  **`getOrCreateReferralCode()` → `verified_clean`, deliberately not renamed.** The hidden write
  is real (a live Postgres upsert via `_generateNewCode`), but "get-or-create" already announces
  the create, and there is exactly one callsite (`invite_friends_sheet.dart:64`). The decision is
  recorded as a reasoned entry in the gate's exemption ledger rather than in prose, so it cannot
  rot silently.

  **The gate (§4.11, shipped in an earlier commit than the refactor):**
  `scripts/check_cqrs_query_naming.dart` + `scripts/cqrs_query_naming_lib.dart`, negative-
  controlled by `test/contracts/cqrs_query_naming_gate_test.dart` against the committed fixture
  `test/fixtures/cqrs_gate/violations.dart`. It deliberately does NOT implement this entry's own
  proposed test (grep bodies for `recordNonFatal`) — that pattern is what forced the 2026-07-29
  removal of `getCurrentRank()`, so catch blocks are stripped first. It also needed a
  writer-verb layer (rule 4 routes writes through repositories, so `box.put(` is the rare shape)
  and TRANSITIVE same-file delegation resolution, without which it missed its own worked example.
  `lib/`: 135 members scanned, 2 mutate, both exempted with reasons, 0 unexempted.

  Behavioral: `test/contracts/subscription_cqrs_behavioral_test.dart` (11 tests). Groups A and B
  are a controlled pair — identical seed and hook counter, differing only in which read is
  called: pure fires 0 invalidations and leaves Hive byte-identical, decision fires ≥1 and wipes.

## OI-45 — L27 concurrency races: 4 unguarded getX→modify→setX patterns (P1)

- **Status**: CLOSED
- **Blocked on**: none — Unit 3a (`6258622b`), Unit 3b (`fa05aa88`) and Unit 3c + the
  behavioral-test gap (2026-08-01, `c8f3d1`) have all landed. See the final closure block below.
- **Verified**: 2026-08-01
- **Identified**: 2026-05-17 · OI-43 / L27 lens scan
- **Risk class**: lost-update race on shared state
- **Effort**: Unit 3b ~1-2 days (new migration + RPC + local version tracking) + Unit 3c ~0.5 day
  (needs its own conflict-resolution design, not a mechanical fix)
- **Top findings:**
  - ~~**CRITICAL**~~ **[CORRECTED 2026-07-29, usage-counter-race batch: downgraded to LOW — this rating does not hold, see the second correction block below]** `UsageCounterService.increment()` (line 74-79) — cross-device race could let users bypass daily caps. Two simultaneous scan-meal requests → only 1 counted. Pattern: `final c = read(); write(c+1)` with no atomicity. Fix: Postgres RPC with FOR UPDATE row lock (mirror `update_streak_progress`).
  - ~~**HIGH**~~ **[CLOSED 2026-07-30, progress-map-consolidation batch Unit 3a — see the third correction block below]** `UserRepository.updateProgress()` (line 75-84) — 4 writers (updateProgress, updateProfileFields, StreakProgressService.commitRefill, commitConsume) all do read-modify-write on the same `progress` map. Lost updates likely.
  - ~~**HIGH**~~ **[DOWNGRADED + CLOSED 2026-07-30, Unit 3a — no live race; see third correction block]** `BadgeService.checkAndUnlock()` — 2 writers (checkAndUnlock + checkAll). Rapid-fire achievement triggers can lose newly-unlocked badges.
  - ~~**MEDIUM**~~ **[CLOSED 2026-07-30, Unit 3a — see third correction block]** `HealthSyncService.syncToHive()` line 190-192 — TOCTOU between `existing == null` check and `put()`.
- **Already mitigated**: StreakProgressService uses migration 056 `update_streak_progress` RPC (the canonical pattern). WorkoutWriteService uses per-(date,exerciseName) `synchronized` mutex.
- **CORRECTED 2026-07-29** (oi-board-corrections batch), re-verified against live code:
  1. **`increment()` CONFIRMED exactly as described** — `usage_counter_service.dart:100-106`,
     still a raw `read; write(current+1)` with zero atomicity. CRITICAL rating stands.
     **[SUPERSEDED same day by the usage-counter-race batch correction further below — this
     pass re-confirmed the code SHAPE but never tested whether that shape actually produces a
     lost update at runtime. It doesn't. See the later correction block for the full
     verification.]**
  2. **`UserRepository.updateProgress()` race is real but 3x UNDER-counted.** Real writer set
     is **12+ callsites across 9 files** `[CORRECTED 2026-07-30, Unit 3a round-2 review, via a
     fresh grep: 15 write callsites (13 updateProgress + 2 saveProgress) across 11 files — the
     "9 files" figure was set early and never recounted as the list below grew; see item 6 of
     the third correction block below]`: `user_repository.dart` `updateProgress:133` +
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
- **CORRECTED 2026-07-29** (usage-counter-race batch, Unit 2 of the same 8-unit batch as the
  correction above — same day, later pass) — **finding 1's "CRITICAL rating stands" was itself
  wrong, on two independent axes, both now closed/verified:**
  1. **The same-device race does not exist — verified, not assumed.** A behavioral test firing
     two concurrent `increment()` calls via `Future.wait` (not sequentially awaited) against the
     UNMODIFIED pre-fix code still counted both — no lost update. Root cause of the non-race:
     `MigratedKey.read` is fully SYNCHRONOUS, and Hive's `Box.put()` mutates its in-memory
     keystore SYNCHRONOUSLY before its own first internal `await` (only the disk flush is
     actually async). Since `increment()`'s only `await` comes AFTER its read, and Dart is
     single-threaded/cooperative, nothing can preempt a caller between its read and its write's
     in-memory landing. This is the SAME structural-safety class already identified above for
     finding 3 (`checkAndUnlock`/`checkAll`) — it just wasn't checked for `increment()` in the
     prior pass, which re-confirmed the CODE SHAPE (`read; write(current+1)`, still true) but
     not the actual RUNTIME interleaving behavior that shape implies.
  2. **The cap-bypass concern is now server-enforced regardless.** All three features this
     service gates now have an authoritative Postgres trigger backstop on `ai_coach_interactions`
     (ai-text-log: migration 026, pre-existing; scan_meal + cart_auditor combined: migration 111,
     2026-07-29, same-day Unit 4 of this batch) — a lost or stale local counter can no longer let
     a request past the real cap, cross-device or same-device; worst case is a stale "X remaining"
     display or a request the server correctly 429s.
  **Downgraded CRITICAL → LOW (display-accuracy only, not a cap-bypass).** A per-key `Completer`
  mutex was added anyway as defense-in-depth (matching the `ProfileWriteService`/
  `WorkoutWriteService` convention for shared Hive-backed state) — not because a reproducible bug
  was found on `increment()` itself, since none was. Same fix applied to the sibling
  `MessageLimitNotifier.incrementToday()` (chat's display counter, `ai_coach_provider.dart:460`),
  found while investigating this finding — identical shape, identical structural non-race, chat's
  real cap also now server-enforced (`trg_chat_app_rate_limit`, migration 111).
  **Independent round-1 review of this correction raised a second, distinct mechanism the
  "structurally impossible" analysis above hadn't considered:** `checkAndResetCounters()`
  (`usage_counter_service.dart:209`) is a SECOND, previously-unlocked writer of the same 3 keys —
  fired on every app-resume, not just cold boot (`day_rollover_service.dart:140`) — with 4
  genuinely-yielding sequential `await` writes unlike `increment()`'s single-await-after-mutation
  shape, a plausible mechanism for a reset-vs-increment race. **Applying the exact same rigor
  demanded of finding 1 (test the actual pre-fix/unlocked code, don't reason from the mechanism
  alone):** a `Future.wait([checkAndResetCounters(), increment()])` concurrent-dispatch test was
  run against BOTH the locked and unlocked reset code — **the corrupted outcome did not reproduce
  either way, and round-2 review sharpened why: this is provably DETERMINISTIC, not merely
  "not observed."** A list literal `[a(), b()]` invokes `a()` then `b()` in that fixed order, and
  calling an async function runs synchronously to its first true suspend point, so
  `checkAndResetCounters()` (listed first)'s reset write lands in Hive's in-memory keystore
  (synchronous, inside `Box.put()`) before `increment()` (listed second) is even invoked.
  Reversing the argument order reverses the outcome (verified empirically, 20/20 runs each
  direction). The lock was added anyway, same per-key `_withLock` as `increment()`, as
  defense-in-depth against a dispatch shape this specific guarantee doesn't reach (independently
  event-loop-scheduled callers, should a future refactor add a genuine `await` before either
  read) — not because a reproducible bug was confirmed today. An earlier draft of this correction
  briefly claimed "a narrow race was real, fixed" before this verification step was run against
  the unlocked code; that claim did not survive the check and is corrected here rather than left
  standing.
  **B-pass review (the mandatory pre-merge 5-lens pass, §4.3) then found a THIRD shape that IS a
  genuine, reproducible bug — unlike every other race investigated in this correction:**
  `DayRolloverObserver` (`day_rollover_service.dart`) has no re-entrancy guard, and its staleness
  gate is written well after `checkAndResetCounters()` returns — a duplicate `resumed` lifecycle
  event before the first rollover completes dispatches a SECOND, independently-scheduled
  `checkAndResetCounters()` call, which (unlike the single-resetter case above) is NOT gated
  against observing stale state. Verified as real by reverting the fix: a synchronous
  `Future.wait([reset, increment, reset])` construction reliably lost the increment 20/20 runs.
  Closed with an outer double-checked-locking guard (`_dailyResetLockKey`) wrapping the entire
  staleness-check-and-reset body, staleness re-checked after acquiring the lock — verified closed
  20/20 runs across 3 orderings post-fix. This is the one fix in this whole investigation that is
  a confirmed-bug fix, not defense-in-depth; see
  `docs/diagnoses/2026-07-29-usage-counter-race-c9e3b1.md`'s "B-pass review" section for the full
  mechanism. Same B-pass round also closed a test-coverage gap: `MessageLimitNotifier.incrementToday()`'s
  lock had only a source-grep test, not a behavioral one — added, and honestly found to NOT
  discriminate (same non-race as `increment()` itself), so documented as invariant-pinning like
  its sibling.
  **Unplanned finding, also closed in the same batch:** the combined scan_meal+cart_auditor
  server cap (15/day, migration 111) undershot the documented PRO product promise
  (`docs/architecture/business-rules.md`: 10 scan-meals/day + 10 cart-audits/day independently =
  20 combined) — a compliant PRO user following the client's own displayed "remaining" counts
  could hit a live 429 well within their documented allowance. Founder decision: raise the server
  to match the documented promise (migration 114, 15→20), not lower the promise to match the
  server. Not a NEW bug introduced by this batch — the 15 value pre-dates it (an existing
  check-then-insert pre-check in `ai-proxy/index.ts`); migration 111 just made it, for the first
  time, an unconditionally-enforced trigger. **Applied live 2026-07-30T06:06:57+05:30** —
  verified via `pg_proc` source + the full live-Postgres behavioral test (20 rows succeed, 21st
  correctly rejected with `cap=20`). The mismatch is closed, not just designed.
  **Findings 2-4 (`UserRepository.updateProgress`, `BadgeService.checkAndUnlock`/`checkAll`,
  `HealthSyncService.syncToHive`) are UNCHANGED by this pass — still open, still Unit 3's scope.**
  This OI stays OPEN; only finding 1 (+ the newly-discovered cap-value mismatch) closes here.
- **CORRECTED 2026-07-30** (progress-map-consolidation batch, Unit 3a — findings 2-4, same
  investigate-then-verify discipline as the two corrections above):
  1. **Finding 2 (`UserRepository.updateProgress`) — SAME-DEVICE half closed; CROSS-DEVICE half
     is NOT (that's Unit 3b, not started).** A `Completer`-based mutex mirroring
     `ProfileWriteService._withLock` was built first, matching the established codebase
     convention — then tested with the same rigor as `increment()`'s own investigation: disabled,
     full suite re-run, compared. Two findings: (a) it gave NO correctness benefit for any
     concurrent `updateProgress`/`saveProgress` pairing tested via `Future.wait` (identical
     structural-safety class to `increment()` — Hive's `Box.put()` lands synchronously, list-order
     dispatch determinism); (b) it ACTIVELY BROKE 2 pre-existing tests
     (`streak_decay_reckon_permanent_ledger_test.dart`) by serializing two previously-independent
     UNAWAITED fire-and-forget writers (`StreakProgressService.commitConsume` +
     `WorkoutRepository._persistCurrentStreakDays`, both fired within one
     `reckonStreakDecayAndPersist()` flow) into a genuine queue — a real timing regression, no
     offsetting correctness gain. **The mutex was removed, not patched around.** The GENUINE,
     confirmed bug is different and simpler: `pro_phase_advance.dart` and `simulation_service.dart`
     read `progress`, awaited REAL plan-generation work (tens-hundreds of ms), then wrote the WHOLE
     map back from that pre-await snapshot — clobbering anything else that landed during the gap.
     Reproduced directly (not argued) and fixed by converting both to `updateProgress(delta)`,
     which re-reads fresh state at write time regardless of lock. Full account:
     `docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`.
  2. **Finding 3 (`BadgeService`) — CONFIRMED no live race, same as the earlier pass already
     found; left unlocked, pinned with a synchronous-invariant tripwire test instead of adding
     lock machinery for a race that cannot occur today.**
  3. **Finding 4 (`HealthSyncService.syncToHive`) — CONFIRMED genuine, closed.** Called both on
     app launch and via the Settings health-sync toggle; its only real await gap sits BEFORE the
     weight read-check-write (inside `fetchLatestWeight`), not between them, so two overlapping
     calls can both pass the `existing == null` guard before either writes. Closed with a
     whole-method in-flight-`Future` dedup guard — a second concurrent caller now awaits the
     first call's result instead of independently re-running the fetch and the unguarded
     check-write. **Round-1 review found a P2 in this exact fix**: the dedup guard's `Completer`
     called `complete()` unconditionally in `finally`, so a deduped follower would see "success"
     even when the leader's sync actually threw — fixed to propagate the real outcome
     (`completeError` + `rethrow`) to every waiter. **Round-2 review then found a P1 in THAT
     fix** (exactly the risk this repo's §4.12 names — "the corrections themselves can introduce
     new defects"): in the common case (no concurrent follower ever calls `syncToHive()` while
     one is in flight), nobody ever attaches a listener to `completer.future` — Dart treats a
     `completeError()` on an unlistened `Future` as an unhandled error and reports it a SECOND
     time to the current `Zone`, which this app's `main.dart` wiring turns into a duplicate FATAL
     Crashlytics report on every ordinary (non-concurrent) sync failure. Independently reproduced
     via a `runZonedGuarded` repro script, not taken on the reviewing agent's word. Fixed by
     attaching a no-op `completer.future.catchError((_) {})` immediately, before the first
     `await` — verified (a second repro) this silences the phantom duplicate without preventing a
     real follower from observing the true outcome via its own listener on the same `Future`.
  4. **Unplanned finding, NOT closed here, spun out as Unit 3b:** `update_streak_progress`
     (migration 056, built 2026-05-11 specifically for this OI's cross-device concern) has been
     **dormant for 2.5 months** — confirmed via its own migration-096 header comment AND an
     exhaustive `.rpc(` grep across `lib/` (one hit, unrelated to progress). Both cloud-push paths
     for the `progress` map (`syncFreezes()`, `_syncUserProgress()`) are plain unversioned
     upserts with zero optimistic-lock protection today. Closing this requires: wiring the
     already-built RPC into `syncFreezes()`, a new sibling RPC for the ~10-11 fields
     `_syncUserProgress` doesn't cover, local version tracking, and bounded retry-on-mismatch —
     none of which exist in this codebase's progress-sync path today. Scoped out of Unit 3a as a
     separable, higher-risk piece (new migration + new local state vs. Unit 3a's already-shipped,
     fully local, empirically-verified fix) rather than folded in or silently dropped.
  5. **Second unplanned finding, found by round-1 review of Unit 3a's own diff, NOT closed here,
     spun out as Unit 3c:** `graduation_screen.dart`'s `_onPro()` (lines 560-670) has the SAME
     general bug class this OI is about — `currentPhase`/`nextPhase` are computed at
     lines 568/573, BEFORE the slow `await scheduleSvc.generateAndSchedule(...)` (lines 642-659),
     then the pre-await `nextPhase` is written via `updateProgress({'current_phase': nextPhase,
     ...})` at line 665. Narrower blast radius than the fixed bug — already `updateProgress`
     (delta), not a whole-map `saveProgress`, so only `current_phase`/`current_week`/
     `phase_started_at`/`plan_generated_at` are at risk, and only if an independent concurrent
     advance (e.g. `pro_phase_advance.dart`'s splash-time auto-advance) lands during the window.
     Not a mechanical copy of Unit 3a's fix: `generateAndSchedule` has already produced real
     schedule rows for `nextPhase` by the time of the stale write, so the correct resolution
     needs its own conflict-resolution design, not a delta-conversion. Full account:
     `docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`'s "Round-1 review" section.
  6. **Round-2 review of Unit 3a's own diff, 3 more findings, all fixed here (no new open
     residual):** (a) the P1 named above in finding 4's own entry — a duplicate-Zone-error
     footgun in round-1's completer fix, fixed with a silencing listener. (b) A stale line
     citation (`_syncToHiveLocked` is at line 189, not 177). (c) The "12+ callsites across 9
     files" figure quoted at the top of finding 2 above was itself stale — a number set early
     and copy-pasted forward without being recounted as the enumerated writer list grew across
     three separate correction passes. Freshly re-counted via `grep -rn
     '\.updateProgress(\|\.saveProgress('` across `lib/`: **15 write callsites (13
     updateProgress + 2 saveProgress) across 11 files** (10 external callers +
     `user_repository.dart` itself, where `saveProgress`'s own body performs the actual Hive
     `put`) — this is now the correct figure, superseding "12+ / 9" everywhere it appears on
     this board. Full account of all 4 round-2 findings (a P3 test-scoping bug in
     `badge_service_synchronous_invariant_test.dart` also fixed, not board-relevant):
     `docs/diagnoses/2026-07-30-progress-map-stale-snapshot-d5c8a3.md`'s "Round-2 review" section.
  **This OI stays OPEN — findings 2-4's SAME-DEVICE / no-live-race / dedup halves are closed;
  finding 2's CROSS-DEVICE half is Unit 3b's scope, and the round-1-review-found
  `graduation_screen.dart` stale-write bug is Unit 3c's scope — neither started.**
- **CLOSED 2026-07-30** (cross-device-progress-lock batch, Unit 3b — finding 2's CROSS-DEVICE half,
  the item this OI's own text names above): the dormant `update_streak_progress` RPC (migration
  056, built 2026-05-11, never wired — see finding 4 in the prior correction block) is now wired
  into `syncFreezes()`; a new sibling RPC (migration 115, `update_user_progress_snapshot`) covers
  the 11 fields `_syncUserProgress` pushes that `update_streak_progress` doesn't. All 3 previously
  version-blind writers (`syncFreezes`, `_syncUserProgress`,
  `UserRepository.syncOnboardingToSupabase`'s onboarding-replay path via
  `pushOnboardingProgressSnapshot`) now route through version-aware writes with bounded
  retry-on-conflict. Full account: `docs/diagnoses/2026-07-30-cross-device-progress-optimistic-lock-e6b9c4.md`.
  Review pipeline converged before landing — 3 independent context-blind rounds + 3 B-pass
  dispatches + 1 11-lens Hermes pass, every single one found a real defect, severity strictly
  decreasing each round (the genuine-convergence signal per §4.12.1, not a unit too large):
  a P0 anon-executable grant on the new RPC (Postgres default-privileges bypass PUBLIC entirely —
  same class as diagnose a9d3f1); a stale pre-await Hive snapshot in both retry helpers that could
  clobber a concurrent same-device write (mirroring Unit 3a's own central bug, caught here by
  Hermes then again by round-3 review after the first fix only covered one of the two retry
  helpers); GREATEST-guards added to 3 monotonic "record" fields (`total_workouts_done`,
  `deployments_complete`, `longest_gap_days`) that were plain `COALESCE` and could silently regress
  on a stale-value retry — `longest_gap_days`'s guard is currently dormant (no live writer
  populates it yet) but closed proactively rather than left as a known gap for whenever one does.
  Migration 115 applied live against `dedsavbjuwgarrhphgnl` (2026-07-30T17:35:29+05:30), ACL
  independently re-verified post-apply via `has_function_privilege` (anon blocked, authenticated +
  service_role executable, matching the P0 fix). 21/21 live-Postgres regression cases (rollback
  transaction, run against the exact content subsequently applied), 46 wiring/contract tests, 6
  behavioral tests for the round-3-added `mergeRpcParamsPreferringNonNull` helper. Residual, NOT
  closed here: `restore-user-snapshot` Edge Function needs a redeploy for its freezes projection's
  new 5th column (`streak_progress_version`) — self-healing in the meantime (client degrades
  safely on an absent key, pinned by its own parity test), tracked as a separate follow-up
  requiring its own deploy authorization, not bundled into this merge. **OI-45 stays OPEN — only
  Unit 3c (`graduation_screen.dart`) and the Unit 3a behavioral-test-coverage gap remain.**
- **CLOSED 2026-08-01** (oi45-phase-advance-monotonic batch, Unit 3c + the Unit 3a
  behavioral-test-coverage gap — the last two items this OI's own text named above; shipped
  together because both needed the same test seam). Full account:
  `docs/diagnoses/2026-08-01-phase-advance-stale-target-c8f3d1.md`.
  1. **Unit 3c is BROADER than finding 5 described, and the description's core premise was
     wrong in the user's favour.** Finding 5 called it "narrower blast radius than the fixed
     bug — already `updateProgress` (delta)". The delta form is indeed safer for the OTHER
     fields, but the `current_phase` VALUE in that delta was still the pre-await one — so the
     residual was not unique to `graduation_screen` at all: `pro_phase_advance.dart:117` and
     `simulation_service.dart:565`, the two callsites Unit 3a "fixed", carried the identical
     stale value. All three now route through one monotonic writer
     (`pro_phase_advance.dart` `commitPhaseAdvance`) that re-reads `current_phase` at write
     time and refuses a lower-or-equal value. Verified root fact: `current_phase` had **no
     monotonic guard anywhere** — `saveProgress` guards `deployments_complete` and writes
     `current_phase` straight through (`user_repository.dart:128-135`).
  2. **A second, likelier defect finding 5 did not name:** `graduation_screen` ran
     `generateAndSchedule` entirely OUTSIDE the module-private advance mutex, so a splash pass
     and a graduation unlock could each generate the same phase — the second overwriting the
     first's `schedule_*` rows and `plan_start` under a user already looking at the plan. The
     mutex is now shared (`withPhaseAdvanceLock`) and graduation takes it around generation +
     write, never across the choice sheet.
  3. **The guard that existed never ran.** `graduation_screen`'s live-phase abort re-check sat
     inside `if (offerChoice)`, and `offerChoice` requires
     `PlanEngineFlags.adherenceGateEnabled` — ship-dark, DEFAULT OFF — so on the production
     default path it had never executed. Hoisted out. **Round-1 review then corrected the
     credit given to that hoist:** on the flag-OFF path there is no `await` between the
     `progress` read and the re-check, so it is provably unreachable today and buys nothing
     until the adherence gate flips ON. What actually closes the default-path hole is the
     shared lock plus `commitPhaseAdvance`'s write-time re-read. Recorded because the first
     draft of this closure claimed the hoist "guards every unlock".
  4. **Task #41 (the Unit-3a B-pass coverage gap) closed, and that B-pass's diagnosis
     corrected.** It attributed the gap to needing "genuinely novel test infrastructure";
     really, driving real plan generation in a test was already established
     (`repeat_content_scheduling_test.dart:154-195`) and no provider override is needed. The
     actual blocker was the auth seam — `ensureOpenedForCurrentSession()` returns null with no
     Supabase, so the function returned `false` on its second line. Those two lines moved into
     the public wrapper; the core is now `@visibleForTesting` and driven for real.
  5. **14 tests, both behavioral ones proven to discriminate by negative control** (reverting
     the guard fails the demotion test; reverting to a whole-map `saveProgress` fails the
     unrelated-field test). An early draft of the demotion test was a **false green** — a 20 ms
     delay let generation finish first, making the interposed write simply the last writer;
     replaced with a single event-loop yield plus an explicit ordering precondition so a miss
     fails loudly. Recorded because the failure mode is generic to every interposition test.
  6. **Not fixed, not applicable:** no data repair. A phase demoted by this in the past leaves
     no trace distinguishing it from a legitimate value, so the historical incidence is
     unknown rather than clean — stated as unknown.

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

## OI-82 — `promote-community-item` calls an RPC that does not exist on this project (P2)

- **Status**: CLOSED IN SOURCE · 2026-08-07 · branch `claude/work-session-3rqcp5` (Unit 1).
  Diagnose `d5b8c2`; test `test/contracts/promote_community_vote_tally_test.dart` (5 assertions,
  negative-controlled by reinstating the defect). **The redeploy is NOT done — see below.**
- **Blocked on**: FOUNDER, for the redeploy only. The code fix is landed; the DEPLOYED bundle still
  contains the dead call until `promote-community-item` is redeployed, which per §4.3 is a separate
  explicit authorization (plan approval ≠ deploy approval). The session that made the fix also had
  no `supabase/.supabase/` access token, so the host-shell deploy path was not available from it.
  Stated rather than omitted because conflating "committed" with "live" is precisely what OI-47 was
  caught doing.
- **Verified**: 2026-08-07 — premise RE-CONFIRMED LIVE today, not inherited: `pg_proc` across every
  schema on `dedsavbjuwgarrhphgnl` returns **zero rows** for `community_votes_summary`.
- **Identified**: 2026-08-01, while waiving RPC reads for the OI-79 gate.
- **What was wrong**: `promote-community-item/index.ts:128` and `:197` both called
  `.rpc("community_votes_summary")`. The function does not exist, so `.rpc()` returned
  `{data: null, error}` (PostgREST reports a missing function as an error object rather than
  throwing) and `candidates ?? fallbackCount(...)` fell through on every tick — the primary
  vote-summary path had never executed in production.
- **What this entry MISSED, and it is the more interesting half**: the error was also
  **unreportable**. The guard was `if (countErr && !list)`, but `fallbackCount` returns `[]` on
  failure and `![]` is `false` in JS, so the branch could not execute even when `countErr` was set.
  A dead guard wrapped a dead call and the pair source-greps as working error handling — the
  literal shape of the source-grep-false-confidence class. (That class is named after a
  `feedback_*.md` that lives only in the harness-local memory directory and is NOT in this repo —
  `memory/MEMORY.md:8` documents that trap. Stating the class in words here so the reference is
  followable from a clone, per the same lesson.)
- **Intent decided (2026-08-07, founder): DELETE the call, promote the tally.** Evidence: no
  migration in the repo has ever defined the function — the sole textual match in
  `supabase/migrations` is a PROSE COMMENT at `101_admin_dashboard_metrics_functions.sql:16` citing
  it as an example of an *existing* public function, which it is not (that comment is NOT corrected
  here — see the tier note below). So there was no unapplied migration to restore; it was speculative code whose
  helper was never written. `fallbackCount` already computed exactly what the RPC's name promises —
  same `{item_id, approves}` shape, same `APPROVAL_THRESHOLD` applied identically — so creating the
  RPC would have meant inventing unspecified ranking behaviour to replace a path that already works.
- **Fix landed**: both `.rpc()` calls, both `oi79-ok` waiver comments and both dead `countErr`
  guards deleted; `fallbackCount` renamed `countApproveVotes` and called directly; its doc comment
  rewritten (it had described itself as a fallback "if the RPC helper doesn't exist yet"). The
  waivers had to go WITH the calls: `check_unbounded_cron_reads.dart` matches waivers by line
  proximity, so an orphaned one can drift onto a neighbouring read and silently bless it. Gate now
  exits 0 with 3 waived reads repo-wide, down from 5, and none in this file.
- **Live state at close (why this closure does not overclaim)**: the entire community-promotion
  surface is dormant — 0 approve votes ever cast, 0 items approved, 0 rows in `food_database` or
  `exercise_library` with `source='community'`. Removing a path that never returned a row cannot
  change an outcome. This was a diagnosability fix, not a user-visible one.
- **Tier note — why migration 101's false-precedent comment was left alone**: that file already
  contains the literal phrase "SECURITY DEFINER" (line 33, plus the `security definer` clauses on
  the three functions it defines), and `blast_radius_content_rules_lib.dart` matches WHOLE-FILE
  content rather than the diff hunk. Editing even a comment there escalates the whole batch
  platform → **catastrophic**, pulling in a hermes pass. Measured, not assumed: staged →
  `catastrophic`, unstaged → `platform`. Tracked as ledger entry `MIG-101-COMMENT` in
  `docs/audit/oi_unit1_backlog.closure.yaml` to ride with the OI-78 unit, which must author a
  migration at that tier anyway. Recorded here because "why didn't they fix the obvious one-line
  comment" is the first question a reader will have.

## OI-79 — Un-ranged PostgREST reads silently truncate at db-max-rows (1000) in cron candidate scans (P1)

- **Status**: CLOSED (2026-08-01, Unit 9 — branch `oi79-paged-cron-reads`, commits `cda5b62c`
  → `017014f1` → `337bf6eb`)
- **Blocked on**: none
- **Verified**: 2026-08-01 (Hermes L31, Unit 5 re-engagement-prefilter) — empirically confirmed
  live, not inferred: an unbounded `GET /rest/v1/food_database?select=id` returns
  ~~`HTTP/1.1 206 Partial Content` with `Content-Range: 0-999/1431`~~.

- **CORRECTION 1 (2026-08-01, Unit 9 — the response is 200, not 206).** Re-measured live against
  `food_database`: the bare read returns **`HTTP 200 OK`**, `Content-Range: 0-999/*`, 1000 rows,
  `error === null`. A 206 requires `Prefer: count=exact`, which supabase-js does not send. This
  matters and is not pedantry — the original text implied a status code a caller could branch on.
  There is none, and the total is `*`, so the response does not even carry what you would need to
  detect the loss. The only signal is the row count, and it is ambiguous.
- **CORRECTION 2 (same pass).** The `morning-alert` pagination precedent cited at `:583-594` is a
  *different and better* pattern than the `.range()` loop this OI implied: it passes `p_offset`/
  `p_limit` into an RPC so ordering and paging both happen server-side. The `.range()` loop is at
  `:790-810`. Also: `.range()` CANNOT raise the cap (a `Range: 0-1499` still yields 1000), and no
  per-role override exists (`pg_db_role_setting` → 0 rows), so `service_role` — what every cron
  uses — is capped like everyone else.
- **Path B resolved.** This OI left "does the cap apply to RPCs?" as *very likely, not proven*. It
  is now irrelevant rather than answered: the helpers page unconditionally, so the behaviour is
  correct either way.
- **Scope found to be larger than filed.** OI-79 named 2 sites. Re-running the lens across the
  whole cron fleet found **21 reads in 4 distinct classes**, one WORSE than the under-coverage
  filed here: truncated `.in()` joins that decide who is EXCLUDED, which do not skip a user but
  *misclassify* one — e.g. `protein-gap-alert` sending "you're short on protein" to someone who hit
  their target (bites at ~250 active-PRO users), and `_shared/notification_prefs` clipping the
  preference tail so every notification toggle past ~175 users was silently ignored under its own
  ABSENT⇒SEND rule.
- **Fix**: `supabase/functions/_shared/paged_fetch.ts` (`fetchAllPages`/`fetchAllByIds`; `orderBy`
  required with no default, since a pagination loop without a stable sort key is its own bug),
  every site routed through it, plus gate `scripts/check_unbounded_cron_reads.dart`.
- **Nothing was truncating live.** 18 users; largest per-user table 565 rows. This was a latent
  correctness fix landed before growth, not an outage — stated so the closure does not overclaim.
- **Evidence**: diagnose `docs/diagnoses/2026-08-01-unbounded-cron-reads-d3f7b2.md`; ledger
  `docs/audit/2026_08_01_oi79_paged_cron_reads_closures.yaml` (41/41 terminal); behavioral proof
  end-to-end against live PostgREST (bare read 1000/`error===null` vs `fetchAllPages` 1431 = exact
  server count, no duplicates across page boundaries); 316 Deno tests; ×2 context-blind review +
  B-pass per §4.12 (`docs/plan-reviews/oi79-paged-cron-reads.md`).
- **Spawned**: OI-80 (below).
- **Identified**: 2026-08-01 · Hermes lens L31 (cron efficiency) during Unit 5's catastrophic-tier
  review.
- **What's wrong**: PostgREST caps an un-ranged response at `db-max-rows` (1000 on this project).
  **supabase-js does NOT treat a 206 as an error** — `error` is null and `data` is simply short, so
  a truncated read is indistinguishable from a small one. `re-engagement/index.ts` has no `.range(`
  or `.limit(` on either candidate path:
  - **Path A** (`.from("coach_memory").select(...).gte("dropout_risk_score", 0.5)`) — REAL,
    empirically confirmed class. At >1000 high-risk users it silently processes a truncated set.
  - **Path B** (the `find_reengagement_silent_candidates` RPC added by migration 117) — PARTIAL.
    PostgREST documents `db-max-rows` as applying to "table, view, or **stored procedure**" (same
    code path), but this could NOT be empirically proven on this project: no anon-executable
    set-returning function here can return >1000 rows (only 18 live users). Treat as very likely,
    not proven.
  - Same exposure very likely applies to the other unpaginated cron candidate scans — `i-see-you-callout`
    paginates (`PAGE_SIZE=1000`), `morning-alert` paginates (`:583-594`), but the rest were not
    audited under this lens. **Scope the fix by re-running the lens across all cron functions, not
    just the two named here.**
- **NOT introduced by Unit 5 — Unit 5 strictly improved it.** The pre-migration-117 Path B
  truncated an *unordered, unfiltered* `.from("users")` fetch at 1000 rows *before* any activity
  filtering, so it could yield ~0 genuinely-silent users; the RPC returns up to 1000
  *already-filtered* ones. Unit 5 added saturation DETECTION (a loud `console.warn` naming this OI
  when either path returns >= 1000 rows, `re-engagement/index.ts:154` and `:240`) so the condition
  is no longer silent — but detection is not a fix.
- **Fix shape**: a `.range(offset, offset + PAGE_SIZE - 1)` pagination loop over both paths, with
  in-repo precedent at `morning-alert/index.ts:583-594` (`PAGE_SIZE` + offset loop, `hasMore`
  termination on a short page). `.range()` works on `.rpc()` calls as well as table selects.
  Cross-check while doing this: `active_users_for_signals()` carries an internal `limit 5000`,
  which is UNREACHABLE through PostgREST if the cap applies to RPCs — contradicting
  `compute-coach-signals/index.ts:6-8`'s "worst-case is 5000" comment. Same class; resolve together.
- **Blast radius estimate**: `account` (Edge Function logic only, no migration, no client) —
  confirm via `scripts/blast_radius_from_diff.dart` at diff time.

## OI-50 — L37 empty/null-shape readers: 23 risky accesses across 6 files (P2)

- **Status**: CLOSED
- **Blocked on**: none — Unit 7 (2026-08-02, diagnose `d4e7c2`) landed both confirmed
  silent-wrong sites. See the final closure block below.
- **Verified**: 2026-08-02
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

  **CLOSED 2026-08-02 — Unit 7, diagnose `d4e7c2`.** Both remaining silent-wrong sites are
  fixed, and the fix is structural rather than two local null-guards, because the 2026-07-29
  correction — accurate on the count — still described them as independent. They are **one**
  bug: the cloud-restore writer (`sync/sync_workout.dart:733-767`) emits a different subset of
  the exlog aggregate fields than the client-side writer, and each reader hand-rolled its own
  reconciliation.

  What was actually wrong, beyond the board text:
  - `workout_receipt_card.dart` did not merely render an empty per-set breakdown. It rendered
    **0 duration** for a restored timed/cardio exercise, because a 2026-05-24 drift-fix had
    hardcoded `const int duration = 0` on the reasoning that the modern writer never emits a
    top-level `duration_seconds` — true of that writer, false of the restore writer (`:766`),
    which is the only one that produces the affected rows.
  - `edit_workout_log_sheet.dart` read only the legacy `sets_completed`, so the SETS box was
    **blank on every cloud-restored row** (restore stamps `set_number`), and its duration box
    used a per-set MAX for a value `save` writes back as a SUM — so saving a restored multi-set
    timed row **wiped the real total to 0**. That is local data loss, not just display drift.

  Fix: one shared reader — `WorkoutReadService.aggregateSetCount` /
  `hasAggregateSetCount` / `aggregateDurationSeconds` — with both surfaces delegating, a
  `hasAggregateData` flag so an absent count is distinguishable from a logged zero, and
  `exlog_no_aggregate_signal` telemetry. Behavioral coverage:
  `test/contracts/exlog_aggregate_read_behavioral_test.dart` (23 tests; 5 verified to fail
  against the pre-fix readers; 63 green across the 10 affected contract files).

  **Three review rounds corrected the scope, in the board's favour.** There were not 2
  hand-rolled aggregate readers but **7**. Round 1 found `week_selector.dart`,
  `exercise_preview_sheet.dart` and `expanded_exercises.dart`; round 2 found
  `workout_repository.dart:941` (`getExercisePRHistory` — it feeds the AI coach via
  `ai_snapshot_builder` and `pattern_detector`, so a restored user's coach reasoned over zeroed
  set history); the B-pass found `train_provider.dart:1556` (the workout-finish PR banner, whose
  hand-rolled divisor collapses to 0 on the APK Test #12.1 shape and silently suppresses a
  genuine PR). All seven now delegate. The gate that should have caught the class,
  `no_top_level_duration_seconds_reads_test.dart`, scanned only `lib/features/train/` and its
  failure message recommended the exact call that causes the bug; it was rewritten to scan
  `lib/core/services/` as well and to pick by semantic.

  The refuted count ("23 risky accesses across 6 files") is left in the heading deliberately —
  the body already corrects it, the wrong claim is useful history, and a CLOSED issue no longer
  appears in `OPEN_INDEX.md`, so nothing surfaces the stale number any more.

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

## OI-53 — Flip the remaining 12 workout-generator ship-dark flags (was 13; equipment-exclusions flipped 2026-08-05)

- **Status**: OPEN
- **Verified**: 2026-08-05 — flag inventory, dependency order and the data lag all re-derived from
  source this session (`plan_engine_flags.dart`, `deload_evaluator.dart:170,173`,
  `ship_dark_pending_review.yaml:76-101`), not carried from the entry's original text.
- **Identified**: 2026-07-26 · workout-generator overhaul complete `7bb766fa`
- **Blocked on**: FOUNDER — but read the shape below before treating this as one decision.
- **What this actually is — 13 product decisions, not one toggle.** The ledger is explicit:
  *"there is no batch discount, and flipping thirteen flags in one commit would be one review
  pretending to be thirteen."* Each flip-on commit needs its own **full ×2 + `bpass: accepted`**
  (§4.12.4 — the lighter `ship_dark_build` tier does NOT apply to a flip). Nothing is broken by
  leaving them OFF: every shipped APK to date has run with all 13 dark, so OFF *is* the current
  product. What is owed is a decision per flag, not a flip.
- **The order is forced by code, not preference.** `enable_readiness` must flip FIRST:
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

- **Status**: CLOSED · 2026-08-07 · branch `claude/work-session-3rqcp5` (Unit 1).
  Entry appended to `docs/sot_registry.yaml` (concept `notification_preferences`, domain `profile`),
  `behavioral_test_path: test/contracts/notification_prefs_rescope_behavioral_test.dart`.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-07 — Gate 42 (`check_sot_behavioral_test_paths.dart`) PASS at 107 concepts;
  `check_reader_manifest_complete.dart` and `check_snapshot_contract.dart` both PASS;
  `sot_registry_completeness_test.dart` ([Gate 7 mirror]) PASS. That last one earned its keep: the
  first draft of this entry cited `line_range: 205-240` for `write` in a 232-line file, and a
  `read` range of 120-145 when `read()` is at :155. Both were caught by the gate, not by review —
  worth recording because this entry's whole point is that its citations be trustworthy.
- **Identified**: 2026-07-27 · B-pass
- **What was missing**: §4.5 requires a `docs/sot_registry.yaml` entry for a new writer/reader
  contract. The arc created one (repository → compileDailySnapshot → Edge Function readers) and
  did not register it. `docs/snapshot_contract.yaml` WAS updated, so the drift gate covers the
  snapshot seam; the SoT registry entry was the missing half.
- **⚠ THIS ENTRY'S READER COUNT WAS WRONG — it said 6, the real number is 10.** Re-derived by grep
  at close time rather than copied (this entry's own citations, and `snapshot_contract.yaml`'s
  `notification_preferences` readers block, are recorded as unvalidated by OI-80). The server
  readers are **not uniform**: SIX consume `_shared/notification_prefs.ts`
  (`morning-alert:56`, `plateau-alert:44`, `pr-detection:24`, `proactive-coach-promotion:27`,
  `protein-gap-alert:46`, `re-engagement:55` — import sites), and **FOUR read
  `snapshot_json.notification_preferences` INLINE and never import the helper**
  (`weekly-recap-ready:54`, `streak-guardian:177`, `workout-window-closing:233`,
  `expiry-reminder:118`). "6" was the helper group only. Recorded because it is a live maintenance
  hazard, not a bookkeeping nit: **a change to the helper's semantics reaches only 6 of 10
  consumers**, and the ABSENT ⇒ SEND default means a divergence fails toward sending notifications
  rather than withholding them.
- **Note on §4.4 r21**: this closure also corrected root `CLAUDE.md` §4.4 r21, which still described
  Gate 42 as emitting a WARN with a `behavioral_test_required: true` backlog. The gate has been
  STRICT by default for some time and that marker is now itself a hard blocker — the stale wording
  is what led this OI's own plan to propose a bare registry entry that would have failed pre-commit.

## OI-76 — Notification count includes PRO-locked rows a free user cannot disable

- **Status**: CLOSED · 2026-08-07 · branch `claude/work-session-3rqcp5` (Unit 1).
  Diagnose `a7e3d1`; tests `test/contracts/notification_pro_key_scoping_test.dart` +
  `test/contracts/paywall_feature_label_test.dart`, both negative-controlled by execution.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-07 — fixed and pinned. `flutter test test/contracts/ test/router/` → 2832 pass
  on Flutter 3.41.4 (the CI-pinned version) with `TZ=Asia/Kolkata`.
- **Identified**: 2026-07-27 · B-pass
- **What was wrong**: `profile_content.dart` counted all 10 registry keys, including Protein Alerts
  and Plateau Check. A free user cannot turn those off, and their server functions PRO-gate anyway,
  so the subtitle permanently read at least 2/10 "enabled" for notifications that would never fire.
- **⚠ THE "Related" LINE BELOW WAS WRONG ON ITS SECOND CLAIM — kept verbatim, corrected here.**
  It read: *"the paywall callback passes `AppConstants.featureProgressPhotos` for notification
  rows — wrong copy, and §4.4 r19 keys server-side verification off that id."*
  1. **The first half understated it.** `PaywallSheet` renders `feature` VERBATIM into its
     letterhead (`paywall_sheet.dart:367`, `'${widget.feature} is a PRO feature'`), so a free user
     tapping a locked notification row was shown the literal string
     **"progress_photos is a PRO feature"** — not merely the wrong copy, the raw identifier. It was
     the only one of ~25 `showPaywallSheet` call sites passing a snake_case constant; every other
     passes a display string.
  2. **The second half is FALSE.** §4.4 r19 does NOT key off this id. `showPaywallSheet`
     (`paywall_sheet.dart:23`) is display + telemetry only and never reaches `gate()` or
     `verifyFromServer()`; r19 keys off `gateAndVerify`'s positional first argument, a different
     call. Both appear together at `profile_content.dart:345-349`, which is the convention this fix
     restores: **id → the gate, display string → the paywall.** Acting on the claim as written
     would have produced a fix aimed at a server-side contract that does not exist — and the
     obvious "swap in a new `AppConstants.featureNotifications`" would have changed nothing, since
     `_featureSubtitle` switches on display strings and any constant still falls to the default arm.
- **Also fixed, found while fixing the above**: all three NOTIFICATIONS rows in `settings_screen.dart`
  pushed `/profile/notification-settings` with no `extra`, so the route's `?? false` default showed a
  **paying PRO user a lock** on the two PRO rows. The screen's own `initState` comment names that
  exact harm as one it fixed, but only the prefs half was ever fixed. `isPro` was already in scope at
  `settings_screen.dart:40`.
- **Load-bearing constraint the fix had to respect**: `allKeys` and `emissionMap()` are NOT narrowed.
  The server's rule is ABSENT ⇒ SEND, so scoping the emitted snapshot by tier — the intuitive
  implementation — would turn the two PRO notifications **ON** for free users. Pinned by a
  negative-controlled test rather than a comment.

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

## OI-83 — cloud→Hive `progress` restore merges bypass every monotonic guard, and can demote `current_phase` (P2)

- **Status**: CLOSED
- **Blocked on**: none — the scoping decision was made by the founder 2026-08-03
  (**local-max-wins**, with telemetry) and Unit A shipped both halves. Closure block at the
  end of this entry.
- **Verified**: 2026-08-03 (Unit A, diagnose `d1f6b3` — all 7 writers re-read directly)
- **Identified**: 2026-08-01 · round-1 context-blind review of the oi45-phase-advance-monotonic
  batch, while checking whether that batch's claim "`current_phase` is now monotonic" holds
  end-to-end. It does not — it holds for the ADVANCE operation only.
- **Risk class**: monotonic-field demotion via a cloud-wins restore
  (`feedback_monotonic_field_recompute_demotion.md`; siblings 3a7b9f, c8f3d1)
- **What's wrong**: `grep -rn "put('progress'" lib/` returns **7** direct writers of the whole
  `progress` map. Exactly one is `UserRepository.saveProgress`. Two of the others are cloud→Hive
  merges that copy the PostgREST row's values verbatim, cloud-wins, straight into `userBox`:
  `sync/sync_profile.dart:612-622` (`_restoreUserProgress`) and
  `auth_session_bootstrapper.dart:322-328`, both shaped
  `{...existingMap, for (final e in cloud.entries) if (e.value != null) e.key: e.value}`.
  A stale cloud row restored over a locally-advanced Hive value therefore demotes `current_phase`
  (and any other monotonic field in that map) with no guard, no telemetry, and no trace — the
  advance-side guard `c8f3d1` added sits on `commitPhaseAdvance`, which these do not go through.
  Two more (`sync_restore_completeness.dart:242,411`) write the map directly as well and want the
  same audit.
- **Why it is NOT folded into c8f3d1**: that batch's scope is the advance operation, and its own
  `restore_methods: not_applicable` is scoped-correct. This is a different operation with a
  different correct answer, and choosing it is a product/architecture call, not a mechanical fix:
  a restore that refuses to lower `current_phase` is right for a second device that is behind, and
  WRONG for a genuine account restore where the cloud row is the only truth left. Guessing between
  those would be exactly the kind of unverified premise this board exists to catch.
- **Fix shape (needs the scoping pass first)**: decide per-field whether the progress map's
  monotonic fields (`current_phase`, `deployments_complete`, `total_workouts_done`,
  `longest_gap_days`) are local-max-wins or cloud-authoritative on restore; then either route all
  4 map writers through one merge helper that applies that rule, or document why verbatim
  cloud-wins is correct and add telemetry when a restore lowers one.
- **Second-order effect, named so it is not rediscovered as a fresh incident** (B-pass F1 of the
  same batch): because these writers bypass `withPhaseAdvanceLock` entirely, one of them can bump
  `current_phase` *while* `graduation_screen._onPro` is inside the lock running
  `generateAndSchedule`. The counter then behaves correctly — `commitPhaseAdvance` declines the
  stale write — but the `schedule_*` rows and `plan_start` already written for that phase are NOT
  rolled back or reconciled against whatever the restore delivered. c8f3d1 narrowed this by
  re-checking the live phase inside the lock immediately before generating (so a bump that lands
  *before* generation no longer causes a wasted generate); the window that remains is a bump
  landing *during* generation, which is this OI's to close.
- **Blast radius estimate**: `account` (touches `lib/core/services/sync/**` +
  `auth_session_bootstrapper.dart`; no migration).

### CLOSURE — Unit A, 2026-08-03, diagnose `d1f6b3`

**Founder decision (the scoping call this entry was waiting on):** the monotonic progress fields
are **local-max-wins on restore**, with telemetry when one is refused. The alternative —
arbitrating on `updated_at` / `streak_progress_version` — is only needed if a *deliberate*
backward move must propagate across devices, and today none does: the only two writes that lower
the phase are onboarding's first write on a fresh account (nothing to demote) and the dev-panel
`resetJourney` (`simulation_service.dart:108`, debug-only). Revisit if a user-facing "restart my
journey" ever ships.

**This entry's "two more want the same audit" — audited, and they are NOT vectors.**
`sync_restore_completeness.dart:242,411`, `sync_service.dart` `_stampProgressVersion` and
`streak_freeze_clamp_migrator.dart` all read-modify-write a freshly-read map and mutate only
freeze keys / `streak_progress_version`, so they preserve whatever `current_phase` is present.
**Exactly 2 of the 7 writers were demotion vectors**, both now routed through the shared
`UserRepository.mergeCloudProgress`. Result recorded in `docs/sot_registry.yaml` so the next pass
does not re-derive it.

**The second-order half is NOT closed — it is REPORTED, and its repair is OI-85.** This closure
originally claimed it was fixed by forcing `PlanIntegrityReconciler` past its `needsHeal` gate.
Review refuted that (inert — `mergeScheduleEntry` re-applies the same predicate per row), then
refuted the follow-up (`preferSnapshot` + orphan sweep — data loss, because cloud `plan_json` is
only daily-fresh and spans every `schedule_*` key). Per §4.12.1 the smallest converged piece
ships: a `phase_advance_declined_rows_stale` event, HIGH-priority in both twin lists so the
frequency can actually be measured, and the repair filed with all three refutations.

**Also corrected:** `sync_profile.dart:592-609` justified the wholesale merge with "a fresh
restore read is always at least as new as whatever's local" — true of the server-owned
`streak_progress_version` it was written about, false of a client-advanced field. Left in place it
would have re-justified the bug for the next reader.

**Round-1 review changed three things in this closure, and each is worth carrying:**
- **`longest_gap_days` is NOT guarded**, though this entry's own fix-shape listed it. It is
  INVERTED — higher is worse, it gates a rank (`rank_service.dart:506`), it has no client writer,
  and migration 115 already GREATESTs it server-side — so local-max-wins could only ever refuse a
  server correction and pin the rank ladder shut. The guarded set is **3**, not 4.
- **A §4.6 kill-switch ships** (`disable_progress_restore_monotonic_merge`). The measured tier is
  `platform`, where `docs/blast_radius.yaml:25` makes `feature_flag` a requirement — and the
  `longest_gap_days` catch is itself the argument: a per-field judgement list can be wrong in a
  way a proven total order cannot.
- **The second-order half is REPORTED, not repaired — and its repair is now OI-85.** Three
  mechanisms were designed and each refuted, the last two by context-blind review: (1) restore
  takes `withPhaseAdvanceLock` → it is a TRY-lock, so the restore would be dropped entirely;
  (2) force past `needsHeal` → INERT, because `mergeScheduleEntry` re-applies the same
  local-has-exercises predicate per row; (3) `preferSnapshot` + deleting rows past the
  re-anchored `plan_end` → DATA LOSS, because cloud `plan_json` is pushed only by the DAILY full
  sync and can be 24h stale (the sweep would delete the WINNER's fresh rows), and the snapshot
  spans every `schedule_*` key box-wide (so it would revert an un-synced local swap). Per
  §4.12.1 the smallest converged piece ships: the demotion fix, plus a
  `phase_advance_declined_rows_stale` event that makes the condition visible for the first time.

**Not deployed, and it needs its own go:** `supabase/functions/log-client-error/index.ts` gains the
two new events in its `HIGH_PRIORITY_OP_TYPES` twin list. The code is committed and the client half
is live; until that function is deployed the server still classifies those events as LOW priority.

Tests: `test/contracts/progress_restore_monotonic_behavioral_test.dart` (23, with the pre-fix
merge inline as the negative control and the default `mergeScheduleEntry` mode as a second one) +
`test/contracts/restore_progress_uses_shared_merge_test.dart` (8 executed, routing pin,
presence-only by construction). 31 total, all green; 87 across the 7 affected suites.

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

## OI-84 — `graduation_screen.dart` added to the Gate 43 allow-list; split owed (P3)

- **Status**: CLOSED
- **Blocked on**: none — it was scheduled work and Unit B did it. Closure block at the end of
  this entry.
- **Verified**: 2026-08-03 (Unit B, diagnose `b4e9c7` — Gate 43 run with the allow-list entry
  DELETED: `OK — no screen exceeds 800 lines`, and `graduation_screen.dart` no longer appears
  in the `ALLOW` output at all)
- **Identified**: 2026-08-01 · Gate 43 blocked the `oi45-phase-advance-monotonic` commit
  (`c8f3d1`, Unit 3c).
- **Risk class**: god-screen / tech-debt ladder regression
- **What happened**: `lib/features/train/screens/graduation_screen.dart` was **794 lines — six
  under Gate 43's 800 ceiling** — so Unit 3c's phase-advance monotonic fix could not touch that
  file at all without tripping the gate. It is now 892 (of the +98, 77 are comment lines added at
  the direct request of the three review rounds). The file was added to the gate's transitional
  allow-list (`scripts/check_god_screen_max_lines.dart`) **on explicit founder authorization**,
  after being shown that (a) the gate has no per-run exception — no env var, no `--warn-only`, it
  exits 1 unconditionally — and (b) the allow-list is a one-way ratchet whose every prior movement
  was a *removal*. This is the first entry ever added to it.
- **Why this is tracked rather than closed**: the allow-list's own header says it "MUST shrink to
  empty when the audit ladder closes". A seventh entry with no owed-work record would quietly
  reverse that direction. This OI is that record.
- **Not a C3/C4 reopening**: `graduation_screen.dart` was never a C3 or C4 target (those were
  `active_workout`, `train`, `profile`, `ai_coach`, all closed by splitting). It was simply under
  the ceiling until this batch.
- **Fix shape (recommended, from the c8f3d1 review)**: rather than a pure part-file split, hoist
  the locked generate + `commitPhaseAdvance` + repeat-nudge block (~120 lines) out of `_onPro` and
  into the shared advance service next to `commitPhaseAdvance`, where the other three advance
  paths already live. That lands the screen at ~770 (under the ceiling honestly, not by
  exemption), leaves the screen doing UI only — choice sheet, snackbars, navigation, provider
  invalidation — and completes the "one place owns the phase advance" thesis c8f3d1 started.
  Reference layout for the alternative pure split: `lib/features/train/screens/active_workout/`.
  **Remove the allow-list entry in the same commit.**
- **Blast radius estimate**: `account` (`graduation_screen.dart` has its own file-scoped account
  rule in `docs/blast_radius.yaml`); no migration, no schema.
  MEASURED at ship time: **`platform`** — but only because the B-pass fix edited
  `docs/blast_radius.yaml` itself (`:171`, a platform-tier path). Per-file, the
  runtime code is `account` (`graduation_screen.dart`, `pro_phase_advance.dart`)
  and everything else is `feature`. The estimate was right about the CODE.

### CLOSURE — Unit B, 2026-08-03, diagnose `b4e9c7`

**909 → 552 lines. The allow-list entry is deleted and the ratchet is shrinking again** (six
entries, all original C4 targets).

Two moves, one deletion, one commit:

1. The ~120-line locked generate + `commitPhaseAdvance` block → `runGraduationPhaseAdvance` in
   `lib/shared/services/pro_phase_advance.dart`, beside the other three advance paths. Its
   `bool?` return became `GraduationAdvanceResult` — a four-case outcome enum plus
   `repeatNudgeFlagged`. The old `false` had covered TWO outcomes that already emitted
   *different* telemetry, so the type was lossier than the instrumentation next to it.
2. The ~250-line phase-2 preview UI → `lib/features/train/widgets/phase2_preview_card.dart`
   (`Phase2PreviewCard` / `Phase2BenefitsCard`). Both builders already took no `ref` and no
   `BuildContext`, so this was a move, not a refactor.
3. The `_allowList` entry deleted from `scripts/check_god_screen_max_lines.dart` in the same
   commit.

**Step 2 was NOT this item's recommended shape, and the reason is worth keeping.** The hoist
alone landed the file at ~791 — **nine lines of margin**. That is the identical condition that
*created* OI-84: the file sat six under the ceiling, so Unit 3c could not touch it at all. This
item's own "~770" estimate had gone stale, because Unit A grew the file from 892 to 909 after
the estimate was written. Founder chose the fuller split once shown the arithmetic. **A board
item's numbers age; re-measure before planning against them.**

Two second-order findings, both fixed in the same commit:

- `docs/blast_radius.yaml:207-216` justified this file's `account` rule with "contains a
  confirmed direct write to the progress map (`_onPro()`)" — **false after the hoist**. The tier
  is unchanged and still correct (the screen is the UI entry point for the PRO advance and gates
  `phases_2_to_12`), but the justification was restated. Same class as the
  `check_writer_reader_drift.dart` citation corrected in `lib/CLAUDE.md` on 2026-08-02: a rule
  whose stated reason is false reads as coverage it does not have.
- The hoist could have relocated the progress write into a path classified BELOW `account`,
  silently weakening the review gate while every other test stayed green. It did not —
  `docs/blast_radius.yaml:226` gives `pro_phase_advance.dart` its own `account` rule — but that
  is now **asserted in a test** rather than assumed, so the next move cannot regress it.

**Verification.** Six pre-existing test files source-grep `graduation_screen.dart` by path;
moving code out of it turns such assertions vacuously true, which is worse than deleting them
(`feedback_source_grep_false_confidence.md`). All six were re-pointed, and ten assertions were
then individually PROVEN to discriminate by perturbing the source and watching each fail —
files restored from copies afterwards and verified byte-identical by md5, never `git checkout`
(the Unit 7 incident). `pro_phase_advance_behavioral_test.dart` gains group D2: four behavioral
tests, one per outcome arm, against real Hive and real plan generation — coverage that could not
previously exist, because the code was a closure inside a widget callback that nothing could
call.

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

## OI-89 — the equipment tier is a SOFT preference: a "bodyweight" user is served gym lifts (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical — it needs a PRODUCT decision first (see "Product question"
  below). The mechanism is understood and verified in code.
- **Verified**: 2026-08-04 (root cause re-read directly in `exercise_selector.dart` +
  `plan_engine/CLAUDE.md`; the flag default re-read in `plan_engine_flags.dart` — the source
  commentary's claim about it did NOT match the code, see below)
- **Identified**: 2026-07-19 · the workout-generator persona sweep (`PlanGenerator.generateV4`,
  18 personas × phases 1-3 = 54 plans, exported by
  `test/plan_generator/persona_matrix_export.dart` in the `persona-sweep-e2e` worktree). The
  sweep's `.xlsx` + commentary were test artifacts and have been deleted as regenerable; this
  entry is the durable record of the one finding inside them that was never filed.
- **Risk class**: plan-engine correctness / user-facing safety-of-expectation
- **What's wrong**: the **bodyweight** persona's generated plan contained **5 picks out of 28 that
  require gym equipment** — Close-Grip Bench Press (barbell + bench), Barbell Curl (×2 slots),
  Standing Calf Raise (barbell), Chin Up (pull-up bar). A genuine no-equipment user opens the app
  and is prescribed exercises they physically cannot perform.
- **Root cause (verified in code, not taken from the sweep's prose)**: `queryV4`'s cascade DROPS
  the `equipment_tier` constraint at **attempt 4** when a muscle slot's on-tier pool is too
  shallow. `lib/shared/repositories/plan_engine/CLAUDE.md:274` lists it plainly —
  `4. attempt4DropEquipment — drop equipment_tier` — and
  `lib/shared/repositories/plan_engine/exercise_selector.dart:660` calls it "the soft tier
  heuristic the cascade itself RELAXES at attempt-4". So the tier is a preference, not a floor,
  BY DESIGN. Contrast the equipment **exclusions** filter, which the same cascade deliberately
  KEEPS at attempt-4 because "an excluded item is a HARD constraint, unlike the soft tier
  heuristic att4 relaxes" (`CLAUDE.md:279`).
- **The mitigation is weaker than the sweep commentary claimed** — worth stating because it
  changes the severity. The commentary described the ⑥ equipment-exclusions feature as
  "(now flag-on)". The code says otherwise: `PlanEngineFlags.equipmentExclusionsEnabled`
  (`lib/shared/repositories/plan_engine/plan_engine_flags.dart:145-153`) reads
  `configBox['enable_equipment_exclusions']` and returns **false** when absent — ship-dark,
  DEFAULT OFF. ~~So protection today requires BOTH (a) that flag switched on AND (b) the user
  actively subtracting "barbell"/"bench"/etc. in the Customize screen.~~ **[(a) NO LONGER
  APPLIES — see the 2026-08-05 update below; and the `:145-153` line range above is stale, the
  getter is now at `plan_engine_flags.dart:169`.]** A bodyweight user who
  never opens Customize gets no protection at all. I could not observe production config from
  the repo, so the discrepancy is recorded rather than resolved — resolve it before sizing the

  > ⚠ **UPDATED 2026-08-05 — condition (a) is now SATISFIED (diagnose `e2d6b8`).** The flag was
  > flipped ON in the `deps-board-equipment` batch; the gate is now the
  > `disable_equipment_exclusions` kill-switch, default ON, so the paragraph above is accurate
  > only as a description of the world before that flip. **Condition (b) still holds and is now
  > the whole of OI-89**: a user who never opens the Customize screen sets no exclusions, so a
  > "bodyweight" user can still be served gym exercises via the SOFT equipment-TIER heuristic.
  > The flip made the item-level EXCLUSION a hard constraint; it did NOT make the tier a hard
  > constraint, and that distinction is precisely what this issue is about. Severity is unchanged
  > for the never-opened-Customize user; it drops to zero for anyone who does set exclusions.
  fix.
- **Product question (this is the real blocker)**: should each equipment tier enforce a **hard
  floor** — never surface a pick whose required equipment the tier cannot provide, falling back
  to a bodyweight substitute or a safe omission — rather than leaking a barbell lift? Today the
  answer is "only if the user manually excludes it, and only if the flag is on."
- **Fix shape (not yet attempted, and NOT to be started before the product call)**: make the
  tier a hard constraint at attempt-4 for the bodyweight tier specifically (the narrowest
  version), with the per-pattern bodyweight floor already used by attempt-5's universal pool
  providing the substitute so a slot is never empty. Needs a behavioral test asserting a
  bodyweight persona's full plan contains zero picks whose `equipment_needed` falls outside the
  tier.
- **Blast radius estimate**: `account` (plan engine, `lib/shared/repositories/plan_engine/**`);
  no migration, no schema. Rule 14 applies — `plan_generator.dart` is not to be modified without
  explicit instruction.

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

## OI-91 — 138 dead `CLAUDE.md §N` citations remain in live code/test/script comments (P3)

- **Status**: CLOSED · 2026-08-07 · branch `oi91-claude-md-citations`, diagnose `b2f7a4`,
  ledger `docs/audit/oi91_claude_md_citations.closure.yaml` (5/5 terminal). All 138 swept
  (survey command now returns 0), **plus 11 wrong-but-live** that this entry recorded as
  unmeasured. Gate 26 extended to a code zone over `.dart`/`.ts`/`.js`/`.sql`/`.sh` and flipped
  to hard-fail, so the class cannot regrow.
  **Three corrections to what this entry said**, recorded rather than quietly fixed:
  1. **The mapping did not need building.** `docs/superpowers/plans/2026-05-18-claude-md-declutter-plan.md`
     Tasks 2.5–2.13 already record the destination for **all 10** dead section numbers; the
     "fix shape" below proposed reconstructing it and covered 4.
  2. **The §19 destination was wrong.** Pointing §19 at `docs/playbook/common-pitfalls.md` would
     have minted 10 fresh broken pointers — only 1 of the 5 quoted entry titles is in that file.
     `2026-05-18-claude-md-declutter-audit.md` shows the Class A/B entries were *deleted because a
     test became their record*, and in 5 cases that test is the very file carrying the citation.
  3. **Blast radius measured `catastrophic`, not `feature`.** Not the migrations — two comment
     lines in `supabase/functions/razorpay-webhook/index.ts`, which `docs/blast_radius.yaml:41`
     maps to catastrophic, and `blast_radius_from_diff.dart` has no comment-only carve-out. The
     three edited migration files carry no `security definer` text so they stay `platform`.
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-07 (count re-derived by the entry's own command → 0; gate
  negative-controlled by execution in both directions). Originally 2026-08-05 at filing time.
- **Identified**: 2026-08-05 · the B-pass on `repo-gate-pattern-sweep` (diagnose e7c3b9), which
  caught that that batch's own completeness grep had an input set of 3 directories while its
  artifacts stated the conclusion unscoped.
- **Risk class**: documentation rot / broken agent navigation
- **What's wrong**: root `CLAUDE.md`'s real `##` headings are exactly `0,1,2,2a,3,4,5,6,7`. Every
  citation of any other section number is a dead pointer. e7c3b9 swept and fixed the
  **prescriptive doc/skill zones** (`.claude/**`, `docs/naming_conventions.md`,
  `docs/audit/AUDIT_PLAYBOOK.md` + `LENS_REGISTRY.md`, `docs/playbook/**`) — 20 sites. It did
  **not** touch in-code comments, where 138 remain:

  ```
  grep -rnoE 'CLAUDE\.md.{0,3}§[0-9]+[a-z]?(\.[0-9]+)?' lib/ test/ scripts/ supabase/ integration_test/ \
    | grep -vE '§(0|1|2|2a|3|4|5|6|7)\b' | wc -l      # -> 138
  ```

  Concentrated in `§15` (the old "Source of Truth Rules", now `docs/architecture/sync.md` +
  `docs/sot_registry.yaml`), `§14`, `§11`, `§19`. Examples:
  `lib/core/constants/app_constants.dart:68` (`§14`),
  `lib/core/services/health_write_service.dart:43` (`§15`),
  `lib/core/services/nutrition_read_service.dart:16` (`§15`).
- **Why no gate catches it**: Gate 26 (`scripts/check_claude_md_citations.dart`) walks only root
  `CLAUDE.md`, `AGENTS.md`, `lib/**/CLAUDE.md` and `supabase/**/CLAUDE.md` — i.e. markdown
  contract files, never `.dart` source comments.
- **Two sub-classes, and the second is the dangerous one:**
  1. **Dead** — the cited section does not exist. Fails loudly the moment someone looks.
  2. **Wrong-but-live** — the cited section exists but is the wrong one, so it reads as correct
     and a grep-based sweep filtered on "outside §0-§7" is structurally blind to it. e7c3b9 found
     two by reading rather than grepping (`naming_conventions.md:293` cited "§6 — Coding rules"
     when §6 is MULTI-TIER COVERAGE and the rules are §4.4; `path-mappings.md:21` pointed
     "Discipline / process" at §3 = SCREENS instead of §4). **The 138 above have NOT been checked
     for this class** — that filter cannot see it, so the real number is ≥138.
- **Fix shape (AS SHIPPED — the original proposal is kept below it for the record)**: the
  authoritative old-section → new-home mapping was **already written** in
  `docs/superpowers/plans/2026-05-18-claude-md-declutter-plan.md` (Tasks 2.5–2.13), covering all
  10 numbers. Applied it; handled §19 per the per-entry classes in the sibling
  `2026-05-18-claude-md-declutter-audit.md`; read every remaining live citation for the
  wrong-but-live class (found 11); extended Gate 26 to a code zone and flipped it to hard-fail.

  *Original proposal, which under-scoped the mapping and mis-routed §19:* "build the
  old-section → new-home mapping once (§15 → `docs/architecture/sync.md`/`docs/sot_registry.yaml`,
  §11 → `docs/architecture/ai.md`, §19 → `docs/playbook/common-pitfalls.md`, §9 →
  `lib/shared/widgets/wardroom/CLAUDE.md`, …), apply it, then read every remaining live `§N`
  citation for the wrong-but-live class rather than trusting the filter. Consider extending
  Gate 26 to scan `.dart` comments so this cannot silently regrow — that is the only version of
  this fix that stays fixed." The last sentence was right and is what shipped.
- **Blast radius estimate**: was `feature`; **measured `catastrophic`** — see the Status block.
- **Root cause worth carrying forward**: the declutter **renumbered** rather than only relocated.
  Old §4 = DATA ARCHITECTURE, §5 = DIRECTORY STRUCTURE, §6 = **the coding rules 1-23**,
  §7 = **DATABASE SCHEMA**; those four numbers now hold entirely different content. So any
  pre-2026-05-18 citation of §4–§7 is suspect on sight, and no grep filtered on "outside the live
  range" can see it. That is why sub-class 2 needed reading, not grepping.

## OI-92 — `_git_lock.sh` reclaim: a failed restore destroys the lock it stole, letting two processes hold the mutex (P1)

- **Status**: CLOSED · 2026-08-05 · the automatic reclaim was DELETED, not patched a fifth time.
  The founder ratified the recommended fix below on 2026-08-05. Shipped on branch
  `discipline-tooling-hardening`: `_RECLAIM_MIN_AGE_SECONDS`, the age gate and the
  steal-verify-restore block are gone; a dead-holder lock is REFUSED with the manual `rm -rf`
  printed. The claim path (atomic `mv -T` publish) is untouched — it was never the defective part.
  The stale-lock test was INVERTED rather than deleted and asserts
  `isNot(contains('Reclaiming stale lock'))`, so re-adding a takeover path now fails a test;
  negative-controlled by execution. Diagnose `c9f4e1` (Round-4 section);
  record `docs/plan-reviews/discipline-tooling-hardening.md`.
  **Found while fixing:** the trap handlers cleaned up but did not terminate, so a Ctrl-C released
  the lock and let the wrapper carry on WITHOUT it — pre-existing for INT/TERM, fixed here with
  its own regression test (see the B-pass doc).
- **Blocked on**: nothing — closed.
- **Verified**: 2026-08-05 (round-4 review of the unshipped `discipline-tooling-hardening` branch;
  the `mv -T` failure mode reproduced by direct execution on this exact Git-Bash/MSYS2 toolchain,
  not by reasoning)
- **Identified**: 2026-08-05 · round-4 review of Unit 3a, `scripts/_git_lock.sh` (UNSHIPPED — the
  branch is not merged, so this is not a live defect on `main`; it is the reason 3a+3c did not
  ship).
- **Risk class**: check-then-act / mutual-exclusion. **Fourth occurrence of the identical shape in
  the same file** — round 1 found it in release, round 2 in claim, round 3 in the reclaim's
  decide-then-act, and this is round 4 in the reclaim's restore-then-delete.

### What's wrong

`scripts/_git_lock.sh:288-289` (unshipped branch):

```sh
mv -T "$graveyard" "$lock_path" 2>/dev/null
rm -rf "$graveyard" 2>/dev/null
```

The `rm -rf` is unconditional, but `mv -T` **fails** when the destination exists and is non-empty
— which is precisely the semantic the *claim* side of this same file depends on. Verified by
execution: with a populated `lock_path`, `mv -T graveyard lock_path` exits 1, `graveyard` survives,
and the following `rm -rf` then deletes it.

Sequence (no injected delay needed):

1. Lock holds dead holder `D`, old enough to clear the age gate.
2. Process **A** reads it, decides stale.
3. Process **B** reads the same, reclaims, publishes its own lock. B legitimately holds it.
4. **A** steals — and the file's own comment concedes `mv -T` is "a blind move keyed on the
   DESTINATION's existence, not the SOURCE's content", so A steals **B's live lock**.
5. The path is momentarily empty; **C** publishes there.
6. A's verify correctly notices it stole the wrong thing (`stolen_pid=B` ≠ `holder_pid=D`) and
   enters the restore branch.
7. `mv -T "$graveyard" "$lock_path"` **fails** — C occupies the path.
8. `rm -rf "$graveyard"` runs anyway → **B's lock is destroyed**.
9. B still believes it holds the mutex; C believes it holds the mutex. **Both proceed** — the exact
   condition the file exists to prevent.

### Why the existing comment does not cover this

The code *does* name the window ("a THIRD process claiming the momentarily-emptied path in the
exact window between this steal and its restore") but dismisses it on the wrong grounds: it argues
that process's own `git_lock_release` "would correctly detect it no longer owns `$lock_path` and
refuse to touch it". That is true and irrelevant — nothing gets *destroyed* by C, but B and C hold
the mutex **simultaneously**, which the note never addresses.

The window is also wider than the file's own standard for "realistically reproducible". The age
gate is justified by the claim that "there is no natural multi-second gap anywhere in this file's
own logic … no subprocess-spawn-class delay". But the steal→restore window contains a `sed`
subprocess plus two `echo`s, and this file's header measures a subprocess spawn at **61–89 ms** on
this stack — the same class it says made the round-2 bug reproducible without injection.

### Recommended fix — remove the reclaim, do not add a fourth layer

`flock` is **not available** on this Git-Bash/MSYS2 stack (checked), so kernel-enforced locking is
not an option. With only `mkdir` / `mv -T` / `kill -0`, an atomic "remove the stale lock AND
install mine" does not exist: a directory target makes `mv -T` fail-if-present (right for claiming,
useless for replacing), and a file target makes it replace unconditionally (right for replacing,
useless for claiming).

So delete the automatic reclaim outright — the age gate and the steal-verify-restore block, ~50
lines — and always refuse, printing the manual `rm -rf "$lock_path"` command the file already
emits. The claim path (`mv -T` publish of a fully-populated private candidate) is sound and
independently verified under 5-way contention; it is only the *reclaim* that has now failed review
four times.

Cost: a holder killed without its EXIT trap firing (SIGKILL, power loss) leaves a lock needing one
manual `rm -rf`, with the command already on screen. That is a cheap price for removing an entire
bug family, and it matches the failure direction the file already commits to for the PID-reuse
case — "wait / manual `rm -rf`, never silently proceed concurrently".

- **Blast radius estimate**: `platform` (`scripts/_git_lock.sh` is promoted to platform by the
  unshipped branch's own `docs/blast_radius.yaml` entry, alongside `safe_commit.sh` /
  `safe_push.sh`); no migration, no schema. Not live on `main`.

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

## OI-98 — notification preferences are push-only: a reinstall overwrites the server's copy with all-enabled (P2)

- **Status**: OPEN
- **Blocked on**: nothing technical. The mechanism is understood and read from code; what is NOT
  established is the exact ordering on a real reinstall (see the caveat below), and that should be
  confirmed before designing the fix.
- **Verified**: 2026-08-07 — by grep across `lib/core/services/` and `lib/features/auth/`, while
  writing OI-75's SoT registry entry. Gate 11 (`check_sync_fanout.dart`) is what forced the
  question: it demanded a `restore_methods:` list and there was nothing truthful to put in it.
- **Identified**: 2026-08-07 · Unit 1 (branch `claude/work-session-3rqcp5`).
- **Risk class**: restore-completeness — the class `docs/architecture/sync.md` exists to prevent.
- **What's wrong**: `notification_preferences` travels UPWARD only.
  - Written into the daily snapshot at `sync_service.dart:842`
    (`'notification_preferences': NotificationPrefsRepository.emissionMap()`), pushed by
    `pushSnapshotNow` (`:870`).
  - **Nothing ever reads it back.** The only read of `snapshot_json` is `:1763-1776`, and it
    selects `fitness_summary` specifically. `grep -rn notification_preferences lib/core/services/
    lib/features/auth/` returns exactly three hits: the emission above, a key name in
    `user_config_migrator.dart:217`, and a comment in `auth_provider.dart:621`. No restore path
    writes the key back to `userBox`.
- **Why this is worse than "prefs don't restore"**: it is not a silent loss, it is an active
  overwrite. On a reinstall `userBox` is empty, so `read()` returns `{}`, so `emissionMap()` emits
  **every key with `{'enabled': true}`** (its documented default — an untouched key emits enabled).
  That map is then pushed and **replaces the server's stored preferences**. A user who had turned
  three notifications off gets all ten back on, and the record of their choice is destroyed rather
  than merely unread. The ABSENT ⇒ SEND rule makes the failure direction "send more", never "send
  less", so nobody complains about silence — they just start receiving notifications they had
  switched off.
- **⚠ Caveat, stated so this is not over-claimed**: the mechanism above is read from code. The exact
  ORDERING on a real reinstall — whether any restore repopulates `userBox` before the first
  `pushSnapshotNow`, and whether the first push happens before or after the user reaches the
  Notifications screen — was NOT traced. Confirm that before designing the fix; if some restore
  path does repopulate the box first, the impact is smaller than described (though the missing
  read-back is still a gap).
- **Fix shape (not attempted)**: give the concept a real restore leg — read
  `snapshot_json->notification_preferences` in the restore path and write it back through
  `NotificationPrefsRepository.write` before the first push. Alternatively, make the emission
  distinguish "user has never set this" from "user set it to enabled", so a fresh install cannot
  masquerade as an explicit all-enabled choice. The second is the more durable fix and is a schema
  question, not just a client one.
- **Related**: OI-75 (its registry entry records `restore_methods: []` with this as the reason);
  OI-80 (the `notification_preferences` reader citations in `snapshot_contract.yaml` are recorded
  as unvalidated).
- **Blast radius estimate**: `account` — touches the sync restore path; no migration, no schema
  change for the first fix shape.

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

## OI-112 — OI numbering collides across concurrent sessions; the LANDING half is now gated, the MINT-TIME half is not

- **Status**: OPEN
- **Blocked on**: nothing — the remaining half is a cross-branch check, and where it runs is still the open decision below
- **Verified**: 2026-08-13 (a FOURTH and largest collision: six ids at once — see "Partially closed").
  The third hit a DIFFERENT session in parallel and is recorded at
  `docs/plan-reviews/claude-commit-merge-push-process-aae061.md:56-58` — "renumbered to OI-106 at
  merge time, an unrelated batch landed its own OI-105 on `main` first". Two sessions hit this
  class independently within a day, neither aware of the other. The "Measured" bullet below
  enumerates only the first two, which are the ones on THIS branch.
- **Partially closed 2026-08-13**: `scripts/build_oi_index.dart` now **fails closed on duplicate
  ids within the board** (`duplicateIds()`), so a corrupt board can no longer render and cannot
  LAND — the merge commit regenerates the index and the gate fires. What this does NOT do is warn
  at **mint time**: two sessions on two branches each picking "the next free number" still both
  validate clean in isolation, because each board is individually duplicate-free. That is the half
  OI-112's fix-shape below addresses, and it remains open.
  Evidence it detects: planting a second `## OI-111` made the generator exit 1 naming the id.
  Mutation-proven — rebuilding the check over `parseOpenIssues` (which drops CLOSED entries)
  reddens exactly the OPEN-vs-CLOSED test; neutering it reddens 4.
  Tests: `test/contracts/oi_index_test.dart` (group "OI-112 scar").
- **Identified**: 2026-08-09 · B-pass Finding 4 on `d4a8de00`
- **Risk class**: cross-session process drift — silent, and both sides validate clean
- **What's wrong**: §4.13 worktrees isolate the git INDEX; they do NOT isolate the shared
  `## OI-NN` numbering NAMESPACE in `docs/audit/open_issues.md`. Two sessions filing issues
  concurrently both pick "the next free number" against *their own* base and both are correct in
  isolation. Nothing — not the OI index generator, not Gate 40, not the merge — compares the two.
- **Measured**: 2026-08-08 mine claimed OI-96/97/98, already taken on `origin/main`; renumbered to
  99/100/101. Within hours `origin/main` advanced again (`c90fc4c0`) with its own OI-99, so mine
  moved to 100/101/102. **Two collisions, one day, same branch.** The manual renumber is a patch,
  not a fix — it goes stale the moment another session lands.
- **Why it matters beyond tidiness**: an OI number is a citation target. Diagnose-docs, closure
  YAMLs and commit messages all cite `OI-NN`. A collision silently repoints someone else's
  citation at your issue.
- **Fix shape**: `scripts/check_oi_numbering_unique.dart` — parse `## OI-(\d+)` from HEAD and from
  `origin/main`, fail when the same number carries a different title. **Open decision:** a
  pre-commit gate would read a possibly-stale local `origin/main` ref (fails safe, but weakly);
  CI is authoritative but only catches it after the push. Probably both, with CI as the real gate.
  A cheaper complement: allocate from a high, per-session-reserved block instead of "next free".
- **Blast radius estimate**: `feature` (a script plus wiring).

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

## OI-102 — local `test/contracts/` takes 18.6 min on every commit, and the lever is not yet known (P2)

- **Status**: CLOSED · 2026-08-11 · ADR-0018 removed the trigger: `pre-commit.sh` no longer runs
  `flutter test test/contracts/` at all, so the 18.6 min is no longer paid per commit. **The
  measurement question this was blocked on is NOT answered** — it is carried forward as OI-106
  rather than closed with it. Closing on "the symptom is gone" while the open question dies
  quietly would be the deferral §4.2 bans; the successor entry is what makes this terminal.
- **Blocked on**: nothing — closed. (Was: a clean measurement. That now blocks OI-106.)
- **Verified**: 2026-08-11 — full JSON-reporter run, `{"success":true,"type":"done","time":1114598}`.
- **Identified**: 2026-08-11.
- **Risk class**: developer-cycle-time; secondarily `--no-verify` pressure (the original I10 motive).
- **What's wrong**: `pre-commit.sh:66` runs `flutter test test/contracts/` — **477 files, 18.6 min,
  on every commit**. The I10 fast/full split (2026-05-21) sized this at ~3 min when `test/contracts/`
  held **179** files; it now holds 477, i.e. ~69% of the whole 694-file suite. The "fast path" has
  eroded into most of the suite.
- **What has ALREADY been ruled out — do not re-derive**:
  - *Optimising the slow files*: distribution is flat. Top 10 files = **8.4%**, top 25 = 15.5%,
    top 200 = 59.7%. Reaching ~5 min needs a 73% cut; no subset optimisation gets there.
  - *`flutter test` → `dart test` migration*: measured **~18%** against a ≥50% bar set in advance
    (warm marginal cost 0.83s vs 0.33s/file; fixed 9.2s vs 3.7s). 447 of 477 files import
    `flutter_test` while only 8 use `testWidgets`, so the migration is broadly *possible* — it just
    does not carry the problem. **Zero prior art in the repo**; the one untouched idea here.
  - *`--concurrency` (16 cores, default is cores/2 = 8)*: **UNPROVEN, and the obvious measurement is
    a trap.** j8-cold 191s → j16-warm 91s looks like 2.1×, but the control refutes it: j8-**warm**
    90s, j16-**warm** 170s. Runs alternate ~90s/~170s with no relationship to the flag.
  - *A "37% fixed per-file startup" figure*: **wrong** — inferred from a 6.8s minimum span, but
    spans are measured under 8-way contention and include queueing (sum-of-spans 8777s ≫ wall 1114.6s).
  - *Diff-conditional test selection*: rejected in `docs/adr/0013-blast-radius-tiered-gating.md:52-67`
    alt #3. 93 contract tests read `docs/` and 265 reference `lib/`, so the dependency graph is broad.
- **Fix shape (measurement first, no predetermined outcome)**: on a QUIET machine (no subagents —
  contamination is why the above is unproven), use **counterbalanced blocks** (`j8×3, j16×3, j16×3,
  j8×3`) or randomised order, n≥5 per arm, reporting the paired distribution. **Alternating
  j8/j16 is the single worst design here** — it is perfectly aliased with the observed period-2
  oscillation. Identify the oscillator BEFORE assigning a 1.9× swing to either arm. Also unexplained
  and probably the real lead: **CI runs 690 files in 417s while local runs 478 in 1114.6s** — ~3.9×
  slower per file locally at ~4× the parallelism.
- **Interaction**: OI-86 (concurrent `flutter test` runs corrupt each other's Hive state) is the
  named hazard for any concurrency increase; 112 contract files use Hive. It is intermittent, so
  "twice consecutively green" does NOT clear it.
- **Blast radius estimate**: `platform` (`scripts/pre-commit.sh` is `docs/blast_radius.yaml:101`).

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

## OI-105 — the `Supabase Integration Tests` CI job has verified NOTHING since it was written: the repo has zero Actions secrets (P2)

- **Status**: OPEN
- **Blocked on**: **founder — this is not an agent-actionable item.** Adding an Actions secret
  requires repo-settings access; an agent can neither read nor write them. Nothing else blocks it.
- **Verified**: 2026-08-11 — queried the authoritative source, not inferred from behaviour:
  `gh api repos/upendraprasad19/AVYA/actions/secrets` → `{"total_count":0,"secrets":[]}`. Checked
  the RAW response deliberately, because an empty `--jq` result and a swallowed auth error are
  indistinguishable at the shell (`feedback_green_check_input_set_width`).
- **Identified**: 2026-08-11 · carried out of the gate-registry/CI-speedup batch, where it was
  recorded only as a "founder-only owed" line in a memory index. Filed as a real OI once the §5
  rule change made clear that a residual living only in agent memory is not tracked at all
  (`feedback_spawn_task_chip_not_durable`, same class).
- **Risk class**: silent-inert-gate / false assurance — a green job that proves nothing, which is
  strictly worse than an absent job because it occupies the slot where real assurance would go.
- **What's wrong**: `.github/workflows/test.yml:334` defines `supabase-tests`, gated
  `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`. Its two real steps
  (`:363` Run Supabase tests, `:371` Run Edge Function tests) each carry
  `if: env.SUPABASE_URL != ''`. With no secret configured, **both steps skip and the job reports
  success.** The `ci-speedup` batch (2026-08-10) added an honest announce step at `:344-350` that
  emits `::warning title=Supabase integration tests did not run::… this job verifies NOTHING. It
  is green because there is nothing to fail, not because integration tests passed.` — so the
  condition is *disclosed*, but disclosure is not coverage, and a `::warning::` on a green run is
  read by nobody.
- **What is actually uncovered** — 6 test files, and the selection is not incidental; it is
  precisely the surface with the worst P0 history in this repo:
  `test/edge_functions/webhook_test.dart` (Razorpay — see the TDZ webhook P0 in
  `closed_issues.md:708`), `redeem_referral_test.dart`, `ai_proxy_test.dart`, `pgvector_test.dart`,
  `test/supabase/auth_restore_test.dart`, `sync_service_test.dart`.
- **Fix shape (founder action, then a verification step that is NOT optional)**:
  1. Add `SUPABASE_URL` + `SUPABASE_ANON_KEY` as repository Actions secrets. Use the **fitness-app**
     project `dedsavbjuwgarrhphgnl` (CLAUDE.md §2a — there are two Supabase projects on the account
     and the other one is a different app entirely). Anon key only; never the service-role key.
  2. **Expect the job to go RED on first real run and treat that as the point, not a regression.**
     These 6 files have never executed in CI. Budget for triage rather than assuming green.
  3. Once green, the `::warning::` at `:344-350` stops firing — that is the observable confirmation
     the job began verifying something, and it is the cheapest available proof.
- **Do NOT "fix" this by deleting the job.** That trades a disclosed gap for a silent one. The
  announce step is the current mitigation and should stay until the secrets land.
- **Blast radius estimate**: `platform` (`.github/workflows/test.yml` is `docs/blast_radius.yaml:184`)
  IF the workflow is edited; adding secrets alone touches no tracked file and has no blast radius.
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

## OI-115 — cleanup() can DELETE from 12 PROD tables and its guard cannot refuse the scenario it was written for (P1)

- **Status**: CLOSED (2026-08-15, `acffbd43` + `e4121c14`)
- **Resolution**: boundary re-keyed on a `const Set` of QA **uuids**
  (`assertDisposableTarget`), which does not move when the credential moves — the defect
  this entry documents. Applied at all THREE delete sites incl. the two in
  `pgvector_test.dart` that bypass `cleanup()`, AND at `ai_proxy_test.dart`'s WRITE path
  (bullet 2, "same boundary question"). Bullet 3 (LateInitializationError masking) fixed
  via `setUpSucceeded`. Mirror-tested: the guard runs BEFORE any delete, proven by moving
  it after the loop and watching only that assertion redden.
- **Blocked on**: nothing — the work is understood and scoped; it needs a design decision
  between a uuid allow-list and a runtime self-check, then implementation.
- **Verified**: 2026-08-13 — round-2 context-blind review, reproduced by direct read of
  `test/supabase/supabase_test_helper.dart:30,148,198` on branch `supabase-ci-http-mock`.
- **Identified**: 2026-08-13 (split out of diagnose 3b7e1c per §4.12.1).
- **Risk class**: production data loss. Bounded TODAY only because `qa@icanbefitter.com` does
  not exist, so sign-in fails and `cleanup()` early-returns on a null `_userId`.
- **What's wrong**: `SupabaseTestHelper.cleanup()` issues `DELETE` across 12 tables of the
  production project (`dedsavbjuwgarrhphgnl`) and CI runs it on every push to `main`. A guard
  was written (branch `supabase-ci-http-mock`, commits `29e8484e` + `a2f50316`) but it compares
  the signed-in email against `disposableTestEmail` — the SAME constant `signIn()` uses via
  `testEmail = disposableTestEmail`. **Both sides move together**, so the scenario the guard's
  own doc comment names — "repoint the constant at an account that DOES exist, because sign-in
  fails" — passes straight through. Real accounts at risk: `test2@gmail.com` … `test7@gmail.com`
  (test7 holds 133 `memory_embeddings` rows, verified by read-only SELECT).
  A pin test detects a repoint but runs in the SAME `flutter test test/supabase/` invocation as
  the file issuing the deletes, alphabetically after it — detection no earlier than the damage.
- **Also in scope, same file family**:
  - `test/edge_functions/pgvector_test.dart` deletes from `memory_embeddings` in setUp and
    tearDownAll; its guard has the same aliasing weakness and cannot fire.
  - `ai_proxy_test.dart` writes `ai_coach_interactions` and burns the signed-in user's daily
    quota — not a DELETE, same boundary question.
  - The guard's `tearDownAll` path throws `LateInitializationError` when `setUpAll` failed
    (which it does today), adding noise to the first-real-run triage OI-105 budgeted for.
- **Fix shape (not attempted)**: make the boundary independent of the sign-in identity — either
  an allow-list of QA **uuids** checked against `targetId`, or a runtime self-check inside
  `assertDisposableTarget` validating the constant's own value, so a repoint fails in the same
  call rather than in another file's test. Prefer the uuid list: an email is a mutable label, a
  uuid is the thing rows are actually keyed by.
- **Where the work is**: branch `supabase-ci-http-mock` (commits `29e8484e`, `a2f50316`) — a
  guard, its tests, and 3 mutation proofs already exist and are worth keeping; the boundary
  design is what needs redoing. Round-2 review findings are the spec.
- **Blast radius estimate**: `feature` for the helper alone; `platform` if the fix also moves the
  QA password to a secret (that requires editing `.github/workflows/test.yml`).

## OI-116 — the QA password is committed to git, and creating the account would put it on prod (P2)

- **Status**: CLOSED (2026-08-15, `e4121c14`)
- **Resolution — SUPERSEDED in part**: all four credential sites now read
  `String.fromEnvironment`; `git grep` for both literals is empty outside dated records;
  `hasCredentials` widened 2→4 inputs; `auth_helper` gained the skip-gate it never had;
  `.env.example` + `DEVICE_TESTING.md` document the keys. The entry also asked for
  `qa@icanbefitter.com` to be created — it was NOT; a different account was used instead.
- **Blocked on**: founder — creating `qa@icanbefitter.com` and adding a `SUPABASE_TEST_PASSWORD`
  Actions secret are account/settings actions an agent cannot perform.
- **Verified**: 2026-08-13 — `git grep QA_Test_2024` across the whole worktree.
- **Identified**: 2026-08-13 (split out of diagnose 3b7e1c per §4.12.1).
- **Risk class**: credential exposure. Not yet realised — the account does not exist, so the
  password currently unlocks nothing.
- **What's wrong**: `QA_Test_2024!` is a literal in `test/supabase/supabase_test_helper.dart`,
  `test/edge_functions/{ai_proxy,pgvector}_test.dart` and
  `integration_test/helpers/auth_helper.dart`, plus `supabase/seed_qa.sql`,
  `integration_test/app_test.dart` and `testing/e2e/*.md`. Creating the account with it would put
  a login on the PRODUCTION project whose password anyone with repo access can read. It is in git
  history regardless, so the account must be created with a NEW password whatever else happens.
- **What has ALREADY been done — do not re-derive** (branch `supabase-ci-http-mock`, `29e8484e` +
  `a2f50316`): all four live uses converted to `String.fromEnvironment('SUPABASE_TEST_PASSWORD')`;
  `hasCredentials` widened to three inputs with a pure `credentialsComplete()` predicate so it is
  mutation-testable; `test.yml` given the env var and quoted `--dart-define`s on both steps; the
  announce step widened to name all three missing secrets.
- **What round 2 found still wrong there**: `integration_test/helpers/auth_helper.dart` has NO
  skip-gate, so device/integration runs would attempt sign-in with an EMPTY password instead of
  skipping — fixing a security issue created a functional one. `SUPABASE_TEST_PASSWORD` is absent
  from `.env.example` and `docs/operations/DEVICE_TESTING.md`, and `scripts/run-device-tests.sh`
  passes only `--dart-define-from-file=.env`. `testing/e2e/01_auth_onboarding.md:15,93` still
  publishes the literal. The `hasCredentials` delegation test is tautological once all three
  secrets exist.
- **Fix shape**: finish the above, then founder creates the account with a NEW password and adds
  the secret. Only then can the `supabase-tests` job go green — and per OI-105 expect the first
  real run to surface genuine failures.
- **Blast radius estimate**: `platform` (`.github/workflows/test.yml`).
## OI-121 — the QA fixture account `qa@icanbefitter.com` does not exist, so `test/supabase/` cannot pass (P1)

- **Status**: CLOSED (2026-08-15, `e4121c14`)
- **Resolution — SUPERSEDED, not satisfied**: this entry is worded around CREATING
  `qa@icanbefitter.com`. That account was abandoned rather than created. The suites now
  sign in as `test6@gmail.com` via the `SUPABASE_TEST_EMAIL` / `SUPABASE_TEST_PASSWORD`
  secrets, so the stated blocker no longer exists — but nobody ever created the account
  this entry asks for, and saying "done" without that distinction would be false.
- **Blocked on**: FOUNDER — genuinely not agent-actionable. Creating an account (or setting its
  password) is a prohibited action for the agent, and it must be done against the live prod project.
- **Verified**: 2026-08-12 — queried the authoritative source, not inferred from the error:
  `select email, created_at from auth.users where email = 'qa@icanbefitter.com'` on
  `dedsavbjuwgarrhphgnl` returned **zero rows**.
- **Identified**: 2026-08-12, while fixing `a7e3c1` (the HTTP-mock bug that was hiding this one).
- **Risk class**: CI correctness. `main` is RED until this is resolved.
- **What's wrong**: `test/supabase/supabase_test_helper.dart:21-22` signs in as
  `qa@icanbefitter.com` / `QA_Test_2024!`. That user is not in `auth.users`. Both integration test
  files die in `setUpAll`, so **zero assertions in either file have ever executed**. This was
  invisible until `a7e3c1` was fixed, because the `TestWidgetsFlutterBinding` HTTP mock was
  answering every request with a fabricated 400 before any of it reached Supabase.
- **How to confirm the fix worked**: after the account exists, the live error changes from
  `AuthApiException(... invalid_credentials)` to the tests actually running. Run locally first:
  `flutter test --dart-define-from-file=.env test/supabase/auth_restore_test.dart`.
- **⚠ Read before creating it — the tests WRITE to the live prod project.**
  `supabase_test_helper.dart:116-143` deletes rows for the signed-in user across 12 tables
  (`user_profile`, `user_preferences`, `workout_logs`, `nutrition_logs`, `weight_logs`, `streaks`,
  `user_progress`, `body_measurements`, `sleep_logs`, `ai_coach_interactions`, `memory_embeddings`,
  `user_daily_snapshots`) in `setUp` **and** `tearDownAll`. That is correct for a throwaway fixture
  account and catastrophic for a real one, so the account MUST be a dedicated QA user and MUST NOT
  be an address that is ever used as a real login. It also means every green CI run mutates prod
  data for that user — acceptable for a fixture, worth stating explicitly rather than discovering.
- **Options, since this is a real decision and not just a chore**:
  1. Create the QA user in the prod project and leave the job running against prod (what the code
     assumes today).
  2. Point the job at a separate Supabase project / branch so CI never writes to prod at all.
  3. Unset the two Actions secrets, which restores the skip and a green `main` — but that returns
     the job to verifying nothing, which is precisely what OI-105 was filed about. Listed for
     completeness, not recommended.
- **Blast radius estimate**: `account` (`test/supabase/**` plus, for option 2, `.github/workflows/test.yml`).

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

## OI-118 — CLOSED, NOT A REPO ISSUE: I read a 14-day-old orphan `/tmp` file and formatted the date out of my own evidence (P3)

- **Status**: CLOSED (`verified_clean` — there is no defect in the repo to fix)
- **Closed**: 2026-08-13, same day as filed, after THREE successive corrections.

> ⚠️ **This entry was WRONG THREE TIMES, each layer found by a different mechanism.** It is kept —
> not deleted — because a board entry describing a bug that does not exist is worse than no entry
> (the standard `docs/audit/oi-mechanism.closure.yaml` sets), and because the progression is the
> most useful thing here.
>
> | # | What I claimed | What is true | Found by |
> |---|---|---|---|
> | 1 | "`safe_commit.sh` logs to a fixed `/tmp` path" | `:43` is `mktemp` w/ `$$` fallback; `cat` to stdout at `:50`, `rm -f` at `:82`. The literal string appears **0** times in every version in its history. | the B-pass |
> | 2 | "concurrent sessions collide on that path" | Nobody collided. `/tmp/safe_commit_run.log` mtime is **2026-07-30 10:51** — an orphan abandoned 14 days before I read it. | me, following up on the B-pass |
> | 3 | "its timestamp looked recent enough to be current" | It looked recent because **my own command discarded the date**: `ls -l --time-style=+%H:%M:%S` prints time-of-day only, so `10:51:04` read as this morning. | me, re-running with `--full-time` |
>
> **The root cause is layer 3 and it is mine, not the repo's.** I chose a view that threw away the
> one field capable of refuting my conclusion, then drew the conclusion — `feedback_green_check_
> input_set_width` in its purest form, with the narrowing done by a display flag rather than a
> filter. Sibling instances that week were measurements killed by controls; this one needed no
> control, only the default `ls` output.

- **Blocked on**: nothing. Nothing to do.
- **Verified**: 2026-08-13 — `ls -l --full-time /tmp/safe_commit_run.log` → `2026-07-30 10:51:04`,
  against `date` → `2026-08-13`. And `grep -rn "safe_commit_run" scripts/` → 0 matches, so nothing
  in the repo writes it at all.
- **Why it is not merely downgraded**: every proposed fix across all three drafts (embed slug/pid;
  write inside the worktree `.git`; document a redirect convention) targets a collision that
  `mktemp` structurally prevents and that did not occur. There is no change to make.
- **What survives, and where it went**: the real hazard is reading an orphan file at a plausible
  path and assuming provenance. That is a working-practice lesson, not a backlog item, and belongs
  in the memory feedback file for the verification class — recorded there rather than left here as
  a phantom issue.
- **Terminal state**: `verified_clean`.

<!-- Original entry text retained below for the record. -->

> ⚠️ **This entry was filed with a FALSE diagnosis and corrected the same day by its own B-pass.**
> The original text claimed "`safe_commit.sh` logs to a fixed `/tmp` path". That is wrong.
> `scripts/safe_commit.sh:43` is `LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_commit_$$.log")"` —
> unique per invocation, with a PID-suffixed fallback — and `:50`/`:82` `cat` it to stdout then
> `rm -f` it. The literal string `safe_commit_run.log` appears **zero** times in that script in
> **every version in its history** (`git log -p --all -- scripts/safe_commit.sh | grep -c` → 0).
> The proposed fix (embed slug/pid in the filename) would have "fixed" a collision the code already
> prevents. **The script requires no change.** Correction retained rather than deleted, because the
> filing error is the more useful record — see Risk class.

- **Status**: OPEN
- **Blocked on**: nothing. It is a practice fix, not a code fix.
- **Verified**: 2026-08-13 (corrected). The OBSERVATION was real: reading `/tmp/safe_commit_run.log`
  for my own failing run returned a **different session's** commit (`e9683418`, branch
  `progress-map-consolidation`) with a plausibly-recent mtime. The CAUSE was not. Nothing in the
  repo writes that path — `grep -rn "safe_commit_run" scripts/` → 0 matches. It exists because
  agent sessions redirect `safe_commit.sh`'s stdout there ad hoc, and several independently chose
  the same obvious name.
- **Identified**: 2026-08-13.
- **Risk class**: misattribution, and the filing error demonstrates it better than the bug does. I
  read a file at a plausible path, assumed the tool wrote it, and filed a "Verified" board entry
  naming a mechanism I never checked against the source. That is
  `feedback_mistake_unverified_done_claims` — the most recurrent class in this repo — committed
  inside a batch whose own theme is signals that misreport. The near-miss was real: I began
  diagnosing 11 test failures from another branch's output and caught it only because the branch
  name at the bottom was not mine.
- **What's actually wrong**: nothing in the tooling. The hazard is a *convention* — any agent
  redirecting to a guessable shared `/tmp` name collides with every concurrent session, and the
  resulting file carries no owner marker.
- **Fix shape**: don't redirect to a hand-picked shared path. `safe_commit.sh` already `cat`s its
  log to stdout, so capture ITS output to a session-scoped file (the harness scratchpad dir) rather
  than inventing `/tmp/<toolname>_run.log`. Worth a line in the §4.3 wrapper docs.
- **Blast-radius estimate**: `feature` (documentation/practice; no script change).

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

## OI-119 — `git_safety_hook.dart` matches command TEXT, so it blocks commands that merely mention a banned form (P3)

- **Status**: OPEN
- **Blocked on**: nothing, but it needs a false-positive analysis before a fix — the hook is
  load-bearing and over-narrowing it would reopen the raw-push hole it exists to close.
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
