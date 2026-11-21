# Plan: coach chat times, duplicate turns, Home tip removal (OI-502, OI-503)

Branch `coach-chat-time-dup`. Founder go 2026-11-13: "let's remove it in the same batch as the time and duplicate
fixes". Tier L (sync): two plan-review rounds, the B-pass, and the plan-review record. Execution mode: **inline**, one
worktree, decided at batch start.

## 0. Observations (founder screenshots, 2026-11-13 07:01 IST, web app on iPhone Safari)

1. The chat bubbles say `01:30` for a turn sent at 07:00 IST, and an earlier one says `11:04` (16:34 IST).
2. One question ("tell me about today's workout") shows twice, each copy with its own reply.
3. Home's AI insight card: the founder asked what the coach tip is. Measured over every coach reply of the last 60 days
   (19 rows), the tip's rule (the last sentence, 10 to 80 characters) produced no tip from any of them. Six were too short
   (`Stand to.`, `Carry on.`), one was too long, and the twelve that would have shown were all a follow-up question, an
   error line (`Try again in a moment.`) or a refusal fragment. Founder decision: remove the tip.

Live evidence for 2 (read-only):
- `ai_coach_interactions` holds ONE row for that turn (`b5f81db2`, `created_at 2026-11-13 01:30:50.53+00`).
- The edge logs show one ai-proxy preflight (01:30:28) and one chat-row insert (01:30:45).
- `client_errors` for the account: `restore_started` 01:30:34, `restore_completed status=success path=singlecall`
  01:31:17. The send and the full restore ran at the same time.

## 1. Writers and readers (file:line at `main` 0b87f5bb)

**Chat row time, `coachBox['coach_<ms>'].created_at`, UTC with `Z` since 2026-09-27 (`80557539`):**
- Writers: `coach_interaction_repository.dart:54` (`saveInteraction`) and `:122` (`saveUserMessagePending`). The
  restore copies the cloud value (`sync_coach.dart:321`, `+00:00` form).
- Readers that treat the string as a local clock or as an IST date:
  - R1 `chat_area.dart:71-72`: prints `timestamp.hour:minute` of `DateTime.tryParse(created_at)`
    (`ai_coach_provider.dart:276`). A `Z` string parses to a UTC DateTime, so the bubble shows UTC.
  - R2 `coach_interaction_repository.dart:268-290`, `getTodayUserMessageCount`: `createdAt.startsWith(istDateStr(now))`.
    Between 00:00 and 05:30 IST a row's UTC date is the previous day, so that window's turns are not counted.
  - R3 `coach_memory_service.dart:80-90`, `extractAndAppendCoachingNotes`: the same `startsWith` test, so the same window
    is missed.
  - R4 `home_provider.dart:724-752`, `_getLatestCoachTip`: the same test. It is removed (section 5).
- Readers that compare instants or sort strings of one format only, so they are unaffected: `CoachChatClear.isHiddenByClear`
  (instant compare), `recentHistoryExchanges` (string sort, `:406`), `ChatHistoryNotifier.build` (sort of
  `_CoachEntry.createdAt`). The string sorts mix `Z` and `+00:00` rows; both are UTC, so the order holds except inside one
  second. That is recorded, and not changed here.

**Chat turn identity across local and cloud:**
- Local writer: `mintCoachKey()` (`coach_interaction_repository.dart:73-78`) keys the row by the PHONE's clock.
- A text turn's cloud row is the ai-proxy reservation INSERT (`ai-proxy/index.ts:904-915`: `channel 'app'`,
  `model_used 'pending'`, `user_message` untruncated, `created_at` = the server's insert time). It is resolved by an
  UPDATE of the reply fields only (`:1214-1235`, `:1300-1310`); the chat `created_at` is never refreshed (round 1 F2: the
  refresh at `:419-426` is the `food_text_analysis` branch). Its id (`chatReservationId`, `:940`) is NOT returned to the
  client.
- A photo turn: the local row is `user_message '[Photo] <caption>'`, `mode 'media'` (`ai_coach_provider.dart:657-663`). The
  cloud row is inserted by ai-media-proxy AFTER the analysis (`ai-media-proxy/index.ts:1000-1010`:
  `'[Photo: <type>] <caption>'`, `created_at: new Date()`). Photo turns double the same way (round 1 F14).
- Push (`sync_coach.dart:178-262`): a row whose `id` is a UUID is skipped (`:183`). Otherwise a cloud row with the same
  `user_message` (first 500 chars) in the last 5 minutes FROM NOW is looked up with no channel filter (`:204-215`). On a
  hit, the local `id` is stamped with that cloud id (`:216-226`). With no hit, the push upserts an `in_app_orphan` row with
  id `_deterministicId('coach|$userId|$key')` and the local `created_at`, then stamps that id (`:229-262`). So one local
  turn can have TWO cloud rows: the ai-proxy `app` row and an orphan echo (round 1 F4). Every restored row today has
  `id` = its Hive key (non-UUID), so the push re-sends restored rows as orphans too.
- Restore (`sync_coach.dart:278-352`): pulls every channel; writes each cloud row at `coach_<cloud created_at ms>` with
  `id` = that key and `source: cloud_restore`; has no owner check (round 1 F5). **It never reads the stamped id**; the
  push comment at `:216-221` and `sync_coach_cross_channel_dedup_test.dart:91-102` promise a "collapse" with no reader.
  The keys differ for every server-written row: two rows, two bubbles, and two units in R2's daily tally.
- Other readers of a coach row's `id`: the push (`:183`) and a same-second sort tie-break
  (`coach_interaction_repository.dart:409`). `ChatMessage.coachKey` is the Hive KEY (`ai_coach_provider.dart:294,320,331`),
  so retry, `recordMediaSaveDecision` and `refreshFromHive` are unaffected by an `id` change (round 1 F7).
- Recurrence: the APK Test #12.8 Bug #1 class (restore key != writer key; `test/sync/restore_keys_deterministic_test.dart:123`),
  and the memory class "a write target with no reader".

## 2. Fix A, the bubble time (OI-502, R1)

- New pure `chatClockLabel(DateTime t)` in `lib/core/utils/date_utils.dart` (not `ist_date.dart`: it reads the device
  clock, not IST), returning `HH:mm` of `t.toLocal()`.
  `chat_area.dart:71` calls it. The device's local clock is what the status bar shows; for an IST device it is IST.
  A legacy row (pre-2026-09-27, no zone) parses as local already, and `toLocal()` keeps it unchanged.
- Test T1: `chatClockLabel(DateTime.utc(2026,11,13,1,30))` is `07:00` under `TZ=Asia/Kolkata`, `01:30` under UTC and
  `10:30` under Tokyo. A zone-less string parsed then formatted keeps its own clock. The test is run under all three zones.
- Wiring pin: the bubble's time comes from `chatClockLabel` (source slice of `chat_area.dart`).

## 3. Fix B, the "today" checks (OI-502, R2 and R3)

- New pure `isIsoOnIstDay(String iso, String istDay)` in `ist_date.dart`: parse `iso` (an unparseable or empty string is
  false), then `istDateStr(parsed) == istDay`. R2 and R3 replace `createdAt.startsWith(todayStr)` with it.
- Test T2 (behavioral, Hive):
  - A row at 00:30 IST today (UTC the previous day) counts toward `getTodayUserMessageCount`.
  - A row at 23:30 IST yesterday does not.
  - A row at 06:00 IST today counts.
  - Run under Kolkata, UTC and Tokyo.
- R3 gets the same helper, a unit test of `isIsoOnIstDay`, and a wiring pin (the method no longer contains
  `startsWith(todayStr)`).

## 4. Fix C, one turn = one row after a restore (OI-503), rev 3: a shared turn key

**Founder decision 2026-11-13** (after round 2 found a P0 in the text-and-time matcher): give each turn ONE identity
that the phone and the server share, instead of guessing. Rounds 1 and 2 kept finding new holes in the guessing
mechanism (rule order, untrusted stamps, retries, clock skew); this design REMOVES that mechanism (memory: remove the
mechanism when review rounds chase its symptoms). Rev 2 (rules 1 to 4, `planMerge`, the content heal) is withdrawn.

**The key**: the local Hive key of the turn (`coach_<ms>`, minted by `mintCoachKey` before the AI call). The phone
sends it as `client_key`; the server stores it on the cloud row; the restore writes the cloud row back AT THAT KEY.

C1. **Migration 178** (minted by `scripts/mint_migration.sh`): `ALTER TABLE public.ai_coach_interactions ADD COLUMN IF
NOT EXISTS client_key text NULL` with `CHECK (client_key IS NULL OR client_key ~ '^coach_[0-9]{10,16}$')`, and a partial
index `(user_id, client_key) WHERE client_key IS NOT NULL` for the push lookup (C4). Nullable, no backfill, no trigger
change (the three BEFORE INSERT rate-limit triggers and `trg_suppress_redundant_updates` read no column list, verified
live). RLS is row-level only (`005`, `008`, `055`, `100`), so the client's own upsert may write the column. Rollback:
`DROP INDEX`, `DROP COLUMN`. Live apply needs the founder's go; it lands BEFORE the Edge Function deploys and before the
merge (C2 and C4 write the column; writing a column that does not exist fails the insert).

C2. **Edge Functions** (deploys need the founder's go):
- `_shared/client_key.ts`: `sanitizeClientKey(raw: unknown): string | null`. A string matching
  `^coach_[0-9]{10,16}$` is returned; anything else is null. Never throws, never logged.
- `ai-proxy`: the chat reservation INSERT (`index.ts:904-915`) adds `client_key: sanitizeClientKey(body.client_key)`.
  Nothing else changes: the dedup replay (`:838-880`) inserts nothing, and the resolve UPDATE keeps the column.
- `ai-media-proxy`: the body destructure (`index.ts:599`) gains `client_key`, sanitized ONCE. The sanitized value is
  passed as a new parameter into the image paywall insert (`:332`) and the video paywall helper (`:372-385`, which today
  sees only `userId, message, mediaUrl`), and used by the analysis insert (`:1001`). Paywall rows are keyed too. A
  paywall row is a complete reply, so on the sending phone it only stamps the id (C5 Present).
- A malformed or absent key is DROPPED (null) and the insert goes ahead unchanged, so the CHECK can never reject an
  insert and a bad key can never break chat (round 3 F5).
- Food and vision rows (`food_text_analysis` `:435`, the vision types `:639`) deliberately carry NO key. Their bodies
  send none, and the food dedup refreshes `created_at` on a reused row (round 3 F7). `predict` (`ai_service.dart:425`)
  inserts no row and sends no key.
- Deno tests: `_shared/client_key_test.ts` (valid, wrong prefix, too short, too long, non-string, injection text) and
  source pins that each insert carries the field.

C3. **Client sends it** in all FOUR request bodies (round 3 F1): `chat` through `callFunction` (`ai_service.dart:369-377`,
the primary transport), `chat` through `_directHttpCall` (`:487-520`, the fallback), `chatWithMedia` through `callFunction`
(`:676-679`) and `chatWithMedia` through `_directMediaHttpCall` (`:723-754`). Each adds `'client_key': clientKey` when
non-null; `chat` and `chatWithMedia` take `{String? clientKey}` and forward it to their fallback. `predict` is excluded.
`SendMessageNotifier.send` passes its `coachKey` (both `.chat(` call sites, `ai_coach_provider.dart:958, 1038`, the second
the auth-retry re-send) and `sendWithMedia` passes its `coachKey` (`:693`). A Retry reuses the row's key, so every
attempt of one turn carries the same key. **In-flight registry** (round 2 F5, round 3 F4): `CoachInteractionRepository` keeps a static COUNTER map
`Map<String, int>`. `beginInFlight(key)` increments it; `endInFlight(key)` decrements it and removes the key at 0;
`isInFlight(key)` is true while the count is above 0. A counter, not a set: the 60 s dedup can hand two live sends the
SAME pending key (`_findRecentDuplicateMessageKey` skips only `failed` rows), and a set would clear the key when the
first send ends.
- Exact points (round 4 F2):
  - In `_sendBody`, a Retry (`existingCoachKey`, `ai_coach_provider.dart:882`) calls `beginInFlight` at the top of its
    branch and opens the `try` THERE, so the reset `put` (pending true, empty reply) is inside it (round 5 P3-a: a
    throwing put must not leak the count).
  - A new send calls it on the first line after `saveUserMessagePending` returns the key (`:895`).
  - Immediately after `beginInFlight`, a `try { ... } finally { endInFlight(key); }` wraps the WHOLE rest of the body:
    the `addMessage` and refresh calls, the history assembly, the AI call, the auth re-send (`:1029-1075`, including its
    `return`), and the last Hive write.
  - `_sendWithMediaBody` (`:658`) does the same from the line after its key.
  - So no throw, `return` or early exit can leak the count, and no await sits between knowing the key and counting it.
- An app restart empties the map, which is correct: after a restart no send is live.
- `endInFlight` on an absent key is a no-op and never goes negative, so a `finally` that runs after `_onUserChanged`
  cleared the map is harmless (round 5 P3-a; tested).
- The map is cleared in `SyncService._onUserChanged` and has a `@visibleForTesting` reset (round 3 F9).
- `sync_service.dart:60` already imports a coach repository, so reading it from the sync part adds no new layering
  edge (round 3 F9). The fake at `test/contracts/coach_chat_refresh_during_send_test.dart` takes the
new parameter. Test: the request body carries `client_key` equal to the row's key (stub server), for chat, the retry
and media.

C4. **Push** (`_syncCoachInteractions`, `sync_coach.dart:178-262`): for a local row whose `id` is not a UUID, FIRST look
up `.eq('user_id', userId).eq('client_key', key).limit(1)`. A hit stamps the cloud id and skips, exactly like today's
text hit. No hit falls through to the existing text lookup UNCHANGED (older rows have no key). The orphan upsert payload
gains `'client_key': key`. So a turn the server never saw is still pushed once, and is keyed. Three guards:
- If the key lookup THROWS (a database without the column), the push falls through to the text lookup and upserts the
  orphan WITHOUT `client_key`, so a missing column never stops the push (round 3 F5).
- The orphan payload carries `client_key` ONLY when the key matches `^coach_[0-9]{10,16}$`; a `coach_<hex>` key (a
  restored row with an unparseable `created_at`) would fail the CHECK on every pass (round 5 P3-d).
- A row with `source == 'cloud_restore'` is never pushed: it came from the cloud, so the cloud already has it (round 5
  P2-a). Today such a row (old restore loop, `id` = the Hive key, not a uuid) is upserted as an `in_app_orphan` echo
  once it is older than the 5-minute text window. That is where the 162 live echoes come from. With the kill switch on,
  the C4 key would make those echoes KEYED, which the C5 echo-skip does not catch.
- A row whose key is in flight is skipped this pass; its server row may not exist yet (round 3 F8).
- The stamp re-reads the row right before its put and writes only `id` onto that fresh copy (no await between them).
  The push no longer writes back the copy it took before its network await, which could undo a restore's fill or
  re-create a deleted copy (round 3 F8).

C5. **Restore** (`_restoreCoachInteractions`, new path; the old loop is kept verbatim behind the kill switch
`configBox['disable_coach_client_key_restore']`, tracked for deletion after the device check on OI-503):
- `ownerChangedSince(userId)` before every put and delete; the pass stops at the first true.
- Cloud rows WITH a valid `client_key` are grouped by it. Each group picks ONE row: a complete one (non-empty
  `ai_response`, `model_used` not `pending`, and not `isRestoredHardFailureRow`) over an incomplete one, then the latest
  `created_at`. A retry is two cloud rows with one key, so it gives one local row.
- The target is the key itself. `ownerChangedSince` (a synchronous bool, `sync_service.dart:616`) is checked at the
  top of each iteration. Then ONE synchronous slice does the in-flight check, `coachBox.get(key)`, the decision and the
  `put(...)` call; the slice ENDS at that call expression, so its trailing `await` is outside it (round 4 F3, round 5
  P3-b; the `raiseTo` pattern; Hive 2.2.3 `put` begins its keystore transaction synchronously, verified in round 2 and
  round 5). The k23 source pin asserts no `await` between the in-flight check and the `put(` call.
  - **Absent**: write the row as today's restore does (same fields, `source: cloud_restore`, `mode` from
    `isRestoredMediaRow`, `had_hard_failure` from the helper), at the client's key, with `id` = the cloud uuid. Another
    device therefore gets the same key as the sending phone.
  - **Present, same turn** (the sending phone): this applies only when the local row's turn text equals the cloud row's.
    Both sides are trimmed, and for a media row a leading `[Photo]`, `[Photo: <x>]` or `[Video]` tag is stripped
    first (`coachTurnText`). Then `id` is stamped when the local `id` is not a UUID. The reply is filled ONLY when ALL of
    these hold:
    - the local row is incomplete (`failed`, `pending`, or an empty `ai_response`);
    - its key is NOT in `inFlightKeys`;
    - the picked cloud row is complete as above.
    Then `ai_response` and `model_used` are taken, `had_hard_failure` is set by the helper, and `pending` and `failed`
    become false. A row whose key is in flight is never touched beyond the id; the live send writes its own reply.
  - **A re-sent failed turn** (round 4 F1): a `failed` local row is NOT filled when a newer local row with the same
    turn text, not failed, exists within 60 s after it. The user has already re-sent that turn, and filling the failed
    row would show the same exchange twice. It keeps its error bubble and Retry, as today.
  - **Present, different text** (round 3 F2): the key is occupied by another turn. Two devices can mint the same ms, or
    a legacy copy can sit there. The local row is left alone, and the cloud row goes down the unkeyed path
    (`coach_<server ms>`). `created_at`, `mode`, `media_*`,
    `media_save_state` and `refunded` are never touched. Nothing is written when nothing changes.
- A stale copy goes: a `source: cloud_restore` row sitting at `coach_<that cloud row's created_at ms>` (a copy an
  earlier, pre-key build made of THIS row) whose key differs from the target, and whose `user_message` equals the
  row's, is deleted after the put (owner-checked). It is derived from that very row, never a guess.
- Only keys matching `^coach_[0-9]+$` are ever targeted, deleted or compared. `coach_memory` lives in the same box
  (round 3 F12).
- Cloud rows WITHOUT a key (every row before this batch, server-originated proactive rows, food analysis rows):
  today's loop, with two changes. (1) `id` = the cloud uuid instead of the Hive key. (2) A row whose `(user_message,
  created_at ms)` equals a KEYED row in the same fetch is skipped: it is a legacy echo of that keyed turn, and writing it
  would re-create the stale copy, whatever the input order (round 3 F3). The push then skips them instead of
  re-sending them as `in_app_orphan` echoes (162 such rows exist live across 18 test accounts, 90 of them same-instant
  echoes of a server row).

C6. **Rows already doubled** (the founder's 07:00 turn, test accounts only; the app is not live): no client matcher is
added. A device heals by signing out and back in. The fresh restore writes each pre-batch cloud row at
`coach_<created_at ms>`, and its same-instant orphan echo lands on the SAME key, so they collapse. Optional, with its own
founder go: one live DELETE of the `in_app_orphan` rows that equal a non-orphan row of the same user, text and
`created_at` (the 90), after a dry-run count. Server readers (rolling context, daily snapshot) then stop seeing those
turns twice.

C7. **Order** (round 3 F5). Each step needs its own founder go:
1. Migration 178 applied live, and the column verified (`information_schema.columns`).
2. `ai-proxy` and `ai-media-proxy` deployed (host-shell `emit_payload.js` / `deploy_via_api.js`; `deno check
   --node-modules-dir=none` first). Smoke-tested with a REAL user token: one chat turn and one photo turn, each row
   carrying `client_key` (the EF auth contract, CLAUDE.md 4.4 rule 9).
3. Merge; then the web deploy and the next build.

What each mixed state does:
- An old client against the new server sends no key: rows stay unkeyed, as today.
- A new client against an old Edge Function: the function ignores the extra field and no key is stored. A push later
  than 5 minutes can then write a keyed orphan next to the unkeyed server row, which shows twice (round 4 F4). So step 2
  is a HARD prerequisite of shipping any client build carrying C3/C4.
- Before the deploy from this branch: `git fetch origin main` and `git diff --name-only HEAD...origin/main --
  supabase/functions` must be empty, or `origin/main` is merged first (the 2026-09-28 near-miss rule in
  `supabase/functions/CLAUDE.md`). The deployed bundle must be byte-identical to what merges; any EF change after the
  deploy means a redeploy before the merge (round 5).
- A new client against a database without the column: the C4 fallback keeps the push working.
- Rollback runs in reverse: the client kill switch, then redeploy the previous EF versions, then `DROP COLUMN`. Never
  drop the column while a deployed EF still writes it. The kill switch gates the RESTORE only. Key emission (C3) and the
  push lookup (C4) stay on; both are harmless, because a stored key nobody reads changes nothing and the lookup falls
  back on a throw (round 4 F5).

**Tests T3**:
- `test/sync/coach_client_key_restore_test.dart` (SyncHarness, seam `restoreCoachInteractionsForTest`):
  - k1. A local complete row at key K and a cloud row with `client_key` K (17 s later) give one row; `id` stamped.
  - k2. A local `failed` row plus a complete cloud row give one completed row (`failed` false).
  - k3. A local `pending` row IN FLIGHT plus a complete cloud row: still pending, only `id` stamped.
  - k3b. The same row NOT in flight (an interrupted send): completed from the cloud.
  - k4. A complete local row plus a cloud `pending` placeholder: unchanged.
  - k5. A cloud row whose `ai_response` is the failure sentinel (`model_used 'failed'`) never fills a failed local row,
    and the row keeps Retry.
  - k6. Retry: two cloud rows with key K (one failed, one complete) give one local row with the complete reply.
  - k7. Another device: no row at K, so the row is written at K with `id` = uuid and `mode` from the recognizer
    (`[Photo: image]` gives media).
  - k8. Media: `media_save_state` and `refunded` on the local row survive.
  - k9. A stale `cloud_restore` copy at `coach_<ms>` for a keyed row is deleted; one with different text is kept.
  - k10. A row without a key is written at `coach_<ms>` with `id` = uuid.
  - k11. The owner changes mid-pass: nothing lands after the change.
  - k12. The kill switch set gives the old behaviour.
  - k13. A second pass changes nothing.
  - k14. A clear marker (OI-479) keeps a hidden local row hidden: its `created_at` is unchanged.
  - k15. Key K is occupied by a different-text incomplete row: it is neither stamped nor filled, and the cloud row is
    written at `coach_<server ms>`.
  - k16. A keyed row plus an unkeyed same-instant echo give one row, run in BOTH input orders.
  - k17. A complete local reply A and a complete cloud reply B leave A.
  - k18. The incomplete shapes, each filled when not in flight: `failed`; `pending`; an empty `ai_response` with
    neither flag.
  - k19. Two overlapping sends share K, and the first ends: K stays in flight until the second ends (the counter).
  - k20. A failed K1, its complete cloud row, and a newer non-failed K2 with the same text 20 s later: K1 is not filled.
  - k21. Media on the Present branch: a failed local `[Photo] cap` row plus a complete cloud `[Photo: image] cap` row:
    stamped and filled. The same for `[Video] cap`. Plus a unit test of `coachTurnText`.
  - k22. `coach_memory` and a `coach_<hex>` key in the same box are never targeted, deleted or compared.
  - k23. The in-flight slice: a source pin that the slice holds no `await`.
  - Pick tiers: complete over incomplete with the incomplete row LATER, the latest of two complete rows, and an equal
    `created_at`. k5 also covers apology text (`isRestoredHardFailureRow`), not only `model_used 'failed'`.
- `test/sync/coach_client_key_push_test.dart`:
  - p1. A keyed cloud row stamps the local row, and nothing is upserted.
  - p2. No keyed row: the text lookup runs as before.
  - p3. The orphan upsert carries `client_key`.
  - p4. The restore runs and then the push: no upsert of the restored row (round 3 F11).
  - p5. The key lookup throws: the text lookup still runs, and the orphan is upserted without `client_key`.
  - p6. An in-flight row is skipped.
  - p7. A restore fill that lands between the push's lookup and its stamp survives (the fresh read).
  - p8. A row deleted between the lookup and the stamp is not re-created (the fresh read is null, so no put).
  - p9. A `cloud_restore` row with a non-uuid `id` (the old loop, kill switch on) is neither looked up nor upserted.
  - p3 also: a `coach_<hex>` key upserts its orphan without `client_key`.
- `test/ai_coach/coach_client_key_request_test.dart`:
  - The key appears in BOTH transports (primary `callFunction` and the direct fallback) for chat, for the auth-retry
    body, and for media.
  - `predict` carries no key.
  - The key is in flight during the AI call and released after its last Hive write, on success, on a throw, on the
    auth-retry success path, on the Retry path (counted before the reset put), and on a throw in the code before the AI
    call.
- Through `ChatHistoryNotifier`, k1 renders one user bubble and one coach bubble, and `getTodayUserMessageCount` counts
  it once.
- Deno: `_shared/client_key_test.ts` (sanitize). Insert-field pins for the ai-proxy chat reservation and all three
  ai-media-proxy inserts. The chat dedup replay still inserts nothing. A malformed key gives a normal reservation.
- SQL (local docker, never prod): the column, the CHECK (a bad value is refused, NULL is allowed), the partial index,
  and an insert by `authenticated` under RLS with the column and with a NULL key.

Pins to repoint, not loosen:
- `test/sync/restore_keys_deterministic_test.dart:123`: an unkeyed row is still keyed by `millisecondsSinceEpoch`.
- `test/contracts/sync_coach_cross_channel_dedup_test.dart:91`: the text lookup is still there, now second.
- `test/contracts/coach_restored_media_mode_writer_to_reader_test.dart:143`: the mode recognizer is used on both paths.
- `test/contracts/coach_chat_clear_behavioral_test.dart:335`: the seam keeps its signature.
- `test/contracts/sync_service_public_api_snapshot_test.dart`.
- The Edge Function source pins that slice the ai-proxy chat reservation or the ai-media-proxy inserts (to be grepped
  before editing).

Accepted bounds (round 3 F7, F8):
- A turn sent by a build older than this one carries no key, so only a sign-out and sign-in collapses its doubles (C6).
- Two same-text turns within ai-proxy's 30 s chat dedup (possible only after a clear, which defeats the client's 60 s
  dedup) give one cloud row. The second local row has no cloud twin and disappears after a re-login.
- The restore reads at most 1000 rows ascending (existing behaviour), so the newest can be cut.
- An incremental restore (`created_at >= since`) never re-fetches a row whose reply was filled in later, so k3b (an
  interrupted send completed from the cloud) heals on a full restore only (round 5).
- Unkeyed restored rows now carry a uuid `id`, so the same-second sort tie-break at `coach_interaction_repository.dart:409`
  orders them arbitrarily within one second.

## 5. Fix D, remove the Home coach tip (founder decision)

- `home_provider.dart:694-698` and `:722-752`: delete `_getLatestCoachTip` and the `💡` append. `AiInsightNotifier.build`
  returns the schedule insight only. The card (`ai_insight_card.dart`) is unchanged.
- Test T4: with a coach reply today whose last sentence is 10 to 80 characters, the insight is exactly the schedule
  sentence (no `💡`). The pattern is `ai_insight_follows_today_row_test.dart`.
- Docs that name the tip (plus `lib/features/home/CLAUDE.md`, the AI insight wording; round 1 F15):
  - `coach_chat_clear.dart:24`
  - `lib/features/ai_coach/CLAUDE.md` (the `coach_chat_cleared_at` row)
  - `docs/sot_registry.yaml:6494` and the reader entry `:6660-6667` (removed)
  - `coach_chat_clear_behavioral_test.dart:303`: the test name and the list drop the Home tip. `home_provider.dart` no
    longer reads chat rows, so it leaves the list.

## 6. Registry, docs and board

- SoT: `coach_interactions` gains the restore match contract (writer `_restoreCoachInteractions`, keyed by
  `client_key`), and the R2/R3 readers get the helper; `behavioral_test_path` is T3 / T2. Ranges are
  re-derived from the code (not shifted) for every method this batch changes, and bare cites are checked against main's
  text (OI-262 lesson).
- `docs/naming_conventions.md`: `client_key` (cloud column and request field), `disable_coach_client_key_restore`,
  `coachTurnText`, `beginInFlight`/`endInFlight`/`isInFlight`, `sanitizeClientKey`, `chatClockLabel`, `isIsoOnIstDay`.
- `lib/core/services/CLAUDE.md` pitfall row "Restore writer keyed differently from production writer": add the
  server-written-row case. `docs/architecture/sync.md`: one bullet.
- Diagnose docs: OI-502 (time, today checks) and OI-503 (duplicate), full template (both are recurrence classes).
- Migration 178 (round 3 F10; round 4 F6): `SET lock_timeout = '5s'` in the file, `ADD COLUMN IF NOT EXISTS`,
  `CREATE INDEX IF NOT EXISTS`, and `RESET lock_timeout;` at the end (the `157_*.sql` pattern, round 5 P3-c). A blocked lock aborts instead of queueing behind traffic (the OI-473 hang).
  - minted with `scripts/mint_migration.sh`;
  - header per `supabase/migrations/CLAUDE.md`;
  - rehearsed in local docker only;
  - the live apply on the founder's go, then `backups/applied_migrations.json` and a regenerated
    `backups/live_schema_columns.json` (`check_schema_column_refs.dart`) in the same commit.
- Edge Functions: `deno check --node-modules-dir=none`, then the whole-tree Deno suite, then the
  `edge-function-deploy-rollback` skill (emit payload, byte-identical deploy, real-token smoke). The deployed versions are
  recorded in the diagnose doc, and the payloads archived the way PR #254 did for v101.
- Board: OI-502 and OI-503 stay OPEN for the founder's device check after merge (times read local; one bubble per turn
  after a reload; an already-doubled turn heals on the next launch).

## 7. Mutations planned (rule 21)

- `chatClockLabel` without `toLocal()`, R2/R3 back to `startsWith`, the helper as `startsWith`, the tip restored: done,
  all red (recorded in the diagnose doc).
- C5:
  - target = the derived key instead of `client_key`: k1 red.
  - the complete-over-incomplete pick reversed: k6 red.
  - the failure-sentinel check removed: k5 red.
  - the in-flight guard removed: k3 red; the fill limited to `failed` only: k3b red.
  - the fill removed: k2 red.
  - the stale-copy delete removed: k9 red, and its text check removed: k9 red.
  - `id` = Hive key on an unkeyed row: k10 and p4 red.
  - the owner guard removed: k11 red.
  - the kill switch read removed: k12 red.
- C5, the round-3 additions:
  - the text check on Present removed: k15 red;
  - the echo skip removed: k16 red;
  - the fill made unconditional: k17 red;
  - the counter changed to a set: k19 red;
  - the per-iteration owner check removed: k11 red.
- C4: the key lookup removed: p1 red. The orphan's `client_key` removed: p3 red. The throw no longer falling through: p5
  red. The in-flight skip removed: p6 red. The fresh read removed: p7 red.
- C3: the key dropped from the PRIMARY chat body: the request test red. The key not passed on the auth retry: red.
- C2: `sanitizeClientKey` returns the raw string: `client_key_test.ts` red. A field removed from one insert: its pin red.
- C1: the CHECK removed: the SQL case red.
- Round 4 additions: the re-sent-turn guard removed: k20 red. The tag stripping removed: k21 red. The key regex guard
  removed: k22 red. An `await` inserted into the slice: k23 red. `beginInFlight` moved after the Retry's reset put: the
  request test red. The push's null fresh-read check removed: p8 red.

## 8. Round 1 dispositions (2026-11-13)

All 17 were taken: F1 the channel filter; F2 the ai-proxy facts corrected; F3 the fresh read and the young-pending rule;
F4 the orphan echo rule and the uuid id; F5 the owner guard; F6/F7 the `:409` tie-break named and the re-push test; F8
the helper and in-flight safety; F9 visible-first; F10/F11 stated, plus extra T2 rows; F12 full paths and the seam; F13
the deterministic heal; F14 photo turns in scope; F15 home and ai_coach CLAUDE.md rows (section 5); F16 the switch's
tracking on OI-503; F17 the relaxed id precondition (rule 4).

## 9. Round 2 dispositions and the redesign (2026-11-13)

Round 2 reviewed rev 2 and found:
- F1 (P0): rule order made the heal unreachable, and legacy orphan echoes re-created the copy.
- F2 (P1): the stamped id is unordered and has no channel filter.
- F3 (P1): failure-sentinel rows counted as complete.
- F4 (P1): a stale snapshot for rows created mid-pass.
- F5 (P2): the 3-minute bound was false (cold-start retries, the auth retry, the direct-HTTP fallback).
- F6 (P2): a retry inside the window still doubled.
- F7 (P2): the tally of merged failed rows.
- F8 (P2): rule 1 has no text check.
- F9 (P2): reply equality and clock skew.
- F10 (P3): smaller gaps.

The founder chose a shared turn key (section 4 rev 3) over another round on the matcher. Disposition:
- F1, F2, F4, F6, F8 and F9 are removed with the matcher. There is no text or time match: the key is exact, a retry
  shares the key, a stamp is no longer read by the restore, and a row created mid-pass is the target key itself, read
  fresh before the put.
- F3 is taken: the failure sentinel never fills a row (k5).
- F5 is taken: no age heuristic. An explicit in-flight set decides (k3, k3b).
- F7 is taken: a fill only turns `failed` off for a non-failure reply, so the tally sees a normal turn.
- F10 is taken: the stale-copy delete checks the text; the time surfaces are confirmed.

## 10. Round 3 dispositions (rev 3.1, 2026-11-13)

Round 3, the first review of the shared-key design, found no P0. All twelve findings are taken:
- F1: all four request bodies are named; `predict` is excluded.
- F2: a text check on the Present branch; an occupied key falls back to the unkeyed path (k15).
- F3: the unkeyed echo skip (k16, both orders).
- F4: the in-flight counter, released after the last write (k19).
- F5: the deploy order, the mixed states, rollback, the push fallback on a missing column (p5), and a bad key dropped,
  never rejected.
- F6: the paywall helpers get the key as a parameter.
- F7: the channels that carry a key, and the 30 s dedup bound.
- F8: the fresh read in the push (p7), the in-flight skip (p6), and the fetch-window and tie-break bounds.
- F9: the reset, `_onUserChanged`, and the layering note.
- F10: the ledger, schema snapshot, docker rehearsal and deploy steps.
- F11: tests k17, k18, the pick tiers, p4 through the restore, both transports.
- F12: the key regex.

## 11. Round 4 dispositions (rev 3.2, 2026-11-13)

Round 4 was the second review of the shared-key design. It found no P0 and no P1; it confirmed the design and every C4
and C5 mutation except those it named. Taken:
- F1: the re-sent-turn guard (k20).
- F2: the exact `beginInFlight` points and the `try`/`finally` span.
- F3: the synchronous slice and its pin (k23).
- F4: the EF deploy as a hard prerequisite, and the deploy-from-branch diff check.
- F5: the kill switch's scope stated.
- F6: `lock_timeout` and `IF NOT EXISTS`; tests k21, k22 and p8.

## 12. Round 5 dispositions (rev 3.3, 2026-11-13): CONVERGED

Round 5 checked the rev 3.2 fold-ins against the code. No P0, no P1; verdict converged. Taken inline:
- P2-a: `cloud_restore` rows are never pushed (C4), test p9.
- P3-a: the Retry branch opens its `try` at `beginInFlight`, before the reset put; `endInFlight` never goes negative.
- P3-b: `ownerChangedSince` is synchronous; the slice ends at the `put(` call, and the k23 pin is defined that way.
- P3-c: `RESET lock_timeout`.
- P3-d: `client_key` only for a key matching the CHECK regex.
- The k11 mutation wording, the incremental-restore bound and the byte-identical-bundle line.
Rounds 3, 4 and 5 found no P0; rounds 4 and 5 found no P1. The plan is executed as rev 3.3.
