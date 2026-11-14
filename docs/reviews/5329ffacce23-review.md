---
reviewed_at: 2026-10-01T22:30:00+05:30
staged_against: <the staged tree before the fixes, hash not retained> (reviewed tree; findings then fixed; final hash 5329ffacce23, this file's name)
blast_radius: platform
reviewer: claude-sonnet-via-skill (3 fresh context-blind subagents: R1 migration 153 + live SQL scripts, R2 Edge Function refund/classifier wiring, R3 client + docs + copy)
lens_set: [guard_without_its_mirror, writer_reader_drift, missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree, function_exception_swallow, unawaited_no_error_sink]
findings_count: 28
verdict: accepted
---

# Code Review (B-pass) — Part B of `gemini3-limits-caching` (limits, failed-turn refund)

Scope: the staged Part B diff (limits 7/20 chat, 4/20 vision, PRO media 10/5, `refund_quota`, client tally, paywall copy, digest, docs). Part A has its own review (`a5a985e852f1-review.md`). Every finding was verified by the author against code and live state and fixed in this batch (none deferred); the three items that are accepted RESIDUE rather than fixes are named in the last section and recorded in the diagnose-docs.

## R1 — migration 153 + live SQL scripts (7 findings, 1 P1)
| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | P1 | `RAISE ... pro=%` on a boolean prints `t`/`f`; ai-proxy's `/pro=true/` never matched, so a PRO user at the vision cap got `tier:"free", limit:4`; every `LIKE '%pro=true%'` assertion in both live scripts would have gone RED | accepted — fixed (explicit `CASE ... 'true' ELSE 'false'` text in both RAISEs; ai-proxy tolerant `pro=(true\|t)\b`; vision falls back to `checkPro`) |
| 2 | P2 | live script R3 deletes the ledger row first, so the `used > 0` guard was untested (mutation: still green) | accepted — fixed (R3b: a pending row against a ledger row forced to 0 asserts used stays 0 and the return is -1) |
| 3 | P2 | food dedup reuses another request's pending row: a second request's transport failure could refund the first request's successful unit | accepted — fixed (`reservationReused`: a reused row never refunds, nor is it registered for the outer-catch refund) + wiring pin |
| 4 | P2 | a client can insert a `channel='app'` non-pending row (before: refused 42501 by the trigger) and flip its own `model_used` | accepted RESIDUE — a client can now store a non-pending `channel='app'` row (a `pending` insert is still refused: INVOKER trigger, `authenticated` cannot execute `consume_quota`, verified live); no quota effect, own history only; founder decision 2026-10-02: ship as-is |
| 5 | P3 | `p_label='pending'` re-arms the latch; NULL `created_at` rolls the whole call back; the budget was spent before the ledger row was known to exist | accepted — fixed (`'pending'` maps to `'failed'`; `COALESCE(v_created, now())`; ledger-row pre-check `FOR UPDATE` BEFORE the budget) + R3b |
| 6 | P3 | R6 / header promised "refunds the day that charged it" but R6 asserts the opposite for a back-dated row | accepted — fixed (header and R6 reworded: the unit goes to the ROW's own day; the 23:59→00:01 case is untestable in one transaction and harmless) |
| 7 | P3 | `DIAGNOSE_ID_PLACEHOLDER` in the header | accepted — fixed (`c4e9b2, d7a1f5`) |

## R2 — Edge Function refund / classifier wiring (10 findings, 2 P1)
| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | P1 | the most common user-input block (HTTP 200, `promptFeedback.blockReason`, no candidates), `IMAGE_SAFETY`, an empty-parts SAFETY and `MAX_TOKENS/LANGUAGE/MALFORMED` were all REFUNDABLE; the existing "unknown empty candidate" test pinned the hole as intended | accepted — fixed (`classifyNoReply`; extended deterministic set; non-refundable retriable set; finishReason carried into the empty-text/empty-parts results) + tests (classifier matrix, per-shape and mixed-sequence end-to-end) |
| 2 | P1 | the deterministic flag came from the LAST attempt only: SAFETY on the primary + a 404/503 on the fallback refunded (user could farm it up to the budget); the reverse order did not | accepted — fixed (sticky `blockSeen` through `geminiChat`, `geminiChatWithTools`, `runToolLoop`, `refundableGeminiChatFailure`) + mixed-sequence tests on BOTH paths |
| 3 | P2 | order pins defeated by hoisting the condition into a const; threw-catch order unpinned; gate count not tied to the refund call | accepted — fixed (position-pinned order assertions incl. the threw-catch, gate-wraps-call regex at both vision sites) |
| 4 | P2 | staged tree red on the Dart side until migration 153 lands in `supabase/migrations/` | accepted — inherent to the apply-first order (Gate 14 rejects an unledgered migration): the migration moves with its ledger entry in the ONE Part B commit after the founder's go; full suite verified green in the simulated post-apply state |
| 5 | P2 | 400 `API_KEY_INVALID` / 401 / 403 (OUR revoked key) burn every user's unit | accepted — fixed (401/403 and 400 invalid-key refund; any other 400 does not) |
| 6 | P3 | food refund can credit a sibling request's success | accepted — fixed (see R1-3) |
| 7 | P3 | digest Top-users counts `refund_budget` as usage | accepted — fixed (`NON_ACTIVITY_KEYS`) + test |
| 8 | P3 | dead `FREE_DAILY_LIMIT`; stale "20/day", "50/day", wrong test pointer | accepted — fixed (constant and its alias pin removed; comments and pointer corrected) |
| 9 | P3 | the outer / threw catches refund unconditionally | accepted RESIDUE — bounded by the 3/day budget; documented in c4e9b2 |
| 10 | P3 | rollout order: a new ai-proxy against the old trigger answers vision 429 with `limit:4` for everyone | accepted — fixed (tier fallback via `checkPro`; deploy order migration → EF stated in c4e9b2) |

## R3 — client, docs, copy (11 findings, 1 P1)
| # | Sev | Finding | Status |
|---|---|---|---|
| 1 | P1 | four contract tests red as staged (migration in `docs/drafts/`) | accepted — see R2-4 |
| 2 | P2 | local lockout: `sendWithMedia` ticked the chat tally and the seed scan counted media / restored `scan_meal` rows; a free user with 3 photos + 4 chats locked at 7 while the server was at 4 | accepted — fixed (`sendWithMedia` never ticks; tally counts only non-media turns) + behavioural test |
| 3 | P2 | the client skipped more than the server refunds (content-blocked and budget-exhausted apologies) | accepted — fixed (200 body `refunded`; `AiChatResponse.refunded`; stored on the row; ticks unless `refunded`) + behavioural tests |
| 4 | P2 | a pin blind to an OR→AND flip of the chat guard | accepted — fixed (the whole guard expression pinned in both tests) + mutation (2 reds) |
| 5 | P2 | wiring pins brittle in the wrong direction and blind elsewhere | accepted — fixed (semantic regexes, widened parse-failure window, per-site order) |
| 6 | P2 | paywall label rename splits the analytics series, undocumented | accepted — documented in d7a1f5 + the ai_coach CLAUDE.md; all producers and the switch pinned to one string |
| 7 | P2 | wrong reader cite (digest `:80`), incomplete redeploy list | accepted — fixed (`buildDigestText :464`; every `gemini.ts` importer listed) |
| 8 | P2 | stale live-facing copy (10/day, "unlimited", 20/day) in agent briefs, e2e charters, architecture docs, memory | accepted — fixed (swept; a test name and two integration-test comments too) |
| 9 | P3 | `chatRateLimitedFromError`: `int.parse` overflow throws out of the error handler; tier regex case-sensitive | accepted — fixed (`int.tryParse`, case-insensitive) + tests |
| 10 | P3 | the tally test re-reads the clock (IST midnight flake) | accepted — fixed (waits out the last 10 s before IST midnight) |
| 11 | P3 | "deeper, personalised insights" is an unsupported quality claim; "Dedicated AI Coach is a PRO feature" reads as the coach being PRO | accepted — fixed (label 'Higher daily AI coach limit', subtitle 'Dedicated coaching with higher daily limits.') |

## Checked clean (all reviewers)
secrets_in_tree (no key / JWT / project id in any added line); no `SECURITY DEFINER` text in the migration; `consume_quota` / `refund_quota` ACL closes PUBLIC, anon and authenticated (platform default privileges grant them directly); both live trigger bodies match 129 / 132 so the inline rollback restores the true live state; two concurrent refunds serialise on the latch and `used - 1 ... AND used > 0` is row-locked; every `refundReservation(` is awaited and never throws; the digest `used > 0` filter changes no non-zero number; Part A numbers (`5 of 38`, heaviest PRO user-day = 10 app rows) re-verified read-only.

## Accepted residue (self-attested; recorded in c4e9b2 / d7a1f5 and the `usage_quota_ledger` SoT entry)
1. A client can store a non-pending `channel='app'` row (no quota effect; own history only). 2. A `runToolLoop` throw refunds regardless of cause, bounded by the 3/day budget. 3. A refund after IST midnight returns the unit to the row's day (no longer the cap in force).
