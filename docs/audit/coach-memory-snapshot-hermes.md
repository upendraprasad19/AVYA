---
branch: coach-memory-snapshot
date: 2026-07-08
blast_radius: platform
method: Hermes multi-lens deep review — 5 fresh-context Opus lens-agents (security/injection, concurrency/race, data-isolation/cross-account, failure-modes/observability, backward-compat/completeness) on the committed branch diff (c467423..HEAD), with live-state (execute_sql + deployed-v73) verification.
verdict: accepted
---

# Hermes report — coach-memory-snapshot (Units 2 + 3 + FC8)

Founder-requested end-of-batch Hermes (chosen despite my finding that the plan's "tool-loop fan-out"
rationale was moot — `tool-loop.ts` is ai-proxy-only, no cron fan-out). Ran anyway for maximum rigor;
it earned its keep — it surfaced 3 real correctness issues the B-pass missed.

## Lens outcomes
- **data-isolation / cross-account / PII → CLEAN.** `recentHistoryExchanges` reads the user-scoped
  guarded `coachBox` (physically namespaced `coachBox_<8hex>` per owner); a prior user's rows are
  unreachable at the storage layer. History is not persisted server-side (no new PII surface).
- **security / injection → 1 accepted residual (P2).** History is seeded into `messages[]` (never the
  system prompt); role hard-clamped to user|model; caps unbypassable; no cross-user/secret reachable
  (userId from verified JWT; GEMINI_API_KEY only in the Gemini URL, never in contents/logs). The one
  residual is the SAME-USER assistant-echo laundering (a user forging `model`-role turns to self-jailbreak
  the CAPTAIN_MANUAL refusals) — already named + accepted at plan-review R1; recorded in the
  `coach_chat_history_replay` SoT entry. Not a cross-user leak; not a ship-blocker.
- **concurrency / race → 2 findings (P3).** (1) the "no self-leak" invariant was FALSE on the 60s
  dedup-reuse path (a resent identical message reuses a COMPLETE row that then echoed into its own
  history). (2) `send()`'s guard brackets an await (pre-existing; benign for history — the read is
  synchronous, both turns' rows pending during each other's assembly).
- **failure-modes / observability → 2 findings (P2 + P3).** (P2) the history assembly ran OUTSIDE the
  `send()` try — a throw would strand the CURRENT message on a forever-spinner. (P3) no telemetry
  distinguishes a history-induced Gemini 400.
- **backward-compat / completeness → 2 findings (P2 + P3).** Core backward-compat SOLID (old clients →
  no history → byte-identical `messages[]`; clean rollback). (P2) `recentHistoryExchanges` replayed
  RESTORED non-chat interactions (food_text_analysis / weekly_report) as fake coach turns. (P3) no
  server-side kill-switch.

## Fixed in this batch (client-only, no redeploy — Hermes-fixes commit)
1. **P2 failure-mode** — history assembly wrapped in try→`null` (an OPTIONAL enrichment can never abort
   the current message). `ai_coach_provider.dart`.
2. **P2 backcompat** — `channel` preserved on restore (`sync_coach.dart`) + `recentHistoryExchanges`
   filters to genuine coach-chat channels (`{app,chat,in_app_orphan}` + null=local); restored non-chat
   rows excluded. `coach_interaction_repository.dart`.
3. **P3 dedup self-leak** — `recentHistoryExchanges(excludeKey: coachKey)` drops the current turn's OWN
   row on every path (fresh + dedup-reuse + retry); the wrong `:734-736` comment corrected.
Tests: `coach_chat_history_replay_writer_to_reader_test` gains excludeKey + channel-exclusion cases (8/8);
`restore_completeness` + coach-sync (38) green; `flutter analyze` clean.

## Not changed (accepted / out-of-scope, per no-deferrals — none are bugs)
- **P2 security laundering** — accepted same-user brand-safety residual (recorded in SoT). Optional
  hardenings (CAPTAIN_MANUAL non-authoritative-history line; per-turn model-role cross-check) each need
  an ai-proxy redeploy — surfaced to the founder as an optional v74.
- **P3 concurrency await** — pre-existing (state-placement predates Unit 2); benign for history.
- **P3 history telemetry** + **P3 server kill-switch** — observability/resilience enhancements (need a
  redeploy); offered to the founder, not required for correctness.

## Verdict
All THREE correctness issues fixed + tested; the two remaining server-side items are an accepted
residual and enhancements, not bugs. **verdict: accepted.**
