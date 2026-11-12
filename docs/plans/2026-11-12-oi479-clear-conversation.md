# OI-479: AI Coach "Clear conversation" (plan)

- **OI:** OI-479 (`docs/audit/open_issues.md`). Branch / worktree `oi479-clear-conversation`.
- **Tier:** L (sync + schema + AI coach). Blast radius `account`. Full x2 plan review, B-pass, diagnose doc.
- **Execution mode (decided at batch start, §4.12.7):** inline, one worktree, one coordinator. No subagent implementation units.
- **Status:** CONVERGED after three review rounds (12 + 12 + 9 findings, all taken; §8-§10). Round 3 found no P0 and no mechanism change: its one P1 is where `_teardown` gets the uid.

## 1. The defect

`lib/features/ai_coach/screens/ai_coach/compact_header.dart:130-132`: `case 'clear': ref.invalidate(chatHistoryProvider);`. `ChatHistoryNotifier.build` (`ai_coach_provider.dart:170-`) re-reads every row of `coachBox`, so the thread comes back unchanged. Nothing in `lib/` clears chat rows except the whole-account wipe (`user_repository.dart:1212`).

## 2. Founder decisions (2026-11-12, in chat)

| # | Decision |
|---|---|
| D1 | Clear = HIDE, never delete. No local or cloud chat row is removed or modified. |
| D2 | The coach's short-term memory (the `history` replay) starts fresh after a clear. Long-term memory (`coach_memory`, coaching notes) is kept. |
| D3 | Today's unresolved "X of Y - Complete workout" tile stays visible after a clear; once the day is completed it goes, as today. |
| D4 | The clear time is synced to the cloud so a restore / reinstall / second device does not bring the old thread back. |
| D5 | Semantic retrieval (`memory_embeddings` -> `match_memories`, up to 5 dated snippets injected by `ai-proxy`) is KEPT. No Edge Function change. |

Why delete is wrong (recorded for reviewers): cloud `ai_coach_interactions` rows are read by `daily-snapshot` (coach memory extraction), `weekly-report`, `evaluate-rank-promotions`, `morning-alert`, `rolling-context`, `proactive-coach-promotion`, `ai-proxy` dedup and `delete-account`; a local-only delete is undone by `_restoreCoachInteractions` (`sync_coach.dart:278`, `since = 2020-01-01`, every row).

Coordinator calls made under D1-D5 (the founder can overturn; none blocks the build):
- **C1 Home coach tip unchanged.** `_getLatestCoachTip` (`home_provider.dart:724-750`) shows a sentence of today's latest reply on Home. It is a Home card, not the conversation; it stays. Reported to the founder 2026-11-12.
- **C2 Pending action cards survive a clear** (same reasoning as D3: they are actions, not conversation). `chat_area.dart:17-45` renders `pendingLogActionsProvider`, `workoutDraftProvider`, `pendingToolIntentsProvider` cards from provider state, not coachBox rows. A clear does not dismiss them: dropping a `LogConfirmCard` mid-countdown or an un-APPLIED intent would silently lose a log the user asked for.

## 3. Mechanism: one marker, `coach_chat_cleared_at`

An instant, stored as a UTC ISO-8601 string with `Z`. A chat row whose `created_at` instant is at or before the marker is hidden from the thread, from the history replay and from the client dedup scan. Nothing else reads it.

### 3.1 Writer (the ONE writer of the local marker, plus the restore adoption)

New `CoachChatClear` (`lib/features/ai_coach/services/coach_chat_clear.dart`):

`clear()`:
1. Owner guard: capture `HiveUserSession.currentOwnerFullId` as the first statement; abort when null.
2. `at = DateTime.now().toUtc()`. New value = max(stored marker, `at`), so a marker never moves backwards.
3. `ownerChangedSince(owner)` re-checked at the sink, then, with NO await between reading the stored marker, computing the max and the `put` (round-3 F2: otherwise `clear()` and the restore adoption can interleave and lower the marker), `userBox['coach_chat_cleared_at'] = value.toIso8601String()`. `userBox` is opened per user by `HiveUserSession.openForUser` (to be confirmed in code at implementation; if it is NOT per-user, the key goes into a per-user box instead and this plan is re-reviewed).
4. The caller invalidates `chatHistoryProvider` after the await.
5. `unawaited(SyncService.instance.pushCoachChatClearedAt(owner))` (§3.3).

`clearedAt()` -> `DateTime?`: parses the stored value; absent, unparseable, or a throwing box read -> null (nothing hidden; fail open, round-2 F10). Each reader reads it ONCE per call, never per row. NO read-time clamp: clamping a future marker to `now` at read time would hide every row up to now, including rows written after the clear (round-1 F2). Future values are prevented at the two sinks instead: `clear()` writes the device's now; the restore adoption (§3.3) caps the adopted cloud value at the device's now.

**Clock skew (accepted, documented; round-1 F3).** Local rows are stamped by the device clock; cloud rows (and so restored rows on another device) carry the server's `created_at`. A row sent within the skew of the clear can land on the other side of the marker on another device or after a restore. The window is the clock skew (normally seconds). The RPC clamps the cloud value to the server's now, and the adoption caps it at the device's now, so a fast device clock can never hide future messages for longer than its own skew.

### 3.2 Readers

| Reader | File:line | Change |
|---|---|---|
| Chat thread | `ChatHistoryNotifier.build`, `ai_coach_provider.dart:170-` | Skip a row whose `created_at` instant is `<=` the marker. Exception (D3): an UNRESOLVED `completion_prompt` row for IST today is always kept (the existing resolved / past-day filters at `:186-203` still apply first). A row with no or unparseable `created_at` while a marker exists is hidden (every real writer stamps one: `saveInteraction` / `saveUserMessagePending` stamp `DateTime.now().toUtc().toIso8601String()`, `CompletionPromptStore.write` stamps UTC `Z`, the restore copies the cloud value). Comparison by INSTANT (`DateTime.tryParse(..)!.toUtc()`), never string compare. The synthetic welcome message added when the list is empty (`:342`) still appears, so a cleared chat shows the welcome state and the quick prompts (`screen.dart:453`, `messages.length <= 1`). With a kept D3 tile the list holds the tile, so neither the welcome bubble nor the quick prompts show; accepted (the tile is the one thing to act on), asserted in T1/T8 (round-2 F12). |
| History replay | `CoachInteractionRepository.recentHistoryExchanges`, `coach_interaction_repository.dart:360-` | Same instant filter before taking the last N exchanges (D2). |
| Client dedup scan | `_findRecentDuplicateMessageKey`, `coach_interaction_repository.dart:167-196` (called by `saveUserMessagePending`, `:100-110`) | Skip rows at or before the marker. Without this, "hi" -> clear -> "hi" within 60 s reuses the hidden row and the new question and reply never show (round-1 F1). |

All three call one pure helper, `isHiddenByClear(Map row, DateTime? marker)`, plus the D3 exception only in the thread reader.

Readers deliberately UNCHANGED (each named so a reviewer can check it):

| Reader | File:line | Why unchanged |
|---|---|---|
| Daily message count | `getTodayUserMessageCount`, `coach_interaction_repository.dart:262`; `MessageLimitNotifier`, `ai_coach_provider.dart:520-` | The limit is server-enforced (`usage_counters`); a clear must never give extra messages. |
| First-ever-message flag | `ai_snapshot_builder.dart:75` | A cleared chat is not a first conversation; flipping it would re-run first-contact behaviour. |
| Coaching-notes extraction | `coach_memory_service.dart:85` | Long-term memory (D2). |
| Home coach tip | `home_provider.dart:724-750` | C1. |
| Badge "chatted with AI" | `badge_service.dart:160` | Lifetime fact. |
| Retry of a failed row | `ai_coach_provider.dart:876` | Keyed by row; a hidden failed row has no visible Retry button. |
| `getLatestInsight` | `coach_interaction_repository.dart:413` | No callers in `lib/`. |
| Cloud readers + semantic retrieval + `ai-proxy` server dedup | Edge Functions listed in §2 | D1, D5. The server dedup (`ai-proxy/index.ts` ~406-424) answers a repeat within 30 s from the cached row; the client writes that answer into its NEW row (F1 fix), so the user sees it. |

### 3.3 Cloud sync

- **Schema:** `user_preferences.coach_chat_cleared_at timestamptz NULL` (new column; number minted with `sh scripts/mint_migration.sh <slug>`).
- **RPC** `public.raise_coach_chat_cleared_at(p_at timestamptz) RETURNS void`, mirroring migration 123's `merge_notification_preferences`:
  - `LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp` (123's form).
  - `IF p_at IS NULL THEN RAISE EXCEPTION ...` (round-1 F4: `LEAST(NULL, now())` is `now()`, which would hide the whole thread everywhere). Also `IF auth.uid() IS NULL THEN RAISE`.
  - `INSERT INTO public.user_preferences AS up (user_id, coach_chat_cleared_at) VALUES (auth.uid(), LEAST(p_at, now())) ON CONFLICT (user_id) DO UPDATE SET coach_chat_cleared_at = GREATEST(up.coach_chat_cleared_at, LEAST(p_at, now())), updated_at = now()` (GREATEST ignores a NULL existing value; monotonic; future client clock clamped to the server's now; `updated_at` as 123 does, round-2 F11). `ON CONFLICT (user_id)` matches `user_preferences_user_id_unique` (`001_create_users.sql:95`); every NOT NULL column other than `user_id` has a default, so the two-column INSERT is valid (round 2, verified).
  - `REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon; GRANT EXECUTE ... TO authenticated`.
  - RLS: `user_preferences` has own-row select / insert / update-with-check policies (migrations 001, 055, 100; verified by review round 1), so the invoker upsert works.
- **Client push** `SyncService.pushCoachChatClearedAt(userId)` in `sync_profile.dart`:
  - Reads the local marker; none -> return. Skips when `userBox['coach_chat_cleared_at_pushed']` equals `'<marker>|<IST today>'` (bounded by IST day like `_pushStreakWeekMarker`, `sync_profile.dart:645-659`, so a lost or out-of-band-nulled cloud value heals within a day; round-1 F10).
  - `ensureFreshToken()`, `ownerChangedSince(userId)` re-checked before the RPC and before writing the pushed-memory.
  - Its OWN `try/catch`; failure -> `_reportSyncFailure(opType: 'upsert_coach_chat_cleared_at', error: e)`, EXCEPT with `fromSignOut: true`, where a failure is only `ErrorTelemetry.logEvent('coach_chat_cleared_at_push_failed', ...)` and the pushed-memory is not written: a timed-out sign-out push keeps running after `clearAllData` (`.timeout` abandons, it does not cancel), and `_reportSyncFailure` would set `sync_sweep_owed` in the shared `syncBox` and arm `SyncRetryController` for the NEXT user (round-3 F5). `ensureFreshToken()` returns null with no session and may start a refresh bounded by `refreshTimeout` that outlives the 2 s (accepted; round-3 F6). The `upsert_` prefix makes `isPushFailureOpType` (`sync_retry_controller.dart:120-`) true, so an outage-shaped failure arms the sweep; NOT added to `kNotSweptOpTypes` (`:101`) because the sweep (`weeklyFullSync`, `sync_service.dart:1342`) re-sends it through `_syncUserPreferences`. The forcing-function test (`test/contracts/sync_retry_controller_test.dart:541-588`) greps `opType:\s*'([a-z0-9_]+)'` across `lib/`: the call is written on ONE line as `opType: 'upsert_coach_chat_cleared_at'` and the literal joins the test's `armed` set (`:543-550`) (round-1 F7, round-2 F4).
  - **Sign-out flush (round-2 F2).** `AuthNotifier._teardown` (`auth_provider.dart:1009-`) wipes `userBox` (`clearAllData`, `user_repository.dart:1208`) with no push first, so an unpushed marker is lost and the next sign-in restores the old thread from 2020. New first step of `_teardown`, before `clearAllData`: `final uid = _supabase.currentUser?.id;` read INSIDE `_teardown` (its signature `Future<void> _teardown()` stays: `profile_signout_routes_through_auth_notifier_test.dart:102` and `signout_unbinds_sdk_identity_test.dart:164` slice on that exact text; round-3 F1), and when non-null `await SyncService.instance.pushCoachChatClearedAt(uid, fromSignOut: true).timeout(const Duration(seconds: 2))` inside its own `try/catch` (best effort; the whole teardown is already bounded by `signOutTimeout`). Only `_teardown` flushes: the other `clearAllData` callers (`main.dart:77,171`, `restoring_screen.dart:372`, `_ensureLocalUser` `auth_provider.dart:1156`) run with no session or with the NEW user already signed in, where the old user's marker cannot be pushed under the right identity (`ownerChangedSince` would refuse), and account deletion removes the cloud data itself (round-3 F7). The remaining loss (cleared offline, signed out before reconnecting) is the OI-253 class (a userBox queue lost at sign-out; fix needs a durable cross-session queue); recorded on OI-253 as a second instance in this batch's board edit.
  - Called from `clear()` and from `_syncUserPreferences` as a SEPARATE statement after that method's existing `try/catch`, unconditionally (not behind `payload.length > 1`), so an upsert or notification-RPC failure never skips it and its failure is never reported under `upsert_user_preferences` (round-1 F6). Cadence: `_syncUserPreferences` runs from `weeklyFullSync`, the profile sync domain and `NotificationPrefsRepository` (`:254`); a push lost offline waits for the next of those or the armed sweep.
- **Restore** `_restoreUserPreferences` (`sync_profile.dart:1083-`):
  - `cloud.remove('coach_chat_cleared_at')` BEFORE the generic merge (as `notification_preferences` at `:1105`), so the column never lands in `userBox['preferences']`.
  - The adoption is its OWN block placed after the existing `userBox.put('preferences')` and `adoptFromCloud` awaits, and it starts with a FRESH `if (ownerChangedSince(userId)) return;` (round-2 F1: an A -> B swap inside either existing await would otherwise write A's marker into B's `userBox`; the existing guard comment at `:1119-1131` says the check belongs one statement before the write). Then, with no await in between: read the LOCAL marker (at the sink, never at method entry; round-1 F9), compute `max(local, min(cloud, deviceNow))` as parsed UTC instants (Postgres returns `+00:00` with microseconds, the local value is `Z`; a string compare would rewrite every launch; round-2 F10), and write only when the instant differs.
  - Reach: `restoreLightweightAlways` (`sync_service.dart:1659-`) restores `user_preferences` on every returning-user launch; the restore-complete tick invalidates `chatHistoryProvider` (`screen.dart:200-205`). A clear on device A hides the thread on B at B's next launch. Not live while B is open (accepted).
  - The `restore-user-snapshot` EF selects `*` (`restore-user-snapshot/index.ts:165-167`) and hands the row to the same method (`sync_service.dart:2338`): no EF change.

### 3.4 UI

- `compact_header.dart`: `case 'clear'` opens a confirmation dialog (Wardroom primitives, DM Sans, palette; copy checked against `lib/shared/widgets/wardroom/CLAUDE.md`). Draft copy: title "Clear this chat?"; body "Messages leave this screen. Your coach still remembers your goals, injuries and preferences."; actions CANCEL / CLEAR. CLEAR -> `if (ref.read(sendMessageProvider)) return;` (round-2 F6: a send can start while the dialog is open, e.g. a retry tap or the photo upload finishing into `sendWithMedia` at `media_picker.dart:~285`; its pre-clear `pending` row would receive the reply by key through `updateInteractionWithResponse`, `coach_interaction_repository.dart:202`, and vanish), then `CoachChatClear.clear()`, then `ref.invalidate(chatHistoryProvider)`.
- The item is disabled while a send is in flight: `_buildCompactHeader` gains `ref.watch(sendMessageProvider)` (a `Notifier<bool>`, true during `send` (`ai_coach_provider.dart:841`) AND `sendWithMedia` (`:626`)), passed as a new `coachHeaderMenuItems(isPro:, isSending:)` parameter. The two pins in `test/contracts/telegram_surface_removed_test.dart` are REPOINTED, not loosened: `:124` (the test's own call) and `:373` (the exact `itemBuilder:(context)=>coachHeaderMenuItems(isPro:isPro),` count 1) become the new call shape with count 1; `:386` (`case'clear':` count 1) holds as is (round-1 F5). Other pins that must still hold (round-2 F8): `telegram_surface_removed_test.dart:405` (`_buildCompactHeader(isPro),` in `screen.dart`: the signature is NOT changed, the header reads `sendMessageProvider` itself); `chat_limit_part_b_client_test.dart:226,241` (`feature: Higher daily AI coach limit` stays; no quoted string in the dialog may contain "unlimited"); `tab_header_no_clip_test.dart:15` (`BoxFit.scaleDown` stays); `user_preferences_coaching_notes_writer_to_reader_test.dart:93` (the first 1,200 chars after `_restoreUserPreferences(String userId` keep `.from('user_preferences')` and `.select()`: new code goes after that window); `progress_restore_freeze_merge_behavioral_test.dart:821` and `sync_queue_progress_marker_test.dart:190` slice up to those method names (the latter counts `if (fromQueue) {` == 3): the new push method is placed AFTER `_restoreUserPreferences`, outside both slices. Grep `test/` again for every literal on the edited lines before each edit (CLAUDE.md §4.9 extraction row).

## 4. Tests (behavioural first; each NEW protection mutated once, §4.4 rule 21)

| # | Test | Asserts | Mutation that must redden it |
|---|---|---|---|
| T1 | `test/contracts/coach_chat_clear_behavioral_test.dart` (real Hive) | Rows before the marker hidden, after shown; `Z` and no-offset `created_at` compared as instants; missing / unparseable `created_at` hidden; today's unresolved prompt kept, resolved prompt hidden, past-day prompt hidden; welcome message shown on a fully cleared chat. | drop the filter in `build`; flip `<=` to `<`; string compare in place of instants; remove the D3 exception. |
| T2 | same file | `recentHistoryExchanges` excludes pre-marker exchanges, keeps post-marker ones in order. | drop the filter in the replay. |
| T3 | same file | "hi" -> clear -> "hi" within 60 s mints a NEW row that the thread shows. | drop the filter in `_findRecentDuplicateMessageKey`. |
| T4 | same file | `getTodayUserMessageCount` and `is_first_ever_message` unchanged by a clear. | ADD the marker filter to those two readers (a pin for "unchanged"). |
| T5 | same file | A restore that re-puts old `ai_coach_interactions` rows (`_restoreCoachInteractions` preFetched seam) keeps them hidden. | drop the thread filter. |
| T6 | `test/sync/coach_chat_cleared_at_restore_test.dart` | `_restoreUserPreferences`: newer cloud raises the local marker; older cloud never lowers it; a cloud value later than device now is capped; the column never lands in `userBox['preferences']`; owner change between fetch and sink writes nothing; a clear made DURING the fetch survives (driven through the NETWORK path, not `preFetched`, which has no await before the sink; round-2 F5. Seam: `test/helpers/sync_stub_server.dart`, real client pointed at the stub as in `streak_week_marker_push_behavioral_test.dart`; `getResponders` is synchronous, so the `user_preferences` GET responder performs the local clear itself while the request is in flight; round-3 F3); an owner swap during the `userBox.put('preferences')` await writes no marker into the new owner's box (flipped with `debugCurrentUidResolverForTests`, `sync_service.dart:638`; round-2 F1). | read local at entry; remove the `cloud.remove`; drop the cap; drop the max; drop the fresh owner check. |
| T7 | same file | Push: `clear()` calls the RPC with the marker; no RPC when the pushed-memory matches today; a failure reports `upsert_coach_chat_cleared_at`; `_syncUserPreferences` pushes even when its upsert throws; a hanging RPC (a delayed `rpcResponders` reply) is abandoned by the 2 s bound; with `fromSignOut: true` a failure reports no sync failure and writes no memory; a source-slice pin (inside the existing `_teardown` slice, end anchor `\n  /// OI-51` kept) that the push precedes `clearAllData` (`_teardown` is private and has no behavioural harness; round-3 F4). | put the push back inside the existing try; drop the memory check; report a sync failure from sign-out; move the teardown push after the wipe (reddens the slice pin only). |
| T8 | `test/ai_coach/clear_conversation_menu_test.dart` (widget) | Menu -> dialog; CANCEL changes nothing; CLEAR hides the thread (`messages.length <= 1`, the screen's empty test at `screen.dart:453`); the item is disabled while `sendMessageProvider` is true; a send starting while the dialog is open makes CLEAR a no-op; pending action cards survive (C2); with a kept D3 tile the thread shows only the tile. | skip the dialog; ignore `isSending`; drop the CLEAR re-check. |
| T9 | `test/contracts/coach_chat_cleared_at_migration_text_test.dart` (precedent `streak_week_marker_migration_text_test.dart`) | The migration text holds: `SECURITY INVOKER`, the `search_path`, the NULL guard, `GREATEST`, `LEAST(p_at, now())`, the REVOKE and GRANT lines, the column type. | delete each clause in turn. |
| T10 | SQL rehearsal in the local docker postgres (`feedback_rehearse_sql_in_local_docker_not_prod`), recorded in the diagnose doc | GREATEST monotonic; future `p_at` clamped; NULL `p_at` raises; anon cannot execute; user A cannot touch user B's row; row created when absent. | the T9 clauses, run live in docker. |

## 5. Docs / registry in the same change

- Diagnose doc `docs/diagnoses/2026-11-12-coach-clear-conversation-noop-<6hex>.md` (full template; writer/reader file:line as above; `touched_layers_checked`; T10 evidence; the mutation results).
- `docs/sot_registry.yaml`: new concept `coach_chat_cleared_at` (writer `CoachChatClear.clear` + the restore adoption; readers the three in §3.2; `behavioral_test_path` T1 / T6). Every EXISTING entry whose line range points into a file this batch edits (`sync_profile.dart`, `coach_interaction_repository.dart`, `ai_coach_provider.dart`, `compact_header.dart`, `auth_provider.dart`) is recomputed from its anchor on the final state of each commit (memory `feedback_registry_range_shift_measured_on_wrong_state`; round-2 F3).
- `docs/audit/open_issues.md`: OI-253 gains the second instance (an unpushed `coach_chat_cleared_at` cleared offline and signed out before reconnecting).
- `docs/naming_conventions.md`: the Hive keys (`coach_chat_cleared_at`, `coach_chat_cleared_at_pushed`), the column, the RPC, the opType.
- `lib/features/ai_coach/CLAUDE.md`: SoT row + the menu sentence; `lib/core/services/CLAUDE.md` only if a contract row there changes.
- `backups/live_schema_columns.json` regenerated; `backups/applied_migrations.json` after the live apply.
- `docs/architecture/sync.md`: the marker in the restore-merge list (max-wins, capped).
- OI-479 closed in the landing commit (`closes-oi:`), moved to `closed_issues.md`.

## 6. Live steps (each needs the founder's explicit go)

1. Apply the migration to `dedsavbjuwgarrhphgnl` after the docker rehearsal and before the merge (`feedback_live_change_then_merge_ordering`): a build that calls the RPC before it exists gets a failed push (reported, retried by the sweep) while the local hide still works, so the order matters only for noise, not data.
2. No Edge Function deploy.

## 7. Out of scope

- Deleting any chat data (D1). A future "delete my chat history" (DPDP-style) would be its own feature.
- Live cross-device hide while both devices are open.
- Hiding past conversations from semantic retrieval (D5).

## 8. Review round 1 (2026-11-12, fresh Sonnet reviewer) — dispositions

| F | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | Client dedup reuses a hidden row | Taken: §3.2 third reader, T3. Verified at `coach_interaction_repository.dart:100-110,167-196`. |
| 2 | P1 | Read-time clamp hides post-clear rows | Taken: read clamp removed; caps at the two sinks (§3.1). |
| 3 | P2 | Client vs server clock skew | Taken: documented as accepted, bounded by the sink caps (§3.1). |
| 4 | P2 | NULL `p_at` | Taken: NULL guard + `auth.uid()` guard; aliased upsert; 123's `search_path` form (§3.3), T9/T10. |
| 5 | P2 | Menu pins | Taken: repoint `:124`, `:373` (§3.4). Verified at `telegram_surface_removed_test.dart:124,373`. |
| 6 | P2 | Push inside the preferences try | Taken: own try, unconditional, after the existing one (§3.3), T7. |
| 7 | P2 | opType classification | Taken: `upsert_coach_chat_cleared_at` (swept push), enumerating test updated (§3.3). |
| 8 | P2 | Pending cards / empty state | Taken: C2 keeps cards; empty test is `messages.length <= 1` (§3.2, T8). |
| 9 | P3 | Local read point in restore | Taken: read at the sink, mutant in T6. |
| 10 | P3 | Pushed-memory forever | Taken: bounded by IST day. |
| 11 | P2 | T8 SQL not committed; T3 pin-only | Taken: T9 migration-text test; T4 mutation is "add the filter". |
| 12 | P3 | Home tip / `getLatestInsight` | Taken: C1; `getLatestInsight` listed as no-caller. |

## 9. Review round 2 (2026-11-12, fresh Sonnet reviewer) — dispositions

| F | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | Restore marker write after two awaits without a fresh owner check | Taken: own block with a fresh `ownerChangedSince` (§3.3), T6 swap case. Verified at `sync_profile.dart:1119-1162`. |
| 2 | P2 | Unpushed marker wiped at sign-out | Taken: 2 s best-effort push first in `_teardown` (verified `auth_provider.dart:1009-1026` pushes nothing today); offline residue recorded on OI-253 (same class). |
| 3 | P2 | Registry ranges shift | Taken: §5 recompute step. |
| 4 | P2 | Forcing-function literal | Taken: one-line call, `armed` set (§3.3). |
| 5 | P2 | T6 mutant unkillable via preFetched | Taken: network path with a delayed stub. |
| 6 | P2 | Send can start while the dialog is open | Taken: CLEAR re-checks `sendMessageProvider` (§3.4), T8. |
| 7 | P3 | Retry / photo paths safe | Confirms the plan. |
| 8 | P3 | Pins to keep | Taken: listed in §3.4. |
| 9 | P3 | Gates for `.rpc` / nullable column | No change needed; the gate loop will confirm. |
| 10 | P3 | Instant compare, read once, fail open | Taken (§3.1, §3.3). |
| 11 | P3 | `updated_at` in the RPC | Taken. |
| 12 | P3 | Welcome hidden with a kept tile | Taken: accepted and asserted (§3.2, T1/T8). |

## 10. Review round 3 (2026-11-12, fresh Sonnet reviewer) — dispositions

| F | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | P1 | `_teardown` has no uid parameter; two tests slice on its signature | Taken: uid read inside `_teardown`, signature unchanged. Verified at `profile_signout_routes_through_auth_notifier_test.dart:102`, `signout_unbinds_sdk_identity_test.dart:164`. |
| 2 | P2 | `clear()` read-max-write must not await in between | Taken (§3.1 step 3). |
| 3 | P2 | No delaying stub client | Taken: GET responder performs the clear; `debugCurrentUidResolverForTests` for the swap (T6). |
| 4 | P2 | No harness for `_teardown` | Taken: behavioural test of the push + source-slice pin (T7). |
| 5 | P2 | Timed-out sign-out push arms the next user's sweep | Taken: `fromSignOut` logs only, no memory write (§3.3). |
| 6 | P3 | `ensureFreshToken` during sign-out | Accepted and noted. |
| 7 | P3 | Other wipe paths need no flush | Taken: stated with reasons. |
| 8 | P3 | `_reportSyncFailure` signature | Confirms the plan. |
| 9 | P3 | Pins tolerate the change; teardown gate scans staged tests | Noted for implementation. |
