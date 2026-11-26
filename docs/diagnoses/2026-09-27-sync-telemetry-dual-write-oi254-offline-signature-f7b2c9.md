---
bug_id: f7b2c9
date: 2026-09-27
batch: ops-alerting-b2a2b
status: fixed
blast_radius: platform
symptom: >
  Three independent client-side telemetry defects, scoped together as unit
  B2a-2b of the ops-alerting batch (the "client classification, queue drift,
  dual write" scope named by the original — since-unrecoverable — B2a plan
  review): (1) the "audit-2026-05-11 H-42 — telemetry pair" idiom, used at
  87 catch sites across `sync_service.dart` and every `part of` domain file
  under `lib/core/services/sync/` (sync_workout/nutrition/health/coach/
  profile/community/realtime/restore_completeness.dart — literally the same
  class), posted the SAME sync failure to `log-client-error` TWICE per
  occurrence: once via the CALLER's own `ErrorTelemetry.recordNonFatal` call
  (generic reason, default `skipServerPost`), and once via
  `_reportSyncFailure`'s own internal write (specific opType). Round 1 of
  this batch's own plan-review found this in a shape narrower than the true
  scope: the FIRST fix pass closed only the duplication `_reportSyncFailure`
  caused BY ITSELF (its own internal `recordNonFatal` call vs its own direct
  `functions.invoke`) — 1 site, not the 87 caller-level pairs, which a manual
  `grep "H-42" sync_service.dart` (13 hits) could not see because it never
  looked inside the 8 part files. The mechanical regression test written to
  pin the ORIGINAL fix (scoped to `sync_service.dart` alone via
  `loadSyncServiceSource()`, which concatenates every part file) caught the
  true count on its own first run, before any human re-review: 87 paired
  sites, not 13. (2) OI-254 (filed by this batch's own B2a-2a B-pass,
  `docs/reviews/46c9b9ff3bde-review.md` finding 1): migration 147's
  `alert_client_errors_spike` `cnt` metric inherits the 087/f0b9d3
  failure-shaped op_type reinclusion regex
  `(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)`, which
  swept in the routine, expected "no active subscription row" outcome
  (`subscription_refresh_query_returned_null`, 28 occurrences/36 days) purely
  because its name ended in `_null` — not because it is an anomaly. (3) no
  client-side mirror existed for migration 147's offline-noise exclusion
  signature, so nothing on the client could ask "would the server-side alert
  classify this exact failure message as offline noise or as a real
  incident" — a gap migration 147's own diagnose-doc (`d2c9f4`) named
  explicitly as a coupling risk this unit needed to close.
concept: sync_error_telemetry
sot_registry_entry: error_telemetry_helper (docs/sot_registry.yaml — no writer/reader/semantic CHANGE from this batch, but the writer's line_range (19-416→19-423) and the sync_service.dart reader's line_range (350-510→2540-2605, correcting a mid-batch citation that undershot _reportSyncFailure's actual body) both drifted from unrelated same-file line-count shifts and are corrected here per §4.9's citation-drift class; the `subscription_payment_grace_window` concept's `failure_op_types` list is updated for fix 2)
writers: >
  Fix 1 (dual-write): { file: lib/core/services/sync_service.dart, method: _reportSyncFailure, line: 2553 } is the single funnel every sync-failure catch block routes through, across ALL 9 files (sync_service.dart is the root; the other 8 are `part of` it under lib/core/services/sync/). _reportSyncFailure itself called
  { file: lib/core/services/error_telemetry.dart, method: recordNonFatal, line: 240 }
  (which itself independently posts to log-client-error) AND its own direct
  `functions.invoke('log-client-error', ...)` a few lines below — that inner
  duplication is the 1-site fix from round 0. Separately, 87 CALLER-level
  sites (the "audit-2026-05-11 H-42 — telemetry pair" idiom, spread across
  all 9 files) each ALSO call `ErrorTelemetry.recordNonFatal` themselves,
  immediately before calling `_reportSyncFailure` — every one of those 87
  independently double-wrote until round 1 of this batch's own review caught
  it. Per-file counts: sync_service.dart itself 13, sync_workout.dart 19,
  sync_health.dart 16, sync_community.dart 9, sync_nutrition.dart 9,
  sync_restore_completeness.dart 9, sync_profile.dart 8, sync_coach.dart 4.
  Fix 2 (OI-254): { file: lib/core/services/subscription_service.dart, method: refreshFromSupabase, line: 906 } — the `response == null` branch's `ErrorTelemetry.logEvent(...)` call, which fed the failure-shaped op_type name into migration 147's `cnt` metric.
  Fix 3 (offlineSignature): no prior writer existed; new pure function
  { file: lib/core/services/sync_error.dart, method: isOfflineNoiseSignature, line: 50 }
  and getter { file: lib/core/services/sync_error.dart, method: isOfflineNoise, line: 89 }.
readers: >
  Fix 1: `public.client_errors` (Postgres table) is the reader surface — every
  row is read by migration 147's `alert_client_errors_spike` cron job and by
  any manual triage query; halving the INSERT rate directly halves the noise
  those readers see per real failure.
  Fix 2: migration 147's `alert_client_errors_spike` `cnt` metric (the outer
  `op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)'`
  reinclusion clause, supabase/migrations/147_alert_client_errors_spike_breadth.sql)
  — the rename removes this op_type from that regex's match set.
  Fix 3: no production reader yet (deliberately — see Fix rationale below);
  the reader is the new contract test
  `test/contracts/offline_signature_migration_147_parity_test.dart`, which
  pins the Dart mirror against the live migration 147 SQL text.
hive_key_prefix: not_applicable (this batch touches telemetry POSTing and pure classification logic — no new Hive key)
hive_key_formula: not_applicable
sync_methods: not_applicable (SyncService._reportSyncFailure is itself part of the sync error-reporting path, not a domain sync method; no new sync fan-out added)
restore_methods: not_applicable
cloud_table: client_errors (Fix 1 — row-count impact); alerts (Fix 2 — indirect, via the alert_client_errors_spike cnt metric this rename affects)
cloud_columns: client_errors.error_code, client_errors.op_type, client_errors.retry_count
contract_test_path: test/sync/sync_telemetry_test.dart (Fix 1); test/contracts/oi254_subscription_refresh_op_type_rename_test.dart (Fix 2); test/contracts/offline_signature_migration_147_parity_test.dart (Fix 3)
ist_handling: not_applicable (no date-keyed state; client_errors.created_at is a plain UTC timestamp read by the cron's rolling 1-hour window, unaffected by this batch)
provider_invalidations: not_applicable (no Riverpod provider reads any of the three touched surfaces)
telemetry_op_types: >
  Fix 1 changes NOTHING about which op_types exist — it removes a duplicate
  INSERT, not a code path. Fix 2 renames exactly one op_type:
  `subscription_refresh_query_returned_null` -> `subscription_refresh_no_active_row`.
  Fix 3 adds no new op_type (it is a pure classification helper, not a
  telemetry emitter).
cross_account_guard: not_applicable (none of the three fixes touch user-scoped Hive state or auth boundaries)
forbidden_patterns_checked:
  - "renaming EVERY op_type that happens to match migration 147's failure-shaped regex, on the theory that all of them are false positives like OI-254 — investigated and REJECTED for 6 of 8 candidates (restoring_destination_unknown, restoring_continue_still_unknown, sync_completed_at_fallback, guarded_box_auto_open_fallback, sync_skipped_null_natural_key, restore_users_row_null_via_singlecall): each carries an explicit code comment proving it is a DELIBERATE observability signal meant to be noticed when it fires rarely (e.g. \"surface every fallback fire so we can measure how often the close-race actually hits in production\"). Renaming these would have silently blinded genuine, intentionally-instrumented signals. Scoped the rename to exactly the one genuine false positive (OI-254's subscription_refresh_query_returned_null), which describes a routine expected state, not an anomaly."
  - "fixing the dual-write bug by removing the direct functions.invoke call in _reportSyncFailure and relying solely on ErrorTelemetry.recordNonFatal's own server leg instead — rejected because recordNonFatal's leg does not carry retryCount, is not integrated with _enqueueTelemetryFailure's next-launch retry queue, and is the newer, less mature of the two paths; keeping the retry-queue-integrated direct call as the canonical client_errors writer and suppressing ONLY recordNonFatal's redundant leg (skipServerPost:true) preserves the more complete telemetry contract."
  - "adding a UI consumer for SyncError.isOfflineNoise to avoid an 'unused getter' smell — rejected per CLAUDE.md's own don't-design-for-hypothetical-future-requirements principle: lib/shared/providers/sync_state_provider.dart's _stateFor method was read directly and confirmed to have NO existing offline-vs-server-error distinction (it only inspects pending count), so there is no real, pre-existing consumer to wire into today. The minimal honest scope is the pure classification function + its parity contract test, immediately usable by a future UI decision without fabricating one now."
  - "mirroring migration 147's three exclusion sub-regexes with uniform case-insensitivity (the natural, easy-to-get-wrong default) — the exception-type override clause is case-SENSITIVE in the live SQL (~, not ~*), verified by re-reading supabase/migrations/147_alert_client_errors_spike_breadth.sql lines 123-140 directly rather than trusting a prior summary of it; mirrored exactly (caseSensitive:true, Dart's default) and mutation-tested (see Verification) — a uniformly-case-insensitive mirror would classify a lowercase exception-type name as a server answer when the live SQL would not, silently diverging the two sides of the same signal."
  - "the compound-boolean-connective mutation-target class (feedback_compound_boolean_connective_mutation_target.md): isOfflineNoiseSignature's status-override and type-override checks are structurally two independent early-return `if` statements (an implicit OR), not a single compound boolean expression — this shape cannot be silently AND-ed by a future edit without changing the code's visible structure. Mutation-tested anyway by deliberately combining them into a single AND-joined condition (the plausible refactor-bug shape) to confirm the two override-exercising tests (status-alone, type-alone) each independently catch it — see Verification."
  - "'queue drift' (one of the four items the original, unrecoverable B2a plan review scoped) silently dropped from this doc's first draft with no investigation record — flagged by round-1 review as a §4.1.5/§4.2 process gap (a scoped item disappearing without saying whether it was ruled out or forgotten). Investigated: `lib/core/services/sync_queue.dart`'s drain-trigger wiring (app launch, connectivity restore, periodic timer, manual retry) — the ORIGINAL 'queue drift' bug this file's own header names (only 2/4 triggers wired for months) — was already fixed 2026-09-16; re-verified live via `grep -rn \"SyncQueue.instance.drain()\" lib/` -> 4/4 call sites confirmed. A SEPARATE, smaller issue was found and fixed in the same pass: `enqueueFresh`'s doc comment falsely claimed a production caller ('used for push-snapshot') that does not exist (`grep -rn enqueueFresh lib/` -> zero callers outside its own definition + test); `pushSnapshotNow()`'s real failure path relies on `_reportSyncFailure` + the in-memory `SyncCoalescer` dirty flag, not this durable queue. Not a live bug (dead code, no caller depends on the false claim) — corrected the doc comment rather than filing an OI, since deleting unused-but-real capability code on a comment technicality would be its own scope creep."
proposed_fix: >
  Fix 1 (dual-write): `ErrorTelemetry.recordNonFatal` gains an optional
  `skipServerPost` parameter (default `false`, so all other call sites are
  unaffected); when `true`, the method returns immediately after its
  Crashlytics leg, before reaching the `log-client-error` POST.
  `SyncService._reportSyncFailure` passes `skipServerPost: true` on its own
  internal `recordNonFatal` call, leaving its own direct `functions.invoke`
  call as the sole `client_errors` writer for every sync failure funneled
  through it (round-0 fix, 1 site). Round 1 (this batch's own plan-review)
  found the true scope was 87 sites wider: every CALLER-level
  `recordNonFatal` call that immediately precedes a `_reportSyncFailure`
  call (the "H-42 telemetry pair" idiom) ALSO needed `skipServerPost: true`
  — applied programmatically (regex-matched, verified paired via a
  `_reportSyncFailure(` lookahead, edited in place) across all 9 files,
  confirmed complete via re-scan (0 remaining unfixed pairs) and
  `flutter analyze` (0 errors/warnings).
  Fix 2 (OI-254): `subscription_service.dart`'s `refreshFromSupabase`
  `response == null` branch's op_type renamed from
  `subscription_refresh_query_returned_null` to
  `subscription_refresh_no_active_row` — a name that avoids every token in
  migration 147's failure-shaped reinclusion regex. `docs/sot_registry.yaml`'s
  `subscription_payment_grace_window` concept's `failure_op_types` list
  updated to match.
  Fix 3 (offlineSignature): three `RegExp` constants in
  `lib/core/services/sync_error.dart` mirroring migration 147's exact
  offline-noise signature, status-override, and type-override clauses
  (byte-for-byte, including the case-sensitivity split), combined via
  `isOfflineNoiseSignature(String)` (a pure function: signature match AND
  NOT (status override OR type override) — implemented as two independent
  early returns, not a compound boolean), and exposed as `bool get
  isOfflineNoise` on the base `SyncError` class (null-safe: an error with no
  message is never offline-noise-shaped).
regression_test_planned: >
  test/sync/sync_telemetry_test.dart — 3 new tests (of 6 in the file): one
  asserts `_reportSyncFailure`'s body contains `skipServerPost: true` AND
  exactly one `functions.invoke('log-client-error'` call (source-grep on the
  compiled method body, the established pattern for this file per its own
  header note on untestable production singletons); one asserts
  `recordNonFatal`'s guard region (between the method signature and the
  `// log-client-error leg.` comment) contains `if (skipServerPost) return;`;
  one (added after round-1 review's P0) sweeps `loadSyncServiceSource()`'s
  FULL concatenated source (sync_service.dart + all 8 part files) for every
  `unawaited(ErrorTelemetry.recordNonFatal(...));` call, checks each one for
  a `_reportSyncFailure(` call within the following 300 characters, and
  asserts EVERY such paired call contains `skipServerPost: true` — with a
  pinned count (87) so a future added/removed pair is caught rather than
  silently drifting the assertion count.
  test/contracts/oi254_subscription_refresh_op_type_rename_test.dart (new,
  5 tests) — parity guard confirming migration 147 still carries the exact
  regex this test mirrors; confirms the OLD op_type name is no longer emitted
  at the exact call site (not a whole-file substring check, since the file's
  own explanatory comment legitimately still mentions the old name); confirms
  the NEW name IS emitted; confirms the new name structurally cannot match
  the failure-shaped regex, with a positive control proving the OLD name DOES
  match (so the assertion isn't vacuous); confirms docs/sot_registry.yaml
  reflects the rename with no stale reference.
  test/contracts/offline_signature_migration_147_parity_test.dart (new,
  12 tests) — 3 parity-guard tests confirming migration 147 still carries
  each of the three exact regex literals (including a NEGATIVE check that the
  type-override clause has NOT been changed to case-insensitive); 5 behavioral
  tests on `isOfflineNoiseSignature` covering: plain connectivity-loss
  messages (true), status-code override (false), exception-type override
  (false), the case-sensitivity parity case — a LOWERCASED exception name
  does NOT cancel the signature match, matching the live SQL's case-sensitive
  `~` exactly (true) — and a bare timeout (false, matching migration 147's
  deliberate non-exclusion of client timeouts); 4 tests on the `SyncError.isOfflineNoise`
  getter including null-safety and the NetworkError/isOfflineNoise
  divergence on a bare-timeout message (transient but not offline-noise-shaped).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/core/services/ — 0 errors, 0 warnings, 17 pre-existing info-level issues none of which touch any of the 9 files this batch edited (sync_service.dart, error_telemetry.dart, subscription_service.dart, sync_error.dart, sync_queue.dart, and the 5 of 8 sync/*.dart part files that needed a fix)" }
  - { tier: 1, layer: contract_tests, status: fixed_in_this_batch, evidence: "34/34 green across the 4 touched/added test files (6 sync_telemetry_test.dart + 5 oi254_subscription_refresh_op_type_rename_test.dart + 12 offline_signature_migration_147_parity_test.dart + 11 ops_alerts_spike_breadth_test.dart). Mutation-proven on ALL THREE fixes plus the round-1-review-driven widening of Fix 1: (Fix 1, round 0) removing `if (skipServerPost) return;` from error_telemetry.dart reddens exactly 1 test; removing `skipServerPost: true` from the sync_service.dart internal call site reddens exactly 1 test — sha256 restored and verified after each (f4ebe491c675b7d5757240b36c6817a13ef0d693fce8fefa19d812e6dfc78d59 and a159898b31a8beac450d88cd3f9c5eca56eca4da5ebbdd7b9509bc41abce70b3). (Fix 1, round 1 — the 87-site widening) removing `skipServerPost: true` from one of the 19 sync_workout.dart sites reddens EXACTLY the new 87-site sweep test, none other; sha256 restored and verified against 8e317f76c0730e4b2e783827eaeca92ad8590ee801fb7304b846cc9242d1f60c. (Fix 2) reverting the new op_type name to the old one reddens exactly 2 tests (the emitter-call-site test and the regex-cannot-match test), none other; sha256 restored (0f40b3ec730ae29551364f02306a697f125a52beaa4d88e4d3745806572afe62). (Fix 3) THREE separate mutations on sync_error.dart, each restored with sha256 re-verified against the original 0d4999ca20a042782d3ed770ce975a4407bbce623b269b09583b1b3a17137c08 after every mutation: (a) adding caseSensitive:false to the type-override regex reddens exactly 1 test; (b) combining the two override early-returns into a single AND-joined condition reddens exactly 2 tests, independently confirming the OR/AND compound-boolean class is covered; (c) removing the null guard on isOfflineNoise (defaulting a null message to a MATCHING literal, not empty-string, since an empty-string default reddens nothing) reddens exactly 1 test." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live grep confirmed subscription_refresh_query_returned_null fires 28x/36 days per migration 147's own diagnose-doc (d2c9f4) impact_analysis — this is the exact live volume Fix 2 removes from cnt's matched set. sync_queue.dart's drain-trigger wiring (queue-drift investigation) re-verified live via grep: 4/4 SyncQueue.instance.drain() call sites confirmed wired (app launch, connectivity restore, periodic timer, manual retry). No live query re-run in this batch since migration 147 (the reader) is not yet applied; the client fixes take effect on next app build regardless of the migration's live-apply status." }
  - { tier: 5, layer: migrations_applied, status: not_applicable, evidence: "no migration touched or applied in this batch — migration 147 (the reader Fix 2/3 target) was applied in the prior unit B2a-2a and is immutable; read only as a reference source here, never edited" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "Fix 1 now genuinely eliminates the dual-write across all 87 caller-level sites plus the 1 internal site (verified via the mechanical 87-site sweep test, not source-grep on a single call). Fix 3's parity test proves the client and server sides of the offline-noise question now agree on migration 147's exact regex text, closing the coupling risk migration 147's own diagnose-doc (d2c9f4) named explicitly." }
impact_analysis: >
  Platform blast radius (`docs/blast_radius.yaml` pins the whole
  `lib/core/services/sync/**` glob to platform tier; this batch's round-1
  widening touches 5 files under it — sync_workout/health/community/
  nutrition/restore_completeness.dart — which is what moved the tier up
  from `account`, the classification this doc originally carried before
  round 1's fix widened the diff. Not catastrophic — no `SECURITY DEFINER`,
  no schema/migration/EF/auth/payment/plan-engine change — so ×2 review +
  B-pass, no Hermes pass).
  No user-facing behavior change in any of the three fixes — all are
  telemetry-shape and pure-classification changes. Before: every sync failure
  wrote TWO client_errors rows instead of one, at 88 total sites across the
  sync layer (Fix 1 — round 0 caught 1, round 1's plan-review caught the
  remaining 87), inflating both the raw row count and (marginally) the
  alert_client_errors_spike cnt metric that reads that table; the routine
  "no active subscription" outcome was indistinguishable, by regex, from a
  genuine failure (Fix 2, OI-254); and no code anywhere on the client could
  answer "does the server-side alert consider this exact failure message
  offline noise" (Fix 3), leaving the gap migration 147's own diagnose-doc
  flagged as an open coupling risk. After: client_errors grows at
  (approximately) half the previous rate per sync failure across the WHOLE
  sync layer, not just the one method originally believed to be the sole
  offender; OI-254 is closed (the one genuine false-positive op_type no
  longer inflates cnt, while the 6 deliberately-instrumented op_types that
  were investigated and found to be genuine observability signals were
  correctly left unrenamed); a new, immediately-usable, parity-tested pure
  function exists for any future consumer that needs to ask the same
  offline-noise question the server-side alert asks; and the "queue drift"
  scope item is confirmed closed (already fixed 2026-09-16, re-verified
  live) with one small correction (a stale, misleading doc comment on
  `enqueueFresh`, an unused-but-real method — fixed, not filed as an OI,
  since no live behavior depended on the false claim).
---

# Sync telemetry: dual-write, OI-254 op_type false-positive, and a client-side offline-noise mirror (B2a-2b)

## What happened

Unit B2a-2b of the ops-alerting batch (following B2a-1's migration 145 and
B2a-2a's migration 147) closed out the client-side half of the original
(since-unrecoverable) B2a plan review's scope: "the client classification,
the queue drift, dual write and spike breadth" — spike breadth was already
shipped in B2a-2a; this unit covers the remaining three, verified fresh
against current code rather than recovered from lost review content:

1. **Dual write.** `SyncService._reportSyncFailure` — the single funnel every
   `catch (e) { _reportSyncFailure(...) }` across `sync_service.dart` AND its
   8 `part of` domain files under `lib/core/services/sync/` routes through —
   itself posted the SAME failure to `log-client-error` TWICE: once via its
   own direct `functions.invoke` call, and once via
   `ErrorTelemetry.recordNonFatal`'s independent server-POST leg (1 site).
   Separately, and MUCH more widely: 87 CALLER-level sites across all 9 files
   follow the "audit-2026-05-11 H-42 — telemetry pair" idiom, where the
   caller ALSO calls `recordNonFatal` (generic reason) immediately before
   calling `_reportSyncFailure` (specific opType) — every one of those 87
   independently double-wrote too, and the round-0 fix (below) did not touch
   them. The two rows from any one double-write disagreed on `retry_count`
   (`recordNonFatal` always sends `0`; the direct call sends the real value)
   — a genuine data-integrity split on what is supposed to describe the same
   event.

2. **OI-254** (filed by this batch's own prior unit's B-pass,
   `docs/reviews/46c9b9ff3bde-review.md` finding 1): migration 147's
   `alert_client_errors_spike` `cnt` metric — deliberately NOT scoped to
   `error_code NOT IN ('event','info')` the way the newer `users`/
   `server_events` breadth arms are, per that migration's own diagnose-doc
   (`d2c9f4`) — inherits the 087/f0b9d3 failure-shaped op_type reinclusion
   regex `(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)`.
   `subscription_service.dart`'s `refreshFromSupabase` emits
   `subscription_refresh_query_returned_null` on every free/expired user's
   routine "no active subscription row" check — a normal, expected outcome,
   not an anomaly — and its name's `_null` suffix matched the regex purely
   by naming coincidence, inflating `cnt` 28 times over 36 days (currently
   non-material: `max(cnt)=24` vs the 40 floor, per migration 147's own
   diagnose-doc).

3. **No client-side offline-noise mirror.** Migration 147 classifies a
   failure message as "offline noise" (excluded from the alert's count)
   using a three-part regex: a connectivity-loss signature, a real-status
   override, and a server-answered-exception-type override. Nothing on the
   client could ask the same question about a given `SyncError`, leaving a
   coupling gap migration 147's own diagnose-doc named explicitly: "B2a-2b
   (client-side telemetry) must define its own offlineSignature to match
   this migration's regex exactly, or the two sides of the same signal will
   classify differently."

## Root cause

**Fix 1 writer/reader (round 0 — the narrower defect):** writer
`lib/core/services/sync_service.dart:2553` (`_reportSyncFailure`) called BOTH
`lib/core/services/error_telemetry.dart:240` (`recordNonFatal`, whose own
server leg independently posts to `log-client-error`) AND its own direct
`functions.invoke('log-client-error', ...)` a few lines later in the same
method — two writers, one event, into `public.client_errors` (the reader
table both migration 147's cron and any manual triage query read).

**Fix 1 writer/reader (round 1 — the true, wider defect, found by this
batch's own plan-review round 1):** 87 additional writers, one per caller
site, each shaped exactly like `unawaited(ErrorTelemetry.recordNonFatal(e,
st, reason: '<generic>')); try { await _reportSyncFailure(opType:
'<specific>', error: e); } catch (_) {}` — spread across `sync_service.dart`
(13) and all 8 `part of` files under `lib/core/services/sync/`
(sync_workout.dart 19, sync_health.dart 16, sync_community.dart 9,
sync_nutrition.dart 9, sync_restore_completeness.dart 9, sync_profile.dart 8,
sync_coach.dart 4). The round-0 fix, scoped only to `_reportSyncFailure`'s
own body, left every one of these 87 sites double-writing exactly as before,
just with the two rows carrying DIFFERENT `op_type`/`reason` values instead
of identical ones. The round-1 reviewer found this by reading the caller
context around `_reportSyncFailure` call sites rather than trusting the
diagnose-doc's "exactly one `functions.invoke('log-client-error'` call site
remains reachable" claim, which was true as a literal grep and false as a
description of the actual client_errors write count.

**Fix 2 writer/reader:** writer
`lib/core/services/subscription_service.dart:906`
(`refreshFromSupabase`'s `response == null` branch) emitted an op_type whose
`_null` suffix matched the reader —
`supabase/migrations/147_alert_client_errors_spike_breadth.sql`'s
`op_type ~* '(fail|error|crash|fallback|unknown|exception|timeout|denied|_null)'`
clause — by naming coincidence rather than by describing an actual failure.

**Fix 3:** no writer or reader existed. The reader that motivated closing
this gap is migration 147's offline-noise exclusion clause itself (lines
123-140 of the migration), which this unit mirrors client-side rather than
consumes directly (Postgres regex text is not directly importable into
Dart).

## Fix

**Fix 1:** `ErrorTelemetry.recordNonFatal` gains `bool skipServerPost = false`
(default preserves all other call sites' behavior unchanged);
`_reportSyncFailure` passes `skipServerPost: true` on its own internal call,
leaving its own direct, retry-queue-integrated (`_enqueueTelemetryFailure` on
failure) `functions.invoke` call as the sole `client_errors` writer from
INSIDE `_reportSyncFailure` (round 0). Round 1 (this batch's own plan-review)
widened the fix to all 87 caller-level H-42 sites: each caller's OWN
`recordNonFatal` call, immediately preceding its `_reportSyncFailure` call,
also gets `skipServerPost: true` — applied programmatically (a script
matched every `unawaited(ErrorTelemetry.recordNonFatal(...));` call, checked
whether a `_reportSyncFailure(` call followed within 300 characters, and
inserted `skipServerPost: true` into every match that didn't already have
it), then verified complete via re-scan (0 remaining) and `flutter analyze`
(0 errors). This preserves each caller's real stack trace (`st`) for
Crashlytics — deliberately NOT collapsed into a single call, since
`_reportSyncFailure`'s own internal Crashlytics leg only receives the bare
error object (no stack trace).

**Fix 2:** renamed `subscription_refresh_query_returned_null` ->
`subscription_refresh_no_active_row` at the one emitting call site. The new
name avoids every token in migration 147's failure-shaped reinclusion regex.
`docs/sot_registry.yaml`'s `subscription_payment_grace_window` concept
updated to match. Six OTHER op_types matching the same regex
(`restoring_destination_unknown`, `restoring_continue_still_unknown`,
`sync_completed_at_fallback`, `guarded_box_auto_open_fallback`,
`sync_skipped_null_natural_key`, `restore_users_row_null_via_singlecall`)
were investigated and deliberately left unrenamed — each carries an explicit
code comment proving it is a genuine, intentionally-instrumented
rare-event-surfacing signal, not a false positive.

**Fix 3:** `lib/core/services/sync_error.dart` gains three `RegExp` constants
mirroring migration 147's exclusion clauses byte-for-byte, a pure
`isOfflineNoiseSignature(String)` function, and a null-safe
`bool get isOfflineNoise` getter on the base `SyncError` class. No UI
consumer was added (none currently exists to wire it into); the function is
immediately usable by a future one without fabricating a placeholder
integration now.

**Kill-switch decision (B-pass Finding 3, blast_radius_mismatch):** platform tier's
`requires:` list in `docs/blast_radius.yaml` nominally calls for a `feature_flag`, and
CLAUDE.md §4.6's feature-flag protocol nominally applies to anything "touching ... sync" —
this diff touches `sync_service.dart` and all 8 of its `part of` files. No kill-switch was
added to any of the three fixes, for a reason specific to each, not a blanket exemption:
Fix 1 (skipServerPost) changes ONLY which of two already-firing writes to `client_errors`
is suppressed — a write-count change, not a write-PATH or schema change, and the retained
write (the retry-queue-integrated one inside `_reportSyncFailure`) is the one that already
carried the durability guarantee (`_enqueueTelemetryFailure` on failure); reverting is a
one-line `git revert` of a pure-arithmetic change, not a live-state migration. Fix 2 (the
OI-254 rename) changes an op_type STRING with no reader anywhere in `lib/`/`supabase/functions/`
keying decision logic on the old literal (confirmed by the cross-tree sweep in "Verified
clean" of the B-pass review) — a straight rename, not a behavior branch. Fix 3 adds a pure
function with zero production callers today (deliberately, per Fix 3 above) — there is no
live code path to gate, because nothing calls it yet. None of the three risk classes §4.6
exists to guard against (a partially-migrated write path, a silently-broken auth/payment
decision, an unreversible schema change) apply here. Consistent with this skill's own
2026-08-11 and 2026-09-16(d) tuning-history precedent that `blast_radius.yaml`'s `requires:`
list is not mechanically enforced repo-wide (`check_blast_radius_coverage.dart` does not
read it) — this is a documented judgment call, not a gap being silently waved through.

## Verification

- `flutter analyze lib/core/services/`: 0 errors, 0 warnings (17
  pre-existing info-level issues, none in any of the 9 touched files).
- 34/34 green across the touched/added test files.
- **Fix 1 mutations, round 0** (2, both on real production code, both
  restored with sha256 verified after): removing `if (skipServerPost)
  return;` from `error_telemetry.dart` reddens exactly 1 of 5
  `sync_telemetry_test.dart` tests; removing `skipServerPost: true` from the
  `sync_service.dart` internal call site reddens exactly 1 of 5 — no other
  test in either file moves.
- **Fix 1 mutation, round 1** (1, on real production code, restored with
  sha256 verified after): removing `skipServerPost: true` from one of
  `sync_workout.dart`'s 19 fixed sites reddens EXACTLY the new 87-site sweep
  test, none other; sha256 restored to
  `8e317f76c0730e4b2e783827eaeca92ad8590ee801fb7304b846cc9242d1f60c`.
- **Fix 2 mutation:** reverting the op_type rename reddens exactly 2 of 5
  `oi254_subscription_refresh_op_type_rename_test.dart` tests (the
  call-site-absence test and the regex-cannot-match test), with the
  positive control (the OLD name DOES match the regex) confirming the
  assertion is not vacuous.
- **Fix 3 mutations** (3, chosen specifically to cover the risk axes a
  faithful-but-lazy mirror would get wrong):
  1. Adding `caseSensitive: false` to the type-override regex (the natural,
     easy-to-get-wrong uniform default) reddens exactly 1 of 12
     `offline_signature_migration_147_parity_test.dart` tests — the
     case-sensitivity-parity test, none other.
  2. Combining the two independent override early-returns into a single
     AND-joined condition (the compound-boolean-connective mutation class
     per `feedback_compound_boolean_connective_mutation_target.md`) reddens
     exactly 2 of 12 — the status-override-alone and type-override-alone
     tests, each independently, confirming the two override clauses are
     correctly OR'd (either alone cancels), not accidentally AND'd (requiring
     both).
  3. Removing the null-safety guard on `isOfflineNoise` (defaulting a null
     message to a matching literal instead of `''`, since an empty-string
     default would have reddened nothing — a "mutation that reddens nothing
     is not proof the case is covered" trap avoided here by choosing a
     default that actually changes observable behavior) reddens exactly 1 of
     12 — the null-safety test, none other.
  All three mutations confirmed applied via direct inspection before running
  (not merely assumed), and `sync_error.dart`'s sha256
  (`0d4999ca20a042782d3ed770ce975a4407bbce623b269b09583b1b3a17137c08`)
  verified to match the pre-mutation original after each of the three
  restore cycles.

## Round-1 plan-review findings, and the "queue drift" scope item

A context-blind round-1 reviewer, dispatched per CLAUDE.md §4.12 before merge,
returned NEEDS-FIXES with one P0 and two P1s, all fixed in this same commit:

- **P0 — Fix 1's dual-write was not actually closed for the caller-level H-42
  sites.** Covered above (Root cause / Fix / Verification). The reviewer's
  own subsequent read confirmed the fix's Crashlytics reasoning, the OI-254
  rename, and the offlineSignature case-sensitivity contract were all
  correct — the P0 was scoped entirely to Fix 1's incomplete coverage.
- **P1 — "queue drift" (one of the four items in the original, unrecoverable
  B2a plan review's scope) had silently disappeared from this doc's first
  draft**, with no record of whether it was investigated or forgotten. It
  WAS investigated, earlier in this batch, before any code was written: the
  original queue-drift bug (`sync_queue.dart`'s drain-trigger wiring —
  documented in that file's own header as "only app-launch and manual retry
  were actually wired for months") was already fixed 2026-09-16; re-verified
  live via `grep -rn "SyncQueue.instance.drain()" lib/` -> 4/4 sites
  confirmed. A smaller, separate issue found in the same investigation —
  `enqueueFresh`'s doc comment falsely claiming a production caller that
  does not exist — is fixed in this batch (`lib/core/services/sync_queue.dart`,
  doc comment only; the method itself is unused-but-real capability code,
  not deleted). The process gap was real: the investigation happened but was
  never written down, so a reader (correctly) could not tell "ruled out" from
  "forgotten." This section is that missing record.
- **P1 — `docs/sot_registry.yaml`'s two `line_range` corrections (for
  `error_telemetry_helper`'s writer/reader citations, made earlier in this
  batch after `check_sot_registry_parity.dart` passed on the STALE ranges
  because they were within-bounds despite pointing at the wrong lines) were
  present in the working tree but never staged.** Had this branch been
  committed from the index as it stood, the stale ranges (`19-280`,
  `350-510`, `197-605` — none of which contain the methods they claim to,
  after the file grew) would have landed instead of the corrected ones
  (`19-416`, `2500-2565`, `197-1237`). Fixed by staging the pending edit;
  no code change needed, since the correction already existed.

Fourth, cosmetic finding (P3, also fixed): `alerts/_thresholds.yaml`'s
`breadth_warn_users` comment still named the OLD op_type
(`subscription_refresh_query_returned_null`) after Fix 2's rename — updated
to the new name (`subscription_refresh_no_active_row`).

## See also

- `docs/diagnoses/2026-09-27-alert-client-errors-spike-filter-drift-recurrence-d2c9f4.md`
  (migration 147 — the OI-254 origin and the offlineSignature coupling risk
  this unit closes)
- `docs/reviews/46c9b9ff3bde-review.md` (the B-pass that filed OI-254)
- `lib/core/services/sync_error.dart`
- `lib/core/services/sync_service.dart`
- `lib/core/services/error_telemetry.dart`
- `lib/core/services/subscription_service.dart`
- `test/sync/sync_telemetry_test.dart`
- `test/contracts/oi254_subscription_refresh_op_type_rename_test.dart`
- `test/contracts/offline_signature_migration_147_parity_test.dart`
- `/home/ubuntu/.claude/projects/-home-ubuntu-projects-avya/memory/feedback_compound_boolean_connective_mutation_target.md`
