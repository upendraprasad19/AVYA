# Plan: coach turns, late link / chat timeout / Retry of a finished turn (OI-505)

Rev 5, 2026-11-13 (after plan-review rounds 1 to 4; round 4 verdict: converged). Branch `coach-late-link-timeout-retry`. Execution mode: INLINE (one
coordinator, one worktree), decided at batch start (§4.12.7). Tier: L (sync + Edge Function + AI chat path). Blast radius:
platform.

Parent batch: PR #260 (OI-502/503, merged 34b5e0ab; migration 178 + ai-proxy v102 + ai-media-proxy v35 live). The shared turn
key `client_key` (`coach_<phone ms>`) exists on `ai_coach_interactions`; the phone sends it in all four request bodies.

## 1. Founder decisions

2026-11-13: fixes 1, 2 and 4 in ONE batch. The ai-proxy deploy needs its own go. A database repair of the surplus rows (section 6)
needs its own go and is NOT part of the code. From the parent batch (still standing): rows already doubled before a fix heal at the
next sign-in; there is no client matcher for them.

## 2. Evidence (live, test account d7a67a37, web app on an iPhone)

| What | Observed |
|---|---|
| 07:00 IST turn "tell me about today's workout" | TWO server rows: `coach_1794533427975` (channel `in_app_orphan`, created 07:00:27.975, uploaded by the push at 12:31) and an unkeyed `app` row created 07:00:50.53 (pre-deploy build). |
| 12:11 IST turn, key `coach_1794552109344` | The browser's request hung during a database outage (12:10:55 to 12:19:51). The page showed "Something went wrong" at 12:30:46 ("Load failed"). The server finished the turn at 12:27:31 (keyed row, 83-char reply). The Retry at 12:35 inserted a SECOND row, same key, created 12:34:58. |
| ai-proxy latency, 24 h before (n=18, HTTP 200) | p50 4.8 s, p95 14.9 s, max 23.1 s (thin sample; test account). |

## 3. Bug history (CLAUDE.md §4.1.5)

- `docs/diagnoses/2026-05-16-sync-coach-cross-channel-dedup.md`: the text lookup's 5-minute window was chosen so "ask the coach, then
  log the same meal text 15 to 90 s later" dedups and "an intentional repeat-log of identical meal text the next morning goes
  through". Recurrence class: **a matcher window anchored to NOW instead of to the turn.**
- `docs/diagnoses/2026-09-26-chat-dedup-replays-failure-marker-e5c9d2.md` + `_shared/chat_dedup.ts`: the 30 s text dedup replays a
  FAILED attempt's 502 so the client's automatic cold-start retries (2/6/12 s; chat is NOT `spendsQuotaPerCall`) do not spend more
  quota. The keyed path MUST NOT bypass it.
- `docs/diagnoses/2026-11-11-chat-refresh-during-send-3e7b41.md`: in-flight counter / Retry bubble semantics.
- `a17bc3` (60 s client dedup, `coach_interaction_repository.dart:103,142,207-236`): the client REUSES the Hive key of any
  non-failed row with the same text within 60 s, including a COMPLETED one. So one key can legitimately carry two deliberate asks.
- Parent `d4a7c9`, `b6d2e8`. Correction to PR #260's note: "rows already doubled heal by sign-out/sign-in" is false for a turn
  LATE-LINKED after the deploy; the push itself creates the new server double (fix 1).
- New diagnose ids `b7e1f3`, `c8f2a4`, `d9a3b5` are unused (checked twice).

## 4. The fixes

### Fix 1: late link anchored to the turn (OI-505 a)

**Writer:** `_syncCoachInteractions` orphan upsert, `lib/core/services/sync/sync_coach.dart:405-440`. **Reader:** the push's text
lookup `:368-390`; the restore `_applyKeyedCoachRows` (`:548-657`). **Defect:** `cutoff = now - 5 min` (`:368`); a server row older
than 5 minutes is invisible, so the push uploads the turn again.
**Design (two steps; the old path is kept as step 2, so nothing the old code matched is lost):**
1. A key matching `kCoachClientKeyPattern` gives `T = DateTime.parse(_coachCreatedAtFromKey(key))` (an ISO UTC string, `:82`).
   Select up to 5 rows of this user with the same text (first 500 chars, as today) and `created_at` in `[T - 5 min, T + 10 min]` (`gte` AND `lte`; the upper bound was 30 min in rev 3, cut to 10 so a later unrelated cross-channel row with the same words cannot be stamped onto a failed turn: round 3 F9), ordered by `created_at`; when the key lookup did not fail ALSO `client_key IS NULL` (a row of another turn's
   key is never a candidate; the same key was already looked up exactly). The candidate NEAREST to `T` (pure helper
   `nearestRowToInstant`) wins: stamp its id, continue.
2. No hit, or an unparseable / out-of-range key: the OLD query exactly as today (`gte now - 5 min`, no `lte`, the B-pass other-key
   rule). This keeps every skewed-clock and slow-turn case the old window caught.
**Kill switch:** `configBox['disable_coach_turn_time_window']` == true skips step 1 (old path verbatim, §4.6).
**Mirror cases:** (a) the same words typed the next morning has another key, so another `T`, so step 1 never matches it; step 2 is the
old behavior; (b) the cross-channel food_text_analysis row 15 to 90 s after `T` IS matched by step 1 whenever the sync runs;
(c) a phone clock skewed by minutes is covered by step 2 exactly as today; (d) two rows in the window (a failed K1 and the real unkeyed
row): the `client_key IS NULL` filter and the nearest-to-`T` pick choose the real one.
**Reach (round 3 F9):** since PR #260 the key lookup matches a keyed server row of ANY age, so step 1 only matters when the server row is UNKEYED (rows written by builds before the 13 Nov deploy, the migration artifact in the evidence). New builds' turns are keyed and need neither window. **Unchanged bound:** the text `eq` uses the first 500 characters, so a stored message longer than 500 characters never matches by text (ai-proxy stores it untruncated, `index.ts:915`); such a turn still doubles on a late link when unkeyed.
**What fix 1 does NOT change (documented bound):** step 1 stamps only the local `id`. An unkeyed server row still restores at
`coach_<server ms>` as a sibling local row (`_applyKeyedCoachRows`, the unkeyed loop `:640-655`), so a device that already shows the
turn twice keeps doing so until its next sign-in; what changes is that NO new server row is created, so the double no longer
survives a sign-in. A test pins this (L10).

### Fix 2: a time limit on the coach chat call, owned by the notifier (OI-505 b)

**Layer decision (round 2 F3):** the timeout and the budget live in the NOTIFIER (`SendMessageNotifier._sendKeyed`,
`_sendWithMediaKeyed`, `lib/features/ai_coach/providers/ai_coach_provider.dart`), so the existing fakes (`implements AiService`:
`test/ai_coach/coach_client_key_request_test.dart:45` `_RecordingAi`, `test/contracts/coach_chat_refresh_during_send_test.dart:43`
`_FakeAi`) can hang and reach it. `AiService.chat` gains `CoachCallBudget? budget` and (fix 4) `bool clientRetry = false`; `chatWithMedia` gains ONLY `budget` (media has no Retry button and `sendWithMedia` takes no `existingCoachKey`, so a media marker would be dead: round 3 F6); BOTH fakes are updated in the same commit. The `_directHttpCall` / `_directMediaHttpCall` call sites pinned by `coach_client_key_request_test.dart:253-263` as exact text (`history: history, clientKey: clientKey);` x2, the media pair x2) gain the new arguments and the pin is REPOINTED.
**Design:**
- `kCoachChatTimeout = 75 s`, `kCoachMediaTimeout = 120 s` (constants beside `CoachCallBudget` in `lib/core/services/coach_call_budget.dart`).
  `await ai.chat(..., budget: b).timeout(kCoachChatTimeout, onTimeout: () { b.expired = true; throw TimeoutException(...); })`.
- `CoachCallBudget { bool expired }` is passed down to `SupabaseService.callFunction({budget})` -> `retryColdStart({budget})`,
  `AiService._directHttpCall` / `_directMediaHttpCall`, and the direct retry helper (extracted as a `@visibleForTesting static
  retryHttpColdStart(invoker, {sleep, budget})`, like `retryColdStart`). Checks (round 2 F1): at the ENTRY of both direct calls after
  their token await and before the first POST; at the TOP of every loop iteration of `retryColdStart` and `retryHttpColdStart`,
  covering the cold-start branch AND the storage-race branch (`supabase_service.dart:575-590`, `ai_service.dart:626-640`); in
  `callFunction` after `ensureFreshToken` / `refreshSession`, before the invoke. Default null = byte-identical behavior for the other
  27 `callFunction` call sites (no fake or override of `callFunction` exists in `test/`).
- **The 401 re-send is inside the same bound (round 3 F1).** `_sendKeyed`'s catch (`ai_coach_provider.dart:1068-1139`) refreshes the session and calls `ai.chat` a SECOND time with no timeout and, in rev 3, no marker. Both calls go through ONE notifier helper `_chatBounded(...)` that creates a fresh `CoachCallBudget`, applies `.timeout(remaining)` and ALWAYS forwards `clientRetry: existingCoachKey != null`, `clientKey: coachKey`, `history: coachHistory`. One shared `Stopwatch` gives a HARD 90 s deadline (round 4 F5): the first call is bounded at 75 s; an auth error at time `t` re-sends ONLY when `t <= 60 s`, `refreshSession()` is wrapped in `.timeout(15 s)` (so it ends by 75 s), and the re-send is bounded at `90 s - elapsed` (>= 15 s). **Classification by TYPE, not text (round 4 F1):** `TimeoutException.toString()` carries the Duration text, which can contain `401` / `502` / `503` / `504` (`Duration(seconds: 40, microseconds: 140123)` prints `0:00:40.140123`), and `isAuthError` (`ai_coach_provider.dart:1077`) gates the re-send block (`:1083`) and the copy (`:1162`). So `final isTimeout = e is TimeoutException; final isAuthError = !isTimeout && (...)`; the `isTimeout` branch is first in the copy chain; the re-send's `catch (retryErr)` (`:1139`) records `retryErr is TimeoutException` and uses the timeout copy instead of the outer auth text. The `in_progress` 503 (both shapes: `FunctionException(status: 503)` and `AiServiceException: in_progress (status: 503)`) is matched on `in_progress` BEFORE the 502/503/504 branch (`:1170`), which would otherwise swallow it as "temporarily unavailable". Test: a `TimeoutException` whose Duration text contains `401` triggers NO re-send; both 503 shapes show the "still working" copy. The source pins `'clientKey: coachKey'` x3 and `history: coachHistory` >= 2 (`coach_client_key_request_test.dart`) are repointed to the helper call sites, never loosened.
- A request already on the wire is not cancelled; its late answer is ignored by the dropped future, and the server row heals the local
  row on the next restore (k3).
- Error copy (Wardroom brand soul, `lib/shared/widgets/wardroom/CLAUDE.md`, loaded before writing): the chat catch
  (`ai_coach_provider.dart:1068-1190`) gets a `TimeoutException` branch with a timeout-specific line and the existing Retry; a 503
  `in_progress` (fix 4) gets "still working" copy. The media catch (`:783-847`) gets the same `TimeoutException` branch whose copy says the photo may still be analysed (a free user's 5-image lifetime meter spends a unit per attempt; today a media timeout shows "couldn't analyse that photo" and logs `ai_media_proxy_unknown_error`). Media failures keep NO Retry button.
**Timeout tests (round 3 F2):** `_sendKeyed` does real Hive disk I/O, which never drains inside `fakeAsync` (`test/contracts/streak_freeze_refill_race_behavioral_test.dart:31`). The two timeouts therefore have `@visibleForTesting static Duration? chatTimeoutOverride` / `mediaTimeoutOverride` beside the constants; the notifier tests are plain `test` with a ~50 ms override and the existing `_FakeAi` Completer pattern; `fakeAsync` is kept only for the pure `retryColdStart` / `retryHttpColdStart` budget tests (no Hive).
**Why 75 s:** 5 times the measured p95 (thin sample), above the cold-start chain (about 20 s) plus Gemini; a legitimately slower turn
finishes server-side and fix 4 returns its stored answer to the Retry.

### Fix 4: a Retry of a finished turn reuses it (OI-505 c; ai-proxy only)

**Writer:** the chat reservation insert `supabase/functions/ai-proxy/index.ts:905-920` (`client_key`, `model_used: "pending"`,
`ai_response: ""`); the resolution UPDATE `:1308-1318`. **Reader:** the 30 s text dedup `:838-889`, `_shared/chat_dedup.ts`.
**Defect:** a Retry minutes later inserts a second row and spends a second unit (the cap trigger is `BEFORE INSERT` only,
migration 111/153).
**Explicit Retry marker (round 2 F2):** the keyed paths run ONLY when the body carries `client_retry: true`, sent by the app only when
`existingCoachKey != null` (the Retry button), in both transports. A new ask never sets it, so a deliberate repeat within the 60 s
client window (same key reused for a different ask) is never served a stale answer and the 30 s text dedup stays the only guard for it.
The automatic cold-start retry of a first send carries no marker either, so it never touches the keyed path (e5c9d2 stays intact).
**Design.** The lookup and the verdict live in ONE `_shared` function `resolveKeyedReplay({clientRetry, clientKey, message, nowMs, loopThrewSentinel, fetchRows})` (round 3 F4) with an injected `fetchRows`, so the wiring is unit-tested without importing ai-proxy. It returns the FINISHED decision, `{kind:'replay', row}` | `{kind:'in_progress', status: 503, body}` | `{kind:'none'}`, so the handler is two `if`s (round 4 F2): `recentDup` becomes `let` and is assigned `keyed.row`; the 503 return reads `keyed.status` and `keyed.body`. Both are source-pinned by their exact text. With `clientRetry === true` (strict), a non-null sanitized `client_key` and the kill switch off, BEFORE the text dedup, it selects up to 5 rows (columns `id, user_message, ai_response, model_used, tokens_used, tool_calls, created_at`: `tokens_used` added, round 4 F3) for `(user_id, client_key, channel 'app')`, newest first (index `idx_ai_coach_interactions_user_client_key`). Pure function
`keyedReplayVerdict(rows, {message, loopThrewSentinel, nowMs, pendingStaleMs = 150000, maxReplayAgeMs = 6 h})` in `_shared/chat_dedup.ts` considers only rows
whose `user_message == message` (the reservation stores it untruncated, 5000-char limit validated first) and returns:
- `replay_reply` (with that row): the NEWEST row created within `maxReplayAgeMs` (6 h; an older answer to a Retry of a days-old failed bubble is stale: round 3 F7) that is complete: `model_used` neither `'pending'` nor the failure sentinel,
  `ai_response` non-empty, AND `tool_calls` (only when `Array.isArray`; `proactive-coach-promotion` writes an OBJECT there: round 2 F5)
  holds no entry with status `queued`, `queued_for_user_confirmation`, `tile_requested` or `legacy_log_actions`. A replay returns text
  only, so a turn whose reply carried an APPLY card, a completion tile or legacy log actions is re-run, never replayed
  (verified: `tool_intents` is only in the live response `:1375`, the replay branch `:879-891` has none). The handler sets `recentDup` to that row and takes the EXISTING `replay_reply` branch (`index.ts:877-891`): one reply body, and `logWriteClaimDetection(` stays at exactly 2 call sites (`coach_write_claim_wiring_test.dart`). It runs before the reservation and any quota spend;
- `in_progress`: no complete row, and a row with `model_used == 'pending'` younger than `pendingStaleMs` exists (150 s, in the PURE
  verdict so it is testable): return **503** `{error: "in_progress", deduplicated: true}`, NO reservation. The client's cold-start retry
  (2/6/12 s) re-asks and gets the reply when the first run finishes; otherwise the error bubble. A handler killed after the
  reservation leaves a pending row that blocks a Retry for at most 150 s (round 2 F4: accepted, Retry-gated);
- `fall_through`: everything else (no row, other message, sentinel/failed rows, stale pending, intent rows). The EXISTING 30 s text
  dedup and processing run unchanged, so a manual Retry of a failed turn re-runs.
**Marker write:** at the resolution UPDATE (`:1308-1318`), when `extracted.actions.length > 0` (legacy `[LOG...]` tags the stored clean
reply no longer carries) append `{ name: "legacy_log_actions", status: "queued", args: { count: n } }` (the count in `args`, as `ToolCallRecord` in `_shared/tools/types.ts` allows; a new field could fail the type check) to the stored `tool_calls`. Readers swept
(round 2 F5): none read it in `supabase/functions` except the writers (`ai-proxy`, `tool-loop.ts`, `types.ts`,
`proactive-coach-promotion`); the client reads `tool_calls_log`, not `tool_calls`; the analytics view `coach_tool_invocations_v` gains one
harmless tool name; re-grepped at implementation.
**Kill switch:** env `DISABLE_CLIENT_KEY_REPLAY` == "1" skips the lookup (old path verbatim). **No migration.**
**Explicit non-goal (round 3 F3):** a Retry offered at 75 s while the FIRST request is still stuck BEFORE ai-proxy's reservation insert (the evidence outage) finds no row, runs, and spends a unit; when the stuck request later arrives it reserves a second row. The restore shows one copy (`pickKeyedCloudCoachRow`), but the unit is lost. Fix 4 does not close this and the diagnose doc says so. Fix 2 makes it reachable (before it, no Retry was offered for 19 minutes); the only client mitigation, cancelling the wire request, is not available through the supabase functions client.
**Media (4b): dropped, not deferred.** No client path re-sends a media key: `sendWithMedia` always mints a new key
(`ai_coach_provider.dart:628-680`), media failures show no Retry button (`:847-850`), and the stored media row cannot rebuild the reply
body (`ai-media-proxy/index.ts:1014-1024`). ai-media-proxy is NOT redeployed. The media TIMEOUT (fix 2) stays.

## 5. Tests (behavioral first; every new test mutated once, §4.4 rule 21)

- Fix 1 `test/sync/coach_late_link_test.dart` (stub server, extended: `test/helpers/sync_stub_server.dart:246-270` throws on `is.null` and
  collapses a repeated `created_at`; it gains `is.null` support and a raw ordered list of query pairs): L1 the 07:00 case (row 5.5 h old, no
  key, now = T + 5.5 h): no upsert, id stamped. L1b skew: phone 8 min ahead (over the 5 min step-1 margin), unkeyed row 1 min before the sync: matched by step 2 ONLY. L3 cross-channel row at T + 60 s matched, with `now - T` > 5 min set explicitly. L4 unparseable key: only the old query (`gte` about now - 5 min, no `lte`). L5 kill switch: old query only. L6 raw request
  shape: `gte = T - 5 min`, `lte = T + 10 min`, `client_key is null`, ordered, limit 10 (round 4 F6: more than 5 same-text unkeyed rows could otherwise cut the nearest one off). L8 a row with another key in the window is not a candidate.
  L9 the same words next morning is not matched by step 1 (uploaded keyed). L10 the documented bound: after the stamp, a restore still writes the
  unkeyed row at its server key (pinned so a later change is deliberate). L11 two candidates: the nearest to `T` wins. L1b, L4, L5, L8, L9 and the other-key stamp rule already pass on the old code and are labelled regression guards (L1b guards step 2 against removal); L1, L3, L6, L10, L11 discriminate (round 4 F7). Seeds use the `toIso8601String()` `Z` form (the stub compares ISO strings as text, `sync_stub_server.dart:280`) and carry an explicit `client_key: null`. Existing fixtures re-anchored: `test/sync/coach_client_key_push_test.dart:30`
  uses key `coach_1763000000000`; `test/contracts/sync_coach_cross_channel_dedup_test.dart:53-70` pins `Duration(minutes:` and `.select('id` and is
  REPOINTED, never loosened.
- Fix 2 `test/ai_coach/coach_chat_timeout_test.dart` (plain `test`, `chatTimeoutOverride` ~50 ms, notifier with a hanging fake; the 401 re-send path hangs too and is bounded; the re-send carries `clientRetry` and the history): the timeout apology + Retry after 75 s; counter 0; the
  late completion changes nothing; media 120 s (no Retry button); `budget.expired` is set. `test/core/coach_call_budget_test.dart`: `retryColdStart` and
  `retryHttpColdStart` perform NO attempt after `expired` (an extra attempt fails the test), at the entry, at the loop top, and in the storage-race
  branch. Pins that read the code being changed, re-run and kept: `test/contracts/retry_loop_guard_test.dart:46-95` (the doc comment above
  `callFunction` must not contain "retry" or "401"), `test/contracts/spends_quota_per_call_source_pins_test.dart:83-107` (regex over the
  forwarded args of `return retryColdStart(`), `test/contracts/edge_function_503_retry_test.dart`.
- Fix 4 `supabase/functions/_shared/chat_dedup_test.ts`: `keyedReplayVerdict` table: no row; other message; real reply; A real + B newer failed (replays
  A); sentinel row (fall_through, then the text dedup still `replay_failure` within 30 s); pending young (in_progress); pending stale
  (fall_through); intent / tile / legacy-marker rows (fall_through); `tool_calls` an object or null (no throw); marker absent (the caller never
  consults it). Client: the two CHAT bodies (both transports, plus the 401 re-send) carry `client_retry: true` ONLY on a Retry; the media bodies never (`test/ai_coach/coach_client_key_request_test.dart` extended). Behavioral `resolveKeyedReplay` tests (injected `fetchRows`): the select column list is asserted from the call (id, user_message, ai_response, model_used, tool_calls, created_at), the `channel = app` and `user_id` filters, no fetch without `client_retry === true`, no fetch under the kill switch, the age cap, the marker. Source pins `test/contracts/coach_keyed_replay_ef_test.dart` (the handler destructures `client_retry` and passes it strictly, calls `resolveKeyedReplay` after the cap/auth block and before the text dedup and the reservation, kill switch, marker write): presence only for the call order, registry `presence_only: true` with the reason that ai-proxy starts `serve(` at module scope; the order is also proven by the live smoke. Existing pins re-run: `coach_write_claim_wiring_test.dart:27,66,87` (do NOT
  rename `dedupCutoff` nor insert a `.select("...")` before the dedup's), `quota_refund_wiring_test.dart:113-181` (indexOf over `index.ts`),
  `ai_proxy_placeholder_resolution_test.dart`, `coach_client_key_ef_insert_test.dart`; `edge_function_503_retry_test.dart:129` counts the literal `client.functions.invoke(` over the unstripped file (never write it in a new comment); `sync_coach_cross_channel_dedup_test.dart:53-70` slices from the FIRST `.select('id` (the key lookup, `sync_coach.dart:345`) and keeps passing only while `existing['id']` and `_stampCoachCloudId(key, cloudId)` stay in that slice; `quota_refund_wiring_test.dart` needs no new `} catch (err_) {` before the outer catch.
- Live smoke (after the deploy go; the `in_progress` case is covered by the unit tests only, a pending row cannot be produced on demand; needs a real login, option to be settled with the founder): one finished turn re-sent with the SAME key, the same
  text and `client_retry: true`: the second answer is `deduplicated: true`, no new row, no unit; the same without the marker runs normally.
- Records: SoT registry (concept `coach_interactions`, `docs/sot_registry.yaml:6549`, notes at `:6673-6710`; there is no `coach_client_key` concept; plus the `presence_only` entry), naming conventions (`client_retry`, `CoachCallBudget`,
  `disable_coach_turn_time_window`, `DISABLE_CLIENT_KEY_REPLAY`), nested CLAUDE.md rows (ai_coach, core/services), diagnose docs (`b7e1f3`, `c8f2a4`,
  `d9a3b5`), `bug-classes.md`, `docs/architecture/sync.md`; no migration, `backups/` untouched.

## 6. Data repair (NOT code; own founder go)

Show the row ids first. For the 07:00 turn keep the real server row (unkeyed, 07:00:50) and delete the keyed orphan (07:00:27); for the 12:11 turn
delete the second row (created 12:34:58). `BEGIN ... ROLLBACK` rehearsal, then the write. The device then shows one copy after its next sign-in.

## 7. Dispositions

Round 1 (11 findings, all verified in the code by the coordinator): F1 P1 keyed verdict only short-circuits on a real reply, else falls through. F2 P1
replay is text-only (intent / tile / legacy rows re-run; marker). F3 P2 `in_progress` 503. F4 P2 newest COMPLETE row of up to 5. F5/F6 P2 fix 1 step 2
keeps the old window; bounds T-5 / T+30. F7 P2 `client_key IS NULL` + ordering. F8 P2 timeout copy branch; budget. F9 P2 4b dropped. F10 P2 tests.
F11 P3 ids free.
Round 2 (7 findings; verdict not converged, no P0/P1): F1 P2 budget entry + loop-top + storage-race checks (taken). F2 P2 explicit `client_retry` marker
(taken; verified `coach_interaction_repository.dart:142,207-236` reuses a completed row's key within 60 s). F3 P2 notifier owns the timeout, fakes updated,
`retryHttpColdStart` extracted (taken; verified two `implements AiService` fakes and no `visibleForTesting` on the helper). F4 P2 stale threshold in the pure
verdict (taken; accepted Retry-gated bound). F5 P3 `Array.isArray` (taken). F6 P3 documented bound + nearest-to-T pick (taken; verified
`_applyKeyedCoachRows` unkeyed loop writes a sibling at the server key). F7 P3 test inventory (taken; verified paths).

Round 3 (10 findings; verdict not converged, no P0/P1; the reviewer judged fix 1 separable): F1 P2 the 401 re-send inside the bound and the marker
(taken; verified `ai_coach_provider.dart:1068-1139` re-sends `ai.chat` with no timeout and no marker). F2 P2 plain `test` + timeout overrides (taken; the
repo's own pitfall: real Hive I/O never drains in fakeAsync). F3 P2 explicit non-goal (taken). F4 P2 `resolveKeyedReplay` in `_shared` with injected
`fetchRows` (taken). F5 P3 pin list (taken). F6 P3 media gets no marker (taken). F7 P3 6 h age cap (taken). F8 P3 test discrimination (taken). F9 P3 reach,
cross-channel bound T+10, 500-char bound (taken). F10 P3 ranges, concept name, media copy, `args` count (taken).

Round 4 (7 findings; VERDICT converged, no P0/P1): F1 P2 timeout classified by type and a hard 90 s deadline (taken). F2 P2 `resolveKeyedReplay` returns the finished decision, exact-text pins, `let recentDup` (taken). F3 P3 `tokens_used` in the select (taken). F4 P3 `in_progress` branch before 502/503/504 plus tests (taken). F5 P3 hard deadline (taken, with F1). F6 P3 limit 10 (taken). F7 P3 test labels (taken).

## 8. Review record

Four independent rounds, each a fresh context-blind Sonnet reviewer with an exhaustive read-only command list; every finding was re-checked by the coordinator in the code before it was folded in. Round 4 converged. Execution is inline, in this order: fix 1, fix 2, fix 4, then records.
