---
plan: coach-log-truth
revision: 13
date: 2026-10-21
blast_radius: platform   # docs/blast_radius.yaml:92 (ai-proxy/**) and :99 (_shared/**) are platform (R1A-2)
tier: L                  # Edge Function + AI prompt (§4.12.6); §4.6 feature-flag protocol
execution_mode: inline   # §4.12.7: one worktree (.claude/worktrees/coach-log-truth)
closes_oi: []            # OI-368 and OI-369 stay OPEN until the post-deploy measurement (§5); see §0.1
files_oi: [OI-373, OI-374, OI-375]  # two parallel workout write paths; remove DISABLE_WRITE_CLAIM_RULE; FC2 hard-codes Recruit (minted 2026-10-21)
---

# Coach stops saying "Logged" before a save: fix the source, then measure (observations 1 and 2 of the 2026-10-21 web walk)

## Revision history
- **rev 1 → rev 2:** round 1 (ground truth A, exposure B), 10 P1s, mapped in rev 2 §8. The founder approved five copy lines (§2.3).
- **rev 2 → rev 3 (founder scope decision 2026-10-21):** round 2 found 10 P1s, all in L3, the server-side rewrite of the coach's reply. The server cannot know which cards are on the user's screen: typed cards live up to 1 h (`pending_tool_intents_provider.dart:90-104`), the workout draft lives until a tap, the client drops a legacy `log_food` when a typed meal intent exists (`ai_coach_provider.dart:1547-1550`), and only the device can resolve a `log_set` exercise id to a name (`:1694`). The R2B table ran 28 realistic replies through L3: 14 came out wrong or misleading. Per §4.12.1 the unit was too large. The founder chose: **ship L1 + L2 (the source of the false text) plus a log-only detector; L3 is dropped; OI-368/369 stay open until a post-deploy measurement decides whether a rewrite is needed, and if it is, it is built in the app, which knows the cards.** Round-2 findings are mapped in §8.
- **rev 3 → rev 4:** rev-3 round 1 (A ground truth, B exposure) found 5 P1s, none against the scope: the rule taught a false 5-second countdown for typed meals, and the tool's own description says the same (`logMealByText.ts:27`); "did it save?" had no true answer; a Dart parity pin breaks when the ICBF blocks move; the media behavioural test is not buildable; the replay branch used out-of-scope variables. The founder approved two more lines on 2026-10-21 (status question, several cards). Mapped in §9.
- **rev 6 → rev 7:** round 6 (A, B): no finding against the fix mechanism; 1 P1 each, both in §5 (the rendered-card mirror resolved names from a field that has no ids; a mismatched queued line had no score). Founder decision 2026-10-21: for the live check the founder signs in as the PRO test account in their own Chrome and the agent drives that browser (no password reaches the agent); the screen is the primary evidence. Mapped in §12.
- **rev 12 → rev 13:** delta check of rev 12: CONVERGED, no P0/P1; 3 P2s and 4 P3s folded in (triage applies only on log or change turns; T2 is decided without a card test; frames must show the reply appearing plus 7 s; column names, frame deletion, scope of a claim). The triage cases are renamed T1/T2 so they no longer read as turn ids A1/A2. Mapped in §18.
- **rev 11 → rev 12:** delta check of rev 11: 1 P1 (a read covers only the fields it returns, so a correct history answer naming an item still scored FALSE) and 2 P2s (an earlier same-kind entry excused the OI-368 reply; the ffmpeg frame window). Rounds 7-11 all found free-text scoring cases; rev 12 replaces case-by-case evidence with CLAIM TRIAGE: the agent decides only (T1, then labelled A1) a claim about an item with a card in this reply and (T2, then labelled A2) a claim about this turn's requested item with no card and no save in this turn's window; every other claim goes to the founder. Mapped in §17.
- **rev 10 → rev 11:** round 10: B CONVERGED; A 1 P1 (a correct answer about an earlier day had no allowed evidence and would be scored FALSE with confidence). Fixed by an evidence rule: FALSE needs POSITIVE evidence (a card for that item in this reply, or a read that covers the item and does not show it); a claim no read covers goes to the founder. Precheck widened to the last 7 days; B's P2s (the agent cannot watch the OS recording; a covered or locked window stalls the countdown) folded in. Mapped in §16.
- **rev 9 → rev 10:** round 9 (A, B): no finding against the fix mechanism or the approved copy; 3 P1s each, all in §5 scoring and evidence (a `BEGIN READ ONLY … ROLLBACK` read may return no rows; water's `updated_at` is stored 5.5 h ahead, so it always looked fresh; "affirmative" undefined and status/control turns unscored). Because the scoring of free text keeps producing scorer-disagreement findings, rev 10 adds a doubt rule: a reply the agent cannot place with certainty goes to the founder. The media rule is now written out in full. Mapped in §15.
- **rev 8 → rev 9:** round 8 (A, B): no finding against the fix mechanism or the approved copy; 1 P1 from A and 2 from B, all in §5: the cloud fallback for countdown cards cannot see water and sleep (one row per day) and was anchored before the model ran; capture is not continuous; the saved-data exemption would have excused the OI-369 transcript itself. Mapped in §14.
- **rev 7 → rev 8:** round 7 (B; both A reviews were cut off by a container restart and re-run in round 8): no finding against the fix mechanism or the approved copy; 2 P1s, both in §5 (countdown cards are gone before a screenshot; scoring (a) marked correct answers FALSE). Founder decision 2026-10-21: the live check runs later from Claude Code on the founder's own computer with the Chrome extension ("Local Claude Code later"); this batch prepares the script (§5). Mapped in §13.
- **rev 5 → rev 6:** rev-3-scope round 3 (A, B): 4 P1s: two kill-switch paths with no pin (day-swap call site, media `ruleOn`), a §5 classification that ignored the cards the client drops, and the "proposed nothing" line firing on every non-log turn. Founder decisions 2026-10-21: keep ONE plan (no split of the measurement); the measurement uses SERVER DATA ONLY with the client's card rules mirrored (§5); the `scheduleTemplate` example "Saved!" becomes "Queued. Tap APPLY to save it." under the switch. Mapped in §11.
- **rev 4 → rev 5:** rev-3-scope round 2 (A ground truth, B exposure): 3 P1s, all in the §5 live check / measurement (budget, request bodies, card-vs-line mismatch blind spot), none in the fix. The founder decided 2026-10-21: one PRO test account over two IST days; the day-swap example narration changes under the switch ("Tap APPLY below to swap them."). Mapped in §10.

## 0. Evidence (live, read-only, 2026-10-21)

`public.ai_coach_interactions`, the founder's three messages (IST):

| time | user message | stored `ai_response` | `tool_calls` | what happened |
|---|---|---|---|---|
| 13:19:59 | `log bench press` | `Roger. Logged.\n\nI need the specifics for that session: sets, reps, and weight used. Stand to.` | null | nothing proposed or written; "Logged." fabricated (OI-368) |
| 13:21:37 | `Log this workout for today: bench press 3 sets of 8 at 60 kg` | `Roger. Bench Press, 3 sets of 8, 60 kg. Logged. Carry on.` | `logSet` queued | LOG SET card waiting for APPLY; founder tapped DISMISS; nothing written (OI-369) |
| 13:29:24 | same | same text | null | legacy `<ICBF_LOG>{"action":"confirm_workout_log"…}` → `WorkoutLogConfirmCard`; founder tapped CONFIRM; Bench Press row `created_at` 13:29:36 |

How each card actually saves (verified R1A/R1B/R2B):
- **Typed intents** (`tool-loop.ts:558-601`, functionResponse `status: "queued_for_user_confirmation"`): `ToolConfirmCard`, APPLY/DISMISS. Nothing is auto-applied.
- **Legacy `confirm_workout_log`:** `WorkoutLogConfirmCard`, `CONFIRM · LOG WORKOUT`. Waits for the tap.
- **Legacy `log_water | log_weight | log_food | log_sleep | log_measurement`:** `LogConfirmCard` auto-confirms after 5 s unless SKIP (`log_confirm_card.dart:34-37`). R2B verified the card mounts within milliseconds of the bubble, so "it logs in 5 seconds unless you tap SKIP" is true when read.

### 0.1 Why OI-368/369 stay open
This batch removes what TEACHES the model to say "Logged" (§1). It does not prove the model stops. The proof is the post-deploy measurement in §5. If it still finds a false claim, the next piece is a client-side guard (the founder's option 2: the app, which knows the cards on screen, shows "Not saved yet. Tap APPLY below." under the bubble and never rewrites the coach's words). Each OI's "Blocked on" line records that.

## 1. Writers and readers (§4.1)

**Writer of the false text: the model.** It is shaped by:
- the queued functionResponse (`tool-loop.ts:593-600`), which never says "not saved";
- `captain_manual.ts` §8 ANTI-FABRICATION (`:409-413`), which has no write-claim rule;
- `ai-proxy/index.ts:975-995` `ICBF_LOG_INSTRUCTIONS`, headed **"FITNESS DATA LOGGING — INSTANT:"**, which tells the model a tagged log is instant;
- `ai-media-proxy/index.ts:728`, the same header in its own prompt (it does not use `CAPTAIN_MANUAL`);
- **`_shared/day_swap_routing.ts:49-50`** `PRO_CAPABLE_BLOCK` example narration: "… Confirm below and it's done." It narrates the swap as done before the tap, and the card's button is APPLY (R4A-P2-1);
- **`_shared/tools/plan/scheduleTemplate.ts:23`** description, sent on every PRO turn, teaches the follow-up "'Saved! Want me to schedule it for Mon/Wed/Fri?'" after `createCustomTemplate`, whose card also waits for APPLY (R5A-P2-3);
- **`_shared/tools/nutrition/logMealByText.ts:27`**, the tool description sent on every turn: "Always trivial-class — the user gets a 5-second auto-confirm card". False: a typed meal becomes a `ToolConfirmCard` that waits for APPLY (`tool_confirm_card.dart:31-35,103`; the countdown was removed in B-4). The card's own doc comment (`tool_confirm_card.dart:15`, "trivial (5s countdown auto-confirm)") is stale the same way (R3B-P1-1);
- chat-history replay of earlier "Logged." replies, and semantic retrieval of past messages from `memory_embeddings` into the prompt (`ai-proxy/index.ts:1083-1100`), a second replay channel (R8A-P3).

**Readers:** the chat bubble (`reply`, `ai-proxy/index.ts:1337-1352`); `ai_coach_interactions.ai_response` (`:1276-1283`, replayed as history and by the 30 s dedup replay `:849-861`); `memory_embeddings` (`:1307-1334`); the `ai-media-proxy` reply (`:971`). **This batch changes none of the readers**: the reply text is never rewritten, so every reader gets exactly what the model said.

**Bug history (§4.1.5):** no prior record of the coach claiming a write. `7fbe21` FC2 (`tool-loop.ts:639-646`) is the precedent wording and is already true ("I've queued that below … tap APPLY").

## 2. Design

### 2.1 L1: the queued functionResponse says what is true
- `tool-loop.ts:593-600` `response` gains `note: "NOT saved yet. The user must tap APPLY on the card. Do not say it is logged, saved or done; say it is queued."` when the rule is enabled.
- `ToolLoopOptions` gains `writeClaimRule?: boolean` (OPTIONAL; `undefined` = enabled, so the ~20 existing `tool-loop_*_test.ts` call sites keep compiling under CI's whole-tree `deno check`, `test.yml:249-252`; R2A-8). The handler passes the value it read once per request; the loop never reads env.
- The field is additive: nothing pins `queued_for_user_confirmation` (verified R1A, R2A).

### 2.2 L2: prompt text, kept out of `CAPTAIN_MANUAL`
`CAPTAIN_MANUAL` is also imported by `weekly-report/index.ts:5,457`, so it is not edited. New pure module `supabase/functions/_shared/write_claim_prompt.ts`:
- `icbfLogInstructions(enabled: boolean): string`: the WHOLE `ai-proxy` ICBF block (`index.ts:975-995`) moved here verbatim, with only its header line parameterised: enabled `FITNESS DATA LOGGING — A CARD FIRST; NOTHING IS SAVED WHEN YOU REPLY:`, disabled the old bytes `FITNESS DATA LOGGING — INSTANT:` (R2A-7: moving the whole block is what makes the OFF bytes testable, because `ai-proxy` calls `serve()` at module scope and cannot be imported).
- `mediaIcbfLogInstructions(enabled: boolean): string`: the `ai-media-proxy` ICBF substring (from `"\n\nFITNESS DATA LOGGING"` to the end of its concatenation at `:728-745`) moved verbatim, same header parameter.
- `writeClaimSuffix(enabled: boolean, opts?: { tools?: boolean }): string`: `""` when disabled; otherwise `"\n\n" + WRITE_CLAIM_RULE` (or the media variant when `tools: false`). The caller appends it unconditionally; because the separator lives inside the suffix, the OFF prompt is byte-identical (R2A-7).
- Use sites: `ai-proxy` `promptParts` uses `icbfLogInstructions(ruleOn)` in place of the const, and `:1134` becomes `systemPrompt = dayInjection + systemPrompt + "\n\n" + antiFabricationRule + writeClaimSuffix(ruleOn);`. `ai-media-proxy` uses `mediaIcbfLogInstructions(ruleOn) + writeClaimSuffix(ruleOn, { tools: false })` as the tail of the `asAuthoredPrompt(...)` argument (`:715-745`), i.e. BEFORE the fenced snapshot block appended at `:746+`, so the rule stays authored text, never inside the untrusted fence.

`WRITE_CLAIM_RULE` (rev 4: by HOW the item was proposed, not by data type, R3B-P1-1; status question, R3B-P1-2; precedence, R3A-P2-1):

```
WRITE CLAIMS — NOTHING IS SAVED WHEN YOU REPLY:
- Anything you propose is NOT saved when you reply. What you proposed with a tool waits for the user to tap APPLY on its card. A workout tag waits for CONFIRM. A water, weight, food, sleep or measurement tag saves after a 5-second countdown unless the user taps SKIP. If you used a tool and a tag for the same item, use the APPLY line.
- Never say logged, saved, recorded, added, tracked, locked in, squared away, on the books or done, and never say swapped, paused, switched, moved, rescheduled, marked, completed, updated or all set, about anything you propose in this reply. Say it is queued, in these words: "Queued. Tap APPLY to log it." (a set or meal you proposed with a tool), "Queued. Tap CONFIRM to log it." (a workout tag), "Queued. It logs in 5 seconds unless you tap SKIP." (a water, weight, food, sleep or measurement tag), "Queued. Tap APPLY to confirm." (any other action you proposed with a tool). If you proposed two or more items and all were tool proposals, say "Queued. Tap APPLY on each card." once; if you mixed tools and tags, give each kind its own line. Put the queued line(s) FIRST in your reply (a countdown card starts when it appears). Only when swapWorkoutDays is the only thing you proposed, the DAY SWAP ROUTING sentence "Tap APPLY below to swap them." is your queued line and may come last; with other proposals, the lines above apply. For a template you proposed with a tool, say "Queued. Tap APPLY to save it."
- If the user asked you to log something and you proposed nothing, do not say anything was logged or queued. Say what you still need. For a workout with no sets, and only when the snapshot shows no entry for that exercise today: "Nothing logged yet. Send the sets and I'll queue it." If it does show one, ask only for the new sets.
- If the user asks whether something saved: if the snapshot shows that exact entry, say it is logged. If not, say: "Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it." Do not queue it again unless they ask.
- Say something is logged only when the snapshot or a history tool's result already shows it.
```

**Media variant** (R3A-P2-1, R9A-P2-2): `ai-media-proxy` offers no tools, so `writeClaimSuffix(enabled, { tools: false })` returns exactly this text (pinned by the golden test; it contains no "tool"):

```
WRITE CLAIMS — NOTHING IS SAVED WHEN YOU REPLY:
- Anything you propose is NOT saved when you reply. A workout tag waits for the user to tap CONFIRM. A water, weight, food, sleep or measurement tag saves after a 5-second countdown unless the user taps SKIP.
- Never say logged, saved, recorded, added, tracked, locked in, squared away, on the books or done, and never say swapped, paused, switched, moved, rescheduled, marked, completed, updated or all set, about anything you propose in this reply. Say it is queued, in these words: "Queued. Tap CONFIRM to log it." (a workout tag), "Queued. It logs in 5 seconds unless you tap SKIP." (a water, weight, food, sleep or measurement tag). If you proposed both kinds, give each its own line. Put the queued line(s) FIRST in your reply (a countdown card starts when it appears).
- If the user asked you to log something and you proposed nothing, do not say anything was logged or queued. Say what you still need. For a workout with no sets, and only when the snapshot shows no entry for that exercise today: "Nothing logged yet. Send the sets and I'll queue it." If it does show one, ask only for the new sets.
- If the user asks whether something saved: if the snapshot shows that exact entry, say it is logged. If not, say: "Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it." Do not queue it again unless they ask.
- Say something is logged only when the snapshot already shows it.
```

**Header wording** (R3B-P3-1, R4B-P2-2): enabled header `FITNESS DATA LOGGING — A CARD FIRST; NOTHING IS SAVED WHEN YOU REPLY:` ("until the user acts" contradicted the countdown tag, which saves when the user does nothing) ("QUEUED FOR THE USER" next to "NEVER for future plans" could read as future tasks).

**Tool description** (R3B-P1-1): `applyWriteClaimDescriptions(tools, enabled)` in `write_claim_prompt.ts`, called in `runToolLoop` before `toolToFunctionDeclaration` (`tool-loop.ts:301-302`). When enabled it returns a COPY of `logMealByText` whose description has the exact substring `Always trivial-class — the user gets a 5-second auto-confirm card showing the parsed nutrition.` replaced by `The user gets a card showing the parsed nutrition and must tap APPLY to log it.`, and its first sentence's `and log it to the user's nutrition for today` by `and queue it for the user's nutrition today` (R4B-P3); when disabled it returns the input array unchanged (same objects, so the declarations are byte-identical). The same function swaps `scheduleTemplate`'s example `'Saved! Want me to schedule it for Mon/Wed/Fri?'` for `'Queued. Tap APPLY to save it. Want me to schedule it for Mon/Wed/Fri?'` (founder 2026-10-21). The test asserts each old substring exists in the live description (a later edit to the tool text fails loudly instead of silently skipping). The stale doc comment at `tool_confirm_card.dart:15` is corrected in this batch (comment only).

**Day-swap narration** (founder 2026-10-21): `daySwapRoutingBlock(isPro, capabilities, ruleOn = true)` gains an optional third parameter (existing calls in `day_swap_routing_test.ts:18-53` keep compiling). With `ruleOn` the `PRO_CAPABLE_BLOCK` example's last sentence `Confirm below and it's done.` becomes `Tap APPLY below to swap them.`; with `false` the block is byte-identical to today. `ai-proxy/index.ts:1035` passes `ruleOn`.

### 2.3 Copy: founder-approved 2026-10-21, now prompt wording
The five approved lines, the day-swap example sentence (rev 5), plus the two approved for rev 4 (`Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it.` and `Queued. Tap APPLY on each card.`), appear verbatim in `WRITE_CLAIM_RULE` as the words the coach should use. No code emits them, so they do NOT go into `_shared/coach_replies.ts` (whose mirror test would demand Dart twins for strings the client never reads). If the client-side guard (§0.1) is built later, it takes them from there.

### 2.4 Detector: log only, never changes text
Pure `detectWriteClaim(reply: string, ctx: { typedIntentTypes: string[]; legacyActions: string[]; replay: boolean; userAskedQuestion: boolean }): WriteClaimDetection | null` in `_shared/write_claim_detector.ts`. Returns `null` when no claim token is present; otherwise:

```
{ token,            // closed list: logged|saved|recorded|locked in|on the books|done (+ the additions below)
  safe_marker,      // closed list name or null (tap|queued|yesterday|ago|last night|last week|last session|as complete|snapshot|will|to log|can log)
  negation,         // not|n't|nothing|no in the same sentence (a curly apostrophe counts)
  unsafe_claims,    // every sentence with a token and neither a marker nor a negation (B-pass F1)
  typed_log, typed_other, legacy_workout, legacy_auto,   // counts from THIS reply only
  replay, user_question }
```

- **Queued lines too** (R4B-P1-2): the detector also fires on any of the six `Queued.` lines and reports `queued_lines: ("apply_log"|"apply_confirm"|"apply_each"|"apply_save"|"apply_swap"|"fc2"|"confirm"|"skip")[]`, every line found in order (a mixed reply such as A6 carries two, R8A-P3) (`apply_save` = "Queued. Tap APPLY to save it.", `apply_swap` = "Tap APPLY below to swap them.", `fc2` = the `tool-loop.ts:645` fallback, R5B-P1-1/R5A-P2-2), so a line that does not match its card (a SKIP line next to typed intents, an APPLY line with no tool intent) shows in the log against the same line's counts. The token list gains `added`, `tracked`, `squared away`, `on the books`, and the change verbs `swapped`, `paused`, `switched`, `moved`, `rescheduled`, `marked`, `completed`, `updated`, `all set` (labels only, R5B-P2-5, R6B-P2-5).
- **Never breaks a reply** (R6B-P2-4): the whole body of `logWriteClaimDetection` is in try/catch → `warn("[write-claim-detect] skipped")` through an injected `warn = console.warn` (R8A-P2, R8B-P2-4), a fixed string: the catch never logs the error object, its message or any input (an error message could quote reply text) (R7B-P3); `extractLogActions` passes `parsed.action` untyped (`ai-proxy/index.ts:203-205`) and the replay reads a cast `recentDup.ai_response` (`:851`), so fixtures cover `action: 123`, `data: null`, `reply: undefined` (no throw). Safe marker `confirm below` is NOT added (the narration changes instead).
- Matching is on word boundaries (R2A-10) over the reply with `*`, `_`, `` ` `` stripped and curly apostrophes made straight; the prescribed lines match with any run of whitespace (a newline, a double space, a NBSP) as one space (B-pass F2). The first claim sentence fills `token` / `safe_marker` / `negation`; every claim sentence is read for `unsafe_claims` (B-pass F1). No segmentation output, no rewrite, so every round-2 segmentation finding is moot.
- The handler logs one line when the result is non-null: `console.log("[write-claim-detect]", JSON.stringify({ fn, interaction_id, rule_on, ...detection }))`. `interaction_id` is `chatReservationId` in `ai-proxy` (declared at `:913`, in scope on the success path). `ai-media-proxy` inserts its row at `:1000` without returning an id, and this batch does not change that insert, so its line carries `interaction_id: null` and is joined to the stored row by function and time. Replay lines carry the original row's id and are excluded from the false-claim count (they repeat an earlier reply). It never logs reply text or the user id; the original text stays in `ai_coach_interactions.ai_response`, which is why rewriting nothing makes every log line auditable after the fact (R2B P2-4).
- **One impure helper** (R3A-P1-2): `logWriteClaimDetection(fn, interactionId, ruleOn, reply, ctx: () => DetectCtx, log = console.log, warn = console.warn): void` (the ctx is a thunk so the handler's ctx expressions also run inside the try, B-pass F3) in the same file runs `detectWriteClaim` and writes the line through the injected `log` (or the fixed string through `warn`); it is tested behaviourally with fakes. A pure `replayCtxOf(extracted: { actions: unknown[] }): DetectCtx` in the same file builds the replay ctx (`typedIntentTypes: []`, `legacyActions` from `extracted.actions`, `replay: true`, `userAskedQuestion: false`) (R8A-P3). Each site is ONE short call to it.
- Wired: `ai-proxy` chat success path after `extractLogActions` (`chatReservationId` in scope, `:1229`); `ai-media-proxy` after `extractLogActions(rawReply)` (`:971`); the dedup replay branch (`replay: true`).
- **Replay branch scope** (R3A-P1-3): `chatReservationId` is declared at `:913`, AFTER the replay branch (`:849-861`), so it cannot be used there. The dedup `.select(...)` at `:814` gains `id` (a read-only change) and the replay call logs `recentDup.id`. `ruleOn` is read once BEFORE the dedup block; its position pin anchors on `dedupCutoff` (`:811`), not on `.select(`, which occurs five times earlier (`:157,379,404,425,626`); the dedup select is at `:814`, `chatReservationId` at `:913` (R6A-P3); the §3 pin uses the same `dedupCutoff` anchor. The replay call passes `extracted.actions` from inside the branch (R5A-P2-6; the stored `ai_response` is the TAG-STRIPPED `cleanReply`, `:1230,1279`, so these are empty in practice and a replay carries no cards — §7's statement stands), as one short statement (`logWriteClaimDetection("ai-proxy", recentDup.id, ruleOn, extracted.reply, () => replayCtxOf(extracted));`, about 100 characters; a deno-fmt'd call with an inline ctx measured 272 characters against 330 of headroom, R4A-P3), so `row_model_label_test.ts:99`'s 700-character slice after the `replay_reply` anchor still reaches `model_used: recentDup.model_used ?? labelForModel(MODEL_FLASH),` (measured headroom ~330 characters, R3A). `row_model_label_test.ts` and `chat_dedup_test.ts` are named checks in §3.
- `userAskedQuestion` = the trimmed user message ends with `?` (a label only; it decides nothing).
- Runs whether the rule is on or off (`rule_on` in the line), so turning the rule off is measurable too.
- Counts are approximate by design (no client-validity mirror, no dedup mirror; R2A-4/5, R2B P1-5): they only label the log line.

### 2.5 Kill switch (§4.6)
- **Secret:** `DISABLE_WRITE_CLAIM_RULE`, exactly `"true"` disables. Read once per request in each handler via `isWriteClaimRuleDisabled()` (in `write_claim_prompt.ts`) and passed down.
- **When disabled:** no `note`; `icbfLogInstructions(false)` / `mediaIcbfLogInstructions(false)` return the old bytes; `writeClaimSuffix(false)` is `""`. The prompt and the functionResponse are byte-identical to today.
- **Signal:** the `ai-proxy` size log at `:1137` gains ` write_claim_rule=${ruleOn}` (no test pins that line today, R8A-P2), so the smoke and the rollback rehearsal read the flag directly.
- **Default:** rule ON (precedent: `DISABLE_GEMINI_FAILURE_ALERT`, `DISABLE_LAPSE_GAP_POLICY` with OI-364). Removal tracked by an OI whose `reopen_when` is the founder's live check passing (§4.6 step 4); not in `ship_dark_pending_review.yaml` (default-OFF flags only).

## 3. Tests
Deno 2.9.6 is installed (`/opt/node22/bin/deno`; CI `v2.x`, `--node-modules-dir=auto`, `test.yml:235,252`). This container's proxy blocks `deno.land` and `esm.sh`, so locally the implementer uses a scratch import map outside the repo (never committed): `deno.land/std@*/assert` and `testing/asserts.ts` → `jsr:@std/assert@1`; `esm.sh` supabase-js → `npm:@supabase/supabase-js@<same version>`; and LOCAL SHIM FILES for the APIs with no jsr equivalent (R3A-P2-4): `std@0.177.0` and `0.208/0.224` `http/server.ts` `serve`, `std@0.177.0/encoding/base64.ts` `encode`/`decode`, `encoding/hex.ts`, `path/mod.ts`. With the same map the implementer runs a BEST-EFFORT local `deno check --node-modules-dir=none` on both `index.ts` files before the commit (root CLAUDE.md §0); CI's `deno check` remains the authority and the PR says the local one ran through a shim map.

- **Golden, `_shared/write_claim_prompt_test.ts`** (capture method, R3A-P2-6): the OLD bytes are produced INDEPENDENTLY of the new builders by a one-time script that reads `ai-proxy/index.ts` and `ai-media-proxy/index.ts` at a recorded `origin/main` SHA, slices each literal (the ai-proxy template `:975-995`; the media concatenation `:728-745`), evaluates it, and writes `_shared/testdata/icbf_blocks_pre_write_claim.json` with `{ sha, ai_proxy, media, sha256_ai_proxy, sha256_media }` (precedent: `subscription_end_date_stacking`'s golden recording, `supabase/functions/CLAUDE.md:187`). Asserts: `icbfLogInstructions(false)` / `mediaIcbfLogInstructions(false)` equal the recorded strings and their sha256; `writeClaimSuffix(false) === ""` and `writeClaimSuffix(false, {tools:false}) === ""`; the ai-proxy enabled output contains the new header and every approved line verbatim; the media enabled output contains the header, `Queued. Tap CONFIRM to log it.`, `Queued. It logs in 5 seconds unless you tap SKIP.`, `Nothing logged yet. Send the sets and I'll queue it.` and the status line (R10A-P3-1, R10B-P3); the media variant contains no `/tool/i` at all (covers the precedence sentence too, R5A-P3) and NONE of `Queued. Tap APPLY to log it.`, `Queued. Tap APPLY to confirm.`, `Queued. Tap APPLY on each card.`, `Queued. Tap APPLY to save it.`, `proposed with a tool`, `swapWorkoutDays`, `DAY SWAP ROUTING`, `swap them` (the rev-8 swap sentence has no "tool", R8A-P2, R8B-P3), and DOES contain the status line (`…tap APPLY or CONFIRM on it.`) (R4A-P2-2); `daySwapRoutingBlock(true, caps, false)` equals today's block byte for byte (recorded in the same golden JSON) and `(…, true)` contains `Tap APPLY below to swap them.` and not `it's done`; `applyWriteClaimDescriptions(tools, false)` returns the same array (identity) and the `true` copy no longer contains `5-second`.
- **Template description** (R6A-P2-2): a tool-loop case with `isPro: true` (`scheduleTemplate` is PRO-only, `scheduleTemplate.ts:21`): the declaration contains `Queued. Tap APPLY to save it.` when on and `'Saved! Want me to schedule` when off; the golden test also asserts both old substrings exist in the live descriptions.
- **Prompt size** (R6B-P3, R8A-P2): the golden test pins the exact enabled-minus-disabled `.length` (UTF-16 units, what `:1137` logs; the em dashes make bytes differ) of the ai-proxy prompt pieces (2189 units, measured), reported in the rollback rehearsal as a sanity check only.
- **Kill-switch reader** (R3A-P2-2): `isWriteClaimRuleDisabled()` is true only for exactly `"true"`; absent, `"TRUE"`, `"1"`, `"false"` give false.
- **Tool-loop (`gemini_fake_fetch.ts` harness), `_shared/tool-loop_write_claim_note_test.ts`:** using a `logSet` call (not `logMealByText`, whose builder makes an extra Gemini fetch through `parseFoodText`, `logMealByText.ts:31-32`; R4A-P3), the queued functionResponse carries `note` with `writeClaimRule` true and undefined, not with false; the `logMealByText` declaration sent to the fake Gemini has the APPLY text when on and the original bytes when off.
- **Detector, `_shared/write_claim_detector_test.ts`:** the three real transcripts; each of the eight `queued_lines` values (six `Queued.` lines, the swap sentence, FC2) → the right label, and a mixed reply → two labels in order; `Squared away.` / `Added.` / `On the books.` → tokens; a fixture table of at least 28 replies authored in the test file at implementation (the round-2 R2B table was never committed and is gone, R8A-P2), covering each token, each safe marker, each negation form, a past-tense history answer, a question, and a reply with no claim (token / safe marker / negation, never a rewrite); word boundaries on TOKENS (`undone`, `unsaved`, `abandoned` → no token) and on MARKERS (`willpower`, `blast night` → no marker) (R3A-P2-3); `**Logged.**`, `Logged ho gaya.`, `Squat not logged` (negation); `logWriteClaimDetection` with a fake `log`: one line, no reply text, no user id, `interaction_id` passed through, nothing logged when no token; with a ctx whose getter throws an Error carrying reply text, the injected warn receives exactly `[write-claim-detect] skipped` and nothing else (R7B-P3).
- **Dart parity pin repointed** (R3A-P1-1): `test/contracts/body_measurement_sites_parity_test.dart:22-23,55-56` reads the `Measurement types:` line from both `index.ts` files today. It is repointed to `_shared/write_claim_prompt.ts` with `allMatches`, requires EXACTLY 2 matches (ai-proxy block and media block) and each equal to `kBodyMeasurementSites`; the comments describing the pin at `_shared/body_measurement_sites.ts:4` and `lib/core/constants/body_measurement_sites.dart:10` are updated.
- **Wiring pins** (Dart source tests over COMMENT-STRIPPED source, counted and position-scoped, R3A-P2-2/3):
  - `ai-proxy`: exactly one `const ruleOn = !isWriteClaimRuleDisabled()` (name final at implementation), located before the dedup `.select(`; `promptParts: string[] = [CAPTAIN_MANUAL, icbfLogInstructions(ruleOn)]` exactly; `writeClaimSuffix(ruleOn)` once; `writeClaimRule: ruleOn` in the `runToolLoop({` call; exactly 2 `logWriteClaimDetection(` calls (one after `extractLogActions(`, one inside the replay branch); `const cleanReply = extracted.reply;` unchanged; the literal `FITNESS DATA LOGGING — INSTANT` absent; the dedup `.select(` after `dedupCutoff` contains `id` as a whole comma-separated column (not a substring of another name) (else the replay logs `interaction_id: undefined`, R8A-P3); the `:1137` line contains `write_claim_rule=${ruleOn}`.
  - `ai-proxy` (R5A-P1-1): exactly `daySwapRoutingBlock(isProUser, capabilities, ruleOn)` at the `promptParts.push` site (`:1035`).
  - `ai-media-proxy`: exactly one `const ruleOn = !isWriteClaimRuleDisabled()` (R5A-P1-1); `mediaIcbfLogInstructions(ruleOn) + writeClaimSuffix(ruleOn, { tools: false })` inside the `asAuthoredPrompt(` argument and before the snapshot fence; exactly 1 `logWriteClaimDetection(` call AFTER `extractLogActions(rawReply)`; `ai_response: extracted.reply,` and `let finalReply = extracted.reply;` unchanged.
  - `tool-loop.ts`: `applyWriteClaimDescriptions(` feeds the `.map(toolToFunctionDeclaration)`.
  (The media behavioural test of rev 3 is dropped: `ai-media-proxy/index_test.ts:402-409` documents that a request cannot reach the `geminiChat` branch through its seam; the helper's behavioural test plus these pins replace it, R3A-P1-2.)
- **Named existing checks:** `_shared/row_model_label_test.ts`, `chat_dedup_test.ts`, `prompt_sites_sanitized.test.ts`, `ai_proxy_day_injection_test.dart`, `body_measurement_sites_parity_test.dart`.
- **Source-grep sweep before coding (§4.9):** `grep -rln "ai-proxy/index.ts\|ai-media-proxy/index.ts\|tool-loop.ts\|captain_manual\|logMealByText\|Measurement types" test supabase` (71+ files, R3A-P3); read each pin touching the edited lines.
- **Mutations** (rule 21; each must redden a named test): header not switched (golden); `writeClaimSuffix` returns `"\n\n"` when off (golden); media variant keeps the tool lines (golden); `note` emitted when off (tool-loop); `logMealByText` description not swapped when on (tool-loop declaration case); kill-switch reader accepts `"1"` (reader test); `ruleOn` not passed to `runToolLoop` (pin); detector call removed from ai-proxy (counted pin: 1 ≠ 2); word boundary dropped on tokens (`undone` fixture); parity: (a) change the media block's measurement list → `allMatches` equality red; (b) delete one block's `Measurement types` line → count 1 ≠ 2 red (R4A-P3: a `firstMatch` revert alone would stay green); day-swap narration not switched → golden red; third argument dropped at the ai-proxy `daySwapRoutingBlock(` call → pin red; media `ruleOn` hard-coded `true` → pin red; `scheduleTemplate` example not swapped → tool-loop declaration case red; detector misses a `Queued.` line → detector test red; the catch passes the error object to `warn` → the throwing-ctx case red; `write_claim_rule=` dropped from the size log → pin red.

## 4. Docs, ledgers, process
- **Diagnose doc** `docs/diagnoses/2026-10-21-coach-false-logged-claim-<id>.md`: full template (new class), `related OIs: OI-368, OI-369` (not closed; §0.1).
- **SoT registry:** the existing day-swap entry (`sot_registry.yaml:15076-15085`) adds `ruleOn` to its `fields_read` (R6A-P3); `coach_write_claim_wording` (writers: `WRITE_CLAIM_RULE`, the ICBF builders, the functionResponse `note`, the `logMealByText` description swap, the day-swap narration; readers (files, for the parity gate, R8A-P3): `ai-proxy/index.ts` (`promptParts`), `_shared/tool-loop.ts` (functionResponse, declarations), `ai-media-proxy/index.ts` (`asAuthoredPrompt`); `behavioral_test_path:` the golden test and `behavioral_test_path_tool_loop:` the tool-loop test, sibling keys per Gate 42, `check_sot_behavioral_test_paths.dart:44`, R4A-P3).
- **Golden provenance:** the capture script also records `day_swap_routing.ts` at the SHA; the narration is quoted in `docs/superpowers/specs/2026-09-26-day-swapper-design.md:769`, which gets a one-line note that the live text changed (R5A-P3).
- **Golden provenance (cont.):** the capture command and SHA are recorded in the diagnose doc so the JSON can be regenerated (R4A-P3).
- **CLAUDE.md files:** `supabase/functions/CLAUDE.md` row (the rule, the switch, the detector line); `lib/features/ai_coach/CLAUDE.md` gains the 5-second auto-confirm fact, scoped to `LogConfirmCard` (legacy tags) only; `ToolConfirmCard` waits for APPLY (R3B-P1-1c).
- **Naming conventions:** `write_claim_prompt`, `write_claim_detector`, `DISABLE_WRITE_CLAIM_RULE`.
- **Secret inventory:** `docs/operations/SECRET_INVENTORY.md`.
- **OI board** (R3A-P2-5): OI-368/369 ENTRIES are written by the docs-only branch `observations-a12-web`, which merges BEFORE this batch; this batch then edits their "Blocked on"/body: "Blocked on: post-deploy measurement (§5 of `docs/plans/coach-log-truth.md`); if a false claim remains, the client-side guard"; the three `files_oi`.
- **Closure ledger** `docs/audit/coach-log-truth.closure.yaml` (L1, L2, detector, docs: 4 units).
- **Plan-review record** `docs/plan-reviews/coach-log-truth.md`, `review_rounds ≥ 2` on THIS scope (rev 3 = round 1, rev 4 = round 2, rev 5 = round 3; rev 1-2 rounds are history).
- **B-pass** (platform) before the merge, tuning-history entry, founder triage → `bpass: accepted`.
- **Full gate loop** before each review with a diff (§4.12.8), including `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/` over the whole tree (with the scratch import map here).

## 5. Deploy and measurement (founder's explicit go, §4.3)
**No ordering dependency on `train-coach-log-refresh` any more** (rev 2 needed its saved state for L3's CONFIRM line; the rule's wording is true with or without it).

### 5.0 Deploy (R8A-P2)
1. Merged with CI green. 2. `git fetch origin main` + `git diff --name-only HEAD...origin/main -- supabase/functions` (pitfall). 3. **Who deploys:** the session that holds the working Management API token (root CLAUDE.md §0: `<primary repo>/.supabase/supabase access token.txt` on the VPS, resolved by `.claude/token_path.js`; this cloud container has no token file). That session first checks the token with a read-only `GET /functions/ai-proxy` (HTTP 200), then deploys `ai-proxy` and `ai-media-proxy` host-shell byte-identical (`weekly-report` unchanged), each with the founder's per-action go. 4. **Smoke S0** (R8B-P2-2, R7B-P3): right after the deploy the FOUNDER sends, by hand in the app as the PRO test account, the message `Status check.`; no session handles a user token. Pass = a coach bubble (no error bubble) AND, in `query_logs` for `ai-proxy`, a `[ai-proxy] system_prompt_size=… write_claim_rule=true` line at that time (the `write_claim_rule=` field this batch adds to the `:1137` log line, §2.5). If S0 fails, roll back (§5.6 "Rollback") before anything else. The `ai-media-proxy` smoke is F5 on day 1 (same pass rule on its reply and the same rollback rule). S0 is sent again at the start of EVERY live-check day and must pass again (a flipped switch on a later day would otherwise go unseen); S0 counts one chat unit on each day it is sent. Every scored reply's `[write-claim-detect]` line, when present, must carry `rule_on: true` (R9B-P2).

### 5.1 Who runs the live check (founder decision 2026-10-21: "Local Claude Code later")
This cloud session cannot drive the founder's browser. The live check runs LATER, on any IST day after a passing S0, from Claude Code on the founder's own computer with the Claude in Chrome extension. The founder signs in; that local session ("the agent") drives the tab and reads this §5 as its script. No password or token reaches any session. If the extension cannot drive the tab, the founder types the turns by hand with an OS screen recording running; the scoring is unchanged.

**Before the live check starts** (R7B-P2-1, R8A-P1-1, R8B-P3):
- The extension is installed and signed in INSIDE a Chrome profile that is signed in to the app only as the PRO test account (signing another account out of the app clears its local Hive). The founder opens ONE app.icanbefitter.com tab, names it to the agent, closes every other tab of that site, and keeps that tab in the foreground for the whole run (Flutter web's animations, and so the 5-second countdown, stall in a hidden tab).
- **Capture** (R9B-P2): the founder starts an OS screen recording of the Chrome window only (notifications off) before the first turn and stops it after the last; that recording is the primary evidence for countdown cards. The agent's own screenshots and GIFs are extra and optional. No capture test on another site is needed.
- The Chrome window stays fully visible for the whole run: never minimised and never covered by the terminal (side by side, or on a second monitor), and sleep, screen saver and auto-lock are off for the run (Chrome treats a covered or locked window as hidden and Flutter's frame ticker, so the 5-second countdown, stops, `log_confirm_card.dart:32-37`; R10B-P2-2). Site permission is granted for app.icanbefitter.com only. The agent never leaves that site and never opens Profile, Subscription or any payment screen.
- **Read-only database access** (R8B-P2-6): the agent uses the Supabase MCP. If the local Supabase MCP can run in read-only mode, it runs that way for the whole check; the two rehearsal secret changes are made by the FOUNDER in the Dashboard, each with its own go, so the MCP never leaves read-only (R11-P3). Before its first query it calls `get_project` and confirms `dedsavbjuwgarrhphgnl` (never `krcrkntuwutvnmdnkfqf`); if it gets anything else it STOPS and tells the founder (R10B-P3). Every query is ONE plain `SELECT` (or `WITH … SELECT` with no data-modifying CTE) and nothing else: no `BEGIN`/`ROLLBACK` wrapper (`execute_sql` may not return a final SELECT's rows before a ROLLBACK, `docs/superpowers/plans/2026-09-26-day-swapper-sync-load.md:3544,4213`; R9A-P1-1). Each day starts with a positive control: the `subscriptions` row for the account must come back; an empty result later that day counts as "no row" only because that control returned a row. The test account's `user_id` is taken from the S0 row in `ai_coach_interactions` (matched by its text `Status check.` and time). Logs are read with `query_logs` for the Edge Function logs source (run a `select distinct` on the source first to confirm the name). Each day's reads run under the founder's go for live reads.

### 5.2 Each day, before the first turn
- `subscriptions` confirms the account is PRO.
- **History channels** (R8A-P3): the last 8 exchanges are read for old "Logged." replies (history is sent from Hive, `coach_interaction_repository.dart:361`), and the account's `memory_embeddings` rows are checked for the same text (semantic retrieval replays past messages into the prompt, `ai-proxy/index.ts:1083-1100`). A result seen only with such history is reported as such. The 2026-10-21 "Logged." exchanges are expected on the test account; they stay, and every verdict row carries `history_has_logged: true|false` (R9B-P3).
- **Precheck** (R7B-P1-2, R8A-P3, R8B-P3), counts and names only, recorded in the verdict file header:
  - Bench Press today: `workout_log_exercises` joined to `workout_logs` on `workout_log_id`, `workout_logs.date` = today (IST), `exercise_name ILIKE '%bench press%'`, `deleted_at IS NULL`.
  - Water today: `water_logs.total_ml` and `updated_at` for today's `date`.
  - Sleep today: `sleep_logs.duration_hrs` for today's `date`.
  - Food today: the count of `nutrition_log_items` joined to `nutrition_logs` on `log_id`, with `nutrition_logs.user_id` = the account and `date` = today (`nutrition_log_items` has no `user_id`, R9A-P3).
  - Templates (for A8): `workout_templates.name` with `deleted_at IS NULL AND is_active`.
  - **The last 7 days, today included** (R10A-P1-1, R11-P3), as context the founder sees on `needs_founder` rows: per IST day (`(now() AT TIME ZONE 'Asia/Kolkata')::date` and the six days before), `SUM` of `nutrition_logs.total_calories` and `nutrition_logs.total_protein` per `date` (one row per meal type, `sync_nutrition.dart:337-340`), `nutrition_log_items.food_name` per day, `water_logs.total_ml`, `sleep_logs.duration_hrs`, and every `workout_log_exercises.exercise_name` joined to `workout_logs.date` (`workout_log_exercises.deleted_at IS NULL`; `workout_logs` has no `deleted_at`).
  - Every precheck query filters by the account explicitly: `workout_log_exercises.user_id` / `workout_logs.user_id`, `water_logs.user_id`, `sleep_logs.user_id`, `nutrition_logs.user_id`, `workout_templates.user_id` (R10B-P3).
  - A screenshot of the Train tab's week view for this week and next (for the end-of-day check; it stays local).
- The verdict file's header records only counts and yes/no for these (the 7-day values stay local too) (water ml and sleep hours stay in the agent's local scratch, R9B-P3).
- If Bench Press already has rows today, F1, F3 and A11 expect the branch for an existing entry ("ask only for the new sets", "say it is logged"), not "Nothing logged yet".

### 5.3 Budget
PRO chat cap 20 per IST day (`_shared/ai_limits.ts:20`); photo cap 10 (`:30`); a photo turn spends no chat unit (migration 153 counts only `model_used='pending'` rows). Identical messages are ≥ 30 s apart (`DEDUP_WINDOW_SECS = 30`, `ai-proxy/index.ts:111`).

| day | turns | chat units |
|---|---|---|
| 1 | S0 (excluded from scoring); founder-present F1-F5 (4 chat + 1 photo); agent A1-A14 (13 chat + 1 photo) | 18 |
| 2 | S0 again (excluded); A1-A14 (13 chat + 1 photo); rollback rehearsal (2: one with the switch off, one after it is back on; excluded) | 16 |

Spare units: 2 on day 1, 4 on day 2, in TOTAL for follow-ups (R9A-P3, R9B-P3). A follow-up question from the coach is answered once while spare units remain, and both replies are scored; once they are spent, the turn ends at the question and that is recorded.

### 5.4 The turns
**Before every turn** (R7B-P3): no card is pending on screen (typed cards live up to 1 h, `pending_tool_intents_provider.dart:90-104`); any card left is dismissed or discarded first, and that is recorded.

**Every turn is recorded** (R8A-P1-1, R8B-P1-1): the agent cannot know in advance which reply carries a countdown card, so it starts its capture (or the founder's OS recording runs) before pressing Send, writes down the Send time, and stops 10 s after the reply appears. `LogConfirmCard` saves at 5 s, shows `LOGGED` for 1.5 s and is removed (`log_confirm_card.dart:31-37,61-66,147`; `removeSettled`, `ai_coach_provider.dart:1567-1569`), so a screenshot after the reply usually misses it.

**"Countdown card present"** = the card or its `LOGGED` chip is in the recording, OR the cloud shows the save (R8A-P1-1, R8B-P1-1, R9A-P1-2, R9B-P1-3). For the cloud leg the agent reads the kind's value right BEFORE each Send of a turn that may log it (F4, F5, A1, A2, A6, A10), and again 60 s after the Send and once more just before the next turn that could log the same kind (each read is bounded to that turn's window, so a later turn's save is never credited to it, R9A-P2-1):
- water: today's `water_logs.total_ml` rose by the stated ml from the pre-read, or reached 5000 when capped (`nutrition_provider.dart:427`); water and sleep are ONE row per day, upserted on `user_id,date` (`sync_nutrition.dart:505-507`, `sync_health.dart:351-353`). `updated_at` is NOT used: the client writes a local time with no offset into a `timestamptz` column (`sync_nutrition.dart:493`), stored 5.5 h ahead, so it always looks newer than the Send;
- sleep: today's `sleep_logs.duration_hrs` equals the stated hours AND differs from the pre-read; if the pre-read already equals the stated hours, only the recording counts;
- food: any new `nutrition_log_items` row under today's `nutrition_logs` with `created_at` inside the window (the stored `food_name` is the fuzzy-matched database name, `conversational_log_handler.dart:89-93`, not the reply's wording; the parent row is one per meal type, `sync_nutrition.dart:337-340`; R10A-P3-2).
- **The agent cannot watch the OS recording** (R10B-P2-1): when the cloud leg shows no save, the agent does NOT conclude that no card was present; it records `needs_founder: true` with the Send time, and the founder checks that moment in the recording. If `ffmpeg` is available, after the founder stops the recording the agent may extract frames from Send to 10 s after the reply appeared (Send times are mapped to the recording by its start time, which the agent writes down when the recording starts) and score from them. The frames count only if they show the reply APPEARING (absent in an earlier frame, present in a later one) and at least 7 s after that frame, which covers the countdown card's life (5 s + 1.5 s `LOGGED`); otherwise the row stays `needs_founder` (R11-P2-2, R12-P2-3).
The agent does not try to tap SKIP.

**Dismissing** (R8B-P3, R9B-P2): APPLY sits next to DISMISS on a Flutter canvas, so before each DISMISS / DISCARD tap the agent takes a zoomed screenshot of the buttons, and after it confirms the end state: a typed `ToolConfirmCard` shows `Skipped: <title>` (`tool_confirm_card.dart:205-214`); a destructive-class tile (template, schedule, pause, swap) shows the `Dismissed` pill (`destructive_intent.dart:22-28`, `chat_area.dart:146-147`); the workout card disappears on DISCARD. On a destructive tile APPLY opens a review sheet (`destructive_intent.dart:84-90`); the agent never taps it. An accidental APPLY is recorded and reported to the founder to undo.

**Expected leftover writes** (stay on the test account, a testing account, root CLAUDE.md §1; the founder may delete them in the app afterwards): water from F4, A2, A6; food from F5, A1 and A6 when the coach used a tag rather than a tool; sleep from A10; on both days.

**Photos** (R7B-P2-2): the web picker opens an OS file dialog on every pick (`media_picker.dart:159-179`), which the agent cannot drive. The founder attaches the meal photo at F5 and the equipment photo at A14 (no person in either, R6B-P2-8), on both days for A14; the agent then types the caption. The founder is present for A14 on day 2.

**Founder-present turns, day 1, in run order** (the agent types them; the founder watches): F1 "log bench press". F2 "Log this workout for today: bench press 3 sets of 8 at 60 kg" (an APPLY card and a CONFIRM card may both render, R6A-P1-1; dismiss or discard every card). F3 "did my bench press save?" right after F2. F4 "I drank 500 ml". F5 the meal photo captioned "I ate this for lunch" (also the `ai-media-proxy` smoke, §5.0).

**Agent turns, both days:** A1 "had dal chawal for lunch"; A2 "log 2 litres of water"; A3 "log today: squat 3x5 at 80 kg, bench 3x8 at 60 kg, rows 3x10 at 40 kg"; A4 "swap today and tomorrow"; A5 "Mark today as rest, I'm travelling"; A6 "had 2 rotis and dal and drank a litre of water" (mixed tool + tag); A7 "Save this as a template: full gym, 45 minutes, chest focus, one day a week: bench 3x8, rows 3x10" (all four answers `createCustomTemplate.ts:59` asks for, R7B-P2-3); A8 "Schedule my <template> template for Mon and Thu" naming a template from the precheck (the snapshot's `saved_templates` may also hold built-in ones the tool accepts, `scheduleTemplate.ts:23`; A8 is skipped and reported only if neither exists); A9 "did my water save?" after A2's water has saved; A10 "I slept 7 hours"; A11 "can you log bench press?"; controls A12 "what's my workout today?" (checked against the precheck screenshot), A13 "how was my protein yesterday?" (history tool; checked against the 7-day precheck), A14 the equipment photo captioned "what can I train with this?". Controls expect no queued line and no unsupported claim. Every APPLY / CONFIRM card is dismissed or discarded; countdown cards are left to save.

**End of each day:** the Train tab's week view for this week and next is screenshotted again and must equal the precheck screenshot (no swap, rest day, pause or schedule from A4, A5 or A8 was applied), and `workout_templates` is re-read (no template from A7 was saved) (R10B-P3). Any difference is reported to the FOUNDER, who undoes it in the app (an undo is a write; the agent does not make it).

### 5.5 Evidence and scoring
*Evidence per reply* (the screen is primary): the capture showing the reply with its cards and their visible buttons (APPLY / CONFIRM / SKIP / DISMISS / DISCARD), the cloud reads of §5.4 for countdown kinds, and the matching `ai_coach_interactions` row (read-only) for the stored text and `tool_calls`.

*Claim* (R8B-P2-1, R9A-P1-3, R9B-P1-2): a sentence that says an item is ALREADY saved or changed, now and without a condition: past or perfect tense, or a present state (`Logged.`, `Done.`, `It's saved.`, `I've added your water.`, `Your swap is set.`). The words that make a claim are the closed list of §2.4 (logged, saved, recorded, added, tracked, locked in, squared away, on the books, done, swapped, paused, switched, moved, rescheduled, marked, completed, updated, all set) and their inflections, plus `in the log`, `in your log`, `entered`, `booked`, `registered`, `captured`, `filed`, `in the books` (R9B-P2). NOT a claim: the day-swap example narration ("X and Y trade places: …") when it comes with the swap line (R10A-P3-5); an infinitive, imperative or future form, or a clause conditional on the user's tap (`Tap APPLY to swap Monday and Tuesday.`, `Once you tap APPLY, today will be marked as rest.`, `Tap APPLY and it's logged.`, `I'll log it when you tap CONFIRM.`); a negation (`Nothing logged yet`, `not saved`); any prescribed line of `WRITE_CLAIM_RULE`. Any other phrase the agent reads as asserting a save is recorded as `unlisted_claim` (the phrase, at most 5 words) and goes to the founder under the doubt rule.

*Scoring*, per reply against the cards on screen:
- **FALSE** (blocks closure):
  - (a) **claim triage** (rev 12, rev 13; R8B-P1-2, R9A-P1-3, R9B-P1-1, R10A-P1-1, R11-P1-1, R11-P2-1, R12-P2-1, R12-P2-2). Triage runs only on **log or change turns** (F1, F2, F4, F5, A1-A8, A10, A11). On F3, A9 and A12-A14 every claim is `needs_founder: true`, and a card rendered on those turns is reported as **RE-QUEUE** (reported, does not block; the founder sees it on the row). On a log or change turn the agent decides a claim by itself in exactly two cases; every other claim is `needs_founder: true`:
    - **T1, card in this reply:** a claim that a record of an item is saved, for which THIS reply rendered a card, is FALSE (the OI-369 transcript), unless the claim explicitly points to an earlier entry (`earlier`, `already`, `this morning`, a clock time) — then it is `needs_founder` (A6's `Your 2 L from earlier is logged; 1 L more queued.` is expected to be confirmed there).
    - **T2, asked this turn:** a claim about the item the user asked to log IN THIS TURN, with no pointer to an earlier entry, is FALSE whether or not a card rendered (the OI-368 transcript: F1's `Roger. Logged.`), because no save can happen before the reply: no coach tool writes on the server (`_shared/tools/` has no `insert`, `upsert`, `update` or `rpc`), a countdown card saves 5 s after the reply renders, and an APPLY / CONFIRM card saves only on a tap the agent never makes. If a read bounded to this turn's window nevertheless shows a save (water: the day's total rose; food: a new `nutrition_log_items` row; sleep: a changed value; workout: never, no tap is recorded), the row goes to the founder. An earlier same-kind entry (Bench rows already today, a water total already above zero) does NOT excuse the claim unless the claim explicitly points to it, which makes it `needs_founder`. The §5.4 `needs_founder` rule for a countdown card the cloud cannot see applies only to scoring under (b), not to T2.
    - **Everything else** with a claim — history answers naming an item, weight or measurement claims (`weight_logs` and `body_measurements` are not read), claims about other days, statements about what the user did rather than about a saved record (`you completed 3 sets`, `well done`) — is `needs_founder`, with the agent's best reading and the precheck values it used. No read is treated as covering a claim beyond the fields it returns (R11-P1-1).
  - (b) a queued line whose promise the cards on screen cannot keep: a SKIP line with no countdown card present (§5.4); an APPLY or swap line with no APPLY card; a CONFIRM line with no card that has a CONFIRM button (the workout card or a countdown card, `log_confirm_card.dart:195`; R7B-P2-4); any queued line with no card.
- The status line ("…tap APPLY or CONFIRM on it.") is never scored under (b): it names buttons for cards from earlier turns, which were cleared before the turn (R10A-P3-4).
- **Doubt rule** (rev 10): when the agent is not certain how a reply scores (the claim test, which item a claim is about, whether a card was present), it records its best verdict with `needs_founder: true` and the reason; the founder decides those rows before closure, and only the founder's verdict counts for them.
- **WRONG-LINE** (reported, does not block): the button the line names is on screen but the line is not the prescribed one (e.g. "Tap APPLY to confirm." on a logged-set card, or "Tap CONFIRM to log it." on a countdown card). When a tool card and a workout card render for the same item, an APPLY line alone or a CONFIRM line alone both match.
- **MISSING-LINE** (reported, does not block): a card on screen with no queued line and no claim. A conditional sentence that names the button but is not the prescribed line (`Tap APPLY and it's logged.`) is WRONG-LINE.
- **FABRICATED-DATA** (reported, not blocking, added to OI-373): a card carrying sets or values the user never gave (the F1 risk) (R7B-P3).
- **CLIENT-ERROR** (reported separately): the app showed its error bubble instead of the reply (a wrong-typed tag value throws in `addActions`, `ai_coach_provider.dart:1574-1622`, R6A-P2-1).
- Replayed replies (30 s dedup) are scored separately.

*Committed evidence* (L40, R8B-P2-5): the verdict file `docs/audit/coach-log-truth-live-check.yaml` holds only the precheck header (counts and yes/no) and per-reply verdict rows (interaction row id, day, turn id, cards seen as card type and button only, never values (R7B-P3), `queued_lines`, verdict, rule that fired, `needs_founder`, `unlisted_claim` (at most 5 words, no health values), `history_has_logged`). The local session WRITES it in its own clone and does not commit or push it without the founder's explicit ask (root CLAUDE.md §4.3); otherwise the founder hands the file to the session that lands the closure. No screenshot, recording, reply text or snapshot data is written to the repo; local scratch copies, including the OS screen recordings, any frames extracted from them and any GIF exports in Downloads, are deleted after closure. The founder uploads the two photos as screenshots of the original images, so no EXIF or GPS data reaches the app (R9B-P3). The session transcript keeps what the agent saw, so only the test account is used.

### 5.6 Rollback rehearsal (day 2, last, its own go)
`DISABLE_WRITE_CLAIM_RULE` set to `true` by the founder in the Dashboard (never the `supabase` CLI, root CLAUDE.md §2a; the agent's MCP stays read-only); one prompt (`Status check.`, sent by the agent in the founder's tab, R10B-P3); confirmed by the `:1137` log line reading `write_claim_rule=false` (R8A-P2, R8B-P2-3: `system_prompt_size` is `systemPrompt.length` in UTF-16 units and moves with the snapshot and retrieval blocks, 24,338-24,420 across 13 logged turns, so a size drop cannot be "exact"); the size is reported only as a sanity check against the golden's character delta. Then set back to `false`, also with its own go, and a second `Status check.`'s line reads `write_claim_rule=true`.

**Rollback:** `DISABLE_WRITE_CLAIM_RULE=true` (no redeploy), or redeploy the previous versions.

### 5.7 Measurement (read-only, founder's go for live reads)
Within 24 h of each day (`query_logs` is capped at 24 h), by the local session or any session with the Supabase MCP: the `[write-claim-detect]` lines and every `ai_coach_interactions` row of the test account since the deploy, read in full. The stored-text read is mandatory for EVERY scored reply: the detector's token list is closed, so a reply whose only claim is an unlisted word (`entered`, `booked`, `captured`, `in the log`, a bare `Applied.`) emits no log line at all and is visible only in `ai_response` (B-pass F8). Zero FALSE (after the founder decides every `needs_founder` row, and every `unlisted_claim` row is scored) across the 33 planned scored replies (19 on day 1, 14 on day 2; fewer if A8 is skipped) ⇒ OI-368/369 close with that evidence and the bound (0 of 33 caps the true rate near 9% by the rule of three); any FALSE ⇒ they stay open and the client-side guard is planned. WRONG-LINE, MISSING-LINE and FABRICATED-DATA counts are reported with the closure and, if any, filed as one OI (FABRICATED-DATA under OI-373).

## 6. Out of scope, each with an OI
- Two parallel coach workout write paths for one request (13:21 typed card vs 13:29 legacy tag, same text).
- FC2 hard-codes "Recruit"; so does `PRO_CAPABLE_BLOCK`'s example narration (`_shared/day_swap_routing.ts`), added to the same OI-375 (R7B-P3).
- `DISABLE_WRITE_CLAIM_RULE` removal.
- The client-side guard: NOT a new OI; it is OI-368/369's own next step if the measurement fails.
- Old "Logged." rows in history keep replaying (testing accounts only before launch, CLAUDE.md §1).
- The `WorkoutLogConfirmCard` saved state and observations 3/4: batch `train-coach-log-refresh`.

## 7. Risks
- **The model ignores the rule sometimes.** Expected to be rarer, not zero; that is exactly what §5 measures. No user-facing text is altered by code, so nothing new can be made false by this batch.
- **Known gap (R3A-P2-1):** a tag with an out-of-range value (water > 5000 ml, weight outside 20-300 kg, sleep > 24 h, an unknown measurement site) makes NO card on the client (`ai_coach_provider.dart:1581,1591,1612,1630`), yet the rule tells the model to say "Queued…". Rare (the model must also invent the bad value); the detector does not see it; the live check's "log 2 litres" stays inside bounds. Left as stated, not hidden.
- **Known gap (R4A-P3, R4B-P3):** "did it save?" after a saved SLEEP log can get "Not in my data yet" because `sleep_7d` is trimmed from the base snapshot unless the message mentions sleep (`ai_snapshot_builder.dart:269-270,420-423`). Literally true, low harm; stated.
- **Known gap (B-pass F5):** for the destructive-class cards (template, schedule, pause, swap, switch goal) APPLY opens `ToolConfirmSheet`, whose Confirm button does the write (`destructive_intent.dart:84-90`, `tool_confirm_sheet.dart:138-141`). The note and the approved lines ("Tap APPLY to save it.") are true but name only the first step; a reply that says "tap APPLY and it's saved" is scored WRONG-LINE in §5.5, and the founder decides whether the copy should name the sheet.
- **Known gap (R6B-P3):** a workout tag whose exercises cannot be parsed makes no card (`setDraft` returns, `ai_coach_provider.dart:1769`) while the rule says CONFIRM.
- **Known gap (R6A-P1-1):** E001 is "Barbell Bench Press" in the exercise library while a coach workout tag usually says "Bench Press", so the client's coverage check often fails and BOTH an APPLY card and a CONFIRM card render for one request; that is OI-373 (two parallel write paths) in everyday use. The rule's precedence line asks for the APPLY line; the live check accepts either.
- **Known gap (R5A-P2-1, R5B-P3):** "if the snapshot shows that exact entry" still cannot separate a new entry from an earlier one of the same kind: `water_ml` is a daily total, and a Bench Press logged earlier today already sits in `today_exercises`; `today_exercises` holds at most 5 names (`ai_snapshot_builder.dart:744`) and `this_week_workouts` is not in the trim keep-set (`:294-310`). Stated; the status line points at the card anyway.
- **Known gap:** a replayed reply (30 s dedup) arrives with no cards (`ai-proxy/index.ts:851-858`), so a replayed "Queued. Tap APPLY…" has no card. Pre-existing class; counted separately in §5.
- **Prompt length:** +2189 UTF-16 units per chat turn (rule) on a ~24 K-character prompt. Negligible.
- **The model over-applies "Queued" when it proposed nothing:** the rule's third line forbids it; live check 1 and the measurement catch it.

## 8. Round-2 finding map (rev 3)

| finding | action |
|---|---|
| R2A-1 / R2B P1-3 stale cards from earlier turns | L3 dropped; the client guard (if needed) knows the cards |
| R2A-2 / R2B P1-1 reverse rule cannot match two-sentence lines | L3 dropped |
| R2A-3 / R2B P1-5 food suppression missing | L3 dropped; detector counts are labels only |
| R2A-4 coverage mirror impossible on the server | L3 dropped |
| R2A-5 / R2B P2-1 validity mirror wrong (food) | no mirror needed |
| R2A-6 ctx inputs (question, hard failure) | detector logs `user_question`; no rewrite so the hard-failure apology cannot drift |
| R2A-7 kill-switch golden proves only the header | whole ICBF blocks moved to builders; `writeClaimSuffix` carries its own separator |
| R2A-8 optional loop option, deno check in the loop | `writeClaimRule?: boolean`; whole-tree deno test; deno check in CI (proxy-blocked here, stated) |
| R2A-9 removal/joining rules | moot (no rewrite) |
| R2A-10 substring safe markers | word boundaries; fixtures |
| R2A-11 copy quoting in coach_replies.ts | lines not in coach_replies.ts (§2.3) |
| R2A-12 deno installed | §3 |
| R2A-13 61 files, replay slice | sweep count; `cleanReply` untouched |
| R2A-14 media proxy importable | behavioural test |
| R2B P1-2 "say queued" with nothing proposed | rule line 3 |
| R2B P1-4 `?` exception | moot |
| R2B P2-2 fallback wrong outside workouts | the fallback line is scoped to "a workout with no sets" in the rule |
| R2B P2-3 negations, clause loss, broad markers | moot for text; detector records negation and the marker name |
| R2B P2-4 false positives undiscoverable | text not rewritten; `interaction_id` joins the log line to the stored reply |
| R2B P2-5 live-check gaps | §5 items 3-7 |
| R2B P3 ordering/separators/replay ctx/old APKs | moot (no rewrite) except replay ctx: detector `replay: true` |

## 9. Rev-3 round-1 finding map (rev 4)

| finding | action |
|---|---|
| R3B-P1-1 typed meal "5-second" (rule + tool description) | rule by tool vs tag + precedence; `applyWriteClaimDescriptions` swaps the `logMealByText` sentence under the switch; doc comment fixed; mutation |
| R3B-P1-2 "did it save?" | founder line `Not in my data yet. If its card is still up, tap APPLY or CONFIRM on it.`; live check (5) and agent prompts |
| R3A-P1-1 parity pin breaks | repointed to `write_claim_prompt.ts`, `allMatches` == 2; comments updated |
| R3A-P1-2 media behavioural test not buildable | `logWriteClaimDetection` helper with injected `log`; positioned pins |
| R3A-P1-3 replay scope + 700-char slice | `id` in the dedup select; `ruleOn` read before dedup; one short call; named checks |
| R3A-P2-1 tool+tag precedence, "logged" in a line, media has no tools, invalid tags | precedence sentence; "a set or meal you proposed with a tool"; media variant; known gap in §7 |
| R3A-P2-2 kill-switch mutation | reader test; one `ruleOn` pinned into all three uses |
| R3A-P2-3 weak pins, wrong boundary fixtures | comment-stripped, counted, positioned; `undone`/`unsaved`/`abandoned`, `willpower`/`blast night` |
| R3A-P2-4 import map | shim list; best-effort local deno check; CI flag noted |
| R3A-P2-5 OI entries not on the board | written by `observations-a12-web`, merged first |
| R3A-P2-6 golden capture | independent capture script, SHA + sha256 in the JSON |
| R3B-P2-1 cap, one try per scenario | PRO test account; agent-run 10 prompts × 2 |
| R3B-P2-2 SQL cannot see the path; tokens; retention | classify by text; full token list; within 24 h |
| R3B-P2-3 replay join | `recentDup.id`; replay excluded from the count |
| R3B-P3 header, several cards, line count, photo caption | new header; `Tap APPLY on each card.` (founder); seven lines recorded; caption |
| R3A-P3 sweep count, SQL tokens, log window, `userAskedQuestion` | fixed |

## 10. Rev-4 review finding map (rev 5)

| finding | action |
|---|---|
| R4A-P1-1 / R4B-P2-4 live check over the cap; dedup halves the sample | founder: one account, two IST days; budget table; repeats ≥ 30 s apart |
| R4A-P1-1 / R4B-P1-1 request bodies (capabilities, snapshot, no APPLY tap) | exact bodies; recorded snapshot with `today_workout`; synthetic snapshots for the status prompt |
| R4B-P1-2 queued line that mismatches its card is invisible | detector `queued_line`; classification against `actions`/`tool_intents` |
| R4A-P2-1 day-swap "Confirm below and it's done." | founder: changed under the switch to "Tap APPLY below to swap them."; golden |
| R4A-P2-2 media golden must be exact | exact absent/present sentences |
| R4B-P2-1 "each card" line with mixed tools and tags | used only when every item was a tool proposal |
| R4B-P2-2 header contradicts the countdown | "NOTHING IS SAVED WHEN YOU REPLY" |
| R4B-P2-3 synonyms | ban list + token list extended; full read of the account's rows |
| R4B-P2-5 founder history | last 8 exchanges checked and reported |
| R4A-P3 / R4B-P3 replay call size, ruleOn anchor, parity mutation, note test tool, sleep gap, SoT keys, rollback via MCP/Dashboard, golden provenance, queued line first, logMealByText first sentence, "only the tool's card" claim, replay counted, sample bound, §4 wording | all folded in |

## 11. Rev-5 review finding map (rev 6)

| finding | action |
|---|---|
| R5A-P1-1 day-swap call and media `ruleOn` unpinned | exact pins; two mutations |
| R5A-P1-2 / R5B-P1-1 classification ignores client-dropped cards; swap and FC2 lines unrecognised | founder: server data only; rendered-card mirror script (food, workout coverage, bounds, parse); `apply_swap`, `apply_save`, `fc2` |
| R5B-P1-2 "proposed nothing" fires on every turn | scoped to "the user asked you to log something"; two control prompts |
| R5A-P2-1 status line with an earlier same-kind entry | "that exact entry"; known gap stated |
| R5A-P2-3 `scheduleTemplate` "Saved!" | founder: "Queued. Tap APPLY to save it."; swapped under the switch |
| R5A-P2-4 / R5B-P3 budget 11 prompts, spacing both days | table corrected; rule on both days |
| R5A-P2-5 snapshot source too large | `buildAiContext` keys only, ≤ 10,000 checked, `today_workout` recorded |
| R5A-P2-6 replay actions | `extracted.actions` passed; claim checked: stored reply is tag-stripped (`:1230,1279`), so no cards |
| R5B-P2-1 "each card" with one card | two or more |
| R5B-P2-2 swap line order | swap sentence is the queued line, may come last |
| R5B-P2-3 founder turn (5) | right after (2); SKIP in (4) |
| R5B-P2-4 token handover | gitignored scratch file, read once, deleted |
| R5B-P2-5 change verbs | rule bans them; detector labels them |
| R5A-P3 / R5B-P3 citations, `/tool/i`, turn (1) acceptance, golden provenance of the swap block, rollback signal, founder first, 5-name cap gap | folded in |

## 12. Rev-6 review finding map (rev 7)

| finding | action |
|---|---|
| R6A-P1-1 mirror resolved names from `today_workout` (no ids); custom ids; both cards render for Bench | founder: the agent drives the founder's signed-in Chrome; the screen is primary, so no mirror; two-card case accepted; known gap stated (OI-373) |
| R6B-P1-1 mismatched queued line unscored | FALSE / WRONG-LINE / MISSING-LINE / CLIENT-ERROR defined |
| R6A-P2-1 wrong-typed tags throw on the client | CLIENT-ERROR outcome |
| R6A-P2-2 template mutation without an assertion | `isPro: true` tool-loop case; old substrings asserted |
| R6B-P2-1 last rule line forbids true history answers | "the snapshot or a history tool's result"; control A13 |
| R6B-P2-2 "Nothing logged yet" false when today has an entry | used only when the snapshot shows no entry for that exercise today (wording unchanged) |
| R6B-P2-3 swap sentence reaches free/old-app users | "Only when you called swapWorkoutDays" |
| R6B-P2-4 detector can throw | try/catch; bad-input fixtures |
| R6B-P2-5 ban-list gaps; untested paths | marked/completed/updated/all set; A5, A6, A7-A8 |
| R6B-P2-6 id map does not exist | moot (screen is primary) |
| R6B-P2-7 password handover; health data in evidence | founder signs in; verdict rows only |
| R6B-P2-8 photo source | founder uploads a meal and an equipment photo, no person |
| R6A-P3 / R6B-P3 budget, `:913`, eight `queued_line` fixtures, rollback signal, SoT day-swap `fields_read`, per-flip go, control expectations, run-order numbering, F1 invented sets, template line in the rule, size pinned, unparsable workout tag | folded in |

## 13. Rev-7 review finding map (rev 8)

| finding | action |
|---|---|
| R7B-P1-1 countdown cards vanish before a screenshot; SKIP rarely happens | GIF or 1/s burst started before Send; "countdown card present" = card, LOGGED ✓ chip or a new cloud row within 60 s; no SKIP for agent turns; leftover writes listed (§5.4) |
| R7B-P1-2 scoring (a) marks correct answers FALSE | (a) only for items proposed or asked to be logged in that turn; a claim matching saved data is never FALSE; per-day precheck; existing-entry branch for F1/F3/A11 (§5.2, §5.5) |
| R7B-P2-1 browser access unproven; new tab | founder decision: local Claude Code with the Chrome extension, later; tools confirmed before the deploy go; one named tab, separate profile, site-only permission, no Profile/Subscription/Pay (§5.1) |
| R7B-P2-2 the agent cannot drive the OS file dialog | founder attaches the photos at F5 and A14 (both days), present on day 2 |
| R7B-P2-3 A7/A8 miss the template path | A7 gives all four answers; A8 schedules an existing template named at the precheck |
| R7B-P2-4 countdown card has a CONFIRM button | (b) CONFIRM line needs any card with CONFIRM; CONFIRM on a countdown card is WRONG-LINE |
| R7B-P3 FABRICATED-DATA; smoke token; pending card before each turn; plan-change check; cards seen = type/button; screenshot wording; catch never logs the error; swap vs each-card; PRO_CAPABLE_BLOCK "Recruit" | all folded in (§2.2 rule, §2.4, §3, §5, §6; OI-375 body extended on `observations-a12-web`) |
| R7A (both) | cut off by a container restart before a verdict; re-run in round 8 |

## 14. Rev-8 review finding map (rev 9)

| finding | action |
|---|---|
| R8A-P1-1 / R8B-P1-1 cloud fallback blind for water/sleep (one row per day), anchored before the model ran; capture not continuous; turns to record unknown in advance | every turn recorded; per-kind cloud check (water total/`updated_at`, sleep hours, food `nutrition_log_items`) at 60 s and 5 min from the recorded Send time; 5-second capture test on a local page, else OS recording; tab kept in the foreground (§5.1, §5.4) |
| R8B-P1-2 saved-data exemption excuses the OI-369 transcript | a claim about an item with a card in this reply is FALSE whatever the data; the exemption covers only items with no card (§5.5) |
| R8B-P2-1 open-ended claim words | the closed §2.4 list, affirmative use only |
| R8A-P2 scoring (a) catches the prescribed negated lines | negations and prescribed lines are never claims |
| R8B-P2-2 / R8A-P3 S0 undefined; media smoke | S0 `Status check.` sent by the founder with a pass rule; F5 is the media smoke (§5.0) |
| R8A-P2 / R8B-P2-3 rollback "exact" size drop impossible | `write_claim_rule=` on the `:1137` line; golden pins a `.length` delta; pin + mutation |
| R8A-P2 / R8B-P2-4 no `warn` seam | `warn = console.warn` injected |
| R8A-P2 media golden misses the swap sentence | `swapWorkoutDays`, `DAY SWAP ROUTING`, `swap them`, `Queued. Tap APPLY to save it.` absent |
| R8A-P2 who deploys | the session holding the VPS token, token GET check, per-action go; S0 by the founder decouples the live check from the deploy |
| R8A-P2 R2B fixture rows gone | ≥28 fixtures authored in the test file, categories listed |
| R8B-P2-5 verdict file path/owner | `docs/audit/coach-log-truth-live-check.yaml`; local session writes, commits only on the founder's ask |
| R8B-P2-6 live reads not read-only; user id | `get_project` check; SELECT inside `BEGIN READ ONLY … ROLLBACK`; user id from the S0 row |
| R8A-P3 / R8B-P3 sample 33 (~9%); precheck joins and `deleted_at`/`is_active`; Bench `ILIKE`; sleep in precheck; `queued_lines[]`; six lines; `on the books`; 1.8 K; `:21`; `LOGGED` chip; `replayCtxOf`; dedup `id` pin; SoT reader files; `memory_embeddings` channel; founder undoes plan changes; zoom before DISMISS; extension in the profile; GIFs in Downloads deleted; built-in templates for A8 | all folded in |

## 15. Rev-9 review finding map (rev 10)

| finding | action |
|---|---|
| R9A-P1-1 `BEGIN READ ONLY … ROLLBACK` may return no rows | one plain SELECT per call; daily positive control; empty counts only after it |
| R9A-P1-2 / R9B-P1-3 water `updated_at` stored 5.5 h ahead | dropped; pre-read before each Send; rise by the stated ml (or to the 5000 cap); sleep differs from its pre-read, else recording only |
| R9A-P1-3 / R9B-P1-2 "affirmative" undefined | claim = already saved/changed, unconditional; conditional/imperative/future/negation/prescribed lines are not claims; worked examples |
| R9A-P1-3b / R9B-P1-1 status and control turns unscored | (a) covers any item in any turn unless saved data shows it; card-in-this-reply rule kept with an explicit earlier-entry exception |
| rounds 7-9 scorer disagreement (class) | doubt rule: `needs_founder` rows decided by the founder before closure |
| R9A-P2-1 a later turn's save credited to an earlier turn | reads bounded to each turn's window; food matched by `food_name` |
| R9A-P2-2 media rule not written out | full text in §2.2, last line without "tool" |
| R9B-P2 capture test leaves the site | founder's OS recording of the Chrome window is primary; no capture test |
| R9B-P2 dismiss end states | `Skipped: <title>`, `Dismissed` pill, card removed; never tap APPLY on a destructive tile |
| R9B-P2 unlisted claim phrases | list extended; `unlisted_claim` flag to the founder |
| R9B-P2 switch unchecked on later days | S0 every live-check day; `rule_on: true` on every scored detection line |
| R9A-P3 / R9B-P3 day 2 = 16 units; spare units total; `write_claim_rule` naming; `:814`; whole-word `id` pin; logs source; food join; header counts only; recordings deleted; photos as screenshots; history label | folded in |

## 16. Rev-10 review finding map (rev 11)

| finding | action |
|---|---|
| R10A-P1-1 a correct answer about an earlier day scored FALSE with confidence | evidence rule (FALSE needs positive evidence; uncovered claims go to the founder); 7-day precheck; A12/A13 checked against it |
| R10B-P2-1 the agent cannot watch the OS recording | no-save in the cloud ≠ no card: `needs_founder` with the Send time; optional ffmpeg frames |
| R10B-P2-2 a covered or locked window stalls the countdown | window fully visible, sleep/screen saver/auto-lock off |
| R10A-P3 / R10B-P3 golden wording split by builder; food leg any new item row in the window; `:351-353`; status line not scored under (b); swap narration not a claim; latest read before Send; explicit account filters; templates re-read at end of day; MCP read-only mode; rehearsal sender; stop on a wrong `get_project` | folded in |

## 17. Rev-11 delta-check map (rev 12)

| finding | action |
|---|---|
| R11-P1-1 a read covers only the fields it returns; item-level history answers scored FALSE | claim triage: only A1 (card in this reply) and A2 (asked this turn, no card, no save in this turn's window) are decided by the agent; all other claims go to the founder |
| R11-P2-1 an earlier same-kind entry excused the OI-368 reply | A2: only a save inside this turn's window excuses it; a claim pointing to an earlier entry goes to the founder |
| R11-P2-2 ffmpeg window fixed at 15 s | frames from Send to 10 s after the reply, mapped by the recording start time, after the recording stops; reply not in frames ⇒ founder |
| R11-P3 `workout_logs` has no `deleted_at`; per-date `SUM`; 7-day read includes today and all names; IST date expression; MCP stays read-only (founder flips the secret); weight/measurement claims go to the founder | folded in |

## 18. Rev-12 delta-check map (rev 13)

| finding | action |
|---|---|
| R12-P2-1 triage could score a true status-turn claim FALSE (A9 re-queues the water) | triage only on log or change turns (F1, F2, F4, F5, A1-A8, A10, A11); on F3, A9, A12-A14 every claim → `needs_founder`, a card there → RE-QUEUE |
| R12-P2-2 T2's no-save test unstated for workouts and clashing with §5.4 | T2 is FALSE whether or not a card rendered (no save can precede the reply); a window read showing a save → founder; per-kind decision paths named; the §5.4 rule applies to (b) only |
| R12-P2-3 frames need not cover the card | frames count only if they show the reply appearing and ≥7 s after it, else founder |
| R12-P3 column names; frame deletion; claim scope; triage labels | `total_calories` / `total_protein`; frames in the deletion list; T1 covers saved-record claims only, statements about what the user did → founder; triage cases renamed T1/T2 |

