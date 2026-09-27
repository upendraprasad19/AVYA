---
branch: single-owner-a
review_rounds: 2
mechanical_only: true
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a5e03de2a231-review.md
hermes: accepted
hermes_report: docs/audit/2026-09-26-hermes-single-owner-a1.md
tier: catastrophic
date: 2026-09-26
---

# Plan review — single-owner-a (unit a1)

**Scope:** ai-proxy `prediction` metering (3/day on the ledger, server-owned
system prompt), request-size limits hoisted into one shared validator, and
delete-account purging every user-owned Storage bucket through one list
(diagnoses 125b81, 40054f). Base `9939750b` (= `origin/main`). Source audit:
`docs/audit/2026-09-26-single-owner-audit-pass2.md`.

**Blast radius: catastrophic** (`docs/blast_radius.yaml:43` pins
`supabase/functions/delete-account/**`) — this batch redeploys ai-proxy,
delete-account, founder-digest and telegram-admin-bot.

## Round 1 (pre-implementation, context-blind, on the original plan)
Findings raised against the original combined batch plan (before it was split
per §4.12.1 — see `docs/plans/2026-09-26-single-owner-batch-a.md`'s own
Revision-3 note). Two units were added to the plan as a direct result (A4
input-limits shape, A5 body-composition scope correction); a1's own two units
(A2 prediction, A3 delete-account buckets) were confirmed sound as scoped.

## Round 2 (pre-implementation, context-blind, on the hardened Revision-3 plan)
7 material findings total across the whole batch. **All 7 that touched a1's
units (F8 mirror scope, F9 ledger scan, anchors) were mechanical** —
citation/scope corrections, not defects in the design — which is why a1
converges here as `mechanical_only: true` while the other 6 findings (all
introduced by Revision 2's refund mechanism and units not in this piece)
drove the split that produced a2/a3/a4 as separate pieces per §4.12.1. Ground
truth for a1's two units was independently re-verified against the live code
(`ai-proxy/index.ts:700-757`'s prediction branch honouring
`context.system_prompt` with no length limit/cap/tier check; the five-bucket
delete-account purge loop) before the split, not assumed from either round's
prose.

## Implementation, then B-pass round 1 (fresh adversarial reviewer)
Full findings + verification + fix detail: `docs/reviews/d65b986f910b-review.md`
(dispatched at `c5d659f52986`, renamed after remediation moved the hash; 2
context-blind agents — read-only lenses 1-5/7/9/10 + rebase/decision/
tool-side-effect, and mutation lenses 6/8 in an isolated worktree).

**7 findings (4 P1, 1 P2, 2 P3); 0 false_alarm — all fixed, each re-proven by
mutation** (Mb1–Mb12, diagnose 125b81): `predict()` swallowed the new 429's
status (client showed generic "try again" for an unretryable daily cap);
a prompt-injection test that never attempted the injection (fixed to
reproduce the exact pre-fix defect, which had reddened 0/15 against the
original test); a Storage-bucket-discovery mirror that resolved constants by
NAME instead of VALUE (a `_exportsLocation`-shaped const was invisible); no
kill switch on the new prediction ledger (`DISABLE_PREDICTION_QUOTA`); a
non-recursive `_shared/` scan blind to `_shared/tools/`; stale migration-number
comments; one stale code comment.

## Hermes pass (5 lenses, catastrophic tier — whole shipped files, not just
the diff)
Full report: `docs/audit/2026-09-26-hermes-single-owner-a1.md` (L1
writer/reader drift, L21 EF semantic correctness, L23 authorization, L29
failure-path/retry economics, L37 empty-state/null-shape readers; 5 agents in
waves of ≤4 per founder rule).

**15 records / 12 distinct, 0 P0, 0 P1, 4 P2 (3 distinct), 11 P3, 0 false
alarms.** Terminal states:
- **9 fixed in this batch:** PRO prediction stuck stale-but-un-refreshable for
  up to 30 days (L1-F1); digest misreporting "none used" while the kill
  switch is on (L1-F2); auto-refresh able to burn the whole daily cap on its
  own with no in-flight guard (L1-F3/L21-F3/L29-F4, one fix); dead import
  (L21-F1); chat dedup replaying an internal failure marker as a real coach
  reply (L29-F3 — new diagnose `e5c9d2`); stale migration-number comments
  (L29-F5); a partial Storage-list failure discarding already-found paths
  before removal (L37-F1); client/server snapshot-size measurement mismatch
  (L37-F2); any 429 read as the daily cap regardless of error code (L37-F3).
- **`upstream_blocked`:** L29-F1 (pre-existing 502-triggers-4x-retry cap burn
  in food_text/scan_meal/cart_auditor) — owned by unit a3, which cannot start
  until a1 merges (both edit ai-proxy).
- **`blocked_on_user`:** L23-F1 (deleted user's token can still write into
  public avatars/banners post-purge; nothing sweeps it) — this is unit a4,
  which the founder approved the same day ("Approve a4, sweep the 12").
- **`verified_clean`:** L21-F2 (a theoretical validator error-message
  mismatch that does not occur in practice — only food_text sends `text`,
  chat always sends `message`).

Accepted by the founder 2026-09-26.

## B-pass round 2 (fresh adversarial reviewer, over the Hermes remediation
delta)
Full findings + verification + fix detail:
`docs/reviews/a5e03de2a231-review.md` (renamed twice after remediation, once
more after founder acceptance moved the diff again — see the file's own
header for the full hash chain back to `d65b986f910b`).

**2 findings (1 P1, 1 P2); 0 false_alarm — both fixed, each re-proven by
mutation** (Mb13–Mb16, diagnose 125b81):
- **P1** — `PredictionService` was the one singleton of 8
  `SingletonLifecycleRegistry`-eligible services never registered, so a
  device-level account switch mid-request could (a) let the new account's
  own tap join the old account's stale in-flight prediction via
  `PredictionAttemptGate.run`'s join line, and (b) let a slow response write
  into whichever account was signed in by the time it resolved (`MigratedKey`
  resolves the box at write time, not request-start time). Fixed by
  registering the service, clearing the gate's in-flight state on account
  change, and capturing+checking the signed-in account across the network
  call before any write.
- **P2** — the client measured its snapshot cap against the plain
  `json.encode(...)` length; the server (this same batch's own L37-F2 fix)
  measures it AFTER `sanitizeJsonForPrompt` re-escapes rare separator
  characters (+5 chars/occurrence), so the two could disagree across the
  9500-char ceiling for the same bytes. Fixed with a matching
  `_sanitizedLength` on the client, computed against a real fixture (a
  throwaway probe script, not an estimate) proven to sit under the plain
  ceiling and over the sanitised one.

Accepted by the founder 2026-09-26.

## Mutation evidence (full list, diagnose 125b81)
20 mutations across the batch's lifecycle (M1–M5b pre-review, Mb1–Mb12
B-pass round 1, Mh1–Mh16 Hermes, Mb13–Mb16 B-pass round 2), each applied by
exact-string replacement with the match count checked (= 1), run once, then
restored byte-for-byte and reconfirmed against the pre-mutation file. Every
mutation reddened at least one assertion for the correct reason (no compile
errors read as proof — the diagnose-doc's own M-series table flags the two
places this could have gone wrong and didn't: M5/M5b's first version reddened
nothing until the wiring test was strengthened to require the guard's
`return`, not just the call's presence; Mb11/Mb12 pairs the real finding with
its own control). Full table: diagnose 125b81's "Mutation proof" section.

Additionally, `chat_dedup_test.ts` (5), `purge_user_storage_test.ts` (7),
`prediction_attempt_gate_test.dart` (15, including the join-avoidance
behavioural test using a real `Completer`), `prediction_service_singleton_lifecycle_test.dart`
(2, real `Hive`/`HiveUserSession.openForUser` proving the registration call
executes, not just appears in source), and
`compact_context_sanitized_length_test.dart` (4, every separator character
built via `String.fromCharCode`/bare hex after the test's own first draft hit
the raw-invisible-character trap CLAUDE.md documents for
`sanitize_for_prompt.ts`) are new files this batch added; all are counted in
the totals above.

## Verification state at record time
- Full pre-commit gate loop (`sh scripts/pre-commit.sh`): green — including
  `check_sot_registry_parity.dart` (a stale `_compactContext` line-range
  citation, widened after the batch's own fix moved the method) and
  `check_skill_tuning_history.dart` (two dated Tuning-history entries
  appended to `.claude/skills/code-review/SKILL.md`, one per B-pass round).
- `flutter analyze lib/` (whole-tree): 0 warnings/errors, 45 pre-existing
  `info`-level issues, none in any file this batch touched.
- Full `flutter test` (`TZ=Asia/Kolkata`): **6502 passed, 9 skipped, 2
  failed.** Both failures are `ward_rank_pill_golden_test.dart` (Lt / SD1
  collapsed), confirmed by running the identical file against unmodified
  base code on this VPS: it fails there too (a font-rendering/environment
  divergence, `dart_test.yaml` excludes `golden`-tagged tests from CI and
  from `pre-push.sh`'s full-suite run, so it is invisible to both).
- `deno check --node-modules-dir=none` on ai-proxy, delete-account,
  founder-digest, telegram-admin-bot: all OK.
- `deno test` over `supabase/functions/`: 615 passed, 2 failed
  (`future-prediction`/`re-engagement` `index_test.ts`, `AddrInUse` — a
  `docker-proxy` container holds port 8000 on this VPS; neither file is
  touched by this batch; no conflict in CI).
- Three review-file renames occurred after this record's inputs were
  finalized, purely from the `docs/reviews/`-and-SKILL.md-excluded staging
  hash moving as (a) the round-2 B-pass fix itself landed, (b) a trailing
  SoT-registry/wired-test-list documentation completion for that fix landed,
  and (c) the founder's acceptance flipped three `verdict:` fields — none
  changed any finding, fix, or test. Full chain documented in
  `docs/reviews/a5e03de2a231-review.md`'s own header.
