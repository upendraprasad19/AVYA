---
reviewed_at: 2026-06-28T22:40:00+05:30
staged_against: client-wins-hardening (350ee5b logUrine sync routing + df29901 rank copy truthfulness)
diff_hash: a29e8f8075a0
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 1
verdict: accepted
---

# Code Review (B-pass) — client-wins-hardening (a29e8f8075a0)

Fresh context-blind Sonnet over `git diff main...client-wins-hardening` — two
logical changes: logUrine sync routing (b6d3f9) + rank copy truthfulness
(f1a9d3, copy-only, engine unchanged). 5 lenses + 4 targeted claim checks.

## Finding 1 — P2 — writer_reader_drift (stale comment)
- **file:line:** lib/features/ai_coach/screens/induction_screen.dart:21
- **claim:** the reveal-sequence doc comment said "Msg 2 (Lt Cdr promise…)" — inaccurate after the pledge rewrite (and stale even pre-change: the old copy said Sub Lieutenant). No runtime impact.
- **verification:** reviewer grepped "Lt Cdr promise" → line 21; Read _buildMsg2 (new "Hold the line / Petty Officer / Lieutenant" copy).
- **triage / fix:** **accepted + fixed in this batch** → comment now reads "Msg 2 (rank pledge — gold emphasis)".
- **status:** accepted — fixed.

## Clean lenses
- **function_exception_swallow:** grep `functions.invoke` over the 3 code files → 0 new. Clean.
- **secrets_in_tree:** grep credential shapes over the diff → 0. Clean.
- **unawaited_no_error_sink:** `unawaited(pushUrineColorLogsForSyncDomain())` → `_syncUrineColorLogs` (sync_health.dart:256-285) has per-entry try/catch + `ErrorTelemetry.recordNonFatal` + `_reportSyncFailure(op_type: upsert_urine_color_log)`. Matches the sibling `logSleep`/`logWeight` pattern. Error sink present. Clean.
- **writer_reader_drift:** `pushUrineColorLogsForSyncDomain` confirmed public on SyncService (sync_health.dart:478) → `_syncUrineColorLogs` (pushes urine_color_ rows). logUrine writes ONLY urine_color_<date>, so dropping syncNutritionData strands nothing. Rewritten contract tests match the new source. Clean.
- **blast_radius_mismatch:** b6d3f9=account (health_write_service), f1a9d3=platform (ceremony_text.ts EF shared) — both diagnose blast_radius fields match blast_radius.yaml. Both diagnose-docs present. Clean.

## Targeted claim checks (all confirmed)
- **(a) TS var scope — CRITICAL:** `weeksHeld` destructured at ceremony_text.ts:61, in scope in BOTH the officerCrossing + LtCdr branches → no ReferenceError / 500 on EF redeploy. Confirmed.
- **(b)** ceremony "standard format" else-branch unchanged + correct. Confirmed.
- **(c)** induction_pledge_test asserts single-line-safe substrings (Petty / month three / Lieutenant / Eighty percent / contract) — all contiguous in the new source despite literal line-wraps. Tests pass. Confirmed.
- **(d)** grep '104 workouts' / 'workouts on the books' / '200 sessions' / 'six months' / 'Sub Lieutenant rank' over both copy files → 0 live claims (only a diagnose-reference comment). Confirmed.

## Founder triage notes
Triaged under standing authorization. Sole P2 (stale comment) fixed in-batch.
Verdict: **accepted.** Engine confirmed unchanged; the critical EF var-scope risk
on redeploy was specifically checked and is safe.
