---
reviewed_at: 2026-09-18T01:16:23+05:30
staged_against: e6dfd9a3
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — e6dfd9a3 (sync-banner-force-retry)

**Summary:** the code is sound. Every behavioral claim in the commit verified by trace against the live files; the sticky-merge interleavings are correct; the budget/grace arithmetic checks out; both structural-test windows verified by computation (not by trusting the tests' own comments). All 6 findings are documentation-integrity or test-robustness items — none require a code change to sync_queue.dart's or sync_state_provider.dart's logic. **All 6 accepted and fixed in the same session (see per-finding status + the remediation section).**

## Finding 1 — P2 — self_attesting_artifact / guard_without_its_mirror
- **file:line:** docs/diagnoses/2026-09-17-sync-retry-silent-noop-forced-retry-d2e8f4.md:180 (vs :87)
- **claim:** the doc contradicted itself on which tests each mutation reddened. The frontmatter evidence (:87) was correct (m2 reddens the 6-min constant pin + the mixed-ages test; the "just under" test is parameterized off the constant and self-adjusts); the prose "Mutation proofs" paragraph said m2 → "'just under the window' reddens" — false (grace=zero makes that op future-dated; −1s >= 0 is false; assertion still passes) — and undercounted m1 as 2 versus the frontmatter's accurate 5 of 6.
- **verification:** re-derived both mutations by trace: m1 (removing `!passForce && `) makes forced passes skip not-due ops too → tests 1/2/3/4/6 = 5 of 6; m2 leaves the just-under test green and reddens constant-pin + mixed-ages.
- **suggested-fix:** correct the prose to match the frontmatter.
- **status:** fixed — prose paragraph rewritten; m5 (the B-pass's own finally-reset mutation) added to both records.

## Finding 2 — P3 — self_attesting_artifact
- **file:line:** docs/diagnoses/2026-09-17-sync-retry-silent-noop-forced-retry-d2e8f4.md:33 (writers field)
- **claim:** "all rerun state reset in finally (:317-319)" cited the wrong lines — the finally block is sync_queue.dart:304-308; the resets are :305-307. :317-319 lands on `pendingOps()`.
- **verification:** read lib/core/services/sync_queue.dart:304-318 in the committed worktree.
- **status:** fixed — citation corrected to :305-307.

## Finding 3 — P3 — self_attesting_artifact (stale-prose-count class)
- **file:line:** docs/diagnoses/2026-09-17-sync-retry-silent-noop-forced-retry-d2e8f4.md:87
- **claim:** "both test files 43/43 green (9 new + 34 in the extended file)" — total 43 correct, components wrong. Actual at e6dfd9a3: 6 tests in sync_queue_force_retry_test.dart + 37 in sync_queue_auto_drain_test.dart (19 pre-existing + 18 added).
- **verification:** `rg -c "^\s*test\("` on both files (6, 37) and `git show HEAD^:` for the pre-existing count (19).
- **status:** fixed — restated; updated again after remediation (7 + 37 = 44, see below).

## Finding 4 — P3 — guard_without_its_mirror
- **file:line:** lib/core/services/sync_queue.dart:290,295
- **claim:** `passForce` is declared outside the do-while and only ever raised, so forcedness is sticky for the WHOLE drain invocation: a forced pass followed by a rerun requested by a PLAIN caller runs that rerun FORCED too — contradicting the "force is per-call, never ambient" wording in the test's reason string and the doc.
- **verification:** trace: plain caller mid-tap-pass sets `_rerunRequested` only; pass N+1 captures `rerunWasForce=false` but `passForce` retains true from `:290`+`:295`.
- **suggested-fix:** re-derive per pass, OR soften the wording — semantics judged fine (one forced pass serving both requesters; bounded by idempotent executors + the retry budget).
- **status:** fixed — wording path chosen deliberately: nuance added to drain()'s doc comment and the diagnose doc's proposed_fix ("force is per-CALL at the trigger sites; a plain call coalesced into an in-flight forced pass rides that pass and is served forced"). No code change — the coalesced shape is what plan-review round 2 specified and what both callers need (dropping either request is worse).

## Finding 5 — P3 — guard_without_its_mirror (residual)
- **file:line:** lib/core/services/sync_queue.dart:306-307
- **claim:** the finally reset of `_rerunRequested`/`_rerunForce` was pinned STRUCTURALLY only (the 800-char source-grep); no behavioral test drove the exception path (throw mid-pass → next plain drain unforced).
- **verification:** grep of both test files — no throwing-executor scenario existed.
- **status:** fixed — new behavioral scenario added (`sync_queue_force_retry_test.dart`: gate-parked pass + mid-pass force request + `gate.completeError` → next plain drain must skip the backoff-windowed op, discriminated by `pendingOps().single.retryCount == 1` since the seed op is legitimately due and runs). Mutation m5 run: removing the finally resets reddens exactly this scenario; restored → green.

## Finding 6 — P3 — test-quality
- **file:line:** test/contracts/sync_queue_force_retry_test.dart:168,197-213
- **claim:** the sticky-rerun scenario's premise failure cascaded obscurely — if `expect(attempts, 1)` failed, the executor stayed parked on `gate.future` forever, leaving `_draining` true for the rest of the file and cascading confusing failures into subsequent tests.
- **verification:** trace of the failure path: premise expect throws → `drained` never awaited → finally never runs → `_draining` persists (setUp clears Hive, not the flag).
- **status:** fixed — the scenario's post-gate section wrapped in try/finally that completes the gate with a cleanup err and swallows the secondary `await drained` error, mirroring the file's `<900ms` premise-guard pattern.

## Remediation summary

All 6 fixed in one remediation commit: 3 doc corrections (F1-F3), 1 wording
nuance with no code change (F4), 1 new behavioral test + its m5 mutation
proof (F5), 1 test-robustness guard (F6). Post-remediation: both test files
44/44 green (7 + 37); flutter analyze on the touched files: No issues found.
One remediation-side lesson worth recording: the first version of F5's test
used a SYNCHRONOUSLY-throwing executor and interleaving failed — a throwing
executor unwinds on MICROTASKS, faster than the test's next statement can
run, so the force request never hit the in-flight guard; the gate-park
pattern (as in the sticky scenario) is the only reliable way to interleave
against a mid-pass throw.

## Checked clean (per lens)

1. **writer_reader_drift** — Hive writes unchanged (`_persist`/`_remove`, key `'pending_sync_<id>'`, sync_queue.dart:381-387). New public reader `pendingOps()` (:318) wraps `_loadAll()`; its corrupt-entry DELETE + telemetry side effect (:398-405) was already reachable pre-commit via `pendingCountSync` — the display timer adds frequency only (≤2 reads/min while raw>0), no shape change. `sync_banner.dart:24` renders `SyncQueued(:final pendingCount)` — raw→displayable is the intended, sync.md-documented change. `pendingOps()` production consumers: `_stateFor` only. `sot_registry` has no sync-queue entry ("not_applicable" consistent).
2. **function_exception_swallow** — no Edge Function file touched. The two new `catch (_) { return false; }` getters mirror the pre-existing `_autoDrainDisabled` pattern deliberately and fail toward fix-ACTIVE.
3. **blast_radius_mismatch** — `lib/core/services/**` → account confirmed at docs/blast_radius.yaml:338; diagnose self-declares account ✓. No pubspec change → no platform bump ✓. Kill-switches: `disable_sync_force_retry=true` → plain drain (:223-225) = pre-commit behavior exactly; `disable_sync_banner_grace=true` → `SyncQueued(rawCount)` (:146) = pre-commit mapping exactly. Auto drains stay unforced: splash_screen.dart:256, provider :168, :182 — exactly 5 `SyncQueue.instance.drain` call sites, only :227 forced.
4. **secrets_in_tree** — full diff reviewed; no credential-shaped literals.
5. **unawaited_no_error_sink** — zero new `unawaited(` in the diff; the new timer body (:193-197) is fully synchronous.
6. **guard_without_its_mirror** — core interleavings traced clean: force during pass N → pass N+1 forced (capture :293-295 before the ops loop); force between passes / two forces → coalesce; force after last ops-loop → cannot be lost (no await between `_notifyPending()` and the while check — single isolate); exception mid-pass → finally resets all three (improvement over pre-commit, which leaked `_rerunRequested`). Forced pass respects everything it should: maxRetries enforced (budget test pins dead-letter at rc==7 on a FORCED pass), non-transient dead-letters immediately (test pins), cross-account refusal (sync_service.dart:730-749 verified live) dead-letters on first tap regardless of force — documented deliberate. `rawCount==0` shortcut: stale-0 self-corrects on next notify + 1-min timer backstop; raw>0 with emptied queue → correct SyncIdle. `retryNow` on empty queue: same cost as before (one `_loadAll`). m1/m3/m4 respellings each caught by a named assertion; F4/F5 record the two uncovered corners (now covered).
7. **missing_input** — configBox/syncBox via `HiveService.getBox` (hive_service.dart:198,213-214); boxes opened at boot pre-runApp, provider builds post-runApp; `markInitializedForTests` exists (:254). Fail-ACTIVE is the safe direction for both switches. `PendingSyncOp` same-library, import resolves (analyze clean).
8. **asserted_fixture_value** — verified by computation: 800-char window fits (anchor unique; farthest target `_rerunRequested…_rerunForce` at distance 680, `_draining = false;` at 655 — the in-flight-guard assertion is NOT dead). All provider windows hold with margin. Budget arithmetic: enqueue rc=1 (executor NOT called) + 5 forced failures (rc→6) + 6th forced drain (rc=7 → dead-letter) = 6 executor calls ✓. Grace boundaries: exactly-6-min counted via >=, 5:59 excluded, mixed → 2, future op excluded ✓. `<900ms` premise guard present. enqueueFresh stream test is NOT trivial: without the new notify, events = `[1]` and `contains(0)` fails — no other 0-emission path exists in the success flow.
9. **self_attesting_artifact (citations)** — drain :282 ✓, filter :299 ✓, top-merge :295 ✓, retryNow :222/:227 ✓, enqueueFresh notify :263 ✓, `_stateFor` :144 ✓, sync_banner.dart:24 ✓, blast_radius.yaml:338 ✓, sync_service.dart:716-749/:730-749 ✓; HEAD^ pre-fix citations all verified against HEAD^. Two citation/count defects found → Findings 1-3.
10. **plan-review record** — `review_rounds: 2` and `ground_truth_verified: true` NOT contradicted: anchor uniqueness, window 800 (its ~736 estimate vs actual 680), zero gates grep the surface (verified: no scripts/*.dart matches sync_queue/SyncBanner), blast_radius.yaml:338. `bpass: pending` correctly still pending pre-merge.
11. **Test-quality** — no fix-discriminating test passes if the feature did nothing. Singleton hazards controlled: executor overwrite per test, `onDeadLetter` nulled in setUp+tearDown, syncBox deleted per test; per-isolate temp dirs → no cross-file contention. One cascade hazard → Finding 6 (fixed).
12. **Display-timer lifecycle** — NotifierProvider non-autoDispose, never invalidated (only sync_banner.dart:24,46 watch/read) → build() runs once; ref.onDispose (:199-208) cancels both timers; no leak in practice. If ever invalidated, re-build would orphan the old timer/subscriptions — the exact pre-existing shape of `_sub`/`_connectivitySub`/`_drainTimer`; latent and unreachable today, not introduced by this commit.
13. **flutter analyze** (re-run by reviewer): No issues found on both touched lib files (5.3 s).
