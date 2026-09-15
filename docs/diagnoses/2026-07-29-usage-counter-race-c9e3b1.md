---
bug_id: c9e3b1
date: 2026-07-29
batch: usage-counter-race
status: fixed
blast_radius: platform
symptom: >
  OI-45 named `UsageCounterService.increment()` (usage_counter_service.dart:100-106)
  as CRITICAL — "cross-device race could let users bypass daily caps... Pattern:
  final c = read(); write(c+1) with no atomicity" — carried forward unchanged
  across two prior re-verification passes (2026-07-26, 2026-07-29 oi-board-
  corrections) that both re-confirmed the CODE SHAPE but never tested the actual
  RUNTIME interleaving behavior that shape implies. Investigating this unit
  (sequenced deliberately after Unit 4, so the investigation could check which
  ai_coach_interactions-backed features already had a trigger backstop) found
  two things the CRITICAL rating had wrong: (1) a behavioral test firing two
  concurrent increment() calls via Future.wait against the UNMODIFIED pre-fix
  code still counted both — no lost update is actually reproducible, because
  MigratedKey.read is fully synchronous and Hive's Box.put() mutates its
  in-memory keystore synchronously before its own first internal await, so
  nothing can preempt a caller between its read and its write's in-memory
  landing under Dart's single-threaded event loop; (2) even setting aside (1),
  all three features this service gates now have an authoritative Postgres
  trigger backstop on ai_coach_interactions (ai-text-log: migration 026,
  pre-existing; scan_meal+cart_auditor combined: migration 111, landed
  same-day as this unit in Unit 4) — a lost or stale local counter can no
  longer let a request bypass the real cap. A third, unplanned finding
  surfaced while cross-referencing migration 111's exact cap value against
  the client's documented product limits: the combined scan_meal+cart_auditor
  server cap (15/day) undershoots the documented PRO promise (10 scan-meals/day
  + 10 cart-audits/day independently = 20 combined, docs/architecture/
  business-rules.md) — a compliant PRO user following the client's own
  displayed "remaining" counts could hit a live 429 well within their
  documented allowance, now that migration 111 made the pre-existing 15 value
  (an old check-then-insert pre-check in ai-proxy/index.ts) a real,
  unconditionally-enforced trigger for the first time.
concept: usage_counter_display_and_vision_cap_value
sot_registry_entry: >
  No new docs/sot_registry.yaml entry — this batch does not change any Hive
  key name, cloud column, or writer/reader file:line contract; it adds an
  internal concurrency primitive (a per-key mutex) to an existing writer and
  raises an existing cap constant via CREATE OR REPLACE. The vision cap's
  writer/reader contract is documented in supabase/functions/CLAUDE.md's SoT
  contracts table (updated in this batch: 15/day → 20/day, migration 114),
  matching the precedent set by Unit 4 for vision_analysis_daily_cap /
  chat_app_daily_cap (Edge-Function-only concepts scoped there, not in the
  heavier Hive+cloud docs/sot_registry.yaml schema).
writers: >
  lib/core/services/usage_counter_service.dart increment() (line 152, now
  wrapped in _withLock, line 156) — one of TWO writers of the 3 per-user Hive
  counters (_aiTextLogCountToday, _scanMealCountToday, _cartAuditorCountToday).
  Callers of increment(): lib/features/nutrition/widgets/food_logger_section.dart:84
  (ai-text-log) and lib/features/ai_coach/services/tool_dispatcher.dart:1269
  (ai-text-log, second writer — AI-coach tool-driven food logging keeping the
  food_logger_section "X remaining" display in sync, per that call site's own
  comment); lib/features/nutrition/providers/nutrition_provider.dart:1379
  (scan_meal) and :1464 (cart_auditor). SECOND writer of the SAME 3 keys,
  found by round-1 review, initially missed by this doc's first draft:
  checkAndResetCounters() (line 209) — called on every app launch (main.dart,
  main_dev.dart, main_prod.dart) AND on every app-RESUME
  (day_rollover_service.dart:140, not just cold boot). Unlike increment()'s
  single-await-after-mutation shape, this method's 4 sequential
  `await MigratedKey.write(...)` calls each genuinely yield to the event
  loop — round-1 review raised this as a plausible reset-vs-increment race
  mechanism. Investigated with the SAME rigor as increment()'s own claim
  (test the pre-fix/unlocked code directly): a concurrent-dispatch test did
  NOT reproduce a corrupted outcome even against the unlocked code, for the
  same underlying reason (Hive's synchronous in-memory `Box.put()` + Dart's
  synchronous `Future.wait` list-evaluation), for a SINGLE resetter racing a
  SINGLE increment. B-pass review then found a THIRD shape that DOES
  reproduce — TWO independently-dispatched checkAndResetCounters() calls
  (reachable via a duplicate app-resume event, day_rollover_service.dart's
  DayRolloverObserver has no re-entrancy guard) racing one increment():
  verified 20/20 lost pre-fix, 20/20 preserved post-fix. Closed with an
  OUTER double-checked-locking guard (_dailyResetLockKey, line 103) wrapping
  the entire staleness-check-and-reset body, staleness re-checked AFTER
  acquiring it — this one is a confirmed bug fix, not defense-in-depth. Each
  of the 3 counter resets still goes through its own per-key
  _withLock (now nested inside the outer lock) as increment(). Sibling writer, same bug class, found while
  investigating this finding: lib/features/ai_coach/providers/
  ai_coach_provider.dart MessageLimitNotifier.incrementToday() (line 460,
  now lock-guarded) — chat's separate msg_count_<date> Hive counter, same
  read-modify-write shape, same non-race finding for increment-vs-increment,
  same defense-in-depth fix (this counter has no analogous
  checkAndResetCounters-style second writer — msg_count_<date> keys expire
  via pruneOld() deletion, not reset-to-zero, and pruneOld only touches keys
  >7 days old, never today's).
  Migration writer: supabase/migrations/114_raise_vision_analysis_cap_to_20.sql
  CREATE OR REPLACEs enforce_vision_analysis_daily_limit (migration 111's
  function), raising the combined cap 15→20.
readers: >
  lib/features/nutrition/widgets/food_logger_section.dart:52 (canUse gate,
  ai-text-log); lib/features/nutrition/widgets/scan_meal_section.dart:41 and
  cart_auditor_section.dart:32 (used() for the "X used today" display);
  lib/features/nutrition/providers/nutrition_provider.dart:1527/1537/1547
  (remaining() providers feeding the "X remaining" UI chips). None of these
  read sites changed in this batch — the fix is entirely inside
  UsageCounterService.increment()'s internals and the server-side cap value;
  the read contract (key names, return semantics) is unchanged.
hive_key_prefix: not_applicable
hive_key_formula: "_aiTextLogCountToday | _scanMealCountToday | _cartAuditorCountToday (unchanged); msg_count_<istDateStr> (MessageLimitNotifier, unchanged)"
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: ai_coach_interactions
cloud_columns: "channel, user_id, created_at (unchanged — migration 114 only changes the trigger function's threshold constant and RAISE EXCEPTION message text, not any column)"
contract_test_path: test/contracts/usage_counter_service_mutex_test.dart, test/contracts/usage_counter_service_race_behavioral_test.dart, test/contracts/vision_analysis_daily_cap_test.dart, test/features/ai_coach/message_limit_cache_test.dart
ist_handling: >
  Unchanged — migration 114 is a CREATE OR REPLACE that preserves migration
  111's Asia/Kolkata day-boundary expression verbatim; only the numeric
  threshold (15→20) and the RAISE EXCEPTION message's parenthetical change.
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  Assumed-but-unverified regression tests (a test that never actually fails
  pre-fix gives false confidence — feedback_source_grep_false_confidence.md's
  sibling class for BEHAVIORAL tests, not just source-grep ones); silently
  "fixing" a client/server cap-value mismatch by unilaterally picking a side
  (lowering the documented PRO promise) without founder input — a product
  decision, not an engineering one; claiming a severity downgrade without
  live-verifying the claimed backstop actually exists (cross-referenced
  migration 111's real trigger shape, not assumed from Unit 4's own summary).
proposed_fix: >
  (1) Behavioral investigation FIRST, before any fix: wrote
  test/contracts/usage_counter_service_race_behavioral_test.dart against the
  UNMODIFIED pre-fix code and confirmed it does NOT fail — the claimed race
  is not reproducible. (2) Added a per-key Completer mutex to
  UsageCounterService (mirroring ProfileWriteService._withLock) and the same
  shape to MessageLimitNotifier.incrementToday() anyway, as defense-in-depth
  matching this codebase's established convention for shared Hive-backed
  state accessed from multiple call sites — NOT as a fix for a reproducible
  bug, since none exists. (3) Migration 114 (CREATE OR REPLACE) raises the
  combined scan_meal+cart_auditor server cap 15→20 to match the documented
  PRO product promise, per explicit founder decision (asked via
  AskUserQuestion rather than resolved unilaterally, since either direction
  — raise server or lower client promise — is a product/revenue decision).
  (4) OI-45's `increment()` finding downgraded CRITICAL → LOW with the full
  verification trail cited on the board; findings 2-4 (progress-map,
  badge-service, health-sync) are UNCHANGED — Unit 3's scope, OI-45 stays
  OPEN.
regression_test_planned: >
  test/contracts/usage_counter_service_mutex_test.dart (source-grep,
  presence-only) + test/contracts/usage_counter_service_race_behavioral_test.dart
  (behavioral — 3 groups. increment-vs-increment and single-resetter-vs-
  increment groups fire concurrent calls via Future.wait and assert no lost
  update, AND document in the header that these same assertions do not fail
  against the pre-fix code — honestly invariant-pinning, not bug-catching,
  per feedback_source_grep_false_confidence.md's spirit extended to
  behavioral tests. The THIRD group, "double-dispatched checkAndResetCounters",
  IS bug-catching: verified to fail 20/20 pre-fix and pass 20/20 post-fix
  across 3 orderings). test/features/ai_coach/message_limit_cache_test.dart
  extended with a concurrent incrementToday() test (closes a B-pass-found
  coverage gap; honestly documented as non-discriminating, same non-race
  mechanism as increment()). test/contracts/vision_analysis_daily_cap_test.dart
  extended with a migration-114-specific case (cap=20, CREATE OR REPLACE on
  the same function). All run green locally pre-live-apply; live-Postgres
  behavioral proof of migration 114's raised threshold is a separate,
  explicit-authorization step (see touched_layers_checked tier 5).
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "usage_counter_service.dart (per-key mutex + B-pass outer double-checked-locking guard) + ai_coach_provider.dart (MessageLimitNotifier, mutex-guarded) both flutter-analyze clean. 4 test files (3 new/extended contracts + message_limit_cache_test.dart), 10 tests in the race-behavioral file alone, all green. The double-dispatch fix specifically verified both directions: reverted -> 20/20 runs lost the increment across 2 orderings; restored -> 20/20 preserved it across 3 orderings." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive key name, shape, or semantic changed — same 3 keys, same read contract" }
  - { tier: 3_postgres_schema, status: fixed_in_this_batch, evidence: "migration 114 CREATE OR REPLACEs enforce_vision_analysis_daily_limit, raising the threshold constant 15->20 and the RAISE EXCEPTION message text; no column/table change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no existing row data touched; function-body DDL only" }
  - { tier: 5_migrations_applied, status: fixed_in_this_batch, evidence: "migration 114 applied live to dedsavbjuwgarrhphgnl at 2026-07-30T06:06:57+05:30 (IST per the DB's own now()), per explicit founder authorization requested via AskUserQuestion (plan approval != deploy approval, CLAUDE.md Sec4.3). backups/applied_migrations.json updated same commit. Verified live via pg_proc.prosrc (daily_count >= 20, message 'cap=20') AND the full live-Postgres behavioral test (test/sql/oi46_daily_cap_triggers_live_verify.sql Case 3, run in a rollback transaction): 20 rows succeed, 21st raises P0001 'vision_analysis_daily_limit_reached (cap=20)'." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "ai-proxy/index.ts touched for doc-comment text only (15/day -> 20/day) — no functional code change, no redeploy required for this batch's correctness (the trigger, not ai-proxy's own code, enforces the number)" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron-dispatched function touched" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS policy change" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage bucket or object touched" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service touched" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "vision_analysis_daily_cap_test.dart's new case traces migration 114's CREATE OR REPLACE end-to-end (function name, threshold, error message, channel gate unchanged). Full live-Postgres proof completed: 20 successful vision requests under the new 20 cap, 21st correctly rejected with 'vision_analysis_daily_limit_reached (cap=20)' (P0001) — see tier 5." }
impact_analysis: >
  Positive: corrects a stale CRITICAL severity rating that had survived two
  prior re-verification passes by re-confirming only the code's SHAPE, not
  its runtime behavior — the actual `increment()`-vs-`increment()` finding
  downgrades to LOW (display accuracy only), a materially different risk
  than "cap bypass." Separately CLOSES a genuine, B-pass-found, empirically
  confirmed lost-update bug (two independently-dispatched
  `checkAndResetCounters()` calls could clobber a concurrent `increment()`)
  via double-checked locking — the one fix in this batch that IS a
  confirmed-bug fix, not defense-in-depth; impact ceiling was already
  bounded by the same server-trigger backstop (worst case was a stale local
  display counter, never a cap bypass), but it's real and now closed rather
  than latent. Closes a genuinely live client/server cap-value mismatch for
  PRO vision-feature users (a real, currently-reachable
  429-despite-documented-quota bug, though pre-dating this batch, not
  introduced by it) via the founder's explicit choice to raise the server
  rather than lower the promise. Adds defense-in-depth mutexes matching
  established codebase convention elsewhere, at zero behavioral cost on the
  happy path.

  No residual on migration 114 as of this doc's final version — applied live
  2026-07-30T06:06:57+05:30, verified via both the function source and the
  full live-Postgres behavioral test; the documented-promise mismatch is
  closed. The mutex additions carry zero residual risk (defense-in-depth or,
  for the double-checked-locking fix, a confirmed closure — not a behavior
  change on any other tested path).
---

# OI-45's `UsageCounterService.increment()` CRITICAL rating was verified-shape but never verified-behavior — most claimed races don't reproduce, one genuine one does, and the real live bug was a cap-value mismatch

## What two prior passes got right, and what they missed

Two board re-verification passes (2026-07-26, then the 2026-07-29 oi-board-corrections batch)
both re-confirmed `usage_counter_service.dart:100-106` still reads
`final current = read(); await write(current + 1)` with no explicit lock, and both concluded
"CRITICAL rating stands." Both were checking the CODE SHAPE against the finding's own
description — a reasonable check, but not a sufficient one. Neither pass asked "does this shape
actually produce a lost update under real concurrent invocation?" — the question this unit's
investigation started with, per the plan's own instruction to check which `ai_coach_interactions`
-gated features Unit 4 (landing the same day) made trigger-safe before deciding whether a new
Postgres RPC was still warranted.

## Investigation, not assumption: the race doesn't reproduce

A behavioral test (`test/contracts/usage_counter_service_race_behavioral_test.dart`) fires two
`increment()` calls via `Future.wait([a, b])` — deliberately NOT sequentially awaited, which is
the shape that would lose an update if the two calls' reads could interleave before either write
landed. Run against the **unmodified pre-fix code**, both increments were still counted
correctly. No lost update.

The reason: `MigratedKey.read` (`lib/core/services/migrated_key.dart:32`) is fully synchronous —
zero `await` anywhere in its body. Hive's `Box.put()` mutates its in-memory keystore
synchronously as the first thing it does, before its own internal `await` (the disk flush is what
actually suspends). `increment()`'s only `await` is `await MigratedKey.write(...)`, which comes
AFTER the read. Under Dart's single-threaded, cooperative event loop, nothing can preempt a
running synchronous stretch of code — so by the time any second caller's `read()` could possibly
run, the first caller has already synchronously read, called `write()`, and had `Box.put()`
synchronously land the new value in memory, all before yielding control back to the event loop.

This is not a novel finding pattern in this OI — finding 3 in the SAME OI-45 entry
(`BadgeService.checkAndUnlock`/`checkAll`) was already downgraded from HIGH on the identical
reasoning ("no `await` between read and write... no live interleaving window") by the prior
correction pass. That pass just didn't apply the same check to `increment()`, because
`increment()`'s `await` comes textually AFTER its read (unlike a fully-synchronous body), which
looks racier on inspection — but is not, once Hive's actual `put()` semantics are accounted for.

## Round-1 review: a second unlocked writer, investigated with the same rigor — and it doesn't race either

An independent, context-blind review of this batch's diff found `checkAndResetCounters()`
(`usage_counter_service.dart:203`) is a SECOND writer of the same 3 keys, previously unlocked, and
raised a plausible mechanism this doc's first draft hadn't considered: unlike `increment()`'s
single-await-after-mutation shape, `checkAndResetCounters()`'s 4 sequential
`await MigratedKey.write(...)` calls each genuinely yield to the event loop — real Hive disk I/O,
not the "one write, already-landed-by-the-time-anything-else-runs" shape that made
increment-vs-increment safe. This is a real mechanistic difference, not a re-hash of the first
finding.

Applying the same standard demanded of the first claim — test the actual pre-fix/unlocked code,
don't reason from the mechanism alone — a `Future.wait([checkAndResetCounters(), increment()])`
concurrent-dispatch test was run against BOTH the locked and unlocked reset code. **The corrupted
outcome did not reproduce either way — and round-2 review sharpened WHY: this isn't merely
"not observed," it's provably deterministic.** A list literal `[a(), b()]` calls `a()` then `b()`
in that fixed order, and calling an async function runs it synchronously up to its first true
suspend point. `checkAndResetCounters()` (list element 0) reaches its reset write, whose own
synchronous prefix (Hive's `Box.put()` landing the value in memory) completes before
`checkAndResetCounters()` hits its first genuine `await` — so by the time `increment()` (element
1) is even invoked, the reset has already landed. Reversing the argument order reverses the
outcome (verified empirically, 20/20 runs each direction — `increment()` first always lands its
write before the reset zeroes it after). The test file now asserts both directions' deterministic
outcome explicitly (`test/contracts/usage_counter_service_race_behavioral_test.dart`'s
"deterministic-order contract" group) rather than the original `anyOf(0, 1)`, which was true but
weaker than what's actually provable, and would have silently kept passing even if a regression
flipped which order is deterministic. The lock was kept anyway (see "The fix" below), but
presented honestly: as defense-in-depth against a dispatch shape this specific guarantee doesn't
reach (independently-scheduled callers whose synchronous prefixes could someday stop being atomic,
e.g. after a refactor adds a genuine `await` before a read), not as a confirmed bug fix.
Overclaiming a "real gap, now closed" here — which an earlier draft of this doc briefly did before
the claim was re-examined — would have repeated the exact overclaiming pattern the whole
investigation exists to correct.

The same review round also caught three citation-accuracy issues, all fixed: `increment()`'s
`_withLock` cited at stale line numbers (the method's line number shifted once the `checkAndResetCounters`
lock-wrapping code was added above it); `incrementToday()` cited at its pre-fix-only line number;
and — most consequential — a checked-in live-verification asset,
`test/sql/oi46_daily_cap_triggers_live_verify.sql` (shipped in Unit 4, inherited by this branch),
hardcoded the superseded cap=15/16th-row values in its vision-cap case. Left unfixed, that file
would have silently started reporting a false failure the moment migration 114 actually went live
— fixed by updating it to cap=20/21st-row, matching what will be true once this batch's migration
applies.

## B-pass review: a THIRD shape — and this one is a genuine, reproducible bug

The mandatory pre-merge B-pass (5-lens review, §4.3) found what round-1 and round-2 missed:
`DayRolloverObserver` (`day_rollover_service.dart`) has no re-entrancy guard, and its staleness
gate (`last_known_date`) is only written well after `checkAndResetCounters()` returns — after the
streak-freeze-refill and streak-decay-reckon steps, not immediately. A duplicate
`AppLifecycleState.resumed` event firing before the first rollover completes (a real, documented
Flutter/Android lifecycle quirk — fast background→foreground→background→foreground, or some OEM
skins double-firing) dispatches a SECOND, independently-scheduled `checkAndResetCounters()` call.

This is mechanistically different from round-1's single-resetter-vs-increment claim (which does
NOT reproduce, per above): with two INDEPENDENT resetters, both can read `last_daily_reset` as
stale (neither's read is gated by anything), both proceed into the per-key reset writes, and
whichever one's write to a given key lands LAST — even if that's after a genuine `increment()`
already landed a fresh value on that same key — unconditionally clobbers it back to 0, since
neither resetter re-checks staleness before its per-key write.

**Verified as a REAL bug, not assumed, and verified as CLOSED, not just patched:**
`Future.wait([checkAndResetCounters(), increment(...), checkAndResetCounters()])` — a synchronous
list construction, not flaky real-world delays — reliably loses the increment: reverting the fix
and re-running produced `0` on 20/20 runs; restoring the fix produced `1` on 20/20 runs. This is
deterministic (not luck) for the same class of reason as the non-races above (Dart's synchronous
list-evaluation + Completer FIFO wake order), just requiring 3 concurrent operations instead of 2
to surface. Two further stress orderings (2 resetters + 1 increment with resetters listed first;
3 resetters + 1 increment) were also verified safe post-fix, 20/20 each.

The fix is double-checked locking: `checkAndResetCounters()`'s entire staleness-check-and-reset
body now runs inside one outer per-run lock (`_dailyResetLockKey`, distinct from the 3 counter
keys), with the staleness condition **re-checked after acquiring the lock**, not just read once at
the top. This makes the staleness READ itself require holding the outer lock — so a second
resetter can never observe `last_daily_reset` as stale unless it is genuinely the first to
acquire the lock; by the time any subsequent caller acquires it, the winner has already finished
(including writing the fresh flag), and the subsequent caller no-ops before touching any per-key
lock at all. This is a general, mutual-exclusion-derived guarantee — provable directly from the
code, not merely an empirical "didn't reproduce in N runs" result like the other findings in this
doc. See `usage_counter_service.dart`'s `checkAndResetCounters()` doc comment and
`test/contracts/usage_counter_service_race_behavioral_test.dart`'s "double-dispatched
checkAndResetCounters" group for the full mechanism.

The same B-pass round also found `MessageLimitNotifier.incrementToday()`'s lock had only a
source-grep presence test, unlike its sibling `UsageCounterService.increment()`'s behavioral
test — closed by adding an equivalent concurrent-dispatch test in
`test/features/ai_coach/message_limit_cache_test.dart`. Honest result, consistent with the rest of
this doc: that specific test (2 identical-shape concurrent calls) does NOT discriminate — same
non-race mechanism as `increment()` itself — so it's documented as invariant-pinning, matching its
sibling, not overclaimed as a bug-catch.

## The real, live, currently-reachable bug: a cap VALUE mismatch, not a race

Cross-referencing migration 111's exact cap (15/day combined, `scan_meal`+`cart_auditor`) against
the client's own documented product limits (`docs/architecture/business-rules.md`: PRO gets 10
scan-meals/day AND 10 cart-audits/day, independently — 20 combined) found a genuine, currently
live discrepancy: migration 111 landed the SAME DAY, in Unit 4, and for the first time made this
pre-existing 15/day value (previously a racy, unenforced check-then-insert pre-check in
`ai-proxy/index.ts`) an unconditionally-enforced Postgres trigger. A PRO user using both features
up to their documented independent limits — nothing racing, nothing malicious, just normal
sequential use — would now hit a real 429 on request #16, despite the client's own "remaining"
display saying they still had quota on both counters.

This predates this batch (the 15 value existed in `ai-proxy/index.ts` before Unit 4 or this unit
touched anything) but was never REACHABLE as a hard rejection until Unit 4's trigger made the
check unconditional. Raising vs. lowering is a product/revenue decision — flagged to the founder
via `AskUserQuestion` rather than resolved unilaterally; founder chose to raise the server cap
(migration 114, 15→20) to match the documented promise.

## The fix

1. `UsageCounterService.increment()`, its sibling second writer `checkAndResetCounters()` (found
   by round-1 review, same non-race conclusion after the same test-the-unlocked-code rigor), and
   the sibling class `MessageLimitNotifier.incrementToday()` (chat's own display counter, same
   shape, same non-race, found while investigating this finding) all get a per-key
   `Completer`-based mutex — kept as defense-in-depth matching `ProfileWriteService`'s and
   `WorkoutWriteService`'s established pattern for shared Hive-backed state, explicitly NOT
   presented as fixing a reproducible bug, since the investigation proved none exists today, for
   either writer pairing. A future refactor that adds an `await` before any of these methods' reads
   (or a future Hive version that changes `Box.put()`'s synchronous-memory-write behavior) would
   silently reintroduce the race these mutexes already guard against.
2. `checkAndResetCounters()` additionally gets an OUTER double-checked-locking guard (B-pass
   finding) — this one IS a confirmed, reproducible bug fix, not defense-in-depth: two
   independently-dispatched resetters (reachable via a duplicate app-resume event) could clobber a
   genuine concurrent `increment()`, verified 20/20 pre-fix and closed 20/20 post-fix. See the
   dedicated section above.
3. Migration 114 raises the combined vision cap 15→20 via `CREATE OR REPLACE` on migration 111's
   function — same shape, same IST boundary, same channel gate, only the threshold and message
   text change.
4. OI-45's `increment()` finding downgraded CRITICAL → LOW on the board, with the full
   verification trail (the non-race finding, the genuine double-dispatch bug + its fix, and the
   server-backstop finding) cited inline so a future pass doesn't have to re-derive it. Findings
   2-4 are untouched — this OI stays OPEN, Unit 3 covers the rest.

## Live apply (2026-07-30)

Per CLAUDE.md §4.3, plan approval is not deploy approval — migration 114's live apply required
its own separate, explicit founder authorization, requested via `AskUserQuestion` after this
unit's ×2 review + B-pass converged. Approved; applied to `dedsavbjuwgarrhphgnl` at
2026-07-30T06:06:57+05:30. Verified live two ways: (1) `pg_proc.prosrc` for
`enforce_vision_analysis_daily_limit` reads `daily_count >= 20` and the raised message says
`cap=20`; (2) the full live-Postgres behavioral test
(`test/sql/oi46_daily_cap_triggers_live_verify.sql` Case 3, run in a rollback transaction against
the real database) — 20 combined `scan_meal`/`cart_auditor` rows succeed, the 21st raises P0001
`vision_analysis_daily_limit_reached (cap=20)`. `backups/applied_migrations.json` updated in the
same commit as the code. The documented-promise mismatch this batch identified is closed.
