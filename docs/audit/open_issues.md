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
  `scripts/pre-commit.sh:169` and `.github/workflows/test.yml:171`; it runs only via
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

- **Status**: OPEN
- **Blocked on**: none
- **Verified**: 2026-08-01 (Unit 9) — `community_votes_summary` is absent from `pg_proc` in EVERY
  schema on `dedsavbjuwgarrhphgnl`, confirmed twice (once by me during the sweep, once
  independently by the round-1 reviewer).
- **Identified**: 2026-08-01, while waiving RPC reads for the OI-79 gate.
- **What's wrong**: `supabase/functions/promote-community-item/index.ts:128` and `:197` both call
  `.rpc("community_votes_summary")`. The function does not exist, so every call errors and the
  code proceeds down its fallback path — meaning the primary vote-summary path has never executed
  in production. The OI-79 gate waives these reads as "cannot truncate", which is true and
  irrelevant: they cannot return rows at all.
- **Why not fixed here**: determining the intent (create the missing RPC vs. delete the dead call
  and promote the fallback to primary) is a product/data decision about how community promotion is
  meant to rank items, not a paging fix.
- **Fix**: decide intent; if the fallback is correct, delete the dead RPC calls and their waivers
  so the gate stops reporting them as waived reads.

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
- **Verified**: 2026-08-03 (Unit A, diagnose `d1f6b3` — both refutations reproduced from code)
- **Identified**: 2026-08-03 · split out of OI-83 per §4.12.1 after two context-blind review
  rounds refuted two successive repair designs, the second as a data-loss risk.
- **Risk class**: stale local rows after a lost advance race (not a demotion — the counter is
  correct; the plan content is not)
- **What's wrong**: when `commitPhaseAdvance` DECLINES after `generateAndSchedule` has already
  run, the `schedule_*` rows and plan window written for the phase we did not advance to are
  left in place. Nothing rolls them back, so the user can read a plan for a phase they are not
  on. Now VISIBLE via `phase_advance_declined_rows_stale` (source, intended, live) — Unit A added
  the telemetry precisely so the frequency can be measured before more repair machinery is built.
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
- **Blocked on**: none for the ANALYSIS; the concrete instance below needs a plan-review record
  from the session that did the work — nobody else can honestly attest to a review they did not
  run.
- **Verified**: 2026-08-03 (reproduced by the blocked push described below; both worktrees and
  the missing file confirmed by direct inspection)
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

## OI-88 — `restoring_screen.dart` added to the Gate 43 allow-list; split owed (P3)

- **Status**: OPEN
- **Blocked on**: nobody yet — no session has picked up the split.
- **Verified**: never
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
- **Fix shape (not yet attempted)**: split into a sibling folder, reference layout
  `lib/features/train/screens/active_workout/` — candidates for extraction: the three key-migrator
  imports + `_healAfterRestoreInBackground`'s reconciler/migrator fan-out (currently inline), and/or
  the `_AnimatedDotsState` loading-indicator widget at the bottom of the file, which has no
  dependency on `_RestoringScreenState`'s fields and could move to its own widget file outright.
  **Remove the allow-list entry in the same commit.**
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
  DEFAULT OFF. So protection today requires BOTH (a) that flag switched on AND (b) the user
  actively subtracting "barbell"/"bench"/etc. in the Customize screen. A bodyweight user who
  never opens Customize gets no protection at all. I could not observe production config from
  the repo, so the discrepancy is recorded rather than resolved — resolve it before sizing the
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

- **Status**: OPEN
- **Blocked on**: nothing — mechanical, but large enough that it wants its own batch rather than
  riding along inside an unrelated fix.
- **Verified**: 2026-08-05 (count re-derived by grep at filing time; see the exact command below)
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
- **Fix shape (not yet attempted)**: build the old-section → new-home mapping once
  (§15 → `docs/architecture/sync.md`/`docs/sot_registry.yaml`, §11 → `docs/architecture/ai.md`,
  §19 → `docs/playbook/common-pitfalls.md`, §9 → `lib/shared/widgets/wardroom/CLAUDE.md`, …),
  apply it, then read every remaining live `§N` citation for the wrong-but-live class rather than
  trusting the filter. Consider extending Gate 26 to scan `.dart` comments so this cannot silently
  regrow — that is the only version of this fix that stays fixed.
- **Blast radius estimate**: `feature` (comments only, no logic); no migration, no schema.
