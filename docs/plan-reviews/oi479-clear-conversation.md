---
branch: oi479-clear-conversation
scope: OI-479 AI Coach "Clear conversation" (founder D1-D5, 2026-11-12). Clear HIDES the thread by one monotonic instant (userBox['coach_chat_cleared_at']); the thread, the coach history replay and the client dedup skip rows at or before it; today's unresolved completion tile is kept; the instant syncs to user_preferences.coach_chat_cleared_at through the monotonic RPC raise_coach_chat_cleared_at (migration 177) and is adopted on restore max-wins; a 2 s best-effort push before the sign-out wipe. Nothing is deleted.
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi479-clear-conversation-bpass.md
---

# Plan-review record: OI-479 "Clear conversation"

Plan: `docs/plans/2026-11-12-oi479-clear-conversation.md`. Every round used one fresh, context-blind Sonnet reviewer
(the agent brief preamble, an exhaustive read-only command list, lenses L1 L2 L8 L9 L10 L11 L15) that verified each
claim against the code. Every finding below was re-checked by the coordinator in the code before it was folded in
(plan sections 8, 9, 10 carry the per-finding dispositions).

## Round 1 (rev 1)
2 P1 + 7 P2 + 3 P3, all taken.
- F1 (P1) a third reader was missing: `_findRecentDuplicateMessageKey` reuses a row within 60 s, so "hi", clear, "hi"
  would write the new turn into a hidden row (verified `coach_interaction_repository.dart:100-110,167-196`).
- F2 (P1) the read-time clamp of a future marker to `now` hid every row up to now: removed; caps at the two sinks.
- F3-F12: clock skew documented; NULL `p_at` guard; the two menu pins named (`telegram_surface_removed_test.dart:124,373`);
  the push in its own try outside the preferences try; op type `upsert_coach_chat_cleared_at` (a swept push); pending
  cards and the empty-state test (`messages.length <= 1`); the restore reads local at the sink; an IST-day bounded
  pushed-memory; a committed migration-text test; the Home tip decided (C1).

## Round 2 (rev 2)
1 P1 + 5 P2 + 6 P3, all taken. The reviewer verified the SQL (unique constraint, defaults on every other NOT NULL
column, RLS own-row policies, `AS up` alias, NULL semantics), that `userBox` is per user, and the restore math.
- F1 (P1) the marker adoption ran after two awaits with no fresh owner check: an account swap could write A's marker
  into B's box (verified `sync_profile.dart:1119-1162`).
- F2 the marker was lost at sign-out (`_teardown` pushes nothing before `clearAllData`): a 2 s push first; the
  offline residue is the OI-253 class, recorded there.
- F3-F12: registry ranges recomputed per commit; the forcing-function literal; T6 through the network path; CLEAR
  re-checks the sending flag; pins to keep; instant compare and fail-open read; `updated_at` in the RPC; the welcome
  bubble with a kept tile.

## Round 3 (rev 3, convergence)
Converged: no P0; 1 P1 that changes no mechanism (where `_teardown` reads the uid: its signature is sliced by two tests,
verified `profile_signout_routes_through_auth_notifier_test.dart:102`, `signout_unbinds_sdk_identity_test.dart:164`),
4 P2 + 4 P3, all taken: no await between read and write in `clear()`; the T6 seam is a GET responder that performs the
clear (the stub's GET responders are synchronous); T7 split into a behavioural push test and a source-slice pin; a
timed-out sign-out push must not arm the next user's sweep (`fromSignOut` logs only).

The rounds went 2 P1 -> 1 P1 -> 1 P1 (mechanical) with no new mechanism class in round 3; the plan is executed as rev 3.

## B-pass (code review of the CI-green head 19b3c23b)
A fresh Sonnet reviewer, `docs/reviews/oi479-clear-conversation-bpass.md`: no P0, P1 or P2; five P3. Two were fixed: the
clear flow's missing error sink (F2) and stale registry cites (F4, widened to every cite into a touched file). Two were
false alarms with reasons: F1's suggested read-time clamp is the round-1 F2 regression, and F3 is outside the founder's
"only clear the conversation in the chat". F5 was already recorded on OI-253. The tier is platform (the diff touches
`lib/core/services/sync/**`); this record said account until the CI inventory fix.
