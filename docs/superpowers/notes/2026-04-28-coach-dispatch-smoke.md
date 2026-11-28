# AI Coach Tool Dispatch — Manual Smoke Test (Plan C C-11)

**Run after installing the APK Test #5 build for verification of OBS-4 fix.**

## What this verifies

OBS-4 reported: AI coach review cards (Reshuffle / Pause) tap-to-apply does nothing, cards never dismiss, pile up in chat thread.

Plan C's investigation found the dispatcher was already wired correctly. The "tap does nothing" perception came from chevron-only InkWell with no terminal-state rendering. Fix landed: explicit APPLY/DISMISS buttons + terminal-state pills + Hive `intent_<id>_dispatched_at` marker for hot-restart resilience.

## Smoke test scenarios

### Scenario 1 — Pause today as rest day

1. Install APK Test #5 build on device.
2. Sign in as a test account with an active workout plan.
3. Open AI Coach tab.
4. Type or speak: **"Mark today as rest day."**
5. Coach replies + emits a review card with title containing "Pause" or "Rest day."
6. Verify the card has TWO visible buttons: **APPLY** (gold) and **DISMISS** (secondary).
7. Tap **APPLY**.
8. Confirm in the bottom sheet that opens.
9. **Verify:** card collapses to a terminal-state pill ("Applied" or similar gold pill, no longer tappable).
10. Switch to Workout tab.
11. **Verify:** today's calendar entry shows REST status (not the original workout type).
12. Switch back to AI Coach tab.
13. **Verify:** card stays in terminal-state pill (not piling up as new).
14. Hot restart the app (kill + relaunch).
15. **Verify:** card still in terminal-state (Hive marker survives restart).

### Scenario 2 — Reshuffle week to 6 days

1. Same sign-in + AI Coach.
2. Type: **"Reshuffle my week to 6 days."** or **"Train 6 days this week."**
3. Coach emits review card listing the new days (Tue/Wed/Thu/Fri/Sat/Sun or similar).
4. Verify APPLY + DISMISS buttons.
5. Tap APPLY → confirm in bottom sheet.
6. **Verify:** card → terminal pill.
7. Switch to Workout tab.
8. **Verify:** calendar shows 6 workout days this week (not the prior 5 or 4).
9. **Verify:** schedule rows reflect the new days (no Mon if Tue-Sun was applied).

### Scenario 3 — Dismiss without apply

1. Repeat Scenario 1 step 1-6.
2. Instead of APPLY, tap **DISMISS**.
3. **Verify:** card → terminal pill labeled "Dismissed" (gray, not gold).
4. Switch to Workout tab.
5. **Verify:** today's schedule UNCHANGED — still original workout type.

### Scenario 4 — Multiple intents queued

1. Sign-in + AI Coach.
2. Send 3 messages in a row that emit different WRITE intents (e.g., "swap squats for lunges", "log my workout", "reschedule to 6 days").
3. **Verify:** each emits its own review card with APPLY/DISMISS buttons.
4. Apply or Dismiss each in sequence.
5. **Verify:** each transitions to its own terminal pill independently.
6. **Verify:** no card "blocks" another from being interacted with.

## Pass criteria

All 4 scenarios PASS. Cards visibly transition from interactive (APPLY/DISMISS) to terminal pills. Schedule changes propagate to Workout tab. Hive markers survive hot restart.

## Fail criteria

Any scenario where:
- APPLY tap doesn't change app state (Workout tab unchanged after Scenario 1 step 11)
- Card never transitions to terminal pill (still shows APPLY/DISMISS after dispatch)
- Schedule rows show stale/incorrect state after dispatch
- Hot restart re-shows the card as un-dispatched

## If a scenario FAILS

1. Capture screenshot of the chat thread + Workout tab.
2. Run `adb logcat | grep -i "tool_dispatcher\|intent\|coachBox"` to capture log output.
3. Inspect Supabase: `SELECT * FROM ai_coach_interactions WHERE user_id = '<id>' ORDER BY created_at DESC LIMIT 10;` to verify the intent was sent server-side.
4. File the failure with: scenario number, observed behavior vs expected, screenshot, log excerpt.

## Reference

- Plan C: `docs/superpowers/plans/2026-04-28-apk-test-5-plan-C-coach-dispatch.md`
- Audit: `docs/superpowers/notes/2026-04-28-coach-tool-audit.md` (all 16 WRITE tools verified ✅)
- Trace: `docs/superpowers/notes/2026-04-28-coach-dispatch-trace.md` (C-1 investigation)
