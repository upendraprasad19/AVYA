---
branch: train-coach-log-refresh
date: 2026-10-21
blast_radius: platform
review_rounds: 10
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/f7148ddecbe1-review.md
---

# Plan-review record: coach chat log refreshes Train, the chat workout card says what saved, readable names (OI-370, OI-371)

Record for the §4.12 merge gate (`scripts/check_plan_review_record_exists.dart`). Plan:
`docs/plans/train-coach-log-refresh.md` (revision 11).

**Tier `account`, M** (`dart run scripts/blast_radius_from_diff.dart` on the changed files → `account`; ai_coach UI +
train UI, §4.12.6). B-pass accepted 2026-10-21: `docs/reviews/f7148ddecbe1-review.md` (reviewed at `fb5048e68fae`; 0 P0/P1, 3 P2 + 9 P3,
fixes mutation-proven). Its F12a fix adds an exact-path `docs/blast_radius.yaml` rule, which makes the batch
**platform** tier. The founder kept F6's saved card and F3's layout as built (2026-10-21).

## Rounds

Every round used context-blind reviewers who checked each claim against code and live state (A: ground truth;
B: exposure). Each round's findings are mapped in the plan (§7-§16).

| round | plan rev reviewed | outcome |
|---|---|---|
| 1 | 1 | 3 P1 (A, B) |
| 2 | 2 | 2 P0/P1 classes in B' (saved state unmounted by the chat list; a failed write shown as saved) + 1 P1 in the test design |
| 3 | 3 | 4 P1 (no runnable chat-slot test, vacuous mutations, guards acting on whatever draft is current, a false "Not saved" on a partial); founder copy decisions |
| 4 | 4 | B converged; A 2 P1 (an unrunnable scroll mutation; the day-not-marked branch off the render path); founder pencil label |
| 5 | 5 | 4 P1 in B'; founder: keep one batch, hold a new card while one saves |
| 6 | 6 | the same P1 from both (the card forgot an earlier partial save) + the invisible held card; founder copy |
| 7 | 7 | B: 1 P1 (backspace blocked on a seeded negative), 3 P2 (A cut off by a container restart, re-run in round 8) |
| 8 | 8 | B P1 (the day left unmarked after a partial save, so saved sets were invisible on Train); A P1s (stale edit sheet on a disposed ref; the deletion clause without a length guard); founder: skip unusable sets |
| 9 | 9 | BOTH converged (no P0/P1); P2s folded into rev 10 |
| 10 | 10 | delta check: converged; test-precision P2s folded into rev 11 |

## Ground truth

Reviewers checked every cited file:line against the worktree (fast-forwarded to origin/main 37c7498e), including
`week_rows.dart:78`, `exercise_preview_sheet.dart:22`, `workout_write_service.dart:541-569,599`,
`workout_schedule_read_service.dart:946-960`, `tool_dispatcher.dart:439-452`, `ai_coach_provider.dart:1543,1761,1781`,
riverpod 3.2.1 `provider_container.dart:679-688,753,1035` and `consumer.dart:454-461`, and probed the Riverpod
paused-count assertion in pure Riverpod (OI-378) and the input-formatter backspace behaviour.

## Founder decisions folded in (2026-10-21)

One batch; the held card; copy for every new line and the five TalkBack labels; unusable exercises skipped with
`Skipped: {names} (no usable sets).`
