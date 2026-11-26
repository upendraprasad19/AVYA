---
branch: oi162-slice2-lessons
date: 2026-09-05
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/004af467034f-review.md
---

# Plan-review record — OI-162 slice-2 lessons (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Docs/process-only** — a root `CLAUDE.md` §4.9 row and a `code-review` skill lens extension.
No code, no schema. Per §4.3 that is a **self-consistency review of the wording**: the only way
this change can be wrong is by asserting something untrue, so both rounds check claims rather
than hunt bugs.

`platform` because `CLAUDE.md` is pinned `platform` in `docs/blast_radius.yaml`. ⚠ Classified
**before** committing this time — the immediately preceding branch (`oi162-slice2-closeout`)
learned that the hard way, merging first and discovering the missing record from the push-time
hook.

## The change

1. Root `CLAUDE.md` §4.9 — new row: *repairing a broken ENFORCEMENT breaks every test that was
   silently relying on it not enforcing.*
2. `.claude/skills/code-review/SKILL.md` lens 8 (`asserted_fixture_value`) — a second sharper
   question: *does this assertion depend on state the test does not CONTROL?*, plus the paired
   diff-side grep.
3. `backups/context_artifact_sizes.json` re-baselined (+1.8% on CLAUDE.md).

Both are drawn from a live incident this session: migration 129 repaired the chat cap, and three
`ai_proxy_test.dart` tests that had asserted a bare `200` for months went red, because they were
green only while the cap was broken.

## Round 1 — claim verification

| Claim | Command | Result |
|---|---|---|
| Exactly THREE tests send a live chat | `grep -c chatBodyOrAssertCapped test/edge_functions/ai_proxy_test.dart` | 3 ✓ (T16 sends none) |
| CI can run 3× per IST day | computed: cap 10, 3/run → 3 full runs (used=9) | 3 ✓ |
| The account was at the cap | live `usage_counters` → `test6@gmail.com chat_app used=10` | ✓ |
| Six readers remain for slices 3-4 | diagnose `e7c4b2` readers list | 6 ✓ |
| The refusal path had no assertion before | read the pre-fix `expect(response.statusCode, 200)` | ✓ |

## Round 2 — ran on round 1's output, and found one

**The row claimed "Six plan-review rounds and a B-pass ALL worried about a new test colliding
with those three."** `grep -c "T15" docs/audit/oi162-slice2-plan.md` → **3**, and reading them
shows the collision was raised **once**, in round 1, then carried forward as a disposition. Five
rounds did not independently worry about it.

Corrected to the sharper and true version: round 1 named the shared QA account as a hazard, and
then everyone — round 1 included — scoped that hazard to the wrong actor. *"Does my test disturb
theirs"* was asked; *"does my change alter the world their assertions assume"* was not. That the
hazard was **identified and then mis-scoped** is what makes the miss worth a permanent row; "six
rounds missed it entirely" would have been a less useful and less accurate lesson.

Also checked clean in round 2: `check_claude_md_citations.dart` PASS (16 files / 1753 sources);
the skill edit sits inside lens 8 and does not disturb the numbered lens list or the Tuning
history shape the §5.1 gate matches; the budget re-record is within band on all three artifacts.

## Verdict

**Converged.** Two rounds, one material correction — an overstatement about how many review
rounds saw the hazard, in a row whose entire subject is people mis-scoping a hazard they had
already found. Fixing it mattered for exactly that reason.
