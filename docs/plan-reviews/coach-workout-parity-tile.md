---
branch: coach-workout-parity-tile
scope: Coach workout parity slice S3 (OI-492, founder decision C). "I'm done" in chat makes the app's own "X of Y - Complete workout" tile appear, with one tap total. A new capability-gated tool requestCompletionTile becomes an auto-run intent (no APPLY card) that re-runs the app's own decideCoachDay and re-shows the local tile row. The coach never completes a day (ADR-0012). Also covered are the kill switch, the fail-closed capability gate and a UTC created_at fix for the tile row.
blast_radius: platform
review_rounds: 7
ground_truth_verified: true
verdict: converged
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
