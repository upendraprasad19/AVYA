---
reviewed_at: 2026-11-11T18:45:00+05:30
staged_against: b635fc97 (branch coach-workout-parity-tile; commit A 3c500fc0 and the staged commit B)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh context-blind seats, S1 server + gate, S2 client)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
verdict_note: no P0 or P1; nine P2. Six are fixed in commit B with mutation-proven tests. S2-F3 led to a pre-existing chat bug on the log_set APPLY path, fixed as its own commit C (diagnose 3e7b41), which closes the tile path's narrow race too; a third seat reviewed commit C and its two P2 are fixed in C.
---

# Code Review: coach workout parity S3, the completion tile tool (OI-492)

Scope: "I'm done" in chat makes the app's own "X of Y - Complete workout" tile appear, one tap total. The server tool `requestCompletionTile` (FREE, capability `request_completion_tile`) is never queued inside a tool-loop round: a call is recorded, and ONE auto-run intent is pushed after the loop unless a `log_set` intent was queued in the turn. The client runs the intent at once (`kAutoRunIntentTypes`), never shows a card, and re-runs its own `decideCoachDay` through `CoachDayCompletion.offerTileIfPartial`, which re-shows the tile row (`reshow: true`, fresh UTC `created_at`) only for a part-logged IST today. The coach never completes a day (ADR-0012 amendment). Also: the kill switch `DISABLE_COMPLETION_TILE_TOOL`, the coverage gate failing closed on a non-literal `requiresCapability`, and commit A's UTC `created_at` fix (diagnose f3d704). Plan: `docs/plans/coach-workout-parity-2-server.md` (S3 text, rev 13 converged after 7 rounds; rev 14 = as built after this review).

Each seat got the diff, the 8 lenses, an exhaustive command list (read-only git, file reads, named test files, `dart analyze` / `deno check` per file, mutation of its own slice under a backup / sha256 restore protocol) and a ban on scripts, the `supabase` CLI, network tools and any database statement. S1 covered `supabase/functions/**` (tool, tool loop, routing, `ai-proxy/index.ts`, the Deno tests) and the coverage gate. S2 covered the client (`tool_dispatcher.dart`, `coach_day_completion.dart`, `pending_tool_intents_provider.dart`, `screen.dart`, `completion_prompt_store.dart`, the capability list) and the Dart tests.

Before dispatch, the gate loop was green:
- whole-project `flutter analyze --no-fatal-infos`: 0 warnings;
- `deno check --node-modules-dir=none` on `ai-proxy/index.ts`; the Deno tile tests;
- the pre-commit gate loop (`PRE_COMMIT_GATE_JOBS=1`) on the staged commit B;
- about 45 mutants, all red except M59b (green by design in the tile file, red in commit A's test).

The full Flutter suite (`TZ=Asia/Kolkata`, golden excluded) ran during the review: 14,099 passed, 15 skipped, exit 0.

## Finding 1 — P2 — guard_without_its_mirror (S1)
- **file:line:** supabase/functions/_shared/tool-loop.ts (the tile branch; `responseHasTileSurfacingWrite`)
- **claim:** The same-response drop keyed on the `logSet` NAME. A response with `[logSet, requestCompletionTile]` where the `logSet` fails Zod validation queued no `log_set` intent, yet the tile was dropped as `not_needed` and the model was told "the logged sets will show the tile". The user got no card and no tile. S1 probed it: no intent at all.
- **verification:** Deno case "(iii) same response [...] with an INVALID logSet".
- **fix:** A tile call is `not_needed` at the call only when a `log_set` intent is ALREADY queued. Otherwise it is recorded (`tile_requested`) and the post-loop `tileWillPush()` decides from the real intents. A tile call in a response that also calls `logSet` gets `COMPLETION_TILE_SAME_RESPONSE_NOTE`, which covers both outcomes. Tests: the two invalid-`logSet` orders push the tile; the valid orders keep one `log_set` intent and a `not_needed` record, with the note the model actually read pinned per order. Mutants S1 to S4 red.
- **status:** fixed

## Finding 2 — P2 — function_exception_swallow (S1)
- **file:line:** supabase/functions/_shared/tool-loop.ts (the post-loop push `catch`)
- **claim:** The path where the tile intent builder throws was untested: a regression could drop the catch (the whole reply fails) or leave the records `tile_requested` with no intent.
- **fix:** A Deno test swaps the registry tool's `intentBuilder` (the registry holds the same object) for a throwing one: no tile intent, every tile record `failed` with the error, no hard failure. Restored in `finally`. Mutants S5 (catch stops marking) and S6 (catch rethrows) red. No test seam was added to `tool-loop.ts`.
- **status:** fixed

## Finding 3 — P2 — guard_without_its_mirror (S1)
- **file:line:** scripts/ai_tool_dispatcher_coverage_lib.dart (`capMatch`)
- **claim:** The literal regex ran on the raw source while the declaration check ran on the comment-stripped source. A commented-out literal next to a live identifier (`// requiresCapability: "x",` above `requiresCapability: CAPABILITY_X,`) was read as the declaration, so the gate failed OPEN.
- **fix:** Both checks read `stripTsComments(content)`. New case for a line and a block comment. Mutants S7 and S8 red; the real-tree gate passes (15 write tools). Ledger evidence appended.
- **status:** fixed

## Finding 4 — P2 — guard_without_its_mirror (S2)
- **file:line:** lib/features/ai_coach/services/tool_dispatcher.dart (`_executeRequestCompletionTile`, owner null)
- **claim:** The owner-null early return (signed out mid-turn) was unpinned: removing it would run the decision with no owner.
- **fix:** Test "no owner: success with ownerChanged, nothing written". Mutant B6 red.
- **status:** fixed

## Finding 5 — P2 — guard_without_its_mirror (S2)
- **file:line:** lib/features/ai_coach/services/tool_dispatcher.dart (`hasPendingLogSet`)
- **claim:** Any `pending` `log_set` card blocked the tile, for up to an hour: a card the user never applies, or one for another day. The coach had just said "tap Complete workout on the tile below", and no tile came.
- **fix:** Only a `log_set` whose APPLY is running (`executing`, not expired) blocks the tile. A waiting card no longer blocks: the tile shows the counts as they are, and a later APPLY re-runs the app's own decision (it never completes a wrong day: the tap re-decides through `decideCoachDay`). Tests: a pending card gives `shown`; the mixed batch shows the tile; the mirrors now use `executing` (expired, `swap_exercise`). Docs: plan rev 14, naming row, nested CLAUDE.md, registry, `ai.md`. Mutants B1 to B5 red.
- **status:** fixed

## Finding 6 — P2 — unawaited_no_error_sink (S2)
- **file:line:** lib/features/ai_coach/services/tool_dispatcher.dart (tile post-step `refreshFromHive()`)
- **claim:** The tile's chat refresh could drop an in-flight loading bubble if the user sent another message in the few milliseconds before the tile write lands.
- **disposition:** The coordinator measured the tile window. `addIntents` runs after the reply is in memory and persisted, so the refresh always includes the reply. The race needs a second send inside one Hive write. Following the same refresh to its other caller showed a REAL, pre-existing bug with a seconds-wide window: a `log_set` APPLY tapped while a reply is pending turns the loading dots into a false "This message didn't finish - Tap Retry", and the reply's `replaceLastMessage` then overwrites the last bubble, which can be the tile that APPLY just wrote. Reproduced by a failing test (2 of 3 red before the fix). Fixed in its own commit (`fix(coach)`, diagnose 3e7b41): `refreshFromHive` keeps an in-flight loading bubble LAST and drops only that turn's pending error bubble (matched by `coachKey`, which the loading bubbles now carry); the retry path adds its loading bubble before its refresh, which also removes a stale error bubble after a successful retry. Test `test/contracts/coach_chat_refresh_during_send_test.dart` (7 cases); 7 mutants red. This closes the tile path's race too.
- **status:** fixed (commit C)

## Finding 7 — P2 — asserted_fixture_value (S2)
- **file:line:** test/contracts/coach_completion_tile_tool_behavioral_test.dart
- **claim:** No test drove an EARLIER batch's card through `addIntents`, the path that had the Riverpod self-read defect; only a same-batch mix was covered.
- **fix:** Test: `addIntents([log_set executing])`, then `addIntents([tile])`: `pendingWrites`, nothing written, no non-fatal. Mutant B7 (drop `pendingIntents: state`) red.
- **status:** fixed

## Review seat on commit C (the 3e7b41 fix; one fresh context-blind Sonnet seat)
Scope: the `ai_coach_provider.dart` diff and its new test, the 8 lenses, the same command rules (mutation of that file only, sha256-restored). Two P2:
- **C-F1 — P2 — guard_without_its_mirror.** `send` and `sendWithMedia` set the in-flight flag only AFTER their first await, so two taps in one frame (a double Retry: `chat_area.dart` does not gate Retry on sending; Retry plus a suggestion chip) both passed `if (state) return`. Each added a loading bubble; the first reply replaced the second's bubble, the second reply replaced the first reply, and one bubble was orphaned. Before the fix a refresh happened to wipe it; with the new refresh rule it would have stayed. **Fixed:** each method is a thin wrapper that claims the flag synchronously after its guard and releases it in `finally`; the bodies moved unchanged into `_sendBody` / `_sendWithMediaBody`, placed right after their wrappers so other tests' source slices still hold them. Tests through the real notifier: two sends in one frame, two media sends in one frame, the free-limit early return releases the flag. Mutants Q1 to Q4 red (Q4 needed the early-return case; it was green before that case existed).
- **C-F2 — P2 — asserted_fixture_value.** The retry reorder was pinned only by a source grep; the retry test re-implemented the sequence by hand. **Fixed:** a fake `AiService` holds the model call open, and the test drives the real `send(existingCoachKey:)`, refreshes mid-flight and checks the dots, no error, and nothing left after the reply. R5 and R6 now redden this behavioural case as well as the pin.
The seat's clean probes: nothing between the moved loading add and its old position depends on order (history assembly reads Hive); `coachKey` on a loading bubble reaches no consumer (Retry needs `isError`, the media chip `isUser`); an account switch mid-send rebuilds the chat as before (unchanged by the diff).

S2 also checked the registry `line_range`s it could reach and found them accurate. They were recomputed from anchors after the fixes.

## Mutation run after the fixes
54 mutants on the fixed tree: every kept mutant from the build run plus B1 to B9 and S1 to S9 (table in `docs/plan-reviews/coach-workout-parity-tile.md`, "B-pass round mutation record"). All RED except M59b, which is GREEN by design (recorded). Files restored and checked by sha256 after each.

## Clean lenses (both seats)
- writer_reader_drift: the tile row's one writer stays `CompletionPromptStore.write`; `ChatHistoryNotifier.build` reads the same fields; the auto-run type set has a server const and a client mirror, pinned on both sides.
- function_exception_swallow: no new `functions.invoke`; the tool-loop catch is Finding 2.
- blast_radius_mismatch: `_shared/**` and `ai-proxy/**` are platform; the record carries `bpass` at platform; the ai-proxy deploy needs its own founder go.
- secrets_in_tree: no credential-shaped literal in the diff; the kill switch is a flag, listed in SECRET_INVENTORY as not a credential.
- unawaited_no_error_sink: the auto-run dispatch in `addIntents` has a `.catchError` to `recordNonFatal('auto_run_intent_dispatch')`.
- missing_input: every file the tests read exists in the diff or on `main`.
- asserted_fixture_value: the registry goldens (PRO/FREE tool lists) were recomputed from `ALL_TOOLS`.

## Founder triage notes
None needed: no P0 or P1, and every P2 is fixed in this batch.

## Tuning entry
- **2026-11-11** - blast-radius platform - 7 findings; 0 false_alarm; tuning: none. Two repeated shapes. First, a guard keyed on a tool's NAME stands in for the effect it predicts: decide from the effect (the queued intent) when it is known, and tell the model only what is certain. Second, an accepted "tiny race" finding deserves one step more: follow the same call to its OTHER callers. Here the tile's few-millisecond window was harmless, but the same `refreshFromHive` on the log_set APPLY path had a seconds-wide window and a reproducible user-visible bug.
