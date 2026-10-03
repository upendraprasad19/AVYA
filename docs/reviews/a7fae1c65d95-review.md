---
reviewed_at: 2026-09-26T18:20:00+05:30
staged_against: a7fae1c65d95  # reviewed at c5d659f52986 → d65b986f910b (round 1, all 7 findings fixed) → this round's delta → a9b9cfc33c19 (first mechanical trailer) → 0a8202144960 (second mechanical trailer) → a5e03de2a231 (third: founder acceptance) → this hash (FOURTH, at the --no-ff merge into main: resolving two real conflicts — .claude/skills/code-review/SKILL.md's Tuning-history append point, and regenerating the auto-generated docs/diagnoses/INDEX.md — against ops-alerting-b2a, which merged to main concurrently and independently while this batch's own commits were already landed on single-owner-a. `git diff --cached` at a merge commit diffs against ONE parent (pre-merge main), so it necessarily differs from every prior hash computed on the feature branch alone. Content unchanged except the two conflict resolutions themselves, both mechanical); renamed each time remediation, founder triage, or a merge-conflict resolution moved the staging hash
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (2 context-blind agents dispatched against the d65b986f910b-reviewed delta — A: read-only lenses 1-5, 7, 9, 10; B: mutation lenses 6, 8 in an isolated worktree with the delta patch applied)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
---

# Code Review — a7fae1c65d95 (single-owner batch a, unit a1, round 2)

> Dispatched against the delta on top of **d65b986f910b** (round 1's 7
> findings, all fixed — see that file): the Hermes-pass remediation itself
> (`docs/audit/2026-09-26-hermes-single-owner-a1.md`), specifically the new
> `PredictionAttemptGate` join-avoidance mechanism and the L37-F2
> sanitized-length snapshot fix. Fixing the 2 findings below moved the
> staged diff again; this file then also absorbed one small mechanical
> trailer (documentation-completeness bookkeeping for the round-2 fix
> itself, see the note after Finding 2) that moved the hash a second time
> to the version this filename now carries. Both moves are pure
> continuations of an already-reviewed fix, not new unreviewed logic — see
> the note.

Scope: `lib/core/services/prediction_service.dart` (`PredictionAttemptGate`,
`PredictionService`), `lib/core/services/ai_service.dart` (`_compactContext`
snapshot-length measurement).

## Finding 1 — P1 — writer_reader_drift / guard_without_its_mirror
- **file:line:** lib/core/services/prediction_service.dart:33-72 (`PredictionAttemptGate`, pre-fix — no lifecycle hook existed); lib/core/services/singleton_lifecycle_registry.dart (the registry itself)
- **claim:** `PredictionService` was the one singleton in this family (SyncService, SubscriptionService, WorkoutScheduleService, UsageCounterService, AiService, RazorpayService, SeedService — all seven registered per `docs/sot_registry.yaml`'s `singleton_lifecycle_registry` concept) that never registered with `SingletonLifecycleRegistry`. Two compounding defects follow: (a) `PredictionAttemptGate.run`'s `if (running != null) return running;` lets a device-level account switch mid-request hand the NEW account's own tap the OLD account's in-flight outcome — a mirror of the exact class the registry exists to close, just never wired for this singleton; (b) even with the join closed, `_regenerate`'s writes (`MigratedKey.write('prediction_text', …)` etc.) resolve `HiveUserSession`'s CURRENT box at write time (`migrated_key.dart`), not the box open when the request started, so a prediction computed for the account that asked for it can land in a different, later-signed-in account's box — the `auth_hive_owner_agreement` class.
- **verification:** `grep -n "SingletonLifecycleRegistry.register" lib/core/services/*.dart` (pre-fix: 7 hits, none in `prediction_service.dart`); traced `PredictionAttemptGate.run`'s join line against `HiveUserSession.openForUser`'s three notify call sites (no callback reached `PredictionAttemptGate` pre-fix).
- **suggested-fix:** register `PredictionService` with the lifecycle registry; on the callback, null out the gate's `_inFlight` field so a switch cannot join a stale request (Dart Futures cannot be cancelled, only dereferenced); separately, capture the signed-in account BEFORE the network call and refuse to write if it changed by the time the response resolves.
- **status:** accepted — fixed: `PredictionService._()` now calls `SingletonLifecycleRegistry.register('PredictionService', _onUserChanged)` (prediction_service.dart:99); `_onUserChanged` calls the new `PredictionAttemptGate.clearInFlightForAccountChange()` (prediction_service.dart:57, 111-112), which nulls `_inFlight`. Independently, `_regenerate` captures `ownerAtStart = HiveUserSession.currentOwnerFullId` before `AiService.instance.predict(...)` (prediction_service.dart:132) and refuses every write via the new `PredictionService.safeToWriteForTest(ownerAtStart, HiveUserSession.currentOwnerFullId)` guard (prediction_service.dart:166, checked before the first `MigratedKey.write` at :175), recording an `ErrorTelemetry.recordNonFatal` and returning `PredictionRefreshOutcome.failed` on a mismatch. `docs/sot_registry.yaml`'s `singleton_lifecycle_registry` concept gained `PredictionService` as an 8th `writers:` entry (its two current-state "seven singletons" prose lines bumped to "eight"; the audit-historical "A7, score 14 — seven core services" sentence describing the ORIGINAL 2026-05-20 finding was left as-is since it is a historical fact about that audit, not the registry's live membership); `test/contracts/singleton_lifecycle_registry_test.dart`'s hardcoded `wired` list gained the matching entry. Tests: `test/services/prediction_attempt_gate_test.dart` (join-avoidance behavioural test using a `Completer` to prove a second tap does NOT resolve to the first request's outcome, plus a `safeToWriteForTest` group — same-owner safe, changed-owner unsafe, signed-out-mid-flight unsafe, no-session-throughout safe); `test/contracts/prediction_service_singleton_lifecycle_test.dart` (NEW — real `Hive`/`HiveUserSession.openForUser` proving the registration call actually EXECUTES, not just appears in source); `test/contracts/prediction_refresh_outcome_wiring_test.dart` (wiring pins: owner captured before `predict()`, guard runs after `predict()` and before the first write, the registration call itself). Mutations Mb13-Mb15 in diagnose 125b81 (`safeToWriteForTest` forced `true`: 2/15 red; `register` call commented out: 3/11 red; `clearInFlightForAccountChange` made a no-op: 1/15 red).

## Finding 2 — P2 — asserted_fixture_value / missing_input
- **file:line:** lib/core/services/ai_service.dart:211-214 (`_compactContext`'s `size()`, pre-fix: `json.encode(working).length`); supabase/functions/_shared/sanitize_for_prompt.ts (`sanitizeJsonForPrompt`, the server-side measurement introduced by the Hermes L37-F2 fix in this same batch)
- **claim:** the server now measures the snapshot cap AFTER `sanitizeJsonForPrompt` re-escapes raw U+2028/U+2029/U+0085 as 6-character `\uXXXX` sequences (+5 per occurrence), but the client's `_compactContext` still measured the PLAIN `json.encode(...).length`. A snapshot near the 9500-char ceiling carrying enough of those rare separator characters (plausible from a paste out of certain word processors or PDF extractors into a free-text field that ends up in the snapshot) passes the client's check and is then rejected server-side with "Snapshot too large" — the client and server disagree about what "under budget" means for the exact same bytes.
- **verification:** read `sanitize_for_prompt.ts`'s escape table against `_compactContext`'s pre-fix `size()`; confirmed with a probe fixture (`'a' * 8300` + 250 separator characters) that plain length (8790) sits under 9500 while the sanitized length (10040) sits over it — a snapshot that would pass the client and fail the server.
- **suggested-fix:** give the client a `_sanitizedLength` matching the server's escape table and measure against that instead of the plain encoded length.
- **status:** accepted — fixed: `AiService._sanitizedLength` (ai_service.dart:177-182) adds 5 per occurrence of the three separator code units; `_compactContext`'s `size()` now calls it (ai_service.dart:213) instead of the plain `.length`. Test: `test/ai_coach/compact_context_sanitized_length_test.dart` (NEW — plain-ASCII no-op case; each separator adds exactly 5; the computed-not-guessed fixture above IS trimmed once measured correctly; the same fixture with separators replaced by plain padding is NOT trimmed, as a control). Every separator character in the test is built via `String.fromCharCode`/bare hex (`0x2028` etc.), never a literal escape in source — the test file's own first draft hit the exact raw-invisible-character trap CLAUDE.md documents for `sanitize_for_prompt.ts` itself (found by hex-dumping the file, not by reading it) and was rewritten to close it. Mutation Mb16 in diagnose 125b81 (`size()` reverted to plain length: 1/4 red).

## Trailing mechanical addendum (no new finding — documentation-completeness only)
After both findings above were fixed and tested, `docs/sot_registry.yaml` and
`test/contracts/singleton_lifecycle_registry_test.dart` were updated (see
Finding 1's `status`) to formally register `PredictionService` as the SoT
registry's 8th `singleton_lifecycle_registry` writer, per CLAUDE.md §4.5/§4.7's
requirement that every new writer/reader contract get a registry entry — this
was implied by Finding 1's fix but not yet written down when the fix landed.
A one-paragraph addendum was also appended to diagnose 125b81 recording that
follow-through. That SoT edit's own new `_compactContext` line_range
(195-260, replacing a now-stale 170-195 left over from BEFORE this round's
`_sanitizedLength`/`size()` fix moved the method) then failed
`check_sot_registry_parity.dart`'s `[stale-line-range]` check at gate-loop
time; fixed by widening the cited range to cover the method's new location,
with a note on the registry entry itself explaining why — moving the hash a
SECOND time, to this file's current name. None of the three edits touch behaviour: a YAML prose/list
addition, a hardcoded test-list literal addition mirroring already-reviewed
source, and a diagnose-doc paragraph. No lens in this pass's `lens_set`
applies to a documentation-only addition with no logic delta, so no fresh
dispatch was made for it — consistent with round 1's own precedent of
renaming after a diff shift that is purely the responsive completion of an
already-reviewed fix (see `d65b986f910b`'s own header).

## Checked and clean (from both reviewers, condensed)
- `PredictionAttemptGate.run`'s automatic/manual budget split (one automatic
  attempt per IST day, manual never skipped) is unaffected by the join-fix —
  `clearInFlightForAccountChange` only clears `_inFlight`, never
  `_readLastAutomaticDay`/`_writeLastAutomaticDay`, so an account switch
  cannot be used to spend a second automatic attempt on the same IST day for
  the SAME account (verified: the day key is Hive-scoped per-account via
  `MigratedKey`, which resolves the current `userBox`).
- `refreshEnabled`'s free/PRO gating is unaffected by either fix (no call
  site changed); still pinned by
  `test/contracts/prediction_refresh_outcome_wiring_test.dart`'s "the
  prediction card enables UPDATE through refreshEnabled" test.
- `outcomeForError`'s 429/`RATE_LIMITED` mapping is unaffected by either fix.
- No secrets, no new `unawaited(` without a sink (`ErrorTelemetry.recordNonFatal`
  in the new guard branch is itself the sink, not fire-and-forget of
  something else).
- Full suite re-run after both fixes + the mechanical addendum: 49/49 green
  across every prediction- and singleton-lifecycle-related test file;
  `flutter analyze lib/` clean of warnings/errors (45 pre-existing infos,
  none in any file this round touched).

## Founder triage notes
Both findings accepted and fixed by the coordinator (0 false alarms), plus
the mechanical addendum. Accepted by the founder 2026-09-26.
