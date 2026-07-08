---
branch: coach-memory-snapshot
date: 2026-07-07
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: pending
hermes: pending
---

# Plan-review record — coach-memory-snapshot (Units 2 + 3 + FC8 of the coach-UX batch)

Keystone record for the §4.12 merge gate. Combined batch (founder call 2026-07-07: "do both
together"): **Unit 2** — coach short-term memory (client forwards the last 8 complete exchanges as a
`history` field → ai-proxy size-caps → tool-loop repairs alternation + seeds `messages[]`); **Unit 3** —
proactive per-request snapshot trim; **FC8** — Go-PRO paywall reachable at the 10/10 daily limit.
Sequenced Unit 2 → Unit 3 → FC8 on one branch, three commits (Unit 2 deployed + live-verified BEFORE
Unit 3 lands). Full plan: `~/.claude/plans/recommended-priority-for-the-snuggly-kurzweil.md`.

## Design review arc (×2 per round, context-blind; every claim re-verified against live code at HEAD)
- **Round 1 (×2 — correctness + risk/security lenses):** both NEEDS-WORK, converged on 8 findings — all
  folded in: repo-layer history assembly (chat() is pure transport with a second fallback body);
  authoritative server byte-cap (truncate-oldest-first, not 400); server-authoritative alternation repair
  + failing-first test; two snapshot budgets stay distinct; exclude `mode:'media'` rows; name the
  assistant-echo laundering residual; `disable_coach_history` kill-switch; deterministic live-verify.
  PASSES: cross-account coachBox read guarded, FC8 predicate sound, no new telemetry PII.
- **Round 2 (×2 on the hardened plan):** confirmed the R1 hardening sound (long passes list) and caught
  ONE new material defect the R1 fix introduced — the missed SECOND `chat()` call site
  (`ai_coach_provider.dart:810` auth-retry) → fixed (assemble history once, thread into both `:755` +
  `:826`). Also: named repo method `recentHistoryExchanges`, truncate→repair order-of-ops invariant,
  `coach_chat_history_replay` SoT concept + stale-reader correction, commit-type labels. Reviewer #2
  recommended SPLIT on §4.12 grounds → founder chose COMBINED (plan already sequences Unit-2-first;
  per-commit `git revert` gives rollback isolation).
- **Round 3 (×2 — bug-introduction + consistency, founder-requested):** BOTH CONVERGED. No new defect
  from the layered edits; the pending-row self-leak is genuinely defended (current turn's row is
  `pending:true` + empty `ai_response`, double-excluded). Folded 3 LOW cleanups: pin
  `recentHistoryExchanges` = 8 EXCHANGES (16 entries) + explicit `created_at` sort; full SoT
  `coach_interactions` stale-entry correction; line-count. Decreasing findings ⇒ no Round 4.

## Ground truth (main agent — verified in source, not subagent prose)
Snapshot lives in the system prompt (FC7 delimit-in-place, `ai-proxy/index.ts:729-743`) so history is a
clean `user→model` chain; `ToolLoopOptions.snapshot` latent/unused; `chat()` has TWO callers
(`ai_coach_provider.dart:742/810`) + TWO bodies (`ai_service.dart:316-320/423-427`); only `message>5000`
+ `snapshot_json>10000` bounded server-side (history was uncapped); the two budgets (8500/9500) are
pinned by 6 tests; media rows are `mode:'media'` `'[Photo] …'`. My own R1 note mis-cited `:810` as
`ai_service.dart` (709 lines) — caught + corrected.

## STATUS — implementation in progress
Unit 2 implemented (client repo `recentHistoryExchanges` + provider dual-site threading + `ai_service`
both bodies; server `capCoachHistory` + `repairHistoryAlternation` + seeding). Contract test
`coach_chat_history_replay_writer_to_reader_test.dart` (6/6 green) + Deno `tool-loop.test.ts`. SoT +
`ai_coach/CLAUDE.md` updated. **Before the `--no-ff` merge (end of batch, after Units 2+3+FC8):** run the
self-triggered **B-pass** (≥platform) → set `bpass: accepted` + `bpass_review:` here; run **Hermes** for
the shared tool-loop fan-out → set `hermes:`; ai-proxy deploy on explicit founder go + deterministic
live-verify on test7.
