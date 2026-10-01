---
reviewed_at: 2026-07-30T00:00:00+05:30
staged_against: e0f4fb3263d0
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

## Triage (post-review, same batch — 2026-07-30)

Both findings independently re-verified against the actual code before acting (per
`feedback_audit_verifier_cannot_trust_own_subagent.md`) — not trusted from the review prose
alone. Both accepted and fixed in this same batch, per `feedback_no_deferrals.md`.

**Finding 1 — accepted, fixed, and this is the one genuinely-reproducible bug this whole batch
found.** Independently confirmed the mechanism by reading `day_rollover_service.dart` directly
(the no-re-entrancy-guard claim and the late `last_known_date` write are both accurate). Applied
the suggested double-checked-locking fix almost verbatim. Went further than the review itself:
built a deterministic (non-flaky) empirical reproduction — `Future.wait([checkAndResetCounters(),
increment(), checkAndResetCounters()])`, a synchronous list construction, not real delays — and
confirmed by reverting the fix that it reliably loses the increment 20/20 runs pre-fix, and
reliably preserves it 20/20 runs post-fix (plus 2 more stress-case orderings, also 20/20 safe).
This is a REAL, closed bug, distinct from every other finding in this batch's diagnose-doc, all
of which investigated similarly plausible mechanisms and found they did NOT reproduce. See
`test/contracts/usage_counter_service_race_behavioral_test.dart`'s "double-dispatched
checkAndResetCounters" group and the diagnose-doc's own updated "The fix" section.

**Finding 2 — accepted, fixed.** Added a behavioral concurrent-dispatch test for
`MessageLimitNotifier.incrementToday()` in `test/features/ai_coach/message_limit_cache_test.dart`,
matching `UsageCounterService.increment()`'s standard. Honest result, consistent with the rest of
this batch: verified by reverting the lock that this specific test construction (2 concurrent
identical-shape calls via one `Future.wait`) does NOT actually discriminate — same non-race
mechanism as `increment()` itself. The coverage gap is closed; the test is documented as
invariant-pinning, not bug-catching, matching its sibling's own honesty standard.

# Code Review — e0f4fb3263d0

Staging hash independently re-derived via `git diff --cached -- ':(top)' ':(top,exclude)docs/reviews' | git hash-object --stdin` → `e0f4fb3263d0c20b3cd551b21717b037142ed5c2` (matches the assigned filename). Blast radius independently re-derived via `dart run scripts/blast_radius_from_diff.dart` on the staged file list → `platform` (matches).

## Finding 1 — P2 — writer_reader_drift (intra-Hive writer-ordering, not field-name drift)

- **file:line:** `lib/core/services/usage_counter_service.dart:213-227` (`checkAndResetCounters`), reachability evidence at `lib/core/services/day_rollover_service.dart:60-93` (`didChangeAppLifecycleState` / `_checkAndRollover`, unmodified by this diff but establishes the trigger mechanism) and `day_rollover_service.dart:138-171` (`_doRolloverWithRef`, shows the staleness-gate write lands only at the *end*).
- **claim:** The new per-key `_withLock` correctly serializes `increment()` against `increment()`, and (per the diff's own deterministic-order proof) a single `checkAndResetCounters()` racing a single `increment()` via a synchronously-evaluated `Future.wait([a(), b()])` list. It does **not** close a third, genuinely-reachable shape the diff's own doc comment gestures at but never traces through: two *independently-dispatched* (not co-scheduled) `checkAndResetCounters()` calls.

  `DayRolloverObserver._checkAndRollover()` (called un-awaited from the synchronous `didChangeAppLifecycleState(resumed)` handler) gates on `configBox['last_known_date'] == today`, but that key is only written at `_doRolloverWithRef`'s step 2 (`day_rollover_service.dart:171`) — *after* `checkAndResetCounters()` has already fully returned. There is no in-flight/re-entrancy guard anywhere in `DayRolloverObserver`. If Flutter/Android delivers two `resumed` events close together (a real, previously-documented class of lifecycle quirk, and trivially reachable by a fast background→foreground→background→foreground) before the first call's `last_known_date` write lands, **both** calls see the stale date and both call `checkAndResetCounters()`.

  Walk the interleaving: resetter R1 zeroes `_aiTextLogCountToday` and releases that key's lock, then moves on to `_scanMealCountToday`. A genuine, real `increment('ai_text_log', …)` (e.g. the user's chat message actually succeeded) now acquires the free lock, reads 0, writes 1 — correct so far. But R2 — the leftover duplicate `checkAndResetCounters()` invocation, which independently decided at its own start that `_aiTextLogCountToday` needed zeroing — eventually reaches its own (redundant) `_withLock(_aiTextLogCountToday, () => write(0))` call. The per-key lock only guarantees R2's write doesn't *tear* against the increment's write; it does nothing to stop R2's unconditional `write(_aiTextLogCountToday, 0)` from landing *after* the increment and silently zeroing it back out. Net effect: a legitimate same-day increment is lost — the exact "lost update" class this batch set out to fix, just via a different writer pair (reset-vs-reset-vs-increment, not increment-vs-increment) than the one the tests exercise.

  This is materially different from the `[checkAndResetCounters(), increment()]` scenario the tests prove deterministic: that proof rests entirely on both calls being invoked synchronously back-to-back inside one list literal, guaranteeing the first call's write lands before the second is even invoked. Two independently-triggered `resumed` events are not co-scheduled that way — there can be a genuine, multi-millisecond async gap (real Hive disk-flush latency) between R1 and R2's respective progress through the 3 keys, which is exactly the "genuinely staggered dispatch via a real timer/callback rather than a synchronously-evaluated `Future.wait` list" caveat the class doc comment on `_locks` (usage_counter_service.dart:206-212) itself names as unreached by its own test — but the comment doesn't go on to confirm whether that gap is actually reachable, or whether the mutex actually closes it if it is. It's reachable (traced above), and the mutex does **not** close it.
- **verification:** Read `day_rollover_service.dart:60-93` — confirm no in-flight/`_rolloverInProgress`-style guard exists around `_checkAndRollover`/`_doRolloverWithRef`. To reproduce directly: a `fakeAsync`/real-`Future.delayed`-based test that starts `checkAndResetCounters()` (call A), lets it progress partway (e.g. `await Future.delayed(Duration(milliseconds: 1))` between two of its internal writes to simulate genuine disk-flush latency rather than the synchronous list-literal shape), starts a second independent `checkAndResetCounters()` (call B) mid-flight, interleaves a real `increment()` between A releasing a key and B redundantly re-touching that same key, and asserts the increment survives. The existing `usage_counter_service_race_behavioral_test.dart` does not cover this shape — its "deterministic-order contract" group only dispatches one resetter + one incrementer via a single `Future.wait` list.
- **suggested-fix:** Double-checked locking: wrap the whole reset body in one outer lock and re-read the staleness condition *after* acquiring it, e.g.
  ```dart
  Future<void> checkAndResetCounters() async {
    final todayStr = istDateStr(DateTime.now());
    await _withLock('__daily_reset__', () async {
      final lastDaily = MigratedKey.read<String>(_lastDailyReset);
      if (lastDaily == todayStr) return; // already reset by a concurrent call
      await _withLock(_aiTextLogCountToday, () => MigratedKey.write(_aiTextLogCountToday, 0));
      await _withLock(_scanMealCountToday, () => MigratedKey.write(_scanMealCountToday, 0));
      await _withLock(_cartAuditorCountToday, () => MigratedKey.write(_cartAuditorCountToday, 0));
      await MigratedKey.write(_lastDailyReset, todayStr);
    });
  }
  ```
  A second concurrent call then blocks on the *same* outer lock and, once it acquires it, observes `lastDaily == todayStr` (the first call already finished) and no-ops instead of redundantly re-zeroing keys a fresh increment may have already touched. Alternatively (cheaper): add a re-entrancy guard in `DayRolloverObserver` itself (`bool _rolloverInFlight`) so a duplicate `resumed` while one rollover is still running is a no-op — this also protects `refillIfNewWeek`/`reckonStreakDecayAndPersist`/the provider-invalidation block from the same double-fire class, which is outside this diff's file list but shares the root cause.
- **impact ceiling, stated for calibration (this is why P2, not P0/P1):** exactly as this diagnose-doc's own severity logic establishes for the sibling increment-vs-increment finding — all three counters this service gates are backstopped by an authoritative Postgres trigger (migrations 026/111/114), so a lost local increment cannot let a request bypass the real cap. Worst case is a stale "X remaining" chip that under-counts, followed by a server-side 429 on the next attempt.
- **status:** fixed — outer double-checked-locking guard added to `checkAndResetCounters()`; deterministically reproduced pre-fix (20/20 lost) and confirmed closed post-fix (20/20 preserved) via `test/contracts/usage_counter_service_race_behavioral_test.dart`'s "double-dispatched checkAndResetCounters" group.

## Finding 2 — P2 — test coverage gap (process, not a runtime bug — extends this diff's own `feedback_source_grep_false_confidence.md` standard to a case it missed)

- **file:line:** `test/contracts/usage_counter_service_mutex_test.dart:30-46` (the *only* test touching `ai_coach_provider.dart`'s new lock, and it is source-grep/presence-only); `lib/features/ai_coach/providers/ai_coach_provider.dart:460-479` (`incrementToday`, the lock-guarded method with no behavioral companion anywhere in the diff).
- **claim:** This same diagnose-doc explicitly invokes `feedback_source_grep_false_confidence.md` and holds `UsageCounterService.increment()` to a behavioral standard — "a test must be shown to actually discriminate fixed-vs-broken, or its passing proves nothing" — and backs that with `usage_counter_service_race_behavioral_test.dart`, which fires real concurrent calls via `Future.wait` and asserts the resulting count. The sibling fix to `MessageLimitNotifier.incrementToday()` (found "while investigating this finding", per the diagnose-doc, and described as "same shape, same non-race finding") gets no equivalent treatment: its only test is `usage_counter_service_mutex_test.dart`'s source-string check that the method body contains `_lock` — it never actually dispatches two concurrent `incrementToday()` calls and asserts the Hive/Riverpod state lands on 2, the way the `UsageCounterService` behavioral test does for `increment()`. Per this repo's own rule (root CLAUDE.md §4.4 rule 21 / Gate 42), a presence-only test is supposed to be paired with a `behavioral_test_path`; here the presence test exists but the pairing doesn't, for this one method, in the same batch that authored the stricter standard for its sibling.
- **verification:** `grep -rn "incrementToday" test/` — only hit is the source-grep test above. No `ProviderContainer`-based concurrent-dispatch test for `MessageLimitNotifier` exists in the diff or pre-existing tree.
- **suggested-fix:** Add a behavioral test mirroring `usage_counter_service_race_behavioral_test.dart`'s first group: build a `ProviderContainer` (with the same Hive/`HiveUserSession` test scaffolding already used elsewhere in this batch), read `messageLimitProvider.notifier`, `await Future.wait([n.incrementToday(), n.incrementToday()])`, and assert `container.read(messageLimitProvider) == 2` (and/or the underlying `msg_count_<today>` Hive value). This is the same shape already proven out for `UsageCounterService` in this batch — low incremental cost, closes the stated-standard gap.
- **status:** fixed — added to `test/features/ai_coach/message_limit_cache_test.dart`. Verified by reverting the lock: this specific construction does NOT discriminate (same non-race mechanism as `increment()`), documented honestly as invariant-pinning rather than overclaimed as a bug-catch.

## Lens-by-lens disposition

### 1. writer_reader_drift
Covered by Finding 1 above (an intra-Hive writer-ordering hazard between two writers of the same key, not a field-name/semantic drift between a Hive write and a cloud read — noted honestly since it doesn't match the lens's literal description but is the closest fit). Beyond that finding, checked explicitly:
- All three `UsageCounterService` keys (`ai_text_log_count_today`, `scan_meal_count_today`, `cart_auditor_count_today`) and `MessageLimitNotifier`'s `msg_count_<istDateStr>` keys have **no cloud writer or reader** — `grep -r` across `lib/core/services/sync/` for all four key literals returns nothing, matching the diagnose-doc's own `sync_methods: not_applicable` / `hive_key_prefix: not_applicable` claims. The only other hit for the three `UsageCounterService` key names outside `usage_counter_service.dart` itself is `lib/core/services/user_config_migrator.dart:78-79`, which is a **key-name list** for `UserConfigMigrator`'s configBox→userBox cross-account migration (confirmed by reading the surrounding context) — it never writes a counter *value*, so it's not a second semantic writer.
- Confirmed `ProfileWriteService._withLock` (`lib/features/profile/services/profile_write_service.dart:128-142`) is byte-for-byte the same acquire/release shape as the new `UsageCounterService._withLock` and `MessageLimitNotifier._lock` — the diff's "mirrors `ProfileWriteService._withLock`" claim is accurate, not just asserted.
- Traced the `_withLock` acquire/release sequence itself for the ordinary (non-double-resetter) cases: because Dart async functions run synchronously up to their first true suspend point, and Hive's `Box.put()` lands its in-memory mutation synchronously before its own internal disk-flush `await`, the lock-acquire (`_locks[key] = c`) always happens with zero yield points before it for the first caller, and the while-loop recheck + re-acquire on wakeup also happens with zero yield points in between — so the increment-vs-increment and single-resetter-vs-single-increment claims in the diagnose-doc and tests hold up under independent tracing. No thundering-herd re-acquisition race exists for waiters queued on the same key.
- Also traced `MessageLimitNotifier.build()` (line 442-454, unchanged by this diff) as a third potential writer of `msg_count_<today>`: it is fully synchronous end-to-end (no `await` between its cache-miss read and its reseed write), so — by the same reasoning as `MigratedKey.read`+`Box.put()` — it cannot be caught mid-way by a concurrent `incrementToday()`, and a concurrent `incrementToday()`'s own in-memory write (if it has already started) is always visible to `build()`'s read before `build()`'s write could stomp it. This is a real difference from `checkAndResetCounters()` (which has 4 *genuinely* yielding sequential writes) and I could not construct a losing interleaving for `build()` — reported here as a checked-and-clean adjacent case, not a finding.

### 2. function_exception_swallow
**No findings for this lens — checked:** `git diff --cached | grep -c "functions.invoke("` → 0. No `.functions.invoke(` call appears anywhere in the staged diff (the two Dart files touched are pure Hive/local-state services; the Edge Function file touched is `ai-proxy/index.ts`, and none of its callers are part of this diff). Lens not applicable to this diff.

### 3. blast_radius_mismatch
**No findings for this lens — checked:** `docs/blast_radius.yaml:62` classifies `supabase/migrations/**` as `platform` (not `catastrophic` — the file name doesn't match any of the `*pseudonymize*`/`*rls*`/`*security_definer*`/`*subscriptions_rls*` catastrophic globs), consistent with the stated frontmatter tier. Verified the migration is treated with platform-appropriate care:
- The 4-tag header required by `supabase/migrations/CLAUDE.md` (`Intent:` / `Destructive?:` / `Rollback strategy:` / `Linked diagnose-doc:`) is present, correctly ordered, and accurate (`Destructive?: no` is correct — this is a `CREATE OR REPLACE` on an existing function, not a DROP/TRUNCATE/lossy ALTER).
- `Rollback strategy: inline` is backed by an actual commented-out reverse-DDL block at file-end, and I diffed it mentally against migration 111's original function: the rollback block reproduces migration 111's exact logic (cap=15, message text `cap=15`) — a real, correct rollback, not a stub.
- Migration numbering (114) doesn't collide with any existing file (`ls supabase/migrations/ | grep '^11[0-9]'` shows 110-114, sequential, 114 new).
- The IST day-boundary expression (`date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'`) is preserved verbatim from migration 111 — verified against migration 111's source directly. This is the *already-correct* boundary (migration 113 fixed a sibling UTC-anchored bug in the food-text trigger the same day; migration 111's vision trigger was never affected by that bug), so migration 114 is not re-introducing a known-fixed defect.
- Per the task brief's specific honesty check: grepped the diagnose-doc for the not-yet-applied disclosure — confirmed present and unambiguous (`touched_layers_checked` tier 5 status `deferred` with evidence "NOT applied live — HELD for the founder's separate, explicit go per CLAUDE.md Sec4.3"; a dedicated "## What is NOT yet true" section restates it). `backups/applied_migrations.json` is correctly absent from the changed-file list, consistent with the migration not having been applied.

### 4. secrets_in_tree
**No findings for this lens — checked:** `git diff --cached | grep -inE "sk-[a-zA-Z0-9]|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN|api[_-]?key\s*[:=]\s*['\"][a-zA-Z0-9]|service_role|SUPABASE_SERVICE_ROLE|password\s*[:=]"` → zero matches across the entire staged diff (docs, SQL, Dart, TS, tests). No credential-shaped literal anywhere.

### 5. unawaited_no_error_sink
**No findings for this lens — checked:** `git diff --cached | grep -c "unawaited("` → 0 (re-verified after an initial noisy grep pass falsely suggested a hit that turned out to be a comment fragment containing the word "await", not an `unawaited(` call). No `unawaited(` call is added anywhere in this diff. Lens not applicable.

## Founder triage notes
<leave blank for founder to fill in>
