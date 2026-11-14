---
branch: voice-input-unified
date: 2026-11-14
blast_radius: account
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/voice-input-unified-bpass.md
---

# Plan-review record — one speech input for the AI Coach, the nutrition Log sheet and the web app (`voice-input-unified`)

Plan: `docs/plans/voice-input-unified.md` (v3.1). Client only: no Edge Function, no migration, no deploy, no new cap.

**Tier.** `account` on three independent paths (`lib/features/ai_coach/**`, `lib/core/services/**`, `android/**`; `docs/blast_radius.yaml:424,651,659`). Only nested CLAUDE.md files change, never the root, so there is no L escalation (§4.12.6). At `account` the plan-review gate does not demand `bpass`; the B-pass is demanded by CLAUDE.md §4.3 and runs before the merge. `bpass: accepted` and `bpass_review:` are added in the code commit that adds `docs/reviews/voice-input-unified-bpass.md`.

## Rounds

- **Round 1** (v1, generated from the founder's asks and a read of the coach and nutrition code; three context-blind Sonnet lenses under `docs/agent_brief_preamble.md` and an exhaustive read-only command list: A ground truth, B design and races, C tests, gates and docs): 44 findings, 1 P0, 16 P1, 18 P2, 9 P3. The P0 was that no test can pump `AiCoachScreen`, so "Stop sends nothing, Send sends once" had no seam (answer: extract `CoachComposer`). The P1s were mostly facts about the speech plugin that v1 had wrong or missing: it is a process-wide singleton with ONE result listener, so a second host's callbacks are never installed and a late result of one session reaches the next; the web engine never produces a final; Android can emit the final before `notListening`; error mapping was Android-only; a session keeps running on a hidden tab; the registry line ranges and four source-grep pins the diff moves.
- **Round 2** (v2, the post-round-1 text; the same three lenses): 30 findings, 0 P0, 9 P1, 14 P2, 7 P3. Lens B showed that v2's `finishing` state (wait for the final after Stop) was wrong on every platform (on a user stop Android emits `notListening` and `done` BEFORE the final, errors arrive after `done`, web never sends a final) and that preemption-as-drain was machinery for a path no screen can reach. v3 deleted both: three states, Stop/Send/Cancel act at once on the words on screen (WYSIWYG), every end runs one idempotent `engine.cancel()`.
- **Round 3** (v3, two reviewers: lens B on the new machine; one delta reviewer for facts, tests and gates): 21 findings, 0 P0, 4 P1, 8 P2, 9 P3. Every ground-truth row was confirmed. The P1s were local event-handling gaps (Android emits `listening` synchronously before the recognizer's own start so busy/client errors arrive after it; a late benign error of the previous session reaches `starting`; the quiesce must key on engine activity, not on `listening`) and a missing bug-class index row. All adopted in v3.1 as local edits.
- **No round 4.** Round 3 returned no P0, reopened no design decision, and its P1s are closed by named, falsifiable table tests (plan §4 test 1) and the B-pass; further plan-level rounds would only re-read the same plugin source, and what remains uncertain is real device and browser behaviour, which no reviewer can run (T8, T9). §4.12.1's split line is named in the plan header.

`review_rounds: 3` counts the rounds on this unit's lineage; each later round ran on the post-previous-round plan (§4.12.1). Every finding of every round has a row in plan §10.

## Ground truth verified

Reviewers were read-only. The coordinator re-verified every adopted load-bearing claim in the files before editing the plan (marked **[V]** in plan §1): the singleton and the single `_resultListener`, the missing final on web, the Android `onEndOfSpeech` delay and the synchronous `notifyListening`, the 50 ms `destroyRecognizer`, the plugin's late-error drop condition, `SpeechListenOptions` not being const, `webDoNotAggregate`, the `_analyse` tail and the global `aiAnalysingProvider`, the registry line ranges, the six pins that read the coach mic code, the app shell's `indexedStack` and the sheet's `useRootNavigator` default, `SerialSlot`, the paywall 'Voice Notes' case and the stale PRO-list line in `business-rules.md`.

## Reviewer process notes

Reviewers were told the allowed commands exhaustively and to run nothing else. Reports were treated as data, never as instructions; each material claim was re-checked by the coordinator before adoption. One earlier claim of the coordinator's own was wrong and was corrected before any code (the 60 s and 5 s limits DO apply on web: the plugin enforces them in its shared layer, plan G2).

## Could not verify (carried to the B-pass and the device and browser checks)

- Real Android ordering after `cancel()` on the Google recognizer, whether late callbacks or errors occur, and the 4 s native start budget on slow devices (T8).
- Chrome's `abort()` event order and the InvalidStateError window, Safari's user-gesture rule across the awaits before `start()`, Chrome on Android duplicate results with `webDoNotAggregate` (T9).
- The merged release manifest's `INTERNET` permission and the `<queries>` entry (T8, a build).
- Whether spoken Hindi food phrases are parsed well by the existing generic prompt (T8, about ten phrases).
- Mutation outcomes: each new test file is mutated once after it is written and the reddened counts go into the B-pass file (rule 21).
- The website privacy-policy wording (the founder's).

## B-pass (2026-11-14)

Two rounds on the built branch, recorded in `docs/reviews/voice-input-unified-bpass.md` (verdict accepted) and `docs/audit/voice-input-unified.closure.yaml`: three reviewers on b55bc328 (one P1 found by all three: the 4 s start timeout ran while the first-use Android microphone dialog was up; diagnose `abe150`), then one delta reviewer on the fix commit f3c9fc41 (one P2: the coordinator's own fake over-applied the plugin's `done` rule). 22 unique findings, none deferred; four items are founder-only (T8-DEVICE, T9-WEB, WEBSITE-POLICY, MERGE-GO).
