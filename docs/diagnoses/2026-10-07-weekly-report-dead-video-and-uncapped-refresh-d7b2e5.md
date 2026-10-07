---
bug_id: d7b2e5
date: 2026-10-07
batch: GitHub issue #78 (Weekly Report touchup)
tier: m_fix
status: fixed
blast_radius: account
symptom: |
  Issue #78: on the Weekly Report screen "Share as Video" never produces a
  video. Root cause: the client polls an Edge Function that has been a 410 Gone
  stub since 2026-04-18. Two adjacent defects found while tracing it: (a) the
  screen's refresh-on-open (initState) fired one thinking-on Gemini call on
  EVERY open for PRO users (the server has no PRO per-day cap, only the free
  lifetime meter), and fired for free users too with no client gate, so a free
  user's first open silently spent their one lifetime report; (b) the card
  title read "AI Weekly Report", off-brand next to the Wardroom/coach voice.
concept: weekly_report_screen
sot_registry_entry: null
writers:
  - { file: lib/features/train/providers/video_render_provider.dart, method_or_widget: VideoRenderNotifier._poll (status != 200 -> return, then 20 attempts -> "Render timed out"), line: 95 }
  - { file: lib/features/profile/screens/reports_screen.dart, method_or_widget: initState silent refresh (pre-fix _generateReport(silent: true) with no gate), line: 64 }
readers:
  - { file: supabase/functions/video-status/index.ts, method_or_widget: serve() always 410 (deprecated 2026-04-18), line: 28 }
  - { file: supabase/functions/weekly-report/index.ts, method_or_widget: free gate (!hasPro && !isFirstReport -> 403); consume_quota only for !hasPro; geminiChat MODEL_PRO thinking on, retries 2, line: 551 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/weekly_report_video_and_refresh_issue78_test.dart
ist_handling:
  - "The once-per-day refresh cap compares istDateStr(cacheStamp) with istDateStr(nowWall()) (lib/core/utils/ist_date.dart); a UTC-date compare would call 23:50 IST and 00:10 IST the same day. Pinned across the IST midnight boundary."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — no new Hive key or cloud column; the existing weekly_report_cache / weekly_report_cache_date keys are read, not changed.
forbidden_patterns_checked:
  - { pattern: "inline isPro check in a widget (rule 5)", absent: true }
proposed_fix: |
  reports_screen.dart: remove the Share-as-Video row and _buildWeeklyVideoShareRow
  plus the two imports; replace Regenerate Report with a back button (context.go('/profile'));
  route the open-time refresh through gateAndVerify(featureWeeklyAiReport) so
  onFree is a no-op and onPro refreshes only when the pure
  shouldSilentRefreshWeeklyReport() (new weekly_report_refresh_policy.dart) says
  the cache is not from today (IST); title/blurb/free-user line move to
  WardroomCopy (Coach's Weekly Dispatch). The dormant video stack (provider,
  VideoShareButton, both Edge Functions, remotion/) is left in place so
  un-deferring video is a small revert. hold_week_identity test + sot_registry
  lose the reports_screen entry, since its only reader was the video row.
review_followups: |
  B-pass (docs/reviews/88ce1db-review.md), all six findings closed in this batch:
  F1 403 NOT_PRO from an explicit Generate now sets first_report_generated and opens
  the paywall (the flag is per-device, so the free-user line could promise a spent
  report); F2 same-day staleness without Regenerate accepted as founder decision,
  stale initState comment corrected; F3 this doc re-tiered s_fix -> m_fix, blast
  radius account (3 product files, lib/core/copy is account tier); F4 stamp written
  with nowWall(); F5 ref.listen re-runs the refresh on a free -> PRO transition;
  F6 stale share-as-video prose in hold_week_identity_behavioral_test.dart fixed.
  B-pass round 2 (docs/reviews/weekly-report-issue78-review.md), all three closed: R2-1 the
  once-per-day cap read a stamp written only AFTER the slow Gemini call, so a re-open, the
  free -> PRO listener or the Generate card could each fire a second call; fixed with a
  static one-call-at-a-time guard (cleared in finally) that also disables the Generate card;
  R2-2 the 403 branch keyed on status alone, now isLifetimeFreeReportSpent() requires the
  NOT_PRO body code (behavioral test); R2-3 the four weak source pins were tightened
  (body-scoped, order-checked, respell/move/decoy mutants), 9 mutants reddened.
regression_test_planned:
  - test/contracts/weekly_report_video_and_refresh_issue78_test.dart
impact_analysis: |
  Client-only, one screen. PRO users lose the manual regenerate button (refresh
  still happens on the first open of each IST day). Free users no longer get a
  report generated on first open; they tap the existing Generate button, which
  already routes first-report-free / then paywall. No Edge Function, schema or
  deploy change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/ : zero warnings/errors, nothing reported in reports_screen.dart, weekly_report_refresh_policy.dart or wardroom_copy.dart; the new test file plus weekly_report_canonical_target, weekly_report_lifetime_meter, weekly_report_pro_gate_writer_to_reader, reports_this_week_count and hold_week_identity_behavioral tests pass." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Reads weekly_report_cache + weekly_report_cache_date written by _generateReport (reports_screen.dart); stamp is nowWall().toIso8601String() (test-clock seam, same clock as the policy), parsed by DateTime.tryParse and compared by IST date; first_report_generated read unchanged." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "Read supabase/functions/video-status/index.ts (410 stub) and weekly-report/index.ts (free gate before Gemini at :156, consume_quota only for !hasPro at :716). Not deployed or changed; no live deploy state queried." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Traced video flow: trigger inserts video_renders row, poll hits video-status which always 410s, client treats non-200 as keep-polling, times out at 20 attempts. Free/PRO weekly-report contract unchanged." }
mutation_proven:
  mutated: "Five sed mutations, each confirmed applied by grep count >= 1: (M1) onFree -> _generateReport(silent: true); (M2) cap comparison inverted; (M3) IST date compare replaced by a UTC date compare; (M4) initState calls _generateReport(silent: true) directly; (M5) old 'AI Weekly Report' title restored."
  result: "All five reddened the new test (M1 1 failed, M2 3 failed, M3 1 failed, M4 1 failed, M5 1 failed); restored tree 11/11 green."
  confirmed_applied: "grep -c printed 1 (M5: 2) after each mutation; failures observed in the run output, compile-clean."
related_bugs:
  - f4a2d8
recurrence: "Not a recurrence of f4a2d8 (server-side lifetime meter); same family on the client: an ungated open-time call spending the free report."
---

## Summary

The weekly-report video row called a backend that returns 410 Gone, so it could
only ever end in "Video failed". It is removed (the stack stays dormant).
Removing Regenerate would have left the uncapped open-time refresh as the only
refresh path, so that refresh is now PRO-only and once per IST day, and a free
user's one report is spent by an explicit tap, never by opening the screen.
The card title moves to the coach voice via WardroomCopy.

## Not verified

No device run; the web/app screen was not launched in this environment. Behavior
is covered by the pure-policy behavioral test and source pins (presence only for
the screen wiring).
