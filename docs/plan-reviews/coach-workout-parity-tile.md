---
branch: coach-workout-parity-tile
scope: Coach workout parity slice S3 (OI-492, founder decision C). "I'm done" in chat makes the app's own "X of Y - Complete workout" tile appear, with one tap total. A new capability-gated tool requestCompletionTile becomes an auto-run intent (no APPLY card) that re-runs the app's own decideCoachDay and re-shows the local tile row. The coach never completes a day (ADR-0012). Also covered are the kill switch, the fail-closed capability gate and a UTC created_at fix for the tile row.
blast_radius: platform
review_rounds: 7
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/coach-workout-parity-tile-bpass.md
---

# Plan-review record: coach workout parity S3 (the completion tile tool)

Plan: `docs/plans/coach-workout-parity-2-server.md`, S3 text only (sections 0 C, 1, 2.1, 3.1, 4.1, the S3 parts of 5.1, 5.2, 6, 7, 7.3 and 8). The S1 and S2 parts of the same plan merged as PR #241 with their own record. The S3 text was reviewed with S1 and S2 in rounds 1 to 3 of that record and left out of its rounds 4 to 6. The rounds below are S3's own. Each round used two context-blind Sonnet reviewers with an exhaustive read-only command list: seat A for ground truth (every file:line and claim checked against the code at `c81d1041`) and seat B for adversarial design and failure modes.

## Round 1 (rev 6 S3 text, re-anchored at c81d1041)
Both seats returned `needs-changes`, with no P0.
- P1s:
  - The Gemini-throw catch decided "apology or not" before the post-loop tile push. A tile-alone turn with a failed summarisation round therefore got the hard-failure apology and a refund over a working tile. Found by both seats.
  - The Train service could not read the ai_coach pending-intents provider; the flag now comes from the dispatcher.
  - Two coach lines tripped the write-claim detector.
- P2s:
  - the `ToolCallRecord.status` union;
  - the tile row's `created_at` was local time without `Z`, a live 1b defect;
  - the exact spec of the surfacing-door pin;
  - the `WRITE_CLAIM_RULE` conflict, now an override line plus R8;
  - day boundary and the legacy draft card, now R9 and R5;
  - the routing condition keyed on plan-matched logs only.
- Mechanical: re-anchors; the dispatcher's early branch; the semantic-memory `[queued: ...]` suffix.
- Folded into rev 7 (changelog "Rev 7" in the plan).

## Round 2 (rev 7)
Both seats returned `needs-changes`, with no P0 or P1. Every round-1 disposition was confirmed correct in design. Twelve P2s:
- the queued-line override sat before `WRITE_CLAIM_RULE` and was absolute. It is now a scoped addendum appended after the rule.
- `failed` was in the pending-write set, which made a dead end. It is dropped, and the reply line is hedged (R10).
- the memory helper had no importable home. It moves to `_shared/`.
- the `created_at` fix needs its own `fix(coach):` commit with a full diagnose doc, and the keep path must normalise old local stamps.
- an empty non-rest plan was excluded by the routing condition. The condition now keys on `all_logged`.
- M45 was a single mutant. It is split into M45a-e.
- an empty routing block still added a prompt separator. The block is now pushed only when non-empty.
- three claimed-but-not-landed changelog items.
- the surfacing-door pin slice was ambiguous.
- the same-response cases need a multi-call Gemini fake, and the detector test could pass vacuously.

Seat A also walked every tool-loop ordering under rev 7 and confirmed the reply, refund flag, intents and final `toolCallsLog` for each. Folded into rev 8 (changelog "Rev 8").

## Round 3 (rev 8)
Both seats returned `needs-changes`. There were two P1s, both prompt text the plan had not landed or not considered:
- the routing block still held "APPLY" and "Queued" although rev 8 moved that rule into the addendum, and the block's own test forbids both words. This was a claimed-but-not-landed change.
- the always-present ICBF instruction "finished a workout without exercise details, ask for sets" comes earlier in the prompt. The tool would have silently never fired. The block now carries a precedence line, pinned by a test, and the device check tries several phrasings.

P2s:
- a single coach reply line for every state, plus the auto-complete-on-APPLY outcome in R10;
- the rest condition now names `today_workout.type`;
- a test that can see the keep-path mutant M59c;
- the slice terminator and the method placement moved into the body text, with `_maybeCompleteScheduledDay(` added to the forbidden list;
- the import direction is stated, with the routing file owning the consts.

Seat A also checked the rev 8 prompt-order claim, the `all_logged` mapping for every day shape, the `tryParse` normalisation and the surfacing-door pin against the code, and found them correct. Folded into rev 9 (changelog "Rev 9").

## Round 4 (rev 9)
Seat A returned `converged`: every rev 9 row had landed in the body and rested on true code facts, and only mechanical items remained. Seat B returned `needs-changes` with three P2s and no P0 or P1. All three are prompt wording, with no new mechanism:
- the "never say counted" bullet is now scoped to the tile call;
- the memory marker for the tile is now a neutral ` [requested: completion tile]` instead of empty;
- the precedence line says the tool is an action, not a data read, against `CAPTAIN_MANUAL`'s "never call a tool for today".

Seat B also walked eight "I'm done" scenarios through the full prompt in order. Folded into rev 10 (changelog "Rev 10").

## Round 5 (rev 10)
Seat B returned `converged`. It walked the full prompt in order for the partial, completed, nothing-logged and meal-plus-done turns, and the new memory marker (no reader parses it; it survives the 200-character retrieval cap). Seat A returned two one-line P2 text items and no P0 or P1:
- the rev 9 import-direction change had not reached section 1d;
- 5.1 claimed the second time-zone run is in the gate loop, but 7.7 did not list it.

Both are folded into rev 11 with the mechanical items (changelog "Rev 11").

## Round 6 (rev 11, confirmation, one seat)
The seat returned `needs-changes` with two P2s that were text completeness only, with no design finding:
- cleanup and doc-pass instructions lived only in changelog rows;
- two assertions promised in 3.1 were missing from the 5.1 test list.

Every design disposition of revs 8 to 11 was confirmed present and correct in the body. Root fix in rev 12: section 3.1.1, an AUTHORITATIVE build checklist that lists every S3 item in commit order, including the cleanups, so the build never depends on a changelog row. The two assertions were added to 5.1, and the mechanical items fixed.

## Round 7 (rev 12, completeness, one seat)
The seat returned `needs-changes` with four P2s, all text completeness, and no design finding. That makes four rounds in a row (rounds 4 to 7) with no design or mechanism finding.
- the surfacing-door count pin had no named test file;
- commit A added `reshow` without a commit-A test for it;
- commit B (`feat`) had no place to record its mutations;
- the rev 12 naming additions and the section 1 `tool_intent.dart` cell had not landed in the body.

The seat mapped every changelog row of revs 7 to 12 to a 3.1.1 item and confirmed every path and symbol against HEAD. Rev 13 applies all four P2s and the mechanical items (stale anchors, the `:16` wording, the process steps as item 20, the registry-range and Gate 42 notes in item 19). Commit A's tests already carry the reshow case (M59a reddens in commit A's own file, both zones).

Verdict: `converged`. The design has been stable since round 4. The last three rounds found only text that had not been transcribed, and 3.1.1 now holds every build item. The B-pass reviews the built diff against 3.1.1.

## S3 build mutation record (commit B)

Harness: each mutant applied by exact-string replacement (each anchor asserted to occur exactly once, the replacement asserted present), the named tests run (Dart under `TZ=Asia/Kolkata`, plus `TZ=Etc/GMT+12` where listed; Deno with `--no-check`), then every file restored and checked by sha256 (`ALL RESTORED`). Every red below is a named assertion failure, not a compile or syntax error. Numbers are failing test cases.

| id | edit | result |
|---|---|---|
| M1 | `requiresCapability` line removed from `requestCompletionTile.ts` | RED: registry (2: the no-caps goldens), tool-loop capability gate (1), tool test (1) |
| M2 | `'request_completion_tile'` dropped from `kCoachClientCapabilities` | RED: `coach_client_capabilities_test` (1), real-tree gate run (exit 1) |
| M3 | `_executeRequestCompletionTile` calls `completeOnTap` first | RED: derive-only slice (1), behavioural (6) |
| M4 | `completeNow` maps to `shown` | RED: all-logged case (1) |
| M5 | `hasExerciseLogsFor` guard dropped | RED: no-logs case (1) |
| M6 | owner re-check disabled | RED: owner-change case (1) |
| M7 | `addIntents` stops partitioning | RED: state-empty and mixed-batch cases (2) |
| M8 | `filterVisibleIntents` keeps the tile | RED: filter case (1) |
| M9 | `reshow` ignored (old `created_at` kept) | RED: both reshow-ordering cases, both zones (2 + 2) |
| M10 | block returned without the capability | RED: routing test |
| M11 | tile branch sends the generic `QUEUED_NOTE` | RED: case (i) |
| M12 | FC2 auto-run line never used | RED: case (vi) |
| M13 | `trigger` enum removed | RED: schema and non-empty-properties cases |
| M28 | kill switch no longer deletes | RED: kill-switch case |
| M32 | B-F1 suppression removed entirely | RED: cross-round and same-response cases |
| M32b | only the per-response check kept | RED: the cross-round cases and (vii) (3) |
| M33 | FC2 `every` -> `some` | RED: (iv) meal + tile throw case |
| M36 | kill switch case-insensitive | RED: `"TRUE"` case |
| M39a | tile status `queued_for_user_confirmation` | RED: case (i) |
| M39b | `queuedStatus` set on `logSet` | RED: registry "no other tool" case |
| M40 | gate fail-closed branch neutered (`unreadableCapability: false`) | RED: `ai_tool_dispatcher_coverage_lib_test` (2: identifier write and read tools) |
| M41a | `swapWorkoutDays.ts` back to the identifier | RED: real-tree gate run ("1 capabilities this gate cannot read") |
| M41b | tile capability literal altered | RED: literal === const case |
| M44 | one tile intent pushed per recorded request | RED: case (v) |
| M45a-e | `hasPendingLogSet` forced false / `pending` dropped / `executing` dropped / `!isExpired` dropped / `log_set` type check dropped | RED: 3 / 2 / 1 / 1 / 1 (the pending, executing, expired and swap_exercise cases, as planned) |
| M58 | catch reads `intents.length > 0` only | RED: case (vi) (apology, alert `hadQueuedIntent:false`) |
| M59a | reshow stamps local time | RED: IST 2, GMT+12 3 (the reshow-ordering and UTC cases) |
| M59b | non-reshow new row stamps local time | GREEN here, as it must be: the tile writes only with `reshow: true`. This mutant reddens in commit A's `coach_completion_prompt_test.dart` (3 cases, both zones; diagnose f3d704). The plan's 5.2 cell naming the tile file for (b) is corrected by this note. |
| M60 | a third `_maybeCompleteScheduledDay(` call inside the tile method | RED: derive-only (2: the slice and the two-door pin) |
| M61a / M61b | `memoryIntentSummary` keeps auto-run types / `index.ts` inlines the old expression | RED / RED |
| M62a-h | addendum before the suffix; addendum absolute; `total_logged >= 1`; `total_planned > total_logged`; precedence bullet removed; rest condition removed; never-bullet unscoped; action-not-read removed | all RED (`completion_tile_routing_test.ts`) |

Survivors: none. One defect was found BEFORE the run by the new behavioural test (the auto-run chain): `addIntents` handed the dispatcher the notifier's own `ref`, and the dispatcher read `pendingToolIntentsProvider` through it, which Riverpod refuses (a provider cannot depend on itself), so the tile would never have shown from the chat. Fixed by passing the notifier's state as `execute(..., pendingIntents:)`; queued cards are added to state first, so a same-batch `log_set` counts as pending (mixed-batch case).

## B-pass round mutation record (after the 2-seat B-pass)

The B-pass (`docs/reviews/coach-workout-parity-tile-bpass.md`) changed three behaviours (plan rev 14): `hasPendingLogSet` is an `executing` `log_set` only; the same-response tile drop is decided after the loop from the real intents; the coverage gate reads the comment-stripped source. The whole set was re-run on the fixed tree with the same harness (54 mutants). M32, M32b and M45a-e were retired because their anchors no longer exist; B1-B5 and S1-S4 cover the same guards in their new form. Every kept M-row above re-ran RED except M59b (GREEN, as recorded). The "mixed-batch case" sentence above is superseded: a same-batch `log_set` card is `pending` and no longer blocks the tile.

| id | edit | result |
|---|---|---|
| B1 | F2 reverted (`pending` blocks again) | RED (the waiting-card and mixed-batch cases) |
| B2 | `executing` -> `pending` | RED (the executing and earlier-batch cases) |
| B3 | `!isExpired` dropped | RED (expired executing mirror) |
| B4 | `log_set` type check dropped | RED (executing swap_exercise mirror) |
| B5 | `hasPendingLogSet` forced false | RED (executing cases) |
| B6 | owner-null early return removed | RED (no-owner case) |
| B7 | `addIntents` stops passing `pendingIntents: state` | RED (earlier-batch case: the Riverpod self-read) |
| B8 | marker stamp dropped from the tile branch | RED (the chain waits on the marker; structure pin) |
| B9 | `filterVisibleIntents` keeps the tile | RED |
| S1 | F1 reverted (`responseHasTileSurfacingWrite ||` back in the drop) | RED (the invalid-logSet cases) |
| S2 | the early `log_set`-already-queued drop removed | RED ([logSet, tile] response shape) |
| S3 | same-response note -> the tool's `queuedNote` | RED |
| S4 | `tileWillPush()` ignores intents | RED (valid same-response cases) |
| S5 | post-loop catch stops marking records `failed` | RED (throwing-builder case) |
| S6 | post-loop catch rethrows | RED (throwing-builder case) |
| S7 | gate literal match on the raw source | RED (commented-literal case) |
| S8 | gate declaration check on the raw source | RED (commented-out declaration case) |
| S9 | `addIntents` stops adding queued cards to state | RED (log_set still enters state) |

Survivors: none (M59b green as recorded above).

